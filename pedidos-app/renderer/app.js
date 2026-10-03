// VentaGO Pedidos — pantalla. Sin frameworks: el proceso principal hace todo el HTTP.
/* global pedidos */
'use strict';

const $ = (s) => document.querySelector(s);
const ESTADOS = [
  { value: 'abierto', label: 'Abierto' },
  { value: 'en_curso', label: 'En curso' },
  { value: 'resuelto', label: 'Resuelto' },
];
const CATEGORIAS = { mejora: 'Mejora', reparacion: 'Reparar PC', correccion: 'Corrección' };
const MAX_FOTOS = 3;
const MIME_OK = ['image/jpeg', 'image/png', 'image/webp'];

let sesion = { conectado: false };
let sel = null;
let filas = [];
let adjuntos = [];
let tiendas = [];
let tiendaSel = null;

// ── utilidades ──────────────────────────────────────────────────────────────
function el(tag, attrs, ...hijos) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v == null || v === false) continue;
    if (k === 'class') e.className = v;
    // ★ CSP sin 'unsafe-inline': el atributo style se bloquea, la propiedad CSSOM no
    else if (k === 'style') e.style.cssText = v;
    else if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
    else e.setAttribute(k, v === true ? '' : v);
  }
  for (const h of hijos.flat()) if (h != null && h !== false) e.append(h instanceof Node ? h : String(h));

  return e;
}
const fecha = (iso) => (iso ? new Date(iso).toLocaleString('es-AR', { dateStyle: 'short', timeStyle: 'short' }) : '');
function hace(iso) {
  if (!iso) return '';
  const s = Math.floor((Date.now() - new Date(iso).getTime()) / 1000);
  if (s < 60) return 'recién';
  if (s < 3600) return `hace ${Math.floor(s / 60)} min`;
  if (s < 86400) return `hace ${Math.floor(s / 3600)} h`;

  return fecha(iso);
}
const money = (n) => `$${Math.round(Number(n) || 0).toLocaleString('es-AR')}`;

async function api(metodo, ruta, body) {
  const r = await pedidos.api(metodo, ruta, body);
  if (!r.ok) throw new Error(r.error || 'Error');

  return r.data;
}

// ── sesión ──────────────────────────────────────────────────────────────────
function pintarSesion(s) {
  sesion = s || { conectado: false };
  $('#vLogin').hidden = sesion.conectado;
  $('#vApp').hidden = !sesion.conectado;
  if (sesion.conectado) cargarLista();
  else setTimeout(() => $('#lUser').focus(), 50);
}

$('#fLogin').addEventListener('submit', async (e) => {
  e.preventDefault();
  $('#lErr').textContent = '';
  $('#lBtn').disabled = true;
  const r = await pedidos.login($('#lUser').value, $('#lPass').value);
  $('#lBtn').disabled = false;
  if (!r.ok) { $('#lErr').textContent = r.error; return; }
  $('#lPass').value = '';
  pintarSesion(r.sesion);
});

$('#bLogout').addEventListener('click', async () => {
  if (!confirm('¿Cerrar la sesión en esta computadora?')) return;
  await pedidos.logout();
});

// ── pestañas ────────────────────────────────────────────────────────────────
let tabActual = 'pedidos';
let webAbierta = false;

function irA(tab) {
  tabActual = tab;
  document.querySelectorAll('.rail [data-tab]').forEach((x) => x.classList.toggle('on', x.dataset.tab === tab));
  $('#tPedidos').hidden = tab !== 'pedidos';
  $('#tTiendas').hidden = tab !== 'tiendas';
  $('#tWeb').hidden = true;
}

document.querySelectorAll('.rail [data-tab]').forEach((b) => b.addEventListener('click', () => {
  // el riel siempre gana: si hay una pantalla web abierta, se cierra
  if (webAbierta) pedidos.cerrarWeb();
  irA(b.dataset.tab);
  if (b.dataset.tab === 'tiendas' && !tiendas.length) cargarTiendas();
}));

$('#bVolver').addEventListener('click', () => pedidos.cerrarWeb());

// ── bandeja ─────────────────────────────────────────────────────────────────
let tBuscar = null;
$('#q').addEventListener('input', () => { clearTimeout(tBuscar); tBuscar = setTimeout(cargarLista, 300); });
$('#fEstado').addEventListener('change', cargarLista);

async function cargarLista() {
  const p = new URLSearchParams();
  if ($('#fEstado').value) p.set('estado', $('#fEstado').value);
  if ($('#q').value.trim()) p.set('q', $('#q').value.trim());
  const qs = p.toString();
  try {
    const r = await api('GET', `/pedidos-soporte/plataforma${qs ? `?${qs}` : ''}`);
    filas = (r && r.items) || [];
  } catch (e) {
    filas = [];
    $('#lista').replaceChildren(el('div', { class: 'vacio' }, e.message));

    return;
  }
  pintarLista();
}

