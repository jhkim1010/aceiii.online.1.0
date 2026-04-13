---
phase: 18
plan: "01"
subsystem: frontend/table
tags: [ag-grid, mui, migration, types, dependencies]
dependency_graph:
  requires: []
  provides: [grid-types-ag-native, no-mui-datagrid-dep]
  affects: [ventago-app/src/components/table, 58-dataconfig-files]
tech_stack:
  added: []
  patterns: [ColDef-extension, MUI-compat-shim, adaptColumns-adapter]
key_files:
  created: []
  modified:
    - ventago-app/src/components/table/grid-types.ts
    - ventago-app/package.json
    - ventago-app/src/views/talleres/tabs/EtapasTab.tsx
    - ventago-app/src/views/talleres/tabs/LiquidacionesTab.tsx
decisions:
  - "Omit<ColDef, 'valueGetter'> + custom valueGetter: (params: any) => any — MUI params.row 패턴 허용"
  - "apiConnector.get<any> 타입 지정 — talleres 탭 pre-existing TS 에러 해결"
metrics:
  duration: "~30min"
  completed: "2026-04-13"
  tasks_completed: 2
  files_changed: 4
requirements: [GRID-01]
---

# Phase 18 Plan 01: AG Grid Migration Complete Summary

**One-liner:** AG Grid 네이티브 타입 shim으로 @mui/x-data-grid 완전 제거 — ColDef 확장 타입 + adaptColumns 어댑터로 58개 소비 파일 무변경 호환 유지.

## What Was Built

### Task 1: grid-types.ts AG Grid 네이티브 타입으로 교체 (commit: 811a23d)

`@mui/x-data-grid`에서 re-export하던 `GridColDef`, `GridRenderCellParams`를 AG Grid 네이티브 타입 기반으로 교체.

- `GridColDef = Omit<ColDef, 'valueGetter'> & { renderCell, renderHeader, align, headerAlign, valueGetter }`
- `GridRenderCellParams` 인터페이스: `row`, `value`, `data`, `field` 속성
- 58개 DataConfig/View 파일의 import 경로 (`src/components/table/grid-types`) 변경 없음

### Task 2: @mui/x-data-grid 제거 + 빌드 검증 (commit: 2ce16ca)

- `package.json` dependencies에서 `@mui/x-data-grid: ^6.0.3` 제거
- `package.json` resolutions에서 `@mui/x-data-grid/@mui/system: 5.12.1` 제거
- `npm install` 실행하여 lockfile 갱신
- `npx next build` 성공 확인

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] GridColDef valueGetter 타입 충돌**
- **Found during:** Task 2 (build)
- **Issue:** `ColDef.valueGetter`가 `ValueGetterParams`를 요구하는데 DataConfig 파일들은 MUI 패턴 `params.row`를 사용 → TypeScript error
- **Fix:** `Omit<ColDef, 'valueGetter'>` + `valueGetter?: (params: any) => any` 오버라이드
- **Files modified:** `ventago-app/src/components/table/grid-types.ts`
- **Commit:** 2ce16ca

**2. [Rule 3 - Blocking] EtapasTab.tsx pre-existing TypeScript error**
- **Found during:** Task 2 (build — cascading after cash-control error fixed)
- **Issue:** `apiConnector.get()` 반환 타입이 `{}` 로 추론되어 `.data` 접근 불가
- **Fix:** `apiConnector.get<any>()` 타입 파라미터 지정
- **Files modified:** `ventago-app/src/views/talleres/tabs/EtapasTab.tsx`
- **Commit:** 2ce16ca

**3. [Rule 3 - Blocking] LiquidacionesTab.tsx same pre-existing TypeScript error**
- **Found during:** Task 2 (build — after EtapasTab fix)
- **Issue:** Same pattern — `apiConnector.get()` untyped, `.data` access fails
- **Fix:** `apiConnector.get<any>()` 타입 파라미터 지정
- **Files modified:** `ventago-app/src/views/talleres/tabs/LiquidacionesTab.tsx`
- **Commit:** 2ce16ca

## Commits

| Commit | Repo | Description |
|--------|------|-------------|
| 811a23d | ventago-app | feat(18-01): replace grid-types.ts with AG Grid native types |
| 2ce16ca | ventago-app | feat(18-01): remove @mui/x-data-grid + fix TS type errors + build verified |
| 5361706 | parent | feat(18-01): bump ventago-app — AG Grid migration complete |

## Verification Results

- `npm ls @mui/x-data-grid` — not in ventago-app/package.json (root node_modules has extraneous copy unrelated to ventago-app)
- `npm run lint` — 0 errors (32 pre-existing react-hooks/exhaustive-deps warnings only)
- `npx next build` — SUCCESS

## Known Stubs

None — all changes are functional type definitions.

## Self-Check: PASSED

- grid-types.ts: imports from `ag-grid-community`, no `@mui/x-data-grid` reference
- package.json: no `@mui/x-data-grid` in dependencies or resolutions
- Build: succeeded with no errors
- Commits 811a23d, 2ce16ca exist in ventago-app; 5361706 in parent worktree branch
