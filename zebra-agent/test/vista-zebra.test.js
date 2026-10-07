/**
 * «Vista Zebra» (2026-10-07) — el ZPL que se muestra es el que se imprimiría, y el emulador
 * recibe ese ZPL con el tamaño de la etiqueta.
 * 실행: node test/vista-zebra.test.js
 */
const assert = require('assert');
const { armarZplVista, renderizarZpl, urlLabelary } = require('../src/vista-zebra');
const { formatBatchLabels, formatTestLabel, resolveMode } = require('../src/zpl-formatter');
const { prepareItems } = require('../src/price-select');

let passed = 0;
async function ok(name, fn) {
  await fn();
  passed += 1;
  console.log('  ✓', name);
}

const simple = { ...resolveMode('simple-face'), darkness: 15, speed: 4 };
const dup = { ...resolveMode('modo-duplicado'), darkness: null, speed: null };
const sel = [{ id: 1, name: 'Lista' }, { id: 2, name: 'Mayorista' }];
// modoImpresion = getPrintMode() de main: con niveles elegidos, priceCount = cantidad de niveles
const ctx = (modo) => ({
  ajustes: { darkness: 15, speed: 4 },
  modoEfectivo: modo,
  modoImpresion: { ...modo, layout: { ...modo.layout, priceCount: sel.length } },
  seleccion: sel,
  qrLayout: {},
});
const prod = (sku, qty = 5) => ({
  name: `PRODUCTO ${sku}`,
  sku,
  barcodeType: 'CODE128',
  prices: [{ priceTypeId: 2, label: 'Mayorista', amount: 900 }, { priceTypeId: 1, label: 'Lista', amount: 1000 }],
  qty,
});
const cuenta = (s, t) => s.split(t).length - 1;