function pintarLista() {
  const cont = $('#lista');
  if (!filas.length) {
    cont.replaceChildren(el('div', { class: 'vacio' }, $('#fEstado').value === '' ? 'No hay pedidos pendientes.' : 'No hay pedidos.'));

    return;
  }
  cont.replaceChildren(...filas.map((f) => el('div', {
    class: `row${f.noLeido ? ' unread' : ''}${sel === f.id ? ' sel' : ''}`,
    onclick: () => abrir(f.id),
  },
  el('div', { class: 't' }, el('b', {}, [f.tienda, f.sucursal].filter(Boolean).join(' · ')), el('span', { class: 'when' }, hace(f.ultimoMensaje))),
  el('div', { class: 'as' }, `#${f.id} · ${f.asunto || ''}`),
  el('div', { class: 'm' },
    el('span', { class: `chip c-${f.estado}` }, (ESTADOS.find((x) => x.value === f.estado) || {}).label || f.estado),
    CATEGORIAS[f.categoria] || f.categoria,
    f.itemsTotal ? ` · ☑ ${f.itemsHechos || 0}/${f.itemsTotal}` : ''))));
}

async function abrir(id) {
  sel = id;
  adjuntos = [];
  pintarLista();
  $('#hilo').replaceChildren(el('div', { class: 'vacio' }, 'Cargando…'));
  try {
    const d = await api('GET', `/pedidos-soporte/plataforma/${id}`);
    pintarHilo(d);
    const f = filas.find((x) => x.id === id);
    if (f && f.noLeido) { f.noLeido = false; pintarLista(); }
  } catch (e) {
    $('#hilo').replaceChildren(el('div', { class: 'vacio' }, e.message));
  }
}

