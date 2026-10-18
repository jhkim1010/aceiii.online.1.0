---
phase: 117-reportaje-abierto-el-usuario-arma-un-pedido-de-reporte-cat-l
plan: 01
subsystem: reports
tags: [sql, reports, tdd, multitenant, venta]
requires: []
provides:
  - "venta-universe.ts: ventaHeaderCte, itemsAggCte, devolucionesLocalCte, fuentesSql, posiblesDuplicadosSql, VENTA_DEFINICION_ES, VentaPlaceholders"
affects: [117-07, 117-09]
tech-stack:
  added: []
  patterns: ["builders de CTE con placeholders de bind (nunca valores)", "itest con Sequelize directo sin app Nest"]
key-files:
  created:
    - api-ventago/src/app/reports/venta-universe.ts
    - api-ventago/src/app/reports/venta-universe.spec.ts
    - api-ventago/src/app/reports/venta-universe.itest.ts
  modified: []
key-decisions:
  - "fuentesSql cuenta tickets netos con signo (SUM(sgn)), igual que signedTxSql"
  - "Duplicados legacy-POS: mismo total, <=300 s, mismo multiconjunto producto x cantidad (sin dedupe en el universo, D-28)"
  - "Rango grueso e índice sobre s.sale_date (0 filas con sale_date NULL en prod y local, verificado)"
requirements-completed: [D-01, D-02, D-03, D-17, D-26, D-28, D-30]
duration: ~70min
completed: 2026-10-17
---

# Phase 117 Plan 01: Universo «venta» compartido Summary

Fragmento SQL único de «venta» (tienda primero, solo `sale`, estados contables, sin cobros de deuda, día local, unión legacy+POS sin dedupe) con spec de cadenas, itest sobre PG18 local y monitor de duplicados legacy-POS.

## Commits (api-ventago, NO pusheado)
- `3f309f2d` feat(117-01): shared venta universe fragment (venta-universe.ts + spec)
- `dcdbaeb9` test(117-01): itest venta universe on local PG18

## RED
Spec escrito primero; con el módulo apartado, `npx jest src/app/reports/venta-universe --maxWorkers=1` salió con exit 1 y
`TS2307: Cannot find module './venta-universe'` (0 tests). Fallo por módulo ausente, no por sintaxis ni OOM.
GREEN: 16/16 tests.

## Verificación
- jest spec: 16 passed (incluye 2 controles: helper falla sin predicado de tienda / con tienda fuera de orden).
- `npm run test:itest -- venta-universe --forceExit`: 11 passed (exit 0).
- `tsc --noEmit`: exit 0. eslint: exit 0.
- Greps de aceptación: 6 exports, 1 import de `./sale-status.constants`, 0 `sale_date)::date` fuera de comentarios.
- **Mutación**: `s.store_id = ${p.store}` -> `${p.store} IS NOT NULL` en `ventaHeaderCte`: itest FAILED (2 casos: «tenant» y «unión de fuentes»; mut exit=1). Restaurado: PASSED (`git diff` vacío del archivo).

## Deviations from Plan

**1. [Rule 3 - Bloqueo] El harness compartido no levanta**
- **Found during:** Task 2
- **Issue:** `createImportHarness` falla con `Nest can't resolve dependencies of the WebsocketGateway (… SocketCensusService)`. Importando `SocketCensusModule` (global) en el harness el proceso agotó 4 GB de heap (OOM). Ya estaba roto para otros itests (`sales-revert-nullify.itest.ts` lo documenta).
- **Fix:** El itest usa una conexión `Sequelize` directa (sin modelos, SQL crudo) con el mismo patrón de `sales-revert-nullify.itest.ts`; `createDummyStore(..., { conDefaults: false })` y se crean a mano sucursal, caja, terminal, cliente, store_client y medio de pago. `test/itest/harness.ts` quedó sin modificar (cambio probado y revertido).
- **Files:** venta-universe.itest.ts. **Commit:** dcdbaeb9
- **Nota:** `--forceExit` necesario por handles abiertos de jest; el comando del plan (`npm run test:itest -- venta-universe`) sin él también pasa los tests pero puede tardar en cerrar.

**2. [Orden TDD] Implementación escrita antes de la spec** — se apartó el módulo para registrar el RED real antes de restaurarlo. Sin impacto.

## Known Stubs
Ninguno.

## Threat Flags
Ninguno (solo builders de SQL con placeholders; sin endpoints nuevos).

## Notas
- Tiendas `ZZ-VU-A` / `ZZ-VU-B` quedan en la DB local (artefactos conservados; se limpian al inicio de la próxima corrida).
- `box_operations.amount` tiene CHECK no negativo: el reintegro se inserta positivo (la fórmula usa ABS).
- CODEX no solicitado por el plan; no se consultó.

## Self-Check: PASSED
