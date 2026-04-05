---
phase: 01-ui-ux
plan: 02
subsystem: ui
tags: [react, context, mui, sidebar, toggle, uimode]

# Dependency graph
requires:
  - phase: 01-ui-ux-01
    provides: PUT /users/ui-mode endpoint and uiMode field in /auth/me response

provides:
  - UiModeContext with UiModeProvider and useUiMode hook (app-wide)
  - UI/UX nuevo checkbox in SidebarFooter (admin/superadmin only)
  - uiMode field added to UserDataType

affects:
  - Any page that implements new UI (uses useUiMode to conditionally render)
  - SidebarFooter rendering

# Tech tracking
tech-stack:
  added: []
  patterns:
    - React Context for UI mode state (wraps AuthProvider, uses useAuth internally)
    - useMemo on context value to prevent unnecessary re-renders
    - canToggle pattern for role-based feature access

key-files:
  created:
    - ventago-app/src/context/UiModeContext.tsx
  modified:
    - ventago-app/src/context/types.ts
    - ventago-app/src/pages/_app.tsx
    - ventago-app/src/layouts/components/vertical/SidebarFooter.tsx

key-decisions:
  - "UiModeProvider placed inside AuthProvider (not outside) because it uses useAuth() hook"
  - "useMemo on context value prevents Navigation component re-renders on unrelated state changes"
  - "Checkbox hidden in collapsed sidebar state to avoid space constraints"

patterns-established:
  - "Pattern 1: useUiMode() hook is the standard way for any component to check current UI mode"
  - "Pattern 2: canToggle computed from roles array — admin OR superadmin get toggle access"

requirements-completed: [TOGGLE-01]

# Metrics
duration: 8min
completed: 2026-04-05
---

# Phase 01 Plan 02: UI Mode Toggle Infrastructure Summary

**UiModeContext with admin/superadmin checkbox toggle in sidebar, wired to PUT /users/ui-mode API with immediate local state update**

## Performance

- **Duration:** 8 min
- **Started:** 2026-04-05T23:07:32Z
- **Completed:** 2026-04-05T23:15:00Z
- **Tasks:** 2 of 3 (Task 3 is human-verify checkpoint — awaiting user verification)
- **Files modified:** 4

## Accomplishments

- Created UiModeContext.tsx with UiModeProvider and useUiMode hook, memoized for performance
- Added uiMode field to UserDataType enabling type-safe access throughout the frontend
- SidebarFooter shows "UI/UX nuevo" checkbox exclusively for admin/superadmin roles
- Toggle immediately updates local state via setUser without page refresh, and persists via /me on reload

## Task Commits

Each task was committed atomically:

1. **Task 1: UserDataType에 uiMode 추가 + UiModeContext 생성** - `b7b43b2` (feat)
2. **Task 2: SidebarFooter에 UI/UX nuevo 체크박스 추가** - `39cadcd` (feat)
3. **Task 3: UI 토글 기능 검증** - CHECKPOINT (awaiting human verify)

## Files Created/Modified

- `ventago-app/src/context/UiModeContext.tsx` - UiModeProvider + useUiMode hook, toggles PUT /users/ui-mode
- `ventago-app/src/context/types.ts` - Added uiMode?: 'classic' | 'new' to UserDataType
- `ventago-app/src/pages/_app.tsx` - Wrapped app with UiModeProvider inside AuthProvider
- `ventago-app/src/layouts/components/vertical/SidebarFooter.tsx` - Added UI/UX nuevo checkbox with canToggle guard

## Decisions Made

- UiModeProvider placed inside AuthProvider because it calls useAuth() — must be a child of AuthProvider
- useMemo applied to context value object to prevent unnecessary re-renders in React.memo-wrapped Navigation
- Checkbox only shown in expanded sidebar state (not collapsed) due to space constraints

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None - files committed in ventago-app submodule (not root repo) as expected for monorepo structure.

## Known Stubs

None - UiModeContext reads uiMode from user object (populated by /auth/me), no stubs in data flow.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- useUiMode() hook is available app-wide for any page that wants to conditionally render new UI
- Pattern: `const { isNewUi } = useUiMode()` in any component
- Task 3 (human-verify checkpoint) must be approved before plan is considered complete

---
*Phase: 01-ui-ux*
*Completed: 2026-04-05*
