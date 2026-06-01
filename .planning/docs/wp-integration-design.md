# WordPress(WooCommerce) ↔ Ventago 양방향 연동 설계

> 상태: **설계 (구현 전)** · 작성 2026-06-01 · v2 (양방향 + 가격/재고 동기화 반영)
> 핵심: SKU 기준으로 Ventago ↔ WP 를 **양방향** 연동한다.
>  - WP 주문 → Ventago "보류판매(Suspendido)" 에 판매원 "Web (WP)" 로 대기
>  - Ventago 재고/가격 변동 → WP 에 즉시 반영 (재고 cap, 가격 2단계 매핑)

---

## 1. 요구사항 (확정)

### 테넌시
- 1 고객(store) → **N 지점(branch)**, **각 지점이 자체 WordPress 사이트** 운영.
- 모든 매핑은 store_id 격리 + branch 단위 채널.

### 방향 ① WP → Ventago (주문 수신)
- WP 홈페이지에서 판매 발생 → 해당 지점 Suspendido 리스트에 대기.
- 판매원 표기 **"Web (WP)"**.
- 상품 매칭 **SKU 기준** (variant SKU 포함, 미매칭 시 customName 폴백).
- 재고 **hold 예약** (기존 suspended 동작).

### 방향 ② Ventago → WP (재고/가격 동기화)
- **오프라인 매장 판매로 SKU 재고 변동 시 → WP 재고 즉시 반영.**
- **재고 출처 지점 = admin 선택 (확정)**: 각 WP 사이트(채널)가 보여줄 재고는
  **admin 이 지정한 1개 지점의 재고**. (전 지점 합산 아님 — 채널마다 `stock_source_branch_id`)
  - 보통 그 사이트를 운영하는 지점 자기 재고지만, admin 이 다른 지점(예: 중앙창고)을
    재고 출처로 지정할 수도 있게 함.
- **가격은 항상 Ventago 단일 소스 (확정)**: 가격 변경은 **이 시스템에서만** WP 로
  반영. **WP(WooCommerce)에서 가격을 수정해도 Ventago 는 무시**하고, 다음 동기화
  때 Ventago 값으로 덮어씀. WP→Ventago 가격 webhook 은 받지 않음.
- **가격 2단계 매핑**: 시스템의 여러 price_type 중 관리자가 **2개**를 골라
  WP 의 **precio (regular)** / **precio de promoción (sale)** 으로 연동.
  - 어떤 SKU 는 **precio normal 만**, 어떤 SKU 는 **normal + promoción 둘 다**.
- **재고 cap(최상위값)**: 관리자가 cap(예: 100) 지정 → 실재고가 cap 이상이면
  WP 에는 **무조건 cap 값**으로 표시 (3000개여도 100 으로). cap 미만이면 실값.

### 방향 ① 부가 — WP 주문 취소 (확정)
- WP(WooCommerce)에서 주문이 **취소**되면 (order.cancelled/refunded webhook):
  - 해당 numPedido 의 SuspendedSale 을 **Suspendido 리스트에서 제거**.
  - 제거 시 **재고 hold 복구** (기존 suspended 삭제 로직이 ProductBranch hold
    역이동 생성 → 재고 환원).
  - 이미 직원이 판매 확정한 뒤라면(suspended 없음) 자동 취소하지 않고
    경고 로그/알림만 (이중 차감·환불 방지 — 직원 수동 처리).

### 방향 ① 부가 — 주문 수신 시 처리
- **고객 자동 등록**: WP 주문의 고객 정보가 **CUIT(DNI) + 주소 + 전화번호를
  모두 정확히** 포함하면 → Ventago `clients` 에 자동 등록(없으면 생성, 있으면
  연결). 셋 중 하나라도 빠지면 등록하지 않고 suspended 메모에만 보존.
- **pedido 번호 표시**: WP 주문번호를 Suspendido **리스트 칼럼**에 표시.
- **comandera 출력 시 pedido 번호 大자 표시**: 이 suspended 가 판매로
  확정되어 영수증(comandera)으로 출력될 때, **WP pedido 번호를 큰 글씨**로
  티켓 상단/지정 위치에 인쇄.

### 방식
- **Webhook + REST API** 혼용:
  - WP→Ventago: webhook (push)
  - Ventago→WP: WooCommerce REST API 호출 (push) + 필요 시 WP→Ventago 풀 동기화 REST

---

## 2. 재사용 자산 / 시스템 현황

