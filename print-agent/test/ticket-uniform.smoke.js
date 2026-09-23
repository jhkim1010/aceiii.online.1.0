/**
 * 두 판매 티켓의 **모양이 같은지** 재는 시험 (2026-09-23).
 *
 * 무슨 일이 있었나: 같은 판매인데 F2(`print_temp` → `formatTempTicketHtml`)와
 * 「티켓 다시 출력」(`print_invoice` → `formatInvoiceHtml`)이 서로 다른 종이를 냈다.
 *   · 재인쇄 쪽만 매장 이름·주소·CUIT 를 찍었다
 *   · 날짜·시각이 한쪽은 제목 줄 인라인, 한쪽은 «Fecha»/«Hora» 라벨 행이었다
 *   · 기본 꼬리 문구가 둘 다 달랐다
 *
 * ★ 사용자 지시: **비-fiscal 티켓에는 매장 이름을 절대 찍지 않는다.**
 *   AFIP 정식 전표(`fiscal-formatter.js`)는 예외다 — razonSocial·CUIT·domicilio 는
 *   법정 기재사항이라 그쪽에서 빼면 전표가 무효가 된다. 그래서 이 파일은
 *   `formatTempTicketHtml` 과 `formatInvoiceHtml` 만 잰다.
 *
 * ★ 이 시험은 «없음» 을 단언한다 — 렌더가 통째로 실패해도 «없음» 은 성립한다.
 *   그래서 아래 ⓪ 대조군이 **먼저** 있어야 한다: 같은 payload 의 다른 값이
 *   실제로 종이에 나왔다는 것을 확인하고 나서야 «매장 이름이 없다» 가 의미를 갖는다.
 */
const assert = require('assert');
const { formatTempTicketHtml, formatInvoiceHtml, formatInvoice } = require('../src/formatter');

// 매장 정보를 **일부러 전부 채워서** 넘긴다 — 빠뜨린 게 아니라 «찍지 않는다» 를 재려면
// 입력에 값이 있어야 한다. 값이 없으면 이 시험은 아무것도 지키지 않는다.
const STORE = { name: 'NOIX-SMOKE', address: 'MORON 3258', cuit: '20337391916', phone: '1122334455' };

const base = {
  store: STORE,
  items: [{ name: 'Remera', quantity: 2, unitPrice: 1000, subtotal: 2000 }],
  totals: { subtotal: 2000, totalAmount: 2000 },
  seller: { name: 'Vendedor-X' },
  client: { name: 'Cliente-Y' },
  invoice: {
    number: 6,
    date: '2026-09-23T12:21:29',
    seller: 'Vendedor-X',
    client: 'Cliente-Y',
  },
};

const f2      = formatTempTicketHtml({ ...base, ticketType: 'invoiced' });
const reimpre = formatInvoiceHtml(base);

// ── ⓪ 대조군 — 렌더가 실제로 일어났다 ──────────────────────────────────────
// 이게 없으면 아래 «매장 이름 없음» 은 «빈 문자열» 로도 통과한다.
for (const [nombre, html] of [['F2', f2], ['reimpresión', reimpre]]) {
  assert(html.includes('Vendedor-X'), `control: ${nombre} renderizó el vendedor`);
  assert(html.includes('Cliente-Y'), `control: ${nombre} renderizó el cliente`);
  assert(html.includes('Remera'), `control: ${nombre} renderizó los items`);
}

// ── ① 매장 이름·주소·CUIT·teléfono 는 어느 쪽에도 없다 ──────────────────────
for (const [nombre, html] of [['F2', f2], ['reimpresión', reimpre]]) {
  assert(!html.includes(STORE.name), `${nombre}: NUNCA el nombre de la tienda`);
  assert(!html.includes(STORE.address), `${nombre}: sin dirección`);
  assert(!html.includes(STORE.cuit), `${nombre}: sin CUIT`);
  assert(!html.includes(STORE.phone), `${nombre}: sin teléfono`);
  assert(!html.includes('CUIT:'), `${nombre}: sin etiqueta CUIT`);
  assert(!html.includes('class="store-header"'), `${nombre}: sin bloque store-header`);
}

// ── ② 날짜·시각은 둘 다 «Fecha»/«Hora» 라벨 행 ─────────────────────────────
// ★ label 과 value 를 **같은 행 안에서** 묶어 읽는다. 문서 아무 데서나 '>Fecha<' 와
//   '23/09/2026' 을 따로 찾으면 행이 끊겨도, 두 값이 뒤바뀌어도 통과한다
//   (2026-09-23 codex LOW 지적).
const filaMeta = (html, label) => {
  const re = new RegExp(
    `<span class="meta-label">${label}</span>\\s*<span class="meta-val">([^<]*)</span>`,
  );
  const m = re.exec(html);

  return m ? m[1].trim() : null;
};

