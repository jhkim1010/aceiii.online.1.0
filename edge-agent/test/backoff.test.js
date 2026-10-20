// [P0-2 2026-10-20] espera creciente de reintento: nunca «se rinde», máximo 30 min.
const test = require('node:test');
const assert = require('node:assert');
const { backoffMs } = require('../src/db');

test('20s, 40s, 80s … y tope 30 min', () => {
  assert.strictEqual(backoffMs(0), 20000); // primer fallo: attempts era 0
  assert.strictEqual(backoffMs(1), 40000);
  assert.strictEqual(backoffMs(2), 80000);
  assert.strictEqual(backoffMs(7), 30 * 60 * 1000);
  assert.strictEqual(backoffMs(1000), 30 * 60 * 1000);
});

test('valores raros no rompen', () => {
  assert.strictEqual(backoffMs(undefined), 20000);
  assert.strictEqual(backoffMs(-3), 20000);
});
