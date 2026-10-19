---
phase: 119-predicci-n-de-ventas-y-recomendaci-n-de-producci-n-qu-cu-nta
plan: 11
subsystem: ui
tags: [nextjs, mui, swr, reportes-v2, prediccion]
requires: [119-10]
provides:
  - "Reportes v2 › Inventario › «Predicción y producción» (slug prediccion-produccion) con pestañas Análisis y Atributos"
  - "Ⓐ línea «Datos usados» y Ⓑ panel «Fundamento» por modelo"
  - "usePrediccion.ts (hooks SWR de /prediccion/*) y prediccion-logica.ts (lógica pura probada)"
affects: [119-12, 119-13]
key-files:
  created:
    - ventago-app/src/views/reports-v2/prediccion/prediccion-logica.ts
    - ventago-app/src/views/reports-v2/prediccion/PrediccionBody.tsx
    - ventago-app/src/views/reports-v2/prediccion/AnalisisTab.tsx
    - ventago-app/src/views/reports-v2/prediccion/AtributosTab.tsx
    - ventago-app/src/views/reports-v2/prediccion/CurvaTallesPanel.tsx
    - ventago-app/src/views/reports-v2/prediccion/DatosUsadosLinea.tsx
    - ventago-app/src/views/reports-v2/prediccion/FundamentoModeloPanel.tsx
    - ventago-app/src/hooks/api/usePrediccion.ts
    - ventago-app/src/__tests__/prediccion-logica.spec.ts
  modified:
    - ventago-app/src/views/reports-v2/registry.ts
    - ventago-app/src/views/reports-v2/nuevo/secciones.ts
decisions:
  - "PESTANAS es una constante extensible en PrediccionBody; 119-12 agrega Backtest/Simulación/Configuración y el botón en #prediccion-acciones"
  - "En el diseño nuevo la entrada va en la sección Stock (pestaña «Predicción»), exigido por reportes-secciones.spec"
metrics:
  completed: 2026-10-19
  tasks: 3
---

# Phase 119 Plan 11: Pantalla C (Análisis) y Atributos Summary

Pantalla de solo lectura sobre /prediccion/* dentro de Reportes v2: tabla de modelos con sell-through/remanente/velocidad/lead time, panel «Fundamento» con cada cifra y su cuenta, curva de talles, rendimiento por atributo con chip «Referencia» y editor opcional (solo con permiso update).

## Commits (ventago-app, repo anidado)
- 2066ea28 feat(119-11): lógica pura, hooks SWR, entrada de registro y cuerpo con pestañas
- a5b397df feat(119-11): pestañas Análisis y Atributos
- 08fb6b75 feat(119-11): línea Datos usados y panel Fundamento

Sin push (regla de la fase).

## Verificación
- jest: prediccion-logica 11 tests + reportes-secciones, 15 passed.
- tsc 0 errores; eslint 0 errores/warnings en prediccion/, usePrediccion.ts.
- Greps: rowHeight 0, severity info 0, apiConnector.get 0 en la pantalla, apiConnector.put 1.
- NO se probó en navegador ni se corrió next build (puede haber dev server).
- CODEX: NO se consultó en este plan (pendiente antes de 119-13).

## Deviations from Plan

**1. [Rule 3 - Bloqueo] Entrada en secciones.ts**
- reportes-secciones.spec exige que todo slug visible del registro esté en una sección; se agregó `prediccion-produccion` a la sección Stock. Archivo no listado en el plan.

**2. TDD condensado**: la lógica de Tasks 1 y 3 y su spec se escribieron juntas y se commitearon en el commit de Task 1 (no hay commits test/feat separados).

**3. Task 2 usa CurvaTallesPanel como panel lateral**; Task 3 lo reemplazó por FundamentoModeloPanel (que incluye la curva), tal como pedía el plan.

## Known Stubs
Ninguno.

## Threat Flags
Ninguno nuevo (solo lecturas; PUT de atributos protegido por @FunctionGuard update en 119-10).

## Self-Check: PASSED
Commits 2066ea28, a5b397df, 08fb6b75 existen en ventago-app; archivos creados presentes.
