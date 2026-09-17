---
phase: 89-qr-public-product-page
plan: 10
subsystem: database
tags: [postgres, sequelize, migrations, prices, upsert, concurrency]

# Dependency graph
requires:
  - phase: 89-01
    provides: "무중단 마이그레이션 규약 골격(lock_timeout, owner DO 블록) — 이 plan 은 CONCURRENTLY 인덱스라 규약 하위집합만 해당"
provides:
  - "prices (product_id, price_type_id) 에 UNIQUE 인덱스(NULLS NOT DISTINCT) — 로컬 5432 + 운영 5434 적용 완료"
  - "upsertPrices 가 ON CONFLICT (product_id, price_type_id) 한 번의 쓰기로 동작"
affects: [89-04, 89-05]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "sequelize bulkCreate({ conflictAttributes }) → upsertKeys → dialect 의 ON CONFLICT(cols) 로 변환됨을 소스(node_modules/sequelize/lib/model.js:1678, .../query-generator.js)로 직접 확인 후 채택 — 원시 SQL 불필요"

key-files:
  created:
    - api-ventago/migrations/2026-09-16-phase89-prices-unique.sql
    - api-ventago/src/app/products/prices-unique.spec.ts
  modified:
    - api-ventago/src/app/products/productsPrice.service.ts

key-decisions:
  - "sequelize 6.37.8 이 conflictAttributes 옵션을 지원함을 node_modules 소스로 직접 확인(model.js:1678-1679) — 원시 SQL(this.sequelize.query) 대안은 채택하지 않음"
  - "TDD RED 커밋을 별도로 만들지 않음 — 이 저장소의 pre-commit 훅(verify-before-commit.sh)이 대상 모듈 jest 실패 시 커밋을 막는다(CLAUDE.md '검증은 자동으로 돈다' 규약). RED 는 로컬에서 4건 실패로 수동 확인만 하고, GREEN 구현과 함께 단일 feat 커밋으로 묶었다(SKIP_VERIFY 미사용, 사용자 승인 없이 훅을 우회하지 않음)"
  - "운영 DDL 적용 승인(apply) — 사용자 확정, 사전 조회(dup=0, nulos=0)가 plan 의 실측과 정확히 일치해 정리 작업 없이 그대로 진행"

patterns-established: []

requirements-completed: [REQ-07]

# Metrics
duration: 15min (체크포인트 승인 대기 시간 제외)
completed: 2026-09-17
---

# Phase 89 Plan 10: prices UNIQUE + ON CONFLICT 업서트 Summary

**`prices (product_id, price_type_id)` 에 `NULLS NOT DISTINCT` UNIQUE 인덱스를 로컬·운영 양쪽에 적용하고, `upsertPrices` 를 `ON CONFLICT` 단일 쓰기로 전환해 "현재 가격"이 한 값으로 확정되게 함**

## Performance

- **Duration:** 약 15분 (Task 3 checkpoint 승인 대기 시간 제외)
- **Started:** 2026-09-17T00:28:41Z (Task 1 커밋 기준)
- **Completed:** 2026-09-17T00:45:00Z (근사)
- **Tasks:** 3/3 완료 (Task 3 은 checkpoint:decision — 사용자 `apply` 승인 후 재개해 완료)
- **Files modified:** 3 (마이그레이션 1 신규, 서비스 1 수정, spec 1 신규)

## Accomplishments
- `uq_prices_product_price_type` UNIQUE 인덱스(NULLS NOT DISTINCT) — 로컬(5432)·운영(5434) 양쪽 유효(valid) 적용 확인
- `upsertPrices` 가 「조회 1회 + 쓰기 2회」 구조에서 **ON CONFLICT 쓰기 1회**로 축소됨 — 경합 시 조용한 중복 행이 원천 차단됨
- 낡은 주석("UNIQUE 제약이 없어 conflict target 이 될 수 없다")을 교정 — 이제 코드와 문서가 갈라지지 않음
- 배포 순서(인덱스 먼저 → 코드 나중)가 실제로 지켜짐: Task 1(마이그레이션 파일) → Task 2(코드) 순으로 커밋했고, Task 3(운영 인덱스 적용)이 이 SUMMARY 작성 시점에 이미 완료돼 있어 Task 2 코드가 배포돼도 안전한 상태
- `prices-unique.spec.ts` 4건 — call-argument 단언 방식으로 conflict target · 갱신 컬럼 · 배치 내 dedup · transaction 전달을 검증, 대조군(transaction 제거) 실증까지 완료

