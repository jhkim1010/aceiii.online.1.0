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

// [2026-10-08] el ticket de venta del POS (F2) llega como print_temp con `sale-auto:<venta>`
assert.strictEqual(copiasDelTicket({ printJobId: 'sale-auto:216521' }, 2), 2, 'POS F2: lo configurado');
assert.strictEqual(copiasDelTicket({ printJobId: 'sale-auto:OFF-01J9X' }, 3), 3, 'POS sin internet: también');
assert.strictEqual(copiasDelTicket({ printJobId: 'sale-modify:216521:k1' }, 3), 1, 'venta modificada: 1');
assert.strictEqual(copiasDelTicket({ printJobId: 'presupuesto:abc' }, 3), 1, 'presupuesto: 1');
assert.strictEqual(copiasDelTicket({ printJobId: 'xsale-auto:1' }, 3), 1, 'prefijo exacto, no «contiene»');

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
const { printTicket, imprimirCopias } = require('../src/print-pipeline');
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

  // print_temp: la imagen ya dibujada se manda N veces
  envios = 0;
  assert.strictEqual(await imprimirCopias(Buffer.from('png'), cfg, () => {}, 2), 2);
  assert.strictEqual(envios, 2, 'print_temp 2 copias = 2 envíos');
  envios = 0;
  await imprimirCopias(Buffer.from('png'), cfg, () => {}, 7.5);
  assert.strictEqual(envios, 1, 'copias raras: 1');

  // ── ④ el llamador: print_temp de main.js usa las copias (sin esto, la función sola no sirve) ──
  const fs = require('fs');
  const main = fs.readFileSync(path.join(__dirname, '..', 'main.js'), 'utf8');
  const ini = main.indexOf("wsConnection.on('print_temp'");
  assert.ok(ini > 0, 'no encuentro el handler print_temp');
  const bloque = main.slice(ini, main.indexOf('wsConnection.on(', ini + 10) > 0 ? main.indexOf('wsConnection.on(', ini + 10) : ini + 6000);
  assert.ok(/copiasDelTicket\(payload, store\.get\('ticketCopias'\)\)/.test(bloque), 'print_temp calcula las copias');
  assert.ok(/await imprimirCopias\(png, printerCfg, broadcastLog, copias\)/.test(bloque), 'print_temp imprime N copias');
  assert.ok(!/await printImage\(png, printerCfg, broadcastLog\)/.test(bloque), 'print_temp ya no imprime 1 sola vez');

  console.log('ticket-copias.smoke OK');
})().catch((e) => { console.error(e); process.exit(1); });
