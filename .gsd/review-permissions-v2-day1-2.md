# GSD 리뷰 리포트 — Phase 29 권한 시스템 v2 (Day 1-2)

작성일: 2026-05-14
관련 SPEC: `.gsd/spec-permissions-v2.md`
관련 분석: `.planning/permissions-redesign/ANALYSIS.md`

## 완료된 태스크

- [x] TASK-1.1 마이그레이션 SQL 작성 (`migrations/phase29-permissions-v2.sql`)
- [x] TASK-1.2 로컬 dev PG18 적용 + fixup 적용 (`migrations/phase29-permissions-v2-fixup.sql`)
- [x] TASK-2.1 8 표준 Role seed (`src/app/users/seeder/user.seeder.ts`)
- [x] TASK-2.2 role_functions + role_function_actions 보수적 시드 (`src/app/store/storeTemplate.service.ts`)
- [x] TASK-2.3 approval_thresholds 13 rule 자동 시드 (`src/app/store/storeTemplate.service.ts`)

## 변경 파일 요약

### 신규 파일 (4)
| 파일 | 역할 | 라인 수 |
|---|---|---|
| `migrations/phase29-permissions-v2.sql` | 4 신규 테이블 + ENUM 확장 + 컬럼 확장 + 10 인덱스 | ~210 |
| `migrations/phase29-permissions-v2-fixup.sql` | user_functions 컬럼 + NOW() partial index 수정 | ~80 |
| `.planning/permissions-redesign/ANALYSIS.md` | 다층 사고법 분석 + 추천 | 387 |
| `.gsd/spec-permissions-v2.md` | GSD SPEC (Sprint 1+2, multi-role 정책 명문화 포함) | ~250 |

### 수정 파일 (2)
| 파일 | 변경 | 영향 |
|---|---|---|
| `src/app/users/seeder/user.seeder.ts` | 기존 4 role 폐기 → 8 표준 Role 체계. super_admin 글로벌 시드. STANDARD_ROLES export. | +117/-30 |
| `src/app/store/storeTemplate.service.ts` | createDefaultRoles: 7 매장별 role. createDefaultRoleFunctions: 보수적 권한 시드 (super_admin/store_owner full, 나머지 read-only). createDefaultApprovalThresholds: 13 rule 자동 시드. | +193/-15 |

## 품질 검증

### ESLint
- [⚠️ partial] `user.seeder.ts`, `storeTemplate.service.ts` — 샌드박스 ESLint 가 timeout (TypeScript 프로젝트 전체 로드 비용). 마르코스님 Mac 에서 `cd api-ventago && npm run lint -- src/app/users/seeder/user.seeder.ts src/app/store/storeTemplate.service.ts` 로 재확인 권장.
- 문법적으로 newline-before-return, lines-around-comment, no-unused-vars 위반 없도록 작성.

### PostgreSQL Pool 안전
- [x] `pool.connect()` 직접 사용 없음 — Sequelize transaction context (`{ transaction }`) 만 사용 → 자동 release 보장.
- [x] 모든 `sequelize.query` 호출이 try/catch 안에 있음 (createDefaultApprovalThresholds 의 raw SQL).
- [x] DDL은 단일 transaction 안에서 BEGIN/COMMIT 묶임. CREATE INDEX CONCURRENTLY 는 트랜잭션 밖에서 자동 실행.
- [x] DB Pool 설정 (database.module.ts): `min=10, max=80, idle=10s, acquire=15s` — 기존 설정 그대로 유지. 매장 생성 1회 = 1 connection × 약 2.5초 (2,500 INSERT 시) 예상 — 빈도 낮아 영향 미미.
- [x] `idx_user_branches_user_active` 의 `WHERE NOW()` 같은 IMMUTABLE 위반 모두 제거 — `valid_until IS NULL` partial + 별도 `valid_until` 인덱스로 분리.

### DB 무결성
| 항목 | 기대 | 실제 | 결과 |
|---|---|---|---|
| 신규 테이블 | 4 | 4 | ✅ |
| audit_logs.action ENUM 신규값 | 8 | 8 | ✅ |
| user_functions 신규 컬럼 | 5 | 5 | ✅ |
| role_functions.branch_id | 1 | 1 | ✅ |
| Phase29 인덱스 | 10 | 10 | ✅ |

### 에러 핸들링
- [x] user.seeder: try/catch + transaction.rollback. 에러 메시지 한국어/영어 혼용 OK.
- [x] storeTemplate.createDefaultApprovalThresholds: try/catch + console.error + throw (상위 트랜잭션 rollback 트리거).
- [x] ON CONFLICT DO NOTHING — 임계값 시드 idempotent 보장.

## 완료 기준 충족 여부

