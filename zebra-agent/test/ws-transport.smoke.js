/**
 * Toda conexión socket.io del agente tiene que ser **websocket-only**.
 * Ejecutar: node test/ws-transport.smoke.js
 *
 * ═══════════════════════════════════════════════════════════════════════════════
 * ★★★ Por qué existe [2026-09-25, reporte del usuario: 「api 값을 넣어도 오류를 발생시켜」]
 *
 *   El asistente de configuración llamaba a `io()` sin `transports`, así que
 *   socket.io arrancaba por **polling**. El polling necesita sticky sessions y el
 *   backend corre con 4 workers de PM2: el segundo request cae en otro worker y el
 *   handshake muere. Resultado: **ninguna API Key servía**, y el mensaje en pantalla
 *   («xhr poll error») no decía nada de la clave.
 *
 *   Medido contra producción con la **misma clave inválida** en los dos casos:
 *     · `transports: ['websocket']` → `auth_error` «Invalid API key…»  (llega)
 *     · por defecto (polling)       → `connect_error` «xhr poll error» (no llega)
 *
 *   El síntoma del lado servidor era una **ausencia**: cero `CONNECTION ATTEMPT` con
 *   clave de zebra en 6 horas, y los agentes zebra 18 y 24 con `last_seen_at` NULL.
 *   Nunca se conectaron, y nada gritó.
 *
 * ★★ La conexión principal ya era websocket-only; el defecto vivía **sólo en el
 *   asistente**. Un agente que nunca pasa el asistente jamás llega a la conexión
 *   buena — por eso un solo sitio sin la opción alcanza para romper el producto.
 * ═══════════════════════════════════════════════════════════════════════════════
 */
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const RUTA = path.join(__dirname, '..', 'main.js');
const BRUTO = fs.readFileSync(RUTA, 'utf8');

/**
 * La fuente **sin comentarios**.
 *
 * ★★★ Obligatorio acá: el comentario que explica este arreglo **cita**
 *   `transports: ['websocket']`. Midiendo el archivo crudo, alguien podría borrar la
 *   opción y dejar el comentario, y esta prueba seguiría pasando — mediría la
 *   documentación, no el código. Los dos controles están abajo.
 */
const sinComentarios = (s) =>
  s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/[^\n]*/g, '$1');

const CODIGO = sinComentarios(BRUTO);

let pasadas = 0;
function ok(nombre, cond) {
  assert.ok(cond, nombre);
  pasadas += 1;
  console.log('  ✓', nombre);
}

/** Los bloques de opciones de cada `io(...)`, del código sin comentarios. */
function bloquesDeIo(fuente) {
  const lineas = fuente.split('\n');
  const bloques = [];
  for (let i = 0; i < lineas.length; i += 1) {
    if (!/\bio\(/.test(lineas[i])) continue;
    const bloque = [];
    for (let j = i; j < lineas.length && j < i + 40; j += 1) {
      bloque.push(lineas[j]);
      if (/^\s*\}\);/.test(lineas[j])) break;
    }
    bloques.push(bloque.join('\n'));
  }

  return bloques;
}

console.log('ws-transport.smoke');

// ── Controles de que estamos midiendo algo ──────────────────────────────────
ok('control — se leyó main.js y es el que creemos',
  BRUTO.length > 5000 && CODIGO.includes("require('socket.io-client')"));

ok('★★★ control — quitar comentarios NO se lleva el código',
  CODIGO.includes('const testSocket = io(') && CODIGO.includes('wsConnection = io('));

ok('★★★ control — pero sí se lleva los comentarios',
  BRUTO.includes('sticky sessions') && !CODIGO.includes('sticky sessions'));

// ── Lo que se fija ──────────────────────────────────────────────────────────
const bloques = bloquesDeIo(CODIGO);

ok(`se encontraron los 2 sitios que abren socket (hay ${bloques.length})`,
  bloques.length === 2);

bloques.forEach((b, i) => {
  ok(`sitio ${i + 1} declara transports websocket-only`,
    /transports:\s*\['websocket'\]/.test(b));
});

// ★ El asistente es el sitio que estaba roto. Se nombra aparte para que, si alguien
//   reordena el archivo, el fallo diga **cuál** falta y no sólo «uno de los dos».
const asistente = bloques.find(b => b.includes('const testSocket = io('));
ok('el asistente (testWsConnection) es websocket-only',
  !!asistente && /transports:\s*\['websocket'\]/.test(asistente));

ok('y además no deja que suba desde polling (upgrade: false)',
  !!asistente && /upgrade:\s*false/.test(asistente));

// ★★ Control en la otra dirección: si esta prueba no midiera nada, borrar la opción
//   seguiría pasando. Se comprueba con la fuente mutada en memoria.
const mutado = CODIGO.replace(/transports:\s*\['websocket'\],?/g, '');
ok('★★ mutante — sin la opción, la comprobación se apaga',
  bloquesDeIo(mutado).every(b => !/transports:\s*\['websocket'\]/.test(b)));

console.log(`\n${pasadas} comprobaciones OK`);
