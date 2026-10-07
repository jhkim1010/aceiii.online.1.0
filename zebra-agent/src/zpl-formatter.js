/**
 * 상품 데이터 → ZPL II 문자열 변환
 * 4종 출력 모드:
 *   - simple-face:        50x25mm 단면
 *   - doble-face:         50x25mm 접이식 양면 배치
 *   - modo-duplicado:     100x25mm 좌우 복제 (cartulina)
 *   - poliamida-vertical: 25x50mm 세로 리본 (텍스트/바코드 90° 회전)
 *
 * 요소별 위치/크기 커스텀 + 가격 0~3개 (priceCount) 지원.
 *
 * 203dpi 기준: 1mm ≈ 8dot
 *   50mm = 400dot, 25mm = 200dot, 100mm = 800dot
 */

// ── 출력 모드 프리셋 ─────────────────────────────────────────────────────
const LABEL_MODES = {
  // 50x25mm 단면
  'simple-face': {
    key: 'simple-face',
    name: 'Simple Face',
    description: '50 x 25mm — una cara',
    width: 400,
    height: 200,
    duplicate: false,
    orientation: 'N', // N = normal, R = 90° 회전
    layout: {
      priceCount: 1,
      name:    { x: 10, y: 5,   fontSize: 22 },
      barcode: { x: 10, y: 30,  height: 50, moduleWidth: 3 },
      price1:  { x: 10, y: 100, fontSize: 28, bold: true },
      price2:  { x: 10, y: 130, fontSize: 20, bold: false },
      price3:  { x: 10, y: 155, fontSize: 20, bold: false },
    },
  },

  // 50x25mm 양면 (doble face — 같은 크기, 다른 배치)
  'doble-face': {
    key: 'doble-face',
    name: 'Doble Face',
    description: '50 x 25mm — plegable',
    width: 400,
    height: 200,
    duplicate: false,
    orientation: 'N',
    layout: {
      priceCount: 1,
      name:    { x: 10, y: 5,   fontSize: 20 },
      barcode: { x: 120, y: 30, height: 45, moduleWidth: 3 },
      price1:  { x: 10, y: 30,  fontSize: 32, bold: true },
      price2:  { x: 10, y: 70,  fontSize: 18, bold: false },
      price3:  { x: 10, y: 95,  fontSize: 18, bold: false },
    },
  },

  // 100x25mm — 무조건 좌우 복제 (왼편 + 오른편 동일 내용)
  'modo-duplicado': {
    key: 'modo-duplicado',
    name: 'Modo Duplicado',
    description: '100 x 25mm — izq + der',
    width: 800,
    height: 200,
    duplicate: true,
    halfWidth: 400,
    orientation: 'N',
    layout: {
      priceCount: 1,
      name:    { x: 10, y: 5,   fontSize: 20 },
      barcode: { x: 10, y: 30,  height: 45, moduleWidth: 3 },
      price1:  { x: 10, y: 95,  fontSize: 26, bold: true },
      price2:  { x: 10, y: 125, fontSize: 18, bold: false },
      price3:  { x: 10, y: 150, fontSize: 18, bold: false },
    },
  },

  // 25x50mm 폴리아미다 세로 리본 — 모든 요소 90° 회전 출력
  'poliamida-vertical': {
    key: 'poliamida-vertical',
    name: 'Poliamida Vertical',
    description: '25 x 50mm — vertical',
    width: 200,
    height: 400,
    duplicate: false,
    orientation: 'R',
    // [2026-10-07 usuario] «출력을 가로로 할지 세로로 할지도 결정할 수 있어야» — la persona elige.
    //   Cada orientación tiene su diseño (los x/y de una no sirven para la otra).
    orientable: true,
    layout: {
      priceCount: 1,
      name:    { x: 160, y: 10,  fontSize: 20 },
      // [2026-10-07] x 60→80: los números del código (debajo de las barras, girados) pisaban
      //   la palabra del nivel de precio (visto con la Vista Zebra)
      barcode: { x: 80,  y: 10,  height: 45, moduleWidth: 3 },
      price1:  { x: 20,  y: 10,  fontSize: 24, bold: true },
      price2:  { x: 20,  y: 200, fontSize: 18, bold: false },
      price3:  { x: 20,  y: 300, fontSize: 18, bold: false },
    },
    // horizontal: 25 mm de ancho → el nombre en hasta 3 renglones, el código abajo y el precio
    //   al pie (autoPrices). El código entra achicado (autoFit) — con SKU largos puede quedar fino.
    layoutHorizontal: {
      priceCount: 1,
      name:    { x: 10, y: 12,  fontSize: 22, lines: 3 },
      barcode: { x: 10, y: 100, height: 80, moduleWidth: 3 },
      price1:  { x: 10, y: 330, fontSize: 40, bold: true },
      price2:  { x: 10, y: 280, fontSize: 22, bold: false },
      price3:  { x: 10, y: 240, fontSize: 22, bold: false },
    },
  },
};

/**
 * [2026-10-07] Modo efectivo = modo base + lo guardado por la persona (labelLayouts[modo]).
 *   custom: { width, height, layout, orientation?, layoutN? }
 *   ★ `layout` es el diseño de la orientación de fábrica (el que existía antes: los guardados
 *     viejos siguen valiendo); `layoutN` el de horizontal, sólo en modos `orientable`.
 */
function modoEfectivo(base, custom = {}, extra = {}) {
  const c = custom || {};
  const horizontal = !!(base.orientable && base.layoutHorizontal && c.orientation === 'N');
  const baseLayout = horizontal ? base.layoutHorizontal : base.layout;
  const propio = horizontal ? c.layoutN : c.layout;
  const width = c.width || base.width;

  return {
    ...base,
    orientation: horizontal ? 'N' : base.orientation,
    width,
    height: c.height || base.height,
    // duplicado 절반 너비는 커스텀 width 의 절반으로 재계산
    halfWidth: base.duplicate ? Math.round(width / 2) : base.halfWidth,
    layout: propio ? { ...baseLayout, ...propio } : baseLayout,
    ...extra,
  };
}

/**
 * [2026-10-07] Lo que se guarda al tocar «Guardar diseño» / «Restablecer» / la orientación,
 *   sin perder el diseño de la OTRA orientación.
 * @param {object} prev  lo guardado hasta ahora (labelLayouts[modo])
 * @param {object} base  el modo de fábrica
 * @param {{ tipo:'diseno'|'reset'|'orientacion', width?, height?, layout?, orientation? }} cambio
 */
function guardarCustom(prev, base, cambio) {
  const p = { ...(prev || {}) };
  const horizontal = !!(base.orientable && base.layoutHorizontal && p.orientation === 'N');
  if (cambio.tipo === 'orientacion') {
    if (!base.orientable || !base.layoutHorizontal) return p;
    if (cambio.orientation === 'N') p.orientation = 'N';
    else delete p.orientation;

    return p;
  }
  if (cambio.tipo === 'reset') {
    delete p.width;
    delete p.height;
    if (horizontal) delete p.layoutN;
    else delete p.layout;

    return p;
  }
  p.width = cambio.width || undefined;
  p.height = cambio.height || undefined;
  if (horizontal) p.layoutN = cambio.layout;
  else p.layout = cambio.layout;

  return p;
}

// 구버전 프리셋 키 → 신규 모드 키 매핑 (설정 마이그레이션용)
const LEGACY_PRESET_ALIASES = {
  '50x25-simple': 'simple-face',
  '50x25-doble': 'doble-face',
  '100x25-cartulina': 'modo-duplicado',
};

/**
 * 모드 키 정규화 — 구버전 키도 신규 모드로 해석
 * @param {string} key
 * @returns {Object} LABEL_MODES 항목 (fallback: simple-face)
 */
function resolveMode(key) {
  const normalized = LEGACY_PRESET_ALIASES[key] || key;

  return LABEL_MODES[normalized] || LABEL_MODES['simple-face'];
}

