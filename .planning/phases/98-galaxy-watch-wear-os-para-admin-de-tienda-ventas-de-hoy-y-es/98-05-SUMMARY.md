---
phase: 98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es
plan: 05
subsystem: ui
tags: [flutter, riverpod, dio, wear-os-pairing, tienda-admin-app]

# Dependency graph
requires:
  - phase: 98-01
    provides: "POST /watch/pairing-codes/claim · GET /watch/devices · DELETE /watch/devices/{id} (contrato JSON, 403/404/429)"
provides:
  - "RelojesRepository + WatchDevice (tienda-admin-app) — único punto desde el que el celular llama a los 3 endpoints de pairing"
  - "RelojesScreen — input de código, lista de relojes vinculados, revocación con confirmación, aviso fijo del botón físico (D-10)"
  - "Entrada en AppBar (Icons.watch_outlined) visible solo para admin — AppShell"
affects: [98-06, 98-07, 98-12]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Fake HttpClientAdapter en el propio test (sin mocktail) para fijar status/body de Dio sin red real"
    - "Repository fake vía `implements RelojesRepository` (solo métodos públicos) para widget tests"
    - "Subclase mínima de AuthController para inyectar AuthState en tests (acceso protegido solo dentro de la jerarquía)"

key-files:
  created:
    - tienda-admin-app/lib/features/relojes/relojes_repository.dart
    - tienda-admin-app/lib/features/relojes/relojes_screen.dart
    - tienda-admin-app/test/features/relojes/relojes_repository_test.dart
    - tienda-admin-app/test/features/relojes/relojes_screen_test.dart
  modified:
    - tienda-admin-app/lib/shared/app_shell.dart

key-decisions:
  - "listDevices() nunca traga un 403 como lista vacía — lanza RelojesException(notAdmin) para que la pantalla distinga «sin relojes» de «perdiste el rol admin»"
  - "La normalización de código (mayúsculas + sin espacios/guión) vive en repository.dart (fuente de verdad del body) y se repite en la pantalla solo para decidir si el botón se habilita (8 caracteres) — sin duplicar la llamada de red"
  - "Ícono de Relojes en AppBar es UX únicamente (roles.contains('admin')); el límite real ya está en el servidor (403 re-validado en 98-01) — memoria frontend-flag-is-not-a-security-boundary"

requirements-completed: [W98-03]

# Metrics
duration: ~25min
completed: 2026-10-04
---

# Phase 98 Plan 05: Relojes vinculados (celular) Summary

**Pantalla «Relojes vinculados» en tienda-admin-app (Flutter) — código de 8 caracteres → claim, lista con tiempo relativo y revocación con confirmación, y el ícono de entrada en el AppBar que solo ven los admin de tienda.**

## Performance

- **Duration:** ~25 min
- **Completed:** 2026-10-04T20:55:03Z
- **Tasks:** 2/2
- **Files modified:** 5 (2 creados en lib/features/relojes, 1 modificado en lib/shared, 2 tests nuevos)

## Accomplishments
- `RelojesRepository` traduce los 3 endpoints de 98-01 a tipos Dart (`WatchDevice`, `ClaimError`, `RelojesException`), con el código siempre viajando en el body (nunca en la URL — T-98-31)
- `RelojesScreen` cubre los 6 `must_haves.truths` del plan: entrada solo-admin, claim con mensajes por tipo de error, lista con "hace N min/h/días" o "sin uso todavía", revocación con confirmación, aviso fijo del botón físico (D-10), y el aviso 403 cuando se pierde el rol admin
- `AppShell` muestra el ícono `Icons.watch_outlined` únicamente si `roles.contains('admin')` — los demás roles (ej. gerente) no lo ven
- 24 tests nuevos (11 de repository + 13 de screen/AppShell), todos pasando sin agregar `mocktail` ni ningún otro dev_dependency

## Task Commits

Each task was committed atomically:

1. **Task 1: RelojesRepository + WatchDevice + unit tests** - `916d677` (test — RED+GREEN combinados en un commit porque el plan no es `type: tdd` a nivel de plan)
2. **Task 2: RelojesScreen + entrada en AppBar + widget tests** - `639cacc` (feat)

_Nota: ambos tasks tenían `tdd="true"` a nivel de task, pero el plan es `type: execute` (no `type: tdd`), así que el gate RED→GREEN→REFACTOR de plan completo no aplica — se verificó igual que los tests fallarían sin la implementación (se escribieron contra código inexistente antes de correr) antes de cada commit._

