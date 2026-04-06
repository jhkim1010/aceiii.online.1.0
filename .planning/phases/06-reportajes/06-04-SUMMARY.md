---
phase: 06-reportajes
plan: 04
subsystem: reports
tags: [reports, backend, frontend, excel, multitenant, alerts, cheque]
requires: [Stocks model, ProductBranch, SalePaymentMethod, PaymentMethod, Wave 1/2/3 patterns]
provides:
  - "ReportsAlertasService — 재고 부족(Sin Stock / Bajo Stock) 알림"
  - "ReportsChequeEstadoService — 수표 결제 현황 (slug=cheque 필터 + fallback)"
  - "/reportes/alertas, /reportes/cheque-estado 페이지"
  - "Hub catalog finalized (15 reports, 모두 구현 완료)"
affects:
  - "modules.seed: alertas + cheque-estado nav 모듈 추가"
  - "ReportesHub: 미구현 placeholder 제거하고 실제 구현된 15개로 정리"
tech-stack:
  added: []
  patterns:
    - "Alertas: reportsStocks SReal 합산 패턴 재활용 (Stocks group by productBranchId)"
    - "Cheque Estado: PaymentMethod.findOne(slug=cheque) → SalePaymentMethod.findAll 필터, 없으면 전체 표시"
    - "MUI Chip variant='filled' (Wave 3 lesson 적용)"
key-files:
  created:
    - api-ventago/src/app/reports/reportsAlertas.service.ts
    - api-ventago/src/app/reports/reportsChequeEstado.service.ts
    - ventago-app/src/views/reports/alertas/hooks/useAlertasReport.tsx
    - ventago-app/src/views/reports/alertas/components/DataConfig.tsx
    - ventago-app/src/views/reports/alertas/components/AlertasReportTable.tsx
    - ventago-app/src/views/reports/alertas/AlertasReport.tsx
    - ventago-app/src/pages/reportes/alertas/index.tsx
    - ventago-app/src/views/reports/cheque-estado/hooks/useChequeEstadoReport.tsx
    - ventago-app/src/views/reports/cheque-estado/components/DataConfig.tsx
    - ventago-app/src/views/reports/cheque-estado/components/ChequeEstadoReportTable.tsx
    - ventago-app/src/views/reports/cheque-estado/ChequeEstadoReport.tsx
    - ventago-app/src/pages/reportes/cheque-estado/index.tsx
  modified:
    - api-ventago/src/app/reports/reports.controller.ts
    - api-ventago/src/app/reports/reports.module.ts
    - api-ventago/src/app/modules/seed/modules.seed.ts
    - ventago-app/src/views/reports/hub/ReportesHub.tsx
decisions:
  - "Alertas는 SReal <= 0 → 'Sin Stock', SReal <= 5 → 'Bajo Stock' 임계값 적용 (LOW_STOCK_THRESHOLD 상수)"
  - "Cheque Estado는 PaymentMethod.findOne(slug='cheque')로 1차 필터, 없으면 SalePaymentMethod 전체 표시 (RESEARCH 권장 fallback)"
  - "Cheque Estado branchId/filter 검색은 메모리 필터 (Sale.branchId 없는 일관된 한계 — Wave 1~3 동일)"
  - "Hub 카탈로그를 unimplemented placeholder 제거 후 15개 실제 구현 페이지로 정리 (Wave 1 Summary의 known stub 해소)"
metrics:
  duration: "~10min"
  completed: "2026-04-06"
  tasks: 2
  files_created: 12
  files_modified: 4
---

# Phase 06 Plan 04: Wave 4 Reports Summary

Wave 4 마지막 보고서 2종(Alertas 재고 부족 알림, Cheque Estado 수표 결제 현황) 백엔드 서비스 + 컨트롤러 엔드포인트 4개 + 프론트엔드 뷰 2개 + 허브 페이지 최종 정리. **Phase 06 reportajes 시스템 완성: 15개 보고서 전체 wired**.

## What Was Built

### Backend (api-ventago)
- **ReportsAlertasService**: ProductBranch + Product(storeId) + Branch include → 각 PB별 Stocks 합산하여 SReal 계산 → SReal <= 0 = 'Sin Stock', SReal <= 5 = 'Bajo Stock' 필터링. reportsStocks SReal 패턴 재활용. 날짜 필터 없음 (현재 재고 상태).
- **ReportsChequeEstadoService**: PaymentMethod.findOne where slug='cheque' AND storeId 1차 조회 → 있으면 paymentMethodId 필터, 없으면 전체. SalePaymentMethod.findAll include Sale(client) + PaymentMethod. branchId/filter는 메모리 필터.
- **Controller**: 4개 신규 엔드포인트 (alertas-report, alertas-report-export, cheque-estado-report, cheque-estado-report-export).
- **Module**: 2 services를 providers + exports.
- **Seed**: nav 모듈 2개 추가 (alertas-reportes, cheque-estado-reportes).

### Frontend (ventago-app)
- **Alertas**: hook (RangeDate 없음) + DataConfig(5 cols, Estado 컬럼은 MUI Chip warning/error 시각화) + Table + Report (단일 12-grid, ProductFilterInput만) + page (WithAccess).
- **Cheque Estado**: hook (RangeDate 포함) + DataConfig(6 cols, Monto 통화 포맷 ARS) + Table + Report (8/4 split with RangeDate) + page.
- **ReportesHub**: 미구현 placeholder 제거 → 실제 구현된 15개 카드만 노출 (Wave 0~4 모두 구현). Wave 1 Summary의 "Hub catalog 11개 미구현" Known Stub 해소.

## Verification

- `cd api-ventago && npx tsc --noEmit` — 통과 (출력 없음).
- `cd ventago-app && npx next build` — Compiled successfully. 신규 페이지:
  - `/reportes/alertas`         3.31 kB
  - `/reportes/cheque-estado`   1.52 kB

## Deviations from Plan

None — 플랜 그대로 실행. Wave 1~3 패턴 일관성 유지.

### Plan Simplifications
- **Search debounce 0.5s + dynamic pageSize**: Wave 1~3과 동일하게 기본 페이지네이션 (SalesReportTable 패턴 유지).
- **CardFilter 컴포넌트**: Wave 1~3 일관성으로 Card+CardHeader 직접 사용.

## Commits

- `a1b0f5a` (api-ventago) — feat(06-04): wave 4 backend - alertas + cheque estado reports
- `6bb2b44` (ventago-app) — feat(06-04): wave 4 frontend - alertas + cheque estado + hub finalization

## Known Stubs

None — 모든 데이터가 실제 DB에 wired됨. Hub catalog의 Wave 1 known stub (11 unimplemented placeholders)도 본 plan에서 해소됨. **Phase 06 reportajes는 stub-free 완성**.

## Self-Check: PASSED

- FOUND: api-ventago/src/app/reports/reportsAlertas.service.ts
- FOUND: api-ventago/src/app/reports/reportsChequeEstado.service.ts
- FOUND: ventago-app/src/views/reports/alertas/AlertasReport.tsx
- FOUND: ventago-app/src/views/reports/cheque-estado/ChequeEstadoReport.tsx
- FOUND: ventago-app/src/pages/reportes/alertas/index.tsx
- FOUND: ventago-app/src/pages/reportes/cheque-estado/index.tsx
- FOUND commit (api-ventago): a1b0f5a
- FOUND commit (ventago-app): 6bb2b44
