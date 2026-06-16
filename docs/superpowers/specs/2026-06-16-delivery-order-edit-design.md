# 배달 주문 편집 기능 (Delivery Order Edit) — 설계

- **날짜**: 2026-06-16
- **영역**: Phase 40 배달/배차/수금 — 보드(`DeliveryBoard`)에서 이미 접수된 주문 편집
- **관련 코드**: `api-ventago/src/app/restaurant-delivery/*`, `ventago-app/src/views/restaurante/DeliveryBoard.tsx`, `.../components/NuevoPedidoModal.tsx`, `print-agent` comanda 템플릿

---

## 1. 배경 / 문제

현재 `restaurant-delivery` 모듈은 주문 **생성**(`POST /order`), **상태 전이**(`PATCH /:id/transition`), **취소**(`POST /:id/cancel`)만 지원한다. 한 번 `Enviar a cocina`로 접수된 주문은 품목·고객정보·결제수단을 수정할 방법이 없어, 정정하려면 취소 후 재접수해야 한다(매출 역분개 부담 + UX 불편).

운영 요구: **주방 조리 중(En cocina)에는 품목을, En camino 진입 전에는 고객/주소/결제수단을 수정**할 수 있어야 한다.

---

## 2. 핵심 제약 (코드 근거)

- 배달 주문은 Entregado 전까지 `Sale.status = DRAFT`. 매출 귀속(`DRAFT→PAID`) + `SalePaymentMethod` 기록은 Entregado에서만 발생(`settleSaleOnDelivery`).
- 재고/box 이동은 Entregado(settle) 또는 cancel(`nullifySale`)에서만 발생 → **편집 창(nuevo/en_cocina/listo)은 모두 DRAFT 구간이라 품목 편집이 재고/현금에 무영향**.
- 내부 생성 주문은 항상 `en_cocina`로 시작(`DeliveryStatus.NUEVO`는 enum에 존재하나 외부앱 연동용 예약 상태 — 현재 미사용).
- QR 결제는 접수 시 MP 인텐트(`amount=totalAmount`, `pendingVentaId=sale.id`)를 미리 생성. `MpQrService.cancelIntent(intentId, userId)` 존재 — 인텐트가 `approved`면 취소 불가(결제 완료), `pending`이면 MP 측 clear 후 `cancelled` 처리.
- 한 주문 = `Sale` + `RestaurantDelivery` 1:1 (`saleId` UNIQUE).

---

## 3. 편집 창 (Edit Window) — 상태별 규칙

| 대상 | 편집 가능 상태 | 잠금 시작 |
|---|---|---|
| **품목 (items)** | `nuevo`, `en_cocina` | `listo` 이후 (주방 완료 = 메뉴 확정) |
| **메타** (customerName, customerPhone, address, paymentMode, canal, externalRef, clientId) | `nuevo`, `en_cocina`, `listo` | `en_camino` 이후 |
| **tipo** (delivery ↔ takeaway) | 편집 불가 (고정) | — |

- 서버가 상태 가드를 **강제**한다(UI와 무관한 방어선). 위반 시 `400 BadRequest` + 스페인어 메시지.
- QR 결제 완료(`intent.status='approved'`)된 주문은 상태와 무관하게 **모든 편집 차단**(정합성 보호).

---

## 4. 백엔드 설계

### 4.1 신규 엔드포인트 (`restaurant-delivery.controller.ts`)

- `GET /restaurant-delivery/:id` — 편집 모달 프리필용 상세. storeId 스코프 단일 조회.
  - 반환: 보드 카드 필드 + `items: [{ productId, name, price, qty, customName }]`.
  - **라우트 순서 주의**: 기존 `GET /board/:branchId`(구체 경로)가 이미 `:id`보다 위에 선언되어 있으므로, `GET /:id`는 그 아래에 둔다(구체 경로 우선 규칙 유지).
- `PATCH /restaurant-delivery/:id` — 부분 편집.
  - `UpdateDeliveryOrderDto`: `items?`, `customerName?`, `customerPhone?`, `address?`, `paymentMode?`, `canal?`, `externalRef?`, `clientId?`, `terminalId?`(QR 재생성용).

### 4.2 `updateOrder(storeId, userId, deliveryId, dto)` 서비스

**단일 TX:**
1. `deliveryModel.findOne({ id, storeId })` (IDOR 가드). 없으면 404.
2. **선제 가드**:
   - QR `approved` 인텐트 존재 → `BadRequestException('El pedido ya fue pagado con QR y no puede editarse')`.
   - `dto.items` 제공인데 상태 ∉ {nuevo, en_cocina} → 400 (품목 편집 창 종료).
   - 메타 필드 제공인데 상태 ∉ {nuevo, en_cocina, listo} → 400 (메타 편집 창 종료).
