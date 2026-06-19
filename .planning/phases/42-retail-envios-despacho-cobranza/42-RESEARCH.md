# Phase 42: Retail Delivery — Despacho / Cuentas por cobrar / Historial - Research

**Researched:** 2026-06-19
**Domain:** OnlineOrder 백본 재사용 + 식당식(Phase 40) 통제 UX 이식 + CreditLedger 외상 정산축
**Confidence:** HIGH (모든 핵심 주장이 코드/스키마로 검증됨)

<user_constraints>
## User Constraints (from 42-CONTEXT.md)

### Locked Decisions (D-01 ~ D-12)
- **D-01 (Sale mirror 재사용):** delivery 통제 대상 = 기존 OnlineOrder. delivered 시 자동 생성되는 sales mirror(`online-order-sales-mirror.service.ts`, source=`online`) 흐름 그대로 → 매출·재고 보고서 자동 반영. **신규 SaleSource 값 만들지 않음.**
- **D-02 (단계별 타임스탬프):** OnlineOrder 모델에 없는 타임스탬프만 마이그레이션 추가. 추측 금지, db-schema-tables.md 대조 (→ research 결과 아래).
- **D-03 (`Listo p/ despacho` 파생):** OnlineOrderStatus enum 에 `Listo` 가 별도로 없으면 `preparedAt` 세팅+미발송으로 파생 또는 신규 `READY` 추가. enum↔CHECK 동기화 선례 따라 plan 에서 확정.
- **D-04 (Transporte 스코프):** `Transporte = { id, storeId, name, isActive, createdAt }`. store_id FK, isActive=false 면 드롭다운 제외(이력 보존). Phase 40 Repartidor 패턴 복제.
- **D-05 (OnlineOrder 연동):** OnlineOrder 에 `transporteId`(FK→transportes, nullable) 추가. 기존 `shippingCarrier`(VARCHAR) 텍스트는 transporte.name 으로 미러(하위호환).
- **D-06 (외상 발송 게이트):** 발송 시 잔액>0 이면 "외상으로 발송" 경고 → 확인 시 차액 1건 CreditLedger `sale_credit`(bucket=credito,+) + StoreClient.balance 증가. saleId/venta 링크 필수. 완납 건은 외상 미발생.
- **D-07 (cobro = 외상 상환):** 외상 잔액 차감 = CreditLedger `payment_in`(bucket=credito,−,FIFO,parentLedgerId→sale_credit). 신규 결제(미적립)는 SalePaymentMethod 직접. cobro 는 어느 상태에서나 가능.
- **D-08 (취소 후 환불 vs favor):** ① Devolver dinero: 환불 → caja 역movement. ② Pasar a favor: CreditLedger `favor_in`(bucket=favor,+) + StoreClient.favorBalance → `favor_apply`. 신규 movement_type 금지.
- **D-09 (cobro 모달):** 기존 `PaymentSummaryModal`(homes/ProductList) split·다중수단 로직 재사용 검토 우선. 재사용 범위 vs delivery 전용 래퍼 판단 (→ research 결과 아래). 수단=Efectivo·Transferencia·Cheque·Tarjeta·QR.
- **D-10 (cobro → caja movement):** 각 cobro(신규 결제분) → box movement. `box-operation.service.addOperation` 재사용(Phase 40 D-05). closingTime=null cashRegister.
- **D-11 (실시간 채널):** Despacho 칸반 = Socket.io push(폴링 아님). Phase 40 DeliveryBoard 게이트웨이/room 패턴 재사용 또는 동형. 카드 단위 payload emit.
- **D-12 (3탭 격상):** 기존 Ventas Online 페이지를 (1) Despacho 칸반(마스터-디테일≈75%+타임라인≈25%) (2) Cuentas por cobrar (3) Historial 로 재구성. 신규 페이지 아님.

### Claude's Discretion
- 칸반 컴포넌트 이식 방식(복제/일반화/공유추출) — plan 단계. **단 식당/의류 화면 통합은 범위 밖.**
- 상태머신 정확 명칭 매핑(enum↔CHECK 동기화) — plan 단계(D-03 연계).
- 타임라인 데이터 병합 쿼리/뷰 구성 — plan 단계. Nota 저장소(OnlineOrder.notes 활용 또는 신규) research 확인 (→ 아래).
- `+Nuevo envío` 입력 콘솔(Phase 40 Nuevo pedido 패턴 이식) + nueva-venta "envío 필요" 유입 연결 — plan 단계.

### Deferred Ideas (OUT OF SCOPE)
- 반품(devolución) — nueva-venta 메인 화면에서 처리(보드 밖).
- 고객용 공개 주문 추적 링크.
- 택배사 L2 API 양방향 연동 — 운송장 수동 입력.
- 라이더/배송기사 모바일 앱·GPS.
- 식당 모드와의 화면 통합 — 별도 도메인 유지.
</user_constraints>

<phase_requirements>
## Phase Requirements (de-facto — 설계 §2 Success Criteria + D-01~D-12)

REQUIREMENTS.md 에 lock 된 ID 없음(ROADMAP: "SPEC 단계에서 lock"). 설계 합의 성공기준을 de-facto 요구로 사용:

