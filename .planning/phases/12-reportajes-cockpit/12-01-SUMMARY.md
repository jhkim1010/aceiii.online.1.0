---
phase: 12-reportajes-cockpit
plan: "01"
subsystem: frontend/reports-v2
tags: [layout, cockpit, redux, registry, filter-schema]
dependency_graph:
  requires: ["08-04"]
  provides: [CockpitLayout, ReportsFilterFields, filterSchema, currentParams]
  affects: [ReportsShell, ReportsTopbar, reports-v2 Redux slice]
tech_stack:
  added: []
  patterns: [schema-driven rendering, localStorage resize persistence, MUI Drawer]
key_files:
  created:
    - ventago-app/src/views/reports-v2/CockpitLayout.tsx
    - ventago-app/src/views/reports-v2/ReportsFilterFields.tsx
  modified:
    - ventago-app/src/store/apps/reports-v2/index.ts
    - ventago-app/src/views/reports-v2/registry.ts
    - ventago-app/src/views/reports-v2/ReportsTopbar.tsx
    - ventago-app/src/views/reports-v2/ReportsShell.tsx
decisions:
  - "CockpitLayout used at shell level (wraps ReportsPreviewPanel as primary slot) so individual Body components can optionally use it for nested KPI+detail layouts in Wave 2+"
  - "filterSchema falls back to paramsSchema in ReportsFilterFields for full Phase 8 backward compat"
  - "setCurrentParams action syncs both paramsBySlug[slug] and currentParams simultaneously to avoid dual state"
metrics:
  duration: "~20 min"
  completed: "2026-04-13T17:57:22Z"
  tasks_completed: 4
  files_changed: 6
---

# Phase 12 Plan 01: Cockpit Infrastructure — Layout + Filter Schema Summary

**One-liner:** CockpitLayout with resizable KPI/Primary/Detail/Drawer slots + filterSchema registry field + schema-driven ReportsFilterFields replacing inline Topbar fields.

## What Was Built

### Task 1 — Redux slice + registry type extensions (ea96276)
- Added `currentParams: Record<string, any>` field to `ReportsV2State`
- Added `setCurrentParams` action: updates both `paramsBySlug[slug]` and `currentParams` atomically
- Added `FilterFieldType` union type: `'sucursal' | 'search' | 'rangeDate' | 'category' | 'paymentMethod'`
- Added `CockpitLayoutConfig` interface with `hasKpiStrip`, `hasDetail`, `hasDrawer`, `primaryHeightPct`
- Added `filterSchema?: FilterFieldType[]` and `cockpitLayout?: CockpitLayoutConfig` to `ReportEntry`

### Task 2+3+4 — New components + Topbar wiring (1ed972e)

**CockpitLayout.tsx:**
- Props: `slug`, `kpis?`, `primary`, `detail?`, `drawer?`, `drawerOpen?`, `onDrawerClose?`, `primaryHeight?`
- KPI Strip: `flex: 0 0 80px`, grid auto-columns, divider gap
- Primary Area: percentage-based height (default 50% when detail present, 100% without)
- Resize handle: `6px` drag handle between Primary and Detail, `row-resize` cursor
- localStorage persistence: `cockpit-primary-pct-{slug}` key, restored on slug change
- Detail Area: `flex: 1` below resize handle
- Drawer: MUI `Drawer` variant=temporary, anchor=right, 380px width, slide animation

**ReportsFilterFields.tsx:**
- Reads `entry.filterSchema` from registry
- Falls back to `paramsSchema` (hasFilter / hasDateRange) for Phase 8 backward compat
- Dispatches `setCurrentParams` on every field change (single Redux source)
- Renders: SucursalField | SearchField | DateRangeField in schema order
- `category` / `paymentMethod` fields return null (Wave 2 placeholder)

**ReportsTopbar.tsx:**
- Replaced inline SucursalField + SearchField + DateRangeField with `<ReportsFilterFields slug={slug} />`
- Removed now-unused imports: useDispatch, useSelector, SucursalField, SearchField, DateRangeField, setParamsForSlug, RootState

### Task 5 — ReportsShell integration (7fcf113)
- Removed `ReportsParamsPanel` (was rendering null — dead stub)
- Added `CockpitLayout` with `primary={<ReportsPreviewPanel slug={slug} />}`
- Shell flex column: `ReportsTopbar (56px)` → `CockpitLayout (flex:1)`
- No kpis/detail/drawer passed at shell level — individual Body components supply those in Wave 2+

## Deviations from Plan

### Auto-fixed Issues

None — plan executed exactly as written.

### Notes
- `ReportsParamsPanel` import removed from shell (was a null-rendering stub from Phase 8 Wave 3; its import was dead weight)
- CockpitLayout is wired at shell level for Wave 1 infrastructure; individual cockpit bodies (VendedorCockpitBody etc.) will use their own internal CockpitLayout instances in Wave 2+ with KPI/detail slots populated

## Known Stubs

| File | Description |
|------|-------------|
| `ReportsFilterFields.tsx` lines 85-86 | `category` and `paymentMethod` FilterFieldType values return null — Wave 2 implementation |
| `CockpitLayout.tsx` — kpis/detail/drawer | Shell passes no kpis/detail/drawer slots at this stage — populated by Wave 2 Body components |

## Threat Flags

None — Wave 1 is pure frontend layout infrastructure, no new network endpoints or auth paths.

## Self-Check

### Files exist
- `ventago-app/src/views/reports-v2/CockpitLayout.tsx` — FOUND
- `ventago-app/src/views/reports-v2/ReportsFilterFields.tsx` — FOUND

### Commits exist
- ea96276 — feat(12-01): extend Redux slice + registry with filterSchema/cockpitLayout types
- 1ed972e — feat(12-01): add CockpitLayout + ReportsFilterFields + wire Topbar
- 7fcf113 — feat(12-01): wire CockpitLayout into ReportsShell

### ESLint
- `npx next lint --dir src/views/reports-v2 --dir src/store/apps/reports-v2` → No ESLint warnings or errors

## Self-Check: PASSED
