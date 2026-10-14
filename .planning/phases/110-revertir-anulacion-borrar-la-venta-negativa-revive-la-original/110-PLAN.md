# Phase 110 — Anulación 되돌리기 (마이너스 판매를 지우면 원래 판매가 살아남)

## 요청 (2026-10-14 사용자)
> 0001 이 0002 에 의해 anula 된 경우 0002 를 지우면 0001 이 다시 살아나 영수증·reimprimir 가능.
> 0001 이 0002 로 anula 되고 0003 으로 대체된 경우는 0002 를 지울 수 없고 0001 도 살릴 수 없다.
> 하나의 anulación 이 다른 매장에 영향 주는 일이 절대 없도록.

## 연결 구조 (근거)
- 원본 `Anulado` + `nullified_by_sale_id=역분개` (sales-create.service.ts:2343-2349) / 역분개 `Anulación` + `nullified_sale_id=원본` (:1984, :2004)
- 대체 판정: 새 판매 `replaces_sale_id=원본` (sales-modify.service.ts:503) → `EXISTS(... replaces_sale_id=원본 AND store_id=원본.store_id)`
- 재취소 인덱스 `uq_sales_one_reversal_per_sale` → 되돌릴 때 역분개의 `nullified_sale_id` 를 비운다

## 허용 조건 (락 잡은 뒤 트랜잭션 안에서)
E1 대상 = `Anulación` 행 · E2 원본 `Anulado` 양방향 일치 · **E3 원본·역분개·요청 매장 동일, 지점 접근 범위 안 (아니면 404)**
E4 대체 판매 없음 · E5 역분개가 매장 기준 오늘 · E6 취소 현금 box_operation 의 caja 세션이 아직 열림
E7 원본 `mp_refunds` 없음(실패 포함) · E8 NC(afip_vouchers) 없음(원본 Factura 는 허용)
E9 `credit_ledger` 에 역분개 기록 없음 · E10 온라인 주문·교환(합계<0)·회수 판매 아님

## 되돌리기 = 보정 행 (원장 삭제 없음)
- stocks: 실제 기록된 `anulacion sale_id=X` 행 합을 매장 조인으로 집계 → `−qty` 보정 행 (`reversion-anulacion`), 잔액은 트리거
- box_operations: 반대 유형 같은 금액, 같은 열린 세션
- 원본 → `Pagado` (새 컬럼 `status_before_nullify`, 없으면 Pagado), `nullified_by_sale_id=NULL`
- 역분개 → `Anulación revertida`, `nullified_sale_id=NULL`, `reverted_nullified_sale_id`, `nullification_reverted_at/by`; daily_number 유지
- sync_outbox 재고 push · @Audit 로그
- 집계: `ACCOUNTING_SALE_STATUSES`(허용 목록)는 자동 제외. **제외 목록 필터 ~90곳**(sales.service:1370 NOT_VOID 등) → `SQL_NOT_VOID` 상수로 통일
- `nullifyInTransaction` / `assertModifiable` 에 `Anulación revertida` 거부 추가

## 테넌트 격리 (최우선)
첫 락 `SELECT … WHERE id=ANY($ids) AND store_id=$store ORDER BY id FOR UPDATE` (2행 아니면 404). 이후 모든 쿼리 store 조건.
itest: 타 매장 id → 404 + 그 매장 sales/stocks/stock_balances/box_operations/credit_ledger 전후 동일, `v_stock_tenant_leak`·drift 0행. 돌연변이: store 조건 제거 시 시험 실패.

## 동시성
lock_timeout 3s · 락 순서 = 취소와 동일(sales id 오름차순 → stock scope productId 오름차순 → caja) · 두 번째 요청 409 · 버튼 비활성화

## API / 앱 / DB
- `GET /sales/:id/revert-nullification/preview` → `{eligible, reasons[]}` · `POST /sales/:id/revert-nullification` · `@FunctionGuard('modificar-venta','update')`
- 앱: Anulación 행의 «Delete» = 되돌리기 (eligible 일 때만, 아니면 tooltip 사유) · SaleDetailPanel 동일
- 마이그레이션(expand): sales 에 `reverted_nullified_sale_id`, `nullification_reverted_at`, `nullification_reverted_by`, `status_before_nullify` (nullable)

## 결정 필요 (권고)
1. 당일 + caja 세션 열림일 때만 → **예**
2. MP 환불 시도 이력(실패 포함) 있으면 차단 → **차단**
3. 외상·seña·favor·교환·온라인 주문은 v1 제외 → **제외**
4. 0002 는 목록에 「Anulación revertida」로 회색 표시 → **남김**
5. 권한 = 취소와 동일(modificar-venta) → **동일**
6. 취소 시 WooCommerce 재고 push 누락(기존 결함)도 함께 수정 → **예**

## 규모 L · 위험: 제외 목록 필터 누락 시 음수 매출 재집계 → 상수화 + grep 시험
