---
phase: 14-permisos-control-ui
plan: 02
subsystem: auth
tags: [nestjs, sequelize, permissions, guards, decorators, scope-enforcement]

requires:
  - phase: 14-01
    provides: [RoleFunctionAction model, UserFunctionAction model, role_function_actions table, user_function_actions table, createWithActions service method]

provides:
  - /me API가 non-superadmin에게 permissions 맵 반환 (functionSlug → {create,read,update,delete})
  - @FunctionGuard('slug', 'action') 데코레이터로 엔드포인트 보호 가능
  - FunctionPermissionGuard (superadmin bypass, role baseline + user override 체크)
  - PUT /role-functions/bulk-actions/:roleId (action 단위 역할 권한 bulk 업데이트)
  - PUT /user-functions/actions/:targetUserId (action 단위 유저 오버라이드 업데이트)
  - POST /user-functions/reset/:targetUserId (유저 override 전부 삭제 → role 기본값 복원)
  - gerente branch scope / admin store scope enforcement

affects: [14-03, 14-04, ventago-app CASL permissions context]

tech-stack:
  added: []
  patterns:
    - FunctionGuard = applyDecorators(RequireFunction, UseGuards(AuthGuard('jwt'), FunctionPermissionGuard))
    - permissions 맵 — superadmin null, non-superadmin role baseline + user override merge
    - enforceScope() — roles는 Users.roles (string[] VIRTUAL 컬럼), includes() 로 비교
    - storeId/branchId nullable 처리 — as number 캐스팅 (컨트롤러 레이어에서만)

key-files:
  created:
    - api-ventago/src/app/auth/decorators/function-guard.decorator.ts
    - api-ventago/src/app/auth/guards/function-permission.guard.ts
  modified:
    - api-ventago/src/app/auth/auth.service.ts
    - api-ventago/src/app/auth/auth.module.ts
    - api-ventago/src/app/role/role-function/role-function.service.ts
    - api-ventago/src/app/role/role-function/role-function.controller.ts
    - api-ventago/src/app/users/user-function/user-function.service.ts
    - api-ventago/src/app/users/user-function/user-function.controller.ts

key-decisions:
  - "Users.roles는 string[] VIRTUAL 컬럼이므로 .some(r => r.slug) 대신 .includes('slug') 사용"
  - "FunctionPermissionGuard는 AuthModule providers에 등록 + SequelizeModule.forFeature([RoleFunction, RoleFunctionAction]) 추가"
  - "storeId/branchId nullable → 컨트롤러 레이어에서 'as number' 캐스팅 (JWT 인증 후 항상 존재 보장)"
  - "permissions 맵 빌딩 시 isSuperadmin 변수 재활용 (me() 내 기존 변수)"

patterns-established:
  - "FunctionGuard 패턴: RequireFunction 메타데이터 → FunctionPermissionGuard에서 Reflector로 읽기"
  - "scope enforcement: requester.roles.includes() + targetUser DB 조회로 branchId/storeId 비교"
  - "action-level 교체 방식: destroy all + create new (upsert 아닌 교체 semantics)"

requirements-completed: [PERM-02, PERM-03, PERM-07]

duration: 5min
completed: "2026-04-09"
---

# Phase 14 Plan 02: 백엔드 권한 인프라 Summary

**/me permissions 맵 + @FunctionGuard 데코레이터 + action-level CRUD API + gerente/admin scope enforcement**

## Performance

- **Duration:** 5 min
- **Started:** 2026-04-09T23:38:28Z
- **Completed:** 2026-04-09T23:43:02Z
- **Tasks:** 2
- **Files modified:** 8 (2 created, 6 modified)

## Accomplishments

- auth.service.ts me() 메서드에 permissions 맵 추가 — non-superadmin은 functionSlug → {create,read,update,delete}, superadmin은 null
- FunctionGuard 데코레이터 + FunctionPermissionGuard 구현 — 엔드포인트 보호, superadmin bypass, role + user override 체인 검증
- RoleFunctionService에 updateActionsForRoleFunction() + bulkUpdateRoleFunctionActions() 추가
- UserFunctionService에 updateUserFunctionActions() + resetToRoleDefaults() 추가
- UserFunctionController에 enforceScope() — gerente는 branchId, admin은 storeId 범위 검증

## Task Commits

1. **Task 1: /me permissions 맵 + FunctionGuard 데코레이터/Guard** - `624bb79` (feat)
2. **Task 2: action-level CRUD API + scope enforcement** - `29e628d` (feat)

## Files Created/Modified

