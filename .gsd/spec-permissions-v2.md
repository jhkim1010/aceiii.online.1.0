# SPEC: 권한 시스템 v2 — RBAC + Branch Scope + Approval Threshold

생성일: 2026-05-14
관련 문서: `.planning/permissions-redesign/ANALYSIS.md`, `Ventago_Permissions_Matrix.xlsx`, `mockup.html`

## 목표

운영 사용자 0명인 zero-cost window 를 활용하여, 권한 모델을 한 번에 v2 (RBAC + Branch Scope + Approval Threshold + Audit) 로 갈아엎습니다. 점진 마이그레이션, 기능 플래그, 병렬 가드 운영을 모두 생략하고, 첫 매장 진입 전에 깨끗한 모델로 확정합니다.

## 배경 및 컨텍스트

### 현재 상태 (As-Is)
- Role 4개 (`superadmin/admin/gerente/vendedor`) — 정의 모호, 멀티지점 미지원
- 권한 체크: `function-permission.guard.ts` 가 3-stage 쿼리 (RoleFunction → RoleFunctionAction → UserFunction). 캐시 없음.
- 로그 분석 (combined-2026-05-14.log): `role_functions` SELECT 가 104ms slow query 로 잡힘 — 캐시 도입 정당성 확보됨.
- `users.branch_id` 단일 FK — 한 사용자가 여러 지점에서 다른 role 을 가질 수 없음.
- `audit_logs` 테이블 존재하지만 권한 변경은 기록 안 됨.
- DB Pool: `min=10, max=80, idle=10s, acquire=15s` (database.module.ts L37-43). 모니터링 인터벌 30/60s, 80% 초과 시 경고. **CLAUDE.md 의 max=50 표기는 오래된 값.**

### 사용자 0명의 자유도
- 기존 `users.branch_id` 데이터 마이그레이션 불필요 → 컬럼 deprecate (즉시 삭제 X, 다음 phase 에서 정리)
- 기존 4 role seed 폐기 → 8 표준 role 로 완전 교체
- ACL `subject` ↔ BE `function_slug` 어휘 통일 가능 (FE 컴포넌트 마이그레이션 부담 X)
- 기능 플래그 / dry-run / 병렬 가드 코드 불필요

### 신규 모델 (4 테이블)
- `user_branches` — (user_id, branch_id, role_id, valid_from/until, granted_by, reason)
- `approval_thresholds` — (store_id, branch_id NULL, function_slug, role_slug, max_amount, max_quantity, approver_role_slug)
- `approval_requests` — (store_id, branch_id, requested_by, function_slug, payload JSONB, status, expires_at)
- `user_permission_cache` — (user_id, branch_id, permissions JSONB, computed_at) — TTL 5분

### Multi-role 정책 (확정)

본 SPEC 의 권한 모델 정책 — 헷갈림 방지를 위해 명시:

1. **한 사용자 / 한 지점 / 1 role** — `user_branches.UNIQUE (user_id, branch_id)` 강제
2. **한 사용자 / 여러 지점 / 지점마다 다른 role** — 지원 (예: 본점 branch_manager + 강남점 cashier)
3. **한 지점에서 여러 role 이 필요한 경우** — `user_functions` 오버라이드로 보완. 예: cashier 가 일시적으로 회계 일부 기능 필요 시 `user_functions` 에 해당 function 만 grant
4. **향후 multi-role-per-branch 확장이 필요해지면** — `UNIQUE (user_id, branch_id)` 를 `UNIQUE (user_id, branch_id, role_id)` 로 완화. 권한 합성 정책은 **UNION + max 한도** (넓은 권한 우선). 본 SPEC 에서는 미구현이지만 PermissionGuard 의 권한 합성 로직을 처음부터 UNION 친화적으로 작성하여 향후 확장 비용 최소화

**충돌 시 정책 (PermissionGuard 구현 가이드)**:
- 권한 (CRUD): 여러 출처(role + user_functions grants) 의 합집합 (UNION). deny 가 명시된 경우만 차단 (`user_functions.allowed = false`)
- 임계값: 여러 role 보유 시 더 큰 max_amount / max_quantity 적용 (Sprint 2 day 6 시점에 multi-role 미지원이지만 함수 시그니처는 N개 role 받도록 작성)

