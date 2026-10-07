/**
 * ticket-copias.js — cuántas copias del ticket de venta (2026-10-07 usuario).
 *
 * > «Print agent가 매번 티켓을 몇 카피를 출력할지 결정할 수 있어야 하는데»
 *   → ajuste del agente (1–3), sólo el ticket de venta.
 *
 * ★ Sólo el ticket que sale SOLO al vender (`printJobId = sale-invoice:<id>`). La reimpresión
 *   (`sale-reprint:…`) la pide una persona y sale 1: si pide una, no le salen tres.
 *   Factura AFIP, comanda, presupuesto y prueba no pasan por acá.
 * ★ Sin printJobId (servidor viejo) → 1, como siempre. Ante cualquier duda, 1.
 * ★ Las copias son UN trabajo: el registro de «ya impreso» (print-dedup) se toma una vez antes de
 *   imprimir. Si el servidor reenvía el mismo trabajo, se rechaza entero — nunca 2×N.
 */
const MAX_COPIAS = 3;

/** Lo guardado → 1..MAX_COPIAS (cualquier cosa rara = 1). */
function normalizarCopias(v) {
  const n = Number(v);

  return Number.isInteger(n) && n >= 1 && n <= MAX_COPIAS ? n : 1;
}

/** Copias para ESTE trabajo de print_invoice. */
function copiasDelTicket(payload, configurado) {
  const job = payload && typeof payload.printJobId === 'string' ? payload.printJobId : '';
  if (!job.startsWith('sale-invoice:')) return 1;
  if (payload && payload.factura) return 1;

  return normalizarCopias(configurado);
}

module.exports = { copiasDelTicket, normalizarCopias, MAX_COPIAS };
