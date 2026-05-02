# SPEC: Phase 28 — 온라인 주문 ↔ 재고·회계 통합

**생성일**: 2026-05-01
**Phase**: 28 (Phase 27 후속)
**Status**: 계획 → 사용자 승인 대기

---

## 1. 목표

Phase 27 에서 분리된 `online_orders` 도메인을 회사의 공용 인프라(`Stocks` ledger, `sales` 테이블, `payment_methods`) 와 연결한다. 결과적으로:

1. **재고 일관성**: 온라인 주문은 `pending` 시점부터 재고를 격리(suspend hold)하여 다른 채널에 팔리지 않도록 한다. 취소/실패 시 자동 복구.
2. **회계 일관성**: `delivered + paid` 시점에 `sales` 테이블에 mirror row 1건을 자동 생성하여 일일 매출 보고서·캐시 통제·결제수단별 집계에 자동 노출.
3. **단일 소스 원칙**: 두 시스템(`products.stock` 직접 변경 vs `Stocks` ledger) 의 분기를 제거. 모든 재고 이동은 `Stocks` ledger 를 거친다.

---

## 2. 배경 및 컨텍스트

### 2.1 사전 환경 이슈 (작업 시작 전 반드시 확인)

`api-ventago/logs/error-2026-05-01.log` 에 다음 에러가 다발:

- `relation "ProductBranch" does not exist` — productStock.service.ts:711, 880 등
- `column SuspendedSale.province_id does not exist`
- `relation "product_branches" does not exist`

→ 메모리 (`MEMORY.md`) 에 따르면 **운영 표준은 "ProductBranch" PascalCase quoted**. 일부 코드가 snake_case `product_branches` 로 쿼리하면서 깨짐. **로컬 dev DB 가 이 문제로 깨져 있을 가능성** → Phase 28 작업 전에 dev DB 의 `ProductBranch` 테이블 존재 여부 확인 필수.

### 2.2 Phase 27 의 한계 (이번 phase 가 해결할 대상)

| 결함 | 위치 | 증상 |
|---|---|---|
| 재고 단일 컬럼만 변경 | `online-orders.service.ts:493-529` | `Stocks` ledger 무시 → 재고 보고서에 안 잡힘 |
| pending 단계 hold 없음 | spec L5 ("confirmed 시점 차감") | pending 5~30분 동안 재고 미격리 → 동시 판매 가능 |
| sales mirror 없음 | `deliverOrder` | 일일 매출 보고서에 0원으로 잡힘 |
| payment_method 문자열 | `online_orders.payment_method VARCHAR(40)` | 결제수단별 집계 불가 |
| 지점 정보 없음 | `online_orders` 에 `branchId` FK 없음 | 지점별 재고 차감 불가 |

### 2.3 활용할 기존 인프라

- **`Stocks` ledger** (`api-ventago/src/app/stocks/stocks.model.ts`) — `type: 'sale'|'adjust'|'suspend'` 컬럼으로 movement 종류 구분. `productStock.service.ts:56-130` 에 hold/release 패턴 완비.
- **`payment_methods`** (운영 DB 시드 — efectivo=1, credito=2, favor=5 등 11종 글로벌)
- **`sales`** + `sales_payment_methods` 테이블 — 일일 보고서가 이 두 테이블만 본다.
- **`@nestjs/schedule`** — pending 만료 cron 용.

---

## 3. 기술 스택

- **언어/프레임워크**: NestJS 11 + TypeScript + Sequelize (`underscored: true`)
- **DB**: PostgreSQL 10 (운영) / 15 (dev) — `BIGSERIAL`, `CHECK constraint` 패턴 유지
- **Pool**: 단일 Sequelize 인스턴스 재사용 (max=50 변경 금지). 트랜잭션 finally commit/rollback 보장.
- **ESLint**: `newline-before-return`, `lines-around-comment`, `no-unused-vars` (warning 도 빌드 차단)
- **테스트**: 기존 `.spec.ts` 패턴 (sales-create.service.spec.ts, reportsSalesCockpit.spec.ts 참고)

---

## 4. Locked Decisions (이번 phase 의 핵심 결정)

