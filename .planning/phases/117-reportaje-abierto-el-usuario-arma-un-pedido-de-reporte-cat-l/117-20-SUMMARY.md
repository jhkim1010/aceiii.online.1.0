---
phase: 117-reportaje-abierto-el-usuario-arma-un-pedido-de-reporte-cat-l
plan: 20
subsystem: ui
tags: [reporte-medida, constructor, chips, accesibilidad]
requires: ["117-15", "117-16", "117-17"]
provides:
  - "pasos/ChipOpcion, ListaRazones, TipoDatos, PasoCard, PasoMetricas, PasoAgrupaciones, PasoComparacion"
affects: [117-22]
key-files:
  created:
    - ventago-app/src/views/reports-v2/a-medida/pasos/ChipOpcion.tsx
    - ventago-app/src/views/reports-v2/a-medida/pasos/ListaRazones.tsx
    - ventago-app/src/views/reports-v2/a-medida/pasos/TipoDatos.tsx
    - ventago-app/src/views/reports-v2/a-medida/pasos/PasoCard.tsx
    - ventago-app/src/views/reports-v2/a-medida/pasos/PasoMetricas.tsx
    - ventago-app/src/views/reports-v2/a-medida/pasos/PasoAgrupaciones.tsx
    - ventago-app/src/views/reports-v2/a-medida/pasos/PasoComparacion.tsx
decisions:
  - "PasoCard extraído como contenedor común de paso (círculo numerado + título + caption)"
  - "Pasar el mouse sobre un chip de métrica también muestra su definición, para que los chips bloqueados (no clickeables) la muestren"
metrics:
  completed: 2026-10-18
---

# Phase 117 Plan 20: Pasos 1, 2 y 4 y selector de tipo Summary

Componentes presentacionales del constructor: chip accesible con bloqueo visible (ícono tabler + motivo escrito en ListaRazones), Paso 1 (métricas, definición siempre visible, aviso de margen, automáticas «+»), Paso 2 (agrupaciones con Select «Tiempo por» y aviso de métricas quitadas), Paso 4 (comparación con rango orientativo; el real prevalece) y selector de tipo de datos. Los bloqueos salen de estadoMetricas/estadoDimensiones; el JSX no decide reglas.

## Commits (ventago-app, no pusheados)
- 161b3c9a: ChipOpcion, ListaRazones, TipoDatos
- 80e7a416: PasoCard, PasoMetricas, PasoAgrupaciones
- 41d1fe2a: PasoComparacion

## Verificación
- app tsc exit 0; eslint de pasos/ exit 0 (también vía hook de commit).
- Gates grep: sin emojis, sin isAdmin/roles/permissions, sin labels fijos de métricas; cadenas de copy presentes.
- No se probó en navegador (se monta en 117-22).

## Deviations from Plan
- [Rule 3] Se agregó PasoCard.tsx (no listado en files_modified) para no duplicar el contenedor numerado en tres pasos.

## Known Stubs
Ninguno. `onAlternar` de TipoDatos es un no-op intencional (sólo ventas existe).

## Self-Check: PASSED
