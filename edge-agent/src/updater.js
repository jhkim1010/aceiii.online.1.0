// [2026-10-24] Guardia — actualización con confirmación (mockup 2026-10-24-guardia-actualizacion)
//
// Flujo: alguien con permiso confirma en la web → el servidor deja una «orden» → Guardia la recibe
// en la respuesta del manifest (cada ~15 s) → revisa sus condiciones → descarga, verifica sha256,
// prepara la versión nueva en una carpeta aparte (npm install ahí) → recién entonces cambia de
// versión y sale con EXIT_ACTUALIZAR para que el supervisor (src/index.js) la levante.
//
// ★ Nunca se tocan: config.json, logs/, la base local ventago_edge. Sólo se reemplazan las
//   entradas que trae el paquete (src/, package.json, node_modules/ …).
// ★ Cualquier fallo ANTES del cambio deja la versión vieja intacta y se informa al servidor.
// ★ «Al cerrar la caja»: la orden vive en el servidor, que sólo la entrega cuando no hay caja
//   abierta en la sucursal. Guardia no ve las ventas online (van directo a la nube) — lo que sí
//   ve, lo revisa acá: outbox vacía, sin venta offline reciente, nube en línea.

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const { spawn } = require('child_process');
const { createLogger } = require('./logger');

const log = createLogger('Updater');

// el supervisor reinicia el hijo inmediatamente cuando sale con este código
const EXIT_ACTUALIZAR = 75;

const URL_PERMITIDA = 'https://github.com/jhkim1010/ventago-downloads/releases/download/';
const MAX_DESCARGA_BYTES = 60 * 1024 * 1024;

// sin venta offline en los últimos 5 min = nadie está usando Guardia para vender ahora
const MIN_IDLE_SEC = 5 * 60;

// lo que el paquete NUNCA puede pisar
const PROTEGIDAS = new Set(['config.json', 'logs', '.actualizacion', '.git']);

const DIR_ESTADO = '.actualizacion';

// ── helpers puros ─────────────────────────────────────────────────────────

function parseVersion(v) {
  const m = /^(\d{1,4})\.(\d{1,4})\.(\d{1,4})(?:[-+].*)?$/.exec(String(v || '').trim());

  return m ? [Number(m[1]), Number(m[2]), Number(m[3])] : null;
}

// -1 / 0 / 1 — una versión ilegible cuenta como la más vieja
function compareVersions(a, b) {
  const pa = parseVersion(a);
  const pb = parseVersion(b);
  if (!pa && !pb) return 0;
  if (!pa) return -1;
  if (!pb) return 1;
  for (let i = 0; i < 3; i += 1) {
    if (pa[i] !== pb[i]) return pa[i] < pb[i] ? -1 : 1;
  }

  return 0;
}

// la orden viene del servidor, pero igual se valida acá: lo que se descarga se ejecuta
function validarOrden(order) {
  if (!order || typeof order !== 'object') return 'orden vacía';
  if (typeof order.id !== 'string' || !order.id) return 'orden sin id';
  if (!parseVersion(order.version)) return `versión inválida: ${order.version}`;
  if (typeof order.sha256 !== 'string' || !/^[0-9a-f]{64}$/.test(order.sha256)) return 'sha256 inválido';
  if (typeof order.url !== 'string' || !order.url.startsWith(URL_PERMITIDA)) {
    return `URL no permitida (sólo ${URL_PERMITIDA})`;
  }
  try {
    const u = new URL(order.url);
    // el texto crudo y el normalizado tienen que quedar dentro del repo (sin «..» ni %2e)
    if (/\.\.|%2e/i.test(order.url) || u.protocol !== 'https:' || u.host !== 'github.com' || !u.href.startsWith(URL_PERMITIDA)) {
      return 'URL no permitida';
    }
  } catch {
    return 'URL inválida';
  }
  if (order.mode !== 'ahora' && order.mode !== 'al_cerrar') return `modo inválido: ${order.mode}`;

  return null;
}

// condiciones que Guardia puede ver por sí misma
function revisarCondiciones({ outboxPending, idleSec, online }, minIdleSec = MIN_IDLE_SEC) {
  const motivos = [];
  if (!online) motivos.push('sin conexión con la nube (Guardia puede estar vendiendo offline)');
  if (outboxPending == null) motivos.push('no se pudo leer la outbox');
  else if (outboxPending > 0) motivos.push(`hay ${outboxPending} ventas offline sin subir`);
  if (idleSec != null && idleSec >= 0 && idleSec < minIdleSec) {
    motivos.push(`venta offline hace ${idleSec} s — se espera ${minIdleSec} s sin uso`);
  }

  return { ok: motivos.length === 0, motivos };
}

