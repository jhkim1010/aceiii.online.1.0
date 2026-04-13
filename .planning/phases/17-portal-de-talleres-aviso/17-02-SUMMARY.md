---
phase: 17-portal-de-talleres-aviso
plan: "02"
subsystem: api-ventago/vendor-portal
tags: [vendor-portal, notifications, cron, subcon-integration]
dependency_graph:
  requires: [17-01]
  provides: [vendor-portal-api, vendor-notifications, due-soon-cron]
  affects: [subcon-envios, subcon-settlements]
tech_stack:
  added: ["@nestjs/schedule (ScheduleModule + @Cron)"]
  patterns: ["forwardRef circular injection", "non-blocking try/catch notification triggers", "SubconOrder JOIN for vendorId scoping"]
key_files:
  created:
    - api-ventago/src/app/vendor-portal/vendor-envios/vendor-envios.service.ts
    - api-ventago/src/app/vendor-portal/vendor-envios/vendor-envios.controller.ts
    - api-ventago/src/app/vendor-portal/vendor-recepciones/vendor-recepciones.service.ts
    - api-ventago/src/app/vendor-portal/vendor-recepciones/vendor-recepciones.controller.ts
    - api-ventago/src/app/vendor-portal/vendor-settlements/vendor-settlements.service.ts
    - api-ventago/src/app/vendor-portal/vendor-settlements/vendor-settlements.controller.ts
    - api-ventago/src/app/vendor-portal/vendor-notifications/vendor-notifications.service.ts
    - api-ventago/src/app/vendor-portal/vendor-notifications/vendor-notifications.controller.ts
    - api-ventago/src/app/vendor-portal/vendor-portal.cron.ts
  modified:
    - api-ventago/src/app/vendor-portal/vendor-portal.module.ts
    - api-ventago/src/app/subcon/envios/envio.service.ts
    - api-ventago/src/app/subcon/subcon-settlements/subcon-settlement.service.ts
    - api-ventago/src/app/subcon/subcon.module.ts
decisions:
  - "Envio.storeId used directly (not Vendor.storeId join) for envios filtering — Envio model has storeId column"
  - "forwardRef() used for VendorPortalModule <-> SubconModule circular dep — single direction SubconModule → VendorPortalModule"
  - "SubconSettlementService.closeSettlement() is a new explicit method rather than hooking into CrudService.update() — avoids overriding base class for all updates"
  - "Notification trigger failures wrapped in try/catch (non-blocking per T-17-09 threat model)"
metrics:
  duration: "~25min"
  completed_date: "2026-04-13T13:01:56Z"
  tasks: 2
  files: 13
---

# Phase 17 Plan 02: Vendor Portal Backend API Summary

Complete REST API for vendor portal — envios listing, recepcion creation, settlement history, notification management, daily due-soon cron, and notification event triggers wired into SubconModule services.

## What Was Built

### Task 1: Envios + Recepciones + Settlements (commit 71cc701)

**VendorEnviosService / VendorEnviosController** (`GET /vendor-portal/envios`):
- Filters by `vendorIds` (from JWT) + `storeId` directly on Envio model (Envio has its own `storeId` column)
- Includes Vendor, Lote (with Product), Etapa, Recepcion associations
- Pagination: `page` + `pageSize` query params

**VendorRecepcionesService / VendorRecepcionesController** (`POST /vendor-portal/recepciones`):
- Sequelize transaction: create Recepcion + update `envio.pendingQuantity` atomically
- Security (T-17-05): `ForbiddenException` if `envio.vendorId` not in JWT vendorIds
- Validation (T-17-06): `BadRequestException` if `receivedQty + rejectedQty > pendingQuantity`
- Auto status: `COMPLETED` if pendingQuantity reaches 0, else `PARTIAL`

**VendorSettlementsService / VendorSettlementsController** (`GET /vendor-portal/settlements`):
- JOIN through SubconOrder to filter by `vendorId` — SubconSettlement has no direct vendorId FK (T-17-07)
- Optional date range filter: `from` + `to` on `settlementDate`

### Task 2: Notifications + Cron + Wiring (commit ef1124c)

**VendorNotificationsService / VendorNotificationsController**:
- `GET /vendor-portal/notifications` — list with optional `storeId` + `isRead` filters, limit 50
- `GET /vendor-portal/notifications/unread-count` — returns `{ count: N }`
- `PATCH /vendor-portal/notifications/:id/read` — single mark with ownership check
- `PATCH /vendor-portal/notifications/read-all` — bulk mark for vendor+store

**VendorPortalCronService** (`vendor-portal.cron.ts`):
- `@Cron('0 9 * * *')` runs daily at 09:00
- Queries PENDING/PARTIAL envios with `dueDate` within 3 days
- Dedup check: skips if `DUE_SOON` notification for same `referenceId` already created today
- All errors caught, logged, non-blocking

**Module wiring**:
- `VendorPortalModule`: ScheduleModule.forRoot() added, all 4 controllers + 5 providers registered, `VendorNotificationsService` exported
- `SubconModule`: imports `forwardRef(() => VendorPortalModule)`
- `EnvioService`: injects `VendorNotificationsService`, fires `NEW_ENVIO` after `createEnvio()` commit — try/catch non-blocking
- `SubconSettlementService`: new `closeSettlement()` method fires `SETTLEMENT_DONE` — try/catch non-blocking

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Envio filtering uses Envio.storeId directly**
- **Found during:** Task 1
- **Issue:** Plan spec suggested filtering via `$vendor.store_id$` join, but Envio model already has its own `storeId` column (confirmed by reading envio.model.ts)
- **Fix:** Used `where: { vendorId: { [Op.in]: vendorIds }, storeId }` directly — simpler and no JOIN needed
- **Files modified:** vendor-envios.service.ts

**2. [Rule 2 - Missing functionality] closeSettlement() explicit method vs CrudService.update() hook**
- **Found during:** Task 2
- **Issue:** SubconSettlementService had no update method — only inherited CrudService base. Hooking into the base `update()` for SETTLEMENT_DONE would affect all updates, not just status→CLOSED transitions
- **Fix:** Added explicit `closeSettlement(id)` method that sets status=CLOSED and triggers notification. Existing CrudService.update() untouched.
- **Files modified:** subcon-settlement.service.ts

## Known Stubs

None — all data sources are wired to real Sequelize queries.

## Threat Flags

No new security-relevant surface beyond the plan's threat model. All T-17-05 through T-17-09 mitigations implemented.

## Self-Check: PASSED

Files created:
- api-ventago/src/app/vendor-portal/vendor-envios/vendor-envios.service.ts ✓
- api-ventago/src/app/vendor-portal/vendor-envios/vendor-envios.controller.ts ✓
- api-ventago/src/app/vendor-portal/vendor-recepciones/vendor-recepciones.service.ts ✓
- api-ventago/src/app/vendor-portal/vendor-recepciones/vendor-recepciones.controller.ts ✓
- api-ventago/src/app/vendor-portal/vendor-settlements/vendor-settlements.service.ts ✓
- api-ventago/src/app/vendor-portal/vendor-settlements/vendor-settlements.controller.ts ✓
- api-ventago/src/app/vendor-portal/vendor-notifications/vendor-notifications.service.ts ✓
- api-ventago/src/app/vendor-portal/vendor-notifications/vendor-notifications.controller.ts ✓
- api-ventago/src/app/vendor-portal/vendor-portal.cron.ts ✓

Commits verified: 71cc701, ef1124c

TypeScript: `npx tsc --noEmit` passes with zero errors.
