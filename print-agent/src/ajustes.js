/**
 * Etiqueta de un descuento / recargo global del ticket (PEDIDO 29, 2026-10-15).
 *
 * Antes el formatter pegaba siempre el nombre: `− Descuento — ${name}`. Las tiendas cargan
 * nombres genéricos y el papel salía «− Descuento — Descuento» o «− Descuento — de»
 * (Shaple: 13 de 22 descuentos «Descuento», 9 «de/DE»).
 *
 * Regla: nombre vacío o GENÉRICO (sin mayúsculas ni acentos) → sólo la palabra base.
 * Cualquier otro nombre («Efectivo 10%», «Cliente frecuente») se conserva.
 * Sólo cambia el TEXTO de la etiqueta — nunca el monto ni la cantidad de líneas.
 */
const GENERICOS = {
  descuento: ['descuento', 'descuentos', 'desc', 'dto', 'de', 'd'],
  recargo: ['recargo', 'recargos', 'rec', 'r'],
};

const BASE = { descuento: '− Descuento', recargo: '+ Recargo' };

const normalizar = (s) =>
  String(s ?? '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[.:\s]+$/g, '')
    .trim();

/** kind: 'descuento' | 'recargo'. Devuelve el texto plano (sin escapar). */
function etiquetaAjuste(kind, name) {
  const base = BASE[kind];
  if (!base) throw new Error(`etiquetaAjuste: kind desconocido «${kind}»`);
  const limpio = String(name ?? '').trim();
  const n = normalizar(limpio);
  if (!n || GENERICOS[kind].includes(n)) return base;

  return `${base} — ${limpio}`;
}

module.exports = { etiquetaAjuste };
