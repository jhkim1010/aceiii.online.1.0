---
phase: 89-qr-public-product-page
plan: 04
subsystem: api
tags: [nestjs, sequelize, public-endpoint, tenant-isolation, qr]

# Dependency graph
requires:
  - phase: 89-01
    provides: "store_configs.qr_precio_publico BOOLEAN NOT NULL DEFAULT false (로컬 5432 + 운영 5434 적용 완료)"
  - phase: 89-10
    provides: "prices (product_id, price_type_id) UNIQUE NULLS NOT DISTINCT — 현재 가격이 한 값으로 확정"
provides:
  - "GET /public/qr-stock/:storeId/:productId?b=&pt= — 인증 없는 공개 상품 조회 API (3갈래: detail/shop_redirect/closed)"
  - "PUBLIC_QR_THROTTLE · PUBLIC_LEAD_THROTTLE · PUBLIC_RESELLER_REGISTER_THROTTLE 상수 (89-05·89-08 이 재사용)"
  - "QrPublicDto 응답 계약 (precioEtiqueta·labelMatch·priceSource·storeApodo)"
affects: [89-06, 89-07, 89-11]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "@Public() 라우트에서 storeId 를 SQL WHERE 로 직접 강제 (전역 테넌트 가드가 no-op 인 자리)"
    - "qr_print_log 조회는 products·branches·price_types 3키 전부로 store_id 를 강제 (로그 테이블 자체엔 store_id 컬럼이 없다)"
    - "priceSource 를 labelMatch 에서 한 줄로 파생 — 불변식을 두 곳에서 각자 정하지 않는다"

key-files:
  created:
    - api-ventago/src/app/print/qr-public.dto.ts
    - api-ventago/src/app/print/qr-public.service.ts
    - api-ventago/src/app/print/qr-public.controller.ts
  modified:
    - api-ventago/src/common/throttle/throttle.constants.ts
    - api-ventago/src/app/print/print.module.ts

key-decisions:
  - "plan 의 <action> 지시 주석 리터럴('is_published_shop', '...row')이 같은 Task 의 acceptance_criteria(해당 문자열 grep 0)와 충돌해, 의미는 그대로 두고 표현만 바꿔 해소(89-01 과 같은 형태의 plan 자체 모순)"
  - "b·pt 쿼리 파라미터에 ParseIntPipe 를 걸지 않음 — 구 라벨(b·pt 없이 s·p 만 인쇄된 라벨)이 400 을 받아 죽는 것을 막기 위해 쓰레기 값도 400 대신 null 로 떨어뜨린다"

requirements-completed: [REQ-02, REQ-03, REQ-07]

# Metrics
duration: 45min
completed: 2026-09-16
---

# Phase 89 Plan 04: QR 공개 상품 조회 API Summary

**`GET /public/qr-stock/:storeId/:productId?b=&pt=` 신설 — 인증 없이 매장·지점·사진·가격을 3갈래(상세/공개몰 리다이렉트/닫힘)로 반환하고, 인쇄 로그 조회는 products·branches·price_types 3키 전부로 테넌트를 강제한다**

## Performance

- **Duration:** 약 45분
- **Started:** 2026-09-16
- **Completed:** 2026-09-16
- **Tasks:** 3/3 완료
- **Files modified:** 5 (신규 3 · 수정 2)

## Accomplishments
- 지금까지 인쇄된 라벨이 가리키는 `https://app.coolsistema.com/m/stock?s=6&p=1`(현재 308→404)의 실제 도착지가 될 백엔드 API 완성
- 매장 판정 3갈래(켜짐→detail, 꺼짐+공개몰켜짐→shop_redirect, 꺼짐+공개몰꺼짐→closed)를 SQL 한 번으로 확정하고, `closed` 는 상품 조회를 시작조차 하지 않음(상품 존재 여부 자체를 누출하지 않음)
- 공개 자격식: `products.store_id` 강제 + (공개몰 ON 이거나 그 상품에 인쇄기록이 있음) — `is_published_shop` 류 게시 플래그를 요구하지 않아 공개몰 미활성 매장에서도 "찍은 그 상품"은 열림(사용자 결정 ③)
- 인쇄 로그 조회는 `qr_print_log`(store_id 컬럼 없음)를 `products`·`branches`·`price_types` 3키 전부로 조인해 테넌트를 강제 — 과거 실제로 교차 테넌트 오염이 있었던 자리(`2026-08-22-w6-limpiar-filas-cruzadas.sql`)라 0건이어도 `logger.warn` 으로 드러내는 코드를 추가
- 가격 표시는 결정 ①(2026-09-16 개정) 그대로: 주 표시는 "그 가격유형의 현재 가격", `printed_price` 와 다를 때만 `precioEtiqueta` 를 병기(같으면 `null`) — 비교는 `mismoMonto()`(센타보 단위)로, 부동소수 직접 비교 금지
- `labelMatch`(exact-label/latest-print/none) 필드로 "구 라벨은 가장 최근 인쇄분 추정일 뿐 스캔한 그 라벨이라는 보장이 없다"는 한계를 응답 자체에 드러냄. `priceSource` 는 `labelMatch` 에서 파생시켜 두 필드가 갈라지지 않게 함
- `@Query('b')`·`@Query('pt')` 는 `ParseIntPipe` 를 걸지 않아 이미 인쇄된 구 라벨(파라미터 없음)이 400 을 받지 않음

