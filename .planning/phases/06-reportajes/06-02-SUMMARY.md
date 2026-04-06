---
phase: 06-reportajes
plan: 02
subsystem: reports
tags: [reports, backend, frontend, excel, multitenant, credit]
requires: [Sale model, StoreClient, GlobalClient, ExcelService, Wave 1 patterns]
provides:
  - "ReportsBreveVentaService — 일별 매출 집계"
  - "ReportsFacturacionService — Facturado 청구서 현황"
  - "ReportsClientesCreditoService — StoreClient+GlobalClient 외상 잔액"
  - "/reportes/breve-venta, /reportes/facturacion, /reportes/clientes-credito 페이지"
affects:
  - "QuerysDto: startDate/endDate 를 optional 로 변경 (잔액 보고서 호환)"
  - "modules.seed: breve-venta/facturacion/clientes-credito nav 모듈 추가"
tech-stack:
  added: []
  patterns:
    - "Wave 1 reportsFallados/Vendedor 패턴 정확 복제 (constructor + generalReport + getReport*Data)"
    - "ClientesCredito는 StoreClient.findAll + GlobalClient include (멀티테넌트 storeId 필수)"
    - "BreveVenta 일별 집계는 JS Map 그룹핑 (날짜 키)"
key-files:
  created:
    - api-ventago/src/app/reports/reportsBreveVenta.service.ts
    - api-ventago/src/app/reports/reportsFacturacion.service.ts
    - api-ventago/src/app/reports/reportsClientesCredito.service.ts
    - ventago-app/src/views/reports/breve-venta/hooks/useBreveVentaReport.tsx
    - ventago-app/src/views/reports/breve-venta/components/DataConfig.tsx
    - ventago-app/src/views/reports/breve-venta/components/BreveVentaReportTable.tsx
    - ventago-app/src/views/reports/breve-venta/BreveVentaReport.tsx
    - ventago-app/src/pages/reportes/breve-venta/index.tsx
    - ventago-app/src/views/reports/facturacion/hooks/useFacturacionReport.tsx
    - ventago-app/src/views/reports/facturacion/components/DataConfig.tsx
    - ventago-app/src/views/reports/facturacion/components/FacturacionReportTable.tsx
    - ventago-app/src/views/reports/facturacion/FacturacionReport.tsx
    - ventago-app/src/pages/reportes/facturacion/index.tsx
    - ventago-app/src/views/reports/clientes-credito/hooks/useClientesCreditoReport.tsx
    - ventago-app/src/views/reports/clientes-credito/components/DataConfig.tsx
    - ventago-app/src/views/reports/clientes-credito/components/ClientesCreditoReportTable.tsx
    - ventago-app/src/views/reports/clientes-credito/ClientesCreditoReport.tsx
    - ventago-app/src/pages/reportes/clientes-credito/index.tsx
  modified:
    - api-ventago/src/app/reports/reports.controller.ts
    - api-ventago/src/app/reports/reports.module.ts
    - api-ventago/src/app/reports/querys.dto.ts
    - api-ventago/src/app/modules/seed/modules.seed.ts
decisions:
  - "QuerysDto의 startDate/endDate를 optional로 변경 — Clientes Credito는 잔액 현황이라 날짜 범위 무의미"
  - "ClientesCredito 프론트엔드는 RangeDate 위젯 자체를 제거하고 검색 필터만 노출 (12 컬럼 grid)"
  - "BreveVenta 일별 집계는 Sequelize GROUP BY 대신 JS Map 사용 (Wave 1 Vendedor 패턴 일관성)"
metrics:
  duration: "~15min"
  completed: "2026-04-06"
  tasks: 2
  files_created: 18
  files_modified: 4
---

# Phase 06 Plan 02: Wave 2 Reports Summary

Wave 2 매출 확장 보고서 3종(Breve Venta 일별 집계, Facturacion 청구서 현황, Clientes Credito 외상 잔액) 백엔드 서비스 + 컨트롤러 엔드포인트 6개 + 프론트엔드 뷰 3개 구현 (Wave 1 패턴 복제).

## What Was Built