// ── 바코드 타입별 ZPL 명령 (orientation 반영) ────────────────────────────
function barcodeZpl(type, x, y, value, h, mw, orientation) {
  const o = orientation === 'R' ? 'R' : 'N';

  switch (type) {
    case 'EAN13':
      return `^FO${x},${y}^BY${mw}^BE${o},${h},Y,N^FD${value}^FS`;
    case 'QR':
      // QR은 회전 개념 없음
      return `^FO${x},${y}^BQN,2,4^FDQA,${value}^FS`;
    case 'CODE128':
    default:
      return `^FO${x},${y}^BY${mw}^BC${o},${h},Y,N,N^FD${value}^FS`;
  }
}

/**
 * 가격 포맷 (아르헨 형식)
 * @param {number|string} amount
 * @returns {string}
 */
function formatPrice(amount) {
  if (amount == null || amount === '') return '';
  const num = typeof amount === 'number' ? amount : parseFloat(amount);
  if (isNaN(num)) return '';

  // 소수점 이하 미출력 — 정수로 반올림하여 표기 (예: $12.999)
  return `$${num.toLocaleString('es-AR', { minimumFractionDigits: 0, maximumFractionDigits: 0 })}`;
}

/**
 * ZPL A0 폰트 텍스트 폭 추정 (dots) — 평균 글자폭 ≈ fontSize * 0.55
 * @param {string} text
 * @param {number} fs
 * @returns {number}
 */
function estTextWidth(text, fs) {
  return Math.ceil(String(text).length * fs * 0.55);
}

/**
 * nivel 라벨 폰트 크기 — 가격 폰트의 1/4 수준 (최소 12dot 가독성 보장)
 * @param {number} amountFs
 * @returns {number}
 */
function nivelFontSize(amountFs) {
  return Math.max(12, Math.round(amountFs / 4));
}

/**
 * CODE128 총 모듈 수 추정 — (문자수 + start/checksum) * 11 + stop 13
 * @param {string} value
 * @returns {number}
 */
function code128Modules(value) {
  return (String(value).length + 2) * 11 + 13;
}

// ZPL ^BY 가 받는 모듈 폭 범위 (1~10 dot)
const MAX_MODULE_WIDTH = 10;

// 스캐너가 안정적으로 읽는 최소 모듈 폭 (203dpi 기준 2dot = 0.25mm).
// 이 아래로 축소돼야 들어가는 SKU 는 라벨을 넓히거나 SKU 를 줄여야 한다.
const MIN_SCANNABLE_MODULE_WIDTH = 2;

// ── QR 자동맞춤 (2026-07-15 D-4/D-6/D-7) ──────────────────────────────────
// ZPL ^BQ 가 받는 magnification 범위 상한
const MAX_QR_MODULE = 10;
const QR_MARGIN = 10;   // 라벨 여백 (dot)
const QR_GAP = 12;      // QR 과 텍스트 사이 간격 (dot)
const QR_WIDTH_CAP = 0.55; // QR 이 쓸 수 있는 최대 폭 비율 → 텍스트에 45% 보장

// QR byte 용량표 (ECC M, byte mode) — [모듈수, 최대 byte]
// ECC Q(25% 복원) → M(15%) 으로 낮춰 같은 URL 을 더 낮은 version 에 담는다.
// 50byte 딥링크: Q 면 v5(37모듈), M 이면 v4(33모듈) → 같은 높이에서 약 25% 확대.
const QR_ECC_M_CAPACITY = [
  [21, 14], [25, 26], [29, 42], [33, 62], [37, 84],
  [41, 106], [45, 122], [49, 152], [53, 180], [57, 213],
];

/**
 * 문자열의 UTF-8 byte 길이.
 * Buffer 가 아니라 TextEncoder 를 쓴다 — renderer(브라우저 컨텍스트)의 프리뷰가
 * 같은 계산을 해야 실물과 어긋나지 않기 때문.
 * @param {string} s
 * @returns {number}
 */
function utf8Len(s) {
  return new TextEncoder().encode(String(s == null ? '' : s)).length;
}

/**
 * byte 길이 → QR 한 변의 모듈 수 (ECC M).
 * @param {number} byteLen
 * @returns {number} 21|25|29|33|37|41|45|49|53|57 (용량 초과 시 최대 57)
 */
function qrModuleCount(byteLen) {
  for (const [modules, cap] of QR_ECC_M_CAPACITY) {
    if (byteLen <= cap) return modules;
  }

  return QR_ECC_M_CAPACITY[QR_ECC_M_CAPACITY.length - 1][0];
}

/**
 * QR magnification 자동 조절 — 사용자 상한(cap) / 라벨 높이 / 폭 55% 캡의 최솟값.
 * 바코드 moduleWidth 와 같은 패턴: 사용자 설정은 "상한"이고 실물이 안 들어가면 줄인다.
 * 폭 캡 덕에 QR 이 이름/가격 영역을 구조적으로 침범할 수 없다.
 * cap 은 `cap || 6` 로 평가한다 — undefined 뿐 아니라 0 도 "미지정"으로 취급해
 * 기본 상한 6 을 쓴다 (effectiveModuleWidth 의 `bc.moduleWidth || 3` 과 동일 관례:
 * falsy 값 = "설정 안 함", 0 을 "상한 0(=사실상 출력 불가)"으로 해석하지 않는다).
 * 진짜로 0 을 상한으로 강제하고 싶다면 이 함수로는 불가능 — 의도된 제약이다.
 * @param {string} valor - QR 에 담을 문자열 (딥링크 또는 SKU)
 * @param {number} cap - 사용자 상한 (#qr-module). falsy(0 포함/undefined) 면 기본 6.
 * @param {number} heightDots - 라벨 높이 (dot)
 * @param {number} regionDots - 상품 1장 폭 (dot)
 * @returns {number} 적용할 magnification (1 이상)
 */
function effectiveQrModule(valor, cap, heightDots, regionDots) {
  const modules = qrModuleCount(utf8Len(valor));
  const capped = Math.max(1, Math.min(MAX_QR_MODULE, cap || 6));
  const byHeight = Math.floor((heightDots - 2 * QR_MARGIN) / modules);
  const byWidth = Math.floor((regionDots * QR_WIDTH_CAP - QR_MARGIN) / modules);

  return Math.max(1, Math.min(capped, byHeight, byWidth));
}

/**
 * 바코드 모듈 폭 자동 조절 (양방향) — 가용 폭에 맞춰 모듈 폭을 키우거나 줄인다.
 * moduleWidth 는 "원하는 폭 = 상한". SKU 가 짧아 폭이 남으면 상한까지 키우고,
 * 문자 포함/긴 SKU 로 넘치면 1까지 줄인다. SKU 길이는 사용자마다 다르므로
 * 상한은 항상 사용자 설정(#lay-bc-mw)이 결정한다.
 * bc.autoFit === false 면 설정값을 그대로 사용 (자동 조절 없음).
 * @param {Object} bc - barcode 레이아웃 { x, y, moduleWidth, autoFit }
 * @param {string} value - 바코드 값
 * @param {string} type - CODE128 | EAN13 | QR
 * @param {string} orientation - 'N' | 'R'
 * @param {Object} region - { width, height }
 * @returns {number} 적용할 moduleWidth
 */
function effectiveModuleWidth(bc, value, type, orientation, region) {
  // 사용자 설정 = 상한 (autoFit off 면 그대로 사용할 값)
  const cap = Math.max(1, Math.min(MAX_MODULE_WIDTH, bc.moduleWidth || 3));

  if (bc.autoFit === false || type === 'QR') return cap;

  // EAN13 은 고정 95모듈, CODE128 은 길이 비례
  const modules = type === 'EAN13' ? 95 : code128Modules(value);
  if (modules <= 0) return cap;

  // 회전(R) 시 바코드는 리본 길이 방향(+y)으로 자란다
  const margin = 10;
  const avail = orientation === 'R'
    ? region.height - (bc.y || 0) - margin
    : region.width - (bc.x || 0) - margin;

  // 가용 폭에 들어가는 최대 모듈 폭 — 사용자 상한을 넘지 않는다
  const fit = Math.floor(avail / modules);

  return Math.max(1, Math.min(cap, fit));
}

