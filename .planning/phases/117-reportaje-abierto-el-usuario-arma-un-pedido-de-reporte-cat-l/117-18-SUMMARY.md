---
phase: 117-reportaje-abierto-el-usuario-arma-un-pedido-de-reporte-cat-l
plan: 18
subsystem: ui
tags: [reporte-medida, resultado, tabla, grafico, tdd]
requires: ["117-15", "117-16"]
provides:
  - "resultado-vista.ts: columnasVista, filasVista, filaTotalVista, paginar, celdaVariacion, titularComparacion, seriesGrafico, metricasDelGrafico, avisosResultado, notasAlPie, origenVentas"
  - "TablaResultado, GraficoResultado, ResultadoCard (presentacionales, los conecta 117-22)"
affects: [117-22]
key-files:
  created:
    - ventago-app/src/views/reports-v2/a-medida/resultado/resultado-vista.ts
    - ventago-app/src/__tests__/reporte-medida-resultado.spec.ts
    - ventago-app/src/views/reports-v2/a-medida/resultado/TablaResultado.tsx
    - ventago-app/src/views/reports-v2/a-medida/resultado/GraficoResultado.tsx
    - ventago-app/src/views/reports-v2/a-medida/resultado/ResultadoCard.tsx
decisions:
  - "filasVista(filas, dims) no recibe desdeIndice: se le pasa la pagina ya recortada, asi la primera fila siempre muestra el valor"
  - "La fila Total toma la variacion de comparacion.variacionTotal (servidor), no de sumar filas"
  - "avisosResultado omite siempre la omitida 'margen' (la cubre la bandera mostrarAvisoMargen, un solo lugar)"
  - "Tramo parcial del grafico: solo punto hueco (discrete markers); el tramo punteado no se dibuja"
metrics:
  completed: 2026-10-18
---

# Phase 117 Plan 18: Card Resultado Summary

Card «Resultado» de Reporte a medida: logica pura probada (30 tests), tabla FullTable de 30 px con fila Total, grafico ApexCharts y todos los estados del UI-SPEC.

## Commits (ventago-app, no pusheados)
- 95785c08: resultado-vista.ts + spec (30 tests)
- 0f80e11a: TablaResultado + GraficoResultado
- 0af7fb58: ResultadoCard

## Verificacion
- jest 30/30; mutacion (titular desde suma de filas) hace fallar 1 test, restaurada.
- tsc app y eslint de la carpeta exit 0; sin rowHeight, sin dangerouslySetInnerHTML, sin setTimeout/setInterval; 2 `dynamic(` en ResultadoCard.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] TDD sin commit RED separado**
- El hook de commit corre tsc; una spec con modulo inexistente bloquea. Spec e implementacion van en un solo commit `feat` (igual que 117-17).

**2. [Rule 1 - Limitacion] Tramo punteado de parciales**
- ApexCharts no permite dashArray por segmento sin series extra; se marca solo el punto hueco. La nota al pie del grafico sigue el copy del UI-SPEC.

## TDD Gate Compliance
Advertencia: no hay commit `test(117-18)` previo al `feat` (ver desviacion 1).

## Known Stubs
Ninguno.

## Self-Check: PASSED
