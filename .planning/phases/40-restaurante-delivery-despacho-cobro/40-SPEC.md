# Phase 40: Restaurante Delivery — Despacho y Cobro — Specification

**Created:** 2026-06-16
**Ambiguity score:** 0.14 (gate: ≤ 0.20)
**Requirements:** 9 locked

## Goal

식당모드(`use_restaurant_mode=true`) 매장이 인터넷 배달 주문을 내부 콘솔로 접수해 주방→배차→배달→**수금→정산 마감**까지 통제한다. 핵심 불변식: *배달 완료(`Entregado`) ≠ 주문 종료* — 현금 contra entrega 주문은 라이더 정산금이 caja(box) movement 로 입금(`Liquidado`)될 때까지 "열린 미수금(Por cobrar)"으로 추적된다.

## Background

코드 현황(2026-06-16 scout):
- **Sale 백본 재사용 가능**: `api-ventago/src/app/sales/sales.model.ts` 에 `source`(SaleSource enum: pos/online/factura), `activityType`(SaleActivityType: sale/movido/fallado), `tableId`(nullable, BelongsTo RestaurantTable `constraints:false`) 존재. `SaleSource` 에 `'delivery'` 추가가 설계 방향.
- **Phase 39 식당 인프라 존재**: `restaurant-tables/`, `restaurant-elements/`, `sales/restaurant-sale/`(RestaurantSaleService — placeOrder/comanda/box-operation/MP 결제 라이프사이클). 식당 sale 도 `activityType='sale'` + `BoxOperationService.addOperation` 경유로 매출 통계 자동 통합 패턴 확립.
- **online-orders 모듈 존재하나 재사용 안 함**: `online-orders/`(online-order.model, sales-mirror, expiry cron, return)는 소매(택배·운송장·배송라벨)용. delivery(라이더·현장 현금수금·실시간 배차)와 라이프사이클이 근본적으로 다름 → 설계상 의도적 제외.
- **재사용 인프라**: `mercadopago/`(mp-webhook QR 자동 확인), `box`/`box-operation`(caja movement), `clients`(CRM/whatsapp), `print`(comanda print-agent).

배달 도메인 전용 엔티티(Repartidor / RestaurantDelivery / RiderSettlement)와 4개 화면은 **아직 존재하지 않는다.** 이 phase 의 1차 산출물이다.

설계 문서: `docs/superpowers/specs/2026-06-16-restaurant-delivery-design.md` (C안 합의).

## Requirements

1. **신규 엔티티 — Repartidor (라이더)**: 식당모드 매장 단위 라이더 등록/조회.
   - Current: 라이더 개념·테이블 없음
   - Target: `repartidores` 테이블(`storeId, name, phone, isActive, createdAt`) + CRUD. `isActive=false` 면 배차 드롭다운/정산 단위에서 제외(삭제 대신 비활성 → 정산 이력 보존)
   - Acceptance: 라이더 생성/목록/비활성 토글이 store-scoped 로 동작하고, `isActive=false` 라이더는 배차 드롭다운 후보에서 빠진다

2. **신규 엔티티 — RestaurantDelivery (배달 주문 메타, Sale 1:1)**: 배달 주문 상태·주소·채널·라이더를 Sale 위에 얹는 통제 레이어.
   - Current: 배달 주문 메타 없음
   - Target: `restaurant_deliveries` 테이블(`storeId, branchId, saleId FK UNIQUE, status enum, tipo[delivery|takeaway], canal[whatsapp|telefono|app|otro], clientId nullable, customerName, customerPhone, address, paymentMode[efectivo|qr|app], repartidorId FK nullable, orderedAt, readyAt, dispatchedAt, deliveredAt, settledAt, externalRef nullable, metadata JSONB`)
   - Acceptance: 주문 접수 시 Sale(`source='delivery'`, `activityType='sale'`, `tableId=null`)과 RestaurantDelivery 가 1:1(saleId UNIQUE)로 단일 트랜잭션 생성되며, 상태 전이 시 해당 타임스탬프 컬럼이 기록된다