| # | Decision | 근거 |
|---|---|---|
| D1 | 재고 hold 시점은 **`pending`** 진입 시 | 결제 대기 동안에도 재고 격리 필요 (마코스님 요구) |
| D2 | hold/release 는 `Stocks` ledger `type='suspend'` 사용 | 기존 suspended-sales 패턴과 동일 → 재고 보고서가 이미 인식 |
| D3 | `confirmed → shipped/delivered` 시 hold 해제 + `type='sale'` 기록 | 실판매 인식 시점 |
| D4 | sales mirror 생성 시점은 `deliverOrder` (기본값) | 회계상 "소유권 이전" 원칙 |
| D5 | `online_orders.branchId` FK 필수 추가 | 지점별 재고/매출 분리. 매장 1지점이면 자동 선택. |
| D6 | `online_orders.payment_method_id` (FK → payment_methods) 추가 | 결제수단별 집계 |
| D7 | `sales.online_order_id` UNIQUE FK 추가 | 멱등성 — 중복 mirror 방지 |
| D8 | `sales.source` enum 컬럼 추가 (`'pos'\|'online'\|'factura'`) | 일일 보고서에서 채널 분리 가능 |
| D9 | pending 24시간 미결제 시 자동 cancel cron | hold 누수 방지 (zombie reservation) |
| D10 | 모든 status 전환은 SERIALIZABLE 트랜잭션 | race condition 방지 (Phase 27 패턴 유지) |

---

## 5. DB 스키마 변경 (마이그레이션)

파일: `api-ventago/migrations/phase28-online-orders-integration.sql`

```sql
BEGIN;

-- 5.1 online_orders: 통합용 컬럼 추가
ALTER TABLE online_orders
  ADD COLUMN IF NOT EXISTS branch_id INTEGER REFERENCES branches(id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS payment_method_id INTEGER REFERENCES payment_methods(id),
  ADD COLUMN IF NOT EXISTS mirror_sale_id INTEGER REFERENCES sales(id),
  ADD COLUMN IF NOT EXISTS stock_held_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS stock_released_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_online_orders_branch
  ON online_orders(branch_id) WHERE branch_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_online_orders_pending_old
  ON online_orders(created_at) WHERE status = 'pending';

-- 5.2 sales: 출처/링크 컬럼
ALTER TABLE sales
  ADD COLUMN IF NOT EXISTS source VARCHAR(20) NOT NULL DEFAULT 'pos'
    CHECK (source IN ('pos','online','factura')),
  ADD COLUMN IF NOT EXISTS online_order_id BIGINT
    REFERENCES online_orders(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uniq_sales_online_order
  ON sales(online_order_id) WHERE online_order_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sales_source ON sales(store_id, source, sale_date);

COMMIT;
```

**PG10/PG15 호환**: `IF NOT EXISTS` 사용 (PG9.6+). `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` 는 PG9.6+ 지원.

---

## 6. 백엔드 변경

### 6.1 신규 서비스: `OnlineOrderStockService`

파일: `api-ventago/src/app/online-orders/online-order-stock.service.ts`

책임:
- `holdStock(order, t)` — pending 진입 시 호출. `Stocks.create({type:'suspend', stock:-qty})` × items
- `releaseHold(order, t)` — cancel 시. `Stocks.create({type:'suspend', stock:+qty})` × items
- `commitSale(order, t)` — delivered 시. hold 해제 + `type='sale'` (-qty) 기록 + `products.stock` 동기화
- `reverseSale(order, t)` — returned 시 역분개

**Pool 안전**: 모든 메서드는 `t: Transaction` 을 인자로 받아 외부 트랜잭션 재사용. 자체 트랜잭션 생성 X.

### 6.2 신규 서비스: `OnlineOrderSalesMirrorService`

파일: `api-ventago/src/app/online-orders/online-order-sales-mirror.service.ts`

책임:
- `createMirror(order, t)` — `Sale` + `SaleItem[]` + `SalePaymentMethod` 생성. `source='online'`, `online_order_id=order.id`
- `nullifyMirror(order, t)` — returned/cancelled-after-deliver 시 sales 역분개 (기존 `salesCreate.nullifySale` 패턴 참조)

**멱등성**: `online_order_id` UNIQUE → 이미 존재하면 skip + warn log.

### 6.3 `OnlineOrdersService` 수정

| 메서드 | 변경 |
|---|---|
| `create()` | `branchId` 자동 결정 (DTO > 매장 단일지점 자동선택). pending 진입 직후 `holdStock()` 호출 |
| `confirmOrder()` | 재고 차감 로직 제거 (이미 hold 됨). `confirmedAt` 만 기록 |
| `shipOrder()` | 변경 없음 |
| `deliverOrder()` | `commitSale()` (hold→sale 전환) + `createMirror()` 호출 |
| `cancelOrder()` | `releaseHold()` 호출. 이미 delivered 였으면 `nullifyMirror()` 도 호출 |
| `adjustStock()` | **삭제** (책임을 OnlineOrderStockService 로 이관) |

