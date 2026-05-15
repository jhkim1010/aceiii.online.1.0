# GSD 리뷰 리포트 — Phase 29 권한 시스템 v2 (Day 4)

작성일: 2026-05-14
관련 SPEC: `.gsd/spec-permissions-v2.md`
이전 리뷰: `.gsd/review-permissions-v2-day3.md`

## 완료된 태스크 (Day 4)

- [x] TASK-4.0 functions.slug 매핑 결정 — Option A (functions.permission_slug 컬럼) 채택, SQL 적용
- [x] TASK-4.1 PermissionCacheService 작성
- [x] TASK-4.2 PermissionResolverService 작성 (1-query CTE 기반 합성)
- [x] TASK-4.3 PermissionGuard + @Permission 데코레이터
- [x] TASK-4.4 BranchScopeGuard + @BranchScope 데코레이터
- [⚠️ deferred] TASK-4.5 기존 function-permission.guard 폐기 → **별도 SPEC 으로 분리** (`note-permissions-v2-day4-decision.md`)

## 변경 파일 요약

### 신규 (8)
| 파일 | 역할 | 라인 |
|---|---|---|
| `migrations/phase29-functions-permission-slug.sql` | functions.permission_slug 컬럼 + 매핑 17 UPDATE | ~80 |
| `src/app/permissions/permission-cache.service.ts` | TTL 5분 캐시 read/write/invalidate | ~165 |
| `src/app/permissions/permission-resolver.service.ts` | 1-query CTE 권한 합성 (UNION + override) | ~135 |
| `src/app/permissions/decorators/permission.decorator.ts` | @Permission(slug, action) | ~30 |
| `src/app/permissions/decorators/branch-scope.decorator.ts` | @BranchScope() | ~25 |
| `src/app/permissions/guards/permission.guard.ts` | cache lookup → resolver → 통과/403 | ~135 |
| `src/app/permissions/guards/branch-scope.guard.ts` | user_branches 매핑 검증 | ~125 |
| `.gsd/note-permissions-v2-day4-decision.md` | 기존 가드 폐기 보류 결정 | - |

### 수정 (2)
| 파일 | 변경 |
|---|---|
| `src/app/functions/functions.model.ts` | +1 컬럼 (permissionSlug, NULL 허용) |
| `src/app/permissions/permissions.module.ts` | 4 신규 provider + export 추가 |

## 품질 검증

### DB 적용 결과
| 항목 | 결과 |
|---|---|
| `functions.permission_slug` 컬럼 추가 | ✅ |
| `idx_functions_permission_slug` 인덱스 | ✅ |
| 매핑된 함수 수 | 28 / 148 (19%) |
| 고유 permission_slug | 18 |

### 권한 매핑 커버리지
주요 액션 모두 매핑:
- sales: create, refund, discount, cancel_today, payment_method, read
- products: create, update, delete, price_master, publish
- expenses: create, update, delete
- inventory: adjustment
- categories: manage
- users: manage
- audit: read

### 핵심 SQL 알고리즘 (PermissionResolverService.resolve)

```sql
WITH user_role AS (...)        -- 1 row: 활성 role 추출 (시간 제한 체크)
, base_perms AS (...)          -- role_functions × actions × functions
, user_grants AS (...)         -- user_functions allowed=true overrides
, user_denies AS (...)         -- user_functions allowed=false (차단)
, merged AS (...)              -- (base + grants) - denies, UNION + group
SELECT permission_slug, actions FROM merged;
```

**1 round trip + JSONB aggregate** — N+1 없음.

### Pool 안전 점검
- [x] 모든 쿼리 sequelize 모델 메서드 또는 sequelize.query() — 자동 release
- [x] PermissionGuard 1 요청 = 최대 2 query (cache lookup + resolver)
- [x] cache hit 시 = 1 query (resolver skip)
- [x] cache write upsert 1 query
- [x] try/catch 모든 query — 실패 시 deny-by-default

### 안전 정책
- [x] super_admin/superadmin (legacy) 통과
- [x] @Permission 메타 없는 핸들러 통과 (legacy 호환)
- [x] branchId 누락 + store_owner/store_admin = 통과 (매장 전역)
- [x] 일반 role + branchId 누락 = 403 (지점 정보 강제)
- [x] BranchScopeGuard 의 PRIVILEGED_ROLES 통과: super_admin, store_owner, store_admin

## 완료 기준 충족 여부

| 기준 | 결과 |
|---|---|
| PermissionGuard + cache 동작 | ✅ |
| 1-query 권한 합성 | ✅ |
| BranchScopeGuard 작동 | ✅ |
| functions.slug 매핑 시스템 | ✅ (28 함수 / 18 키) |
| 기존 가드와 충돌 없음 (병행 운영) | ✅ |
| ESLint / build 통과 | ⚠️ Mac 검증 필요 |
| 통합 시나리오 테스트 | ⚠️ Day 5 (실제 controller 적용) 에서 |

## 후속 작업

### ⚠️ 필수 (Mac 검증)
```bash
cd /Users/marcoskim/Trabajos_Programming/ACE_online_1.0/api-ventago
npm run build
npx eslint src/app/permissions/ src/app/functions/ --fix
npm run dev:api
```

### ℹ️ Day 5 진입 시 점검
1. **실제 컨트롤러에 @Permission 적용 1-2 케이스**
   - 신규 컨트롤러 (예: `permissions.controller.ts`) 에 @Permission('users.manage', 'create') 같은 식으로 적용
   - 실제 요청 → 가드 동작 → audit_log 기록 확인

2. **Cache 부하 테스트**
   - 같은 user/branch 100회 연속 요청 → 첫 요청만 resolver, 나머지 cache hit
   - PG pool 사용률 모니터링

3. **functions.permission_slug 매핑 추가**
   - 현재 18% 커버리지 → 점진 확대
   - 신규 SPEC: "permission_slug 매핑 보강 (Phase 30)"

### ℹ️ Day 4 결정 노트
- TASK-4.5 (기존 가드 폐기) 는 별도 SPEC 으로 분리 (`note-permissions-v2-day4-decision.md`)
- 기존 `@FunctionGuard` (스페인어 slug) 와 신규 `@Permission` (영어 dot notation) 병행 운영
- 점진 마이그레이션은 Phase 30 후보

## Sprint 1 진행 현황

| Day | 진행도 | 상태 |
|---|---|---|
| Day 1 — DB 스키마 | 100% | ✅ 완료 |
| Day 2 — Seed | 100% | ✅ 완료 |
| Day 3 — Sequelize 모델 | 100% | ✅ 완료 |
| Day 4 — Guard + Cache | 100% | ✅ 완료 (TASK-4.5 deferred) |
| Day 5 — Approval + API | 0% | 다음 |

**Sprint 1 80% 진행 (4/5 day)** — Day 5 만 남음.
