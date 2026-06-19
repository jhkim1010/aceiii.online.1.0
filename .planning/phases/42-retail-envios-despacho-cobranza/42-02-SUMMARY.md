---
phase: 42-retail-envios-despacho-cobranza
plan: 02
subsystem: online-orders (retail despacho / cuentas por cobrar)
tags: [backend, online-orders, transporte, credit, caja, despacho, cobro]
requires:
  - "42-01: TransportesService + Transporte model (transporte.name 미러 소비)"
  - "credit: CreditLedgerService / CreditValidationService / CreditPaymentService (외상 회계)"
  - "box-operation: BoxOperationService (caja movement)"
provides:
  - "OnlineOrder.transporteId / preparedAt / dispatchedAt 컬럼"
  - "shipOrder 완납게이트(metadata.shipSaldo 의도 기록 + 익명 차단 + assertCreditEligible)"
  - "registerCobro (split FIFO payment_in + caja, 열린-caja 가드)"
  - "cancelOrder refundAction(devolver/favor) 분기"
  - "migration 42-02-online-orders-cols.sql (미적용 — 42-03 가 순서대로 로컬 적용)"
affects:
  - "42-03 deliver: metadata.shipSaldo 를 읽어 sale_credit ledger 행 누적 (mirrorSaleId 존재 시점)"
  - "42-04 게이트웨이/cuentas-por-cobrar 라우트"
  - "42-05~08 프론트 (Despacho 칸반 / Cuentas por cobrar / 타임라인 / CobroModal)"
tech-stack:
  added: []
  patterns:
    - "완납 게이트: ship 에서 외상 axis 결정(shipSaldo 의도) — sale_credit ledger 행은 deliver(42-03) 이연 (mirrorSaleId DB CHECK 회피)"
    - "registerPayment 자체 SERIALIZABLE tx → 절대 중첩 안 함 (Pitfall 3)"
    - "appendMovement 는 항상 외부 t 주입 (cancel/favor 경로)"
    - "열린 caja(closingTime=null) 미오픈 시 cobro/devolver 엄격 차단 (Phase 40 parity, Pitfall 4)"
    - "transporteId plain INTEGER (no @ForeignKey) — boot-hang guard"
key-files:
  created:
    - api-ventago/migrations/42-02-online-orders-cols.sql
    - api-ventago/src/app/online-orders/dto/cobro-online-order.dto.ts
    - api-ventago/src/app/online-orders/dto/cancel-online-order.dto.ts
    - api-ventago/src/app/online-orders/online-orders.service.spec.ts
  modified:
    - api-ventago/src/app/online-orders/online-order.model.ts
    - api-ventago/src/app/online-orders/dto/ship-online-order.dto.ts
    - api-ventago/src/app/online-orders/online-orders.service.ts
    - api-ventago/src/app/online-orders/online-orders.controller.ts
    - api-ventago/src/app/online-orders/online-orders.module.ts
    - api-ventago/src/app/transportes/transportes.service.ts
decisions:
  - "ship 은 metadata.shipSaldo 에 외상 의도만 기록 — sale_credit ledger 행은 deliver(42-03)에서 mirrorSaleId 기준 누적 (RESOLVED Pitfall-1 seam, RESEARCH Open Q1). ship 에서 appendMovement(sale_credit) 호출 안 함."
  - "assertCreditEligible 실제 시그니처는 positional (storeClientId, storeId, requestedAmount, transaction) — plan interface 의 object 형이 아님. 실제 코드에 맞춤."
  - "received(기수금) 캐노니컬 소스 부재 → computeReceivedSoFar: metadata.received 우선, 없으면 paymentStatus='paid'→total / else 0 (보수적)."
  - "registerCobro 헤더 paymentMethodId 는 split 첫 줄 사용(registerPayment 헤더 1개 한계) — 자금 출처 정확 분개는 줄별 caja addOperation 으로."
  - "ship DTO carrier 도 @IsOptional 화 (transporteId 오면 transporte.name 미러) — 레거시 online 발송(carrier 직접) 호환(RD-12)."
  - "transportes.findScoped private→public (shipOrder 가 transporte.name 소비)."
  - "OnlineOrdersModule 이 CreditModule/BoxOperationModule/TransportesModule import — 싱글턴 재사용(새 풀 X). CashRegister/StoreClient forFeature 등록."
