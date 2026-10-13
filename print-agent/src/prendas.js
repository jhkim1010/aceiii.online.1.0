/**
 * «Prendas: N» — cuántas prendas se lleva el cliente (pedido de tienda, 2026-10-13).
 *
 * Se imprime **arriba del TOTAL** en todos los tickets (venta, temporal/regalo,
 * texto plano y factura fiscal). Una sola función para todos: si cada layout
 * contara por su cuenta, el mismo ticket diría números distintos según la ruta.
 *
 * Reglas:
 *   · N = suma de cantidades de las líneas que NO son devolución. Las líneas de
 *     promoción gratis (isPromoFree, precio 0) **cuentan** — el cliente se las lleva.
 *   · Devolución = `isReturn === true` o cantidad negativa. El servidor guarda la
 *     devolución como cantidad negativa (sales-create.service.ts) y el POS manda
 *     `signoLinea(p) * quantity` — por eso el signo es la señal principal.
 *     M = suma en valor absoluto.
 *   · Cantidad ausente → 1, igual que la columna «Cnt» (`item.quantity || 1`):
 *     el papel no puede decir 1 en la fila y 0 en el total.
 *   · Cantidades con decimales (tela por metro) se suman igual y se imprimen sin
 *     ceros de más («2.5», no «2.500»).
 *
 * ★ Fuente de las líneas: `itemsRaw` antes que `items`. El servidor agrupa `items`
 *   por (madre, precio) — un cambio de talle del mismo modelo al mismo precio
 *   (devuelve M, se lleva L) queda en **un** grupo con cantidad 0 neta. `itemsRaw`
 *   trae una fila por sale_item con su signo. Las rutas sin `itemsRaw` (POS /print/temp)
 *   ya mandan una fila por línea del carrito con su signo.
 */

const num = (v) => {
  if (v === undefined || v === null || v === '') return 1;
  const n = typeof v === 'string' ? Number(v.replace(',', '.')) : Number(v);

  return Number.isFinite(n) ? n : 0;
};

// Redondeo a 3 decimales para que 0.1 + 0.2 no imprima 0.30000000000000004.
const fmt = (n) => String(Number((Math.round(n * 1000) / 1000).toFixed(3)));

/**
 * @param {Array<object>} lines  filas con `quantity` (o `cant` en la factura) e `isReturn?`
 * @returns {{ llevadas: number, devueltas: number }}
 */
function contarPrendas(lines) {
  let llevadas = 0;
  let devueltas = 0;
  for (const it of Array.isArray(lines) ? lines : []) {
    if (!it || typeof it !== 'object') continue;
    const q = num(it.quantity !== undefined ? it.quantity : it.cant);
    if (it.isReturn === true || q < 0) devueltas += Math.abs(q);
    else llevadas += q;
  }

  return { llevadas, devueltas };
}

/** Las filas que representan el ticket: `itemsRaw` si viene, si no `items`. */
function lineasDelTicket(data) {
  const d = data || {};
  if (Array.isArray(d.itemsRaw) && d.itemsRaw.length > 0) return d.itemsRaw;

  return Array.isArray(d.items) ? d.items : [];
}

/**
 * Textos a imprimir. Sin líneas → [] (no se imprime nada).
 * @returns {string[]}  ['Prendas: N'] o ['Prendas: N', 'Devueltas: M']
 */
function lineasPrendas(lines) {
  if (!Array.isArray(lines) || lines.length === 0) return [];
  const { llevadas, devueltas } = contarPrendas(lines);
  const out = [`Prendas: ${fmt(llevadas)}`];
  if (devueltas > 0) out.push(`Devueltas: ${fmt(devueltas)}`);

  return out;
}

/** HTML para los tickets térmicos. `clase` permite estilos por layout. */
function prendasHtml(lines, clase = 'prendas') {
  const ls = lineasPrendas(lines);
  if (ls.length === 0) return '';

  // Sólo dígitos, punto y texto fijo — no hace falta escapar.
  return `<div class="${clase}">${ls
    .map((l) => {
      const [k, v] = l.split(': ');

      return `<div class="prendas-row"><span>${k}:</span><span>${v}</span></div>`;
    })
    .join('')}</div>`;
}

module.exports = { contarPrendas, lineasDelTicket, lineasPrendas, prendasHtml };