for (const [nombre, html] of [['F2', f2], ['reimpresión', reimpre]]) {
  assert(filaMeta(html, 'Fecha') === '23/09/2026', `${nombre}: fila Fecha con la fecha de la venta`);
  assert(filaMeta(html, 'Hora') === '12:21:29', `${nombre}: fila Hora con la hora de la venta`);
  // 제목 줄에 다시 인라인으로 붙으면 안 된다 (그게 종전 F2 의 모양이었다).
  assert(!/presupuesto-title">[^<]*—[^<]*\d{2}\/\d{2}\/\d{4}/.test(html),
    `${nombre}: la fecha no vuelve al título`);
}

// ── ③ el payload REAL de F2 manda date y time por separado ─────────────────
// `ProductList.tsx` (autoImpTiq) envía `date: '23/9/2026'` + `time: '12:21:29'`.
// Parsear sólo la fecha da la medianoche → «Hora 00:00:00» en el papel.
// Esto se rompió de verdad el 2026-09-23 y lo cazó codex, no este test:
// el fixture ISO de arriba pasaba igual. Por eso el caso real va aparte.
const f2Real = formatTempTicketHtml({
  ...base,
  ticketType: 'invoiced',
  invoice: { number: 6, date: '23/9/2026', time: '12:21:29', seller: 'Vendedor-X', client: 'Cliente-Y' },
});
assert(filaMeta(f2Real, 'Fecha') === '23/09/2026', 'payload real: fecha');
assert(filaMeta(f2Real, 'Hora') === '12:21:29', 'payload real: hora (NO 00:00:00)');

// time con formato basura no se imprime crudo — se cae a la hora de la fecha.
const f2Sucio = formatTempTicketHtml({
  ...base,
  ticketType: 'invoiced',
  invoice: { number: 6, date: '2026-09-23T12:21:29', time: '<script>x</script>', seller: 'V', client: 'C' },
});
assert(!f2Sucio.includes('<script>'), 'nunca interpola un time con markup');
assert(filaMeta(f2Sucio, 'Hora') === '12:21:29', 'time inválido → hora de la fecha');

// ── ④ 기본 꼬리 문구가 같다 ─────────────────────────────────────────────────
for (const linea of ['¡Gracias por su compra!', 'Conserve este comprobante']) {
  assert(f2.includes(linea), `F2: pie «${linea}»`);
  assert(reimpre.includes(linea), `reimpresión: pie «${linea}»`);
}
// 매장별 문구는 서버가 `footer.extra` 로 싣는다 — 에이전트에 박아 두지 않는다.
assert(!reimpre.includes('falla de fábrica'),
  'la política de una tienda no va hardcodeada en el agente');

// ── ⑤ 대조군 — 매장이 설정한 문구는 여전히 나간다 ───────────────────────────
// Los DOS caminos tienen que seguir imprimiéndolo: si sólo se comprueba uno,
// borrar `renderFooterExtra` del otro sobrevive (2026-09-23 codex LOW).
const conExtra = formatInvoiceHtml({ ...base, footer: { extra: ['@mitienda', 'Cambios: Lun-Vie'] } });
assert(conExtra.includes('@mitienda'), 'control: reimpresión imprime footer.extra');
const f2ConExtra = formatTempTicketHtml({
  ...base, ticketType: 'invoiced', footer: { extra: ['@mitienda'] },
});
assert(f2ConExtra.includes('@mitienda'), 'control: F2 imprime footer.extra');

// ── ⑥ el fallback de texto sigue la misma regla ────────────────────────────
// Hoy no lo llama nadie (src/index.js es código muerto), pero el módulo lo exporta:
// si alguien lo revive, la regla «sin nombre de tienda» tiene que seguir en pie.
// ★ `formatInvoice` devuelve un ARRAY de líneas, no un string — `.includes()` sobre
//   el array compara elementos completos y daría false siempre (el control lo cazó).
const texto = [].concat(formatInvoice(base)).join('\n');
assert(texto.includes('Vendedor-X'), 'control: el fallback de texto sí renderizó');
assert(!texto.includes(STORE.name), 'fallback de texto: NUNCA el nombre de la tienda');
assert(!texto.includes(STORE.cuit), 'fallback de texto: sin CUIT');

console.log('ticket-uniform smoke OK');
