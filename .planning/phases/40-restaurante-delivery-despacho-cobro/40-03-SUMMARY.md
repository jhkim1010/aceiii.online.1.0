---
phase: 40-restaurante-delivery-despacho-cobro
plan: 03
subsystem: api
tags: [sequelize, socket.io, jwt, websocket, postgres, restaurant-delivery]

# Dependency graph
requires:
  - phase: 40-restaurante-delivery-despacho-cobro (Wave 1, plan 01/02)
    provides: restaurant_deliveries table + chk_rd_status/tipo/canal/payment_mode CHECK constraints
provides:
  - RestaurantDelivery Sequelize model (status/tipo/canal/paymentMode enums mirrored to DB CHECK)
  - DeliveryStatus/DeliveryTipo/DeliveryCanal/PaymentMode exported enums (status source of truth)
  - Sale 1:1 BelongsTo (constraints:false, cyclic-FK avoidance)
  - /restaurant Socket.io gateway (browser JWT auth + branch:{id} room authorization + card emit)
affects: [40-04 (restaurant-delivery service/module wiring), 40-05 (DeliveryBoard frontend socket subscription)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Browser-JWT Socket.io gateway (verifyAsync on handshake.auth.token) — first non-API-Key WS auth in codebase"
    - "Socket.io room authorization by store ownership (branch belongs to authenticated user's store)"

key-files:
  created:
    - api-ventago/src/app/restaurant-delivery/restaurant-delivery.model.ts
    - api-ventago/src/app/restaurant-delivery/restaurant-delivery.gateway.ts
  modified: []

key-decisions:
  - "Gateway authenticates browser clients via JwtService.verifyAsync(JWT_SECRET_KEY), not Electron API-Key (D-03)"
  - "Branch-room join authorized against Branch.storeId == JWT storeId before client.join (T-40-09 IDOR mitigation)"
  - "emitDeliveryUpdated pushes card-level payload only (no full reload) — pool saving (D-04)"

patterns-established:
  - "Browser-JWT Socket.io gateway: verify handshake.auth.token in handleConnection, disconnect on failure"
  - "Store-scoped room authorization for WebSocket subscriptions"

requirements-completed: [REQ-2, REQ-6]

# Metrics
duration: ~7min
completed: 2026-06-16
---

# Phase 40 Plan 03: RestaurantDelivery Model + /restaurant Gateway Summary

**RestaurantDelivery Sequelize model with status/tipo/canal/paymentMode enums mirrored verbatim to DB CHECK strings, plus a new /restaurant Socket.io gateway that authenticates browser board clients by JWT and pushes card-level delivery updates to store-authorized branch:{id} rooms.**

## Performance

- **Duration:** ~7 min
- **Started:** 2026-06-16T17:16:00Z
- **Completed:** 2026-06-16T17:23:04Z
- **Tasks:** 2
- **Files created:** 2

## Accomplishments
- RestaurantDelivery model maps the existing `restaurant_deliveries` table (Wave 1) — no new migration. All four enums (`DeliveryStatus` 9 values, `DeliveryTipo`, `DeliveryCanal`, `PaymentMode`) exported with string values matching the DB CHECK constraints (`chk_rd_status` etc.) verbatim.
- Sale 1:1 `BelongsTo` declared with `constraints:false` (cyclic-FK avoidance, mirroring sales.model.ts `tableId` pattern); `saleId` UNIQUE enforced by the Wave 1 partial index.
- New `/restaurant` namespace gateway: `handleConnection` verifies `handshake.auth.token` via `JwtService.verifyAsync` and stores `storeId` on `client.data`; unauthenticated clients are disconnected (T-40-08).
- `join` handler authorizes the requested `branchId` against the authenticated user's store (Branch.storeId lookup) before `client.join(branch:{id})` — prevents cross-store card leakage (T-40-09 IDOR).
- `emitDeliveryUpdated(branchId, card)` emits `delivery_updated` card-level payloads to the branch room (D-04, no full reload).
- `/print-agent` gateway and `emitPrintTemp` comanda channel left untouched (additive — retail not regressed).

## Task Commits

Each task was committed atomically inside the api-ventago nested repo:

1. **Task 1: RestaurantDelivery model with enums mirrored to DB CHECK** - `ceaada7` (feat)
2. **Task 2: /restaurant Socket.io gateway with JWT auth + branch room emit** - `af82cfc` (feat)

## Files Created/Modified
- `api-ventago/src/app/restaurant-delivery/restaurant-delivery.model.ts` - RestaurantDelivery model + DeliveryStatus/DeliveryTipo/DeliveryCanal/PaymentMode enums; Sale 1:1 BelongsTo constraints:false; explicit field: snake_case columns; JSONB metadata; timestamp columns.
- `api-ventago/src/app/restaurant-delivery/restaurant-delivery.gateway.ts` - /restaurant Socket.io gateway: JWT handleConnection auth, store-scoped branch-room join authorization, emitDeliveryUpdated card emit.

## Decisions Made
- **JWT verification via JwtService:** Used `@nestjs/jwt` `verifyAsync` with `process.env.JWT_SECRET_KEY` (same secret/strategy as the HTTP JWT path) rather than re-implementing token parsing. The JwtModule that provides `JwtService` will be wired into the restaurant-delivery module in plan 04 (module/DI wiring is out of this plan's scope per the plan objective).
- **Branch authorization via Branch model:** Injected the `Branch` model and authorize `join` by `findOne({ id: branchId, storeId })`. SequelizeModule.forFeature([Branch, RestaurantDelivery]) will be added in plan 04's module.
- **Card-level emit only:** `emitDeliveryUpdated` emits a caller-supplied `card` payload; the service (plan 04) builds the card (`toCard`) so the gateway stays a thin transport (D-04).

## Deviations from Plan

None - plan executed exactly as written. Both tasks' grep verify blocks passed and `npm run build` (nest build) succeeded with no errors.

## Issues Encountered
None. Note: the gateway depends on `JwtService` and the `Branch` model via DI; these providers are supplied by the restaurant-delivery module created in plan 04 (explicitly that plan's scope per the plan's objective — "module/app.module wiring is plan 04"). The standalone `nest build` compiles cleanly because TypeScript resolves the imports; runtime DI wiring lands in plan 04.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Model + gateway contracts ready for plan 04 (restaurant-delivery.service.ts + module) to inject and emit against.
- Plan 04 must: add `RestaurantDelivery` + `Branch` to `SequelizeModule.forFeature`, import `JwtModule` (or AuthModule's JwtModule export), declare `RestaurantDeliveryGateway` as a provider, and register the module in app.module.
- Plan 05 (DeliveryBoard frontend) subscribes to `/restaurant`, emits `join` with `{ branchId }`, listens for `delivery_updated`.

## Self-Check: PASSED

- FOUND: api-ventago/src/app/restaurant-delivery/restaurant-delivery.model.ts
- FOUND: api-ventago/src/app/restaurant-delivery/restaurant-delivery.gateway.ts
- FOUND: commit ceaada7 (Task 1)
- FOUND: commit af82cfc (Task 2)
- FOUND: 40-03-SUMMARY.md
- nest build: PASSED (no errors)

---
*Phase: 40-restaurante-delivery-despacho-cobro*
*Completed: 2026-06-16*
