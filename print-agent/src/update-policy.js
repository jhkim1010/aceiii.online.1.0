// src/update-policy.js — ¿cuándo se puede reiniciar el agente para instalar una actualización?
// (mismo archivo en print-agent y zebra-agent)
//
// ★ Por qué existe (실측 2026-10-06): la descarga ya andaba, pero la instalación sólo
//   ocurría «al salir del agente». Las tiendas lo dejan prendido todo el día y el «Salir»
//   de la bandeja usaba app.exit(), que **no** dispara 'quit' → autoInstallOnAppQuit nunca
//   corría. Resultado: print 1.2.5/1.2.6 en la calle con 1.2.10 publicado, zebra 1.0.28/1.0.30
//   con 1.0.32.
//
// ★ Regla dura: nunca reiniciar con una impresión en curso (un reinicio a mitad de un
//   trabajo puede perderlo o, si el servidor lo reenvía, imprimirlo dos veces).

// Ventana de instalación automática, en hora LOCAL de la PC de la tienda: [desde, hasta)
const VENTANA_DESDE = 3;
const VENTANA_HASTA = 6;

// Sin imprimir nada durante este tiempo = el agente está quieto
const QUIETO_MS = 10 * 60 * 1000;

/**
 * Instalación automática (sin que nadie toque nada).
 * @returns {{ ok: boolean, motivo?: string }}
 */
function puedeInstalarSolo({ listo, ahora, enCurso, ultimaActividad }) {
  if (!listo) return { ok: false, motivo: 'sin-descarga' };

  const hora = new Date(ahora).getHours();
  if (hora < VENTANA_DESDE || hora >= VENTANA_HASTA) return { ok: false, motivo: 'fuera-de-horario' };

  if (enCurso > 0) return { ok: false, motivo: 'imprimiendo' };

  if (ahora - (ultimaActividad || 0) < QUIETO_MS) return { ok: false, motivo: 'actividad-reciente' };

  return { ok: true };
}

/**
 * Botón «Actualizar ahora»: lo pide una persona, así que no importa la hora.
 * Las impresiones en curso no se miran acá: el reinicio pasa siempre por
 * `esperarQuieto()` (abajo), que espera a que terminen.
 */
function puedeInstalarAMano({ listo }) {
  if (!listo) return { ok: false, motivo: 'sin-descarga' };

  return { ok: true };
}

// Después del último envío a la impresora el agente todavía confirma al servidor
// (ACK con timeout de 10 s: mark_qr_printed, print ack). Reiniciar antes = el servidor
// no sabe que se imprimió y lo vuelve a mandar → copia doble.
const ACK_MS = 12 * 1000;

const dormir = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * Cuenta los trabajos de impresión en curso. `envolver(fn)` devuelve una función que
 * marca inicio y fin (también si falla) — se aplica a la llamada que toca la impresora.
 *
 * `cerrar()` deja en la puerta los trabajos nuevos (esperan, no se pierden) mientras se
 * decide reiniciar; `abrir()` los deja pasar. `esperarQuieto()` es el único lugar que
 * decide «se puede reiniciar ya»: sin trabajos en curso, sin trabajos en la puerta y
 * pasado el ACK del último.
 */
function crearActividad(reloj = () => Date.now()) {
  const estado = { enCurso: 0, esperando: 0, ultimaActividad: 0, cerrado: false };
  let soltarPuerta = null;
  let puerta = null;

  const envolver = (fn) => async (...args) => {
    while (estado.cerrado) {
      estado.esperando += 1;
      try {
        await puerta;
      } finally {
        estado.esperando -= 1;
      }
    }
    estado.enCurso += 1;
    estado.ultimaActividad = reloj();
    try {
      return await fn(...args);
    } finally {
      estado.enCurso -= 1;
      estado.ultimaActividad = reloj();
    }
  };

  const cerrar = () => {
    if (estado.cerrado) return;
    estado.cerrado = true;
    puerta = new Promise((r) => { soltarPuerta = r; });
  };

  const abrir = () => {
    if (!estado.cerrado) return;
    estado.cerrado = false;
    soltarPuerta();
  };

  /**
   * Cierra la puerta y espera a que el agente quede quieto. Devuelve true con la puerta
   * CERRADA (el que llama reinicia en el mismo tick, sin await en el medio). Si en el
   * plazo no se logra, la abre y devuelve false.
   */
  const esperarQuieto = async ({ plazoMs = 2 * 60 * 1000, pasoMs = 250, dormirFn = dormir } = {}) => {
    const t0 = reloj();
    while (reloj() - t0 < plazoMs) {
      cerrar();
      if (estado.esperando > 0) {
        // alguien llegó mientras estaba cerrado: que imprima primero
        abrir();
      } else if (estado.enCurso === 0 && reloj() - estado.ultimaActividad >= ACK_MS) {
        return true;
      }
      await dormirFn(pasoMs);
    }
    abrir();

    return false;
  };

  return { estado, envolver, cerrar, abrir, esperarQuieto };
}

module.exports = {
  puedeInstalarSolo,
  puedeInstalarAMano,
  crearActividad,
  VENTANA_DESDE,
  VENTANA_HASTA,
  QUIETO_MS,
  ACK_MS,
};
