# Phase 39 — Modo Restaurante · Brainstorm Notes (2026-06-13)

> Pre-spec 메모. `/gsd-spec-phase 39` 이 이걸 입력으로 삼아 SPEC 을 정제한다.

## 요구사항 원문 (사용자, 2026-06-13)

식당용 판매 모듈:
- 메뉴가 단순하다.
- 외상 개념 없음.
- 매장 내 **테이블 단위**로 컨트롤. 테이블 모양(원형/긴 원/정사각/직사각)과 **위치 배정을 사용자가 지정** 가능.
- 테이블 아이콘 선택 → 웨이터 이름 선택 → categoría · 음식 메뉴 · 수량 입력.
- 주문이 **주방으로 전달**.
- 음식이 나오기까지 걸린 시간이 테이블별 기록.
- 음식이 나온 뒤 **소비에 걸린 시간**도 테이블별 기록.
- 테이블 선택 → 감열 프린터로 **resumen de pago** 출력.
- **현금/카드/MercadoPago** 중 무엇으로 수금했는지 기록.
- 웨이터(vendedor) 컨트롤, gasto 컨트롤, 매상 관리도 가능.
- configuración(admin)에서 **식당용으로 셋팅하면 venta 화면이 식당 모드로** 나타나게.

## 확정 결정 (brainstorming)

- **D-1 — 재구축 X, 기존 시스템 확장.** 별도 식당 전용 프로젝트를 만들지 않는다. 인증/세션보안/매장계층(store→branch→box→terminal)/sellers/gastos/payment-methods/mercadopago/print-agent(comandera)/socket.io/CASL/배포를 그대로 재사용. 식당 모듈의 본질은 "새 결제 엔진"이 아니라 **같은 sales 엔진 위에 다른 주문 UI(테이블·웨이터·주방)를 씌우는 것**. "메뉴 단순 + 외상 없음" 조건이 식당을 소매보다 오히려 단순한 케이스로 만든다.
- **D-2 — 신규로 만드는 것 (최소):**
  1. `restaurant_tables` — 배치도(형태 enum, x/y 위치, 좌석수, 상태). store/branch 스코프.
  2. `sales` 식당 전용 컬럼 — `table_id` FK + 주문 타이밍 컬럼들. **모두 nullable → 소매 모드 무영향.**
  3. "modo restaurante" 플래그 — `store_configs` (기존 use_* 플래그 패턴).
  4. 전용 venta 프론트 화면 (`SalonView` 가칭).
- **D-3 — venta 화면 분기.** 플래그로 분기: 소매=기존 `VcontrolHome`, 식당=신규 Salón 뷰. 한 계정으로 소매·식당 매장 혼용 가능.
- **D-4 — MVP 우선.** Slice 1(본 Phase) = 식당모드 토글 + 테이블 배치도 편집/뷰 + 주문→주방(comanda 출력) + resumen 결제 + 기본 타이밍 기록. 후속 슬라이스(별도 Phase 후보) = KDS(주방 디스플레이) 고도화 + 상세 타이밍 분석 리포트.
- **D-5 — 관리/리포트 재사용.** 웨이터·gasto·매상 관리는 기존 모듈(sellers, gastos, sales 통계) 자동 통합. 본 Phase 신규 구현 최소화.

## 미해결 질문 (→ spec/discuss 에서 결정)

- **Q1 주방 전달 방식**: comandera(감열) 출력 vs 주방 화면(KDS) vs 둘 다. 기존 print-agent 인프라(`/print-agent` socket, `print_*` emit) 우선 검토.
- **Q2 타이밍 트리거**: 두 이벤트("음식 나옴", "소비 완료")를 누가/어디서 마킹하나? (주방이 ready 마킹 / 웨이터가 served·closed 마킹 등)
- **Q3 메뉴 소스**: 기존 `products`/`categories` 재사용 여부. 식당 단순 메뉴를 기존 상품에 매핑할지, 별도 경량 메뉴를 둘지.
- **Q4 배치도 충실도**: 자유 드래그 평면 편집기(픽셀 위치) vs 단순 그리드. UI 토큰 비용/구현 난이도 trade-off.
- **Q5 open-ticket 상태 모델**: 미결제 테이블의 "열린 주문"을 기존 sales DRAFT 로 표현할지, 별도 상태를 둘지. (테이블에 여러 차례 주문 추가 → 마지막에 합산 결제)

## 재사용 가능한 기존 자산 (탐색 결과)

- **sales**: `api-ventago/src/app/sales/` — `sales.model.ts`, `sales-create.service.ts`(print emit 포함), `sales.controller.ts`. status enum(DRAFT/PENDING_PAYMENT/PAID...), source enum(pos/online/factura), sellerId FK.
- **결제**: `payment_methods` + `sale_payment_methods`(분할결제 지원), MercadoPago `api-ventago/src/app/mercadopago/`(QR/intents/webhook).
- **웨이터**: `sellers` 모델 — 로그인 없이 존재 가능, branchId/linkedUserId. (식당 "웨이터" = branchId 설정된 seller)
- **프린트**: `api-ventago/src/app/print/` — `print.service.ts`(emitPrintInvoice/Temp/Fiscal), `print.gateway.ts`(`/print-agent` namespace, `branch:{id}` room). resumen 은 emitPrintTemp/Invoice 패턴 재사용.
- **socket**: `/print-agent` + `/realtime`(terminal:{id}, user:{id}, store:{id}) — KDS 라우팅에 `branch:{id}` 패턴 재사용 가능.
- **설정 플래그**: `store_configs`(use_supplier/use_size/...) + `stores.useVariants` 선례 → `use_restaurant_mode` 추가.
- **프론트 venta**: `ventago-app/src/pages/nueva-venta/index.tsx` → `views/homes/VcontrolHome.tsx`. configuración: `ventago-app/src/pages/configuracion/`.

## 시각 자료 (brainstorm companion)

- `.superpowers/brainstorm/.../feature-map.html` — 6블록 구성도
- `.superpowers/brainstorm/.../rebuild-vs-extend.html` — 재구축 vs 확장 비교 (결정: 확장)

## 다음 단계

`/gsd-spec-phase 39` — WHAT 정제(falsifiable success criteria) + Q1~Q5 해소 → `/gsd-discuss-phase 39` → `/gsd-plan-phase 39`.