(async () => {
  console.log('vista-zebra\n');

  await ok('lote: sólo el primer producto y una sola etiqueta — lo mismo que «Imprimir 1 de prueba»', () => {
    const { zpl } = armarZplVista({ tipo: 'lote', items: [prod('AAA111'), prod('BBB222')], opciones: {} }, ctx(simple));
    assert.strictEqual(cuenta(zpl, '^XA'), 1);
    assert.ok(zpl.includes('^FDAAA111') && !zpl.includes('BBB222'));
    const m = ctx(simple).modoImpresion;
    const esperado = formatBatchLabels(prepareItems([{ ...prod('AAA111'), qty: 1 }], sel, m.layout), m, {
      simbolo: 'barras', porEtiqueta: 1, texto: {},
    });
    assert.strictEqual(zpl, esperado);
  });

  await ok('lote: los precios salen en el orden de los niveles elegidos (Lista, Mayorista)', () => {
    const { zpl } = armarZplVista({ tipo: 'lote', items: [prod('AAA111')], opciones: {} }, ctx(simple));
    assert.ok(zpl.indexOf('1.000') > -1 && zpl.indexOf('900') > -1, zpl);
  });

  await ok('lote QR en doble banda con 2 por etiqueta: una fila de 4', () => {
    const { zpl } = armarZplVista({ tipo: 'lote', items: [prod('AAA111')], opciones: { simbolo: 'qr', porEtiqueta: 2 } }, ctx(dup));
    assert.strictEqual(cuenta(zpl, '^BQN'), 4);
  });

  await ok('lote QR: respeta lo guardado en la pestaña QR (sin precio → no sale el precio)', () => {
    const c = { ...ctx(simple), qrLayout: { mostrarPrecio: false } };
    const { zpl } = armarZplVista({ tipo: 'lote', items: [prod('AAA111')], opciones: { simbolo: 'qr' } }, c);
    const sinCfg = armarZplVista({ tipo: 'lote', items: [prod('AAA111')], opciones: { simbolo: 'qr' } }, ctx(simple)).zpl;
    assert.ok(sinCfg.includes('1.000'), 'sin config el precio sale');
    assert.ok(!zpl.includes('1.000'), zpl);
  });

  await ok('diseño: usa el modo de la pantalla (sin guardar) y el SKU de muestra', () => {
    const enPantalla = { ...simple, width: 480, layout: { ...simple.layout, name: { x: 33, y: 7, fontSize: 20 } } };
    const { zpl, mode } = armarZplVista({ tipo: 'diseno', mode: enPantalla, sku: 'MUESTRA9' }, ctx(simple));
    assert.ok(zpl.includes('^PW480'));
    assert.ok(zpl.includes('^FO33,7'));
    assert.ok(zpl.includes('^FDMUESTRA9'));
    assert.ok(/~SD15/.test(zpl), 'densidad de la impresora');
    assert.strictEqual(mode.width, 480);
  });

  await ok('test: exactamente la etiqueta de «Imprimir test»', () => {
    const { zpl } = armarZplVista({ tipo: 'test' }, ctx(dup));
    assert.strictEqual(zpl, formatTestLabel(dup, { darkness: 15, speed: 4 }));
  });

  await ok('sin productos o tipo desconocido: nada que mostrar (no se inventa una etiqueta)', async () => {
    assert.strictEqual(armarZplVista({ tipo: 'lote', items: [] }, ctx(simple)).zpl, null);
    assert.strictEqual(armarZplVista({ tipo: 'otro' }, ctx(simple)).zpl, null);
    const r = await renderizarZpl(null);
    assert.strictEqual(r.ok, false);
  });

  await ok('emulador: tamaño en pulgadas a 203 dpi según ^PW/^LL', () => {
    assert.ok(urlLabelary(400, 200).endsWith('/8dpmm/labels/1.97x0.98/0/'));
    assert.ok(urlLabelary(800, 200).endsWith('/3.94x0.98/0/'));
  });

  await ok('emulador: manda el ZPL tal cual y devuelve la imagen como data URL', async () => {
    let visto = null;
    const fake = async (url, o) => {
      visto = { url, o };

      return { ok: true, status: 200, headers: new Map([['content-type', 'image/png']]), arrayBuffer: async () => Uint8Array.from([137, 80, 78, 71]).buffer };
    };
    const zpl = formatTestLabel(dup, {});
    const r = await renderizarZpl(zpl, { fetchImpl: fake });
    assert.ok(r.ok);
    assert.ok(r.png.startsWith('data:image/png;base64,iVBORw'));
    assert.strictEqual(visto.o.body, zpl);
    assert.strictEqual(visto.o.method, 'POST');
    assert.ok(visto.url.includes('/3.94x0.98/0/'), visto.url);
  });

  await ok('emulador: límite, error y sin red → mensaje, nunca excepción', async () => {
    const z = formatTestLabel(simple, {});
    const r429 = await renderizarZpl(z, { fetchImpl: async () => ({ ok: false, status: 429, text: async () => '' }) });
    assert.match(r429.error, /Esperá/);
    const r400 = await renderizarZpl(z, { fetchImpl: async () => ({ ok: false, status: 400, text: async () => 'ERROR: bad' }) });
    assert.match(r400.error, /400.*bad/);
    const red = await renderizarZpl(z, { fetchImpl: async () => { throw new Error('ENOTFOUND'); } });
    assert.match(red.error, /internet/);
  });

  await ok('[codex 046] más de 15" o respuesta que no es PNG → error, no una imagen engañosa', async () => {
    let llamado = false;
    const f = async () => { llamado = true; return { ok: true, status: 200, headers: new Map([['content-type', 'image/png']]), arrayBuffer: async () => new ArrayBuffer(4) }; };
    const largo = await renderizarZpl('^XA\n^PW4000\n^LL200\n^XZ', { fetchImpl: f });
    assert.strictEqual(largo.ok, false);
    assert.strictEqual(llamado, false);
    const html = await renderizarZpl(formatTestLabel(simple, {}), {
      fetchImpl: async () => ({ ok: true, status: 200, headers: new Map([['content-type', 'text/html']]), arrayBuffer: async () => new ArrayBuffer(4) }),
    });
    assert.strictEqual(html.ok, false);
  });

  console.log(`\n${passed} ok`);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
