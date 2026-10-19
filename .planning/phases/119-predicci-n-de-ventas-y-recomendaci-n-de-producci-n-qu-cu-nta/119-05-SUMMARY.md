---
phase: 119-predicci-n-de-ventas-y-recomendaci-n-de-producci-n-qu-cu-nta
plan: 05
subsystem: api
tags: [forecast, daily_sales_agg, launch_date, migration, itest]
requires: [119-01, 119-04]
provides:
  - ForecastAggService (refrescarTienda / refrescarTodas / tiendasHabilitadas)
  - ForecastModule registrado en app.module.ts
  - buildLaunchDateUpsert (D-04)
  - constantes forecast (DISCLAIMER_SINTETICO_ES, AGG_*, ADVISORY_CLASS_FORECAST)
  - migracion 2026-10-20-phase119-forecast-fundamento.sql (aplicada SOLO en local)
affects: [119-06, 119-07, 119-08, 119-13]
key-files:
  created:
    - api-ventago/migrations/2026-10-20-phase119-forecast-fundamento.sql
    - api-ventago/src/app/forecast/forecast.constants.ts
    - api-ventago/src/app/forecast/zona-tienda.ts
    - api-ventago/src/app/forecast/agg/launch-date.sql.ts
    - api-ventago/src/app/forecast/agg/daily-sales-agg.service.ts
    - api-ventago/src/app/forecast/agg/daily-sales-agg.itest.ts
    - api-ventago/src/app/forecast/forecast.module.ts
  modified:
    - api-ventago/src/app/forecast/contrato/daily-sales-agg.sql.ts
    - api-ventago/src/app/forecast/contrato/daily-sales-agg.sql.spec.ts
    - api-ventago/src/app.module.ts
requirements-completed: [D-04, D-05, D-06, D-08, D-02, D-12]
completed: 2026-10-19
---

# Phase 119 Plan 05: Servicio de agregado B Summary

Servicio que refresca `daily_sales_agg` por tienda en ventanas de 31 dias (transaccion corta, statement_timeout 60s, lock_timeout 2s, advisory lock por tienda), mantiene el watermark, completa `launch_date` y queda registrado como `ForecastModule`; la apertura legacy se detecta por `stocks.source = 'legacy_opening'` y el itest pasa 12/12 contra PG18 local.

## Commits (api-ventago, sin push)

- `bb9b7cf8` apertura legacy por `source` + migracion «Fundamento» (4 objetos: forecast_datos_usados, forecast_modelo_tickets, forecast_policy_sim_traces, columnas sum_abs_error/sum_error/sum_actual)
- `58111ba6` ForecastAggService, launch-date, constantes, zona-tienda, ForecastModule
- `8628f47e` itest (12 casos) + bind propio del DELETE

## Verificacion

- jest `src/app/forecast` 61 pasan; migration-conventions pasa; tsc 0 errores; eslint 0 problemas.
- `npm run test:itest -- daily-sales-agg --forceExit`: 12/12 (incluye el bloque store 6 sintetico, que se ejecuto y no se salto).
- Migracion aplicada en LOCAL (psql: 3 tablas + 3 columnas). NO aplicada en produccion (queda para 119-13). Intel regenerado (`.planning/intel/db-schema-*.md`, sin commitear en este plan).

## Deviations from Plan

**1. [Rule 1 - Bug] DELETE con parametros sin referenciar.** `deleteSql` usaba `$1,$3,$4` y el servicio le pasaba 5 binds; Postgres falla con "could not determine data type of parameter $2". Se renumero a `$1,$2,$3` (bind `[storeId, desde, hasta]`) en el contrato y su spec.

**2. [Plan vs. libro] `suspend` no mueve el saldo.** El plan esperaba `stock_eod` 3 en D4 tras una fila `legacy_pedido`/`suspend` de -1. El trigger `stock_balances_apply` no suma `type='suspend'` a `on_hand` (solo a `reservado`), y el contrato replica ese trigger (decision de 119-04). El itest afirma `stock_eod` 4 = `stock_balances.on_hand` y `qty` 0; sigue valiendo que la fila no es venta ni ingreso ni fuente de launch_date.

**3. [Test] Consulta independiente del store 6.** Para coincidir con la definicion de venta debe usar los 5 estados contables (Facturado, Pagado, Pendiente por pagar, Anulado, Anulacion) y `-ABS(cantidad)` en Anulacion (regla 117-13). Con eso Σqty coincide exacto (3.011).

**4. [Menor] Migracion con `--single-transaction` + BEGIN/COMMIT** emite dos WARNING inofensivos (igual que la migracion 2026-10-19).

## Notas para siguientes planes

- Local: store 6 tiene ahora `daily_sales_agg` poblado (refresco 2025-11-01..2026-10-18) y tres tiendas fixture `ZZ-F119-AGG-*` (no se borran).
- El servicio no tiene cron ni controller (llegan en 119-07/08); en cron recordar que workers no lideres pierden los `@Cron`.
- Sin modelos Sequelize nuevos: todo SQL crudo, el arranque no depende de la migracion en prod. Aun asi, desplegar migracion antes que el codigo cuando algo llame al servicio (119-13).

## CODEX

No se consulto CODEX manualmente en este plan; el hook post-commit lo lanza en segundo plano (`.team/reviews/auto-*.md`). Pendiente de leer antes de 119-13. No hubo push ni escritura en produccion (la medicion de la apertura legacy en prod fue la de 2026-10-19 citada por el plan).

## Known Stubs

None.

## Self-Check: PASSED
