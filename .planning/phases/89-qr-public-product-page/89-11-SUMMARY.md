---
phase: 89-qr-public-product-page
plan: 11
subsystem: testing
tags: [jest, bash, postgres, tenant-isolation, deployment-gate, qr]

# Dependency graph
requires:
  - phase: 89-04
    provides: "GET /public/qr-stock/:storeId/:productId — 검증 대상 서비스(QrPublicService)"
  - phase: 89-01
    provides: "store_configs.qr_precio_publico · ventago_leads (로컬+운영 적용 완료)"
  - phase: 89-10
    provides: "prices (product_id, price_type_id) UNIQUE NULLS NOT DISTINCT (로컬+운영 적용 완료)"
provides:
  - "qr-public.service.spec.ts — 23개 단위 시험(분기·테넌트 bind/문자열·자격식·라벨식별·가격·응답필드), 대조군 4건 실제로 빨개짐을 확인"
  - "verificar-qr-public-tenant.sh — 실DB 3키 테넌트 격리 검사(대조군 + 표본부재 감지 exit 2)"
  - "verificar-esquema-phase89.sh — 8항목 스키마 배포 게이트, 기본 검사 대상이 앱의 .env DATABASE_* 접속 DB"
affects: [89-09]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "sequelize.query 를 가짜로 바꿔 SQL 문자열·bind 를 관찰(mock 경계는 DI 가 아니라 프로토타입 심기)"
    - "대조군은 소스를 임시로 훼손 → 시험이 실제로 빨개지는지 확인 → 원복(코드에 영구히 남기지 않음)"
    - "실DB 검사 스크립트는 서비스 SQL 을 복사하지 않고 조건을 독립적으로 재작성(공통원인실패 방지)"
    - "스키마 배포 게이트는 PGTARGET 을 사람이 고르게 두지 않고 .env DATABASE_* 를 기본 대상으로 읽는다"

key-files:
  created:
    - api-ventago/src/app/print/qr-public.service.spec.ts
    - api-ventago/scripts/verificar-qr-public-tenant.sh
    - api-ventago/scripts/verificar-esquema-phase89.sh
  modified: []

key-decisions:
  - "T6 최초 버전은 'p.store_id' 단순 포함 검사였는데, 같은 쿼리의 EXISTS 서브쿼리(b.store_id = p.store_id)에 같은 문자열이 우연히 섞여 있어 실제 테넌트 조건을 지워도 통과했다 — `= $2` 까지 묶는 정규식으로 강화해 대조군을 실제로 유효하게 만듦(Rule 1, 대조군 실증 도중 발견)"
  - "verificar-qr-public-tenant.sh 의 CROSS_SQL 을 count(*) FROM (...) 로 감쌀 때 내부 세미콜론이 남아 있어 psql 구문오류가 났는데, 그 오류가 빈 문자열 → ${VAR:-0} 로 조용히 '0행'으로 접혀 '위반 없음'을 거짓 보고할 뻔했다 — require_int() 가드를 추가해 숫자로 안 읽히는 결과는 즉시 exit 2 로 죽이게 함(Rule 1, 실행 중 실제로 발견)"
  - "verificar-esquema-phase89.sh 의 기본 PGTARGET 을 'prod'가 아니라 'app'(이 저장소 .env 의 DATABASE_* 접속 DB)으로 정함 — 오늘 실제로 벌어진 사고(마이그레이션은 로컬 5432, 앱은 스테이징 15432)를 그대로 반영한 orchestrator 지시를 그대로 따름"

requirements-completed: [REQ-02, REQ-03, REQ-07]

# Metrics
duration: 40min
completed: 2026-09-17
---

# Phase 89 Plan 11: 시험이 검증 대상을 실제로 실행하게 만든다 Summary

**QrPublicService 단위 시험 23건(대조군 4건 실증) + 실DB 3키 테넌트 격리 스크립트 + 앱의 실접속 DB(.env DATABASE_*)를 기본 대상으로 삼는 8항목 스키마 배포 게이트를 신설**

## Performance

- **Duration:** 약 40분
- **Started:** 2026-09-16 (파일 읽기 시작)
- **Completed:** 2026-09-17T02:32:30Z (마지막 Task 커밋)
- **Tasks:** 3/3 완료
- **Files modified:** 3 (전부 신규)

