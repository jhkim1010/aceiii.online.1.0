---
phase: 35-activity-ledger
plan: 01
subsystem: database
tags: [postgresql, sequelize, migration, schema, sales, ledger]

# Dependency graph
requires:
  - phase: existing v1.0
    provides: sales 테이블 + branches 테이블 (Store/Branch 계층)
provides:
  - sales.activity_type / origin_branch_id / target_branch_id 컬럼
  - chk_sales_activity_type CHECK 제약 (sale | movido | fallado)
  - fk_sales_origin_branch / fk_sales_target_branch FK 제약 → branches(id)
  - 3 인덱스 (idx_sales_activity_date + 2 partial index)
  - Sale 모델 SaleActivityType enum + activityType/originBranchId/targetBranchId 컬럼 + originBranch/targetBranch BelongsTo 관계
affects: [35-activity-ledger-plan-02, 35-activity-ledger-plan-03, sales-service, reports, stock-cockpit]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "PG10/PG15 호환 idempotent DDL — IF NOT EXISTS + DO 블록 (pg_constraint 체크)"
    - "VARCHAR + CHECK 를 native ENUM TYPE 의 대안으로 사용 (PG10 호환)"
    - "Sale 모델 명시적 WHERE 정책 — @DefaultScope 사용 금지 (SPEC D-04 risk 1 회피)"
    - "Partial index 패턴: WHERE col IS NOT NULL — sparse FK 컬럼에 적용"

key-files:
  created:
    - "api-ventago/migrations/phase35-activity-ledger.sql"
  modified:
    - "api-ventago/src/app/sales/sales.model.ts"

key-decisions:
  - "VARCHAR(16) + CHECK 를 native ENUM 대신 사용 — 추후 ALTER 용이성 + PG10 호환"
  - "FK 제약 ON DELETE 미지정 (기본 NO ACTION) — branches 삭제 시 movido/fallado 사용 이력 보존"
  - "@DefaultScope 추가하지 않음 — 명시적 WHERE 'sale' 절을 Plan 02 에서 sales.service 에 도입 (의도치 않은 누락 가능성 차단)"
  - "partial index (WHERE col IS NOT NULL) — sale 행은 origin/target NULL 이므로 인덱스 크기 절약"

patterns-established:
  - "Idempotent DDL guard: DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_constraint ...) THEN ALTER TABLE ... END IF; END $$;"
  - "Phase 35 unified ledger 패턴: sales 테이블 1행 = 모든 재고 영향 트랜잭션 (sale/movido/fallado)"

requirements-completed: [AL-01, AL-02, AL-03]

# Metrics
duration: 5min
completed: 2026-05-22
---

# Phase 35 Plan 01: Activity Ledger Foundation Summary

**sales 테이블을 unified transaction ledger 로 확장 — activity_type/origin_branch_id/target_branch_id 컬럼 + Sequelize 모델 매핑 (movido/fallado 1급 시민화의 토대)**

## Performance

- **Duration:** 5 min
- **Started:** 2026-05-22T22:08:34Z
- **Completed:** 2026-05-22T22:13:49Z
- **Tasks:** 2
- **Files modified:** 2 (1 created, 1 modified)

## Accomplishments
- sales 테이블에 3 신규 컬럼 추가 (PG10/PG15 호환 마이그레이션, 기존 26 row 모두 DEFAULT='sale' 적용)
- CHECK 제약 + 2 FK + 3 INDEX 추가, 모두 idempotent (DO 블록 가드 검증)
- Sale 모델에 SaleActivityType enum + 3 컬럼 + 2 BelongsTo(Branch) 노출
- ESLint + NestJS 빌드 통과

## Task Commits

각 task 가 api-ventago nested git repo 에 원자적으로 commit 되었습니다:

1. **Task 1: 마이그레이션 SQL 작성 + 적용** — `8838f59` (feat)
   - `api-ventago/migrations/phase35-activity-ledger.sql` 생성 (85 lines)
   - 로컬 PG18 적용 + idempotent 재실행 검증
2. **Task 2: Sale 모델 확장** — `560ff6f` (feat)
   - `api-ventago/src/app/sales/sales.model.ts` 수정 (+38 lines)
   - `npm run build` PASS / `eslint sales.model.ts` PASS

_Plan metadata (SUMMARY.md) 는 부모 워킹트리에서 별도 commit (orchestrator 가 wave 종료 후 처리)._

## Files Created/Modified
- `api-ventago/migrations/phase35-activity-ledger.sql` — Phase 35 DDL 마이그레이션 (3 컬럼 + CHECK + 2 FK + 3 INDEX, PG10/PG15 호환, idempotent)
- `api-ventago/src/app/sales/sales.model.ts` — SaleActivityType enum + activityType/originBranchId/targetBranchId 컬럼 + originBranch/targetBranch BelongsTo + Branch import

## Migration Verification (local PG18)

