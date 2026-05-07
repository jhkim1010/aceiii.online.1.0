---
phase: 12-reportajes-cockpit
plan: "02"
subsystem: reports-vendedor-cockpit
tags: [reports, cockpit, vendedor, frontend, backend, reference-pattern]
dependency_graph:
  requires: [12-01]
  provides: [vendedor-cockpit, vendedor-cockpit-trend, vendedor-cockpit-mix, vendedor-cockpit-ventas, vendedor-cockpit-detail, cockpit-reference-pattern]
  affects: [reports-v2/registry, reports-controller, reports-module, shared/KpiStrip, shared/Sparkline]
tech_stack:
  added: []
  patterns:
    - raw-sql-3-or-fewer-queries-per-endpoint
    - lazy-loaded-detail-tabs (mix/trend/ventas only fetch on tab click)
    - kpi-strip-card-grid-detail-pattern (reference for all subsequent cockpit migrations)
    - shared-cockpit-helpers (fmtGs/fmtInt/fmtPct/deltaColor/medalFor/Sparkline/KpiStrip/TopItemCell)
    - sequelize-raw-sql-with-cte (WITH bounds AS ... curr/prev period comparison)
key_files:
  created:
    - api-ventago/src/app/reports/reportsVendedorCockpit.service.ts
    - ventago-app/src/views/reports/vendedor/VendedorCockpitBody.tsx
    - ventago-app/src/views/reports/vendedor/VendedorCockpitDetail.tsx
    - ventago-app/src/views/reports/vendedor/hooks/useVendedorCockpit.tsx
    - ventago-app/src/views/reports/vendedor/hooks/useVendedorCockpitDetail.tsx
  modified:
    - api-ventago/src/app/reports/reports.controller.ts (4 new vendedor-cockpit endpoints)
    - api-ventago/src/app/reports/reports.module.ts (registered ReportsVendedorCockpitService)
    - ventago-app/src/views/reports-v2/registry.ts (lazy import → VendedorCockpitBody)
decisions:
  - "Phase 12 reference 패턴 정립 — Vendedor가 모든 후속 cockpit 마이그레이션의 표준 모델"
  - "단일 메인 엔드포인트(/reports/vendedor-cockpit) 1회 호출로 KPI summary + 카드 리스트 + 일별 스파크 모두 반환"
  - "상세 탭(trend/mix/ventas)은 사용자가 카드 클릭 시에만 lazy fetch — pool 사용 최소화"
  - "raw SQL 사용 (Sequelize ORM 미사용) + CTE 패턴(WITH bounds AS ...)으로 현재/직전 기간 비교 1쿼리 처리"
  - "유효 판매 상태 필터 (Facturado/Pagado/Pendiente por pagar) — 기존 reportsVendedor.service와 일관성 유지"
  - "Mix dimension은 product/category/color/size/season 5종으로 제한 (SalesDimensionsService와 통합)"
  - "Anulación 처리: 유효 집계는 status IN (...), 반품 건수는 status = 'Anulación' 별도 카운트"
metrics:
  completed_date: "2026-04-09 ~ 2026-04-11 (코드), 2026-05-07 (소급 SUMMARY)"
  files_changed: 8
  service_methods: 4 (getCockpit, getTrend, getMix, getVentas)
  endpoints: 4
---

# Phase 12 Plan 02: Vendedor Cockpit Migration Summary (소급 작성)

**One-liner:** Vendedor 보고서를 reference cockpit 패턴(KPI strip + 카드 그리드 + lazy 상세 탭)으로 완전 재구현 — Phase 12의 모든 후속 마이그레이션이 따르는 표준 모델

> **소급 작성 노트 (2026-05-07):** 코드는 2026-04-09~04-11 사이에 완료되었고 12-04~12-08 SUMMARY에서 reference pattern으로 명시적으로 인용되었으나 SUMMARY.md 파일이 누락되어 있었음. 본 문서는 git 커밋 + 실제 소스 파일을 기반으로 retroactively 작성됨.

---

## Backend Architecture

### `reportsVendedorCockpit.service.ts` (api-ventago)

원자적 raw SQL + CTE 기반 cockpit 서비스. 메인 엔드포인트는 3 query 이내, 상세 탭은 사용자 인터랙션 시에만 lazy 호출.

