---
phase: 06-reportajes
plan: 03
subsystem: reports
tags: [reports, backend, frontend, excel, multitenant, stocks, suspended-sales]
requires: [Stocks model, ProductBranch, SuspendedSale, ExcelService, Wave 1/2 patterns]
provides:
  - "ReportsIngresoService — 재고 입고 조회 (Stocks > 0)"
  - "ReportsMovidosService — 재고 이동 조회 (Stocks 전체, Ingreso/Egreso 구분)"
  - "ReportsReservadoService — 보류 판매 조회 (SuspendedSale)"
  - "/reportes/ingreso, /reportes/movidos, /reportes/reservado 페이지"
affects:
  - "modules.seed: ingreso/movidos/reservado nav 모듈 추가"
tech-stack:
  added: []
  patterns:
    - "Wave 1/2 reports 패턴 정확 복제 (constructor + generalReport + getReport*Data)"
    - "Stocks → ProductBranch → Product/Branch include 체인 (멀티테넌트 storeId via Product.storeId)"
    - "Movidos: stock 부호로 Ingreso/Egreso 타입 매핑, 프론트 Chip 시각화"
key-files:
  created:
    - api-ventago/src/app/reports/reportsIngreso.service.ts
    - api-ventago/src/app/reports/reportsMovidos.service.ts
    - api-ventago/src/app/reports/reportsReservado.service.ts
    - ventago-app/src/views/reports/ingreso/hooks/useIngresoReport.tsx
    - ventago-app/src/views/reports/ingreso/components/DataConfig.tsx
    - ventago-app/src/views/reports/ingreso/components/IngresoReportTable.tsx
    - ventago-app/src/views/reports/ingreso/IngresoReport.tsx
    - ventago-app/src/pages/reportes/ingreso/index.tsx
    - ventago-app/src/views/reports/movidos/hooks/useMovidosReport.tsx
    - ventago-app/src/views/reports/movidos/components/DataConfig.tsx
    - ventago-app/src/views/reports/movidos/components/MovidosReportTable.tsx
    - ventago-app/src/views/reports/movidos/MovidosReport.tsx
    - ventago-app/src/pages/reportes/movidos/index.tsx
    - ventago-app/src/views/reports/reservado/hooks/useReservadoReport.tsx
    - ventago-app/src/views/reports/reservado/components/DataConfig.tsx
    - ventago-app/src/views/reports/reservado/components/ReservadoReportTable.tsx
    - ventago-app/src/views/reports/reservado/ReservadoReport.tsx
    - ventago-app/src/pages/reportes/reservado/index.tsx
  modified:
    - api-ventago/src/app/reports/reports.controller.ts
    - api-ventago/src/app/reports/reports.module.ts
    - api-ventago/src/app/modules/seed/modules.seed.ts
decisions:
  - "BoxOperation(type='ingreso') 현금 입금은 제외 — Caja 모듈에서 이미 관리되므로 Ingreso 보고서는 재고 입고(Stocks)만 표시 (단순화)"
  - "Movidos 보고서에서 stock 부호로 Ingreso/Egreso 타입 분류, 프론트는 success/error Chip 으로 시각 구분"
  - "ProductBranch include 체인 강제 사용 (RESEARCH Pitfall 5 회피) — Stocks 직접 조회는 상품 정보 손실"
  - "MUI Chip variant='filled' 사용 — Chip 컴포넌트는 'tonal' variant 미지원 (Button과 다름)"
metrics:
  duration: "~10min"
  completed: "2026-04-06"
  tasks: 2
  files_created: 18
  files_modified: 3
---

# Phase 06 Plan 03: Wave 3 Reports Summary

Wave 3 재고/보류 보고서 3종(Ingreso 재고 입고, Movidos 재고 이동, Reservado 보류 판매) 백엔드 서비스 + 컨트롤러 엔드포인트 6개 + 프론트엔드 뷰 3개 구현 (Wave 1/2 패턴 복제).

## What Was Built

