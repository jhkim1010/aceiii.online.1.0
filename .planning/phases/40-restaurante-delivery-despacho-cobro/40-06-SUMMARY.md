---
phase: 40-restaurante-delivery-despacho-cobro
plan: 06
subsystem: api
tags: [nestjs, sequelize, mercadopago, webhook, minio, csv, restaurant-delivery, idempotency]

# Dependency graph
requires:
  - phase: 40-04
    provides: RestaurantDeliveryService + RestaurantDeliveryGateway + RestaurantDeliveryModule(exports) + qr intent linkage(pendingVentaId=sale.id)
  - phase: 40-03
    provides: RestaurantDelivery model + DeliveryStatus/PaymentMode enums + externalRef/saleId/settledAt columns
provides:
  - DeliveryPayoutCsvService — L1 payout CSV reconciliation (MinIO store + fixed-template parse + externalRef/amount exact-match → liquidado auto-confirm + flagged)
  - "POST /restaurant-delivery/payout/reconcile — multipart CSV upload endpoint (@Auth, FileInterceptor, storeId-scoped)"
  - MpWebhookService.autoCloseQrDelivery — additive post-commit QR delivery auto-close hook keyed on intent.pendingVentaId → delivery.saleId
  - MercadopagoModule imports forwardRef(RestaurantDeliveryModule) for delivery model + gateway DI