| 약식 ID | 설명 | Research Support |
|----|-------------|------------------|
| RD-1 | Transporte 관리 목록(CRUD, isActive 토글), use_envios 게이팅 | Phase 40 repartidores 모델/서비스/컨트롤러/카드 1:1 복제. migration 40-01 패턴 |
| RD-2 | Despacho 칸반(Nuevo→Preparando→Listo→En tránsito→Entregado) 마스터-디테일 | DeliveryBoard.tsx 칸반 구조 + OnlineOrderStatus 매핑(D-03 파생) |
| RD-3 | 발송 시 transporte 선택+운송장, 완납 게이트(잔액>0 경고→외상) | shipOrder + ShipOnlineOrderDto 확장 + CreditLedger sale_credit |
| RD-4 | 부족분 발송 시 외상 적립(sale_credit + StoreClient.balance) | credit-ledger.service.appendMovement, credit-validation.assertCreditEligible |
| RD-5 | cobro(부분/split) 어느 상태든 등록, 외상 차감 payment_in FIFO + caja movement | credit-payment.service.registerPayment + box-operation.addOperation |
| RD-6 | 취소(결제 후) 환불 vs favor 분기 | nullifyMirror + favor_in(appendMovement) |
| RD-7 | Cuentas por cobrar 탭(saldo>0 집계 + 고객별 잔액 + cobro) | StoreClient.balance + credit-report.service |
| RD-8 | Historial 탭(종료 건 — DELIVERED 완납 + CANCELLED) | useDeliveryHistory 패턴 |
| RD-9 | 실시간 보드 Socket.io push | RestaurantDeliveryGateway 패턴(신규 게이트웨이 or 재사용) |
| RD-10 | delivery Sale → 매출/재고 보고서 자동 반영(source=online) | createMirror(이미 동작 — activity_type='sale') |
| RD-11 | Ticket/Recibo 감열 출력 | print.service.emitPrintTemp 재사용 |
| RD-12 | 소매 무회귀 (online-orders 기존 흐름 보존) | runStatusTx 분기 — 아래 회귀 점검 참조 |
</phase_requirements>

## Summary

이 phase 의 본질은 **신규 도메인 구축이 아니라 기존 OnlineOrder 백본에 식당식 통제 UX(칸반·타임라인·외상정산)를 얹는 것**이다. 데이터 백본은 이미 적합하고 검증됨(`online_orders` 테이블 + sales mirror + Credit 모듈). 따라서 신규 코드는 (a) `Transporte` 엔티티 1개, (b) OnlineOrder 보강 컬럼(transporteId + 누락 타임스탬프), (c) `use_envios` 플래그, (d) Despacho/cobro/취소 서비스 메서드, (e) 프론트 3탭 + 칸반 + cobro 래퍼 모달 로 최소화된다.

**가장 중요한 아키텍처 발견(plan 에서 반드시 반영):** 현재 OnlineOrder 의 sales mirror 는 **DELIVERED 시점에 일괄 생성 + `paymentStatus=PAID` 무조건 설정**된다(`deliverOrder` L336-363). 이는 "완납 후 발송" 모델과 충돌한다. Phase 42 의 "부족분 발송→외상" 게이트(D-06)는 **SHIP 시점에 결제상태/외상을 결정**해야 하므로, mirror 생성 시점과 결제 귀속 로직을 재정렬해야 한다. **이것이 이 phase 최대의 통합 리스크이자 회귀 위험 지점이다.**

**Primary recommendation:** Phase 40 의 "매출 귀속 시점 vs 수금축 분리" 패턴(D-01)을 그대로 차용하라 — **매출/재고는 DELIVERED 에 인식(기존 mirror 유지), 외상(수금축)은 SHIP 시점 잔액으로 별도 결정**. mirror 의 `paymentStatus=PAID` 강제 설정을 "잔액 0 이면 PAID, 잔액>0 이면 외상 sale_credit + paymentStatus 유지" 로 분기. 단 이 변경은 소매 online-orders 의 기존 deliver 흐름을 건드리므로 **회귀 검증 필수**.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Despacho 상태 전이(ship/deliver/cancel) | API / Backend (online-orders.service) | DB (SERIALIZABLE tx) | 재고+회계+외상 단일 트랜잭션 불변식. 클라이언트는 명령만 |
| 외상 적립/상환(sale_credit/payment_in/favor) | API / Backend (credit 모듈) | DB (store_clients FOR UPDATE) | append-only 원장 + SERIALIZABLE — 절대 프론트 계산 금지 |
| cobro → caja movement | API / Backend (box-operation) | DB | control-de-caja 마감 일치, closingTime=null 가드 |
| 실시간 보드 push | API / Backend (Socket.io gateway) | Browser (socket.io-client) | 카드 payload emit, branch room |
| 칸반/타임라인/모달 렌더 | Browser (React/MUI) | Frontend Server (Next pages) | next/dynamic ssr:false 코드스플리팅 |
| 보드/이력 데이터 fetch | Browser (SWR hooks) | API | 5분 dedup, 폴링 아님(실시간은 socket) |
| Transporte CRUD | API / Backend | DB | store 단위 멀티테넌트 |
| use_envios 게이팅 | Browser (config context) + API | DB (store_configs) | UI 노출 + 백엔드 엔드포인트 가드 |

## Standard Stack

이 프로젝트는 확립된 모노레포 스택을 사용 — 신규 라이브러리 도입 불필요. 모두 기존 검증된 버전 재사용.

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| @nestjs/core | ^11.0.1 | 백엔드 프레임워크 | [VERIFIED: api-ventago/package.json] 프로젝트 표준 |
| sequelize-typescript | ^2.1.6 | ORM (underscored:true) | [VERIFIED: package.json] snake_case 자동매핑 |
| socket.io | ^4.8.1 | 실시간 게이트웨이 | [VERIFIED: package.json] Phase 40 게이트웨이 동일 |
| next | 13.3.2 | 프론트(Pages Router) | [VERIFIED: ventago-app/package.json] |
| @mui/material | 5.12.2 | UI | [VERIFIED] 다크 네이비+골드 테마 |
| socket.io-client | ^4.8.3 | 보드 클라이언트 | [VERIFIED] DeliveryBoard.tsx 사용 |
| swr | ^2.4.1 | 데이터 캐시 | [VERIFIED] useDeliveryBoard/useDeliveryHistory 선례 |

