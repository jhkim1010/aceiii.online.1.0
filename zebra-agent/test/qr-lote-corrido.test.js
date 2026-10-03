/**
 * [2026-10-03 · usuario] Lote QR **de corrido** entre productos.
 * Ejecutar: node test/qr-lote-corrido.test.js
 *
 * Antes: cada producto empezaba fila nueva. Doble banda + 2 QR = 4 por fila;
 *   1×19 + 4×1  →  9 filas, 13 casilleros en blanco.
 * Ahora:            6 filas, 1 casillero en blanco.
 * Donde empieza otro producto: raya vertical a la izquierda (no en la 1ª celda de la fila)
 *   y la descripción SIEMPRE, aunque la pestaña QR la tenga apagada.
 */
const assert = require('assert');
const { formatBatchLabels, qrLoteFilas, filasDeLoteQrTotal, zplADibujo } = require('../src/zpl-formatter');

const DOBLE_BANDA = { key: 'duplicate', width: 800, halfWidth: 400, height: 200, duplicate: true, layout: {} };
const SIMPLE = { key: 'simple-face', width: 400, height: 200, layout: {} };
const it = (sku, qty) => ({ name: `PRODUCTO ${sku}`, sku, qty, prices: [{ label: 'Lista', amount: 1000 }] });
const LOTE = [it('A', 19), it('B', 1), it('C', 1), it('D', 1), it('E', 1)];
const OPC = { simbolo: 'qr', porEtiqueta: 2, texto: { mostrarNombre: false } }; // descripción APAGADA

const filas = (zpl) => (zpl.match(/\^XA/g) || []).length;
const qrs = (zpl) => (zpl.match(/\^BQN/g) || []).length;

// ① el caso del usuario
const z = formatBatchLabels(LOTE, DOBLE_BANDA, OPC);
assert.strictEqual(filas(z), 6, '6 filas (antes 9)');
assert.strictEqual(qrs(z), 23, '23 QR = 23 unidades, ni uno más');
assert.strictEqual(filasDeLoteQrTotal(LOTE, DOBLE_BANDA, OPC), 6, 'el recuento coincide con lo impreso');

// ② cada QR lleva el SKU de su producto, en orden: 19 A, después B C D E
const skus = [...z.matchAll(/\^FDMA,([^\^]+)\^FS/g)].map((m) => m[1]);
assert.deepStrictEqual(skus, [...Array(19).fill('A'), 'B', 'C', 'D', 'E']);

// ③ rayas: donde empieza B (fila 5, celda 4), C (fila 6 celda 1 → SIN raya), D, E
const f = qrLoteFilas(LOTE, DOBLE_BANDA, OPC);
const rayas = f.map((x) => (x.zpl.match(/\^GB3,/g) || []).length);
assert.deepStrictEqual(rayas, [0, 0, 0, 0, 1, 2], 'raya sólo donde cambia DENTRO de la fila');

// ④ descripción forzada sólo donde empieza un producto (pestaña QR la tiene apagada)
const nombres = z.match(/\^FDPRODUCTO /g) || [];
assert.ok(nombres.length >= 5, 'cada producto muestra su descripción al empezar');
assert.ok(!f[1].zpl.includes('^FDPRODUCTO'), 'una fila llena de A (no empieza nada) no fuerza descripción');

// ⑤ la vista previa ve la raya
const dib = zplADibujo(f[4].zpl);
assert.ok(dib.elementos.some((e) => e.tipo === 'linea' && e.alto === 200), 'la vista previa dibuja la raya');

// ⑥ CONTROL: un solo producto se imprime igual que antes (sin rayas, mismas filas)
const solo = formatBatchLabels([it('A', 9)], DOBLE_BANDA, OPC);
assert.strictEqual(filas(solo), 3);
assert.ok(!solo.includes('^GB'), 'un solo producto: sin rayas');

// ⑦ simple (1 por fila): nunca hay raya — cada fila es una celda
const s = formatBatchLabels(LOTE, SIMPLE, { simbolo: 'qr', porEtiqueta: 1 });
assert.strictEqual(filas(s), 23);
assert.ok(!s.includes('^GB'));

console.log('qr-lote-corrido OK');
