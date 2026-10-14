/**
 * [2026-10-14 usuario] «QR code 출력할 때 새 제품을 출력하기 시작할 때 제품 이름을 쓰는데 지금은
 *   1줄만 쓰고 있어. 그걸 4줄까지 출력해서 긴 이름도 모두 잘 출력하게 해 줘»
 * Apilado (2 por etiqueta): la celda donde empieza un producto lleva el nombre hasta en 4
 * renglones; las demás siguen con 1 (QR grande). Ejecutar: node test/qr-nombre-nuevo.test.js
 */
const assert = require('assert');
const { formatBatchLabels } = require('../src/zpl-formatter');

const MODE = { key: 'simple-face', width: 400, height: 200, layout: {} };
const LARGO = 'PANTALON CARGO GABARDINA ELASTIZADA CON BOLSILLOS LATERALES TALLE ESPECIAL';
const item = (name, sku, qty) => ({ name, sku, prices: [{ label: 'Minorista', amount: 8500 }], qty });

let passed = 0;
const ok = (n, c) => { assert.ok(c, n); passed += 1; console.log('  ✓', n); };

// Textos de cada celda: lo que va entre un ^BQN y el siguiente
const celdas = (zpl) => zpl.split('^BQN').slice(1);
const textos = (celda) => [...celda.matchAll(/\^A0N,\d+,\d+(?:\^FB[^^]*)?\^FD([^^]*)\^FS/g)].map((m) => m[1]);

console.log('qr-nombre-nuevo.test');

const z = formatBatchLabels([item(LARGO, 'SKU1', 3), item('REMERA LISA', 'SKU2', 1)], MODE, { simbolo: 'qr', porEtiqueta: 2 });
const c = celdas(z);
ok('4 celdas (3 + 1)', c.length === 4);

const primera = textos(c[0]);
ok('1.ª celda: nombre en 4 renglones + precio', primera.length === 5);
ok('1.ª celda: los renglones son el nombre en orden', LARGO.startsWith(primera.slice(0, 4).join(' ')));

// [2026-10-14] con «mostrarNombre» (por defecto) TODAS las celdas llevan el nombre hasta 4 renglones
ok('2.ª celda (mismo producto, descripción siempre): también 4 renglones + precio', textos(c[1]).length === 5);

// Descripción apagada: sólo la celda donde empieza el producto lleva el nombre
const sinNombre = celdas(formatBatchLabels([item(LARGO, 'SKU1', 3)], MODE, {
  simbolo: 'qr', porEtiqueta: 2, texto: { mostrarNombre: false },
}));
ok('descripción apagada: la celda nueva lleva el nombre en 4 renglones', textos(sinNombre[0]).length === 5);
ok('descripción apagada: las demás sólo el precio', textos(sinNombre[1]).length === 1);
ok('celda donde empieza el 2.º producto: también varios renglones si hace falta',
  textos(c[3])[0] === 'REMERA LISA');

const mod = (celda) => Number(celda.match(/^,2,(\d+)/)[1]);
ok('el QR de la celda con nombre largo se achica para dejar lugar', mod(sinNombre[0]) < mod(sinNombre[1]));
ok('★ nunca por debajo de módulo 3', mod(c[0]) >= 3);

// Control: un nombre corto en la celda nueva no cambia nada respecto de las otras
const corto = celdas(formatBatchLabels([item('REMERA', 'SKU3', 2)], MODE, { simbolo: 'qr', porEtiqueta: 2 }));
ok('control: nombre corto → 1 renglón y mismo QR en las dos celdas',
  textos(corto[0]).length === 2 && mod(corto[0]) === mod(corto[1]));

console.log(`\n${passed} OK`);
