// [2026-09-09] 티켓 날짜 — «Invalid Date» 도, **조용히 틀린 날짜**도 손님에게 안 간다.
//
// 무슨 일이 있었나: `formatInvoiceHtml` 이 `new Date(data.invoice.date)` 로 파싱했고,
// `buildTestTicketData`(print-agent 자신)가 `toLocaleDateString('es-AR')` 로 "13/9/2026"
// 을 보냈다. JS 는 그 문자열을 **미국식 M/D/Y 로 읽는다**:
//   · 13~31 일 → 월이 13 이상이라 `Invalid Date` → 종이에 "Invalid Date" 가 찍힌다.
//   · 1~12 일  → **월과 일이 조용히 뒤바뀐다.** "5/9/2026" 이 5월 9일이 된다.
//     이쪽이 더 나쁘다 — 틀린 줄 아무도 모른다.
//
// ★ 이 검사에는 **대조군이 있다.** 정상 ISO 가 정확히 그 날짜로 렌더되는 것을 함께
//   단언하지 않으면 "항상 «—» 를 찍는다" 로 바꿔도 통과한다.
//
// ★ 폴백 규칙(codex 지적): 「없다」와 「깨졌다」는 다르게 다룬다.
//   없으면 지금 시각(레거시 payload 보존), 깨졌으면 «—»(날짜를 만들어내지 않는다).
//
// 실행: node print-agent/test/ticket-date.smoke.js
const assert = require('assert');
const { formatInvoiceHtml } = require('../src/formatter');

const base = {
  store: { name: 'TIENDA' },
  client: { name: 'C' },
  seller: { name: 'S' },
  invoice: { number: 'Ticket-000001' },
  items: [{ name: 'P', quantity: 1, unitPrice: 100, subtotal: 100 }],
  totals: { subtotal: 100, totalAmount: 100 },
};

const render = (date) =>
  formatInvoiceHtml({ ...base, invoice: { ...base.invoice, date } });

// 렌더된 「Fecha」 값만 꺼낸다.
function fechaDe(html) {
  assert(!html.includes('Invalid Date'), 'nunca imprime "Invalid Date"');
  const m = html.match(/meta-val">([^<]+)<\/span>/);

  return m ? m[1].trim() : null;
}

// ── ① 정상 경로(대조군) — 서버 buildInvoiceData 는 항상 ISO 를 보낸다 ──
assert.strictEqual(
  fechaDe(render('2026-09-13T10:20:30.000Z')),
  '13/09/2026',
  'ISO se rinde con la fecha exacta',
);

// ── ② 옛 클라이언트의 es-AR 문자열 — 구제하되 **뒤바꾸지 않는다** ──
assert.strictEqual(fechaDe(render('13/9/2026')), '13/09/2026', 'dd/mm/yyyy dia 13');
// ★ 여기가 핵심이다. 수정 전에는 이 값이 09/05/2026(5월 9일)로 나왔다.
assert.strictEqual(
  fechaDe(render('5/9/2026')),
  '05/09/2026',
  'dd/mm/yyyy dia 5 — NO se invierte a 09/05',
);
assert.strictEqual(fechaDe(render('1/12/2026')), '01/12/2026', 'dd/mm/yyyy dia 1');

// ── ③ 존재하지 않는 날짜 · 쓰레기 → 날짜를 **만들어내지 않는다** ──
for (const roto of ['31/2/2026', '0/9/2026', '13/13/2026', 'no-es-fecha', '2026-99-99']) {
  assert.strictEqual(
    fechaDe(render(roto)),
    '—',
    `fecha corrupta se deja en blanco: ${roto}`,
  );
}

// ── ④ 날짜가 아예 없는 레거시 payload → 지금 시각(종전 동작 보존) ──
const hoy = new Date().toLocaleDateString('es-AR', {
  day: '2-digit',
  month: '2-digit',
  year: 'numeric',
});
for (const ausente of [undefined, null, '']) {
  assert.strictEqual(
    fechaDe(render(ausente)),
    hoy,
    `sin fecha usa el momento actual: ${String(ausente)}`,
  );
}

// ── ⑤ Date 객체와 epoch 도 받는다 ──
assert.strictEqual(
  fechaDe(render(new Date(2026, 8, 13, 10, 20))),
  '13/09/2026',
  'objeto Date',
);
assert.strictEqual(
  fechaDe(render(Date.UTC(2026, 8, 13, 12, 0))),
  '13/09/2026',
  'epoch ms',
);

// ── ⑥ 이 저장소 자신의 시험 티켓이 ISO 를 보내는가 (생산자 쪽 회귀 방어) ──
// main.js 를 require 하면 Electron 이 필요하므로 소스를 읽어 확인한다.
const fs = require('fs');
const path = require('path');
const mainSrc = fs.readFileSync(path.join(__dirname, '..', 'main.js'), 'utf8');
const bloque = mainSrc.slice(
  mainSrc.indexOf('function buildTestTicketData'),
  mainSrc.indexOf('async function printTest'),
);
assert(bloque.length > 0, 'se encontro buildTestTicketData');

// ★ **주석은 세지 않는다.** 처음 이 검사를 쓸 때 주석에 적어 둔
//   'toLocaleDateString' 이라는 낱말 때문에 헛실패했다 — 검사가 코드가 아니라
//   설명문을 읽고 있었다. 실제 payload 줄만 본다.
const lineasCodigo = bloque
  .split('\n')
  .map((l) => l.trim())
  .filter((l) => l && !l.startsWith('//'));
const lineaFecha = lineasCodigo.find((l) => l.startsWith('date:'));

assert(lineaFecha, 'buildTestTicketData tiene un campo date');
assert(
  lineaFecha.includes('toISOString()'),
  `buildTestTicketData envia ISO — encontrado: ${lineaFecha}`,
);
assert(
  !lineasCodigo.some((l) => /^(date|time):/.test(l) && l.includes('toLocale')),
  'control: ningun campo de fecha/hora usa toLocaleDateString/TimeString',
);

console.log('ticket-date smoke OK');
