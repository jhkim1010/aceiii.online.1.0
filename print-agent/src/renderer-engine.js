/**
 * renderer-engine.js
 *
 * Electron offscreen BrowserWindow를 사용하여
 * HTML 문자열 → PNG Buffer 변환.
 *
 * - 싱글톤 패턴: BrowserWindow를 앱 수명 동안 1개만 유지 (재사용)
 * - 동시 렌더링 요청은 Promise 큐로 직렬 처리
 * - 렌더링 타임아웃 10초 (감열 티켓 수준에선 충분)
 *
 * 사용법 (main.js에서):
 *   const { renderHtmlToPng } = require('./src/renderer-engine');
 *   const pngBuffer = await renderHtmlToPng(htmlString, 576);
 */

const { BrowserWindow, nativeImage } = require('electron');
const { applyFontSettings } = require('./font-settings');

// ─── 상태 ──────────────────────────────────────────────────────────────────────
let offscreenWin = null;
let renderQueue  = Promise.resolve(); // 직렬 큐

// ─── 이진화 임계값 ──────────────────────────────────────────────────────────────
// 감열 프린터는 1비트(검/백) 장치다. 캡처된 PNG 에 남는 '회색'(막대 배경·안티에일
// 리어싱된 글자 가장자리)이 프린터/드라이버로 넘어가면 하프톤 디더(점무늬)로 바뀌어
// 흐리게·읽기 어렵게 나온다. 여기서 미리 순수 흑/백으로 눌러 회색을 제거하면:
//   - 진한 막대 = 완전한 검정(디더 없음), 글자 = 진하고 선명
//   - 어떤 출력 경로(ESC/POS·Windows 드라이버)든 회색이 없어 디더가 발생하지 않음
// 128 = 밝기 중간값. 검정 위 흰 글자(반전)와 흰 위 검정 글자의 획 굵기가 균형을
// 이루는 '가장 선명한' 지점. 더 진하게(획을 더 굵게) 원하면 140~160 으로 올린다
// (단, 너무 올리면 반전 막대의 흰 글자가 얇아진다).
const BINARIZE_THRESHOLD = 128;

// ─── offscreen 창 생성 (최초 1회) ──────────────────────────────────────────────
function getOrCreateWindow() {
  if (offscreenWin && !offscreenWin.isDestroyed()) {
    return offscreenWin;
  }

  offscreenWin = new BrowserWindow({
    width: 576,        // 80mm @ 203dpi
    height: 1200,      // 충분히 큰 초기 높이 (콘텐츠에 맞게 재조정)
    show: false,       // 화면에 표시하지 않음
    webPreferences: {
      offscreen: true,           // offscreen 렌더링 활성화
      nodeIntegration: false,
      contextIsolation: true,
      backgroundThrottling: false,
    },
  });

  // 창 닫힘 시 참조 정리
  offscreenWin.on('closed', () => { offscreenWin = null; });

  return offscreenWin;
}

// ─── offscreen 첫 paint 대기 ─────────────────────────────────────────────────
// offscreen 렌더러는 첫 프레임 paint 전에 capturePage 하면 투명/백지 이미지가
// 나올 수 있다(빈 종이의 유력 원인). invalidate 로 강제 재도색 후 첫 'paint'
// 이벤트를 기다리되, 이벤트가 오지 않아도 fallbackMs 후 반드시 resolve(무한대기 방지).
function waitForNextPaint(wc, fallbackMs = 400) {
  return new Promise((resolve) => {
    let done = false;
    const finish = () => {
      if (done) return;
      done = true;
      try { wc.removeListener('paint', onPaint); } catch (_e) { /* ignore */ }
      resolve();
    };
    const onPaint = () => finish();

    try { wc.on('paint', onPaint); } catch (_e) { /* offscreen 아닐 때 방어 */ }
    try { wc.invalidate(); } catch (_e) { /* ignore */ }
    setTimeout(finish, fallbackMs);
  });
}

