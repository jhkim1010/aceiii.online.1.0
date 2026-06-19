# Phase 42: Retail Delivery — Despacho / Cuentas por cobrar / Historial - Context

**Gathered:** 2026-06-19
**Status:** Ready for planning
**Source:** Brainstorming 설계 합의 (docs/superpowers/specs/2026-06-19-retail-delivery-despacho-design.md)

<domain>
## Phase Boundary

의류(비식당, `use_envios=true`) 모드 매장이 Web·WhatsApp·전화로 주문받아 **transporte(택배사/자가배송)** 로 발송하고, 부족분을 **고객 외상(cuenta corriente)** 으로 통제하는 라이프사이클 통제 레이어. Phase 40 식당 delivery 의 직관적 통제 UX(칸반·타임라인·정산)를 의류로 이식하되, **정산축이 "라이더 현금 rendir" → "고객 외상 갚음(cobro)"** 으로 바뀐다.

핵심 불변식: **발송 ≠ 종료** — 완납 후 발송이 원칙이며, 부족분을 남기고 발송하면 그 차액이 외상으로 잔류해 회수 대상이 된다. 완납 발송 건은 Cuentas por cobrar 에 들어오지 않고 깨끗이 종료, 부족분 건만 빨강으로 잔류.

**아키텍처 결정(A안):** 식당이 신규 `RestaurantDelivery` 레이어를 만든 것과 달리, 의류 배송은 **기존 `online-orders`(OnlineOrder) 백본이 만들어진 바로 그 도메인**(채널·운송장·택배사·결제상태)이다. 따라서 데이터는 OnlineOrder 그대로 재사용하고, 부족한 "직관적 통제 경험"(칸반·타임라인·외상통제)만 신규로 얹는다. 신규 엔티티는 `Transporte` 1개 + OnlineOrder 보강 + 외상은 기존 CreditLedger/StoreClient 재사용.

본 CONTEXT 는 설계 문서가 합의한 범위(WHAT)의 **구현 방식(HOW)** 회색지대를 다룬다.

</domain>

<decisions>
## Implementation Decisions

### 데이터 백본 — OnlineOrder 재사용 범위
- **D-01 (Sale mirror 재사용):** delivery 통제 대상 = 기존 OnlineOrder. delivered 시 자동 생성되는 sales mirror(`online-order-sales-mirror.service.ts`, source=`online`) 흐름 그대로 → 매출·재고 보고서 자동 반영. **신규 SaleSource 값 만들지 않음.** 신규 코드 최소화 원칙.
- **D-02 (단계별 타임스탬프):** OnlineOrder 모델은 이미 라이프사이클 타임스탬프(`orderedAt`/`preparedAt`/`dispatchedAt`/`deliveredAt` 등)를 보유 가능성 높음 — **research 가 현 컬럼을 확인**, 없는 것만 마이그레이션 추가(타임라인·SLA용). 추측 금지, db-schema-tables.md 대조.
- **D-03 (`Listo p/ despacho` 컬럼 파생):** OnlineOrderStatus enum 에 `Listo` 가 PREPARING 과 별도 상태로 없으면, **`preparedAt` 세팅 + 미발송(dispatchedAt null)** 으로 파생하거나 신규 `READY` 상태를 추가 — plan 단계에서 enum↔DB CHECK 동기화 선례(SaleStatus, OnlineOrderStatus) 따라 확정. 신규 컬럼/enum 최소화 우선.

### Transporte 모델 (신규)
- **D-04 (스코프/구조):** `Transporte` = `{ id, storeId, name, isActive, createdAt }`. 매장 단위(store_id FK), `isActive=false` 면 발송 드롭다운 제외(이력 보존 — 삭제 아님). Phase 40 `Repartidor` 카드/모델 패턴 그대로 의류로 복제.
- **D-05 (OnlineOrder 연동):** OnlineOrder 에 `transporteId`(FK→transportes, nullable) 추가. 기존 `shippingCarrier`(VARCHAR) 텍스트는 선택한 transporte.name 으로 채워 하위호환 미러(Phase 27-28 텍스트 필드 유지).

