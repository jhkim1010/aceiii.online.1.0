---
phase: 40-restaurante-delivery-despacho-cobro
plan: 02
subsystem: api
tags: [nestjs, sequelize, repartidor, delivery, restaurant, multitenant, idor]

# Dependency graph
requires:
  - phase: 40-01
    provides: repartidores table (SERIAL id, store_id FK, name, phone, is_active, timestamps)
  - phase: 39
    provides: restaurant-tables module (store-scoped CRUD + findScoped IDOR pattern analog)
provides:
  - Repartidor Sequelize model mapped to repartidores table (explicit field: snake_case)
  - RepartidoresService — store-scoped CRUD with soft-deactivate (no hard delete)
  - findByStore(storeId, activeOnly) — activeOnly=true feeds dispatch dropdown (active riders only)
  - RepartidoresController — /repartidores REST (GET list / POST create / PUT :id), @Auth() + storeId from JWT
  - RepartidoresModule exporting RepartidoresService + SequelizeModule for downstream consumption (plan 04 RiderSettlement)
affects: [40-04-rider-settlement, 40-05-dispatch-board, 40-restaurante-delivery]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Store-scoped CRUD via findScoped(id, storeId) → NotFound on cross-store id (IDOR guard, cloned from restaurant-tables)"
    - "Soft-deactivate (isActive=false) instead of destroy — preserves settlement FK history"
    - "activeOnly flag on findByStore to filter dispatch-eligible riders without a second method"

key-files:
  created:
    - api-ventago/src/app/repartidores/repartidores.model.ts
    - api-ventago/src/app/repartidores/dto/repartidor.dto.ts
    - api-ventago/src/app/repartidores/repartidores.service.ts
    - api-ventago/src/app/repartidores/repartidores.service.spec.ts
    - api-ventago/src/app/repartidores/repartidores.controller.ts
    - api-ventago/src/app/repartidores/repartidores.module.ts
  modified:
    - api-ventago/src/app.module.ts

key-decisions:
  - "No destroy() on RepartidoresService — REQ-1 mandates soft-deactivate to preserve rider_settlements history"
  - "storeId always derived from @GetUser() JWT, never request body (IDOR mitigation T-40-05)"
  - "findByStore(storeId, true) is the single source for active-rider dispatch dropdown — no separate findActive method"

patterns-established:
  - "Repartidor module is a verbatim store-scoped clone of restaurant-tables with isActive soft-toggle replacing occupancy logic"

requirements-completed: [REQ-1]

# Metrics
duration: 12min
completed: 2026-06-16
---

# Phase 40 Plan 02: Repartidor (Rider) Backend Module Summary

**Store-scoped Repartidor CRUD module (model + DTO + service + controller + module) with soft-deactivate and findScoped IDOR guard, registered in app.module — the rider registry that feeds the dispatch dropdown and settlement units.**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-06-16
- **Completed:** 2026-06-16
- **Tasks:** 2
- **Files modified:** 7 (6 created, 1 modified)

## Accomplishments
- Repartidor Sequelize model bound to the existing 40-01 `repartidores` table (explicit `field:` snake_case per Phase 39 convention; `is_active` soft-toggle)
- RepartidoresService with store-scoped `create` / `findByStore` / `update`, `findScoped` IDOR guard, and NO hard delete (soft-deactivate only — preserves settlement history)
- `findByStore(storeId, activeOnly)` — `activeOnly=true` returns only `isActive=true` riders (dispatch dropdown source)
- RepartidoresController under `/repartidores` with `@Auth()` on every route and `storeId` always taken from JWT (IDOR-safe)
- RepartidoresModule exports `RepartidoresService` + `SequelizeModule` so plan 04 (RiderSettlement) can consume Repartidor
- Registered `RepartidoresModule` in `api-ventago/src/app.module.ts`; `nest build` passes; 5/5 service unit tests green

## Task Commits

Each task committed atomically inside api-ventago:

