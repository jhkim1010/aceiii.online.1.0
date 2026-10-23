/**
 * PEDIDO 89 (suerte) — «Imprimir sin info de categoría» y «Código (SKU) en columna».
 *
 * ① función pura: sólo el primer «[...]» inicial; si no queda nada, el nombre igual
 * ② sin opciones (default) el ticket NO cambia: [SKU] dentro de la descripción, «SubTot»
 * ③ sinCategoria: venta, temporal, regalo y texto plano pierden el «[categoría]»; el payload no se muta
 * ④ skuColumna: Cnt · SKU · Descripcion · P.Unit · Precio, el SKU sale de la descripción,
 *   la matriz de variantes cubre una columna más (colspan 4) y el regalo sigue sin precios
 * ⑤ configure: sólo booleanos; getOpciones es lo que usan los formatters por defecto
 *
 * Ejecutar: node print-agent/test/ticket-items.smoke.js
 */
const assert = require('assert');
const ticketItems = require('../src/ticket-items');
const { formatInvoiceHtml, formatTempTicketHtml, formatInvoice } = require('../src/formatter');

const cuerpo = (html) => html.replace(/<style[\s\S]*?<\/style>/g, '');
const texto = (html) => cuerpo(html).replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ');

const data = () => ({
  invoice: { number: '1043', date: '2026-10-22T15:30:00-03:00' },
  seller: { name: '001 caja' },
  items: [
    {
      quantity: 2, unitPrice: 3500, subtotal: 7000, code: 'AP0123',
      name: '[ACCESORRIOS DE PELO] COLITA B/N',
      variants: { colors: ['Rojo', 'Azul'], sizes: ['S', 'M'], matrix: { Rojo: { S: 1 }, Azul: { M: 1 } } },
    },
    { quantity: 1, unitPrice: 900, subtotal: 900, code: '', name: 'Venta libre' },
  ],
  totals: { subtotal: 7900, totalAmount: 7900 },
  paymentMethods: [{ method: 'Efectivo', amount: 7900 }],
});

const NADA = { sinCategoria: false, skuColumna: false };
const SIN_CAT = { sinCategoria: true, skuColumna: false };
const AMBAS = { sinCategoria: true, skuColumna: true };

// ── ① función pura ─────────────────────────────────────────────────────────
assert.strictEqual(ticketItems.nombreSinCategoria('[ACCESORRIOS DE PELO] COLITA B/N'), 'COLITA B/N');
assert.strictEqual(ticketItems.nombreSinCategoria('  [A/-]  AROS'), 'AROS');
assert.strictEqual(ticketItems.nombreSinCategoria('[A] [B] AROS'), '[B] AROS', 'sólo el primer bloque');
assert.strictEqual(ticketItems.nombreSinCategoria('AROS [DORADO]'), 'AROS [DORADO]', 'sólo al inicio');
assert.strictEqual(ticketItems.nombreSinCategoria('[SOLO CATEGORIA]'), '[SOLO CATEGORIA]', 'vacío → igual');
assert.strictEqual(ticketItems.nombreSinCategoria(undefined), undefined);

// ── ② default: nada cambia ─────────────────────────────────────────────────
{
  const t = texto(formatInvoiceHtml(data(), NADA));
  assert.ok(t.includes('[AP0123] [ACCESORRIOS DE PELO] COLITA B/N'), t);
  assert.ok(t.includes('SubTot') && !t.includes(' SKU '));
  assert.ok(!formatInvoiceHtml(data(), NADA).includes('sku-cell'));
}

// ── ③ sin categoría ────────────────────────────────────────────────────────
{
  const d = data();
  const venta = texto(formatInvoiceHtml(d, SIN_CAT));
  assert.ok(venta.includes('[AP0123] COLITA B/N'), venta);
  assert.ok(!venta.includes('ACCESORRIOS'), 'venta');
  assert.ok(!texto(formatTempTicketHtml(d, SIN_CAT)).includes('ACCESORRIOS'), 'temporal');
  assert.ok(!texto(formatTempTicketHtml({ ...d, hidePrices: true }, SIN_CAT)).includes('ACCESORRIOS'), 'regalo');
  assert.ok(!formatInvoice(d, 48, SIN_CAT).join('\n').includes('ACCESORRIOS'), 'texto plano');
  assert.strictEqual(d.items[0].name, '[ACCESORRIOS DE PELO] COLITA B/N', 'no muta el payload');
}

// ── ④ SKU en columna ───────────────────────────────────────────────────────
{
  const html = formatInvoiceHtml(data(), AMBAS);
  const t = texto(html);
  assert.ok(/Cnt SKU Descripcion P\.Unit Precio/.test(t), t);
  assert.ok(!t.includes('SubTot'));
  assert.ok(/<td class="qty-cell">2<\/td>\s*<td class="sku-cell">AP0123<\/td>\s*<td class="desc-cell">COLITA B\/N<\/td>/.test(html), 'fila');
  assert.ok(!html.includes('[AP0123]'), 'el SKU ya no va en la descripción');
  assert.ok(/<td class="sku-cell"><\/td>\s*<td class="desc-cell">Venta libre<\/td>/.test(html), 'sin SKU: celda vacía');
  assert.ok(html.includes('colspan="4" class="variant-table-cell"'), 'matriz cubre la columna extra');
  assert.ok(html.includes('.sku-cell'), 'CSS de la columna');

  const temp = formatTempTicketHtml(data(), AMBAS);
  assert.ok(/Cnt SKU Descripcion P\.Unit Precio/.test(texto(temp)));

  const regalo = formatTempTicketHtml({ ...data(), hidePrices: true }, AMBAS);
  assert.ok(/Cnt SKU Descripcion/.test(texto(regalo)) && !texto(regalo).includes('P.Unit'), 'regalo sin precios');
  assert.ok(!texto(regalo).includes('3.500'), 'regalo sin montos');

  assert.ok(formatInvoice(data(), 48, AMBAS).some((l) => l.startsWith('2  AP0123  COLITA B/N')), 'texto plano');
}

// ── ⑤ configure ────────────────────────────────────────────────────────────
{
  assert.deepStrictEqual(ticketItems.getOpciones(), NADA, 'apagado por defecto');
  ticketItems.configure({ sinCategoria: true, skuColumna: 'si' });
  assert.deepStrictEqual(ticketItems.getOpciones(), SIN_CAT, 'no-booleano ignorado');
  assert.ok(!texto(formatInvoiceHtml(data())).includes('ACCESORRIOS'), 'el default lee la opción guardada');
  ticketItems.configure({ sinCategoria: false });
}

console.log('ticket-items.smoke OK');
