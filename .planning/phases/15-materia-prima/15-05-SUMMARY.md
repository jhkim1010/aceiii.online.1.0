---
phase: 15-materia-prima
plan: "05"
subsystem: frontend/materia-prima
tags: [components, refactoring, ui, materia-prima]
dependency_graph:
  requires: []
  provides:
    - materia-prima component library (constants, KpiCard, StockBar, MaterialCard, CategoryChips)
    - refactored InventarioView using extracted components
  affects:
    - ventago-app/src/views/materia-prima/InventarioView.tsx
tech_stack:
  added: []
  patterns:
    - Extracted component pattern for materia-prima views
    - CSS grid for responsive card layout
    - Box-based progress bar (no LinearProgress dependency)
key_files:
  created:
    - ventago-app/src/views/materia-prima/components/constants.ts
    - ventago-app/src/views/materia-prima/components/KpiCard.tsx
    - ventago-app/src/views/materia-prima/components/StockBar.tsx
    - ventago-app/src/views/materia-prima/components/MaterialCard.tsx
    - ventago-app/src/views/materia-prima/components/CategoryChips.tsx
  modified:
    - ventago-app/src/views/materia-prima/InventarioView.tsx
decisions:
  - CATEGORY_COLORS map in constants.ts as single source of truth for category colors (Tela/Boton/Cierre/Hilo/Accesorio)
  - Material interface exported from MaterialCard.tsx so other views can import it
  - CSS grid used instead of MUI Grid for card layout — avoids unnecessary wrapper divs
  - categoryCounts computed in InventarioView and passed to CategoryChips for real-time counts display
metrics:
  duration: "~15min"
  completed_date: "2026-04-12"
  tasks_completed: 2
  files_created: 5
  files_modified: 1
---

# Phase 15 Plan 05: Shared Component Library + InventarioView Refactoring Summary

**One-liner:** Extracted reusable materia-prima component library (constants, KpiCard, StockBar, MaterialCard, CategoryChips) and refactored InventarioView to use them with mockup-aligned card design.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create shared components — constants, KpiCard, StockBar, MaterialCard | 969ceae | components/constants.ts, KpiCard.tsx, StockBar.tsx, MaterialCard.tsx |
| 2 | Create CategoryChips and refactor InventarioView | 9305707 | components/CategoryChips.tsx, InventarioView.tsx |

## What Was Built

### Task 1: Shared Component Library

**constants.ts** — Single source of truth for category colors:
- `CATEGORY_COLORS`: Tela=#3B82F6, Boton=#8B5CF6, Cierre=#EC4899, Hilo=#F97316, Accesorio=#14B8A6
- `KPI_COLORS`: blue, orange, green, red

**KpiCard.tsx** — Reusable KPI card with 3px top color indicator (per D-08):
- Props: label, value, color (blue/orange/green/red), subtitle
- Absolute positioned 3px color bar at top of card
- Value typography colored to match the indicator

**StockBar.tsx** — Stock status display with Box-based progress bar (per D-03):
- Props: stock, minStock
- Badge chip: Normal (green #DCFCE7/#16A34A), Bajo (orange #FEF3C7/#F59E0B), Agotado (red #FEE2E2/#DC2626)
- Box-based bar fill (no LinearProgress) with matching colors
- Numeric display: "{stock} / {minStock} min."

**MaterialCard.tsx** — Material card with category color bar (per D-01, D-02):
- 4px top color bar using `categoryColor` prop
- Code line: Tela shows "COD · Tela · Color: X · Origen: Y", others show "COD · Categoria"
- StockBar embedded in card body
- Footer: price (left) + supplier (right), separated by border-top
- Exports `Material` interface for use in other views

### Task 2: CategoryChips + InventarioView Refactoring

**CategoryChips.tsx** — Color-coded category filter chips (per D-04):
- "Todos" chip (purple #7C3AED when selected)
- Category chips with CATEGORY_COLORS when selected
- Optional `counts` prop to show item counts per category
- Toggled filled/outlined style

**InventarioView.tsx** — Refactored to use all extracted components:
- Removed: LinearProgress, Paper, Chip (category filter), Grid (replaced with CSS grid)
- Added: MaterialCard, CategoryChips, CATEGORY_COLORS imports
- CSS grid: 3 cols on lg, 2 on sm, 1 on xs
- Category counts computed and passed to CategoryChips
- Dialog form kept unchanged (working correctly)

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None. All components receive real data from API. `color`, `origin`, `quality` fields on Material are optional — shown as "-" when absent (backend may not return them yet, but this is by design per D-02).

## Threat Flags

None. Pure display-only refactoring, no new data paths or auth changes.

## Self-Check: PASSED

Files created:
- ventago-app/src/views/materia-prima/components/constants.ts — FOUND
- ventago-app/src/views/materia-prima/components/KpiCard.tsx — FOUND
- ventago-app/src/views/materia-prima/components/StockBar.tsx — FOUND
- ventago-app/src/views/materia-prima/components/MaterialCard.tsx — FOUND
- ventago-app/src/views/materia-prima/components/CategoryChips.tsx — FOUND
- ventago-app/src/views/materia-prima/InventarioView.tsx — MODIFIED

Commits verified:
- 969ceae — feat(15-05): create shared materia-prima components
- 9305707 — feat(15-05): create CategoryChips and refactor InventarioView

ESLint: All 6 files pass with 0 errors.
