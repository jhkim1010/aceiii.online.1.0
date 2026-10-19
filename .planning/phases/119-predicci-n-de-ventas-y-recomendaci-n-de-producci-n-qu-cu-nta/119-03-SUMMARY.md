---
phase: 119-predicci-n-de-ventas-y-recomendaci-n-de-producci-n-qu-cu-nta
plan: 03
subsystem: forecast
tags: [tdd, cuantil-empirico, politica-sim, moq, backtest]
requires: []
provides:
  - cuantilTipo7, erroresPrevios, UMBRAL_MIN_ERRORES
  - simularOrigen, agregarPolitica, elegirCandidato, CR_GRID
affects: [119-07, 119-08]
tech-stack:
  added: []
  patterns: [funciones puras, cuantil empirico sin normal]
key-files:
  created:
    - api-ventago/src/app/forecast/modelos/cuantil-empirico.ts
    - api-ventago/src/app/forecast/modelos/cuantil-empirico.spec.ts
    - api-ventago/src/app/forecast/modelos/politica-sim.ts
    - api-ventago/src/app/forecast/modelos/politica-sim.spec.ts
key-decisions:
  - "S = forecast(L+R) + cuantil tipo 7 de errores previos; sin stock de seguridad adicional"
  - "Menos de 5 errores -> sin_distribucion (orden 0, no entra al agregado)"
requirements-completed: [D-10, D-03, D-08]
duration: ~15min
completed: 2026-10-19
---

# Phase 119 Plan 03: Núcleo puro de simulación de política Summary

Cuantil empírico tipo 7 con errores previos sin fuga, y simulación diaria por origen con MOQ, lead time y WIP, más la regla de candidato de CR.

## Commits (api-ventago)
- 3809b015 test: RED cuantil-empirico (SKIP_VERIFY=1, el módulo aún no existía)
- fcc4a7e2 feat: GREEN cuantil-empirico
- b3916228 test: RED politica-sim (SKIP_VERIFY=1, mismo motivo)
- a674bc34 feat: GREEN politica-sim (gate normal)

## Verificación
- `npx jest src/app/forecast/modelos --maxWorkers=1`: 5 suites, 50 tests, 0 fallos.
- cuantil-empirico: 11 tests; grep de sqrt/stddev/zScore/1.645/1.96 fuera de comentarios = 0.
- Mutación de control: reemplazar `Math.ceil(falta / moq) * moq` por `falta` hizo fallar 2 tests; restaurado y 14/14 verde.

## Deviations from Plan
None - plan ejecutado como estaba escrito. Prettier del repo (comillas, paréntesis en arrow) se aplicó antes de los commits GREEN.

## CODEX
No se ejecutó revisión CODEX en este plan (omitida); no se afirma ninguna revisión.

## Notas
- No hubo push, DDL ni cambios en producción.
- Límites declarados en el código: demanda censurada por quiebres usada tal cual; lotes reales posteriores al origen no entran.

## Known Stubs
None.

## Self-Check: PASSED
