---
phase: 42-retail-envios-despacho-cobranza
plan: 03
subsystem: online-orders (despacho/외상 deliver attribution)
tags: [RD-1, RD-4, RD-10, RD-12, pitfall-1, sale_credit, regression-gate, migration]
requires:
  - "42-01 (transportes table + use_envios migrations)"
  - "42-02 (online_orders prepared_at/dispatched_at/transporte_id cols + shipOrder records metadata.shipSaldo + CreditLedgerService wired into OnlineOrdersService)"
provides:
  - "deliverOrder conditional paymentStatus (PAID only when shipSaldo<=0)"
  - "deliverOrder sale_credit accrual from metadata.shipSaldo (saleId=mirror.id, same SERIALIZABLE tx)"
  - "createMirror receivedAmount param → payment row = 실수령액 (total − shipSaldo)"
  - "RD-12 regression gate spec (fully-paid deliver = PAID + full payment row + no appendMovement)"
  - "all 3 migrations live on local PG18 dev DB"
affects:
  - "Cuentas por cobrar (shortfall orders now surface as 외상 instead of silent PAID)"
  - "daily revenue reports (mirror unchanged — source=online, idempotent)"
tech-stack:
  added: []
  patterns:
    - "external-tx injection (sale_credit reuses the deliver SERIALIZABLE tx t — no new pool)"
    - "mirror-idempotency-derived double-accrual guard (order.mirrorSaleId==null = new mirror this call)"
key-files:
  created: []
  modified:
    - "api-ventago/src/app/online-orders/online-orders.service.ts (deliverOrder conditional PAID + sale_credit accrual)"
    - "api-ventago/src/app/online-orders/online-order-sales-mirror.service.ts (createMirror receivedAmount → 실수령액 payment row)"
    - "api-ventago/src/app/online-orders/online-orders.service.spec.ts (3 deliver tests: 완납/부족분/멱등)"
decisions:
  - "Double-accrual guard via createMirror idempotency signal: capture isNewMirror = (order.mirrorSaleId == null) BEFORE createMirror; accrue sale_credit only when isNewMirror — re-deliver returns existing mirror and skips accrual."
  - "실수령액 passed as optional 3rd param to createMirror (backward compatible — undefined → totalAmount, no regression for other callers)."
  - "shipSaldoStoreClientId absence at deliver throws BadRequest (data-invariant: ship must have recorded it when shipSaldo>0)."
metrics:
  duration: "~6m"
  tasks: 3
  files-modified: 3
  completed: 2026-06-19T15:57:46Z
---

# Phase 42 Plan 03: Deliver→Mirror Payment Attribution Realignment + sale_credit Accrual Summary

발송 ≠ 종료, 부족분 외상 모델을 deliver 단계에서 완성 — 무조건 PAID 강제를 제거해 부족분(metadata.shipSaldo>0)을 외상으로 남기고, mirror 생성 직후 같은 SERIALIZABLE deliver tx 로 sale_credit 1건(saleId=mirror.id)을 누적하며, 완납 주문의 기존 매출/재고 반영은 100% 보존(RD-12 회귀 게이트). 3개 마이그레이션을 로컬 PG18 dev DB 에 적용.

## What Was Built

### Task 1 — [BLOCKING] 마이그레이션 적용 (RD-1)
세 마이그레이션을 순서대로(42-01 → 42-02 → 42-03) 로컬 PG18 `ventago` DB 에 멱등 적용. 핵심은 42-02 의 online_orders 컬럼(prepared_at/dispatched_at/transporte_id) — 이전엔 count=0 이었음. 적용 후 BLOCKING 스키마 검증 `SCHEMA_OK` 통과(3 online_orders 컬럼 + transportes 테이블 + store_configs.use_envios). 운영 PG10 미적용.

### Task 2 — deliver 결제귀속 재정렬 + sale_credit 누적 (Pitfall 1, RD-4 deliver side, RD-10)
- `deliverOrder` (online-orders.service.ts): 무조건 `order.paymentStatus = PAID` 제거 → `shipSaldo <= 0 ? PAID : order.paymentStatus`(부족분 외상 유지). mirror.id 생성 직후 `shipSaldo>0 && isNewMirror` 일 때만 `creditLedgerService.appendMovement({ movementType:'sale_credit', amount:shipSaldo, saleId:mirror.id, transaction:t })` — 같은 deliver SERIALIZABLE tx, 새 pool 없음.
- `createMirror` (online-order-sales-mirror.service.ts): optional `receivedAmount` 3번째 인자 추가 → sale_payment_methods.amount = 실수령액(total−shipSaldo). 미지정 시 totalAmount(완납 회귀-0). 불변식 SaleSource.ONLINE / SaleActivityType.SALE / online_order_id UNIQUE / dailyNumber 보존.

