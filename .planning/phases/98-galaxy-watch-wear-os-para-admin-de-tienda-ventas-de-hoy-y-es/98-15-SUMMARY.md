---
phase: 98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es
plan: 15
subsystem: ui
tags: [nextjs, mui, ventago-app, wear-os-pairing, d-16]

# Esta plan es ad-hoc: ejecutada directamente desde la decisión D-16 del usuario
# (98-CONTEXT.md, 2026-10-05), sin un 98-15-PLAN.md previo — el pedido llegó ya
# como instrucción de ejecución directa, no como fase de planificación.

# Dependency graph
requires:
  - phase: 98-01
    provides: "POST /watch/pairing-codes/claim · GET /watch/devices · DELETE /watch/devices/{id} (contrato JSON, 403/404/429, @Auth(admin))"
  - phase: 98-05
    provides: "Patrón de referencia (tienda-admin-app RelojesRepository/RelojesScreen) — mismo mapeo de errores y textos"
  - phase: 98-14
    provides: "revoke() debe envolver errores — no dejarlos crudos hasta la pantalla (CODEX P2 ya corregido del lado celular, replicado acá desde el inicio)"
provides:
  - "RelojesCard (ventago-app) — segunda entrada de pairing (D-16), además del celular (D-06)"
  - "relojes-logic.ts — lógica pura reutilizable/testeada sin depender de .tsx"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Lógica pura en .ts separada del componente .tsx — la app jest no puede importar .tsx (memory: app-jest-cannot-import-tsx)"
    - "next/dynamic(ssr:false) para la tarjeta nueva — code-splitting obligatorio (CLAUDE.md)"

key-files:
  created:
    - ventago-app/src/views/relojes/relojes-logic.ts
    - ventago-app/src/views/relojes/RelojesCard.tsx
    - ventago-app/src/__tests__/relojes-logic.spec.ts
  modified:
    - ventago-app/src/pages/admin/generar-token.tsx

key-decisions:
  - "El gate por roles.includes('admin') en la página es cosmético (memory: frontend-flag-is-not-a-security-boundary) — el servidor ya re-valida en cada request (claim/devices/revoke son @Auth(admin), D-05: re-chequeo de rol en cada llamada, no sólo en el JWT)."
  - "No se tocó WithAccess, el hub de Configuración, ni ningún menú/sidebar — la tarea pidió explícitamente reportar y proponer, no ejecutar, cambios de permission seeds/structure o sidebar (ver hallazgo abajo)."
  - "Mismos textos/mapeo de error que tienda-admin-app (98-05/98-14): 404→'Código inválido o vencido', 403→'Sólo el administrador de la tienda puede vincular relojes' (+ deshabilita input), 429→'Demasiados intentos. Esperá un minuto.', red→'Sin conexión'. revoke() replica desde el inicio la corrección de 98-14 (no deja DioException/AxiosError sin manejar)."

requirements-completed: []

# Metrics
duration: ~50min
completed: 2026-10-05
---

# Phase 98 Plan 15 (ad-hoc, D-16): Reloj Galaxy vinculable también desde la web Summary

**`/admin/generar-token` ahora tiene una sección «Reloj Galaxy» (código K7Q4-29XM → Vincular, lista de relojes con tiempo relativo, Quitar con confirmación) — segunda vía de pairing (D-16) sin tocar el contrato de API ni el flujo del celular (98-05/98-14).**

## Hallazgo previo (pedido por la tarea antes de construir)

Se verificó quién puede llegar hoy a `/admin/generar-token`:

- **La página no tiene ningún gate de acceso** (`WithAccess`, rol, o similar). A diferencia de páginas hermanas en `src/pages/admin/` (`revendedores.tsx`, `vto.tsx`, `soporte-remoto.tsx`, que sí envuelven su contenido en `<WithAccess allowedApps={[...]}>` o `superadminOnly`), `generar-token.tsx` sólo pasa por el `AuthGuard` global de `_app.tsx` — **cualquier usuario autenticado, de cualquier rol**, puede abrirla tecleando la URL directamente.
- **No está enlazada desde ningún menú/sidebar.** `grep -rn "admin/generar-token"` en todo `ventago-app/src` sólo encuentra referencias en comentarios (`ChatBubble.tsx`, `menu-chat-entradas.spec.ts`) que documentan que esta ruta "ya no es el único lugar" para abrir el chat de IA — es decir, es un resto de una versión anterior del menú.
- **La clave `generar-token` del hub `/configuracion` (`src/pages/configuracion/index.tsx:88`, `requiredApps: ['admin']`) ya no apunta a esta página** — renderiza `AccesoVentagoView` (`src/views/acceso-ventago/AccesoVentagoView.tsx`), una feature nueva y distinta («Acceso de Ventago»: códigos de acceso temporal para agentes de soporte, con alcances/revocación/auditoría) que coincidentemente comparte el mismo texto de menú pero es un componente completamente distinto del diálogo de "Token de Soporte Técnico" que vive en `generar-token.tsx`.