/**
 * 바코드가 라벨에 들어가는지 진단 — UI 경고/프리뷰용 (출력 자체는 막지 않음).
 * @param {Object} bc - barcode 레이아웃
 * @param {string} value - 바코드 값
 * @param {string} type - CODE128 | EAN13 | QR
 * @param {string} orientation - 'N' | 'R'
 * @param {Object} region - { width, height }
 * @returns {Object} { moduleWidth, totalWidth, avail, overflow, tooNarrow }
 */
function inspectBarcodeFit(bc, value, type, orientation, region) {
  const mw = effectiveModuleWidth(bc, value, type, orientation, region);
  const modules = type === 'EAN13' ? 95 : code128Modules(value);
  const margin = 10;
  const avail = orientation === 'R'
    ? region.height - (bc.y || 0) - margin
    : region.width - (bc.x || 0) - margin;
  const totalWidth = modules * mw;

  return {
    moduleWidth: mw,
    totalWidth,
    avail,
    overflow: totalWidth > avail,               // 상한을 못 줄여 라벨 밖으로 나감
    tooNarrow: mw < MIN_SCANNABLE_MODULE_WIDTH, // 너무 얇아 스캔 실패 위험
  };
}

/**
 * 출력 밀도 명령 (~SD) — 라벨 포맷(^XA..^XZ) 밖의 전역 즉시 명령
 * @param {number|string} value - 0~30 절대값
 * @returns {string|null} 범위 밖/미설정 시 null (프린터 기본값 사용)
 */
function darknessZpl(value) {
  const d = parseInt(value, 10);
  if (!Number.isFinite(d) || d < 0 || d > 30) return null;

  return `~SD${String(d).padStart(2, '0')}`;
}

/**
 * 출력 속도 명령 (^PR) — 라벨 포맷 내부 명령
 * @param {number|string} value - 2~14 ips
 * @returns {string|null} 범위 밖/미설정 시 null (프린터 기본값 사용)
 */
function speedZpl(value) {
  const s = parseInt(value, 10);
  if (!Number.isFinite(s) || s < 2 || s > 14) return null;

  return `^PR${s}`;
}

/**
 * 단일 복제본 ZPL 라인 생성 (오프셋 적용 가능)
 * @param {Object} item - { name, sku, barcodeType, prices: [{ label, amount }] }
 * @param {Object} layout - 위치/크기 설정 (priceCount, autoPrices 포함)
 * @param {string} orientation - 'N' | 'R'
 * @param {number} offsetX - X축 오프셋 (duplicado 오른쪽 복제본용)
 * @param {Object} region - 복제본 영역 { width, height } (auto 배치 기준)
 * @returns {string[]} ZPL 라인 배열
 */
function renderCopy(item, layout, orientation, offsetX = 0, region = { width: 400, height: 200 }) {
  const lines = [];
  const font = orientation === 'R' ? '^A0R' : '^A0N';
  const barcodeType = (item.barcodeType || 'CODE128').toUpperCase();

  // 상품명 (제품 설명)
  const nm = layout.name || { x: 10, y: 5, fontSize: 20 };
  if (item.name) {
    // [2026-10-07] `lines` > 1: el nombre se parte en renglones dentro del ancho (^FB) —
    //   en una etiqueta angosta en horizontal no entra en uno
    const renglones = Number(nm.lines) > 1 ? Math.min(5, Number(nm.lines)) : 0;
    const ancho = orientation === 'R' ? region.height - nm.y - 10 : region.width - nm.x - 10;
    const fb = renglones && ancho > 0 ? `^FB${ancho},${renglones},0,L,0` : '';
    lines.push(`^FO${nm.x + offsetX},${nm.y}${font},${nm.fontSize},${nm.fontSize}${fb}^FD${sanitize(item.name)}^FS`);
  }

  // 바코드 (SKU를 바코드 값으로 사용)
  const bc = layout.barcode || { x: 10, y: 30, height: 45, moduleWidth: 3 };
  const barcodeValue = item.sku || item.barcode || '';
  if (barcodeValue) {
    const mw = effectiveModuleWidth(bc, barcodeValue, barcodeType, orientation, region);
    lines.push(barcodeZpl(barcodeType, bc.x + offsetX, bc.y, barcodeValue, bc.height, mw, orientation));
  }

  // 가격 0~3개 — priceCount로 출력 개수 제한 (0이면 미출력)
  const rawCount = layout.priceCount;
  const priceCount = Math.max(0, Math.min(3, rawCount == null ? 3 : parseInt(rawCount, 10) || 0));
  const prices = item.prices || [];

  // 가격 블록 구성 — nivel 라벨(1/4 크기)은 금액 위에 별도 표시
  const blocks = [];
  for (let i = 0; i < priceCount; i++) {
    const slot = layout[`price${i + 1}`] || { x: 10, y: 100, fontSize: 24 };
    const priceData = prices[i];
    if (!priceData) continue;

    const amountText = formatPrice(priceData.amount);
    if (!amountText) continue;

    const aFs = slot.fontSize || 24;
    blocks.push({
      slot,
      amountText,
      labelText: priceData.label || '',
      aFs,
      lFs: nivelFontSize(aFs),
      bold: !!slot.bold,
    });
  }

  const auto = layout.autoPrices !== false;

  if (auto && orientation === 'N') {
    // 자동 배치 — 오른쪽 하단부터 왼쪽으로 (Precio 1 이 맨 오른쪽)
    const marginR = 10;
    const marginB = 8;
    const gap = 18;
    let rightEdge = region.width - marginR;

    for (const b of blocks) {
      const aW = estTextWidth(b.amountText, b.aFs);
      const lW = b.labelText ? estTextWidth(b.labelText, b.lFs) : 0;
      const w = Math.max(aW, lW);
      const x = Math.max(0, rightEdge - w);
      const amountY = Math.max(0, region.height - marginB - b.aFs);
      const labelY = Math.max(0, amountY - b.lFs - 2);

      if (b.labelText) {
        lines.push(`^FO${x + (w - lW) + offsetX},${labelY}${font},${b.lFs},${b.lFs}^FD${sanitize(b.labelText)}^FS`);
      }
      const fw = b.bold ? Math.round(b.aFs * 1.2) : b.aFs;
      lines.push(`^FO${x + (w - aW) + offsetX},${amountY}${font},${b.aFs},${fw}^FD${sanitize(b.amountText)}^FS`);

      rightEdge = x - gap;
    }
  } else if (auto && orientation === 'R') {
    // 세로 리본 자동 배치 — price1 슬롯을 기점으로 리본 방향(+y)으로 차례대로
    const gap = 16;
    const x0 = (layout.price1 && layout.price1.x) || 20;
    let y = (layout.price1 && layout.price1.y) || 10;

    for (const b of blocks) {
      if (b.labelText) {
        lines.push(`^FO${x0 + b.aFs + 2 + offsetX},${y}${font},${b.lFs},${b.lFs}^FD${sanitize(b.labelText)}^FS`);
      }
      const fw = b.bold ? Math.round(b.aFs * 1.2) : b.aFs;
      lines.push(`^FO${x0 + offsetX},${y}${font},${b.aFs},${fw}^FD${sanitize(b.amountText)}^FS`);

      const len = Math.max(
        estTextWidth(b.amountText, b.aFs),
        b.labelText ? estTextWidth(b.labelText, b.lFs) : 0,
      );
      y += len + gap;
    }
  } else {
    // 수동 배치 — 슬롯 x/y = 금액 위치, nivel 라벨은 금액 위(N)/옆(R)에 소형 표시
    for (const b of blocks) {
      const { slot } = b;

      if (b.labelText) {
        if (orientation === 'R') {
          lines.push(`^FO${slot.x + b.aFs + 2 + offsetX},${slot.y}${font},${b.lFs},${b.lFs}^FD${sanitize(b.labelText)}^FS`);
        } else {
          const labelY = Math.max(0, slot.y - b.lFs - 2);
          lines.push(`^FO${slot.x + offsetX},${labelY}${font},${b.lFs},${b.lFs}^FD${sanitize(b.labelText)}^FS`);
        }
      }
      const fw = b.bold ? Math.round(b.aFs * 1.2) : b.aFs;
      lines.push(`^FO${slot.x + offsetX},${slot.y}${font},${b.aFs},${fw}^FD${sanitize(b.amountText)}^FS`);
    }
  }

  return lines;
}

