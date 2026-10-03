// [2026-10-02] Factura térmica — «Forma de pago» con el monto de cada medio (pedido #3 NOIX).
//
// ★ Con control: sin `pagos` la sección NO aparece (factura parcial / payload viejo).
//   Si sólo se probara el caso con pagos, «imprimir siempre la sección» también pasaría.
// ★ Escapa HTML del nombre del medio (lo escribe la tienda).
//
// Ejecutar: node print-agent/test/fiscal-pagos.smoke.js
const assert = require('assert');
const { formatFiscalHtml } = require('../src/fiscal-formatter');

const base = {
  letra: 'B', cod: '06', number: '00008-00000123', fecha: '2026-10-02T15:00:00Z',
  emisor: { razonSocial: 'NOIX SA', cuit: '20337391916', condIva: 'IVA Responsable Inscripto' },
  receptor: { tipo: 'consumidorFinal' },
  items: [{ cant: 1, desc: 'Remera', pUnit: 45000, subtotal: 45000 }],
  neto: 45000, iva21: 0, total: 45000, ivaDiscrim: false,
  cae: '75401234567890', caeVto: '2026-10-12', qrUrl: 'https://www.afip.gob.ar/fe/qr/?p=x',
};

(async () => {
  // ① con pagos: cada medio con su monto, en orden
  const html = await formatFiscalHtml({
    ...base,
    pagos: [
      { metodo: 'Efectivo', opcion: null, monto: 20000 },
      { metodo: 'Mercado Pago', opcion: 'QR', monto: 15000 },
      { metodo: 'Banco <b>', opcion: null, monto: 10000 },
    ],
  });
  assert(html.includes('Forma de pago'), 'aparece la sección');
  const i1 = html.indexOf('Efectivo');
  const i2 = html.indexOf('Mercado Pago (QR)');
  const i3 = html.indexOf('Banco &lt;b&gt;');
  assert(i1 > 0 && i2 > i1 && i3 > i2, 'los tres medios, en orden, con opción y escapados');
  assert(html.includes('20.000,00') && html.includes('15.000,00') && html.includes('10.000,00'), 'montos');
  assert(!html.includes('Banco <b>'), 'no inyecta HTML');
  assert(html.indexOf('Forma de pago') > html.indexOf('TOTAL:'), 'va debajo del TOTAL');

  // ② control: sin pagos (factura parcial o servidor viejo) → sin sección
  const sin = await formatFiscalHtml(base);
  assert(!sin.includes('Forma de pago'), 'sin pagos no hay sección');
  const vacio = await formatFiscalHtml({ ...base, pagos: [] });
  assert(!vacio.includes('Forma de pago'), 'lista vacía tampoco');

  console.log('fiscal-pagos.smoke OK');
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
