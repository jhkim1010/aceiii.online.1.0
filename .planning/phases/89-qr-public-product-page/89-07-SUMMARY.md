---
phase: 89-qr-public-product-page
plan: 07
subsystem: api
tags: [nestjs, qr, print-agent, backward-compatibility]

# Dependency graph
requires:
  - phase: 89-04
    provides: "GET /public/qr-stock/:storeId/:productId?b=&pt= — b/pt 를 선택 파라미터로 받아 labelMatch: 'exact-label' 로 응답하는 계약"
provides:
  - "print.service.ts 의 buildQrUrl() 헬퍼 — QR URL 조립을 한 곳으로 모음(정의 1 + 사용 2)"
  - "신 라벨 QR 에 &b={branchId}&pt={priceTypeId} 포함 — qr_print_log 유니크 키 3개가 다 채워져 그 행이 확정됨(exact-label)"
  - "b·pt 없는 구 라벨의 하위호환 유지 — 값이 없거나 정수가 아니면 해당 파라미터를 붙이지 않음"
affects: [89-09, 89-11]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "쓰레기 값을 라벨에 인쇄하지 않는 선택적 쿼리 조립 — Number.isInteger(n) && n > 0 가드를 통과한 값만 &key= 로 붙인다"
    - "any 타입 테스트 하네스에 새 시험을 추가할 때는 로컬 인터페이스로 캐스팅해 신규 줄에서 no-unsafe-* 를 만들지 않는다(하네스 전체를 재타입하지 않음)"

key-files:
  created: []
  modified:
    - api-ventago/src/app/print/print.service.ts
    - api-ventago/src/app/print/print.controller.ts
    - api-ventago/src/app/print/print-product-ownership.spec.ts
    - api-ventago/src/app/print/print.service.qr.spec.ts

key-decisions:
  - "plan 이 지시한 주석 원문 리터럴('/m/stock?s=6&p=10')이 같은 Task 의 acceptance_criteria(grep -c \"m/stock?s=\" 가 1이어야 함)와 충돌 — 89-01/89-04/89-06 과 동일한 형태의 plan 자체 모순. 의미는 유지하고 주석 표현만 동의어로 교체해 해소"
  - "print-product-ownership.spec.ts 의 기존 단언(toHaveBeenCalledWith(89, 11))이 buildQrPayload 세 번째 인자(branchId) 추가로 깨짐 — Rule 1 로 자동 수정(branchId=1 추가)"
  - "print.service.qr.spec.ts 의 새 시험 블록에서 makeService 의 any 타입 svc 를 그대로 쓰면 신규 줄마다 no-unsafe-* 에러가 나 커밋 게이트가 막힘 — 하네스 전체를 재타입하지 않고, 새 블록에서만 로컬 TestableQrService 인터페이스로 캐스팅해 해소(범위 확장 없음)"

requirements-completed: [REQ-01]

# Metrics
duration: 40min
completed: 2026-09-16
---

# Phase 89 Plan 07: QR URL 에 지점·가격유형 싣기 — 하위호환 유지 Summary

**print.service.ts 의 QR URL 조립 두 지점을 `buildQrUrl()` 헬퍼 하나로 통합하고, 신 라벨에는 `&b={branchId}&pt={priceTypeId}` 를 실어 `qr_print_log` 유니크 키 3개를 전부 채우면서도 값이 없거나 쓰레기면 아무것도 붙이지 않아 구 라벨을 그대로 살린다**

## Performance

- **Duration:** 약 40분
- **Started:** 2026-09-16
- **Completed:** 2026-09-16
- **Tasks:** 2/2 완료
- **Files modified:** 4