### 기존 모델 확장
- `role_functions`: `branch_id INTEGER NULL` 컬럼 추가
- `user_functions`: `branch_id NULL`, `valid_from/until`, `reason`, `granted_by` 컬럼 추가
- `audit_logs.action` ENUM 확장: `assign, revoke, grant, deny, threshold_change, role_create, role_delete, scope_change`

## 기술 스택

- **언어/프레임워크**: NestJS 11 + TypeScript (백엔드), Next.js 13 + React 18 (프론트)
- **DB**: PostgreSQL 15 (dev Docker `dbpostgres`), 운영 PG10 호스트
- **ORM**: Sequelize + sequelize-typescript (`underscored: true`)
- **Pool**: `min=10, max=80, idle=10s, acquire=15s` (database.module.ts) — 권한 v2 의 캐시 도입으로 pool 압박 감소가 목표
- **상태관리**: Redux Toolkit + SWR (`src/hooks/api/`)
- **UI**: Material-UI (MUI) 5
- **인가**: 기존 ACL → `function_slug` 어휘로 통일
- **ESLint 설정**: `api-ventago/.eslintrc.js`, `ventago-app/.eslintrc.js`

## 태스크 목록

### Sprint 1 — Backend (1주)

#### Day 1: DB 스키마

- [ ] **TASK-1.1**: 마이그레이션 SQL 작성 — 신규 테이블 4개 + 기존 컬럼 확장 + ENUM 확장. 단일 파일.
  - 파일: `api-ventago/migrations/phase29-permissions-v2.sql`
  - PG10/15 양쪽 호환 (ENUM ALTER 는 PG10 호환 문법 사용)
  - 인덱스는 `CREATE INDEX CONCURRENTLY` (CONCURRENTLY 는 트랜잭션 밖에서 실행)
  - 운영 사용자 0명 → backfill 스크립트 불필요

- [ ] **TASK-1.2**: 로컬 dev PG18 에 마이그레이션 적용 + 스키마 reference 갱신
  - 실행: `psql -d ventago -f migrations/phase29-permissions-v2.sql`
  - 후속: `./.planning/intel/db-schema.regen.sh`
  - 결과: `.planning/intel/db-schema-tables.md` + `db-schema-fks.md` 갱신, git commit

#### Day 2: Seed + 기본 데이터

- [ ] **TASK-2.1**: 8 표준 Role seed 작성 (기존 4 role seed 교체)
  - 파일: `api-ventago/src/app/users/seeder/user.seeder.ts`
  - 기존 `vendedor/admin/gerente/superadmin` 폐기, 신규 `super_admin/store_owner/store_admin/branch_manager/cashier/inventory_clerk/accountant/viewer` 시드
  - storeId NULL 인 super_admin 1개 + 매장 생성 시 나머지 7개 자동 생성

- [ ] **TASK-2.2**: 기본 `role_functions` + `role_function_actions` seed
  - 파일: `api-ventago/src/app/users/seeder/role-permissions.seeder.ts` (신규)
  - 데이터 출처: `Ventago_Permissions_Matrix.xlsx` Permission Matrix 시트 (31 함수 × 8 role)
  - 매장 생성 시 해당 storeId 로 자동 시드 (`storeTemplate.service.ts` 의 `createStoreDefaults` 확장)

- [ ] **TASK-2.3**: 기본 `approval_thresholds` seed (10개 액션)
  - 파일: `api-ventago/src/app/users/seeder/approval-thresholds.seeder.ts` (신규)
  - 데이터 출처: 매트릭스 xlsx 의 "승인 임계값" 시트
  - 매장 생성 시 해당 storeId 로 자동 시드 (값은 ARS 기준 기본값, owner 가 셋업 마법사에서 조정)

#### Day 3: Sequelize 모델

