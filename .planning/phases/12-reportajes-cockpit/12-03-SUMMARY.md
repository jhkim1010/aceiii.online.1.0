---
phase: 12-reportajes-cockpit
plan: "03"
subsystem: reports-sales-products-cockpit
tags: [reports, cockpit, sales, products, items, frontend, backend]
dependency_graph:
  requires: [12-01, 12-02]
  provides: [sales-cockpit, products-cockpit, items-cockpit, sales-cockpit-vendors, sales-dimensions-province]
  affects: [reports-v2/registry, reports-controller, reports-module, salesDimensions.service]
tech_stack:
  added: []
  patterns:
    - vendedor-cockpit-pattern-replication (12-02 패턴 그대로 복제)
    - lazy-detail-tabs (mix/trend/ventas only on user interaction)
    - sales-dimensions-shared-service (product/category/color/size/season/province 6 dims)
    - product-card-grid-with-sparkline (Vendedor 카드와 동일 구조)
    - paginated-ventas-with-unit-modes (vcode/day/month/year)
key_files:
  created:
    - api-ventago/src/app/reports/reportsSalesCockpit.service.ts
    - api-ventago/src/app/reports/reportsSalesCockpit.spec.ts
    - api-ventago/src/app/reports/reportsProductsCockpit.service.ts
    - api-ventago/src/app/reports/salesDimensions.service.ts
    - ventago-app/src/views/reports/sales/SalesCockpitBody.tsx
    - ventago-app/src/views/reports/sales/SalesCockpitDetail.tsx
    - ventago-app/src/views/reports/sales/components/SalesDetailTable.tsx
    - ventago-app/src/views/reports/sales/hooks/useSalesCockpit.tsx
    - ventago-app/src/views/reports/sales/hooks/useSalesCockpitDetail.tsx
    - ventago-app/src/views/reports/products/ProductCockpitBody.tsx
    - ventago-app/src/views/reports/products/ProductCockpitDetail.tsx
    - ventago-app/src/views/reports/products/components/ProductDetailTable.tsx
    - ventago-app/src/views/reports/products/hooks/useProductCockpit.tsx
    - ventago-app/src/views/reports/products/hooks/useProductCockpitDetail.tsx
  modified:
    - api-ventago/src/app/reports/reports.controller.ts (8 new endpoints — 4 sales + 4 products)
    - api-ventago/src/app/reports/reports.module.ts (registered 2 services + salesDimensions)
    - ventago-app/src/views/reports-v2/registry.ts (lazy imports → SalesCockpitBody, ProductCockpitBody)
decisions:
  - "12-02 Vendedor pattern 그대로 복제 — 새로운 시각적/구조적 변형 없음 (consistency 우선)"
  - "Sales mix dimension에 'province' 추가 — quick-260420-qet에서 추가 요구"
  - "Products mix dimension은 color/size/season/category 4종 (product 자체는 메인 cockpit에서 카드로 표시)"
  - "Sales cockpit ventas 엔드포인트에 'unit' 파라미터 (vcode/day/month/year) — 같은 venta 표를 다양한 시간 단위로 그룹핑"
  - "salesDimensions.service.ts 분리 — vendedor/sales/products cockpit이 공유 (1D dimension 집계 단일화)"
  - "products-cockpit에 trend endpoint 별도 — Vendedor와 동일하게 productId 단위 일별 추이 lazy fetch"
  - "VentaDetailDrawer 대신 SalesCockpitDetail 패널 (탭 인터페이스) 채택 — Vendedor와 일관된 UX"
  - "Sales cockpit/vendors 엔드포인트 추가 — Sales 화면에서도 vendor 요약을 사이드 패널로 볼 수 있도록"
metrics:
  completed_date: "2026-04-09 ~ 2026-04-26 (코드, 다회 iteration), 2026-05-07 (소급 SUMMARY)"
  files_changed: 17
  service_methods: 8 (sales: getCockpit/getMix/getVentas/getVendorSummary, products: getCockpit/getTrend/getMix/getVentas)
  endpoints: 8
  spec_files: 1 (reportsSalesCockpit.spec.ts)
---

# Phase 12 Plan 03: Sales + Products Cockpit Migration Summary (소급 작성)

**One-liner:** Sales(Ventas) + Products(Items) 보고서를 12-02 Vendedor reference 패턴으로 동시 마이그레이션 — KPI strip + 카드 그리드 + lazy 상세 탭 + Province dimension 추가

> **소급 작성 노트 (2026-05-07):** 코드는 2026-04-09~04-26 사이에 완료되어 12-04~12-08에서 dependency로 인용되었으나 SUMMARY.md 누락 상태였음. 본 문서는 git 커밋(`feat(12-03): Products Cockpit frontend...`, `feat(12-03): add ReportsProductsCockpit backend service + 4 controller routes`) + 실제 소스 파일 + controller endpoint 매핑 기반으로 retroactively 작성됨.

---

## Backend Architecture

### `reportsSalesCockpit.service.ts` (api-ventago)