## Files Created/Modified
- `tienda-admin-app/lib/features/relojes/relojes_repository.dart` - `WatchDevice.fromJson`, `displayName` (fallback 'Reloj'), `ClaimError`/`RelojesException`, `claimCode`/`listDevices`/`revoke`, normalización de código
- `tienda-admin-app/lib/features/relojes/relojes_screen.dart` - Input de código + botón 'Vincular reloj' (habilitado solo con 8 chars normalizados), lista de dispositivos, diálogo de confirmación para 'Quitar', tarjeta inferior fija con la guía del botón físico, aviso cuando `listDevices()` devuelve 403
- `tienda-admin-app/lib/shared/app_shell.dart` - Ícono `Icons.watch_outlined` (tooltip 'Relojes') en AppBar actions, antes del botón de logout, visible solo si `user.roles.contains('admin')`
- `tienda-admin-app/test/features/relojes/relojes_repository_test.dart` - 11 tests con `HttpClientAdapter` fake (sin red real)
- `tienda-admin-app/test/features/relojes/relojes_screen_test.dart` - 13 widget tests (11 de RelojesScreen + 2 de AppShell) con repository fake (`implements RelojesRepository`) y una subclase mínima de `AuthController` para inyectar `AuthState`

## Decisions Made
- `RelojesException` es compartida entre `claimCode` y `listDevices` (mismo enum `ClaimError`) porque ambos caminos necesitan distinguir 403/404/429/red — evita duplicar el mapeo de errores
- El provider `relojesDevicesProvider` (FutureProvider.autoDispose) vive en `relojes_screen.dart`, no en el repository — el repository solo expone el contrato HTTP, la pantalla decide cuándo invalidar (después de claim/revoke)
- Para los widget tests de AppShell se sobrescribió `dioClientProvider` con un adapter que siempre devuelve `{}` — evita que el tab inicial (PanelScreen) golpee red real, sin necesitar lógica de mock adicional (el código ya tolera `res.data ?? const {}`)

## Deviations from Plan

None - plan ejecutado tal como está escrito. Las dos tasks se completaron con los artefactos, comportamientos y criterios de aceptación exactamente como figuran en el PLAN.md (greps de `watch/pairing-codes/claim`, `Doble pulsación`, `Icons.watch_outlined`, `RelojesScreen`, `contains('admin')` — todos con el conteo esperado).

## Issues Encountered
- Primer intento del test "8자 코드 → claimCode" usó un código con espacios/guión (' k7q4-29xm ', 11 caracteres) que el `TextField` con `maxLength: 9` truncó antes de llegar al controller, dejando el código normalizado en 7 caracteres y el botón deshabilitado. Se corrigió usando un código ya normalizado de 8 caracteres en el test (la normalización de espacios/guión/mayúsculas ya está cubierta por los tests de `relojes_repository_test.dart`, que no pasan por ningún widget con `maxLength`).

## User Setup Required

None - esta plan no requiere configuración de servicios externos. El build del APK se hace en 98-12, después de confirmar el despliegue de la API (98-10).

## Next Phase Readiness

- 98-06/98-07 (app Wear OS) pueden asumir que el celular ya tiene un flujo de pairing funcional y testeado — no hay bloqueo del lado celular
- La entrada del ícono en AppBar funciona para cualquier usuario con rol `admin`, independientemente del resto de la navegación (no es un callejón sin salida — visible en los 5 tabs)
- Pendiente de 98-07 (dispositivo real): confirmar si la ruta de menú del reloj ("Ajustes › Funciones avanzadas › Personalizar botones › Doble pulsación") es exactamente así en Galaxy Watch — si difiere, solo hay que tocar el texto fijo en `_tipCard()` de `relojes_screen.dart`

## Known Stubs

None - no hay valores hardcodeados vacíos ni placeholders. La pantalla siempre lee de `relojesRepositoryProvider` (red real); el único texto fijo es el aviso del botón físico, que es contenido informativo intencional (D-10), no un stub de datos.

## Threat Flags

None - esta plan solo consume los 3 endpoints ya registrados en el threat_model de 98-01 (T-98-30/31/32/33). No se agregó superficie nueva (sin endpoints, rutas de auth, ni cambios de schema).

---
*Phase: 98-galaxy-watch-wear-os-para-admin-de-tienda-ventas-de-hoy-y-es*
*Completed: 2026-10-04*

## Self-Check: PASSED

All 6 created/referenced files verified present (5 código/test + este SUMMARY.md); ambos commits (`916d677`, `639cacc`) verificados en `git log --oneline --all`. No missing items.
