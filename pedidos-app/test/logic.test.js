const test = require('node:test');
const assert = require('node:assert');
const { detectarNovedades, textoAviso, esPersonalVentago, desenvolver } = require('../src/logic');

const f = (id, ultimo, noLeido = true) => ({ id, ultimoMensaje: ultimo, noLeido, tienda: 'NOIX', asunto: 'x' });

test('primera lectura: no avisa nada (si no, saltan todos al abrir)', () => {
  const r = detectarNovedades(null, [f(1, 'a'), f(2, 'b')]);
  assert.deepStrictEqual(r.avisos, []);
  assert.strictEqual(r.vistos.size, 2);
});

test('pedido nuevo no leído → aviso «nuevo»', () => {
  const v = detectarNovedades(null, [f(1, 'a')]).vistos;
  const r = detectarNovedades(v, [f(1, 'a'), f(2, 'b')]);
  assert.deepStrictEqual(r.avisos.map((a) => [a.tipo, a.fila.id]), [['nuevo', 2]]);
});

test('mensaje nuevo en pedido conocido → aviso «mensaje»', () => {
  const v = detectarNovedades(null, [f(1, 'a', false)]).vistos;
  const r = detectarNovedades(v, [f(1, 'b', true)]);
  assert.deepStrictEqual(r.avisos.map((a) => a.tipo), ['mensaje']);
});

test('sin cambios o ya leído → no avisa (nuestras respuestas no notifican)', () => {
  const v = detectarNovedades(null, [f(1, 'a')]).vistos;
  assert.deepStrictEqual(detectarNovedades(v, [f(1, 'a')]).avisos, []);
  assert.deepStrictEqual(detectarNovedades(v, [f(1, 'b', false)]).avisos, []);
});

test('un pedido que sale de la página y vuelve no se re-notifica como nuevo', () => {
  let v = detectarNovedades(null, [f(1, 'a'), f(2, 'b')]).vistos;
  v = detectarNovedades(v, [f(2, 'b')]).vistos;
  assert.deepStrictEqual(detectarNovedades(v, [f(1, 'a'), f(2, 'b')]).avisos, []);
});

test('textos del aviso', () => {
  assert.match(textoAviso({ tipo: 'nuevo', fila: { id: 7, tienda: 'Cielo', asunto: 'Stock' } }).titulo, /Pedido nuevo · Cielo/);
  assert.strictEqual(textoAviso({ tipo: 'mensaje', fila: { id: 7, tienda: 'Cielo', sucursal: 'Centro', asunto: 'Stock' } }).cuerpo, '#7 · Stock');
});

test('sólo personal de Ventago', () => {
  assert.ok(esPersonalVentago(['agent']));
  assert.ok(esPersonalVentago(['superadmin']));
  assert.ok(!esPersonalVentago(['admin']));
  assert.ok(!esPersonalVentago(undefined));
});

test('desenvolver { data }', () => {
  assert.deepStrictEqual(desenvolver({ data: [1] }), [1]);
  assert.deepStrictEqual(desenvolver({ items: [1], porPagina: 20 }), { items: [1], porPagina: 20 });
  assert.deepStrictEqual(desenvolver([1]), [1]);
});
