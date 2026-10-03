// [2026-10-02] Factura térmica — «Vencimiento CAE» no corre un día por la zona horaria.
//
// cae_vto llega como 'YYYY-MM-DD'. Con new Date() eso es medianoche UTC y en Argentina
// (-03) se veía el día ANTERIOR. Se fija TZ a Buenos Aires para que la prueba sea la
// misma en cualquier máquina (sin esto, en una PC en UTC el bug no se ve y el test pasa solo).
//
// Ejecutar: node print-agent/test/fiscal-fecha.smoke.js
process.env.TZ = 'America/Argentina/Buenos_Aires';
const assert = require('assert');
const { formatFiscalHtml } = require('../src/fiscal-formatter');

const base = {
  letra: 'B', cod: '06', number: '00008-00000123',
  emisor: { razonSocial: 'X', cuit: '1', condIva: 'RI' },
  receptor: { tipo: 'consumidorFinal' },
  items: [], neto: 0, iva21: 0, total: 0, ivaDiscrim: false,
  cae: '1', qrUrl: 'x',
};

(async () => {
  // control: el ambiente realmente está en -03 (si no, la prueba no prueba nada)
  assert.strictEqual(new Date('2026-10-12').getDate(), 11, 'TZ -03 activo (control)');

  const html = await formatFiscalHtml({ ...base, caeVto: '2026-10-12', fecha: '2026-10-02T21:30:00-03:00' });
  assert(html.includes('Vencimiento CAE:</span> 12/10/2026'), 'cae_vto tal cual: 12/10/2026');
  assert(!html.includes('11/10/2026'), 'nunca el día anterior');
  // la fecha de emisión (con hora) sigue en hora local: 02/10, no 03/10 (UTC)
  assert(html.includes('02/10/2026'), 'fecha de emisión local');

  console.log('fiscal-fecha.smoke OK');
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
