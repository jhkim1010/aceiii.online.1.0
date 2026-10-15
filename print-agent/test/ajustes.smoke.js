/**
 * PEDIDO 29 (2026-10-15) — etiqueta de descuentos / recargos globales del ticket.
 *
 * ① función pura: genérico (vacío, «Descuento», «de», mayúsculas, acentos, espacios) → sólo
 *    la palabra base; nombre propio → «base — nombre».
 * ② los dos layouts (venta formatInvoiceHtml y temporal formatTempTicketHtml) usan la regla,
 *    siguen ARRIBA del TOTAL, y la cantidad de líneas y los montos no cambian.
 * ③ control: el nombre propio NO se borra (si la regla tragara todo, esto falla).
 *
 * Ejecutar: node print-agent/test/ajustes.smoke.js
 */
const assert = require('assert');
const { etiquetaAjuste } = require('../src/ajustes');
const { formatInvoiceHtml, formatTempTicketHtml } = require('../src/formatter');

const cuerpo = (html) => html.replace(/<style[\s\S]*?<\/style>/g, '');
const texto = (html) => cuerpo(html).replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ');

// ── ① función pura ─────────────────────────────────────────────────────────
for (const g of ['', '   ', null, undefined, 'Descuento', 'DESCUENTO', 'descuento ', 'de', 'DE', 'Desc.', 'dto', 'Descuentos']) {
  assert.strictEqual(etiquetaAjuste('descuento', g), '− Descuento', `genérico: ${JSON.stringify(g)}`);
}
for (const g of ['', 'Recargo', 'RECARGO', 'rec']) {
  assert.strictEqual(etiquetaAjuste('recargo', g), '+ Recargo', `genérico recargo: ${JSON.stringify(g)}`);
}
// control: nombres propios se conservan tal cual (recortados)
assert.strictEqual(etiquetaAjuste('descuento', 'Efectivo 10%'), '− Descuento — Efectivo 10%');
assert.strictEqual(etiquetaAjuste('descuento', '  Cliente frecuente '), '− Descuento — Cliente frecuente');
assert.strictEqual(etiquetaAjuste('recargo', 'Tarjeta 3 cuotas'), '+ Recargo — Tarjeta 3 cuotas');
// «Recargo» es genérico para recargo pero NO para descuento (y al revés)
assert.strictEqual(etiquetaAjuste('descuento', 'Recargo'), '− Descuento — Recargo');
assert.strictEqual(etiquetaAjuste('recargo', 'de'), '+ Recargo — de');
assert.throws(() => etiquetaAjuste('otro', 'x'));

// ── ② layouts ──────────────────────────────────────────────────────────────
const venta = {
  ticketType: 'invoiced',
  invoice: { number: 'Ticket-000099', date: '2026-10-15T15:00:00.000Z' },
  items: [{ name: 'REMERA', quantity: 2, unitPrice: 50000, subtotal: 100000 }],
  totals: { subtotal: 100000, totalAmount: 63500 },
  discounts: [
    { name: 'Descuento', amount: 30000 },
    { name: 'de', amount: 1000 },
    { name: 'Efectivo 10%', amount: 6000 },
  ],
  recharges: [{ name: 'Recargo', amount: 500 }],
  paymentMethods: [{ method: 'Efectivo', amount: 63500 }],
};

for (const [label, fn] of [['venta', formatInvoiceHtml], ['temporal', formatTempTicketHtml]]) {
  const html = cuerpo(fn(venta));
  const t = texto(fn(venta));
  assert(!/Descuento — Descuento/.test(t), `${label}: no repite «Descuento — Descuento»`);
  assert(!/Descuento — de\b/.test(t), `${label}: no imprime «Descuento — de»`);
  assert(!/Recargo — Recargo/.test(t), `${label}: no repite «Recargo — Recargo»`);
  assert(t.includes('− Descuento — Efectivo 10%'), `${label}: conserva el nombre propio`);
  // misma cantidad de líneas de descuento que antes (3) y de recargo (1)
  assert.strictEqual((html.match(/class="sum-row minus"/g) || []).length, 3, `${label}: 3 líneas de descuento`);
  assert.strictEqual((html.match(/class="sum-row plus"/g) || []).length >= 1, true, `${label}: recargo presente`);
  // montos intactos
  for (const m of ['30.000', '1.000', '6.000']) assert(t.includes(m), `${label}: monto ${m}`);
  // arriba del TOTAL
  const iD = t.indexOf('− Descuento');
  const iT = t.search(/TOTAL \$/);
  assert(iD >= 0 && iT > iD, `${label}: descuento arriba del TOTAL`);
}

// el nombre se escapa (no rompe el HTML del ticket)
assert(cuerpo(formatTempTicketHtml({ ...venta, discounts: [{ name: '<b>VIP</b>', amount: 1 }] })).includes('&lt;b&gt;VIP&lt;/b&gt;'));

console.log('ajustes.smoke OK');
