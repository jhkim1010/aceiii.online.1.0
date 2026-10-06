/**
 * [PEDIDO 10] «Diseño del texto» está cableado sin abrir un camino de impresión nuevo.
 * Ejecutar: node test/qr-diseno-cableado.smoke.js
 *
 *  ★ Imprimir lee lo GUARDADO (qrLayout); la vista previa puede leer lo que se está moviendo.
 *  ★ El editor (arrastrar, flechas, guardar) NO imprime — regla «nunca imprimir de más».
 *  ★ Cada comprobación se corre también contra un mutante para ver que de verdad mira algo.
 */
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const sinComentarios = (s) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/[^\n]*/g, '$1');
const leer = (...p) => fs.readFileSync(path.join(__dirname, '..', ...p), 'utf8');
const MAIN = sinComentarios(leer('main.js'));
const UI = sinComentarios(leer('renderer', 'index.html'));

let passed = 0;
function ok(name, cond) {
  assert.ok(cond, name);
  passed += 1;
  console.log('  ✓', name);
}

const bloque = (src, desde, hasta) => {
  const i = src.indexOf(desde);
  const j = src.indexOf(hasta, i + desde.length);

  return i >= 0 && j > i ? src.slice(i, j) : '';
};

// 1) imprimir el lote usa lo guardado
const imprimirMain = (src) => bloque(src, "ipcMain.handle('print:labels'", 'ipcMain.handle(');
const usaGuardado = (src) => /texto:\s*store\.get\('qrLayout'\)/.test(imprimirMain(src)) && !/textoPrevia/.test(imprimirMain(src));
ok('print:labels toma el texto de lo guardado (no de textoPrevia)', usaGuardado(MAIN));
ok('  mutante: si imprimir leyera textoPrevia, se nota',
  !usaGuardado(MAIN.replace("ipcMain.handle('print:labels'", "ipcMain.handle('print:labels' /*textoPrevia*/ ; textoPrevia")));

// 2) la vista previa del lote acepta textoPrevia
const previa = bloque(MAIN, "ipcMain.handle('qr:previewLote'", 'ipcMain.handle(');
ok('qr:previewLote usa textoPrevia para la vista previa', /opciones\.textoPrevia/.test(previa));

// 3) imprimir espera el guardado pendiente
const imprimirUi = (src) => bloque(src, 'async function imprimirLote(', 'const items = [];');
ok('imprimirLote espera dtGuardarPendiente() antes de armar la lista', /await dtGuardarPendiente\(\)/.test(imprimirUi(UI)));
ok('  mutante: sin la espera, se nota', !/await dtGuardarPendiente\(\)/.test(imprimirUi(UI.replace('await dtGuardarPendiente()', 'dtGuardarPendiente()'))));

// 4) el editor no imprime
const editor = (src) => bloque(src, 'var dtDiseno = null;', 'var qrPvIdx = 0;');
const imprime = (b) => /printLabels|qrPrint|imprimirLote\(|print:labels|qr:print/.test(b);
ok('el bloque del editor existe', editor(UI).length > 2000);
ok('el editor no llama a ninguna impresión', !imprime(editor(UI)));
ok('  mutante: una llamada a imprimir dentro del editor se detecta',
  imprime(editor(UI.replace('function dtGuardarPendiente()', 'function dtGuardarPendiente() { api.printLabels([], {}); }'))));

// 5) la pestaña QR ya no depende del botón
ok('botón «Guardar configuración» oculto', /display:none;">\s*<button class="btn btn-primary" id="qr-save-layout">/.test(UI));
ok('la pestaña QR guarda sola al cambiar', /qrGuardarPronto\(\)/.test(UI) && /setConfig\('qrLayout'/.test(bloque(UI, 'function qrGuardarPronto', "$('#qr-bandas').addEventListener")));
ok('la pestaña QR conserva tamaño/alineación (qrReadLayout los incluye)', /\.\.\.\(qrTextoExtra \|\| \{\}\)/.test(bloque(UI, 'function qrReadLayout', 'function optMm')));

// 6) [codex] un solo flujo de impresión; imprimir vacía AMBOS guardados; la pestaña QR no pisa tamaño/alineación
const lock = (src) => /if \(printing \|\| flujoImprimir\) return;\s*flujoImprimir = true;/.test(src);
ok('un segundo clic no abre otro flujo de impresión (lock antes del primer await)', lock(UI));
ok('  mutante: sin el lock, se nota', !lock(UI.replace('flujoImprimir = true;', '')));
const vacia = (src) => /if \(qrGuardarTimer\) qrGuardarYa\(\);/.test(bloque(src, 'async function dtGuardarPendiente', 'var dtGuardadoOk'));
ok('imprimir también vacía el guardado pendiente de la pestaña QR', vacia(UI));
ok('  mutante: sin eso, se nota', !vacia(UI.replace('if (qrGuardarTimer) qrGuardarYa();', '')));
ok('si el guardado falló, no imprime', /if \(!\(await dtGuardarPendiente\(\)\)\)/.test(UI));
ok('la pestaña QR no manda tamaño/alineación', /const \{ nombreFs, precioFs, nombreAlign, precioAlign, \.\.\.propio \} = qrReadLayout\(\);/.test(UI));

console.log(`\n${passed} comprobaciones OK`);
