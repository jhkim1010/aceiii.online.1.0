---
phase: 69-tenant-isolation-security-hardening
plan: 03
subsystem: api
tags: [nestjs, sequelize, multi-tenant, transaction, security]

# Dependency graph
requires:
  - phase: 67-tenant-isolation-absolute-hooks
    provides: "assertProductInStore, isSuperAdminUser/storeIdOfUser 스코프 유틸"
  - phase: 68-derived-scope-observe
    provides: "ProductBranch 를 파생 격리 대상으로 등록(observe 모드) — 이 플랜이 실제 차단으로 보강"
provides:
  - "PUT /products/:id/correct-today 의 branchIds/items[].variantId 전량 소유권 검증(403)"
  - "correctTodayStocks 검증+원장보정+가격갱신 단일 트랜잭션 통합"
  - "교차매장 correct-today 회귀 테스트 6종 + 컨트롤러 scope 전달 테스트 1종"
affects: [69-04, 69-06, 69-tenant-isolation-security-hardening]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "필수(optional 아님) scope 인자로 호출부 누락을 컴파일 타임에 차단"
    - "ProductBranch 조회에 product/branch 양쪽 required:true INNER JOIN + storeId where 로 2중 방어"
    - "검증 쿼리까지 트랜잭션 안에 포함해 스냅샷 일관성 확보"

key-files:
  created: []
  modified:
    - api-ventago/src/app/products/productStock.service.ts
    - api-ventago/src/app/products/products.controller.ts
    - api-ventago/src/app/products/productStock.service.spec.ts
    - api-ventago/src/app/products/products.controller.spec.ts

key-decisions:
  - "priceUpdates/basePrice 의 `?` 를 제거하고 `T | undefined` 로 타입만 바꿔 뒤따르는 필수 scope 인자를 TS1016(required-after-optional) 없이 추가함 — 호출부 실제 동작은 무변경"
  - "ProductBranch 조회의 product/branch storeId where 는 superadmin 여부와 무관하게 항상 parent.storeId 로 적용(내부 정합성 검증이지 요청자 스코프 검증이 아니므로) — 요청자 스코프 검증(1~3번)만 isSuperAdmin 시 skip"
  - "Task 1(검증)과 Task 2(트랜잭션 통합)를 한 커밋(29f21dd)으로 병합 — 검증 쿼리를 트랜잭션 스냅샷 안에 포함시켜야 한다는 요구 자체가 두 태스크를 코드 레벨에서 분리 불가능하게 만듦"

requirements-completed: [R2]

# Metrics
duration: ~55min
completed: 2026-08-01
---

# Phase 69 Plan 03: correct-today 재고정정 교차매장 쓰기 차단(R2/CR-02) Summary

**`PUT /products/:id/correct-today` 의 branchIds/variantId 전량 소유권 검증 + 검증·원장보정·가격갱신 단일 트랜잭션 통합으로 타 매장 Stocks 원장 오염 경로(R2/CR-02) 봉쇄**

## Performance

- **Duration:** ~55분 (정확한 시작 타임스탬프 미기록 — 세션 로그 기준 추정)
- **Completed:** 2026-08-01T02:25Z
- **Tasks:** 3/3
- **Files modified:** 4 (서비스 1, 컨트롤러 1, 스펙 2)

## Accomplishments

- `correctTodayStocks` 가 `branchIds` 전량을 `Branch.findAll({id IN, storeId: parent.storeId})` 로, `items[].variantId` 전량을 `storeId` + `parentId` 이중 조건으로 검증 — 불일치 시 요청 전체가 `ForbiddenException`/`NotFoundException` 으로 종료되고 `Stocks` 행이 0개 생성됨
- `ProductBranch.findAll` 조회에 `product`/`branch` 양쪽 `required: true` INNER JOIN + `storeId` where 를 추가해 2중 방어선 구축(Phase 68 Sager 함정 — `required` 누락 시 필터가 ON 절로 내려가 무력화되는 문제 회피)
- 검증 쿼리(Branch/Product findAll) 부터 원장 보정(`Stocks.create`)·가격 갱신(`Price`/`Product.update`)까지 전부 하나의 `sequelize.transaction()` 으로 통합 — 종전에는 `priceUpdates`/`basePrice` 가 트랜잭션 밖에서 별도 커밋돼 부분 저장 위험이 있었음(CLAUDE.md Phase 64 결함 2·3·4 유형)
- 교차매장 회귀 테스트 6종 + 컨트롤러 scope 전달 고정 테스트 1종 추가, 구코드에서 실패함을 실측 확인