3. **품목 편집**(`dto.items` 제공 시): `SaleItem.destroy({ saleId })` → `bulkCreate(신규)` → `computedTotal = Σ price*qty` → `sale.update({ totalAmount })`. (클라 total 무시 — 서버 진실, 변조 방지: createOrder와 동일 원칙)
4. **메타 패치**: 허용된 필드만 delivery에 update. 결과 `tipo=delivery`인데 `address` 빈값이면 400.
5. 갱신된 delivery 반환(TX 내).

**TX 커밋 후 부수효과** (외부 HTTP/프린트를 TX 안에서 잡지 않음 — createOrder 패턴 동일):
- **QR 인텐트 재조정** (`pendingVentaId=sale.id`로 활성 인텐트 조회):
  - 미결제 + (총액 변동 OR QR→타수단) → `cancelIntent(intentId, userId)`.
  - 미결제 + (타수단→QR OR QR 유지 & 총액 변동) → 기존 미결제 인텐트 cancel 후 `createIntent({ amount:새 total, terminalId, pendingVentaId:sale.id, ... })`.
  - `terminalId` 부재로 재생성 불가 시 400(`Seleccioná una terminal para el cobro con QR`).
  - 헬퍼: `MpQrService`에 `findActiveIntentByVenta(saleId)` 추가(`mp_payment_intents` 조회, terminal 상태 제외) — cancelIntent가 intentId를 받으므로 조회 경로 필요.
- **코만다 재출력**: 품목 변경 & 상태=`en_cocina`면 `printService.emitPrintTemp(branchId, { kind:'comanda', delivery:true, modified:true, saleId, customerName, address, items })`.
  - print-agent comanda 템플릿: `modified` 플래그 true면 헤더에 `*** MODIFICADO ***` 출력(템플릿 소폭 보강).
- **보드 푸시**: `deliveryGateway.emitDeliveryUpdated(branchId, toCard(delivery, sale))` — 갱신된 total 반영.

### 4.3 에러 처리

- 모든 가드 위반은 `BadRequestException`(400) + 명확한 스페인어 메시지 → 프론트 인라인 Alert + 글로벌 토스트로 노출(에러 가시성 규약).
- storeId 스코프 강제(IDOR — T-40 시리즈와 일관).

---

## 5. 프론트엔드 설계

### 5.1 `NuevoPedidoModal` 편집 모드 확장 (신규 모달 X — DRY)

- props 추가: `editCard?: DeliveryCard`(없으면 생성 모드).
- 편집 모드:
  - 마운트 시 `GET /restaurant-delivery/:id`로 품목 로드 → `cart` 프리필 + 메타(tipo·canal·paymentMode·고객·주소·externalRef) 프리필.
  - `tipo` ToggleButton **disabled**(고정).
  - 제목 `Editar pedido`, 버튼 `Guardar cambios` → `apiConnector.patch('/restaurant-delivery/:id', payload)`.
  - 카드 `status` 기준 enable/disable:
    - 품목 그리드/코만다 수량 조절: 상태 ∈ {nuevo, en_cocina}일 때만 활성.
    - 메타 필드: 상태 ∈ {nuevo, en_cocina, listo}일 때만 활성.
  - QR 결제 모드 유지/전환 시 `terminalId = user.terminalId` 전송(생성 모달과 동일 소스).
- 생성 모드는 기존 동작 그대로(회귀 없음).

### 5.2 `DeliveryCardItem` — 편집 진입점

- **"Editar"(연필) 버튼** 추가 — 편집 창 상태(`nuevo`/`en_cocina`/`listo`)일 때만 노출.
- `onEdit(card)` 콜백 → `BoardColumn` → `DeliveryBoard`로 전달.

### 5.3 `DeliveryBoard` — 모달 공용

- `editCard` state 추가. 단일 `NuevoPedidoModal` 인스턴스를 생성/편집 공용으로 사용.
- "Nuevo pedido" 버튼 & Nuevo 컬럼 빈 공간 클릭 = 생성 모드(`editCard=null`).
- 연필 버튼 = 편집 모드(`editCard=card`).
- `onCreated`/저장 성공 시 `mutate()` + 모달 닫기(소켓 push와 별개로 즉시 재검증).

---

## 6. 테스트

`restaurant-delivery.service.spec.ts` 확장:
- 품목 편집 → SaleItem 교체 + `totalAmount` 재계산 검증.
- 품목 편집 `listo`에서 차단(400).
- 메타 편집 `listo` 허용 / `en_camino` 차단(400).
- QR 미결제 편집(총액 변동) → cancel + recreate 호출 검증.
- QR `approved` 편집 시도 → throw 검증.
- 품목 변경 시 코만다 `emitPrintTemp(modified:true)` emit 검증.
- delivery + 주소 빈값 → 400.

---

## 7. 비범위 (YAGNI)

- tipo(delivery↔takeaway) 전환 — 주소 필수성/라이더 의미 변동으로 복잡 → 제외.
- 부분 품목 델타 코만다(추가분만 인쇄) — 전체 MODIFICADO 재출력로 충분.
- en_camino 이후 편집 — 차단(배차/조리 완료 후 변경 금지).
- 편집 이력(audit log) — 별도 phase 후보.
