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
    layout: {
      priceCount: 1,
      name:    { x: 160, y: 10,  fontSize: 20 },
      barcode: { x: 60,  y: 10,  height: 45, moduleWidth: 3 },
      price1:  { x: 20,  y: 10,  fontSize: 24, bold: true },
      price2:  { x: 20,  y: 200, fontSize: 18, bold: false },
      price3:  { x: 20,  y: 300, fontSize: 18, bold: false },
    },
  },
};

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

  return `$${num.toLocaleString('es-AR', { minimumFractionDigits: 2 })}`;
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
 * @param {string} qrUrl - 인코딩할 딥링크
 * @param {number} cap - 사용자 상한 (#qr-module). falsy(0 포함/undefined) 면 기본 6.
 * @param {number} heightDots - 라벨 높이 (dot)
 * @param {number} regionDots - 상품 1장 폭 (dot)
 * @returns {number} 적용할 magnification (1 이상)
 */
function effectiveQrModule(qrUrl, cap, heightDots, regionDots) {
  const modules = qrModuleCount(utf8Len(qrUrl));
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
    lines.push(`^FO${nm.x + offsetX},${nm.y}${font},${nm.fontSize},${nm.fontSize}^FD${sanitize(item.name)}^FS`);
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
function formatBatchLabels(items, mode) {
  const labels = [];

  // 출력 밀도 (~SD — 절대값 00~30, 미설정 시 프린터 기본값)
  // ~SD 는 라벨 포맷(^XA..^XZ) 밖의 전역 명령이라 배치 앞에 1회만 전송
  const sd = mode ? darknessZpl(mode.darkness) : null;
  if (sd) labels.push(sd);

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
 * 단일 상품 QR 블록 렌더 (offsetX 적용 — doble 오른쪽 복제본용)
 * 좌 = QR(qrUrl 인코딩, 자동맞춤), 우 = 제품명(줄바꿈) + `{priceLabel}: {price}`.
 * 좌우 경계는 고정 비율이 아니라 QR 실측 폭에서 역산한다 (2026-07-15 D-5).
 * @param {Object} p - { qrUrl, name, price, priceLabel, qrModule, fontSize, region, height, offsetX }
 * @returns {string[]} ZPL 라인 배열
 */
function renderQrBlock(p) {
  const { qrUrl, name, price, priceLabel, qrModule, fontSize, region, height, offsetX } = p;
  const lines = [];

  // qrModule 은 사용자 상한 — 라벨 높이/폭에 맞춰 실효값을 산출한다
  const modules = qrModuleCount(utf8Len(qrUrl));
  const module = effectiveQrModule(qrUrl, qrModule, height, region);

  // 좌 QR — qrUrl 을 훼손 없이 인코딩 (Phase 37 파서 계약: sanitize 는 ^,~ 만 제거, 딥링크엔 없음)
  // ECC M(^FDMA) — Q 에서 낮춰 같은 높이에 더 큰 QR (D-7)
  lines.push(`^FO${offsetX + QR_MARGIN},${QR_MARGIN}^BQN,2,${module}^FDMA,${sanitize(qrUrl)}^FS`);

  // 우 패널 — QR 우측끝에서 gap 만큼 띄운 지점부터. 폭 55% 캡 덕에 항상 텍스트 자리가 남는다.
  const qrRight = QR_MARGIN + modules * module;
  const textX = offsetX + qrRight + QR_GAP;
  const availW = Math.max(1, region - qrRight - QR_GAP - QR_MARGIN);

  let y = QR_MARGIN;
  const nameLines = wrapQrText(sanitize(name || ''), fontSize, availW);
  for (const ln of nameLines) {
    lines.push(`^FO${textX},${y}^A0N,${fontSize},${fontSize}^FD${ln}^FS`);
    y += fontSize + 4;
  }

  // 가격줄 — `{priceLabel}: {price}` (이름 아래)
  const priceFs = Math.max(14, Math.round(fontSize * 0.9));
  const priceText = `${sanitize(priceLabel || '')}: ${formatPrice(price)}`.trim();
  lines.push(`^FO${textX},${y}^A0N,${priceFs},${priceFs}^FD${priceText}^FS`);

  return lines;
}

/**
 * QR 델타 라벨 ZPL 생성 (순수 함수) — Phase 38 D-8/D-9/D-10.
 *   좌 QR(qrUrl 딥링크, 자동맞춤으로 폭 55% 캡까지 확대) + 우 제품명 + 가격(나머지 폭 전부).
 *   좌우 경계는 고정 비율이 아니라 QR 실측 폭에서 역산한다. mode='doble' 이면 같은 상품 2장.
 * @param {Object} args
 * @param {string} args.qrUrl - `${WEB}/m/stock?s=&p=` 딥링크 (그대로 인코딩)
 * @param {string} args.name - 제품명
 * @param {number|string} args.price - 가격
 * @param {string} args.priceLabel - 가격 라벨 (예: Minorista)
 * @param {Object} [args.layout] - { widthMm, heightMm, qrModule, fontSize, mode, darkness, speed }
 *   qrModule 은 상한(기본 6) — 라벨 높이/폭이 실효값을 줄일 수 있다.
 *   (연혁) 과거엔 좌우 폭을 splitRatio 로 고정 분할했으나 폐기 — 지금은 QR 실측 폭에서 역산.
 * @returns {string} ZPL 문자열
 */
function formatQrLabel({ qrUrl, name, price, priceLabel, layout } = {}) {
  const cfg = layout || {};
  const widthMm = cfg.widthMm || 50;
  const heightMm = cfg.heightMm || 25;
  const qrModule = cfg.qrModule || 6;
  const fontSize = cfg.fontSize || 22;
  const mode = cfg.mode === 'doble' ? 'doble' : 'simple';

  // 203dpi 환산 (1mm ≈ 8dot). region = 상품 1장 폭, doble 은 미디어 폭 2배
  const region = Math.round(widthMm * 8);
  const H = Math.round(heightMm * 8);
  const totalW = mode === 'doble' ? region * 2 : region;

  // 밀도(~SD)는 포맷 밖 전역 명령 → ^XA 앞, 속도(^PR)는 포맷 안.
  // QR 은 항목별로 따로 전송되므로(qr:print 루프) 라벨마다 동봉한다.
  const lines = [];
  const sd = darknessZpl(cfg.darkness);
  if (sd) lines.push(sd);

  lines.push('^XA', `^PW${totalW}`, `^LL${H}`, '^CI28');

  const pr = speedZpl(cfg.speed);
  if (pr) lines.push(pr);

  const blockArgs = { qrUrl, name, price, priceLabel, qrModule, fontSize, region, height: H };

  // 왼쪽 (또는 단일) 블록
  lines.push(...renderQrBlock({ ...blockArgs, offsetX: 0 }));

  // doble: 같은 상품을 오른쪽에 복제 (offsetX = region)
  if (mode === 'doble') {
    lines.push(...renderQrBlock({ ...blockArgs, offsetX: region }));
  }

  lines.push('^XZ');

  return lines.join('\n');
}

module.exports = {
  formatLabel,
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

  // 하위 호환 (구버전 import 대비)
  LABEL_PRESETS: LABEL_MODES,
  formatBarcodeLabel: formatLabel,
};
