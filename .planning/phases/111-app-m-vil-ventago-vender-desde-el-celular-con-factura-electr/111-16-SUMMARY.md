---
phase: 111-app-m-vil-ventago-vender-desde-el-celular-con-factura-electr
plan: 16
subsystem: mobile
tags: [flutter, go_router, riverpod, auth, device-approval]
requires: ["111-10", "111-15", "111-18"]
provides:
  - "Login con app:'colibri' sin seleccion de sucursal"
  - "Compuerta del celular (pendiente/aprobado/baja/bloqueado) con polling de 10 s"
  - "router.dart (redirect por sesion y celular, ShellRoute con HomeShell), main.dart cableado"
  - "Re-login que vuelve a la ubicacion y conserva borradores"
  - "api_paths_gate_test (D-22)"
affects: [111-19]
key-files:
  created:
    - colibri/lib/app/router.dart
    - colibri/lib/features/auth/{auth_repository,auth_controller,login_screen}.dart
    - colibri/lib/features/device/{device_repository,device_controller,device_screens}.dart
    - colibri/test/{device_flow_test,api_paths_gate_test}.dart
  modified:
    - colibri/lib/main.dart
    - colibri/lib/app/paths.dart
    - colibri/lib/core/storage/secure_storage.dart
decisions:
  - "decideRedirect es una funcion pura (testeable); 'from' solo acepta rutas internas"
  - "Logout/401 borran solo tokens y nombre, nunca deleteAll (borraria la sal de la huella del celular)"
  - "Estado 404 de /device/status = celular no registrado -> register automatico"
metrics:
  completed: 2026-10-16
  colibri-commits: 7d5bc5d, 9261a8c
---

# Phase 111 Plan 16: Login, dispositivo y router de Colibri Summary

Cualquier rol web entra con `app:'colibri'`, el celular se registra y espera aprobacion (la pantalla cambia sola), la baja bloquea todo, y un 401 pide la contrasena y vuelve al mismo lugar sin tocar borradores.

## Commits (submodulo colibri, publicado al remoto privado)
- Task 1: colibri 7d5bc5d (auth, dispositivo, router, main, 8 tests)
- Task 2: colibri 9261a8c (compuerta de rutas API, 5 tests)
- Raiz: gitlink commiteado aparte. Monorepo raiz, api-ventago y ventago-app NO se pushearon.

## Verificacion
`flutter analyze`: No issues found. `flutter test`: 42 tests pasan (device_flow 8, api_paths_gate 5). Greps de aceptacion: sin `clear()/deleteAll` en core/network, sin "password" en core/storage, sin requireBranchSelection/availableBranches en lib.
Prueba manual de la compuerta: se agrego `'/mobile/me'` a device_repository.dart y el test fallo (`Actual: [device_repository.dart: /mobile/me]`); revertido con git checkout.

## Deviations from Plan
- [Rule 3] Rutas `colibri/` y `app:'colibri'` en vez de `ventago-movil` (decision del usuario).
- Etiqueta del celular al registrar: `Celular android|ios` (no hay paquete de modelo de dispositivo instalado; no se agrego dependencia). El encargado puede renombrarlo en la web (Plan 15).
- Se agrego `AppPaths.deviceBlocked` y `StorageKeys.userName` (nombre no secreto para prellenar el re-login); `DeviceController`/`DeviceBlockedScreen` para Unknown/TerminalInactiva.
- Se permitio push del repo privado colibri por instruccion del orquestador.

## Known Stubs
Ninguno nuevo. Las pestanas Stock/Reportes siguen ocultas hasta que Plan 12 registre rutas; `TemporaryHome` queda solo para su test heredado.

## Notes
- STATE.md y ROADMAP.md quedan sin commitear a proposito.
- Gate de commit raiz: se usa solo el commit del gitlink.

## Self-Check: PASSED
