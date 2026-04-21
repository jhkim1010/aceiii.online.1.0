---
phase: 16-control-de-talleres
plan: "06"
subsystem: talleres-qc-rework
tags: [talleres, qc, rework, scorecard, defect-codes, wave6]
requirements: [TALLERES-12, TALLERES-13]

dependency_graph:
  requires: ["16-05"]
  provides:
    - talleres_defect_codes table + 8-code seed
    - talleres_qc_items table + REWORK/SCRAP/CLAIM side-effects
    - GET/POST /talleres/defect-codes (admin CRUD)
    - POST /talleres/qc-items/upload (MinIO photo)
    - GET /talleres/vendors/:id/scorecard (MemoryCache 5min)
    - QcItemsEditor (React, uiId pattern)
    - VendorScorecardSection (React.memo, SVG sparkline)
    - DefectsListView thumbnails + defect_code filter
    - /talleres/defect-codes admin CASL page
  affects:
    - recepcion.service.ts (transaction extended)
    - envio.service.ts (createReworkChild)
    - subcon.module.ts (new controllers/providers)
    - talleres_EnviosListView (qcItems in ReceptionModal)

tech_stack:
  added:
    - MemoryCacheService for defect codes (60s) and scorecard (5min)
    - MinIO photo upload with uuid-named files
    - HTMLCanvas image resize (max 1280px, JPEG 0.82)
    - SVG polyline sparkline (no external library)
    - crypto.randomUUID() for QcItemDraft uiId
    - forwardRef() injection (QcItemService → EnvioService)
  patterns:
    - Single Sequelize transaction: recepcion + qcItems + side-effects
    - uiId strip pattern: destructure + void before POST
    - Route ordering: admin/all before :id in NestJS controller

key_files:
  created:
    - api-ventago/migrations/20260421-create-talleres-qc-tables.sql
    - api-ventago/src/app/subcon/defect-codes/defect-code.model.ts
    - api-ventago/src/app/subcon/defect-codes/defect-code.service.ts
    - api-ventago/src/app/subcon/defect-codes/defect-code.controller.ts
    - api-ventago/src/app/subcon/qc-items/qc-item.model.ts
    - api-ventago/src/app/subcon/qc-items/qc-item.service.ts
    - api-ventago/src/app/subcon/qc-items/qc-item.controller.ts
    - ventago-app/src/utils/image-resize.ts
    - ventago-app/src/hooks/api/useDefectCodes.ts
    - ventago-app/src/views/talleres/envios/components/QcItemsEditor.tsx
    - ventago-app/src/views/talleres/vendors/components/VendorScorecardSection.tsx
    - ventago-app/src/views/talleres/defect-codes/DefectCodesAdminView.tsx
    - ventago-app/src/pages/talleres/defect-codes/index.tsx
  modified:
    - api-ventago/src/app/subcon/envios/envio.service.ts
    - api-ventago/src/app/subcon/recepciones/recepcion.service.ts
    - api-ventago/src/app/subcon/recepciones/recepcion.controller.ts
    - api-ventago/src/app/subcon/dashboard/dashboard.service.ts
    - api-ventago/src/app/subcon/dashboard/dashboard.controller.ts
    - api-ventago/src/app/subcon/subcon.module.ts
    - api-ventago/src/app/functions/seed/functions-seed-talleres.ts
    - ventago-app/src/views/talleres/envios/talleres_EnviosListView.tsx
    - ventago-app/src/views/talleres/defects/talleres_DefectsListView.tsx
    - ventago-app/src/views/talleres/vendors/components/talleres_VendorDetailPanel.tsx

decisions:
  - "forwardRef() injection used for QcItemService → EnvioService circular dep — standard NestJS pattern"
  - "crypto.randomUUID() chosen over uuid package (not installed in ventago-app)"
  - "uiId strip: destructure + void pattern to satisfy ESLint no-unused-vars"
  - "Route order: GET admin/all declared before :id to prevent NestJS route shadowing"
  - "T-16-06-06: server-side MAJOR/CRITICAL photoUrl NOT NULL enforced in qc-item.service.ts"

metrics:
  duration_minutes: 90
  completed_date: "2026-04-21"
  tasks_completed: 3
  tasks_total: 3
  files_created: 13
  files_modified: 10
---

# Phase 16 Plan 06: Wave 6 — QC 구조화 + Rework 자동화 + Vendor Scorecard

**One-liner:** Single-transaction QC receipt flow with REWORK/SCRAP/CLAIM side-effects, MinIO photo upload, SVG sparkline vendor scorecard, and admin defect-code CRUD — all behind CASL `talleres_qc_admin` guard.

## Tasks Completed