**Conclusión:** hoy `/admin/generar-token` es una ruta huérfana — nadie la encuentra navegando, pero quien conoce/adivina la URL la abre sin importar su rol. La sección Reloj Galaxy agregada en esta plan queda detrás de un chequeo de rol *sólo en el cliente* (coherente con lo pedido: "Show the section only for users whose roles include 'admin'"), pero la página en sí sigue sin gate real.

**Fix mínimo propuesto (no ejecutado — requiere decisión del usuario):** envolver el contenido de `generar-token.tsx` en `<WithAccess allowedApps={['admin']}>` (mismo patrón que `revendedores.tsx`/`soporte-remoto.tsx`), lo cual sólo toca este archivo — no requiere cambios de permission seeds/structure ni de sidebar config. Si además se quiere que el personal autorizado *encuentre* la pantalla navegando (hoy no hay ningún enlace), eso sí tocaría el hub de Configuración o el sidebar y se dejó fuera del alcance de esta plan tal como se indicó.

## Performance

- **Duration:** ~50 min
- **Completed:** 2026-10-05
- **Tasks:** 1 (sin PLAN.md previo — ejecución directa de instrucción ad-hoc)
- **Files modified:** 4 (3 nuevos en `ventago-app/src/views/relojes/` + `src/__tests__/`, 1 modificado en `src/pages/admin/`)

## Accomplishments

- `relojes-logic.ts`: normalización de código (mayúsculas, sin espacios/guión — igual que `relojes_repository.dart` `_normalize`), validación de longitud (8), mapeo de status HTTP → tipo de error (404/403/429/otro), mensajes de claim y de revoke, nombre a mostrar (`model` o `'Reloj'`), `lastSeenLabel` ('sin uso todavía'/'hace un momento'/'hace N min|h|días') — 7 tests jest, todos pasando
- `RelojesCard.tsx`: input de código (mayúsculas automáticas, máx. 9 caracteres visibles) + botón «Vincular reloj» (deshabilitado hasta 8 caracteres normalizados) → `POST /watch/pairing-codes/claim` (código sólo en el body); lista de relojes vinculados vía `GET /watch/devices` (403 se distingue de lista vacía, igual que `RelojesRepository.listDevices`); «Quitar» con `Dialog` de confirmación → `apiConnector.remove('/watch/devices/' + id)` (no `.delete()`); errores de claim y de revoke mostrados con `Snackbar`+`Alert` (revoke nunca deja una excepción sin manejar — réplica de la corrección 98-14 desde el inicio); línea de ayuda fija (D-10) sobre el botón físico del reloj
- `generar-token.tsx`: se agregó `useAuth()` + gate `user.roles.includes('admin')` alrededor de un `<RelojesCard />` cargado con `next/dynamic(ssr:false)` — el diálogo de token de soporte existente queda sin cambios
- `tsc --noEmit`: 0 errores. `eslint` (4 archivos tocados): 0 errores/warnings (exit code 0 verificado explícitamente). `jest src/__tests__/relojes-logic.spec.ts`: 7/7 pasando
- Verificación visual con `next build` se omitió — había un servidor dev corriendo en el puerto 3050 (memory: `next-build-breaks-running-dev-server`) y la tarea autorizaba omitir en ese caso

## Task Commits

Sin PLAN.md, se ejecutó como una sola unidad de trabajo (no hay tasks numeradas de un plan):

1. **relojes-logic.ts + RelojesCard.tsx + generar-token.tsx + test** — `df1fa943` (feat, ventago-app) — paso por el hook `verify-before-commit.sh` sin `SKIP_VERIFY`
2. **Puntero ventago-app** — `9a23925` (chore, root)

