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

const { BrowserWindow } = require('electron');

// ─── 상태 ──────────────────────────────────────────────────────────────────────
let offscreenWin = null;
let renderQueue  = Promise.resolve(); // 직렬 큐

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

// ─── HTML → PNG Buffer ─────────────────────────────────────────────────────────
/**
 * HTML 문자열을 PNG 버퍼로 렌더링
 *
 * @param {string}  html       - 렌더링할 HTML 전체 문자열
 * @param {number}  width      - 출력 폭 px (80mm = 576)
 * @param {number}  timeout    - 최대 대기 ms (기본 10000)
 * @returns {Promise<Buffer>}  PNG 바이너리 버퍼
 */
function renderHtmlToPng(html, width = 576, timeout = 10000) {
  // 직렬 큐에 추가 — 동시 렌더링 방지
  renderQueue = renderQueue.then(() => _render(html, width, timeout));

  return renderQueue;
}

async function _render(html, width, timeout) {
  const win = getOrCreateWindow();
  const wc  = win.webContents;

  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      reject(new Error('렌더링 타임아웃 (10s)'));
    }, timeout);

    // HTML을 data URL로 로드
    const dataUrl = `data:text/html;charset=utf-8,${encodeURIComponent(html)}`;

    wc.loadURL(dataUrl);

    wc.once('did-finish-load', async () => {
      try {
        // 콘텐츠 실제 높이 계산
        const contentHeight = await wc.executeJavaScript(
          'document.body.scrollHeight'
        );

        // 창 크기를 콘텐츠에 맞게 조정
        win.setSize(width, Math.max(contentHeight, 100));

        // 한 프레임 대기 (레이아웃 안정화)
        await new Promise((r) => setTimeout(r, 80));

        // 캡처
        const nativeImg = await wc.capturePage({
          x: 0,
          y: 0,
          width,
          height: contentHeight,
        });

        clearTimeout(timer);
        resolve(nativeImg.toPNG());
      } catch (err) {
        clearTimeout(timer);
        reject(err);
      }
    });

    wc.once('did-fail-load', (_e, code, desc) => {
      clearTimeout(timer);
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
