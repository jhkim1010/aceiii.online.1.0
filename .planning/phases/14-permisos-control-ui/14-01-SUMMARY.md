---
phase: 14-permisos-control-ui
plan: 01
subsystem: api-ventago
tags: [db-schema, sequelize, permissions, crud-actions]
dependency_graph:
  requires: []
  provides: [RoleFunctionAction model, UserFunctionAction model, role_function_actions table, user_function_actions table]
  affects: [role-function.service.ts, role-function.model.ts, user-function.model.ts]
tech_stack:
  added: []
  patterns: [Sequelize HasMany association, composite UNIQUE index via @Table indexes, findOrCreate for idempotent action creation]
key_files:
  created:
    - api-ventago/src/app/role/role-function/role-function-action.model.ts
    - api-ventago/src/app/users/user-function/user-function-action.model.ts
  modified:
    - api-ventago/src/app/role/role-function/role-function.model.ts
    - api-ventago/src/app/users/user-function/user-function.model.ts
    - api-ventago/src/app/role/role-function/role-function.module.ts
    - api-ventago/src/app/users/user-function/role-function.module.ts
    - api-ventago/src/app/role/role-function/role-function.service.ts
decisions:
  - UNIQUE 제약을 Docker exec SQL이 아닌 Sequelize @Table indexes로 모델에 직접 정의 — 서버 sync 시 자동 생성됨
  - UserFunctionAction에 allowed boolean 필드 추가 — 역할 권한을 사용자가 오버라이드 가능하도록
  - createWithActions에서 findOrCreate 사용 — 중복 호출에도 idempotent 보장
  - DB backfill을 로컬 psql로 직접 실행 (Docker 미사용 환경)
metrics:
  duration: 25min
  completed_date: "2026-04-09"
  tasks_completed: 2
  files_changed: 7
---

# Phase 14 Plan 01: DB Schema — RoleFunctionAction + UserFunctionAction Summary

**One-liner:** CRUD 액션 단위 권한 테이블 2개(role_function_actions, user_function_actions) 생성 + Sequelize 모델 정의 + 기존 364개 role_functions 레코드에 4개 CRUD 액션 backfill (1456행).

## What Was Built

Phase 14 전체의 DB 기반. 기존에는 role_functions 테이블이 기능 접근 허용/차단만 했으나, 이제 각 기능에 대해 create/read/update/delete 액션별 세분화된 권한 제어가 가능해짐.

### Task 1: Sequelize 모델 정의 (commit: 3ebbae2)

- `RoleFunctionAction` 모델 신규 생성: `roleFunctionId` FK + `action` (STRING 20) + composite UNIQUE index
- `UserFunctionAction` 모델 신규 생성: `userFunctionId` FK + `action` + `allowed` boolean + composite UNIQUE index
- `RoleFunction` 모델에 `@HasMany(() => RoleFunctionAction)` 관계 추가
- `UserFunction` 모델에 `@HasMany(() => UserFunctionAction)` 관계 추가
- `RoleFunctionModule`, `UserFunctionModule` forFeature 배열에 새 모델 등록

### Task 2: DB sync + backfill + Service 업데이트 (commit: 62872aa)

- Sequelize auto-sync로 `role_function_actions`, `user_function_actions` 테이블 자동 생성됨
- Composite UNIQUE 제약 `role_function_actions_rf_action_unique`, `user_function_actions_uf_action_unique` 적용
- 기존 364개 `role_functions` 레코드에 4개 CRUD 액션 backfill → 1456행 삽입 (364 × 4 = 1456, 검증 완료)
- `RoleFunctionService.createWithActions()` 메서드 추가: 새 RoleFunction 생성 시 4개 액션 자동 생성
- `updateFunctionsForRole()` 메서드가 `createWithActions()`를 호출하도록 변경

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | 3ebbae2 | feat(14-01): add RoleFunctionAction + UserFunctionAction Sequelize models |
| 2 | 62872aa | feat(14-01): add UNIQUE indexes to action models + createWithActions service method |

## Verification Results

- TypeScript 컴파일: 에러 없음 (`tsc --noEmit`)
- `role_function_actions` 행 수: 1456 (= 364 role_functions × 4)
- `user_function_actions` 행 수: 0 (정상 — 아직 사용자 개별 오버라이드 없음)
- UNIQUE 제약 `role_function_actions_rf_action_unique`: 존재 확인
- UNIQUE 제약 `user_function_actions_uf_action_unique`: 존재 확인

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical Functionality] UNIQUE 제약을 모델에 직접 정의**
- **Found during:** Task 2
- **Issue:** 플랜에서는 Docker exec SQL로 UNIQUE 제약을 별도 추가하도록 되어 있었으나, 이는 배포 환경에서만 가능하고 로컬에서는 Docker exec 사용 불가
- **Fix:** `@Table({ indexes: [{ unique: true, fields: [...], name: '...' }] })` 패턴으로 Sequelize 모델에 직접 정의 — 서버 기동 시 자동으로 인덱스 생성됨. 기존 codebase 패턴(products.model.ts 등) 동일 방식
- **Files modified:** role-function-action.model.ts, user-function-action.model.ts

**2. [Rule 3 - Blocking Issue] Docker 미사용 환경에서 psql 직접 실행**
- **Found during:** Task 2
- **Issue:** 플랜의 DB backfill이 `docker exec api_ventago node -e "..."` 기반으로 작성되어 있으나 Docker가 로컬에 없음
- **Fix:** 로컬 PostgreSQL(localhost:5432)에 직접 psql로 backfill SQL 실행. ON CONFLICT DO NOTHING 패턴 유지하여 멱등성 보장.
- **Files modified:** 코드 변경 없음 (DB 직접 조작)

## Known Stubs

없음 — 모든 필드가 실제 데이터로 채워져 있음.

## Threat Flags

없음 — 새 네트워크 엔드포인트나 외부 접근 경로 없음. DB 스키마 변경만 포함.

## Self-Check: PASSED

- [x] `api-ventago/src/app/role/role-function/role-function-action.model.ts` 존재
- [x] `api-ventago/src/app/users/user-function/user-function-action.model.ts` 존재
- [x] commit 3ebbae2 존재
- [x] commit 62872aa 존재
- [x] role_function_actions 1456행 (364 × 4)
- [x] UNIQUE 제약 양쪽 테이블 모두 적용