## Task Commits

Each task was committed atomically (서브모듈 `api-ventago` 커밋 → 슈퍼프로젝트 gitlink 포인터 커밋 순):

1. **Task 1: prices UNIQUE 인덱스 마이그레이션 (CONCURRENTLY · NULLS NOT DISTINCT)** - `fb245035` (api-ventago, feat) + `5e863ea` (root, chore: submodule pointer)
2. **Task 2: upsertPrices 를 ON CONFLICT 로 + 낡은 주석 교정** - `c834bddc` (api-ventago, feat — 아래 「TDD Gate Compliance」참고) + `9f657ab` (root, chore: submodule pointer)
3. **Task 3: 로컬 5432 → 운영 5434 인덱스 적용** - DB 변경 (소스 파일 커밋 없음). 사용자 승인(`apply`) 후 운영 5434 에 마이그레이션 실행, 아래 「적용 확인」 참고.

**Plan metadata:** (이 커밋 — SUMMARY + STATE.md + ROADMAP.md)

## Files Created/Modified
- `api-ventago/migrations/2026-09-16-phase89-prices-unique.sql` - `CREATE UNIQUE INDEX CONCURRENTLY ... NULLS NOT DISTINCT` (BEGIN/COMMIT 없음, INVALID 복구 절차 주석 포함)
- `api-ventago/src/app/products/productsPrice.service.ts` - `upsertPrices` 를 `bulkCreate({ conflictAttributes: ['productId','priceTypeId'], updateOnDuplicate: ['amount','updatedAt'] })` 단일 호출로 교체 + 주석 교정
- `api-ventago/src/app/products/prices-unique.spec.ts` - 신규 spec, 4 테스트

## TDD Gate Compliance

★ 이 plan 의 Task 2 는 `tdd="true"` 로 지정돼 RED → GREEN → (REFACTOR) 순서를 요구했다.
RED 단계는 **로컬에서 수동으로 실행해 4건 실패를 확인**했으나(아래 원문 참고), **별도의 `test(...)` 커밋을 만들지 않았다.**

이유: 이 저장소의 `.claude/hooks/verify-before-commit.sh` (CLAUDE.md § 「검증은 자동으로 돈다」)는 커밋 대상 모듈의 jest 가 실패하면 **커밋 자체를 막는다** — RED 단계의 정의(테스트가 실패해야 한다)와 이 훅의 전제(커밋되는 코드는 테스트를 통과해야 한다)가 정면으로 충돌한다. CLAUDE.md 의 검증 규약이 plan 의 커밋 세분화보다 우선한다는 executor 규칙(project_context § CLAUDE.md enforcement)에 따라, `SKIP_VERIFY=1` 로 훅을 우회하는 대신 **RED 확인은 로컬 실행으로만 하고, GREEN 구현과 하나의 `feat(89-10): ...` 커밋으로 묶었다.**

**RED 단계 실측(커밋되지 않음, 이 SUMMARY 로 대체 기록):**
```
$ npx jest src/app/products/prices-unique.spec.ts --maxWorkers=1
FAIL src/app/products/prices-unique.spec.ts
  ● Test 1~4 전부: TypeError: this.priceModel.findAll is not a function
Tests: 4 failed, 4 total
```
(당시 구현이 `priceModel.findAll` 을 호출하는데 spec 의 mock 에는 `bulkCreate` 만 있어 즉시 실패 — RED 조건 충족)

**GREEN 단계 실측(커밋 `c834bddc`):**
```
$ npx jest src/app/products/prices-unique.spec.ts --maxWorkers=1
PASS src/app/products/prices-unique.spec.ts
Tests: 4 passed, 4 total
```

**REFACTOR:** 별도 커밋 없음 — GREEN 구현이 이미 최종 형태(단일 `bulkCreate` 호출)라 추가 정리가 필요 없었다.

