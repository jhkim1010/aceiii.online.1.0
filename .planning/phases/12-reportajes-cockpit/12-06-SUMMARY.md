---
phase: 12-reportajes-cockpit
plan: "06"
subsystem: reports-cockpit
tags: [cockpit, clientes, breve-venta, reservado, alertas, kpi, frontend, backend]
dependency_graph:
  requires: ["12-01"]
  provides: ["clientes-credito-cockpit", "breve-venta-cockpit", "reservado-cockpit", "alertas-cockpit"]
  affects: ["reports-v2/registry"]
tech_stack:
  added: []
  patterns:
    - "KpiStrip + Tabs (Resumen + Lista) — reused from Wave 04/05"
    - "parallel raw SQL queries (pool-safe)"
    - "lazy registry swap — legacy ReportBody replaced by CockpitBody"
key_files:
  created:
    - api-ventago/src/app/reports/reportsClientesCreditoCockpit.service.ts
    - api-ventago/src/app/reports/reportsBreveVentaCockpit.service.ts
    - api-ventago/src/app/reports/reportsReservadoCockpit.service.ts
    - api-ventago/src/app/reports/reportsAlertasCockpit.service.ts
    - ventago-app/src/views/reports/clientes-credito/ClientesCreditoCockpitBody.tsx
    - ventago-app/src/views/reports/clientes-credito/hooks/useClientesCreditoCockpit.tsx
    - ventago-app/src/views/reports/breve-venta/BreveVentaCockpitBody.tsx
    - ventago-app/src/views/reports/breve-venta/hooks/useBreveVentaCockpit.tsx
    - ventago-app/src/views/reports/reservado/ReservadoCockpitBody.tsx
    - ventago-app/src/views/reports/reservado/hooks/useReservadoCockpit.tsx
    - ventago-app/src/views/reports/alertas/AlertasCockpitBody.tsx
    - ventago-app/src/views/reports/alertas/hooks/useAlertasCockpit.tsx
  modified:
    - api-ventago/src/app/reports/reports.module.ts
    - api-ventago/src/app/reports/reports.controller.ts
    - ventago-app/src/views/reports-v2/registry.ts
decisions:
  - "Clientes Crédito uses store_clients + global_clients raw SQL join (no date range needed)"
  - "Breve Venta uses SVG bar chart for daily distribution vs line chart used in Facturacion"
  - "Reservado uses ventas_suspendidas table directly (confirmed from reportsReservado.service)"
  - "Alertas cockpit reuses LOW_STOCK_THRESHOLD=5 from existing reportsAlertas.service"
  - "Clients table referenced as quoted 'Clients' in SQL (no underscored tableName in model)"
metrics:
  duration_minutes: 35
  completed_date: "2026-04-13"
  tasks_completed: 2
  files_created: 12
  files_modified: 3
---

# Phase 12 Plan 06: Clientes & Control Cockpit Migration Summary

Migrated 4 Clientes & Control reports to unified CockpitLayout pattern: raw SQL parallel queries on backend, KpiStrip + Tabs on frontend, registry lazy-import swapped.

## Tasks Completed

### Task 1 — Backend cockpit services + controller endpoints

4 new cockpit services created following the established `ReportsFacturacionCockpitService` pattern:

| Service | Endpoint(s) | SQL queries |
|---------|-------------|-------------|
| `reportsClientesCreditoCockpit` | `GET /reports/clientes-credito-cockpit` + `/clientes` | `store_clients JOIN global_clients` — no date range |
| `reportsBreveVentaCockpit` | `GET /reports/breve-venta-cockpit` + `/ventas` | `sales` with generate_series trend |
| `reportsReservadoCockpit` | `GET /reports/reservado-cockpit` + `/reservados` | `ventas_suspendidas` with generate_series trend |
| `reportsAlertasCockpit` | `GET /reports/alertas-cockpit` + `/alertas` | `product_branches JOIN stocks` HAVING clause |

All services: parallel `Promise.all` query execution, pool-safe single connection pattern.

**Commits:**
- `api-ventago@3ceefef` — feat(12-06): add Clientes+BreveVenta+Reservado+Alertas cockpit backend services

### Task 2 — Frontend cockpit bodies + hooks + registry wiring

4 CockpitBody components + 4 hooks created:

| Report | Body | KPI | Primary | Detail Tab |
|--------|------|-----|---------|------------|
| Clientes Crédito | `ClientesCreditoCockpitBody` | totalBalance/clientCount/avgBalance/topDebtorBalance | TOP debtors bar list | paginated clientes table |
| Breve Venta | `BreveVentaCockpitBody` | totalTx/totalAmount/avgAmount/peakDayAmount | SVG bar chart (daily) | paginated por-día table |
| Reservado | `ReservadoCockpitBody` | totalTx/totalAmount/avgAmount/periodDays | SVG line+area chart (daily) | paginated reservados table |
| Alertas | `AlertasCockpitBody` | totalAlerts/outOfStock/lowStock/productCount | alert card list (Chip badges) | paginated alertas table |

Registry updated: lazy imports swapped to new CockpitBody files + `filterSchema` and `cockpitLayout` added to all 4 entries.

**Commits:**
- `ventago-app@8f5514a` — feat(12-06): add Clientes+BreveVenta+Reservado+Alertas cockpit bodies + registry wiring

## Deviations from Plan

None — plan executed exactly as written.

## ESLint Verification

```
✔ No ESLint warnings or errors
```

All 4 CockpitBody files + 4 hook files + registry.ts — clean lint pass. Rules observed:
- `newline-before-return`: return statements have blank line above
- `lines-around-comment`: no bare comment violations
- `no-unused-vars`: all imports used

## Known Stubs

None — all KPI values flow from live SQL queries, no placeholder data.

## Self-Check: PASSED

Files created verified:
- api-ventago/src/app/reports/reportsClientesCreditoCockpit.service.ts ✓
- api-ventago/src/app/reports/reportsBreveVentaCockpit.service.ts ✓
- api-ventago/src/app/reports/reportsReservadoCockpit.service.ts ✓
- api-ventago/src/app/reports/reportsAlertasCockpit.service.ts ✓
- ventago-app/src/views/reports/clientes-credito/ClientesCreditoCockpitBody.tsx ✓
- ventago-app/src/views/reports/breve-venta/BreveVentaCockpitBody.tsx ✓
- ventago-app/src/views/reports/reservado/ReservadoCockpitBody.tsx ✓
- ventago-app/src/views/reports/alertas/AlertasCockpitBody.tsx ✓

Commits verified:
- api-ventago@3ceefef ✓
- ventago-app@8f5514a ✓
