---
phase: 119-predicci-n-de-ventas-y-recomendaci-n-de-producci-n-qu-cu-nta
plan: 06
subsystem: api
tags: [forecast, talleres, lead-time, wip, itest]
requires: [119-01]
provides:
  - ProduccionInsumosService (leadTimePorModelo, leadTimeDefault, wipEnFecha, lotesDeModelo, ingresosPorProducto)
affects: [119-07, 119-08, 119-10]
key-files:
  created:
    - api-ventago/src/app/forecast/produccion/produccion-insumos.sql.ts
    - api-ventago/src/app/forecast/produccion/produccion-insumos.service.ts
    - api-ventago/src/app/forecast/produccion/produccion-insumos.itest.ts
requirements-completed: [D-03, D-04, D-10, D-12]
completed: 2026-10-19
---

# Phase 119 Plan 06: Insumos de produccion Summary

Servicio de solo lectura que deriva de talleres el lead time por modelo (mediana corte a recepcion final POSTED), el WIP a una fecha, los lotes que explican un modelo y el ingreso por producto (talleres, luego legacy_ingresos, luego stocks production), con fallback a `forecast_store_settings.lead_time_days`.

## Commits (api-ventago, sin push)

- `fe318bbb` SQL y servicio
- `d1762ea0` itest (10 casos)

## Verificacion

- tsc 0 errores; eslint limpio; `grep -c "store_id = $1::int"` = 20 (>= 6); sin imports de `app/talleres`.
- `npm run test:itest -- produccion-insumos --forceExit`: 10/10 (lead 21 = mediana de 19 y 23, WIP con llegada real y estimada, recepcion revertida de 99 no suma, cascada de ingresos, lotesDeModelo, aislamiento entre tiendas).
- Humo de lectura sobre store 6 local: 10 modelos con lead (p. ej. 22/17/21 dias), 7 lotes WIP al 2026-10-19, 103 productos con ingreso.
- El cableado en ForecastModule queda para 119-10 (como indica el plan).

## Deviations from Plan

**1. [Rule 1 - Bug] Regla de WIP.** El plan dice WIP = recibido POSTED < total_quantity. Con rechazos en etapas previas (el seed rechaza 0-3 % en costura) un lote COMPLETED nunca llega a `total` y apareceria como WIP para siempre. Se agrego: un lote COMPLETED/CLOSED sin recepcion final POSTED vigente, o con la ultima ya ocurrida (<= t), sale del WIP. El itest lo cubre con L2 (total 32, final 30).

**2. [Aclaracion] Enum de lotes.** `enum_talleres_lotes_status` = {OPEN, IN_PROGRESS, COMPLETED, CLOSED}; no existe CANCELLED, asi que no se filtra. Un lote sin recepcion final no cuenta si ya esta COMPLETED/CLOSED.

**3. [Detalle] `lotesDeModelo`.** `recepcionFinal`/`diasLead` solo se informan para lotes COMPLETED (en curso = null); `tallerPrincipal` es el envio con mayor (ultima recepcion no revertida - envio_date), y en lotes en curso cae a un envio con duracion nula si no hay otro.

## CODEX

No se consulto CODEX manualmente en este plan; el hook post-commit lo lanza en segundo plano (`.team/reviews/auto-*.md`). Pendiente de leer antes de 119-13. Sin push ni escritura en produccion.

## Known Stubs

None.

## Self-Check: PASSED