| Method | Purpose | Pool 사용 |
|--------|---------|-----------|
| `getCockpit(filters)` | KPI summary (curr+prev) + vendedores 카드 리스트 + 일별 스파크 | 1 connection (raw SQL CTE) |
| `getTrend(sellerScopedFilters)` | 선택된 seller의 일별 추이 — 상세 탭 Tendencia 클릭 시 | 1 connection |
| `getMix(filters, dimension)` | product/category/color/size/season 차원의 매출 mix | 1 connection |
| `getVentas(paginatedFilters)` | 선택된 seller의 venta 페이지네이션 리스트 | 1 connection |

**유효 상태 상수:**
```ts
const VALID_STATUSES = ['Facturado', 'Pagado', 'Pendiente por pagar']
```

**필터 시그니처:**
```ts
type CockpitFilters = {
  storeId?: number | null
  branchId?: number | null
  startDate: string  // yyyy-MM-dd
  endDate: string    // yyyy-MM-dd
  filter?: string    // 판매원명 검색
}
```

### Endpoints (`reports.controller.ts`)

| Endpoint | Permission Slug | Service method |
|----------|----------------|----------------|
| GET /reports/vendedor-cockpit | reporte-vendedor | getCockpit |
| GET /reports/vendedor-cockpit/trend | reporte-vendedor | getTrend |
| GET /reports/vendedor-cockpit/mix | reporte-vendedor | getMix |
| GET /reports/vendedor-cockpit/ventas | reporte-vendedor | getVentas |

---

## Frontend Architecture

### Layout (`VendedorCockpitBody.tsx`)

- **KpiStrip** (4 KPI cards + Top Vendedor 위젯): Total Ventas / Transacciones / Ticket Promedio / Descuento Prom.
- **Vendedor Card Grid** (auto-fill, minmax 210px): 각 카드는 medal(🥇🥈🥉) + sparkline + tx/ticket/desc/dev chip
- **Detail Panel** (선택 시 마운트): VendedorCockpitDetail — Tendencia / Mix / Ventas 탭

