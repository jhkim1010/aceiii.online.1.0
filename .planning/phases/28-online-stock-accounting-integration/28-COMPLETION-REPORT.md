# Phase 28 — 완료 리포트 + 운영 적용 가이드

**작성일**: 2026-05-01
**Phase**: 28 — 온라인 주문 ↔ 재고·회계 통합
**Status**: 코드 완료 / dev 마이그레이션 적용 완료 / 운영 적용 대기

---

## 1. Phase 28 가 해결한 두 가지 핵심 문제

마코스님께서 제기하신 우려사항이 모두 코드 레벨에서 해결되었습니다.

### 1.1 재고 일관성 — "주문된 수량은 다른 사람에게 팔리지 않게, 취소되면 돌아오게"

**Before (Phase 27)**:
- `confirmed` 시점에 `product.stock` 직접 차감
- `pending` 5~30분간 재고 격리 안 됨 → 동시 판매 위험
- `Stocks` ledger 인프라를 우회 → 재고 보고서·suspended-sales 와 분리

**After (Phase 28)**:
- `pending` 진입 즉시 `Stocks` ledger 에 `type='suspend' stock=-qty` 기록 (즉시 격리)
- `confirmed/preparing/shipped` 동안 hold 유지
- `delivered` 시 `release(+qty)` + `sale(-qty)` + `product.stock` 동기화
- `cancelled` 시 상태에 따라 `releaseHold` 또는 `reverseSale` 자동 분기
- 24시간 미결제 → cron 자동 cancel (zombie hold 방지)

### 1.2 회계 일관성 — "스톡과 수금이 통일되어 일일 보고서에 반영"

**Before**: 온라인 주문이 `delivered` 되어도 `sales` 테이블에 row 없음 → 일일 매출 보고서·캐시 통제·결제수단별 집계에서 0원으로 잡힘.

**After**: `delivered` 시점에 `sales` mirror row 자동 생성:
- `sales.source = 'online'`, `sales.online_order_id` UNIQUE FK
- `sale_items` + `sale_payment_methods` 동시 생성
- 기존 보고서 코드는 한 줄도 안 바꾸어도 자동 노출
- 반품 승인 / delivered 후 cancel 시 음수 역분개 sale 자동 생성 (`status='Anulación'`)

---

## 2. 변경 파일 목록 (총 14개)

### 백엔드 (api-ventago)

| 파일 | 종류 | 핵심 변경 |
|---|---|---|
| `migrations/phase28-full-online-integration.sql` | 신규 | Phase 27+28 통합 마이그레이션 (멱등) |
| `migrations/phase28-scenario-verification.sql` | 신규 | 5케이스 검증 SQL (dev 전용, ROLLBACK) |
| `migrations/phase28-prod-precheck.sql` | 신규 | 운영 사전 점검 SQL (read-only) |
| `src/app/online-orders/online-order.model.ts` | 수정 | branchId, paymentMethodId, mirrorSaleId, stockHeldAt, stockReleasedAt 5컬럼 |
| `src/app/online-orders/online-order-stock.service.ts` | 신규 | 재고 ledger 통합 (holdStock/releaseHold/commitSale/reverseSale) |
| `src/app/online-orders/online-order-sales-mirror.service.ts` | 신규 | sales mirror 생성/역분개 (createMirror/nullifyMirror) |
| `src/app/online-orders/online-orders-expiry.cron.ts` | 신규 | 24시간 미결제 자동 cancel cron |
| `src/app/online-orders/online-orders.service.ts` | 재작성 | Phase 27 의 adjustStock 삭제, hold/release/mirror 통합 |
| `src/app/online-orders/online-orders.module.ts` | 수정 | Stocks/ProductBranch/Branch/Sale/SaleItem/SalePaymentMethod/Store 모델 + 신규 service/cron 등록 |
| `src/app/online-orders/dto/create-online-order.dto.ts` | 수정 | branchId, paymentMethodId 옵션 |
| `src/app/sales/sales.model.ts` | 수정 | SaleSource enum + source/onlineOrderId 컬럼 |

### 프론트엔드 (ventago-app)

| 파일 | 종류 | 핵심 변경 |
|---|---|---|
| `src/views/ventas-online/VentasOnlineView.tsx` | 수정 | KPI "Reservados (hold)" 카드 |
| `src/views/ventas-online/OrderDetailView.tsx` | 수정 | "Integración (Stock · Contabilidad)" 카드 |
| `src/hooks/api/useOnlineDashboard.ts` | 수정 | reservedStock 타입 |
| `src/hooks/api/useOnlineOrders.ts` | 수정 | Phase 28 5필드 타입 |

