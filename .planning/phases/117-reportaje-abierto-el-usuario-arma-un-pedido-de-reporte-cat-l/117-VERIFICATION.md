---
phase: 117-reportaje-abierto-el-usuario-arma-un-pedido-de-reporte-cat-l
verified: 2026-10-18T22:30:00Z
status: passed
score: 24/24 plans' must-haves verified (roadmap goal 8/8 truths)
overrides_applied: 0
---

# Phase 117: Reporte a medida — Verification Report

**Phase Goal:** Un usuario con el permiso abre Reportes › «Reporte a medida», arma un pedido de ventas desde un catálogo cerrado (plantillas, 4 pasos con bloqueos y motivo, resumen validado, arreglos en un clic), lo ejecuta y obtiene tabla + gráfico + comparación alineada + CSV, y lo guarda para re-ejecutarlo con un clic desde la navegación. El servidor valida (tienda por sesión, permisos, límites), compila SQL parametrizado sobre UN fragmento común de «venta», ejecuta read-only con timeout y límites de concurrencia, y revalida guardados con los permisos de quien los abre.
**Verified:** 2026-10-18
**Status:** passed
**Re-verification:** No — initial verification

Submodule HEADs match the deployed SHAs: api-ventago `33a3b43b` (#1204), ventago-app `eeede8db` (#1161). No uncommitted source changes in either submodule (only untracked `dist-*` build dirs in api).

## Goal Achievement — Observable Truths (roadmap level)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | One common SQL «venta» fragment (store first, activity_type='sale', accounting statuses, no credit payments, local day, legacy+POS union) used by every query | VERIFIED | `reports/venta-universe.ts` `ventaHeaderCte`: `s.store_id = ${p.store}` first, `SOLO_VENTA_SQL`, `ACCOUNTING_SALE_STATUSES`, `EXCLUDE_DEUDA_PAGO_SQL`, `COALESCE(sale_day_local, sale_date AT TIME ZONE tz)`, no `source` predicate; `compiler.ts` imports from `../reports/venta-universe`; `posiblesDuplicadosSql` monitor exists |
| 2 | Server validates strictly: unknown keys 400, 8 KB cap, catalog-driven blocks, Spanish messages + one-click fixes, margin 403 direct / stripped on saved | VERIFIED | `order.validator.ts` L118 `CLAVE_DESCONOCIDA`, L208-225 `Buffer.byteLength` vs `LIMITES.maxBytesPedido`, reads `bloqueadaCon` from catalog, L449-475 margin strip with `omitidas` + fix patch |
| 3 | Store from session, permission per route, margin via admin-only function, agent excluded | VERIFIED | Controller: every one of 12 handlers has `@FunctionGuard('reporte-a-medida','read')` (method level); `storeIdOfUser(user)`; `isAllowedStrict(... 'reporte-a-medida-margen')`; no `@AgentePermitido/@AgentScope` → `jwt-global.guard` 403s agent without store |
| 4 | Parametrized SQL, read-only tx, timeout 5/20 s, advisory locks tienda/usuario/global | VERIFIED | `executor.service.ts`: `SET TRANSACTION READ ONLY; SET LOCAL statement_timeout`, `pg_try_advisory_xact_lock($1::int,$2::int)` → 429 TIENDA/USUARIO/SERVIDOR_OCUPADO, 57014 → 408; compiler joins all carry `store_id = $1::int`, values via `bind` |
| 5 | Execution returns table + chart + comparison (D-31/D-31a, parcial buckets, total variation) + CSV | VERIFIED | `post-process.ts`, `period.ts` (alineación/bucketContieneHoy), front `ResultadoCard` (dynamic Tabla/Grafico), `TablaResultado` uses `FullTable` without `rowHeight`, `api.ts` `postBlob` CSV; controller `exportar-csv` endpoints |
| 6 | Constructor: 4 steps, blocked chips visible with reason, templates (Stock actual → link), sticky summary with fixes | VERIFIED | `pasos/PasoMetricas|PasoAgrupaciones` consume `estadoMetricas/estadoDimensiones`; `PasoPeriodo`, `PasoComparacion` (`comparacionLocal`), `TipoDatos`, `PlantillasCarrusel`, `BarraTuReporte` (`onAplicarFix`); templates.ts D-20 no margin, `stock_actual` with `enlace: stocks` |
| 7 | Saved reports: CRUD, share, reorder, save-as, catalog-version, re-execute with opener's permissions | VERIFIED | `pedidos.service.ts` 7× `store_id = $1`, `listar()` selects `p.order_json`; controller `pedidos/:id/ejecutar` runs with `modo:'guardado'` and current `margenPermitido`; front `MisReportesTabla` (reordenarGuardados/eliminarGuardado), `GuardarDialog`, `useGuardadoAbierto` (`Promise.all`) |
| 8 | Reachable from navigation, permission-gated, saved reports one click from the menu (D-13/D-29) | VERIFIED | `registry.ts` slug `reporte-a-medida` + `permissionSlug` (enforced in ReportsShell L38-40 and ReportsSidebar L104-106), lazy `a-medida/ReporteMedidaBody`; `nuevo/secciones.ts` section `a-medida`; ReportsSidebar «Mis reportes» (`useReporteMedidaPedidos`, max 10 + «Ver todos (n)»), badge NUEVO; `_app.tsx` tab title; `MisReportesMenu` wired in Body for «Nuevo» design |

**Score:** 8/8 roadmap truths; all 24 plans' must-have artifacts exist and all key_links matched.

## Required Artifacts

All 61 artifacts listed in the 24 PLAN frontmatters exist with substantive size (e.g. validator 874 lines, compiler 743, post-process 581, ReporteMedidaBody 425, MisReportesTabla 390, ResultadoCard 260 — min_lines thresholds met). No MISSING or STUB.

## Key Link Verification

All declared key_link patterns found (grep -a): venta-universe→sale-status.constants; migrations `perm-cache:`; FUNCIONES_SOLO_ADMIN has both slugs (used only by seeding/backfill — admin can still grant via Permisos, consistent with D-05); backup coverage `'reporte_medida_pedidos'`; validator→catalog; compiler→venta-universe; availability→`getOrLoad`; service→`compilarPedido(`; app.module→`ReporteMedidaModule`; conciliation script→`compilarPedido`; comparacion itest→`ReportsGananciaService`; front api→`postBlob(` (exists in api.service.ts); hooks→`/reporte-medida/catalogo` with 300000 dedup and null key without permission; periodo-local `Math.ceil(diasEnRango`; espejo spec reads `catalog/catalog.ts`; Body→`AccionesTopbar.useReportActionsRegistration({refresh, downloadExcel})`. Status: all WIRED.

## Data-Flow Trace (Level 4)

| Artifact | Data | Source | Real data | Status |
|---|---|---|---|---|
| ResultadoCard/Tabla/Grafico | resultado | `useEjecucionReporte` → POST /reporte-medida/ejecutar → executor SQL over `sales` | yes | FLOWING |
| ReportsSidebar «Mis reportes» | pedidos | SWR `/reporte-medida/pedidos` → `reporte_medida_pedidos` SELECT | yes | FLOWING |
| Pasos chips | catalogo | SWR `/reporte-medida/catalogo` → `construirCatalogo` + availability query (60 s cache) | yes | FLOWING |

## Behavioral Spot-Checks / Probes

| Behavior | Command | Result | Status |
|---|---|---|---|
| Front Reporte a medida + registry/secciones specs | `npx jest src/__tests__/reporte-medida src/__tests__/reportes-secciones src/__tests__/registry-nombres` | 10 suites, 153 tests passed | PASS |
| API module unit specs + venta-universe | `npx jest -i src/app/reporte-medida src/app/reports/venta-universe.spec.ts` | 14 suites, 235 tests passed | PASS |
| Prod seed admin-only | read-only psql on 5434 | both functions granted to 28 roles, all slug `admin` | PASS |
| Prod table/sequence owner | read-only psql | `coolsistema` / `coolsistema` | PASS |
| Live route deployed | `curl https://newapi.coolsistema.com/api/reporte-medida/catalogo` | 401 (not 404) | PASS |

Itests (DB-backed) not re-run here (memory policy); SUMMARYs 117-12/13 record them green and the prod reconciliation.

## Requirements Coverage

D-01..D-32 incl. D-31a are all claimed across plans' `requirements:` fields (no orphaned IDs). Spot mapping: D-01/02/17/26/28 → venta-universe; D-05/07/27 → migrations + FUNCIONES_SOLO_ADMIN + isAllowedStrict (prod verified admin-only); D-08/09/10/30 → catalog `bloqueadaCon` + validator; D-11/20/23 → templates.ts; D-12/16 → guardado mode revalidation + pedidos service (ids only, catalog_version); D-13/29 → registry/sidebar/secciones; D-14/31/31a → period.ts + periodo-local port; D-15 → save-as/rename/reorder; D-18 → TipoDatos + REPORT_TYPES; D-19 → availability; D-21 → metricasAuto; D-22 → normalizarMedioPago / «Sin …» rows; D-24/25 → process decisions (UI-SPEC approved); D-32 → visible labels. All SATISFIED.

## Anti-Patterns Found

None blocking. Grep hits for TODO/XXX are false positives (Spanish word «TODO valor» in compiler.ts comment; size ladder «XXS/XXL» in size-order.ts).

## Human Verification

Already completed (per orchestrator context): user approved prod browser steps 1-9 and 11 on 2026-10-18; step 10 (non-admin + Margen) verified locally. No new unverified items requiring human testing.

Known minor cosmetic notes recorded in 117-24-SUMMARY (not goal-blocking, pending user decision): topbar «Ejecutar» disabled on entry while validating; x-axis labels truncated; chart footer mentions dashed segment but ApexCharts draws hollow points; stray «próximamente» line under type chips.

## Gaps Summary

No gaps. The phase goal is achieved in code and in production: closed catalog, server-side strict validation with session store and permission gating, parametrized read-only compilation over a single venta fragment with timeouts and concurrency locks, result table/chart/comparison/CSV, and saved reports re-executable from navigation with the opener's permissions.

---

_Verified: 2026-10-18_
_Verifier: Claude (gsd-verifier)_
