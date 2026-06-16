---
phase: 40-restaurante-delivery-despacho-cobro
plan: 05
subsystem: api
tags: [nestjs, sequelize, transaction, box-operation, rider-settlement, cash, idor]

# Dependency graph
requires:
  - phase: 40-02
    provides: Repartidor model/service (rider registry — settlement unit)
  - phase: 40-04
    provides: RestaurantDelivery model + DeliveryStatus.{POR_COBRAR,LIQUIDADO} + PaymentMode.EFECTIVO; efectivo→por_cobrar receivable gap this plan closes
  - phase: 40-01
    provides: rider_settlements + rider_settlement_items tables (migrations, unapplied locally)
provides:
  - RiderSettlement + RiderSettlementItem models (parent/child, HasMany)
  - RiderSettlementService — buildSettlement (efectivo+por_cobrar aggregation, expected/received/difference) + registerRendition (ONE aggregated box movement, D-05; blocks without open caja, D-06; rendido→liquidado)
  - RiderSettlementController — /rider-settlement REST (build/:id/:id/rendition), @Auth() storeId-scoped
  - RiderSettlementModule — DI wiring (BoxOperationModule + RepartidoresModule), registered in app.module
affects: [40-06 (MP webhook hook / settlement consumers), 40-07/40-08 (frontend RiderSettlementView consumes /rider-settlement)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Money-path terminus: efectivo por_cobrar deliveries aggregate into ONE box (caja) movement at rendición (D-05) — never per-order, keeps caja clean and matches the shift-close model"
    - "STRICTER than Phase 39: registerRendition THROWS BadRequestException if no open cashRegister (closingTime=null) — cash must reconcile with control-de-caja (D-06), unlike Phase 39 payment which skips the box-op"
    - "rendido flag idempotency: items flagged rendido=true; por_cobrar→liquidado transition + the status filter exclude already-settled orders from re-credit (T-40-16)"
    - "Cash-only settlement scope: selection strictly filters paymentMode=efectivo + status=por_cobrar so qr/app orders never enter a cash settlement (T-40-19 / REQ-7 AC③)"

key-files:
  created:
    - api-ventago/src/app/rider-settlement/rider-settlement.model.ts
    - api-ventago/src/app/rider-settlement/dto/rider-settlement.dto.ts
    - api-ventago/src/app/rider-settlement/rider-settlement.service.ts
    - api-ventago/src/app/rider-settlement/rider-settlement.service.spec.ts
    - api-ventago/src/app/rider-settlement/rider-settlement.controller.ts
    - api-ventago/src/app/rider-settlement/rider-settlement.module.ts
  modified:
    - api-ventago/src/app.module.ts

key-decisions:
  - "ONE aggregated box movement per rendición (D-05): boxOperationService.addOperation called exactly once with amount=Σ rendido item amounts, type='venta', executionType='automatico', description=Rendición repartidor #N. grep count of addOperation( = 1."
  - "Block (not skip) without open caja (D-06): cashRegister findOne({userId, closingTime:null}); null → throw BadRequestException('Abrí la caja antes de registrar la rendición'). Phase 39's recordBoxOperation skips silently — delivery settlement is the control terminus so it must hard-block to keep control-de-caja reconciled."
  - "Partial settlement: dto.itemIds subset flips only those items rendido/liquidado; settlement status = all rendido ? 'closed' : 'partial'. closedAt set only when closed."
  - "find-or-create open settlement keyed on {storeId, repartidorId, status in (open,partial)}; existing items deduped by restaurantDeliveryId so re-running buildSettlement does not duplicate rows."

patterns-established:
  - "Settlement amount sourced from delivery.sale.totalAmount via include association (no N+1 — single scoped findAll with sale join)"

requirements-completed: [REQ-3, REQ-7]

# Metrics
duration: ~5min
completed: 2026-06-16
---

# Phase 40 Plan 05: Rider Settlement Backend Summary

**RiderSettlement is the money-path terminus of the delivery control invariant — buildSettlement aggregates a rider's efectivo + por_cobrar deliveries (qr/app strictly excluded) into a parent settlement with expected/received/difference cash, and registerRendition records ONE aggregated box (caja) movement via BoxOperationService.addOperation (D-05), hard-blocking with BadRequestException when no open cashRegister exists (D-06, stricter than Phase 39), then flips rendido orders to liquidado inside a single transaction — controller and module wired and registered in app.module with nest build green and 3/3 service unit tests passing.**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-06-16T19:00:17Z
- **Completed:** 2026-06-16T19:05:09Z
- **Tasks:** 2 (Task 2 via TDD)
- **Files:** 7 (6 created, 1 modified)

## Accomplishments
- `RiderSettlement` (parent) + `RiderSettlementItem` (child) models: store/repartidor scope, `box_session_id` (→cash_registers.id), `expected_cash`/`received_cash`/`difference` FLOAT, `status` (open|partial|closed), `note`, `opened_at`/`closed_at`, `@HasMany items`. Child: `settlement_id` FK + `@BelongsTo`, `restaurant_delivery_id`, `amount`, `rendido` BOOLEAN. All columns explicit `field:` snake_case (Phase 39/40 model convention).
- DTOs: `BuildSettlementDto { @IsInt repartidorId }`, `RegisterRenditionDto { @IsOptional @IsArray itemIds?; @IsOptional @IsString note? }`.
- `buildSettlement(storeId, repartidorId)` (REQ-3): single TX; find-or-create open settlement; single scoped `findAll` on RestaurantDelivery filtered `paymentMode=EFECTIVO + status=POR_COBRAR` (qr/app excluded, REQ-7 AC③) with `sale` include for the amount; dedupes existing items by `restaurantDeliveryId`; `expectedCash = Σ amount`; returns settlement with items.
- `registerRendition(storeId, userId, settlementId, dto)` (REQ-7, D-05/D-06): single TX; storeId-scoped findOne (IDOR, T-40-18); **D-06** `cashRegister findOne({ userId, closingTime: null })` → null throws `BadRequestException('Abrí la caja antes de registrar la rendición')`; determines rendido items (dto.itemIds subset or all); **D-05** exactly ONE `boxOperationService.addOperation({ cashRegisterId, userId, terminalId, amount: total, type:'venta', executionType:'automatico', description })`; flags items `rendido=true` (T-40-16); updates rendido deliveries → `status=LIQUIDADO, settledAt`; settlement `receivedCash=total, difference=expected-total, status=closed|partial, boxSessionId, closedAt`.
- `get(storeId, id)`: storeId-scoped findOne with items (NotFound = IDOR guard).
- Controller `@Controller('rider-settlement')` with `@Auth()` on every route: `POST build`, `GET :id`, `POST :id/rendition`; storeId/userId from `@GetUser()`.
- Module imports `SequelizeModule.forFeature([RiderSettlement, RiderSettlementItem, RestaurantDelivery, CashRegister])` + `BoxOperationModule` (exports BoxOperationService) + `RepartidoresModule`; registered in app.module.

## Task Commits

Each task committed atomically inside the api-ventago nested repo:

1. **Task 1: RiderSettlement + RiderSettlementItem models + DTOs** — `1df60bd` (feat)
2. **Task 2 (RED): failing RiderSettlementService spec** — `4eba497` (test)
3. **Task 2 (GREEN): service + controller + module + app.module** — `c234128` (feat)

_Task 2 used TDD (test → feat). No refactor commit needed — implementation passed on first GREEN after a test-mock fidelity fix (see Deviations)._

## Decisions Made
- **ONE aggregated box movement (D-05):** the single `addOperation` call site (grep count = 1) credits the sum of rendido item amounts, matching the shift-close model and avoiding many small per-order caja entries.
- **Hard block without open caja (D-06):** unlike Phase 39 `recordBoxOperation` which skips the box-op when no register is open, delivery settlement throws — cash cannot be settled outside an open caja session, guaranteeing control-de-caja reconciliation (T-40-17).
- **Partial settlement support:** `dto.itemIds` flips only the named items; settlement status resolves to `closed` only when every item is rendido, else `partial` (closedAt set only on close).
- **Amount from delivery.sale.totalAmount:** sourced via `include` association on the single scoped findAll — no N+1, honoring the pool rule.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Test fixture] post-update item state needed to be mocked for the closed-path assertion**
- **Found during:** Task 2 GREEN (first jest run)
- **Issue:** The service flags items `rendido=true` via `itemModel.update`, then re-reads all items (step 7) to decide closed vs partial. The unit-test mock returned the same stale `rendido:false` row on every `findAll`, so the closed-path assertion (`status:'closed'`) failed even though the service logic was correct.
- **Fix:** Made the mock realistic — `findAll` returns `rendido:false` on the first call (rendido-target determination) and `rendido:true` thereafter (the post-update close judgment), mirroring the real DB round-trip. No service change; the production code computes `allRendido` from the freshly-read rows correctly.
- **Files modified:** rider-settlement.service.spec.ts
- **Commit:** c234128

