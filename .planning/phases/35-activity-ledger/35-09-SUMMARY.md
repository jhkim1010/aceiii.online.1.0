---
phase: 35-activity-ledger
plan: 09
subsystem: testing
tags: [uat, verification, checkpoint, manual, sh, automation]
status: awaiting_user_validation

# Dependency graph
requires:
  - phase: 35-01
    provides: sales.activity_type + CHECK + FKs + indexes
  - phase: 35-02
    provides: stock.movement permission + InjectBranchIdFromOriginGuard
  - phase: 35-03
    provides: activity_type='sale' filter on 13 services + /sales/daily-stats endpoint
  - phase: 35-04
    provides: useDailySalesStats SWR hook + SalesResumenTable component
  - phase: 35-05
    provides: DataConfig Tipo chip + URL/chip sync + Resumen drilldown
  - phase: 35-06
    provides: ProductList toast Ver detalle link
  - phase: 35-07
    provides: Stock Cockpit MOV+/MOV-/FAL columns + OFFSET coloring + cell navigate
  - phase: 35-08
    provides: phase35-backfill-movidos-to-sales.sql + dry-run shell + backfill_failures DDL
provides:
  - 35-UAT.md (22 UAT items + U9b/U12b regression + DEFERRED U18 + implemented U19)
  - phase35-uat.sh (automated DB schema + code grep + cURL smoke; 21 PASS / 0 FAIL / 1 SKIP)
  - awaiting_user_validation status checkpoint for manual UI/E2E verification
affects:
  - 35-RUNBOOK-PROD.md (separate doc — production backfill, written only after user UAT sign-off)
  - ROADMAP.md Phase 35 status (stays "verifying" until user marks all U items)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "UAT checklist 1:1 mapping to SPEC L450-481 — each U item has 절차 / 기대 / 결과 칸"
    - "Automated check categories: auto-pass (PASS), auto-pending (SKIP - api offline), manual (UI/E2E)"
    - "Bash uat script with env-overridable PG_*/API_BASE/API_JWT — runs as ci or dev"
    - "set -uo pipefail (not -e) so SKIP paths do not abort the run"
    - "psql_q helper isolates PGOPTIONS / 2>/dev/null for clean output"
    - "Frontend infra checks via find for component drift tolerance"
    - "Verbatim script output embedded in 35-UAT.md (not a separate log file)"

key-files:
  created:
    - ".planning/phases/35-activity-ledger/35-UAT.md"
    - "api-ventago/test/phase35-uat.sh"
  modified: []

key-decisions:
  - "Status awaiting_user_validation — plan 09 is autonomous:false so the orchestrator returns the manual checklist to the user"
  - "Script runs 21 automated checks but is read-only — no UI launching, no destructive DB ops"
  - "cURL smoke (U9/U9b/U10) intentionally optional via API_JWT env var so the script never hangs on missing api-ventago"
  - "Frontend component checks use find (not hard-coded paths) — tolerates Phase 35-04/07 path conventions (views/sales/list/components vs views/ventas)"
  - "U18 DEFERRED is documented inline in UAT.md as a checklist N/A, not as a TODO — user can decide Phase 35-C registration during sign-off"
  - "U19 implementation is documented as a regression check, not new work — Plan 35-07 Task 2 already shipped it"
  - "Production backfill (U21) is dev-only in this UAT — operations RUNBOOK is a separate artifact gated on user sign-off"

patterns-established:
  - "Phase UAT scaffold pattern: 35-UAT.md + phase-UAT.sh + per-U item table with 자동/매뉴얼 카테고리"
  - "Script summary embedded verbatim in UAT.md (auditable in git diff)"
  - "Read-only verifier shell — no INSERT/UPDATE/DROP on operations DB"

requirements-completed: [AL-34, AL-35, AL-36]

# Metrics
duration: 6min
completed: 2026-05-22
---

# Phase 35 Plan 09: UAT Scaffold + Auto-Verification Script Summary

**Phase 35-A/35-B/Backfill 의 22 UAT 항목 (U1..U22) + 회귀 검증 2건 (U9b/U12b) 을 체크리스트 + 절차 + 결과 칸으로 정리한 `35-UAT.md` 와, DB/코드 grep/cURL smoke 21 자동 검증을 실행하는 `phase35-uat.sh` 작성. 자동 검증 21/21 PASS (FAIL 0). U18 DEFERRED, U19 implemented in 35-07. 매뉴얼 UI/E2E 검증은 사용자에게 위임 (awaiting_user_validation).**

## Performance

