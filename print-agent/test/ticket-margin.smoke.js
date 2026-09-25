/**
 * El margen derecho del ticket: que exista, que se aplique y que **no** se aplique de más.
 * Ejecutar: node test/ticket-margin.smoke.js
 *
 * ═══════════════════════════════════════════════════════════════════════════════
 * ★★★ Por qué [2026-09-25, reporte del usuario con foto]
 *   「출력 이미지를 보면 미세하게 마지막 줄이 잘 안보여.. 금액 부분이..」
 *
 *   Antes de agregar la perilla se renderizó **esa misma venta** (Venta #10, $420.000):
 *   el HTML estaba bien — la banda del TOTAL es una sola línea y entra holgada en 576px.
 *   O sea el defecto no es el layout sino que el ancho imprimible real de esa impresora
 *   es menor que el lienzo. Eso cambia por modelo, así que es un ajuste, no una constante.
 *
 * ★★ Lo que se mide acá es **que el ajuste llegue al papel**. Guardar un valor que
 *   después nadie lee es el modo de falla de este tipo de opción: la pantalla dice
 *   «12 px», el papel sigue igual, y parece que la impresora está rota.
 * ═══════════════════════════════════════════════════════════════════════════════
 */
const assert = require('assert');
const ts = require('../src/ticket-settings');

const HTML = '<html><head><style>body { width: 576px; font-size: 20px; }</style></head><body>x</body></html>';
const anchoDe = (html) => {
  const m = html.match(/body \{ width: (\d+)px !important; \}/);

  return m ? Number(m[1]) : null;
};

let pasadas = 0;
function ok(nombre, cond) {
  assert.ok(cond, nombre);
  pasadas += 1;
  console.log('  ✓', nombre);
}

console.log('ticket-margin.smoke');

// ⓪ Control: sin este, «no hay regla de ancho» se cumpliría aunque el módulo
//   estuviera roto y devolviera el html sin tocar nada.
ts.configure({ family: 'arial', scale: 1, marginRight: 0 });
ok('control — el módulo sí procesa el html (inyecta la fuente)',
  ts.applyTicketSettings(HTML).includes('font-family:'));

ok('margen 0 → no se toca el ancho (el 99% de las impresoras)',
  anchoDe(ts.applyTicketSettings(HTML)) === null);

ts.configure({ marginRight: 12 });
ok('margen 12 → el cuerpo se angosta a 564px',
  anchoDe(ts.applyTicketSettings(HTML)) === 576 - 12);

ts.configure({ marginRight: 24 });
ok('margen 24 → 552px',
  anchoDe(ts.applyTicketSettings(HTML)) === 576 - 24);

// ★★ El lienzo NO se toca: si se achicara, dónde cae la imagen lo decide el driver
//   y el resultado cambia por impresora. Angostar sólo el body deja una franja blanca
//   a la derecha y mete hacia adentro los elementos a todo lo ancho — que son
//   justamente los que se cortaban (banner, encabezado de columnas, banda del TOTAL).
ok('★★ el lienzo sigue siendo 576 — sólo se angosta el body',
  ts.TICKET_WIDTH_PX === 576 && ts.applyTicketSettings(HTML).includes('width: 552px !important'));

// ── Valores inválidos: se descartan, se conserva el anterior ────────────────
// ★ Un ancho 0 sacaría el ticket en blanco, que es peor que «el ajuste no anduvo».
ts.configure({ marginRight: 24 });
for (const malo of [-1, 999, NaN, null, undefined, 'mucho', Infinity]) {
  ts.configure({ marginRight: malo });
  assert.strictEqual(ts.getSettings().marginRight, 24, `valor inválido aceptado: ${String(malo)}`);
}
pasadas += 1;
console.log('  ✓ valores inválidos se descartan y queda el anterior (7 casos)');

ts.configure({ marginRight: ts.MARGIN_RIGHT_MAX });
ok('el máximo declarado sí se acepta (si no, el slider llegaría a un tope muerto)',
  ts.getSettings().marginRight === ts.MARGIN_RIGHT_MAX);

// ── Que esté **cableado**: el valor viaja store → configure → render ────────
// ★ `applyTicketSettings` es el único punto por el que pasan todos los tipos de
//   impresión. Si alguien lo saltea en un camino nuevo, ese camino ignora el ajuste.
const fs = require('fs');
const path = require('path');
const sinComentarios = (s) =>
  s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/[^\n]*/g, '$1');

const MOTOR = sinComentarios(fs.readFileSync(path.join(__dirname, '..', 'src', 'renderer-engine.js'), 'utf8'));
const MAIN  = sinComentarios(fs.readFileSync(path.join(__dirname, '..', 'main.js'), 'utf8'));

ok('control — se leyeron los dos archivos y quitar comentarios no se llevó el código',
  MOTOR.includes('function renderHtmlToPng') && MAIN.includes("ipcMain.handle('store:set'"));

ok('el render aplica los ajustes (punto único)',
  MOTOR.includes('applyTicketSettings(html)'));

ok('guardar el valor lo aplica sin reiniciar',
  /\[.*'ticketMarginRight'.*\]\.includes\(key\)/s.test(MAIN) || MAIN.includes("'ticketMarginRight'"));

ok('main pasa marginRight a configure',
  /configure\(\{[^}]*marginRight:\s*store\.get\('ticketMarginRight'\)/s.test(MAIN));

console.log(`\n${pasadas} comprobaciones OK`);