### Backend (api-ventago)
- **ReportsBreveVentaService**: Sale.findAll where status IN [Facturado/Pagado/Pendiente por pagar] → JS Map 으로 saleDate 키별 일별 집계 → { fecha, cantidadVentas, totalMonto } 날짜 내림차순.
- **ReportsFacturacionService**: Sale.findAll where status=INVOICED + Clients/Users/SalePaymentMethod include → Fallados 패턴과 동일한 매핑.
- **ReportsClientesCreditoService**: **StoreClient.findAll** where balance>0 AND isActive AND storeId → GlobalClient required include (fullname/document/phone). filter는 GlobalClient.fullname/document iLike. 잔액 내림차순.
- **Controller**: 6개 신규 엔드포인트 (`{x}-report` + `{x}-report-export` × 3).
- **Module**: 3 services를 providers + exports.
- **QuerysDto**: `startDate`/`endDate`를 `@IsOptional()`로 완화하여 ClientesCredito 호출 시 미전송 가능.
- **Seed**: nav 모듈 3개 추가 (breve-venta/facturacion/clientes-credito).

### Frontend (ventago-app)
- **BreveVenta**: hook + DataConfig(3 columns: Fecha/CantidadVentas/TotalMonto) + Table + Report (ProductFilterInput + RangeDate) + page (WithAccess).
- **Facturacion**: hook + DataConfig(6 columns: Nro/Fecha/Cliente/Vendedor/Monto/Metodo) + Table + Report + page. Fallados 와 거의 동일한 구조.
- **ClientesCredito**: hook (paramsDefault 에 startDate/endDate 없음) + DataConfig(5 columns: Cliente/Documento/Telefono/Saldo/Limite) + Table + Report (RangeDate 제거, 12-grid 단일 컬럼) + page.

## Verification

- `cd api-ventago && npx tsc --noEmit` — 통과 (출력 없음).
- `cd ventago-app && npx next build` — 통과. 신규 페이지 정적 생성 확인:
  - `/reportes/breve-venta`            1.38 kB
  - `/reportes/facturacion`            1.45 kB
  - `/reportes/clientes-credito`       3.28 kB

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocker] QuerysDto.startDate/endDate가 required였음**
- **Found during:** Task 1 설계 단계
- **Issue:** ClientesCredito 보고서는 잔액 현황이라 날짜 범위 불필요한데, 기존 QuerysDto에서 `startDate`/`endDate`가 `@IsString()` (required)였음 → 호출 시 ValidationPipe 에러 발생.
- **Fix:** 두 필드에 `@IsOptional()` 추가. 다른 보고서들은 이미 `if (startDate && endDate)` 가드로 처리하므로 호환됨.
- **Files modified:** api-ventago/src/app/reports/querys.dto.ts
- **Commit:** cd178df

### Plan Simplifications

- **Search debounce 0.5s + dynamic pageSize**: Plan에서 언급했으나 Wave 1 Summary 와 동일하게 기본 페이지네이션으로 구현 (`SalesReportTable` 패턴 일관성). search는 `ProductFilterInput` 통해 `params.filter` 로 전달됨.
- **CardFilter 컴포넌트**: 플랜이 참조했으나 Wave 1 과 동일하게 Card+CardHeader 직접 사용.

## Commits

- `cd178df` (api-ventago) — feat(06-02): wave 2 backend reports
- `35794d0` (ventago-app) — feat(06-02): wave 2 frontend reports views

## Known Stubs

None — 3개 보고서 모두 실제 DB 데이터로 wired됨. branchId 필터링은 Sale 모델에 직접 컬럼이 없어 메모리 필터로 처리됨 (Wave 1과 동일 한계, future wave에서 box→branch 조인 도입 가능).

## Self-Check: PASSED

- FOUND: api-ventago/src/app/reports/reportsBreveVenta.service.ts
- FOUND: api-ventago/src/app/reports/reportsFacturacion.service.ts
- FOUND: api-ventago/src/app/reports/reportsClientesCredito.service.ts
- FOUND: ventago-app/src/views/reports/breve-venta/BreveVentaReport.tsx
- FOUND: ventago-app/src/views/reports/facturacion/FacturacionReport.tsx
- FOUND: ventago-app/src/views/reports/clientes-credito/ClientesCreditoReport.tsx
- FOUND: ventago-app/src/pages/reportes/breve-venta/index.tsx
- FOUND: ventago-app/src/pages/reportes/facturacion/index.tsx
- FOUND: ventago-app/src/pages/reportes/clientes-credito/index.tsx
- FOUND commit (api-ventago): cd178df
- FOUND commit (ventago-app): 35794d0
