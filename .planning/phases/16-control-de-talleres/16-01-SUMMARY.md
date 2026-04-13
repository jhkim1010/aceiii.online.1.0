---
phase: 16-control-de-talleres
plan: "01"
subsystem: talleres-ui
tags: [backend, frontend, dashboard, nestjs, nextjs, sequelize]
dependency_graph:
  requires: []
  provides:
    - GET /talleres/dashboard/stats (KPI + vendorDistribution + debtSummary + recentMovements)
    - TalleresMainView 7-tab shell with URL query state
    - DashboardTab with KPI cards + bar charts + overdue list + recent movements
  affects:
    - api-ventago/src/app/subcon/subcon.module.ts
    - ventago-app/src/pages/talleres/index.tsx
tech_stack:
  added: []
  patterns:
    - NestJS controller/service with @Auth + @GetUser storeId isolation
    - Sequelize Promise.all parallel queries with fn/col snake_case aggregation
    - CSS Grid KPI layout (repeat(4, 1fr))
    - CSS horizontal bar chart (pure MUI Box, no charting library)
key_files:
  created:
    - api-ventago/src/app/subcon/dashboard/dashboard.service.ts
    - api-ventago/src/app/subcon/dashboard/dashboard.controller.ts
    - ventago-app/src/views/talleres/components/KpiCard.tsx
    - ventago-app/src/views/talleres/components/CssBarChart.tsx
    - ventago-app/src/views/talleres/components/OverdueAlertList.tsx
    - ventago-app/src/views/talleres/tabs/DashboardTab.tsx
  modified:
    - api-ventago/src/app/subcon/subcon.module.ts
    - ventago-app/src/views/talleres/TalleresMainView.tsx
decisions:
  - SubconSettlement lacks storeId/vendorId directly — query via SubconOrder join with storeId + vendorId filter (Rule 1 adaptation)
  - Recepcion has no loteId/vendorId/etapaId — getRecentMovements includes Envio→Lote/Vendor/Etapa chain
  - pages/talleres/index.tsx and TalleresMainView.tsx were pre-existing; only DashboardTab wired in
  - OverdueAlertList data sourced from existing /talleres/envios/dashboard/overdue endpoint
metrics:
  duration: ~30min
  completed_date: "2026-04-13"
  tasks: 2
  files_changed: 8
---

# Phase 16 Plan 01: Backend Dashboard API + Tab Shell + Dashboard Tab Summary

**One-liner:** NestJS dashboard/stats API with parallel Sequelize aggregation + Next.js 7-tab TalleresMainView shell wired to DashboardTab (KPI cards, CSS bar charts, overdue alerts, recent movements table).

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Backend — Dashboard 통합 API 신규 구축 | api-ventago@fbd1514 | dashboard.service.ts, dashboard.controller.ts, subcon.module.ts |
| 2 | Frontend — Tab Shell + 공유 컴포넌트 + Dashboard Tab | ventago-app@56878df | KpiCard.tsx, CssBarChart.tsx, OverdueAlertList.tsx, DashboardTab.tsx, TalleresMainView.tsx |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Adaptation] SubconSettlement debt query via SubconOrder join**
- **Found during:** Task 1
- **Issue:** SubconSettlement model has no `storeId` or `vendorId` columns — the plan assumed direct grouping by these fields on the settlement table
- **Fix:** Query SubconSettlement with include of SubconOrder (which has `storeId` + `vendorId`), then post-process to aggregate debt by vendor in memory
- **Files modified:** api-ventago/src/app/subcon/dashboard/dashboard.service.ts
- **Commit:** api-ventago@fbd1514

**2. [Rule 1 - Adaptation] Recepcion recent movements via Envio chain**
- **Found during:** Task 1
- **Issue:** Recepcion model has no `loteId`, `vendorId`, or `etapaId` — only `envioId`. The plan specified "Recepcion include: same associations" which is not possible directly.
- **Fix:** Include Envio in Recepcion query, and within Envio include Lote, Vendor, Etapa
- **Files modified:** api-ventago/src/app/subcon/dashboard/dashboard.service.ts
- **Commit:** api-ventago@fbd1514

**3. [Rule 1 - Pre-existing files] pages/talleres/index.tsx and TalleresMainView.tsx already existed**
- **Found during:** Task 2
- **Issue:** Both files were already created (by a prior execution). TalleresMainView had a Dashboard placeholder. index.tsx already had correct uiMode toggle logic.
- **Fix:** Updated TalleresMainView to import and render DashboardTab instead of the placeholder. index.tsx needed no changes.
- **Files modified:** ventago-app/src/views/talleres/TalleresMainView.tsx
- **Commit:** ventago-app@56878df

## Known Stubs

None — all KPI and chart data is sourced live from the `/talleres/dashboard/stats` API. The OverdueAlertList sources from `/talleres/envios/dashboard/overdue` (pre-existing endpoint). No placeholder data.

## Threat Flags

No new trust boundaries introduced beyond what the plan's threat model covers. T-16-01 and T-16-02 mitigations applied:
- `@Auth(ValidRoles.admin, ValidRoles.superadmin, ValidRoles.vendedor, ValidRoles.gerente)` on TalleresDashboardController
- storeId sourced exclusively from JWT token via `@GetUser()` — not from query params

## Self-Check: PASSED

All created files verified present. Both submodule commits confirmed:
- api-ventago@fbd1514 — dashboard.service.ts + dashboard.controller.ts + subcon.module.ts
- ventago-app@56878df — KpiCard.tsx + CssBarChart.tsx + OverdueAlertList.tsx + DashboardTab.tsx + TalleresMainView.tsx
