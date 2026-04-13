---
phase: 12-reportajes-cockpit
plan: "04"
subsystem: reports-finanzas-cockpit
tags: [reports, cockpit, finanzas, facturacion, gastos, cheque-estado, frontend, backend]
dependency_graph:
  requires: [12-01]
  provides: [facturacion-cockpit, gasto-cockpit, cheque-estado-cockpit]
  affects: [reports-v2/registry, reports-controller, reports-module]
tech_stack:
  added: []
  patterns:
    - raw-sql-parallel-queries
    - cockpit-body-pattern
    - kpi-strip-card-variant
    - lazy-loaded-detail-tab
key_files:
  created:
    - api-ventago/src/app/reports/reportsFacturacionCockpit.service.ts
    - api-ventago/src/app/reports/reportsGastoCockpit.service.ts
    - api-ventago/src/app/reports/reportsChequeEstadoCockpit.service.ts
    - ventago-app/src/views/reports/facturacion/hooks/useFacturacionCockpit.tsx
    - ventago-app/src/views/reports/facturacion/FacturacionCockpitBody.tsx
    - ventago-app/src/views/reports/gastos/hooks/useGastoCockpit.tsx
    - ventago-app/src/views/reports/gastos/GastoCockpitBody.tsx
    - ventago-app/src/views/reports/cheque-estado/hooks/useChequeEstadoCockpit.tsx
    - ventago-app/src/views/reports/cheque-estado/ChequeEstadoCockpitBody.tsx
  modified:
    - api-ventago/src/app/reports/reports.controller.ts
    - api-ventago/src/app/reports/reports.module.ts
    - ventago-app/src/views/reports-v2/registry.ts
decisions:
  - "Lazy-loaded detail tab pattern (useMemo trigger) instead of auto-load on mount — avoids pool hits until user clicks"
  - "ChequeEstado: stacked bar chart per day (processed/pending/bounced) instead of pie — shows temporal pattern"
  - "Gastos trend uses error.main (red) to visually distinguish expenses from revenue charts"
  - "Single cockpit endpoint per report returns summary + trend + primary aggregation in one call"
metrics:
  duration: "~70 minutes"
  completed: "2026-04-13T18:09:12Z"
  tasks_completed: 8
  files_changed: 12
---

# Phase 12 Plan 04: Finanzas Cockpit Migration Summary

Migrated 3 Finanzas reports (Facturación, Gastos, Cheque Estado) to the Cockpit pattern established in 12-01/02/03. Each report now has a backend cockpit service using raw SQL with parallel queries, a frontend hook, a cockpit body component with KPI strip + trend chart + detail table, and registry entries updated.

## Tasks Completed

| Task | Description | Commit |
|------|-------------|--------|
| 1 | reportsFacturacionCockpit.service.ts — KPI + trend + top clients + paginated facturas | c4d271c |
| 2 | reportsGastoCockpit.service.ts — KPI + trend + category breakdown + paginated gastos | c4d271c |
| 3 | reportsChequeEstadoCockpit.service.ts — KPI by status + stacked trend + paginated cheques | c4d271c |
| 4 | Wire backend — controller (6 new endpoints) + module (3 new services) | c4d271c |
| 5 | FacturacionCockpitBody + useFacturacionCockpit hook | e48f02e |
| 6 | GastoCockpitBody + useGastoCockpit hook | e48f02e |
| 7 | ChequeEstadoCockpitBody + useChequeEstadoCockpit hook | e48f02e |
| 8 | Registry: swap lazy imports + add cockpitLayout + filterSchema | b2c5d8d, 8dde840 |

## Backend Architecture

### New Services (raw SQL, pool-safe)

**reportsFacturacionCockpit.service.ts**
- `getCockpit()`: 3 parallel queries — KPI summary (curr+prev periods), daily trend, TOP 5 clients
- `getFacturas()`: paginated invoices with client + seller + payment methods