metrics:
  duration: ~9min
  completed: 2026-06-19
  tasks: 4
  files: 10
---

# Phase 42 Plan 02: OnlineOrder Despacho + 완납게이트 + Cobro + Cancel Favor Summary

OnlineOrder 백본을 의류 배송 통제용으로 보강: transporteId + 단계 타임스탬프 추가, ship 에 완납 게이트(saldo>0 → metadata.shipSaldo 의도 기록 + 익명 차단 + assertCreditEligible, 완납 → 무기록), 부분/split cobro(FIFO payment_in + caja, 열린-caja 가드), cancel→Devolver/Favor 분기. 모든 외상/caja 회계는 기존 싱글턴 서비스 경유(새 풀 0).

## What Was Built

### Task 1 — Migration + 모델 컬럼 + ship DTO (commit 6179da1)
- `42-02-online-orders-cols.sql`: `prepared_at` / `dispatched_at` / `transporte_id`(FK transportes ON DELETE SET NULL) + index. 전부 NULLABLE → 기존 행 영향 0 (RD-12). **미적용** — 42-03 BLOCKING task 가 42-01 마이그레이션과 순서 맞춰 로컬 적용.
- `online-order.model.ts`: `preparedAt` / `dispatchedAt` / `transporteId`. transporteId 는 boot-hang guard 로 plain INTEGER(@ForeignKey 미사용, 데코레이터 정확히 3개 유지: Store/Branch/PaymentMethod).
- `ship-online-order.dto.ts`: `transporteId` @IsOptional @IsInt @IsPositive; carrier 도 optional 화.

### Task 2 — prepareOrder + shipOrder 완납게이트 (TDD, commit fcc6d74)
- `prepareOrder`: side-effect 로 `preparedAt = new Date()` → "Listo p/ despacho" 파생(preparedAt!=null && dispatchedAt==null, D-03, 신규 enum 없음).
- `shipOrder(storeId,id,dto,userId)`: transporte 해석(findScoped) → `shippingCarrier=transporte.name`(D-05) + `transporteId` + `trackingCode` + `dispatchedAt`. 그 후 완납 게이트:
  - saldo = total − computeReceivedSoFar(order)
  - saldo<=0 → 무기록(완납, 기존 shipSaldo 흔적 제거 멱등)
  - saldo>0 → 익명(clientId null) `BadRequestException` 차단(Pitfall 2) → assertCreditEligible(storeClientId, storeId, saldo, t) (동일 tx) → `metadata.shipSaldo / shipSaldoStoreClientId / shipSaldoUserId` 의도만 기록. **appendMovement / sale_credit 행 없음** (deliver/42-03 이연).

### Task 3 — registerCobro + cancel Devolver/Favor (TDD, commit fcc6d74)
- `cobro-online-order.dto.ts`: `payments: PaymentLineDto[]`(paymentMethodId/amount/optionId/bankName/chequeNumber, @ValidateNested @Type) + receiptNo?.
- `cancel-online-order.dto.ts`: `refundAction?: 'devolver'|'favor'`.
- `registerCobro(storeId,orderId,dto,userId)`: 열린 caja 확인(미오픈→차단 Pitfall 4) → 식별고객 해석 → `registerPayment(credit_payment, 합계)` **자체 tx(중첩 X, Pitfall 3)** → 줄별 `addOperation(income/cobro)` → metadata.timeline_notes/received 누적.
- `cancelOrder(...,dto,userId)`: 기존 reverseSale + nullifyMirror 경로 보존(RD-12). wasCommitted+paid>0 시 `devolver`=caja 역 movement(amount 음수) / `favor`=appendMovement favor_in(saleId=mirrorSaleId, 외부 t).

