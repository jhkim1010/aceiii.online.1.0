// [2026-10-24] actualización de Guardia — comparación de versiones, validación de la orden,
// condiciones, extracción segura y el cambio de versión (con fallo a mitad → queda la vieja).
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const zlib = require('zlib');
const u = require('../src/updater');

const SHA = 'a'.repeat(64);
const URL_OK = 'https://github.com/jhkim1010/ventago-downloads/releases/download/guardia-latest/guardia-0.3.0.tgz';
const orden = (o = {}) => ({ id: 'o1', version: '0.3.0', url: URL_OK, sha256: SHA, mode: 'ahora', ...o });

function tmp() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'guardia-upd-'));
}

// tar ustar mínimo para los tests (lo mismo que produce git archive, sin pax)
function tarEntry(name, data, tipo = '0') {
  const h = Buffer.alloc(512);
  h.write(name, 0, 100, 'utf8');
  h.write('0000644\0', 100);
  h.write('0000000\0', 108);
  h.write('0000000\0', 116);
  h.write(data.length.toString(8).padStart(11, '0') + '\0', 124);
  h.write('00000000000\0', 136);
  h.write('        ', 148);
  h.write(tipo, 156);
  h.write('ustar\0', 257);
  h.write('00', 263);
  let sum = 0;
  for (const b of h) sum += b;
  h.write(sum.toString(8).padStart(6, '0') + '\0 ', 148);
  const pad = Buffer.alloc(Math.ceil(data.length / 512) * 512 - data.length);

  return Buffer.concat([h, data, pad]);
}

function tgz(files) {
  const parts = Object.entries(files).map(([n, c]) => tarEntry(n, Buffer.from(c)));

  return zlib.gzipSync(Buffer.concat([...parts, Buffer.alloc(1024)]));
}

test('compareVersions', () => {
  assert.strictEqual(u.compareVersions('0.3.0', '0.2.0'), 1);
  assert.strictEqual(u.compareVersions('0.2.0', '0.10.0'), -1);
  assert.strictEqual(u.compareVersions('1.0.0', '1.0.0'), 0);
  assert.strictEqual(u.compareVersions('basura', '0.0.1'), -1);
  assert.strictEqual(u.compareVersions('0.3.0-beta', '0.3.0'), 0);
});

test('validarOrden: sólo https de github.com/jhkim1010/ventago-downloads y sha256 de 64 hex', () => {
  assert.strictEqual(u.validarOrden(orden()), null);
  assert.match(u.validarOrden(orden({ url: 'http://github.com/jhkim1010/ventago-downloads/releases/download/x.tgz' })), /URL/);
  assert.match(u.validarOrden(orden({ url: 'https://github.com/otro/repo/releases/download/x.tgz' })), /URL/);
  assert.match(u.validarOrden(orden({ url: 'https://github.com.evil.io/jhkim1010/ventago-downloads/releases/download/x' })), /URL/);
  assert.match(u.validarOrden(orden({ url: `${URL_OK.replace('guardia-latest/', '')}../../x` })), /URL/);
  assert.match(u.validarOrden(orden({ sha256: 'ABC' })), /sha256/);
  assert.match(u.validarOrden(orden({ version: 'x' })), /versión/);
  assert.match(u.validarOrden(orden({ mode: 'ya' })), /modo/);
  assert.ok(u.validarOrden(null));
});

test('revisarCondiciones', () => {
  assert.deepStrictEqual(u.revisarCondiciones({ outboxPending: 0, idleSec: -1, online: true }), { ok: true, motivos: [] });
  assert.strictEqual(u.revisarCondiciones({ outboxPending: 0, idleSec: 900, online: true }).ok, true);
  const r = u.revisarCondiciones({ outboxPending: 12, idleSec: 30, online: false });
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.motivos.length, 3);
  assert.match(r.motivos.join(), /12 ventas offline/);
  assert.strictEqual(u.revisarCondiciones({ outboxPending: null, idleSec: -1, online: true }).ok, false);
});

test('extraerTgz: quita package/, salta config.json/logs/node_modules, rechaza «..»', () => {
  const d = tmp();
  const escritos = u.extraerTgz(
    tgz({ 'package/package.json': '{}', 'package/src/a.js': 'x', 'package/config.json': 'PISA', 'package/logs/l': 'x', 'package/node_modules/m/i.js': 'x' }),
    d,
  );
  assert.deepStrictEqual(escritos.sort(), ['package.json', 'src/a.js']);
  assert.ok(!fs.existsSync(path.join(d, 'config.json')));
  assert.throws(() => u.extraerTgz(tgz({ 'package/../fuera.js': 'x' }), tmp()), /«\.\.»/);
  assert.throws(() => u.extraerTgz(tgz({ '/etc/x': 'x' }), tmp()), /absoluta/);
});

function instalacionVieja() {
  const root = tmp();
  fs.mkdirSync(path.join(root, 'src'));
  fs.writeFileSync(path.join(root, 'src', 'index.js'), 'viejo');
  fs.writeFileSync(path.join(root, 'package.json'), JSON.stringify({ version: '0.2.0' }));
  fs.mkdirSync(path.join(root, 'node_modules'));
  fs.writeFileSync(path.join(root, 'node_modules', 'VIEJO'), '1');
  fs.writeFileSync(path.join(root, 'config.json'), 'secreto');
  fs.mkdirSync(path.join(root, 'logs'));

  return root;
}

const paquete030 = () => tgz({ 'package/package.json': JSON.stringify({ version: '0.3.0' }), 'package/src/index.js': 'nuevo' });