- **Duration:** 6 min
- **Started:** 2026-05-22T23:55:06Z
- **Completed:** 2026-05-23T00:01:00Z (approx)
- **Tasks:** 2 (Task 3 checkpoint은 본 plan 의 종료점 — fresh agent 안 됨, 사용자 사인오프 기대)
- **Files created:** 2 (parent + api-ventago)
- **Files modified:** 0

## Accomplishments

- `.planning/phases/35-activity-ledger/35-UAT.md` 신규 작성 (565 lines)
  - 사전 조건 + Phase 35-A/35-B/Backfill 3 그룹 + 종합 평가 + 부록 raw output
  - 22 UAT 항목 (U1..U22) + 회귀 2건 (U9b, U12b) 1:1 매핑 SPEC L450-481
  - U18: 명시적 DEFERRED — Phase 35-C/36 후보 사유 명시
  - U19: 명시적 "Plan 07 Task 2 에서 구현됨" 표기 + 검증 절차
  - 각 항목: 카테고리(auto/manual/cURL/E2E) + 절차 + 기대 + 결과 칸 ([ ] PASS / [ ] FAIL / [ ] pending)
- `api-ventago/test/phase35-uat.sh` 신규 작성 (292 lines, executable)
  - 21 자동 검증 항목 (PASS 21 / FAIL 0 / SKIP 1)
  - env-overridable: `PG_HOST/PG_PORT/PG_DB/PG_USER/API_BASE/API_JWT`
  - 카테고리: DB schema, code grep, frontend component presence, backfill DDL, cURL smoke (optional)
  - bash syntax 검증 PASS, `set -uo pipefail` 안전성
- 로컬 PG18 (localhost:5432/ventago) 에 대해 실제 실행 → 21 PASS / 0 FAIL / 1 SKIP (cURL smoke api offline)
- 자동 검증 raw output 을 35-UAT.md 의 "자동 검증 스크립트 결과" 섹션에 verbatim 임베드 (auditable)

## Task Commits

| Task | Name | Repo | Hash | Files |
|------|------|------|------|-------|
| 1 | 35-UAT.md 작성 | parent | `7db894d` | `.planning/phases/35-activity-ledger/35-UAT.md` |
| 2 | phase35-uat.sh 작성 + 실행 | api-ventago | `3d416de` | `api-ventago/test/phase35-uat.sh` |
| Checkpoint | 사용자 매뉴얼 UAT 사인오프 | — | — | (orchestrator returns checklist to user) |

_본 SUMMARY.md 는 plan metadata commit 의 일부로 부모 repo 에 별도 추가 commit 됨._

## Files Created/Modified

- **Created:** `.planning/phases/35-activity-ledger/35-UAT.md` — Phase 35 UAT 체크리스트 + 절차 + 결과 + 자동 검증 raw output
- **Created:** `api-ventago/test/phase35-uat.sh` — 자동 검증 쉘 (executable, 292 lines)

## Automated Verification Result

```
=== Phase 35 UAT 자동 검증 ===
  PG: marcoskim@localhost:5432/ventago
  API: http://localhost:5002/api (JWT NOT SET → cURL SKIP)
  Repo: /Users/marcoskim/Trabajos_Programming/ACE_online_1.0

[21 items PASS — see 35-UAT.md "자동 검증 스크립트 결과" section for verbatim output]

=== 자동 검증 요약 ===
  PASS: 21
  FAIL: 0
  SKIP: 1   (cURL smoke — api-ventago not running)

exit code: 0
```

**Pass coverage (per U item):**
- U1 (schema): 4 checks PASS (3 columns + CHECK + 2 FK + 3 indexes)
- U4/U5 (filter integrity): 2 checks PASS (no invalid activity_type rows, no NULL)
- U9 (permission seed): 3 checks PASS (function row, 11 role mappings, 5 expected roles)
- U9b (user_functions migration): 1 PASS (0 grants OK — 90-day window empty in dev)
- U12 (matrix grep): 1 PASS (all 7 reports/dashboards services contain activity_type filter)
- U12b (code grep): 2 PASS (sales-create + online-order-mirror filter applied)
- U3/U4/U5/U11 (frontend infra): 2 PASS (SalesResumenTable + useDailySalesStats found)
- U15/U16/U19 (cockpit infra): 2 PASS (PanelB MOV+/MOV-/FAL refs + navigate code)
- U20 (backfill infra): 4 PASS (SQL + shell + table + column)
- U9/U9b/U10 (cURL smoke): 1 SKIP (api offline)

## Manual Verification Items (Returned to User)