## Files Created/Modified

- `ventago-app/src/views/relojes/relojes-logic.ts` — lógica pura (normalización, validación, mapeo de errores, `lastSeenLabel`, `watchDeviceDisplayName`)
- `ventago-app/src/views/relojes/RelojesCard.tsx` — componente MUI de la sección «Reloj Galaxy»
- `ventago-app/src/__tests__/relojes-logic.spec.ts` — 7 tests jest
- `ventago-app/src/pages/admin/generar-token.tsx` — import de `useAuth`, gate por rol, `next/dynamic` de `RelojesCard`, sección agregada al final del `<Box>` (el diálogo de token de soporte no se modificó)

## Decisions Made

Ver `key-decisions` en el frontmatter.

## Deviations from Plan

No aplica un "plan" previo en sentido formal (es la primera ejecución ad-hoc de D-16). Dentro del alcance pedido por el usuario no hubo desviaciones: se construyó exactamente lo descrito (input+botón, lista+quitar+confirmación, errores 404/403/429/red, aviso D-10, gate de rol cosmético, extracción a componente+lógica pura con test, verificación tsc/eslint/jest, commit con paths explícitos sin `-A`, push de ambos repos sin pedir aprobación, confirmación de build Jenkins + contenedor).

## Issues Encountered

- El primer intento de `git add` + `git commit` en un solo comando (para el puntero del root) fue bloqueado por el hook `PreToolUse` del propio CLAUDE.md (memory: `pretooluse-gate-sees-index-before-add`) — se corrigió separando `git add` y `git commit` en comandos distintos, como ya estaba documentado.
- Jenkins build #962 (`front-coolsistema`) estaba en curso (`docker buildx` corriendo `npm run build`) cuando se consultó por primera vez — se esperó en background hasta que apareciera `build.xml` con el resultado, en vez de adivinar el número de build (memory: `jenkins-build-number-is-already-mine`, confirmado por SHA en `changelog.xml`).

## User Setup Required

None — no se requiere configuración de servicios externos. El contrato de API (`/watch/pairing-codes/claim`, `/watch/devices`) ya estaba desplegado desde 98-10.

## Next Phase Readiness

- Pendiente de decisión del usuario: aplicar o no el fix mínimo propuesto arriba (`WithAccess allowedApps={['admin']}` en `generar-token.tsx`) y, si se quiere que el personal *encuentre* la pantalla navegando, dónde enlazarla (hub de Configuración vs. sidebar) — ninguna de las dos cosas se tocó en esta plan.
- 98-12 (checkpoint pendiente, Task 2 — claim desde el celular por el usuario) y 98-07 (Play Store) siguen siendo las plans formales abiertas del phase; esta 98-15 no las bloquea ni las adelanta.

## Known Stubs

None — `RelojesCard` siempre lee de los 3 endpoints reales (`/watch/pairing-codes/claim`, `/watch/devices`, `/watch/devices/{id}`); no hay valores hardcodeados vacíos ni placeholders de datos. El único texto fijo es la línea de ayuda del botón físico (D-10), contenido informativo intencional, no un stub.

## Threat Flags

None — esta plan sólo consume los 3 endpoints ya registrados en el threat_model de 98-01 (T-98-30/31/32/33), con el mismo contrato y el mismo mapeo de errores que la pantalla equivalente del celular (98-05/98-14). No se agregó superficie nueva (sin endpoints, sin rutas de auth, sin cambios de schema). El hallazgo documentado arriba (página sin `WithAccess`) es sobre una condición **preexistente** de `generar-token.tsx`, no introducida por esta plan — se reporta por transparencia, no se "oculta" bajo esta sección porque no es una superficie nueva que esta plan haya abierto.

---
*Phase: 98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es*
*Completed: 2026-10-05*

## Self-Check: PASSED

Archivos verificados presentes en disco (`relojes-logic.ts`, `RelojesCard.tsx`, `relojes-logic.spec.ts`, `generar-token.tsx` modificado); commits `df1fa943` (ventago-app) y `9a23925` (root) verificados en `git log --oneline --all` de cada repo. Jenkins build #962 de `front-coolsistema` = SUCCESS (changelog.xml contiene `df1fa943`), contenedor `ventagoapp` recreado (`Up 12 seconds` al momento de la verificación). No missing items.
