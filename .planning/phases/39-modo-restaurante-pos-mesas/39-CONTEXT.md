# Phase 39: Modo Restaurante — POS por mesas - Context

**Gathered:** 2026-06-14
**Status:** Ready for planning

<domain>
## Phase Boundary

기존 Ventago sales 엔진 위에 **테이블·웨이터·주방 주문 UI**를 씌우는 식당(restaurante) 모드. configuración의 매장별 `useRestaurantMode` 플래그가 nueva-venta 화면을 기존 소매 뷰(`VcontrolHome`) 대신 신규 `SalonView`(테이블 배치도)로 분기한다. 웨이터가 테이블 클릭 → 메뉴·수량 입력 → comanda 감열 출력 → 수동 타이밍 마킹 → resumen 출력 → 현금/카드/MP 수금. 소매 매장(플래그 OFF)은 무영향.

본 CONTEXT는 SPEC.md가 잠근 11개 요구사항(WHAT)의 **구현 방식(HOW)**만 다룬다. 논의한 회색지대: split/merge 정산 모델 · 테이블 상태↔DRAFT sale 동기화 · 배치도 좌표 스키마.

</domain>

<spec_lock>
## Requirements (locked via SPEC.md)

**11 requirements are locked.** See `39-SPEC.md` for full requirements, boundaries, and acceptance criteria.

Downstream agents MUST read `39-SPEC.md` before planning or implementing. Requirements are not duplicated here.

**In scope (from SPEC.md):**
- `useRestaurantMode` 매장별 플래그 (store_configs) + configuración 토글
- `restaurant_tables` 테이블 + CRUD + 자유 드래그(x/y) 배치도 편집기 (configuración 전용)
- `sales` 식당 nullable 컬럼 (table_id + 타이밍)
- `SalonView` 프론트 분기 (플래그 기반)
- 주문 → comanda 감열 출력 (기존 print-agent 재사용)
- 웨이터 수동 타이밍 마킹 (음식 나옴 / 소비 완료)
- 열린 주문 = DRAFT sale 누적 모델
- resumen 감열 출력 (사전 cuenta + 결제 후 영수증)
- 현금/카드/MercadoPago 수금 + split(인원 분할) + merge(테이블 합산) 결제
- 메뉴 = products + 식당 카테고리 필터 재사용
- 웨이터·gasto·매상 통계 = 기존 모듈 자동 통합

**Out of scope (from SPEC.md):**
- KDS(주방 디스플레이 화면) — comanda 감열 출력만. 후속 Phase 후보
- 상세 타이밍 분석 리포트/대시보드 — 기본 타이밍 데이터만 기록
- 예약(reserva) / 대기자(waitlist) 관리
- 신규 메뉴 테이블 / 경량 메뉴 모델 (products 재사용)
- 신규 SaleStatus enum / DB CHECK 변경 (DRAFT 재사용)
- 테이블 회전/리사이즈 편집 (위치 x/y + 형태 선택까지만)
- 외상(cuenta corriente) 개념

</spec_lock>

<decisions>
## Implementation Decisions

### split/merge 정산 모델
- **D-01 (split):** 인원별 분할 결제는 **단일 DRAFT sale 유지 + 복수 `sale_payment_methods` 행**으로 표현한다. 자식 sale을 만들지 않는다. 매출 통계 무오염(테이블 = 1 sale), 신규 enum/재고 영향 0. `sale_payment_methods`는 `saleId` FK이므로 한 sale에 결제수단·금액 행을 여러 개 INSERT.
- **D-02 (split 분할 기준):** **N등분(자동 균등) + 결제수단별 임의 금액 입력** 둘 다 지원. item 단위 귀속 분할(누가 무엇을 먹었는지)은 후속 Phase로 연기 (자식-sale 모델이 필요하므로 D-01과 충돌).
- **D-03 (merge):** 여러 테이블 합산 결제는 **각 테이블의 DRAFT sale을 그대로 유지한 채 한 결제 인터랙션으로 동시 PAID 전환**하고, 결제 금액을 각 sale의 `sale_payment_methods`에 배분 기록한다. 1 sale로 reparent 통합하지 **않는다** — 테이블별·웨이터별 매출 귀속과 재고(각 sale 이미 자기 items 차감)를 보존하기 위함. UI에서만 "합산 한 번" 인터랙션.
- **D-04 (merge 시각화):** merge는 **결제 시점 일회성**(결제 모달에서 복수 테이블 선택). salon 평면도에 영속 'merge 그룹'을 표시하지 않으며 `restaurant_tables`에 group_id 컬럼을 추가하지 않는다.