**대조군 실증(수동, 커밋되지 않은 임시 편집 → 원복):** `transaction` 을 옵션에서 잠시 제거하고 재실행:
```
$ npx jest src/app/products/prices-unique.spec.ts --maxWorkers=1
✕ Test 4 (대조군): 쓰기 호출에 transaction 이 반드시 넘어간다
  Expected: {"fakeTransaction": true}
  Received: undefined
Tests: 1 failed, 3 passed, 4 total
```
원복 후 4건 전부 재통과 확인(`c834bddc` 커밋 전).

## 적용 확인 (직접 조회 원문)

### 로컬 (5432) — Task 3 진행 중 직접 적용
```
$ psql -p 5432 -d ventago -v ON_ERROR_STOP=1 -f api-ventago/migrations/2026-09-16-phase89-prices-unique.sql
CREATE INDEX

$ psql -p 5432 -d ventago -tAc "SELECT indexdef FROM pg_indexes WHERE indexname='uq_prices_product_price_type';"
CREATE UNIQUE INDEX uq_prices_product_price_type ON public.prices USING btree (product_id, price_type_id) NULLS NOT DISTINCT

$ psql -p 5432 -d ventago -tAc "SELECT indexrelid::regclass FROM pg_index WHERE NOT indisvalid;"
(빈 결과)
```

### 운영 사전 확인 (5434, 읽기 전용 — 승인 전)
```
$ ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -tAc \"SELECT count(*) total, count(*)-count(DISTINCT (product_id,price_type_id)) dup, count(*) FILTER (WHERE product_id IS NULL OR price_type_id IS NULL) nulos FROM prices;\""
1607|0|0
```
→ `dup=0`, `nulos=0` — plan 에 적힌 2026-09-16 실측과 정확히 일치. 정리 작업 없이 인덱스 생성 가능함을 재확인.

### 운영 (5434) — 사용자 `apply` 승인 후 적용
```
$ ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -v ON_ERROR_STOP=1" < api-ventago/migrations/2026-09-16-phase89-prices-unique.sql
CREATE INDEX

$ ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -tAc \"SELECT indexdef FROM pg_indexes WHERE indexname='uq_prices_product_price_type';\""
CREATE UNIQUE INDEX uq_prices_product_price_type ON public.prices USING btree (product_id, price_type_id) NULLS NOT DISTINCT

$ ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -tAc \"SELECT indexrelid::regclass FROM pg_index WHERE NOT indisvalid;\""
(빈 결과)
```

★ 한 번에 성공 — INVALID 인덱스가 생기지 않아 `DROP INDEX CONCURRENTLY` 재시도 절차는 필요 없었다.

## Decisions Made
- **sequelize 버전과 구현 선택**: `sequelize@6.37.8`(`node -e "console.log(require('sequelize/package.json').version)"`). `bulkCreate` 옵션에 `conflictAttributes` 를 그대로 지원함을 `node_modules/sequelize/lib/model.js:1678-1679`(`options2.upsertKeys = options2.conflictAttributes.map(...)`)와 `dialects/abstract/query-generator.js`(`upsertKeys` → `ON CONFLICT (...)` 생성)에서 직접 확인해 채택. 원시 SQL(`this.sequelize.query`) 경로는 불필요.
- **운영 DDL 적용 승인**: 사용자가 checkpoint 에서 `apply` 선택. 사전 조회(`dup=0`, `nulos=0`)가 plan 의 실측과 일치해 정리 작업 없이 그대로 진행, 실제로 한 번에 유효한 인덱스가 생성됨.
- **TDD RED 커밋 생략**: 위 「TDD Gate Compliance」 참고. CLAUDE.md 의 커밋 전 검증 규약(실패하는 jest 는 커밋 차단)이 plan 의 RED 단독 커밋 요구보다 우선한다고 판단.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - 커밋 차단 해소] TDD RED 단독 커밋이 이 저장소의 pre-commit 훅과 충돌**
- **Found during:** Task 2 (RED 테스트 작성 직후 커밋 시도)
- **Issue:** plan 의 TDD 실행 흐름은 RED(실패하는 테스트)를 `test(...)` 커밋으로 먼저 남기라고 지시하지만, 이 저장소의 `verify-before-commit.sh` 훅은 대상 모듈의 jest 가 실패하면 커밋 자체를 차단한다(`api jest 실패` 로 즉시 거절).
- **Fix:** RED 확인은 로컬 실행(`npx jest ... --maxWorkers=1`, 4건 실패 원문을 SUMMARY 에 기록)으로 대체하고, GREEN 구현이 완료된 뒤 spec+구현을 하나의 `feat(89-10): ...` 커밋으로 묶었다. `SKIP_VERIFY=1` 은 사용하지 않았다(사용자 승인 없이 검증 우회 금지 원칙 유지).
- **Files modified:** `api-ventago/src/app/products/prices-unique.spec.ts`, `api-ventago/src/app/products/productsPrice.service.ts`
- **Verification:** RED 4건 실패 원문 + GREEN 4건 통과 원문 + 대조군(transaction 제거) 실패 원문 전부 이 SUMMARY 「TDD Gate Compliance」에 붙임
- **Committed in:** `c834bddc` (구현+테스트 단일 커밋)