## Accomplishments
- `buildQrUrl(storeId, parentProductId, branchId?, priceTypeId?)` 사설 헬퍼를 신설해 `buildQrPayload`(전체 QR 출력)와 델타 목록 조립(NUEVO/CAMBIO) 두 지점이 모두 이 헬퍼를 호출하도록 통합 — QR URL 조립이 한 곳으로 모임(`grep -c "m/stock?s=" print.service.ts` = 1)
- `opt(clave, v)` 내부 가드가 `Number.isInteger(n) && n > 0` 를 통과한 값만 `&key=value` 로 붙인다 — `&b=NaN`·`&b=undefined` 같은 되돌릴 수 없는 문자열이 실물 라벨에 인쇄되는 것을 원천 차단
- `print.controller.ts` 의 `printQr` 이 이미 `resolvePrintBranchId(req, body)` 로 소유권 검사를 거친 `branchId` 를 `buildQrPayload` 세 번째 인자로 그대로 전달 — 새로 조회하지 않음
- `&b=`·`&pt=` 는 반드시 `p=` 뒤에 붙어 기존 회귀 시험의 부분 문자열 단언(`'/m/stock?s=6&p=10'`)이 그대로 유지됨
- 신규 회귀 시험 5건(A~E) + 대조군 실증: `Number.isInteger` 가드를 일시적으로 제거해 Test B·C 가 실제로 빨개지는 것을 확인한 뒤 원복 — 가드가 없으면 시험이 통과하지 못한다는 것을 실측으로 증명
- 하위호환 확인: `branchId` 를 생략하고 `buildQrPayload` 를 부르면(구 호출부와 동일한 형태) `&b=` 가 붙지 않고, `priceTypeId`/`branchId` 에 `0`·`NaN`·`'abc'` 를 줘도 해당 파라미터가 붙지 않음(두 파라미터가 서로 독립적으로 검증됨)

## Task Commits

각 Task 는 서브모듈(api-ventago) 커밋 → 슈퍼프로젝트 gitlink 포인터 커밋 순으로 원자적으로 커밋됨:

1. **Task 1: 두 조립 지점에 `&b=`·`&pt=` 추가 (값이 유효할 때만)** - `2264751e` (api-ventago, feat) + `466357c` (root, chore: submodule pointer)
2. **Task 2: 하위호환 회귀 시험 — `b` 없는 라벨이 계속 동작한다** - `ead5cefd` (api-ventago, test) + `185ba09` (root, chore: submodule pointer)

**Plan metadata:** (이 커밋 — SUMMARY + STATE.md + ROADMAP.md)

## Files Created/Modified
- `api-ventago/src/app/print/print.service.ts` - `buildQrUrl()` private 헬퍼 신설(정의 1). `buildQrPayload` 시그니처에 세 번째 선택 인자 `branchId?: number | null` 추가, 두 조립 지점(전체 출력/델타 목록) 모두 이 헬퍼 호출로 교체. 델타 목록 루프 안에서 `p.id` 를 `(p as { id: number }).id` 로 캐스팅해 신규 줄의 `no-unsafe-member-access` eslint 오류 회피
- `api-ventago/src/app/print/print.controller.ts` - `printQr` 이 `buildQrPayload` 호출 시 이미 확정된 `branchId` 를 세 번째 인자로 전달
- `api-ventago/src/app/print/print-product-ownership.spec.ts` - `buildQrPayload` 호출 단언에 세 번째 인자(`branchId=1`) 반영(회귀 방지)
- `api-ventago/src/app/print/print.service.qr.spec.ts` - `[Phase 89] QR 에 지점 싣기 — 하위호환` describe 블록 신설, 5개 시험(A~E) + `TestableQrService` 로컬 타입 인터페이스