## Task Commits

1. **Task 1+2: correctTodayStocks 소유권 검증 + 단일 트랜잭션 통합** - `29f21dd` (feat)
2. **Task 3: 교차매장 회귀 테스트 6종** - `b5de9a6` (test)

**Plan metadata:** (이 SUMMARY 커밋 — 루트 레포에서 별도 커밋 예정)

_Note: Task 1과 Task 2는 코드 레벨에서 분리 불가능해(검증 쿼리를 트랜잭션 스냅샷 안에 포함해야 함) 한 커밋으로 병합했다. 아래 "Deviations" 참조._

## Files Created/Modified

- `api-ventago/src/app/products/productStock.service.ts` — `correctTodayStocks` 시그니처에 필수 `scope` 인자 추가, 부모/branchIds/variantId 소유권 검증, ProductBranch 양쪽 storeId JOIN, 전체를 단일 트랜잭션으로 재구성
- `api-ventago/src/app/products/products.controller.ts` — `correctTodayStocks` 호출부에서 `{ storeId, isSuperAdmin }` 스코프를 서비스로 전달
- `api-ventago/src/app/products/productStock.service.spec.ts` — `Branch`/`ProductBranch.findAll`/`Stocks.findAll`/`sequelize.transaction` mock 추가 + `correctTodayStocks — 교차매장 차단(R2/CR-02)` describe 블록(6 케이스)
- `api-ventago/src/app/products/products.controller.spec.ts` — `correctTodayStocks` 가 scope 를 그대로 전달하는지 고정하는 케이스 1개

## Decisions Made

- **TS1016 회피 방법:** `priceUpdates`/`basePrice` 파라미터의 `?` (optional marker) 를 제거하고 각각 `Array<...> | undefined`, `number | undefined` 타입으로 바꿔, 필수(진짜 optional 아님) `scope` 를 마지막 인자로 추가해도 "required parameter cannot follow optional parameter" 컴파일 에러가 나지 않도록 했다. 호출부(`products.controller.ts`) 는 여전히 `undefined` 를 넘길 수 있으므로 런타임 동작은 무변화.
- **ProductBranch JOIN 은 superadmin 여부와 무관하게 항상 적용:** PLAN 의 "scope.isSuperAdmin === true 면 전부 skip" 은 1~3번(요청자 storeId 와 비교하는 검증)에 대한 것으로 해석했다. 4번(ProductBranch 의 product/branch 를 `parent.storeId` 로 JOIN)은 요청자 스코프가 아니라 "이 상품·지점이 실제로 같은 매장 소속인가"라는 내부 정합성 검증이라 superadmin 도 포함해 항상 적용한다 — Threat Register `T-69-11` 의 "product·branch 양쪽 required:true" 문구와 일치.
- **Task 1/2 커밋 병합:** PLAN 은 두 태스크로 나눴지만, Task 2 의 요구사항("검증 쿼리도 같은 transaction: tx 로 실행해 스냅샷 일관성 확보")을 만족하려면 Task 1 에서 만든 검증 로직을 트랜잭션 시작 이전 위치에 둘 수 없다(트랜잭션 자체를 검증 앞으로 당겨야 함). 두 태스크를 순차 커밋하면 중간 커밋이 "검증은 있지만 트랜잭션 밖"인 상태로 남아 오히려 혼란스러워, 최종 형태로 한 번에 커밋했다.

## Deviations from Plan

### 계획대로 진행 (자동수정 규칙 적용 없음)

수정 3개 규칙(버그/누락기능/블로커) 트리거 없음 — R2 결함 자체가 이 플랜의 목적이었고, 계획된 범위 내에서 전부 구현됨.

