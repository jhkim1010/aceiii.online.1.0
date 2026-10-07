/**
 * [2026-10-07 usuario] «Vista Zebra» — cómo sale de verdad la etiqueta.
 *
 * > «Zebra agent 에서 생성한 zpl 코드를 읽으면 어떻게 출력될지 확인할 수 있을텐데..» → opción 2
 *
 * La vista previa del diseño (canvas) es un dibujo aproximado: no sabe cuándo el código de barras
 * se sale de la etiqueta ni cómo queda la fuente de la impresora. Acá se manda el MISMO ZPL que se
 * imprime a Labelary (emulador de Zebra en línea, 203 dpi) y se muestra la imagen que devuelve.
 *
 * ★ Sale a internet el contenido de la etiqueta (nombre, SKU, precio). Por eso es un botón — nunca
 *   automático — y la pantalla lo dice. Sin internet no hay vista: la impresión no depende de esto.
 * ★ Sólo la PRIMERA etiqueta del ZPL (índice 0): es una muestra, no el lote.
 */

const { formatBatchLabels, formatTestLabel } = require('./zpl-formatter');
const { prepareItems } = require('./price-select');

const LABELARY = 'https://api.labelary.com/v1/printers/8dpmm/labels';
const DPI = 203.2; // 8 dpmm
const MAX_PULGADAS = 15; // límite de Labelary
const MAX_PNG_BYTES = 3 * 1024 * 1024; // una etiqueta de 203 dpi pesa KB; más es una respuesta rara

/** Ancho y alto (dots) de la primera etiqueta: lo que dicen ^PW/^LL, si no el modo. */
function tamanoDeZpl(zpl, mode) {
  const pw = /\^PW(\d+)/.exec(zpl);
  const ll = /\^LL(\d+)/.exec(zpl);

  return {
    ancho: pw ? Number(pw[1]) : (mode && mode.width) || 400,
    alto: ll ? Number(ll[1]) : (mode && mode.height) || 200,
  };
}

const pulgadas = (dots) => (dots / DPI).toFixed(2);

function urlLabelary(ancho, alto) {
  return `${LABELARY}/${pulgadas(ancho)}x${pulgadas(alto)}/0/`;
}

/**
 * ZPL → PNG (data URL). Nunca lanza: devuelve { ok:false, error } con un texto para la persona.
 * @param {string} zpl
 * @param {{ mode?: object, fetchImpl?: Function, timeoutMs?: number }} [o]
 */
async function renderizarZpl(zpl, { mode = null, fetchImpl = globalThis.fetch, timeoutMs = 12000 } = {}) {
  if (!zpl || typeof zpl !== 'string') return { ok: false, error: 'No hay etiqueta para mostrar' };
  const { ancho, alto } = tamanoDeZpl(zpl, mode);
  // [codex 046] no achicar en silencio: con otro tamaño la imagen no sería la etiqueta real
  if (!(ancho > 0 && alto > 0 && ancho <= MAX_PULGADAS * DPI && alto <= MAX_PULGADAS * DPI)) {
    return { ok: false, error: `La etiqueta mide ${ancho}×${alto} dots: el emulador sólo dibuja hasta ${MAX_PULGADAS}" por lado.` };
  }
  try {
    const r = await fetchImpl(urlLabelary(ancho, alto), {
      method: 'POST',
      headers: { Accept: 'image/png', 'Content-Type': 'application/x-www-form-urlencoded' },
      body: zpl,
      signal: AbortSignal.timeout(timeoutMs),
    });
    if (r.status === 429) return { ok: false, error: 'Demasiadas vistas seguidas. Esperá unos segundos.' };
    if (!r.ok) {
      const txt = String(await r.text().catch(() => '')).slice(0, 200);

      return { ok: false, error: `El emulador no pudo leer la etiqueta (${r.status})${txt ? `: ${txt}` : ''}` };
    }
    // [codex 046] sólo una imagen PNG de tamaño razonable
    const tipo = String((r.headers && r.headers.get && r.headers.get('content-type')) || '');
    const largo = Number((r.headers && r.headers.get && r.headers.get('content-length')) || 0);
    if (!tipo.startsWith('image/png') || largo > MAX_PNG_BYTES) {
      return { ok: false, error: 'El emulador devolvió algo que no es una imagen.' };
    }
    const buf = Buffer.from(await r.arrayBuffer());
    if (buf.length > MAX_PNG_BYTES) return { ok: false, error: 'El emulador devolvió una imagen demasiado grande.' };

    return { ok: true, png: `data:image/png;base64,${buf.toString('base64')}`, ancho, alto };
  } catch (_) {
    return { ok: false, error: 'Sin conexión con el emulador (hace falta internet).' };
  }
}