/**
 * 단일 상품 라벨 ZPL 생성
 * @param {Object} item - { name, sku, barcodeType, prices: [{ label, amount }] }
 * @param {Object} mode - LABEL_MODES 중 하나 (커스텀 layout/width/height 오버라이드 가능)
 * @returns {string} ZPL 문자열
 */
function formatLabel(item, mode) {
  const m = mode || LABEL_MODES['simple-face'];
  const layout = m.layout || LABEL_MODES['simple-face'].layout;
  const orientation = m.orientation === 'R' ? 'R' : 'N';

  const lines = [
    '^XA',
    `^PW${m.width}`,
    `^LL${m.height}`,
    '^CI28',
  ];

  // 출력 속도 (^PR — 2~14 ips, 미설정 시 프린터 기본값)
  const pr = speedZpl(m.speed);
  if (pr) lines.push(pr);

  // 복제본 영역 크기 (duplicado 는 절반 폭 기준으로 auto 배치)
  const region = {
    width: m.duplicate && m.halfWidth ? m.halfWidth : m.width,
    height: m.height,
  };

  // 왼쪽 (또는 단일) 복제본
  lines.push(...renderCopy(item, layout, orientation, 0, region));

  // modo-duplicado: 오른쪽 복제본
  if (m.duplicate && m.halfWidth) {
    lines.push(...renderCopy(item, layout, orientation, m.halfWidth, region));
  }

  lines.push('^XZ');

  return lines.join('\n');
}

/**
 * 여러 상품 라벨 일괄 생성 (qty 반복 포함)
 * @param {Array} items - [{ name, sku, barcodeType, prices, qty }]
 * @param {Object} mode - 출력 모드 (LABEL_MODES 항목 또는 커스텀)
 * @returns {string} 전체 ZPL 문자열
 */
/**
 * QR 라벨 규칙 — 수량을 라벨 수로 옮긴다(지금은 `qrLoteFilas` 가 지킨다).
 *
 * ★★★ [2026-09-25 사용자 요구] 「바코드 대신 QR code 출력으로 선택」 +
 *   「티켓 하나당 1개를 출력할지 2개를 출력할지 선택」
 *
 * ★★ QR 에 담는 것은 **SKU** 다(사용자 결정: 「A 로 해야 바코드 리더기로 사용하겠지」).
 *   딥링크는 세 번째 탭(QR pendientes)에 그대로 남는다 — 그쪽은 손님이 휴대폰으로
 *   찍는 용도고, 이쪽은 매장 리더가 읽는 용도다. **같은 화면에 섞지 않는다.**
 *
 * ★ 수량은 **단위 수**이지 라벨 수가 아니다. 2개/라벨이면 9개 = 2장짜리 4장 + 1장짜리 1장.
 *   `ceil` 로 반올림해 2장짜리로만 찍으면 스티커가 하나 남는다.
 *
 * (qrLabelsDeItem — una fila por producto — se reemplazó por qrLoteFilas el 2026-10-03:
 *  las filas se llenan de corrido entre productos. Ver qrLoteFilas.)
 */

/**
 * [v1.0.29] Lo común a imprimir y a la vista previa del lote QR: el mismo diseño.
 * ★ Rollo: del modo elegido (doble banda si `duplicate`). Texto y QR: de la pestaña QR.
 */
function qrLoteBase(item, mode, opciones) {
  const porEtiqueta = opciones && opciones.porEtiqueta === 2 ? 2 : 1;
  const bandas = mode && mode.duplicate && mode.halfWidth ? 2 : 1;
  const anchoDots = mode && mode.width ? (bandas === 2 ? mode.halfWidth : mode.width) : 400;

  // 가격은 사용자가 고른 니벨의 첫 줄 — QR 라벨은 한 줄만 그린다.
  const primera = Array.isArray(item.prices) && item.prices.length > 0 ? item.prices[0] : null;
  const base = {
    contenido: String(item.sku || ''),
    name: item.name,
    price: primera ? primera.amount : item.price,
    priceLabel: primera ? primera.label : '',
  };
  const layout = {
    widthMm: anchoDots / 8,
    heightMm: mode && mode.height ? mode.height / 8 : 25,
    darkness: mode ? mode.darkness : undefined,
    speed: mode ? mode.speed : undefined,
    bandas,

    // qué texto y dónde + posición/tamaño del QR — lo guardado en la pestaña QR (qrLayout)
    ...[...TEXTO_KEYS, ...DISENO_QR_KEYS].reduce((o, k) => {
      if (opciones && opciones.texto && opciones.texto[k] !== undefined && opciones.texto[k] !== null && opciones.texto[k] !== '') o[k] = opciones.texto[k];

      return o;
    }, {}),
  };

  return { layout, base, porEtiqueta, bandas, porFila: bandas * porEtiqueta };
}

/** [v1.0.29] Una fila del lote QR para la vista previa / avisos (mismo camino que imprimir). */
function qrLotePreview(item, mode, opciones) {
  const { layout, base, porEtiqueta, porFila } = qrLoteBase(item, mode, opciones);
  const r = formatQrLabelConAvisos({ ...base, layout: { ...layout, mode: porEtiqueta === 2 ? 'doble' : 'simple' } });

  return { ...r, porFila, dibujo: zplADibujo(r.zpl) };
}

/**
 * ★★ [2026-10-03 · usuario] **Las filas se llenan de corrido entre productos.**
 *
 *   Antes cada producto empezaba fila nueva: con doble banda + 2 QR (4 por fila), 1 de
 *   19 + 4 de 1 salían en 9 filas con **13 casilleros en blanco** — con muchos productos
 *   de a 1 se tiraban 3 de cada 4 adhesivos. Ahora: 6 filas, 1 en blanco.
 *   Decisión del usuario: un adhesivo puede llevar QR de dos productos (se cortan).
 *
 *   Para que no se confundan al cortar, en la celda donde **empieza** otro producto:
 *     · una **raya vertical** a su izquierda (si no es la primera celda de la fila)
 *     · la **descripción siempre**, aunque en la pestaña QR esté apagada
 */
function qrLoteFilas(items, mode, opciones) {
  const lista = Array.isArray(items) ? items : [];
  if (lista.length === 0) return [];

  const { layout, porEtiqueta, porFila } = qrLoteBase(lista[0], mode, opciones);
  const modo = porEtiqueta === 2 ? 'doble' : 'simple';

  const celdas = [];
  for (const it of lista) {
    const { base } = qrLoteBase(it, mode, opciones);
    const qty = Math.max(1, it.qty || 1);
    for (let i = 0; i < qty; i++) celdas.push({ ...base, nuevo: i === 0 });
  }

  const filas = [];
  for (let i = 0; i < celdas.length; i += porFila) {
    const fila = celdas.slice(i, i + porFila);
    filas.push({
      ...formatQrLabelConAvisos({ ...fila[0], layout: { ...layout, mode: modo, celdas: fila } }),
      porFila,
    });
  }

  return filas;
}

/** [2026-10-03] Filas del lote entero, llenando de corrido (lo mismo que qrLoteFilas imprime). */
function filasDeLoteQrTotal(items, mode, opciones) {
  const porEtiqueta = opciones && opciones.porEtiqueta === 2 ? 2 : 1;
  const bandas = mode && mode.duplicate && mode.halfWidth ? 2 : 1;
  const unidades = (Array.isArray(items) ? items : []).reduce((s, it) => s + Math.max(1, (it && it.qty) || 1), 0);

  return Math.ceil(unidades / (bandas * porEtiqueta));
}