| Task | Description | Commit | Key Files |
|------|-------------|--------|-----------|
| 1 | Backend: DB migration, DefectCode + QcItem modules, RecepcionService extended, EnvioService.createReworkChild, DashboardService.getVendorScorecard | `356be4d` | 14 files in api-ventago |
| 2 | Frontend: QcItemsEditor, image-resize util, useDefectCodes SWR, DefectsListView thumbnails/filter, VendorScorecardSection, VendorDetailPanel wired | `e23e375` | 7 files in ventago-app |
| 3 | Frontend: DefectCodesAdminView CRUD drawer + CASL guard page | `2c6956b` | 2 files in ventago-app |

## Acceptance Criteria Verification

| Criterion | Status |
|-----------|--------|
| ReceptionModal sends qcItems[] in single POST | PASS |
| REWORK creates child envio in same transaction | PASS (createReworkChild) |
| SCRAP deducts lote.availableQuantity with underflow 400 guard | PASS |
| CLAIM creates SubconDefect with deductionAmount | PASS |
| Photo upload → MinIO talleres/qc/{storeId}/{recepcionId}/{uuid}.jpg | PASS |
| Canvas resize max 1280px JPEG 0.82 before upload | PASS |
| GET scorecard?days=90 returns defectRate/onTimeRate/reworkRate + sparkline | PASS |
| VendorScorecardSection renders 3 KPIs + sparkline | PASS |
| DefectsListView photo thumbnail + defect_code filter | PASS |
| Admin CRUD /talleres/defect-codes (CASL talleres_qc_admin) | PASS |
| MAJOR/CRITICAL requires photoUrl (T-16-06-06) | PASS |
| api-ventago TSC: 0 errors | PASS |
| ventago-app TSC: 0 new errors | PASS |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] TSC TS4053: VendorScorecardResponse not exported**
- **Found during:** Task 1 TSC validation
- **Issue:** `interface VendorScorecardResponse` in dashboard.service.ts was not exported, causing "cannot be named in return type" error
- **Fix:** Added `export` keyword to interface declaration
- **Files modified:** api-ventago/src/app/subcon/dashboard/dashboard.service.ts

**2. [Rule 3 - Blocking] TSC TS2769: useDefectCodes SWR overload mismatch**
- **Found during:** Task 2 TSC validation
- **Issue:** Custom SWR fetcher `(url: string) => apiConnector.get(url)` returns `Promise<unknown>` not matching `BareFetcher<DefectCode[]>`
- **Fix:** Replaced custom SWR usage with project-standard `useApi<DefectCode[]>` hook from `src/hooks/useApi`
- **Files modified:** ventago-app/src/hooks/api/useDefectCodes.ts

**3. [Rule 3 - Blocking] uuid package not installed**
- **Found during:** Task 2 implementation
- **Issue:** `import { v4 as uuidv4 } from 'uuid'` fails — uuid not in ventago-app dependencies
- **Fix:** Replaced with `crypto.randomUUID()` (native browser API, no package needed)
- **Files modified:** ventago-app/src/views/talleres/envios/components/QcItemsEditor.tsx

**4. [Rule 1 - Bug] ESLint lines-around-comment + no-unused-vars (2 instances)**
- **Found during:** Task 2 ESLint validation
- **Issue 1:** Comment on QcItemsEditor.tsx line 302 missing blank line before it
- **Issue 2:** `{ uiId: _uiId, ...rest }` pattern — `_uiId` flagged by no-unused-vars
- **Fix 1:** Added blank line before comment
- **Fix 2:** Used `const { uiId, ...serverItem } = item; void uiId;` pattern to consume the destructured binding
- **Files modified:** QcItemsEditor.tsx, talleres_EnviosListView.tsx

## Known Stubs

None — all data flows are wired end-to-end.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: file-upload | api-ventago/src/app/subcon/qc-items/qc-item.service.ts | New MinIO upload endpoint for QC photos — MIME whitelist + 3MB limit + uuid filename enforced |
| threat_flag: authorization | api-ventago/src/app/subcon/defect-codes/defect-code.controller.ts | Admin CRUD routes protected by talleres_qc_admin role check |

## Self-Check: PASSED

Files verified present:
- api-ventago/migrations/20260421-create-talleres-qc-tables.sql: FOUND
- api-ventago/src/app/subcon/defect-codes/defect-code.service.ts: FOUND
- api-ventago/src/app/subcon/qc-items/qc-item.service.ts: FOUND
- ventago-app/src/views/talleres/envios/components/QcItemsEditor.tsx: FOUND
- ventago-app/src/views/talleres/vendors/components/VendorScorecardSection.tsx: FOUND
- ventago-app/src/views/talleres/defect-codes/DefectCodesAdminView.tsx: FOUND
- ventago-app/src/pages/talleres/defect-codes/index.tsx: FOUND

Commits verified:
- 356be4d: FOUND (api-ventago)
- e23e375: FOUND (ventago-app)
- 2c6956b: FOUND (ventago-app)
