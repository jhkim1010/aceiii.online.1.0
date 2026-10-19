---
phase: 119-predicci-n-de-ventas-y-recomendaci-n-de-producci-n-qu-cu-nta
plan: 12
subsystem: ui
tags: [nextjs, mui, swr, apexcharts, reportes-v2, prediccion]
requires: [119-11]
provides:
  - "Pestañas Backtest, Simulación y Configuración en «Predicción y producción»"
  - "Ⓒ gráfico real vs pronóstico y Ⓓ cuenta de 7 pasos"
  - "Botón «Recalcular ahora» con estado de la cadena en DB"
affects: [119-13]
key-files:
  created:
    - ventago-app/src/views/reports-v2/prediccion/BacktestTab.tsx
    - ventago-app/src/views/reports-v2/prediccion/BacktestSeriePanel.tsx
    - ventago-app/src/views/reports-v2/prediccion/SimulacionTab.tsx
    - ventago-app/src/views/reports-v2/prediccion/TrazaSimulacionPanel.tsx
    - ventago-app/src/views/reports-v2/prediccion/ConfiguracionTab.tsx
    - ventago-app/src/views/reports-v2/prediccion/ChipCorrida.tsx
  modified:
    - ventago-app/src/views/reports-v2/prediccion/PrediccionBody.tsx
    - ventago-app/src/views/reports-v2/prediccion/prediccion-logica.ts
    - ventago-app/src/hooks/api/usePrediccion.ts
    - ventago-app/src/__tests__/prediccion-logica.spec.ts
decisions:
  - "Las filas de métricas/simulación de la API son snake_case crudas (SQL directo); los tipos del front las reflejan, no el camelCase del plan"
  - "El gráfico Ⓒ muestra un origen a la vez (x = semanas +1..+H); la fecha del origen va en la anotación"
metrics:
  completed: 2026-10-19
  tasks: 3
---

# Phase 119 Plan 12: Backtest, Simulación y Configuración Summary

Tres pestañas nuevas sobre /prediccion/*: métricas WAPE/Bias/MASE con gráfico real vs pronóstico, simulación CR × MOQ con la cuenta paso a paso de la combinación explicada, configuración de la tienda y recálculo manual, todo con chip «SINTÉTICO» (descargo en tooltip) y UI compacta.

## Commits (ventago-app, repo anidado)
- 224680e3 feat(119-12): pestañas Backtest, Simulación y Configuración con gráfico Ⓒ y cuenta Ⓓ

Sin push (regla de la fase).

## Verificación
- jest prediccion-logica: 23 passed (12 de 119-11 + 12 nuevos incluidos textoWape, textoFillRate sin «promedio», 3 etiquetas, 7 filas de traza, serieGrafico, test que prohíbe «verificado»).
- tsc 0 errores; eslint 0 errores/warnings.
- Greps: severity info 0, rowHeight 0, «promedio» en TrazaSimulacionPanel 0, /prediccion/ejecutar 1, package.json sin cambios.
- NO se probó en navegador ni se corrió next build.
- CODEX: NO se consultó en este plan (omitido; pendiente antes de 119-13).

## Deviations from Plan

1. **Un solo commit** en vez de uno por tarea: las tres tareas tocan los mismos archivos (lógica, hooks, BacktestTab, SimulacionTab) y se escribieron juntas; TDD condensado como en 119-11.
2. **[Rule 1] Tipos snake_case**: la API devuelve filas SQL crudas (`horizon_bucket`, `fill_rate`, `moq_politica`, ...), no camelCase como decía la sección interfaces; los tipos y columnas usan snake_case.
3. **«Ver cuenta»** es un botón en la fila de la combinación explicada (`params.trazaCombinacion`) en vez de clic en la «fila candidata», porque la traza sólo existe para esa combinación (puede ser CR por defecto o 0,9).
4. **Gráfico Ⓒ por origen**: elige un origen y muestra +1..+H semanas; el selector de series de nivel modelo usa los 50 modelos más vendidos (la API no lista claves de serie).

## Known Stubs
Ninguno.

## Threat Flags
Ninguno nuevo. T-119-35/36/37 mitigados (chip + test, polling sólo con enCurso, Yup con rangos del DTO).

## Self-Check: PASSED
Commit 224680e3 existe en ventago-app; los 6 archivos nuevos presentes.
