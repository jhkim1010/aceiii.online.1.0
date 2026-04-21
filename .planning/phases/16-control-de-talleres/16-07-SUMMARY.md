---
phase: 16
plan: "07"
subsystem: talleres
tags: [tarifa-historización, settlement-state-machine, pdf, wave-7]
dependency_graph:
  requires: [16-06]
  provides: [tarifa-history, settlement-lifecycle, settlement-pdf]
  affects: [subcon-settlements, vendor-etapas, liquidaciones-tab, etapas-tab]
tech_stack:
  added: [pdfkit, "@types/pdfkit"]
  patterns: [state-machine, partial-unique-index, swr-2min, union-type-detection]
key_files:
  created:
    - api-ventago/migrations/20260422-vendor-etapa-historization-step1-schema.sql
    - api-ventago/migrations/20260422-vendor-etapa-historization-step2-enum.sql
    - api-ventago/migrations/20260422-vendor-etapa-historization-step3-verify.sql
    - api-ventago/src/app/subcon/subcon-settlements/subcon-settlement-line.model.ts
    - api-ventago/src/app/subcon/subcon-settlements/types.ts
    - api-ventago/src/app/subcon/subcon-settlements/settlement-pdf.service.ts
    - ventago-app/src/hooks/api/useSettlements.ts
    - ventago-app/src/views/talleres/liquidaciones/components/GenerateDraftDialog.tsx
    - ventago-app/src/views/talleres/liquidaciones/components/SettlementDetailDrawer.tsx
    - ventago-app/src/views/talleres/etapas/components/RateHistoryPanel.tsx
  modified:
    - api-ventago/src/app/subcon/vendor-etapas/vendor-etapa.model.ts
    - api-ventago/src/app/subcon/vendor-etapas/vendor-etapa.service.ts
    - api-ventago/src/app/subcon/vendor-etapas/vendor-etapa.controller.ts
    - api-ventago/src/app/subcon/subcon-settlements/subcon-settlement.model.ts
    - api-ventago/src/app/subcon/subcon-settlements/subcon-settlement.service.ts
    - api-ventago/src/app/subcon/subcon-settlements/subcon-settlement.controller.ts
    - api-ventago/src/app/subcon/subcon.module.ts
    - api-ventago/src/app/functions/seed/functions-seed-talleres.ts
    - ventago-app/src/services/api.service.ts
    - ventago-app/src/views/talleres/tabs/LiquidacionesTab.tsx
    - ventago-app/src/views/talleres/tabs/EtapasTab.tsx
decisions:
  - "pdfkit over puppeteer: no headless Chrome needed, smaller footprint, pdfkit@^0.15"
  - "3-step migration split: PG10 requires ALTER TYPE ADD VALUE outside transaction (step2 autocommit)"
  - "union type detection in api.service.ts get(): backward-compatible blob support without breaking 15+ callers"
  - "status as DataType.STRING(20) instead of ENUM decorator: avoids sequelize-typescript enum sync issues"
  - "subconOrderId nullable: Wave 7 settlements are vendor-direct, not tied to a subconOrder"
metrics:
  duration_minutes: 90
  completed_date: "2026-04-21"
  tasks_completed: 3
  tasks_total: 3
  files_created: 10
  files_modified: 11
---

# Phase 16 Plan 07: Wave 7 — Tarifa Historización + Auto-liquidación Summary

**One-liner:** Full tarifa rate history with partial unique index + Settlement DRAFT→CONFIRMED→PAID state machine with pdfkit PDF generation and Zedonk-themed frontend drawers.

---

## Tasks Completed