### 외상 연동 — CreditLedger/StoreClient 재사용 (신규 메커니즘 금지)
- **D-06 (외상 발송 게이트):** 발송 시 잔액 > 0 이면 **"외상으로 발송" 경고** → 확인 시 차액 1건을 CreditLedger `sale_credit`(bucket=credito, +) + StoreClient.balance 증가. saleId/venta 링크 필수(credit-ledger.model.ts `relatedSaleId`). 완납 건은 외상 미발생.
- **D-07 (cobro = 외상 상환):** 부분/split cobro 가 외상 잔액을 차감할 때 CreditLedger `payment_in`(bucket=credito, −, FIFO, parentLedgerId → sale_credit). 신규 결제(아직 미적립)는 SalePaymentMethod 직접 기록. cobro 는 어느 상태에서나 등록 가능.
- **D-08 (취소 후 환불 vs favor):** `Cancelar pedido`(결제 후) → ① **Devolver dinero**: 환불 → caja 역movement. ② **Pasar a favor**: 지불액을 CreditLedger `favor_in`(bucket=favor, +) + StoreClient.favorBalance → 다음 구매/외상에 `favor_apply` 사용. 두 경로 모두 기존 credit 모듈 movement_type 재사용(신규 type 금지).

### cobro 모달 (부분/split) — PaymentSummaryModal 재사용
- **D-09 (모달 재사용 vs 신규):** 기존 `PaymentSummaryModal`(homes/ProductList) 의 split·다중수단 로직 재사용 검토 우선. delivery cobro 는 잔액 컨텍스트(saldo pendiente)·외상 적립 분기가 추가되므로, research 가 재사용 가능 범위 vs delivery 전용 래퍼 필요 여부 판단. 수단 = Efectivo·Transferencia·Cheque(은행/번호)·Tarjeta·QR(기존 매장 PaymentMethod 설정).
- **D-10 (cobro → caja movement):** 각 cobro(신규 결제분)는 box movement 반영 → control-de-caja 마감 일치. `box-operation.service.addOperation` 재사용(Phase 40 D-05 선례). 외상 상환분(payment_in)도 caja 입금 movement 동반 — plan 에서 매핑 확정.

### 실시간 보드 (Socket.io)
- **D-11 (채널):** Despacho 칸반 실시간 = Socket.io 푸시(폴링 아님). Phase 40 DeliveryBoard 가 사용하는 게이트웨이/room 패턴 재사용 또는 동형 — research 가 Phase 40 의 실시간 채널 구현(신규 namespace vs 기존)을 확인해 그대로 따름. 카드 단위 payload emit(전체 재조회 회피, pool 절약).

### 화면 구조
- **D-12 (3탭 격상):** 기존 Ventas Online 페이지(`views/ventas-online/`, ShippingManagementTab 보유)를 3탭으로 재구성: (1) **Despacho** 칸반(마스터-디테일 보드≈75% + 타임라인≈25%, Phase 32 stocks-historial-drawer 패턴), (2) **Cuentas por cobrar**(부족분 외상 통제 + 고객별 잔액 + 입금), (3) **Historial**(종료 건). 신규 페이지 아님 — 기존 페이지 격상.

### Claude's Discretion
- **칸반 컴포넌트 이식:** Phase 40 `DeliveryBoard.tsx` 의 칸반 구조·카드·마스터디테일 레이아웃을 의류용으로 복제/일반화할지, 공유 컴포넌트로 추출할지는 plan 단계. 단 식당/의류 화면 통합은 명시적 범위 밖(설계 §8) — 코드 재사용은 OK, 화면 통합은 금지.
- **상태머신 매핑 정확 명칭:** `Nuevo`(PENDING/CONFIRMED)·`Preparando`(PREPARING)·`Listo p/ despacho`·`En tránsito`(SHIPPED)·`Entregado`(DELIVERED) ↔ OnlineOrderStatus enum string/CHECK 동기화는 plan 단계(D-03 연계).
- **타임라인 데이터 병합:** 단계별 타임스탬프(orderedAt/preparedAt/dispatchedAt/deliveredAt) + 결제 이벤트(SalePaymentMethod + CreditLedger)를 시간순 병합하는 쿼리/뷰 구성은 plan 단계. Nota(내부 메모)는 타임라인 기록 저장소(OnlineOrder.internalNotes 컬럼 활용 또는 신규) research 확인.
- **`+Nuevo envío` 입력 콘솔:** Phase 40 식당 Nuevo pedido 모달 패턴(채널·고객 자동완성·주소·품목 피커·cobro) 의류 이식. nueva-venta "envío 필요" 건의 보드 자동 유입 연결 지점은 plan 에서 OnlineOrder 생성 경로 확인 후 결정.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### 설계 문서 (아키텍처 합의 — 필수)
- `docs/superpowers/specs/2026-06-19-retail-delivery-despacho-design.md` — A안 합의(online-orders 백본 재사용 + 식당식 통제 UX), 3탭 구조, 데이터 모델(Transporte 신규 + OnlineOrder 보강 + Credit 재사용), 상태머신 매핑, 완납 게이트, cobro/취소 흐름, 범위 밖. **MUST read before planning.**

