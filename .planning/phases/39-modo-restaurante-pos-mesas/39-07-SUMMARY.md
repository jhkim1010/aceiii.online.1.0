---
phase: 39-modo-restaurante-pos-mesas
plan: 07
subsystem: frontend (SalonView + 주문/결제) + backend (totalAmount sync + getSale)
tags: [restaurant, salonview, order-modal, payment-modal, split-merge, mp-qr, next-dynamic, checkpoint-pending]
status: checkpoint-pending
requires:
  - 39-03 (print-agent print_temp 핸들러 — comanda/cuenta/영수증 실제 인쇄)
  - 39-05 (restaurant-sale 백엔드 라우트: order/timing/cuenta/pay/pay-merge)
  - 39-06 (StoreConfigContext.useRestaurantMode + restaurantCategoryIds + useRestaurantTables SWR)
provides:
  - "nueva-venta 식당 분기 (useRestaurantMode → SalonView vs VcontrolHome, next/dynamic ssr:false)"
  - "SalonView 배치도 판매 화면 (정규화 좌표 렌더, 상태 3색, 편집 진입점 없음 — 권한 분리)"
  - "OrderModal (웨이터 branchId 필터 + 메뉴 restaurantCategoryIds 필터 + 수량 + 주방 전달 comanda)"
  - "TableCard 타이밍 버튼 (served/closed → PATCH :id/timing)"
  - "RestaurantPaymentModal (cuenta + 현금/카드/MP + split 균등·임의 + merge + 영수증, MP QR processedIntentRef guard)"
  - "백엔드 placeOrder totalAmount 동기화 (결제 검증 통과 보장) + GET :id 조회 라우트"
affects:
  - ventago-app/src/pages/nueva-venta/index.tsx (식당 분기)
  - api-ventago restaurant-sale.service/controller (totalAmount sync + getSale)
tech-stack:
  added: []
  patterns:
    - "useStoreConfig().useRestaurantMode 분기 + loaded Skeleton (FOUC 회피)"
    - "정규화 좌표(0~1) → containerRef getBoundingClientRect 픽셀 변환 (렌더 전용, w/h 미저장)"
    - "형태+좌석수 비례 크기 (BASE[shape] * (0.8 + min(seats,12)/12*0.6))"
    - "useSellers() 인자 없는 전체 → 호출처 branchId 필터 (seller.branchId === branchId)"
    - "메뉴 = products + restaurantCategoryIds 필터 (null/빈 → 전체 폴백)"
    - "split = N등분 균등(잔돈 첫 행) + 결제수단별 임의 금액 입력 둘 다"
    - "merge = saleIds 배열 [현재, ...선택] → pay-merge (각 sale 유지, 백엔드 grand-total 검증)"
    - "MP QR = McdpgQrPanel 재사용 + socket+polling processedIntentRef 멱등 트리거"
    - "placeOrder totalAmount = Σ subtotal 동기화 (결제 검증 sum !== totalAmount 통과 보장)"
key-files:
  created:
    - ventago-app/src/views/restaurante/SalonView.tsx
    - ventago-app/src/views/restaurante/components/TableCard.tsx
    - ventago-app/src/views/restaurante/components/OrderModal.tsx
    - ventago-app/src/views/restaurante/components/RestaurantPaymentModal.tsx
  modified:
    - ventago-app/src/pages/nueva-venta/index.tsx
    - api-ventago/src/app/sales/restaurant-sale/restaurant-sale.service.ts
    - api-ventago/src/app/sales/restaurant-sale/restaurant-sale.controller.ts
decisions:
  - "placeOrder totalAmount 동기화를 백엔드에서 강제 (프론트 전송 금액보다 신뢰 + 변조 방지 + 단일 진실 소스) — 39-05 follow-up 갭 해소"
  - "timing 호출 PUT→PATCH 정정 (컨트롤러가 @Patch(':id/timing'))"
  - "GET :id 조회 라우트 신규 추가 (39-05 컨트롤러에 sale 조회 부재 — 결제 모달 합산 표시 불가)"
  - "merge 표시 총액은 현재 테이블 saleTotal — grand-total 정확 검증은 백엔드 최종 (프론트 1차 표시)"
  - "MP 라인 존재 시에만 320px QR side-panel 노출 (PaymentSummaryModal 패턴)"