### Supporting (전부 기존 in-house 모듈 — import only)
| 모듈 | Purpose | When to Use |
|---------|---------|-------------|
| CreditLedgerService | append-only 외상/favor 원장 | D-06/D-08 외상 적립·favor |
| CreditPaymentService | FIFO 외상 입금 | D-07 cobro 상환 |
| CreditValidationService | 한도/document 검증 | D-06 외상 발송 사전검증 |
| BoxOperationService | caja movement | D-10 cobro→caja |
| OnlineOrderSalesMirrorService | sales mirror 생성/역분개 | D-01 매출/재고 |
| print.service emitPrintTemp | 감열 출력 | Ticket/Recibo |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| OnlineOrder 백본(A안) | 신규 retail-delivery 레이어(B안) | ❌ 설계 거부 — online-orders 기능 중복, 배송 시스템 2개 공존 |
| 기존 /restaurant 게이트웨이 재사용 | 신규 /envios 게이트웨이 | plan 결정 — 아래 D-11 분석 참조 |

**Installation:** 신규 npm 패키지 없음.

**Version verification:** [VERIFIED] 위 버전은 모두 `package.json` 직접 확인 (2026-06-19). 신규 의존성 추가 불필요하므로 registry 조회 불필요.

## Architecture Patterns

### System Architecture Diagram

```
                       ┌──────────────────────────────────────────────┐
                       │  Ventas Online 페이지 (3탭 — D-12)             │
                       │  Despacho 칸반 │ Cuentas x cobrar │ Historial │
                       └───────┬──────────────┬───────────────┬────────┘
        SWR fetch (board)      │              │ SWR (saldo>0) │ SWR (종료)
        socket push (card) ◄───┤              │               │
                               ▼              ▼               ▼
                   ┌───────────────────────────────────────────────┐
                   │  apiConnector (get/post/put/remove)            │
                   └───────┬───────────────────────────────────────┘
                           │ HTTP
        ┌──────────────────▼───────────────────────────────────────┐
        │ online-orders.controller  (+ transportes.controller 신규)  │
        └──────────────────┬───────────────────────────────────────┘
                           ▼
   ┌────────────────────────────────────────────────────────────────┐
   │ online-orders.service.runStatusTx (SERIALIZABLE 단일 트랜잭션)   │
   │                                                                  │
   │  confirm → prepare → ship ───────────► deliver ──────► (Entregado)│
   │                         │                  │                      │
   │            잔액>0? ─yes─►│                  │                      │
   │                         ▼                  ▼                      │
   │            CreditLedger.appendMovement  SalesMirror.createMirror  │
   │            (sale_credit, bucket=credito) (source=online, PAID)    │
   │                         │                  │                      │
   │                         ▼                  ▼                      │
   │            StoreClient.balance↑     sales + sale_items (재고/매출) │
   │                                                                  │
   │  cobro(어느 상태든) ──► CreditPaymentService.registerPayment      │
   │                         (payment_in FIFO) + box-op.addOperation   │
   │                                                                  │
   │  cancel(결제후) ──► nullifyMirror  ┬─ Devolver: caja 역movement   │
   │                                    └─ Favor: appendMovement(favor_in)│
   └──────────────────────────────┬───────────────────────────────────┘
                                  │ commit 후
                                  ▼
                   Socket.io gateway.emitXxxUpdated(branchId, card)
                                  │
                                  ▼  to(`branch:{id}`)
                           브라우저 보드 카드 병합
```

핵심 데이터 흐름: 주문 입력 → confirm/prepare(hold 유지) → **ship(transporte+운송장, 잔액>0 시 외상 적립)** → deliver(mirror=매출/재고 인식) → 잔액 잔류 시 Cuentas por cobrar → cobro(payment_in+caja) → 잔액 0 종료.

### Recommended Project Structure

```
api-ventago/src/app/
├── transportes/                    # 신규 — repartidores 1:1 복제
│   ├── transportes.model.ts        # { id, storeId, name, isActive }
│   ├── transportes.service.ts      # findByStore(activeOnly), CRUD
│   ├── transportes.controller.ts
│   ├── transportes.module.ts
│   └── dto/transporte.dto.ts
├── online-orders/                  # 보강 (확장 only)
│   ├── online-order.model.ts       # + transporteId, + preparedAt/dispatchedAt
│   ├── online-orders.service.ts    # ship 외상게이트 + cobro + cancel분기 + emit
│   ├── online-orders.controller.ts # + cobro/cancel-favor 라우트
│   ├── dto/ship-online-order.dto.ts# + transporteId
│   └── online-orders-board.gateway.ts  # 신규 OR /restaurant 재사용 (D-11)
api-ventago/migrations/
├── 42-01-transportes.sql           # 40-01 패턴
├── 42-02-online-orders-cols.sql    # ALTER ADD COLUMN IF NOT EXISTS
└── 42-03-store-config-use-envios.sql  # 39-03 패턴

ventago-app/src/
├── views/ventas-online/
│   ├── VentasOnlineView.tsx        # 3탭 격상(기존 envios/devoluciones → Despacho/CxC/Historial)
│   ├── DespachoBoard.tsx           # 신규 — DeliveryBoard 칸반 이식(의류)
│   ├── CuentasPorCobrarTab.tsx     # 신규
│   ├── HistorialTab.tsx            # 신규
│   └── components/
│       ├── EnvioTimeline.tsx       # 타임라인 패널(우 25%)
│       ├── CobroModal.tsx          # PaymentSummaryModal 래퍼(D-09)
│       └── NuevoEnvioModal.tsx     # NuevoPedidoModal 이식
├── hooks/api/
│   ├── useDespachoBoard.ts         # useDeliveryBoard 패턴
│   ├── useCuentasPorCobrar.ts
│   └── useTransportes.ts           # useRepartidores 패턴
└── configs/envioLabels.ts          # deliveryLabels 패턴
```