### Task 병합 (계획 구조 변경, Rule 4 아님 — 실행 순서상 불가피)

- Task 1과 Task 2를 하나의 커밋으로 병합. 사유는 위 "Decisions Made" 참조. 아키텍처 변경이 아니라 동일 함수 내 실행 순서 재배치이므로 Rule 4(아키텍처 변경 승인 필요) 대상이 아니라고 판단해 자동 진행함.

**Total deviations:** 1 (커밋 구조 병합, 코드 동작 변경 아님)
**Impact on plan:** 없음 — 최종 코드는 PLAN 의 `must_haves`/`acceptance_criteria` 를 전부 만족.

## Issues Encountered

- **사전 존재 실패 스펙 (범위 밖):** `productStock.service.spec.ts` 의 `createVariantsBatch` 관련 14개 테스트와 `products.service.spec.ts` 의 5개 테스트가 이 플랜과 무관하게 이미 실패 상태였다(`git stash` 로 69-03 변경분 제외 후 동일하게 재현 확인 — 실패 테스트명·개수 동일). `correctTodayStocks` 를 건드리지 않은 메서드라 Scope Boundary 규칙에 따라 수정하지 않고 `.planning/phases/69-tenant-isolation-security-hardening/deferred-items.md` 에 기록만 남겼다.
- **TS1016 (required-after-optional):** 위 Decisions Made 참조 — `priceUpdates`/`basePrice` 타입을 조정해 해결.

## Verification Evidence

### 1. `npx tsc --noEmit -p tsconfig.json` — baseline 16건 유지, 신규 에러 0건

```
$ npx tsc --noEmit -p tsconfig.json 2>&1 | grep -c "error TS"
16
```

16건 전부 `afip-output.service.spec.ts`/`sales.controller.spec.ts`/`suspended-sales.*.spec.ts` — 이 플랜이 건드리지 않은 파일들의 기존 오류(TS2554, 이 플랜 이전부터 존재).

**scope 필수 인자 검증 (acceptance criteria 명시 요구):** 컨트롤러 호출부에서 마지막 `{ storeId, isSuperAdmin }` 인자를 일부러 제거하고 재실행:

```
$ (제거 후) npx tsc --noEmit -p tsconfig.json 2>&1 | grep "products.controller.ts"
src/app/products/products.controller.ts(826,52): error TS2554: Expected 7 arguments, but got 6.
```

→ 컴파일 실패 확인 후 원복, 재확인 시 baseline 16건으로 복귀.

### 2. Jest — 신규 테스트 전부 통과, 무관 테스트 무회귀

```
$ npx jest src/app/products/productStock.service.spec.ts -t "correctTodayStocks"
correctTodayStocks — 교차매장 차단(R2/CR-02)
  ✓ branchIds 에 타 매장(20) 지점을 섞으면 ForbiddenException + create 0회
  ✓ items[].variantId 가 타 매장(20) 상품이면 ForbiddenException + create 0회
  ✓ items[].variantId 가 같은 매장이지만 다른 부모(6)의 자식이면 ForbiddenException + create 0회
  ✓ 존재하지 않는 variantId 는 NotFoundException + create 0회
  ✓ 정상 경로(자기 매장 branch + 자기 부모의 자식 variant) — 무회귀, commit 1회 rollback 0회
  ✓ 트랜잭션 도중 예외(대상 ProductBranch 없음) 발생 시 rollback 1회, commit 0회
Tests: 20 skipped, 6 passed, 26 total
```

```
$ npx jest src/app/products/products.controller.spec.ts
Tests: 42 passed, 42 total
```

전체 `productStock.service.spec.ts` (createVariantsBatch 14건 pre-existing 실패 포함):
```
$ npx jest src/app/products/productStock.service.spec.ts
Tests: 14 failed, 12 passed, 26 total
```
→ `git stash` 로 69-03 이전 상태에서 동일 커맨드 실행 시 동일하게 `14 failed, 6 passed, 20 total` (신규 6건 제외하면 실패 목록 완전 일치) — 이 플랜이 새로 깨뜨린 테스트 없음.

### 3. Task 3 acceptance criteria — "구코드로 되돌렸을 때 실패 개수" 실측

