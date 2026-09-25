/**
 * ticket-settings.js  (antes `font-settings.js`)
 *
 * 티켓 출력의 **사용자 조정값** 중앙 관리 — 폰트·크기·오른쪽 여백.
 * - 모든 출력물(invoice/fiscal/temp/qr/test)은 renderHtmlToPng() 를 거치므로
 *   그 진입점에서 applyTicketSettings() 한 번만 호출하면 전체 적용된다.
 * - 폰트: <head> 끝에 body { font-family: ... !important } override 주입
 *   (티켓 CSS 는 body 에서만 font-family 를 선언 → 상속으로 전체 반영)
 * - 크기: CSS/inline 의 `font-size: Npx` 전체를 배율 스케일링
 *   (px 값이 60+ 곳에 산재 → regex 일괄 변환이 가장 안전)
 *
 * 사용법 (main.js):
 *   const ticketSettings = require('./src/ticket-settings');
 *   ticketSettings.configure({ family: …, scale: …, marginRight: store.get('ticketMarginRight') });
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

// ─── 오른쪽 여백 ────────────────────────────────────────────────────────────────
//
// ★★★ [2026-09-25 사용자 보고] 「출력 이미지를 보면 미세하게 마지막 줄이 잘 안보여..
//   금액 부분이..」 — 사진의 그 판매(Venta #10, $420.000)를 그대로 렌더해 봤더니
//   **HTML 은 멀쩡했다**: TOTAL 밴드가 한 줄이고 576px 안에 여유 있게 들어간다.
//   즉 결함은 레이아웃이 아니라 **캔버스 폭과 프린터의 실제 인쇄 가능 폭이 어긋나는 것**
//   이다. 그 어긋남은 프린터 모델·드라이버마다 다르므로 코드로 정할 수 없다 — 그래서
//   조정값으로 둔다.
//
// ★★ 오른쪽만 둔다(사용자 결정 2026-09-25: 「오른쪽에서 마진만 줘도 충분한데」).
//   잘리는 쪽이 오른쪽이고, 손잡이가 둘이면 캐셔가 어느 쪽을 움직여야 하는지 모른다.
//
// ★ 대가는 **줄바꿈**이다. 폭을 좁히면 긴 상품명이 한 줄 더 접힌다. 실측(같은 티켓):
//     0px → 878px 높이   ·   12px → 878 (변화 없음)
//    24px → 930 (+1줄)   ·   48px → 955
//   ⤷ 12px 까지는 **공짜**다. 글자가 잘리는 일은 없다 — 접힐 뿐이다(표 셀이 word-wrap).
//   그래서 기본값은 0 이고, 필요한 만큼만 올리게 둔다.
const TICKET_WIDTH_PX      = 576; // 80mm @ 203dpi
const MARGIN_RIGHT_MIN     = 0;
const MARGIN_RIGHT_MAX     = 64; // 그 이상은 폭이 아니라 프린터 설정이 틀린 것이다
const DEFAULT_MARGIN_RIGHT = 0;

// ─── 현재 설정 (in-memory, main.js 가 configure 로 갱신) ────────────────────────
let current = {
  family:      DEFAULT_FONT_ID,
  scale:       DEFAULT_SCALE,
  marginRight: DEFAULT_MARGIN_RIGHT,
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

    // ★ 범위 밖은 **버린다**(직전 값 유지). 잘못된 값으로 폭을 0 으로 만들면 티켓이
    //   통째로 빈 종이로 나가는데, 그건 「설정이 안 먹었다」보다 훨씬 나쁘다.
    //
    // ★★★ `Number(...)` 로 시작하면 안 된다 — **`Number(null)` 과 `Number('')` 이 0 이다.**
    //   0 은 이 값의 **유효한 값**이라(여백 없음) 그대로 통과해 여백을 조용히 지운다.
    //   위의 `scale` 은 같은 모양인데도 안 걸린다: 거기선 0 이 `>= 0.5` 에서 탈락한다.
    //   즉 「같은 코드 모양이니 괜찮겠지」가 여기서 틀린다 — **0 이 뜻을 갖는 값이면
    //   느슨한 변환이 곧 결함이다.** (시험이 이 자리에서 잡았다.)
    const crudo = opts ? opts.marginRight : undefined;

    if (
      typeof crudo === 'number' &&
      Number.isFinite(crudo) &&
      crudo >= MARGIN_RIGHT_MIN &&
      crudo <= MARGIN_RIGHT_MAX
    ) {
      current.marginRight = Math.round(crudo);
    }
  } catch (err) {
    console.error('[ticket-settings] configure error:', err.message);
  }
}

/** 현재 설정 조회 (진단/미리보기용) */
function getSettings() {
  const font = FONT_OPTIONS.find((f) => f.id === current.family) || FONT_OPTIONS[0];

  return {
    family:      current.family,
    stack:       font.stack,
    scale:       current.scale,
    marginRight: current.marginRight,
  };
}

/**
 * HTML 문자열에 사용자 조정값(폰트·크기·오른쪽 여백) 적용
 * @param {string} html - formatter 가 생성한 티켓 HTML
 * @returns {string}    - override 가 적용된 HTML
 */
function applyTicketSettings(html) {
  if (typeof html !== 'string' || html.length === 0) return html;

  try {
    let out = html;
    const { stack, scale, marginRight } = getSettings();

    // 1) 크기 배율 — `font-size: Npx` (CSS 블록 + inline style 모두) 일괄 스케일
    if (scale !== 1) {
      out = out.replace(/font-size:\s*([\d.]+)px/g, (_m, n) => {
        const scaled = Math.max(Math.round(parseFloat(n) * scale), 8);

        return `font-size: ${scaled}px`;
      });
    }

    // 2) 폰트 패밀리 + 오른쪽 여백 — body override 주입 (상속으로 전체 반영)
    //
    // ★ 캔버스(576px)는 **건드리지 않는다.** body 만 좁히면 오른쪽에 흰 띠가 남아
    //   전폭 요소(상단 배너·열 머리·TOTAL 검정 밴드)까지 같이 안으로 들어온다 —
    //   잘리던 것이 바로 그 전폭 요소들이다. 캔버스를 줄이면 프린터가 이미지를
    //   어디에 놓을지는 드라이버가 정하므로 결과가 프린터마다 달라진다.
    const reglaAncho =
      marginRight > 0
        ? ` body { width: ${TICKET_WIDTH_PX - marginRight}px !important; }`
        : '';
    const overrideStyle = `<style>body { font-family: ${stack} !important; }${reglaAncho}</style>`;

    if (out.includes('</head>')) {
      out = out.replace('</head>', `${overrideStyle}</head>`);
    } else {
      // <head> 가 없는 방어적 케이스 — 문서 앞에 주입
      out = overrideStyle + out;
    }

    return out;
  } catch (err) {
    // 폰트 적용 실패가 출력 자체를 막으면 안 됨 — 원본 그대로 반환
    console.error('[ticket-settings] applyTicketSettings error:', err.message);

    return html;
  }
}

module.exports = {
  FONT_OPTIONS,
  SIZE_OPTIONS,
  DEFAULT_FONT_ID,
  DEFAULT_SCALE,
  TICKET_WIDTH_PX,
  MARGIN_RIGHT_MIN,
  MARGIN_RIGHT_MAX,
  DEFAULT_MARGIN_RIGHT,
  configure,
  getSettings,
  applyTicketSettings,
};
