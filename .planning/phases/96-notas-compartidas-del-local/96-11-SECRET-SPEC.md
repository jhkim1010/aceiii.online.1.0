# 96-11 — Nota secreta (con contraseña por nota)

Pedido del usuario 2026-09-28: «nota 중에서 만든사람이 원하면 비밀 nota 기능을 줘서 그 경우에는 암호를 넣어야만 열리도록».
Decisiones (usuario vía AskUserQuestion + recomendaciones aceptadas):

| # | Decisión |
|---|---|
| S-01 | Cualquier usuario que puede crear notas puede marcarla «🔒 Nota secreta», personal o Todos. |
| S-02 | Contraseña **por nota**, elegida por el autor (mín. 4 caracteres, máx. 64). Se comunica fuera del sistema. |
| S-03 | Protección = **gate en servidor**: se guarda sólo el hash (bcrypt, el mismo paquete que ya usa auth). Sin la contraseña correcta el servidor **no envía** cuerpo, adjuntos, respuestas, reacciones ni historial de edición. (NO cifrado de contenido.) |
| S-04 | Bloqueada se ve: título, remitente, destino, importancia, fecha, 🔒. Búsqueda sólo por título para secretas (el cuerpo nunca participa del match). Toast: sólo título. |
| S-05 | Desbloqueo por respuesta: `POST /notas/:id/unlock { password }` devuelve el detalle completo en ESA respuesta. `GET /notas/:id` de una secreta devuelve `locked: true` y campos sensibles vacíos. El cliente no guarda el desbloqueo: al cambiar de nota o recargar, vuelve a pedir. Sin excepción para autor ni admin. |
| S-06 | Toda ruta que expone contenido sensible debe exigir desbloqueo: detalle, adjuntos (`/nota-adjuntos/:id` de nota secreta → exige el password en el cuerpo de un POST, o un token de desbloqueo de vida corta (≤5 min, en memoria o firmado, atado a userId+notaId, NUNCA en la URL)), historial, lecturas no (lecturas no son contenido), responder/reaccionar (exigen password o el token). Elegir el mecanismo más simple que no ponga secretos en URLs. |
| S-07 | Anti fuerza bruta: 5 intentos fallidos por (userId, notaId) → bloqueado 15 min (429). Contador persistido en DB (sobrevive a 4 workers PM2) — no en memoria. |
| S-08 | Lectura/Entendido: marcar «vista» sólo tras desbloquear; «Entendido» sólo desbloqueada. |
| S-09 | Olvido: el autor puede fijar una contraseña nueva al editar, sin conocer la anterior (resetea los contadores de intentos de esa nota). Quitar el secreto también lo puede hacer el autor. |
| S-10 | Crear/editar secreta en el mismo formulario: switch «🔒 Nota secreta» + campo contraseña + confirmación. |

## Esquema (expand, aditivo — la tabla `notas` ya existe en producción)
- `notas.is_secret BOOLEAN NOT NULL DEFAULT false`, `notas.secret_hash VARCHAR(100) NULL`, CHECK `(is_secret = false) OR (secret_hash IS NOT NULL)` agregado `NOT VALID` + `VALIDATE` aparte (W4).
- Tabla nueva `nota_unlock_attempts (id, store_id, nota_id, user_id, failed_count, locked_until, updated_at)` UNIQUE(nota_id, user_id), FK compuesta `(nota_id, store_id) → notas(id, store_id)` como las demás; owner coolsistema.
- `SET lock_timeout = '5s'`. Archivo nuevo `api-ventago/migrations/2026-09-28-c-notas-secretas.sql`.

## Reglas de proyecto que aplican
Visibilidad D-05 sigue siendo el primer filtro (una secreta invisible → 404, nunca 423/401). Tenant absoluto. `secret_hash` nunca sale en ninguna respuesta ni log. Nunca la contraseña en query string. Sequelize `@Column` con `type` explícito. Emit/IO fuera de la tx. Tests deben fallar antes del fix; mutación sobre el gate de contenido (quitar el blanqueo → test falla).
