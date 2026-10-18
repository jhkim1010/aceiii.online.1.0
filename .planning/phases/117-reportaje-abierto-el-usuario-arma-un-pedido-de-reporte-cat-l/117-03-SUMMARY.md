---
phase: 117-reportaje-abierto-el-usuario-arma-un-pedido-de-reporte-cat-l
plan: 03
subsystem: permissions
tags: [sql, migrations, production, permissions]
requires: [117-02]
provides:
  - "prod: functions reporte-a-medida y reporte-a-medida-margen (sólo admin, 28 tiendas)"
  - "prod: tabla reporte_medida_pedidos (owner coolsistema)"
affects: [117-10, 117-12]
key-files:
  created: []
  modified: []
key-decisions:
  - "Aplicado por el orquestador con aprobación directa del usuario en el chat («승인»); el executor rechazó una aprobación reenviada por agente"
requirements-completed: [D-05, D-27]
completed: 2026-10-17
---

# 117-03 — Migraciones de Phase 117 aplicadas en producción (PG18 5434)

## Aprobación
- Preflight read-only (executor): N admin = 28, funciones 0, tabla inexistente, módulo `dashboard-reportes` id 16, rol coolsistema existe.
- El usuario aprobó en el chat («승인») tras ver SQL + filas esperadas.
- Justo antes de aplicar: **23:33 BA (sábado)**, usuarios activos 15 min = **1** (regla diurna no aplica).

## Aplicación
| Archivo | Comando | Resultado |
|---|---|---|
| `migrations/2026-10-17-reporte-medida-a-permisos.sql` | `psql -p 5434 -v ON_ERROR_STOP=1 --single-transaction` | `INSERT 0 1` ×2 · `INSERT 0 56` (role_functions) · `INSERT 0 56` (role_function_actions) · exit 0 |
| `migrations/2026-10-17-reporte-medida-b-pedidos.sql` | `psql -p 5434 -v ON_ERROR_STOP=1` (BEGIN/COMMIT propios) | CREATE TABLE + 3 CREATE INDEX + DO (owner) · COMMIT · exit 0 |

## Verificación (prod)
- `reporte-a-medida`: 28 grants admin, **0 no-admin**, acción `read`.
- `reporte-a-medida-margen`: 28 grants admin, **0 no-admin**, acción `read`.
- Owner `reporte_medida_pedidos` y `reporte_medida_pedidos_id_seq` = **coolsistema**.
- `\d reporte_medida_pedidos` local (5432) vs prod (5434): **idéntico** (diff vacío).
- Filas de `functions` (slug, name, módulo) iguales en local y prod.

## Notas
- Sin reinicio de servicios. Sin push: el código se despliega en 117-12 (seed antes que código).
- `-- perm-cache:` sólo agrega grants (no revoca), y ningún código usa todavía estos slugs.
