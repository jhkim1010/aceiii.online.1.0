// VentaGO Pedidos — reglas puras (se prueban con `node --test`, sin Electron).

/**
 * Qué notificar entre dos lecturas de la bandeja.
 *
 * `vistos` = Map id → ultimoMensaje que ya conocíamos. `null` = primera lectura:
 *   no se notifica nada (si no, al abrir la app saltarían todos los pendientes de golpe).
 * Se notifica una fila NO LEÍDA cuando es nueva o su último mensaje cambió.
 * ★ Lo que escribe Ventago no deja la fila «no leída» (el servidor lo marca leído),
 *   así que nuestras propias respuestas no notifican.
 */
function detectarNovedades(vistos, filas) {
  const siguiente = new Map();
  const avisos = [];
  for (const f of filas || []) {
    if (f == null || f.id == null) continue;
    const marca = String(f.ultimoMensaje ?? '');
    siguiente.set(f.id, marca);
    if (vistos === null) continue;
    if (!f.noLeido) continue;
    if (!vistos.has(f.id)) {
      avisos.push({ tipo: 'nuevo', fila: f });
    } else if (vistos.get(f.id) !== marca) {
      avisos.push({ tipo: 'mensaje', fila: f });
    }
  }
  // ★ conservar lo conocido que no vino en esta página — si no, al volver a aparecer
  //   se notificaría como «nuevo» un pedido viejo.
  if (vistos) {
    for (const [id, marca] of vistos) if (!siguiente.has(id)) siguiente.set(id, marca);
  }

  return { vistos: siguiente, avisos };
}

/** Texto de la notificación del sistema. */
function textoAviso(a) {
  const f = a.fila || {};
  const tienda = [f.tienda, f.sucursal].filter(Boolean).join(' · ');
  const titulo = a.tipo === 'nuevo' ? `Pedido nuevo · ${tienda}` : `Nuevo mensaje · ${tienda}`;

  return { titulo, cuerpo: `#${f.id} · ${f.asunto ?? ''}` };
}

/** La app es sólo para el personal de Ventago. */
function esPersonalVentago(roles) {
  const r = Array.isArray(roles) ? roles : [];

  return r.includes('superadmin') || r.includes('super_admin') || r.includes('agent');
}

/** Respuesta de la API: algunas rutas envuelven en { data }. */
function desenvolver(r) {
  return r && typeof r === 'object' && !Array.isArray(r) && 'data' in r && Object.keys(r).length <= 3
    ? r.data
    : r;
}

module.exports = { detectarNovedades, textoAviso, esPersonalVentago, desenvolver };