- **`ventas_suspendidas`** + `/suspended-sales` API: 판매원·지점·고객·품목·변형
  (`variantQuantities`)·메모·재고 hold 보존. ventas 화면 Suspendido 리스트가 읽음.
  → WP 주문을 SuspendedSale 1건으로 변환하면 별도 UI 없이 노출.
- **가격 구조** (실제 스키마 확인됨):
  - `price_types(id, name, description, store_id, status, rounding_*, ...)` — 가격
    레벨 정의. 예: PRECIO 1, PRE.121, MINORISTA, DES.3 (store 1 기준).
  - `prices(id, product_id, price_type_id, amount, currency, ...)` — 상품별 레벨가.
    값 컬럼은 **`amount`** (value 아님).
  - 한 상품은 여러 price_type 에 각각 amount 를 가짐.
  - `branch_price_types_disabled` — 지점별 특정 price_type 비활성 가능.
- **고객(clients)**: CUIT/DNI(`document`), 주소(`address`), 전화(`phone`),
  `fullname`/`nameFantasy` 보유. WP 고객 자동 등록 대상.
- **comandera 출력**: print-agent `formatter.js`(영수증 HTML). pedido 번호
  大자 블록을 여기 추가. SuspendedSale → Sale 확정 시 numPedido 가 sale 로
  이어져 print payload 에 실려야 함.
- **재고**: `stocks` / `product_branch` (지점별). 오프라인 판매는 sale_items →
  ProductBranch 차감. 변동 지점이 곧 WP 채널 매핑 단위.

---

## 3. 아키텍처 (양방향)

```
┌─────────────────────────────┐         ┌──────────────────────────────┐
│  WordPress / WooCommerce     │         │        Ventago               │
│  (지점별 N개 사이트)          │         │                              │
│                              │         │                              │
│  주문 발생 ──webhook(push)──────────▶  POST /integrations/wp/orders   │
│                              │         │   → SuspendedSale(source=wp) │
│                              │         │   → 재고 hold                 │
│                              │         │                              │
│  WC REST API  ◀──push────────────────  오프라인 판매/가격변경 hook    │
│  (stock/price update)        │         │   → wp-sync.service          │
│                              │         │   → 재고 cap 적용 + 2단계가격 │
└─────────────────────────────┘         └──────────────────────────────┘
```

---

## 4. 데이터 모델 (마이그레이션)

### 4-1. `wp_channels` — 지점별 WP 연결 (신규)
| 컬럼 | 타입 | 설명 |
|---|---|---|
| id | serial PK | |
| store_id | int FK→stores | 격리 |
| branch_id | int FK→branches, UNIQUE | 지점당 1 채널 (이 사이트의 소유 지점) |
| stock_source_branch_id | int FK→branches | **WP 에 보여줄 재고 출처 지점** (admin 선택). 보통 branch_id 와 동일하나 다른 지점/중앙창고 지정 가능 |
| channel_key | varchar UNIQUE | WP→Ventago webhook 식별자 |
| secret | varchar | webhook HMAC 서명용 |
| site_url | varchar | WP 사이트 URL |
| wc_consumer_key | varchar | **Ventago→WC REST 호출용** (WooCommerce 키) |
| wc_consumer_secret | varchar | 〃 (암호화 저장 권장) |
| stock_cap | int default 100 | 재고 최상위 표시값 |
| regular_price_type_id | int FK→price_types, null | WP 'precio' 로 보낼 레벨 |
| promo_price_type_id | int FK→price_types, null | WP 'precio promoción' 로 보낼 레벨 |
| is_active | bool | |
| last_received_at / last_pushed_at | timestamptz | 헬스 표시 |

> 가격 레벨 매핑은 **채널(지점) 기본값**. SKU별 예외는 4-3 으로.
> **재고 출처**: push 시 `stock_source_branch_id` 의 ProductBranch 재고만 사용.
> 또한 그 지점 재고가 변동될 때만 해당 채널로 push (다른 지점 판매는 영향 없음).

### 4-2. `ventas_suspendidas.source` 컬럼 (기존 테이블 변경)
| source | varchar(10) default 'pos' | 'pos' \| 'wp' — 프론트 "Web (WP)" 판단 |

### 4-3. `wp_product_sync` — SKU별 동기화 정책/상태 (신규)
| 컬럼 | 타입 | 설명 |
|---|---|---|
| id | serial PK | |
| store_id / branch_id | int FK | |
| product_id | int FK→products | Ventago 상품(변형 포함) |
| sku | varchar | 매칭 키 (조회 인덱스) |
| sync_enabled | bool default true | 이 SKU 를 WP 와 동기화할지 |
| price_mode | varchar | 'normal' \| 'normal_promo' — SKU별 가격 정책 |
| wc_product_id | int null | WC 측 product id (매칭 캐시, 첫 push 시 채움) |
| last_synced_stock | int null | 마지막 push 한 (cap 적용된) 재고 |
| last_synced_at | timestamptz | |

