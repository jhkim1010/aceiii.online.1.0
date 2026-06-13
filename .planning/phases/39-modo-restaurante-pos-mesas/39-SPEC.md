# Phase 39: Modo Restaurante — POS por mesas — Specification

**Created:** 2026-06-13
**Ambiguity score:** 0.16 (gate: ≤ 0.20)
**Requirements:** 11 locked

## Goal

식당(restaurante) 업종을 위한 테이블 단위 POS 모드를 기존 Ventago 시스템 **확장**으로 추가한다. configuración에서 매장별 `useRestaurantMode` 플래그를 켜면 nueva-venta 화면이 기존 소매 뷰(`VcontrolHome`) 대신 **테이블 배치도(salón) 뷰**로 분기된다. 웨이터(seller)가 테이블을 클릭 → categoría·음식 메뉴·수량 입력 → 감열 프린터로 comanda(주방 전표) 출력 → 테이블별 두 타이밍 이벤트(음식 나옴 / 소비 완료)를 수동 기록 → resumen de pago 출력 후 현금/카드/MercadoPago로 수금한다. 소매 매장은 플래그가 꺼져 있어 **무영향**.

## Background

scout 결과 — 식당 전용 자산은 코드베이스에 **전무**하며, 재사용할 인프라는 모두 존재한다:

- **`StoreConfig` 모델** (`api-ventago/src/app/store/config/storeConfig.model.ts`): `useSupplier`/`useSeason`/`useSize` 등 `use*` BOOLEAN 플래그 패턴 확립. `useRestaurantMode` 추가의 깔끔한 선례. — 식당 플래그 없음.
- **`Sale` 모델** (`api-ventago/src/app/sales/sales.model.ts`): `SaleStatus`(DRAFT/INVOICED/PENDING_PAYMENT/PAID/NULLIFIED/NULLIFICATION), `SaleSource`(pos/online/factura), `SaleActivityType`(sale/movido/fallado), `sellerId` FK → `Seller`. — `table_id`·타이밍 컬럼·restaurant source 전부 없음.
- **`print.service`** (`api-ventago/src/app/print/print.service.ts`): `emitPrintTemp`/`emitPrintInvoice`/`emitFiscalReceipt`/`emitPrintBarcode`/`emitPrintQr` — 모두 `/print-agent` namespace의 `branch:{id}` room으로 fire-and-forget emit. comanda·resumen 출력은 `emitPrintTemp` 패턴 재사용.
- **결제**: `payment_methods` + `sale_payment_methods`(분할결제 지원) + MercadoPago 모듈(QR/intents/webhook) 존재.
- **웨이터**: `sellers` 모델(branchId/linkedUserId) — 식당 웨이터 = branchId 설정된 seller로 직접 매핑.
- **프론트 venta**: `ventago-app/src/pages/nueva-venta/index.tsx` → `views/homes/VcontrolHome.tsx`. configuración: `ventago-app/src/pages/configuracion/`.

**1차 산출물(아직 존재하지 않는 것):** `restaurant_tables` 테이블, `sales`의 식당 nullable 컬럼, `useRestaurantMode` 플래그, `SalonView` 프론트 화면, 배치도 편집기, comanda/resumen 출력 흐름, 타이밍 기록.

## Requirements

1. **Modo restaurante 플래그**: 매장별 식당 모드 on/off.
   - Current: `StoreConfig`에 식당 관련 플래그 없음
   - Target: `store_configs.use_restaurant_mode` BOOLEAN(default false) 추가. configuración admin UI에서 토글
   - Acceptance: 플래그 OFF 매장은 nueva-venta가 기존 `VcontrolHome` 렌더, ON 매장은 `SalonView` 렌더. 한 계정에 소매·식당 매장 혼용 시 매장별로 올바르게 분기

2. **restaurant_tables 테이블**: 테이블 배치도 영속 모델.
   - Current: 테이블 개념의 테이블/모델 없음
   - Target: `restaurant_tables`(store/branch 스코프) — 형태 enum(원형/긴원형/정사각/직사각), x·y 위치(평면 좌표), 좌석수, 상태(libre/ocupada), `current_sale_id` 등. store_id/branch_id FK
   - Acceptance: 테이블 CRUD API 존재. branch별로 테이블 목록 조회 시 위치·형태·상태가 정확히 반환됨

