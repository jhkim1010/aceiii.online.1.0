// [P0-3 2026-10-20 CODEX] hash estable del cuerpo de una venta: claves ordenadas (el mismo cobro
//   reenviado da el mismo hash aunque cambie el orden de los campos).
const crypto = require('crypto');

function canonico(v) {
  if (Array.isArray(v)) return `[${v.map(canonico).join(',')}]`;
  if (v && typeof v === 'object') {
    return `{${Object.keys(v)
      .sort()
      .map((k) => `${JSON.stringify(k)}:${canonico(v[k])}`)
      .join(',')}}`;
  }

  return JSON.stringify(v === undefined ? null : v);
}

function hashCuerpo(v) {
  return crypto.createHash('sha256').update(canonico(v)).digest('hex');
}

module.exports = { hashCuerpo, canonico };
