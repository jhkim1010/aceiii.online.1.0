---
phase: 16-control-de-talleres
plan: "02"
subsystem: frontend
tags: [pipeline, kanban, etapa-flow, talleres, ui]
dependency_graph:
  requires:
    - ventago-app/src/views/talleres/components/constants.ts
    - api-ventago/src/app/subcon/etapas/etapa.controller.ts (GET /talleres/etapas/all)
    - api-ventago/src/app/subcon/envios/envio.controller.ts (GET /talleres/envios/all)
    - api-ventago/src/app/subcon/lotes/lote.controller.ts (GET /talleres/lotes/all)
  provides:
    - ventago-app/src/views/talleres/components/EtapaFlowVisual.tsx
    - ventago-app/src/views/talleres/components/PipelineKanban.tsx
    - ventago-app/src/views/talleres/tabs/PipelineTab.tsx
    - ventago-app/src/views/talleres/TalleresMainView.tsx (shell)
    - ventago-app/src/pages/talleres/index.tsx
  affects:
    - ventago-app/src/views/talleres/TalleresMainView.tsx (pipeline tab wired)
tech_stack:
  added: []
  patterns:
    - CSS flexbox Kanban (read-only, no drag&drop)
    - Circular node flow visualization (MUI Box)
    - Promise.all parallel API fetching
    - URL shallow routing for tab state
key_files:
  created:
    - ventago-app/src/views/talleres/components/EtapaFlowVisual.tsx
    - ventago-app/src/views/talleres/components/PipelineKanban.tsx
    - ventago-app/src/views/talleres/components/constants.ts
    - ventago-app/src/views/talleres/tabs/PipelineTab.tsx
    - ventago-app/src/views/talleres/TalleresMainView.tsx
    - ventago-app/src/pages/talleres/index.tsx
  modified: []
decisions:
  - "TalleresMainView created with full shell (all 7 tabs) in this worktree to enable parallel execution — 16-01 integrated DashboardTab via parallel merge"
  - "PipelineKanban stage color derived from items state: completed=green, overdue=orange, active=purple, empty=grey"
  - "EtapaFlowVisual isDone requires all envios COMPLETED AND pendingQuantity=0"
  - "constants.ts owned by 16-02 since it was needed before 16-01 artifacts existed"
metrics:
  duration: "~25 minutes"
  completed_date: "2026-04-13"
  tasks_total: 2
  tasks_completed: 2
  files_created: 6
  files_modified: 0
---

# Phase 16 Plan 02: Pipeline Tab — Etapa Flow + Kanban Visualization Summary

**One-liner:** CSS flexbox read-only Kanban board with per-etapa columns + circular node flow visualization showing selected lot's process progress.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | EtapaFlowVisual + PipelineKanban 공유 컴포넌트 | ef3b58f | EtapaFlowVisual.tsx, PipelineKanban.tsx, constants.ts |
| 2 | PipelineTab 조립 + TalleresMainView 탭 연결 | e609817 | PipelineTab.tsx, TalleresMainView.tsx, index.tsx |

## What Was Built

### EtapaFlowVisual (`components/EtapaFlowVisual.tsx`)
- Circular node flow (48x48px, borderRadius 50%) sorted by etapa.order
- Three states: done (green #4CAF50, ✓ icon), active (purple #7C4DFF, pendingQuantity count), inactive (grey #e0e0e0)
- Arrow (→) between nodes, none after last
- Renders `selectedLoteEnvios` filtered for selected lot

### PipelineKanban (`components/PipelineKanban.tsx`)
- CSS flexbox layout, minWidth 200px per column, overflowX auto
- Stage top border color: completed=green, overdue=orange, active=purple, empty=grey
- Badge (lotes count) uses light/dark color pair matching border color
- Items show loteNumber, vendorName, quantity, dueDate with overdue alert (⚠)
- Read-only: zero drag&drop events

### PipelineTab (`tabs/PipelineTab.tsx`)
- Parallel data load: `Promise.all([etapas, envios, lotes])` from 3 existing APIs
- Auto-selects first IN_PROGRESS lot; falls back to first lot if none
- Lot selector dropdown (OPEN + IN_PROGRESS lots)
- Status Chip for selected lot (En Proceso / Abierto)
- Upper card: EtapaFlowVisual for selected lot's envios
- Lower section: PipelineKanban with all envios grouped by etapa (PENDING/PARTIAL only)

### TalleresMainView + pages/talleres/index.tsx
- 7-tab shell with URL shallow routing (`router.query.tab`)
- UI toggle: `uiMode === 'new'` → TalleresMainView, otherwise legacy ControlPanel
- Pipeline tab fully wired (not placeholder)

## Deviations from Plan

### Auto-additions

**1. [Rule 2 - Missing] constants.ts created in 16-02 instead of 16-01**
- Both plans reference constants.ts; as parallel executor, this plan created it first to unblock EtapaFlowVisual
- Content exactly matches 16-01 spec (TALLER_COLORS, TALLER_LIGHT_COLORS, STATUS_CONFIG, TALLERES_TABS, DashboardStats)

**2. [Rule 2 - Missing] TalleresMainView.tsx created with full 7-tab shell**
- Plan said "update existing TalleresMainView" but 16-01 hadn't created it yet (parallel wave)
- Created full shell matching 16-01 spec + Pipeline tab wired
- 16-01 parallel executor integrated DashboardTab import via merge

**3. [Rule 2 - Missing] pages/talleres/index.tsx created**
- Required for UI toggle to work; listed in 16-01 plan but needed here for complete integration

## Known Stubs

| File | Description |
|------|-------------|
| TalleresMainView.tsx | Tabs: talleres, lotes, envios, liquidaciones, etapas show "Próximamente" placeholder — resolved in waves 2 & 3 (plans 03, 04) |
| TalleresMainView.tsx dashboard tab | Shows "Próximamente" initially — replaced by DashboardTab by 16-01 parallel merge |

## Self-Check: PASSED

Files verified:
- `ventago-app/src/views/talleres/components/EtapaFlowVisual.tsx` — FOUND
- `ventago-app/src/views/talleres/components/PipelineKanban.tsx` — FOUND
- `ventago-app/src/views/talleres/components/constants.ts` — FOUND
- `ventago-app/src/views/talleres/tabs/PipelineTab.tsx` — FOUND
- `ventago-app/src/views/talleres/TalleresMainView.tsx` — FOUND
- `ventago-app/src/pages/talleres/index.tsx` — FOUND

Commits verified:
- ef3b58f — Task 1: EtapaFlowVisual + PipelineKanban + constants
- e609817 — Task 2: PipelineTab + TalleresMainView + index page

ESLint: PASSED (all files — no warnings or errors)
