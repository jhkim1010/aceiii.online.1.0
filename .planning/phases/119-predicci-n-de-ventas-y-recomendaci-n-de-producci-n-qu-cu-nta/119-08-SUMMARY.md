---
phase: 119-predicci-n-de-ventas-y-recomendaci-n-de-producci-n-qu-cu-nta
plan: 08
subsystem: api-ventago/forecast
tags: [forecast, simulacion, politica, cron, orquestador]
requires: [119-03, 119-05, 119-06, 119-07, 119-15]
provides:
  - PoliticaRunnerService (D2, trazas de 7 pasos)
  - ForecastOrquestadorService (cadena agregado -> resumenes -> backtest -> simulacion)
  - ForecastNightlyCron (05:35 hora de tienda, sólo líder)
affects: [119-10, 119-12]
key-files:
  created:
    - api-ventago/src/app/forecast/simulacion/politica-runner.service.ts
    - api-ventago/src/app/forecast/simulacion/politica-runner.itest.ts
    - api-ventago/src/app/forecast/forecast-orquestador.service.ts
    - api-ventago/src/app/forecast/forecast-nightly.cron.ts
decisions:
  - "Errores agrupados (< 5 propios) escalados por demanda semanal media de entrenamiento, sin supuesto normal"
  - "Stock inicial sin fila o con par con actividad 'indeterminado' omite el origen"
  - "Cadena detenida por enCurso/sinDatos/omitida se cierra 'failed' con el paso en error"
metrics:
  tasks: 2
  completed: 2026-10-19
---

# Phase 119 Plan 08: Simulación de política D2 + orquestador + cron Summary

Simulación 6 CR x 2 MOQ por origen del último backtest, con candidato de CR y trazas de 7 pasos persistidas, más la cadena nocturna (cron 05:35 ART sólo líder) y «Recalcular ahora» sin await.

## Commits (repo api-ventago)
- e7e67667: PoliticaRunnerService + itest
- 81c41b4a: ForecastOrquestadorService + ForecastNightlyCron

## Qué se hizo
- **PoliticaRunnerService.correr(storeId, triggeredBy, userId?, backtestRunId?)**: toma el último backtest 'done' (o el indicado, verificando store_id), modelo_base = menor MASE (empate o sin MASE -> media_movil_4), L/WIP de talleres con fallback, protección recortada a 8 semanas, errores sin fuga vía `erroresPrevios` (llamado origen por origen para conservar una sola fuente de la regla), agrupación con escalado, 12 filas de resultados, un candidato a lo sumo, trazas de la combinación (candidato, cr_default o 0.9 fijo) en lotes de 1.000 antes del paso a 'done'. is_synthetic/disclaimer salen de `crearRun`.
- **ForecastOrquestadorService**: `ejecutarTienda`, `ejecutarTodas('cron')` (serie, log por tienda), `iniciarManual` (BadRequest si no habilitada; crea la cadena sincrónicamente; calcula sin await). `params.paso` se actualiza al empezar cada paso.
- **ForecastNightlyCron**: `@Cron('35 5 * * *', { name: 'forecast-nightly', timeZone: DEFAULT_STORE_TZ })`, flag running, catch sin relanzar. No toca ForecastModule (lo cablea 119-10).

## Verificación
- tsc y eslint (src/app/forecast) limpios.
- itest politica-runner: 9 passed, 0 failed. Valores exactos con significado: P (stock 10, sin WIP) fill 51/84, perdidas 33, sobrante 33; W (lote IN_PROGRESS 100) fill 1, sobrante 246, orden 0; M1 constante S = 28; n de errores propios = k.
- **Mutación**: aflojar la regla sin futuro de `erroresPrevios` (+28 días) hizo fallar 4 de 9 tests; restaurado.
- Smoke de la cadena completa contra store 6 local (PG18 5432): cadena 'done', 61 orígenes ok, 14 sin_distribucion, candidato CR 0.5, trazas 75. Prueba temporal, no se commiteó.

## Deviations from Plan
None funcionales. Notas:
- El itest usa un M2 con pico cada 3 semanas (un patrón alternante de 2 semanas da error cero en ventanas de 4 semanas, test trivial).
- Commit RED separado no aplica (plan sin `tdd`); no se usó SKIP_VERIFY.

## Pendientes / límites
- **CODEX no se consultó** en este plan (no hay revisión que reportar); queda para la revisión automática post-commit / antes de push.
- Sin push, sin DDL/DML en prod, sin reinicios (deploy sólo en 119-13).
- El orquestador no tiene itest propio (el plan no lo pedía); cubierto por el smoke manual.

## Known Stubs
None.

## Threat Flags
None.

## Self-Check: PASSED
Archivos creados presentes; commits e7e67667 y 81c41b4a existen en api-ventago.
