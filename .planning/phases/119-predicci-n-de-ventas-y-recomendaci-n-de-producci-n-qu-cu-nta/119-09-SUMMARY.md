---
phase: 119-predicci-n-de-ventas-y-recomendaci-n-de-producci-n-qu-cu-nta
plan: 09
subsystem: api
tags: [forecast, analisis, itest, tenant-isolation]
requires: [119-01, 119-05, 119-06, 119-15]
provides:
  - resolverTiendaForecast (portero de tienda)
  - ForecastAnalisisService (resumenModelos, curvaTalles, atributos, listaAtributos, fundamentoModelo)
affects: [119-10, 119-11]
key-files:
  created:
    - api-ventago/src/app/forecast/forecast-scope.ts
    - api-ventago/src/app/forecast/forecast-scope.spec.ts
    - api-ventago/src/app/forecast/analisis/analisis.sql.ts
    - api-ventago/src/app/forecast/analisis/forecast-analisis.service.ts
    - api-ventago/src/app/forecast/analisis/forecast-analisis.itest.ts
requirements-completed: [D-03, D-06, D-07, D-08, D-12]
completed: 2026-10-19
---

# Phase 119 Plan 09: Analisis C y portero de tienda Summary

Servicio de analisis sin pronostico (resumen por modelo, curva de talles, atributos con mejores/peores simetricos, fundamento con terminos) sobre tablas agregadas, mas el portero `resolverTiendaForecast` con las 4 ramas de `resolveScopedStoreId`.

## Commits (api-ventago, sin push)

- `28d6957a` portero + spec (8 tests)
- `a9baac0f` servicio, SQL e itest (8 tests)

## Verificacion

- `forecast-scope.spec.ts`: 8/8. `npm run test:itest -- forecast-analisis`: 8/8 (A sell-through 0.8 y fuente talleres, B neto 55 con devolucion, atributos fabric/fabric_fit, curva S-M-L, fundamento con los mismos numeros que el resumen, tramos de quiebre, semana excluida 2026-05-18, tickets tal cual, modelo ajeno -> 404, aislamiento entre tiendas).
- tsc y eslint de `src/app/forecast` limpios; 0 `FROM sales`; 0 `products.stock`.
- El commit gate (hook) paso en ambos commits sin `SKIP_VERIFY`.

## Decisiones y desviaciones

1. **[Definicion] Dia sin stock a nivel modelo.** El plan decia contar (par, dia) en el resumen y dias en el fundamento. Para que ambos coincidan exactamente se usa una sola definicion: un dia cuenta si TODAS las filas (sucursal x variante) del modelo ese dia estan `sin_stock`; indeterminado si todas lo estan; mezcla no cuenta. `tramos[].sucursal` vale `'todas'`.
2. **[Definicion] Semanas excluidas.** Usan la misma formula que el backtest (filas sin_stock / filas no indeterminadas de la semana, nivel modelo) con `CUOTA_CENSURA` de `forecast.constants.ts`.
3. **[Simplificacion] Paginacion en TS.** El plan sugeria LIMIT/OFFSET en SQL; se ordena y recorta en TS porque `sell_through` es derivado (ingreso viene de talleres) y hay cientos de modelos (D-06). `listaAtributos` si pagina en SQL.
4. **[Fixture] Devolucion de B.** Se sembro B con 60 bruto y 5 devueltas (neto 55); por eso el sell-through del grupo `pano` es 175/300 y no 0.6 literal.
5. **Fallback de tickets.** Si `forecast_modelo_tickets` no tiene fila del modelo, `vendido` cae a la suma del agregado y `tickets` queda null.
6. `ingresoFuente` de un modelo con fuentes mixtas entre variantes: prioridad talleres > legacy_ingreso > ingreso_stock.
7. El cableado en `ForecastModule` (providers/controller) queda para 119-10, como en 119-06.

## CODEX

No se consulto CODEX manualmente en este plan; el hook post-commit lo lanza en segundo plano (`.team/reviews/auto-*.md`). Pendiente de leer antes de 119-13. Sin push, sin escritura ni DDL en produccion.

## Known Stubs

None.

## Self-Check: PASSED