**2. [Rule 1 - 사소한 eslint 정합] spec 파일의 `Object.create(...prototype)` + `any` mock 패턴이 api eslint(추가한 줄) 게이트에 걸림**
- **Found during:** Task 2 (첫 커밋 시도, `@typescript-eslint/no-unsafe-*` 25건)
- **Issue:** 새 spec 파일 전체가 "추가한 줄"이라 `no-unsafe-assignment`/`no-unsafe-member-access`/`no-unsafe-call` 이 즉시 게이트에 걸렸다. 이 저장소의 기존 spec(`sku-serial.service.spec.ts`, `madre-guard.spec.ts` 등)도 같은 패턴을 파일 상단 `/* eslint-disable ... */` 로 허용하고 있었다.
- **Fix:** 같은 패턴(파일 상단 `eslint-disable` 3개 규칙)을 적용해 0 errors 로 정리(불필요한 `no-unsafe-argument` 는 「사용되지 않은 지시어」 경고가 나와 제거).
- **Files modified:** `api-ventago/src/app/products/prices-unique.spec.ts`
- **Verification:** `npx eslint src/app/products/prices-unique.spec.ts` → 0 errors, 0 warnings
- **Committed in:** `c834bddc`

---

**Total deviations:** 2 (둘 다 이 저장소의 검증 규약과의 정합을 위한 조정. 기능·SQL·conflict target·transaction 전달 등 plan 이 요구한 실제 동작은 전혀 바뀌지 않았다)
**Impact on plan:** 없음 — acceptance criteria 전부 충족(아래 「Self-Check」참고).

## Issues Encountered
None - 로컬·운영 마이그레이션 모두 한 번에 성공(INVALID 인덱스 없음), jest/tsc 모두 최종 통과.

## User Setup Required
None - 외부 서비스 설정 불필요.

## Next Phase Readiness
- `uq_prices_product_price_type` 가 로컬·운영 양쪽에 유효하게 존재하므로, Task 2 의 `ON CONFLICT` 코드가 다음 배포에서 500 없이 동작한다(배포 순서: 인덱스 먼저 → 이미 완료, 코드는 이 plan 커밋에 포함돼 있으므로 이후 일반 배포 파이프라인을 따르면 됨).
- 89-04(가격 표시)·89-05 가 이제 「현재 가격」을 결정론적으로 읽을 수 있다 — 중복 행에 의한 임의성이 제거됨.
- ★ `idx_prices_product_price_type`(non-unique, 같은 두 컬럼) 은 **이 phase 에서 지우지 않았다.** 이제 같은 컬럼 조합에 인덱스가 2개(중복)다 — 쓰기 비용이 약간 늘 뿐 위협은 아니며, 별도 정리 plan 이 필요하면 그때 지운다.
- 블로커 없음.

---
*Phase: 89-qr-public-product-page*
*Completed: 2026-09-17*

## Self-Check: PASSED

- FOUND: api-ventago/migrations/2026-09-16-phase89-prices-unique.sql
- FOUND: api-ventago/src/app/products/prices-unique.spec.ts
- FOUND: .planning/phases/89-qr-public-product-page/89-10-SUMMARY.md
- FOUND commit fb245035 (api-ventago submodule)
- FOUND commit c834bddc (api-ventago submodule)
- FOUND commit 5e863ea (root)
- FOUND commit 9f657ab (root)
