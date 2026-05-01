# Spec — Ventas Online (온라인 판매 관리)

**작성일**: 2026-05-01
**Phase**: 27 (다음 phase 번호)
**Status**: 계획 → 실행

---

## 1. 목적

오프라인 매장 POS 외에, **온라인 채널(Mercado Libre, Webshop, Instagram, WhatsApp 등)** 로 들어오는 주문을 한 곳에서 관리.
주문 라이프사이클(접수 → 확정 → 준비 → 발송 → 배달 → 반품)을 통합 추적하고, 채널별 KPI를 한눈에 파악.

기존 `sales` 테이블은 오프라인 + factura 흐름 전용으로 두고, **온라인 주문은 별도 도메인** (`online_orders`) 으로 격리한다.
이유:
- 결제 흐름이 다름 (Pasarela / 게이트웨이 응답 → 비동기 confirmed)
- 배송 라이프사이클 (carrier, tracking, label)
- 반품/환불 정책 (mercadolibre 마켓 규정 등)
- 채널별 metadata (외부 주문번호, 외부 status code 등)

---

## 2. Locked Decisions

| # | Decision | 근거 |
|---|---|---|
| L1 | 별도 테이블 `online_orders` (sales 와 분리) | 도메인 차이 (라이프사이클, 결제, 반품) |
| L2 | `order_number` UNIQUE per store | 매장별 자체 카운터 (`UNIQUE (store_id, order_number)`) |
| L3 | 채널 enum: `mercadolibre`, `webshop`, `instagram`, `whatsapp`, `other` | 확장 가능 (ALTER TYPE ADD VALUE) |
| L4 | 상태 enum: `pending`, `confirmed`, `preparing`, `shipped`, `delivered`, `cancelled`, `returned` | 라이프사이클 |
| L5 | 재고 차감은 **confirmed 시점** | pending 은 결제 대기 → 차감 안함 |
| L6 | 트랜잭션 SERIALIZABLE | 동시 confirm 시 재고 race condition 방지 |
| L7 | `online_returns` 별도 테이블 | 부분 반품 + 사유/환불액 추적 |
| L8 | 사이드바 "Ventas Online" 메뉴는 `venta` 앱 children 에 하드코딩 | DB module 시드 없이도 즉시 노출 (Phase 5 모듈 시드 패턴) |

---

## 3. DB 스키마

PostgreSQL 10/15 호환. **GENERATED AS IDENTITY 금지** (PG10 미지원), `BIGSERIAL` 사용.
모든 테이블 `store_id` 격리 + index.

### 3.1 `online_orders`

```
id                BIGSERIAL PK
store_id          INTEGER NOT NULL FK→stores
order_number      INTEGER NOT NULL                    -- 매장별 자체 카운터 (1부터)
channel           VARCHAR(20) NOT NULL CHECK IN (...) -- enum
client_id         INTEGER FK→store_clients NULL       -- 익명 주문 가능
client_name       VARCHAR(160)                        -- 비회원/snapshot
client_phone      VARCHAR(40)
client_email      VARCHAR(160)
status            VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK IN (...)
subtotal          NUMERIC(12,2) NOT NULL DEFAULT 0
shipping_cost     NUMERIC(12,2) NOT NULL DEFAULT 0
discount          NUMERIC(12,2) NOT NULL DEFAULT 0
total             NUMERIC(12,2) NOT NULL DEFAULT 0    -- subtotal + shipping - discount
payment_method    VARCHAR(40)                         -- "mercadopago", "transferencia", etc.
payment_status    VARCHAR(20) DEFAULT 'pending'       -- pending|paid|refunded|failed
payment_reference VARCHAR(120)                        -- 외부 게이트웨이 ID
shipping_carrier  VARCHAR(60)                         -- "Andreani", "Correo Argentino"
tracking_code     VARCHAR(80)
shipping_label_url TEXT                               -- MinIO key (zebra-agent 출력 가능)
external_order_id VARCHAR(120)                        -- 채널 외부 주문번호 (mercadolibre 등)
notes             TEXT
metadata          JSONB DEFAULT '{}'::jsonb
created_at        TIMESTAMPTZ DEFAULT NOW()
updated_at        TIMESTAMPTZ DEFAULT NOW()
confirmed_at      TIMESTAMPTZ
shipped_at        TIMESTAMPTZ
delivered_at      TIMESTAMPTZ
cancelled_at      TIMESTAMPTZ

UNIQUE (store_id, order_number)
INDEX (store_id, status)
INDEX (store_id, channel)
INDEX (store_id, created_at DESC)
INDEX (external_order_id) WHERE external_order_id IS NOT NULL
```