## Decisions Made
- **plan 내부 모순 해소(Rule 1)**: `<interfaces>`/`<action>` 절이 예시로 든 주석 원문에 `'/m/stock?s=6&p=10'` 리터럴이 그대로 있었는데, 같은 Task 의 acceptance(`grep -c "m/stock?s=" == 1`)는 그 문자열이 파일에 **한 번만** 있어야 한다고 요구했다 — 조립 코드(1회)와 설명 주석(1회)을 합치면 2가 되어 충돌. 의미는 유지하고 주석의 리터럴 문자열만 "스토어·상품 쿼리 부분 문자열" 로 바꿔 해소(SQL/로직 무변경).
- **기존 시험 회귀 수정(Rule 1)**: `print-product-ownership.spec.ts` 는 `buildQrPayload` 가 `(89, 11)` 두 인자로만 불린다고 단언했는데, 이 plan 이 세 번째 인자(`branchId`)를 항상 전달하도록 컨트롤러를 바꿔 그 단언이 깨졌다. 테스트가 이미 만드는 `branchId=1`(REQ.user.branchId)을 그대로 단언에 반영해 회귀를 막았다.
- **테스트 하네스 타입 안전성(Rule 1, 유사)**: `print.service.qr.spec.ts` 의 `makeService` 는 파일 전역에서 `svc: any` 를 반환하는 기존 관례다. 새 시험 5개를 그 관례 그대로(`const { svc } = makeService(...)`) 작성하면 신규 줄마다 `no-unsafe-call`/`no-unsafe-member-access` 가 발생해 커밋 게이트(추가된 줄의 eslint 오류만 차단)에 걸린다. 하네스 전체를 재타입하는 것은 이 plan 범위 밖이므로, 새 블록에서만 `TestableQrService`(최소 인터페이스)로 `as` 캐스팅해 신규 줄만 타입 안전하게 만들었다 — 기존 시험·하네스는 무변경.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - plan 내부 모순] Task 1 주석 리터럴이 acceptance_criteria(1건 요구)와 충돌**
- **Found during:** Task 1 acceptance 검증(`grep -c "m/stock?s=" print.service.ts`)
- **Issue:** `<action>` 이 지시한 주석 원문에 `'/m/stock?s=6&p=10'` 리터럴이 있어, 실제 조립 코드(1회) + 이 주석(1회) = 2회가 되어 "1이어야 한다"는 acceptance 와 충돌(89-01/89-04/89-06 과 동일한 형태의 plan 자체 모순)
- **Fix:** SQL·로직·조립 코드는 그대로 두고, 주석의 리터럴 문자열만 "스토어·상품 쿼리 부분 문자열을 그대로 단언한다"로 동의어 교체
- **Files modified:** `api-ventago/src/app/print/print.service.ts`
- **Verification:** `grep -c "m/stock?s="` → 1, `grep -c "buildQrUrl"` → 3(정의 1 + 사용 2), `npx tsc --noEmit` 0, `npx jest src/app/print --maxWorkers=1` 7/7 suites 통과
- **Committed in:** `2264751e` (Task 1 커밋)

**2. [Rule 1 - 회귀] `print-product-ownership.spec.ts` 의 기존 단언이 시그니처 변경으로 깨짐**
- **Found during:** Task 1 acceptance 검증(`npx jest src/app/print`)
- **Issue:** `buildQrPayload` 세 번째 인자(`branchId`)를 컨트롤러가 항상 전달하도록 바꾸자, 기존 시험의 `expect(buildQrPayload).toHaveBeenCalledWith(89, 11)` (두 인자만 단언)이 실패
- **Fix:** 그 시험이 이미 구성한 `REQ.user.branchId=1` 이 실제로 전달되는 값이므로, 단언을 `toHaveBeenCalledWith(89, 11, 1)` 로 갱신(로직 무변경, 시험만 현재 계약에 맞춤)
- **Files modified:** `api-ventago/src/app/print/print-product-ownership.spec.ts`
- **Verification:** `npx jest src/app/print --maxWorkers=1` 7/7 suites, 62/62(Task 1 시점) 통과
- **Committed in:** `2264751e` (Task 1 커밋)

