# PLAN: [Phase 44.1-P1] 매출인식 시점 이동 (deliver → ship)
확정일: 2026-07-08 · SPEC: `spec-recognition-at-ship.md` · 전제 단계(P2 되돌리기의 선행)

## 스코프
- `shipOrder` 에 판매확정(commitSale+createMirror+sale_credit) 추가, `deliverOrder` 는 deliveredAt 로 축소 + 레거시 폴백.
- 스키마/마이그레이션 없음. 신규 DB connect 0(기존 tx 재사용).
- Phase 42/40 회귀 UAT 필수.

## 태스크

### TASK-P1-1 · shipOrder 에 판매확정 이동
`api-ventago/src/app/online-orders/online-orders.service.ts` (shipOrder:802~923)
- runStatusTx sideEffect 안, **assertCreditEligible 통과 + metadata 기록 이후**에 추가:
  1. `await this.stockService.commitSale(order, t);`
  2. `const shipSaldo = Number(order.metadata?.shipSaldo ?? 0);` (이미 계산된 saldo 사용)
     `const isNewMirror = order.mirrorSaleId == null;`
     `const receivedAmount = shipSaldo > 0 ? Number((Number(order.total) - shipSaldo).toFixed(2)) : undefined;`
     `const mirror = await this.mirrorService.createMirror(order, t, receivedAmount);`
     `order.mirrorSaleId = mirror.id;`
  3. `if (shipSaldo > 0 && isNewMirror) { await this.creditLedgerService.appendMovement({ storeId, storeClientId: shipStoreClientId, movementType: 'sale_credit', amount: shipSaldo, saleId: mirror.id, branchId: order.branchId ?? null, userId, note: 'Envío #... despachado con saldo', transaction: t }); }`
     - storeClientId/userId 는 방금 계산/기록한 값 재사용(metadata 왕복 불필요 — 같은 tx 스코프에 변수 존재).
  4. `order.stockReleasedAt = new Date();` `if (shipSaldo <= 0) order.paymentStatus = PAID;`
- deliver 의 기존 코드 블록(960~1003)을 그대로 **이동**(복붙 아님 — 로직 재사용). SERIALIZABLE 유지 위해 shipOrder 의 runStatusTx 에 `Transaction.ISOLATION_LEVELS.SERIALIZABLE` 인자 추가(현재 default) — 재고+회계 동시성 안전.

### TASK-P1-2 · deliverOrder 축소 + 레거시 폴백
동 파일 deliverOrder:931~1022
- sideEffect 를 다음으로 교체:
  ```
  if (order.mirrorSaleId == null) {
    // 레거시 in-flight (구모델 SHIPPED) — 기존 deliver 로직 폴백(commitSale+createMirror+sale_credit)
    ... 기존 blocks 유지 ...
  }
  order.deliveredAt = new Date();
  this.setStageActor(order, 'delivered', userId, userName);
  ```
- 신규 주문(ship 에서 mirror 생성됨)은 폴백 미발동 → deliveredAt 만.
- SERIALIZABLE 유지(폴백이 재고/회계 건드릴 수 있으므로).

### TASK-P1-3 · Phase 40 restaurant-delivery 공유 여부 확인
- `restaurant-delivery.service.ts` 가 `mirrorService.createMirror`/`commitSale` 을 자체 호출하는지 확인.
- 공유(같은 헬퍼 직접 호출)면 무영향(그 흐름은 자기 시점 유지). online-orders 의 ship/deliver 만 이동하므로 restaurant 는 별개. 교차 호출 없으면 회귀 없음 — 확인만.

### TASK-P1-4 · 회귀 UAT (브라우저 + DB 검증)
- 신규 envío 완납: ship → Ventas 에 sale 즉시 노출 + paymentStatus=PAID. deliver → deliveredAt 만.
- 신규 envío 외상(shipSaldo>0): ship → mirror + sale_credit 1건(credito bucket +saldo). deliver → 변화 없음. 중복 sale_credit 0.
- 레거시: (구모델로) SHIPPED 상태 주문을 deliver → 폴백으로 mirror 생성, Ventas 노출.
- cobro: ship 직후 Cobro envío 수금 정상.
- 재고: product.stock 총 1회 차감(생성 시), ship/deliver 무변경.

### TASK-P1-5 · pool/회귀 안전
- ship/deliver 모두 기존 runStatusTx 단일 tx — 신규 connect 0. pg-pool-doctor 확인.
- cancelOrder(SHIPPED/DELIVERED wasCommitted 경로) 무변경 확인 — 소매/식당 회귀 금지.

## 완료 기준
- 신규 주문: 판매확정 = ship, deliver = deliveredAt. 레거시 폴백 동작. Ventas 누락 0.
- Phase 42/40 회귀 UAT PASS. sale_credit 중복/누락 0. 재고 이중차감 0.
- ESLint 0(변경은 백엔드 위주지만 lint 확인). pool 안전.

## 미해결
- 없음(폴백으로 마이그레이션 회피). TASK-P1-3 은 확인 태스크(코드 읽기).
