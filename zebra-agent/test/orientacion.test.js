/**
 * Poliamida vertical / horizontal (2026-10-07) — la persona elige; cada orientación con su diseño.
 * 실행: node test/orientacion.test.js
 */
const assert = require('assert');
const { modoEfectivo, guardarCustom, formatLabel, resolveMode } = require('../src/zpl-formatter');

let passed = 0;
function ok(name, cond) {
  assert.ok(cond, name);
  passed += 1;
  console.log('  ✓', name);
}

const poli = resolveMode('poliamida-vertical');
const simple = resolveMode('simple-face');
const item = { name: 'REMERA OVERSIZE NEGRA M', sku: '259423611017', barcodeType: 'CODE128', prices: [{ label: 'Lista', amount: 15999 }] };

// ── modo efectivo ──
ok('sin elegir nada: vertical (como siempre)', modoEfectivo(poli, {}).orientation === 'R');
const h = modoEfectivo(poli, { orientation: 'N' });
ok('horizontal: orientación N y el diseño horizontal', h.orientation === 'N' && h.layout === poli.layoutHorizontal);
ok('un modo no orientable ignora la orientación guardada', modoEfectivo(simple, { orientation: 'R' }).orientation === 'N');
ok('el diseño guardado de vertical (guardados viejos) no se mezcla con horizontal',
  modoEfectivo(poli, { orientation: 'N', layout: { name: { x: 999, y: 1, fontSize: 9 } } }).layout.name.x === poli.layoutHorizontal.name.x);
ok('el diseño horizontal guardado se aplica en horizontal',
  modoEfectivo(poli, { orientation: 'N', layoutN: { name: { x: 33, y: 1, fontSize: 9 } } }).layout.name.x === 33);
ok('densidad/velocidad (extra) siguen entrando', modoEfectivo(poli, {}, { darkness: 12 }).darkness === 12);

// ── guardar ──
let c = guardarCustom({ layout: { a: 1 } }, poli, { tipo: 'orientacion', orientation: 'N' });
ok('elegir horizontal no borra el diseño vertical', c.orientation === 'N' && c.layout.a === 1);
c = guardarCustom(c, poli, { tipo: 'diseno', width: 200, height: 400, layout: { b: 2 } });
ok('guardar en horizontal escribe layoutN, deja layout', c.layoutN.b === 2 && c.layout.a === 1);
c = guardarCustom(c, poli, { tipo: 'reset' });
ok('restablecer en horizontal borra sólo el horizontal', !c.layoutN && c.layout.a === 1 && c.orientation === 'N');
c = guardarCustom(c, poli, { tipo: 'orientacion', orientation: 'R' });
ok('volver a vertical', !c.orientation && modoEfectivo(poli, c).orientation === 'R');
ok('orientación en un modo no orientable: no cambia nada',
  JSON.stringify(guardarCustom({ layout: { a: 1 } }, simple, { tipo: 'orientacion', orientation: 'N' })) === JSON.stringify({ layout: { a: 1 } }));

// ── la etiqueta ──
const zV = formatLabel(item, modoEfectivo(poli, {}));
const zH = formatLabel(item, modoEfectivo(poli, { orientation: 'N' }));
ok('vertical: todo girado', zV.includes('^A0R') && zV.includes('^BCR') && !zV.includes('^A0N'));
ok('horizontal: todo derecho', zH.includes('^A0N') && zH.includes('^BCN') && !zH.includes('^A0R'));
ok('horizontal: el nombre se parte en hasta 3 renglones dentro de 200 (^FB180,3)', /\^FO10,12\^A0N,22,22\^FB180,3,0,L,0\^FDREMERA/.test(zH));
ok('vertical: el nombre sigue en un renglón (sin ^FB)', !zV.includes('^FB'));
ok('[Vista Zebra] vertical: el código ya no pisa el nivel de precio (x 80)', zV.includes('^FO80,10^BY'));
const by = Number(/\^BY(\d+)/.exec(zH)[1]);
ok(`horizontal: el código se achica para entrar (^BY${by})`, by >= 1 && by < 3);
ok('otros modos no cambian (sin ^FB)', !formatLabel(item, modoEfectivo(simple, {})).includes('^FB'));

console.log(`\n${passed} ok`);
