# Phase 6: Reportajes (15개 보고서 시스템) - Context

**Gathered:** 2026-04-06
**Status:** Ready for planning
**Source:** Conversation-derived (기존 POS 시스템 스크린샷 + 코드 탐색)

<domain>
## Phase Boundary

기존 POS 시스템의 15개 보고서를 Ventago에 완전 구현.
- 기존 완료: Ventas, Items(Venta), StockRpt Gen (3개)
- 신규 구현: 12개 보고서
- 모든 보고서는 Reportajes 사이드바 메뉴 하위에 위치

</domain>

<decisions>
## Implementation Decisions

### 아키텍처 패턴 (Locked)
- 기존 보고서 패턴 따름: Frontend Hook → Backend Service → Excel Export
- 백엔드: `api-ventago/src/app/reports/` 모듈에 서비스 추가
- 프론트엔드: `ventago-app/src/views/reports/` 에 뷰 추가, `ventago-app/src/pages/reportes/` 에 페이지 추가
- 모든 보고서는 QuerysDto 패턴 사용 (startDate, endDate, filter, branchId 등)

### 15개 보고서 목록 (Locked)

| # | 보고서 | 설명 | Wave | 데이터 소스 |
|---|--------|------|------|------------|
| 1 | Ventas | 매출 보고서 | ✅완료 | Sales |
| 2 | Items (Venta) | 상품별 판매 | ✅완료 | SaleItem |
| 3 | StockRpt Gen | 재고 보고서 | ✅완료 | Stocks |
| 4 | Vendedor | 판매원별 실적 | Wave 1 | Sale.sellerId |
| 5 | Gasto | 비용 보고서 | Wave 1 | Expenses |
| 6 | Fallados | 취소/실패 판매 | Wave 1 | Sale.status=Anulado |
| 7 | Corregido (C) | 수정 판매 | Wave 1 | Sale.status=Anulación |
| 8 | Breve Venta | 간략 매출 요약 | Wave 2 | Sales (일별/시간대별 집계) |
| 9 | Facturacion | 청구서 현황 | Wave 2 | Sale.status=Facturado |
| 10 | Clientes (Credito) | 고객 외상 | Wave 2 | StoreClient.balance/creditLimit |
| 11 | Ingreso (Deposito) | 입고/입금 내역 | Wave 3 | Stocks(+방향), BoxOperation |
| 12 | Movidos | 재고 이동 | Wave 3 | Stocks movements |
| 13 | Reservado | 보류 판매 | Wave 3 | SuspendedSale |
| 14 | Alertas | 알림 (재고부족 등) | Wave 4 | 계산 기반 (새 로직) |
| 15 | Cheque Estado | 수표/결제 상태 | Wave 4 | 새 모델 필요 가능 |

### Wave 구조 (Locked)
- **Wave 1 (06-01)**: Vendedor, Gasto, Fallados, Corregido + 보고서 허브 페이지 — 기존 데이터만 활용
- **Wave 2 (06-02)**: Breve Venta, Facturacion, Clientes Credito — 매출 데이터 확장 집계
- **Wave 3 (06-03)**: Ingreso Deposito, Movidos, Reservado — 재고/보류 데이터 활용
- **Wave 4 (06-04)**: Alertas, Cheque Estado + 대시보드 통합 — 새 모델/로직 필요

### 공통 기능 (Locked)
- 모든 보고서에 기간별(startDate/endDate) 필터링
- 모든 보고서에 지점별(branchId) 필터링
- 모든 보고서에 Excel 내보내기
- 모든 보고서에 텍스트 검색 필터
- 화면 높이 기반 자동 pageSize 조절 (PermissionsListView 패턴)
- 검색 input은 상시 노출 (필터 버튼 없이), 0.5초 debounce

### UI 패턴 (Locked)
- CardFilter 컴포넌트 사용 (showFilterButton=false, 검색 input을 actions에 배치)
- FullTable 컴포넌트 사용 (서버 사이드 페이지네이션)
- 기존 보고서(Ventas, Items, StockRpt)의 뷰 패턴 그대로 활용
- 보고서 허브 페이지: /reportes/ 에 15개 보고서 링크가 그리드로 표시

### Claude's Discretion
- 각 보고서의 세부 테이블 컬럼 구성
- Alertas 보고서의 알림 조건 (재고 부족 기준값 등)
- Cheque Estado 모델 설계 (필요 시)
- 대시보드 차트 종류 및 배치

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### 기존 보고서 패턴 (필수 참조)
- `ventago-app/src/views/reports/sales/SalesReport.tsx` — 매출 보고서 뷰 패턴
- `ventago-app/src/views/reports/sales/hooks/useSalesReport.ts` — 보고서 Hook 패턴
- `api-ventago/src/app/reports/reports.controller.ts` — 보고서 API 엔드포인트 패턴
- `api-ventago/src/app/reports/reports-sales.service.ts` — 보고서 서비스 패턴 (쿼리, Excel)

### 데이터 모델 (필수 참조)
- `api-ventago/src/app/sales/sales.model.ts` — Sale 모델 (status, sellerId)
- `api-ventago/src/app/expenses/expenses.model.ts` — Expense 모델
- `api-ventago/src/app/suspended-sales/suspended-sales.model.ts` — SuspendedSale 모델
- `api-ventago/src/app/clients/clients.model.ts` — Client 모델
- `api-ventago/src/app/store/store-client/store-client.model.ts` — StoreClient (balance, creditLimit)
- `api-ventago/src/app/products/products.model.ts` — Product 모델

### UI 컴포넌트
- `ventago-app/src/components/cards/CardFilter.tsx` — 보고서 카드 래퍼
- `ventago-app/src/components/table/FullTable.tsx` — 데이터 테이블

### 네비게이션
- `ventago-app/src/navigation/vertical/index.ts` — 사이드바 메뉴 (reportes 앱)
- `api-ventago/src/app/modules/seed/modules.seed.ts` — Reportajes 모듈 seed

</canonical_refs>

<specifics>
## Specific Ideas

- 기존 POS 시스템에서 "Imprimir Reportaje" 패널에 15개 버튼이 5x3 그리드로 배치됨
- Ventago에서는 사이드바 하위 메뉴로 구현하되, /reportes/ 페이지에 허브(버튼 그리드) 표시
- 기존 보고서 3개(Ventas, Items, StockRpt)는 이미 잘 동작하므로 구조만 허브에 통합

</specifics>

<deferred>
## Deferred Ideas

- 보고서 PDF 내보내기 (현재는 Excel만)
- 보고서 자동 이메일 발송 (스케줄링)
- 보고서 커스텀 템플릿

</deferred>

---

*Phase: 06-reportajes*
*Context gathered: 2026-04-06 via conversation*
