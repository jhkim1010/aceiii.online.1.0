---
phase: 14-permisos-control-ui
plan: 03
subsystem: frontend-acl
tags: [casl, permissions, crud-ui, role-management]
dependency_graph:
  requires: [14-02]
  provides: [granular-casl-ability, crud-action-row, role-permissions-drawer-crud]
  affects: [ventago-app/src/configs/acl.ts, ventago-app/src/@core/components/auth/AclGuard.tsx, ventago-app/src/context/types.ts, ventago-app/src/views/users/roles]
tech_stack:
  added: []
  patterns: [CASL granular rules, Map<number, Set<string>> state, functional chips UI]
key_files:
  created:
    - ventago-app/src/views/users/roles/components/CrudActionRow.tsx
  modified:
    - ventago-app/src/configs/acl.ts
    - ventago-app/src/@core/components/auth/AclGuard.tsx
    - ventago-app/src/context/types.ts
    - ventago-app/src/views/users/roles/RolePermissionsDrawer.tsx
    - ventago-app/src/views/users/roles/hooks/useRoleFunctions.ts
decisions:
  - "buildAbilityFor 3번째 인자로 PermissionsMap 추가 — AclGuard에서 auth.user.permissions 전달"
  - "superadmin 체크를 permissions 맵 체크보다 먼저 수행 (T-14-07 Elevation of Privilege 대응)"
  - "useRoleFunctions 반환값을 number[] → RoleFunctionData[] 로 변경하여 CRUD actions 포함"
  - "RolePermissionsDrawer state를 Set<number> → Map<number, Set<string>>으로 교체"
  - "Module/App 체크박스 일괄 토글 시 4 action 전부 추가/제거"
metrics:
  duration: ~25min
  completed: "2026-04-09T23:50:55Z"
  tasks_completed: 3
  files_changed: 6
---

# Phase 14 Plan 03: Frontend CASL Refactor + CrudActionRow + RolePermissionsDrawer CRUD Summary

**One-liner:** Refactored CASL `buildAbilityFor` from `manage:all` to permission-map-driven granular rules, added `CrudActionRow` 4-chip component, and extended `RolePermissionsDrawer` to display and save CRUD actions per function via `PUT /role-functions/bulk-actions/:roleId`.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | CASL buildAbilityFor refactor + AclGuard + AuthContext | 60f02f0 | acl.ts, AclGuard.tsx, types.ts |
| 2 | CrudActionRow component | c646e26 | CrudActionRow.tsx (new) |
| 3 | RolePermissionsDrawer CRUD + useRoleFunctions | e9597ad | RolePermissionsDrawer.tsx, useRoleFunctions.ts |

## What Was Built

### Task 1 — CASL buildAbilityFor Refactoring

- `acl.ts`: Replaced `manage:all` for all logged-in users with `permissions`-map-based `can(action, fnSlug)` rules
- Added `PermissionsMap` type export matching `/me` response shape
- `buildAbilityFor` now accepts 3rd parameter `permissions?: PermissionsMap | null`
- superadmin still gets `manage:all` (checked first — T-14-07 Elevation of Privilege guard)
- fallback: if no `permissions` map, grants `read` on `subject` (backward compat)
- `AclGuard.tsx`: passes `auth.user.permissions` as 3rd arg to `buildAbilityFor`
- `types.ts`: added `permissions?` field to `UserDataType`

### Task 2 — CrudActionRow Component

New file: `src/views/users/roles/components/CrudActionRow.tsx`

- 4 chips: C (success/green), R (primary/blue), U (warning/orange), D (error/red)
- `filled` variant when action enabled, `outlined` when disabled
- `user-override` mode: shows `warning.main` border when value differs from `roleActions`
- `aria-label` with "habilitado"/"deshabilitado" state
- gap: 2 (8px) per UI-SPEC

### Task 3 — RolePermissionsDrawer + useRoleFunctions

- `useRoleFunctions`: returns `RoleFunctionData[]` (includes `actions: string[]` from `roleFunctionActions`)
- `RolePermissionsDrawer`: replaced `checked: string[]` with `functionActions: Map<number, Set<string>>`
- Each function row now shows `CrudActionRow` instead of single Checkbox
- Module-level Checkbox: toggles all 4 actions on/off for all module functions
- App-level Checkbox: toggles all 4 actions on/off for all app functions
- Indeterminate: true when some functions have partial or mixed actions
- `Guardar`: calls `PUT /role-functions/bulk-actions/:roleId` with `{ data: [{ functionId, actions }] }`
- Summary strip at bottom: `{N} funciones — {X} completos / {Y} parciales`

## Deviations from Plan

### Auto-fixed Issues

None — plan executed as written.

## Threat Flags

None — no new network endpoints, auth paths, or schema changes introduced. Frontend CASL is UI-only per T-14-08 acceptance (real enforcement is backend FunctionPermissionGuard).

## Self-Check: PASSED

- ventago-app/src/configs/acl.ts — modified (commit 60f02f0)
- ventago-app/src/@core/components/auth/AclGuard.tsx — modified (commit 60f02f0)
- ventago-app/src/context/types.ts — modified (commit 60f02f0)
- ventago-app/src/views/users/roles/components/CrudActionRow.tsx — created (commit c646e26)
- ventago-app/src/views/users/roles/RolePermissionsDrawer.tsx — modified (commit e9597ad)
- ventago-app/src/views/users/roles/hooks/useRoleFunctions.ts — modified (commit e9597ad)
- ESLint: no errors on all task files
