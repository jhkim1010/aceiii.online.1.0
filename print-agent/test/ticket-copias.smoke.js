// Copias del ticket de venta (2026-10-07) — sólo el automático de la venta; nunca 2×N.
// 실행: node print-agent/test/ticket-copias.smoke.js
const assert = require('assert');
const path = require('path');
const { copiasDelTicket, normalizarCopias } = require('../src/ticket-copias');

// ── ① qué trabajos llevan copias ──
const venta = { printJobId: 'sale-invoice:42' };
assert.strictEqual(copiasDelTicket(venta, 3), 3, 'ticket automático de la venta: lo configurado');
assert.strictEqual(copiasDelTicket(venta, 2), 2);
assert.strictEqual(copiasDelTicket({ printJobId: 'sale-reprint:42:abc' }, 3), 1, 'reimpresión: 1');
assert.strictEqual(copiasDelTicket({ printJobId: 'sale-invoice:42', factura: {} }, 3), 1, 'factura AFIP: 1');
assert.strictEqual(copiasDelTicket({}, 3), 1, 'sin printJobId (servidor viejo): 1');
assert.strictEqual(copiasDelTicket(null, 3), 1);

// ── ② lo guardado raro nunca multiplica ──
for (const raro of [undefined, null, 0, -1, 4, 99, 1.5, '2x', NaN, {}]) {
  assert.strictEqual(normalizarCopias(raro), 1, `copias(${String(raro)}) = 1`);
}
assert.strictEqual(normalizarCopias('2'), 2, 'el select guarda número; texto numérico también sirve');

// ── ③ la tubería: se dibuja una vez y se manda N veces ──
const dir = path.join(__dirname, '..', 'src');
let dibujos = 0;
let envios = 0;
require.cache[require.resolve(path.join(dir, 'renderer-engine'))] = {
  exports: { renderHtmlToPng: async () => { dibujos += 1; return Buffer.from('png'); } },
};
require.cache[require.resolve(path.join(dir, 'printer'))] = {
  exports: { printImage: async () => { envios += 1; } },
};
require.cache[require.resolve(path.join(dir, 'formatter'))] = {
  exports: { formatInvoiceHtml: () => '<html></html>' },
};
const { printTicket } = require('../src/print-pipeline');
const cfg = { type: 'network', host: 'x', port: 9100 };

(async () => {
  await printTicket({}, cfg, () => {}, { copias: 3 });
  assert.deepStrictEqual([dibujos, envios], [1, 3], '3 copias = 1 dibujo, 3 envíos');

  dibujos = 0; envios = 0;
  await printTicket({}, cfg, () => {});
  assert.deepStrictEqual([dibujos, envios], [1, 1], 'sin opción: 1 (como antes)');

  dibujos = 0; envios = 0;
  await printTicket({}, cfg, () => {}, { copias: 0 });
  assert.deepStrictEqual([dibujos, envios], [1, 1], 'copias inválidas: 1');

  console.log('ticket-copias.smoke OK');
})().catch((e) => { console.error(e); process.exit(1); });
