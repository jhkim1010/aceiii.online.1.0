/**
 * [2026-10-02] QR 라벨 글자 옵션 — 가격/제품명 출력 여부와 시작 위치(mm).
 * 실행: node test/qr-texto.test.js
 */
const assert = require('assert');
const { formatQrLabel, formatBatchLabels } = require('../src/zpl-formatter');

let passed = 0;
function ok(name, cond) {
  assert.ok(cond, name);
  passed += 1;
  console.log('  ✓', name);
}

const base = { contenido: 'SKU-123', name: 'REMERA NEGRA', price: 12999, priceLabel: 'Precio' };
const fo = (zpl, txt) => {
  const m = zpl.split('\n').find((l) => l.includes(`^FD${txt}`));

  return m ? m.match(/\^FO(\d+),(\d+)/).slice(1).map(Number) : null;
};

for (const mode of ['simple', 'doble']) {
  console.log(`\n[${mode}]`);
  const def = formatQrLabel({ ...base, layout: { mode } });
  ok(`${mode}: por defecto nombre y precio`, def.includes('^FDREMERA NEGRA') && def.includes('^FDPrecio: $12.999'));

  const sinPrecio = formatQrLabel({ ...base, layout: { mode, mostrarPrecio: false } });
  ok(`${mode}: sin precio → no hay precio, sí nombre`, !sinPrecio.includes('$12.999') && sinPrecio.includes('REMERA'));

  const sinNombre = formatQrLabel({ ...base, layout: { mode, mostrarNombre: false } });
  ok(`${mode}: sin nombre → no hay nombre, sí precio`, !sinNombre.includes('REMERA') && sinNombre.includes('$12.999'));

  const nada = formatQrLabel({ ...base, layout: { mode, mostrarNombre: false, mostrarPrecio: false } });
  ok(`${mode}: sin nada → sólo QR`, !nada.includes('REMERA') && !nada.includes('$12.999') && nada.includes('^BQN'));

  // posición: 5 mm, 12 mm → 40, 96 dots (en doble, también en la segunda celda desplazada)
  const pos = formatQrLabel({ ...base, layout: { mode, precioX: 5, precioY: 12 } });
  ok(`${mode}: precio empieza donde se pidió (5mm,12mm = 40,96)`, JSON.stringify(fo(pos, 'Precio')) === '[40,96]');
  if (mode === 'doble') {
    const lineas = pos.split('\n').filter((l) => l.includes('^FDPrecio'));
    ok('doble: la segunda celda va desplazada media etiqueta (200 dots)', lineas[1].startsWith('^FO240,96'));
  }

  // sin posición: el precio va debajo del nombre (lo de siempre)
  const [, yN] = fo(def, 'REMERA');
  const [, yP] = fo(def, 'Precio');
  ok(`${mode}: automático → precio debajo del nombre`, yP > yN);

  // sólo precio en automático: ocupa el lugar del nombre
  const [, ySolo] = fo(sinNombre, 'Precio');
  ok(`${mode}: sin nombre, el precio sube a la primera línea`, ySolo === yN);
}

// doble: sin texto, el QR crece (el alto que ocupaban los renglones vuelve al QR)
const mod = (z) => Number(z.match(/\^BQN,2,(\d+)/)[1]);
ok(
  'doble: sin renglones el módulo del QR no baja (y suele subir)',
  mod(formatQrLabel({ ...base, layout: { mode: 'doble', mostrarNombre: false, mostrarPrecio: false } })) >=
    mod(formatQrLabel({ ...base, layout: { mode: 'doble' } })),
);

// el lote («por cantidad») usa el mismo ajuste
const lote = formatBatchLabels(
  [{ sku: 'A1', name: 'CAMPERA', prices: [{ label: 'Precio', amount: 5000 }], qty: 1 }],
  { width: 400, height: 200 },
  { simbolo: 'qr', porEtiqueta: 1, texto: { mostrarPrecio: false } },
);
ok('lote QR respeta «sin precio»', lote.includes('CAMPERA') && !lote.includes('$5.000'));
const loteDef = formatBatchLabels(
  [{ sku: 'A1', name: 'CAMPERA', prices: [{ label: 'Precio', amount: 5000 }], qty: 1 }],
  { width: 400, height: 200 },
  { simbolo: 'qr', porEtiqueta: 1 },
);
ok('lote QR sin ajuste → como siempre', loteDef.includes('$5.000'));

console.log(`\n${passed} checks passed ✅`);