metrics:
  duration: ~14min
  tasks: 3 of 4 (Task 4 = 브라우저 human-verify checkpoint)
  files: 7
  completed: 2026-06-14
requirements: [REQ-4, REQ-6, REQ-7, REQ-8, REQ-9, REQ-10, REQ-11]
---

# Phase 39 Plan 07: SalonView 주문/결제 Summary

req4/6/7/8/9/10/11 프론트 사용자 대면 흐름 전체 완성. (1) nueva-venta 가 `useStoreConfig().useRestaurantMode` 로 SalonView(식당) vs VcontrolHome(소매) 분기, loaded 전 Skeleton 으로 FOUC 회피, 둘 다 next/dynamic ssr:false. (2) SalonView 가 useRestaurantTables 를 정규화 좌표→픽셀로 캔버스에 절대 배치, 상태 3색(libre/ocupada/por_cobrar), 클릭 시 status 분기(libre/ocupada→주문, por_cobrar→결제), 편집 진입점 없음(권한 분리 req5). (3) TableCard 가 형태+좌석수 비례 크기 + 타이밍 버튼(served/closed → PATCH :id/timing). (4) OrderModal 이 웨이터(useSellers 전체 → branchId 필터) + 메뉴(products + restaurantCategoryIds 필터) + 수량 + 주방 전달(POST order → comanda emit). (5) RestaurantPaymentModal 이 cuenta(사전, DRAFT 유지) + 현금/카드/MP + split(N등분 균등 + 임의 금액) + merge(pay-merge) + 영수증 + MP QR(McdpgQrPanel + processedIntentRef guard). 백엔드는 placeOrder totalAmount 동기화(결제 검증 통과 보장) + GET :id 조회 라우트 추가. **Task 4(브라우저 검증)는 human-verify checkpoint — 미완료(checkpoint-pending).**

## What Was Built