**3. [Rule 1 - lint] 델타 목록 루프의 `p.id` any 접근이 커밋 게이트(추가 줄 eslint)에 걸림**
- **Found during:** Task 1 커밋 시도(pre-commit hook, "api eslint — 내가 추가한 줄에 오류가 있다: print.service.ts:354")
- **Issue:** `products: any[]` 배열의 `p.id` 를 새로 추가한 줄에서 `buildQrUrl` 인자로 바로 넘기자 `no-unsafe-member-access` 가 신규 줄에 걸림(파일 전체는 기존에도 같은 패턴이 수십 곳 있으나, 게이트는 "추가된 줄"만 본다)
- **Fix:** `const productId: number = (p as { id: number }).id;` 로 한 번 캐스팅한 뒤 그 변수를 넘기도록 변경 — 객체를 먼저 특정 타입으로 단언하면 그 멤버 접근은 `any` 기원이 아니게 되어 규칙이 통과함
- **Files modified:** `api-ventago/src/app/print/print.service.ts`
- **Verification:** `npx eslint src/app/print/print.service.ts` 로 해당 줄(354) 재확인 → 오류 0, `npx tsc --noEmit` 0, `npx jest src/app/print --maxWorkers=1` 통과
- **Committed in:** `2264751e` (Task 1 커밋)

**4. [Rule 1 - lint] 신규 시험 블록의 any 타입 접근이 커밋 게이트에 걸림**
- **Found during:** Task 2 작성 중 사전 점검(`npx eslint src/app/print/print.service.qr.spec.ts`)
- **Issue:** 새 시험 5개를 기존 하네스 관례(`const { svc } = makeService(...)`, `svc: any`)그대로 작성하면 신규 줄마다 `no-unsafe-call`/`no-unsafe-member-access`가 발생 — 파일 전체(기존 186개 문제, 원본에도 존재)와 별개로 **추가된 줄**이 게이트에 걸림
- **Fix:** 하네스 자체(`makeService`)는 건드리지 않고, 새 describe 블록 안에서만 `TestableQrService`(최소 인터페이스: `getQrItems`/`buildQrPayload`/`productRepo.findByPk`/`pricesRepo.findOne` 시그니처)를 정의해 `makeService(...).svc as TestableQrService` 로 캐스팅. 이후 모든 신규 줄이 타입 안전
- **Files modified:** `api-ventago/src/app/print/print.service.qr.spec.ts`
- **Verification:** `npx eslint src/app/print/print.service.qr.spec.ts` — 신규 블록(293행 이후) 구간에서 오류 0(파일 전체는 기존과 동일하게 186개 유지, 전부 원본 라인), `npx tsc --noEmit` 0, `npx jest` 7/7 suites·67/67 tests 통과
- **Committed in:** `ead5cefd` (Task 2 커밋)

---

**Total deviations:** 4 auto-fixed (Rule 1 — plan 내부 모순 1건, 기존 시험 회귀 1건, lint 회피 2건)
**Impact on plan:** SQL 없음(이 plan 은 DB 접근 없음), 응답 계약·URL 조립 로직은 plan 지시 그대로. 사람이 읽는 주석 표현·기존 시험 단언·타입 캐스팅만 조정. 스코프 확장 없음(하네스 전체 재타입 등은 하지 않음).

## Issues Encountered
None — 두 Task 모두 위 자잘한 조정 외에는 acceptance criteria 를 첫 시도 또는 두 번째 시도에서 충족.

## User Setup Required
None - 외부 서비스 설정 불필요. 코드 배포만으로 완결되는 plan.

## ★ 대조군 실증 (plan 이 명시적으로 요구한 절차)

Task 2 의 acceptance 는 "`Number.isInteger` 가드를 지우면 Test C 가 빨개지는 것을 확인했다"를 SUMMARY 에 남기도록 요구한다. 실제로 확인함:

