---
phase: 117-reportaje-abierto
plan: 05
subsystem: api
tags: [reporte-medida, executor, advisory-locks, read-only, statement-timeout]
requires: ["117-04"]
provides:
  - "reporte-medida/executor.service.ts: ReporteMedidaExecutorService.ejecutar, LOCK_CLASE_TIENDA/USUARIO/GLOBAL (1170001..3), globalMax, mapearErrorPg"
affects: [117-09]
key-files:
  created:
    - api-ventago/src/app/reporte-medida/executor.service.ts
    - api-ventago/src/app/reporte-medida/executor.spec.ts
    - api-ventago/src/app/reporte-medida/executor.itest.ts
key-decisions:
  - "El tope de tiempo es de la corrida completa: cada consulta recibe SET LOCAL statement_timeout = lo que queda"
  - "idle_in_transaction_session_timeout = mismo tope, en la primera sentencia"
requirements-completed: [D-25]
completed: 2026-10-17
---

# Phase 117 Plan 05: Ejecutor de Reporte a medida Summary

Ejecutor en una transaccion READ ONLY por corrida, con timeout fijado por constantes del servidor (5 s pantalla / 20 s CSV, tope de la corrida entera), limites de concurrencia por `pg_try_advisory_xact_lock` (tienda 1, usuario 1, global 1..6 por `REPORTE_MEDIDA_GLOBAL_MAX`, default 4) y mapeo de errores PG a HTTP (57014 a 408, lock ocupado a 429 con retryAfterMs 2000, resto a 500 ERROR_CONSULTA sin SQL).

## Commits (api-ventago, NO pusheado)
- `74b72612` feat: executor.service.ts + executor.spec.ts
- `09db76f4` test: executor.itest.ts
- `0899c131` fix: deadline de corrida completa + idle_in_transaction_session_timeout (hallazgos CODEX)

## Verificacion
- jest `src/app/reporte-medida/executor --maxWorkers=1`: 8 passed (exit 0). tsc exit 0. eslint exit 0.
- `npm run test:itest -- executor --forceExit`: 6 passed (exit 0): TIENDA_OCUPADA + auto-liberacion, control con tiendas/usuarios distintos (ambos corren), USUARIO_OCUPADO, SERVIDOR_OCUPADO (GLOBAL_MAX=1), pg_sleep(7) a 408 en ~5.2 s y siguiente corrida pasa, UPDATE por el ejecutor falla con updated_at intacto (control: el mismo UPDATE en tx normal revertida si es valido).
- Greps de aceptacion: `replacements` 0, `SET TRANSACTION READ ONLY` 1, locks de sesion 0.
- Grep de clases de lock (`pg_try_advisory_xact_lock|pg_advisory_xact_lock(117` en api-ventago/src antes de escribir): 0 resultados, 1170001..3 libres.

## CODEX
Reporte: `/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/.team/reviews/117-05-codex.md`
- HIGH: statement_timeout limita cada consulta, no la corrida (N consultas = N x timeout). Corregido: deadline calculado desde el inicio, `SET LOCAL statement_timeout` con el tiempo restante antes de cada consulta, 408 si se agoto. Spec nuevo lo cubre.
- MEDIUM: sin proteccion idle-in-transaction. Corregido: `SET LOCAL idle_in_transaction_session_timeout` con el mismo tope.
- Sin otros hallazgos (xact locks aptos para pgbouncer, una conexion por corrida, READ ONLY primera sentencia).

## Deviations from Plan

**1. [Rule 3 - Bloqueo] itest sin harness**
- `test/itest/harness.ts` (DI roto, y su importacion pesada hizo que ts-jest agotara el heap: tambien `venta-universe` itest dio OOM exit 134 en esta sesion). El itest usa Sequelize directo y `new ReporteMedidaExecutorService(seq)`, y crea la tienda con `INSERT` y nombre unico por corrida `ZZ-RM-EXEC-<timestamp>` (no se borra nada). No importa harness.

**2. [Orden TDD]** La implementacion se escribio antes que el spec (RED real no registrado); spec e implementacion en un solo commit, segun la regla del plan.

## Known Stubs
Ninguno.

## Threat Flags
Ninguno nuevo.

## Notas
- Tienda dummy `ZZ-RM-EXEC-*` queda en la DB local por corrida (artefactos conservados).
- Pendiente fuera de alcance: `venta-universe.itest` con OOM por el harness en esta maquina (no tocado).

## Self-Check: PASSED
