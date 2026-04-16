/**
 * 상품 데이터 → ZPL II 문자열 변환
 * CODE128, EAN13, QR 3가지 바코드 타입 지원
 */

// 바코드 타입별 ZPL 명령어 매핑
const BARCODE_COMMANDS = {
  CODE128: (x, y, value, height = 60) =>
    `^FO${x},${y}^BY2^BCN,${height},Y,N,N^FD${value}^FS`,
  EAN13: (x, y, value, height = 60) =>
    `^FO${x},${y}^BY2^BEN,${height},Y,N^FD${value}^FS`,
  QR: (x, y, value) =>
    `^FO${x},${y}^BQN,2,4^FDQA,${value}^FS`,
};

/**
 * 단일 상품 바코드 라벨 ZPL 생성
 * @param {Object} item - { name, price, barcode, barcodeType }
 * @param {Object} store - { name }
 * @param {Object} labelSize - { width, height } (dot 단위, 기본 400x236)
 * @returns {string} ZPL 문자열
 */
function formatBarcodeLabel(item, store = {}, labelSize = {}) {
  const width = labelSize.width || 400;
  const height = labelSize.height || 236;
  const barcodeType = (item.barcodeType || 'CODE128').toUpperCase();
  const barcodeCmd = BARCODE_COMMANDS[barcodeType] || BARCODE_COMMANDS.CODE128;

  // 가격 포맷 (소수점 2자리, $ 접두사)
  const priceStr = typeof item.price === 'number'
    ? `$${item.price.toLocaleString('es-AR', { minimumFractionDigits: 2 })}`
    : `$${item.price || '0.00'}`;

  const lines = [
    '^XA',
    `^PW${width}`,
    `^LL${height}`,
    '^CI28',
    // 상품명 (상단)
    `^FO20,10^A0N,28,28^FD${sanitize(item.name || '')}^FS`,
    // 가격
    `^FO20,45^A0N,22,22^FD${priceStr}^FS`,
    // 바코드
    barcodeCmd(20, 80, item.barcode || '', 60),
    // 매장명 (하단)
    `^FO20,160^A0N,18,18^FD${sanitize(store.name || '')}^FS`,
    '^XZ',
  ];

  return lines.join('\n');
}

/**
 * 여러 상품 라벨 ZPL 일괄 생성 (qty 반복 포함)
 * @param {Array} items - [{ name, price, barcode, barcodeType, qty }]
 * @param {Object} store - { name }
 * @param {Object} labelSize - { width, height }
 * @returns {string} 전체 ZPL 문자열 (라벨 연속)
 */
function formatBatchLabels(items, store = {}, labelSize = {}) {
  const labels = [];

  for (const item of items) {
    const qty = Math.max(1, item.qty || 1);
    const zpl = formatBarcodeLabel(item, store, labelSize);

    for (let i = 0; i < qty; i++) {
      labels.push(zpl);
    }
  }

  return labels.join('\n');
}

// ZPL 특수문자 이스케이프 (^, ~ 제거)
function sanitize(str) {
  return String(str).replace(/[\^~]/g, '');
}

module.exports = { formatBarcodeLabel, formatBatchLabels };
