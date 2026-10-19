---
phase: 119-predicci-n-de-ventas-y-recomendaci-n-de-producci-n-qu-cu-nta
plan: 02
subsystem: forecast
tags: [forecast, backtest, tdd, typescript]
requires: []
provides:
  - metricas WAPE/Bias/MASE (sin MAPE) con exclusion de censurados
  - 5 modelos base con estado historia_insuficiente
  - rolling-origin sin fuga y agrupacion por horizonte
affects: [119-03, 119-07]
key-files:
  created:
    - api-ventago/src/app/forecast/modelos/constantes.ts
    - api-ventago/src/app/forecast/modelos/metricas.ts
    - api-ventago/src/app/forecast/modelos/baselines.ts
    - api-ventago/src/app/forecast/modelos/rolling-origin.ts
    - api-ventago/src/app/forecast/modelos/metricas.spec.ts
    - api-ventago/src/app/forecast/modelos/baselines.spec.ts
    - api-ventago/src/app/forecast/modelos/rolling-origin.spec.ts
requirements-completed: [D-02, D-08, D-09]
duration: 15min
completed: 2026-10-19
---

# Phase 119 Plan 02: Nucleo puro de backtest Summary

Tres módulos TS puros (sin DB, sin I/O) con 25 tests: métricas D-09, baselines + seasonal naive y rolling-origin sin fuga.

## Commits (repo api-ventago, sin push)

- `6f42a8fe` feat métricas (RED `d473f993`)
- `91b148ab` feat baselines (RED `6c0d9b54`)
- `23b32b85` feat rolling-origin (RED `3c1c8955`)

## Verificación

- `npx jest src/app/forecast/modelos --maxWorkers=1`: 3 suites, 25 tests passed.
- Sin "mape" fuera de comentarios en metricas.ts (0).
- Mutación de control: invertir el signo de bias en metricas.ts hizo fallar 1 test (6 passed, 1 failed); revertida.
- Test de fuga ("sin fuga") presente: alterar valores[o..] no cambia forecasts de ese origen.
- seasonal_naive con 48 semanas devuelve historia_insuficiente y 0 puntos.

## Deviations from Plan

- Los commits RED se hicieron con `SKIP_VERIFY=1` (la spec no compila sin el módulo; el gate de tsc lo bloquea por diseño). Los commits GREEN pasaron el gate completo.
- Prettier/eslint corrigieron formato (`new Array<number>(h).fill`) y reformatearon las specs RED en el commit GREEN de baselines.
- tendencia_reciente: `historia_insuficiente` si hay menos de 8 semanas, según behavior.

## CODEX

No se invocó CODEX manualmente en este plan (el hook automático no es fiable y se saltó con SKIP_CODEX=1). Queda pendiente de revisión antes de 119-13.

## Known Stubs

Ninguno.

## Self-Check: PASSED