- [ ] **TASK-3.1**: 4개 신규 모델 클래스 작성
  - 파일:
    - `api-ventago/src/app/permissions/models/user-branch.model.ts`
    - `api-ventago/src/app/permissions/models/approval-threshold.model.ts`
    - `api-ventago/src/app/permissions/models/approval-request.model.ts`
    - `api-ventago/src/app/permissions/models/user-permission-cache.model.ts`
  - `underscored: true` 준수 (camelCase 속성 → snake_case 컬럼 자동 매핑)
  - User / Branch / Role 과 association 정의

- [ ] **TASK-3.2**: 기존 모델 확장
  - `api-ventago/src/app/users/user-function/user-function.model.ts` — branch_id, valid_from/until, reason, granted_by 컬럼 추가
  - `api-ventago/src/app/role/role-function/role-function.model.ts` (또는 동등 위치) — branch_id 컬럼 추가
  - `api-ventago/src/app/audit-log/audit-log.model.ts` — action ENUM 값 추가

- [ ] **TASK-3.3**: PermissionsModule 신설 + 모델 등록
  - 파일: `api-ventago/src/app/permissions/permissions.module.ts`
  - SequelizeModule.forFeature 로 4 모델 등록

#### Day 4: Guard + Cache

- [ ] **TASK-4.1**: 신규 `PermissionGuard` (1-query + cache)
  - 파일: `api-ventago/src/app/auth/guards/permission.guard.ts` (신규)
  - 동작: ① cache lookup → HIT 시 JSONB 검사 ② MISS 시 단일 SQL (user_branches JOIN role_functions JOIN role_function_actions LEFT JOIN user_functions WHERE valid_until IS NULL OR > NOW()) ③ 결과 cache INSERT (TTL 5분 = computed_at 기준 sliding)
  - **PG pool 안전**: `pool.query()` 사용 (`pool.connect()` 패턴 안 씀, Sequelize transaction 내부 자동 release)
  - try/catch 필수, 에러 시 deny-by-default + 로그

- [ ] **TASK-4.2**: 신규 `BranchScopeGuard`
  - 파일: `api-ventago/src/app/auth/guards/branch-scope.guard.ts` (신규)
  - 요청 path/body 의 `branchId` 와 user 의 `user_branches` 매칭 검증
  - `@BranchScope({ paramName: 'branchId' })` 데코레이터로 컨트롤러에 적용

- [ ] **TASK-4.3**: 기존 `function-permission.guard.ts` 폐기
  - 코드 삭제 + 사용처 `@FunctionGuard` 데코레이터를 `@Permission` 으로 일괄 치환
  - 영향 파일: 약 30-40개 컨트롤러 (예상). grep 으로 일괄 식별

- [ ] **TASK-4.4**: Cache invalidation 로직
  - 파일: `api-ventago/src/app/permissions/permission-cache.service.ts`
  - `invalidateUser(userId)`, `invalidateBranch(branchId)`, `invalidateAll()` 메서드
  - 권한 변경 모든 경로 (UserBranch, UserFunction, RoleFunction, ApprovalThreshold) 의 hook 에서 호출

#### Day 5: Approval + Audit + API

- [ ] **TASK-5.1**: `approval.service.ts` + `approval.controller.ts`
  - 파일: `api-ventago/src/app/permissions/approval.service.ts`, `approval.controller.ts`
  - 임계값 체크 로직 + 큐잉 (`approval_requests` INSERT) + socket.io 푸시 (승인자에게 알림)
  - 엔드포인트: `POST /api/approval/requests`, `GET /api/approval/requests?status=pending`, `POST /api/approval/requests/:id/approve`, `POST /api/approval/requests/:id/reject`
  - **PG pool 안전**: 모든 쿼리 try/finally + pool.query() 또는 transaction.commit/rollback finally release

- [ ] **TASK-5.2**: audit_log 권한 변경 기록
  - 파일: `api-ventago/src/app/audit-log/audit-log.service.ts` 확장
  - `logPermissionChange(userId, action, oldValues, newValues, reason)` 메서드 추가
  - UserBranch / UserFunction / Role 모든 변경 hook 에서 호출 — 같은 transaction 안에서 실행하여 권한만 바뀌고 audit 누락되는 케이스 차단
  - audit INSERT 실패 시 ROLLBACK

