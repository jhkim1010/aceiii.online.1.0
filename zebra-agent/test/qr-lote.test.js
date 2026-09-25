/**
 * Imprimir por cantidad con QR en vez de código de barras.
 * Ejecutar: node test/qr-lote.test.js
 *
 * ═══════════════════════════════════════════════════════════════════════════════
 * ★★★ [2026-09-25 사용자 요구]
 *   「각 아이템을 갯수대로 바코드 출력하는 부분에서 바코드 대신 QR code 출력으로
 *    선택해서 출력할 수 있게 해줘」 +「티켓 하나당 1개 / 2개를 선택」
 *
 * ★★ Lo que va DENTRO del QR es el **SKU**, decisión del usuario:
 *   「A 로 해야 바코드 리더기로 사용하겠지」. O sea: lo lee el lector de la tienda,
 *   igual que el código de barras de hoy, sólo que en otro símbolo.
 *   El **enlace profundo** sigue viviendo en la tercera pestaña (QR pendientes) —
 *   ése lo escanea un cliente con el teléfono. Son dos usos distintos y este archivo
 *   fija que **no se mezclen**: si alguien hiciera que esta pantalla mande una URL,
 *   el lector de la tienda dejaría de reconocer sus propias etiquetas.
 *
 * ★ Y la cantidad es de **unidades**, no de etiquetas. Con 2 por etiqueta, 9 unidades
 *   son 4 etiquetas dobles + 1 simple. Redondear para arriba deja un adhesivo de más
 *   dando vueltas, que en una etiqueta de precio es un problema, no un sobrante.
 * ═══════════════════════════════════════════════════════════════════════════════
 */
const assert = require('assert');
const { formatBatchLabels, qrModuleCount, utf8Len } = require('../src/zpl-formatter');

const MODE = { key: 'simple-face', width: 400, height: 200, layout: {} };
const SKU = '2515014-V';
const ITEM = {
  name: '[VESTIDO] MICROFIBRA PUNTILLAS',
  sku: SKU,
  prices: [{ priceTypeId: 1, label: 'Minorista', amount: 8500 }],
  qty: 1,
};

let passed = 0;
function ok(name, cond) {
  assert.ok(cond, name);
  passed += 1;
  console.log('  ✓', name);
}

const cuenta = (zpl, re) => (zpl.match(re) || []).length;
const etiquetas = (zpl) => cuenta(zpl, /\^XA/g);
const qrs = (zpl) => cuenta(zpl, /\^BQN/g);

console.log('qr-lote.test');

// ── ⓪ Control: sin opciones nada cambia ────────────────────────────────────
// ★ Va primero. Sin esto, «el QR sale» se cumpliría aunque la ruta de barras
//   estuviera rota, y romperla es peor que no tener la función nueva.
const barras = formatBatchLabels([{ ...ITEM, qty: 3 }], MODE);
ok('⓪ control — sin opciones sigue siendo código de barras, 3 etiquetas',
  qrs(barras) === 0 && /\^BC/.test(barras) && etiquetas(barras) === 3);

const barras2 = formatBatchLabels([{ ...ITEM, qty: 3 }], MODE, { simbolo: 'barras' });
ok('⓪ control — pedir barras explícitamente da lo mismo', barras2 === barras);

// ── A) El QR lleva el SKU, no una URL ──────────────────────────────────────
const qr1 = formatBatchLabels([{ ...ITEM, qty: 2 }], MODE, { simbolo: 'qr', porEtiqueta: 1 });

ok('A: ★★ el QR codifica el SKU', qr1.includes(`^FDMA,${SKU}^FS`));
ok('A: ★★★ y NO una URL — esta pantalla es para el lector de la tienda',
  !/\^FDMA,[^\n]*https?:/.test(qr1) && !/\/m\/stock/.test(qr1));
ok('A: ya no hay código de barras cuando se elige QR',
  !/\^BC/.test(qr1) && qrs(qr1) === 2);

// ── B) 1 por etiqueta: unidades = etiquetas ────────────────────────────────
for (const qty of [1, 2, 5]) {
  const z = formatBatchLabels([{ ...ITEM, qty }], MODE, { simbolo: 'qr', porEtiqueta: 1 });
  ok(`B: 1 por etiqueta · ${qty} unidades → ${qty} etiquetas, ${qty} QR`,
    etiquetas(z) === qty && qrs(z) === qty);
  ok(`B: ${qty} unidades · ancho de la etiqueta intacto (^PW400)`,
    cuenta(z, /\^PW400/g) === qty && !/\^PW800/.test(z));
}

