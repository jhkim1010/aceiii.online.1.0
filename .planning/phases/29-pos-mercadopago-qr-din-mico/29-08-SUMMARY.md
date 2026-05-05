---
phase: 29-pos-mercadopago-qr-din-mico
plan: 08
subsystem: payments
tags: [mercadopago, wallet, transfer, cron, sequelize, transactions, oauth-refresh]

# Dependency graph
requires:
  - phase: 29
    provides: "Plan 02b mp_* models, Plan 03 MpOAuthService.refreshAccount, Plan 05 MpWalletService.computeBalance, Plan 04 mp_payment_intents pending state"
provides:
  - MpTransferService — atomic MP wallet → physical box transfer (single Sequelize TX, dual SELECT FOR UPDATE locks)
  - TransferMpToCashDto — class-validator DTO (positive amount, integer ids)
  - MpWalletController — 3 REST endpoints (list wallets, list movements, POST transfer)
  - MpWalletReconcileCron — daily 03:00 wallet balance drift detection + correction + stale-intent sweep
  - MpTokenRefreshCron — daily 04:00 D-7 OAuth token pre-emptive refresh
  - Cross-store transfer rejection (wallet.storeId === box.storeId enforcement)
  - Stale-intent cleanup path for Plan 04 createIntent rollbacks (status='expired')
affects: [29-08b, 29-09, future-cash-control-ui, mp-reconciliation-monitoring]

# Tech tracking
tech-stack:
  added: []  # 모든 deps Plan 02b/03/05 에서 이미 설치 (@nestjs/schedule, sequelize-typescript, class-validator)
  patterns:
    - "Multi-row SELECT FOR UPDATE in single Sequelize TX (wallet + box atomic lock — Pattern 6)"
    - "Cross-table balance flow: mp_movements ↔ mp_transfers ↔ box_operations linked via FK back-fill"
    - "Cron job pattern: separate small async methods (reconcileWallets / sweepStaleIntents) for testability"
    - "OAuth token rotation in cron uses MpOAuthService.refreshAccount (Pitfall 2 — both tokens re-saved)"
    - "Auth gate via @Auth(admin, superadmin, gerente) — vendedor JWT cannot reach endpoint (T-29-vendedor-bypass)"

key-files:
  created:
    - api-ventago/src/app/mercadopago/wallet/mp-transfer.service.ts
    - api-ventago/src/app/mercadopago/wallet/mp-transfer.service.spec.ts
    - api-ventago/src/app/mercadopago/wallet/mp-wallet.controller.ts
    - api-ventago/src/app/mercadopago/dto/transfer-mp-to-cash.dto.ts
    - api-ventago/src/app/mercadopago/cron/mp-wallet-reconcile.cron.ts
    - api-ventago/src/app/mercadopago/cron/mp-wallet-reconcile.cron.spec.ts
    - api-ventago/src/app/mercadopago/cron/mp-token-refresh.cron.ts
    - api-ventago/src/app/mercadopago/cron/mp-token-refresh.cron.spec.ts
  modified:
    - api-ventago/src/app/mercadopago/mercadopago.module.ts

key-decisions:
  - "Box balance updated via box_operations INSERT (executionType='automatico') tied to OPEN cash_register, NOT direct box.balance UPDATE — Box has no balance column; existing system computes balance from cash_register + box_operations (PATTERNS analog: cashRegister.service.ts autoCloseAndReopen retiro/ingreso pattern)"
  - "Transfer rejects with code BOX_CLOSED if no open cash_register exists for target box (deviation Rule 2 — required for correctness; closed caja cannot receive funds)"
  - "MpTransferService returns boxBalanceAfter=0 placeholder; UI calls separate box.service.findAllByStorePaginated for canonical balance (avoids double computation in TX)"
  - "Stale-intent sweep uses Op.lt + new Date() (not raw SQL) — leverages Sequelize update affectedCount return shape"
  - "MpTokenRefreshCron delegates token rotation to existing MpOAuthService.refreshAccount (single source of truth — same TX wraps access+refresh re-save per Pitfall 2)"
  - "Movements pagination capped at limit=100 (CLAUDE.md performance rule pageSize ≤ 50 is for frontend; backend limit cap defends against runaway clients)"