### 직전 Phase 컨텍스트 (delivery 통제 UX 원형 — 패턴 일관성)
- `.planning/phases/40-restaurante-delivery-despacho-cobro/40-CONTEXT.md` — Phase 40 식당 delivery 의 D-01~D-08 결정(매출 귀속, 실시간 채널, caja 매핑, box-operation 재사용). 정산축 차이(라이더 현금 vs 고객 외상)에 유의해 패턴만 이식
- `.planning/phases/40-restaurante-delivery-despacho-cobro/40-SPEC.md` — 식당 delivery 요구사항(대조용)

### DB schema reference (SQL/migration 작성 전 필수 — 추측 금지)
- `.planning/intel/db-schema-tables.md` — 133개 테이블 전체 컬럼 (타입/NOT NULL/default). OnlineOrder 현 컬럼(타임스탬프/transporte) 확인 필수
- `.planning/intel/db-schema-fks.md` — 모든 외래 키 관계

### Backend 재사용 대상 (확장 only)
- `api-ventago/src/app/online-orders/online-order.model.ts` — `OnlineOrder` 백본. OnlineOrderChannel/Status/PaymentStatus enum, shippingCarrier/trackingCode/shippingLabelUrl, 라이프사이클 타임스탬프(orderedAt/preparedAt/dispatchedAt/deliveredAt), salesMirrorId. **transporteId 추가 + 없는 타임스탬프만 추가**
- `api-ventago/src/app/online-orders/online-orders.service.ts` + `online-orders.controller.ts` — 주문 CRUD/ship 흐름. `dto/ship-online-order.dto.ts`(발송 DTO — transporteId/운송장 추가 지점)
- `api-ventago/src/app/online-orders/online-order-sales-mirror.service.ts` — delivered 시 Sale mirror 생성(source=online, 멱등성 salesMirrorId). 매출/재고 자동 반영(D-01)
- `api-ventago/src/app/online-orders/online-order-stock.service.ts` — 재고 차감/복원 흐름(취소 시)
- `api-ventago/src/app/credit/credit-ledger.model.ts` — `CreditLedger`(movement_type: sale_credit/payment_in/favor_in/favor_apply/favor_refund, bucket: credito/senia/favor, relatedSaleId, parentLedgerId). 외상 발송(D-06)·cobro 상환(D-07)·취소 favor(D-08)
- `api-ventago/src/app/credit/services/credit-ledger.service.ts` + `credit-payment.service.ts` + `credit-validation.service.ts` — 외상 적립/입금(FIFO)/한도검증 서비스. 신규 외상 메커니즘 만들지 말고 이 서비스 경유
- `api-ventago/src/app/shared/store-clients/store-clients.model.ts` — `StoreClient`(balance/favorBalance/creditLimit). 외상·favor 잔액. 고객 자동완성/주소
- `api-ventago/src/app/box-operation/box-operation.service.ts` — `addOperation()` cobro/환불 caja movement(D-10). closingTime=null cashRegister 패턴(Phase 40 D-05/D-06)
- `api-ventago/src/app/print/print.gateway.ts` + `print.service.ts` — `/print-agent` 게이트웨이 + `emitPrintTemp(branchId,data)`. Ticket(packing slip)/Recibo(영수증) 감열 출력 재사용
- `api-ventago/src/app/store/config/storeConfig.model.ts` — store_configs. **`use_envios`(Boolean, 기본 false) 신규** 게이트(Transporte 카드/보드 노출)
- `api-ventago/src/app/payment-methods/payment-methods.model.ts` — PaymentMethod(cobro 수단 설정)
- `api-ventago/migrations/` — 신규 `transportes` 테이블 + OnlineOrder ALTER(transporteId, 없는 타임스탬프) + store_configs use_envios. **PG10/PG15 호환**(SERIAL, snake_case, CHECK=enum 동기화, CREATE INDEX ... WHERE)

