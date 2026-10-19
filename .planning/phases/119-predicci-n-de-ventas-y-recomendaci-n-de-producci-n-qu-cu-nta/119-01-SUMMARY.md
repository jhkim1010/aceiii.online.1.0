---
phase: 119-predicci-n-de-ventas-y-recomendaci-n-de-producci-n-qu-cu-nta
plan: 01
subsystem: database
tags: [postgres, migrations, forecast, permissions]
requires: []
provides:
  - 7 tablas forecast_* / product_attributes / daily_sales_agg (local 5432)
  - funcion prediccion-produccion (admin read+update)
  - settings y atributos sinteticos de store 6
affects: [119-05, 119-06, 119-07, 119-10, 119-13]
key-files:
  created:
    - api-ventago/migrations/2026-10-19-phase119-forecast-tablas.sql
    - api-ventago/migrations/2026-10-19-phase119-forecast-permisos.sql
    - api-ventago/migrations/2026-10-19-phase119-forecast-store6-sintetico.sql
  modified:
    - .planning/intel/db-schema-tables.md
    - .planning/intel/db-schema-fks.md
requirements-completed: [D-01, D-02, D-03, D-06, D-07]
duration: 15min
completed: 2026-10-19
---

# Phase 119 Plan 01: Esquema forecast Summary

Siete tablas nuevas (sin ALTER de tablas existentes), permiso propio `prediccion-produccion` solo admin y datos de configuración/atributos sintéticos de store 6, aplicados en la DB local.

## Tasks

1. Tablas (D-06): 7 tablas, FK compuesta `(run_id, store_id)` en las 3 tablas hijas, índice único parcial de corrida `running`, owner coolsistema. Commit api-ventago `6cca1597` (junto con tareas 2).
2. Permisos + sintético store 6: función con 36 tiendas / 72 acciones / 0 concesiones no-admin; settings enabled=true y 10 product_attributes is_synthetic. Mismo commit `6cca1597`.
3. Aplicado en local 5432, intel regenerado (commit en repo raíz).

## Verificación

- migration-conventions.spec.ts: 9 passed.
- Local: 7 tablas, 1 función, `forecast_store_settings.enabled` de store 6 = t.
- Producción (5434): NO tocada (checkpoint de 119-13).

## Datos sintéticos en local

Sí quedaron aplicados en local: `seed-coolsistema-produccion.sql` y `seed-coolsistema-ventas.sql` pasaron primero en ROLLBACK (encadenados en una transacción: 2061 ventas, 2226 unidades) y luego se aplicaron de verdad (2061 ventas con nota SINTÉTICO 119 en store 6).

## Deviations from Plan

None. Nota: el commit imprimió errores de `git gc/reflog-expire` por locks viejos de ramas/worktrees phase88 en api-ventago/.git; el commit se creó igual.

## CODEX

No se consultó CODEX manualmente en este plan; el hook post-commit lo lanza en segundo plano (informe en `.team/reviews/auto-*.md`), a leer antes de cualquier push (119-13).

## Self-Check: PASSED
