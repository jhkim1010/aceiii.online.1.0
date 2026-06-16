# 식당 배달(Delivery) — 주문 접수 · 배차 · 수금 통제 설계

- **날짜**: 2026-06-16
- **상태**: 설계 합의 완료 (구현 계획 대기)
- **범위**: 식당모드(`use_restaurant_mode`) 매장의 인터넷 배달 주문 라이프사이클 — 접수 → 조리 → 배차 → 배달 → 수금 → 정산 마감
- **관련**: Phase 39 식당모드 POS, Phase 34 Client WhatsApp+CRM, 기존 `online-orders`(소매), `mercadopago/`, `box`(caja)

---

## 1. 문제 정의

식당이 인터넷(WhatsApp · 전화 · 배달앱)으로 주문을 받고, 라이더로 내보내고, 돈을 수금해 오고, **수금이 끝날 때까지 통제**해야 한다. 가장 어려운 지점은 **현금 contra entrega** — 라이더가 현장에서 현금을 받아 돌아오므로, 돈이 카하에 정산될 때까지 "열린 미수금"으로 추적해야 한다.

**핵심 원칙**: *배달 완료 ≠ 주문 종료.* 음식이 나가도 돈이 정산(conciliado)되기 전까지는 열린 주문으로 통제한다.

---

## 2. 합의된 요구사항 (브레인스토밍 결과)

- **주문 유입 경로**: WhatsApp, 배달앱(PedidosYa/Rappi), 전화/직원 수동 입력. **고객용 자체 주문 메뉴는 제외** — 직원이 받아 입력하는 내부 콘솔.
- **수금 모드 (3종 공존)**:
  - 현금 contra entrega — 라이더 수금 → 카하 정산 (일/교대 단위)
  - QR/이체 (MercadoPago) — webhook 자동 확인
  - 배달앱 수금 — 플랫폼이 받고 식당은 payout으로 늦게 정산 (주 단위)
  - 외상(fiado) **제외**
- **라이더 관리**: 정식 관리 — 등록(목록) + 배차 + 정산.
- **배달앱 정산 수준**: **L1 (정산 CSV 대조)** — 주문은 수동 입력, payout CSV 업로드 시 자동 매칭 + 불일치만 표시.

---

## 3. 아키텍처 결정

**채택: C안 — 신규 delivery 레이어 + 기존 `Sale` 백본 재사용.**

기존 `online-orders` 모듈은 **재사용하지 않는다.** 그것은 소매(의류) 이커머스용(택배사·운송장·배송라벨)이라 식당 배달(라이더·현장 현금수금·실시간 배차)과 라이프사이클이 근본적으로 다르다. 억지 통합 시 두 도메인이 한 모델에서 충돌한다.

| 대안 | 판단 |
|---|---|
| A. online-orders 확장 | ❌ 소매/식당 상태머신 충돌, 보고서 오염 |
| B. 완전 신규 (금전·재고까지) | ❌ 성숙한 Sale·결제·comanda·MP 인프라 중복 재구현 |
| **C. delivery 레이어 + Sale 재사용** | ✅ Phase 39 인프라 위에 얹힘, 보고서 자동 반영, 도메인 분리 |

식당모드 살롱 옆에 "Delivery" 탭을 추가하는 형태. mesa(매장 내) ↔ delivery 가 같은 `Sale` 위에서 돌되, delivery 만의 배차·수금정산 통제 레이어를 갖는다.

---

## 4. 상태 머신

```
Nuevo → En cocina → Listo → En camino → Entregado → Liquidado
(접수)   (comanda)   (배차전) (라이더배정)  (배달완료)   (수금정산)
```

**수금 축(병렬)**: 각 주문은 `paymentMode`(efectivo|qr|app)와 `paymentStatus`를 가진다.
- **QR**: 결제 시 webhook 자동 → 배달 완료와 동시에 종료 (`Por cobrar` 안 들름)
- **efectivo**: 배달 완료 후 `Por cobrar`(미수금)에 머묾 → 라이더 정산 시 `Liquidado`
- **app**: 배달 완료 시 `Conciliación`(정산 대기) 버킷 → payout CSV 대조 시 종료

---

## 5. 데이터 모델

### 신규 엔티티 3개

**`Repartidor`** (라이더)
- `id, storeId, name, phone(whatsapp), isActive, createdAt`
- 식당모드 매장 단위. `isActive=false`면 배차 드롭다운 제외(삭제 대신 비활성 → 정산 이력 보존).

**`RestaurantDelivery`** (배달 주문 메타 — Sale 1:1)
- `id, storeId, branchId, saleId(FK→sales, UNIQUE), status(enum), tipo(delivery|takeaway), canal(whatsapp|telefono|app|otro)`
- `clientId(FK, nullable), customerName, customerPhone, address` (스냅샷)
- `paymentMode(efectivo|qr|app), repartidorId(FK, nullable)`
- `orderedAt, readyAt, dispatchedAt, deliveredAt, settledAt`
- `externalRef`(배달앱 주문번호, nullable), `metadata(JSONB)`

**`RiderSettlement`** (라이더 정산 마감)
- `id, storeId, repartidorId(FK), boxSessionId(FK→caja 세션, nullable)`
- `expectedCash, receivedCash, difference, status(open|partial|closed)`
- `openedAt, closedAt, note`
- 연결: `RiderSettlementItem`(settlementId, restaurantDeliveryId, amount, rendido bool) — 어떤 주문이 이 정산에 포함됐는지.

