---
phase: 119-predicci-n-de-ventas-y-recomendaci-n-de-producci-n-qu-cu-nta
plan: 07
subsystem: api-ventago/forecast
tags: [backtest, rolling-origin, forecast_runs, ttl, d-09]
requires: [119-01, 119-02, 119-05]
provides:
  - BacktestRunnerService.correr
  - run-registro (crearRun, cerrarRun, metaSintetica, RUN_TTL_MIN)
  - buildSeriesSemanalesSql
  - CUOTA_CENSURA
key-files:
  created:
    - api-ventago/src/app/forecast/runs/run-registro.ts
    - api-ventago/src/app/forecast/backtest/series.sql.ts
    - api-ventago/src/app/forecast/backtest/backtest-runner.service.ts
    - api-ventago/src/app/forecast/backtest/backtest-runner.itest.ts
  modified:
    - api-ventago/src/app/forecast/forecast.constants.ts
decisions:
  - La retención (10 corridas por tienda y kind) vive sólo en cerrarRun, no duplicada en el runner; no toca corridas 'running'.
  - Nivel variante pide tope+1 al SQL por volumen descendente y descarta la de menor volumen (params.recortado = true).
metrics:
  tasks: 2
  completed: 2026-10-19
---

# Phase 119 Plan 07: Runner de backtest Summary

Backtest D por categoría, modelo y variante desde `daily_sales_agg`, con registro de corridas con TTL, persistencia atómica y descargo sintético/real.

## Commits (repo api-ventago, sin push)
- `313528da` feat(119-07): runner, registro de corridas, series SQL, CUOTA_CENSURA
- `3653b11d` test(119-07): itest del runner (12 casos)

## Resultado
- tsc y eslint limpios; `npm run test:itest -- backtest-runner`: 12/12 pasan.
- Los puntos se escriben en lotes de 5.000 (transacción propia); métricas y paso a 'done' en una sola transacción final. Puntos de variante no se persisten.
- crearRun marca 'failed'/'abandonada' las 'running' más viejas que el TTL (30/30/60 min) y devuelve `{enCurso}` ante 23505.
- seasonal_naive queda 'historia_insuficiente' con 48 semanas; las identidades wape = sum_abs_error/sum_actual y bias = sum_error/sum_actual se verifican con serie constante y con un control no constante (sum_abs_error > 0).

## Deviations from Plan
- [Rule 2] Agregué un 12º test de control con serie no constante: con series constantes todas las sumas son 0 y la identidad Σ pasaría trivialmente.
- Sin otras desviaciones.

## Notas
- Sin push, sin DDL/escrituras en producción. Todo corrió contra PG18 local (5432).
- CODEX: no se consultó en este plan (no se declara revisión). Queda pendiente para el diff antes de 119-13.
- El gate de commit pasó con normalidad (sin SKIP_VERIFY).
- Cableado a módulo/cron: pendiente en 119-10.

## Known Stubs
Ninguno.

## Self-Check: PASSED
Archivos creados existen; commits 313528da y 3653b11d presentes en api-ventago.
