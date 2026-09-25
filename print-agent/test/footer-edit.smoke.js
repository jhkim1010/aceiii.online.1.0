/**
 * Editar el pie de impresión desde el agente — que esté cableado y que **no** guarde
 * una copia local. Ejecutar: node test/footer-edit.smoke.js
 *
 * ═══════════════════════════════════════════════════════════════════════════════
 * ★★★ [2026-09-25 사용자 요구] 「pie de impresión 의 내용을 print agent 에서 직접
 *   수정할 수 있으면 더 편할거 같아」
 *
 * ★★ La regla que hay que sostener: **el valor vive en el servidor**
 *   (`branch_agents.printer_config.footerLines`), y el servidor **pisa** el pie que
 *   venga en el payload de impresión (`applyTicketFooter`). Si el agente guardara una
 *   copia en su `electron-store`, la pantalla del agente mostraría una cosa, el papel
 *   otra, y la pantalla web (Sucursales › Impresora) una tercera. Tres verdades para
 *   el mismo dato es exactamente el defecto que se persiguió todo el día.
 *   ⤷ Lectura: `agent_info` (el servidor lo manda al conectar).
 *     Escritura: socket `set_footer` (el servidor resuelve **qué** agente por la clave).
 *
 * ★ Y sin conexión no se edita: si el cuadro apareciera vacío y alguien guardara,
 *   **borraría** el pie que hoy sale impreso sin haberlo visto nunca.
 * ═══════════════════════════════════════════════════════════════════════════════
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

let pasadas = 0;
function ok(nombre, cond) {
  assert.ok(cond, nombre);
  pasadas += 1;
  console.log('  ✓', nombre);
}

console.log('footer-edit.smoke');

// ── Controles: ¿estamos midiendo algo? ──────────────────────────────────────
ok('control — se leyeron los archivos y son los que creemos',
  MAIN.includes("ipcMain.handle('store:set'") && PRELOAD.includes('contextBridge') && UI.includes('<textarea id="footerText"'));

ok('★★★ control — quitar comentarios se lleva los comentarios, no el código',
  MAIN_BRUTO.includes('로컬 사본을 두지 않는다') &&
  !MAIN.includes('로컬 사본을 두지 않는다') &&
  MAIN.includes("ipcMain.handle('footer:set'"));

// ── El camino completo: UI → preload → main → socket ────────────────────────
ok('la UI llama a setFooter', UI.includes('window.electronAPI.setFooter('));
ok('preload expone getFooter/setFooter',
  PRELOAD.includes("invoke('footer:get')") && PRELOAD.includes("invoke('footer:set'"));
ok('main atiende los dos ipc',
  MAIN.includes("ipcMain.handle('footer:get'") && MAIN.includes("ipcMain.handle('footer:set'"));
ok('y escribe por socket, con el evento que el servidor escucha',
  MAIN.includes("wsConnection.emit('set_footer'"));

// ── La regla: NADA de copia local ───────────────────────────────────────────
// ★ Mide que no exista una clave propia de footer en el electron-store. `_lastAgentInfo`
//   es la caché de lo que mandó el servidor, no una fuente — por eso se permite.
const escrituras = [...MAIN.matchAll(/store\.set\('([^']+)'/g)].map((m) => m[1]);
ok(`★★ no hay clave de footer propia en el store (claves: ${[...new Set(escrituras)].join(', ')})`,
  !escrituras.some((k) => /footer/i.test(k)));

ok('★★ la lectura sale de lo que mandó el servidor, no de un valor guardado',
  /footer:get[\s\S]{0,400}_lastAgentInfo/.test(MAIN));

// ── Sin conexión no se edita ni se guarda ───────────────────────────────────
ok('main rechaza guardar si no hay conexión',
  /footer:set[\s\S]{0,300}connectionStatus !== 'connected'[\s\S]{0,120}ok: false/.test(MAIN));

ok('la UI deshabilita el cuadro cuando no está conectado',
  UI.includes('footerText.disabled = !listo') && UI.includes('btnSaveFooter.disabled = !listo'));

// ── Lo guardado se repinta con la respuesta del servidor ────────────────────
// ★ El servidor recorta a 4 líneas × 60 caracteres. Si la pantalla dejara lo tipeado,
//   mostraría renglones que el papel no tiene.
ok('la UI repinta con lo que devolvió el servidor',
  /r\.footerLines[\s\S]{0,200}footerText\.value\s*=/.test(UI) || /footerText\.value = \(r\.footerLines/.test(UI));

ok('una reconexión vuelve a pintar el pie',
  UI.includes('window.__recargarFooter'));

// ── Mutante en memoria: si se saca el emit, el cableado deja de medirse ─────
ok('★★ mutante — sin el emit, la comprobación de escritura se apaga',
  !MAIN.split("wsConnection.emit('set_footer'").join('').includes("wsConnection.emit('set_footer'"));

console.log(`\n${pasadas} comprobaciones OK`);
