# GSD 리뷰 리포트 — Phase 29 권한 시스템 v2 (Day 3)

작성일: 2026-05-14
관련 SPEC: `.gsd/spec-permissions-v2.md`
이전 리뷰: `.gsd/review-permissions-v2-day1-2.md`

## 완료된 태스크 (Day 3)

- [x] TASK-3.1 UserBranch 모델
- [x] TASK-3.2 ApprovalThreshold 모델
- [x] TASK-3.3 ApprovalRequest 모델
- [x] TASK-3.4 UserPermissionCache 모델
- [x] TASK-3.5 기존 모델 확장 (UserFunction +5 컬럼, RoleFunction +1 컬럼, AuditLog ENUM +8값)
- [x] TASK-3.6 PermissionsModule 신설 + AppModule 등록

## 변경 파일 요약

### 신규 (5)
| 파일 | 용도 | 라인 |
|---|---|---|
| `src/app/permissions/models/user-branch.model.ts` | 사용자-지점-역할 매핑 | ~85 |
| `src/app/permissions/models/approval-threshold.model.ts` | 승인 임계값 | ~70 |
| `src/app/permissions/models/approval-request.model.ts` | 승인 대기 큐 | ~95 |
| `src/app/permissions/models/user-permission-cache.model.ts` | 권한 계산 캐시 (TTL 헬퍼 포함) | ~70 |
| `src/app/permissions/permissions.module.ts` | NestJS 모듈 (4 모델 등록) | ~35 |

### 수정 (3)
| 파일 | 변경 |
|---|---|
| `src/app/users/user-function/user-function.model.ts` | +5 컬럼 (branchId, validFrom, validUntil, reason, grantedBy) + Branch/Users(grantor) association |
| `src/app/role/role-function/role-function.model.ts` | +1 컬럼 (branchId) + Branch association |
| `src/app/audit-log/audit-log.model.ts` | action ENUM 5 → 13 값 (assign/revoke/grant/deny/threshold_change/role_create/role_delete/scope_change) + TS 타입 union 동기화 |
| `src/app.module.ts` | PermissionsModule import + imports 배열 등록 |

## 품질 검증

### 모델 정합성 (DB 스키마 ↔ Sequelize 모델)
| 검사 | 결과 |
|---|---|
| `user_branches` 컬럼 9개 ↔ UserBranch 모델 속성 | ✅ 일치 (id, userId, branchId, roleId, isDefault, validFrom, validUntil, grantedBy, reason) |
| `approval_thresholds` 컬럼 9개 ↔ ApprovalThreshold | ✅ 일치 (id, storeId, branchId, functionSlug, roleSlug, maxAmount, maxQuantity, approverRoleSlug + timestamps) |
| `approval_requests` 컬럼 11개 ↔ ApprovalRequest | ✅ 일치 |
| `user_permission_cache` 컬럼 4개 ↔ UserPermissionCache (composite PK) | ✅ 일치 |
| `user_functions` 신규 5컬럼 ↔ UserFunction 확장 | ✅ 일치 |
| `role_functions.branch_id` ↔ RoleFunction 확장 | ✅ 일치 |
| `audit_logs.action` ENUM 13값 ↔ AuditLog ENUM | ✅ 일치 (5 기존 + 8 신규) |

### Sequelize underscored 매핑
- 모든 신규 모델이 camelCase 속성 사용 → `underscored: true` 전역 설정으로 snake_case DB 컬럼 자동 매핑
- 예외: `tableName: 'user_branches'` 명시 (모델명 UserBranch 의 자동 복수화 불일치 방지)

### Pool 안전
- [x] 신규 모델은 클래스 정의만 — runtime connection 사용 없음
- [x] PermissionsModule 의 `SequelizeModule.forFeature` 는 모델 메타데이터 등록만 — pool 영향 없음
- [x] 캐시 invalidation 로직은 Day 4 (PermissionGuard) 작업에서 구현 예정

### 타입 안전성
- [x] ApprovalRequestStatus union type export — 컨트롤러에서 안전한 status 비교
- [x] PermissionMap interface export — `{ [functionSlug: string]: string[] }` 형식 강제
- [x] UserPermissionCache.isExpired() 헬퍼 메서드 — TTL 5분 기본값