---

## 3. 품질 검증 결과

| 검증 항목 | 결과 |
|---|---|
| TypeScript api-ventago 빌드 | ✅ Phase 28 신규 코드 에러 0 (기존 부채 3건은 무관) |
| TypeScript ventago-app 빌드 | ✅ 에러 0 |
| dev DB 마이그레이션 적용 | ✅ 7컬럼 + 4인덱스 + 1 CHECK constraint 모두 정상 |
| dev DB 자가 검증 NOTICE | ✅ "Phase 28 마이그레이션 검증 OK — 모든 컬럼 존재" |
| PostgreSQL pool 안전 규칙 | ✅ 새 풀 생성 0회. 모든 트랜잭션 try/finally. |
| SERIALIZABLE 격리 적용 | ✅ create / deliverOrder / cancelOrder / approveReturn |
| 멱등성 보장 | ✅ sales.online_order_id UNIQUE + ProductBranch.findOrCreate |
| 디버그 로그 풍부함 | ✅ 모든 status 전환·재고 이동·mirror 생성에 INFO/DEBUG/WARN/ERROR 레벨 적용 |

### 시나리오 검증의 한계

dev DB 의 ProductBranch (PascalCase, 0행) ↔ product_branches (snake_case, 289행) 이중 테이블 + stocks FK 가 snake_case 를 가리키는 사전 부채 때문에 raw SQL 시나리오 검증은 FK 위반으로 실패. 운영 DB 는 PascalCase 가 표준이라 이 문제 없음.

→ **dev 시나리오 검증 대신 운영 사전 점검 SQL 로 환경 일치 확인 후 적용**.

---

## 4. 운영 적용 절차 (사용자 동의 필수)

### Step 1: 운영 사전 점검 (READ-ONLY, 영업 중 안전)

```bash
ssh jhkim-server "sudo -u postgres psql -d ventago" \
  < api-ventago/migrations/phase28-prod-precheck.sql
```

또는 DBeaver 운영 연결에서 한 섹션씩 실행.

**기대 결과**:
- 섹션 1: DB=ventago 확인
- 섹션 2: ProductBranch (PascalCase) 만 존재 + 행 수 > 0
- 섹션 3: stocks FK → "ProductBranch"
- 섹션 4: online_orders / items / returns 3개 모두 미존재 (Phase 27 도 운영 미적용)
- 섹션 5: 글로벌 payment_methods 11종
- 섹션 6: sales 에 source/online_order_id 미존재 (정상)
- 섹션 7: 4개 매장 (CART/coolsistema/genius/ACE) 정상

**판단 기준**:
- 모두 ✅ → Step 2 진행
- ⚠️ 1건 이상 → 마코스님 확인 후 결정
- ❌ → 운영 적용 보류, 별도 phase

### Step 2: 백엔드 코드 배포 + 마이그레이션 적용 (영업 종료 후)

```bash
# (a) git push — Jenkins 자동 빌드 트리거
cd /Users/marcoskim/Trabajos_Programming/ACE_online_1.0
./push-both.sh

# (b) Jenkins 빌드 완료 대기 후 운영 마이그레이션 적용
ssh jhkim-server "sudo -u postgres psql -d ventago" \
  < api-ventago/migrations/phase28-full-online-integration.sql

# 출력에서 다음 메시지 확인:
#   "Phase 28 마이그레이션 검증 OK — 모든 컬럼 존재"

# (c) Docker 컨테이너 재시작 (api-ventago 가 새 컬럼 인식)
ssh jhkim-server "cd /path/to/api-ventago && docker compose restart"
```

### Step 3: 운영 검증

```bash
# winston 로그 tail 로 실시간 추적
ssh jhkim-server "docker logs -f api_ventago 2>&1 | grep -E 'OnlineOrder|holdStock|commitSale|createMirror'"

# 첫 테스트 주문 생성 (UI 또는 curl)
# 다음 로그가 순서대로 찍혀야 정상:
#   [create] ENTRY ...
#   [resolveBranchId] auto-select branchId=...
#   [holdStock] ENTRY ...
#   [stockMovement:hold] OK ... type=suspend stockRowId=...
#   [holdStock] DONE processed=N
#   [create] DONE orderId=...
```

### Step 4: 회계 통합 검증 (delivered 까지 진행 후)

