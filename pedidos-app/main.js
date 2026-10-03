// VentaGO Pedidos — app de escritorio para el personal de Ventago (superadmin@app · agent@app).
//
// ★ Las tiendas siguen usando la web. Esta app sólo usa la API de plataforma:
//   /pedidos-soporte/plataforma/*  (bandeja)  ·  /admin-console/tenants (Tiendas)
// ★ Sesión: token de dispositivo (90 días, revocable) — nunca se guarda la contraseña.
//   El JWT (6 h) vive sólo en memoria del proceso principal; el renderer nunca lo ve.

const {
  app, BrowserWindow, BrowserView, Tray, Menu, ipcMain, Notification, nativeImage, safeStorage, shell, powerMonitor, session,
} = require('electron');
const path = require('path');
const fs = require('fs');
const os = require('os');
const crypto = require('crypto');
const { detectarNovedades, textoAviso, esPersonalVentago, desenvolver } = require('./src/logic');

const DEV = process.argv.includes('--dev');
const API = process.env.VENTAGO_API || (DEV ? 'http://localhost:5002/api' : 'https://newapi.coolsistema.com/api');
const WEB = DEV ? 'http://localhost:3050' : 'https://app.coolsistema.com';
const POLL_MS = 30_000;
const REFRESH_MS = 5 * 60 * 60 * 1000; // antes de las 6 h del JWT

let win = null;
let webView = null; // la web DENTRO de la ventana principal (a la derecha del riel)
let webSesion = null; // lo que web-preload.js inyecta en la próxima carga
let tray = null;
let salir = false;
let accessToken = null;
let usuario = null; // { name, roles }
let vistos = null;
let noLeidos = 0;
let pollTimer = null;
let refreshTimer = null;

// ── persistencia ────────────────────────────────────────────────────────────
const dir = () => app.getPath('userData');
const archivo = (n) => path.join(dir(), n);

function leerJson(n, def) {
  try { return JSON.parse(fs.readFileSync(archivo(n), 'utf8')); } catch { return def; }
}
function escribirJson(n, v) {
  fs.mkdirSync(dir(), { recursive: true });
  fs.writeFileSync(archivo(n), JSON.stringify(v, null, 2));
}

function prefs() {
  return { notificaciones: true, sonido: true, ...leerJson('prefs.json', {}) };
}

function deviceId() {
  const p = leerJson('device.json', {});
  if (p.id) return p.id;
  const id = `pedidos-${crypto.randomUUID()}`;
  escribirJson('device.json', { id });

  return id;
}

// el token de dispositivo va cifrado con el llavero del sistema (Keychain / DPAPI)
function guardarTokenDispositivo(t) {
  if (!t) { try { fs.unlinkSync(archivo('session.bin')); } catch { /* no había */ } return; }
  if (!safeStorage.isEncryptionAvailable()) return; // sin llavero no se guarda: se pide login
  fs.mkdirSync(dir(), { recursive: true });
  fs.writeFileSync(archivo('session.bin'), safeStorage.encryptString(t));
}
function leerTokenDispositivo() {
  try { return safeStorage.decryptString(fs.readFileSync(archivo('session.bin'))); } catch { return null; }
}

// ── HTTP ────────────────────────────────────────────────────────────────────
async function http(metodo, ruta, { body, form, auth = true, crudo = false } = {}) {
  const headers = {};
  if (auth && accessToken) headers.Authorization = `Bearer ${accessToken}`;
  let payload;
  if (form) payload = form;
  else if (body !== undefined) { headers['Content-Type'] = 'application/json'; payload = JSON.stringify(body); }
  const r = await fetch(`${API}${ruta}`, { method: metodo, headers, body: payload });
  if (crudo) return r;
  const txt = await r.text();
  let data = null;
  try { data = txt ? JSON.parse(txt) : null; } catch { data = txt; }
  if (!r.ok) {
    const msg = (data && (Array.isArray(data.message) ? data.message.join(' · ') : data.message)) || `HTTP ${r.status}`;
    const e = new Error(msg);
    e.status = r.status;
    throw e;
  }

  return desenvolver(data);
}

