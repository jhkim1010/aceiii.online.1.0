// [2026-10-12] RAW ESC/POS por el spooler de Windows — los bytes que se mandan.
//
// Lo que tiene que valer: el ticket (PNG) se convierte en el MISMO tipo de comandos que el
// camino de red (que sí imprime): imagen D24 (ESC * 33), avance y corte (GS V). Y los
// bytes de imagen tienen que reflejar la tinta del PNG.
// ★ Control: un PNG en blanco da bytes de imagen todos en 0 — si el PNG con tinta también
//   diera 0, el test no estaría viendo la imagen (= «papel en blanco» que queremos evitar).
//
// Ejecutar: node print-agent/test/raw-escpos.smoke.js
const assert = require('assert');
const { PNG } = require('pngjs');
const { buildEscposImageBytes } = require('../src/printer');
const { PS_SCRIPT } = require('../src/win-raw');

const png = (ink) => {
  const p = new PNG({ width: 576, height: 48 });
  for (let y = 0; y < 48; y++) {
    for (let x = 0; x < 576; x++) {
      const i = (576 * y + x) << 2;
      const black = ink && y >= 8 && y < 40 && x >= 100 && x < 476;
      const v = black ? 0 : 255;
      p.data[i] = v; p.data[i + 1] = v; p.data[i + 2] = v; p.data[i + 3] = 255;
    }
  }

  return PNG.sync.write(p);
};

const D24 = Buffer.from([0x1b, 0x2a, 0x21]);
const CUT = Buffer.from([0x1d, 0x56]);

// bytes de imagen: lo que sigue a cada cabecera D24 (n = ancho, 3 bytes por columna)
const imageBytes = (buf) => {
  let total = 0;
  let ink = 0;
  let at = buf.indexOf(D24);
  while (at >= 0) {
    const n = buf.readUInt16LE(at + 3);
    const slice = buf.subarray(at + 5, at + 5 + n * 3);
    total += slice.length;
    for (const b of slice) if (b) ink++;
    at = buf.indexOf(D24, at + 5 + n * 3);
  }

  return { total, ink };
};

(async () => {
  const conTinta = await buildEscposImageBytes(png(true));
  const enBlanco = await buildEscposImageBytes(png(false));

  assert.ok(conTinta.indexOf(D24) >= 0, 'falta la imagen D24 (ESC * 33)');
  assert.ok(conTinta.lastIndexOf(CUT) > conTinta.lastIndexOf(D24), 'el corte (GS V) tiene que ir después de la imagen');

  const a = imageBytes(conTinta);
  const b = imageBytes(enBlanco);
  assert.strictEqual(a.total, 576 * 3 * 2, `48px de alto = 2 franjas de 24 · 576 col · 3 bytes (fue ${a.total})`);
  assert.strictEqual(b.ink, 0, 'control: PNG en blanco → imagen toda en 0');
  assert.ok(a.ink > 0, 'el PNG con tinta tiene que dar bytes de imagen distintos de 0');

  // el script RAW: datatype RAW y nombre/ruta por variables de entorno (sin inyección)
  assert.ok(PS_SCRIPT.includes('di.pDataType = "RAW"'), 'datatype RAW');
  assert.ok(PS_SCRIPT.includes('$env:VENTAGO_PRINTER_NAME') && PS_SCRIPT.includes('$env:VENTAGO_RAW_FILE'));

  console.log(`raw-escpos.smoke OK — ${conTinta.length} bytes, tinta=${a.ink}/${a.total}`);
})().catch((e) => { console.error(e); process.exit(1); });