3. **신규 엔티티 — RiderSettlement (라이더 현금 정산 마감)**: 라이더별 현금 미수금 정산을 caja 마감과 연결.
   - Current: 라이더 현금 정산 개념 없음
   - Target: `rider_settlements`(`storeId, repartidorId FK, boxSessionId FK nullable, expectedCash, receivedCash, difference, status[open|partial|closed], openedAt, closedAt, note`) + `rider_settlement_items`(`settlementId, restaurantDeliveryId, amount, rendido bool`)
   - Acceptance: 한 정산은 포함된 현금 주문 목록을 가지며, `expectedCash`/`receivedCash`/`difference` 가 산출되고 rendido 처리된 주문만 `Liquidado` 로 전환된다

4. **SaleSource 'delivery' 확장**: 보고서 자동 반영 + 소매 online 과 분리.
   - Current: `SaleSource = {pos, online, factura}`, DB CHECK 동기화
   - Target: `SaleSource.DELIVERY='delivery'` 추가 + DB CHECK 제약 갱신(PG10/PG15 호환 마이그레이션). delivery sale 은 `activityType='sale'` 유지 → 기존 매출 보고서 코드 변경 없이 포함
   - Acceptance: delivery sale 행이 `source='delivery'` 로 저장되고, 기존 매출 보고서(activityType='sale' 필터)에 자동 집계되며 소매 online mirror 와 구분된다

5. **주문 접수 콘솔 (Nuevo pedido 모달)**: 직원이 WhatsApp·전화·배달앱 주문을 입력.
   - Current: 식당모드에 mesa(살롱) 주문만 존재, delivery 접수 진입점 없음
   - Target: Tipo 토글(Delivery=주소·라이더 / Para llevar=주소·라이더 생략), Canal 칩, 전화번호 기존 고객 자동완성(없으면 인라인 생성)+주소, mesa `OrderModal` 동일 메뉴 피커, Cobro 모드(Efectivo/QR/App) 선택. "Enviar a cocina" → Sale(DRAFT)+RestaurantDelivery 생성 + comanda 발송 → 보드 `En cocina`
   - Acceptance: Delivery/Takeaway 각각 접수 시 Sale+RestaurantDelivery 생성 + comanda 출력 호출이 발생하고, takeaway 는 주소·라이더 필드를 강제하지 않는다

6. **배차 보드 칸반 (Tablero de despacho)**: 상태별 컬럼으로 주문 라이프사이클 시각 통제.
   - Current: 배차 보드 없음
   - Target: 컬럼 = `Nuevo · En cocina · Listo · En camino · Por cobrar`(+ app 전용 `Conciliación` 버킷). 카드 = 주문번호·고객·주소·경과시간 타이머·총액·수금모드 뱃지·라이더 칩. `Listo` 카드 "Asignar" → activo 라이더 드롭다운으로 `En camino` 전이. 실시간 = Socket.io 푸시
   - Acceptance: 주문이 상태 전이 시 올바른 컬럼으로 이동하고, Socket.io 이벤트로 다른 클라이언트에 푸시되며, 라이더 미배정 주문은 `En camino` 로 넘어갈 수 없다

7. **현금 미수금(Por cobrar) 통제 + 라이더 정산 → caja 입금**: 핵심 통제 불변식의 falsifiable 증명. *(R1 결정)*
   - Current: 배달 후 현금 미수금 추적 메커니즘 없음
   - Target: 현금(`paymentMode=efectivo`) 주문은 `Entregado` 후 `Por cobrar` 칸반 컬럼에 잔류. 라이더 정산 화면에서 rendido 체크 → "Registrar rendición en caja" → 해당 주문 `Liquidado` 전환 + 현금이 box(caja) movement 로 입금. QR/app 주문은 `Por cobrar` 에 들어오지 않음
   - Acceptance: ① 현금 배달완료 주문은 정산 전까지 `Por cobrar` 에 잔류 ② "Registrar rendición" 실행 시 box movement(addOperation) 가 기록되고 주문이 `Liquidado` 로 전환 ③ QR/app 주문은 `Por cobrar` 컬럼에 절대 나타나지 않음

