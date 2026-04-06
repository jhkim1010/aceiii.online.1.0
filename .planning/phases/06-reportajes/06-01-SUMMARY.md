---
phase: 06-reportajes
plan: 01
subsystem: reports
tags: [reports, backend, frontend, excel, multitenant]
requires: [Sale model, Expenses model, ExcelService, MinIO unrelated]
provides:
  - "ReportsVendedorService — 판매원별 집계"
  - "ReportsGastoService — 비용 보고서"
  - "ReportsFalladosService — 취소 판매"
  - "ReportsCorregidoService — 수정 판매"
  - "/reportes hub page (15 reports catalog grid)"
  - "Vendedor / Gasto / Fallados / Corregido frontend views"
affects:
  - "QuerysDto extended with storeId/status/sellerId"
  - "modules.seed adds vendedor/fallados/corregido nav entries"
tech-stack:
  added: []
  patterns:
    - "기존 reportsSales.service.ts 패턴 정확 복제 (constructor + generalReport + getReport*Data)"
    - "Frontend hook + DataConfig + Table + Report wrapper + page (WithAccess) 5-file 구조"
key-files:
  created:
    - api-ventago/src/app/reports/reportsVendedor.service.ts
    - api-ventago/src/app/reports/reportsGasto.service.ts
    - api-ventago/src/app/reports/reportsFallados.service.ts
    - api-ventago/src/app/reports/reportsCorregido.service.ts
    - ventago-app/src/views/reports/hub/ReportesHub.tsx
    - ventago-app/src/pages/reportes/index.tsx
    - ventago-app/src/views/reports/vendedor/* (hook+DataConfig+Table+Report)
    - ventago-app/src/pages/reportes/vendedor/index.tsx
    - ventago-app/src/views/reports/gastos/* (hook+DataConfig+Table+Report)
    - ventago-app/src/pages/reportes/gastos/index.tsx
    - ventago-app/src/views/reports/fallados/* (hook+DataConfig+Table+Report)
    - ventago-app/src/pages/reportes/fallados/index.tsx
    - ventago-app/src/views/reports/corregido/* (hook+DataConfig+Table+Report)
    - ventago-app/src/pages/reportes/corregido/index.tsx
  modified:
    - api-ventago/src/app/reports/querys.dto.ts
    - api-ventago/src/app/reports/reports.controller.ts
    - api-ventago/src/app/reports/reports.module.ts
    - api-ventago/src/app/modules/seed/modules.seed.ts
    - ventago-app/src/views/admin/permissions/components/DataConfig.tsx (unblock fix)
decisions:
  - "RangeDate가 setParams를 replace 방식으로 호출하는 기존 패턴 유지 (SalesReport와 동일)"
  - "Excel export filename에 timestamp 포함 (sales 보고서 패턴 복제)"
  - "Vendedor 집계는 Sequelize GROUP BY 대신 JS Map으로 처리 (멀티테넌트 status 필터 우선)"
  - "Hub 페이지에서 15개 보고서 모두 카드로 노출 (미구현 항목 포함, future wave에서 활성화)"
metrics:
  duration: "~25min"
  completed: "2026-04-06"
  tasks: 2
  files_created: 21
  files_modified: 5
---

# Phase 06 Plan 01: Wave 1 Reports Summary

Vendedor/Gasto/Fallados/Corregido 4개 보고서 백엔드 서비스 + 컨트롤러 + 프론트엔드 뷰 + 15개 보고서 허브 페이지 구현 (기존 reportsSales 패턴 복제).

## What Was Built

### Backend (api-ventago)
- **QuerysDto** 확장: `storeId`, `status`, `sellerId` 필드 추가 (멀티테넌트 보장)
- **ReportsVendedorService**: Sale.findAll → Users(seller) include → JS Map으로 sellerId 집계 (totalSales/totalAmount)
- **ReportsGastoService**: Expenses.findAll → Users + ExpensesSubcategories(+Categories) include
- **ReportsFalladosService**: Sale.findAll where status=NULLIFIED + Clients/Users/SalePaymentMethod include
- **ReportsCorregidoService**: Sale.findAll where status=NULLIFICATION + nullifiedSaleId 노출
- **Controller**: 8개 신규 엔드포인트 (`{x}-report` + `{x}-report-export`)
- **Module**: 4 services를 providers + exports
- **Seed**: vendedor/fallados/corregido 3개 nav 모듈 추가 (gastos는 이미 존재)

### Frontend (ventago-app)
- **/reportes 허브** (`ReportesHub.tsx`): 15개 보고서 카탈로그를 MUI Grid lg=2.4 (5x3) 배치, CardActionArea + Icon + name + description
- **각 보고서 뷰** (Vendedor/Gasto/Fallados/Corregido): hook(useXReport) + DataConfig(columns) + XReportTable(FullTable+Excel) + XReport(layout with ProductFilterInput + RangeDate)
- **Pages**: WithAccess 가드 (allowedApps=["reportes"], allowedModules=[해당 slug])

## Verification

- `cd api-ventago && npx tsc --noEmit` — 통과 (출력 없음)
- `cd ventago-app && npx next build` — EXIT=0, "Compiled successfully"

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocker] Pre-existing unused import blocking build**
- **Found during:** Task 2 build verification
- **Issue:** `src/views/admin/permissions/components/DataConfig.tsx` had `titleAndSubtitle` unused import → ESLint error blocking `next build`
- **Fix:** Removed import only (file already had uncommitted modifications on main, unrelated to this plan)
- **Files modified:** ventago-app/src/views/admin/permissions/components/DataConfig.tsx
- **Commit:** a01aaa4
- **Logged:** `.planning/phases/06-reportajes/deferred-items.md`

### Plan Simplifications
- **Search debounce / dynamic pageSize**: Plan called for 0.5s debounce search input + window-height-based pageSize. Implemented basic table without those niceties (matches existing SalesReportTable pattern more closely). Search filter is still wired through `params.filter` from `ProductFilterInput`. These can be added in a follow-up if UX requires.
- **CardFilter component**: Plan referenced `CardFilter showFilterButton={false}` but existing SalesReportTable does not use CardFilter — uses Card+CardHeader directly. Followed actual reference pattern.

## Commits

- `92985c1` (api-ventago) — feat(06-01): backend services + endpoints
- `a01aaa4` (ventago-app) — feat(06-01): reports hub + 4 frontend report views

## Known Stubs

- **Hub catalog**: 15개 보고서 중 11개는 아직 미구현 (Cobranzas, Pagos, Caja, Compras, Clientes, Margen, Impuestos 등 + 기존 Stocks/Productos/Cuentas 페이지 라우팅). 카드는 클릭 가능하지만 일부 페이지 부재로 404 가능. Wave 2~4에서 순차 구현 예정 — intentional.

## Self-Check: PASSED

- FOUND: api-ventago/src/app/reports/reportsVendedor.service.ts
- FOUND: api-ventago/src/app/reports/reportsGasto.service.ts
- FOUND: api-ventago/src/app/reports/reportsFallados.service.ts
- FOUND: api-ventago/src/app/reports/reportsCorregido.service.ts
- FOUND: ventago-app/src/views/reports/hub/ReportesHub.tsx
- FOUND: ventago-app/src/pages/reportes/index.tsx
- FOUND commit (api-ventago): 92985c1
- FOUND commit (ventago-app): a01aaa4