let refrescando = null;
async function refrescar() {
  if (refrescando) return refrescando;
  refrescando = (async () => {
    const dt = leerTokenDispositivo();
    if (!dt) throw Object.assign(new Error('sin sesión'), { status: 401 });
    try {
      const r = await http('POST', '/auth/device/refresh', { body: { deviceToken: dt }, auth: false });
      accessToken = r.accessToken;
      guardarTokenDispositivo(r.deviceToken);
      usuario = { name: r.name, roles: r.roles || [] };
      if (!esPersonalVentago(usuario.roles)) throw Object.assign(new Error('no es personal'), { status: 403 });
    } catch (e) {
      if (e.status === 401 || e.status === 403) cerrarSesion(false);
      throw e;
    }
  })().finally(() => { refrescando = null; });

  return refrescando;
}

// toda llamada autenticada: si el JWT venció, se refresca una vez y se reintenta
async function api(metodo, ruta, opts) {
  try {
    return await http(metodo, ruta, opts);
  } catch (e) {
    if (e.status !== 401) throw e;
    await refrescar();

    return http(metodo, ruta, opts);
  }
}

// ── sesión ──────────────────────────────────────────────────────────────────
async function login(usuarioTxt, password) {
  const r = await http('POST', '/auth/login', {
    body: { emailOrUsername: String(usuarioTxt || '').trim(), password: String(password || '') },
    auth: false,
  });
  if (!r || !r.accessToken) throw new Error('Usuario o contraseña incorrectos.');
  accessToken = r.accessToken;
  // ★ el registro del dispositivo sólo lo acepta el servidor para superadmin/agent sin tienda
  let reg;
  try {
    reg = await http('POST', '/auth/device/register', {
      body: { deviceId: deviceId(), deviceName: `Pedidos · ${os.hostname()}`.slice(0, 120), platform: process.platform },
    });
  } catch (e) {
    accessToken = null;
    if (e.status === 401 || e.status === 403) throw new Error('Esta app es sólo para el personal de Ventago.');
    throw e;
  }
  guardarTokenDispositivo(reg.deviceToken);
  await refrescar(); // trae nombre y roles, y valida que el dispositivo funciona
  arrancar();

  return estadoSesion();
}

function cerrarSesion(revocar = true) {
  const dt = leerTokenDispositivo();
  if (revocar && dt) http('POST', '/auth/device/revoke', { body: { deviceToken: dt }, auth: false }).catch(() => {});
  guardarTokenDispositivo(null);
  accessToken = null;
  webSesion = null;
  cerrarWebInterna();
  session.fromPartition(PARTICION_WEB).clearStorageData().catch(() => {});
  usuario = null;
  vistos = null;
  noLeidos = 0;
  clearInterval(pollTimer);
  clearInterval(refreshTimer);
  pintarBadge();
  enviar('sesion', estadoSesion());
}

function estadoSesion() {
  return usuario ? { conectado: true, nombre: usuario.name, roles: usuario.roles } : { conectado: false };
}

function arrancar() {
  clearInterval(pollTimer);
  clearInterval(refreshTimer);
  vistos = null;
  revisar();
  pollTimer = setInterval(revisar, POLL_MS);
  refreshTimer = setInterval(() => refrescar().catch(() => {}), REFRESH_MS);
  enviar('sesion', estadoSesion());
}

// ── novedades ───────────────────────────────────────────────────────────────
async function revisar() {
  if (!accessToken) return;
  try {
    const [lista, nl] = await Promise.all([
      api('GET', '/pedidos-soporte/plataforma?estado=todos'),
      api('GET', '/pedidos-soporte/plataforma/no-leidos'),
    ]);
    const r = detectarNovedades(vistos, (lista && lista.items) || []);
    vistos = r.vistos;
    noLeidos = Number(nl && nl.count) || 0;
    pintarBadge();
    const p = prefs();
    if (p.notificaciones && Notification.isSupported()) {
      for (const a of r.avisos) {
        const t = textoAviso(a);
        const n = new Notification({ title: t.titulo, body: t.cuerpo, silent: !p.sonido });
        n.on('click', () => { mostrar(); cerrarWebInterna(); enviar('abrir-pedido', a.fila.id); });
        n.show();
      }
    }
    if (r.avisos.length) enviar('bandeja-cambio');
    enviar('conexion', { ok: true });
  } catch (e) {
    enviar('conexion', { ok: false, error: e.message });
  }
}

