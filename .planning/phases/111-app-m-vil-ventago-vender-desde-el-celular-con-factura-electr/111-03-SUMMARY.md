---
phase: 111-app-m-vil-ventago-vender-desde-el-celular-con-factura-electr
plan: 03
subsystem: api-mobile-pos
tags: [nestjs, contracts, tenant-isolation, timezone, mercadopago-qr]
requires: [111-01]
provides:
  - pos-contracts.ts (36 interfaces + POS_ERROR)
  - deviceCtx(req) / PosDevice / RequestWithDevice
  - storeDayWindow (store timezone)
  - countSinEmitir / listSinEmitir (no day window by default, D-12)
  - MobilePosModule + 6 empty sub-module shells wired into AppModule
affects: [111-04, 111-05, 111-06, 111-07, 111-08, 111-15, 111-17]
tech-stack:
  added: []
  patterns: [Intl-based store-day helpers reused from common/utils/store-day.util]
key-files:
  created:
    - api-ventago/src/app/mobile/pos/shared/pos-contracts.ts
    - api-ventago/src/app/mobile/pos/shared/pos-request.ts
    - api-ventago/src/app/mobile/pos/shared/store-day.ts
    - api-ventago/src/app/mobile/pos/shared/store-day.spec.ts
    - api-ventago/src/app/mobile/pos/shared/sin-emitir.query.ts
    - api-ventago/src/app/mobile/pos/shared/sin-emitir.query.spec.ts
    - api-ventago/src/app/mobile/pos/mobile-pos.module.ts
    - api-ventago/src/app/mobile/pos/{context,sales,fiscal,stock,reports,mp}/pos-*.module.ts
  modified:
    - api-ventago/src/app.module.ts
key-decisions:
  - "Sin-emitir excludes both Anulado and Anulación statuses and filters activityType='sale'"
  - "Client name resolved storeClient->globalClient.fullname, falling back to legacy client.fullname"
duration: ~20min
completed: 2026-10-16
---

# Phase 111 Plan 03: Shared POS foundation Summary

Typed /mobile/pos contracts (including MP QR shapes), deviceCtx tenant helper, store-timezone day window and a window-less «sin emitir» query, plus empty sub-module shells wired into AppModule.

## Commits (api-ventago repo, not pushed)
- 378b1e7d feat(111-03): contracts, deviceCtx, storeDayWindow, sin-emitir
- 9815b3d3 feat(111-03): module shells and MobilePosModule in AppModule

## Verification
- jest src/app/mobile: 8 suites, 76 tests pass (8 new). tsc exit 0. eslint and prettier clean on new files.

## Deviations from Plan
- **[Rule 3] AppModule path:** plan said `src/app/app.module.ts`; the real file is `src/app.module.ts`. Edited that one.
- **[Rule 1] Lint:** `PosErrorCode | string` replaced by `PosErrorCode | (string & {})` (keeps autocomplete, satisfies no-redundant-type-constituents); `Number(r.id)` to avoid no-unsafe-assignment. First commit attempt was blocked by the gate and redone.
- Report-response contract shapes (CajaReportResponse, StockReportResponse, catalog items) were only loosely specified; defined with the plan's `{valor,cuenta}` convention. Plans 07/08 may extend them.

## Known Stubs
Module shells are intentionally empty; each is filled by Plans 04/05/06/07/08/17.

## Notes
- Not pushed. STATE.md/ROADMAP.md left uncommitted (contain others' changes). Root gitlink for api-ventago not committed.

## Self-Check: PASSED