### Pattern 1: 상태전이 단일 트랜잭션 + side-effect 콜백
**What:** `runStatusTx(storeId, id, fromStatuses[], toStatus, sideEffect, isolationLevel)` 가 lock → 검증 → side-effect → status 저장 → commit 을 단일 트랜잭션으로 처리.
**When to use:** 모든 Despacho 상태 전이. 신규 ship 외상 게이트는 ship 의 sideEffect 콜백 안에 넣는다.
```typescript
// Source: api-ventago/src/app/online-orders/online-orders.service.ts:303-328, 801-858
// ship 외상 게이트 확장 예 (plan 에서 구현)
return this.runStatusTx(
  storeId, id,
  [OnlineOrderStatus.CONFIRMED, OnlineOrderStatus.PREPARING],
  OnlineOrderStatus.SHIPPED,
  async (order, t) => {
    order.transporteId = dto.transporteId;
    order.shippingCarrier = transporte.name;   // 하위호환 미러(D-05)
    order.trackingCode = dto.trackingCode;
    order.dispatchedAt = new Date();           // 신규 타임스탬프
    // 완납 게이트(D-06): 잔액 = total − 기수령. >0 이면 외상 sale_credit
    // ※ mirror/매출 인식은 deliver 에 그대로 — 여기선 외상축만 결정
  },
  Transaction.ISOLATION_LEVELS.SERIALIZABLE,
);
```