### Task 1: nueva-venta 분기 + SalonView + TableCard
- **nueva-venta/index.tsx**: `useStoreConfig()` 에서 `useRestaurantMode`/`loaded` 추출. loaded 전 `<Skeleton>` (소매 뷰 깜빡임 회피). `useRestaurantMode ? <SalonView/> : <VcontrolHome/>`. SalonView 도 `next/dynamic(ssr:false)`. WithAccess + SaleProductsProvider 래핑 보존.
- **SalonView.tsx**: `useContext(BranchContext).selectedBranchId`(폴백 user.branchId) → `useRestaurantTables(branchId)`. containerRef + resize 측정으로 컨테이너 px 확보 → TableCard 에 전달. status 클릭 분기(`por_cobrar`→RestaurantPaymentModal, else→OrderModal). 헤더에 상태 범례(편집 버튼 없음). 로딩/에러/빈 상태 처리.
- **TableCard.tsx**: 형태+좌석수 비례 크기(`BASE[shape] * (0.8 + min(seats,12)/12*0.6)`, shape별 borderRadius). 상태 3색(libre=중립 #232342, ocupada=골드 보더/틴트, por_cobrar=골드 강조). 타이밍 버튼(점유 시) Servido/Consumido → `PATCH /restaurant-sale/:id/timing { event }`. 에러 인라인 Alert + 토스트.

### Task 2: OrderModal
- **OrderModal.tsx**: 웨이터 = `useSellers()`(인자 없는 전체) → `sellers.filter(s => s.branchId === branchId)` Select. 메뉴 = `apiConnector.get('/products/by-parent?parent=false')` → `restaurantCategoryIds` 필터(null/빈 → 전체 폴백) → 카테고리 탭 + 그리드. 장바구니 수량 +/-. "Enviar a cocina" → `POST /restaurant-sale/order { tableId, sellerId, sellerName, items }` → onOrdered → mutate. 점유 테이블 추가 주문 동일 라우트. 에러 더블 노출.

### Task 3: RestaurantPaymentModal
- **RestaurantPaymentModal.tsx**: sale 합산 = `GET /restaurant-sale/:id`(items + totalAmount). cuenta = `POST :id/cuenta`(DRAFT 유지). 결제수단 `/payment-methods` → split(N등분 균등 `Math.floor` + 잔돈 첫 행 / 결제수단별 임의 금액 입력 둘 다). 단일 = `POST :id/pay`, merge = 토글 → 다중 선택 → `POST pay-merge { saleIds:[현재,...선택], payments }`. MP QR = McdpgQrPanel side-panel(1fr+320px) + useMpAccounts/useMpPaymentIntent/useMpApprovedSocket + `processedIntentRef` double-trigger guard. sandbox=골드/prod=cyan. 성공 → onPaid → mutate.

### 백엔드 (totalAmount sync + getSale)
- **restaurant-sale.service.ts**: placeOrder 가 매 주문 누적 후 `totalAmount = Σ(모든 item.subtotal)` 갱신 → settleSale 의 `sum !== Number(sale.totalAmount)` integer 검증이 통과하도록 보장(39-05 follow-up 갭). `getSale(storeId, saleId)` 추가(items + totalAmount, storeId 스코프).
- **restaurant-sale.controller.ts**: `@Get(':id')` 라우트(구체 경로 아래) → getSale.

## Acceptance Criteria Verification

| 기준 | 결과 |
|------|------|
| nueva-venta useRestaurantMode 분기 + SalonView dynamic(ssr:false) + VcontrolHome 보존 | PASS (grep 2) |
| SalonView useRestaurantTables + 정규화 좌표→픽셀(posX*) | PASS |
| SalonView 편집 진입점 0 (권한 분리 req5) | PASS (drag/Agregar/position 0건, removeEventListener 만 매칭) |
| TableCard 상태 3색 + 형태별 borderRadius | PASS |
| TableCard 타이밍 PATCH /restaurant-sale/:id/timing { event } | PASS (PUT→PATCH 정정) |
| OrderModal useSellers + branchId 필터 + products + restaurantCategoryIds 필터 | PASS (grep 5) |
| OrderModal 주방 전달 POST /restaurant-sale/order + mutate | PASS |
| RestaurantPaymentModal cuenta + pay + pay-merge | PASS (grep 11) |
| split N등분 + 임의 금액 둘 다 (D-02) | PASS (applyEvenSplit + addPaymentLine) |
| merge saleIds 배열 전송 | PASS |
| MP QR processedIntentRef double-trigger guard | PASS |
| 결제 성공 후 mutate (테이블 libre) | PASS (onPaid) |
| 에러 인라인 Alert + 토스트 더블 | PASS |
| .delete( 0 (apiConnector.remove/patch) | PASS (0건) |
| ESLint 5파일 0 에러 | PASS |
| tsc --noEmit (front + back) 0 | PASS |
| restaurant-sale.service spec 회귀 (totalAmount sync 후) | PASS (14/14) |

## Tasks Completed

| Task | Name | Submodule Commit | Parent Pointer |
|------|------|------------------|----------------|
| BE | totalAmount sync + GET :id | api-ventago bbf156f | 10c75ec |
| 1 | nueva-venta 분기 + SalonView + TableCard | ventago-app 23c78ac | 10c75ec |
| 2 | OrderModal | ventago-app 487d51f | 10c75ec |
| 3 | RestaurantPaymentModal | ventago-app d416c66 | 10c75ec |
| 4 | 브라우저 human-verify | **PENDING (checkpoint)** | — |

## Deviations from Plan

플랜 의도대로 구현. 결제 동작 보장을 위한 백엔드 최소 수정 + 실 라우트 정합 정정:

1. **[Rule 1 - 결제 깨짐 방지] placeOrder totalAmount 동기화 (백엔드)**: 39-05 가 SaleItem.subtotal 만 기록하고 sale.totalAmount 를 채우지 않아, settleSale 의 `sum !== Number(sale.totalAmount)` 검증이 0/stale totalAmount 와 비교되어 결제가 항상 BadRequest 가 되는 갭. placeOrder 가 매 주문 누적 직후 `totalAmount = Σ subtotal` 을 갱신하도록 백엔드 수정. 프론트 전송 금액보다 신뢰(변조 방지) + 단일 진실 소스. spec 14/14 회귀 통과. 커밋: api-ventago bbf156f.

2. **[Rule 3 - 실 라우트] GET :id 조회 라우트 추가 (백엔드)**: 39-05 컨트롤러에 sale 조회 GET 이 없어 RestaurantPaymentModal 이 합산 내역/총액을 표시할 수 없음. `getSale(storeId, saleId)` + `@Get(':id')`(구체 경로 아래) 추가, storeId 스코프(IDOR 방지). 커밋: api-ventago bbf156f.

3. **[Rule 1 - 실 라우트] timing 호출 PUT→PATCH 정정 (프론트)**: 컨트롤러가 `@Patch(':id/timing')` 인데 플랜 예시는 PATCH 의도였으나 초안에서 PUT 으로 작성 → `apiConnector.patch` 로 정정.

4. **[명확화] merge 표시 총액**: merge 시 프론트는 현재 테이블 saleTotal 만 표시(다른 sale 총액 합산 표시는 생략). 백엔드가 grand-total = Σ sale.totalAmount 를 최종 검증(39-05 settleSale)하므로 프론트는 1차 표시만 담당. payments 합계가 백엔드 grand-total 과 불일치하면 BadRequest 로 방어.

## Known Stubs

없음 — 모든 경로 실 백엔드 라우트(39-05 + 본 plan 추가 GET :id) 연결. comanda/cuenta/영수증 실제 감열 출력은 print-agent print_temp 핸들러(39-03)에 의존(운영 재빌드는 39-03 사용자 액션). MP QR 실제 결제는 운영 MP 계정 + 단말 socket 필요(Phase 29 인프라).

## Threat Model Mitigations Applied

| Threat | Mitigation 적용 |
|--------|----------------|
| T-39-16 (split 금액 변조) | 프론트 split 합계 표시(paidSoFar/remaining) 1차 + 백엔드 settleSale `sum !== totalAmount` integer 정확 검증(최종). totalAmount 동기화로 검증 기준 신뢰 확보 |
| T-39-17 (MP QR 중복 트리거) | processedIntentRef double-trigger guard — socket + polling 양쪽 도착해도 1회만 confirmPayment (Phase 29 패턴 재사용) |
| T-39-18 (SalonView 편집 진입) | SalonView/TableCard 에 추가/드래그/삭제 버튼 0 — 편집은 39-06 configuración 전용 (drag/Agregar/position 키워드 0건) |

## Checkpoint (Task 4 — human-verify, BLOCKING)

브라우저 + print-agent 수동 검증 대기. 상세 단계는 PLAN.md Task 4 how-to-verify 참조:
1. ./dev.sh + npm run dev:print
2. 식당 매장 로그인 → nueva-venta → SalonView 배치도 (소매는 VcontrolHome)
3. 테이블 클릭 → 웨이터 선택 → 식당 카테고리 메뉴만 → 수량 → 주방 전달 → comanda PNG
4. 같은 테이블 2회 주문 → 단일 sale items 누적(DB)
5. Servido/Consumido → served_at/closed_at(DB)
6. cuenta → PNG + DRAFT 유지
7. 결제 현금 단일 + split(N등분) → sale_payment_methods 복수 행, DRAFT→PAID, 테이블 libre, 영수증
8. merge 2 테이블 → 각 sale PAID(table_id 유지)
9. 소매 매장 sale/통계 회귀 0

승인("approved") 시 39-07 완료, 문제 시 단계+화면 설명.

## Self-Check: PASSED

(아래 자동 검증 결과 참조)
