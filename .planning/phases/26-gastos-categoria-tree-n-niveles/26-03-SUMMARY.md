---
phase: 26-gastos-categoria-tree-n-niveles
plan: "03"
subsystem: ventago-app
tags: [nextjs, react-arborist, tree-ui, expense-categories, korean-ime, drag-drop, soft-delete, swr]
dependency_graph:
  requires: [ExpenseCategoryController 8 endpoints (Wave 2), expense_categories table (Wave 1)]
  provides: [CategoriasGastosTreeView, CategoryNode, CreateNodeDialog, MoveNodeDialog, DeleteNodeDialog, useExpenseCategoryTree, buildTree utils, /configuracion/categorias-gastos page, sidebar nav entry]
  affects: [ventago-app/src/navigation/vertical/index.ts, ventago-app/public/locales/]
tech_stack:
  added: [react-arborist@^3.5.0]
  patterns: [react-arborist custom NodeRenderer, SWR 5-min dedup, next/dynamic SSR-off code splitting, MUI Dialog with policy radio, Korean IME isComposing guard]
key_files:
  created:
    - ventago-app/src/hooks/api/useExpenseCategoryTree.ts
    - ventago-app/src/views/configuracion/categorias-gastos/utils/buildTree.ts
    - ventago-app/src/views/configuracion/categorias-gastos/components/CategoryNode.tsx
    - ventago-app/src/views/configuracion/categorias-gastos/components/CreateNodeDialog.tsx
    - ventago-app/src/views/configuracion/categorias-gastos/components/MoveNodeDialog.tsx
    - ventago-app/src/views/configuracion/categorias-gastos/components/DeleteNodeDialog.tsx
    - ventago-app/src/views/configuracion/categorias-gastos/CategoriasGastosTreeView.tsx
    - ventago-app/src/pages/configuracion/categorias-gastos/index.tsx
  modified:
    - ventago-app/src/navigation/vertical/index.ts
    - ventago-app/public/locales/es.json
    - ventago-app/public/locales/ko.json
    - ventago-app/public/locales/en.json
    - ventago-app/package.json
decisions:
  - "apiConnector is a default export — named import { apiConnector } fails TS. Fixed all imports to default import pattern."
  - "ACL system grants manage:all to all authenticated users — Page.acl = {action:'read', subject:'configuracion'} matches existing configuracion pages (ventas/productos). Vendedor exclusion is structural (no admin app in their user.structure), not CASL subject-based."
  - "Sidebar nav injected as hardcoded entry in both superadmin block and admin append block — navigation is DB-driven but admin always gets hardcoded extras like nav_generate_token."
  - "react-arborist searchMatch signature is (node, term) => boolean where node has a .data property — multiKeywordPathMatch signature adapted accordingly."
  - "Task 5 is checkpoint:human-verify — execution paused awaiting manual UI verification."
metrics:
  duration: ~9min (tasks 1-4)
  completed_date: "2026-04-28"
  tasks_completed: 4
  tasks_total: 5
  files_created: 8
  files_modified: 5
---

# Phase 26 Plan 03: Admin Tree Management UI Summary

**One-liner:** react-arborist tree at /configuracion/categorias-gastos — SWR hook, buildTree util, CategoryNode with Korean IME guard, Create/Move/Delete dialogs with 3-policy delete and archived toggle — Next.js build passes.

---

## Tasks Completed

| Task | Name | Commit (ventago-app) | Files |
|------|------|---------------------|-------|
| 26-03-01 | react-arborist install + SWR hook + buildTree | 2526ff8 | package.json, useExpenseCategoryTree.ts, buildTree.ts |
| 26-03-02 | CategoryNode (Korean IME guard) | 4117e70 | CategoryNode.tsx |
| 26-03-03 | Create/Move/Delete dialogs | b747bd4 | CreateNodeDialog.tsx, MoveNodeDialog.tsx, DeleteNodeDialog.tsx |
| 26-03-04 | Main tree view + page + sidebar + i18n | dee79ba | CategoriasGastosTreeView.tsx, index.tsx, navigation/index.ts, locales |

Outer repo bumps: 19c1e4b, 727cfd3, 0fa0011, 4ab4069

---

## Pending

| Task | Name | Status |
|------|------|--------|
| 26-03-05 | Manual UI verification | checkpoint:human-verify — awaiting approval |

---

## Architecture Highlights

### react-arborist v3.5.0
- `<Tree<TreeNode> data={treeData} ...>` with custom `CategoryNode` renderer
- `disableDrop({ parentNode, dragNodes })` — returns `true` if `dragNodes[0].parent.id !== parentNode.id` (same-parent-only D&D per CONTEXT D1.2)
- `searchTerm` + `searchMatch={multiKeywordPathMatch}` — AND-tokenized path search
- `onMove` → PUT /:id/sort per dragged id
- `onRename` → PUT /:id with {name}

### Korean IME Safety
Applied in 3 locations:
- `CategoryNode.tsx` RenameInput: `onKeyDown` with `e.nativeEvent.isComposing || e.keyCode === 229`
- `CreateNodeDialog.tsx` name TextField: same guard
- `CategoriasGastosTreeView.tsx` search TextField: same guard

### buildTree Utils
- `buildTreeFromFlat(flat)` — O(N) Map-based conversion, recursive sort
- `multiKeywordPathMatch(node, term)` — splits on whitespace, every token must match haystack (`path + name`)
- `getValidMoveTargets(flat, movingNodeId)` — excludes self, descendants (cycle prevention), archived nodes, targets that would push subtree depth > 5

