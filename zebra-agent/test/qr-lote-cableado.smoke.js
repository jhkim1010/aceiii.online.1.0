/**
 * El selector de símbolo está **cableado**: pantalla → preload → main → formatter.
 * Ejecutar: node test/qr-lote-cableado.smoke.js
 *
 * ★★★ La decisión pura vive en `qr-lote.test.js`. Acá se mide que el valor **llegue**:
 *   una opción que la pantalla guarda y nadie lee es el modo de falla de este tipo de
 *   control — se elige «QR», sale un código de barras, y parece que la impresora está
 *   mal configurada.
 * ★ Y que la tercera pestaña (enlace profundo) **no se toque**: son dos usos distintos
 *   del mismo símbolo y mezclarlos rompe el lector de la tienda.
 */
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const sinComentarios = (s) =>
  s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/[^\n]*/g, '$1');

const leer = (...p) => fs.readFileSync(path.join(__dirname, '..', ...p), 'utf8');
const MAIN_BRUTO = leer('main.js');
const MAIN = sinComentarios(MAIN_BRUTO);
const PRELOAD = sinComentarios(leer('preload.js'));
const UI_BRUTO = leer('renderer', 'index.html');
const UI = sinComentarios(UI_BRUTO);

let passed = 0;
function ok(name, cond) {
  assert.ok(cond, name);
  passed += 1;
  console.log('  ✓', name);
}

console.log('qr-lote-cableado.smoke');

// ── Controles de que medimos algo ──────────────────────────────────────────
ok('control — se leyeron los archivos y son los que creemos',
  MAIN.includes("ipcMain.handle('print:labels'") &&
  PRELOAD.includes('contextBridge') &&
  UI.includes('id="lote-simbolo-qr"'));

// ★ La frase tiene que estar **en una sola línea** del archivo: la primera versión
//   citó un texto partido por el salto de línea del comentario y el control falló —
//   que es para lo que está. (Mismo tropiezo que en la app esta mañana.)
const SOLO_EN_COMENTARIO = 'esta opción no puede cambiar lo que ya salía';
ok('★★★ control — quitar comentarios se lleva los comentarios, no el código',
  MAIN_BRUTO.includes(SOLO_EN_COMENTARIO) &&
  !MAIN.includes(SOLO_EN_COMENTARIO) &&
  MAIN.includes('formatBatchLabels(prepareItems(items)'));

// ── El camino completo ─────────────────────────────────────────────────────
ok('la pantalla manda las opciones', UI.includes('api.printLabels(items, opciones)'));
ok('preload las pasa', /printLabels:\s*\(items,\s*opciones\)/.test(PRELOAD));
ok('main las recibe', /print:labels',\s*async\s*\(_event,\s*items,\s*opciones\)/.test(MAIN));
ok('y se las da al formatter',
  /formatBatchLabels\(prepareItems\(items\),\s*mode,\s*\{[\s\S]{0,120}simbolo/.test(MAIN));

// ── El defecto por defecto: ausente = barras ───────────────────────────────
// ★ Esta opción es nueva; si su ausencia cambiara algo, rompería lo que ya salía.
ok('★★ sin opciones, main resuelve barras',
  /const esQr = !!\(opciones && opciones\.simbolo === 'qr'\)/.test(MAIN));

// ── «Por etiqueta» sólo para QR ────────────────────────────────────────────
ok('la pantalla esconde «por etiqueta» cuando son barras',
  /caja\.style\.display = o\.simbolo === 'qr' \? 'flex' : 'none'/.test(UI));

// ── El recuento que se informa son etiquetas, no unidades ──────────────────
ok('★★ main informa etiquetas (ceil por producto) cuando son 2 por etiqueta',
  /Math\.ceil\(Math\.max\(1, it\.qty \|\| 1\) \/ 2\)/.test(MAIN));
ok('★★ y la pantalla usa la misma cuenta', /Math\.ceil\(it\.qty \/ 2\)/.test(UI));

// ── La tercera pestaña sigue mandando el enlace profundo ───────────────────
// ★★★ Si esto se rompiera, el cliente escanearía un SKU con el teléfono y no pasaría
//   nada; y al revés, el lector de la tienda no reconocería una URL.
ok('★★★ la pestaña QR sigue mandando el enlace profundo (item.qrUrl), no el SKU',
  /formatQrLabel\(\{[\s\S]{0,120}contenido: item\.qrUrl/.test(MAIN));
ok('★★★ y el lote manda el SKU, no una URL',
  !/qrLabelsDeItem[\s\S]{0,200}qrUrl/.test(MAIN));

// ── Mutantes en memoria ────────────────────────────────────────────────────
ok('★★ mutante — sin el paso de opciones a printLabels, la comprobación se apaga',
  !UI.split('api.printLabels(items, opciones)').join('').includes('api.printLabels(items, opciones)'));

console.log(`\n${passed} comprobaciones OK`);