const MUESTRA_NOMBRE = 'REMERA OVERSIZE NEGRA M';
const MUESTRA_MONTOS = [12999, 9750, 8100];

/**
 * El ZPL que se mostraría — con las MISMAS funciones que imprimen.
 *   tipo 'diseno': el modo armado en pantalla (sin guardar) + un producto de muestra
 *   tipo 'lote'  : el primer producto elegido, como «Imprimir 1 de prueba» (print:labels)
 *   tipo 'test'  : la etiqueta de «Imprimir test»
 * @param {object} args  { tipo, mode?, sku?, items?, opciones? } (viene de la pantalla)
 * @param {object} ctx   { ajustes:{darkness,speed}, modoEfectivo, modoImpresion, seleccion, qrLayout }
 * @returns {{ zpl: string|null, mode: object|null }}
 */
function armarZplVista({ tipo, mode, sku, items, opciones } = {}, ctx) {
  const { darkness = null, speed = null } = ctx.ajustes || {};
  if (tipo === 'test') {
    return { zpl: formatTestLabel(ctx.modoEfectivo, { darkness, speed }), mode: ctx.modoEfectivo };
  }
  const seleccion = Array.isArray(ctx.seleccion) ? ctx.seleccion : [];
  if (tipo === 'diseno') {
    // densidad/velocidad son de la impresora, no del diseño — como al imprimir
    const m = { ...(mode || ctx.modoEfectivo), darkness, speed };
    if (seleccion.length > 0) m.layout = { ...(m.layout || {}), priceCount: seleccion.length };
    const niveles = seleccion.length > 0 ? seleccion : [{ id: null, name: '' }];
    const muestra = {
      name: MUESTRA_NOMBRE,
      sku: String(sku || 'VG00123456'),
      barcodeType: 'CODE128',
      prices: niveles.slice(0, 3).map((s, i) => ({ priceTypeId: s.id ?? null, label: s.name || '', amount: MUESTRA_MONTOS[i] })),
      qty: 1,
    };

    return { zpl: formatBatchLabels(prepareItems([muestra], seleccion, m.layout || {}), m, { simbolo: 'barras' }), mode: m };
  }
  if (tipo !== 'lote' || !Array.isArray(items) || items.length === 0) return { zpl: null, mode: null };
  // lote: igual que print:labels con «prueba» — una fila del primer producto
  const m = ctx.modoImpresion;
  const esQr = !!(opciones && opciones.simbolo === 'qr');
  const porEtiqueta = opciones && opciones.porEtiqueta === 2 ? 2 : 1;
  const porFila = esQr ? (m.duplicate && m.halfWidth ? 2 : 1) * porEtiqueta : 1;

  return {
    zpl: formatBatchLabels(prepareItems([{ ...items[0], qty: porFila }], seleccion, m.layout || {}), m, {
      simbolo: esQr ? 'qr' : 'barras',
      porEtiqueta,
      texto: ctx.qrLayout || {},
    }),
    mode: m,
  };
}

module.exports = { renderizarZpl, armarZplVista, urlLabelary, tamanoDeZpl, LABELARY };