function pintarHilo(d) {
  if (!d || d.id !== sel) return;
  const items = d.items || [];
  const hechos = items.filter((i) => i.hecho).length;
  const err = el('span', { class: 'err small' });

  const estado = async (v) => {
    try { pintarHilo(await api('PATCH', `/pedidos-soporte/plataforma/${d.id}/estado`, { estado: v })); cargarLista(); } catch (e) { err.textContent = e.message; }
  };
  const tildar = async (it) => {
    try { pintarHilo(await api('PATCH', `/pedidos-soporte/plataforma/${d.id}/items/${it.id}`, { hecho: !it.hecho })); cargarLista(); } catch (e) { err.textContent = e.message; }
  };

  const cab = el('div', { class: 'th' },
    el('h2', {}, `#${d.id} · ${d.asunto || ''}`),
    el('div', { class: 'meta' }, [d.tienda, d.sucursal, d.autor, CATEGORIAS[d.categoria] || d.categoria, `creado ${fecha(d.createdAt)}`].filter(Boolean).join(' · ')),
    el('div', { class: 'acts' },
      ESTADOS.map((x) => el('button', { class: `btn${d.estado === x.value ? ' on' : ''}`, onclick: () => d.estado !== x.value && estado(x.value) }, x.label)),
      el('button', { class: 'btn', style: 'margin-left:auto', onclick: () => abrirInterna('/admin/pedidos', null, 'Pedidos (web)') }, 'Ver en la web')));

  const cuerpo = el('div', { class: 'body' });
  if (items.length) {
    cuerpo.append(el('div', { class: 'check' },
      el('div', { class: 'h' }, `Checklist · ${hechos} de ${items.length} hechos — clic para tildar`),
      el('div', { class: 'prog' }, el('i', { style: `width:${(hechos / items.length) * 100}%` })),
      items.map((it) => el('div', { class: `ck${it.hecho ? ' done' : ''}`, onclick: () => tildar(it) },
        el('i', { class: 'bx' }),
        el('div', {}, el('span', { class: 'tx' }, it.texto),
          it.hecho && it.hechoAt ? el('small', {}, `✓ ${it.hechoPor || 'Ventago'} · ${fecha(it.hechoAt)}`) : null)))));
  }
  for (const m of d.mensajes || []) {
    const fotos = el('div', { class: 'fotos' });
    for (let i = 0; i < (m.fotos || 0); i++) {
      const img = el('img', { alt: 'foto' });
      pedidos.foto(d.id, m.id, i).then((src) => { if (src) img.src = src; else img.alt = 'Foto no disponible'; });
      img.addEventListener('click', () => {
        if (!img.src) return;
        const z = el('div', { class: 'zoom', onclick: () => z.remove() }, el('img', { src: img.src }));
        document.body.append(z);
      });
      fotos.append(img);
    }
    cuerpo.append(el('div', { class: `msg${m.desdePlataforma ? ' me' : ''}` },
      el('div', { class: 'w' }, `${m.autor || (m.desdePlataforma ? 'Ventago' : 'Tienda')} · ${fecha(m.createdAt)}`),
      m.texto,
      m.fotos ? fotos : null));
  }

  // responder
  const ta = el('textarea', { placeholder: 'Respuesta para la tienda… (pegá capturas con Ctrl/Cmd+V)' });
  const adj = el('div', { class: 'adj' });
  const pintarAdj = () => adj.replaceChildren(...adjuntos.map((f, i) => el('span', {}, f.name, el('b', { onclick: () => { adjuntos.splice(i, 1); pintarAdj(); } }, '×'))));
  const sumar = (files) => {
    for (const f of files) {
      if (adjuntos.length >= MAX_FOTOS) { err.textContent = `Máximo ${MAX_FOTOS} fotos.`; break; }
      if (!MIME_OK.includes(f.type)) { err.textContent = 'Sólo fotos JPG, PNG o WEBP.'; continue; }
      if (f.size > 5 * 1024 * 1024) { err.textContent = 'Cada foto puede pesar hasta 5 MB.'; continue; }
      const nombre = !f.name || f.name === 'image.png' ? `captura-${adjuntos.length + 1}.${f.type.split('/')[1]}` : f.name;
      adjuntos.push({ file: f, name: nombre, type: f.type });
    }
    pintarAdj();
  };
  ta.addEventListener('paste', (e) => {
    const imgs = [...(e.clipboardData?.items || [])].filter((it) => it.kind === 'file' && MIME_OK.includes(it.type)).map((it) => it.getAsFile()).filter(Boolean);
    if (imgs.length) { e.preventDefault(); sumar(imgs); }
  });
  const inp = el('input', { type: 'file', accept: MIME_OK.join(','), multiple: true, hidden: true });
  inp.addEventListener('change', () => { sumar([...inp.files]); inp.value = ''; });
  const bEnviar = el('button', { class: 'btn pri' }, 'Enviar');
  bEnviar.addEventListener('click', async () => {
    if (!ta.value.trim()) { err.textContent = 'Escribí el mensaje.'; return; }
    bEnviar.disabled = true;
    err.textContent = '';
    const fotos = await Promise.all(adjuntos.map(async (a) => ({ name: a.name, type: a.type, bytes: new Uint8Array(await a.file.arrayBuffer()) })));
    const r = await pedidos.responder(d.id, ta.value.trim(), fotos);
    bEnviar.disabled = false;
    if (!r.ok) { err.textContent = r.error; return; }
    adjuntos = [];
    pintarHilo(r.data);
    cargarLista();
  });
  ta.addEventListener('keydown', (e) => { if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) bEnviar.click(); });

  const comp = el('div', { class: 'comp' },
    el('div', { class: 'r' }, ta, el('button', { class: 'btn', onclick: () => inp.click() }, '📎 Fotos'), bEnviar, inp),
    adj, err);

  $('#hilo').replaceChildren(cab, cuerpo, comp);
  cuerpo.scrollTop = cuerpo.scrollHeight;
}

// ── Tiendas ─────────────────────────────────────────────────────────────────
$('#qT').addEventListener('input', pintarTiendas);

async function cargarTiendas() {
  try {
    tiendas = (await api('GET', '/admin-console/tenants')) || [];
  } catch (e) {
    $('#tablaT').replaceChildren(el('tr', {}, el('td', {}, e.message)));

    return;
  }
  pintarTiendas();
}

function pintarTiendas() {
  const q = $('#qT').value.trim().toLowerCase();
  const lista = tiendas.filter((t) => !q || String(t.storeName || '').toLowerCase().includes(q));
  $('#tablaT').replaceChildren(
    el('tr', {}, el('th', {}, 'Tienda'), el('th', { class: 'n' }, 'Vtas hoy'), el('th', { class: 'n' }, 'Vtas mes'), el('th', {}, 'FE')),
    ...lista.map((t) => el('tr', { class: `r${tiendaSel === t.storeId ? ' sel' : ''}`, onclick: () => { tiendaSel = t.storeId; pintarTiendas(); pintarTienda(t); } },
      el('td', {}, t.storeName || `#${t.storeId}`),
      el('td', { class: 'n' }, t.salesToday ?? 0),
      el('td', { class: 'n' }, t.salesMonth ?? 0),
      el('td', {}, t.modFacturaElectronica ? '✓' : '—'))));
}