### 6.4 신규 cron: `OnlineOrdersExpiryCron`

파일: `api-ventago/src/app/online-orders/online-orders-expiry.cron.ts`

```typescript
@Cron('*/15 * * * *')  // 15분마다
async expireOldPending() {
  // 24시간 이상 pending → cancel + hold release
  // store.cron.ts 패턴 참고
}
```

### 6.5 DTO 변경

- `CreateOnlineOrderDto` — `branchId?: number`, `paymentMethodId?: number` 추가
- `ShipOnlineOrderDto` — 변경 없음

### 6.6 모듈 wiring

- `OnlineOrdersModule` imports: `SalesModule` (mirror 생성용), `StocksModule` (없으면 Stocks 모델 직접 import)
- providers: `OnlineOrderStockService`, `OnlineOrderSalesMirrorService`, `OnlineOrdersExpiryCron`

---

## 7. 프론트엔드 변경 (최소)

| 파일 | 변경 |
|---|---|
| `views/ventas-online/VentasOnlineView.tsx` | KPI 카드에 "예약중 재고 (hold) N개" 표시 |
| `views/ventas-online/OrderDetailView.tsx` | 결제수단 select (payment_methods 드롭다운), 지점 select |
| `views/ventas-online/CreateOrderDialog.tsx` (있을 경우) | branchId, paymentMethodId 필드 추가 |

SWR 훅은 변경 없음 (기존 `/online-orders` 응답에 새 필드만 추가됨).

---

## 8. 태스크 목록 (4 Wave)

### Wave 1 — DB 마이그레이션 + 모델 (반일)
- [ ] TASK-1.1: 사전 점검 — `error-2026-05-01.log` 의 ProductBranch 에러 원인 확인 (운영 영향 없는지)
- [ ] TASK-1.2: 마이그레이션 SQL 작성 — `phase28-online-orders-integration.sql`
- [ ] TASK-1.3: dev DB 적용 + 검증 (mcp__postgres-ventago__query 로 SELECT)
- [ ] TASK-1.4: `OnlineOrder` 모델에 `branchId`, `paymentMethodId`, `mirrorSaleId`, `stockHeldAt`, `stockReleasedAt` 컬럼 추가
- [ ] TASK-1.5: `Sale` 모델에 `source`, `onlineOrderId` 컬럼 추가
- [ ] TASK-1.6: `npm run build` (api-ventago) 통과

### Wave 2 — 재고 통합 (1일)
- [ ] TASK-2.1: `OnlineOrderStockService` 신규 작성 (4개 메서드)
- [ ] TASK-2.2: `OnlineOrdersService.create()` 수정 — `holdStock` 호출
- [ ] TASK-2.3: `confirmOrder` 에서 재고 차감 제거 (hold 그대로 유지)
- [ ] TASK-2.4: `cancelOrder` 에서 `releaseHold` 호출
- [ ] TASK-2.5: 기존 `adjustStock` 메서드 삭제
- [ ] TASK-2.6: 단위 테스트 — `online-order-stock.service.spec.ts`
- [ ] TASK-2.7: ESLint + build 통과

### Wave 3 — Sales Mirror (1일)
- [ ] TASK-3.1: `OnlineOrderSalesMirrorService` 신규 작성
- [ ] TASK-3.2: `deliverOrder` 에 `commitSale` + `createMirror` 호출 추가
- [ ] TASK-3.3: `cancelOrder` 분기 — delivered 였으면 `nullifyMirror` 추가
- [ ] TASK-3.4: 반품(`createReturn`) 시 mirror 역분개 검토
- [ ] TASK-3.5: `OnlineOrdersExpiryCron` 작성 (24시간 미결제 자동 cancel)
- [ ] TASK-3.6: 단위 테스트 — mirror 생성 멱등성, 동시성
- [ ] TASK-3.7: ESLint + build 통과

### Wave 4 — 프론트 + 검증 (반일)
- [ ] TASK-4.1: `VentasOnlineView` KPI 카드에 hold 재고 표시
- [ ] TASK-4.2: `OrderDetailView` 에 결제수단/지점 select
- [ ] TASK-4.3: 주문 생성 폼에 branchId/paymentMethodId 추가
- [ ] TASK-4.4: ESLint (api-ventago + ventago-app) 통과
- [ ] TASK-4.5: 통합 시나리오 검증 (아래 §9)