## Task Commits

각 Task 는 서브모듈(api-ventago) 커밋 → 슈퍼프로젝트 gitlink 포인터 커밋 순으로 원자적으로 커밋됨:

1. **Task 1: throttle 상수 2개 + 공개 응답 DTO** - `2d2d1a95` (api-ventago, feat) + `6fc98ae` (root, chore: submodule pointer)
2. **Task 2: 서비스 — 공개 자격식·3갈래·3키 테넌트 강제·가격 판정** - `bf3be4a5` (api-ventago, feat) + `64601e4` (root, chore: submodule pointer)
3. **Task 3: 공개 컨트롤러 + 모듈 등록** - `60594026` (api-ventago, feat) + `0d4bff2` (root, chore: submodule pointer)

**Plan metadata:** (이 커밋 — SUMMARY + STATE.md + ROADMAP.md)

## Files Created/Modified
- `api-ventago/src/common/throttle/throttle.constants.ts` - `PUBLIC_QR_THROTTLE`(분당 60) · `PUBLIC_LEAD_THROTTLE`(분당 5) · `PUBLIC_RESELLER_REGISTER_THROTTLE`(분당 3) 세 상수 추가 — 89-05·89-08 이 import 만 하도록 이 plan 이 한 번에 정의
- `api-ventago/src/app/print/qr-public.dto.ts` - 신규. `QrPublicDto`/`QrPublicProductDto` — 재고·원가·공급처·SKU 필드 없음, `precioEtiqueta`/`labelMatch`/`priceSource`/`storeApodo` 포함
- `api-ventago/src/app/print/qr-public.service.ts` - 신규. `getPublicProduct()` — 매장 3갈래 → 상품 자격식 → 지점 이름(선택) → 인쇄 로그 3키 조인 → 가격 판정 → 이미지 폴백. `@InjectConnection()` 원시쿼리, row 스프레드 금지
- `api-ventago/src/app/print/qr-public.controller.ts` - 신규. `GET public/qr-stock/:storeId/:productId?b=&pt=` — `@Public()`+`@Throttle(PUBLIC_QR_THROTTLE)`, b·pt 는 `toPositiveIntOrNull()` 로 유연 파싱
- `api-ventago/src/app/print/print.module.ts` - `controllers`/`providers` 배열에 `QrPublicController`/`QrPublicService` 등록. `SequelizeModule.forFeature`는 무변경(메인 연결 사용)

## Decisions Made
- **plan 내부 모순 해소(Rule 1)**: Task 2 의 `<action>` 이 지시한 정확한 주석 문구에 `is_published_shop`·`...row` 리터럴이 포함돼 있었으나, 같은 Task 의 `<acceptance_criteria>`는 그 문자열이 파일에 **없어야** 한다고 요구했다(89-01 의 Task 1 과 동일한 형태의 plan 자체 모순). SQL·필드·로직은 전혀 바꾸지 않고 주석 표현만 바꿔(`is_published_shop` → "공개몰 목록 게시 여부(shop-catalog 가 쓰는 그 플래그)", `...row` → "row 객체를 그대로 펼치는 표기") 의미를 유지하면서 두 요구를 동시에 만족시켰다.
- **b·pt 를 `ParseIntPipe` 로 강제하지 않음**: plan 지시대로, 구 라벨(파라미터 자체가 없음)이 400 을 받지 않도록 문자열 파싱 헬퍼(`toPositiveIntOrNull`)로 처리 — 하위호환이 이 phase 의 첫 가치라는 판단을 그대로 따름.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - plan 내부 모순] Task 2 주석 리터럴이 acceptance_criteria 와 충돌**
- **Found during:** Task 2 acceptance 검증(grep 체크 실행 중)
- **Issue:** `<action>` 이 지시한 SQL 자격식 주석 원문에 `is_published_shop` 문자열과 `...row` 표기가 그대로 들어 있었는데, 같은 Task 의 `<acceptance_criteria>`는 "그 문자열이 파일에 0건이어야 한다"를 요구해 지시된 원문 그대로 쓰면 acceptance 가 실패하는 모순이었다.
- **Fix:** SQL·필드명·로직은 그대로 두고, 두 군데 주석 표현만 리터럴 문자열을 피하는 동의어로 교체(의미 동일).
- **Files modified:** `api-ventago/src/app/print/qr-public.service.ts`
- **Verification:** `grep -c "is_published_shop"` → 0, `grep -cE "\.\.\.(row|rows\[0\])"` → 0, 그 외 acceptance 항목 전부 통과, `npx tsc --noEmit` 0, `npx jest src/app/print --maxWorkers=1` 7/7 suites 통과
- **Committed in:** `bf3be4a5` (Task 2 커밋)