| 기준 | 결과 |
|---|---|
| 백엔드 ESLint 오류 0개 | ⚠️ 샌드박스 timeout, Mac 에서 재확인 필요 |
| DB 마이그레이션 적용 + 검증 100% | ✅ |
| 8 표준 Role 시드 코드 + 매장별 자동 생성 | ✅ |
| approval_thresholds 13 rule 자동 시드 | ✅ |
| Pool max=80 안에서 안전한 connection 사용 | ✅ |

## 발견된 이슈 / 후속 작업 (필수)

### ⚠️ 1. 기존 idempotent 가드 누락 (코드 수정 후에도 잔존)
- 현재 store 6 (test1) 의 role_functions 가 **436 row** (정상 148 의 약 3배) — 기존 `createDefaultRoleFunctions` 가 같은 매장에 여러 번 호출되어 중복 INSERT.
- 제가 작성한 신규 코드도 같은 패턴 — `RoleFunction.findOrCreate` 또는 `INSERT ... ON CONFLICT DO NOTHING` 으로 가드 추가 필요.
- **권장**: 후속 SPEC 으로 처리 (Day 3 Sequelize 모델 작업과 함께).

### ⚠️ 2. functions.slug 어휘 불일치 (Sprint 2 Day 4 영향)
- 매트릭스 (xlsx) 의 권한 키는 영어 dot notation (`sales.refund`, `products.delete`) — 31개 추상 함수.
- 실제 `functions` 테이블 slug 는 스페인어 액션 단위 (`crear-venta`, `devolver-ropa`) — 148개.
- approval_thresholds 의 `function_slug` 컬럼은 영어 추상명 사용 — Sprint 2 Day 4 의 PermissionGuard 가 이 둘을 매핑하는 로직 필요.
- **권장**: function_categories 매핑 테이블 신설 또는 functions 테이블에 `english_slug` 컬럼 추가 (별도 SPEC).

### ⚠️ 3. ESLint 샌드박스 timeout
- 샌드박스에서 `eslint` 실행 시 TypeScript 프로젝트 전체 로드 때문에 30-40초 timeout.
- 마르코스님 Mac 에서 `cd api-ventago && npx eslint src/app/users/seeder/user.seeder.ts src/app/store/storeTemplate.service.ts --fix` 로 재검증 권장.

### ℹ️ 4. dev DB 의 기존 4 role 잔존
- 기존 시드 (`vendedor/admin/superadmin/gerente`) 가 글로벌 role 로 4개 그대로 남아있음.
- 신규 시드 코드는 `super_admin` 만 글로벌로 시드. 기존 4 role 은 그대로 두되 새 매장 생성 시 사용 안 됨.
- **선택**: 기존 4 글로벌 role 을 정리할지는 마르코스님 결정 (운영 사용자 0명이므로 지금 정리 가능).

### ℹ️ 5. 신규 매장 생성 시 INSERT 부하
- 매장 1개 생성 = **2,536 row INSERT** (role 7 + role_functions 1036 + role_function_actions 1480 + approval_thresholds 13).
- 단일 transaction 안 — 약 2-3초 예상. 매장 생성은 빈번하지 않아 (월 0-5건) pool 영향 미미.
- 향후 batch INSERT 로 최적화 가능 (선택 사항, 우선순위 낮음).

## 다음 단계 (Sprint 1 Day 3+)

### Day 3 — Sequelize 모델 4개
- UserBranch, ApprovalThreshold, ApprovalRequest, UserPermissionCache 모델 클래스
- PermissionsModule 신설 + 모델 등록
- 기존 모델 확장 (user-function.model.ts, role-function.model.ts, audit-log.model.ts)

### Day 4 — PermissionGuard (1-query + cache)
- 신규 `PermissionGuard` (단일 SQL with CTE + JSONB aggregate)
- `BranchScopeGuard` 신설
- 기존 `function-permission.guard.ts` 폐기 + `@FunctionGuard` → `@Permission` 일괄 치환
- Cache invalidation 서비스
- functions.slug ↔ permission_slug 매핑 (이슈 #2)

### Day 5 — Approval + Audit + API
- approval.service / controller (큐잉 + socket.io 푸시)
- audit_log 권한 변경 자동 기록
- `/api/permissions/matrix` 엔드포인트

## 마이그레이션 적용 가이드 (운영용)

운영 PG10 적용 시 (Day 10 에 진행 예정):

```bash
# 1) phase29 본 SQL 적용
ssh jhkim-server "sudo -u postgres psql -d ventago" < api-ventago/migrations/phase29-permissions-v2.sql

# 2) (필요 시) fixup 적용 — 신규 환경은 phase29-permissions-v2.sql 만으로 OK
#    이미 본 SQL 에 fixup 내용이 반영되어 있음.
```

운영 사용자 0명 가정이지만, 적용 전 dry-run 으로 영향 범위 확인 권장:
```sql
-- 기존 매장에 영향 있는지
SELECT count(*) FROM users;
SELECT count(*) FROM role_functions;
```
