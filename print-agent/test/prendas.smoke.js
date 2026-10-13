/**
 * «Prendas: N» arriba del TOTAL (pedido de tienda, 2026-10-13).
 *
 * ① la función pura cuenta bien (normal · devoluciones · promo gratis · decimales · vacío)
 * ② CADA layout la imprime y ARRIBA del TOTAL: venta (formatInvoiceHtml), temporal
 *    (formatTempTicketHtml), temporal sin precios (regalo), texto plano (formatInvoice)
 *    y factura fiscal (formatFiscalHtml, usa `cant`).
 * ③ itemsRaw gana sobre items: el grupo (madre, precio) neto 0 de un cambio de talle
 *    no puede borrar las prendas.
 *
 * Los asserts usan números que sólo salen de la suma correcta (3, no 2 ni 1).
 * Ejecutar: node print-agent/test/prendas.smoke.js
 */
const assert = require('assert');
const { contarPrendas, lineasPrendas, lineasDelTicket } = require('../src/prendas');
const { formatInvoiceHtml, formatTempTicketHtml, formatInvoice } = require('../src/formatter');
const { formatFiscalHtml } = require('../src/fiscal-formatter');

const cuerpo = (html) => html.replace(/<style[\s\S]*?<\/style>/g, '');
const texto = (html) => cuerpo(html).replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ');

// ── ① función pura ─────────────────────────────────────────────────────────
assert.deepStrictEqual(contarPrendas([{ quantity: 2 }, { quantity: 1 }]), { llevadas: 3, devueltas: 0 });
assert.deepStrictEqual(
  contarPrendas([{ quantity: 2 }, { quantity: -1 }, { quantity: 1, isReturn: true }]),
  { llevadas: 2, devueltas: 2 },
  'devolución por signo y por isReturn',
);
assert.deepStrictEqual(
  contarPrendas([{ quantity: 2, unitPrice: 100 }, { quantity: 1, unitPrice: 0, isPromoFree: true }]),
  { llevadas: 3, devueltas: 0 },
  'la prenda de promo gratis se la lleva',
);
assert.deepStrictEqual(lineasPrendas([{ quantity: 1.5 }, { quantity: '1' }]), ['Prendas: 2.5']);
assert.deepStrictEqual(lineasPrendas([{ quantity: 0.1 }, { quantity: 0.2 }]), ['Prendas: 0.3'], 'sin ruido de coma flotante');
assert.deepStrictEqual(lineasPrendas([{ quantity: 2 }, { quantity: 2 }]), ['Prendas: 4'], 'entero sin ceros');
assert.deepStrictEqual(lineasPrendas([{ quantity: 3 }, { quantity: -1 }]), ['Prendas: 3', 'Devueltas: 1']);
assert.deepStrictEqual(lineasPrendas([{ name: 'sin cantidad' }]), ['Prendas: 1'], 'igual que la columna Cnt');
assert.deepStrictEqual(lineasPrendas([]), [], 'vacío → nada');
assert.deepStrictEqual(lineasPrendas(undefined), []);
assert.deepStrictEqual(contarPrendas([{ cant: 2 }, { cant: 1 }]), { llevadas: 3, devueltas: 0 }, 'factura usa cant');

// ③ itemsRaw primero
const grupoNeto = {
  items: [{ name: 'REMERA', quantity: 0 }, { name: 'JEAN', quantity: 1 }],
  itemsRaw: [{ quantity: 1 }, { quantity: -1 }, { quantity: 1 }, { quantity: 1 }],
};
assert.strictEqual(lineasDelTicket(grupoNeto), grupoNeto.itemsRaw);
assert.strictEqual(lineasDelTicket({ items: [{ quantity: 1 }] }).length, 1, 'sin itemsRaw → items');
assert.strictEqual(lineasDelTicket({ items: [{ quantity: 1 }], itemsRaw: [] }).length, 1, 'itemsRaw vacío → items');

