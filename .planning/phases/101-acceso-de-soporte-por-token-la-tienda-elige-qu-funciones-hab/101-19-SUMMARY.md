---
phase: 101-acceso-de-soporte-por-token-la-tienda-elige-qu-funciones-hab
plan: 19
status: COMPLETE — aprobado por el usuario («승인» 2026-10-09) y desplegado
---

# Phase 101 Plan 19: Despliegue a producción — paquete de aprobación

## Medición (sólo lectura, producción 5434)
- 2026-10-09 08:25 ART — usuarios activos (15 min, `active_sessions`): **1**
- 2026-10-09 08:26 ART — usuarios activos: **1** → regla diurna: ≤ 5, se puede (el usuario: «5명 이하면 진행»).
  Se vuelve a medir inmediatamente antes de cada paso.

## Estado actual en producción (leído)
| Consulta | Valor |
|---|---|
| CHECK `agent_action_policies_action_check` | `cert, usuarios_terminales, legacy` |
| `agent_action_policies` | 3 filas (1 por acción vieja) |
| agentes de plataforma (rol `agent` sin tienda) | 1 |
| `support_sessions` | 0 filas; columnas `grant_id/viewer_claim/viewer_seen_at`: 0 de 3 |
| `support_access_grants` | existe |
| roles `admin` de tienda | 24 |
| módulo `token-soporte` / función `generar-token-soporte` | 0 / 0 |
| app `admin` | 1 |
| índices únicos para los `ON CONFLICT` (role_functions, role_function_actions, agent_action_policies) | presentes |

Local 5432: las tres migraciones ya están aplicadas (CHECK con `sesion_remota`, `grant_id`, módulo).

## filas previstas por sentencia
| Migración | Sentencia | Filas previstas |
|---|---|---|
| b `2026-10-08-b-agente-alcances-ver.sql` | DROP/ADD CHECK (valida 3 filas) | 0 escritas |
| b | INSERT políticas (1 agente × 5 alcances) | **5** |
| c `2026-10-08-c-support-sessions-agente.sql` | 3 × ADD COLUMN nullable (tabla con 0 filas) | 0 |
| d `2026-10-08-d-menu-token-soporte.sql` | INSERT módulo | **1** |
| d | INSERT función | **1** |
| d | INSERT role_functions (roles admin de tienda) | **24** |
| d | INSERT role_function_actions (`read`) | **24** |
| e `2026-10-09-a-token-soporte-max-1h.sql` | DROP/ADD CHECK `support_tokens.grant_minutes IN (30,60,120)` (valida 8 filas) | 0 escritas |

Todas con `SET lock_timeout = '5s'`, `--single-transaction`, `ON_ERROR_STOP=1`. d sólo otorga (no revoca) → el caché de
permisos no puede dar «de más»; el deploy recrea el contenedor.

## Orden
1. b → c → e en 5434 (antes de la API: `SupportSession` gana columnas, `crearAgente` inserta 8 alcances,
   y la API nueva guarda `grant_minutes = 60`).
2. push api-ventago (29 commits) → Jenkins `api-new-coolsistema`, verificar por SHA, contenedor recreado.
3. d en 5434 justo antes del front.
4. push ventago-app (17 commits) → `front-coolsistema`, por SHA, `ventagoapp` recreado; puntero en la raíz.
5. Humo.

## Compatibilidad API nueva × front viejo (verificado con `git show origin/main:` del front)
| Cambio | Qué ve el front viejo | ¿Seguro API primero? |
|---|---|---|
| ① 403 con `code` | `api.service` viejo avisa ante cualquier 403 con `x-agent-grant`; sólo llama handlers cert/usuarios_terminales/legacy, cuyas marcas no cambian | sí |
| ② eventos agrupados | la tabla vieja lee `at`, `tipo`, `alcance` — se conservan | sí |
| ③ código sin `uso`/`aviso` | `codigo.uso &&` / `codigo.aviso &&` — opcionales | sí |
| ④ `/support-token/*` | el módulo `support-token` sigue en la API hasta 101-20 | sí |
| ⑤ redacción `confirmToken`/`Branch.apiKey` | ningún consumidor (101-04) | sí |
| ⑥ columnas nuevas de `support_sessions` y 8 alcances | por eso b y c van antes del push de la API | sí, con b/c antes |
| ⑦ seed d con front viejo | el ítem «Token de soporte» apuntaría a `/admin/token-soporte`, que el front viejo no tiene → d justo antes del push del front; ventana medida | ventana de minutos |
| ⑧ endpoints `/acceso-ventago/*` | `@Auth(admin)` por rol, no dependen del seed d | sí |
| ⑨ duración máx. 1 h (pedido 2026-10-09) | el front viejo ofrece «2 horas» → la API nueva responde 400 si alguien lo elige entre el deploy de la API y el del front (default 30 min funciona) | ventana de minutos |
| rollback | volver primero el front, después la API | — |

