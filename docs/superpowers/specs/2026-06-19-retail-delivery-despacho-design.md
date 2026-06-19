# 의류(소매) Delivery — Despacho · Cuentas por cobrar · Historial 설계

- **날짜**: 2026-06-19
- **상태**: 설계 합의 완료 (구현 계획 대기)
- **범위**: 의류(비식당) 모드 매장이 Web·WhatsApp·전화로 주문받아 transporte(택배/자가배송)로 발송하고, 부족분을 외상으로 통제하는 라이프사이클
- **관련**: Phase 40 식당 delivery(통제 UX 원형), Phase 27-28 online-orders(데이터 백본), Phase 26 Credit/외상·favor, 기존 PaymentSummaryModal·print-agent·box(caja)
- **원형과의 관계**: 식당 delivery의 직관적 통제(칸반/정산/이력)를 의류로 이식하되, "정산축"이 라이더 현금 → 고객 외상으로 바뀐다.

---

## 1. 문제 정의

의류 매장이 Web/WhatsApp/전화로 주문을 받아 택배사(또는 자가배송)로 보내고, 돈을 받고, **수금이 끝날 때까지 통제**해야 한다. 식당과 공유하는 원칙은 **"발송 ≠ 종료"**. 단 의류는:

- 라이더 현장 현금이 없다. 대신 **완납 후 발송**이 원칙.
- 부족분을 남기고 보내면 그 차액이 **고객 외상(cuenta corriente)**으로 적립되어 회수 대상이 된다.
- 배차 대상이 라이더(repartidor)가 아니라 **운송업체(transporte)** — Correo Argentino, OCA, Andreani, Propia cuenta 등.

---

## 2. 합의된 요구사항 (브레인스토밍 결과)

- **주문 유입**: Web·WhatsApp·전화(직원 수동 입력) + 매장 즉석판매(nueva-venta)에서 "envío 필요" 건. 고객용 자체 주문 화면은 제외.
- **판매 화면 유지**: nueva-venta는 그대로. delivery 통제는 분리된 별도 화면.
- **배차 대상**: 관리되는 **Transporte 목록**(CRUD). 발송 시 드롭다운 선택 + 운송장 입력.
- **수금 원칙**: 완납 후 발송. 부족분 발송 시 차액 = 외상(고객). **언제든 부분결제(cobro parcial)** 등록 가능, 현금·이체·cheque·tarjeta·QR 혼합(split).
- **취소(결제 후)**: 환불(devolver) 또는 favor(선수금 권리) 전환.
- **반품**: 이 보드 범위 밖 — nueva-venta 메인 화면에서 처리.

---

## 3. 아키텍처 결정

**채택: A안 — 기존 `online-orders`(OnlineOrder) 백본 재사용 + 식당식 통제 UX 입히기.**

식당이 신규 `RestaurantDelivery`를 만든 이유는 online-orders가 식당(라이더·현장현금·실시간배차)에 안 맞았기 때문. 그러나 **의류 배송은 online-orders가 만들어진 바로 그 도메인**(채널·운송장·택배사·결제상태)이다. 따라서 데이터는 OnlineOrder 그대로 쓰고, 부족한 "직관적 통제 경험"(칸반·타임라인·외상통제)만 얹는다.

| 대안 | 판단 |
|---|---|
| A. online-orders 백본 + 통제 UX | ✅ 데이터 이미 적합, 신규 코드 최소, 보고서·재고 자동 반영 |
| B. 신규 retail-delivery 레이어(식당 복제) | ❌ online-orders와 기능 중복, retail 배송 시스템 2개 공존 |
| C. 식당+의류 공용 통제 화면 | ❌ 두 도메인 상태머신 상이, 복잡도 급증 (Phase 40이 이미 거부한 통합) |

---

## 4. 통제 구조 — 3탭 (Ventas Online 페이지 격상)

기존 Ventas Online 페이지(ShippingManagementTab 보유)를 다음 3탭으로 재구성:

| 탭 | 식당 대응 | 역할 |
|---|---|---|
| **Despacho** | Tablero(칸반) | 발송 단계별 칸반 보드 (transporte 배차) |
| **Cuentas por cobrar** | Liquidación | 부족분(외상) 남은 건 통제 + 고객별 잔액 + 입금 등록 |
| **Historial** | Historial | 종료(배달완료+완납/취소) 주문 이력 |