function pintarBadge() {
  if (process.platform === 'darwin' && app.dock) app.dock.setBadge(noLeidos > 0 ? String(noLeidos) : '');
  if (process.platform !== 'darwin') app.setBadgeCount(noLeidos);
  if (tray) {
    tray.setToolTip(noLeidos > 0 ? `VentaGO Pedidos — ${noLeidos} sin leer` : 'VentaGO Pedidos');
    tray.setContextMenu(menuTray());
  }
  if (win) win.setTitle(noLeidos > 0 ? `VentaGO Pedidos — ${noLeidos} sin leer` : 'VentaGO Pedidos');
}

// ── ventana / bandeja del sistema ───────────────────────────────────────────
function crearVentana() {
  win = new BrowserWindow({
    width: 1280,
    height: 820,
    minWidth: 900,
    minHeight: 600,
    title: 'VentaGO Pedidos',
    backgroundColor: '#1a1a2e',
    icon: path.join(__dirname, 'assets/icon-512.png'),
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });
  win.loadFile(path.join(__dirname, 'renderer/index.html'));
  // cerrar = esconder (sigue avisando desde la bandeja del sistema)
  win.on('close', (e) => {
    if (!salir) { e.preventDefault(); win.hide(); }
  });
  // enlaces externos → navegador
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (/^https?:\/\//.test(url)) shell.openExternal(url);

    return { action: 'deny' };
  });
  win.webContents.on('will-navigate', (e, url) => {
    if (!url.startsWith('file://')) { e.preventDefault(); if (/^https?:\/\//.test(url)) shell.openExternal(url); }
  });
}

function mostrar() {
  if (!win) crearVentana();
  win.show();
  win.focus();
}

function menuTray() {
  const p = prefs();
  const inicio = app.getLoginItemSettings().openAtLogin;

  return Menu.buildFromTemplate([
    { label: usuario ? `VentaGO Pedidos · ${usuario.name || ''}` : 'VentaGO Pedidos', enabled: false },
    { type: 'separator' },
    { label: noLeidos > 0 ? `Abrir — ${noLeidos} sin leer` : 'Abrir', click: mostrar },
    { label: 'Notificaciones', type: 'checkbox', checked: p.notificaciones, click: (m) => escribirJson('prefs.json', { ...p, notificaciones: m.checked }) },
    { label: 'Sonido', type: 'checkbox', checked: p.sonido, click: (m) => escribirJson('prefs.json', { ...p, sonido: m.checked }) },
    { label: 'Iniciar con el sistema', type: 'checkbox', checked: inicio, click: (m) => app.setLoginItemSettings({ openAtLogin: m.checked, openAsHidden: true }) },
    { type: 'separator' },
    { label: 'Cerrar sesión', enabled: !!usuario, click: () => cerrarSesion(true) },
    { label: 'Salir', click: () => { salir = true; app.quit(); } },
  ]);
}

function crearTray() {
  let img = nativeImage.createFromPath(path.join(__dirname, 'assets/tray-icon.png'));
  if (process.platform === 'darwin') img = img.resize({ width: 16, height: 16 });
  tray = new Tray(img);
  tray.setToolTip('VentaGO Pedidos');
  tray.setContextMenu(menuTray());
  tray.on('click', mostrar);
}

function enviar(canal, dato) {
  if (win && !win.isDestroyed()) win.webContents.send(canal, dato);
}

// ── web dentro de la app ────────────────────────────────────────────────────
// [2026-10-03 usuario] «que mis empleados terminen todo dentro de la app»: legacy y factura
//   electrónica son las pantallas de la web (ya probadas), abiertas en una ventana propia que
//   entra logueada — nunca el navegador.
const PARTICION_WEB = 'persist:ventago-web';
const origenWeb = () => new URL(WEB).origin;

// Medidas del renderer (renderer/style.css): riel 56 px · barra «← Volver» 44 px
const RIEL_PX = 56;
const BARRA_PX = 44;

function ubicarWeb() {
  if (!webView || !win) return;
  const [w, h] = win.getContentSize();
  webView.setBounds({ x: RIEL_PX, y: BARRA_PX, width: Math.max(0, w - RIEL_PX), height: Math.max(0, h - BARRA_PX) });
}

function crearWebView() {
  webView = new BrowserView({
    webPreferences: {
      preload: path.join(__dirname, 'web-preload.js'),
      partition: PARTICION_WEB,
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });
  webView.setBackgroundColor('#ffffff');
  const wc = webView.webContents;
  // fuera de Ventago → navegador; dentro → la misma vista
  wc.setWindowOpenHandler(({ url }) => {
    if (url.startsWith(origenWeb())) wc.loadURL(url);
    else if (/^https?:\/\//.test(url)) shell.openExternal(url);

    return { action: 'deny' };
  });
  wc.on('will-navigate', (e, url) => {
    if (!url.startsWith(origenWeb())) { e.preventDefault(); if (/^https?:\/\//.test(url)) shell.openExternal(url); }
  });
  wc.on('page-title-updated', (_e, t) => enviar('web-titulo', t));
}

async function abrirWebInterna(ruta, tienda, titulo) {
  if (!accessToken) throw new Error('Sin sesión');
  // JWT fresco + userData: /auth/me devuelve el usuario y (a veces) un token nuevo
  const me = await api('GET', '/auth/me');
  const esSuper = (usuario?.roles || []).includes('superadmin');
  const acting = esSuper && tienda && Number.isInteger(tienda.id) ? { id: tienda.id, name: String(tienda.name || `#${tienda.id}`) } : null;
  webSesion = { token: (me && me.accessToken) || accessToken, userData: me || null, acting };

  mostrar();
  if (!webView) crearWebView();
  win.setBrowserView(webView);
  ubicarWeb();
  webView.setAutoResize({ width: true, height: true });
  enviar('web-abierta', { titulo: titulo || '', tienda: tienda && tienda.name ? tienda.name : '' });
  await webView.webContents.loadURL(`${WEB}${ruta}`);
}

function cerrarWebInterna() {
  if (win && !win.isDestroyed() && webView) win.setBrowserView(null);
  if (webView) webView.webContents.loadURL('about:blank').catch(() => {});
  enviar('web-cerrada');
}

// ── IPC (el renderer pide; el principal habla con la API) ───────────────────
// ★ lista cerrada de rutas: el renderer no puede pedir cualquier URL con nuestro token
const RUTAS = [
  /^\/pedidos-soporte\/plataforma(\?.*)?$/,
  /^\/pedidos-soporte\/plataforma\/no-leidos$/,
  /^\/pedidos-soporte\/plataforma\/\d+$/,
  /^\/pedidos-soporte\/plataforma\/\d+\/estado$/,
  /^\/pedidos-soporte\/plataforma\/\d+\/items\/\d+$/,
  /^\/pedidos-soporte\/plataforma\/\d+\/mensajes$/,
  /^\/admin-console\/tenants$/,
  /^\/admin-console\/tenants\/\d+\/errors(\?limit=\d+)?$/,
];
// /auth/me: sólo la usa abrirWebInterna (no el renderer) — por eso no está en RUTAS
const rutaOk = (r) => typeof r === 'string' && RUTAS.some((re) => re.test(r));

ipcMain.handle('sesion', () => estadoSesion());
ipcMain.handle('login', async (_e, u, p) => {
  try { return { ok: true, sesion: await login(u, p) }; } catch (e) { return { ok: false, error: e.message }; }
});
ipcMain.handle('logout', () => { cerrarSesion(true); return true; });
ipcMain.handle('api', async (_e, metodo, ruta, body) => {
  if (!['GET', 'POST', 'PATCH'].includes(metodo) || !rutaOk(ruta)) return { ok: false, error: 'Ruta no permitida' };
  try {
    const data = await api(metodo, ruta, { body });
    if (/\/plataforma\/\d+$/.test(ruta) || /\/estado$|\/items\/\d+$|\/mensajes$/.test(ruta)) setTimeout(revisar, 300);

    return { ok: true, data };
  } catch (e) { return { ok: false, error: e.message, status: e.status }; }
});
// respuesta con fotos: llegan como [{name,type,bytes}] desde el renderer
ipcMain.handle('responder', async (_e, id, texto, fotos) => {
  if (!Number.isInteger(id)) return { ok: false, error: 'id' };
  try {
    const armar = () => {
      const fd = new FormData();
      fd.append('texto', String(texto || ''));
      for (const f of (fotos || []).slice(0, 3)) {
        fd.append('fotos', new Blob([Buffer.from(f.bytes)], { type: f.type }), f.name);
      }

      return fd;
    };
    const data = await api('POST', `/pedidos-soporte/plataforma/${id}/mensajes`, { form: armar() })
      .catch(async (e) => { throw e; });
    setTimeout(revisar, 300);

    return { ok: true, data };
  } catch (e) { return { ok: false, error: e.message }; }
});
ipcMain.handle('foto', async (_e, id, mensajeId, idx) => {
  if (![id, mensajeId, idx].every(Number.isInteger)) return null;
  try {
    let r = await http('GET', `/pedidos-soporte/plataforma/${id}/mensajes/${mensajeId}/fotos/${idx}`, { crudo: true });
    if (r.status === 401) { await refrescar(); r = await http('GET', `/pedidos-soporte/plataforma/${id}/mensajes/${mensajeId}/fotos/${idx}`, { crudo: true }); }
    if (!r.ok) return null;
    const buf = Buffer.from(await r.arrayBuffer());

    return `data:${r.headers.get('content-type') || 'image/jpeg'};base64,${buf.toString('base64')}`;
  } catch { return null; }
});
ipcMain.handle('abrir-web', async (_e, ruta, tienda, titulo) => {
  if (typeof ruta !== 'string' || !/^\/[A-Za-z0-9/_?=&#.-]*$/.test(ruta)) return { ok: false, error: 'Ruta no permitida' };
  try {
    await abrirWebInterna(ruta, tienda, titulo);

    return { ok: true };
  } catch (e) { return { ok: false, error: e.message }; }
});
ipcMain.on('web-sesion', (e, origen) => {
  // ★ sólo la ventana web interna y sólo en el origen de Ventago
  e.returnValue = webView && e.sender === webView.webContents && origen === new URL(WEB).origin ? webSesion : null;
});
ipcMain.handle('cerrar-web', () => { cerrarWebInterna(); return true; });
ipcMain.handle('info', () => ({ version: app.getVersion(), api: API, dev: DEV }));

// ── arranque ────────────────────────────────────────────────────────────────
if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on('second-instance', mostrar);
  app.setName('VentaGO Pedidos');
  if (process.platform === 'win32') app.setAppUserModelId('com.coolsistema.ventago-pedidos');

  app.whenReady().then(async () => {
    if (process.platform === 'darwin' && app.dock) app.dock.setIcon(path.join(__dirname, 'assets/icon-512.png'));
    crearTray();
    const oculto = app.getLoginItemSettings().wasOpenedAsHidden || process.argv.includes('--hidden');
    crearVentana();
    if (oculto) win.hide();
    if (leerTokenDispositivo()) {
      try { await refrescar(); arrancar(); } catch { enviar('sesion', estadoSesion()); }
    }
    // al volver de suspensión, mirar enseguida
    powerMonitor.on('resume', () => setTimeout(revisar, 3000));
  });

  app.on('activate', mostrar);
  app.on('before-quit', () => { salir = true; });
  app.on('window-all-closed', (e) => e.preventDefault());
}