// ─── 캡처 이미지 잉크 픽셀 측정(백지 진단) ────────────────────────────────────
// escpos image.js 와 동일한 기준(alpha=0 또는 r,g,b 모두 >200 → 잉크 아님)으로
// 실제로 인쇄될 '검은 픽셀' 수를 센다. ink=0 이면 프린터가 아니라 렌더 단계에서
// 이미 백지가 만들어졌다는 결정적 증거가 된다.
function measureInk(nativeImg) {
  try {
    const size   = nativeImg.getSize();          // { width, height } — DPR 반영될 수 있음
    const bitmap = nativeImg.getBitmap();         // BGRA 원시 픽셀 버퍼
    let ink = 0;
    let transparent = 0;

    for (let i = 0; i < bitmap.length; i += 4) {
      const b = bitmap[i];
      const g = bitmap[i + 1];
      const r = bitmap[i + 2];
      const a = bitmap[i + 3];

      if (a === 0) { transparent++; continue; }
      if (!(r > 200 && g > 200 && b > 200)) ink++;
    }

    const total = size.width * size.height || 1;

    return {
      width:       size.width,
      height:      size.height,
      ink,
      transparent,
      total,
      inkPct:      ((ink / total) * 100).toFixed(2),
      transpPct:   ((transparent / total) * 100).toFixed(2),
    };
  } catch (e) {
    return { error: e.message };
  }
}

// ─── 순수 흑백 이진화 ──────────────────────────────────────────────────────────
// nativeImage(BGRA) → 밝기 임계값으로 각 픽셀을 완전한 검정(0,0,0) 또는 완전한
// 흰색(255,255,255)으로 눌러 회색을 제거한다. 투명 픽셀은 종이(흰색)로 처리.
// 반환: 회색이 전혀 없는 새 nativeImage. 실패 시 원본을 그대로 반환(출력 안전).
function binarize(img, threshold = BINARIZE_THRESHOLD) {
  try {
    const size = img.getSize();
    const bmp  = Buffer.from(img.getBitmap()); // BGRA 복사본(원본 불변)

    for (let i = 0; i < bmp.length; i += 4) {
      const b = bmp[i];
      const g = bmp[i + 1];
      const r = bmp[i + 2];
      const a = bmp[i + 3];

      // 투명 = 종이(흰색). 그 외는 표준 밝기(luma) 계산.
      const lum = a === 0 ? 255 : (0.299 * r + 0.587 * g + 0.114 * b);
      const v   = lum < threshold ? 0 : 255;

      bmp[i] = v; bmp[i + 1] = v; bmp[i + 2] = v; bmp[i + 3] = 255;
    }

    return nativeImage.createFromBitmap(bmp, { width: size.width, height: size.height });
  } catch (_e) {
    return img; // 이진화 실패가 출력 자체를 막지 않도록 원본 유지
  }
}

// ─── HTML → PNG Buffer ─────────────────────────────────────────────────────────
/**
 * HTML 문자열을 PNG 버퍼로 렌더링
 *
 * @param {string}   html       - 렌더링할 HTML 전체 문자열
 * @param {number}   width      - 출력 폭 px (80mm = 576)
 * @param {number}   timeout    - 최대 대기 ms (기본 10000)
 * @param {function} log        - 단계별 진단 로그 콜백(선택) — 미지정 시 console 만 사용
 * @returns {Promise<Buffer>}   PNG 바이너리 버퍼
 */
function renderHtmlToPng(html, width = 576, timeout = 10000, log = null) {
  // 티켓 폰트/크기 사용자 설정 적용 — 모든 출력 타입 공통 진입점
  const styledHtml = applyFontSettings(html);

  // 직렬 큐에 추가 — 동시 렌더링 방지
  renderQueue = renderQueue.then(() => _render(styledHtml, width, timeout, log));

  return renderQueue;
}

