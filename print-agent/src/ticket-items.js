/**
 * Opciones de las líneas de producto del ticket (PEDIDO 89 · suerte, 2026-10-23).
 *
 * suerte: «[ACCESORRIOS DE PELO] COLITA B/N» — el «[categoría]» viene dentro del nombre del
 * producto (Ventago lo arma al cargar) y en el papel ocupa el renglón que necesita el nombre.
 *
 * - `sinCategoria`: quita el primer «[...]» del inicio del nombre **sólo al imprimir**.
 *   Si no queda nada, el nombre sale como estaba. Mismo criterio que el Zebra (PEDIDO 45).
 * - `skuColumna`: el SKU sale en su propia columna — Cnt · SKU · Descripción · P.Unit · Precio —
 *   en vez de «[SKU]» delante del nombre.
 *
 * ★ Las dos apagadas por defecto: con ambas en false el ticket es idéntico al de antes
 *   (lo fija test/ticket-items.smoke.js comparando contra el HTML sin opciones).
 * ★ La factura AFIP (fiscal-formatter.js) no las usa — no se tocó su descripción.
 */
const PREFIJO_CATEGORIA_RE = /^\s*\[[^\]\n]*\]\s*/;

const DEFAULTS = { sinCategoria: false, skuColumna: false };

let current = { ...DEFAULTS };

/** Boot + store:set — sólo acepta booleanos; cualquier otra cosa deja el valor anterior. */
function configure(opts) {
  if (!opts) return;
  for (const k of Object.keys(DEFAULTS)) {
    if (typeof opts[k] === 'boolean') current[k] = opts[k];
  }
}

function getOpciones() {
  return { ...current };
}

function nombreSinCategoria(name) {
  if (typeof name !== 'string') return name;
  const resto = name.replace(PREFIJO_CATEGORIA_RE, '');

  return resto.trim() ? resto : name;
}

/** Copia de `data` con los nombres ya preparados (no muta el payload original). */
function prepararItems(data, opciones) {
  if (!data || !opciones || opciones.sinCategoria !== true || !Array.isArray(data.items)) {
    return data;
  }

  return {
    ...data,
    items: data.items.map((it) => (it ? { ...it, name: nombreSinCategoria(it.name) } : it)),
  };
}

module.exports = { DEFAULTS, configure, getOpciones, nombreSinCategoria, prepararItems };
