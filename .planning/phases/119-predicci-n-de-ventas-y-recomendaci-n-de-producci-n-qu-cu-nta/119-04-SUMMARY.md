---
phase: 119-predicci-n-de-ventas-y-recomendaci-n-de-producci-n-qu-cu-nta
plan: 04
subsystem: api
tags: [forecast, sql, daily_sales_agg, stockout]
requires: [119-01]
provides:
  - buildRefrescoDailySalesAgg (deleteSql + insertSql, bind [store, tz, desde, hasta, cutoff])
  - fuentePredicadoSql / POLITICA_FUENTE_ES
  - diaLocalSql exportada desde venta-universe
affects: [119-05]
key-files:
  created:
    - api-ventago/src/app/forecast/contrato/fuente-politica.ts
    - api-ventago/src/app/forecast/contrato/fuente-politica.spec.ts
    - api-ventago/src/app/forecast/contrato/daily-sales-agg.sql.ts
    - api-ventago/src/app/forecast/contrato/daily-sales-agg.sql.spec.ts
  modified:
    - api-ventago/src/app/reports/venta-universe.ts
requirements-completed: [D-04, D-05, D-06]
duration: 20min
completed: 2026-10-19
---

# Phase 119 Plan 04: Contrato daily_sales_agg Summary

Constructor SQL puro que parte de `ventaHeaderCte` y agrega politica de fuente legacy por tienda, cantidad firmada por linea, devuelto separado y quiebre de stock en 3 valores (default `indeterminado`).

## Commits (api-ventago)

- `8c06e363` politica de fuente + `export` de diaLocalSql (1 insercion / 1 borrado en venta-universe.ts)
- `8ae30f80` constructor SQL del refresco + spec

## Verificacion

- `jest src/app/forecast/contrato` : 2 suites, 11 tests pasan; `compiler.spec` (Reporte a medida) intacto, 3 snapshots sin actualizar.
- `tsc --noEmit` y eslint limpios.
- Extra: el insertSql se ejecuto en local (store 6, 2026-01-01..2026-10-18, PREPARE/EXECUTE dentro de BEGIN/ROLLBACK): 60.913 filas, 3.125 unidades, con_stock 57.275 / sin_stock 2.990 / indeterminado 648. Nada quedo escrito.

## Decisiones

- Las filas de stocks que suman el saldo replican `stock_balances_apply`: todas salvo `type = 'suspend'`; el trigger no mira `is_active`, asi que tampoco el SQL.
- Grilla densa por par (branch, producto) con ProductBranch y libro de stocks; ventas en pares sin ProductBranch quedan `indeterminado` con `stock_eod` NULL.
- Se agrego `branch_id IS NOT NULL` (columna NOT NULL en destino).

## Deviations from Plan

None - plan ejecutado como estaba escrito.

## Notas para 119-05

- `legacy_opening` es el tipo indicado por el plan, pero en la DB local no existe ninguna fila con ese `type` (las filas de origen legacy tienen type NULL y `source` con legacy). La rama de apertura legacy hoy no se activa; si se quiere usarla de verdad habra que definir como se identifica esa apertura.
- La ventana grande (todo el ano) genera ~61k filas para store 6; el servicio debe refrescar por ventana (watermark) como previsto.
- Productos con `product_id` NULL en sale_items quedan fuera (Deferred).

## CODEX

No se consulto CODEX manualmente; el hook post-commit lo lanza en segundo plano (`.team/reviews/auto-*.md`). Pendiente de leer antes de 119-13. No hubo push ni escritura en produccion.

## Known Stubs

None.

## Self-Check: PASSED