async function _render(html, width, timeout, log) {
  // 진단 로그: 전달된 콜백 + 콘솔 동시 출력
  const diag = (m) => {
    console.log(m);
    if (typeof log === 'function') { try { log(m); } catch (_e) { /* ignore */ } }
  };
  const win = getOrCreateWindow();
  const wc  = win.webContents;

  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      reject(new Error('렌더링 타임아웃 (10s)'));
    }, timeout);

    // HTML을 data URL로 로드
    const dataUrl = `data:text/html;charset=utf-8,${encodeURIComponent(html)}`;

    diag(`🖥️ [render] loadURL 시작 (html=${html ? html.length : 0} chars, width=${width})`);
    wc.loadURL(dataUrl);

    wc.once('did-finish-load', async () => {
      try {
        // 콘텐츠 실제 높이 계산
        const rawHeight = await wc.executeJavaScript(
          'document.body ? document.body.scrollHeight : 0'
        );

        // 높이 0/음수 방어 — capturePage(height:0) 은 빈 이미지를 만든다(빈 종이).
        const contentHeight = Math.max(Number(rawHeight) || 0, 100);

        if (!rawHeight || rawHeight <= 0) {
          diag(`⚠️ [render] body.scrollHeight=${rawHeight} → 최소 높이 ${contentHeight}px 로 대체(콘텐츠 미렌더 의심)`);
        }

        // 창 크기를 콘텐츠에 맞게 조정
        win.setSize(width, contentHeight);

        // offscreen 첫 paint 대기(백지 방지) + 레이아웃 안정화 여유
        await waitForNextPaint(wc, 400);
        await new Promise((r) => setTimeout(r, 40));

        // 캡처 — 높이는 방어된 contentHeight 사용
        const nativeImg = await wc.capturePage({
          x: 0,
          y: 0,
          width,
          height: contentHeight,
        });

        // ── 순수 흑백 이진화: 회색 제거 → 디더 없이 최대로 진하고 선명하게 ──
        const binImg = binarize(nativeImg);

        // ── 백지 진단: 실제 잉크 픽셀 수 측정(이진화 결과 기준) ──
        const ink = measureInk(binImg);

        if (ink.error) {
          diag(`🔬 [render] 잉크 측정 실패: ${ink.error}`);
        } else if (ink.ink === 0) {
          diag(
            `🟥 [render] 경고: 잉크 픽셀 0 — 렌더 결과가 백지! ` +
              `size=${ink.width}x${ink.height} 투명=${ink.transpPct}% ` +
              `(offscreen paint 실패/폰트 미로드/height 0 의심)`,
          );
        } else {
          diag(
            `🔬 [render] 캡처 OK size=${ink.width}x${ink.height} ` +
              `잉크=${ink.ink}px(${ink.inkPct}%) 투명=${ink.transpPct}%`,
          );
        }

        const pngBuf = binImg.toPNG();

        diag(`🖨️ [render] PNG 생성 완료 (이진화 threshold=${BINARIZE_THRESHOLD}, ${pngBuf ? pngBuf.length : 0} bytes)`);

        clearTimeout(timer);
        resolve(pngBuf);
      } catch (err) {
        clearTimeout(timer);
        diag(`❌ [render] 캡처 중 오류: ${err.message}`);
        reject(err);
      }
    });

    wc.once('did-fail-load', (_e, code, desc) => {
      clearTimeout(timer);
      diag(`❌ [render] HTML 로드 실패: ${desc} (${code})`);
      reject(new Error(`HTML 로드 실패: ${desc} (${code})`));
    });
  });
}

// ─── 정리 (앱 종료 시 호출) ────────────────────────────────────────────────────
function destroyRenderer() {
  if (offscreenWin && !offscreenWin.isDestroyed()) {
    offscreenWin.destroy();
    offscreenWin = null;
  }
}

module.exports = { renderHtmlToPng, destroyRenderer };
