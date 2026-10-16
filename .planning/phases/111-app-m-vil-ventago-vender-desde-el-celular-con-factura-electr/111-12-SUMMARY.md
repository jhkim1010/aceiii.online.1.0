---
phase: 111-app-m-vil-ventago-vender-desde-el-celular-con-factura-electr
plan: 12
subsystem: mobile
tags: [flutter, riverpod, ingreso, reportes, idempotencia, colibri]
requires: ["111-10", "111-16", "111-11", "111-07", "111-08"]
provides:
  - "Ingreso de stock por escaneo continuo con deshacer, edicion, nota, destino y confirmacion idempotente"
  - "Reportes Ventas/Caja/Stock con el texto «que cuenta» de cada numero"
key-files:
  created:
    - colibri/lib/features/ingreso/{ingreso_model,ingreso_store,ingreso_repository,ingreso_screen}.dart
    - colibri/lib/features/reportes/{reportes_repository,reportes_screen}.dart
    - colibri/test/{ingreso_model_test,reportes_parse_test}.dart
  modified:
    - colibri/lib/features/ingreso/ingreso_routes.dart
    - colibri/lib/features/reportes/reportes_routes.dart
decisions:
  - "Con clave pendiente el borrador queda congelado (no se agrega/edita): el reintento envia la misma clave y el mismo cuerpo."
  - "Rechazo definitivo del servidor (4xx con codigo, salvo EN_CURSO/CLAVE_CONFLICTO) libera la clave; sin respuesta o 5xx va a verificar por clave."
  - "Fecha «Hoy» no se envia: el servidor usa el dia de la tienda; una fecha elegida va como componentes de calendario del selector, nunca UTC."
  - "Sucursales de reportes salen de context.branches; «Todas» (0) solo con permiso de ventas."
metrics:
  colibri-commits: 848cebc, 676a8ed
  tests: 122 (flutter test), analyze 0 issues
  completed: 2026-10-16
---

# Phase 111 Plan 12: Ingreso de stock y Reportes Summary

Pestanas Stock y Reportes de Colibri: ingreso por escaneo que nunca se envia dos veces y tres reportes que muestran las cifras y captions del servidor.

## Commits (submodulo colibri, pusheado al remoto privado)
- 848cebc ingreso: modelo puro, borrador persistente, maquina de confirmacion, pantalla, rutas (15 tests)
- 676a8ed reportes: repositorio, pantalla, rutas (5 tests de parseo)
- Raiz: gitlink commiteado aparte. Monorepo raiz, api-ventago y ventago-app NO pusheados.

## Verificacion
`flutter analyze`: No issues found. `flutter test`: 122 pasan. Greps: `Idempotency-Key` y `by-key` en ingreso_repository; `branchId=` 0 en lib/features/ingreso; `cuenta` 12 veces y `AppPaths.sinEmitir` en reportes_screen; `stock/branches` ausente en reportes.

## Deviations from Plan
- [Rule 3] Rutas `colibri/` en lugar de `ventago-movil/`.
- `GET /stock/balances` responde `{branchId, balances[]}` (no un array pelado como decia el plan): el parser acepta ambas formas.
- `ReportValue` ya existia en pos_contracts.dart; reportes_repository define el suyo y la pantalla oculta el del contrato.
- Sonido distinto en repeticion: heavyImpact + doble click del sistema (sin paquete nuevo, supuesto A2).
- Los tests de ingreso cubren tambien la maquina de confirmacion (doble toque, corte, not_found, 422, clave pendiente al arrancar), mas alla de las operaciones puras.

## Known Stubs
- `AppPaths.sinEmitir` aun no tiene ruta registrada (pantalla del Plan 19): «Ver todas las pendientes ›» falla hasta entonces.

## Notes
- Sin tests de widget; pantallas no probadas en dispositivo ni contra la API real (camara, sonido, selector de fecha, «Todas» = 0 en day/stock, que el servidor deberia aceptar segun Plan 08: sin verificar).
- «Mantener sin conexion» de reportes solo conserva los datos en memoria mientras la pantalla vive.
- STATE.md y ROADMAP.md quedan SIN commitear a proposito.

## Self-Check: PASSED
Commits 848cebc y 676a8ed existen en colibri; archivos creados presentes.