**2. [Rule 1 - lint] eslint prettier 포맷 오류 2건**
- **Found during:** Task 2·3 커밋 게이트(pre-commit hook)
- **Issue:** 삼항 연산자 줄바꿈, 배열 리터럴 줄바꿈이 prettier 규칙과 불일치해 커밋이 차단됨
- **Fix:** `npx eslint --fix` 로 해당 파일만 포맷 교정(다른 파일 무영향)
- **Files modified:** `api-ventago/src/app/print/qr-public.service.ts`, `api-ventago/src/app/print/print.module.ts`
- **Verification:** `npx eslint` 재실행 0 errors, `npx tsc --noEmit` 0, acceptance grep 재확인 전부 통과

---

**Total deviations:** 2 auto-fixed (Rule 1 — plan 내부 모순 1건, lint 포맷 1건)
**Impact on plan:** SQL·응답 계약·테넌트 격리 로직은 plan 지시 그대로. 사람이 읽는 주석 표현·코드 포맷만 조정. 스코프 확장 없음.

## Issues Encountered
None — 3개 Task 모두 acceptance criteria 를 최종적으로 충족(위 두 자잘한 lint/문구 조정 외에는 첫 시도에 통과).

## User Setup Required
None - 외부 서비스 설정 불필요. `THROTTLE_PUBLIC_QR_LIMIT` 등 env 는 선택적 튜닝용으로 기본값이 이미 동작한다.

## ★ 이 API 가 해결하지 못하는 것 (plan 이 명시한 한계 — 해결했다고 쓰지 않음)

**한계 1 — 구 라벨에서는 어느 라벨을 스캔했는지 서버가 알 수 없다.**
`qr_print_log` 의 유니크 키는 `(branch_id, product_id, price_type_id)` 3개인데 현재 인쇄된 URL(`?s=&p=`)은 2개만 싣는다. 구 라벨은 `printed_at DESC LIMIT 1` 로 "가장 최근 인쇄분"을 고를 수밖에 없고, 그것이 스캔한 그 라벨이라는 보장은 없다. 응답의 `labelMatch: 'latest-print'` 가 이 사실을 드러낸다. 89-07 이 `&b=`·`&pt=` 를 실어 신 라벨에서만 이 모호성을 없앤다.

**한계 2 — 숫자 ID 열거를 막지 못한다.**
`?s=6&p=1` 은 연번이고, 서버는 요청자가 실물 라벨을 들었는지 구분할 수단이 없다. `@Throttle` 은 속도를 늦출 뿐이다. 공개몰을 안 켠 매장(`stores.slug IS NULL`)에서는 인쇄 기록이 있는 상품만 상세를 내보내 부분 완화만 한다 — 인쇄된 라벨의 연번 열거 자체는 여전히 못 막는다. 불투명 토큰은 이 phase 범위 밖.

## Next Phase Readiness
- 89-06(프론트 공개 페이지)이 이제 이 API 를 raw `fetch()` 로 호출할 수 있다.
- 89-05(리드 폼)·89-08(reseller 폼)이 이 plan 이 정의한 `PUBLIC_LEAD_THROTTLE`/`PUBLIC_RESELLER_REGISTER_THROTTLE` 을 import 만 하면 된다(같은 파일 같은 wave 충돌 방지).
- 89-07 이 `&b=`·`&pt=` 를 실은 신 라벨 인쇄 흐름을 완성하면 `labelMatch: 'exact-label'` 비중이 늘어난다.
- 89-11(시험)이 `qr-public.controller.spec.ts` 등을 작성해 이 서비스의 테넌트 격리·3갈래·가격 판정을 자동 검증할 예정 — 이 plan 은 기존 print 시험(7 suites/62 tests)이 깨지지 않는 것까지만 확인했다.
- 블로커 없음.

---
*Phase: 89-qr-public-product-page*
*Completed: 2026-09-16*

## Self-Check: PASSED

- FOUND: api-ventago/src/app/print/qr-public.dto.ts
- FOUND: api-ventago/src/app/print/qr-public.service.ts
- FOUND: api-ventago/src/app/print/qr-public.controller.ts
- FOUND: api-ventago/src/common/throttle/throttle.constants.ts
- FOUND: api-ventago/src/app/print/print.module.ts
- FOUND: .planning/phases/89-qr-public-product-page/89-04-SUMMARY.md
- FOUND commit 2d2d1a95 (api-ventago submodule)
- FOUND commit bf3be4a5 (api-ventago submodule)
- FOUND commit 60594026 (api-ventago submodule)
- FOUND commit 6fc98ae (root)
- FOUND commit 64601e4 (root)
- FOUND commit 0d4bff2 (root)
