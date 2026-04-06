---
phase: 08-reportajes-ux
plan: 01
subsystem: reports-hooks
tags: [refactor, hooks, controlled-mode, phase-8]
requires:
  - Phase 6 report hooks (15 useXxxReport)
provides:
  - 15 controlled-mode hooks accepting optional externalParams
  - 15 xxxDefaultParams named exports
affects:
  - ventago-app/src/views/reports/*/hooks/
tech-stack:
  added: []
  patterns: ["controlled hook", "params-injection", "backward-compatible fallback"]
key-files:
  created: []
  modified:
    - ventago-app/src/views/reports/vendedor/hooks/useVendedorReport.tsx
    - ventago-app/src/views/reports/gastos/hooks/useGastoReport.tsx
    - ventago-app/src/views/reports/fallados/hooks/useFalladosReport.tsx
    - ventago-app/src/views/reports/corregido/hooks/useCorregidoReport.tsx
    - ventago-app/src/views/reports/breve-venta/hooks/useBreveVentaReport.tsx
    - ventago-app/src/views/reports/facturacion/hooks/useFacturacionReport.tsx
    - ventago-app/src/views/reports/ingreso/hooks/useIngresoReport.tsx
    - ventago-app/src/views/reports/movidos/hooks/useMovidosReport.tsx
    - ventago-app/src/views/reports/reservado/hooks/useReservadoReport.tsx
    - ventago-app/src/views/reports/cheque-estado/hooks/useChequeEstadoReport.tsx
    - ventago-app/src/views/reports/alertas/hooks/useAlertasReport.tsx
    - ventago-app/src/views/reports/clientes-credito/hooks/useClientesCreditoReport.tsx
    - ventago-app/src/views/reports/sales/hooks/useSalesReport.tsx
    - ventago-app/src/views/reports/products/hooks/useProductsReport.tsx
    - ventago-app/src/views/reports/stocks/hooks/useStockReport.tsx
decisions:
  - "과도기 backward-compatible 패턴: externalParams 미제공 시 내부 useState fallback 유지 → Wave 1 단독 빌드도 그린"
  - "Variant A helpers(setThisMonth/setToday/clear)는 fallback 모드에서만 동작. 외부 모드에서는 호출자가 재구현 (Wave 2)"
  - "Drilldown fetchers가 overrideParams 2번째 인자 수신 — 셸에서 외부 params 주입 가능"
metrics:
  duration: "~15min"
  completed: "2026-04-06"
---

# Phase 8 Plan 01: Controlled-mode Report Hooks Refactor — Summary

**One-liner:** Phase 6의 15개 useXxxReport 훅을 controlled mode로 전환 — 외부 params 우선 주입 + backward-compatible 내부 fallback으로 Phase 8 셸(ReportsPreviewPanel) embedding 기반 마련.

## What Shipped

15개 report hook 전부가 `(externalParams?: any)` 시그니처로 변경되었고, 각 훅 모듈이 `xxxDefaultParams()` named export를 제공한다. 기존 Phase 6 `/reportes/*` 페이지는 변경 없이 동작 (Next.js build green, 16개 /reportes 라우트 전부 정적 생성 확인).

## Hook Catalog

| # | Hook | Variant | Default Params Shape | Extras |
|---|------|---------|----------------------|--------|
| 1 | useVendedorReport | B | `{startDate, endDate, filter}` | — |
| 2 | useGastoReport | B | `{startDate, endDate, filter}` | — |
| 3 | useFalladosReport | B | `{startDate, endDate, filter}` | — |
| 4 | useCorregidoReport | B | `{startDate, endDate, filter}` | — |
| 5 | useBreveVentaReport | B | `{startDate, endDate, filter}` | — |
| 6 | useFacturacionReport | B | `{startDate, endDate, filter}` | — |
| 7 | useIngresoReport | B | `{startDate, endDate, filter}` | — |
| 8 | useMovidosReport | B | `{startDate, endDate, filter}` | — |
| 9 | useReservadoReport | B | `{startDate, endDate, filter}` | — |
| 10 | useChequeEstadoReport | B | `{startDate, endDate, filter}` | — |
| 11 | useAlertasReport | C | `{filter}` | — |
| 12 | useClientesCreditoReport | C | `{filter}` | — |
| 13 | useSalesReport | A | `{startDate, endDate, filter, isParent:true}` | helpers + `getSaleItemsSummary(id, overrideParams?)` |
| 14 | useProductsReport | A | `{startDate, endDate, filter, isParent:true}` | helpers + `getProductSalesSummary(id, overrideParams?)` |
| 15 | useStockReport | A | `{startDate, endDate, filter, isParent:true}` | helpers + `getProductStockSummary(id, overrideParams?)` |

## Tasks Executed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | 12 Variant B/C hooks controlled mode | `37140bb` | 12 files |
| 2 | 3 Variant A hooks + helpers + drilldown override | `3b2b389` | 3 files |

## Verification

- `npx tsc --noEmit` — 에러 0
- `npm run build` (Next.js + ESLint) — exit 0, all /reportes/* routes generated
- Backward-compat 확인: 기존 Phase 6 페이지가 훅을 인자 없이 호출 → 내부 fallback state 동작

## Deviations from Plan

None — plan executed exactly as written.

## Wave 2 (08-02) TODO — Body Extraction

각 view의 `XxxReport.tsx`는 현재 훅에서 params를 읽고 있다. Wave 2에서 다음을 수행:

1. **Params Panel 구축** — 선택된 slug에 맞는 input 필드(date range / filter / isParent) 렌더
2. **Body 컴포넌트 추출** — 각 view의 테이블/차트 부분을 `ReportsPreviewPanel`이 직접 렌더할 수 있는 presentational 컴포넌트로 분리. 현재 훅을 직접 호출하는 wrapper를 유지하되, 내부는 stateless table/chart로 전환.
3. **Slug → Hook 매핑 레지스트리** 생성 (`src/views/reports-v2/hookRegistry.ts`)
4. **Helper 재구현** — Variant A 페이지들(`sales/ventas`, `products/items`, `stocks/stocks`)에서 `setThisMonth/setToday/clear`를 params panel의 로컬 함수로 재구현
5. **Drilldown UI** — ReportsPreviewPanel이 `getSaleItemsSummary/getProductSalesSummary/getProductStockSummary` 호출 시 `overrideParams`로 셸 params 주입

## Self-Check: PASSED

- Modified files verified present (15/15)
- Commits verified: `37140bb`, `3b2b389`
- Build green
