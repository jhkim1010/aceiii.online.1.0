---
phase: 111-app-m-vil-ventago-vender-desde-el-celular-con-factura-electr
plan: 08
subsystem: api-mobile-pos
tags: [nestjs, reports, store-timezone, caja, colibri]
requires: ["111-03", "111-15"]
provides:
  - GET /mobile/pos/reports/day/:branchId (?fecha=AAAA-MM-DD), /caja, /stock/:branchId
  - PosReportsService (day, caja, stock)
  - DashboardsModule exports SalesDashboardsService
key-files:
  created:
    - api-ventago/src/app/mobile/pos/reports/pos-reports.service.ts (+ spec)
    - api-ventago/src/app/mobile/pos/reports/pos-reports.controller.ts (+ spec)
  modified:
    - api-ventago/src/app/mobile/pos/reports/pos-reports.module.ts
    - api-ventago/src/app/mobile/pos/shared/pos-contracts.ts
    - api-ventago/src/app/dashboards/dasboards.module.ts
decisions:
  - Day numbers come from SalesService.getDailySummary with explicit dates from storeDayWindow; cobrado = buckets minus credito, aCuenta = buckets.credito, as the web DailySalesStats
  - Facturado from ReportsFacturacionCockpitService.getCockpit (afip_vouchers, NC subtract), the web facturacion source
  - Caja esperado is totals.saldoFinal from CashRegisterService (no arithmetic here); session found by the device box
metrics:
  completed: 2026-10-16
  api-commit: f5017b9c
---

# Phase 111 Plan 08: Reportes del celular Summary

Tres reportes del celular (dia, caja, stock) compuestos con los mismos servicios que la web, con el dia de la tienda como ventana y un texto «que cuenta» por numero.

## Commits (api-ventago, no pushed)
- f5017b9c feat(111-08): reportes del celular (dia, caja, stock) con los servicios de la web (ambas tareas en un commit: servicio, controlador y modulo se compilan juntos)

## Verification
- jest `src/app/mobile/pos/reports`: 20 tests verdes (servicio 16, controlador 4); `src/app/mobile` completo: 24 suites / 274 tests verdes. tsc 0, eslint limpio.
- Caso de la trampa UTC literal: 2026-10-16T01:30Z -> fecha 2026-10-15 y getDailySummary con startDate=endDate='2026-10-15'.
- Mutaciones: quitar `window` de countSinEmitir y reemplazar saldoFinal por totals.venta -> 2 tests fallan. Restaurado, 20 verdes.
- Acceptance greps: sin `toISOString().slice(0, 10)` salvo en el helper de aritmetica de calendario minus7 (no es «hoy»); sin `initialAmount +`; `git diff` sobre src/app/reports vacio.

## Deviations from Plan
- **[Rule 2] Contratos:** `CajaReportResponse` y `StockReportResponse` de Plan 03 no cubrian lo que pide este plan (`abierta:false`, ingresos/retiros, lista de operaciones, mas vendidos, alertas). Se reescribieron en pos-contracts.ts; no tenian consumidores en el repo (grep en colibri/shared/api). `DayReportResponse` no cambio.
- Stock: el cockpit no da unidades totales; se informan productos (variantes), sin stock, bajo stock (1-5) y alertas de bajo/sin stock. Se omite a proposito el valor de stock (T-111-46: nada de costo/valor).
- `porMedio.slug` es el titulo del medio normalizado: getDailySummary agrupa por titulo y no devuelve slug.
- Facturado resta notas de credito (asi lo hace el cockpit de la web); el texto lo dice.
- El cockpit de facturacion filtra por `created_at` con fecha sin zona (igual que la web); se reutiliza tal cual para que coincidan las cifras.

## Notes
- No se hizo push. STATE.md y ROADMAP.md quedan sin commitear a proposito; el gitlink de api-ventago en el root tampoco.
- El arranque real de Nest (DI de PosReportsModule: SalesModule, ReportsModule, DashboardsModule, BoxOperationModule, CashRegisterModule) no se probo contra una BD; solo tsc y specs con mocks. Revisar al levantar la API local antes de Plan 14.
- Sin DDL/DML de produccion.

## Known Stubs
Ninguno.

## Self-Check: PASSED
Commit f5017b9c existe en api-ventago; los 4 archivos nuevos y el modulo estan presentes.