### 회귀 위험 분석 (기존 모델 확장)
- [x] **UserFunction**: 모든 신규 컬럼이 `allowNull: true` 또는 default 값 보유 → 기존 row 영향 없음
- [x] **RoleFunction.branchId**: `allowNull: true` → 기존 row 가 NULL 로 자동 해석 (= 매장 전체)
- [x] **AuditLog ENUM**: 기존 5값 보존 + 8값 추가 → 기존 코드 영향 없음

## 완료 기준 충족 여부

| 기준 | 결과 |
|---|---|
| 신규 모델 4개 + 기존 3개 확장 | ✅ |
| Sequelize-typescript 패턴 준수 (기존 코드와 일관) | ✅ |
| underscored:true 자동 매핑 활용 | ✅ |
| PermissionsModule + AppModule 등록 | ✅ |
| ESLint / npm run build 통과 | ⚠️ 샌드박스 timeout — Mac 검증 필요 (별도 task) |

## 후속 작업 (Day 4 진입 전 권장)

### ⚠️ 1. Mac 에서 build 검증 (필수)
```bash
cd api-ventago
npm run build
# 또는
npx tsc --noEmit
```
모델 import path 오류, association 사이클 등이 build 시점에 잡힙니다.

### ⚠️ 2. ESLint 검증 (필수)
```bash
cd api-ventago
npx eslint src/app/permissions/ src/app/users/user-function/ src/app/role/role-function/ src/app/audit-log/ --fix
```
newline-before-return, lines-around-comment 위반 자동 수정.

### ℹ️ 3. 모델 등록 효과 확인
- 앱 재시작 (`npm run dev:api`) 후 로그에서 `[SequelizeModels]` 출력 확인
- 4 신규 모델 (UserBranch, ApprovalThreshold, ApprovalRequest, UserPermissionCache) 이 등록되어야 함
- DatabaseModule 의 `criticalModels` 디버그 검사에 추가 가능 (선택)

## 다음 단계 (Day 4 — PermissionGuard)

신규 모델이 준비되었으므로 핵심 로직 구현 가능:

1. **PermissionGuard** (`src/app/auth/guards/permission.guard.ts`)
   - 요청마다: cache lookup → MISS 시 1-query 권한 합성 → cache INSERT
   - 단일 SQL with CTE: `user_branches JOIN role_functions JOIN role_function_actions LEFT JOIN user_functions WHERE valid_until IS NULL OR valid_until > NOW()`
   - JSONB aggregate 로 권한 set 구성

2. **BranchScopeGuard** (`src/app/auth/guards/branch-scope.guard.ts`)
   - `@BranchScope({ paramName: 'branchId' })` 데코레이터
   - 요청 path/body 의 branchId 가 user.user_branches 에 속하는지 검증

3. **PermissionCacheService** (`src/app/permissions/permission-cache.service.ts`)
   - `invalidateUser(userId)`, `invalidateBranch(branchId)`, `invalidateAll()`
   - 권한 변경 hook 에서 호출

4. **기존 `function-permission.guard.ts` 폐기**
   - `@FunctionGuard` → `@Permission` 일괄 치환 (약 30-40개 컨트롤러)

5. **functions.slug 매핑 이슈 해결** (Day 1-2 review 의 후속)
   - 영어 dot notation (`sales.refund`) ↔ 스페인어 액션 (`crear-venta`) 매핑
   - 옵션 A: `function_categories` 매핑 테이블 신설
   - 옵션 B: `functions` 테이블에 `english_slug` 컬럼 추가
   - 결정: Day 4 시작 시 마르코스님과 합의

## 누적 진행 상황 (Sprint 1)

| Day | 진행도 | 상태 |
|---|---|---|
| Day 1 — DB 스키마 | 100% | ✅ 완료 |
| Day 2 — Seed | 100% | ✅ 완료 |
| Day 3 — Sequelize 모델 | 100% | ✅ 완료 (build 검증만 남음) |
| Day 4 — Guard + Cache | 0% | 다음 |
| Day 5 — Approval + API | 0% | 다음 |