### Task 4 — 컨트롤러/모듈 wiring (commit 9a0d143)
- controller: `POST :id/cobro`(storeId+userId server-derived, IDOR-safe), ship→user.id 전달, cancel→CancelOnlineOrderDto+user.id.
- module: TransportesModule + CreditModule + BoxOperationModule import(싱글턴 재사용) + forFeature CashRegister/StoreClient.

## Verification Results

- `npx jest online-orders.service` → **10/10 PASS** (RD-3/4/6/7)
- `npx jest transportes.service` → 5/5 PASS (findScoped public 화 회귀 0)
- `npx tsc --noEmit` → online-orders 영역 신규 에러 **0** (총 2건은 pre-existing mp-webhook spec, out-of-scope)
- appendMovement 는 cancel(favor) 경로에만 존재 — shipOrder 에 없음 (HIGHEST-RISK CONSTRAINT 준수)
- deliver→mirror 경로 / paymentStatus 무변경 (42-03 영역 미침범)

## Deviations from Plan

### Auto-fixed / 조정 사항

**1. [Rule 3 - Blocking] assertCreditEligible / registerPayment 실제 시그니처 적용**
- Found during: Task 2/3
- Issue: PLAN interface 블록은 assertCreditEligible 를 object 인자로 기술했으나 실제 코드는 positional `(storeClientId, storeId, requestedAmount, transaction)`.
- Fix: 실제 시그니처에 맞춰 호출. registerPayment 는 plan 과 동일(object). 별도 파일 변경 없음.
- Commit: fcc6d74

**2. [Rule 3 - Blocking] transportes.findScoped private→public**
- Issue: plan 이 shipOrder 에서 `TransportesService.findScoped` 사용을 지시하나 해당 메서드가 private 였음.
- Fix: public 으로 노출(주석 갱신). 기존 update() 내부 호출 영향 없음.
- Files: transportes.service.ts · Commit: fcc6d74

**3. [Rule 3 - Blocking] api-ventago 는 git 서브모듈**
- 커밋은 서브모듈(feat/phase42-wave1) 내부에서 수행. 루트 superproject 의 서브모듈 포인터 갱신은 본 wave 범위 밖(상위 오케스트레이터/푸시 단계 담당).

**4. [조정] ship DTO carrier optional 화 + cobro 헤더 결제수단**
- carrier 를 @IsOptional 로 바꿔 transporte.name 미러 fallback 허용(레거시 호환). registerPayment 헤더는 split 첫 줄 paymentMethodId 사용(헤더 1개 한계), 자금 분개는 줄별 caja movement.

### Out-of-scope (deferred, NOT fixed)
- `mp-webhook.service.spec.ts:72,178` TS2554 (Phase 29) — pre-existing, deferred-items.md 기록.

## Authentication Gates
None.

## Threat Surface
계획된 threat register(T-42-04~09) 범위 내. 신규 라우트 `POST :id/cobro` 는 @Auth() + storeId/userId server-derived(IDOR-safe, T-42-07). 신규 위협 표면 없음.

## Notes for 42-03 (deliver)
- ship 은 `metadata.shipSaldo`(+shipSaldoStoreClientId/shipSaldoUserId)에 외상 **의도**만 기록한다.
- **sale_credit ledger 행은 deliver(42-03)에서** `metadata.shipSaldo` 를 읽어 `appendMovement({movementType:'sale_credit', saleId: mirrorSale.id, ...})` 로 1회 누적해야 한다(mirrorSaleId 가 deliver 의 createMirror 이후 존재 → sale_credit DB CHECK 충족). 이것이 RESOLVED Pitfall-1 seam(RESEARCH Open Q1) — 미해결 결정이 아님.
- deliver 의 paymentStatus 재정렬도 42-03 영역. 본 plan 은 deliver 를 건드리지 않았다.

## Self-Check: PASSED
- 모든 생성 파일 존재(migration, cobro/cancel DTO, spec, SUMMARY, deferred-items).
- 모든 커밋 존재(서브모듈 feat/phase42-wave1): 6179da1 / fcc6d74 / 9a0d143.
