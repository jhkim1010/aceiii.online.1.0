---
phase: 119-predicci-n-de-ventas-y-recomendaci-n-de-producci-n-qu-cu-nta
plan: 13
subsystem: forecast / despliegue
requires: [119-16]
affects: [119-14]
status: COMPLETO
---

# Phase 119 Plan 13: Despliegue a producción — Summary

## Aprobaciones
- 119-16: "aprobado" (2026-10-20). Orden de desplegar: "진행". DDL prod: "승인" tras ver SQL e impacto.

## Gates locales (2026-10-20 00:10 ART, por exit code)
- api tsc 0 · api eslint src/app/forecast 0 · api jest forecast+store+migrations 48 suites / 607 tests OK
- app tsc 0 · app eslint reports-v2 0 errores (1 warning previo en CockpitLayout) · app jest prediccion-logica 25 OK
- CODEX: c4 sin hallazgos; c6 HIGH corregido en f0ec8509; c5 MEDIUM/LOW (selectores top 50) y c2 HIGH x4 aceptados por el usuario al aprobar 119-16 (quedan como pendientes de la phase).

## DDL prod (5434) — 00:12 ART, usuarios activos medidos justo antes: 2
| Archivo | Resultado |
|---|---|
| 2026-10-19-phase119-forecast-tablas.sql | 7 CREATE TABLE + 4 índices, owner coolsistema |
| 2026-10-19-phase119-forecast-permisos.sql | functions +1, role_functions +28, role_function_actions +56; concesiones_no_admin 0 |
| 2026-10-19-phase119-forecast-store6-sintetico.sql | forecast_store_settings +1, product_attributes +10 |
| 2026-10-20-phase119-forecast-fundamento.sql | 3 CREATE TABLE + ALTER forecast_backtest_metrics (3 columnas) |
- 10 tablas con owner coolsistema; secuencias product_attributes_id_seq / forecast_runs_id_seq → coolsistema; store 6 enabled = t.
- Columnas local vs prod de las 10 tablas: 122 = 122, diff vacío.

## Push y builds
- api-ventago f0ec8509 (incluye 4dd6c85e Pedidos, SQL ya aplicado antes) → Jenkins api-new-coolsistema #1221 SUCCESS, "Checking out Revision f0ec8509", api_ventago healthy. GET /api/prediccion/estado sin token = 401.
- ventago-app 0a720ee4 → Jenkins front-coolsistema #1187 SUCCESS, contenedor ventagoapp recreado, app.coolsistema.com 200.

## Siguiente
- 119-14: verificación en prod (cron nocturno 05:35 de store 6 y pantallas).
