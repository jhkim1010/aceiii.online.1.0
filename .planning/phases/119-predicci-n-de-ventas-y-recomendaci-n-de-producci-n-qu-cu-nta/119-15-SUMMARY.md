---
phase: 119-predicci-n-de-ventas-y-recomendaci-n-de-producci-n-qu-cu-nta
plan: 15
subsystem: api
tags: [forecast, resumenes, fundamento, itest]
requires: [119-05, 119-06]
provides:
  - ForecastResumenesService.recalcular(storeId) -> { datosUsados, modelos }
  - buildTicketsPorModeloSql / buildTicketsTiendaSql / buildDatosUsadosSql
affects: [119-08, 119-10]
key-files:
  created:
    - api-ventago/src/app/forecast/resumenes/resumenes.sql.ts
    - api-ventago/src/app/forecast/resumenes/resumenes.sql.spec.ts
    - api-ventago/src/app/forecast/resumenes/forecast-resumenes.service.ts
    - api-ventago/src/app/forecast/resumenes/forecast-resumenes.itest.ts
requirements-completed: [D-12, D-04, D-08]
completed: 2026-10-19
---

# Phase 119 Plan 15: Resumenes nocturnos Summary

Servicio que cada noche escribe `forecast_modelo_tickets` y `forecast_datos_usados` de la tienda con la misma definicion de venta que el agregado (`ventaHeaderCte` + `fuentePredicadoSql`); la pantalla solo los lee.

## Commits (api-ventago, sin push)

- `21bb6265` constructores SQL + spec (6 tests)
- `65425873` servicio + itest (7 casos)

## Verificacion

- `jest src/app/forecast/resumenes --maxWorkers=1`: 6/6.
- `tsc --noEmit` y eslint limpios.
- `npm run test:itest -- forecast-resumenes --forceExit`: 7/7 (tickets 2 ventas - 1 anulacion = 1, vendidas 3, devueltas 1, legacy post-corte excluida; unidades_netas = Σqty directo de daily_sales_agg; tienda con apertura legacy -> `mixto` y tramo D2..D2 que termina el dia anterior a la apertura; aislamiento entre tiendas; idempotencia; tienda deshabilitada).

## Decisiones

- Periodo = [primer dia de daily_sales_agg, watermark]. Sin watermark o sin filas el servicio devuelve `{datosUsados:false, modelos:0}` y no escribe.
- Tickets de la tienda se cuentan aparte (ventas distintas, anulacion resta 1) en la misma transaccion que los tickets por modelo.
- `stock_fuente` y tramos se calculan por dias: un dia es indeterminado si todos los pares con actividad lo estan; `libro` sin tramos, `indeterminado` si todos los dias lo son, `mixto` en otro caso.
- Lotes/unidades e `ingreso_fuentes` son acumulados sin filtro de fecha (consistentes entre si; `ingresosPorProducto` de 119-06 no filtra por periodo). Las fuentes se resuelven antes de abrir la transaccion 2.
- El conteo de filas de modelos se lee con `count(*)` (el `rowCount` del INSERT con CTE no llego por el metadata de Sequelize).

## Deviations from Plan

- `buildDatosUsadosSql` no lee `forecast_modelo_tickets` (el plan lo mencionaba): sumarla contaria tickets multi-modelo dos veces, por eso los tickets de la tienda vienen de `buildTicketsTiendaSql`.
- El itest no cubre `lotes > 0` (fixture de talleres demasiado pesado); verifica `lotes = 0` e `ingreso_fuentes` con valores no triviales (ingreso_stock: 2 productos, 7 u.). Pendiente para 119-16 con datos de store 6.

## CODEX

No se consulto CODEX manualmente; el hook post-commit lo lanza en segundo plano (`.team/reviews/auto-*.md`). Pendiente de leer antes de 119-13. Sin push ni escritura en produccion. El cableado en ForecastModule es de 119-10.

## Known Stubs

None.

## Self-Check: PASSED
