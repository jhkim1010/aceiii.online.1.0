// renderer/update-banner.js — franja de actualización arriba de la ventana
// (mismo archivo en print-agent y zebra-agent)
//
// Muestra la versión instalada y el estado de la actualización:
//   al día · buscando · descargando N% · lista (botón «Actualizar ahora») · error (reintentar)
// Nunca se instala solo: sólo con «Actualizar ahora» (o «sí» en la pregunta al descargar).
(function updateBanner() {
  const api = window.electronAPI;
  if (!api || typeof api.getUpdateEstado !== 'function') return;

  const css = document.createElement('style');
  css.textContent = `
    #upd-banner { display:flex; align-items:center; gap:10px; padding:6px 12px; margin:0 0 8px;
      font-size:12px; color:#9a9cb8; background:#16162a; border:1px solid #2a2a4a; border-radius:8px; }
    #upd-banner.listo { color:#1a1a2e; background:#f5a623; border-color:#f5a623; font-weight:600; }
    #upd-banner.error { color:#ffb4a8; border-color:#5a2a2a; }
    #upd-banner .upd-txt { flex:1; min-width:0; }
    #upd-banner button { font-size:12px; padding:3px 10px; border-radius:6px; cursor:pointer;
      border:1px solid #3a3a5a; background:#22223a; color:#e0e0e0; }
    #upd-banner.listo button { background:#1a1a2e; color:#f5a623; border-color:#1a1a2e; }
    #upd-banner button:disabled { opacity:.5; cursor:default; }
  `;
  document.head.appendChild(css);

  const el = document.createElement('div');
  el.id = 'upd-banner';
  el.innerHTML = '<span class="upd-txt"></span><button type="button"></button>';
  const contenedor = document.querySelector('.container') || document.body;
  contenedor.insertBefore(el, contenedor.firstChild);

  const txt = el.querySelector('.upd-txt');
  const btn = el.querySelector('button');
  let aviso = null; // mensaje temporal tras un clic (p.ej. «hay una impresión en curso»)

  const hace = (ms) => {
    if (!ms) return '';
    const min = Math.round((Date.now() - ms) / 60000);

    return min < 1 ? ' · recién' : min < 60 ? ` · hace ${min} min` : ` · hace ${Math.round(min / 60)} h`;
  };

  const pintar = (e) => {
    if (!e) return;
    el.className = e.fase === 'listo' ? 'listo' : e.fase === 'error' ? 'error' : '';
    btn.style.display = '';
    btn.disabled = false;

    if (!e.disponible) {
      txt.textContent = `v${e.actual} · actualización automática sólo en la versión instalada de Windows`;
      btn.style.display = 'none';
    } else if (e.fase === 'listo') {
      txt.textContent = `Nueva versión v${e.nueva} lista (tenés v${e.actual}) · se instala sólo si tocás «Actualizar ahora»`;
      btn.textContent = 'Actualizar ahora';
      btn.onclick = async () => {
        btn.disabled = true;
        txt.textContent = `Instalando v${e.nueva}: se reinicia en cuanto terminen las impresiones...`;
        const r = await api.instalarUpdate();
        if (!r || !r.ok) {
          aviso = (r && r.motivo) || 'No se pudo actualizar';
          txt.textContent = aviso;
          setTimeout(() => { aviso = null; api.getUpdateEstado().then(pintar); }, 4000);
          btn.disabled = false;
        } else {
          txt.textContent = `Instalando v${e.nueva}: se reinicia en cuanto terminen las impresiones...`;
        }
      };
    } else if (e.fase === 'descargando') {
      txt.textContent = `Descargando v${e.nueva}... ${e.progreso ?? 0}% (tenés v${e.actual})`;
      btn.style.display = 'none';
    } else if (e.fase === 'buscando') {
      txt.textContent = `v${e.actual} · buscando actualización...`;
      btn.textContent = 'Buscar actualización';
      btn.disabled = true;
    } else if (e.fase === 'error') {
      txt.textContent = `v${e.actual} · no se pudo comprobar actualizaciones${hace(e.ultimaBusqueda)}`;
      btn.textContent = 'Reintentar';
      btn.onclick = () => { btn.disabled = true; api.buscarUpdate().then(pintar); };
    } else {
      txt.textContent = `v${e.actual}${e.fase === 'al-dia' ? ' · al día' + hace(e.ultimaBusqueda) : ''}`;
      btn.textContent = 'Buscar actualización';
      btn.onclick = () => { btn.disabled = true; api.buscarUpdate().then(pintar); };
    }

    if (aviso) txt.textContent = aviso;
  };

  api.getUpdateEstado().then(pintar).catch(() => {});
  if (typeof api.onUpdateEstado === 'function') api.onUpdateEstado(pintar);
})();
