---
phase: 12-reportajes-cockpit
plan: "05"
subsystem: reports
tags: [cockpit, inventario, stocks, corregido, movidos, fallados, ingreso, frontend, backend]
dependency_graph:
  requires: ["12-01"]
  provides: ["inventario-cockpit-bodies"]
  affects: ["reports-v2/registry", "api-ventago/reports"]
tech_stack:
  added: []
  patterns: ["raw-sql-cockpit-service", "kpi-strip-tabs-pattern", "parallel-query-pool-safe"]
key_files:
  created:
    - api-ventago/src/app/reports/reportsStocksCockpit.service.ts
    - api-ventago/src/app/reports/reportsCorregidoCockpit.service.ts
    - api-ventago/src/app/reports/reportsMovidosCockpit.service.ts
    - api-ventago/src/app/reports/reportsFalladosCockpit.service.ts
    - api-ventago/src/app/reports/reportsIngresoCockpit.service.ts
    - ventago-app/src/views/reports/stocks/StocksCockpitBody.tsx
    - ventago-app/src/views/reports/stocks/hooks/useStocksCockpit.tsx
    - ventago-app/src/views/reports/corregido/CorregidoCockpitBody.tsx
    - ventago-app/src/views/reports/corregido/hooks/useCorregidoCockpit.tsx
    - ventago-app/src/views/reports/movidos/MovidosCockpitBody.tsx
    - ventago-app/src/views/reports/movidos/hooks/useMovidosCockpit.tsx
    - ventago-app/src/views/reports/fallados/FalladosCockpitBody.tsx
    - ventago-app/src/views/reports/fallados/hooks/useFalladosCockpit.tsx
    - ventago-app/src/views/reports/ingreso/IngresoCockpitBody.tsx
    - ventago-app/src/views/reports/ingreso/hooks/useIngresoCockpit.tsx
  modified:
    - api-ventago/src/app/reports/reports.controller.ts
    - api-ventago/src/app/reports/reports.module.ts
    - ventago-app/src/views/reports-v2/registry.ts
decisions:
  - "Stocks cockpit skips date range (point-in-time snapshot); uses filter + sucursal only"
  - "Corregido/Fallados use sales.status — nullification vs nullified respectively"
  - "Movidos/Ingreso use stocks table created_at for date filtering (consistent with legacy)"
  - "All 5 services use 3 parallel raw SQL queries (getCockpit) + 2 parallel for paginated detail"
metrics:
  duration: "~55 minutes"
  completed_date: "2026-04-13T18:25:03Z"
  tasks_completed: 3
  files_created: 15
  files_modified: 3
---

# Phase 12 Plan 05: Inventario Cockpit Migration Summary

5 Inventario reports fully migrated to CockpitLayout pattern — raw SQL backend services, typed React hooks, KPI Strip + chart + detail tab UI, and registry wired to new cockpit bodies.

## What Was Built

### Backend (5 new cockpit services)

**reportsStocksCockpit.service.ts**
- `getCockpit()`: 3 parallel queries — KPI summary (total SKU / stock value / out-of-stock / low-stock / dead-stock), category value ranking (top 10), stock alert list (top 10 items with `out`/`low`/`dead` badge type)
- `getStocks()`: paginated SKU list with stock qty + value, ordered by total_stock ASC (lowest first)
- Note: no date range — stocks is a point-in-time report

**reportsCorregidoCockpit.service.ts**
- `getCockpit()`: 3 parallel queries — KPI summary with delta vs prev period, daily trend (generate_series zero-fill), user-level correction ranking
- `getCorregidos()`: paginated corrections list with client + user + nullified sale reference

**reportsMovidosCockpit.service.ts**
- `getCockpit()`: 3 parallel queries — KPI (total movements / ingreso qty / egreso qty / branch count with delta), daily ingreso+egreso trend, branch-level ranking
- `getMovidos()`: paginated stock movement list with tipo (Ingreso/Egreso)