**정산축 재해석**: 식당 "라이더 현금 rendir" 자리에 의류는 **"고객 외상 갚음(cobro)"**이 들어간다. 완납 발송은 Cuentas por cobrar에 안 들어오고 깨끗이 종료된다. 부족분 건만 빨강으로 잔류.

---

## 5. 화면 (UI/UX)

### 5.1 마스터-디테일 레이아웃
- **좌(≈75%)**: Despacho 칸반 보드.
- **우(≈25%)**: 좌측에서 선택한 카드의 상세 타임라인. (Phase 32 stocks-historial-drawer 패턴 재현)

### 5.2 Despacho 보드 (칸반)
- **컬럼(상태)**: `Nuevo → Preparando → Listo p/ despacho → En tránsito → Entregado`.
  - 각 컬럼에 **같은 상태의 모든 pedido가 세로로 누적**, 헤더에 건수 뱃지.
- **카드**: 주문#, 채널 뱃지(Web/WhatsApp/Teléfono/MercadoLibre/Instagram), 고객명, 주소, 금액, 결제상태 뱃지(Pagado/Parcial/Sin pagar), (발송 후) transporte 칩 + 운송장, (부족분) 빨강 `Saldo $X`.
- **Despachar 액션**: `Listo` 카드 → transporte 드롭다운 선택 + 운송장 입력 → `En tránsito`.
- **완납 게이트**: 발송 시 잔액 > 0이면 **"외상으로 발송" 경고** → 확인 시 차액이 외상(CreditLedger `sale_credit` + StoreClient.balance) + 카드에 `Saldo $X` + Cuentas por cobrar로.
- **+Nuevo envío**: Web/WhatsApp/전화 주문 직원 입력 콘솔(식당 Nuevo pedido와 동일 — 채널·고객 자동완성·주소·품목 피커·cobro). 매장 즉석판매(nueva-venta) "envío 필요" 건도 보드로 자동 유입.
- **실시간**: Socket.io 푸시(폴링 아님) — 식당 DeliveryBoard 패턴.

### 5.3 상세 타임라인 패널 (우측)
- **헤더**: 주문#, 고객, 채널, 주소. 잔액 있으면 `Saldo pendiente $X` 빨강 뱃지.
- **액션 버튼**: 🎫 **Ticket**(발송 티켓/packing slip, print-agent 감열) · 🧾 **Recibo**(결제 영수증, print-agent 감열) · 📝 **Nota**(내부 메모 → 타임라인 기록).
- **타임라인(시간순)**: Pedido creado → Pago $X(수단) → Preparación completada → Nota(있으면) → Despachado(transporte, ⚠ saldo 있으면 표시) → Entregado → Pendiente de cobro(잔액 있으면).
  - **데이터 출처**: 발송 레코드 단계별 타임스탬프(orderedAt/preparedAt/dispatchedAt/deliveredAt) + 결제 이벤트(SalePaymentMethod + CreditLedger)를 시간순 병합.
- **Registrar cobro 버튼** → cobro 모달.
- **Cancelar pedido**(결제 후) → 환불 vs favor 선택.

### 5.4 Cobro 모달 (부분결제/분할) — 기존 PaymentSummaryModal 재사용
- **언제든**: 어느 상태에서나 cobro 등록.
- **수단**: Efectivo · Transferencia · Cheque(은행/번호) · Tarjeta · QR (기존 매장 PaymentMethod 설정).
- **Parcial**: 잔액 일부만 받으면 나머지 외상 잔류.
- **Split**: 한 cobro 안에서 혼합(예: 현금 $10k + cheque $5k).
- **기록**: 각 cobro → 타임라인 이벤트 + saldo 차감 + CreditLedger `payment_in`(외상 상환) 또는 SalePaymentMethod → caja movement 반영.

### 5.5 Cuentas por cobrar 탭
- 부족분(saldo > 0) 남은 발송 건을 **빨강으로 집계** (완납 건은 안 옴).
- 고객별 외상 잔액(StoreClient.balance) 표시.
- "Registrar cobro" → 외상 차감 → 0이 되면 건 종료.