## Issues Encountered
- The local dev DB does not have the `rider_settlements` / `rider_settlement_items` tables (migration 40-01 unapplied). Per the plan's guardrails, runtime DB smoke tests were intentionally skipped; verification relied on `nest build` (DI graph for BoxOperationService + CashRegister resolves) + the grep blocks + 3 mocked unit tests.

## Threat Surface
No new trust-boundary surface beyond the plan's `<threat_model>`. The new `/rider-settlement` REST routes are all `@Auth()` + storeId-from-JWT (T-40-18); the rendition is one TX with exactly one aggregated addOperation and rendido-flag idempotency (T-40-16); cash cannot bypass an open caja (T-40-17); settlement selection strictly filters efectivo+por_cobrar so qr/app never enter the cash flow (T-40-19).

## User Setup Required
None for this plan. (Operator must apply migration 40-01 — rider_settlements + rider_settlement_items tables — to dev/prod DB per the standard psql runbook before runtime use; this is Wave 1's artifact.)

## Next Phase Readiness
- Plan 06/07/08 consumers can import RiderSettlementModule (exports RiderSettlementService). The frontend RiderSettlementView consumes `POST /rider-settlement/build`, `GET /rider-settlement/:id`, `POST /rider-settlement/:id/rendition`.
- The por_cobrar → liquidado transition is now the closing half of the receivable gap opened by plan 04's `settleSaleOnDelivery`.

## Self-Check: PASSED

- FOUND: api-ventago/src/app/rider-settlement/rider-settlement.model.ts
- FOUND: api-ventago/src/app/rider-settlement/dto/rider-settlement.dto.ts
- FOUND: api-ventago/src/app/rider-settlement/rider-settlement.service.ts
- FOUND: api-ventago/src/app/rider-settlement/rider-settlement.service.spec.ts
- FOUND: api-ventago/src/app/rider-settlement/rider-settlement.controller.ts
- FOUND: api-ventago/src/app/rider-settlement/rider-settlement.module.ts
- FOUND: commit 1df60bd (Task 1)
- FOUND: commit 4eba497 (Task 2 RED)
- FOUND: commit c234128 (Task 2 GREEN)
- TDD gate sequence valid: feat(models) → test(RED) → feat(GREEN service/controller/module)
- nest build: PASSED (exit 0, no errors); 3/3 service unit tests green
- both task verify grep blocks: PASS; single addOperation call site confirmed (grep -c = 1)

---
*Phase: 40-restaurante-delivery-despacho-cobro*
*Completed: 2026-06-16*