### 3.2 `online_order_items`

```
id              BIGSERIAL PK
online_order_id BIGINT NOT NULL FK→online_orders ON DELETE CASCADE
product_id      INTEGER FK→products NULL    -- soft-link (상품 삭제돼도 주문 유지)
variant_id      INTEGER NULL                -- 변형 ID (옵션)
sku             VARCHAR(80)
product_name    VARCHAR(200) NOT NULL       -- snapshot
size            VARCHAR(40)
color           VARCHAR(40)
quantity        INTEGER NOT NULL CHECK (quantity > 0)
unit_price      NUMERIC(12,2) NOT NULL
total_price     NUMERIC(12,2) NOT NULL      -- unit_price * quantity
created_at      TIMESTAMPTZ DEFAULT NOW()
updated_at      TIMESTAMPTZ DEFAULT NOW()

INDEX (online_order_id)
INDEX (product_id) WHERE product_id IS NOT NULL
```

### 3.3 `online_returns`

```
id              BIGSERIAL PK
online_order_id BIGINT NOT NULL FK→online_orders ON DELETE CASCADE
reason          VARCHAR(40) NOT NULL CHECK IN ('wrong_size','damaged','description_mismatch','other')
reason_detail   TEXT
status          VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK IN ('pending','approved','rejected','refunded')
refund_amount   NUMERIC(12,2) DEFAULT 0
created_at      TIMESTAMPTZ DEFAULT NOW()
resolved_at     TIMESTAMPTZ

INDEX (online_order_id)
INDEX (status)
```

---

## 4. 백엔드 모듈 (NestJS)

경로: `api-ventago/src/app/online-orders/`

### 4.1 파일 구조

```
online-orders/
├── dto/
│   ├── create-online-order.dto.ts
│   ├── ship-online-order.dto.ts
│   ├── filter-online-orders.dto.ts
│   ├── return-online-order.dto.ts
│   └── update-return-status.dto.ts
├── online-order.model.ts
├── online-order-item.model.ts
├── online-return.model.ts
├── online-orders.service.ts
├── online-orders.controller.ts
└── online-orders.module.ts
```

### 4.2 서비스 메서드

- `findFiltered(storeId, filters, pagination)` — 목록 조회 (status/channel/from/to)
- `findById(storeId, id)` — 상세 + items + returns
- `create(storeId, userId, dto)` — 트랜잭션, order_number 매장별 자동 증가
- `confirmOrder(storeId, id)` — pending → confirmed, 재고 차감 (SERIALIZABLE)
- `prepareOrder(storeId, id)` — confirmed → preparing
- `shipOrder(storeId, id, carrier, trackingCode)` — preparing → shipped, shipped_at 기록
- `deliverOrder(storeId, id)` — shipped → delivered, delivered_at 기록
- `cancelOrder(storeId, id)` — pending/confirmed → cancelled, 재고 복구 (SERIALIZABLE)
- `getDashboard(storeId, range)` — KPI: 월 주문수, 매출, 미발송 카운트, 채널별 비중
- `createReturn(storeId, orderId, dto)` — 반품 등록
- `updateReturnStatus(storeId, returnId, status, refundAmount)`

### 4.3 컨트롤러 (REST)

```
GET    /online-orders              — list with filters + pagination
GET    /online-orders/dashboard    — KPI 카드용
GET    /online-orders/:id          — detail
POST   /online-orders              — create
PATCH  /online-orders/:id/confirm
PATCH  /online-orders/:id/prepare
PATCH  /online-orders/:id/ship     — body: { carrier, trackingCode }
PATCH  /online-orders/:id/deliver
PATCH  /online-orders/:id/cancel
POST   /online-orders/:id/return   — body: { reason, reasonDetail, refundAmount }
GET    /online-returns             — list
PATCH  /online-returns/:id/approve — body: { refundAmount }
PATCH  /online-returns/:id/reject
```

권한:
- 읽기: `admin`, `superadmin`, `gerente`, `vendedor`
- 쓰기 (status 전환/등록): `admin`, `superadmin`, `gerente`
- 반품 승인: `admin`, `superadmin`

---

## 5. 프론트엔드 (Next.js + MUI)

### 5.1 페이지

```
ventago-app/src/pages/ventas-online/
├── index.tsx                      — VentasOnlineView wrapper
└── [orderId].tsx                  — OrderDetailView wrapper
```

### 5.2 뷰