### Backend (api-ventago)
- **ReportsIngresoService**: `Stocks.findAll where stock > 0` → ProductBranch (required) → Product (required, storeId 필터) + Branch include. 결과: { fecha, sku, producto, sucursal, cantidad }, 날짜 내림차순.
- **ReportsMovidosService**: `Stocks.findAll` (양수+음수 모두) → 동일 include 체인. stock 부호로 'Ingreso'/'Egreso' 타입 분류, cantidad는 절대값.
- **ReportsReservadoService**: `SuspendedSale.findAll` (underscored: true 환경) → Clients(as: client) + Users(as: user) include. storeId/saleDate/filter 지원. 결과: { id, fecha, cliente, vendedor, monto }.
- **Controller**: 6개 신규 엔드포인트 (`{x}-report` + `{x}-report-export` × 3).
- **Module**: 3 services를 providers + exports.
- **Seed**: nav 모듈 3개 추가 (ingreso/movidos/reservado).

### Frontend (ventago-app)
- **Ingreso**: hook + DataConfig(5 cols: Fecha/SKU/Producto/Sucursal/Cantidad) + Table + Report + page.
- **Movidos**: hook + DataConfig(6 cols, Tipo 컬럼은 MUI Chip으로 success/error 시각화) + Table + Report + page.
- **Reservado**: hook + DataConfig(5 cols: ID/Fecha/Cliente/Vendedor/Monto Total[priceColumn 통화 포맷]) + Table + Report + page.
- 모든 페이지: ProductFilterInput + RangeDate 필터 위젯, Excel 다운로드 버튼, WithAccess 가드.

## Verification

- `cd api-ventago && npx tsc --noEmit` — 통과 (출력 없음).
- `cd ventago-app && npx next build` — 통과. 신규 페이지 정적 생성 확인:
  - `/reportes/ingreso`     1.43 kB
  - `/reportes/movidos`     1.52 kB
  - `/reportes/reservado`   1.43 kB

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] MUI Chip variant='tonal' 미지원**
- **Found during:** Task 2 build verification
- **Issue:** 플랜은 Movidos Tipo 컬럼에 `<Chip variant="tonal">`을 명시했으나, MUI Chip 컴포넌트는 `'outlined' | 'filled'` 만 허용 → TypeScript 컴파일 에러.
- **Fix:** `variant="filled"` 로 변경. color='success'/'error' 가 색상 구분을 충분히 제공.
- **Files modified:** ventago-app/src/views/reports/movidos/components/DataConfig.tsx
- **Commit:** fd45bac (수정 포함 단일 커밋)

### Plan Simplifications

- **BoxOperation(type='ingreso') 입금 데이터**: 플랜 RESEARCH에서 언급되었으나, Caja 모듈에서 이미 관리되어 중복 — Ingreso 보고서는 재고 입고(Stocks > 0)만 표시. 플랜의 ※ 표기와 일치.
- **Search debounce / dynamic pageSize**: Wave 1/2와 동일하게 기본 페이지네이션 사용 (SalesReportTable 패턴 일관성).

## Commits

- `01a9794` (api-ventago) — feat(06-03): wave 3 backend reports
- `fd45bac` (ventago-app) — feat(06-03): wave 3 frontend report views

## Known Stubs

None — 3개 보고서 모두 실제 DB 데이터로 wired됨. branchId 필터링은 Stocks → ProductBranch.branchId 경유 메모리 필터로 처리.

## Self-Check: PASSED

- FOUND: api-ventago/src/app/reports/reportsIngreso.service.ts
- FOUND: api-ventago/src/app/reports/reportsMovidos.service.ts
- FOUND: api-ventago/src/app/reports/reportsReservado.service.ts
- FOUND: ventago-app/src/views/reports/ingreso/IngresoReport.tsx
- FOUND: ventago-app/src/views/reports/movidos/MovidosReport.tsx
- FOUND: ventago-app/src/views/reports/reservado/ReservadoReport.tsx
- FOUND: ventago-app/src/pages/reportes/ingreso/index.tsx
- FOUND: ventago-app/src/pages/reportes/movidos/index.tsx
- FOUND: ventago-app/src/pages/reportes/reservado/index.tsx
- FOUND commit (api-ventago): 01a9794
- FOUND commit (ventago-app): fd45bac