/** [v1.0.29] Cuántas filas (pasadas de la impresora) salen para `qty` unidades. */
function filasDeLoteQr(qty, mode, opciones) {
  const porEtiqueta = opciones && opciones.porEtiqueta === 2 ? 2 : 1;
  const bandas = mode && mode.duplicate && mode.halfWidth ? 2 : 1;

  return Math.ceil(Math.max(1, qty || 1) / (bandas * porEtiqueta));
}

/**
 * @param {Object} [opciones] - { simbolo: 'barras'|'qr', porEtiqueta: 1|2 }
 *   미지정이면 바코드 — 기존 호출부의 동작이 바뀌지 않는다.
 */
function formatBatchLabels(items, mode, opciones) {
  const labels = [];
  const esQr = !!(opciones && opciones.simbolo === 'qr');

  // 출력 밀도 (~SD — 절대값 00~30, 미설정 시 프린터 기본값)
  // ~SD 는 라벨 포맷(^XA..^XZ) 밖의 전역 명령이라 배치 앞에 1회만 전송
  // ★ QR 경로에서는 `formatQrLabel` 이 라벨마다 ~SD 를 동봉하므로 여기서 또 넣지 않는다.
  const sd = mode && !esQr ? darknessZpl(mode.darkness) : null;
  if (sd) labels.push(sd);

  // ★ [2026-10-03] QR: todas las unidades de todos los productos, de corrido (qrLoteFilas)
  if (esQr) {
    for (const f of qrLoteFilas(items, mode, opciones)) labels.push(f.zpl);

    return labels.join('\n');
  }

  for (const item of items) {

    const qty = Math.max(1, item.qty || 1);
    const zpl = formatLabel(item, mode);

    for (let i = 0; i < qty; i++) {
      labels.push(zpl);
    }
  }

  return labels.join('\n');
}

// ZPL 특수문자 이스케이프
function sanitize(str) {
  return String(str).replace(/[\^~]/g, '');
}

// ── QR 배치 델타 라벨 (Phase 38 — QR 자동맞춤 좌 + 텍스트 우 분할) ─────────
/**
 * 우 패널 텍스트 줄바꿈 — estTextWidth 기준으로 폭 초과 시 단어 단위 분할.
 * 한 단어가 그 자체로 폭을 넘으면 문자 단위로 쪼갠다.
 * @param {string} text - 이미 sanitize 된 텍스트
 * @param {number} fs - 폰트 크기
 * @param {number} maxWidth - 가용 폭 (dot)
 * @returns {string[]} 줄 배열 (최소 1줄)
 */
function wrapQrText(text, fs, maxWidth) {
  const clean = String(text).trim();
  if (!clean) return [''];

  const words = clean.split(/\s+/);
  const lines = [];
  let cur = '';

  const pushWord = (w) => {
    // 단어 하나가 폭 초과 → 문자 단위 분할
    if (estTextWidth(w, fs) > maxWidth) {
      if (cur) { lines.push(cur); cur = ''; }
      let chunk = '';
      for (const ch of w) {
        if (chunk && estTextWidth(chunk + ch, fs) > maxWidth) {
          lines.push(chunk);
          chunk = ch;
        } else {
          chunk += ch;
        }
      }
      cur = chunk;

      return;
    }

    const trial = cur ? `${cur} ${w}` : w;
    if (estTextWidth(trial, fs) <= maxWidth) {
      cur = trial;
    } else {
      if (cur) lines.push(cur);
      cur = w;
    }
  };

  for (const w of words) pushWord(w);
  if (cur) lines.push(cur);

  return lines.length ? lines : [''];
}

/**
 * [2026-10-02 사용자 요구] QR 라벨의 글자 — 「가격을 출력할지, 제품 설명을 출력할지,
 *   출력하면 그 위치는 어디서 시작할지」.
 *   · mostrarNombre / mostrarPrecio — 기본 true (지금까지 나가던 그대로).
 *   · nombreX/Y · precioX/Y — **mm**, 칸(한 장 또는 반 칸)의 왼쪽 위 기준.
 *     비우면(null) 자동 배치 = 지금까지의 위치.
 * ★ 둘 다 끄면 글자가 없다 — 쌓기(2개/라벨)에서는 그만큼 QR 이 커진다.
 */
const TEXTO_KEYS = [
  'mostrarNombre', 'mostrarPrecio', 'nombreX', 'nombreY', 'precioX', 'precioY',
  // [PEDIDO 10] tamaño (dots) y alineación de cada texto. Sin valor = como siempre.
  'nombreFs', 'precioFs', 'nombreAlign', 'precioAlign',
];

/**
 * [v1.0.29] Lo demás del diseño QR que el lote «Etiquetas → QR» toma de la pestaña QR:
 * posición del QR y tamaños. (Ancho/alto NO: el lote usa el rollo del modo elegido.)
 */
const DISENO_QR_KEYS = ['qrX', 'qrY', 'qrModule', 'fontSize'];

function textoQr(cfg) {
  const mm = (v) => {
    if (v === null || v === undefined || v === '') return null;
    const n = Number(v);

    return Number.isFinite(n) && n >= 0 ? Math.round(n * 8) : null;
  };
  // [PEDIDO 10] tamaño de letra en dots (10–60). Vacío = el automático de siempre.
  const fs = (v) => {
    if (v === null || v === undefined || v === '') return null;
    const n = Math.round(Number(v));

    return Number.isFinite(n) && n >= 10 ? Math.min(60, n) : null;
  };
  const al = (v) => (v === 'C' || v === 'R' ? v : 'L');

  return {
    nombreFs: fs(cfg.nombreFs),
    precioFs: fs(cfg.precioFs),
    nombreAlign: al(cfg.nombreAlign),
    precioAlign: al(cfg.precioAlign),
    nombre: cfg.mostrarNombre !== false,
    precio: cfg.mostrarPrecio !== false,
    nombreX: mm(cfg.nombreX),
    nombreY: mm(cfg.nombreY),
    precioX: mm(cfg.precioX),
    precioY: mm(cfg.precioY),
    // [v1.0.29] posición del QR (mm desde la esquina de la celda). null = automático.
    qrX: mm(cfg.qrX),
    qrY: mm(cfg.qrY),
  };
}

/**
 * [PEDIDO 10] Un texto de la etiqueta QR. Alineación L = la línea de siempre (byte por byte);
 * C/R = ^FB (bloque de 1 línea del ancho `w`) que centra o alinea a la derecha dentro de él.
 */
function lineaTexto(x, y, fs, align, w, texto) {
  const fb = align === 'C' || align === 'R' ? `^FB${Math.max(1, w)},1,0,${align}` : '';

  return `^FO${x},${y}^A0N,${fs},${fs}${fb}^FD${texto}^FS`;
}

/** [PEDIDO 10] Dónde quedó cada texto (sólo la 1.ª celda) — para arrastrarlo en la vista previa. */
function anotarCaja(p, caja) {
  if (p.cajas) p.cajas.push({ ...caja, offsetX: p.offsetX });
}

/** Alto del bloque de texto con el tamaño automático (para medir cuánto achica el elegido). */
function lineHAuto(t, fs) {
  return (fs + 4) * ((t.nombre ? 1 : 0) + (t.precio ? 1 : 0));
}

/**
 * 좁은 칸(25mm)용 QR 블록 — QR 위, 글자 아래로 **쌓는다**.
 *
 * ★★★ [2026-09-25 사용자 요구] 「50mm x 25mm etiqueta 1개에 2개씩 출력」
 *   25mm 칸에 좌우 배치(QR|글자)를 그대로 넣으면 글자 칸이 **8.6mm** 로 무너진다
 *   (실측). 쌓으면 글자가 칸 폭 전체(22.5mm)를 쓴다.
 *
 * ★★ 그리고 QR 은 **작아지지 않는다.** 지금 QR 은 폭이 아니라 **높이**에 걸려 있어서
 *   (라벨이 25mm) 좌우로 나눠도 폭은 한도가 아니다. 실측:
 *     50mm 한 칸(좌우 배치)  module 5 → QR 20.6mm
 *     25mm 칸 (쌓기, 글자 2줄) module 4 → QR 16.5mm   ← 이 저장소 최소 스캔 폭의 2배
 *   글자를 3줄로 늘리면 그때부터 module 3(12.4mm) 로 떨어진다. 그래서 **2줄이 상한**이다.
 *
 * @param {Object} p - { contenido, name, price, priceLabel, qrModule, fontSize, cell, height, offsetX }
 * @returns {string[]} ZPL 라인 배열
 */