test('prepararStaging + cambiarVersion: cambia, guarda la anterior, no toca config.json/logs; volverAtras restaura', async () => {
  const root = instalacionVieja();
  const staging = await u.prepararStaging(root, paquete030(), '0.3.0', {
    instalar: async (dir) => fs.mkdirSync(path.join(dir, 'node_modules')),
  });
  u.cambiarVersion(root, staging);
  assert.strictEqual(fs.readFileSync(path.join(root, 'src', 'index.js'), 'utf8'), 'nuevo');
  assert.strictEqual(fs.readFileSync(path.join(root, 'config.json'), 'utf8'), 'secreto');
  assert.ok(fs.existsSync(path.join(root, 'logs')));
  assert.strictEqual(fs.readFileSync(path.join(root, '.actualizacion', 'anterior', 'src', 'index.js'), 'utf8'), 'viejo');
  assert.ok(!fs.existsSync(staging));

  assert.strictEqual(u.volverAtras(root), true);
  assert.strictEqual(fs.readFileSync(path.join(root, 'src', 'index.js'), 'utf8'), 'viejo');
  assert.strictEqual(JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8')).version, '0.2.0');
});

test('fallo de npm install (antes del cambio) → staging borrado, versión vieja intacta', async () => {
  const root = instalacionVieja();
  await assert.rejects(
    u.prepararStaging(root, paquete030(), '0.3.0', { instalar: async () => { throw new Error('npm roto'); } }),
    /npm roto/,
  );
  assert.strictEqual(fs.readFileSync(path.join(root, 'src', 'index.js'), 'utf8'), 'viejo');
  assert.ok(!fs.existsSync(path.join(root, '.actualizacion', 'staging-0.3.0')));
});

test('paquete con otra versión adentro → rechazado', async () => {
  const root = instalacionVieja();
  await assert.rejects(u.prepararStaging(root, paquete030(), '0.4.0', { instalar: async () => {} }), /se esperaba 0.4.0/);
});

test('fallo a mitad del cambio (rename) → deshace y queda la versión vieja', async () => {
  const root = instalacionVieja();
  const staging = await u.prepararStaging(root, paquete030(), '0.3.0', {
    instalar: async (dir) => fs.mkdirSync(path.join(dir, 'node_modules')),
  });
  let n = 0;
  const renameQueFalla = (a, b) => {
    n += 1;
    // node_modules y package.json ya cambiados; falla al mover src
    if (n === 5) throw new Error('EBUSY simulado');
    fs.renameSync(a, b);
  };
  assert.throws(() => u.cambiarVersion(root, staging, { rename: renameQueFalla }), /se dejó la anterior/);
  assert.strictEqual(fs.readFileSync(path.join(root, 'src', 'index.js'), 'utf8'), 'viejo');
  assert.strictEqual(JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8')).version, '0.2.0');
  assert.ok(fs.existsSync(path.join(root, 'node_modules', 'VIEJO')));
  assert.ok(fs.existsSync(path.join(root, '.actualizacion', 'staging-0.3.0', 'package.json')));
});

function depsBase(root, extra = {}) {
  const reportes = [];

  return {
    reportes,
    deps: {
      root,
      currentVersion: '0.2.0',
      condiciones: async () => ({ outboxPending: 0, idleSec: -1, online: true }),
      report: async (id, estado, detalle) => reportes.push([estado, detalle]),
      instalar: async (dir) => fs.mkdirSync(path.join(dir, 'node_modules')),
      salir: () => {},
      ...extra,
    },
  };
}

test('procesarOrden: sha256 que no coincide → error, nada cambia', async () => {
  const root = instalacionVieja();
  const buf = paquete030();
  const { deps, reportes } = depsBase(root, { fetchImpl: async () => new Response(buf) });
  assert.strictEqual(await u.procesarOrden(orden(), deps), 'error');
  assert.match(reportes.at(-1)[1], /sha256 no coincide/);
  assert.strictEqual(fs.readFileSync(path.join(root, 'src', 'index.js'), 'utf8'), 'viejo');
});

test('procesarOrden: condiciones no cumplidas → esperando (sin descargar)', async () => {
  const root = instalacionVieja();
  let descargas = 0;
  const { deps, reportes } = depsBase(root, {
    condiciones: async () => ({ outboxPending: 3, idleSec: -1, online: true }),
    fetchImpl: async () => { descargas += 1; },
  });
  assert.strictEqual(await u.procesarOrden(orden({ id: 'o-esp' }), deps), 'esperando');
  assert.strictEqual(descargas, 0);
  assert.deepStrictEqual(reportes.map((r) => r[0]), ['esperando']);
});

test('procesarOrden: todo bien → cambia y sale con 75', async () => {
  const root = instalacionVieja();
  const buf = paquete030();
  let codigo = null;
  const { deps, reportes } = depsBase(root, {
    fetchImpl: async () => new Response(buf),
    salir: (c) => { codigo = c; },
  });
  assert.strictEqual(await u.procesarOrden(orden({ sha256: u.sha256(buf) }), deps), 'cambiada');
  assert.strictEqual(codigo, u.EXIT_ACTUALIZAR);
  assert.deepStrictEqual(reportes.map((r) => r[0]), ['descargando', 'instalando', 'aplicando']);
  assert.strictEqual(fs.readFileSync(path.join(root, 'src', 'index.js'), 'utf8'), 'nuevo');
  assert.strictEqual(u.leerEstado(root).fase, 'cambiada');
});

test('procesarOrden: versión marcada como fallida → error sin reintentar; versión igual → ignorada', async () => {
  const root = instalacionVieja();
  u.guardarEstado(root, { fallidas: ['0.3.0'] });
  const { deps, reportes } = depsBase(root);
  assert.strictEqual(await u.procesarOrden(orden(), deps), 'error');
  assert.match(reportes[0][1], /no arrancó/);
  assert.strictEqual(await u.procesarOrden(orden({ version: '0.2.0' }), deps), 'ignorada');
});