### Frontend 재사용/분기 대상
- `ventago-app/src/views/ventas-online/ShippingManagementTab.tsx` + `ventago-app/src/pages/ventas-online/` — **3탭 격상 대상**(Despacho/Cuentas por cobrar/Historial)
- `ventago-app/src/views/restaurante/DeliveryBoard.tsx` — Phase 40 칸반 보드 원형(마스터-디테일·카드·실시간). 의류 이식 참조(화면 통합 아님)
- `ventago-app/src/hooks/api/useDeliveryBoard.ts` + `useDeliveryHistory.ts` — Phase 40 보드/이력 SWR 훅 선례
- `ventago-app/src/configs/deliveryLabels.ts` — 상태 라벨 매핑 선례
- `ventago-app/src/views/homes/components/ProductList/components/PaymentSummaryModal.tsx` — split/부분결제 모달(D-09 cobro 재사용 검토)
- `ventago-app/src/services/api.service.ts` — apiConnector(get/post/put/remove). **remove() 사용(.delete 아님)**

### 프로젝트 규약
- `CLAUDE.md` — Sequelize underscored(snake_case), PG10/PG15 호환, pool min=10/max=80, 300ms 타겟+코드스플리팅(next/dynamic ssr:false), SWR 훅(5분 dedup), ESLint(newline-before-return/lines-around-comment/no-unused-vars), apiConnector.remove(), pageSize≤50
- `.claude/skills/sketch-findings-ace-online/SKILL.md` — Ventago 다크 네이비+골드 테마, MUI 5 매핑(보드/cobro 모달/Transporte 카드 UI 작업 시 참조)

</canonical_refs>

<specifics>
## Specific Ideas

- **상태머신(설계 §4.2):** `Nuevo → Preparando → Listo p/ despacho → En tránsito → Entregado`. 각 컬럼 = 같은 상태 pedido 세로 누적 + 헤더 건수 뱃지.
- **카드:** 주문#, 채널 뱃지(Web/WhatsApp/Teléfono/MercadoLibre/Instagram), 고객명, 주소, 금액, 결제상태 뱃지(Pagado/Parcial/Sin pagar), (발송 후) transporte 칩 + 운송장, (부족분) 빨강 `Saldo $X`.
- **Despachar 액션:** `Listo` 카드 → transporte 드롭다운(activo만) + 운송장 입력 → `En tránsito`. 잔액>0 시 완납 게이트 경고.
- **타임라인 패널(우 ≈25%):** 헤더(주문#·고객·채널·주소·Saldo pendiente 빨강) + 액션(🎫 Ticket·🧾 Recibo·📝 Nota) + 시간순 이벤트(Pedido creado → Pago $X(수단) → Preparación completada → Nota → Despachado(transporte, ⚠saldo) → Entregado → Pendiente de cobro) + Registrar cobro + Cancelar pedido.
- **Cuentas por cobrar 탭:** saldo>0 건만 빨강 집계, 고객별 외상 잔액(StoreClient.balance), Registrar cobro → 0 되면 종료.
- **설정 > Transporte 카드:** `use_envios=true` 시만 노출. 목록(이름·activo 토글·수정/삭제) + 인라인 추가(Phase 40 Repartidores 카드 패턴).

</specifics>

<deferred>
## Deferred Ideas

- **반품(devolución)** — nueva-venta 메인 화면에서 처리(이 보드 밖, 설계 §8).
- **고객용 공개 주문 추적 링크** — 후속.
- **택배사 L2 API 양방향 연동** — 운송장 수동 입력. payout/대조 자동화는 후속.
- **라이더/배송기사 모바일 앱·GPS** — 해당 없음(transporte는 업체 단위).
- **식당 모드와의 화면 통합** — 별도 도메인 유지(설계 §8, Phase 40 이 이미 거부).

</deferred>

---

*Phase: 42-retail-envios-despacho-cobranza*
*Context gathered: 2026-06-19 (from brainstorming design spec)*
