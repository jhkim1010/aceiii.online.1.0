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
      barcode: { x: 10, y: 30,  height: 50, moduleWidth: 2 },
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
      barcode: { x: 120, y: 30, height: 45, moduleWidth: 2 },
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
      barcode: { x: 10, y: 30,  height: 45, moduleWidth: 2 },
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
      barcode: { x: 60,  y: 10,  height: 45, moduleWidth: 2 },
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

/**
 * 바코드 모듈 폭 자동 조절 — 문자 포함 SKU 로 바코드가 길어져 라벨을
 * 넘어가면 설정된 moduleWidth 에서 1까지 줄여 가용 폭에 맞춘다.
 * bc.autoFit === false 면 설정값 그대로 사용.
 * @param {Object} bc - barcode 레이아웃 { x, moduleWidth, autoFit }
 * @param {string} value - 바코드 값
 * @param {string} type - CODE128 | EAN13 | QR
 * @param {string} orientation - 'N' | 'R'
 * @param {Object} region - { width, height }
 * @returns {number} 적용할 moduleWidth
 */
function effectiveModuleWidth(bc, value, type, orientation, region) {
  let mw = Math.max(1, bc.moduleWidth || 2);

  if (bc.autoFit === false || type === 'QR') return mw;

  // EAN13 은 고정 95모듈, CODE128 은 길이 비례
  const modules = type === 'EAN13' ? 95 : code128Modules(value);

  // 회전(R) 시 바코드는 리본 길이 방향(+y)으로 자란다
  const margin = 10;
  const avail = orientation === 'R'
    ? region.height - (bc.y || 0) - margin
    : region.width - (bc.x || 0) - margin;

  while (mw > 1 && modules * mw > avail) {
    mw -= 1;
  }

  return mw;
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
  const bc = layout.barcode || { x: 10, y: 30, height: 45, moduleWidth: 2 };
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
  const speed = parseInt(m.speed, 10);
  if (Number.isFinite(speed) && speed >= 2 && speed <= 14) {
    lines.push(`^PR${speed}`);
  }

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
  const darkness = mode ? parseInt(mode.darkness, 10) : NaN;
  if (Number.isFinite(darkness) && darkness >= 0 && darkness <= 30) {
    labels.push(`~SD${String(darkness).padStart(2, '0')}`);
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

module.exports = {
  formatLabel,
  formatBatchLabels,
  resolveMode,
  estTextWidth,
  nivelFontSize,
  code128Modules,
  effectiveModuleWidth,
  LABEL_MODES,
  LEGACY_PRESET_ALIASES,

  // 하위 호환 (구버전 import 대비)
  LABEL_PRESETS: LABEL_MODES,
  formatBarcodeLabel: formatLabel,
};