patterns-established:
  - "Atomic cross-aggregate transfer: lock both source (mp_wallets) + destination (box) before any mutation"
  - "Cron split into testable async methods + master @Cron orchestrator (avoids stub clock in tests)"
  - "Per-iteration try/catch in cron loops — one failure does not abort whole batch"

requirements-completed:
  - MP-POS-01

# Metrics
duration: 18 min
completed: 2026-05-06
---

# Phase 29 Plan 08: Caja MP Backend Operations Summary

**Atomic MP→cash transfer service with dual-row LOCK + 2 daily cron jobs (wallet drift reconcile + stale-intent sweep + D-7 OAuth token refresh)**

## Performance

- **Duration:** 18 min
- **Started:** 2026-05-05T14:52:53Z
- **Completed:** 2026-05-05T15:10:54Z
- **Tasks:** 2
- **Files created:** 8
- **Files modified:** 1

## Accomplishments

- **MpTransferService**: Single Sequelize TX with `lock: t.LOCK.UPDATE` on both `mp_wallets` and `box` rows. Inserts `mp_movements (transfer_out)` + `mp_transfers` audit row + `box_operations (ingreso, automatico)` tied to open `cash_register`, then back-fills `mp_movements.transfer_id` and decrements `mp_wallets.balance`. Insufficient balance throws `BadRequestException` with code `MP_INSUFFICIENT_BALANCE`.
- **MpWalletController**: 3 endpoints (`GET /mercadopago/wallets`, `GET /mercadopago/wallets/:walletId/movements`, `POST /mercadopago/transfers`) gated by `@Auth(admin, superadmin, gerente)`. POST transfer wears `@Audit(entityType='mp_transfer', action='create')` for compliance log.
- **MpWalletReconcileCron** (daily 03:00): Recomputes each wallet balance via `MpWalletService.computeBalance` and corrects drift > 0.01 in cache. Also sweeps `mp_payment_intents` rows with `status='pending'` and `expires_at < NOW()` → `status='expired'` (cleanup path for Plan 04 createIntent rollbacks + abandoned QR sessions).
- **MpTokenRefreshCron** (daily 04:00): Pre-emptively refreshes OAuth tokens for `mp_accounts` where `expires_at < NOW + 7 days` and `disconnected_at IS NULL`. Delegates to `MpOAuthService.refreshAccount` (which atomically re-saves both refresh + access tokens per RESEARCH §Pitfall 2). On refresh failure, sets `disconnected_at` so frontend can prompt re-OAuth.
- **Threat mitigations**: T-29-double-spend (dual SELECT FOR UPDATE), T-29-05 cross-store (storeId equality assertion), T-29-balance-drift (nightly reconcile), T-29-stale-intents (sweep), T-29-refresh-token-loss (cron + delegated rotation), T-29-vendedor-bypass (backend role gate).
- **Test coverage growth**: 60 → 71 mercadopago tests (11 new across MpTransferService + 2 cron specs).

## Task Commits

Each task was committed atomically:

1. **Task 1 RED — Failing MpTransferService spec + DTO** — `57b6461` (test, TDD red phase)
2. **Task 1 GREEN — MpTransferService atomic transfer implementation** — `0f1d3db` (feat, TDD green phase, 6/6 tests pass)
3. **Task 2 — MpWalletController + 2 cron jobs + module wiring** — `4bf6c3d` (feat, 5 new files + module update)

## Files Created/Modified