| Task | Name | Commit | Sub-repo | Key Files |
|------|------|--------|----------|-----------|
| 1 | Backend: Tarifa historia + Settlement state machine + PDF | `3f71a89` | api-ventago | migrations/*.sql, vendor-etapa.service.ts, subcon-settlement.service.ts, settlement-pdf.service.ts |
| 2 | Frontend: LiquidacionesTab + GenerateDraftDialog + SettlementDetailDrawer | `f7971b1` | ventago-app | useSettlements.ts, LiquidacionesTab.tsx, GenerateDraftDialog.tsx, SettlementDetailDrawer.tsx |
| 3 | Frontend: EtapasTab matrix + RateHistoryPanel | `b13101a` | ventago-app | EtapasTab.tsx, RateHistoryPanel.tsx |

---

## Artifacts Delivered

### Backend (api-ventago @ 3f71a89)

**Migrations (3-step split for PG10 compatibility):**
- `step1-schema.sql` — transactional DDL: effective_from/to columns, partial unique index `idx_vendor_etapa_active`, settlement meta columns (vendorId, confirmedAt, confirmedBy, periodFrom, periodTo, deductionAmount, totalGrossAmount), `talleres_settlement_lines` table
- `step2-enum.sql` — `ALTER TYPE ... ADD VALUE IF NOT EXISTS` for DRAFT/CONFIRMED/PAID/CANCELLED (runs OUTSIDE transaction — autocommit required)
- `step3-verify.sql` — verification queries for pg_enum, column info, indexes, FKs

**VendorEtapaService methods:**
- `setRate(vendorId, etapaId, unitPrice, effectiveFrom)` — FOR UPDATE lock, idempotent if same price+date, closes prior active with effectiveTo=effectiveFrom-1day
- `getRateAt(vendorId, etapaId, date)` — date-range overlap query
- `listHistory(vendorId, etapaId)` — ordered effectiveFrom DESC
- `validateVendorOwnership(vendorId, storeId)` — multi-tenant guard

**Settlement state machine (INV-1..INV-4):**
- `generateForPeriod()` — single transaction, 366-day limit, existing DRAFT upsert, recepciones+envios aggregate, legacy defects and QC claims, bulkCreate lines
- `confirm()` — LOCK.UPDATE, requires lines≥1 and netAmount>0
- `cancel()` — DRAFT only (INV-3)
- `markPaid()` — CONFIRMED only (INV-4)
- `SettlementImmutableException` — BadRequestException with code `SETTLEMENT_IMMUTABLE`

**SettlementPdfService:** pdfkit A4, store header, BORRADOR watermark label, lines table, totals section, `sanitize()` strips control chars

**CASL seed:** `talleres_settlement_confirm` function slug registered

### Frontend (ventago-app)

**Task 2 (f7971b1):**
- `useSettlements` SWR hook — 2min dedupingInterval, exports SettlementRow interface
- `LiquidacionesTab` — 6-status STATUS_CHIP, KPI cards, row-click→Drawer, `+ Generar borrador` button
- `GenerateDraftDialog` — Vendor Autocomplete, date pickers, validation, `POST /talleres/settlements/draft`
- `SettlementDetailDrawer` — 420px Drawer, lines table, 3 KPI cards, immutable banner, PDF download via responseType blob

**Task 3 (b13101a):**
- `EtapasTab` — matrix cells clickable (`setSelectedCell`), `Chip 'Sin tarifa'` when no price, hover bgcolor
- `RateHistoryPanel` — 420px Drawer, timeline with vertical line+dot, active Chip gold, nueva tarifa form with date validation

---

## Must-Have Truths Verification

| # | Invariant | Status |
|---|-----------|--------|
| INV-1 | CONFIRMED/PAID/CANCELLED → immutable (SettlementImmutableException) | PASS |
| INV-2 | confirm() requires lines≥1 and netAmount>0 | PASS |
| INV-3 | cancel() only from DRAFT | PASS |
| INV-4 | markPaid() only from CONFIRMED | PASS |
| T-16-07-07 | generateForPeriod period max 366 days | PASS |
| IDX-01 | Only one active rate per (vendor, etapa) — partial unique index | PASS |

---

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] TSC null safety on subconOrderId**
- **Found during:** Task 1 compilation
- **Issue:** `findByPk(settlement.subconOrderId)` — `Type 'null' is not assignable to parameter of type 'Identifier | undefined'`
- **Fix:** Added null check: `settlement.subconOrderId ? await this.subconOrderModel.findByPk(settlement.subconOrderId) : null`
- **Files modified:** subcon-settlement.service.ts
- **Commit:** 3f71a89

**2. [Rule 1 - Bug] api.service.ts get() broke all existing callers**
- **Found during:** Task 2 integration
- **Issue:** Initial `GetBlobConfig` wrapper with `params` key required all existing callers to change `get(path, { page:0 })` → `get(path, { params: { page:0 } })` — ~15 files would break
- **Fix:** Union type detection at runtime: `if ('responseType' in configOrParams)` distinguishes blob config from legacy plain params object. All existing callers unchanged.
- **Files modified:** api.service.ts
- **Commit:** f7971b1

**3. [Rule 2 - Missing critical] status field as STRING instead of ENUM decorator**
- **Found during:** Task 1 model design
- **Issue:** Sequelize-typescript ENUM decorator causes sync conflicts with manually managed ENUM type in PG10
- **Fix:** `DataType.STRING(20)` with CHECK constraint in migration, TypeScript union `SettlementStatus` type for compile-time safety
- **Files modified:** subcon-settlement.model.ts
- **Commit:** 3f71a89

**4. [Rule 3 - Blocking] 3-step migration split for PG10**
- **Found during:** Task 1 migration design
- **Issue:** PG10 requires `ALTER TYPE ADD VALUE` to run outside any transaction. Single-file migration with `BEGIN/COMMIT` would fail.
- **Fix:** Split into step1 (transactional DDL), step2 (autocommit ENUM), step3 (verify). Step2 documented as requiring `psql` without `--single-transaction` flag.
- **Files modified:** 3 new migration files
- **Commit:** 3f71a89

---

## Known Stubs

None. All data sources are wired to real API endpoints.

---

## Threat Flags

None. No new network endpoints beyond what the plan specified. All settlement mutation routes (confirm/cancel/mark-paid) are protected by JWT + session guards inherited from base controller. PDF download route protected by same guards.

---

## Self-Check

Commits exist:
- api-ventago `3f71a89` — FOUND
- ventago-app `f7971b1` — FOUND
- ventago-app `b13101a` — FOUND

Key files exist:
- api-ventago/migrations/20260422-vendor-etapa-historization-step1-schema.sql — FOUND
- api-ventago/src/app/subcon/subcon-settlements/settlement-pdf.service.ts — FOUND
- api-ventago/src/app/subcon/subcon-settlements/subcon-settlement-line.model.ts — FOUND
- ventago-app/src/hooks/api/useSettlements.ts — FOUND
- ventago-app/src/views/talleres/liquidaciones/components/GenerateDraftDialog.tsx — FOUND
- ventago-app/src/views/talleres/liquidaciones/components/SettlementDetailDrawer.tsx — FOUND
- ventago-app/src/views/talleres/etapas/components/RateHistoryPanel.tsx — FOUND

## Self-Check: PASSED
