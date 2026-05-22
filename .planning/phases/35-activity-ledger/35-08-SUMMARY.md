---
phase: 35-activity-ledger
plan: 08
subsystem: database
tags: [postgresql, migration, backfill, dry-run, sql, idempotent]

# Dependency graph
requires:
  - phase: 35-01
    provides: sales.activity_type / origin_branch_id / target_branch_id + CHECK + FKs + indexes
  - phase: 35-02
    provides: StockService.createStockMovement 트랜잭션 패턴 (sales+sale_items+stocks 일관 INSERT, note 형식 reference)
provides:
  - phase35-backfill-movidos-to-sales.sql (idempotent backfill SQL — movido(out/in) + fallado → sales 그룹화 INSERT)
  - phase35-backfill-dry-run.sh (BEGIN→backfill→ROLLBACK 검증 스크립트, dev/prod 환경)
  - backfill_failures 테이블 스키마 (parse 실패 행 격리, D-09 위험 처리)
  - stocks.backfill_processed_sale_id 추적 컬럼 (idempotent guard)
affects: [35-uat (운영 backfill 실행)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Idempotent backfill: stocks.backfill_processed_sale_id IS NULL guard → 재실행 시 중복 INSERT 방지"
    - "Group-by-second 그룹화 (DATE_TRUNC('second', created_at) + origin/target/baseNote) — 같은 createStockMovement 호출 단위로 매핑"
    - "Parse failure isolation: regexp_match 결과 NULL → backfill_failures 격리 + sales 미생성 (D-09 안전망)"
    - "Dry-run pattern: awk 로 SQL 의 COMMIT → ROLLBACK 치환 + 검증 쿼리 inline 삽입 (TX 보호)"
    - "PG10/PG15/PG18 호환 SQL: regexp_match, SPLIT_PART, ARRAY_AGG, DATE_TRUNC, ALTER TABLE ... ADD COLUMN IF NOT EXISTS (모두 PG 9.4+)"
    - "BSD/macOS awk multi-line 변수 회피: 외부 임시 파일 + getline 패턴"

key-files:
  created:
    - "api-ventago/migrations/phase35-backfill-movidos-to-sales.sql"
    - "api-ventago/migrations/phase35-backfill-dry-run.sh"
  modified: []

key-decisions:
  - "운영 backfill 실행은 본 plan 범위 외 — Phase 35-UAT 에서 별도 PR + 사용자 승인 (D-09)"
  - "Local PG18 dry-run 만으로 알고리즘 검증 — Docker 미설치 환경 (env_overrides 흡수)"
  - "backfill_failures + stocks.backfill_processed_sale_id 는 backfill SQL 자체의 일부 — 운영 적용 후에도 영구 유지 (audit trail)"
  - "그룹화 정밀도 second 유지 (SPEC D-09 결정) — millisecond 전환은 운영 실행 시 위험 감지 후 결정"
  - "movido(in) 행은 INSERT 하지 않고 짝(out) sale 과 매칭만 (UPDATE backfill_processed_sale_id) — sales 행 중복 방지"

patterns-established:
  - "DDL idempotent guard: CREATE TABLE IF NOT EXISTS + ADD COLUMN IF NOT EXISTS"
  - "PL/pgSQL DO 블록으로 그룹화 + 다중 INSERT — RETURNING id INTO local var → child INSERT 패턴"
  - "Phase 35 backfill marker: sales.notes LIKE '[Backfill Phase 35]%' (운영에서 식별 가능한 prefix)"

requirements-completed: [AL-30, AL-31, AL-32, AL-33]

# Metrics
duration: 4min
completed: 2026-05-22
---

# Phase 35 Plan 08: Backfill SQL + Dry-Run Validation Summary

**stocks(type='adjust', note LIKE 'movido%'|'fallado%') 행을 sales+sale_items 1급 시민으로 backfill 하는 idempotent SQL + ROLLBACK-안전 dry-run 검증 스크립트 작성 — 로컬 PG18 에서 실행 검증 완료, 운영 적용은 Phase 35-UAT 보류.**

## Performance

- **Duration:** 4 min
- **Started:** 2026-05-22T23:46:05Z
- **Completed:** 2026-05-22T23:50:57Z
- **Tasks:** 2
- **Files created:** 2

## Accomplishments
- `phase35-backfill-movidos-to-sales.sql` 작성 (252 lines, PG10/PG15/PG18 호환)
  - movido(out) 그룹화 → sales(activity_type='movido') + sale_items INSERT
  - fallado: 그룹화 → sales(activity_type='fallado') + sale_items INSERT
  - movido(in) 행은 짝(out) sale 과 매칭 → backfill_processed_sale_id 만 UPDATE (INSERT 없음)
  - parse 실패 행 → backfill_failures 격리 (sales 미생성)
  - idempotent: `backfill_processed_sale_id IS NULL` guard 로 재실행 안전
- `phase35-backfill-dry-run.sh` 작성 (168 lines, executable)
  - awk 로 SQL 의 COMMIT → ROLLBACK 치환 + 검증 쿼리 inline 삽입
  - dev (localhost PG18) / prod (jhkim-server SSH PG10) 환경 지원
  - BEFORE/AFTER counts 출력으로 ROLLBACK 검증 자동화
- Local PG18 dry-run 실행 → BEFORE/AFTER sales count 동일 (변경 없음 검증)
- `npm run build` PASS (모델 변경 없음 확인)

## Task Commits

각 task 가 api-ventago nested git repo 에 원자적으로 commit 되었습니다:

1. **Task 1: backfill SQL 스크립트 + backfill_failures 테이블** — `04c8e50` (feat)
   - `api-ventago/migrations/phase35-backfill-movidos-to-sales.sql` 생성 (252 lines)
   - 9개 acceptance criteria 모두 통과 (CREATE TABLE / regexp_match / 3 패턴 / [Backfill Phase 35] prefix 등)
2. **Task 2: dry-run 검증 쉘 스크립트** — `6fa1d28` (feat)
   - `api-ventago/migrations/phase35-backfill-dry-run.sh` 생성 (168 lines, executable)
   - bash -n syntax 통과, dry-run 실행 후 sales 변경 없음 확인

_Plan metadata (SUMMARY.md) 는 부모 워킹트리에서 별도 commit (orchestrator 가 wave 종료 후 처리)._

## Files Created/Modified

- `api-ventago/migrations/phase35-backfill-movidos-to-sales.sql` — 신규. 6-step idempotent backfill SQL.
- `api-ventago/migrations/phase35-backfill-dry-run.sh` — 신규. ROLLBACK-안전 검증 wrapper.

## Dry-Run Verification (local PG18)

```text
=== Phase 35 Backfill Dry-Run (dev) ===
SQL file: /Users/marcoskim/Trabajos_Programming/ACE_online_1.0/api-ventago/migrations/phase35-backfill-movidos-to-sales.sql

=== BEFORE (read-only) ===
 activity_type | row_count
---------------+-----------
 sale          |        26
(1 row)

 candidates_movido_out | candidates_movido_in | candidates_fallado
-----------------------+----------------------+--------------------
                     8 |                    8 |                  0
(1 row)


=== DRY-RUN 실행 (ROLLBACK 보장) ===

BEGIN
NOTICE:  relation "backfill_failures" already exists, skipping
CREATE TABLE
NOTICE:  relation "idx_backfill_failures_source" already exists, skipping
CREATE INDEX
NOTICE:  column "backfill_processed_sale_id" of relation "stocks" already exists, skipping
ALTER TABLE
COMMENT
DO
DO
UPDATE 8
INSERT 0 0

--- backfill 결과 요약 ---
 activity_type | backfilled_rows
---------------+-----------------
 movido        |               3
(1 row)


--- backfill_failures 수 ---
 failed_rows
-------------
           0
(1 row)


--- 처리된 stocks 수 ---
 distinct_sales | total_stock_rows
----------------+------------------
              3 |               16
(1 row)


--- 미처리 movido(out) / fallado / movido(in) 행 ---
 unprocessed_movido_out | unprocessed_movido_in | unprocessed_fallado
------------------------+-----------------------+---------------------
                      0 |                     0 |                   0
(1 row)


--- 활동별 sales 행 분포 (backfill 포함) ---
 activity_type | count
---------------+-------
 movido        |     3
 sale          |    26
(2 rows)

ROLLBACK

=== AFTER (read-only — ROLLBACK 후 변경 없음 확인) ===
 activity_type | row_count
---------------+-----------
 sale          |        26
(1 row)

 marked_stocks
---------------
             0
(1 row)

 persisted_failures
--------------------
                  0
(1 row)


=== Dry-Run 완료 (ROLLBACK 적용 — 실제 변경 없음) ===
검토 후 운영 적용은 별도 PR 승인 + 운영 DB 백업 후 실행 (Phase 35-UAT).
```

**검증 결과:**
- **BEFORE sales=26 (sale only) == AFTER sales=26 (sale only)** — ROLLBACK 완벽 작동 ✓
- 8 movido(out) → 3 distinct movido sales 그룹화 (3개 createStockMovement 호출의 합)
- 16 stocks 마킹 (8 out + 8 in 매칭) — out 만 sale 생성, in 은 짝과 매칭만
- 0 backfill_failures — 모든 note 패턴 정상 파싱
- 0 미처리 행 — 모든 candidate 처리

## Decisions Made

- **운영 적용 보류**: D-09 risk 처리. 본 plan 은 SQL + dry-run 검증만. 운영 실행은 Phase 35-UAT 에서 별도 승인 필요.
- **Group-by-second 그룹화**: SPEC D-09 결정 유지. 운영 빈도상 1초 미만에 동일 (origin, target, baseNote) 충돌 거의 없음. 위험 감지 시 millisecond 로 전환 가능.
- **movido(in) INSERT 안 함**: 짝(out)이 이미 sale 을 생성했으므로 in 행은 추적 컬럼만 UPDATE. 중복 sale 방지.
- **store_id 도달 경로**: `branches.store_id` 직접 조회 (단순). branch 가 삭제되어 NULL 이면 backfill_failures 격리.
- **notes 길이 안전**: `sales.notes` 가 VARCHAR(255) — `LEFT('[Backfill Phase 35] ' || base_note, 255)` 로 clip 처리.
- **price/subtotal/discount_amount = 0 (NOT NULL)**: sale_items 의 NOT NULL NUMERIC 제약 충족 + D-10 통계 오염 차단 (모든 매출 쿼리는 activity_type='sale' 필터).

## Deviations from Plan

### Environment Adjustments (env_overrides 지시)

**1. [Environment override] Docker 미설치 → 로컬 PG18 직접 접속**
- **Found during:** Pre-Task 1 (환경 점검)
- **Issue:** PLAN sketch 의 검증 명령은 `docker exec dbpostgres psql -U coolsistema -d ventago < migrations/...` 가정. env_overrides 가 명시적으로 호스트 PG18 직접 접속을 지시.
- **Fix:** dry-run 스크립트 dev 환경을 `psql -h localhost -p 5432 -U $USER -d ventago -v ON_ERROR_STOP=1` 로 작성 (PLAN sketch 의 `dbpostgres` 미사용).
- **Files modified:** N/A (스크립트 작성 시 직접 반영)
- **Verification:** Local PG18 18.3 에서 dry-run 정상 실행 + ROLLBACK 검증.

### Auto-fixes (Rule 1 - Bug)

**1. [Rule 1 - Bug] Initial sanity-check 가 의도와 달리 실제 변경을 commit**
- **Found during:** Task 1 직후 SQL syntax sanity-check (`psql -c "BEGIN;" -f file.sql -c "ROLLBACK;"`)
- **Issue:** PLAN sketch 의 backfill SQL 자체가 `BEGIN; ... COMMIT;` 으로 감싸져 있어, 외부 `BEGIN; ... ROLLBACK;` 으로 감싸도 내부 COMMIT 이 우선 실행되어 변경이 persist 됨. 본 명령 후 sales 에 3개 movido + stocks 16개 마킹이 commit 됨.
- **Fix:** 즉시 cleanup transaction 실행 — DELETE sale_items / DELETE movido sales / UPDATE stocks SET backfill_processed_sale_id=NULL / DELETE backfill_failures 로 dev DB 를 깨끗한 상태로 복원. 이후 dry-run 스크립트는 awk 로 내부 COMMIT 을 ROLLBACK 으로 치환하는 패턴 사용 (PLAN sketch 명세대로).
- **Files modified:** 데이터 cleanup 만, 코드 변경 없음
- **Commit:** N/A (DB 상태 복원, 코드 변경 무관)

### Auto-fixes (Rule 3 - Blocking)

**2. [Rule 3 - Blocking] BSD awk 가 multi-line `-v verify="$HEREDOC"` 에서 newline 오류**
- **Found during:** Task 2 첫 dry-run 실행 시도
- **Issue:** macOS BSD awk 는 `awk -v var="multi-line string"` 의 줄바꿈을 `newline in string` 오류로 처리. `\echo` 명령 3개가 모두 fail.
- **Fix:** 검증 쿼리를 별도 임시 파일(`$TMP_VERIFY`)에 작성 → awk 가 `getline line < verify_file` 로 외부 파일 read 하여 inline 삽입. BSD/GNU awk 모두 호환.
- **Files modified:** `api-ventago/migrations/phase35-backfill-dry-run.sh` (Task 2 의 동일 commit 에 포함 — 별도 commit 없음)
- **Commit:** `6fa1d28` (Task 2 commit 에 통합 — 첫 시도 실패 후 동일 task scope 내에서 수정)

---

**Total deviations:** 1 environment + 1 bug (cleanup 만) + 1 blocking (Task 2 inline fix)
**Impact on plan:** SQL 본문/알고리즘은 plan 명세대로. dry-run 스크립트의 BSD awk 호환은 plan sketch 가 GNU awk 가정 — 호환성 보강.

## Issues Encountered

- Initial sanity-check 의 잘못된 가정 (외부 BEGIN/ROLLBACK 이 내부 COMMIT 을 덮을 것이라는 오해) — 즉시 cleanup 으로 복구. 이 경험이 dry-run 스크립트의 awk substitution 패턴의 필요성을 재확인시킴.
- BSD/macOS awk 와 GNU awk 의 multi-line `-v` 차이 — `getline line < file` 패턴이 양쪽 모두 호환.

## Threat Flags

scan 결과: 새 threat surface 도입 없음. backfill SQL 은 기존 sales/stocks 테이블 + Plan 01 에서 신설된 컬럼만 사용. backfill_failures 테이블은 새 데이터 store 이나 인증/네트워크 경로 없음 — audit trail 용 internal table.

## Next Phase Readiness

- **Phase 35-UAT 준비**: 본 plan 의 SQL + dry-run 스크립트는 검증 완료. UAT 단계에서:
  1. 운영 PG10 에서 `./phase35-backfill-dry-run.sh prod` 실행으로 dry-run COUNT 검증
  2. 사용자 검토 후 SQL 직접 실행 (`ssh jhkim-server "sudo -u postgres psql -d ventago" < phase35-backfill-movidos-to-sales.sql`)
  3. UAT criterion U20/U21/U22 검증
- **Operational safety**: 운영 적용 시 사전 백업 + 사용자 승인 필수 (D-09).
- **Blocker/Concern 없음**.

## Self-Check: PASSED

**Files verified:**
- `api-ventago/migrations/phase35-backfill-movidos-to-sales.sql` — FOUND
- `api-ventago/migrations/phase35-backfill-dry-run.sh` — FOUND (executable)

**Commits verified (api-ventago repo):**
- `04c8e50` (Task 1) — FOUND
- `6fa1d28` (Task 2) — FOUND

**Dry-run verification:**
- BEFORE sales count == AFTER sales count (26 sale rows, ROLLBACK 정상)
- backfill_failures persist=0 (ROLLBACK 정상)
- stocks marked persist=0 (ROLLBACK 정상)
- Algorithm: 8 movido(out) → 3 sales + 16 stocks tracked, 0 parse failures

**Build verification:**
- `cd api-ventago && npm run build` → PASS (NestJS SWC build, exit 0)

---
*Phase: 35-activity-ledger*
*Completed: 2026-05-22*