// ── ② layouts ──────────────────────────────────────────────────────────────
const venta = {
  ticketType: 'invoiced',
  invoice: { number: 'Ticket-000012', date: '2026-10-13T15:00:00.000Z' },
  items: [
    { name: 'REMERA', quantity: 2, unitPrice: 5000, subtotal: 10000 },
    { name: 'MEDIA PROMO', quantity: 1, unitPrice: 0, subtotal: 0 },
    { name: 'JEAN', quantity: -1, unitPrice: 9000, subtotal: -9000 },
  ],
  totals: { subtotal: 1000, totalAmount: 1000 },
  paymentMethods: [{ method: 'Efectivo', amount: 1000 }],
};

const antesDelTotal = (t, label, totalRe) => {
  const iP = t.indexOf('Prendas: 3');
  const iD = t.indexOf('Devueltas: 1');
  const iT = t.search(totalRe);
  assert(iP >= 0, `${label}: falta «Prendas: 3» → ${t.slice(-400)}`);
  assert(iD > iP, `${label}: falta «Devueltas: 1» después de Prendas`);
  assert(iT > iD, `${label}: Prendas/Devueltas deben ir ARRIBA del TOTAL`);
};

antesDelTotal(texto(formatInvoiceHtml(venta)), 'venta', /TOTAL \$/);
antesDelTotal(texto(formatTempTicketHtml(venta)), 'temporal', /TOTAL \$/);

// sin precios: no hay TOTAL, pero el conteo queda (va bajo los ítems, antes del pie)
const regalo = texto(formatTempTicketHtml({ ...venta, hidePrices: true }));
assert(regalo.includes('Prendas: 3') && regalo.includes('Devueltas: 1'), 'regalo: conteo presente');
assert(!/TOTAL \$/.test(regalo), 'regalo: sigue sin TOTAL');
assert(regalo.indexOf('Prendas: 3') < regalo.indexOf('Gracias por su compra'), 'regalo: antes del pie');

// texto plano
const plano = formatInvoice(venta);
const iTot = plano.findIndex((l) => l.startsWith('TOTAL:'));
assert.strictEqual(plano[iTot - 2], 'Prendas: 3', `texto: ${JSON.stringify(plano)}`);
assert.strictEqual(plano[iTot - 1], 'Devueltas: 1');

// venta sin devoluciones → sin «Devueltas»
const simple = texto(formatInvoiceHtml({ ...venta, items: venta.items.slice(0, 2) }));
assert(simple.includes('Prendas: 3') && !simple.includes('Devueltas'), 'sin devolución no imprime Devueltas');

// sin ítems → sin línea
assert(!texto(formatInvoiceHtml({ ...venta, items: [] })).includes('Prendas'), 'vacío no imprime');

// la reimpresión del servidor: itemsRaw manda sobre el grupo neto
const servidor = texto(formatInvoiceHtml({ ...venta, ...grupoNeto }));
assert(servidor.includes('Prendas: 3') && servidor.includes('Devueltas: 1'), `itemsRaw en el ticket → ${servidor.slice(-300)}`);

// factura fiscal
(async () => {
  const fiscal = texto(
    await formatFiscalHtml({
      letra: 'B', cod: '06', number: '0003-00000012',
      emisor: { razonSocial: 'X', cuit: '20-1-1', condIva: 'RI' },
      receptor: { tipo: 'consumidorFinal' },
      items: [
        { cant: 2, desc: 'REMERA', pUnit: 5000, subtotal: 10000 },
        { cant: 1, desc: 'MEDIA', pUnit: 0, subtotal: 0 },
        { cant: -1, desc: 'JEAN', pUnit: 9000, subtotal: -9000 },
      ],
      total: 1000, cae: '1', caeVto: '2026-10-23', qrUrl: 'https://x',
    }),
  );
  antesDelTotal(fiscal, 'fiscal', /TOTAL: /);
  console.log('prendas smoke OK');
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