---

## 9. 통합 시나리오 검증 (Wave 4 끝)

dev DB 에서 다음 시나리오를 끝까지 추적:

1. **정상 흐름**:
   `POST /online-orders` (pending) → Stocks ledger 에 `type='suspend' stock=-qty` 1건 생긴다
   → `PATCH /confirm` → 변화 없음 (hold 유지)
   → `PATCH /ship` → 변화 없음
   → `PATCH /deliver` → Stocks 에 `type='suspend' stock=+qty` (release) + `type='sale' stock=-qty` 2건 추가, sales 에 mirror row 1건 생성, paymentStatus=paid
   → `GET /reports/sales-cockpit` 일일 매출에 mirror row 의 total 이 포함되는지 확인

2. **취소 흐름 (pending 단계)**:
   pending → cancel → Stocks 에 release (+qty) 1건. sales mirror 없음.

3. **취소 흐름 (delivered 후)**:
   delivered → cancel → sales mirror 역분개 + Stocks 입고 처리.

4. **만료 cron**:
   24시간 + 1분 전 created_at 의 pending 주문 1건 → cron 실행 후 cancelled, hold release 됨.

5. **동시성**:
   같은 상품 마지막 1개에 대해 pending 주문 2건 동시 생성 시도 → 두 번째 요청은 BadRequest (재고 부족) 또는 SERIALIZABLE 충돌로 retry 후 fail.

---

## 10. 완료 기준

- [ ] ESLint warning/error 0개 (api-ventago + ventago-app)
- [ ] `npm run build` 양 워크스페이스 모두 통과
- [ ] 시나리오 §9 의 5개 케이스 모두 dev DB 에서 PASS
- [ ] PostgreSQL pool 체크리스트:
  - 모든 새 트랜잭션 finally 에서 commit/rollback 보장
  - 새 Sequelize 인스턴스 생성 X (InjectConnection 재사용)
  - 외부 호출 메서드는 `t: Transaction` 파라미터로 트랜잭션 전파
- [ ] 신규 단위 테스트 4건 이상 (stock service 2 + mirror service 2)
- [ ] 마이그레이션 SQL 운영 적용 가능 상태 (사용자 동의 후 적용 — 이번 phase 에서는 적용 X)

---

## 11. 금지사항 / 주의사항

- ❌ **운영 DB 자동 적용 금지** — DDL 은 사용자 동의 후 영업 종료 시간대에 수동 적용
- ❌ **새 Pool 인스턴스 생성 금지** — 기존 Sequelize 단일 인스턴스만 사용
- ❌ **`Stocks` 우회 금지** — `products.stock` 만 직접 변경하는 코드 추가 금지. 반드시 `Stocks` ledger 경유.
- ❌ **트랜잭션 분리 금지** — 재고 hold + sales mirror 는 같은 SERIALIZABLE 트랜잭션 안에서 처리
- ❌ **하드코딩 매장 ID 금지** — 모든 쿼리는 `storeId` 파라미터화
- ⚠️ **사전 환경 이슈** — `ProductBranch`/`product_branches` 충돌 (로그 2026-05-01) 는 본 phase 범위 외이지만 dev DB 가 깨져있으면 Wave 1 진행 불가 → TASK-1.1 에서 우선 진단

---

## 12. Out of Scope (Phase 29+ 로 분리)

- Mercado Libre / WhatsApp 실제 API webhook 연동
- 결제 게이트웨이 webhook (MercadoPago)
- 자동 송장 PDF 생성 (zebra-agent 통합)
- 매장별 매출인식 시점 설정 (`stores.online_revenue_recognition`) — 기본 `delivered` 로 고정
- 반품 환불액 자동 계산 (현재는 수동 입력)

---

## 13. 커밋 전략

| Wave | 커밋 메시지 |
|------|--------------|
| 1 | `feat(online-orders): Phase 28 Wave 1 — DB 통합 컬럼 + 모델 (branch_id, payment_method_id, mirror_sale_id, sales.source/online_order_id)` |
| 2 | `feat(online-orders): Phase 28 Wave 2 — Stocks ledger 통합 (suspend hold/release/sale 패턴)` |
| 3 | `feat(online-orders): Phase 28 Wave 3 — Sales mirror + 만료 cron + 반품 역분개` |
| 4 | `feat(ventas-online): Phase 28 Wave 4 — 프론트 통합 + 통합 시나리오 검증` |