## Accomplishments
- `qr-public.service.spec.ts` — `sequelize.query` 를 가짜로 바꿔 SQL 문자열·bind 를 그대로 캡처하는 방식으로 23개 단위 시험 작성. 분기(closed/shop_redirect/detail) · 테넌트 bind/SQL 문자열 · 공개 자격식 · 라벨 식별(exact-label/latest-print/none) · 가격 판정(현재가·폴백·`precioEtiqueta`·센타보 경계) · 응답 필드(재고/SKU/원가/store_id 부재)까지 전부 커버
- 대조군 4건을 **실제로 소스를 훼손 → 시험이 빨개지는지 확인 → 원복**하는 방식으로 실증(아래 「대조군 실증」 참고). 이 과정에서 T6 시험 자체가 무력했던 것을 발견해 즉시 고쳤다
- `verificar-qr-public-tenant.sh` — 서비스의 SQL 을 복사하지 않고 조건을 독립적으로 재작성해 실 DB(로컬 5432·운영 5434)에서 3판(상품 테넌트·인쇄로그 3키·closed 분기 표본)을 검사. 대조군 행 수·표본 부재 감지가 실제로 살아 있음을 확인
- `verificar-esquema-phase89.sh` — 8항목 스키마 배포 게이트. ★ 기본 검사 대상을 사람이 `PGTARGET` 으로 고르게 두지 않고 **앱이 실제로 접속하는 DB**(`.env` 의 `DATABASE_*`, 코드가 `DB_*` 는 안 읽는다는 근거까지 포함)를 읽어 자동으로 정함 — 오늘 실제로 벌어진 "마이그레이션은 로컬에, 앱은 스테이징에" 사고를 다시 만들지 않기 위해서
- 세 스크립트/시험 모두 대조군이 실제로 작동함을 직접 확인(아래 원문 참고)

## Task Commits

각 Task 는 서브모듈(api-ventago) 커밋 → 슈퍼프로젝트 gitlink 포인터 커밋 순으로 원자적으로 커밋됨:

1. **Task 1: 서비스 단위 시험 23건 + 대조군 4건 실증** - `de7058ab` (api-ventago, test) + `a1448dc` (root, chore: submodule pointer)
2. **Task 2: 실DB 3키 테넌트 격리 검사 스크립트** - `40a048c8` (api-ventago, feat) + `d926795` (root, chore: submodule pointer)
3. **Task 3: 스키마 적용·선후 호환 검사 (배포 게이트)** - `d921ec3b` (api-ventago, feat) + `ba94bc8` (root, chore: submodule pointer)

**Plan metadata:** (이 커밋 — SUMMARY + STATE.md + ROADMAP.md)

## Files Created/Modified
- `api-ventago/src/app/print/qr-public.service.spec.ts` - 신규. `QrPublicService.getPublicProduct` 23개 단위 시험 — `Object.create(prototype)` + 가짜 `sequelize.query`(호출 순서대로 답 반환, SQL·bind 캡처). 서비스에서 상수를 import 하지 않고 기대값은 전부 리터럴
- `api-ventago/scripts/verificar-qr-public-tenant.sh` - 신규. `PGTARGET=local|prod`(기본 prod). 판1(상품 store_id 방어+대조군) · 판2(인쇄로그 3키 교차 카운트+전체행수 대조군) · 판3(closed 분기 표본 존재, 경고 전용). `require_int()` 로 SQL 오류를 "0행 통과"로 착각하지 않게 즉시 죽임
- `api-ventago/scripts/verificar-esquema-phase89.sh` - 신규. `PGTARGET=app(기본)|local|prod`. 8항목(컬럼·전매장 false 확인·테이블+시퀀스 owner·notified_at·UNIQUE 인덱스·INVALID 인덱스 부재·구버전 호환·중복 재확인)을 판정해 "배포 가능: 예/아니오" 출력