> `price_mode='normal'` → regular 만 push, promoción 비움.
> `price_mode='normal_promo'` → regular + sale 둘 다 push.
> 미등록 SKU 는 채널 기본정책(예: normal) 적용하거나 동기화 제외 — 관리자 설정.

---

## 5. 백엔드 (api-ventago)

### 모듈 `src/app/integrations/wp/`
```
wp.module.ts
wp-channel.model.ts / wp-product-sync.model.ts
wp.guard.ts                  HMAC 서명 검증 (WP→Ventago)
wp-webhook.controller.ts     @Public POST /integrations/wp/orders   (주문 수신)
                             @Public POST /integrations/wp/orders/cancel (취소 수신)
wp-webhook.service.ts        SKU매칭 → SuspendedSale(source=wp) 멱등 생성 + hold
                             + 취소 시 suspended 제거 + 재고 복구
wp-channel.controller.ts     지점 채널 CRUD (admin)
wp-channel.service.ts        key/secret 발급·재발급, 가격레벨·cap 설정
wp-sync.service.ts           Ventago→WC push (재고/가격) — cap + 2단계가격 적용
wp-sync.controller.ts        수동 전체 재동기화 / SKU별 토글 (admin)
wc-client.ts                 WooCommerce REST API 클라이언트 (consumer key/secret)
dto/...
```

### 5-1. 방향① WP→Ventago (주문)
1. `WpGuard`: `x-wp-channel`+`x-wp-signature` HMAC(rawBody) 검증, is_active 확인.
2. `line_items[].sku` → `products(sku, storeId)` 매칭 (variant 포함).
   미매칭 → customName + notes 원문.
3. **고객 자동 등록** (조건부):
   - WP payload 의 `document`(CUIT/DNI) + `address` + `phone` 이 **셋 다 존재**하면:
     - `clients` 에서 (store_id, document) 로 조회 → 있으면 그 client 연결,
       없으면 신규 생성 (fullname/nameFantasy, address, phone, document, email).
     - SuspendedSale.clientId 에 연결.
   - 셋 중 하나라도 없으면 clientId=null, 고객정보는 notes 에 원문 보존
     (직원이 확정 시 수동 처리).
   - ※ `ventas_suspendidas` 는 이미 clientId FK 보유 — 재사용.
4. `SuspendedSalesService.create()` 재사용 + source='wp', userId/sellerId=null,
   **numPedido=WP주문번호** (모델에 이미 존재), branchId=채널지점, clientId(위).
5. 멱등: (numPedido, branchId) 중복 → 200 무시.
6. 재고 hold (기존 create 로직).

### 5-1-bis. 방향① WP 주문 취소 수신
1. WC `order.cancelled` / `order.refunded` webhook → `/integrations/wp/orders/cancel`.
2. (numPedido, branchId, source='wp') 로 SuspendedSale 조회.
   - **존재 시**: `SuspendedSalesService.remove()` 호출 → suspended 삭제 +
     ProductBranch hold 역이동(재고 복구). 200.
   - **없을 시** (이미 직원이 판매 확정함): 자동 취소 안 함 → 경고 로그 +
     (선택) 관리자 알림. 이중 차감/환불 방지. 200 (webhook 재시도 멈춤).

### 5-1-ter. pedido 번호 전파 (suspended → sale → comandera)
- `ventas_suspendidas.numPedido` 는 이미 존재 → WP 주문번호 저장.
- **확정 시 sales 로 전파**: suspended → 판매 확정(create) 경로에서 numPedido 를
  `sales` 로 옮겨야 함. `sales` 에 `num_pedido` 컬럼이 **없음 확인됨** → 추가(마이그레이션).
- **print payload**: 확정 판매가 comandera 로 emit 될 때(print_invoice/temp)
  `buildInvoiceData` 가 numPedido 를 payload 에 포함 → formatter 가 大자 렌더.

### 5-2. 방향② Ventago→WC (재고/가격 push)
**트리거** (Ventago 내부 이벤트):
- 오프라인 판매 확정 (sale create) → 영향 SKU 재고 변동.
- 재고 정정/입고/이동.
- 가격 변경 (regular/promo 매핑된 price_type 의 prices 변경).

