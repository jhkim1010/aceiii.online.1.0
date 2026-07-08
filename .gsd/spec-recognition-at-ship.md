# SPEC: [Phase 44.1-P1] 매출인식 시점 이동 (deliver → ship)
생성일: 2026-07-08 · 전제 단계(P1) · 후속: `spec-despacho-revert.md`(P2)

## 목표
envío(online_orders) 흐름에서 **판매 확정(Ventas mirror sale + 재고 sale 전환 + 외상 sale_credit)** 인식 시점을 `deliverOrder`(entregado)에서 `shipOrder`(en_transito)로 앞당긴다. entregado 는 순수 물류 완료 마일스톤(deliveredAt 기록)으로 축소된다.

## 배경
- 현재(코드 확인): 재고 hold+product.stock 차감은 **주문 생성(pending)** 시점(`holdStock`, line 435, product.stock -qty at line 104). deliver 의 `commitSale` 은 ledger 를 suspend→sale 로 재분류만(product.stock 무변경, line 216).
- 현재 deliver(deliverOrder:931~1022)가 하는 것: `commitSale` + `createMirror`(mirrorSaleId) + `sale_credit` 누적(shipSaldo>0) + deliveredAt + paymentStatus.
- 현재 ship(shipOrder:802~923)이 하는 것: shipSaldo 계산 + `assertCreditEligible`(자격검증) + metadata 의도 기록. **mirror/sale_credit 은 deliver 로 이연**(Phase 42 설계).
- 사용자 결정(2026-07-08): 발송(ship)이 판매 확정 시점이어야 한다 → mirror/sale_credit 을 ship 으로 이동.

## 변경 사항
### shipOrder (CONFIRMED/PREPARING → SHIPPED) — 판매 확정 추가
기존 shipSaldo 계산/자격검증 유지 + 아래 추가(deliver 에서 이동):
1. `stockService.commitSale(order, t)` — ledger suspend→sale (product.stock 무변경, 이미 차감됨).
2. `receivedAmount = shipSaldo>0 ? total-shipSaldo : undefined`; `mirror = createMirror(order, t, receivedAmount)`; `order.mirrorSaleId = mirror.id`.
3. `shipSaldo>0 && isNewMirror` → `appendMovement({movementType:'sale_credit', amount:shipSaldo, saleId:mirror.id, ...})` (mirror.id 존재 후 — DB CHECK 충족).
4. paymentStatus: `shipSaldo<=0 ? PAID : 유지`. stockReleasedAt = now(sale 확정 의미).
- saleDate: `createMirror` 는 `order.deliveredAt ?? new Date()` 사용 → ship 시 deliveredAt=null → ship 시각. (원하면 shippedAt 명시 전달)

### deliverOrder (SHIPPED → DELIVERED) — 물류 완료로 축소
- 제거: commitSale / createMirror / sale_credit.
- 유지: `order.deliveredAt = new Date()`; `setStageActor(order,'delivered',...)`.
- **레거시 안전 폴백(필수)**: `if (order.mirrorSaleId == null)` 이면 (구모델에서 발송된 in-flight 주문) 기존 deliver 로직(commitSale+createMirror+sale_credit)을 그대로 실행. → 배포 시점에 이미 SHIPPED 상태인 주문도 Ventas 누락 없이 안전. 신규 주문은 ship 에서 mirror 생김 → 폴백 미발동.

## 데이터/마이그레이션
- **스키마 변경 없음**. 컬럼 무변경(mirrorSaleId/deliveredAt 등 그대로).
- **운영 마이그레이션 불필요** — 폴백으로 in-flight 주문 처리. 백필 없음.
- 과거 delivered 주문: 이미 mirror 존재 → 무영향.

## 회귀 검증 (필수 — 완료된 Phase 42/40 재무 코드)
- Phase 42 의류 envío: ship 완납/외상 두 경로 → Ventas 노출 시점이 ship 으로 당겨짐 확인. shipSaldo>0 외상 배송 → sale_credit 이 ship 에서 1건만 누적(중복/누락 0).
- cobro(Cobro envío): mirror 가 ship 부터 존재하므로 발송 직후 수금 가능 — 회귀 아닌 의도된 변화. 확인.
- Phase 40 restaurant-delivery: 동일 헬퍼(commitSale/createMirror) 공유 여부 확인 — 공유 시 별도 회귀 검증, 미공유 시 무관.
- 재고 이중차감 0: product.stock 은 여전히 생성 시 1회만 차감. ship 의 commitSale 은 product.stock 무변경 확인.
- cancelOrder: SHIPPED/DELIVERED 모두 wasCommitted=true 경로 유지(mirror 존재) — 무변경 확인.

## 완료 기준
- 신규 주문 ship 시: Ventas mirror 생성 + (외상이면)sale_credit 1건. deliver 시: deliveredAt 만.
- 레거시 in-flight(구모델 SHIPPED) deliver 시: 폴백으로 mirror 생성 — Ventas 누락 0.
- Phase 42/40 회귀 UAT PASS. 재고 이중차감 0. pool 안전(전 작업 동일 tx).

## 금지/주의
- product.stock 차감 로직 이동 금지 — 재고는 생성 시 그대로.
- sale 행 삭제/중복 금지. mirror UNIQUE(onlineOrderId) 멱등 유지.
- Phase 42 shipSaldo 게이트/자격검증 로직 변경 금지 — 순서만 재배치(검증 후 mirror).
