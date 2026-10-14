/**
 * [PEDIDO 31 · coolsistema 2026-10-14] «cuando se selecciona imprimir sin precio y se guarda, imprime
 * con precio» + «para imprimir 2 en el modo duplicado, imprime cuatro etiquetas».
 * Ejecutar: node test/pedido31.test.js
 */
const assert = require('assert');
const { formatBatchLabels, resolveMode } = require('../src/zpl-formatter');
const { prepareItems } = require('../src/price-select');
const { armarZplVista } = require('../src/vista-zebra');

let passed = 0;
const ok = (n, c) => { assert.ok(c, n); passed += 1; console.log('  ✓', n); };
const filas = (z) => (z.match(/\^XA/g) || []).length;
const cuenta = (z, s) => z.split(s).length - 1;

const DUP = resolveMode('modo-duplicado');
const SIMPLE = resolveMode('simple-face');
const item = (sku, qty) => ({
  name: `PROD ${sku}`, sku, qty,
  prices: [{ priceTypeId: 1, label: 'PRECIO 1', amount: 100 }],
});

console.log('pedido31.test');

// ── 1) «Sin precio» guardado ────────────────────────────────────────────────
ok('guardado sin precio → ningún precio', prepareItems([item('A', 1)], [], {}, true)[0].prices.length === 0);
ok('control: nunca guardado → 1.er precio del servidor (como siempre)',
  prepareItems([item('A', 1)], [], { priceCount: 1 }, false)[0].prices.length === 1);
ok('control: con un nivel elegido sale ese precio',
  prepareItems([item('A', 1)], [{ id: 1, name: 'PRECIO 1' }], {}, true)[0].prices.length === 1);

const zSin = formatBatchLabels(prepareItems([item('A', 1)], [], {}, true), { ...SIMPLE, layout: { ...SIMPLE.layout, priceCount: 0 } });
ok('la etiqueta no lleva «$»', !zSin.includes('$'));

const vista = armarZplVista({ tipo: 'diseno', sku: 'X1' }, {
  ajustes: {}, modoEfectivo: SIMPLE, modoImpresion: SIMPLE, seleccion: [], seleccionGuardada: true, qrLayout: {},
});
ok('la vista previa tampoco lleva precio', !vista.zpl.includes('$'));
const vistaVieja = armarZplVista({ tipo: 'diseno', sku: 'X1' }, {
  ajustes: {}, modoEfectivo: SIMPLE, modoImpresion: SIMPLE, seleccion: [], seleccionGuardada: false, qrLayout: {},
});
ok('control: vista sin guardar → con precio (como antes)', vistaVieja.zpl.includes('$'));

// ── 2) Duplicado: cantidad = etiquetas ──────────────────────────────────────
const z2 = formatBatchLabels([item('A', 2)], DUP);
ok('2 etiquetas → 1 fila', filas(z2) === 1);
ok('… con las 2 etiquetas (izq + der)', cuenta(z2, '^BC') === 2);

const z3 = formatBatchLabels([item('A', 3)], DUP);
ok('3 etiquetas → 2 filas', filas(z3) === 2);
ok('… 3 códigos de barras en total (la derecha de la última vacía)', cuenta(z3, '^BC') === 3);

const zAB = formatBatchLabels([item('A', 1), item('B', 1)], DUP);
ok('A×1 + B×1 → 1 fila con A a la izquierda y B a la derecha',
  filas(zAB) === 1 && zAB.includes('PROD A') && zAB.includes('PROD B'));

const zS = formatBatchLabels([item('A', 2)], SIMPLE);
ok('control: Simple Face 2 → 2 etiquetas (sin cambio)', filas(zS) === 2);

console.log(`\n${passed} OK`);