**reportsGastoCockpit.service.ts**
- `getCockpit()`: 3 parallel queries — KPI summary (curr+prev), daily trend, category breakdown (TOP 8)
- `getGastos()`: paginated expenses with category + subcategory + user

**reportsChequeEstadoCockpit.service.ts**
- `getCockpit()`: 2 parallel queries — KPI by status (processed/pending/bounced), daily stacked trend
- `getCheques()`: paginated cheque payments (slug='cheque' filter, graceful fallback)

### New Endpoints (reports.controller.ts)

| Endpoint | Guard | Service method |
|----------|-------|----------------|
| GET /reports/facturacion-cockpit | reporte-facturacion | getCockpit |
| GET /reports/facturacion-cockpit/facturas | reporte-facturacion | getFacturas |
| GET /reports/gasto-cockpit | reporte-gastos | getCockpit |
| GET /reports/gasto-cockpit/gastos | reporte-gastos | getGastos |
| GET /reports/cheque-estado-cockpit | reporte-cheque-estado | getCockpit |
| GET /reports/cheque-estado-cockpit/cheques | reporte-cheque-estado | getCheques |

## Frontend Architecture

Each cockpit body follows the SalesCockpit pattern:
- **KpiStrip (card variant)** — 4 KPI cards with delta indicators
- **Tab 0 (Resumen)**: SVG trend chart (2/3 width) + primary aggregation list (1/3 width)
- **Tab 1 (Detail)**: lazy-loaded paginated table (only fetches when tab clicked)

### Component Details

**FacturacionCockpitBody**: KPIs (Total Facturado / Facturas / Promedio / Pendientes) + daily area chart + TOP 5 clients ranking + invoices table.

**GastoCockpitBody**: KPIs (Total / Cantidad / Promedio / Categorías) + daily area chart in `error.main` (red, visually distinct from revenue) + category ranking with red bars + expenses table.

**ChequeEstadoCockpitBody**: KPIs (Total Cheques / Monto / Pendientes / Rebotados) + stacked bar chart by day (green=processed, orange=pending, red=bounced) + estado breakdown cards + cheques table with status Chip.

## Registry Changes

All 3 finanzas entries updated:
- `bodyComponent` lazy import now points to `*CockpitBody` instead of `*ReportBody`
- `filterSchema: ['sucursal', 'rangeDate']` added
- `cockpitLayout: { hasKpiStrip: true, hasDetail: false, hasDrawer: false }` added

Legacy `*ReportBody` files preserved (not deleted).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - ESLint] Fixed lines-around-comment violations in registry.ts**
- **Found during:** Task 8 verification (ESLint run)
- **Issue:** Two inline comments added without preceding blank line
- **Fix:** Added blank lines before Phase 12 Wave 04 comment blocks
- **Files modified:** ventago-app/src/views/reports-v2/registry.ts
- **Commit:** 8dde840

## Known Stubs

None. All KPI values are wired to real backend data. Detail tables fetch live data on tab click.

## Threat Flags

None. New endpoints are guarded with existing `@FunctionGuard` decorators (same permission slugs as existing legacy endpoints). No new trust boundaries introduced.

## Self-Check: PASSED

Files created:
- api-ventago/src/app/reports/reportsFacturacionCockpit.service.ts — EXISTS
- api-ventago/src/app/reports/reportsGastoCockpit.service.ts — EXISTS
- api-ventago/src/app/reports/reportsChequeEstadoCockpit.service.ts — EXISTS
- ventago-app/src/views/reports/facturacion/FacturacionCockpitBody.tsx — EXISTS
- ventago-app/src/views/reports/gastos/GastoCockpitBody.tsx — EXISTS
- ventago-app/src/views/reports/cheque-estado/ChequeEstadoCockpitBody.tsx — EXISTS

Commits verified:
- api-ventago: c4d271c
- ventago-app: e48f02e, b2c5d8d, 8dde840