### Created (8)
- `api-ventago/src/app/mercadopago/dto/transfer-mp-to-cash.dto.ts` — class-validator DTO (Min(0.01) on amount; required mpWalletId, targetBoxId; optional note)
- `api-ventago/src/app/mercadopago/wallet/mp-transfer.service.ts` — atomic transfer service (191 lines, single TX, dual LOCK, 8-step flow)
- `api-ventago/src/app/mercadopago/wallet/mp-transfer.service.spec.ts` — 6 unit tests (happy + 5 failure modes)
- `api-ventago/src/app/mercadopago/wallet/mp-wallet.controller.ts` — 3 REST endpoints with @Auth + @Audit + ParseIntPipe
- `api-ventago/src/app/mercadopago/cron/mp-wallet-reconcile.cron.ts` — daily 03:00 cron (drift correction + stale-intent sweep)
- `api-ventago/src/app/mercadopago/cron/mp-wallet-reconcile.cron.spec.ts` — 5 unit tests (drift detection, tolerance, per-wallet error isolation, sweep success/failure)
- `api-ventago/src/app/mercadopago/cron/mp-token-refresh.cron.ts` — daily 04:00 cron (D-7 token refresh + disconnected_at on failure)
- `api-ventago/src/app/mercadopago/cron/mp-token-refresh.cron.spec.ts` — 4 unit tests (query filter, success counting, failure marks disconnected_at, batch isolation)

### Modified (1)
- `api-ventago/src/app/mercadopago/mercadopago.module.ts` — Added Box/BoxOperation/CashRegister to SequelizeModule.forFeature; registered MpWalletController; registered MpTransferService + 2 crons in providers; exported MpTransferService

## Decisions Made

1. **Box balance via box_operations, not direct UPDATE** — The Box model has no `balance` column; existing system computes balance from `SUM(cash_register.initialAmount) + SUM(ingreso/venta) - SUM(gasto/retiro)`. Plan instruction "UPDATE box.balance += amount" was interpreted as INSERT box_operations (ingreso) tied to the open cash_register, matching existing patterns in `cashRegister.service.ts` autoCloseAndReopen.
2. **BOX_CLOSED gate (Rule 2 deviation)** — If target box has no open cash_register, transfer rejects with `BadRequestException(code='BOX_CLOSED')`. Without this, INSERT into box_operations would FK-fail or attach to a stale closed register.
3. **Movements pagination cap** — Hardcoded `Math.min(limit, 100)` in controller defends against malicious or buggy clients requesting unbounded result sets.
4. **Cron testability split** — Each cron exposes individual `reconcileWallets()`, `sweepStaleIntents()`, `refreshExpiringTokens()` async methods that the @Cron-decorated entry simply calls. Tests instantiate the class with mocked deps and call the method directly (no fake timer needed).
5. **boxBalanceAfter=0 in transfer response** — Transfer service does not recompute box balance to avoid query duplication inside the TX. Frontend reads canonical balance via existing `box.service.findAllByStorePaginated` after success.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical Functionality] Added BOX_CLOSED gate**
- **Found during:** Task 1 (MpTransferService implementation)
- **Issue:** Plan specified "INSERT box_operations" but didn't address what happens when target box has no open cash_register. Without an open register, the FK reference would fail at INSERT time, causing TX rollback with a confusing error.
- **Fix:** Added explicit `cashRegisterModel.findOne({ boxId, closingTime: null })` check before INSERT; throws `BadRequestException({ message, code: 'BOX_CLOSED' })` with clear Spanish message if absent.
- **Files modified:** mp-transfer.service.ts (steps 5 + cashRegister query in TX)
- **Verification:** Test mocks include cashRegister object; happy path explicitly verifies `boxOperationModel.create` receives correct cashRegisterId.
- **Committed in:** 0f1d3db (Task 1 GREEN commit)

**2. [Rule 2 - Missing Critical Functionality] Added cross-store check before balance check**
- **Found during:** Task 1 (test "rejects cross-store transfer")
- **Issue:** Plan listed cross-store check as one of many validations but didn't specify ordering. Putting it after balance check would leak information about wallet balance to attackers attempting cross-tenant transfers.
- **Fix:** Cross-store check runs immediately after wallet+box LOCK acquisition, before balance evaluation. Returns generic store-mismatch error.
- **Files modified:** mp-transfer.service.ts (step 3 — placed before step 4 balance check)
- **Verification:** Test "rejects cross-store transfer" passes; balance never inspected when storeId differs.
- **Committed in:** 0f1d3db