// ── C) 2 por etiqueta: la cuenta que importa ───────────────────────────────
// ★★ El caso que se rompe solo: el impar. 9 unidades NO son 5 etiquetas dobles.
const casos = [
  { qty: 1, etiq: 1, qr: 1 },
  { qty: 2, etiq: 1, qr: 2 },
  { qty: 3, etiq: 2, qr: 3 },
  { qty: 6, etiq: 3, qr: 6 },
  { qty: 9, etiq: 5, qr: 9 },
];
for (const c of casos) {
  const z = formatBatchLabels([{ ...ITEM, qty: c.qty }], MODE, { simbolo: 'qr', porEtiqueta: 2 });
  ok(`C: 2 por etiqueta · ${c.qty} unidades → ${c.etiq} etiqueta(s) y exactamente ${c.qr} QR`,
    etiquetas(z) === c.etiq && qrs(z) === c.qr);
}

// ★★★ Lo que el redondeo se llevaría puesto: nunca se imprime un QR de más.
//   (Un `ceil` daría 10 QR para 9 unidades — un adhesivo suelto con un precio.)
const impar = formatBatchLabels([{ ...ITEM, qty: 9 }], MODE, { simbolo: 'qr', porEtiqueta: 2 });
ok('C: ★★★ 9 unidades imprimen 9 QR, ni uno más', qrs(impar) === 9);

// ★ Y la última etiqueta usa la MISMA geometría (media celda), para que el corte
//   caiga donde la mano ya aprendió.
const bloquesImpar = impar.split('^XA').filter(Boolean);
const ultima = bloquesImpar[bloquesImpar.length - 1];
ok('C: la etiqueta impar final lleva 1 QR en la misma media celda',
  (ultima.match(/\^BQN/g) || []).length === 1 && /\^PW400/.test(ultima));

const modulosSku = qrModuleCount(utf8Len(SKU));
const moduloImpar = Number(ultima.match(/\^BQN,2,(\d+)/)[1]);
const primera = bloquesImpar[0];
ok('C: y con el mismo tamaño de QR que las dobles',
  moduloImpar === Number(primera.match(/\^BQN,2,(\d+)/)[1]));

// ★★★ «La misma geometría» se mide por la POSICIÓN, no por «hay un QR».
//   Un mutante que armara la última con el diseño `simple` (QR a la izquierda,
//   texto a la derecha) también daba 1 QR, ^PW400 y el mismo módulo — sobrevivía.
//   Lo que cambia es **dónde cae**: apilado va centrado en la media celda (x≈37),
//   `simple` lo pega al margen (x=10). Y de esa x depende que el corte quede en el
//   mismo lugar que en todas las otras etiquetas del lote.
const xDe = (bloque) => Number(bloque.match(/\^FO(\d+),/)[1]);
ok(`C: ★★★ el QR de la impar cae donde el primero de las dobles (x=${xDe(ultima)})`,
  xDe(ultima) === xDe(primera));
ok('C: ★★ y está centrado en la media celda, no pegado al margen',
  xDe(ultima) > 10);

// ★ El texto también: apilado va DEBAJO del QR, no al costado.
const yTextoUltima = Number(ultima.match(/\^FO\d+,(\d+)\^A0N/)[1]);
ok('C: ★★ en la impar el texto va debajo del QR (apilado), no al costado',
  yTextoUltima > 10 + modulosSku * moduloImpar);

// ── D) El SKU corto hace un QR cómodo — medido, no supuesto ────────────────
ok(`D: SKU «${SKU}» = ${modulosSku} módulos (vs 33 del enlace profundo)`,
  modulosSku < 33);
ok(`D: módulo ${moduloImpar} dot ≥ mínimo legible 2 dot`, moduloImpar >= 2);

// ── E) Varios productos en un lote ─────────────────────────────────────────
const lote = formatBatchLabels(
  [
    { ...ITEM, qty: 3 },
    { ...ITEM, sku: '258705', name: '[TOP] TUL VOLADO', qty: 2 },
  ],
  MODE,
  { simbolo: 'qr', porEtiqueta: 2 },
);
ok('E: dos productos · 3+2 unidades → 2+1 etiquetas y 5 QR',
  etiquetas(lote) === 3 && qrs(lote) === 5);
ok('E: cada producto lleva su propio SKU',
  lote.includes(`^FDMA,${SKU}^FS`) && lote.includes('^FDMA,258705^FS'));

// ── F) El precio y el nombre siguen saliendo ───────────────────────────────
ok('F: el nombre y el precio del nivel elegido salen en la etiqueta',
  /\^FD\[VESTIDO\]/.test(qr1) && /Minorista: /.test(qr1));

// ── G) Sin precios no se cae ───────────────────────────────────────────────
const sinPrecio = formatBatchLabels(
  [{ name: 'X', sku: 'S1', prices: [], qty: 1 }],
  MODE,
  { simbolo: 'qr', porEtiqueta: 2 },
);
ok('G: un producto sin precios se imprime igual', /\^XA/.test(sinPrecio) && sinPrecio.includes('^FDMA,S1^FS'));

console.log(`\n${passed} checks passed ✅`);