### Task 3 — RD-12 회귀 게이트 (online-orders 스위트)
spec 에 deliver 3건 추가: (a) 완납 deliver → PAID + 전액 결제행 + appendMovement 미호출, (b) shipSaldo>0 → PAID 강제 금지 + 실수령액 + sale_credit 1건(saleId=mirror.id, 같은 tx), (c) 멱등 재-deliver → sale_credit 미중복. 기존 cancel('devolver'/'favor') 테스트가 nullifyMirror 호출을 이미 단언 → cancel 경로 회귀 보호. 13 tests passed.

## Deviations from Plan

### Out-of-Scope Note (not a deviation — clarification)

**1. `credit` / `box-operation` 별도 spec 파일 부재**
- **Found during:** Task 3
- **Issue:** 플랜의 `npx jest online-orders credit box-operation` 명령은 3개 스위트를 기대하나, 리포지토리에 독립 `credit*/box*` spec 파일이 존재하지 않음 — credit(appendMovement/sale_credit/favor_in)과 box(addOperation/devolver) 통합 검증은 모두 online-orders.service.spec.ts 안에서 mock 으로 커버됨.
- **Resolution:** online-orders 스위트(13 tests)가 credit+box 연동을 단언하므로 RD-12 게이트는 충족. 별도 spec 신설은 범위 외(scope boundary) — 신규 spec 파일을 만들지 않음.

### ESLint (pre-existing 패턴, 범위 외)

수정 파일에 잔존하는 `@typescript-eslint/no-unsafe-*` 에러는 전부 pre-existing 프로젝트 패턴(`order.metadata`/jest `mock.calls` 의 `any`). git stash baseline 으로 확인 시 동일 소스 파일에 이미 24건 존재. 신규 코드(receivedAmount 캐스트, shipSaldo 가드)는 완전 타입드 — 새 에러 0건. 백엔드 빌드는 `nest build`(SWC) 로 eslint 를 실행하지 않으며 TypeScript 컴파일은 클린(tsc --noEmit 무에러). CLAUDE.md 의 "lint 가 빌드를 막음" 규칙은 프론트엔드(ventago-app) 한정.

## Authentication Gates

None.

## Verification Results

- **BLOCKING 스키마 검증:** `SCHEMA_OK` (3 online_orders 컬럼 + transportes + use_envios) — Task 1 게이트 통과
- **jest online-orders:** 13 passed, 1 suite (완납 회귀 + 부족분 sale_credit + 멱등 포함)
- **jest online-orders credit box-operation:** 1 suite matched (credit/box 독립 spec 부재 — online-orders 스위트가 통합 커버)
- **tsc --noEmit:** 수정 파일 무에러
- **acceptance grep:** 무조건 PAID 제거 확인 / `shipSaldo <= 0 ?` 조건형 존재 / `sale_credit` + `saleId: mirrorSale.id` 매칭 / SaleSource.ONLINE + SaleActivityType.SALE 불변식 유지
- **deletion check:** 삭제 파일 0

## Key Decisions

- 중복 누적 가드: createMirror 의 online_order_id UNIQUE 멱등성을 신호로 활용 — createMirror 호출 전 `order.mirrorSaleId == null`(이번 호출 신규 생성)일 때만 sale_credit 누적. 재-deliver 는 기존 mirror 반환 → 누적 skip.
- 실수령액 전달: createMirror 에 optional 3번째 인자로 — 다른 호출자 시그니처 하위호환(undefined → totalAmount).
- shipSaldoStoreClientId 부재 시 BadRequest(데이터 불변식: shipSaldo>0 이면 ship 에서 반드시 기록).

## Commits

- `9dda6e4` (api-ventago submodule): feat(42-03): deliver→mirror 결제귀속 재정렬 + shipSaldo sale_credit 누적 (Pitfall 1 / RD-4/RD-12)

## Self-Check: PASSED

- FOUND: api-ventago/src/app/online-orders/online-orders.service.ts (modified)
- FOUND: api-ventago/src/app/online-orders/online-order-sales-mirror.service.ts (modified)
- FOUND: api-ventago/src/app/online-orders/online-orders.service.spec.ts (modified)
- FOUND commit: 9dda6e4 (api-ventago submodule)
- SCHEMA_OK verified on local PG18 dev DB