**push 로직** (`wp-sync.service`):
```
변동 발생 (anyBranch, sku) 마다:
  // 이 SKU 의 재고가 변한 지점(anyBranch)을 stock_source_branch_id 로 삼는
  // 채널들을 찾는다. (그 지점을 재고출처로 지정한 사이트만 영향받음)
  for each channel where channel.stock_source_branch_id == anyBranch && active:
    sourceBranch = channel.stock_source_branch_id        ← admin 지정 지점
    realStock = ProductBranch 가용재고(sourceBranch, product)
    cappedStock = min(realStock, channel.stock_cap)       ← 재고 cap
    policy = wp_product_sync[sku].price_mode ?? 채널기본
    regular = prices[product, channel.regular_price_type_id].amount
    sale    = policy=='normal_promo'
                ? prices[product, channel.promo_price_type_id].amount
                : null                                     ← promo 없으면 비움
    WC REST PUT /products/<wc_id>:
       { stock_quantity: cappedStock, manage_stock: true,
         regular_price: regular, sale_price: sale ?? '' }
    wp_product_sync 갱신 (last_synced_stock, wc_product_id, last_synced_at)
```
- **디바운스/배치**: 한 판매가 여러 SKU 변동 → 큐로 모아 배치 push (WC rate-limit).
- **실패 처리**: 재시도 큐 + last_pushed_at/에러 기록. (online-orders cron 패턴 재사용)
- **wc_product_id 매칭**: 최초엔 WC REST `GET /products?sku=` 로 조회 후 캐시.

### pool / 성능 (CLAUDE.md)
- push 는 외부 HTTP I/O → DB 트랜잭션 밖에서. 영향 SKU 만 골라 배치.
- webhook 수신은 트랜잭션 1개 (매칭 SELECT + suspended insert + hold).
- 재고 cap 으로 WC 부하/노출 최소화 (3000 → 100).

---

## 6. 프론트엔드 (ventago-app)

### 6-1. Suspendido 리스트 — "Web (WP)" + pedido 번호
- `source==='wp'` → 판매원 칼럼 **`🌐 Web (WP)`** 배지(cyan) + 행 시각 구분.
- **pedido 번호 칼럼**: `numPedido` 를 리스트에 칼럼으로 표시 (WP 주문 추적).
  POS 보류는 빈 값 → "—".

### 6-1-bis. comandera 출력 — pedido 번호 大자
- print-agent `formatter.js` (formatInvoiceHtml / formatTempTicketHtml):
  payload 에 `numPedido` 있으면 티켓 상단(또는 고객 위)에 **큰 글씨 블록**으로
  `PEDIDO  #<numPedido>` 인쇄. WP 출처 주문을 창고/배송 직원이 즉시 식별.
- 백엔드 `buildInvoiceData` 가 sale.numPedido → payload.numPedido 전달.

### 6-2. 설정 UI 배치 (확정)
**원칙**: "각 지점이 자체 WP 사이트" → 채널 설정은 **지점(sucursal) 단위**.
SKU별 예외는 대량 관리가 필요 → **가격 화면(precios)** 에 컬럼.

#### 6-2-a. `sucursales/[id]` — "🌐 Web (WordPress)" 탭/카드
프린터 에이전트(`impresora.tsx`) 페이지와 **동일 패턴** (학습비용 0).
4개 섹션으로 방향·대상 구분하여 혼동 방지 (sketch-findings Configuración 패턴):

```
┌─ Integración Web (WordPress) ──────────────[● Conectado]─┐
│ ① Conexión (WP → Ventago)                                │
│    Webhook URL pedidos:   …/integrations/wp/orders   [📋]│
│    Webhook URL cancelar:  …/wp/orders/cancel         [📋]│
│    Channel Key: wpch_…  [📋]                              │
│    Secret: ••••  [Regenerar]  ⚠️ solo se ve 1 vez        │
│ ② WooCommerce (Ventago → WP)                             │
│    Site URL / Consumer Key / Consumer Secret             │
│    [Probar conexión]                                     │
│ ③ Stock                                                  │
│    Sucursal de stock: [▼ Esta sucursal]  ← 재고출처 지점 │
│    Tope de stock:     [ 100 ]            ← cap          │
│ ④ Precios                                                │
│    WP precio (regular):   [▼ PRECIO 1]                   │
│    WP precio promoción:   [▼ DES.3   ]                   │
│ ── Estado ──                                             │
│    Activo [✔] · Última recepción / sincronización        │
│    [⟳ Resincronizar todo el catálogo]                    │
└──────────────────────────────────────────────────────────┘
```
- 섹션①=받기(webhook), ②=보내기(WC키), ③=재고, ④=가격 — 방향이 다른 항목을 끊어서 표시.
- secret/consumer_secret 은 생성·재발급 시 1회만 표시.