```
=== 1) Activity type counts (expect all=sale) ===
 activity_type | count
---------------+-------
 sale          |    26

=== 2) Constraints (expect 3 rows) ===
chk_sales_activity_type
fk_sales_origin_branch
fk_sales_target_branch

=== 3) Indexes (expect 3 rows) ===
idx_sales_activity_date
idx_sales_origin_branch
idx_sales_target_branch

=== 4) Columns (data types) ===
 activity_type    | character varying | NO  | 'sale'::character varying
 origin_branch_id | integer           | YES | NULL
 target_branch_id | integer           | YES | NULL

=== 5) NULL activity_type rows: 0 ===

=== Idempotent re-run: PASS (NOTICE messages only, no errors) ===
```

## Decisions Made

- **VARCHAR(16) + CHECK 대신 native ENUM 미사용**: 추후 활동 종류 추가 시 ALTER 부담 최소화 + PG10 운영 환경 호환 (Phase 25/26 검증된 패턴)
- **FK ON DELETE 미지정 (기본 NO ACTION)**: 지점이 삭제되어도 movido/fallado 사용 이력은 보존되어야 함 (audit trail)
- **`@DefaultScope` 미적용**: SPEC D-04 risk 1 회피 — `WHERE activity_type='sale'` 누락 시 매출 통계가 movido/fallado 행으로 오염될 위험. 명시적 WHERE 절은 Plan 02 의 sales.service 에서 일괄 적용 예정
- **Partial index (WHERE IS NOT NULL)**: sale 행이 압도적 다수(전체 row 의 ~95%+ 추정)이고 origin/target 은 NULL — partial index 로 인덱스 크기를 movido/fallado 행 수만큼만 유지

## Deviations from Plan

### Environment Adjustment (not a code deviation)

**1. [Environment override] Docker 없는 로컬 환경 → 호스트 PG18 직접 접속**
- **Found during:** Task 1 (마이그레이션 SQL 적용)
- **Issue:** Plan 은 `docker exec dbpostgres psql -U coolsistema -d ventago < migrations/...` 사용을 가정. 본 머신에는 docker 가 설치되어 있지 않음 (orchestrator env_overrides 명시).
- **Fix:** `psql -h localhost -p 5432 -U $USER -d ventago -v ON_ERROR_STOP=1 -f api-ventago/migrations/phase35-activity-ledger.sql` 로 대체 (env_overrides 지시).
- **Files modified:** N/A (실행 명령만 변경)
- **Verification:** 5 검증 쿼리 + idempotent 재실행 PASS
- **Committed in:** N/A

### Code Auto-fixes

None — 두 task 모두 PLAN 명세대로 정확히 실행됨.

---

**Total deviations:** 1 environment-only (코드 변경 없음)
**Impact on plan:** 환경 차이 (docker 없음) 만 흡수. SQL 내용/모델 구조는 plan 과 동일.

## Issues Encountered

- `npm run lint` (전체 프로젝트 lint script) 가 사전 존재하는 5198 errors 를 보고. 본 plan 의 scope boundary 규칙에 따라 사전 존재 lint 오류는 처리하지 않음. **수정한 `sales.model.ts` 단일 파일 대상 ESLint (`npx eslint --no-fix src/app/sales/sales.model.ts`) 는 EXIT=0 으로 통과** — 본 plan 의 변경은 깨끗함.
- 별도 issue 없음.

## Next Phase Readiness

- **Plan 02 준비 완료**: sales 테이블에 movido/fallado 행을 insert 할 수 있는 스키마 + Sequelize 매핑이 모두 갖춰짐. Plan 02 에서 `StockService.createStockMovement` 가 sale 행(activityType='movido'/'fallado') 을 단일 트랜잭션으로 생성 가능.
- **명시적 WHERE 정책 후속 작업**: 현재 sales.service / reports 의 모든 매출 쿼리는 `activity_type='sale'` 필터를 추가해야 함 (Plan 02 범위). 이 plan 에서는 `@DefaultScope` 미적용으로 자동 적용 안 됨 → Plan 02 가 명시적으로 추가해야 함.
- **운영 PG10 적용 보류**: 본 plan 은 로컬 dev 만 적용. 운영 적용은 Phase 35-UAT 단계에서 별도 승인 후 진행 예정 (plan action 명시).
- **Blocker/Concern 없음**.

## Self-Check: PASSED

**Files verified:**
- `api-ventago/migrations/phase35-activity-ledger.sql` — FOUND
- `api-ventago/src/app/sales/sales.model.ts` — FOUND (modified)

**Commits verified (api-ventago repo):**
- `8838f59` (Task 1) — FOUND
- `560ff6f` (Task 2) — FOUND

**DB verification:**
- 3 columns present, 26 existing rows backfilled to 'sale'
- 3 constraints (1 CHECK + 2 FK) present
- 3 indexes present
- Idempotent re-run: no errors

---
*Phase: 35-activity-ledger*
*Completed: 2026-05-22*
