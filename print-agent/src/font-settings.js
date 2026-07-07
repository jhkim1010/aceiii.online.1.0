/**
 * font-settings.js
 *
 * 티켓 출력 폰트/크기 중앙 관리.
 * - 모든 출력물(invoice/fiscal/temp/qr/test)은 renderHtmlToPng() 를 거치므로
 *   그 진입점에서 applyFontSettings() 한 번만 호출하면 전체 적용된다.
 * - 폰트: <head> 끝에 body { font-family: ... !important } override 주입
 *   (티켓 CSS 는 body 에서만 font-family 를 선언 → 상속으로 전체 반영)
 * - 크기: CSS/inline 의 `font-size: Npx` 전체를 배율 스케일링
 *   (px 값이 60+ 곳에 산재 → regex 일괄 변환이 가장 안전)
 *
 * 사용법 (main.js):
 *   const fontSettings = require('./src/font-settings');
 *   fontSettings.configure({ family: store.get('ticketFont'), scale: store.get('ticketFontScale') });
 */

// ─── 폰트 목록 (Windows 기본 탑재 위주, fallback 포함) ─────────────────────────
// id 는 electron-store 에 저장되는 키. stack 은 CSS font-family 값.
const FONT_OPTIONS = [
  { id: 'arial',          label: 'Arial',           stack: "Arial, 'Helvetica Neue', Helvetica, sans-serif" },
  { id: 'verdana',        label: 'Verdana',         stack: 'Verdana, Geneva, sans-serif' },
  { id: 'tahoma',         label: 'Tahoma',          stack: 'Tahoma, Geneva, sans-serif' },
  { id: 'segoe',          label: 'Segoe UI',        stack: "'Segoe UI', 'Helvetica Neue', sans-serif" },
  { id: 'calibri',        label: 'Calibri',         stack: "Calibri, 'Segoe UI', sans-serif" },
  { id: 'trebuchet',      label: 'Trebuchet MS',    stack: "'Trebuchet MS', 'Lucida Grande', sans-serif" },
  { id: 'georgia',        label: 'Georgia',         stack: 'Georgia, serif' },
  { id: 'times',          label: 'Times New Roman', stack: "'Times New Roman', Times, serif" },
  { id: 'courier',        label: 'Courier New (clásica)', stack: "'Courier New', 'Lucida Console', monospace" },
  { id: 'consolas',       label: 'Consolas',        stack: 'Consolas, Menlo, monospace' },
  { id: 'lucida-console', label: 'Lucida Console',  stack: "'Lucida Console', Monaco, monospace" },
];

// ─── 크기 배율 목록 ─────────────────────────────────────────────────────────────
const SIZE_OPTIONS = [
  { scale: 0.85, label: 'Pequeño (85%)' },
  { scale: 1.0,  label: 'Normal (100%)' },
  { scale: 1.15, label: 'Grande (115%)' },
  { scale: 1.3,  label: 'Muy grande (130%)' },
  { scale: 1.45, label: 'Extra grande (145%)' },
];

const DEFAULT_FONT_ID = 'arial'; // 가독성 개선 요구로 기본값을 Arial 로 변경
const DEFAULT_SCALE   = 1.0;

// ─── 현재 설정 (in-memory, main.js 가 configure 로 갱신) ────────────────────────
let current = {
  family: DEFAULT_FONT_ID,
  scale:  DEFAULT_SCALE,
};

/**
 * 설정 갱신 — 부팅 시 + store:set(ticketFont/ticketFontScale) 시 호출
 * @param {{ family?: string, scale?: number }} opts
 */
function configure(opts) {
  try {
    if (opts && typeof opts.family === 'string' && FONT_OPTIONS.some((f) => f.id === opts.family)) {
      current.family = opts.family;
    }

    const s = Number(opts && opts.scale);

    if (Number.isFinite(s) && s >= 0.5 && s <= 2) {
      current.scale = s;
    }
  } catch (err) {
    console.error('[font-settings] configure error:', err.message);
  }
}

/** 현재 설정 조회 (진단/미리보기용) */
function getSettings() {
  const font = FONT_OPTIONS.find((f) => f.id === current.family) || FONT_OPTIONS[0];

  return { family: current.family, stack: font.stack, scale: current.scale };
}

/**
 * HTML 문자열에 폰트/크기 설정 적용
 * @param {string} html - formatter 가 생성한 티켓 HTML
 * @returns {string}    - 폰트 override 가 적용된 HTML
 */
function applyFontSettings(html) {
  if (typeof html !== 'string' || html.length === 0) return html;

  try {
    let out = html;
    const { stack, scale } = getSettings();

    // 1) 크기 배율 — `font-size: Npx` (CSS 블록 + inline style 모두) 일괄 스케일
    if (scale !== 1) {
      out = out.replace(/font-size:\s*([\d.]+)px/g, (_m, n) => {
        const scaled = Math.max(Math.round(parseFloat(n) * scale), 8);

        return `font-size: ${scaled}px`;
      });
    }

    // 2) 폰트 패밀리 — body override 주입 (상속으로 전체 반영)
    const overrideStyle = `<style>body { font-family: ${stack} !important; }</style>`;

    if (out.includes('</head>')) {
      out = out.replace('</head>', `${overrideStyle}</head>`);
    } else {
      // <head> 가 없는 방어적 케이스 — 문서 앞에 주입
      out = overrideStyle + out;
    }

    return out;
  } catch (err) {
    // 폰트 적용 실패가 출력 자체를 막으면 안 됨 — 원본 그대로 반환
    console.error('[font-settings] applyFontSettings error:', err.message);

    return html;
  }
}

module.exports = {
  FONT_OPTIONS,
  SIZE_OPTIONS,
  DEFAULT_FONT_ID,
  DEFAULT_SCALE,
  configure,
  getSettings,
  applyFontSettings,
};
