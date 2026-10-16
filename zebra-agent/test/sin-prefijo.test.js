/**
 * [PEDIDO 45 · Cielo] «Ocultar el prefijo […]»: la etiqueta imprime «PINZA PARA PIERCING P47» en vez de
 * «[HERRAMIENTAS/-] PINZA PARA PIERCING P47». Apagada (por defecto) el ZPL es idéntico byte por byte.
 * Ejecutar: node test/sin-prefijo.test.js
 */
const assert = require('assert');
const { formatBatchLabels, resolveMode, nombreParaEtiqueta, qrLoteFilas } = require('../src/zpl-formatter');

let passed = 0;
const ok = (n, c) => { assert.ok(c, n); passed += 1; console.log('  ✓', n); };

const NOMBRE = '[HERRAMIENTAS/-] PINZA PARA PIERCING P47';
const item = (name = NOMBRE, qty = 4) => ({ name, sku: '25942379001', qty, prices: [{ label: 'P1', amount: 1000 }] });
const textos = (zpl) => (zpl.match(/\^FD[^\^]*/g) || []).map((s) => s.slice(3)).join(' | ');

console.log('sin-prefijo.test');

// ── la regla ─────────────────────────────────────────────────────────────────
ok('apagado: el nombre no cambia', nombreParaEtiqueta(NOMBRE, {}) === NOMBRE);
ok('apagado (sin texto): no cambia', nombreParaEtiqueta(NOMBRE, undefined) === NOMBRE);
ok('sinPrefijo «true» como string no cuenta', nombreParaEtiqueta(NOMBRE, { sinPrefijo: 'true' }) === NOMBRE);
ok('encendido: quita el bloque inicial', nombreParaEtiqueta(NOMBRE, { sinPrefijo: true }) === 'PINZA PARA PIERCING P47');
ok('[CAT] simple', nombreParaEtiqueta('[HERRAMIENTAS] PINZA P48', { sinPrefijo: true }) === 'PINZA P48');
ok('sólo el primer bloque', nombreParaEtiqueta('[A] [B] REMERA', { sinPrefijo: true }) === '[B] REMERA');
ok('sin prefijo: igual', nombreParaEtiqueta('REMERA LISA', { sinPrefijo: true }) === 'REMERA LISA');
ok('corchetes en el medio: igual', nombreParaEtiqueta('REMERA [XL] AZUL', { sinPrefijo: true }) === 'REMERA [XL] AZUL');
ok('«[» sin cerrar: igual', nombreParaEtiqueta('[ROTO REMERA', { sinPrefijo: true }) === '[ROTO REMERA');
ok('sólo prefijo: no deja la etiqueta vacía', nombreParaEtiqueta('[HERRAMIENTAS/-]', { sinPrefijo: true }) === '[HERRAMIENTAS/-]');

// ── QR (Modo Duplicado, 4 por fila — el caso de la foto) ─────────────────────
const dup = resolveMode('modo-duplicado');
const qr = (texto) => formatBatchLabels([item()], dup, { simbolo: 'qr', porEtiqueta: 2, texto });
const qrBase = qr({ mostrarNombre: true, mostrarPrecio: false });
ok('control QR: apagado = ZPL idéntico a no mandar la clave',
  qrBase === qr({ mostrarNombre: true, mostrarPrecio: false, sinPrefijo: false }));
ok('control QR: apagado lleva el prefijo', textos(qrBase).includes('[HERRAMIENTAS/-]'));
const qrOn = qr({ mostrarNombre: true, mostrarPrecio: false, sinPrefijo: true });
ok('QR encendido: ninguna celda lleva el prefijo', !textos(qrOn).includes('[HERRAMIENTAS'));
ok('QR encendido: las 4 celdas llevan el nombre', (textos(qrOn).match(/PINZA PARA PIERCING/g) || []).length === 4);
ok('QR encendido: el contenido del QR (SKU) no cambia', (qrOn.match(/\^FDMA,25942379001\^FS/g) || []).length === 4);

// vista previa = mismo camino (qrLoteFilas lo usa main.js para dibujar)
const filas = qrLoteFilas([item()], dup, { simbolo: 'qr', porEtiqueta: 2, texto: { sinPrefijo: true } });
ok('vista previa: sin prefijo también', filas.length > 0 && !filas.some((f) => f.zpl.includes('[HERRAMIENTAS')));

// ── barras ───────────────────────────────────────────────────────────────────
for (const k of ['simple-face', 'modo-duplicado']) {
  const m = resolveMode(k);
  const sinOps = formatBatchLabels([item(NOMBRE, 2)], m);
  ok(`control barras ${k}: apagado = idéntico a la llamada sin opciones`,
    sinOps === formatBatchLabels([item(NOMBRE, 2)], m, { texto: { sinPrefijo: false } }));
  const on = formatBatchLabels([item(NOMBRE, 2)], m, { texto: { sinPrefijo: true } });
  ok(`barras ${k}: sin prefijo`, !on.includes('[HERRAMIENTAS') && on.includes('PINZA PARA PIERCING'));
}

// el item original no se toca (lo usa también el resumen de impresión)
const original = item();
formatBatchLabels([original], dup, { texto: { sinPrefijo: true } });
ok('no muta el item de entrada', original.name === NOMBRE);

console.log(`\n${passed} passed`);