function renderQrBlockApilado(p) {
  const { contenido, name, price, priceLabel, qrModule, fontSize, cell, height, offsetX } = p;
  const t = p.texto || textoQr({});
  const lines = [];

  // 글자 줄이 차지하는 높이 — QR 이 쓸 수 있는 높이는 그만큼 줄어든다.
  // (안 찍는 줄은 자리를 차지하지 않는다 — 둘 다 끄면 QR 이 칸 높이를 다 쓴다)
  const fs = Math.max(12, Math.min(fontSize, 16));
  // [PEDIDO 10] el tamaño elegido por el usuario saca el texto del tope 12–16 (el QR se achica
  //   lo necesario y se avisa). Sin elegir = el automático de siempre.
  const fsN = t.nombreFs ?? fs;
  const fsP = t.precioFs ?? fs;
  const textBlock = (t.nombre ? fsN + 4 : 0) + (t.precio ? fsP + 4 : 0);

  const modules = qrModuleCount(utf8Len(contenido));
  const cap = Math.max(1, Math.min(MAX_QR_MODULE, qrModule || 6));
  const moduloPara = (bloque) => Math.max(1, Math.min(
    cap,
    Math.floor((height - 2 * QR_MARGIN - bloque) / modules),
    Math.floor((cell - 2 * QR_MARGIN) / modules),
  ));
  const module = moduloPara(textBlock);

  const qrDots = modules * module;

  // [PEDIDO 10] avisar cuánto se achicó el QR por las letras grandes
  if (p.avisos && (t.nombreFs !== null || t.precioFs !== null)) {
    const sinElegir = moduloPara(lineHAuto(t, fs));
    if (module < sinElegir) {
      p.avisos.push({ campo: 'qr', mm: Math.round((qrDots / 8) * 10) / 10, modulo: module, chico: module <= 2 });
    }
  }

  // ★ QR 은 칸 안에서 **가운데**. 왼쪽 정렬이면 두 QR 사이가 비어 한 장처럼 안 보이고,
  //   가위로 반을 자를 때 어디가 경계인지도 알기 어렵다.
  const qrX = offsetX + (t.qrX ?? Math.max(QR_MARGIN, Math.round((cell - qrDots) / 2)));
  const qrY = t.qrY ?? QR_MARGIN;
  lines.push(`^FO${qrX},${qrY}^BQN,2,${module}^FDMA,${sanitize(contenido)}^FS`);

  // 글자 — 자동이면 칸 폭 전체, 위치를 정했으면 그 자리부터 칸 오른쪽 끝까지.
  let y = qrY + qrDots + 4;

  // 1줄: 제품명 (넘치면 자른다 — 두 줄로 접으면 가격이 밀려 나간다)
  if (t.nombre) {
    const x = t.nombreX ?? QR_MARGIN;
    const yy = t.nombreY ?? y;
    const availW = Math.max(1, cell - x - QR_MARGIN);
    const completo = sanitize(name || '').trim();
    const nameLine = wrapQrText(completo, fsN, availW)[0] || '';
    lines.push(lineaTexto(offsetX + x, yy, fsN, t.nombreAlign, availW, nameLine));
    anotarCaja(p, { campo: 'nombre', x: offsetX + x, y: yy, alto: fsN, ancho: availW });
    // [v1.0.29] avisar si el nombre no entra (antes se cortaba en silencio)
    if (p.avisos && nameLine.length < completo.length) {
      p.avisos.push({ campo: 'nombre', mostrado: nameLine, total: completo.length });
    }
    if (t.nombreY === null) y += fsN + 4;
  }

  // 2줄: 가격
  if (t.precio) {
    const x = t.precioX ?? QR_MARGIN;
    const yy = t.precioY ?? y;
    const availW = Math.max(1, cell - x - QR_MARGIN);
    const priceText = `${sanitize(priceLabel || '')}: ${formatPrice(price)}`.trim();
    lines.push(lineaTexto(offsetX + x, yy, fsP, t.precioAlign, availW, priceText));
    anotarCaja(p, { campo: 'precio', x: offsetX + x, y: yy, alto: fsP, ancho: availW });
  }

  return lines;
}

/**
 * 단일 상품 QR 블록 렌더 (offsetX 적용 — doble 오른쪽 복제본용)
 * 좌 = QR(`contenido` 인코딩, 자동맞춤), 우 = 제품명(줄바꿈) + `{priceLabel}: {price}`.
 * 좌우 경계는 고정 비율이 아니라 QR 실측 폭에서 역산한다 (2026-07-15 D-5).
 * @param {Object} p - { contenido, name, price, priceLabel, qrModule, fontSize, region, height, offsetX }
 * @returns {string[]} ZPL 라인 배열
 */
function renderQrBlock(p) {
  const { contenido, name, price, priceLabel, qrModule, fontSize, region, height, offsetX } = p;
  const t = p.texto || textoQr({});
  const lines = [];

  // qrModule 은 사용자 상한 — 라벨 높이/폭에 맞춰 실효값을 산출한다
  const modules = qrModuleCount(utf8Len(contenido));
  const module = effectiveQrModule(contenido, qrModule, height, region);

  // 좌 QR — 값을 훼손 없이 인코딩 (Phase 37 파서 계약: sanitize 는 ^,~ 만 제거 — 딥링크·SKU 둘 다 안전)
  // ECC M(^FDMA) — Q 에서 낮춰 같은 높이에 더 큰 QR (D-7)
  const qrLeft = t.qrX ?? QR_MARGIN;
  const qrTop = t.qrY ?? QR_MARGIN;
  lines.push(`^FO${offsetX + qrLeft},${qrTop}^BQN,2,${module}^FDMA,${sanitize(contenido)}^FS`);

  // 우 패널 — QR 우측끝에서 gap 만큼 띄운 지점부터. 폭 55% 캡 덕에 항상 텍스트 자리가 남는다.
  const qrRight = qrLeft + modules * module;
  const textX = offsetX + qrRight + QR_GAP;
  const availW = Math.max(1, region - qrRight - QR_GAP - QR_MARGIN);

  let y = QR_MARGIN;
  if (t.nombre) {
    // 위치를 정했으면 그 자리부터 라벨 오른쪽 끝까지 줄바꿈한다
    const x = t.nombreX === null ? textX : offsetX + t.nombreX;
    const w = t.nombreX === null ? availW : Math.max(1, region - t.nombreX - QR_MARGIN);
    let yy = t.nombreY ?? y;
    const fsN = t.nombreFs ?? fontSize;
    const nameLines = wrapQrText(sanitize(name || ''), fsN, w);
    anotarCaja(p, { campo: 'nombre', x, y: yy, alto: fsN, ancho: w });
    let mostradas = 0;
    for (const ln of nameLines) {
      lines.push(lineaTexto(x, yy, fsN, t.nombreAlign, w, ln));
      if (yy + fsN <= height) mostradas++;
      yy += fsN + 4;
    }
    // [v1.0.29] líneas que caen fuera del alto de la etiqueta = nombre cortado
    if (p.avisos && mostradas < nameLines.length) {
      const visto = nameLines.slice(0, mostradas).join(' ');
      p.avisos.push({ campo: 'nombre', mostrado: visto, total: sanitize(name || '').trim().length });
    }
    if (t.nombreY === null) y = yy;
  }

  // 가격줄 — `{priceLabel}: {price}` (자동이면 이름 아래)
  if (t.precio) {
    const priceFs = t.precioFs ?? Math.max(14, Math.round(fontSize * 0.9));
    const priceText = `${sanitize(priceLabel || '')}: ${formatPrice(price)}`.trim();
    const x = t.precioX === null ? textX : offsetX + t.precioX;
    const w = t.precioX === null ? availW : Math.max(1, region - t.precioX - QR_MARGIN);
    const yy = t.precioY ?? y;
    lines.push(lineaTexto(x, yy, priceFs, t.precioAlign, w, priceText));
    anotarCaja(p, { campo: 'precio', x, y: yy, alto: priceFs, ancho: w });
  }

  return lines;
}