## Decisions Made
- **T6 대조군 강화(Rule 1)**: `qr-public.service.spec.ts` 최초 버전에서 T6(「상품 조회 SQL 에 p.store_id 조건이 있다」)를 단순 `toContain('p.store_id')` 로 작성했는데, 대조군 실증(WHERE 절의 `AND p.store_id = $2` 를 제거) 시 실제로는 **같은 쿼리 안 EXISTS 서브쿼리의 `b.store_id = p.store_id`** 에 동일 문자열이 남아 있어 시험이 계속 통과했다. `p\.store_id\s*=\s*\$2` 정규식으로 바꿔 실제 WHERE 절의 조건만 특정하도록 고쳤고, 재실증으로 이번엔 정말 빨개지는 것을 확인했다.
- **require_int() 가드 추가(Rule 1)**: `verificar-qr-public-tenant.sh` 작성 중 `CROSS_SQL` 을 `count(*) FROM (...)` 으로 감싸면서 내부 세미콜론이 중복돼 psql 구문 오류가 났는데, 그 오류 출력(빈 문자열)이 `${VAR:-0}` 에 가려 조용히 "교차 테넌트 행 0건 — 위반 없음"으로 보고될 뻔했다. 모든 숫자 판정 지점에 `require_int()` 를 넣어 정수로 안 읽히는 결과는 즉시 exit 2 로 죽이게 했다.
- **verificar-esquema-phase89.sh 기본 대상 = 앱 실접속 DB(orchestrator 지시)**: 오늘 실제로 "마이그레이션은 로컬 5432 ventago 에 적용, 앱은 `.env` 의 `DATABASE_HOST=127.0.0.1 DATABASE_PORT=15432 DATABASE_NAME=ventago_staging`(SSH 터널 → 운영 5434 별도 DB)을 보고 있었다"는 어긋남이 있었고, 아무 장치도 이를 알리지 않았다. 그래서 기본 `PGTARGET` 을 `local`/`prod` 중 하나로 두지 않고 `.env` 의 `DATABASE_*` 를 직접 읽는 `app` 을 기본값으로 정했다. `DB_*` 블록도 `.env` 에 있지만 `src/config/env.config.ts:25-27` 이 `DATABASE_*` 만 읽으므로 그것만 대상으로 삼았다.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - 검사 무력화] T6 대조군이 실제로는 아무것도 검증하지 않고 있었다**
- **Found during:** Task 1, 「대조군 실증」 절차 중 (`AND p.store_id = $2` 를 실제로 제거하고 재실행)
- **Issue:** T6 의 `expect(calls[1].sql).toContain('p.store_id')` 는 상품 조회 SQL 안의 EXISTS 서브쿼리(`b.store_id = p.store_id`)에도 매칭돼, WHERE 절의 실제 테넌트 조건을 지워도 시험이 계속 통과했다.
- **Fix:** `expect(calls[1].sql).toMatch(/p\.store_id\s*=\s*\$2/)` 로 바꿔 WHERE 절의 그 조건 자체를 특정
- **Files modified:** `api-ventago/src/app/print/qr-public.service.spec.ts`
- **Verification:** 조건 제거 → 실패 확인(`Expected substring: "pt.store_id"` 형태 메시지가 아니라 정규식 불일치로 실패) → 원복 → 23/23 재통과
- **Committed in:** `de7058ab` (Task 1 커밋 — 최종본에 이미 반영)

**2. [Rule 1 - 검사 무력화] CROSS_SQL 세미콜론 중복이 SQL 오류를 "0행"으로 위장시킴**
- **Found during:** Task 2, 로컬 최초 실행 중(작성 직후 `PGTARGET=local` 로 돌려봄)
- **Issue:** `CROSS_SQL` 문자열 끝에 세미콜론을 남긴 채 `SELECT count(*) FROM ($CROSS_SQL) x;` 로 감싸 psql 구문 오류가 났는데, 그 출력이 빈 문자열이 되어 `${CROSS_COUNT:-0}` 가 그것을 "0" 으로 접어 "교차 테넌트 행 0건, 위반 없음"으로 조용히 통과했다.
- **Fix:** `CROSS_SQL` 에서 세미콜론 제거 + 모든 숫자 판정에 `require_int()` 가드 추가(정수로 안 읽히면 exit 2)
- **Files modified:** `api-ventago/scripts/verificar-qr-public-tenant.sh`
- **Verification:** 원래 버그를 재현(세미콜론 재삽입) → `require_int` 가 exit 2 로 잡아내는 것 확인 → 원복 → `PGTARGET=local`/`prod` 재실행 정상(exit 0)
- **Committed in:** `40a048c8` (Task 2 커밋 — 최종본은 이미 수정된 상태)

**3. [Rule 1 - acceptance 불일치] Task 3 의 「8개 항목」 요구와 최초 9개 check() 호출이 어긋남**
- **Found during:** Task 3, acceptance 검증 중
- **Issue:** ventago_leads 의 테이블 owner 와 시퀀스 owner 를 별도 check() 두 번으로 작성해 총 9개 항목이 됐는데, plan 의 acceptance 는 "8개 항목을 각각 한 줄씩 출력한다"를 요구했다.
- **Fix:** 두 owner 확인을 `tableowner || '|' || sequenceowner` 한 줄 SQL로 합쳐 8개 항목으로 정리(검사 내용은 동일 — 여전히 둘 다 확인)
- **Files modified:** `api-ventago/scripts/verificar-esquema-phase89.sh`
- **Verification:** 재실행 결과 "항목 8개 통과 / 0개 미달" 확인(app/local/prod 전부)
- **Committed in:** `d921ec3b` (Task 3 커밋 — 최종본에 이미 반영)