**Phase 35-A (14 items + 2 regression):**
- U1 (UI register): POS 화면에서 movido 등록 + DB 확인
- U2: ventaVista 리스트 [MOV] chip + JEFE→SALA 라우트
- U3: Resumen 테이블 MOV+/MOV− 셀 정확
- U4: PRENDAS 카운트 변화 없음 (regression)
- U5: VENTAS 금액 변화 없음 (regression)
- U6: Resumen 행 클릭 → URL ?branch=X + chip
- U7: Resumen 셀 클릭 → 2 chip + URL
- U8: chip X 클릭 → URL 제거
- U9: 권한 없는 user → 403 (cURL with API_JWT)
- U9b: 비-privileged + 권한 부여 + 자기 지점 → 200 (cURL with API_JWT)
- U10: 다른 지점 origin → 403 (cURL with API_JWT)
- U11: 단일 지점 사용자 → TOTAL 행 숨김
- U12: /reportes/ventas 수치 변화 없음
- U12b: 신규 sale dailyNumber === lastSale + 1
- U13: fallado 등록 + [FAL] chip + FAL 셀
- U14: movBalance 알람 (정합성 인위적 깨뜨림)

**Phase 35-B (5 items, U18 deferred):**
- U15: Stock Cockpit MOV+/MOV−/FAL 컬럼 정확
- U16: OFFSET 변동 없음 (regression)
- U17: STOCK 등식 검증 (수동 spot check)
- U18: **DEFERRED — Phase 35-C/36 후보** (자동 N/A 처리)
- U19: MOV+ 셀 click → ventaVista navigate (Plan 35-07 Task 2 구현 검증)

**Backfill (3 items):**
- U20: backfill dry-run (./api-ventago/migrations/phase35-backfill-dry-run.sh dev)
- U21: backfill 실제 INSERT 후 과거 ventaVista 표시 (dev only)
- U22: backfill 후 매출 보고서 수치 변화 없음

## Decisions Made

- **autonomous:false + status awaiting_user_validation**: Plan 09 의 Task 3 은 checkpoint:human-verify. 본 SUMMARY 는 매뉴얼 UAT 항목 사용자 반환을 명시.
- **자동 검증 쉘 read-only**: phase35-uat.sh 는 SELECT/grep 만 수행. DB INSERT/UPDATE/DROP 없음 (CLAUDE.md 의 운영 쿼리 안전 규칙 준수, dev 환경에서도 영향 없음).
- **frontend component 검색 패턴**: `find ... -name "SalesResumenTable.tsx"` (실제 경로: `views/sales/list/components/`) — hard-coded path 대신 검색으로 drift 흡수.
- **cURL smoke optional + API_JWT env**: api-ventago 가 미실행 환경에서도 스크립트가 hang 없이 SKIP 처리. 사용자는 dev:api 실행 + JWT 발급 후 재실행 가능.
- **production backfill 제외**: U21 dev only, U22 dev only. 운영 backfill 은 35-RUNBOOK-PROD.md 별도 작성 (사용자 사인오프 후 진행).

## Deviations from Plan

### Environment Adjustment (not a code deviation)

**1. [Environment override] Docker 부재 → 호스트 PG18 직접 접속**
- **Found during:** Task 2 스크립트 작성
- **Issue:** Plan 의 `docker exec dbpostgres psql ...` 패턴 사용 불가 (Docker 미설치).
- **Fix:** psql_q 헬퍼를 `psql -h $PG_HOST -p $PG_PORT -U $PG_USER -d $PG_DB` 로 작성. PG_* 환경변수 default 는 localhost:5432, 운영에서는 env override 가능.
- **Files modified:** `api-ventago/test/phase35-uat.sh`
- **Committed in:** `3d416de` (api-ventago)

### Code Auto-fixes

**1. [Rule 1 — Bug fix] cURL HEALTH 응답 코드 출력 버그 (`000000`)**
- **Found during:** Task 2 첫 실행
- **Issue:** `API_HEALTH=$(curl ... || echo "000")` 패턴이 set -uo pipefail 환경에서 `responded 000000` 출력 (`-w '%{http_code}'` 와 `|| echo 000` 가 모두 호출됨).
- **Fix:** `API_HEALTH="$(curl ... 2>/dev/null)"` + `[ -z ] || [ "000" ]` 가드. 또한 출력 메시지에 `/health` path 명시.
- **Files modified:** `api-ventago/test/phase35-uat.sh`
- **Committed in:** `3d416de` (api-ventago, 동일 commit)