### Card Interactivity
- 카드 클릭 → `selectedSellerId` 상태 토글 → 같은 카드 재클릭 시 deselect
- 선택된 카드: cyan border (#5DF2FF) + cyan glow + translateY hover

### Hook (`useVendedorCockpit.tsx`)
- 메인 cockpit 데이터 fetcher (KPI + cards + sparkline)
- params 변경 시에만 refetch — apiConnector.get 기반

### Detail Hook (`useVendedorCockpitDetail.tsx`)
- 탭별 lazy fetcher — sellerId + 활성 탭 변경 시에만 fetch

---

## Shared Components 도입 (`reports/shared/`)

12-02에서 cockpit 패턴의 공용 헬퍼/컴포넌트가 도입됨 — 후속 마이그레이션이 그대로 재사용:

| Helper/Component | 용도 |
|-----------------|------|
| `fmtGs(amount)` | 과라니 ₲ 포맷 (천 단위 구분) |
| `fmtInt(n)` | 정수 포맷 |
| `fmtPct(n)` | 퍼센트 포맷 + ↑↓ 방향 |
| `deltaColor(pct)` | delta 부호 → success/error/text.secondary 매핑 |
| `medalFor(rank)` | rank 0/1/2 → 🥇🥈🥉 |
| `Sparkline` | 7~30 포인트 미니 SVG 라인 차트 |
| `KpiStrip` | 4 KPI 카드 + topItem slot |
| `TopItemCell` | 1위 위젯 (label/title/subtitle) |

---

## SQL 패턴 — CTE bounds + curr/prev 비교

```sql
WITH bounds AS (
  SELECT :storeId::int AS p_store_id,
         :branchId::int AS p_branch_id,
         :startDate::date AS p_start,
         :endDate::date AS p_end,
         (:endDate::date - :startDate::date + 1) AS len
),
curr AS (
  SELECT
    COALESCE(SUM(s.total_amount), 0)::bigint AS total_amount,
    COUNT(*)::int                            AS tx,
    CASE WHEN COUNT(*) > 0 THEN ROUND(AVG(s.total_amount))::bigint ELSE 0 END AS avg_ticket,
    CASE WHEN SUM(s.subtotal) > 0
         THEN ROUND((SUM(s.discount_amount)::numeric / NULLIF(SUM(s.subtotal),0)::numeric) * 100, 2)
         ELSE 0 END                          AS disc_pct
  FROM sales s
  CROSS JOIN bounds b
  LEFT JOIN "Sellers" u ON u.id = s.seller_id
  WHERE (b.p_store_id IS NULL OR s.store_id = b.p_store_id)
    AND s.status IN (:validStatuses)
    AND s.sale_date >= b.p_start
    AND s.sale_date <= b.p_end
)
-- (prev CTE 동일 패턴 + delta 계산)
SELECT * FROM curr, prev;
```

이 패턴이 후속 모든 cockpit 서비스(Sales/Products/Finanzas/Inventario/Clientes)의 SQL 템플릿이 됨.

---

## Pool 절약 효과

- **이전 (legacy `/reports/vendedor`)**: 페이지 로드 시 KPI 1회 + ranking 1회 + 각 vendedor detail N회 = (N+2) connections
- **이후 (`/reports/vendedor-cockpit`)**: 1 endpoint = 1 connection. 상세 탭은 사용자 클릭 시에만 추가 1 connection.
- 매장당 평균 5명 vendedor 가정 시: **7 → 1 connection** (페이지 로드)

---

## Registry Changes (`reports-v2/registry.ts`)

```ts
// Before:
const VendedorReportBody = lazy(() => import('src/views/reports/vendedor/VendedorReportBody'))

// After (12-02):
const VendedorReportBody = lazy(() => import('src/views/reports/vendedor/VendedorCockpitBody'))
```

Legacy `VendedorReportBody.tsx` 파일은 보존(미삭제) — 비교 검증 + rollback 가능.

---

## Reference Pattern Established

이 plan에서 정립된 패턴은 12-04 SUMMARY에서 명시적으로 인용:
> "Each cockpit body follows the SalesCockpit pattern... Migrated 3 Finanzas reports to the Cockpit pattern established in **12-01/02/03**"

후속 plan들이 직접 재사용한 요소:
- `KpiStrip` / `Sparkline` / `TopItemCell` 컴포넌트
- raw SQL CTE bounds + curr/prev 비교 SQL 패턴
- lazy detail-tab 패턴
- 단일 cockpit endpoint = 1 connection 원칙
- `cockpitLayout: { hasKpiStrip, hasDetail, hasDrawer }` registry 메타

---

## 관련 커밋

| Commit | 내용 |
|--------|------|
| `459d461` ventago-app | feat: POS QMode 자동추가 + CodigosMadres 모드 + **Vendedor Cockpit** + 보고서 개선 |
| `67a11f1` api-ventago | feat: sellers linked_user_id + **vendedor cockpit** + sales province/dimensions |
| `959fbfa` ventago-app | feat: reports granular permissions + **shared cockpit components** |

---

## Self-Check: PASSED (소급 검증)

- [x] `VendedorCockpitBody.tsx` — EXISTS (Apr 11)
- [x] `VendedorCockpitDetail.tsx` — EXISTS (Apr 9)
- [x] `reportsVendedorCockpit.service.ts` — EXISTS (Apr 27 latest mtime, 4 methods 확인)
- [x] `useVendedorCockpit.tsx` / `useVendedorCockpitDetail.tsx` — EXISTS
- [x] `reports.controller.ts` — 4 vendedor-cockpit endpoints (line 185, 197, 209, 236) 확인
- [x] `registry.ts` — `VendedorReportBody = lazy(() => import('.../VendedorCockpitBody'))` (line 80) 확인
- [x] 12-04 SUMMARY가 본 plan을 reference pattern으로 명시
- [x] 12-08 SUMMARY의 `dependency_graph.requires`에 `12-02` 포함

## Known Stubs

없음. 모든 KPI/cards/detail 데이터가 실제 backend 라이브 데이터로 wired.

## Threat Flags

없음. 모든 신규 endpoint는 기존 `@FunctionGuard('reporte-vendedor')`로 보호 — 새로운 trust boundary 추가 없음.