3. **sales 식당 전용 컬럼 (전부 nullable)**: 소매 모드 무영향 보장.
   - Current: `Sale`에 table_id·타이밍 컬럼 없음
   - Target: `sales`에 `table_id` FK(nullable) + 주문 타이밍 컬럼(`ordered_at`, `served_at`, `closed_at` 등) 추가, 전부 nullable
   - Acceptance: 마이그레이션 후 기존 소매 sale 생성/조회가 동일하게 동작(회귀 0). 식당 sale은 table_id가 채워짐. 기존 매출 통계 쿼리(activity_type='sale') 결과 불변

4. **SalonView 프론트 분기**: 식당 전용 판매 화면.
   - Current: nueva-venta는 `VcontrolHome` 단일 렌더
   - Target: `useRestaurantMode` 플래그로 `SalonView`(신규) / `VcontrolHome`(기존) 분기. SalonView는 배치도에 테이블을 형태·위치대로 표시, 상태별 색상 구분
   - Acceptance: 식당 매장 로그인 → nueva-venta 진입 시 배치도 뷰 표시, 각 테이블이 DB의 위치/형태/상태대로 렌더. 코드 스플리팅(`next/dynamic`, ssr:false) 적용

5. **배치도 편집기 (configuración 전용, 자유 드래그)**: 관리자가 테이블 배치.
   - Current: 배치 편집 UI 없음
   - Target: configuración 영역에서만 테이블 추가/이동/삭제 + 형태 선택 + x/y 드래그 배치(평면 편집기). 회전·리사이즈는 제외
   - Acceptance: configuración에서 테이블 드래그 시 x/y 좌표가 저장되고 SalonView에 반영됨. SalonView(판매 화면)에서는 배치 편집 진입점 없음(권한 분리)

6. **주문 → comanda 감열 출력**: 주방 전달.
   - Current: comanda 출력 흐름 없음
   - Target: 테이블 클릭 → 웨이터(seller) 선택 → categoría·메뉴·수량 입력 → "주방으로 전달" 시 해당 branch의 comandera로 comanda 출력(`emitPrintTemp` 패턴 재사용)
   - Acceptance: 주문 확정 시 `branch:{id}` room으로 print emit 발생. comanda에 테이블명·웨이터·품목·수량 포함. KDS 화면은 생성하지 않음

7. **타이밍 수동 마킹 (웨이터, 2 이벤트)**: 테이블별 시간 기록.
   - Current: 타이밍 기록 없음
   - Target: SalonView 테이블 카드의 버튼으로 웨이터가 "음식 나옴"(served_at), "소비 완료=결제 직전"(closed_at)을 마킹. 자동 트리거/KDS 마킹 아님
   - Acceptance: served_at/closed_at가 해당 sale 행에 타임스탬프로 기록됨. ordered_at→served_at(조리 시간), served_at→closed_at(체류 시간)을 계산 가능한 데이터가 남음

8. **열린 주문 = DRAFT sale 누적**: 미결제 테이블 표현.
   - Current: 열린 주문 상태 모델 없음
   - Target: 점유 테이블 = 상태 DRAFT인 sale 1건. 추가 주문 = 동일 sale에 sale_items 추가. 신규 SaleStatus enum 추가 없음
   - Acceptance: 같은 테이블에 2회 이상 주문 추가 시 단일 DRAFT sale의 items가 누적됨. 결제 시 DRAFT→PAID 전환. 신규 상태 enum/DB CHECK 변경 없음

9. **resumen de pago 출력 (사전 cuenta + 결제 후 영수증)**: 감열 2종.
   - Current: resumen 출력 없음
   - Target: (a) 결제 전 손님 요청 시 합산 내역(cuenta, 비공식/non-fiscal) 감열 출력, (b) 결제 완료 후 영수증 출력. 둘 다 `branch:{id}` print emit
   - Acceptance: 결제 전 cuenta 출력 시 테이블 합산 금액·품목이 인쇄되고 sale 상태는 DRAFT 유지. 결제 후 영수증 출력은 PAID 전환 후 발생