**2. [Rule 1 — Bug fix] SalesResumenTable.tsx 경로 hard-code**
- **Found during:** Task 2 첫 실행 (FAIL 1)
- **Issue:** 스크립트가 `views/ventas/SalesResumenTable.tsx` 를 찾았으나, Plan 35-04 가 실제로는 `views/sales/list/components/` 에 생성.
- **Fix:** `find $REPO_ROOT/ventago-app/src -type f -name "SalesResumenTable.tsx" | head -1` 로 동적 검색. drift 발견 후 재실행 → PASS.
- **Files modified:** `api-ventago/test/phase35-uat.sh`
- **Committed in:** `3d416de` (api-ventago, 동일 commit)

### Architectural Deviations

None — plan 의 명세대로 정확히 진행됨.

---

**Total deviations:** 1 environment-only + 2 inline auto-fixes (Rule 1)
**Impact on plan:** 환경 차이 흡수 + 첫 실행 버그 즉시 fix. 최종 결과는 FAIL 0 / PASS 21.

## Issues Encountered

- api-ventago process 가 dev 환경에 미실행 → cURL smoke (U9/U9b/U10) 1건 SKIP. 사용자가 `npm run dev:api` 후 재실행 가능 (스크립트는 idempotent).
- 자동 검증 쉘 첫 실행에서 frontend component 경로 hard-code 발견 → find 검색으로 수정 후 PASS.
- Plan 09 Task 3 (Checkpoint) 는 본 plan 의 종료점. fresh agent 가 spawn 안 됨, 사용자 매뉴얼 UAT 사인오프 대기.

## Threat Flags

본 plan 은 verification artifact 만 생성 — 신규 surface 추가 없음. phase35-uat.sh 는 read-only DB query + code grep + optional cURL. **Threat flags 없음.**

## Self-Check: PASSED

**Files verified:**
- `.planning/phases/35-activity-ledger/35-UAT.md` — FOUND (565 lines, 22 U items + U9b/U12b)
- `api-ventago/test/phase35-uat.sh` — FOUND (292 lines, executable, bash -n PASS)

**Commits verified:**
- parent `7db894d` (Task 1, 35-UAT.md) — FOUND in `git log`
- api-ventago `3d416de` (Task 2, phase35-uat.sh) — FOUND in api-ventago `git log`

**Script verification:**
- `chmod +x` applied (executable bit set)
- `bash -n` PASS (no syntax errors)
- actual run: PASS=21, FAIL=0, SKIP=1, exit code 0
- 21 자동 검증 항목 모두 PASS (U1/U4/U5/U9/U9b/U12/U12b/U20 + frontend infra)

**Acceptance criteria (Task 1):**
- 22 `### U1:` ~ `### U22:` headers — VERIFIED via grep loop
- "Phase 35-A 검증" + "Phase 35-B 검증" + "Backfill 검증" 3 sections — VERIFIED
- DEFERRED + U9b + U12b keywords — VERIFIED (13 total matches)
- 종합 평가 sign-off section — VERIFIED
- Pre-conditions checklist — VERIFIED

**Acceptance criteria (Task 2):**
- File exists + executable — PASS
- `bash -n` exits 0 — PASS
- `check_pass|check_fail|check_skip` matches: 46 (>= 5) — PASS
- `stock.movement` matches: 8 (>= 2) — PASS
- `activity_type` matches: 15 (>= 2) — PASS
- U1/U4-U5/U9/U9b/U12b/U20 자동 검증 항목 커버 — PASS
- 매뉴얼 검증 안내 + U18 DEFERRED — PASS
- exit code 0 (FAIL=0) — PASS

---

## Status: awaiting_user_validation

**Plan 09 Task 3 (Checkpoint:human-verify) 의 사용자 사인오프 대기 중.**

다음 단계 (사용자):
1. `npm run dev:api` + `npm run dev:app` 실행
2. (선택) `API_JWT=<your token> ./api-ventago/test/phase35-uat.sh` 재실행하여 cURL smoke 보충
3. `.planning/phases/35-activity-ledger/35-UAT.md` 의 U1-U22 매뉴얼 절차 수행
4. 각 결과 칸에 [x] PASS / [x] FAIL 체크
5. U18 DEFERRED 결정 confirm (Phase 35-C 등록 or 영구 defer)
6. 종합 평가 3 그룹 모두 PASS 시 → "all PASS — Phase 35 complete (U18 deferred to phase XX)" 입력

이후 orchestrator 가 STATE.md / ROADMAP.md 업데이트 (Phase 35 status → COMPLETE).

---
*Phase: 35-activity-ledger*
*Plan: 09*
*Status: awaiting_user_validation*
*Completed: 2026-05-22*
