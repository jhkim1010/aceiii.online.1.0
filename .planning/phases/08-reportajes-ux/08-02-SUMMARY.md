---
phase: 08-reportajes-ux
plan: 02
subsystem: reports-views
tags: [refactor, body-extraction, phase-8, wave-2]
requires:
  - 08-01 controlled-mode hooks (xxxDefaultParams exports)
provides:
  - 15 XxxReportBody.tsx embeddable components (params/setParams props)
  - 15 XxxReport.tsx thin wrappers (useState + <Body />)
  - Variant A wrappers own setThisMonth/setToday/clear helpers
affects:
  - ventago-app/src/views/reports/*/
tech-stack:
  added: []
  patterns: ["body-wrapper split", "controlled props injection", "optional helper props"]
key-files:
  created:
    - ventago-app/src/views/reports/vendedor/VendedorReportBody.tsx
    - ventago-app/src/views/reports/gastos/GastoReportBody.tsx
    - ventago-app/src/views/reports/breve-venta/BreveVentaReportBody.tsx
    - ventago-app/src/views/reports/fallados/FalladosReportBody.tsx
    - ventago-app/src/views/reports/corregido/CorregidoReportBody.tsx
    - ventago-app/src/views/reports/facturacion/FacturacionReportBody.tsx
    - ventago-app/src/views/reports/ingreso/IngresoReportBody.tsx
    - ventago-app/src/views/reports/movidos/MovidosReportBody.tsx
    - ventago-app/src/views/reports/reservado/ReservadoReportBody.tsx
    - ventago-app/src/views/reports/cheque-estado/ChequeEstadoReportBody.tsx
    - ventago-app/src/views/reports/alertas/AlertasReportBody.tsx
    - ventago-app/src/views/reports/clientes-credito/ClientesCreditoReportBody.tsx
    - ventago-app/src/views/reports/sales/SalesReportBody.tsx
    - ventago-app/src/views/reports/products/ProductReportBody.tsx
    - ventago-app/src/views/reports/stocks/StockReportBody.tsx
  modified:
    - ventago-app/src/views/reports/vendedor/VendedorReport.tsx
    - ventago-app/src/views/reports/gastos/GastoReport.tsx
    - ventago-app/src/views/reports/breve-venta/BreveVentaReport.tsx
    - ventago-app/src/views/reports/fallados/FalladosReport.tsx
    - ventago-app/src/views/reports/corregido/CorregidoReport.tsx
    - ventago-app/src/views/reports/facturacion/FacturacionReport.tsx
    - ventago-app/src/views/reports/ingreso/IngresoReport.tsx
    - ventago-app/src/views/reports/movidos/MovidosReport.tsx
    - ventago-app/src/views/reports/reservado/ReservadoReport.tsx
    - ventago-app/src/views/reports/cheque-estado/ChequeEstadoReport.tsx
    - ventago-app/src/views/reports/alertas/AlertasReport.tsx
    - ventago-app/src/views/reports/clientes-credito/ClientesCreditoReport.tsx
    - ventago-app/src/views/reports/sales/SalesReport.tsx
    - ventago-app/src/views/reports/products/ProductReport.tsx
    - ventago-app/src/views/reports/stocks/StockReport.tsx
decisions:
  - "Variant A helper props(setThisMonth/setToday/clear)는 optional — 셸은 자체 Topbar로 대체 가능"
  - "Drilldown(useEffect)이 getSaleItemsSummary/getProductSalesSummary 호출 시 현재 params 를 override 로 명시 전달 → 외부 params 모드에서 회귀 0"
  - "pages/reportes/*, ReportesHub.tsx 미수정 (CONTEXT.md locked 원칙 준수)"
metrics:
  duration: "~20min"
  completed: "2026-04-06"
---

# Phase 8 Plan 02: Body/Wrapper Split for 15 Report Views — Summary

**One-liner:** Phase 6 의 15개 report view 컴포넌트를 `XxxReportBody` (controlled, 셸 embeddable) + `XxxReport` (thin wrapper, useState 소유) 로 분리. Variant A 3개는 wrapper 가 `setThisMonth/setToday/clear` helpers 를 소유하며 Body 에 optional props 로 전달.

## What Shipped

15개의 `XxxReportBody.tsx` 가 신규 추가되었고, 15개의 `XxxReport.tsx` 가 각각 10~35줄의 thin wrapper 로 축소되었다. 각 Body는 `{ params, setParams }` (Variant A는 + 3 optional helpers) props 를 받아 내부에서 `useXxxReport(params)` 를 호출한다. default export 이름은 유지되어 `pages/reportes/*` import 경로는 변경되지 않았다.

## Body Registry (Wave 3 lazy import 참고)

| # | Slug | Body 경로 | Variant | Props |
|---|------|----------|---------|-------|
| 1 | vendedor | `views/reports/vendedor/VendedorReportBody` | B | params, setParams |
| 2 | gastos | `views/reports/gastos/GastoReportBody` | B | params, setParams |
| 3 | breve-venta | `views/reports/breve-venta/BreveVentaReportBody` | B | params, setParams |
| 4 | fallados | `views/reports/fallados/FalladosReportBody` | B | params, setParams |
| 5 | corregido | `views/reports/corregido/CorregidoReportBody` | B | params, setParams |
| 6 | facturacion | `views/reports/facturacion/FacturacionReportBody` | B | params, setParams |
| 7 | ingreso | `views/reports/ingreso/IngresoReportBody` | B | params, setParams |
| 8 | movidos | `views/reports/movidos/MovidosReportBody` | B | params, setParams |
| 9 | reservado | `views/reports/reservado/ReservadoReportBody` | B | params, setParams |
| 10 | cheque-estado | `views/reports/cheque-estado/ChequeEstadoReportBody` | B | params, setParams |
| 11 | alertas | `views/reports/alertas/AlertasReportBody` | C | params, setParams (no date range) |
| 12 | clientes-credito | `views/reports/clientes-credito/ClientesCreditoReportBody` | C | params, setParams (no date range) |
| 13 | sales/ventas | `views/reports/sales/SalesReportBody` | A | params, setParams, setThisMonth?, setToday?, clear? |
| 14 | products/items | `views/reports/products/ProductReportBody` | A | params, setParams, setThisMonth?, setToday?, clear? |
| 15 | stocks | `views/reports/stocks/StockReportBody` | A | params, setParams, setThisMonth?, setToday?, clear? |

## Tasks Executed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Extract Body from 12 Variant B/C reports | `e8d33d5` | 24 files (12 new + 12 modified) |
| 2 | Extract Body from 3 Variant A reports with helper props | `b104298` | 6 files (3 new + 3 modified) |

## Verification

- `npx tsc --noEmit` — 에러 0 (Task 1, Task 2 각각 확인)
- `npm run build` — exit 0, 15개 `/reportes/*` 라우트 모두 정적 생성
- `ls src/views/reports/*/[A-Z]*Body.tsx | wc -l` → `15`
- `git diff` 확인: `src/pages/reportes/` 및 `src/views/reports/ReportesHub.tsx` 변경 없음

## Deviations from Plan

None — plan executed exactly as written.

## Wave 3 TODO

1. `src/views/reports-v2/hookRegistry.ts` — slug → `React.lazy(() => import('...Body'))` 매핑 15개 항목
2. `ReportsPreviewPanel` 이 slug 에 해당하는 Body 를 dynamic import 해 현재 params 주입
3. Variant A 셸 Topbar 에 "Este mes / Hoy / Limpiar" 액션 별도 구현 (Body helper props 미전달)

## Self-Check: PASSED

- 15 Body files verified present
- 15 wrappers verified modified
- Commits verified: `e8d33d5`, `b104298`
- Build green, all /reportes/* routes generated
- pages/reportes/* and ReportesHub.tsx untouched
