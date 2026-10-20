// [P0-3] misma venta → mismo hash (orden de claves no importa); otra venta → otro hash.
const test = require('node:test');
const assert = require('node:assert');
const { hashCuerpo } = require('../src/body-hash');

test('el orden de las claves no cambia el hash', () => {
  assert.strictEqual(hashCuerpo({ a: 1, b: [{ x: 1, y: 2 }] }), hashCuerpo({ b: [{ y: 2, x: 1 }], a: 1 }));
});

test('otra venta (otro monto) → otro hash', () => {
  assert.notStrictEqual(hashCuerpo({ totalAmount: 100 }), hashCuerpo({ totalAmount: 101 }));
});