### 테이블 상태 ↔ DRAFT sale 동기화
- **D-05 (상태 저장):** `restaurant_tables`에 **명시 `status` 컬럼 + `current_sale_id` FK를 둘 다 저장**하고, 주문 생성/결제/cuenta 트랜잭션 경계에서 동기화한다. salon 렌더는 `restaurant_tables` 단일 조회로 끝나도록(sales JOIN 최소화 → pool 절약, 300ms 타겟). drift 방지는 서비스 레이어 트랜잭션으로 보장.
- **D-06 (상태 종류):** `libre` / `ocupada` / `por_cobrar`. `por_cobrar`는 cuenta(사전 합산) 요청 또는 결제 직전 상태 — salon에서 색상으로 구분(3단계). 예약/대기자 상태는 SPEC out-of-scope.
- **D-07 (current_sale_id):** 점유 테이블 = `current_sale_id`가 가리키는 DRAFT sale 1건. 추가 주문 = 동일 sale에 sale_items 추가(req 8). 결제 완료 시 sale DRAFT→PAID, 테이블 `status=libre` + `current_sale_id=NULL`로 같은 트랜잭션에서 리셋.

### 배치도 좌표 스키마
- **D-08 (좌표계):** 테이블 x/y는 **정규화 0~1 float**로 저장. 캔버스 크기 무관 비율 배치 → 편집기/SalonView/태블릿/폰에서 동일 레이아웃, 반응형 300ms 타겟 친화. 편집기 ↔ 런타임 좌표 일관성 확보.
- **D-09 (다중 salón):** MVP UI는 **1 branch = 1 평면**이지만, `restaurant_tables`에 **nullable `zone`(또는 `salon_name`) 컬럼을 미리 추가**해 다층/테라스 확장 여지를 저비용으로 확보. 컬럼만 두고 UI 다중-평면 전환은 후속 Phase.
- **D-10 (테이블 크기):** 형태 enum(원형/긴원형/정사각/직사각)별 베이스 크기에 **좌석수 비례 스케일** 적용(2인<4인<8인). w/h를 따로 저장하지 않고 형태+좌석수에서 파생(리사이즈는 req5 out-of-scope). 겹침 방지 계산은 SalonView 렌더 책임.

### Claude's Discretion
선택하지 않은 두 영역은 SPEC 제약에 맞춰 다음 기본값으로 진행(plan 단계 재조정 가능):
- **comanda 증분 주문:** "주방으로 전달" 시 **새로 추가된 sale_items만** comanda로 출력(전체 재출력 X — 주방 워크플로 자연스러움). 라운드(curso)는 sale_items의 `created_at` 묶음으로 추적하고 **신규 round/curso 컬럼을 추가하지 않는다**. comanda 페이로드는 `emitPrintTemp(branchId, data)` 패턴 재사용 — 테이블명·웨이터·이번 라운드 품목·수량 포함.
- **메뉴 카테고리 필터:** 식당 메뉴로 노출할 카테고리는 **`store_config`에 식당 카테고리 id 목록(JSON/배열)으로 저장**(매장별 유연, `categories` 테이블 스키마 무변경). SalonView 주문 입력 시 이 목록의 categoría만 products 기반 메뉴로 표시.
- comanda/resumen 출력은 모두 `print.service`의 `emitPrintTemp` + `branch:{id}` room 패턴 재사용 (신규 print 인프라 금지 — SPEC constraint).
- `useRestaurantMode` 플래그 default = **false**(소매 무영향). 기존 `StoreConfig` use_* 플래그가 default true인 것과 다름에 주의.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase spec (locked requirements)
- `.planning/phases/39-modo-restaurante-pos-mesas/39-SPEC.md` — 11 locked requirements, boundaries, acceptance criteria. **MUST read before planning or implementing.**
- `.planning/phases/39-modo-restaurante-pos-mesas/39-BRAINSTORM-NOTES.md` — 요구사항 원문 + 확정 결정(D-1~D-5, 확장 only) 배경