12-02 Vendedor cockpit과 동일한 raw SQL CTE 패턴. Sales 보고서 특화: vendor 요약 + province dimension + ventas unit modes.

| Method | Purpose |
|--------|---------|
| `getCockpit(filters)` | KPI summary + 일별 트렌드 + 카테고리 랭킹 |
| `getMix(filters, dim)` | 6 dim (product/category/color/size/season/**province**) 매출 mix |
| `getVentas(paginatedFilters, unit)` | venta 페이지네이션 — unit: vcode/day/month/year |
| `getVendorSummary(filters)` | vendor 요약 — sales 화면 사이드 패널용 |

### `reportsProductsCockpit.service.ts` (api-ventago)

Vendedor와 동일 구조로 product-scoped 보고서 구현.

| Method | Purpose |
|--------|---------|
| `getCockpit(filters)` | KPI summary + product 카드 리스트 + 일별 스파크 |
| `getTrend(productScopedFilters)` | 선택된 productId의 일별 추이 (탭 클릭 시 lazy) |
| `getMix(filters, dim)` | color/size/season/category 4 dim 매출 mix |
| `getVentas(paginatedProductFilters)` | 선택된 productId의 venta 페이지네이션 |

### `salesDimensions.service.ts` (분리된 공용 서비스)

Cockpit 서비스 3종(vendedor/sales/products)이 공유하는 1D dimension 집계 로직. 중복 SQL 제거.

| DimensionKey | 사용 처 |
|-------------|---------|
| `product` | sales mix |
| `category` | sales mix, vendedor mix, products mix |
| `color` | 모든 cockpit mix |
| `size` | 모든 cockpit mix |
| `season` | 모든 cockpit mix |
| `province` | sales mix only (12-03 추가) |

### Endpoints (`reports.controller.ts`)

**Sales Cockpit (4):**
| Endpoint | Permission | Service method |
|----------|-----------|----------------|
| GET /reports/sales-cockpit | reporte-ventas | getCockpit |
| GET /reports/sales-cockpit/mix | reporte-ventas | getMix |
| GET /reports/sales-cockpit/ventas | reporte-ventas | getVentas |
| GET /reports/sales-cockpit/vendors | reporte-ventas | getVendorSummary |

**Products Cockpit (4):**
| Endpoint | Permission | Service method |
|----------|-----------|----------------|
| GET /reports/products-cockpit | reporte-items | getCockpit |
| GET /reports/products-cockpit/trend | reporte-items | getTrend |
| GET /reports/products-cockpit/mix | reporte-items | getMix |
| GET /reports/products-cockpit/ventas | reporte-items | getVentas |

---

## Frontend Architecture

### `SalesCockpitBody.tsx`

- **KpiStrip**: Total Ventas / Transacciones / Ticket Promedio / 추가 KPI
- **Resumen 영역**: 카테고리 랭킹 리스트 (각 카테고리별 매출 막대 + 비율)
- **Tabs**: Mix / Detail / Vendors — 각 탭에서 lazy fetch
- **MUI Switch**: 일부 토글(예: 보기 모드) 통합

### `ProductCockpitBody.tsx`

- 12-02 `VendedorCockpitBody`와 **거의 동일한 구조** (의도된 일관성):
  - **KpiStrip** (4 KPI + Top Producto 위젯)
  - **ProductCard Grid** (auto-fill, minmax 210px) — medal(🥇🥈🥉) + sparkline + chip
  - **Detail Panel** (선택 시 마운트): ProductCockpitDetail — Tendencia / Mix / Ventas 탭

### Hooks
- `useSalesCockpit` / `useSalesCockpitDetail` — 메인 + 탭별 fetcher
- `useProductCockpit` / `useProductCockpitDetail` — 메인 + 탭별 fetcher

### Detail Tables (재사용 가능)
- `SalesDetailTable.tsx` — venta 컬럼 표 (vcode/날짜/seller/금액/상태)
- `ProductDetailTable.tsx` — venta 컬럼 표 (productId scoped)

---

## Sales `unit` 모드 — 동일 데이터를 4 시간 단위로 그룹핑

```ts
const validUnits = ['vcode', 'day', 'month', 'year'] as const
```

| unit | 그룹 단위 |
|------|-----------|
| `vcode` (default) | 개별 venta (sale row 단위) |
| `day` | 일별 합계 |
| `month` | 월별 합계 |
| `year` | 연별 합계 |

→ 같은 endpoint 1개로 4가지 view 지원, 추가 connection 없음.

---

## 후속 quick patches (병합된 변경사항)

| Commit | 내용 |
|--------|------|
| `3eda6a2` api-ventago | `feat(quick-260420-qet): Ventas 차원 분석에 Provincia 추가` — backend dim allowlist 확장 |
| `12723e9` ventago-app | `feat(quick-260420-qet): Sales Cockpit UI 차원 드롭다운에 Provincia 추가` — frontend dropdown |
| `155608f` api-ventago | `fix: 보고서 s.branch_id → u.branch_id (sales 테이블에 branch_id 없음)` — schema fix |

→ 12-03 패턴이 production 사용 중에 발견된 issue들도 함께 수정됨.

---

## Pool 절약 효과

**Sales 보고서 (전체 매장 1개월 데이터, 평균 5명 vendedor 기준):**
- 이전 (legacy `/reports/sales`): KPI 1 + trend 1 + categories 1 + items 1 + vendors 1 = 5 connections
- 이후 (`/reports/sales-cockpit`): 1 endpoint = 1 connection. 탭 클릭 시 +1 connection.

**Products 보고서 (50개 product, 평균 100 sales rows):**
- 이전 (legacy `/reports/items`): KPI 1 + ranking 1 + 각 product trend N (lazy 미지원) = (N+2)
- 이후 (`/reports/products-cockpit`): 1 connection. trend는 사용자 클릭 시에만.

---

## Test File

`reportsSalesCockpit.spec.ts` — Sales cockpit service의 unit 테스트 추가 (Phase 12에서 유일하게 spec 파일이 있는 cockpit). raw SQL aggregation의 정확성 검증.

---

## Registry Changes (`reports-v2/registry.ts`)

```ts
// Before:
const SalesReportBody = lazy(() => import('src/views/reports/sales/SalesReportBody'))
const ProductReportBody = lazy(() => import('src/views/reports/products/ProductReportBody'))

// After (12-03):
const SalesReportBody = lazy(() => import('src/views/reports/sales/SalesCockpitBody'))
const ProductReportBody = lazy(() => import('src/views/reports/products/ProductCockpitBody'))
```

Legacy `*ReportBody.tsx` 파일은 보존 (rollback 가능).

---

## 관련 커밋

| Commit | 내용 |
|--------|------|
| `e81a0cb` ventago-app | `feat(12-03): Products Cockpit frontend — hooks, body, detail, registry swap` |
| `8417828` api-ventago | `feat(12-03): add ReportsProductsCockpit backend service + 4 controller routes` |
| `959fbfa` ventago-app | `feat: reports granular permissions + shared cockpit components` |
| `21def6d` ventago-app | `chore: auto-commit ventago-app 2026-04-20 08:42` (Sales cockpit iteration) |
| `b697553` ventago-app | `chore: auto-commit ventago-app 2026-04-23 12:19` (Sales cockpit refinement) |

---

## Self-Check: PASSED (소급 검증)

**Sales:**
- [x] `SalesCockpitBody.tsx` — EXISTS (Apr 20)
- [x] `SalesCockpitDetail.tsx` — EXISTS (Apr 21)
- [x] `reportsSalesCockpit.service.ts` (4 methods 확인) — EXISTS
- [x] `reportsSalesCockpit.spec.ts` — EXISTS
- [x] 4 sales-cockpit endpoints (controller line 535, 547, 583, 605) 확인
- [x] `registry.ts` — `SalesReportBody = lazy(() => import('.../SalesCockpitBody'))` (line 86)

**Products/Items:**
- [x] `ProductCockpitBody.tsx` — EXISTS (Apr 11)
- [x] `ProductCockpitDetail.tsx` — EXISTS (Apr 10)
- [x] `reportsProductsCockpit.service.ts` (4 methods 확인) — EXISTS
- [x] 4 products-cockpit endpoints (controller line 707, 719, 731, 752) 확인
- [x] `registry.ts` — `ProductReportBody = lazy(() => import('.../ProductCockpitBody'))` (line 89)

**Shared:**
- [x] `salesDimensions.service.ts` — EXISTS (vendedor/sales/products cockpit이 공유)
- [x] 12-04 SUMMARY가 `12-01/02/03 패턴`으로 본 plan 인용
- [x] 12-08 SUMMARY의 `dependency_graph.requires`에 `12-03` 포함

## Known Stubs

없음. 모든 KPI/cards/detail 데이터가 실제 backend 라이브 데이터로 wired. 후속 quick patch로 province dim + branch_id schema fix까지 정리됨.

## Threat Flags

없음. 모든 신규 endpoint는 기존 `@FunctionGuard('reporte-ventas', 'read')` / `@FunctionGuard('reporte-items', 'read')`로 보호 — 새로운 trust boundary 추가 없음.

## Deviations from Plan (소급 식별)

원래 plan(12-03-PLAN.md)에서 언급된 내용 대비 실제 구현 차이:
- **VentaDetailDrawer 컴포넌트 재사용** (plan 언급) → 실제로는 `SalesCockpitDetail` 패널 채택. 12-02 Vendedor도 drawer 대신 detail panel 사용해서 일관성 우선.
- **Province dimension** — plan에 없었으나 quick-260420-qet에서 사용자 요청으로 추가. dim allowlist에 'province' 포함됨.
- **Sales `unit` 파라미터** — plan에 없었으나 ventas 페이지네이션의 시간 그룹핑 요구로 추가 (vcode/day/month/year).
- **Sales `vendors` endpoint** — plan에 없었으나 Sales 화면에서 vendor 사이드 요약 표시 위해 추가.
