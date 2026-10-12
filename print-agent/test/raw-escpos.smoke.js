// [2026-10-12] RAW ESC/POS por el spooler de Windows — los bytes que se mandan.
//
// Tiene que valer:
//  - imagen como RASTER (GS v 0), no ESC * 33: con D24 la impresora frena en cada franja de
//    24 puntos y sale «como matricial» (Shaple, 2026-10-12)
//  - bloques de a 256 filas como máximo, todas las filas del PNG presentes
//  - los bytes de imagen reflejan la tinta del PNG
//  - termina con avance + corte (GS V)
// ★ Control: un PNG en blanco da bytes de imagen todos en 0 — si el PNG con tinta también
//   diera 0, el test no estaría viendo la imagen (= el «papel en blanco» que queremos evitar).
//
// Ejecutar: node print-agent/test/raw-escpos.smoke.js
const assert = require('assert');
const { PNG } = require('pngjs');
const { buildEscposImageBytes } = require('../src/printer');
const { PS_SCRIPT } = require('../src/win-raw');

const W = 576;
const png = (h, ink) => {
  const p = new PNG({ width: W, height: h });
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < W; x++) {
      const i = (W * y + x) << 2;
      const black = ink && y >= 8 && y < h - 8 && x >= 100 && x < 476;
      const v = black ? 0 : 255;
      p.data[i] = v; p.data[i + 1] = v; p.data[i + 2] = v; p.data[i + 3] = 255;
    }
  }

  return PNG.sync.write(p);
};

const GSV0 = Buffer.from([0x1d, 0x76, 0x30, 0x00]);
const D24 = Buffer.from([0x1b, 0x2a, 0x21]);
const CUT = Buffer.from([0x1d, 0x56]);

const bloques = (buf) => {
  const out = [];
  let at = buf.indexOf(GSV0);
  while (at >= 0) {
    const xBytes = buf.readUInt16LE(at + 4);
    const rows = buf.readUInt16LE(at + 6);
    const data = buf.subarray(at + 8, at + 8 + xBytes * rows);
    out.push({ xBytes, rows, ink: data.reduce((n, b) => n + (b ? 1 : 0), 0), len: data.length });
    at = buf.indexOf(GSV0, at + 8 + xBytes * rows);
  }

  return out;
};

(async () => {
  const conTinta = await buildEscposImageBytes(png(600, true));
  const enBlanco = await buildEscposImageBytes(png(600, false));

  assert.strictEqual(conTinta.indexOf(D24), -1, 'no tiene que usar ESC * 33 (sale como matricial)');
  const b = bloques(conTinta);
  assert.deepStrictEqual(b.map((x) => x.rows), [256, 256, 88], 'bloques de 256 filas, todas las filas');
  assert.ok(b.every((x) => x.xBytes === W / 8 && x.len === x.xBytes * x.rows), 'ancho 72 bytes y datos completos');
  assert.ok(b.reduce((n, x) => n + x.ink, 0) > 0, 'el PNG con tinta tiene que dar bytes distintos de 0');
  assert.strictEqual(bloques(enBlanco).reduce((n, x) => n + x.ink, 0), 0, 'control: PNG en blanco → todo 0');
  assert.ok(conTinta.lastIndexOf(CUT) > conTinta.lastIndexOf(GSV0), 'el corte va después de la imagen');
  assert.deepStrictEqual([...conTinta.subarray(0, 2)], [0x1b, 0x40], 'empieza con ESC @');

  // el script RAW: datatype RAW y nombre/ruta por variables de entorno (sin inyección)
  assert.ok(PS_SCRIPT.includes('di.pDataType = "RAW"'), 'datatype RAW');
  assert.ok(PS_SCRIPT.includes('$env:VENTAGO_PRINTER_NAME') && PS_SCRIPT.includes('$env:VENTAGO_RAW_FILE'));

  console.log(`raw-escpos.smoke OK — ${conTinta.length} bytes, bloques ${b.map((x) => x.rows).join('+')}`);
})().catch((e) => { console.error(e); process.exit(1); });
