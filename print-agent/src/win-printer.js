/**
 * win-printer.js
 *
 * 시스템 프린터(이름 기반) 무음 인쇄.
 * Electron BrowserWindow.webContents.print({ deviceName, silent: true }) 를 사용해
 * OS 프린터 드라이버로 직접 출력한다. libusb / escpos-usb 같은 네이티브 의존성이
 * 전혀 필요 없으며, 한 PC 에 여러 프린터(감열 + HP 등)가 연결돼 있어도
 * deviceName 으로 특정 프린터를 고정 선택할 수 있다.
 *
 * 용지 절단(cut) 및 용지폭은 Windows 프린터 드라이버의 환경설정(80mm roll)에 따른다.
 *
 * 사용법 (main 프로세스 전용 — BrowserWindow 필요):
 *   const { listSystemPrinters, printImageSilent } = require('./win-printer');
 */
'use strict';

const { BrowserWindow } = require('electron');

// ─── 감열 프린터 표준 상수 ──────────────────────────────────────────────────
const DEFAULT_WIDTH_PX  = 576;   // 80mm @ 203dpi
const DPI               = 203;
const MICRONS_PER_INCH  = 25400;

// PNG 버퍼 → data URL
const pngToDataUrl = (buf) => `data:image/png;base64,${buf.toString('base64')}`;

// PNG IHDR 에서 픽셀 높이 추출 (바이트 20~23, big-endian). 실패 시 null.
const readPngHeight = (buf) => {
  try {
    if (buf && buf.length > 24) return buf.readUInt32BE(20);
  } catch (_e) { /* 손상된 헤더 — 기본값 사용 */ }

  return null;
};

// PNG IHDR 에서 픽셀 폭 추출 (바이트 16~19, big-endian). 실패 시 null.
// Retina(scaleFactor 2배) 캡처는 폭이 576 이 아니라 1152 로 잡히므로, 페이지
// 높이는 '픽셀→dpi' 가 아니라 실제 PNG 종횡비로 계산해야 scaleFactor 에 무관해진다.
const readPngWidth = (buf) => {
  try {
    if (buf && buf.length > 24) return buf.readUInt32BE(16);
  } catch (_e) { /* 손상된 헤더 — 기본값 사용 */ }

  return null;
};

/**
 * 설치된 시스템 프린터 목록 조회
 * @returns {Promise<Array<{ name, displayName, description, status, isDefault }>>}
 */
async function listSystemPrinters() {
  const win = new BrowserWindow({
    show: false,
    webPreferences: { offscreen: true },
  });

  try {
    // getPrintersAsync: Electron 21+ 권장 API (동기 getPrinters 는 deprecated)
    const printers = await win.webContents.getPrintersAsync();

    return printers.map((p) => ({
      name:        p.name,
      displayName: p.displayName || p.name,
      description: p.description || '',
      status:      p.status,
      isDefault:   !!p.isDefault,
    }));
  } finally {
    if (!win.isDestroyed()) win.destroy();
  }
}

/**
 * PNG 버퍼를 지정한 시스템 프린터로 무음 출력
 * @param {Buffer}   pngBuffer     렌더된 영수증 PNG
 * @param {object}   cfg           { deviceName, widthPx?, heightPx? }
 * @param {function} log           단계별 진단 로그 콜백(선택)
 * @returns {Promise<void>}
 */