/**
 * QR 델타 라벨 ZPL 생성 (순수 함수) — Phase 38 D-8/D-9/D-10.
 *   좌 QR(`contenido`, 자동맞춤으로 폭 55% 캡까지 확대) + 우 제품명 + 가격(나머지 폭 전부).
 *   좌우 경계는 고정 비율이 아니라 QR 실측 폭에서 역산한다. mode='doble' 이면 같은 상품 2장.
 * @param {Object} args
 * @param {string} args.contenido - QR 에 담을 **문자열 그대로**.
 *   ★★★ [2026-09-25] 여기는 `qrUrl` 이었다. 그런데 이제 담기는 것이 두 종류다:
 *     · 세 번째 탭(QR pendientes) — `${WEB}/m/stock?s=&p=` 딥링크. 손님이 휴대폰으로 찍는다.
 *     · 「갯수대로」 탭 — **SKU**. 매장 바코드 리더가 읽는다(사용자 결정 2026-09-25).
 *   이름이 `qrUrl` 인 채로 SKU 를 넘기면, 오늘 하루 종일 쫓던 바로 그 모양이 된다
 *   (`editar-stock-de-producto` 가 `delete` 를 요구하는 것처럼 — 이름이 거짓말한다).
 * @param {string} args.name - 제품명
 * @param {number|string} args.price - 가격
 * @param {string} args.priceLabel - 가격 라벨 (예: Minorista)
 * @param {Object} [args.layout] - { widthMm, heightMm, qrModule, fontSize, mode, darkness, speed }
 *   qrModule 은 상한(기본 6) — 라벨 높이/폭이 실효값을 줄일 수 있다.
 *   (연혁) 과거엔 좌우 폭을 splitRatio 로 고정 분할했으나 폐기 — 지금은 QR 실측 폭에서 역산.
 * @returns {string} ZPL 문자열
 */
function formatQrLabel(args = {}) {
  return formatQrLabelConAvisos(args).zpl;
}

/**
 * Igual que `formatQrLabel`, pero devuelve también los avisos (nombre cortado).
 *
 * ★★ [v1.0.29 · usuario] **Rollo doble banda** (`bandas: 2` — 2 etiquetas a lo ancho,
 *   p. ej. «Modo Duplicado» 100 × 25): cada etiqueta se dibuja por separado. Antes el QR
 *   tomaba los 100 mm como UNA etiqueta: «1 QR» salía cruzando las dos, y «2 QR en 1
 *   etiqueta» daba 2 por fila en vez de 4 (el usuario corta cada etiqueta al medio).
 *   `widthMm` es el ancho de **una** etiqueta; `^PW` = ancho × bandas.
 * ★ `bloques` = cuántas celdas de la fila se llenan (las de un resto). Las demás quedan
 *   en blanco **en su lugar**, para que los cortes caigan siempre en el mismo sitio.
 */
function formatQrLabelConAvisos({ contenido, name, price, priceLabel, layout } = {}) {
  const cfg = layout || {};
  const widthMm = cfg.widthMm || 50;
  const heightMm = cfg.heightMm || 25;
  const qrModule = cfg.qrModule || 6;
  const fontSize = cfg.fontSize || 22;
  const mode = cfg.mode === 'doble' ? 'doble' : 'simple';
  const bandas = cfg.bandas === 2 ? 2 : 1;

  // 203dpi 환산 (1mm ≈ 8dot).
  //
  // ★★★ [2026-09-25] 여기서 `totalW = region * 2` 였다 — 즉 **미디어 폭을 두 배로**
  //   선언했다. 50x25 라벨에서 `doble` 을 고르면 `^PW800`(100mm) 이 나가는데,
  //   프린터는 실제 용지 폭에서 자르므로 **오른쪽 QR 이 통째로 안 나온다.**
  //   ⤷ `^PW` 는 **언제나 설정된 라벨 폭 × 밴드 수**다. `doble` 은 한 장을 둘로 나눠 쓴다.
  const region = Math.round(widthMm * 8);
  const H = Math.round(heightMm * 8);
  const totalW = region * bandas;
  const porEtiqueta = mode === 'doble' ? 2 : 1;
  const cell = mode === 'doble' ? Math.floor(region / 2) : region;
  const celdas = bandas * porEtiqueta;
  // [2026-10-03] `cfg.celdas` = un producto por celda (lote de corrido). Sin eso, como antes:
  //   el mismo producto en `bloques` celdas.
  const porCelda = Array.isArray(cfg.celdas) && cfg.celdas.length > 0 ? cfg.celdas.slice(0, celdas) : null;
  const llenas = porCelda
    ? porCelda.length
    : cfg.bloques ? Math.max(1, Math.min(celdas, Math.floor(cfg.bloques))) : celdas;

  // 밀도(~SD)는 포맷 밖 전역 명령 → ^XA 앞, 속도(^PR)는 포맷 안.
  const lines = [];
  const sd = darknessZpl(cfg.darkness);
  if (sd) lines.push(sd);

  lines.push('^XA', `^PW${totalW}`, `^LL${H}`, '^CI28');

  const pr = speedZpl(cfg.speed);
  if (pr) lines.push(pr);

  const avisos = [];
  const cajas = [];
  const texto = textoQr(cfg);
  for (let k = 0; k < llenas; k++) {
    const banda = Math.floor(k / porEtiqueta);
    const mitad = k % porEtiqueta;
    const offsetX = banda * region + mitad * cell;
    // el aviso es el mismo en todas las celdas — se junta sólo de la primera
    const av = k === 0 ? avisos : null;
    const cj = k === 0 ? cajas : null;
    const c = porCelda ? porCelda[k] : { contenido, name, price, priceLabel, nuevo: false };

    // [2026-10-03] donde empieza otro producto: descripción siempre + raya a la izquierda
    const tx = c.nuevo && !texto.nombre ? { ...texto, nombre: true } : texto;
    if (c.nuevo && k > 0) lines.push(`^FO${offsetX},0^GB3,${H},3^FS`);

    if (mode === 'doble') {
      // 반 칸(25mm)에는 좌우 배치가 안 들어간다 — 쌓는다.
      lines.push(...renderQrBlockApilado({
        contenido: c.contenido, name: c.name, price: c.price, priceLabel: c.priceLabel,
        qrModule, fontSize, cell, height: H, offsetX, texto: tx, avisos: av, cajas: cj,
      }));
    } else {
      lines.push(...renderQrBlock({
        contenido: c.contenido, name: c.name, price: c.price, priceLabel: c.priceLabel,
        qrModule, fontSize, region, height: H, offsetX, texto: tx, avisos: av, cajas: cj,
      }));
    }
  }

  lines.push('^XZ');

  return { zpl: lines.join('\n'), avisos, cajas, bandas, celdasPorFila: celdas, anchoEtiqueta: region, alto: H };
}

/**
 * [v1.0.29] Lo que se dibuja, leído del **mismo ZPL** que se imprime — para la vista previa
 * exacta. Sólo entiende lo que genera este módulo: ^PW ^LL ^FO + (^BQN|^A0N) + ^FD.
 * ★ El QR se dibuja con su tamaño real (módulos × aumento); su contenido no hace falta.
 */