- `api-ventago/src/app/auth/decorators/function-guard.decorator.ts` - @FunctionGuard 통합 데코레이터 + FUNCTION_METADATA_KEY + @RequireFunction
- `api-ventago/src/app/auth/guards/function-permission.guard.ts` - FunctionPermissionGuard (CanActivate, superadmin bypass, DB 기반 권한 검증)
- `api-ventago/src/app/auth/auth.service.ts` - me()에 permissions 맵 빌딩 로직 추가 + RoleFunctionAction/UserFunctionAction import
- `api-ventago/src/app/auth/auth.module.ts` - SequelizeModule.forFeature([RoleFunction, RoleFunctionAction]) + FunctionPermissionGuard provider 등록
- `api-ventago/src/app/role/role-function/role-function.service.ts` - getFunctionsByRoleAndStore()에 RoleFunctionAction include, updateActionsForRoleFunction(), bulkUpdateRoleFunctionActions() 추가
- `api-ventago/src/app/role/role-function/role-function.controller.ts` - PUT bulk-actions/:roleId 엔드포인트 추가
- `api-ventago/src/app/users/user-function/user-function.service.ts` - getUserFunctions()에 UserFunctionAction include, updateUserFunctionActions(), resetToRoleDefaults() 추가
- `api-ventago/src/app/users/user-function/user-function.controller.ts` - PUT actions/:targetUserId + POST reset/:targetUserId + enforceScope() 추가

## Decisions Made

- Users.roles는 `string[]` VIRTUAL 컬럼이므로 `.some(r => r.slug === 'superadmin')` 대신 `.includes('superadmin')` 사용 — TypeScript 타입 오류 수정
- FunctionPermissionGuard를 AuthModule providers에 등록하고 RoleFunction/RoleFunctionAction을 SequelizeModule.forFeature에 추가 — RoleFunctionModule이 AuthModule에 import되지 않기 때문
- storeId/branchId nullable (number | null) → 컨트롤러 레이어에서 `as number` 캐스팅 — JWT 인증 후 실질적으로 항상 존재하는 값
- permissions 맵 빌딩 시 me() 내의 기존 `isSuperadmin` 변수를 재활용하여 중복 조회 방지

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Users.roles 타입 불일치 수정**
- **Found during:** Task 2 TypeScript 컴파일
- **Issue:** 플랜의 `user.roles?.some(r => r.slug === 'superadmin')` 코드가 Users 모델의 `roles: string[]` VIRTUAL 컬럼 타입과 불일치하여 TS2339 오류 발생
- **Fix:** enforceScope()에서 `.some(r => r.slug)` → `.includes('role-slug')` 로 변경. FunctionPermissionGuard는 `request.user`를 `any`로 처리하여 기존 코드 유지
- **Files modified:** user-function.controller.ts
- **Verification:** npx tsc --noEmit 성공
- **Committed in:** 29e628d (Task 2 commit)

**2. [Rule 3 - Blocking] storeId/branchId nullable 타입 오류 수정**
- **Found during:** Task 2 TypeScript 컴파일
- **Issue:** `storeId: number | null` 을 `number` 매개변수에 전달 시 TS2345 오류
- **Fix:** 컨트롤러 레이어에서 `user.storeId as number` 캐스팅 추가
- **Files modified:** role-function.controller.ts, user-function.controller.ts
- **Verification:** npx tsc --noEmit 성공
- **Committed in:** 29e628d (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (1 type bug, 1 blocking type error)
**Impact on plan:** 두 수정 모두 TypeScript 타입 정확성을 위한 필수 수정. 기능 범위 변경 없음.

## Issues Encountered

- auth.module.ts에 RoleFunctionModule이 import되어 있지 않아 RoleFunction/RoleFunctionAction 모델이 AuthService에서 접근 불가 — SequelizeModule.forFeature 직접 추가로 해결

## Known Stubs

없음 — 모든 구현이 실제 DB 쿼리 기반.

## Threat Flags

없음 — 플랜의 threat_model에 명시된 T-14-03 ~ T-14-06 모두 구현됨.

## Next Phase Readiness

- Plan 03 (프론트엔드 CASL + permissions context): /me 응답의 permissions 맵 사용 가능
- Plan 04 (역할/유저 권한 관리 UI): bulk-actions API + actions/reset API 사용 가능
- FunctionGuard 데코레이터는 즉시 적용 가능 (`@FunctionGuard('ventas', 'create')`)

## Self-Check: PASSED

- `api-ventago/src/app/auth/decorators/function-guard.decorator.ts` — FOUND
- `api-ventago/src/app/auth/guards/function-permission.guard.ts` — FOUND
- Task 1 commit `624bb79` — FOUND
- Task 2 commit `29e628d` — FOUND

---
*Phase: 14-permisos-control-ui*
*Completed: 2026-04-09*
