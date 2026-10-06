/**
 * [PEDIDO 10 · 2026-10-06] «Diseño del texto» de la etiqueta QR — tamaño y alineación de la
 * descripción y el precio, y dónde quedó cada texto (para arrastrarlo en la vista previa).
 * Ejecutar: node test/qr-diseno-texto.test.js
 *
 * ★ Sin las claves nuevas la etiqueta sale idéntica (lo prueban qr-texto / qr-v1029 y el
 *   cotejo byte a byte del PR). Acá: que las claves nuevas LLEGUEN al ZPL.
 */
const assert = require('assert');
const { formatQrLabel, formatQrLabelConAvisos, formatBatchLabels, zplADibujo, qrLotePreview } = require('../src/zpl-formatter');

let passed = 0;
function ok(name, cond) {
  assert.ok(cond, name);
  passed += 1;
  console.log('  ✓', name);
}

const base = { contenido: '25372379003187', name: 'REMERA OVERSIZE', price: 12999, priceLabel: 'Precio' };
const linea = (zpl, txt) => zpl.split('\n').find((l) => l.includes(`^FD${txt}`)) || '';
const alto = (l) => Number((/\^A0N,(\d+),/.exec(l) || [])[1]);
const qrMod = (zpl) => Number((/\^BQN,2,(\d+)/.exec(zpl) || [])[1]);

for (const mode of ['simple', 'doble']) {
  console.log(`\n[${mode}]`);
  const def = formatQrLabel({ ...base, layout: { mode } });

  // tamaño
  const grande = formatQrLabel({ ...base, layout: { mode, nombreFs: 24, precioFs: 30 } });
  ok(`${mode}: tamaño de la descripción = el elegido`, alto(linea(grande, 'REMERA')) === 24);
  ok(`${mode}: tamaño del precio = el elegido (independiente)`, alto(linea(grande, 'Precio')) === 30);
  ok(`${mode}: sin elegir = el tamaño de siempre`,
    alto(linea(formatQrLabel({ ...base, layout: { mode, nombreFs: '' } }), 'REMERA')) === alto(linea(def, 'REMERA')));

  // alineación
  const centro = formatQrLabel({ ...base, layout: { mode, nombreAlign: 'C', precioAlign: 'R' } });
  ok(`${mode}: Centro → ^FB …,C en la descripción`, /\^FB\d+,1,0,C\^FDREMERA/.test(centro));
  ok(`${mode}: Der → ^FB …,R en el precio`, /\^FB\d+,1,0,R\^FDPrecio/.test(centro));
  ok(`${mode}: Izq (o nada) → sin ^FB (la línea de siempre)`, !def.includes('^FB') &&
    !formatQrLabel({ ...base, layout: { mode, nombreAlign: 'L' } }).includes('^FB'));
  ok(`${mode}: valor raro de alineación → Izq`, !formatQrLabel({ ...base, layout: { mode, nombreAlign: 'X' } }).includes('^FB'));

  // cajas = donde está el ^FO del texto (la vista previa arrastra sobre esto)
  const r = formatQrLabelConAvisos({ ...base, layout: { mode, nombreX: 3, nombreY: 15, nombreAlign: 'C' } });
  const cn = r.cajas.find((c) => c.campo === 'nombre');
  const fo = /\^FO(\d+),(\d+)/.exec(linea(r.zpl, 'REMERA'));
  ok(`${mode}: caja de la descripción = su ^FO (${cn && cn.x},${cn && cn.y})`, cn && cn.x === Number(fo[1]) && cn.y === Number(fo[2]));
  ok(`${mode}: caja en mm = lo pedido (3mm,15mm → 24,120 dots desde la celda)`, cn.x - cn.offsetX === 24 && cn.y === 120);
  ok(`${mode}: sólo la 1.ª celda trae cajas`, r.cajas.length === 2 && r.cajas.every((c) => c.offsetX === 0));

  // el dibujo de la vista previa entiende ^FB
  const d = zplADibujo(centro).elementos.find((e) => e.tipo === 'texto' && e.texto.startsWith('REMERA'));
  ok(`${mode}: la vista previa lee ancho y alineación del ^FB`, d && d.alinear === 'C' && d.ancho > 0);
}

console.log('\n[doble: letras grandes achican el QR y se avisa]');
{
  const auto = formatQrLabelConAvisos({ ...base, layout: { mode: 'doble' } });
  const grande = formatQrLabelConAvisos({ ...base, layout: { mode: 'doble', nombreFs: 30, precioFs: 30 } });
  ok('el tope 12–16 se suelta si el usuario elige (30 sale 30)', alto(linea(grande.zpl, 'REMERA')) === 30);
  ok('sin elegir sigue el tope 12–16 (fuente 22 → 16)', alto(linea(formatQrLabel({ ...base, layout: { mode: 'doble', fontSize: 22 } }), 'REMERA')) === 16);
  ok('el QR se achica', qrMod(grande.zpl) < qrMod(auto.zpl));
  const av = grande.avisos.find((a) => a.campo === 'qr');
  const lado = zplADibujo(grande.zpl).elementos.find((e) => e.tipo === 'qr').lado;
  ok(`aviso «el QR bajó a X mm» (= lado real ${lado} dots / 8)`, av && av.mm === Math.round((lado / 8) * 10) / 10);
  ok('sin letras elegidas: sin aviso de QR', !auto.avisos.some((a) => a.campo === 'qr'));
  const enorme = formatQrLabelConAvisos({ ...base, layout: { mode: 'doble', nombreFs: 60, precioFs: 60 } });
  ok('QR de módulo ≤ 2 → aviso «chico» (rojo)', enorme.avisos.some((a) => a.campo === 'qr' && a.chico));
  const chica = formatQrLabelConAvisos({ ...base, layout: { mode: 'doble', nombreFs: 12, precioFs: 12 } });
  ok('letras más chicas que el automático: no achica, no avisa', !chica.avisos.some((a) => a.campo === 'qr'));
}

console.log('\n[lote «Etiquetas → Código QR» usa las claves nuevas]');
{
  const lote = formatBatchLabels(
    [{ sku: 'A1', name: 'CAMPERA', prices: [{ label: 'Precio', amount: 5000 }], qty: 1 }],
    { width: 400, height: 200 },
    { simbolo: 'qr', porEtiqueta: 2, texto: { precioFs: 28, precioAlign: 'C' } },
  );
  const lp = linea(lote, 'Precio');
  ok('lote: tamaño y alineación del precio llegan', alto(lp) === 28 && /\^FB\d+,1,0,C/.test(lp));
  const pv = qrLotePreview({ sku: 'A1', name: 'CAMPERA', prices: [{ label: 'Precio', amount: 5000 }] },
    { width: 400, height: 200 }, { simbolo: 'qr', porEtiqueta: 2, texto: { nombreX: 2 } });
  ok('vista previa del lote devuelve cajas', Array.isArray(pv.cajas) && pv.cajas.some((c) => c.campo === 'nombre' && c.x === 16));
}

console.log(`\n${passed} checks passed ✅`);