8. **MercadoPago QR 자동 수금 (기존 재사용)**: QR 주문은 webhook 으로 자동 종료.
   - Current: mp-webhook 인프라는 mesa/POS 결제용으로 존재
   - Target: `paymentMode=qr` 배달 주문은 기존 `mp-webhook.service.ts` 흐름 재사용 → 결제 webhook 수신 시 `paymentStatus=pagado` 자동. 배달 완료와 동시에 종료(`Por cobrar` 미경유)
   - Acceptance: QR 배달 주문이 webhook 결제 확인 후 별도 수동 정산 없이 종료 상태가 되고, `Por cobrar`/라이더 현금 정산 대상에 포함되지 않는다

9. **배달앱 L1 정산 CSV 대조**: payout CSV 업로드로 자동 매칭 + 불일치만 노출. *(R1 결정)*
   - Current: 배달앱 정산 대조 없음
   - Target: `paymentMode=app` 주문은 배달 완료 시 `Conciliación` 버킷(주 단위). payout CSV 업로드 → `externalRef` 로 주문 자동 매칭 → 매칭건 Conciliado 자동 확정, 미매칭/금액 불일치만 빨강 표시
   - Acceptance: CSV 업로드 후 externalRef 가 일치하는 주문은 자동 Conciliado 로 표시되고, 매칭 실패/금액 불일치 행만 빨강으로 잔류한다

## Boundaries

**In scope:**
- 신규 엔티티 3개: Repartidor, RestaurantDelivery(Sale 1:1), RiderSettlement(+ Item)
- `SaleSource` 에 `'delivery'` 추가 (DB CHECK 마이그레이션 PG10/PG15 호환)
- 화면 4개: (1) 설정 > Repartidores 카드(식당모드 on 일 때만), (2) 주문 접수 모달(Delivery/Para llevar), (3) 배차 보드 칸반, (4) 라이더 정산
- 수금 3종: 현금 contra entrega(라이더→caja 정산), QR(MP webhook 자동), 배달앱(L1 CSV 대조)
- 경과시간 타이머 표시 (고정 임계값, 시각 보조)
- comanda 출력(print-agent 재사용, delivery 표식)
- Socket.io 실시간 보드 푸시
- delivery sale 의 매출 보고서 자동 반영(activityType='sale')

**Out of scope:**
- 고객용 공개 주문 추적 링크 — 추후 WhatsApp 상태 메시지로 확장 (YAGNI)
- 배달앱 L2 완전 API 양방향 동기화 — 플랫폼 파트너 API 확보 후 별도 phase
- 라이더 모바일 전용 앱/화면 — 추후 (Phase 37 mobile 계열과 별개)
- GPS 실시간 위치 추적 — 별도 phase
- 외상(fiado) 배달 — credit 모듈 통합은 별도
- SLA 설정·초과 알림 — 이번엔 고정 임계값 경과시간 표시만 (R1 결정)
- 금액 tolerance 매칭 — L1 은 externalRef 정확 매칭만 (R1 결정)
- 소매 `online-orders` 모듈 통합/확장 — 도메인 충돌로 의도적 제외

## Constraints

- **DB 호환**: 신규 테이블·CHECK 제약 마이그레이션은 운영 PG10 + dev PG15/local PG18 호환 (SERIAL, `CREATE UNIQUE INDEX ... WHERE`, `EXECUTE PROCEDURE` 등 프로젝트 표준 패턴 준수). Sequelize `underscored:true` → DB 컬럼 snake_case.
- **Sale 백본 재사용 필수**: 신규 금전·재고·comanda 로직을 중복 재구현하지 않고 기존 RestaurantSaleService/SalePaymentMethod/BoxOperationService/MinIO/print 패턴을 재사용한다.
- **매출 무오염**: delivery sale 은 `activityType='sale'` 유지. 모든 매출 쿼리는 명시적 `activityType='sale'` 필터 정책 유지(Phase 35 규약).
- **멀티테넌트 격리**: 모든 신규 테이블에 `storeId` FK + store-scoped 조회. 식당모드 매장 전용(store 단위 배타).
- **Pool 절약**: 보드/정산 조회는 N+1 회피, 불필요한 sales JOIN 금지. 참조 데이터는 캐시 패턴 준수 (CLAUDE.md 성능 규약, pool min=10/max=80).
- **ESLint**: newline-before-return / lines-around-comment / no-unused-vars 빌드 차단 규칙 준수.
- **실시간**: 보드 갱신은 Socket.io 푸시(폴링 아님).

## Acceptance Criteria