affects: [40-07/40-08 (rider settlement consumes liquidado state; frontend payout/board UI consumes reconcile result + auto-close cards)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Webhook side-effect isolation: QR delivery auto-close lives in the post-commit section, try/catch-guarded so it never throws into the Phase 29 webhook-200 invariant; critical wallet-credit TX untouched"
    - "Server-truth reconciliation: CSV amount matched against sales.total_amount (not a client field); exact equality via cent-rounded integer compare (no tolerance — SPEC out-of-scope)"
    - "Defensive CSV ingest: file type/size validated before parse, fixed header literal validated, malformed rows collected (never thrown) — T-40-20"

key-files:
  created:
    - api-ventago/src/app/restaurant-delivery/delivery-payout-csv.service.ts
    - api-ventago/src/app/restaurant-delivery/dto/payout-match.dto.ts
  modified:
    - api-ventago/src/app/restaurant-delivery/restaurant-delivery.controller.ts
    - api-ventago/src/app/restaurant-delivery/restaurant-delivery.module.ts
    - api-ventago/src/app/mercadopago/webhook/mp-webhook.service.ts
    - api-ventago/src/app/mercadopago/mercadopago.module.ts

key-decisions:
  - "QR auto-close keyed on intent.pendingVentaId (= delivery.saleId, set at intake in plan 04) because the intent-centric webhook never resolves a Sale by saleId — the linkage is intent → delivery, not webhook → sale"
  - "autoCloseQrDelivery placed in the existing post-commit block AFTER emitToTerminal, fully try/catch-guarded — webhook always returns 200 (Phase 29 invariant), wallet-credit critical TX is not touched"
  - "RestaurantDeliveryModule already imports MercadopagoModule; adding the reverse import (MercadopagoModule → RestaurantDeliveryModule) creates a cycle, resolved with forwardRef on BOTH sides"
  - "CSV expected amount = sales.total_amount (server truth), compared with cent-rounded integer equality to avoid float drift while preserving EXACT match (no tolerance)"
  - "Only conciliacion-status APP deliveries are flipped to liquidado (T-40-22 double-settle guard); already-liquidado rows are not re-matched"

requirements-completed: [REQ-8, REQ-9]

# Metrics
duration: ~5min
completed: 2026-06-16
---

# Phase 40 Plan 06: Delivery Payout CSV Reconciliation + MP QR Auto-Close Summary

**The two non-cash collection terminals: (REQ-9) a DeliveryPayoutCsvService that stores the original payout CSV in MinIO, validates the fixed `external_ref,amount` header, exact-matches each row to an APP delivery by externalRef + sales.total_amount, auto-confirms matches to Liquidado and flags the rest red; and (REQ-8) an additive, post-commit, try/catch-guarded MP webhook hook that auto-closes a `paymentMode=qr` delivery to Liquidado via `intent.pendingVentaId → delivery.saleId` without entering Por cobrar or cash settlement — with the existing wallet-credit TX, emitToTerminal, and retail/POS/mesa paths left byte-for-byte unchanged.**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-06-16T19:08:07Z
- **Completed:** 2026-06-16T19:13:31Z
- **Tasks:** 2
- **Files:** 6 (2 created, 4 modified)

## Accomplishments

### Task 1 — Payout CSV reconciliation (REQ-9, D-07/D-08)
- `DeliveryPayoutCsvService.reconcile(storeId, branchId, file)`:
  - **T-40-20 guards (pre-parse):** rejects missing file, files over 5MB, and non-text MIME types before any parsing.
  - **D-07:** stores the original CSV via `minioService.uploadFile(file, ` payout-{storeId}-{ts}.csv `)` for audit trail.
  - **D-08 fixed template:** validates the header row equals exactly `external_ref,amount` (whitespace-normalized) and rejects otherwise. `amount` parsed under the period-decimal contract via a strict `^-?\d+(\.\d+)?$` regex (no thousands separator, no currency symbol; no `eval`). Malformed/short rows are collected as `flagged` (`malformed_row`), never thrown.
  - **Matching:** for each row, `findOne({ storeId, externalRef, paymentMode: APP })` (T-40-21 IDOR scope). Expected amount = `sales.total_amount` (server truth) compared by cent-rounded integer equality (EXACT, no tolerance). Match + `status=conciliacion` → `{ status: LIQUIDADO, settledAt }` + board card emit. No match → `no_match`; amount differs → `amount_mismatch`; already-settled (non-conciliacion) → not re-matched (T-40-22).
  - Returns `{ matched, flagged, fileName }`.
- `dto/payout-match.dto.ts`: `PayoutReconcileResult` / `PayoutMatchedRow` / `PayoutFlaggedRow` + `PayoutFlagReason` (`no_match | amount_mismatch | malformed_row`).
- Controller: `@Post('payout/reconcile')` `@Auth()` `@UseInterceptors(FileInterceptor('file'))` → `csvService.reconcile(user.storeId, +branchId, file)`.
- Module: added `MinioModule` to imports + `DeliveryPayoutCsvService` to providers/exports.

### Task 2 — MP QR webhook auto-close (REQ-8, D-01)
- `MpWebhookService.autoCloseQrDelivery(intent)`: in the EXISTING post-commit `if (processedIntent)` block, AFTER `emitToTerminal('mercadopago:approved', ...)`, looks up `RestaurantDelivery` where `{ saleId: intent.pendingVentaId, paymentMode: QR }`. If found and not already `liquidado`/`cancelado`, sets `{ status: LIQUIDADO, settledAt }` and emits the updated board card. Non-delivery intents (POS/mesa/retail) → no-op.
- **Invariant preservation:** the whole hook is `try/catch`-guarded (logs, never throws) so the webhook still returns 200 (Phase 29). Verified via `git diff` that no `creditOnSale`, `emitToTerminal`, `intent.update`, `LOCK.UPDATE`, or `findByPk` line changed — the change is purely additive.
- DI: injected `@InjectModel(RestaurantDelivery)` + `RestaurantDeliveryGateway` into `MpWebhookService`; `mercadopago.module.ts` imports `forwardRef(() => RestaurantDeliveryModule)`.

## Task Commits

Each task committed atomically inside the api-ventago nested repo:

1. **Task 1: delivery payout CSV reconciliation service + endpoint + module wiring** — `f6d7ad1` (feat)
2. **Task 2: MP webhook QR delivery auto-close hook + module forwardRef** — `df81370` (feat)

## Decisions Made
- **Linkage is intent → delivery, not webhook → sale.** The Phase 29 webhook is intent-centric and never resolves a Sale by saleId. Plan 04 set `intent.pendingVentaId = sale.id = delivery.saleId`, so the hook queries the delivery directly by that key.
- **Bidirectional forwardRef.** RestaurantDeliveryModule already imported MercadopagoModule (for MpQrService). Adding MercadopagoModule → RestaurantDeliveryModule (for the model + gateway) closes a cycle, so `forwardRef` was applied on both module imports.
- **Server-truth amount.** CSV `amount` is matched against `sales.total_amount`, not any field stored on the CSV row alone, to keep the comparison authoritative. Cent-rounded integer compare avoids float drift while remaining an EXACT match.
- **Conciliacion-only flip.** Only APP deliveries in `conciliacion` are auto-confirmed; already-`liquidado` rows are excluded, preventing CSV re-upload double-settle (T-40-22).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking: TS compile] raw query typing required `QueryTypes`/`Transaction` from `sequelize`**
- **Found during:** Task 1 build
- **Issue:** Using `type: 'SELECT' as any` on `sequelize.query` produced `TS2322` (the overload inferred a `[undefined, number]` result tuple instead of the row array).
- **Fix:** imported `QueryTypes` + `Transaction` from `sequelize` and used `type: QueryTypes.SELECT` (matches the existing `restaurant-delivery.service.ts` raw-query pattern). Behavior identical.
- **Files modified:** delivery-payout-csv.service.ts
- **Commit:** f6d7ad1