```
ventago-app/src/views/ventas-online/
├── VentasOnlineView.tsx           — KPI 카드 + 필터 + 주문 테이블 + 탭(Pedidos|Envíos|Devoluciones)
├── OrderDetailView.tsx            — 2컬럼: 고객+상품 | 타임라인+결제+액션
├── ShippingManagementTab.tsx      — preparing/shipped 상태 위주 테이블 + 송장발행
└── ReturnsTab.tsx                 — 반품 목록 + 승인/거부
```

### 5.3 SWR 훅

```
ventago-app/src/hooks/api/
├── useOnlineOrders.ts             — useOnlineOrders(filters) → { data, error, isLoading, mutate }
├── useOnlineOrder.ts              — useOnlineOrder(id)
├── useOnlineDashboard.ts          — useOnlineDashboard()
└── useOnlineReturns.ts            — useOnlineReturns(filters)
```

### 5.4 사이드바

`ventago-app/src/navigation/vertical/index.ts` 의 `getAppChildren('venta')` 분기에 하드코딩 추가:

```typescript
if (appSlug === 'venta') {
  children.unshift({
    title: t('nav_online_sales'),
    icon: 'tabler:world-www',
    path: '/ventas-online',
    action: 'read',
    subject: 'venta',
  });
}
```

번역 키 `nav_online_sales: "Ventas Online"` 추가.

### 5.5 디자인 (mockup pattern)

- Primary color: `#05a7cf` (mockup의 시안 톤)
- 다크 사이드바 + 골드 강조 (기존 mockup pattern 유지)
- KPI 카드: MUI `Card` + `Typography` + 아이콘
- 테이블: MUI DataGrid (`@mui/x-data-grid`) — pageSize 50

---

## 6. 트랜잭션 / 동시성

- `confirmOrder`: SERIALIZABLE — 재고 확인 + 차감을 단일 트랜잭션
- `cancelOrder`: SERIALIZABLE — 재고 복구
- `create` (order_number 자동 증가): `SELECT MAX(order_number) FROM online_orders WHERE store_id = ?` 후 +1 — `UNIQUE` 제약으로 race 시 retry (최대 3회)

PostgreSQL pool 재사용:
- Sequelize 단일 인스턴스 (`api-ventago/src/database/database.module.ts`) — 새 풀 생성 금지
- 트랜잭션 finally 에서 commit/rollback 보장
- 직접 `pg` Client 사용 시 finally release 필수

---

## 7. 에러 처리 / 디버깅

- 모든 컨트롤러 메서드: try/catch 없이 NestJS exception filter 의존
- 서비스 메서드: 명시적 `NotFoundException` / `BadRequestException` / `ConflictException`
- 디버그 로그: `Logger.debug(...)` 로 status 전환마다 기록
- 트랜잭션 실패 시: `Logger.error(...)` 후 throw

---

## 8. 커밋 전략

| Wave | 변경 | 커밋 메시지 |
|------|------|--------------|
| 1 | DB 마이그레이션 + Sequelize 모델 + 모듈 등록 | `feat(online-orders): Phase 27 Wave 1 — DB 마이그레이션 + 모델 (online_orders / items / returns)` |
| 2 | service + controller + DTOs + 모듈 wiring | `feat(online-orders): Phase 27 Wave 2 — 서비스/컨트롤러/DTO + REST API` |
| 3 | 프론트엔드 페이지 + 뷰 컴포넌트 | `feat(ventas-online): Phase 27 Wave 3 — 프론트엔드 페이지 + 뷰 컴포넌트` |
| 4 | SWR 훅 + 사이드바 + 번역 + ESLint | `feat(ventas-online): Phase 27 Wave 4 — SWR 훅 + 사이드바 통합 + 최종 검증` |

각 Wave 완료 시 해당 서브모듈 (api-ventago / ventago-app) 에서 개별 커밋.

---

## 9. ESLint 검증

각 Wave 후 해당 서브모듈에서:
```
npm run lint --workspace=api-ventago
npm run lint --workspace=ventago-app
```

- `newline-before-return`, `lines-around-comment`, `no-unused-vars`: 빌드 차단 → 즉시 수정.

---

## 10. 미적용 / 후속 (Out of scope for Phase 27)

- Mercado Libre / WhatsApp 실제 API 연동 (Phase 28+)
- 결제 게이트웨이 webhook (Phase 28+)
- 자동 송장 PDF 생성 (zebra-agent 활용 — Phase 28+)
- 다국어 운송장 (한국어/영어/스페인어 동시) — 현재는 ES만