- [ ] 식당모드 매장에서 라이더(Repartidor)를 등록·조회·비활성 토글할 수 있고, `isActive=false` 라이더는 배차 드롭다운에서 제외된다
- [ ] 주문 접수 모달에서 Delivery/Takeaway 주문을 입력하면 Sale(`source='delivery'`, `activityType='sale'`, `tableId=null`) + RestaurantDelivery(saleId UNIQUE) 가 단일 트랜잭션으로 생성되고 comanda 출력이 호출된다
- [ ] Takeaway 주문은 주소·라이더 입력을 강제하지 않는다
- [ ] 배차 보드 칸반이 `Nuevo·En cocina·Listo·En camino·Por cobrar`(+ `Conciliación`) 컬럼을 표시하고 상태 전이 시 카드가 올바른 컬럼으로 이동한다
- [ ] 라이더 미배정 주문은 `En camino` 로 전이할 수 없다
- [ ] 보드 상태 변경이 Socket.io 이벤트로 다른 클라이언트에 푸시된다
- [ ] 현금(efectivo) 배달완료 주문은 정산 전까지 `Por cobrar` 에 잔류한다
- [ ] 라이더 정산에서 "Registrar rendición en caja" 실행 시 box(caja) movement 가 기록되고 rendido 주문이 `Liquidado` 로 전환된다
- [ ] QR/app 주문은 `Por cobrar` 컬럼 및 라이더 현금 정산 대상에 나타나지 않는다
- [ ] QR(MercadoPago) 배달 주문은 기존 mp-webhook 흐름으로 결제가 자동 확인되어 수동 정산 없이 종료된다
- [ ] 배달앱 payout CSV 업로드 시 externalRef 가 일치하는 주문은 자동 Conciliado 로 표시되고 미매칭/금액 불일치 행만 빨강으로 잔류한다
- [ ] delivery sale 이 기존 매출 보고서에 자동 집계된다 (보고서 코드 변경 없이)
- [ ] 신규 마이그레이션이 PG10/PG15 양쪽에서 clean apply + idempotent re-run 된다
- [ ] 설정 > Repartidores 카드는 `use_restaurant_mode=true` 일 때만 노출된다

## Ambiguity Report

| Dimension          | Score | Min  | Status | Notes                                            |
|--------------------|-------|------|--------|--------------------------------------------------|
| Goal Clarity       | 0.90  | 0.75 | ✓      | 라이프사이클 + 통제 불변식 명확                   |
| Boundary Clarity   | 0.92  | 0.70 | ✓      | 설계 §6/§9 + R1 으로 in/out 명시                  |
| Constraint Clarity | 0.80  | 0.65 | ✓      | Sale 재사용·PG10/15·멀티테넌트·실시간 확정        |
| Acceptance Criteria| 0.78  | 0.70 | ✓      | R1 3개 결정으로 미수금/CSV/타이머 AC 확정          |
| **Ambiguity**      | 0.14  | ≤0.20| ✓      |                                                  |

Status: ✓ = met minimum, ⚠ = below minimum (planner treats as assumption)

## Interview Log

| Round | Perspective | Question summary                          | Decision locked                                                       |
|-------|-------------|-------------------------------------------|-----------------------------------------------------------------------|
| 0     | Researcher  | (scout) 무엇이 존재하는가                  | Sale source/activityType/tableId 확장 가능, Phase 39 식당 인프라 존재, online-orders 제외 |
| 1     | Boundary/AC | Por cobrar 완료 기준?                      | 칸반 컬럼 + 라이더정산→caja 입금까지 open (R7)                         |
| 1     | Boundary/AC | 배달앱 L1 CSV 대조 최소 동작?              | externalRef 매칭 + 매칭 자동확정 + 불일치 빨강 (R9), tolerance 매칭 제외 |
| 1     | Boundary/AC | SLA 타이머 = 요구사항 vs 시각 보조?         | 시각 보조 — 고정 임계값 경과시간 표시만, 설정/알림 범위 밖             |

---

*Phase: 40-restaurante-delivery-despacho-cobro*
*Spec created: 2026-06-16*
*Next step: /gsd-discuss-phase 40 — implementation decisions (테이블 DDL 세부·상태 전이 가드 구현·보드 컴포넌트 구조·CSV 파서 등)*