**3. [Rule 1 - Bug] Adjusted spec test imports for NestJS exception classes**
- **Found during:** Task 1 RED phase initial run
- **Issue:** Initial spec used `expect.toThrow('Saldo insuficiente')` strict string match but service throws BadRequestException with structured payload (object with `message` field).
- **Fix:** Changed assertions to `toThrow(/Saldo insuficiente/)` regex match, allowing the error to wrap the message.
- **Files modified:** mp-transfer.service.spec.ts (test 2 — insufficient balance)
- **Verification:** Test passes against final implementation.
- **Committed in:** 57b6461 (RED commit) — test was correct before final impl shipped

---

**Total deviations:** 3 auto-fixed (2 missing critical, 1 bug in test setup)
**Impact on plan:** All deviations were necessary for correctness. Plan deliverables fully met; no scope creep. The BOX_CLOSED gate hardens an edge case that production users would have hit on day 1.

## Issues Encountered

- None blocking. Build + all tests green on first attempt after GREEN implementation. Module wiring required adding 3 cross-module models (Box, BoxOperation, CashRegister) to SequelizeModule.forFeature in MercadopagoModule — a clean addition since these models are already registered globally in their own modules.

## TDD Gate Compliance

Plan 08 Task 1 used TDD; gate sequence verified:
1. RED: `57b6461` — failing test commit (TS2307 cannot find module)
2. GREEN: `0f1d3db` — implementation, 6/6 tests pass
3. REFACTOR: not needed (clean first-pass implementation)

Task 2 was non-TDD (auto), with tests added alongside implementation (spec files committed in same commit as service files).

## User Setup Required

None — Plan 08 builds backend services only. No new env vars, no external service config. Cron jobs auto-register via `@nestjs/schedule` (already imported in app.module.ts:88).

## Next Phase Readiness

- **Plan 08b** (frontend): Can now consume the 3 wallet endpoints from `control-de-caja` UI page. Endpoint contracts are stable; response shapes documented in controller types.
- **Plan 09** (refunds): MpTransferService pattern + LOCK approach can be reused for refund debit flow (parallel structure).
- **Production deployment**: Cron jobs will start running on first deploy. Recommend monitoring logs at 03:00 / 04:00 UTC the first night to confirm:
  - `mp_wallet reconcile: N wallets revisados, M con drift (corregidos)`
  - `mp_payment_intents stale sweep: K pending → expired`
  - `mp_token refresh: candidates=X refreshed=Y failed=Z`
- **No blockers.**

## Self-Check: PASSED

Files verified:
- FOUND: api-ventago/src/app/mercadopago/wallet/mp-transfer.service.ts
- FOUND: api-ventago/src/app/mercadopago/wallet/mp-transfer.service.spec.ts
- FOUND: api-ventago/src/app/mercadopago/wallet/mp-wallet.controller.ts
- FOUND: api-ventago/src/app/mercadopago/dto/transfer-mp-to-cash.dto.ts
- FOUND: api-ventago/src/app/mercadopago/cron/mp-wallet-reconcile.cron.ts
- FOUND: api-ventago/src/app/mercadopago/cron/mp-wallet-reconcile.cron.spec.ts
- FOUND: api-ventago/src/app/mercadopago/cron/mp-token-refresh.cron.ts
- FOUND: api-ventago/src/app/mercadopago/cron/mp-token-refresh.cron.spec.ts
- FOUND: api-ventago/src/app/mercadopago/mercadopago.module.ts (modified)

Commits verified:
- FOUND: 57b6461 (test/RED)
- FOUND: 0f1d3db (feat/GREEN)
- FOUND: 4bf6c3d (feat — controller + crons + module)

Tests: 71/71 mercadopago suite tests pass; build exits 0.

---
*Phase: 29-pos-mercadopago-qr-din-mico*
*Completed: 2026-05-06*
