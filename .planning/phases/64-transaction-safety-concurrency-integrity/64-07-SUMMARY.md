# Phase 64 Plan 07 — 매장 경계 검증 + 재고 원장 불변 · SUMMARY

**Executed:** 2026-07-28
**Requirements:** R8, R9
**Status:** 코드 완료 · 정책 확정 반영 완료

## 정책 (사용자 확정 2026-07-28)

> **각 매장은 반드시 자기 상품만 판매한다. 절대 혼합 운용은 없다.**

이 확정에 따라 계획 단계의 "위반 데이터가 있으면 차단 도입을 재검토" 조항은 소멸했다.
차단은 **예외 없이** 적용하고, 폴백 경로도 남기지 않는다.

## Task 1 — 사전 조사 (읽기 전용, 로컬 5432 + 운영 5434)

| 쿼리 | 로컬 | 운영 |
|---|---|---|
| (1) 판매 아이템 상품 ≠ 판매 매장 | 0행 | **10건 / 6종** |
| (2) 판매원 타 매장 소속 | 0행 | 0행 |
| (3) 터미널→box→지점 타 매장 | 0행 | 0행 |

운영 위반 6종 상세는 `64-VALIDATION.md` §2. 요약: 전부 **2026-03-31 ~ 04-30** 테스트기 유입,
최근 3개월 0건. 정책상 이는 **위반 잔존 데이터**이며 과거 데이터로 남긴다(소급 수정 없음).
차단은 신규 판매에만 적용되므로 운영 영향 없음.

## Task 2 — 매장 경계 강제 (R8)

`sales-create.service.ts`

| 대상 | 변경 |
|---|---|
| 상품 | `findByPk(id)` → `findOne({ where: { id, storeId } })`, 불일치 404 |
| 판매원 | `findByPk(id)` → `findOne({ where: { id, storeId } })`, 불일치 **400** (종전 NULL 강등 → 실적 오염) |
| 연결 판매원 안전망 | `findOne({ linkedUserId, isActive, storeId })` — storeId 조건 추가 |
| 지점 | `dtoBranchId` 를 `findOne({ id, storeId })` 로 검증, 불일치 400 |
| `storeId` 자체 | **폴백 제거** — 없으면 400 (`processSaleItems` 진입 가드) |

`restaurant-sale.service.ts` — **신규 검증 추가**

식당 모드 `placeOrder` 는 종전에 `dto.items[].productId` 를 **검증 없이 그대로** `sale_items` 에
넣고 있었다. 소매 경로만 고쳤다면 식당 모드로 경계가 그대로 뚫렸을 것이다.
`assertProductsBelongToStore()` 를 추가해 트랜잭션 진입 전 **단일 쿼리**로 전량 확인하고,
타 매장 상품이 섞이면 위반 productId 를 명시해 400.

> 쿼리 수: 품목 N개여도 조회 1회(`WHERE id IN (...) AND store_id = ?`). pool 영향 무시 가능.

점검했으나 변경 불필요한 경로:
- 오프라인 push → `SalesCreateService.create` 위임이라 자동 적용
- 온라인 주문 재고 조정(`online-order-stock.service.ts:364`) → 이미 생성·검증된 주문 아이템의
  사후 재고 동기화(FOR UPDATE), 신규 경계 진입점 아님
- 보류 판매 확정 → POS 판매 생성 경유

## Task 3 — 재고 원장 불변 (R9)

`stocks.service.ts`

| 메서드 | 변경 |
|---|---|
| `findByProduct` | `where: { productId }` (존재하지 않는 컬럼) → `ProductBranch` include 경유. `branchId` 선택 필터 추가 |
| `updateStock` | 원장 행 UPDATE → `adjust()` 위임 |
| `delete` | 원장 행 DELETE → `adjust()` 위임 |
| `adjust` (신규) | 원본 행을 `FOR UPDATE` 로 잠그고 **반대 부호 보정 행** INSERT + `products.stock` 동시 조정, 단일 트랜잭션. `note` 에 `mov#{id} / user#{id} / 사유` 기록 |
| `create` | `productBranchId` 또는 `(productId + branchId)` 수용 → ProductBranch 해석 후 원장 INSERT + 캐시 반영 |

`stocks.controller.ts` — `DELETE /stocks/:id` 는 라우트를 유지하되 `adjust` 로 위임(기존 클라이언트 호환).
`GET /stocks/by-product` 에 `branchId` 쿼리 파라미터 추가. 프런트에서 `PUT/DELETE /stocks/:id` 사용처 **0건** 확인.

DTO: `CreateStockDto` 에 `branchId`/`productBranchId` 추가(둘 다 선택, 서비스가 검증),
`UpdateStockDto` 에 `reason` 추가(보정 사유).

## 검증

```
npx tsc --noEmit -p tsconfig.json     → 대상 모듈 에러 0
npx jest src/app/stocks               → 7 passed (신규)
npx jest src/app/sales/restaurant-sale → 16 passed (기존 14 + 경계 2)

grep 게이트
  stocks 대상 productId 참조            → 0
  .destroy() / stock.update(            → 0 / 0
  "no pertenece a esta tienda"          → 2 (판매원/지점)
  "no pertenece(n) a esta tienda"       → 1 (식당 상품)

eslint baseline 대조
  sales-create.service.ts   147 → 147 (동일)
  stocks/ 신규 spec          0 problems
```

## 남은 것

- 브라우저 UAT: RG-11(generic 상품 판매), RG-12(레거시 데이터 판매), 식당 모드 주문
- 운영 위반 잔존 10건 정리 여부 — 정책상 위반이나 과거 데이터. 별도 과제로 둘지 사용자 판단 필요