function printImageSilent(pngBuffer, cfg = {}, log = () => {}) {
  const deviceName = cfg.deviceName;

  if (!deviceName) {
    return Promise.reject(new Error('deviceName 미설정 — 출력할 프린터 이름을 선택하세요'));
  }

  // 실제 PNG 픽셀 크기 (Retina 캡처면 2배로 잡힘)
  const pngW = readPngWidth(pngBuffer);
  const pngH = readPngHeight(pngBuffer);

  // 물리 페이지 폭은 감열 80mm 기준으로 고정(576px @ 203dpi). 폭은 논리 목표를 쓰고,
  // 페이지 높이는 실제 PNG '종횡비' 로 계산 → scaleFactor(2배 캡처)에 무관.
  const widthPx  = cfg.widthPx || DEFAULT_WIDTH_PX;
  const aspect   = (pngW && pngH) ? (pngH / pngW) : ((cfg.heightPx || 1200) / widthPx);

  const pageWidthMicron  = Math.round((widthPx / DPI) * MICRONS_PER_INCH);
  const pageHeightMicron = Math.round(pageWidthMicron * aspect);
  const widthMm          = (widthPx / DPI) * 25.4;

  log(
    `🪟 [win-print] device="${deviceName}" png=${pngW || '?'}x${pngH || '?'} ` +
      `page=${widthMm.toFixed(1)}mm x ${(pageHeightMicron / 1000).toFixed(1)}mm`,
  );

  return new Promise((resolve, reject) => {
    const win = new BrowserWindow({
      width:  widthPx,
      height: Math.round(widthPx * aspect),
      show:   false,
      // backgroundThrottling:false — 숨김 창 렌더 스로틀 방지 (가상 프린터/일부
      // 드라이버에서 paint 전에 print 가 실행돼 백지가 나오는 문제 완화)
      webPreferences: { sandbox: true, backgroundThrottling: false },
    });

    let settled = false;
    const cleanup = () => { if (!win.isDestroyed()) win.destroy(); };
    const done = (err) => {
      if (settled) return;
      settled = true;
      cleanup();
      err ? reject(err) : resolve();
    };

    // 여백 0, 이미지 폭 100% — 감열 용지에 꽉 차게
    const html = `<!doctype html><html><head><meta charset="utf-8">
      <style>
        @page { margin: 0; size: ${widthMm}mm auto; }
        html, body { margin: 0; padding: 0; }
        /* image-rendering: pixelated — 스케일 시 최근접(nearest) 보간을 강제.
         * 이미 순수 흑백으로 이진화된 PNG 를 bilinear 로 리샘플하면 경계에 회색이
         * 다시 생겨 드라이버가 하프톤(점무늬)으로 찍는다. pixelated 로 회색 재생성
         * 을 막아 최대한 진하고 선명하게 유지. */
        img { display: block; width: 100%; image-rendering: pixelated; }
      </style></head>
      <body><img src="${pngToDataUrl(pngBuffer)}"></body></html>`;

    const dataUrl = `data:text/html;charset=utf-8,${encodeURIComponent(html)}`;

    win.webContents.loadURL(dataUrl);

    win.webContents.once('did-finish-load', async () => {
      try {
        // ── 백지 방지 핵심: <img> 가 실제 디코드될 때까지 대기 ──────────────────
        // show:false 숨김 창은 페인트가 지연/스로틀될 수 있어, did-finish-load
        // 직후 곧바로 print() 하면 이미지가 아직 안 그려져 백지가 인쇄된다.
        const imgState = await win.webContents.executeJavaScript(`new Promise((resolve) => {
          const img = document.querySelector('img');
          if (!img) return resolve('no-img');
          const ok = () => {
            try {
              (img.decode ? img.decode() : Promise.resolve())
                .then(() => resolve('decoded:' + img.naturalWidth + 'x' + img.naturalHeight))
                .catch(() => resolve('decode-fail'));
            } catch (_e) { resolve('ready'); }
          };
          if (img.complete && img.naturalWidth > 0) return ok();
          img.onload = ok;
          img.onerror = () => resolve('img-error');
          setTimeout(() => resolve('timeout'), 2500);
        })`);

        log(`🖼️ [win-print] 이미지 상태: ${imgState}`);

        if (imgState === 'no-img' || imgState === 'img-error') {
          return done(new Error(`인쇄용 이미지 준비 실패 (${imgState}) — 백지 방지 위해 중단`));
        }

        // 레이아웃/페인트 안정화 여유
        await new Promise((r) => setTimeout(r, 120));

        win.webContents.print(
          {
            deviceName,
            silent:          true,
            printBackground: true,
            margins:         { marginType: 'none' },
            pageSize:        { width: pageWidthMicron, height: pageHeightMicron },
          },
          (success, failureReason) => {
            if (success) {
              log('✅ [win-print] print() 성공 콜백');
              done(null);
            } else {
              log(`❌ [win-print] print() 실패: ${failureReason || 'desconocido'}`);
              done(new Error(`무음 인쇄 실패: ${failureReason || 'desconocido'}`));
            }
          },
        );
      } catch (e) {
        done(new Error(`인쇄 준비 중 오류: ${e.message}`));
      }
    });

    win.webContents.once('did-fail-load', (_e, code, desc) => {
      done(new Error(`인쇄용 HTML 로드 실패: ${desc} (${code})`));
    });
  });
}

module.exports = { listSystemPrinters, printImageSilent };