### SWR Hook
```typescript
useExpenseCategoryTree(showArchived = false)
// dedupingInterval: 5 * 60 * 1000 (CLAUDE.md 5-min dedup)
// fetcher: apiConnector.get(url) (default export)
```

### Delete Dialog — 3 Policies
- **promote**: children promoted to current parent (backend handles)
- **move**: children moved to user-selected target (getValidMoveTargets filters candidates)
- **cascade**: entire subtree archived
- Shows in-use count from GET /:id/in-use before confirmation

### Sidebar Navigation
- Superadmin hardcoded block: `nav_expense_categories` → `/configuracion/categorias-gastos`
- Regular admin append: same entry added after `nav_generate_token`
- i18n keys added: `nav_expense_categories` in es/ko/en locale files

### Page Code Splitting
```typescript
// next/dynamic with ssr:false — react-arborist is browser-only
const CategoriasGastosTreeView = dynamic(
  () => import(...).then((m) => m.CategoriasGastosTreeView),
  { ssr: false },
)
```
Route `/configuracion/categorias-gastos` = 400B (correctly tiny — component deferred).

---

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] apiConnector named import TypeScript error**
- **Found during:** Task 26-03-04 (tsc --noEmit check)
- **Issue:** All files used `import { apiConnector } from 'src/services/api.service'` but `apiConnector` is a default export, not named. TypeScript error TS2614 on 5 files.
- **Fix:** Changed all 5 imports to default import: `import apiConnector from 'src/services/api.service'`
- **Files modified:** useExpenseCategoryTree.ts, CategoriasGastosTreeView.tsx, CreateNodeDialog.tsx, MoveNodeDialog.tsx, DeleteNodeDialog.tsx
- **Commit:** dee79ba

---

## Known Stubs

None. All components are fully wired to live API endpoints. The `apiConnector.get('/expense-categories/tree')` fetches real data. All mutation endpoints (POST, PUT, DELETE, restore) are wired.

---

## Threat Flags

None beyond the plan's threat model. T-26-12 through T-26-15 addressed:
- T-26-12 (vendedor access): Page.acl + structural exclusion (vendedor has no 'admin' app in user.structure)
- T-26-13 (D&D cross-parent bypass): `disableDrop` UI guard + backend cycle/depth guards remain
- T-26-14 (archived info disclosure): Mostrar archivados toggle is admin-only UI; backend filters status=1 by default
- T-26-15 (large tree DoS): react-arborist virtualization handles this

---

## Wave 4 Reuse Guide

The following utilities are ready for Wave 4 (Gasto form selector):
- `buildTreeFromFlat` — reusable for rendering any flat expense_categories response as a tree
- `multiKeywordPathMatch` — reusable as react-arborist searchMatch or for autocomplete filtering
- `getValidMoveTargets` — reusable for depth validation in any category picker
- `ExpenseCategoryDto` type from `useExpenseCategoryTree.ts` — canonical shape

Wave 4 will need:
- A `CategoryTreeSelector` component (inline dropdown, not full-page tree)
- MRU localStorage logic (`expense_category_mru_user_${userId}_store_${storeId}`)
- Inline create flow (D4.3)

---

## Build Verification

- `npx tsc --noEmit`: PASSED — 0 TypeScript errors
- `npm run build` (Next.js): PASSED — `/configuracion/categorias-gastos` = 400B (SSR off)
- `npm run lint` (eslint --fix): PASSED — no errors in new files (pre-existing exhaustive-deps warning in navigation/index.ts is not an error per .eslintrc.json)

---

## Self-Check

### Files Verified

- `ventago-app/src/hooks/api/useExpenseCategoryTree.ts` — FOUND
- `ventago-app/src/views/configuracion/categorias-gastos/utils/buildTree.ts` — FOUND
- `ventago-app/src/views/configuracion/categorias-gastos/components/CategoryNode.tsx` — FOUND
- `ventago-app/src/views/configuracion/categorias-gastos/components/CreateNodeDialog.tsx` — FOUND
- `ventago-app/src/views/configuracion/categorias-gastos/components/MoveNodeDialog.tsx` — FOUND
- `ventago-app/src/views/configuracion/categorias-gastos/components/DeleteNodeDialog.tsx` — FOUND
- `ventago-app/src/views/configuracion/categorias-gastos/CategoriasGastosTreeView.tsx` — FOUND
- `ventago-app/src/pages/configuracion/categorias-gastos/index.tsx` — FOUND

### Commits Verified (ventago-app)

- `2526ff8` feat(phase-26-03): install react-arborist + SWR hook + buildTree util
- `4117e70` feat(phase-26-03): add CategoryNode renderer with Korean IME guard
- `b747bd4` feat(phase-26-03): add Create/Move/Delete category dialogs
- `dee79ba` feat(phase-26-03): main tree view + page + sidebar + i18n + fix default imports

### Outer Repo Bumps

- `19c1e4b` chore: bump ventago-app for phase 26 wave 3 task 1
- `727cfd3` chore: bump ventago-app for phase 26 wave 3 task 2
- `0fa0011` chore: bump ventago-app for phase 26 wave 3 task 3
- `4ab4069` chore: bump ventago-app for phase 26 wave 3 task 4

## Self-Check: PASSED
