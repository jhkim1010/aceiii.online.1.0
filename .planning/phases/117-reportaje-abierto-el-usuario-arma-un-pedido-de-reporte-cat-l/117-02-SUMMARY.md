---
phase: 117-reportaje-abierto-el-usuario-arma-un-pedido-de-reporte-cat-l
plan: 02
subsystem: permissions
tags: [sql, migrations, permissions, multitenant]
requires: []
provides:
  - "functions reporte-a-medida y reporte-a-medida-margen (sólo admin)"
  - "tabla reporte_medida_pedidos (local)"
affects: [117-03, 117-10, 117-12]
key-files:
  created:
    - api-ventago/migrations/2026-10-17-reporte-medida-a-permisos.sql
    - api-ventago/migrations/2026-10-17-reporte-medida-b-pedidos.sql
  modified:
    - api-ventago/src/app/store/store-defaults.constants.ts
    - api-ventago/src/app/store/funciones-solo-admin.spec.ts
    - api-ventago/src/app/store/store-backup-coverage.ts
    - api-ventago/src/app/store/store-backup-inventory.txt
    - api-ventago/src/app/store/vaciado/vaciado-catalogo.ts
    - api-ventago/src/app/store/store-restore-unlinked-refs.ts
    - api-ventago/src/app/store/store-restore-manifest.spec.ts
    - api-ventago/src/app/store/store-restore-{columns,fk-catalog,trigger-catalog,unique-catalog,unlinked-refs}.txt
    - .planning/intel/db-schema-tables.md
key-decisions:
  - "Margen es función propia admin-only, no hereda de reporte-ganancia"
requirements-completed: [D-05, D-07, D-12, D-15, D-16, D-27, D-29]
completed: 2026-10-17
---

# Phase 117 Plan 02: permisos y tabla de pedidos Summary

Dos migraciones aplicadas SOLO en la DB local (PG18 5432), más FUNCIONES_SOLO_ADMIN y registros de tabla. Sin push, sin escrituras en producción.

## Commits (api-ventago, NO pusheado)
- `1a680a6e` migraciones permiso + tabla
- `703d9d03` sólo-admin + registros + catálogos de restauración

## Verificación
- Local: 2 funciones; 36 tiendas con concesión `read` cada una; 0 concesiones a roles no admin.
- Tabla `reporte_medida_pedidos` existe; owner = coolsistema (el rol existe localmente), secuencia también.
- migration-conventions spec: 9/9. `jest src/app/store`: 36 suites / 511 tests, exit 0.
- Mutación: quitar `reporte-a-medida-margen` de FUNCIONES_SOLO_ADMIN hizo fallar la spec (exit 1); restaurado, pasa.
- intel regenerado (`db-schema-tables.md`; fks sin cambios).

## Deviations from Plan

**1. [Rule 3 - Bloqueo] Catálogos de restauración**
- El gate de commit falló (`store-restore-plan`, `store-restore-manifest`, `store-restore-identity`): la tabla nueva debe declararse también para restauración.
- Fix: regeneré los 4 scripts `regen-restore-*`, subí el conteo de manifest 177→178 y agregué dos reglas REMAP (`store_id` -> stores, `owner_user_id` -> users) en `store-restore-unlinked-refs.ts`.
- Nota: la regeneración trajo deriva de otras sesiones de la DB local (sale_payment_methods.*, sales.invoice_pending_at, wp_channels.crear_al_marcar, wp_product_sync.creado_por_ventago); es el estado real de la DB local.

**2. [Ajuste] Registro en vaciado/eliminar**
- `reporte_medida_pedidos` entró en VACIADO_CONSERVAR (nuevo bloque). `eliminar-catalogo.ts` no necesitó cambios: la spec pasa (toma SIMPLE_STORE_TABLES).
- `store-backup-sensitive-columns.txt` solo cambió el timestamp; lo revertí.

## Pendiente
- Aplicar ambos SQL en producción (plan 117-03, requiere aprobación) ANTES del push de 117-12.

## Known Stubs
Ninguno.

## Self-Check: PASSED
