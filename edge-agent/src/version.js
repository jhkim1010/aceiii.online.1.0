// [2026-10-24] versión de Guardia — una sola fuente: package.json (la que trae el paquete publicado)
const path = require('path');
const fs = require('fs');

let VERSION = '0.0.0';
try {
  VERSION = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'package.json'), 'utf8')).version || VERSION;
} catch {
  // sin package.json legible: se informa 0.0.0 y el servidor ofrecerá actualizar
}

module.exports = { VERSION };
