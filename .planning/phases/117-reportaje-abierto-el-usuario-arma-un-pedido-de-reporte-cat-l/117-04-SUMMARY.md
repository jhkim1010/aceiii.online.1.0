---
phase: 117-reportaje-abierto
plan: 04
subsystem: api
tags: [reporte-medida, catalog, period, pure-functions]
requires: []
provides:
  - "api-ventago/src/app/reporte-medida: order.types, consulta.types, catalog/catalog, catalog/templates, period"
affects: [117-05, 117-06, 117-07, 117-08, 117-11]
tech-stack:
  added: []
  patterns: ["catalogo como datos", "fechas puras sobre YYYY-MM-DD con getUTC*"]
key-files:
  created:
    - api-ventago/src/app/reporte-medida/order.types.ts
    - api-ventago/src/app/reporte-medida/consulta.types.ts
    - api-ventago/src/app/reporte-medida/catalog/catalog.ts
    - api-ventago/src/app/reporte-medida/catalog/templates.ts
    - api-ventago/src/app/reporte-medida/catalog/catalog.spec.ts
    - api-ventago/src/app/reporte-medida/period.ts
    - api-ventago/src/app/reporte-medida/period.spec.ts
key-decisions:
  - "METRICA_IDS / DIMENSION_IDS / FILTRO_IDS / PRESET_IDS son arrays const en order.types.ts y los tipos derivan de ellos"
  - "Enlace de Stock actual usa registryId 'stocks' (slug real del registry del front)"
requirements-completed: [D-08, D-09, D-10, D-11, D-14, D-16, D-18, D-20, D-21, D-23, D-29, D-30, D-31, D-31a, D-32]
duration: ~25min
completed: 2026-10-17
---

# Phase 117 Plan 04: Catálogo y períodos de Reporte a medida Summary

Catálogo semántico como datos (métricas con bloqueos por grano, dimensiones, filtros, límites, plantillas D-23) y resolvedor puro de períodos con comparación alineada por día de la semana o por calendario (D-31/D-31a).

## Commits (repo api-ventago, sin push)
- ab8b06ea: tipos, catálogo y plantillas (+ spec, 13 tests)
- 53d74aff: period.ts (+ spec, 24 tests; también pasa con TZ=Asia/Seoul)

## Verificación
- jest `src/app/reporte-medida` --maxWorkers=1: 37 passed (exit 0)
- TZ=Asia/Seoul period: 24 passed
- `npx tsc --noEmit`: exit 0
- Gates grep: sin "reportaje abierto", sin 'margen' en templates, sin `new Date()` ni get* locales en period.ts

## Deviations from Plan

**1. [Rule 3 - Bloqueo] Formato prettier exigido por el gate de commit**
- Primer commit bloqueado por eslint prettier/prettier; se corrió `eslint --fix` sólo sobre los archivos propios y se recomitió (sin SKIP_VERIFY).

**2. Error en expectativa del spec (no en el código)**
- Mi caso "ultimos_90_dias semanal" esperaba desde 2026-04-21; el cálculo correcto (−91 días) es 2026-04-20. Corregido el spec.

El RED se confirmó (el spec no compilaba por módulo inexistente) y no se commiteó solo, según la regla.

## Known Stubs
Ninguno.

## Self-Check: PASSED
Los 7 archivos existen y ambos commits están en el log de api-ventago.