1. **Task 1 (RED): failing RepartidoresService test + model + DTO + service skeleton** - `fcda735` (test)
2. **Task 1 (GREEN): implement Repartidor store-scoped CRUD service** - `b7522df` (feat)
3. **Task 2: Repartidor controller + module + app.module registration** - `f8d206f` (feat)

_Task 1 used TDD (test → feat). No refactor commit needed — implementation was clean on first GREEN._

## Files Created/Modified
- `api-ventago/src/app/repartidores/repartidores.model.ts` - Repartidor model, `@Table('repartidores')`, store_id FK + BelongsTo Store, `field: 'is_active'` boolean default true
- `api-ventago/src/app/repartidores/dto/repartidor.dto.ts` - CreateRepartidorDto (name/phone) + UpdateRepartidorDto (name/phone/isActive optional)
- `api-ventago/src/app/repartidores/repartidores.service.ts` - store-scoped create/findByStore/update + private findScoped IDOR guard; soft-deactivate, no destroy
- `api-ventago/src/app/repartidores/repartidores.service.spec.ts` - 5 unit tests (storeId injection, single-SELECT no JOIN, activeOnly filter, cross-store NotFound, soft-deactivate no-destroy)
- `api-ventago/src/app/repartidores/repartidores.controller.ts` - `@Controller('repartidores')`, @Auth() routes, storeId from @GetUser
- `api-ventago/src/app/repartidores/repartidores.module.ts` - SequelizeModule.forFeature([Repartidor]), exports service + SequelizeModule
- `api-ventago/src/app.module.ts` - import + register RepartidoresModule alongside RestaurantTablesModule

## Decisions Made
- **Soft-deactivate only (no destroy):** REQ-1 requires deactivation to preserve `rider_settlements` history; `update({isActive:false})` is the deactivation path. A test asserts `destroy` is never called.
- **storeId from JWT only:** mitigates IDOR (threat T-40-05/T-40-06); every controller route is `@Auth()` and passes `user.storeId` to the service.
- **activeOnly flag, not a second method:** `findByStore(storeId, true)` filters dispatch-eligible riders, keeping the service surface minimal.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- The Task 1 verify block greps `! grep -q "destroy"` against the service file. The initial doc-comment contained the literal word "destroy" ("삭제(destroy) 미제공"), which would fail the gate. Rephrased the comment to "하드 삭제 미제공" so the assertion (no `destroy` anywhere in the service) holds. Behavior unchanged.
- ESLint reports `@typescript-eslint/no-unsafe-*` and prettier diffs on the new files, but the in-production analog (`restaurant-tables.service.ts` + spec) produces the identical error profile, and the real build gate (`nest build`) passes cleanly. The named CLAUDE.md build-blocker rules (newline-before-return / lines-around-comment / no-unused-vars) are all satisfied. No action needed.

## User Setup Required
None - no external service configuration required. (The `repartidores` table migration 40-01 must be applied to the target DB by the operator per the standard SSH psql runbook; that is Wave 1's artifact, not this plan's.)

## Next Phase Readiness
- Repartidor registry is ready. Plan 04 (RiderSettlement) can import `RepartidoresModule` to consume the `Repartidor` model + service.
- Plan 05 (dispatch board) can call `findByStore(storeId, true)` for the active-rider assignment dropdown.
- Frontend (settings > Repartidores card, gated on `use_restaurant_mode=true`) consumes `/repartidores` REST — to be built in the frontend plan.

## Self-Check: PASSED

- All 6 created module files present on disk
- 40-02-SUMMARY.md present
- All 3 task commits (fcda735 test, b7522df feat, f8d206f feat) found in api-ventago git log
- TDD gate sequence valid: test(RED) → feat(GREEN) → feat(controller/module)
- `nest build` exit 0; 5/5 service unit tests green

---
*Phase: 40-restaurante-delivery-despacho-cobro*
*Completed: 2026-06-16*