**La API sale primero; el front después; el 410 al final (101-20).**

## CODEX (revisión manual previa al push, 2026-10-09)
No había informes automáticos para los commits de la phase (el hook no corre). Se revisó el diff completo en 6 partes:

| Parte | Resultado |
|---|---|
| A guards / auth | sin bloqueantes |
| B sesión remota (support) | sin bloqueantes |
| C agente · migraciones · secretos | sin bloqueantes |
| D1 front núcleo | **BLOQUEANTE** — al cambiar de código (tienda A → B) la caché SWR (clave = URL, 5 min) podía mostrar un instante datos de A bajo el banner de B → **corregido** app `a326eedf` (entrar = recarga completa) |
| D2 front sesión remota | sin bloqueantes |
| D3 front pantallas | **BLOQUEANTE** — `ver_admin` abre `/sucursales/:id/web` y recibe `channelKey` + `wcConsumerKey` (el secreto no sale; CODEX lo llamó «credenciales completas», es exagerado, pero contradice «no ve claves») → **corregido** api `1f43597e` (null para agentes; spec en el controlador, mutante muere) |

## Agregado en este plan
- api `8f791690` + app `a0cda254` + migración e: **Token de soporte máx. 1 hora** (30 min · 1 h). El canje recorta a 1 h un
  código generado con 2 h antes del cambio. Spec del canje en el servicio; mutante «el canje respeta 120» muere.
  Migración e aplicada en local 5432.

## Ejecución en producción (2026-10-09)
| Hora ART | Usuarios activos (15 min) | Paso | Resultado |
|---|---|---|---|
| 09:24 | 0 | b | CHECK nuevo + INSERT **5** políticas |
| 09:24 | 0 | c | 3 columnas nullable |
| 09:24 | 0 | e | CHECK `grant_minutes IN (30,60,120)` |
| — | — | comparación local × producción (`support_sessions` + 2 CHECK) | **iguales** |
| 09:24 | 0 | push api `87a5401a..8f791690` | Jenkins `api-new-coolsistema` **#1114 SUCCESS** (SHA en el log), blue/green → 5003, `api_ventago` healthy |
| 09:28:13 | 0 | d | módulo 1 · función 1 · role_functions **24** · acciones **24** |
| 09:28:23 | — | push app `e404b483..a0cda254` | Jenkins `front-coolsistema` **#1039 SUCCESS**, `ventagoapp` recreado 12:32 UTC |

Ventana del ítem de menú sin página (d → front nuevo): 12:28:16 → ~12:33 UTC (≈ 5 min).

Humo: `/api/health` 200; `/acceso-ventago/opciones`, `/agente/tienda/contexto`, `/integrations/wp/channels` → 401 sin token
(rutas montadas, no 404); front `/login` 200; `_buildManifest` incluye `admin/token-soporte`, su chunk 200.
No verificado: humo con token de admin/agente en producción (no hay credenciales de prueba en producción); la opción
«1 hora» se verificó en build de producción local justo antes (código 250 → `grant_minutes = 60`, grant 113 de 60 min,
entrar a pantallas = recarga completa).

Puntero de submódulo en la raíz: **no** se tocó (regla del proyecto: no se stagean punteros en la raíz).

## Pedido #23 (israel, coolsistema, 09:25 ART)
Captura: front VIEJO, Configuración › «Acceso de Ventago» → «Forbidden resource». israel es **gerente**; generar códigos
es sólo admin (D-17). El front viejo mostraba la pantalla a gerente (callejón sin salida) — con el front nuevo el menú
sólo existe para admin. No lo causó este deploy (09:25 fue antes de cambiar la API y el CHECK nuevo acepta lo viejo).
