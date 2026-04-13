---
phase: 15-materia-prima
plan: "06"
subsystem: frontend/materia-prima
tags: [dashboard, charts, css-only, materia-prima, refactoring]
dependency_graph:
  requires:
    - 15-05 (constants.ts, KpiCard.tsx component library)
  provides:
    - CategoryDistributionChart component (CSS-only vertical bar chart)
    - DebtSummaryChart component (horizontal bar chart)
    - Refactored MateriaPrimaDashboardView with 2-col grid layout
  affects:
    - ventago-app/src/views/materia-prima/MateriaPrimaDashboardView.tsx
tech_stack:
  added: []
  patterns:
    - CSS-only bar charts (no external chart library) using MUI Box
    - 2-column CSS grid layout for responsive dashboard
    - Proportional bar height calculation (maxCount normalization)
key_files:
  created:
    - ventago-app/src/views/materia-prima/components/CategoryDistributionChart.tsx
    - ventago-app/src/views/materia-prima/components/DebtSummaryChart.tsx
  modified:
    - ventago-app/src/views/materia-prima/MateriaPrimaDashboardView.tsx
decisions:
  - CSS-only bar charts using MUI Box — avoids chart library dependency per D-06/D-07 spec
  - distribucionCategoria and deudaPorProveedor as optional fields with empty-array fallback — backend may not return them yet
  - Critical alerts (stock=0) get red border (#DC2626) + #FEF2F2 background; warning alerts get amber border (#F59E0B)
  - Removed stockAgotado KPI from 4-card row; replaced with Valor Inventario and Deuda Proveedores per mockup
metrics:
  duration: "~10min"
  completed_date: "2026-04-12"
  tasks_completed: 2
  files_created: 2
  files_modified: 1
---

# Phase 15 Plan 06: Dashboard Refactoring with CSS Bar Charts Summary

**One-liner:** Refactored MateriaPrimaDashboardView to 2-column grid with CSS-only vertical/horizontal bar charts (CategoryDistributionChart, DebtSummaryChart) and shared KpiCard integration.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create CategoryDistributionChart and DebtSummaryChart | 7856f91 | components/CategoryDistributionChart.tsx, DebtSummaryChart.tsx |
| 2 | Refactor MateriaPrimaDashboardView with 2-col grid layout | f343827 | MateriaPrimaDashboardView.tsx |

## What Was Built

### Task 1: Chart Components

**CategoryDistributionChart.tsx** — CSS-only vertical bar chart (per D-06):
- Props: `{ distribution: Array<{ category: string, count: number }> }`
- Proportional bar heights: `Math.max((count / maxCount) * 80, 4)px` with 4px minimum
- Bar colors from `CATEGORY_COLORS` constant (Tela/Boton/Cierre/Hilo/Accesorio)
- Container: `height: 120px`, flex row, `alignItems: flex-end` for bars to grow upward
- Count label above bar, category label below

**DebtSummaryChart.tsx** — Horizontal bar chart (per D-07):
- Props: `{ debts: Array<{ supplier: string, amount: number }> }`
- Red danger color `#DC2626` for bars and amount text
- Background track `#FEE2E2`, fill `#DC2626`
- Bar width proportional to maxAmount: `(amount / maxAmount) * 100%`
- Amounts formatted with `toLocaleString('es-CO')`
- Last row has no bottom border

### Task 2: Dashboard Refactoring

**MateriaPrimaDashboardView.tsx** — Complete redesign per D-05, D-06, D-07, D-08:
- Page title with `tabler:layout-dashboard` icon (fontSize 22, fontWeight 700)
- 4-column KPI row using shared `KpiCard` component: Total Materiales (blue), Stock Bajo (orange), Valor Inventario (green), Deuda Proveedores (red)
- First 2-col row: Alertas de Stock (left) + CategoryDistributionChart (right)
- Second 2-col row: DebtSummaryChart (left) + Ultimos Movimientos table (right)
- Alert critical styling: `borderLeft: '4px solid #DC2626'`, background `#FEF2F2`
- Alert warning styling: `borderLeft: '4px solid #F59E0B'`
- Movements table with `tabler:arrow-up`/`tabler:arrow-down` icons in colored Chips
- `DashboardData` interface expanded with optional `distribucionCategoria` and `deudaPorProveedor`

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

- `distribucionCategoria` and `deudaPorProveedor` fields are optional with `|| []` fallback. If the backend `/materia-prima/dashboard` endpoint does not yet return these fields, the charts render as empty (0 bars). This is intentional per plan spec — backend integration is a separate concern.

## Threat Flags

None. Pure display-only refactoring. No new network endpoints, auth paths, or data mutation paths introduced. CSS-only rendering with no external library attack surface per T-15-04.

## Self-Check: PASSED

Files created:
- ventago-app/src/views/materia-prima/components/CategoryDistributionChart.tsx — FOUND
- ventago-app/src/views/materia-prima/components/DebtSummaryChart.tsx — FOUND
- ventago-app/src/views/materia-prima/MateriaPrimaDashboardView.tsx — MODIFIED

Commits verified:
- 7856f91 — feat(15-06): create CategoryDistributionChart and DebtSummaryChart components
- f343827 — feat(15-06): refactor MateriaPrimaDashboardView with 2-col grid layout

ESLint: All 3 files pass with 0 errors.
