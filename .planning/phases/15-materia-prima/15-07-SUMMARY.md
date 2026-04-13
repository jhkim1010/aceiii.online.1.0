---
phase: 15-materia-prima
plan: "07"
subsystem: frontend/materia-prima
tags: [ui, refactoring, materia-prima, mockup-alignment]
dependency_graph:
  requires:
    - 15-05 (KpiCard, constants shared components)
  provides:
    - refactored ProveedoresView with KpiCard and mockup supplier cards
    - refactored MovimientosView with styled chips, WorkOrder dropdown (D-10)
    - refactored PagosView with KpiCard and styled table
  affects:
    - ventago-app/src/views/materia-prima/ProveedoresView.tsx
    - ventago-app/src/views/materia-prima/MovimientosView.tsx
    - ventago-app/src/views/materia-prima/PagosView.tsx
tech_stack:
  added: []
  patterns:
    - KpiCard component applied to Proveedores and Pagos KPI rows
    - CSS grid for supplier card layout
    - Box-based inline type chips (no MUI Chip dependency for movement types)
    - WorkOrder dropdown auto-fills reference field (D-10)
key_files:
  created: []
  modified:
    - ventago-app/src/views/materia-prima/ProveedoresView.tsx
    - ventago-app/src/views/materia-prima/MovimientosView.tsx
    - ventago-app/src/views/materia-prima/PagosView.tsx
decisions:
  - KpiCard used in ProveedoresView and PagosView — replaces old Grid/Card/CardContent KPI rows
  - Supplier cards use Box-based CSS grid (no MUI Grid) for responsive layout matching mockup
  - MovimientosView type chips use Box inline element with Icon — matches mockup .type-chip design
  - WorkOrder dropdown in Salida dialog auto-fills reference with OT-{id} but user can override manually (D-10)
  - Removed CardContent wrapper from MovimientosView table — Card wraps Table directly with overflow hidden
metrics:
  duration: "~20min"
  completed_date: "2026-04-12"
  tasks_completed: 2
  files_created: 0
  files_modified: 3
---

# Phase 15 Plan 07: ProveedoresView, MovimientosView, PagosView Refactoring Summary

**One-liner:** Refactored 3 materia-prima views to mockup alignment — KpiCard KPIs, mockup supplier cards, styled movement type chips, WorkOrder dropdown in Salida dialog (D-10), and styled payment tables.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Refactor ProveedoresView with KpiCard and mockup styling | 11d7f52 | ProveedoresView.tsx |
| 2 | Refactor MovimientosView (D-09/D-10) and PagosView with KpiCard | 08c613c | MovimientosView.tsx, PagosView.tsx |

## What Was Built

### Task 1: ProveedoresView

**KPI row** — Replaced Grid/Card/CardContent with 3 KpiCard components in CSS grid:
- Total Proveedores: color='blue'
- Deuda Total: color='red', value formatted with es-CO locale
- Total Pagado: color='green', value formatted with es-CO locale

**Supplier cards** — CSS grid `repeat(3, 1fr)` on md, `repeat(2, 1fr)` on sm, `1fr` on xs. Each card:
- Border `1px solid #E2E8F0`, borderRadius `12px`, padding `20px`
- Header: supplier name (fontSize 15, fontWeight 700) + Rating stars right-aligned
- Contact info: contacto, telefono, email stacked in single Typography with lineHeight 1.6
- Financials grid: Deuda (`#DC2626`) and Pagado (`#16A34A`) in 2-column CSS grid
- Registrar Pago button: `#7C3AED` background (mockup primary purple), rounded corners

**Removed imports:** Grid, Card, CardContent (fully replaced by KpiCard + Box-based layout)

### Task 2: MovimientosView + PagosView

**MovimientosView**:
- Action buttons: Entrada `#16A34A` / Salida `#F59E0B` with borderRadius `8px`
- Table card: `borderRadius: '12px', border: '1px solid #E2E8F0', overflow: 'hidden'`
- Header cells: `fontSize: 11, fontWeight: 600, textTransform: 'uppercase', letterSpacing: 0.5, color: '#64748B', background: '#F8FAFC'`
- Type chips: Box inline element — Entrada (`#DCFCE7` bg / `#16A34A` text) and Salida (`#FEF3C7` bg / `#F59E0B` text) with Icon arrows
- Entrada dialog: subtitle text added, retains supplier + precio unitario + estadoPago fields (D-09)
- Salida dialog: WorkOrder dropdown fetches `/mes/work-orders`, selecting a WO auto-fills reference `OT-{id}`, user can still type manually (D-10)

**PagosView**:
- KPI row: 3 KpiCard components (Deuda Total red, Pagado Este Mes green, Proximo Vencimiento blue)
- Table card: same styling as MovimientosView (`borderRadius: '12px'`, uppercase headers)
- Method chips: MUI Chip with `sx={{ padding: '3px 10px', borderRadius: '12px', fontSize: 11, fontWeight: 500, border: '1px solid #E2E8F0', background: '#F8FAFC' }}`

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None. All 3 views fetch real data from existing API endpoints. WorkOrder data may return empty array if no work orders exist — UI shows "Sin orden de trabajo" option which is intentional.

## Threat Flags

None. Pure display-only refactoring — no new data paths, endpoints, or auth changes introduced.

## Self-Check: PASSED

Files modified:
- ventago-app/src/views/materia-prima/ProveedoresView.tsx — FOUND
- ventago-app/src/views/materia-prima/MovimientosView.tsx — FOUND
- ventago-app/src/views/materia-prima/PagosView.tsx — FOUND

Commits verified:
- 11d7f52 — feat(15-07): refactor ProveedoresView with KpiCard and mockup supplier cards
- 08c613c — feat(15-07): refactor MovimientosView and PagosView with mockup styling

ESLint: All 3 files pass with 0 errors.

Acceptance criteria verified:
- ProveedoresView imports KpiCard and uses 3 KpiCard instances — PASS
- ProveedoresView has gridTemplateColumns for responsive supplier cards — PASS
- ProveedoresView has #DC2626 (debt) and #16A34A (paid) value colors — PASS
- ProveedoresView has #7C3AED for Registrar Pago button — PASS
- MovimientosView has #16A34A (Entrada) and #F59E0B (Salida) — PASS
- MovimientosView has workOrders state and /mes/work-orders fetch (D-10) — PASS
- MovimientosView has 'Orden de Trabajo' label in Salida dialog — PASS
- MovimientosView has textTransform: 'uppercase' for table headers — PASS
- PagosView imports KpiCard and uses 3 KpiCard instances — PASS
- PagosView has borderRadius: '12px' for table card — PASS