`29f21dd`(Task1+2 커밋) 를 되돌린 상태(services/controller 만 `708b540` 로 checkout, 신규 테스트는 유지)에서:

```
$ npx jest src/app/products/productStock.service.spec.ts src/app/products/products.controller.spec.ts
FAIL productStock.service.spec.ts — Test suite failed to run (TS2554: Expected 4-6 arguments, but got 7) × 6곳
FAIL products.controller.spec.ts — 1 failed, 41 passed, 42 total
  ✕ scope(storeId+isSuperAdmin) 를 서비스에 그대로 전달한다
Tests: 1 failed, 41 passed, 42 total (productStock 스위트는 컴파일 자체가 안 되어 0/26 집계)
```

→ **실패 개수: productStock.service.spec.ts 전체(26/26, 컴파일 실패로 스위트 자체 실행 불가) + products.controller.spec.ts 1건**, 총 신규 테스트 7개(6+1) 모두가 구코드에서 실패(또는 컴파일 불가)함을 확인. 검증 후 `git checkout HEAD -- ...` 로 즉시 원복.

### 4. `grep -n "transaction: tx"` — 4건 이상 요구, 12건 확인

```
$ grep -c "transaction: tx" api-ventago/src/app/products/productStock.service.ts
12
```

### 5. ESLint — 변경 파일에 신규 에러 없음(서비스/컨트롤러), 스펙 파일은 기존 `any` 패턴과 동일 계열 증가

```
$ npx eslint src/app/products/productStock.service.ts   # baseline 144 → 142 (fix 후, 개선)
$ npx eslint src/app/products/products.controller.ts     # baseline 48 → 48 (무변화)
```

스펙 파일(`productStock.service.spec.ts`, `products.controller.spec.ts`) 은 파일 전체가 `any` 캐스팅 mock 패턴을 이미 광범위하게 쓰고 있어(`no-unsafe-*` 규칙), baseline 267→307(신규 테스트 코드가 동일 패턴을 그대로 답습) 문제로 늘었으나 **전부 warning/error 유형이 기존 파일과 동일 계열**이며, `package.json` 의 `build` 스크립트(`nest build`)는 eslint 를 실행하지 않으므로 배포 빌드를 막지 않는다(CLAUDE.md 의 "ESLint 경고=빌드에러" 규정은 프런트엔드 대상 — 백엔드는 SWC 빌드).

## User Setup Required

None - no external service configuration required. DDL 없음(계획서 명시) — 마이그레이션 불필요.

## Next Phase Readiness

- `correctTodayStocks` 최종 시그니처(69-06 이 참조):
  ```ts
  async correctTodayStocks(
    parentId: number,
    date: string,
    branchIds: number[],
    items: Array<{ variantId: number; newStock: number }>,
    priceUpdates: Array<{ priceTypeId: number; amount: number; currency?: string }> | undefined,
    basePrice: number | undefined,
    scope: { storeId: number | null; isSuperAdmin: boolean },
  ): Promise<{ updated: number; created: number; deleted: number; pricesUpdated: number; pricesCreated: number }>
  ```
- R2/CR-02 봉쇄 완료 — Wave 1(R1/W1, R2/W2, R3/W3) 병렬 계획 중 W2 완료.
- 미완료 항목 없음. `deferred-items.md` 에 기록된 두 건(products.service.spec.ts 5건, productStock createVariantsBatch 14건)은 이 플랜과 무관한 pre-existing 드리프트로, 별도 플랜/조사 대상.

## Self-Check: PASSED

- FOUND: api-ventago/src/app/products/productStock.service.ts
- FOUND: api-ventago/src/app/products/products.controller.ts
- FOUND: api-ventago/src/app/products/productStock.service.spec.ts
- FOUND: api-ventago/src/app/products/products.controller.spec.ts
- FOUND commit: 29f21dd (feat, Task 1+2)
- FOUND commit: b5de9a6 (test, Task 3)
- FOUND: .planning/phases/69-tenant-isolation-security-hardening/deferred-items.md

---
*Phase: 69-tenant-isolation-security-hardening*
*Plan: 03*
*Completed: 2026-08-01*
