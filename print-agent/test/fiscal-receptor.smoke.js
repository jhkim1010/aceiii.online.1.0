// [2026-10-14] Factura B/C — comprador identificado: nombre, tipo de documento y domicilio se
// imprimen SIN quitar la leyenda de la condición (Consumidor Final). Cielo PV3 #48 salió sin nombre.
// Ejecutar: node print-agent/test/fiscal-receptor.smoke.js
const assert = require('assert');
const { formatFiscalHtml } = require('../src/fiscal-formatter');

const base = {
  letra: 'B', cod: '11', number: '00003-00000048', caeVto: '2026-10-24',
  emisor: { razonSocial: 'X', cuit: '1', condIva: 'Monotributo' },
  items: [], neto: 0, iva21: 0, total: 102, ivaDiscrim: false, cae: '1', qrUrl: 'x',
};

(async () => {
  const con = await formatFiscalHtml({
    ...base,
    receptor: {
      tipo: 'consumidorFinal', condIva: 'Consumidor Final', doc: '20940612145',
      nombre: 'sung kyu mo', docLabel: 'CUIT', domicilio: 'Paso 133, Buenos Aires',
    },
  });
  assert(con.includes('Consumidor Final'), 'la leyenda de la condición sigue');
  assert(con.includes('Cliente:</span> sung kyu mo'), 'nombre del comprador');
  assert(con.includes('CUIT:</span> 20940612145'), 'tipo de documento del servidor');
  assert(con.includes('Domicilio:</span> Paso 133, Buenos Aires'), 'domicilio');

  // control: servidor viejo (sin campos nuevos) → igual que antes
  const viejo = await formatFiscalHtml({ ...base, receptor: { tipo: 'consumidorFinal', doc: '30111222' } });
  assert(viejo.includes('Consumidor Final'), 'sin condIva: «Consumidor Final» como antes');
  assert(viejo.includes('Doc:</span> 30111222'), 'sin docLabel: «Doc» como antes');
  assert(!viejo.includes('Cliente:'), 'sin nombre no se inventa');

  console.log('fiscal-receptor.smoke OK');
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