### 재사용 (변경 없음 또는 최소)
- `Sale` (`source` 에 신규 값 `'delivery'` 추가 — 소매 `'online'`과 분리, `tableId=null`, `activityType='sale'`) → 보고서 자동 반영
- `SaleItem`, `SalePaymentMethod` (split 결제 그대로)
- `mercadopago/` (mp-webhook, mp-qr, mp-wallet) — QR 결제 자동 확인
- `box`(caja) — 라이더 정산 입금이 카하 movement로 기록
- `clients`(CRM) — 고객 자동완성/주소 기억
- `print`(comanda) — 주방 출력

---

## 6. 화면 (UI/UX)

### 6.1 설정 > Repartidores 카드
- `use_restaurant_mode=true`일 때만 노출 (off면 카드 숨김 — store 단위 배타 원칙).
- 라이더 목록(이름·WhatsApp·activo 토글·수정/삭제) + 인라인 추가 행.
- activo 라이더만 배차 드롭다운/정산 단위로 흐름.

### 6.2 주문 접수 모달 (Nuevo pedido)
- Tipo 토글: `Delivery`(주소·라이더) / `Para llevar`(주소·라이더 생략).
- Canal 칩(WhatsApp/teléfono/app) 기록.
- Cliente: 전화번호로 기존 고객 자동완성("cliente conocido"), 신규 인라인 생성, 주소.
- 품목: mesa `OrderModal`과 동일 메뉴 피커.
- Cobro 모드 선택(Efectivo 기본 / QR / App) → 보드 뱃지·정산 버킷 결정.
- "Enviar a cocina" → `Sale`(DRAFT) + `RestaurantDelivery` 생성 + comanda 발송 → 보드 `En cocina`.

### 6.3 배차 보드 (Tablero de despacho) — 칸반
- 컬럼 = 상태: `Nuevo · En cocina · Listo · En camino · Por cobrar`(+ `Conciliación` app 버킷).
- 카드: 주문번호, 고객, 주소, 타이머(SLA 초과 시 앰버→빨강), 총액, **수금모드 뱃지(색=모드)**, 라이더 칩(배정 후).
- `Listo` 카드 "Asignar" → activo 라이더 드롭다운.
- **`Por cobrar`(빨강) = 통제 핵심**: 배달됐으나 현금 미수금만 잔류. QR/app는 여기 안 옴.
- 실시간: Socket.io 푸시(현 폴링 대체) — 주방/배차 동시작업 대비.

### 6.4 라이더 정산 (Liquidación de repartidor)
- 라이더별: 엔트레가 수, **efectivo a rendir**(강조), QR+app(정보용).
- 현금 주문 목록 + rendido 체크. 미rendido는 빨강 잔류.
- Esperado vs Recibido(contado) → **Diferencia(faltante/sobrante)**. 차액 = 미정산 주문.
- "Registrar rendición en caja" → rendido 주문 `Liquidado` 전환 + 현금을 caja movement로 입금 → 카하 마감 연결. "Guardar parcial" 지원.

---

## 7. 수금 연동 상세

### MercadoPago — 자동 (기존 재사용)
- `mp-webhook.service.ts`: QR 결제 → webhook → `paymentStatus=pagado` 자동. 수동 점검 불필요.
- `mp-wallet.service.ts`: 입금(정산) 대조 추적.
- 배달 QR 주문은 이 인프라 그대로 사용 → 배달 완료 시 자동 종료.

### 배달앱 (PedidosYa/Rappi) — L1 정산 CSV 대조
- 주문: 수동 입력 (cobro=app), 배달 완료 시 `Conciliación` 버킷(주 단위).
- payout CSV 업로드 → `externalRef`로 주문 자동 매칭 → **불일치만 빨강 표시**.
- 돈 흐름 성격이 다름: 현금=교대 마감(일), 앱=payout 대조(주).
- L2(완전 API 양방향 동기화)는 **별도 phase** — 플랫폼 파트너 API 확보 후.

---

## 8. 통합 지점

- **보고서**: delivery `Sale`은 `activityType='sale'` 유지 → 매출 통계 자동 포함 (보고서 코드 변경 불필요).
- **재고**: Sale 품목 차감 흐름 재사용. 단일 variant 코드마드레 이슈는 기존 POS 수정(70ec4b5) 적용됨.
- **카하**: 라이더 정산 입금 = box movement → control-de-caja 마감과 일치.
- **comanda**: 주방 출력은 기존 print-agent(/print-agent) 재사용. delivery 표식 추가.
- **CRM**: clients/whatsapp 재사용, 라이더에게 주소 click-to-chat.

---

## 9. 범위 밖 (Out of scope, YAGNI)

- 고객용 주문 추적 링크(공개) — 추후 WhatsApp 상태 메시지로 확장.
- 배달앱 L2 완전 API 연동 — 별도 phase.
- 라이더 모바일 전용 앱/화면 — 추후.
- GPS 실시간 위치 추적.
- 외상(fiado) 배달 — credit 모듈 통합은 별도.

---

## 10. 가정 (확정, 다르면 재논의)

- 보드 실시간 = Socket.io 푸시.
- QR·app 주문은 배달 완료 시 현금 `Por cobrar`에 안 들어감 (각자 자동/주단위 버킷).
- 식당/일반(의류) 모드는 store 단위 배타 — delivery는 식당모드 매장 전용.