10. **결제 — 현금/카드/MercadoPago + split/merge**: 수금 기록.
    - Current: 식당 결제 흐름 없음 (소매 sale_payment_methods는 존재)
    - Target: 테이블 결제 시 현금/카드/MP 수금수단 기록(기존 `sale_payment_methods` 재사용, MP는 기존 QR/intent 흐름). 추가로 인원별 split(한 계산서 분할) + 여러 테이블 merge(합산 결제) 지원
    - Acceptance: 결제 수단별 금액이 sale_payment_methods에 기록됨. split 시 한 테이블 금액이 복수 결제로 분할 기록됨. merge 시 복수 테이블의 DRAFT sale이 하나의 결제로 정산됨

11. **메뉴 = products 재사용 + 식당 카테고리 필터**: 음식 메뉴 소스.
    - Current: 식당 전용 메뉴 테이블 없음
    - Target: 기존 `products`/`categories`를 메뉴로 재사용. 식당 모드에서는 지정된 categoría만 메뉴로 노출(필터). 신규 메뉴 테이블 생성 없음
    - Acceptance: SalonView 주문 입력 시 products 기반 메뉴가 categoría별로 표시됨. 식당 카테고리 필터로 비식당 상품이 메뉴에서 제외됨. 판매 시 기존 재고·가격·매출 통계와 자동 통합

## Boundaries

**In scope:**
- `useRestaurantMode` 매장별 플래그 (store_configs) + configuración 토글
- `restaurant_tables` 테이블 + CRUD + 자유 드래그(x/y) 배치도 편집기 (configuración 전용)
- `sales` 식당 nullable 컬럼 (table_id + 타이밍)
- `SalonView` 프론트 분기 (플래그 기반)
- 주문 → comanda 감열 출력 (기존 print-agent 재사용)
- 웨이터 수동 타이밍 마킹 (음식 나옴 / 소비 완료)
- 열린 주문 = DRAFT sale 누적 모델
- resumen 감열 출력 (사전 cuenta + 결제 후 영수증)
- 현금/카드/MercadoPago 수금 + split(인원별 분할) + merge(테이블 합산) 결제
- 메뉴 = products + 식당 카테고리 필터 재사용
- 웨이터·gasto·매상 통계 = 기존 모듈 자동 통합 (신규 구현 없음)

**Out of scope:**
- **KDS(주방 디스플레이 화면)** — Round 1에서 comanda 감열 출력만 선택. 후속 Phase 후보
- **상세 타이밍 분석 리포트/대시보드** — 기본 타이밍 데이터만 기록(req 7). 차트·통계 분석은 후속 Phase
- **예약(reserva) / 대기자(waitlist) 관리** — MVP 범위 밖. 별도 backlog
- **신규 메뉴 테이블 / 경량 메뉴 모델** — products 재사용으로 결정(req 11)
- **신규 SaleStatus enum / DB CHECK 변경** — DRAFT sale 재사용으로 결정(req 8)
- **테이블 회전/리사이즈 편집** — 위치(x/y)+형태 선택까지만(req 5)
- **외상(cuenta corriente) 개념** — 요구사항 원문에서 명시적으로 없음

## Constraints

- **기존 시스템 확장 only (재구축 X)**: 인증/세션보안/매장계층(store→branch→box→terminal)/sellers/payment-methods/mercadopago/print-agent/socket.io/CASL/배포를 그대로 재사용. 별도 식당 프로젝트 생성 금지.
- **소매 모드 무영향**: `sales` 신규 컬럼은 전부 nullable. 마이그레이션이 기존 소매 sale 생성/조회/통계에 회귀를 일으키면 안 됨.
- **PG10/PG15 호환**: 운영 PG10 + 로컬 PG18. 마이그레이션 SQL은 양쪽 호환 문법 사용 (snake_case 컬럼, `GENERATED AS IDENTITY` 등 PG10 미지원 기능 회피).
- **connection pool 절약**: 식당 모드 신규 쿼리는 pool 낭비 없도록(현재 min=10/max=80). slow query 100ms 이상 즉시 최적화.
- **프론트 300ms 타겟 + 코드 스플리팅**: SalonView는 `next/dynamic(ssr:false)`. 참조 데이터는 SWR 훅.
- **ESLint**: newline-before-return / lines-around-comment / no-unused-vars 빌드 차단 규칙 준수.
- **comanda/resumen 출력**: 기존 `emitPrintTemp` + `branch:{id}` room 패턴 재사용 (신규 print 인프라 금지).