### DB schema reference (SQL/migration 작성 전 필수 — 추측 금지)
- `.planning/intel/db-schema-tables.md` — 133개 테이블 전체 컬럼 (타입/NOT NULL/default)
- `.planning/intel/db-schema-fks.md` — 모든 외래 키 관계

### Backend 재사용 대상 (확장 only)
- `api-ventago/src/app/sales/sales.model.ts` — `Sale` 모델. SaleStatus(DRAFT='Borrador'...), SaleSource(pos/online/factura), SaleActivityType(sale/movido/fallado), sellerId FK. `storeClientId`가 nullable 컬럼 추가 선례 → `table_id`+타이밍 컬럼 동일 패턴
- `api-ventago/src/app/sales/sales-payment-methods/sales-payment-method.model.ts` — `SalePaymentMethod`(saleId FK + paymentMethodId + paymentMethodOptionId + amount). split = 한 sale에 복수 행, merge = 복수 sale 동시 기록
- `api-ventago/src/app/store/config/storeConfig.model.ts` — `StoreConfig` use_* BOOLEAN 패턴 → `useRestaurantMode` (default false) + 식당 카테고리 id 목록 컬럼
- `api-ventago/src/app/print/print.service.ts` — `emitPrintTemp(branchId, data)` → `branch:{id}` room의 `print_temp` emit (fire-and-forget). comanda + resumen 재사용. `emitPrintInvoice`/`emitPrintQr`도 동일 게이트웨이
- `api-ventago/src/app/sellers/sellers.model.ts` — `Seller`(branchId/linkedUserId). 식당 웨이터 = branchId 설정된 seller
- `api-ventago/src/app/mercadopago/` — QR/intents/webhook (기존 결제 흐름 재사용)

### Frontend 재사용/분기 대상
- `ventago-app/src/pages/nueva-venta/index.tsx` — 분기 지점. 현재 `VcontrolHome` dynamic import. `useRestaurantMode`로 `SalonView`/`VcontrolHome` 분기 (둘 다 `next/dynamic`, ssr:false)
- `ventago-app/src/views/homes/VcontrolHome.tsx` — 기존 소매 venta 뷰 (식당 모드에서 미사용, 무변경)
- `ventago-app/src/pages/configuracion/` — 토글 + 배치도 편집기 진입점