function zplADibujo(zpl) {
  const out = { ancho: 0, alto: 0, elementos: [] };
  for (const ln of String(zpl).split('\n')) {
    let m = /\^PW(\d+)/.exec(ln);
    if (m) out.ancho = Number(m[1]);
    m = /\^LL(\d+)/.exec(ln);
    if (m) out.alto = Number(m[1]);
    m = /^\^FO(\d+),(\d+)\^BQN,2,(\d+)\^FDMA,(.*)\^FS$/.exec(ln);
    if (m) {
      const mod = Number(m[3]);
      const modulos = qrModuleCount(utf8Len(m[4]));
      out.elementos.push({ tipo: 'qr', x: Number(m[1]), y: Number(m[2]), modulos, modulo: mod, lado: modulos * mod });
      continue;
    }
    // [2026-10-03] raya entre productos (^GB ancho,alto,grosor)
    m = /^\^FO(\d+),(\d+)\^GB(\d+),(\d+),(\d+)\^FS$/.exec(ln);
    if (m) {
      out.elementos.push({ tipo: 'linea', x: Number(m[1]), y: Number(m[2]), ancho: Number(m[3]), alto: Number(m[4]) });
      continue;
    }
    // [PEDIDO 10] ^FB opcional = bloque de 1 línea alineado (C/R) dentro de `ancho`
    m = /^\^FO(\d+),(\d+)\^A0N,(\d+),(\d+)(?:\^FB(\d+),\d+,\d+,([LCRJ]))?\^FD(.*)\^FS$/.exec(ln);
    if (m) {
      const e = { tipo: 'texto', x: Number(m[1]), y: Number(m[2]), alto: Number(m[3]), texto: m[7] };
      if (m[5]) { e.ancho = Number(m[5]); e.alinear = m[6]; }
      out.elementos.push(e);
    }
  }

  return out;
}

/**
 * Etiqueta de prueba («Imprimir test» y «Imprimir prueba» del panel).
 *
 * ★ [2026-10-07 usuario] «더블 밴드로 놓고 테스트 버튼을 누를 때 더블 밴드로 나오게».
 *   Antes era un ZPL fijo de 50×25 (^PW400): con «Modo Duplicado» (100×25) salía sólo la
 *   etiqueta izquierda y la derecha en blanco. Ahora sigue el modo como `formatLabel`:
 *   ^PW = ancho del modo y, si es doble banda, la misma prueba en las dos mitades.
 * ★ Los demás modos salen igual que antes (50×25, a la izquierda).
 * ★ [2026-10-07] Etiqueta angosta (Poliamida, 25×50): la prueba sigue la orientación elegida —
 *   vertical = girada (^A0R/^BCR, como la etiqueta real), horizontal = 25 mm de ancho con un
 *   código corto que entra entero. Antes salía la de 50×25 y se cortaba («…TES»).
 *
 * @param {Object} mode - modo efectivo (getEffectiveMode): width, halfWidth, duplicate, name
 * @param {{darkness?: number|null, speed?: number|null}} ajustes
 * @returns {string} ZPL
 */
function formatTestLabel(mode, { darkness = null, speed = null } = {}) {
  const doble = !!(mode && mode.duplicate && mode.halfWidth);
  // [codex 048] sólo los modos con orientación elegible (Poliamida), no cualquier ancho chico
  const angosta = !doble && mode && mode.orientable && mode.width && mode.width < 400;
  if (angosta) return testAngosta(mode, { darkness, speed });
  const ancho = doble ? mode.width : 400;
  // ★ [codex 041] el código se achica a su etiqueta, igual que `renderCopy`: con ^BY3 mide
  //   435 dots. En doble banda la izquierda se metía en la derecha; en una cara (400 dots)
  //   se cortaba el final (2026-10-07 «맞춰줘»). Nunca más ancho que los 400 de antes.
  const region = doble ? mode.halfWidth : Math.min(400, (mode && mode.width) || 400);
  const by = effectiveModuleWidth({ x: 10, moduleWidth: 3 }, '1234567890', 'CODE128', 'N', {
    width: region,
    height: (mode && mode.height) || 200,
  });
  const copia = (dx) => [
    `^FO${10 + dx},5^A0N,22,22^FDVENTAGO ZEBRA TEST^FS`,
    `^FO${10 + dx},30^BY${by}^BCN,50,Y,N,N^FD1234567890^FS`,
    `^FO${10 + dx},100^A0N,28,28^FD$0.00^FS`,
    `^FO${10 + dx},135^A0N,16,16^FDD:${darkness ?? 'auto'} V:${speed ?? 'auto'}^FS`,
    // en doble banda, cuál es cuál: así se ve si la derecha salió corrida
    ...(doble ? [`^FO${10 + dx},158^A0N,16,16^FD${dx === 0 ? 'IZQ' : 'DER'} · ${sanitize(mode.name || '')}^FS`] : []),
  ];

  return [
    darknessZpl(darkness),
    '^XA',
    `^PW${ancho}`,
    // [codex 041] el alto del modo (puede estar personalizado), como la etiqueta real
    `^LL${doble && mode.height ? mode.height : 200}`,
    '^CI28',
    speedZpl(speed),
    ...copia(0),
    ...(doble ? copia(mode.halfWidth) : []),
    '^XZ',
  ]
    .filter(Boolean)
    .join('\n');
}

function testAngosta(mode, { darkness, speed }) {
  const ancho = mode.width;
  const alto = mode.height || 400;
  const girada = mode.orientation === 'R';
  const pie = `D:${darkness ?? 'auto'} V:${speed ?? 'auto'}`;
  let campos;
  if (girada) {
    // el texto corre a lo largo de la etiqueta (+y); x = de afuera hacia adentro
    const by = effectiveModuleWidth({ x: 0, y: 10, moduleWidth: 3 }, '1234567890', 'CODE128', 'R', { width: ancho, height: alto });
    campos = [
      `^FO${ancho - 34},10^A0R,22,22^FDVENTAGO ZEBRA TEST^FS`,
      `^FO${ancho - 120},10^BY${by}^BCR,60,Y,N,N^FD1234567890^FS`,
      `^FO26,10^A0R,28,28^FD$0.00^FS`,
      `^FO6,10^A0R,16,16^FD${pie} · VERTICAL^FS`,
    ];
  } else {
    const by = effectiveModuleWidth({ x: 10, moduleWidth: 3 }, '1234', 'CODE128', 'N', { width: ancho, height: alto });
    campos = [
      `^FO10,10^A0N,22,22^FB${ancho - 20},2,0,L,0^FDVENTAGO ZEBRA TEST^FS`,
      `^FO10,70^BY${by}^BCN,60,Y,N,N^FD1234^FS`,
      `^FO10,170^A0N,28,28^FD$0.00^FS`,
      `^FO10,210^A0N,16,16^FD${pie}^FS`,
      `^FO10,232^A0N,16,16^FDHORIZONTAL^FS`,
    ];
  }

  return [
    darknessZpl(darkness),
    '^XA',
    `^PW${ancho}`,
    `^LL${alto}`,
    '^CI28',
    speedZpl(speed),
    ...campos,
    '^XZ',
  ]
    .filter(Boolean)
    .join('\n');
}

module.exports = {
  modoEfectivo,
  guardarCustom,
  formatLabel,
  formatTestLabel,
  formatBatchLabels,
  formatQrLabel,
  resolveMode,
  estTextWidth,
  nivelFontSize,
  code128Modules,
  effectiveModuleWidth,
  inspectBarcodeFit,
  darknessZpl,
  speedZpl,
  MAX_MODULE_WIDTH,
  MIN_SCANNABLE_MODULE_WIDTH,
  utf8Len,
  qrModuleCount,
  effectiveQrModule,
  MAX_QR_MODULE,
  QR_MARGIN,
  QR_GAP,
  QR_WIDTH_CAP,
  LABEL_MODES,
  LEGACY_PRESET_ALIASES,
  textoQr,
  TEXTO_KEYS,
  DISENO_QR_KEYS,
  formatQrLabelConAvisos,
  zplADibujo,
  qrLotePreview,
  filasDeLoteQr,
  qrLoteFilas,
  filasDeLoteQrTotal,

  // 하위 호환 (구버전 import 대비)
  LABEL_PRESETS: LABEL_MODES,
  formatBarcodeLabel: formatLabel,
};
