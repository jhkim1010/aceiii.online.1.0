---
phase: 16-control-de-talleres
plan: "03"
subsystem: frontend
tags: [talleres, tabs, table, collapse, drawer, filters, mui]
dependency_graph:
  requires: [16-01, 16-02]
  provides: [TalleresTab, LotesTab, EnviosTab, VendorExpandedRow, LoteDetailDrawer]
  affects: [TalleresMainView]
tech_stack:
  added: []
  patterns: [MUI Table + Collapse expandable rows, 420px right Drawer, multi-filter table, overdue row highlighting]
key_files:
  created:
    - ventago-app/src/views/talleres/tabs/TalleresTab.tsx
    - ventago-app/src/views/talleres/drawers/VendorExpandedRow.tsx
    - ventago-app/src/views/talleres/tabs/LotesTab.tsx
    - ventago-app/src/views/talleres/drawers/LoteDetailDrawer.tsx
    - ventago-app/src/views/talleres/tabs/EnviosTab.tsx
  modified:
    - ventago-app/src/views/talleres/TalleresMainView.tsx
decisions:
  - Used MUI Table (not DataGrid) for TalleresTab to enable native Collapse support for expandable rows
  - Single expandedId (number|null) for one-at-a-time row expansion — no multi-expand
  - Promise.all() for parallel API loads in all 3 tabs
  - EtapaFlowVisual reused in LoteDetailDrawer for etapa progress visualization
metrics:
  duration: ~25min
  completed: "2026-04-13T11:49:00Z"
  tasks_completed: 2
  files_created: 5
  files_modified: 1
---

# Phase 16 Plan 03: Wave 2 Tabs Summary

**One-liner:** MUI Table+Collapse vendor tab, 420px lote detail drawer with EtapaFlowVisual + timeline, and multi-filter envios table with overdue row highlighting wired into TalleresMainView.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | TalleresTab + VendorExpandedRow | d007a8a | TalleresTab.tsx, VendorExpandedRow.tsx |
| 2 | LotesTab + LoteDetailDrawer + EnviosTab + TalleresMainView | d2d9445 | LotesTab.tsx, LoteDetailDrawer.tsx, EnviosTab.tsx, TalleresMainView.tsx |

## What Was Built

### Task 1: TalleresTab + VendorExpandedRow

**TalleresTab.tsx** — MUI Table with Collapse expandable rows (D-07, D-08):
- 3 filter controls: text search, status (active/inactive), etapa selector
- `expandedId: number | null` — only one row expanded at a time
- Avatar with 6-color rotation + 2-char initials
- `apiConnector.get('/talleres/vendors/all')` + `'/talleres/etapas/all'` via Promise.all
- Collapse with `unmountOnExit` for clean DOM

**VendorExpandedRow.tsx** — Expanded row panel:
- 4 stat cards: Pendientes (purple), Deuda (red), Cumplimiento (conditional color >=90 green / >=80 orange / else red), Rating (orange star)
- Capacity progress bar with `height: 4`, orange if >=80%, green otherwise

### Task 2: LotesTab + LoteDetailDrawer + EnviosTab + TalleresMainView

**LotesTab.tsx** — Lote table with 420px right drawer (D-10):
- Promise.all loads lotes + etapas + envios simultaneously
- `handleRowClick` sets selectedLote + opens Drawer
- Progress bar (height: 6, green) per lote based on COMPLETED envio qty
- Drawer: `anchor='right'`, `width: { xs: '100%', md: 420 }`

**LoteDetailDrawer.tsx** — 420px right panel (D-09):
- 3 quantity distribution cards: Disponible (#ede7f6/purple), En Taller (#fff3e0/orange), Completado (#e8f5e9/green)
- EtapaFlowVisual reused for etapa progress (filtered by loteId)
- Timeline: vertical 2px left line (#e8e8e8), dot colors (green=COMPLETED, purple=PENDING/PARTIAL, grey=other), movement list sorted by createdAt DESC
- Action buttons: "Nuevo Envio" (primary) + "Cerrar Lote" (outline/error) — placeholder handlers

**EnviosTab.tsx** — Envios table with 3-filter + overdue highlighting:
- Filters: statusFilter + vendorFilter + etapaFilter + searchQuery
- Overdue detection: `dueDate < now && status in [PENDING, PARTIAL]`
- Overdue row: `bgcolor: '#fbe9e7'`
- Overdue chip: "Atrasado" in red, Vencimiento cell shows `date (-Nd)`
- Acciones: "Recibir" button for active, "Recibido" text for completed

**TalleresMainView.tsx** — Updated tab wiring:
- Added imports for TalleresTab, LotesTab, EnviosTab
- Replaced "Próximamente" placeholders with actual components

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

| Stub | File | Reason |
|------|------|--------|
| "Nuevo Taller" button | TalleresTab.tsx | Placeholder — VendorFormDrawer integration is future work |
| "Nuevo Lote" button | LotesTab.tsx | Placeholder — create lote modal is future work |
| "Enviar"/"Cerrar" actions | LotesTab.tsx | Placeholder — stopPropagation only, modal integration future |
| "Nuevo Envio" button | EnviosTab.tsx | Placeholder — envio creation modal is future work |
| "Recibir" button | EnviosTab.tsx | Placeholder — recepcion modal is future work |
| "Nuevo Envio"/"Cerrar Lote" | LoteDetailDrawer.tsx | Placeholder — modal integration future |

These stubs are action buttons; data display (the plan's core goal) is fully functional.

## Threat Flags

None — frontend only, uses existing API with storeId filtering already in place.

## Self-Check: PASSED

- [x] ventago-app/src/views/talleres/tabs/TalleresTab.tsx — FOUND (commit d007a8a)
- [x] ventago-app/src/views/talleres/drawers/VendorExpandedRow.tsx — FOUND (commit d007a8a)
- [x] ventago-app/src/views/talleres/tabs/LotesTab.tsx — FOUND (commit d2d9445)
- [x] ventago-app/src/views/talleres/drawers/LoteDetailDrawer.tsx — FOUND (commit d2d9445)
- [x] ventago-app/src/views/talleres/tabs/EnviosTab.tsx — FOUND (commit d2d9445)
- [x] ventago-app/src/views/talleres/TalleresMainView.tsx — UPDATED (commit d2d9445)
- [x] ESLint: no warnings or errors on all 5 new files + TalleresMainView