**2. [Rule 3 - Blocking: DI cycle] changed `MercadopagoModule` import in RestaurantDeliveryModule to `forwardRef`**
- **Found during:** Task 1 module wiring (anticipating Task 2's reverse import)
- **Issue:** Task 2 adds `MercadopagoModule → RestaurantDeliveryModule`. RestaurantDeliveryModule already imported `MercadopagoModule` plainly; a plain import on both sides would fail NestJS module resolution with a circular-dependency error.
- **Fix:** wrapped `MercadopagoModule` in `forwardRef(() => MercadopagoModule)` in RestaurantDeliveryModule and `RestaurantDeliveryModule` in `forwardRef(() => RestaurantDeliveryModule)` in MercadopagoModule.
- **Files modified:** restaurant-delivery.module.ts (Task 1 commit), mercadopago.module.ts (Task 2 commit)
- **Commits:** f6d7ad1, df81370

## Issues Encountered
- Local dev DB lacks the `restaurant_deliveries` table (migrations 40-01/40-02/40-04 unapplied). Per the plan guardrails, no runtime DB smoke was performed; verification relied on `nest build` (DI graph resolves in both RestaurantDeliveryModule and MercadopagoModule) + the grep blocks + the no-regression `git diff` check on the webhook critical lines.

## Threat Surface
No new trust-boundary surface beyond the plan's `<threat_model>`. CSV upload validates type/size/header before parse and parses defensively (T-40-20); reconciliation is storeId-scoped (T-40-21); only conciliacion rows flip (T-40-22); the QR webhook hook acts only on an already-processed, approved intent post-commit and is try/catch-guarded so the webhook 200 invariant holds (T-40-23/T-40-24). MinIO stores the original payout CSV for audit (D-07).

## Retail / POS / Mesa No-Regression
The MP webhook change is post-commit, additive, and fully guarded. `git diff` confirms zero edits to the critical transaction, `creditOnSale`, `emitToTerminal`, `intent.update`, or the SELECT-FOR-UPDATE/`findByPk` idempotency lines. Non-delivery intents short-circuit (`!delivery → return`), so existing retail/POS/mesa QR flows are untouched.

## User Setup Required
None for this plan. (Operator must apply migrations 40-01/40-02/40-04 to dev/prod DB per the standard psql runbook before runtime use — Wave 1's artifact. MinIO env vars already provisioned for existing logo upload.)

## Next Phase Readiness
- Plans 40-07/40-08 (rider settlement + frontend) consume the `liquidado`/`settledAt` state produced by both paths and the `POST /restaurant-delivery/payout/reconcile` `{ matched, flagged, fileName }` result for the payout UI (matched green / flagged red).

## Self-Check: PASSED

- FOUND: api-ventago/src/app/restaurant-delivery/delivery-payout-csv.service.ts
- FOUND: api-ventago/src/app/restaurant-delivery/dto/payout-match.dto.ts
- FOUND: commit f6d7ad1 (Task 1)
- FOUND: commit df81370 (Task 2)
- nest build: PASSED (exit 0, no errors)
- both task verify grep blocks: PASS
- webhook critical-line no-regression git diff: PASS (additive only)

---
*Phase: 40-restaurante-delivery-despacho-cobro*
*Completed: 2026-06-16*