1. `print.service.ts` 의 `opt()` 헬퍼에서 `Number.isInteger(n) && n > 0 ? ... : ''` 를 `` `&${clave}=${n}` `` (조건 없이 항상 붙임)로 임시 변경
2. `npx jest src/app/print/print.service.qr.spec.ts --maxWorkers=1` 재실행 → **Test B·C 가 실제로 실패**:
   - Test B: `qrUrl` 이 `...&b=NaN&pt=2` 로 나와 `not.toContain('&b=')` 위반
   - Test C: `...&b=0&pt=2` 로 나와 같은 위반
   - Test A·D·E 는 영향 없음(정상 값만 다루므로) — 대조군이 **정확히 의도한 두 시험만** 잡아낸다는 것도 함께 확인
3. `print.service.ts` 를 원본으로 완전히 복원(`git diff --stat` 로 diff 없음 확인) 후 전체 시험 재실행 → 7/7 suites, 67/67 tests, exit 0

이로써 가드가 없으면 하위호환 시험이 실제로 그 결함을 잡는다는 것이 실측됐다 — "통과가 곧 지켜짐"이 아니라 "제거하면 빨개진다"까지 확인함.

## ★ 이 plan 이 해결하지 못하는 것 (plan 이 명시한 한계 — 해결했다고 쓰지 않음)

**구 라벨의 모호성은 그대로 남는다.** 이미 인쇄돼 매장에 붙어 있는 라벨(운영 `qr_print_log` 5행, 지점 6)은 `b`·`pt` 가 없으므로 이 plan 이후에도 여전히 "가장 최근 인쇄분" 추정(`labelMatch: 'latest-print'`)으로만 조회된다. 이 plan 이 바꾸는 것은 **앞으로 새로 인쇄되는 라벨**뿐이다. 89-04 의 API 는 이미 이 두 갈래를 구분해 응답하고 있었고, 이 plan 은 "신 라벨이 확정 갈래(`exact-label`)로 들어갈 수 있게" 만든 것이 전부다.

**QR 크기 변화가 실물 인쇄에서 읽히는지는 코드로 증명되지 않는다.** `&b=123&pt=11` 로 URL 이 약 12자 안팎 늘어난다. zebra-agent 의 자동 크기맞춤(`effectiveQrModule`)이 이를 흡수하는지는 이 plan 의 범위 밖이며, 89-09 체크포인트의 실물 스캔으로만 확인된다. 안 읽히면 `&pt=` 부터 되돌리는 것을 권장(`&b=` 가 지점 표시라는 더 큰 가치를 준다) — 그때는 `labelMatch` 가 `'latest-print'` 로 남고 89-06 의 기존 문구가 그대로 뜬다(기능은 산다).

## Next Phase Readiness
- 89-09(실물 인쇄·스캔 체크포인트)가 이제 신 라벨을 인쇄하면 `&b=`·`&pt=` 가 실린 QR 을 만들 수 있다 — 스캔 시 `labelMatch: 'exact-label'` 응답을 실측으로 확인할 수 있다.
- 89-11(자동화 시험)이 이 plan 의 회귀 시험 패턴(`TestableQrService` 로컬 캐스팅)을 다른 `any` 하네스 파일에도 재사용할 수 있다.
- 배포 순서 권장: 89-06(공개 페이지)이 이미 배포된 뒤에 이 plan 을 배포하는 것을 권한다. 먼저 나가도 안전하다 — 그 QR 도 89-04/89-06 이 없으면 어차피 페이지가 없어 404 다.
- 블로커 없음.

---
*Phase: 89-qr-public-product-page*
*Completed: 2026-09-16*

## Self-Check: PASSED

- FOUND: api-ventago/src/app/print/print.service.ts
- FOUND: api-ventago/src/app/print/print.controller.ts
- FOUND: api-ventago/src/app/print/print-product-ownership.spec.ts
- FOUND: api-ventago/src/app/print/print.service.qr.spec.ts
- FOUND: .planning/phases/89-qr-public-product-page/89-07-SUMMARY.md
- FOUND commit 2264751e (api-ventago submodule, Task 1)
- FOUND commit ead5cefd (api-ventago submodule, Task 2)
- FOUND commit 466357c (root, Task 1 pointer)
- FOUND commit 185ba09 (root, Task 2 pointer)
