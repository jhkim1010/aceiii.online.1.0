/**
 * [2026-10-14 usuario] Etiqueta de BARRAS: el nombre del producto hasta en 4 renglones; el código
 * baja (mismo alto) por debajo del nombre sin pisar los precios. Ejecutar: node test/barras-nombre-4.test.js
 */
const assert = require('assert');
const { formatBatchLabels, resolveMode } = require('../src/zpl-formatter');

let passed = 0;
const ok = (n, c) => { assert.ok(c, n); passed += 1; console.log('  ✓', n); };
const LARGO = 'PANTALON CARGO GABARDINA ELASTIZADA CON BOLSILLOS LATERALES TALLE ESPECIAL MUY LARGO EXTRA';
const item = (name, conPrecio = true) => ({
  name, sku: '2501', qty: 1, prices: conPrecio ? [{ label: 'P1', amount: 100 }] : [],
});
const renglones = (z) => Number((z.match(/\^FB\d+,(\d+),/) || [0, 1])[1]);
const barras = (z) => {
  const m = z.match(/\^FO\d+,(\d+)\^BY[^\n]*\n?[^]*?\^BC[NR],(\d+)/) || z.match(/\^FO\d+,(\d+)[^\n]*\^BC[NR],(\d+)/);

  return { y: Number(m[1]), alto: Number(m[2]) };
};

console.log('barras-nombre-4.test');
for (const k of ['simple-face', 'doble-face', 'modo-duplicado']) {
  const m = resolveMode(k);
  const corto = formatBatchLabels([item('REMERA')], m);
  const largo = formatBatchLabels([item(LARGO)], m);
  const b0 = barras(corto);
  const b1 = barras(largo);
  ok(`${k}: nombre corto → 1 renglón, código donde siempre (control)`, renglones(corto) === 1 && b0.y === m.layout.barcode.y);
  ok(`${k}: nombre largo → entre 2 y 4 renglones`, renglones(largo) >= 2 && renglones(largo) <= 4);
  ok(`${k}: el código baja por debajo del nombre`, b1.y >= m.layout.name.y + renglones(largo) * (m.layout.name.fontSize + 4));
  ok(`${k}: el código no queda más bajo que 30 dots`, b1.alto >= 30);
  ok(`${k}: el código termina antes de los precios`, b1.y + b1.alto <= m.height - 8 - (m.layout.price1.fontSize || 24));
}
const pol = formatBatchLabels([item(LARGO)], resolveMode('poliamida-vertical'));
ok('control: Poliamida vertical no cambia (sin ^FB)', !/\^FB/.test(pol));

// [CODEX] precios en posiciones fijas del diseño: el código no los pisa
{
  const base = resolveMode('simple-face');
  const manual = { ...base, layout: { ...base.layout, autoPrices: false } };
  const z = formatBatchLabels([item(LARGO)], manual);
  const b = barras(z);
  ok('precios manuales: el código termina antes del precio 1 del diseño', b.y + b.alto <= base.layout.price1.y);
}

console.log(`\n${passed} OK`);