### Pattern 2: CreditLedger append-only — 외부 트랜잭션 주입 필수
**What:** `appendMovement(input)` 은 호출자가 연 트랜잭션을 **필수 인자로** 받는다(내부에서 새 tx 열지 않음). store_clients 를 FOR UPDATE 잠금하고 bucket 갱신.
**When to use:** D-06 sale_credit, D-08 favor_in.
```typescript
// Source: api-ventago/src/app/credit/services/credit-ledger.service.ts:91
await this.creditLedgerService.appendMovement({
  storeId, storeClientId,
  movementType: 'sale_credit',     // bucket=credito, +
  amount: saldoPendiente,
  saleId: mirrorSale.id,           // venta 링크 필수 (DB CHECK)
  branchId, userId,
  dueDate: null,                   // 만기일 옵션
  note: `Envío #${order.orderNumber} despachado con saldo`,
  transaction: t,                  // ★ 외부 tx 주입
});
```

### Pattern 3: CreditPayment FIFO — 자체 트랜잭션 보유
**What:** `registerPayment(dto)` 은 **자체 SERIALIZABLE 트랜잭션을 연다**(Pattern 2 와 다름). FIFO 로 sale_credit 차감 → payment_in, 잔여 → favor_in.
**When to use:** D-07 cobro 가 외상 잔액 차감 시.
```typescript
// Source: api-ventago/src/app/credit/services/credit-payment.service.ts:70-138
// 주의: receiptNo 필수, paymentMethodId 필수. 자체 tx 이므로 online-orders tx 와 분리 호출.
await this.creditPaymentService.registerPayment({
  storeId, storeClientId,
  paymentKind: 'credit_payment',   // FIFO 외상 상환
  totalAmount: cobroAmount,
  paymentMethodId, optionId,
  receiptNo, branchId, userId, note,
});
```

### Pattern 4: Socket.io 카드 payload emit (commit 후)
**What:** 상태 전이 commit **후** `emitXxxUpdated(branchId, card)` 로 변경된 카드만 push. 전체 재조회 회피(pool 절약, 300ms).
```typescript
// Source: api-ventago/src/app/restaurant-delivery/restaurant-delivery.gateway.ts:92
// + restaurant-delivery.service.ts:180 (commit 후 emit)
this.gateway.emitEnvioUpdated(order.branchId, this.toCard(order));
```

### Anti-Patterns to Avoid
- **mirror 의 `paymentStatus=PAID` 무조건 설정을 그대로 둠:** 부족분 발송 시 외상인데 PAID 로 표시되면 Cuentas por cobrar 가 비어버림. deliver 의 L355 분기 필수.
- **CreditLedger 행 UPDATE/DELETE:** append-only 위반. 정정은 반대 movement 만.
- **appendMovement 를 트랜잭션 없이 호출:** BadRequestException 던짐(L109).
- **registerPayment 를 online-orders 트랜잭션 안에서 호출:** 자체 SERIALIZABLE tx 를 열므로 중첩 → 데드락/에러. commit 전후 순서 분리.
- **익명 OnlineOrder(clientId=null)에 외상 적립:** assertCreditEligible 이 store_client + document(DNI/CUIT) 요구 → 실패. 아래 Open Question 참조.
- **보드 갱신을 폴링으로:** D-11 위반. socket push 만.
- **식당/의류 화면 통합:** 명시적 범위 밖.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| 외상 잔액 계산/차감 | 수동 balance 산술 | CreditLedgerService / CreditPaymentService | append-only 불변식 + FOR UPDATE race 방지 + FIFO + bucket_after cache |
| 외상 한도 검증 | 수동 limit 비교 | CreditValidationService.assertCreditEligible | document 검증 + credit_status(blocked/hold) + 한도 race lock |
| 매출/재고 반영 | delivery 전용 sale 생성 | OnlineOrderSalesMirrorService.createMirror | 멱등성(UNIQUE online_order_id) + dailyNumber + sale_items + 보고서 자동 |
| 취소 회계 역분개 | 수동 음수 sale | nullifyMirror | NULLIFIED 마킹 + 양방향 링크 + 부분환불 |
| caja movement | 직접 box_operations INSERT | BoxOperationService.addOperation | closingTime=null cashRegister 가드 + control-de-caja 일치 |
| 실시간 보드 | 폴링/수동 socket | RestaurantDeliveryGateway 패턴 | JWT 검증 + branch room IDOR 가드 + 카드 emit |
| Transporte CRUD | 처음부터 | repartidores 모델/서비스/카드 복제 | isActive 소프트토글 + store 격리 패턴 검증됨 |

**Key insight:** 이 도메인은 **회계 불변식(외상·매출·caja)이 핵심**이다. 수동 계산은 거의 항상 race condition·이중계상·보고서 누락을 만든다. 기존 서비스는 SERIALIZABLE + FOR UPDATE 로 이미 검증됨 — 전부 경유하라.

## Runtime State Inventory

> Phase 42 는 신규 엔티티 + 컬럼 추가(greenfield+augment) 이며 rename/migration 이 아니므로 대부분 해당 없음. 단 데이터 정합성 관점에서 명시:

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | 기존 online_orders 행은 transporte_id=NULL, prepared_at/dispatched_at=NULL 로 백필됨(nullable). shipping_carrier 텍스트 그대로 유지 | 마이그레이션 nullable ADD — 기존 행 영향 0 |
| Live service config | use_envios 는 store_configs 신규 컬럼 DEFAULT false → 기존 매장 자동 OFF | 마이그레이션만, 활성화는 매장별 수동 |
| OS-registered state | None — 검증: 이 phase 는 OS 등록 상태 없음 |  |
| Secrets/env vars | None — JWT_SECRET_KEY 기존 재사용(게이트웨이). 신규 secret 없음 |  |
| Build artifacts | None — npm 신규 패키지 없음. 서브모듈 재빌드만(api-ventago/ventago-app) |  |

## Common Pitfalls

### Pitfall 1: mirror 의 결제 귀속 시점 불일치 (★최대 리스크)
**What goes wrong:** 현재 `deliverOrder` 가 DELIVERED 에서 mirror 생성 + `paymentStatus=PAID` 무조건 설정. 부족분 발송 건이 deliver 되면 외상인데 PAID 로 덮여 Cuentas por cobrar 에 안 뜸.
**Why it happens:** Phase 27-28 online-orders 는 "배달=완납" 가정으로 설계됨. Phase 42 는 "발송≠종료, 부족분 외상" 모델.
**How to avoid:** Phase 40 D-01 패턴 차용 — **매출/재고는 deliver 에 인식(mirror 유지), 외상은 ship 잔액으로 별도 결정**. deliver 의 `paymentStatus=PAID`(L355)를 "잔액 0 이면 PAID, 아니면 미러 paymentStatus 유지" 로 분기. mirror.createMirror 의 sale_payment_methods 생성(L148)도 실수령액만 반영하도록 검토.
**Warning signs:** 부족분 발송 후 deliver 했는데 Cuentas por cobrar 가 비어 있음; StoreClient.balance 와 mirror sale_payment_methods 합계 불일치.

### Pitfall 2: 익명 주문 외상 불가
**What goes wrong:** OnlineOrder 는 clientId=NULL(익명, client_name 스냅샷) 허용. assertCreditEligible 은 store_client + globalClient.document(DNI/CUIT) 필수.
**Why it happens:** 외상은 회수 대상이라 식별된 고객 필요.
**How to avoid:** 외상 발송(D-06) 시 `clientId != null` 강제 — 익명 주문은 완납만 허용하거나 발송 전 고객 등록 요구. plan 에서 UX 결정.
**Warning signs:** "CRÉDITO requiere DNI/CUIT" BadRequestException.

### Pitfall 3: registerPayment 트랜잭션 중첩
**What goes wrong:** cobro 를 online-orders runStatusTx 안에서 registerPayment 호출 시 자체 SERIALIZABLE tx 중첩 → 데드락/SAVEPOINT 충돌.
**How to avoid:** cobro 는 상태전이와 분리된 독립 작업으로 설계(어느 상태든 가능 — D-07). registerPayment 호출 후 별도로 order 메타(타임라인 이벤트) 갱신.
**Warning signs:** 40001 serialization_failure, deadlock detected.

### Pitfall 4: caja 미오픈 시 cobro 차단 vs 진행
**What goes wrong:** Phase 40 D-06 은 정산 시 closingTime=null cashRegister 없으면 **차단**(엄격). 신규 결제분(cobro)은 caja 입금 필요.
**How to avoid:** D-10 — 신규 결제분 cobro 는 열린 caja 필수(addOperation). 외상 상환분(payment_in)도 caja 동반 movement 매핑은 plan 확정. 일관성 위해 Phase 40 의 "Abrí la caja antes" 가드 차용 권장.
**Warning signs:** cobro 했는데 control-de-caja 마감 금액 불일치.

### Pitfall 5: enum↔DB CHECK 동기화 누락(D-03)
**What goes wrong:** `Listo p/ despacho` 를 새 enum 값으로 추가하면 online_orders.status CHECK 제약 갱신 누락 시 INSERT 실패.
**How to avoid:** **권장: 신규 enum 값 추가하지 말고 파생** — `preparedAt` 세팅 + dispatchedAt(또는 shippedAt) null 로 "Listo" 컬럼 파생. 신규 컬럼/enum 최소화 원칙(D-03). 부득이 추가 시 40-04 의 DROP-then-ADD CHECK 패턴.
**Warning signs:** "violates check constraint online_orders_status_check".

## Code Examples

### 누락 타임스탬프 마이그레이션 (40-01/39-03 패턴)
```sql
-- Source: 패턴 = api-ventago/migrations/39-03-store-config-restaurant.sql, 40-01-repartidores.sql
-- 42-02-online-orders-cols.sql
BEGIN;
-- 누락 타임스탬프 (현 모델: confirmed_at/shipped_at/delivered_at/cancelled_at 만 존재)
ALTER TABLE online_orders ADD COLUMN IF NOT EXISTS prepared_at TIMESTAMP WITH TIME ZONE NULL;
ALTER TABLE online_orders ADD COLUMN IF NOT EXISTS dispatched_at TIMESTAMP WITH TIME ZONE NULL;
-- transporte FK (nullable — 기존 행 영향 0)
ALTER TABLE online_orders ADD COLUMN IF NOT EXISTS transporte_id INTEGER NULL
  REFERENCES transportes(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_online_orders_transporte ON online_orders (transporte_id);
COMMIT;
```

### use_envios 플래그 (39-03 패턴)
```sql
-- 42-03-store-config-use-envios.sql
BEGIN;
ALTER TABLE store_configs ADD COLUMN IF NOT EXISTS use_envios BOOLEAN NOT NULL DEFAULT false;
COMMIT;
```

### Transporte 모델 (Repartidor 1:1 복제)
```typescript
// Source 패턴: api-ventago/src/app/repartidores/repartidores.model.ts
@Table({ tableName: 'transportes', timestamps: true })
export class Transporte extends Model {
  @ForeignKey(() => Store)
  @Column({ field: 'store_id', type: DataType.INTEGER, allowNull: false })
  storeId: number;
  @Column({ type: DataType.STRING(120), allowNull: false })
  name: string;
  @Column({ field: 'is_active', type: DataType.BOOLEAN, allowNull: false, defaultValue: true })
  isActive: boolean;
}
```

### cobro 모달 — PaymentSummaryModal 직접 재사용 불가 (D-09)
```
// Source: ventago-app/.../PaymentSummaryModal.tsx:57
const { setPaymentMethods, paymentMethods, selectedClient } = useSaleProducts();
// ↑ POS 판매 컨텍스트(useSaleProducts)에 강결합 — selectedClient/paymentMethods 를 sale 흐름에서 끌어옴.
// 결론(D-09): 직접 재사용 불가. delivery 전용 CobroModal 래퍼 필요.
//   - 재사용 가능: split UI 레이아웃, 수단 선택 행, "Aplicar saldo a favor" 칩, getSaldoPendiente 로직
//   - 신규 필요: saldo pendiente(외상) 컨텍스트, payment_in vs SalePaymentMethod 분기, registerPayment 연동
// 권장: 내부 결제수단 선택 UI 컴포넌트를 추출해 공유, 컨텍스트 의존부는 props 주입형 래퍼로 분리.
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| online-orders: 배달=완납 가정 | 발송≠종료, 부족분 외상 | Phase 42(본) | deliver 결제귀속 분기 필요(Pitfall 1) |
| 식당 신규 delivery 레이어(B안) | online-orders 백본 재사용(A안) | Phase 42 설계 | 신규 코드 최소 |
| 보드 폴링(Phase 39 mesa) | Socket.io push(Phase 40~) | Phase 40 | RestaurantDeliveryGateway 패턴 |

**Deprecated/outdated:** 없음. 기존 모듈 전부 현행.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | "Listo p/ despacho" 는 신규 enum 없이 preparedAt 파생이 바람직 | Pitfall 5/D-03 | enum 추가 결정 시 CHECK 마이그레이션 1개 추가 필요(저위험, 패턴 존재) |
| A2 | cobro 외상 상환분(payment_in)도 caja movement 동반 | D-10 | 회계 정책 차이 — 외상 상환이 caja 입금인지 매장 정책 확인 필요(plan/user) |
| A3 | 외상 발송은 식별 고객(clientId+document)만 허용 | Pitfall 2 | 익명 외상 정책은 매장 결정 — UX 분기 영향 |
| A4 | /restaurant 게이트웨이 재사용 vs 신규 /envios — 신규 권장 | D-11/Open Q | 식당/의류 도메인 분리 원칙상 신규가 일관적, 단 코드 중복. plan 결정 |

## Open Questions (RESOLVED)

1. **deliver 결제 귀속 재정렬 범위 (★)**
   - What we know: 현 deliver 가 mirror 생성 + paymentStatus=PAID 무조건. sale_payment_methods 는 paymentMethodId 있을 때 totalAmount 전액.
   - What's unclear: ship 에서 실수령액만 sale_payment_methods 로, 부족분만 sale_credit 으로 나누는 정확한 분기 시점(ship vs deliver) 및 mirror 의 결제수단 행 처리.
   - Recommendation: Phase 40 D-01 "매출 인식=deliver, 수금축=별도" 차용. ship 시 외상 결정, deliver 시 mirror(매출/재고). mirror 의 paymentStatus/sale_payment_method 분기를 plan task 로 명시 + 회귀 테스트.
   - **RESOLVED:** mirrorSaleId 는 DELIVER 시점에 createMirror 가 생성하므로 sale_credit(saleId 필수, DB CHECK) 적립은 **DELIVER 시점**에 수행. SHIP 시점에는 `order.metadata.shipSaldo` 에 부족분 의도만 기록 + 익명 주문 차단(assertCreditEligible). deliver 결제귀속 재정렬(조건부 paymentStatus + 실수령 mirror payment row) = 42-03 Task 2, 회귀 = 42-03 Task 3.

2. **Socket.io 게이트웨이: /restaurant 재사용 vs 신규 /envios**
   - What we know: RestaurantDeliveryGateway 가 /restaurant namespace + branch:{id} room + JWT 검증 + emitDeliveryUpdated 보유. card 페이로드 구조는 식당 delivery 형태.
   - What's unclear: 의류 카드 payload 가 식당과 다름(transporte vs repartidor, 외상 vs 라이더현금). 같은 namespace 의 다른 이벤트명으로 재사용할지 신규 게이트웨이를 둘지.
   - Recommendation: **신규 게이트웨이(예: OnlineOrdersBoardGateway, namespace /envios)** — 도메인 분리 원칙(설계 §8) 일관. RestaurantDeliveryGateway 코드를 거의 그대로 복제(JWT+room 패턴). 신규 이벤트 `envio_updated`.
   - **RESOLVED:** 신규 게이트웨이 `OnlineOrdersBoardGateway`(namespace `/envios`, `envio_updated` 이벤트, JWT handshake + branch room IDOR 가드, post-commit emit) = 42-04. `/print-agent` 미확장.

3. **Nota(내부 메모) 저장소**
   - What we know: online_orders.notes(TEXT) 단일 컬럼 존재. 타임라인은 여러 Nota + 시간순 이벤트 병합 필요.
   - What's unclear: 여러 Nota 를 시간순으로 누적하려면 단일 notes 컬럼으로 부족.
   - Recommendation: metadata(JSONB) 에 timeline_notes 배열 누적하거나 신규 경량 테이블(online_order_notes). 단순성 위해 metadata JSONB 활용 권장(신규 테이블 회피). plan 결정.
   - **RESOLVED:** `metadata.timeline_notes` JSONB 배열 누적(신규 테이블 회피). Nota-append 백엔드 라우트 + 타임라인 detail(:id 이벤트 병합) 의 소유 task 는 plan revision 에서 백엔드 plan 에 명시.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| PostgreSQL (로컬 PG18 / 운영 PG10) | 마이그레이션 | ✓ | PG18 local / PG10 prod | — (PG10 호환 SQL 필수) |
| Node/NestJS 빌드 | 백엔드 | ✓ | nest ^11 | — |
| socket.io 인프라 | 실시간 보드 | ✓ | ^4.8.1 (기존 게이트웨이) | — |
| print-agent (감열) | Ticket/Recibo | ✓ (조건부) | Electron 28 | 매장에 에이전트 미설치 시 출력 skip(기존 emitPrintTemp fire-and-forget) |
| MinIO | (이 phase 직접 미사용) | ✓ | — | shippingLabelUrl 텍스트만, 파일 업로드 없음 |

**Missing dependencies with no fallback:** 없음.
**Missing dependencies with fallback:** print-agent 미설치 매장은 출력 버튼이 no-op (기존 동작 — 회귀 아님).

## Validation Architecture

> .planning/config.json 의 nyquist_validation 키 미확인 시 enabled 가정. 백엔드는 jest spec 선례 있음(restaurant-delivery.service.spec.ts).

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Jest (api-ventago, *.service.spec.ts 선례) |
| Config file | api-ventago/package.json jest 설정(또는 jest.config) — plan 에서 확인 |
| Quick run command | `cd api-ventago && npx jest online-orders` |
| Full suite command | `cd api-ventago && npm test` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| RD-3 | ship(완납) → 외상 미발생, paymentStatus 정상 | unit | `npx jest online-orders.service` | ❌ Wave 0 |
| RD-4 | ship(부족분) → sale_credit 1건 + StoreClient.balance↑ | unit | `npx jest online-orders.service` | ❌ Wave 0 |
| RD-5 | cobro → payment_in FIFO + box-op 1건 | unit | `npx jest online-orders.service` | ❌ Wave 0 |
| RD-6 | cancel→favor → favor_in + favorBalance↑ | unit | `npx jest online-orders.service` | ❌ Wave 0 |
| RD-10 | deliver(완납) → mirror PAID, 매출 반영 (기존 동작 보존) | unit | `npx jest online-orders.service` | ❌ Wave 0 |
| RD-12 | 기존 online-orders deliver/cancel 회귀 0 | unit | `npx jest online-orders` | 부분(기존 spec 확인) |
| RD-9 | gateway JWT 검증 + branch room IDOR | unit | `npx jest *board.gateway` | ❌ Wave 0 (restaurant-delivery.gateway 패턴 복제) |
| RD-2/7/8 | 칸반/CxC/Historial 렌더 | manual (browser UAT) | — | manual |

### Sampling Rate
- **Per task commit:** `cd api-ventago && npx jest <touched module>`
- **Per wave merge:** `cd api-ventago && npm test` (online-orders + credit + box-operation 회귀)
- **Phase gate:** 풀 스위트 green + 브라우저 UAT(완납발송/부족분발송→cobro→종료/취소favor 시나리오)

### Wave 0 Gaps
- [ ] `api-ventago/src/app/online-orders/online-orders.service.spec.ts` — ship 외상게이트/cobro/cancel favor 커버 (restaurant-delivery.service.spec.ts L181 "efectivo→por_cobrar, box-op 미호출" 패턴 차용)
- [ ] `api-ventago/src/app/transportes/transportes.service.spec.ts` — repartidores.service.spec.ts 복제
- [ ] gateway spec — restaurant-delivery.service.spec.ts L62 mock 패턴
- [ ] 회귀 가드 테스트: 기존 deliver(완납) 경로가 mirror PAID 그대로 유지하는지

## Security Domain

> security_enforcement 키 미확인 — 포함. 외상/결제/caja 도메인이라 보안 중요.

### Applicable ASVS Categories
| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | JWT(Passport) 기존. 게이트웨이 handshake.auth.token 검증(restaurant-delivery.gateway L42) |
| V3 Session Management | yes | SessionGuard 선례 — 보드/cobro 컨트롤러에 @UseGuards 검토 |
| V4 Access Control | yes (★) | store_id 스코프 모든 쿼리 필수. 게이트웨이 branch room IDOR 가드(타 store 카드 유출 방지 — restaurant-delivery.gateway L77) |
| V5 Input Validation | yes | class-validator DTO(ShipOnlineOrderDto 선례). cobro 금액 범위 검증 |
| V6 Cryptography | no | 신규 암호화 없음 |

### Known Threat Patterns
| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| 타 store 외상/주문 조작 | Tampering/Info Disclosure | 모든 service 메서드 storeId 인자 + where 조건(online-orders.service 선례) |
| 게이트웨이 익명 구독 → 카드 유출 | Information Disclosure | handshake JWT 검증 + branch room store 소속 확인(IDOR 가드) |
| cobro 금액 음수/초과 | Tampering | DTO 검증 + registerPayment assertValidDto(totalAmount>0) |
| 외상 한도 우회 | Elevation/Tampering | assertCreditEligible(한도 + credit_status + document) |
| 결제수단 조작으로 매출 오염 | Tampering | mirror activity_type='sale' 고정, source 화이트리스트 CHECK |

## 소매 무회귀 점검 (RD-12 — 사용자 메모: 식당/소매 회귀 절대 금지)

**이 phase 가 건드리는 공유 경로 (회귀 위험):**
1. **`online-orders.service.deliverOrder` (L336)** — 결제귀속 분기 추가 시 기존 완납 online 주문 deliver 흐름 영향. **회귀 검증 필수: 완납 주문은 기존대로 mirror PAID.**
2. **`online-order-sales-mirror.service.createMirror` (L52)** — sale_payment_methods 분기 변경 시 기존 매출/재고 보고서 영향. **activity_type='sale'·source='online' 불변 유지.**
3. **`online-orders.service.cancelOrder` (L378)** — favor 분기 추가 시 기존 nullifyMirror 경로 영향. **기존 취소(환불) 경로 보존.**
4. **store_configs 신규 컬럼** — DEFAULT false 라 기존 매장 영향 0 (39-03 선례 검증).
5. **online_orders 신규 컬럼** — 전부 nullable, 기존 행 영향 0.

**검증 포인트(plan 의 verification step 에 포함):**
- [ ] use_envios=false 매장: Ventas Online 페이지 기존 동작(Pedidos/Envíos/Devoluciones) 그대로 보이는가? (3탭 격상이 기존 탭을 깨지 않는가)
- [ ] 완납 online 주문 deliver → 기존처럼 mirror PAID + 매출 반영 (분기 추가 후에도)
- [ ] 기존 online 취소(환불) → nullifyMirror 정상 (favor 분기가 기본 경로 안 깨뜨림)
- [ ] sales 보고서(activity_type='sale')에 delivery sale 정상 집계, 이중계상 없음
- [ ] control-de-caja 마감: cobro caja movement 합계 일치

## Sources

### Primary (HIGH confidence — 직접 코드/스키마 검증)
- `api-ventago/src/app/online-orders/online-order.model.ts` — 컬럼/enum 전체 (transporteId/preparedAt/dispatchedAt 부재 확인)
- `.planning/intel/db-schema-tables.md:992-1029` — online_orders 실제 DB 컬럼 (모델과 일치 확인)
- `.planning/intel/db-schema-tables.md:1498-1517` — store_clients balance/favorBalance/creditLimit
- `api-ventago/src/app/online-orders/online-orders.service.ts:273-428,801-858` — confirm/prepare/ship/deliver/cancel + runStatusTx
- `api-ventago/src/app/online-orders/online-order-sales-mirror.service.ts` — createMirror/nullifyMirror (source=online, activity_type=sale, 멱등성)
- `api-ventago/src/app/credit/credit-ledger.model.ts` + `services/credit-ledger.service.ts` — movement_type/bucket, appendMovement(tx 필수)
- `api-ventago/src/app/credit/services/credit-payment.service.ts` — registerPayment(자체 SERIALIZABLE tx, FIFO)
- `api-ventago/src/app/credit/services/credit-validation.service.ts:42-116` — assertCreditEligible(document+한도)
- `api-ventago/src/app/box-operation/box-operation.service.ts` — addOperation 시그니처
- `api-ventago/src/app/rider-settlement/rider-settlement.service.ts:150-228` — closingTime=null cashRegister + addOperation 매핑
- `api-ventago/src/app/restaurant-delivery/restaurant-delivery.gateway.ts` — /restaurant namespace, JWT, branch room, emit
- `api-ventago/src/app/repartidores/repartidores.model.ts` — Transporte 복제 원형
- `api-ventago/migrations/40-01-repartidores.sql`, `40-04-sales-source-delivery.sql`, `39-03-store-config-restaurant.sql` — PG10/15 호환 패턴
- `ventago-app/src/views/ventas-online/VentasOnlineView.tsx` — 현 탭 구조(pedidos/envios/devoluciones)
- `ventago-app/src/views/restaurante/DeliveryBoard.tsx` — 칸반 + socket.io-client 패턴
- `ventago-app/src/views/homes/components/ProductList/components/PaymentSummaryModal.tsx:57` — useSaleProducts 강결합(직접재사용 불가)

### Secondary (MEDIUM)
- `.planning/phases/40-restaurante-delivery-despacho-cobro/40-CONTEXT.md` — Phase 40 D-01~D-08 패턴 원형
- `docs/superpowers/specs/2026-06-19-retail-delivery-despacho-design.md` — A안 아키텍처 합의

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — package.json 직접 확인, 신규 의존성 없음
- Architecture (OnlineOrder 보강/Credit 연동): HIGH — 모든 서비스 시그니처/흐름 코드 검증
- 결제귀속 재정렬(Pitfall 1): HIGH(문제 식별) / MEDIUM(해법 정확 분기는 plan 설계 필요)
- 게이트웨이/cobro 모달 재사용 판단: HIGH — 강결합/패턴 직접 확인
- Validation: MEDIUM — jest 선례 존재, 신규 spec 작성 필요(Wave 0)

**Research date:** 2026-06-19
**Valid until:** 2026-07-19 (안정 — in-house 코드 기반, 외부 라이브러리 변동 없음)