### 프로젝트 규약
- `CLAUDE.md` — Sequelize underscored(snake_case), PG10/PG15 호환, pool min=10/max=80, 300ms 타겟+코드스플리팅, SWR 훅, ESLint(newline-before-return/lines-around-comment/no-unused-vars)
- `.claude/skills/sketch-findings-ace-online/SKILL.md` — Ventago 다크 네이비+골드 테마, MUI 5 매핑 (SalonView UI 작업 시 참조)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`Sale` 모델 nullable 컬럼 추가**: `storeClientId`(Phase 25)가 nullable FK 추가 선례. `table_id`(FK→restaurant_tables) + `ordered_at`/`served_at`/`closed_at`(timestamp) 모두 nullable로 동일 패턴 추가 → 소매 회귀 0
- **`SalePaymentMethod`**: saleId+paymentMethodId+paymentMethodOptionId+amount. split = 한 sale에 복수 INSERT, merge = 복수 sale에 동시 INSERT. 신규 결제 테이블 불필요
- **`StoreConfig`**: use_* BOOLEAN(기존 default true) → `useRestaurantMode` BOOLEAN default **false** + 식당 카테고리 id 목록 컬럼
- **`print.service.emitPrintTemp`**: `branch:{id}` room으로 `print_temp` fire-and-forget. comanda/cuenta/영수증 출력 전부 이 패턴
- **`Seller`**: branchId 설정 seller = 식당 웨이터. 신규 웨이터 모델 불필요

### Established Patterns
- **nueva-venta 분기**: `index.tsx`가 `next/dynamic(ssr:false)`로 `VcontrolHome` 로드. `SalonView`도 동일 dynamic import + `useRestaurantMode` 분기 (코드 스플리팅 규약)
- **store→branch→box→terminal 계층**: restaurant_tables는 store_id+branch_id FK 스코프 (멀티테넌트 격리)
- **매출 무오염 규칙**: 모든 매출 쿼리 `activity_type='sale'` 명시 필터. 식당 sale도 activity_type=sale 유지 → 기존 통계 자동 통합 (req 11)
- **SWR 참조 데이터 캐시**: 메뉴(products/categories)·테이블 목록은 SWR 훅 (5분 dedup)

### Integration Points
- **DB 마이그레이션**: `api-ventago/migrations/` SQL (PG10/PG15 호환 — snake_case, GENERATED AS IDENTITY 회피). 신규 `restaurant_tables` + `sales` ALTER(nullable 컬럼) + `store_configs` ALTER
- **configuración 토글 + 배치도 편집기**: 신규 페이지(configuración 영역). 판매 화면(SalonView)에는 편집 진입점 없음(권한 분리, req 5)
- **socket.io `/print-agent`**: comanda/resumen emit. KDS용 `/realtime` 라우팅은 본 Phase 미사용

</code_context>

<specifics>
## Specific Ideas

- 테이블 형태 enum: 원형 / 긴원형 / 정사각 / 직사각 (요구사항 원문 명시)
- 상태 색상 구분: libre / ocupada / por_cobrar 3단계 (Ventago 다크네이비+골드 테마 위에서 — sketch-findings 참조)
- 타이밍 2 이벤트: ordered_at(첫 comanda 전송) → served_at(음식 나옴, 웨이터 버튼) → closed_at(소비 완료=결제 직전, 웨이터 버튼). 조리시간/체류시간 산출 데이터 확보
- resumen 2종: 사전 cuenta(non-fiscal, DRAFT 유지) + 결제 후 영수증(PAID 후)

</specifics>

<deferred>
## Deferred Ideas

- **KDS(주방 디스플레이 화면)** — comanda 감열만 본 Phase. `/realtime` 라우팅으로 후속 Phase
- **상세 타이밍 분석 리포트/대시보드** — 기본 타이밍 데이터만 기록, 차트/통계는 후속
- **item 단위 split(누가 무엇을 먹었는지 귀속 분할)** — D-01 단일-sale 모델과 충돌(자식-sale 필요). 후속 Phase
- **영속 merge 그룹(단체손님 사전 묶음)** — D-04로 결제시점 일회성만. group_id 컬럼은 미추가
- **다층/테라스 다중 salón UI** — D-09로 zone 컬럼만 확보, UI 전환은 후속
- **테이블 회전/리사이즈 편집** — req5 out-of-scope (위치+형태까지만)
- **예약(reserva) / 대기자(waitlist) 관리** — MVP 범위 밖, 별도 backlog

</deferred>

---

*Phase: 39-modo-restaurante-pos-mesas*
*Context gathered: 2026-06-14*