## Acceptance Criteria

- [ ] `store_configs.use_restaurant_mode` 컬럼 존재 + configuración 토글 동작
- [ ] 플래그 OFF → `VcontrolHome`, ON → `SalonView` 분기 (매장별 혼용 정상)
- [ ] `restaurant_tables` 테이블 + CRUD API 존재, 형태/x·y 위치/좌석수/상태 저장·조회
- [ ] `sales`에 table_id + 타이밍 컬럼(nullable) 추가, 기존 소매 sale 회귀 0
- [ ] configuración 배치도 편집기에서 드래그 시 x/y 저장 → SalonView 반영
- [ ] SalonView 판매 화면에는 배치 편집 진입점 없음 (권한 분리)
- [ ] 주문 확정 시 `branch:{id}` room으로 comanda print emit (테이블명·웨이터·품목·수량 포함)
- [ ] KDS 화면 미생성 확인
- [ ] served_at/closed_at가 웨이터 버튼 마킹으로 sale 행에 타임스탬프 기록
- [ ] 같은 테이블 2회+ 주문 시 단일 DRAFT sale에 items 누적, 결제 시 DRAFT→PAID
- [ ] 신규 SaleStatus enum / DB CHECK 변경 없음
- [ ] 결제 전 cuenta 감열 출력 (DRAFT 유지) + 결제 후 영수증 출력 (PAID 후)
- [ ] 현금/카드/MP 수금이 sale_payment_methods에 기록
- [ ] split(인원 분할) + merge(테이블 합산) 결제 동작
- [ ] SalonView 메뉴가 products + 식당 카테고리 필터로 표시, 판매가 기존 재고·매출 통계와 통합

## Ambiguity Report

| Dimension          | Score | Min  | Status | Notes                                          |
|--------------------|-------|------|--------|------------------------------------------------|
| Goal Clarity       | 0.90  | 0.75 | ✓      | 메뉴·주방·타이밍·배치·결제 전부 결정             |
| Boundary Clarity   | 0.85  | 0.70 | ✓      | 명시적 out-of-scope 7항목, split/merge IN 확정  |
| Constraint Clarity | 0.75  | 0.65 | ✓      | 확장 only, nullable, PG10/15, pool, 300ms      |
| Acceptance Criteria| 0.82  | 0.70 | ✓      | 15개 pass/fail 체크박스                         |
| **Ambiguity**      | 0.16  | ≤0.20| ✓      | 3 라운드 후 gate 통과                           |

Status: ✓ = met minimum, ⚠ = below minimum (planner treats as assumption)

## Interview Log

| Round | Perspective     | Question summary               | Decision locked                                      |
|-------|-----------------|--------------------------------|------------------------------------------------------|
| 1     | Researcher      | 메뉴 소스?                     | products 재사용 + 식당 카테고리 필터                  |
| 1     | Researcher      | 주방 전달 방식?                | 감열 comanda 출력만 (KDS 제외)                        |
| 1     | Researcher      | 타이밍 이벤트 트리거?          | 웨이터가 SalonView에서 수동 마킹                      |
| 2     | Boundary Keeper | 배치도 충실도?                 | 자유 드래그 평면 편집기 (x/y + 형태)                  |
| 2     | Simplifier      | 열린 주문 모델?                | 기존 DRAFT sale 재사용 (신규 enum 없음)               |
| 2     | Boundary Keeper | 명시적 제외 범위?              | KDS · 상세 타이밍 리포트 · 예약/대기자 제외           |
| 3     | Boundary Keeper | 결제 단위 (split/merge)?       | split/merge 포함                                      |
| 3     | Boundary Keeper | 배치도 편집 권한?              | admin/configuración 전용                              |
| 3     | Boundary Keeper | resumen 출력 시점?             | 사전 cuenta + 결제 후 영수증 둘 다                    |

---

*Phase: 39-modo-restaurante-pos-mesas*
*Spec created: 2026-06-13*
*Next step: /gsd-discuss-phase 39 — implementation decisions (테이블 상태머신, 배치도 좌표 스키마, comanda 페이로드, split/merge sale 정산 로직 등 HOW)*
