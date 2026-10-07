/**
 * formatTestLabel — «Imprimir test» sigue el modo elegido (2026-10-07).
 * 실행: node test/test-label.test.js
 *
 *  - Modo Duplicado (doble banda): ^PW = ancho del modo y la prueba en las DOS etiquetas
 *  - los demás modos: el ZPL de antes, con el código achicado a su etiqueta
 */
const assert = require('assert');
const { formatTestLabel, resolveMode } = require('../src/zpl-formatter');

let passed = 0;
function ok(name, cond) {
  assert.ok(cond, name);
  passed += 1;
  console.log('  ✓', name);
}

console.log('formatTestLabel — prueba según el modo\n');

// el ZPL fijo que imprimía la prueba antes del cambio (main.js printTest)
const ANTES = (d, v) =>
  [
    d,
    '^XA',
    '^PW400',
    '^LL200',
    '^CI28',
    v,
    '^FO10,5^A0N,22,22^FDVENTAGO ZEBRA TEST^FS',
    '^FO10,30^BY3^BCN,50,Y,N,N^FD1234567890^FS',
    '^FO10,100^A0N,28,28^FD$0.00^FS',
    `^FO10,135^A0N,16,16^FDD:${d ? 15 : 'auto'} V:${v ? 4 : 'auto'}^FS`,
    '^XZ',
  ]
    .filter(Boolean)
    .join('\n');

// ── doble banda ──
const dup = { ...resolveMode('modo-duplicado') };
const zDup = formatTestLabel(dup, {});
ok('doble banda: ^PW800 (las dos etiquetas)', zDup.includes('^PW800') && !zDup.includes('^PW400'));
ok(
  'doble banda: la prueba sale dos veces',
  zDup.split('VENTAGO ZEBRA TEST').length - 1 === 2 && zDup.split('^FD1234567890').length - 1 === 2,
);
ok('doble banda: la derecha empieza en la mitad (x = 400 + 10)', zDup.includes('^FO410,5^A0N,22,22^FDVENTAGO ZEBRA TEST'));
ok('doble banda: el código de barras derecho también corrido', /\^FO410,30\^BY\d\^BCN/.test(zDup));
ok('doble banda: cada mitad dice cuál es', zDup.includes('IZQ · Modo Duplicado') && zDup.includes('DER · Modo Duplicado'));
ok('doble banda: un solo ^XA/^XZ (una etiqueta física)', zDup.split('^XA').length === 2 && zDup.split('^XZ').length === 2);

// [codex 041] cada código entra en su mitad (como renderCopy): x + módulos × ^BY ≤ mitad
const { code128Modules } = require('../src/zpl-formatter');
const by = Number(/\^BY(\d+)/.exec(zDup)[1]);
ok(
  `doble banda: el código entra en su mitad (^BY${by} → ${10 + code128Modules('1234567890') * by} ≤ 400)`,
  10 + code128Modules('1234567890') * by <= dup.halfWidth,
);
ok('doble banda: ^LL del modo', zDup.includes(`^LL${dup.height}`));
ok('doble banda: alto personalizado', formatTestLabel({ ...dup, height: 240 }, {}).includes('^LL240'));

// ancho personalizado del modo (getEffectiveMode recalcula halfWidth)
const zCustom = formatTestLabel({ ...dup, width: 832, halfWidth: 416 }, {});
ok('ancho personalizado: ^PW832 y la derecha en x = 426', zCustom.includes('^PW832') && zCustom.includes('^FO426,5'));

// ── los demás modos: igual que antes salvo el código, que ahora entra en la etiqueta ──
const ANTES_BY2 = ANTES(null, null).replace('^BY3', '^BY2');
for (const key of ['simple-face', 'doble-face']) {
  const z = formatTestLabel(resolveMode(key), {});
  ok(`${key}: el ZPL de antes con ^BY2`, z === ANTES_BY2);
  const byK = Number(/\^BY(\d+)/.exec(z)[1]);
  ok(`${key}: el código entra en 400 dots (^BY${byK})`, 10 + code128Modules('1234567890') * byK <= 400);
}
// [codex 048] un modo NO orientable con ancho chico personalizado sigue con la prueba de siempre
ok('simple-face angosta (300): no usa la prueba de Poliamida', !formatTestLabel({ ...resolveMode('simple-face'), width: 300 }, {}).includes('HORIZONTAL'));
// [2026-10-07] poliamida (25×50): la prueba sigue la orientación elegida — ya no la de 50×25 cortada
const { modoEfectivo } = require('../src/zpl-formatter');
const poli = resolveMode('poliamida-vertical');
const zV = formatTestLabel(modoEfectivo(poli, {}), {});
ok('poliamida vertical: ^PW200 ^LL400, texto y código girados', zV.includes('^PW200') && zV.includes('^LL400') && zV.includes('^A0R') && /\^BCR/.test(zV) && !zV.includes('^A0N'));
const byV = Number(/\^BY(\d+)/.exec(zV)[1]);
ok(`poliamida vertical: el código (^BY${byV}) entra a lo largo de los 400`, 10 + code128Modules('1234567890') * byV <= 400 && byV >= 2);
const zH = formatTestLabel(modoEfectivo(poli, { orientation: 'N' }), {});
const byH = Number(/\^BY(\d+)/.exec(zH)[1]);
ok('poliamida horizontal: derecho, en 200 de ancho', zH.includes('^PW200') && zH.includes('^A0N') && /\^BCN/.test(zH) && !zH.includes('^A0R'));
ok(`poliamida horizontal: código corto entero y legible (^BY${byH})`, zH.includes('^FD1234^FS') && 10 + code128Modules('1234') * byH <= 190 && byH >= 2);
ok('poliamida horizontal: el título se parte en el ancho (^FB) — antes salía «…TES»', /\^FB180,2/.test(zH));
// una cara con ancho personalizado mayor: la prueba sigue en ^PW400, así que el código también
ok('una cara ancha: el código sigue ajustado a 400', formatTestLabel({ ...resolveMode('simple-face'), width: 832 }, {}) === ANTES_BY2);
// sin modo (por si acaso): como una cara
ok('sin modo: como una cara', formatTestLabel(null, {}) === ANTES_BY2);

// densidad y velocidad siguen entrando
const conAjustes = formatTestLabel(resolveMode('simple-face'), { darkness: 15, speed: 4 });
ok('densidad/velocidad: ~SD y ^PR presentes', /~SD15/.test(conAjustes) && /\^PR4/.test(conAjustes));
ok('densidad/velocidad en doble banda', /~SD15/.test(formatTestLabel(dup, { darkness: 15, speed: 4 })));

console.log(`\n${passed} ok`);
