/**
 * [v1.0.29] Rollo doble banda · posición del QR · avisos · dibujo para la vista previa.
 * Ejecutar: node test/qr-v1029.test.js
 *
 * ★★ Usuario (2026-10-02): «doble banda + 2 QR en 1 etiqueta → en una fila tienen que verse
 *   4 QR; el usuario corta cada etiqueta al medio con tijera». Antes salían 2 (y con «1 QR»
 *   uno solo, cruzando las dos etiquetas).
 */
const assert = require('assert');
const {
  formatBatchLabels, formatQrLabelConAvisos, zplADibujo, qrLotePreview, filasDeLoteQr, LABEL_MODES,
} = require('../src/zpl-formatter');

const DOBLE_BANDA = LABEL_MODES['modo-duplicado']; // 100 × 25, 2 etiquetas a lo ancho
const SIMPLE = LABEL_MODES['simple-face'];
const ITEM = { name: 'REMERA', sku: 'AB-1', prices: [{ label: 'Lista', amount: 1000 }], qty: 1 };

const qrsDe = (zpl) => (zpl.match(/\^BQN/g) || []).length;
const filas = (zpl) => zpl.split('^XZ').filter((x) => x.includes('^XA')).map((x) => `${x}^XZ`);
const xsQr = (zpl) => [...zpl.matchAll(/\^FO(\d+),\d+\^BQN/g)].map((m) => Number(m[1]));

let ok = 0;
const t = (nombre, fn) => { fn(); ok++; console.log('  ✓', nombre); };

// sanity: el modo existe y es de 2 a lo ancho — si no, todo lo demás mide otra cosa
assert.strictEqual(DOBLE_BANDA.duplicate, true);
assert.strictEqual(DOBLE_BANDA.halfWidth, 400);

t('doble banda + 2 QR en 1 etiqueta → 4 QR por fila, ^PW = 100 mm', () => {
  const zpl = formatBatchLabels([{ ...ITEM, qty: 4 }], DOBLE_BANDA, { simbolo: 'qr', porEtiqueta: 2 });
  const fs = filas(zpl);
  assert.strictEqual(fs.length, 1);
  assert.strictEqual(qrsDe(fs[0]), 4);
  assert.match(fs[0], /\^PW800/);
  // una por cuarto: 0–200, 200–400, 400–600, 600–800
  const xs = xsQr(fs[0]);
  assert.deepStrictEqual(xs.map((x) => Math.floor(x / 200)), [0, 1, 2, 3]);
});

t('doble banda + 1 QR por etiqueta → 2 QR por fila, uno en cada etiqueta', () => {
  const zpl = formatBatchLabels([{ ...ITEM, qty: 2 }], DOBLE_BANDA, { simbolo: 'qr', porEtiqueta: 1 });
  const fs = filas(zpl);
  assert.strictEqual(fs.length, 1);
  assert.strictEqual(qrsDe(fs[0]), 2);
  const xs = xsQr(fs[0]);
  assert.ok(xs[0] < 400 && xs[1] >= 400, `QR fuera de su etiqueta: ${xs}`);
});

t('cantidad = unidades: 9 en doble banda × 2 → 2 filas de 4 + 1 fila con 1', () => {
  const zpl = formatBatchLabels([{ ...ITEM, qty: 9 }], DOBLE_BANDA, { simbolo: 'qr', porEtiqueta: 2 });
  const fs = filas(zpl);
  assert.deepStrictEqual(fs.map(qrsDe), [4, 4, 1]);
  // la fila incompleta mantiene el ancho (los cortes caen en el mismo lugar)
  assert.match(fs[2], /\^PW800/);
  assert.strictEqual(filasDeLoteQr(9, DOBLE_BANDA, { porEtiqueta: 2 }), 3);
});

t('control: rollo simple sigue igual (1 y 2 por etiqueta)', () => {
  const uno = filas(formatBatchLabels([{ ...ITEM, qty: 3 }], SIMPLE, { simbolo: 'qr', porEtiqueta: 1 }));
  assert.deepStrictEqual(uno.map(qrsDe), [1, 1, 1]);
  assert.match(uno[0], /\^PW400/);
  const dos = filas(formatBatchLabels([{ ...ITEM, qty: 3 }], SIMPLE, { simbolo: 'qr', porEtiqueta: 2 }));
  assert.deepStrictEqual(dos.map(qrsDe), [2, 1]);
  assert.strictEqual(filasDeLoteQr(3, SIMPLE, { porEtiqueta: 2 }), 2);
});

t('posición del QR (mm) se respeta en cada celda', () => {
  const zpl = formatBatchLabels([{ ...ITEM, qty: 4 }], DOBLE_BANDA, {
    simbolo: 'qr', porEtiqueta: 2, texto: { qrX: 2, qrY: 1.5 },
  });
  // 2 mm = 16 dots, 1.5 mm = 12 dots, en cada cuarto
  assert.deepStrictEqual([...zpl.matchAll(/\^FO(\d+),(\d+)\^BQN/g)].map((m) => [Number(m[1]), Number(m[2])]),
    [[16, 12], [216, 12], [416, 12], [616, 12]]);
});

t('posición vacía = automático (control: no aparece 0,0)', () => {
  const zpl = formatBatchLabels([{ ...ITEM, qty: 1 }], SIMPLE, { simbolo: 'qr', porEtiqueta: 1, texto: { qrX: '', qrY: null } });
  assert.doesNotMatch(zpl, /\^FO0,0\^BQN/);
});

t('aviso: nombre largo en media etiqueta se corta; nombre corto no avisa', () => {
  const largo = formatQrLabelConAvisos({
    contenido: 'AB-1', name: 'CAMPERA PUFFER OVERSIZE CAPUCHA DESMONTABLE', price: 1, priceLabel: 'L',
    layout: { widthMm: 50, heightMm: 25, mode: 'doble', bandas: 2 },
  });
  assert.strictEqual(largo.avisos.length, 1, 'un aviso por etiqueta, no uno por celda');
  assert.ok(largo.avisos[0].mostrado.length < largo.avisos[0].total);
  const corto = formatQrLabelConAvisos({
    contenido: 'AB-1', name: 'MEDIAS', price: 1, priceLabel: 'L',
    layout: { widthMm: 50, heightMm: 25, mode: 'doble' },
  });
  assert.strictEqual(corto.avisos.length, 0);
});

t('dibujo: se lee del mismo ZPL (ancho, alto, 4 QR con su lado real, textos)', () => {
  const r = qrLotePreview({ ...ITEM, qty: 1 }, DOBLE_BANDA, { porEtiqueta: 2 });
  assert.strictEqual(r.porFila, 4);
  assert.strictEqual(r.dibujo.ancho, 800);
  assert.strictEqual(r.dibujo.alto, 200);
  const qrs = r.dibujo.elementos.filter((e) => e.tipo === 'qr');
  assert.strictEqual(qrs.length, 4);
  assert.ok(qrs.every((q) => q.lado === q.modulos * q.modulo && q.lado > 0));
  assert.ok(r.dibujo.elementos.some((e) => e.tipo === 'texto' && e.texto === 'REMERA'));
});

console.log(`\n${ok} ok`);