---

**Total deviations:** 3 auto-fixed (전부 Rule 1 — 검사 자체의 결함을 실행 중 발견해 즉시 고침)
**Impact on plan:** 세 건 모두 "시험/검사가 실제로 검증 대상을 실행하는가"라는 이 plan의 목적 그 자체에 해당하는 수정이다. 스코프 확장 없음.

## 대조군 실증 (Task 1 — 소스를 임시로 훼손 → 실패 확인 → 원복)

1. **상품 조회에서 `AND p.store_id = $2` 제거** (`sed`로 `AND 1=1` 치환) → 최초에는 T6 가 통과해 무력함을 발견(위 Deviation 1) → T6 를 강화한 뒤 재실증: `npx jest -t T6` 결과 `p\.store_id\s*=\s*\$2` 매칭 실패로 **빨개짐** 확인 → `cp` 로 원복 → `diff` 로 원본과 동일함 확인
2. **로그 조회에서 `AND pt.store_id = $2` 제거** (`AND 1=1` 치환) → `npx jest -t T8` 결과:
   ```
   Expected substring: "pt.store_id"
   Received string: "...AND 1=1..."
   Tests: 1 failed
   ```
   → 원복 → `diff` 로 동일함 확인
3. **`precioEtiqueta` 를 `Number(logRow.printed_price)` 로 고정(항상 병기)** → `npx jest -t T17` 결과:
   ```
   expect(received).toBeNull()
   Received: 1000
   Tests: 1 failed
   ```
   → 원복 → `diff` 로 동일함 확인
4. **`closed` 분기의 조기 반환 제거**(`if (!store.qr_on && !hasSlug)` → `if (false && ...)`) → `npx jest -t "T3:"` 결과:
   ```
   NotFoundException: No encontrado
     at QrPublicService.getPublicProduct (qr-public.service.ts:129:13)
   Tests: 1 failed
   ```
   (상품 조회로 흘러 들어가 mock 답이 소진돼 `NotFoundException` 이 던져짐 — 조기 반환이 사라졌다는 증거) → 원복 → `diff` 로 동일함 확인

4건 모두 원복 후 `git diff --stat src/app/print/qr-public.service.ts` 무변경, `npx jest src/app/print --maxWorkers=1` 8 suites/90 tests 전부 재통과 확인.

## 실DB 검사 원문

### `verificar-qr-public-tenant.sh` — `PGTARGET=local`
```
공개 QR 조회 — 테넌트 격리 감사 (로컬 PG18 (5432))

── 판 1: 상품 테넌트 (products.store_id) ──
표본: product_id=1, owner_store=3, other_store=6
방어 있는 조회(p.id=1 AND p.store_id=6) → 행 0개 (0이어야 함)
대조군(store_id 조건 제거, p.id=1 만) → 행 1개 (1 이상이어야 함 — 0이면 이 검사가 아무것도 안 한 것)

── 판 2: 인쇄 로그 3키 (products·branches·price_types 의 store_id) ──
qr_print_log 전체 행 수: 4
교차 테넌트 행(branch 기준 또는 price_type 기준) 개수: 0 (0이어야 함)

── 판 3: closed 매장 구조 확인 (qr_precio_publico=false AND slug 없음) ──
closed 분기에 해당하는 매장 수: 342

✓ 테넌트 격리 위반 없음, 대조군·표본 확인 통과.
```
(exit 0)

### `verificar-qr-public-tenant.sh` — `PGTARGET=prod` (읽기 전용 SELECT 뿐)
```
공개 QR 조회 — 테넌트 격리 감사 (운영 srv803182 (5434))

── 판 1: 상품 테넌트 (products.store_id) ──
표본: product_id=1, owner_store=3, other_store=6
방어 있는 조회(p.id=1 AND p.store_id=6) → 행 0개 (0이어야 함)
대조군(store_id 조건 제거, p.id=1 만) → 행 1개 (1 이상이어야 함 — 0이면 이 검사가 아무것도 안 한 것)

── 판 2: 인쇄 로그 3키 (products·branches·price_types 의 store_id) ──
qr_print_log 전체 행 수: 5
교차 테넌트 행(branch 기준 또는 price_type 기준) 개수: 0 (0이어야 함)

── 판 3: closed 매장 구조 확인 (qr_precio_publico=false AND slug 없음) ──
closed 분기에 해당하는 매장 수: 12

✓ 테넌트 격리 위반 없음, 대조군·표본 확인 통과.
```
(exit 0 — 운영 실측 기준선 qr_print_log 5행 · 14 매장 중 12개 closed 자격과 정확히 일치)

