// [2026-10-24] Supervisor de Guardia — lo que ejecuta la tarea programada (Windows) / launchd (macOS).
//
// Levanta src/main.js como proceso hijo y:
//   · si el hijo sale con EXIT_ACTUALIZAR (75) → acaba de cambiar de versión: lo vuelve a levantar
//     YA, desde el disco (o sea, la versión nueva). No depende de que Windows reinicie la tarea.
//   · si la versión recién cambiada se cae en los primeros 2 min → vuelve a la anterior
//     (.actualizacion/anterior), anota la versión como fallida y la levanta de nuevo.
//   · cualquier otra salida → sale con el mismo código (como antes: la tarea/launchd reintenta).
//
// ★ Este archivo se mantiene mínimo a propósito: el proceso supervisor sigue corriendo su código
//   viejo después de una actualización, así que no debe depender de nada que cambie seguido.

const path = require('path');
const { fork } = require('child_process');
const updater = require('./updater');
const { createLogger } = require('./logger');

const log = createLogger('Supervisor');
const ROOT = path.join(__dirname, '..');
const VENTANA_ARRANQUE_MS = 2 * 60 * 1000;

let hijo = null;
let saliendo = false;

function lanzar() {
  const inicio = Date.now();
  hijo = fork(path.join(ROOT, 'src', 'main.js'), process.argv.slice(2), { cwd: ROOT, stdio: 'inherit' });
  log.info(`main.js iniciado pid=${hijo.pid}`);

  hijo.on('exit', (code, signal) => {
    hijo = null;
    if (saliendo) process.exit(code ?? 0);

    if (code === updater.EXIT_ACTUALIZAR) {
      log.info('cambio de versión — relanzando');
      lanzar();

      return;
    }

    const estado = updater.leerEstado(ROOT);
    if (estado.fase === 'cambiada' && code !== 0 && Date.now() - inicio < VENTANA_ARRANQUE_MS) {
      log.error(`la versión ${estado.hacia} se cayó al arrancar (code=${code} signal=${signal}) — volviendo a ${estado.desde}`);
      try {
        updater.volverAtras(ROOT);
        updater.guardarEstado(ROOT, {
          ...estado,
          fase: 'revertida',
          fallidas: [...new Set([...(estado.fallidas || []), estado.hacia])],
          at: new Date().toISOString(),
        });
        lanzar();

        return;
      } catch (err) {
        log.error('volver atrás falló:', err);
      }
    }

    log.warn(`main.js salió code=${code} signal=${signal}`);
    process.exit(code ?? 1);
  });
}

function terminar(signal) {
  saliendo = true;
  if (hijo) hijo.kill(signal);
  else process.exit(0);
}

process.on('SIGINT', () => terminar('SIGINT'));
process.on('SIGTERM', () => terminar('SIGTERM'));

lanzar();