- [ ] **TASK-5.3**: 권한 매트릭스 API
  - 파일: `api-ventago/src/app/permissions/permissions.controller.ts`
  - `GET /api/permissions/matrix?storeId=X&branchId=Y` — 매트릭스 화면용 (Role × Function × Action)
  - `GET /api/permissions/users/:id` — 사용자 상세
  - `PUT /api/permissions/users/:id/branches` — 사용자의 user_branches 일괄 갱신
  - `PUT /api/permissions/roles/:slug/functions` — role 의 권한 매트릭스 갱신
  - 단일 SQL with CTE + JSONB aggregate (1 round trip — N+1 방지)

- [ ] **TASK-5.4**: 백엔드 ESLint 검증
  - 실행: `cd api-ventago && npx eslint . --fix`
  - 오류 0개 확인 (newline-before-return, lines-around-comment, no-unused-vars 주의)

### Sprint 2 — Frontend + 검증 (1주)

#### Day 6-7: 권한 관리 페이지

- [ ] **TASK-6.1**: 4탭 페이지 신설
  - 파일: `ventago-app/src/pages/configuracion/permisos/index.tsx` (신규)
  - 파일: `ventago-app/src/views/configuracion/permisos/PermissionsView.tsx` (신규)
  - 4 탭: 권한 매트릭스 / 사용자 상세 / 감사 로그 / 승인 임계값
  - mockup.html 의 다크 네이비 + 골드 테마를 MUI 5 + sx props 로 변환
  - 코드 스플리팅: `next/dynamic(() => import(...), { ssr: false })`

- [ ] **TASK-6.2**: SWR 훅 4개 신설
  - 파일: `ventago-app/src/hooks/api/usePermissionsMatrix.ts`
  - 파일: `ventago-app/src/hooks/api/useUserBranches.ts`
  - 파일: `ventago-app/src/hooks/api/useApprovalQueue.ts`
  - 파일: `ventago-app/src/hooks/api/useAuditLog.ts`
  - 5분 dedup, 에러 핸들링 포함

- [ ] **TASK-6.3**: 매트릭스 그리드 컴포넌트
  - 파일: `ventago-app/src/views/configuracion/permisos/MatrixGrid.tsx`
  - sticky header + sticky first column
  - 셀 클릭 → CRUD 4 체크박스 popover
  - 변경된 셀은 노란 배경, "저장하지 않음" 토스트
  - React.memo 적용 (재렌더 비용 큰 컴포넌트)

- [ ] **TASK-6.4**: 사용자 상세 / 감사 로그 / 임계값 컴포넌트
  - 파일: `ventago-app/src/views/configuracion/permisos/UserDetail.tsx`
  - 파일: `ventago-app/src/views/configuracion/permisos/AuditLog.tsx`
  - 파일: `ventago-app/src/views/configuracion/permisos/ThresholdEditor.tsx`

#### Day 8: ACL 어휘 통일

- [ ] **TASK-7.1**: ACL generator 스크립트
  - 파일: `ventago-app/scripts/gen-permissions.ts` (신규)
  - 동작: `/api/permissions/functions` 엔드포인트 호출 → TypeScript enum 자동 생성 → `src/configs/permissions.gen.ts` 출력
  - 빌드 시 `prebuild` 훅에서 자동 실행

- [ ] **TASK-7.2**: 기존 ACL `subject` 일괄 치환
  - 영향 파일: `ventago-app/src/configs/acl.ts`, `roles.ts`, 모든 `WithAccess` 사용처 (약 60-80개 컴포넌트 예상)
  - 새 어휘: `Permission.SALES_REFUND` (enum) 형태
  - sed 또는 codemod 로 일괄 치환

- [ ] **TASK-7.3**: 프론트엔드 ESLint 검증
  - 실행: `cd ventago-app && npx eslint . --fix`
  - 오류 0개 확인

#### Day 9: E2E 테스트

