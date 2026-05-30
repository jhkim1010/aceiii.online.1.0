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
 * @param {Buffer} pngBuffer       렌더된 영수증 PNG
 * @param {object} cfg             { deviceName, widthPx?, heightPx? }
 * @returns {Promise<void>}
 */
function printImageSilent(pngBuffer, cfg = {}) {
  const deviceName = cfg.deviceName;

  if (!deviceName) {
    return Promise.reject(new Error('deviceName 미설정 — 출력할 프린터 이름을 선택하세요'));
  }

  const widthPx  = cfg.widthPx  || DEFAULT_WIDTH_PX;
  const heightPx = cfg.heightPx || readPngHeight(pngBuffer) || 1200;

  // px → micron (Electron pageSize 단위)
  const pageWidthMicron  = Math.round((widthPx  / DPI) * MICRONS_PER_INCH);
  const pageHeightMicron = Math.round((heightPx / DPI) * MICRONS_PER_INCH);
  const widthMm          = (widthPx / DPI) * 25.4;

  return new Promise((resolve, reject) => {
    const win = new BrowserWindow({
      width:  widthPx,
      height: heightPx,
      show:   false,
      webPreferences: { sandbox: true },
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
        img { display: block; width: 100%; }
      </style></head>
      <body><img src="${pngToDataUrl(pngBuffer)}"></body></html>`;

    const dataUrl = `data:text/html;charset=utf-8,${encodeURIComponent(html)}`;

    win.webContents.loadURL(dataUrl);

    win.webContents.once('did-finish-load', () => {
      win.webContents.print(
        {
          deviceName,
          silent:          true,
          printBackground: true,
          margins:         { marginType: 'none' },
          pageSize:        { width: pageWidthMicron, height: pageHeightMicron },
        },
        (success, failureReason) => {
          done(success ? null : new Error(`무음 인쇄 실패: ${failureReason || 'desconocido'}`));
        },
      );
    });

    win.webContents.once('did-fail-load', (_e, code, desc) => {
      done(new Error(`인쇄용 HTML 로드 실패: ${desc} (${code})`));
    });
  });
}

module.exports = { listSystemPrinters, printImageSilent };