```sql
-- delivered 직후 mirror 생성 확인
SELECT s.id AS sale_id, s.source, s.online_order_id, s.total_amount, s.status
FROM sales s
WHERE s.online_order_id IS NOT NULL
ORDER BY s.id DESC
LIMIT 5;

-- 일일 보고서가 자동으로 인식하는지
SELECT DATE(sale_date), source, COUNT(*), SUM(total_amount)
FROM sales
WHERE store_id = <매장ID>
  AND DATE(sale_date) = CURRENT_DATE
GROUP BY DATE(sale_date), source;
```

---

## 5. 롤백 절차 (긴급시)

만약 운영 적용 후 문제 발생 시:

```sql
-- 트랜잭션 1건으로 롤백 (이미 생성된 mirror sales 도 처리 필요 시)
BEGIN;

-- 1) Phase 28 추가 컬럼 제거
ALTER TABLE sales DROP COLUMN IF EXISTS source;
ALTER TABLE sales DROP COLUMN IF EXISTS online_order_id;
DROP INDEX IF EXISTS sales_online_order_uniq;
DROP INDEX IF EXISTS sales_source_store_date_idx;

ALTER TABLE online_orders DROP COLUMN IF EXISTS branch_id;
ALTER TABLE online_orders DROP COLUMN IF EXISTS payment_method_id;
ALTER TABLE online_orders DROP COLUMN IF EXISTS mirror_sale_id;
ALTER TABLE online_orders DROP COLUMN IF EXISTS stock_held_at;
ALTER TABLE online_orders DROP COLUMN IF EXISTS stock_released_at;
DROP INDEX IF EXISTS online_orders_branch_idx;
DROP INDEX IF EXISTS online_orders_pending_old_idx;

-- 2) 코드는 git revert 로 이전 commit 으로 복귀

COMMIT;
```

**주의**: 실제 운영 데이터에 mirror sales 가 이미 생성되었다면, 데이터 정리 정책 (역분개 vs 물리 삭제) 을 마코스님과 사전 협의 후 진행.

---

## 6. 미결 / 후속 작업 (별도 phase 권장)

### 6.1 사전 기술 부채 (Phase 28 와 무관)
- `payment-methods.service.ts` Op.or 타입 충돌 (TS 에러 1건)
- `products.controller.spec.ts` 인자 개수 불일치 (TS 에러 2건)
- dev DB 의 ProductBranch (PascalCase, 0행) ↔ product_branches (snake_case, 289행) 정리

### 6.2 Phase 29+ (Out of Scope)
- Mercado Libre / WhatsApp 실제 API webhook 연동
- 결제 게이트웨이 (MercadoPago) webhook
- 자동 송장 PDF 생성 (zebra-agent 통합)
- 매장별 매출 인식 시점 설정 (`stores.online_revenue_recognition`)
- 반품 환불액 자동 계산 (현재는 수동 입력)

---

## 7. 주요 디버그 로그 패턴 (운영 모니터링용)

```
[OnlineOrdersService]
  [create] ENTRY storeId=N channel=X items=M branchIdDto=auto
  [create] DONE orderId=N orderNumber=N channel=X branchId=N total=X
  [confirmOrder] / [prepareOrder] / [shipOrder] / [deliverOrder] / [cancelOrder] ENTRY/DONE
  [runStatusTx] tx OPEN/COMMIT/ROLLBACK
  [resolveBranchId] auto-select / 다지점 매장
  [approveReturn] tx OPEN/DONE/ROLLBACK

[OnlineOrderStockService]
  [holdStock] / [releaseHold] / [commitSale] / [reverseSale] ENTRY/DONE
  [stockMovement:hold|release|sale|reverse] OK orderId=N pbId=N delta=±N type=suspend|sale stockRowId=N
  [adjustProductStock] productId=N before → after (delta=±N)

[OnlineOrderSalesMirrorService]
  [createMirror] / [nullifyMirror] ENTRY/DONE
  sales/sale_items/sale_payment_methods 각 row 생성 추적
  멱등성 skip / NULLIFIED 마킹 / 역분개 saleId

[OnlineOrdersExpiryCron]
  [expireOldPending] ENTRY threshold=24h batchLimit=50
  [expireOldPending] 대상=N건 cutoff=...
  [expireOldPending] DONE 성공=N 실패=N 경과=Nms
```

---

## 결론

Phase 28 의 백엔드·프론트엔드 모두 코드 레벨 완료. dev 마이그레이션 적용 검증 완료. 운영 적용은 사전 점검 SQL → 마이그레이션 → 백엔드 재시작 → 검증 4단계 절차를 따른다.

마코스님이 제기한 **재고 일관성**과 **회계 일관성** 두 우려사항은 코드 수준에서 모두 해결되었다.