#### 6-2-b. `precios` 화면 — SKU별 동기화·가격정책 컬럼
이미 가격을 보는 그리드라 맥락 일치 + 대량 SKU 한눈에 관리:
```
SKU         Producto      PRECIO 1   DES.3    Web   Promo Web
2601…015    Kaliowski L   60.000     54.000   [✔]   [✔]   ← normal+promo
2601…001    Remera niño    9.680      —        [✔]   [ ]   ← normal만
```
- **Web** 토글 = `wp_product_sync.sync_enabled` (이 SKU 를 WP 와 동기화할지).
- **Promo Web** 토글 = `price_mode`(normal ↔ normal_promo). Web off 면 비활성.
- 채널 기본정책을 두되, 행별 예외를 여기서 조정. 1차엔 채널 기본 + 최소 예외.

> preferencias(매장 통합설정)에는 넣지 않음 — 지점 N개 채널을 한 탭에 욱여넣으면
> 복잡. 단, 후속으로 preferencias 에 "전체 채널 상태 요약" 위젯은 고려(§11).

---

## 7. WordPress 측

- **WooCommerce (권장 — 완전 쇼핑몰)**:
  - WP→Ventago 주문: WC 내장 Webhook (Order created/updated) → Delivery URL+Secret.
  - Ventago→WP 재고/가격: WC REST API (consumer key/secret) 로 Ventago 가 push.
  - SKU 는 WC product 의 SKU 필드 = Ventago products.sku.
- **일반 WP (비-WooCommerce)**: 재고/가격 쇼케이스만 — REST 조회 엔드포인트
  제공하거나 스니펫으로 표시. (쇼핑몰 기능 없으면 방향② 가치 제한적)

---

## 8. 보안
- WP→Ventago: 채널 secret HMAC(rawBody) timing-safe 검증, store 격리.
- Ventago→WC: consumer secret 암호화 저장, HTTPS, 응답에 secret 미노출.
- 재고 cap 으로 실재고 비노출(영업 정보 보호 부수효과).

---

## 9. 작업 단계
1. **DB**: wp_channels (stock_source_branch_id 포함), wp_product_sync,
   ventas_suspendidas.source, sales.num_pedido 추가 (마이그레이션).
2. **방향① 주문 수신**: webhook + SuspendedSale(source=wp, numPedido) + hold
   + **고객 자동 등록**(CUIT+주소+전화 모두 시).
3. **방향① 취소 수신**: order.cancelled/refunded → suspended 제거 + 재고 복구.
4. **프론트 Suspendido**: "Web (WP)" 배지 + **pedido 번호 칼럼**.
5. **pedido 번호 전파**: suspended→sale numPedido 이관 + buildInvoiceData payload
   + **comandera formatter 大자 인쇄** (print-agent).
6. **방향② 재고/가격 push**: wc-client + wp-sync.service
   (재고출처 지점 + cap + 2단계가격) + 판매/가격변경 hook 연결 + 배치/재시도.
7. **sucursal WP 설정 UI**: 채널·WC키·**재고출처 지점**·cap·가격레벨 매핑·재동기화.
8. **SKU별 price_mode** 정책 UI (선택).
9. **WooCommerce 설정 가이드** (webhook 주문+취소 + REST 키 발급법).

## 10. 결정 완료 (확정)
- **재고 출처**: 채널마다 `stock_source_branch_id` — admin 이 사이트별로
  보여줄 재고 지점 지정 (전 지점 합산 ❌). 그 지점 재고 변동 시에만 push.
- **가격 단일 소스**: 가격은 Ventago 에서만 수정 → WP push. **WP 에서 가격 수정
  해도 무시**하고 다음 동기화 때 덮어씀. WP→Ventago 가격 webhook 안 받음.
- **WP 주문 취소**: suspended 에서 제거 + 재고 복구. 단 이미 판매 확정된 건은
  자동 취소 안 함(경고만).

## 11. 미결정 / 후속
- 고객 자동등록 시 **document 형식 검증** 수준 (CUIT 11자리 / DNI 7~8자리 체크?).
- **결제상태**(paid/pending) 를 suspended 메모/우선순위에 반영?
- comandera pedido 번호 위치: 상단 vs 고객정보 위 (sketch 로 확정).
- 장기 방치 WP suspended **cron 만료** (online-orders-expiry 재사용).
- WC product 가 **없는** SKU 자동 생성할지 vs 매칭만.
- 환불(refund) 과 취소(cancel) 를 구분 처리할지 (부분환불 등).
