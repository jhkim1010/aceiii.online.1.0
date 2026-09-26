/**
 * Una sola instancia del agente por PC. Ejecutar: node test/single-instance.smoke.js
 *
 * ★ [2026-09-26 사용자 요구] 「같은 api 값을 갖고 있는 print agent 가 2개 뜨지 못하게」
 *   Dos instancias en la misma PC se conectan con la **misma clave**; el servidor deja
 *   la última y corta la anterior (DUPLICATE_CONNECTION). En producción se vio en NOIX
 *   (caja1, misma IP). zebra-agent ya tenía el candado; a print-agent le faltaba.
 *
 * ★ El candado tiene que ir **antes** de `app.whenReady()` y la segunda instancia tiene
 *   que **salir** — si sólo mostrara la ventana, igual abriría su propio socket.
 */
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const sinComentarios = (s) =>
  s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/[^\n]*/g, '$1');

const MAIN = sinComentarios(
  fs.readFileSync(path.join(__dirname, '..', 'main.js'), 'utf8'),
);

let pasadas = 0;
function ok(nombre, cond) {
  assert.ok(cond, nombre);
  pasadas += 1;
  console.log('  ✓', nombre);
}

const candado = (src) => {
  const lock = src.indexOf('app.requestSingleInstanceLock()');
  const ready = src.indexOf('app.whenReady()');

  return (
    lock >= 0 &&
    ready > lock &&
    /if\s*\(\s*!\s*gotSingleLock\s*\)\s*\{\s*app\.(exit|quit)\(/.test(src) &&
    /app\.on\(\s*'second-instance'/.test(src)
  );
};

console.log('single-instance.smoke');

// ── Controles: el detector tiene que fallar sin candado ──────────────────────
const sinCandado = MAIN.replace('app.requestSingleInstanceLock()', 'true');
ok('control: sin requestSingleInstanceLock el detector falla', !candado(sinCandado));

const sinSalir = MAIN.replace(/if\s*\(\s*!\s*gotSingleLock\s*\)\s*\{\s*app\.exit\(0\);\s*\}/, '');
ok('control: si la segunda instancia no sale, el detector falla', !candado(sinSalir));

// ── Regla ────────────────────────────────────────────────────────────────────
ok('print-agent toma el candado de instancia única antes de whenReady y sale si no lo obtiene', candado(MAIN));

console.log(`single-instance.smoke: ${pasadas} OK`);