- [ ] **TASK-8.1**: E2E 테스트 시나리오 작성
  - 파일: `api-ventago/test/e2e/permissions.e2e-spec.ts` (신규)
  - 시나리오: ① 매장 생성 → 8 role 자동 시드 → 사용자 추가 → user_branches 부여 → 환불 임계값 초과 시도 → 승인 큐 INSERT → 승인 → 감사 로그 4건 확인 (assign, refund_attempt, approval, refund_success)
  - **금지**: DB mock 사용 금지. 실제 dev PG18 hit (CLAUDE.md 규칙 준수, 사용자 메모리 #2 testing 정책)

- [ ] **TASK-8.2**: PG pool 부하 테스트
  - 파일: `api-ventago/test/load/permissions-pool.test.ts` (신규)
  - 시나리오: 100개 동시 요청 × 50회 반복 → pool 사용률 P95 ≤ 50%, cache hit ≥ 95% 확인
  - 실패 시 cache TTL / invalidation 패턴 점검

#### Day 10: 첫 매장 셋업

- [ ] **TASK-9.1**: 매장 셋업 마법사 페이지
  - 파일: `ventago-app/src/pages/admin/store/setup-wizard.tsx` (신규)
  - 단계: 매장 정보 → 8 role 확인 (커스터마이징 가능) → approval_thresholds 기본값 확인 → 첫 사용자 생성
  - super_admin 만 접근 가능

- [ ] **TASK-9.2**: 운영 PG10 마이그레이션 적용 + 스모크 테스트
  - 운영 서버에 phase29-permissions-v2.sql 적용 (사용자 확인 필수 — DDL)
  - 첫 매장 (ACE) 마법사 실행 → 8 role 시드 확인
  - 첫 사용자 로그인 → 권한 매트릭스 화면 정상 표시 확인

## 완료 기준

- [ ] 백엔드 ESLint 오류 0개
- [ ] 프론트엔드 ESLint 오류 0개
- [ ] E2E 테스트 100% 통과
- [ ] PG pool 사용률 P95 ≤ 50% (현재 80% 임계 경고에서 여유)
- [ ] cache hit ratio ≥ 95%
- [ ] 권한 체크 latency P95 ≤ 30ms (현재 role_functions 단일 쿼리만 104ms)
- [ ] audit_logs 의 entity_type='permission' 정상 적재
- [ ] 첫 매장 owner 가 신규 UI 로 사용자 5명 셋업 (SQL 도움 없이)

## 금지사항 / 주의사항

- **`pool.connect()` 직접 사용 금지** — `sequelize.query()` 또는 모델 메서드 사용 (Sequelize 가 자동 release)
- **권한 변경 트랜잭션 안에 audit_log INSERT 강제** — 둘이 분리되면 권한만 바뀌고 audit 누락 발생
- **Frontend 에 새 ACL 어휘를 mockup HTML 그대로 hardcode 금지** — 반드시 generator 로 BE source of truth 가져옴
- **CLAUDE.md 의 `pool max=50` 표기는 오래된 값** — 실제는 `max=80, min=10`. SPEC 적용 후 CLAUDE.md 업데이트 필요 (별건 task)
- **OnlineOrdersExpiryCron 의 "이전 실행 진행 중" 경고는 별개 이슈** — 본 SPEC 범위 밖, 별도 추적 (로그에서 끊임없이 발생 중)
- **운영 PG10 마이그레이션 SQL 실행은 반드시 사용자 확인** — DDL 은 CLAUDE.md 운영 서버 규칙 준수
- **운영 사용자 0명 가정** — 도중에 사용자가 들어오면 backfill 전략으로 즉시 전환 필요
- **8 role 확정 전에 ACE owner 와 30분 인터뷰 권장** (선택, SPEC 외) — 이 단계를 생략하고 코드 작성하면 운영 진입 후 조정 비용 발생

## 후속 작업 (이 SPEC 범위 밖)

- **OnlineOrdersExpiryCron stuck 조사** — 로그에서 매 15분마다 "이전 실행 진행 중" skip 발생 (별도 SPEC)
- **`users.branch_id` 컬럼 정리** — 다음 phase 에서 deprecate → drop
- **CASL 도입 여부 검토** — "본인이 만든 판매만 환불" 같은 조건부 권한이 늘어나면 (3개월 후 점검 시 결정)
- **CLAUDE.md `pool max` 표기 갱신** — `max=50` → `max=80`