**reportsFalladosCockpit.service.ts**
- `getCockpit()`: 3 parallel queries — KPI (nullified count / lost amount / cancellation rate % with deltas), daily bar trend, top-5 products by lost amount (via sale_items JOIN)
- `getFallados()`: paginated cancelled sales list

**reportsIngresoCockpit.service.ts**
- `getCockpit()`: 3 parallel queries — KPI (entry count / total qty / branch count / product count with deltas), daily entry trend (totalQty bars), branch-level ranking
- `getIngresos()`: paginated stock entry list (stock > 0 only)

### Frontend (5 hooks + 5 cockpit bodies)

Each cockpit body follows identical pattern:
1. `useXxxCockpit(params)` hook — `useMemo` merged params, `useEffect` auto-fetch, typed state
2. `KpiStrip` with 4 KPI cards (icons, colors, delta indicators where applicable)
3. Tab 0: Resumen — SVG chart (bar/stacked) + ranking sidebar
4. Tab 1: Detail list — lazy-loaded paginated MUI table via secondary API endpoint

**Specific visualizations:**
- Stocks: category value bar ranking + alert badge list (Sin stock / Stock bajo / Dead stock)
- Corregido: daily correction bar chart + user ranking
- Movidos: split ingreso/egreso stacked bar chart + branch ranking + Chip tipo badge
- Fallados: daily cancellation bar chart + top-5 lost products ranking
- Ingreso: daily entry quantity bar chart + branch ranking

### Registry (`registry.ts`)
- All 5 inventario lazy imports swapped to new CockpitBody components
- Added `filterSchema` and `cockpitLayout` for all 5 entries
- Stocks: `filterSchema: ['sucursal', 'search']` (no date range)
- Corregido/Movidos/Fallados/Ingreso: `filterSchema: ['sucursal', 'rangeDate']`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical] Stocks cockpit omits date range**
- **Found during:** Task 1 (backend design)
- **Issue:** Stocks is a current-state snapshot, not a time-series report. The original plan mentioned "Primary: category stock value treemap" without specifying date filtering
- **Fix:** Backend `getCockpit()` accepts no startDate/endDate; controller endpoint only passes storeId/branchId/filter
- **Files modified:** reportsStocksCockpit.service.ts, reports.controller.ts, registry.ts (filterSchema uses 'search' not 'rangeDate')

## Known Stubs

None — all 5 cockpit bodies are wired to real backend endpoints with actual data.

## Self-Check: PASSED

Files verified present:
- api-ventago/src/app/reports/reportsStocksCockpit.service.ts — FOUND
- api-ventago/src/app/reports/reportsCorregidoCockpit.service.ts — FOUND
- api-ventago/src/app/reports/reportsMovidosCockpit.service.ts — FOUND
- api-ventago/src/app/reports/reportsFalladosCockpit.service.ts — FOUND
- api-ventago/src/app/reports/reportsIngresoCockpit.service.ts — FOUND
- ventago-app/src/views/reports/stocks/StocksCockpitBody.tsx — FOUND
- ventago-app/src/views/reports/corregido/CorregidoCockpitBody.tsx — FOUND
- ventago-app/src/views/reports/movidos/MovidosCockpitBody.tsx — FOUND
- ventago-app/src/views/reports/fallados/FalladosCockpitBody.tsx — FOUND
- ventago-app/src/views/reports/ingreso/IngresoCockpitBody.tsx — FOUND

Commits verified:
- api-ventago auto-commit: 902cec2 (all 5 backend services + controller + module)
- ventago-app partial auto-commit: 0d94cf8 (StocksCockpitBody + CorregidoCockpitBody + all 5 hooks)
- ventago-app final commit: 5572ebe (FalladosCockpitBody + IngresoCockpitBody + MovidosCockpitBody + registry.ts)
- Parent repo commit: 9adc526