async function pintarTienda(t) {
  const esSuper = (sesion.roles || []).includes('superadmin');
  const tienda = { id: t.storeId, name: t.storeName || `#${t.storeId}` };
  const errores = el('div', { class: 'mut small' }, 'Cargando errores…');
  $('#detT').replaceChildren(
    el('div', { class: 'th' },
      el('h2', {}, t.storeName || `#${t.storeId}`),
      el('div', { class: 'meta' }, `tienda #${t.storeId} · ${t.branches} sucursal(es) · ${t.terminals} terminal(es) · última actividad ${hace(t.lastActivityAt) || '—'}`),
      el('div', { class: 'acts' },
        // [2026-10-03] todo dentro de la app: se abre una ventana propia ya logueada (no el navegador)
        esSuper ? el('button', { class: 'btn', onclick: () => abrirInterna(`/admin/tiendas/detalle/${t.storeId}`, tienda, 'Ficha de la tienda') }, 'Ficha de la tienda') : null,
        el('button', { class: 'btn pri', onclick: () => abrirInterna(esSuper ? '/configuracion/importar-legacy' : '/admin/agente', tienda, 'Importar legacy') }, 'Importar legacy'),
        el('button', { class: 'btn pri', onclick: () => abrirInterna(esSuper ? `/admin/tiendas/detalle/${t.storeId}` : '/admin/agente', tienda, 'Factura electrónica') }, 'Factura electrónica'))),
    el('div', { class: 'body' },
      el('div', { class: 'card' }, el('h3', {}, 'Uso'),
        el('div', { class: 'kv' },
          el('span', {}, 'Ventas hoy / mes'), el('span', {}, `${t.salesToday ?? 0} / ${t.salesMonth ?? 0}`),
          el('span', {}, 'Facturado mes'), el('span', {}, money(t.revenueMonth)),
          el('span', {}, 'Facturas hoy / mes'), el('span', {}, `${t.facturasToday ?? 0} / ${t.facturasMonth ?? 0}`),
          el('span', {}, 'Factura electrónica'), el('span', {}, t.modFacturaElectronica ? 'activa' : 'no'),
          el('span', {}, 'Errores 24 h'), el('span', {}, String(t.errors24h ?? 0)),
          el('span', {}, 'Managem. estimado'), el('span', {}, money(t.expectedFee)))),
      el('div', { class: 'card' }, el('h3', {}, 'Errores recientes'), errores),
      esSuper
        ? el('p', { class: 'mut small' }, `Legacy y factura electrónica se abren en una ventana de la app actuando como ${tienda.name}.`)
        : el('p', { class: 'mut small' }, 'Legacy y factura electrónica: ingresá el código de acceso que te da la tienda (se abre «Acceso a tiendas»).')));
  try {
    const errs = (await api('GET', `/admin-console/tenants/${t.storeId}/errors?limit=20`)) || [];
    if (tiendaSel !== t.storeId) return;
    errores.replaceChildren(errs.length
      ? el('table', {}, ...errs.map((x) => el('tr', {}, el('td', {}, fecha(x.createdAt)), el('td', {}, x.statusCode), el('td', {}, `${x.method || ''} ${x.path || ''}`), el('td', {}, x.message || ''))))
      : 'Sin errores recientes.');
  } catch (e) {
    errores.textContent = e.message;
  }
}

async function abrirInterna(ruta, tienda, titulo) {
  const r = await pedidos.abrirWeb(ruta, tienda, titulo);
  if (!r || !r.ok) alert(`No se pudo abrir: ${(r && r.error) || 'error'}`);
}

// ── eventos del proceso principal ───────────────────────────────────────────
pedidos.on('sesion', pintarSesion);
pedidos.on('web-abierta', (w) => {
  webAbierta = true;
  $('#tPedidos').hidden = true;
  $('#tTiendas').hidden = true;
  $('#tWeb').hidden = false;
  $('#webTit').textContent = w.titulo || '';
  $('#webSub').textContent = w.tienda ? `· ${w.tienda}` : '';
});
pedidos.on('web-cerrada', () => {
  webAbierta = false;
  irA(tabActual);
});
pedidos.on('bandeja-cambio', () => { if (sesion.conectado) cargarLista(); });
pedidos.on('abrir-pedido', (id) => {
  irA('pedidos');
  abrir(id);
});
pedidos.on('conexion', (c) => {
  const n = $('#conn');
  n.classList.toggle('off', !c.ok);
  n.title = c.ok ? 'Conectado' : `Sin conexión: ${c.error || ''}`;
  pedidos.api('GET', '/pedidos-soporte/plataforma/no-leidos').then((r) => {
    const k = r.ok ? Number(r.data && r.data.count) || 0 : 0;
    $('#badge').hidden = k === 0;
    $('#badge').textContent = k;
  });
});

pedidos.sesion().then(pintarSesion);
