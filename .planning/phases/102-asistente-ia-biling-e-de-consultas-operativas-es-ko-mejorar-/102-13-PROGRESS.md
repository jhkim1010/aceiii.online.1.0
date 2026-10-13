# 102-13 Progress

2026-10-13 09:42 ART — Task 1 detenida antes del push por 2 commits ajenos (api a2428263, app 7200d69f).
2026-10-13 ~09:56 ART — El usuario aprobo desplegarlos juntos (par: api primero, app despues).

## Task 1 (push + builds)

| Paso | Detalle |
|---|---|
| Usuarios activos antes del push api | 1 (09:56 ART, <=5) |
| API push | HEAD 14598fd8 (22 commits, incl. a2428263, 800a3d35, 14598fd8) |
| Build api-new-coolsistema | #1134 SUCCESS (el log contiene 14598fd8); blue/green, activo puerto 5003, api_ventago recreado 13:01 UTC |
| Logs API | sin errores Sequelize meta/knowledge_refuerzos ni DI KnowledgeRefuerzo |
| POST /api/users/1/resetear-clave sin token | 401 |
| POST /api/chat/message/stream sin token | 401 |
| Usuarios activos antes del push app | 1 (~10:03 ART) |
| App push | HEAD a7027f6f (6 commits, incl. 7200d69f) |
| Build front-coolsistema | #1068 SUCCESS (log contiene a7027f6f); ventagoapp recreado 13:08 UTC |
| Chunks _next/static | 200 |

## Task 1 pasos 5 y 6 — PENDIENTES (bloqueo)

Las cuentas de prueba de la memoria (perm.*) existen SOLO en la base local; en produccion no hay
cuenta de prueba ni credenciales disponibles, y crear una seria DML en produccion (no autorizado).
Faltan: curl -N de streaming con marcas de tiempo (>=16h ART), 403 de /chat/refuerzos/preview y
GET /chat/refuerzos con cuenta no superadmin. Se necesita una cuenta de produccion (no superadmin)
o que el usuario lo corrobore.

## Task 1 paso 7
ROADMAP.md: Phase 102 con 16 planes listados (102-16-PLAN.md presente).

## Task 2 (launchd)

- ~/.config/ventago/asistente-fusion.env (600, fuera del repo); token/chat tomados por lectura del .env de produccion (mismo que usa el bot de Pedidos).
- plist copiado a ~/Library/LaunchAgents y cargado con launchctl bootstrap (rc 0); 22:00 diario + RunAtLoad; primer RunAtLoad salio con exit 0 (hora <16, se salto solo).
- Dry-run contra produccion (FORZAR_HORA=22 --dry-run): "0 refuerzos activos; sale en silencio", exit 0; `git status -- manuales/` vacio.
- --probar-aviso: exit 0 (curl -f). getChat del grupo -5247883057: ok:true.

## Task 3
Checkpoint human-verify pendiente (despues de las 16h ART). SUMMARY no creado.
