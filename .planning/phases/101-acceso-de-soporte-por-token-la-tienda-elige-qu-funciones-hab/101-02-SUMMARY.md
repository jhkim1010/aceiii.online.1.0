---
phase: 101-acceso-de-soporte-por-token-la-tienda-elige-qu-funciones-hab
plan: 02
subsystem: database
tags: [migrations, agent-scopes, support-sessions, menu, permissions]
requires: [101-01]
provides:
  - "agent_action_policies CHECK con 8 alcances + 5 politicas enabled=TRUE para agent@app"
  - "support_sessions.grant_id / viewer_claim / viewer_seen_at (nullable)"
  - "modulo admin token-soporte (/admin/token-soporte) + funcion generar-token-soporte solo rol admin"
  - "rolPuedeRecibirFuncion / FUNCIONES_SOLO_ADMIN (tiendas nuevas + backfill de /me)"
affects: [101-19, frontend token-soporte]
key-files:
  created:
    - api-ventago/migrations/2026-10-08-b-agente-alcances-ver.sql
    - api-ventago/migrations/2026-10-08-c-support-sessions-agente.sql
    - api-ventago/migrations/2026-10-08-d-menu-token-soporte.sql
    - api-ventago/src/app/store/funciones-solo-admin.spec.ts
  modified:
    - api-ventago/src/app/store/store-defaults.constants.ts
    - api-ventago/src/app/store/storeTemplate.service.ts
    - api-ventago/src/app/auth/auth.service.ts
    - .planning/intel/db-schema-tables.md
    - .planning/intel/db-schema-fks.md
key-decisions:
  - "Politicas nuevas enabled=TRUE (D-21)"
  - "Funcion del menu solo para slug='admin', mismo origen que exigirAdminDeTienda"
requirements-completed: [D-02, D-11, D-14, D-17, D-19, D-21]
completed: 2026-10-08
---

# Phase 101 Plan 02: Migraciones de alcances, sesiones y menu Summary

Tres migraciones aditivas aplicadas en LOCAL (5432) e idempotentes, mas el filtro `rolPuedeRecibirFuncion` para que solo el rol admin reciba la funcion del menu en tiendas nuevas y en el backfill de /me.

## Commits
- api-ventago 2b05901f: migraciones b/c/d + rolPuedeRecibirFuncion + spec (sin push)
- raiz: intel regenerado + este SUMMARY

## Verificacion (local 5432)
- CHECK: 8 valores (cert, usuarios_terminales, legacy, ver_ventas, ver_productos, ver_facturas, ver_admin, sesion_remota).
- agent@app: 8 politicas, todas enabled=t.
- support_sessions: grant_id, viewer_claim, viewer_seen_at, todas nullable.
- `generar-token-soporte` -> `/admin/token-soporte|generar-token-soporte|21` (21 tiendas, 21 acciones read).
- Segunda ejecucion de cada archivo: exit 0, `INSERT 0 0` (sin duplicados).
- migration-conventions.spec: 9/9. jest src/app/store: 28 suites / 431 tests exit 0. tsc exit 0.
- Control: renombrar la llamada en storeTemplate -> funciones-solo-admin.spec falla (exit 1); restaurado.
- Mediciones: agent_action_policies 3 filas (local y prod), support_sessions 0 filas (local y prod), lectura.

## Deviations from Plan
- Archivo c: el plan decia "N filas en produccion"; medido 0, anotado asi.
- Prettier reformateo una linea preexistente de store-defaults.constants.ts; se revirtio para no tocar codigo ajeno.

## Pendiente
Produccion (5434) NO aplicada: queda para 101-19 con aprobacion. Orden b -> c -> d, antes del deploy.

## Self-Check: PASSED