### 5.6 취소 흐름 (결제 후)
- `Cancelar pedido` → 이미 지불액 처리 선택:
  - 💸 **Devolver dinero**: 환불 → caja 역movement.
  - 🎟️ **Pasar a favor**: 지불액을 고객 favor(선수금 권리)로 → CreditLedger `favor_in` + StoreClient.favorBalance. 다음 구매/외상에 `favor_apply`로 사용.

### 5.7 설정 > Transporte 카드
- `use_envios=true`일 때만 노출. 운송업체 목록(이름·activo 토글·수정/삭제) + 인라인 추가. (식당 Repartidores 카드 패턴)
- activo 항목만 발송 드롭다운에 노출.

---

## 6. 데이터 모델

### 재사용 (변경 없음 또는 최소)
- **OnlineOrder** (백본): channel, status, paymentStatus, shippingCarrier, trackingCode, shippingLabelUrl, shippingCost — 의류 배송에 이미 적합.
- **Sale** (source=`online`): online-orders가 이미 mirror 생성 → 보고서·재고 자동 반영. 신규 SaleSource 값 불필요.
- **SalePaymentMethod / PaymentMethod**: split·부분결제·cheque.
- **CreditLedger** (`sale_credit`/`payment_in`/`favor_in`/`favor_apply`) + **StoreClient**(balance·favorBalance·creditLimit): 외상·favor.
- **box(caja)**: cobro/환불 movement. **print-agent**: ticket/recibo. **clients/whatsapp**: CRM.

### 신규 / 보강
- **`Transporte`** 모델(신규): `id, storeId, name, isActive, createdAt`. 매장 단위, isActive=false면 드롭다운 제외(이력 보존).
- **OnlineOrder 보강**:
  - `transporteId` (FK→transportes, nullable). shippingCarrier 텍스트는 선택값으로 채움(하위호환).
  - 단계별 타임스탬프: `preparedAt`, `dispatchedAt`, `deliveredAt` (orderedAt = createdAt). 타임라인·SLA용. (현 모델에 없는 것만 추가)
  - 외상 연동: 발송 시 잔액 → CreditLedger `sale_credit` 1건(pendingVenta/saleId 링크).
- **store_configs**: `use_envios` (Boolean, 기본 false) — 의류 배송 통제 활성 게이트.

### 상태머신 매핑 (OnlineOrder status → 컬럼)
- `Nuevo` = PENDING/CONFIRMED · `Preparando` = PREPARING · `Listo p/ despacho` = 준비완료(preparedAt set, 미발송) · `En tránsito` = SHIPPED · `Entregado` = DELIVERED.
- `Listo`를 PREPARING과 구분하려면 `preparedAt` 세팅으로 파생하거나 `READY` 상태 추가 — 구현 계획에서 확정.

---

## 7. 통합 지점

- **보고서**: delivery Sale은 source=`online`·activityType=`sale` → 매출 통계 자동 포함.
- **재고**: Sale 품목 차감 흐름 재사용.
- **카하**: cobro/환불 = box movement → control-de-caja 마감과 일치.
- **외상/favor**: 기존 Credit 모듈 그대로 (신규 외상 메커니즘 만들지 않음).
- **출력**: ticket(발송)/recibo(결제) = print-agent 감열 재사용.
- **CRM**: clients 자동완성/주소 기억, whatsapp click-to-chat.

---

## 8. 범위 밖 (Out of scope, YAGNI)

- **반품(devolución)**: nueva-venta 메인 화면에서 처리(이 보드 밖).
- 고객용 주문 추적 링크(공개).
- 택배사 API 양방향 연동(L2) — 운송장 수동 입력. payout/대조 자동화는 후속.
- 라이더/배송기사 모바일 앱·GPS.
- 식당 모드와의 화면 통합(별도 도메인 유지).

---

## 9. 가정 (확정, 다르면 재논의)

- 의류/식당 모드는 store 단위 배타. 의류 배송 통제는 `use_envios` 매장 전용.
- 보드 실시간 = Socket.io 푸시.
- 완납 건은 Cuentas por cobrar에 들어오지 않음. 부족분 건만 외상 잔류.
- Transporte는 관리 목록(자유 텍스트 아님). shippingCarrier 텍스트는 선택값 미러.
- 통제 화면 위치 = 기존 Ventas Online 페이지 3탭 격상.