### `verificar-esquema-phase89.sh` — 기본(app, `.env` DATABASE_*)
```
Phase 89 스키마 배포 게이트 — 앱이 보는 DB (.env DATABASE_*) — host=127.0.0.1 port=15432 db=ventago_staging

[OK]    store_configs.qr_precio_publico 존재·boolean·NOT NULL·default=false (boolean|NO|false)
[OK]    store_configs 전 매장 qr_precio_publico=false 인 채 배포됨(공개 즉시전환 없음) (0)
[OK]    ventago_leads 테이블+시퀀스 owner=coolsistema (ALTER TABLE OWNER 는 시퀀스를 안 옮긴다) (coolsistema|coolsistema)
[OK]    ventago_leads.notified_at 컬럼 존재 (1)
[OK]    uq_prices_product_price_type 존재·UNIQUE·NULLS NOT DISTINCT (t)
[OK]    INVALID 인덱스 없음(pg_index.indisvalid 전부 true)
[OK]    store_configs.qr_precio_publico 기본값 존재(구버전 INSERT 도 안전, 실제 쓰기 없이 판정) (t)
[OK]    prices (product_id,price_type_id) 중복 0 (인덱스로 구조적 보장, 재확인) (0)

항목 8개 통과 / 0개 미달
배포 가능: 예
```
(exit 0 — `PGTARGET=local`·`PGTARGET=prod` 도 동일하게 8/8 통과, exit 0 확인)

### `verificar-esquema-phase89.sh` 대조군 (존재하지 않는 컬럼명으로 임시 치환)
```
[FALTA] store_configs.qr_precio_publico 존재·boolean·NOT NULL·default=false — 기대: 'boolean|NO|false' / 실제: ''
...
[FALTA] store_configs.qr_precio_publico 기본값 존재(구버전 INSERT 도 안전, 실제 쓰기 없이 판정) — 기대: 't' / 실제: ''
항목 6개 통과 / 2개 미달
배포 가능: 아니오
```
(exit 1 — 컬럼명을 원복한 뒤 `diff` 로 원본과 동일함 확인, 실제 DB 는 전혀 건드리지 않음)

## Issues Encountered
None — 세 Task 모두 최종적으로 acceptance criteria 충족(위 세 건은 검사 스크립트/시험 자체의 결함을 실행 중 발견해 즉시 고친 것으로, 「시험이 검증 대상을 실제로 실행하는가」라는 이 plan의 핵심 목적에 해당).

## User Setup Required
None - 외부 서비스 설정 불필요. 세 파일 모두 이 저장소 안에서 자족적으로 동작한다.

## Next Phase Readiness
- 89-09(배포 게이트)가 `verificar-esquema-phase89.sh` 를 그대로 호출해 배포 가능 여부를 판정할 수 있다.
- `verificar-qr-public-tenant.sh` 는 CI/사람이 언제든 `PGTARGET=local|prod` 로 재실행해 테넌트 격리를 재확인할 수 있다(서비스 SQL 을 복사하지 않으므로 서비스가 바뀌어도 독립적으로 유효).
- ★ `verificar-esquema-phase89.sh` 의 기본 대상(app, `.env` DATABASE_*)은 **이 저장소의 현재 `.env` 설정에 의존**한다. `.env` 가 가리키는 DB(현재 `ventago_staging`)가 바뀌면 스크립트는 자동으로 새 대상을 따라가지만, 그 사실 자체(무엇을 보고 있는지)는 스크립트 출력 최상단에 항상 찍힌다.
- 블로커 없음.

---
*Phase: 89-qr-public-product-page*
*Completed: 2026-09-17*

## Self-Check: PASSED

- FOUND: api-ventago/src/app/print/qr-public.service.spec.ts
- FOUND: api-ventago/scripts/verificar-qr-public-tenant.sh
- FOUND: api-ventago/scripts/verificar-esquema-phase89.sh
- FOUND: .planning/phases/89-qr-public-product-page/89-11-SUMMARY.md
- FOUND commit de7058ab (api-ventago submodule)
- FOUND commit 40a048c8 (api-ventago submodule)
- FOUND commit d921ec3b (api-ventago submodule)
- FOUND commit a1448dc (root)
- FOUND commit d926795 (root)
- FOUND commit ba94bc8 (root)
