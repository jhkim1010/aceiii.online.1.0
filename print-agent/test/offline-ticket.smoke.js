// [A-2] 인터넷 없이 잡힌 판매의 티켓 — 「NO FISCAL」 + 참조 번호.
//
// ★ 이 검사에는 **대조군이 있다.** 온라인 판매·견적·형식이 틀린 번호가 그대로
//   남는 것을 함께 단언하지 않으면, "무조건 오프라인 티켓을 그린다" 로 바꿔도
//   이 파일은 통과한다.
//
// 실행: node print-agent/test/offline-ticket.smoke.js
const assert = require('assert');
const { formatTempTicketHtml, formatInvoiceHtml } = require('../src/formatter');

const VALIDO = 'OFF-01M21Q5CNV7S0RNG42TTQ44BY4';
const REF = 'Q44BY4'; // 뒤 6자 — 손님이 전화로 불러 주는 값

const base = {
  ticketType: 'invoiced',
  store: { name: 'TIENDA' },
  items: [{ name: 'Producto', quantity: 1, unitPrice: 100, subtotal: 100 }],
  totals: { subtotal: 100, totalAmount: 100 },
  invoice: { seller: 'V', client: 'C' },
};

// ── ① 오프라인 캡처 (번호만 있고 판매번호 없음) ──
const captura = formatTempTicketHtml({ ...base, offlineNumber: VALIDO });
assert(captura.includes('VENTA REGISTRADA SIN CONEXIÓN'), 'banner sin conexión');
assert(captura.includes('NO FISCAL — DOCUMENTO NO VÁLIDO COMO FACTURA'), 'banner no fiscal');
assert(captura.includes('Venta sin conexión —'), 'título de venta, no presupuesto');
assert(!captura.includes('Presupuesto —'), 'NUNCA presupuesto: la venta ya se cobró');
assert(!captura.includes('PRESUPUESTO TEMPORAL'), 'sin banner de presupuesto');
assert(captura.includes(REF), 'referencia corta visible');
assert(captura.includes(VALIDO), 'número completo visible');
assert(captura.includes('no reemplaza la factura'), 'pie: no reemplaza la factura');

// ── ② 동기화 뒤 재인쇄 (판매번호도 있음) → 평소 티켓 + 참조 한 줄 ──
const reimpresion = formatTempTicketHtml({
  ...base,
  offlineNumber: VALIDO,
  invoice: { ...base.invoice, number: 43 },
});
assert(reimpresion.includes('Venta # 43'), 'reimpresión usa el número fiscal');
assert(reimpresion.includes('Ref. sin conexión'), 'reimpresión conserva la referencia');
assert(!reimpresion.includes('NO FISCAL —'), 'reimpresión no lleva el banner de captura');

// ── ③ 대조군: 온라인 판매는 그대로 ──
const online = formatTempTicketHtml({ ...base, invoice: { ...base.invoice, number: 42 } });
assert(online.includes('Venta # 42'), 'control: venta online normal');
assert(!online.includes('SIN CONEXIÓN'), 'control: sin rastro de offline');
assert(!online.includes('NO FISCAL'), 'control: sin NO FISCAL');

// ── ④ 대조군: 견적은 그대로 ──
const presupuesto = formatTempTicketHtml({ ...base, ticketType: 'temp' });
assert(presupuesto.includes('PRESUPUESTO TEMPORAL'), 'control: presupuesto intacto');
assert(!presupuesto.includes('SIN CONEXIÓN'), 'control: presupuesto sin offline');

// ── ⑤ 형식이 틀리면 오프라인 모드를 켜지 않는다 ──
// 아무 문자열이나 「NO FISCAL」을 만들 수 있으면 온라인 판매가 그렇게 찍힐 수 있다.
// 통과한 값이 [0-9A-Z-] 뿐이라는 것이 HTML 보간의 안전 근거이기도 하다.
for (const malo of [
  'OFF-3-17',                          // 옛 형식(지점-seq)
  'OFF-01M21Q5CNV7S0RNG42TTQ44BY',     // 25자
  'OFF-01M21Q5CNV7S0RNG42TTQ44BY44',   // 27자
  'OFF-01M21Q5CNV7S0RNG42TTQ44BYI',    // I 는 Crockford 밖
  '<script>alert(1)</script>',
  '',
  null,
  42,
]) {
  const html = formatTempTicketHtml({ ...base, offlineNumber: malo });
  assert(!html.includes('NO FISCAL'), `formato inválido no activa offline: ${String(malo)}`);
  assert(!html.includes('<script>'), 'nunca interpola markup crudo');
}

// ── ⑥ print_invoice(서버 재인쇄) 경로도 참조를 muestra ──
const invBase = {
  invoice: { number: 'Ticket-000043', date: new Date().toISOString() },
  store: { name: 'X' }, client: { name: 'C' }, seller: { name: 'S' },
  items: [{ quantity: 1, unitPrice: 100, subtotal: 100, name: 'P' }],
  totals: { subtotal: 100, totalAmount: 100 },
};
assert(formatInvoiceHtml({ ...invBase, offlineNumber: VALIDO }).includes('Ref. sin conexión'),
  'print_invoice muestra la referencia');
assert(!formatInvoiceHtml(invBase).includes('Ref. sin conexión'),
  'control: sin offlineNumber no aparece la fila');

console.log('offline-ticket smoke OK');