function sha256(buf) {
  return crypto.createHash('sha256').update(buf).digest('hex');
}

// ── tar.gz mínimo (sin dependencias) ──────────────────────────────────────
// Soporta lo que producen `git archive` y `npm pack`: archivos, carpetas, cabeceras pax ('x'/'g')
// y nombres largos GNU ('L'). Rechaza rutas absolutas, «..» y enlaces.

function leerOctal(buf) {
  const s = buf.toString('ascii').replace(/\0.*$/, '').trim();

  return s ? parseInt(s, 8) : 0;
}

function rutaSegura(nombre, stripPrefix) {
  let n = nombre.replace(/\\/g, '/');
  if (stripPrefix && n.startsWith(stripPrefix)) n = n.slice(stripPrefix.length);
  n = n.replace(/^\.\//, '').replace(/\/+$/, '');
  if (!n) return null;
  if (n.startsWith('/') || /^[A-Za-z]:/.test(n)) throw new Error(`ruta absoluta en el paquete: ${nombre}`);
  if (n.split('/').some((p) => p === '..')) throw new Error(`ruta con «..» en el paquete: ${nombre}`);

  return n;
}

function extraerTgz(tgz, destino, { stripPrefix = 'package/' } = {}) {
  const tar = zlib.gunzipSync(tgz);
  let off = 0;
  let nombreLargo = null;
  let paxPath = null;
  const escritos = [];

  while (off + 512 <= tar.length) {
    const h = tar.subarray(off, off + 512);
    if (h.every((b) => b === 0)) break;
    const size = leerOctal(h.subarray(124, 136));
    const tipo = String.fromCharCode(h[156] || 48);
    const datos = tar.subarray(off + 512, off + 512 + size);
    off += 512 + Math.ceil(size / 512) * 512;

    if (tipo === 'g') continue;
    if (tipo === 'x') {
      const m = /\d+ path=([^\n]*)\n/.exec(datos.toString('utf8'));
      paxPath = m ? m[1] : null;
      continue;
    }
    if (tipo === 'L') {
      nombreLargo = datos.toString('utf8').replace(/\0.*$/s, '');
      continue;
    }

    const prefijo = h.subarray(345, 500).toString('utf8').replace(/\0.*$/s, '');
    const base = h.subarray(0, 100).toString('utf8').replace(/\0.*$/s, '');
    const nombre = paxPath || nombreLargo || (prefijo ? `${prefijo}/${base}` : base);
    paxPath = null;
    nombreLargo = null;

    const rel = rutaSegura(nombre, stripPrefix);
    if (!rel) continue;
    if (PROTEGIDAS.has(rel.split('/')[0]) || rel.split('/')[0] === 'node_modules') continue;

    const abs = path.join(destino, rel);
    if (tipo === '5') {
      fs.mkdirSync(abs, { recursive: true });
    } else if (tipo === '0' || tipo === '\0' || tipo === '7') {
      fs.mkdirSync(path.dirname(abs), { recursive: true });
      fs.writeFileSync(abs, datos);
      escritos.push(rel);
    } else {
      throw new Error(`tipo de entrada no permitido en el paquete (${tipo}): ${nombre}`);
    }
  }

  return escritos;
}

// ── preparar / cambiar / volver atrás ─────────────────────────────────────

function dirEstado(root) {
  return path.join(root, DIR_ESTADO);
}

function leerEstado(root) {
  try {
    return JSON.parse(fs.readFileSync(path.join(dirEstado(root), 'estado.json'), 'utf8'));
  } catch {
    return {};
  }
}

function guardarEstado(root, estado) {
  fs.mkdirSync(dirEstado(root), { recursive: true });
  fs.writeFileSync(path.join(dirEstado(root), 'estado.json'), JSON.stringify(estado, null, 2));
}

function borrar(p) {
  fs.rmSync(p, { recursive: true, force: true });
}

function buscarNpmCli() {
  const dir = path.dirname(process.execPath);
  const cands = [
    path.join(dir, 'node_modules', 'npm', 'bin', 'npm-cli.js'), // Windows
    path.join(dir, '..', 'lib', 'node_modules', 'npm', 'bin', 'npm-cli.js'), // macOS/Linux
  ];

  return cands.find((c) => fs.existsSync(c)) || null;
}

function npmInstall(dir, timeoutMs = 10 * 60 * 1000) {
  return new Promise((resolve, reject) => {
    const cli = buscarNpmCli();
    const args = ['install', '--omit=dev', '--no-audit', '--no-fund'];
    const child = cli
      ? spawn(process.execPath, [cli, ...args], { cwd: dir, stdio: 'pipe' })
      : spawn(process.platform === 'win32' ? 'npm.cmd' : 'npm', args, { cwd: dir, stdio: 'pipe', shell: process.platform === 'win32' });
    let salida = '';
    child.stdout.on('data', (d) => { salida = (salida + d).slice(-2000); });
    child.stderr.on('data', (d) => { salida = (salida + d).slice(-2000); });
    const timer = setTimeout(() => { child.kill(); reject(new Error('npm install: tiempo agotado')); }, timeoutMs);
    child.on('error', (e) => { clearTimeout(timer); reject(e); });
    child.on('exit', (code) => {
      clearTimeout(timer);
      if (code === 0) resolve();
      else reject(new Error(`npm install salió con ${code}: ${salida.slice(-300)}`));
    });
  });
}

// arma <root>/.actualizacion/staging-<v> con el paquete y sus dependencias
async function prepararStaging(root, tgz, version, { instalar = npmInstall } = {}) {
  const staging = path.join(dirEstado(root), `staging-${version}`);
  borrar(staging);
  fs.mkdirSync(staging, { recursive: true });
  try {
    extraerTgz(tgz, staging);
    const pkg = JSON.parse(fs.readFileSync(path.join(staging, 'package.json'), 'utf8'));
    if (pkg.version !== version) throw new Error(`el paquete dice versión ${pkg.version}, se esperaba ${version}`);
    if (!fs.existsSync(path.join(staging, 'src', 'index.js'))) throw new Error('el paquete no trae src/index.js');
    await instalar(staging);
  } catch (err) {
    borrar(staging);
    throw err;
  }

  return staging;
}

// Cambia de versión moviendo entradas (rename = rápido y reversible).
// root/<e> → .actualizacion/anterior/<e>,  staging/<e> → root/<e>
// Si algo falla a mitad, deshace lo hecho y la versión vieja queda como estaba.
function cambiarVersion(root, staging, { rename = fs.renameSync } = {}) {
  const anterior = path.join(dirEstado(root), 'anterior');
  borrar(anterior);
  fs.mkdirSync(anterior, { recursive: true });

  const entradas = fs.readdirSync(staging).filter((e) => !PROTEGIDAS.has(e));
  const hechos = [];
  try {
    for (const e of entradas) {
      const actual = path.join(root, e);
      if (fs.existsSync(actual)) {
        rename(actual, path.join(anterior, e));
        hechos.push(['movida', e]);
      }
      rename(path.join(staging, e), actual);
      hechos.push(['nueva', e]);
    }
  } catch (err) {
    for (const [tipo, e] of hechos.reverse()) {
      try {
        if (tipo === 'nueva') fs.renameSync(path.join(root, e), path.join(staging, e));
        else fs.renameSync(path.join(anterior, e), path.join(root, e));
      } catch (e2) {
        log.error(`deshacer «${e}» falló:`, e2);
      }
    }
    throw new Error(`no se pudo cambiar de versión (se dejó la anterior): ${err.message}`);
  }
  borrar(staging);

  return entradas;
}

// vuelve a la versión guardada en .actualizacion/anterior (la usa el supervisor)
function volverAtras(root) {
  const anterior = path.join(dirEstado(root), 'anterior');
  if (!fs.existsSync(anterior)) return false;
  const descartada = path.join(dirEstado(root), `descartada-${Date.now()}`);
  fs.mkdirSync(descartada, { recursive: true });
  for (const e of fs.readdirSync(anterior)) {
    if (PROTEGIDAS.has(e)) continue;
    const actual = path.join(root, e);
    if (fs.existsSync(actual)) fs.renameSync(actual, path.join(descartada, e));
    fs.renameSync(path.join(anterior, e), actual);
  }
  borrar(anterior);
  borrar(descartada);

  return true;
}

// ── orquestación ──────────────────────────────────────────────────────────

const estadoRt = { enCurso: false, ultimaActividadMs: null, ultimoAviso: new Map() };

function marcarActividad() {
  estadoRt.ultimaActividadMs = Date.now();
}

function idleSec() {
  return estadoRt.ultimaActividadMs == null ? -1 : Math.floor((Date.now() - estadoRt.ultimaActividadMs) / 1000);
}

async function descargar(url, fetchImpl = fetch) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 5 * 60 * 1000);
  try {
    const res = await fetchImpl(url, { signal: ctrl.signal, redirect: 'follow' });
    if (!res.ok) throw new Error(`descarga HTTP ${res.status}`);
    const buf = Buffer.from(await res.arrayBuffer());
    if (buf.length > MAX_DESCARGA_BYTES) throw new Error(`paquete demasiado grande (${buf.length} bytes)`);

    return buf;
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Procesa una orden recibida en el manifest. deps (inyectables para tests):
 *   root, currentVersion, condiciones(): {outboxPending, idleSec, online},
 *   report(orderId, estado, detalle), fetchImpl, instalar, salir(code)
 * Devuelve el resultado ('ignorada' | 'esperando' | 'error' | 'cambiada').
 */
async function procesarOrden(order, deps) {
  const { root, currentVersion, report } = deps;
  if (estadoRt.enCurso) return 'en_curso';

  const invalida = validarOrden(order);
  if (invalida) {
    await report(order?.id, 'error', invalida);

    return 'error';
  }
  if (compareVersions(order.version, currentVersion) <= 0) return 'ignorada'; // el servidor la cierra al ver la versión

  const estado = leerEstado(root);
  if ((estado.fallidas || []).includes(order.version)) {
    await report(order.id, 'error', `la versión ${order.version} no arrancó y se volvió a ${currentVersion}`);

    return 'error';
  }

  const cond = revisarCondiciones(await deps.condiciones());
  if (!cond.ok) {
    // no inundar al servidor: un aviso por orden por minuto
    const k = `${order.id}:${cond.motivos.join('|')}`;
    if (Date.now() - (estadoRt.ultimoAviso.get(k) || 0) > 60000) {
      estadoRt.ultimoAviso.set(k, Date.now());
      await report(order.id, 'esperando', cond.motivos.join('; '));
    }

    return 'esperando';
  }

  estadoRt.enCurso = true;
  try {
    await report(order.id, 'descargando', `${currentVersion} → ${order.version}`);
    const tgz = await descargar(order.url, deps.fetchImpl);
    const hash = sha256(tgz);
    if (hash !== order.sha256) throw new Error(`sha256 no coincide (${hash.slice(0, 12)}…) — no se instala`);

    await report(order.id, 'instalando', 'npm install en carpeta aparte');
    const staging = await prepararStaging(root, tgz, order.version, { instalar: deps.instalar });

    // última revisión justo antes de cambiar (la descarga + npm install tardan)
    const cond2 = revisarCondiciones(await deps.condiciones());
    if (!cond2.ok) {
      borrar(staging);
      await report(order.id, 'esperando', cond2.motivos.join('; '));

      return 'esperando';
    }

    await report(order.id, 'aplicando', `reinicio ~1 min`);
    cambiarVersion(root, staging);
    guardarEstado(root, {
      ...estado,
      fase: 'cambiada',
      desde: currentVersion,
      hacia: order.version,
      orderId: order.id,
      at: new Date().toISOString(),
    });
    log.info(`versión cambiada ${currentVersion} → ${order.version} — saliendo para reiniciar`);
    (deps.salir || ((c) => process.exit(c)))(EXIT_ACTUALIZAR);

    return 'cambiada';
  } catch (err) {
    log.error('actualización falló (queda la versión anterior):', err);
    await report(order.id, 'error', String(err.message || err).slice(0, 480));

    return 'error';
  } finally {
    estadoRt.enCurso = false;
  }
}

module.exports = {
  EXIT_ACTUALIZAR,
  MIN_IDLE_SEC,
  DIR_ESTADO,
  compareVersions,
  validarOrden,
  revisarCondiciones,
  sha256,
  extraerTgz,
  prepararStaging,
  cambiarVersion,
  volverAtras,
  leerEstado,
  guardarEstado,
  procesarOrden,
  marcarActividad,
  idleSec,
};
