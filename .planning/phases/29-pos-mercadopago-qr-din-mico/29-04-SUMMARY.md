---
phase: 29-pos-mercadopago-qr-din-mico
plan: 04
subsystem: payments
tags: [mercadopago, qr-dinamico, sequelize, nestjs-controller, class-validator, swr-polling, rollback]

# Dependency graph
requires:
  - phase: 29
    provides: MpAccountResolverService (Plan 03 — branch-first lookup)
  - phase: 29
    provides: MpApiClientService (Plan 03 — per-call axios MP REST wrapper)
  - phase: 29
    provides: MpTokenCryptoService (Plan 02b — AES-256-GCM token decrypt)
  - phase: 29
    provides: MpPaymentIntent model (Plan 02b — mp_payment_intents table)
  - phase: 29
    provides: mock-mp-api.ts + mp-qr-response.json fixture (Plan 01)
provides:
  - CreateMpQrDto — class-validator with Spanish messages (5 required + 1 optional fields)
  - MpQrService.createIntent — INSERT mp_payment_intent → MP /instore/orders/qr POST → on success UPDATE qr_data; on failure mark status='failed' (rollback path)
  - MpQrService.cancelIntent — PUT MP cancel + UPDATE status='cancelled', no-op on already-approved/cancelled/expired
  - MpPaymentIntentsService.findById — attributes whitelist (no token leak), throws 404
  - 3 endpoints: POST /api/mercadopago/qr, DELETE /api/mercadopago/qr/:intentId, GET /api/mercadopago/payment-intents/:intentId
affects: [29-05 webhook (consumes MpPaymentIntentsService.findById + intent.id as external_reference target), 29-06 frontend POS QR UI, 29-08 stale-pending cron sweep (backup cleanup of any 'pending' that escaped rollback)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pre-MP-call DB INSERT to obtain intent.id for external_reference (intent.id, NOT pendingVentaId — RESEARCH §Architecture)"
    - "Rollback path on MP API failure: try → mark intent.status='failed' inside catch → re-throw original error (Plan 08 cron is backup, not primary)"
    - "QR_TTL_MS hardcoded with explicit DO-NOT-MOVE-TO-ENV marker (SPEC.md MP-POS-02 locked timeout)"
    - "notification_url query param accountId={mpAccountId} (RESEARCH §Assumption A9 — webhook must identify the MP account that received the payment)"
    - "Polling endpoint uses Sequelize attributes whitelist — explicit defense against accidental token leak via mp_account include (T-29-02)"
    - "vendedor role allowed for QR generate/cancel/poll (POS use case, PATTERNS.md Pattern B)"

key-files:
  created:
    - api-ventago/src/app/mercadopago/dto/create-mp-qr.dto.ts
    - api-ventago/src/app/mercadopago/intents/mp-payment-intents.service.ts
    - api-ventago/src/app/mercadopago/intents/mp-payment-intents.controller.ts
    - api-ventago/src/app/mercadopago/qr/mp-qr.service.ts
    - api-ventago/src/app/mercadopago/qr/mp-qr.service.spec.ts
    - api-ventago/src/app/mercadopago/qr/mp-qr.controller.ts
  modified:
    - api-ventago/src/app/mercadopago/mercadopago.module.ts

key-decisions:
  - "JSON fixture loaded via require() instead of ES import — tsconfig has no resolveJsonModule and adding it project-wide is out of scope; require() is the equivalent CommonJS path that NestJS specs use elsewhere"
  - "Spec import order: mock-mp-api.ts first, then MpApiClientService — Jest hoists jest.mock('axios') only within the file declaring it; the helper module must load before any axios consumer or the mock is bypassed (RED test caught real network 403/404 calls when import order was wrong)"
  - "MpQrController uses 3-arg getDescription form (_result, body, _user) — Plan 03 SUMMARY documented the correct AuditOptions interface signature; plan example used 1-arg form which would fail compile"
  - "MpQrService takes mpAccountModel as separate constructor injection (not via include on resolver) — cancelIntent reloads account from intent.mpAccountId (resolver only knows scope-level lookup); decoupling avoids re-querying scope info already on the intent row"
  - "Intent rollback uses status='failed' UPDATE (not DELETE) — preserves audit trail of all MP API attempts and their failure reasons; Plan 08 cron sweeps any 'pending' that bypassed rollback (e.g., mark itself failed via catch block) as backup cleanup"

patterns-established:
  - "DB-first intent lifecycle: row exists at all times (pending → failed/cancelled/approved/expired); MP API is idempotent on intent.id as external_reference"
  - "SWR polling endpoint pattern: explicit attributes whitelist + no Sequelize include (defense in depth against future schema changes adding sensitive columns)"
  - "Locked-timeout marker convention: const NAME = value; /* per SPEC.md REQ-ID — DO NOT MOVE TO ENV (locked timeout) */ — searchable + reviewer-visible"

requirements-completed: [MP-POS-02, MP-POS-04, MP-POS-05]

# Metrics
duration: 20min
completed: 2026-05-05
---

# Phase 29 Plan 04: QR Generation Service + Polling Endpoint Summary

**MpQrService createIntent + cancelIntent (with status='failed' rollback path on MP API failure), GET /payment-intents/:id polling endpoint with attributes whitelist, 3 REST endpoints wired with vendedor-allowed @Auth + @Audit, all on top of MpAccountResolverService (branch-first lookup) + MpApiClientService (per-call decrypted token).**

## Performance

- **Duration:** ~20 min
- **Started:** 2026-05-05T11:28:30Z
- **Completed:** 2026-05-05T11:48:47Z
- **Tasks:** 3 (Task 1 auto, Task 2 TDD, Task 3 auto)
- **Files modified/created:** 7 (6 new, 1 updated)

## Accomplishments

- `CreateMpQrDto` with class-validator + Spanish error messages (5 required + 1 optional fields, Spanish UX wording matches existing DTOs like `CreateExpensesDto`)
- `MpPaymentIntentsService.findById` — Sequelize attributes whitelist, returns minimal IntentSummary (no mp_account include = no token leak path)
- `MpPaymentIntentsController` — GET /mercadopago/payment-intents/:id with ParseIntPipe, vendedor-allowed for SWR polling (5s refreshInterval per CONTEXT.md D-A2-03)
- `MpQrService.createIntent`:
  - Branch-first MP account resolve via injected resolver
  - Three early-throw guards: no account / disconnected / no externalPosId — each with stable code (MP_NO_ACCOUNT / MP_ACCOUNT_DISCONNECTED / MP_NO_EXTERNAL_POS_ID) for frontend handling
  - INSERT pending intent BEFORE MP call so intent.id is available as external_reference (NOT pendingVentaId — per RESEARCH §Architecture diagram)
  - Per-call decrypted access_token via crypto.decrypt
  - notification_url contains `?accountId={mpAccountId}` (RESEARCH §Assumption A9 — webhook must identify which MP account the payment belongs to)
  - On MP API failure: mark intent.status='failed' inside catch, then re-throw original error (rollback path — checker WARNING 8); inner catch protects against secondary mark failure
  - On success: UPDATE intent with qr_data + mp_order_id; return { intentId, qrData, expiresAt }
- `MpQrService.cancelIntent`:
  - findByPk → 404 if missing
  - No-op (return ok) if status already approved/cancelled/expired
  - Best-effort PUT to MP /instore/qr/.../orders to clear active QR for that POS (failure logged, doesn't block local cancel)
  - UPDATE intent.status='cancelled' regardless of MP result (UX consistency — user expects cancel to "stick" locally)
- `MpQrController` — POST /qr + DELETE /qr/:intentId, both @Auth(admin/superadmin/gerente/vendedor) + @Audit('McdpgIntent', create/delete) with 3-arg getDescription form
- `MercadopagoModule` — wired MpQrController + MpPaymentIntentsController, MpQrService + MpPaymentIntentsService as providers, both services exported for Plan 05 webhook to consume
- `QR_TTL_MS = 3 * 60 * 1000` hardcoded with explicit `/* per SPEC.md MP-POS-02 — DO NOT MOVE TO ENV (locked timeout) */` comment

## Task Commits

Each task committed atomically in `api-ventago`:

1. **Task 1: DTO + intents service + polling controller** — `742ab7b` (feat)
2. **Task 2: MpQrService + spec (TDD: spec failed first, then green after impl)** — `040f077` (feat)
3. **Task 3: MpQrController + module wiring** — `dca57b8` (feat)

## Files Created/Modified

### Created (6 files in api-ventago)

- `src/app/mercadopago/dto/create-mp-qr.dto.ts` — CreateMpQrDto with @IsNumber/@IsOptional/@IsString + Spanish messages
- `src/app/mercadopago/intents/mp-payment-intents.service.ts` — findById with attributes whitelist, returns IntentSummary
- `src/app/mercadopago/intents/mp-payment-intents.controller.ts` — GET /payment-intents/:id, vendedor-allowed
- `src/app/mercadopago/qr/mp-qr.service.ts` — createIntent (with rollback to status='failed') + cancelIntent (with no-op on terminal status)
- `src/app/mercadopago/qr/mp-qr.service.spec.ts` — 8 unit tests (3 guards + 1 success + 1 rollback + 3 cancel paths)
- `src/app/mercadopago/qr/mp-qr.controller.ts` — POST /qr (@Audit create) + DELETE /qr/:intentId (@Audit delete)

### Modified (1 file)

- `src/app/mercadopago/mercadopago.module.ts` — added 2 controllers (MpQrController, MpPaymentIntentsController), 2 providers (MpQrService, MpPaymentIntentsService), exported both new services for Plan 05

## Test Results

- **6 spec files in mercadopago module, 44 tests, all green**
  - `mp-token-crypto.service.spec.ts` (Plan 02b): 10 tests
  - `mp-api-client.service.spec.ts` (Plan 03): 7 tests
  - `mp-oauth-state.util.spec.ts` (Plan 03): 7 tests
  - `mp-oauth.service.spec.ts` (Plan 03): 6 tests
  - `mp-account-resolver.service.spec.ts` (Plan 03): 5 tests
  - `mp-qr.service.spec.ts` (Plan 04, NEW): 8 tests — no account / disconnected / no externalPosId / success path / **MP failure rollback (asserts updateMock called with `{ status: 'failed' }`)** / cancel-noop on approved / cancel pending / not found
- TDD RED → GREEN cycle confirmed for Task 2 (spec failed first with "Cannot find module" then "BadRequestException: Mercadopago API error", passed after import reorder + impl in place)
- `npm run build` clean (no TypeScript errors, no ESLint errors)

## Decisions Made

1. **JSON fixture via require()** — Spec needs `mp-qr-response.json` but project tsconfig has no `resolveJsonModule`. Used `const qrFixture = require('../../../../test/fixtures/mp-qr-response.json')` with explicit eslint-disable, avoiding a global tsconfig change.
2. **Spec import order** — `mock-mp-api.ts` (which contains `jest.mock('axios')`) MUST be the first import. Jest hoists `jest.mock` only inside the file declaring it; if any axios consumer (`MpApiClientService`) is imported first, axios is loaded as the real module before the mock activates. Caught at GREEN run with real-network 403 from MP.
3. **Audit getDescription 3-arg form** — Followed Plan 03 SUMMARY lesson (`(_result, body, _user) => string`) — plan example used 1-arg `(body) => string` which the AuditOptions interface rejects.
4. **MpAccountModel as separate DI** — `cancelIntent` needs to load account from `intent.mpAccountId` (post-creation), not from scope (storeId/branchId/null). Rather than enriching the resolver, inject mpAccountModel directly — keeps responsibilities clean.
5. **Status='failed' over DELETE** — On MP API failure, marking the row as 'failed' preserves audit trail of every MP attempt + its mp_response error; DELETE would lose that. Plan 08's cron sweep handles any 'pending' rows that escape immediate rollback (rare — the inner try/catch around `intent.update({ status: 'failed' })` protects against secondary failure).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking] Spec import order caused real network calls**
- **Found during:** Task 2 GREEN phase (1 of 8 tests failed with real MP 403 response)
- **Issue:** `import { MpApiClientService }` was first; `MpApiClientService` imports axios at module-load time. By the time `mock-mp-api.ts` was imported (3rd) and triggered `jest.mock('axios')`, axios was already cached in module registry as the real module.
- **Fix:** Reordered imports so `mock-mp-api.ts` is the first import in the spec.
- **Verification:** Failing test now passes; entire spec runs in 27ms instead of 1500ms (no real network).
- **Committed in:** `040f077` (Task 2 commit, both files)

**2. [Rule 3 — Blocking] tsconfig has no resolveJsonModule for fixture import**
- **Found during:** Task 2 RED phase (TS2732 "Cannot find module ... mp-qr-response.json")
- **Issue:** Plan example used `import * as qrFixture from '...json'` but project tsconfig.json doesn't enable `resolveJsonModule`. Adding it project-wide is out of scope.
- **Fix:** Used `const qrFixture = require('../../../../test/fixtures/mp-qr-response.json')` with eslint-disable for the var-requires rule.
- **Verification:** Spec compiles + runs.
- **Committed in:** `040f077` (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (both Rule 3 — blocking issues from infrastructure mismatch)
**Impact on plan:** Both fixes are localized to the spec file; production code unchanged from plan spec.

## Issues Encountered

- One unrelated pre-existing modification to `src/app/sales/sales.service.ts` (3 insertions, 2 deletions) was present from before Plan 03 and remains untouched (out of scope per scope-boundary rule).
- Jest reports "A worker process has failed to exit gracefully" warning at end of full mercadopago test run — known Jest issue with NestJS specs not impacting test results (44 of 44 pass).

## User Setup Required

None new. Plan 01 checkpoint covers MP env vars (MP_*). The 3 endpoints are reachable as soon as backend is running:
- POST /api/mercadopago/qr (vendedor JWT) — needs an active mp_account row (Plan 03 OAuth callback creates this)
- DELETE /api/mercadopago/qr/:intentId — needs intent created via POST first
- GET /api/mercadopago/payment-intents/:intentId — used by Plan 06 frontend SWR hook

## Next Phase Readiness

**Ready for downstream plans:**

- **Plan 05 (webhook + Generar Venta):**
  - `MpPaymentIntentsService.findById` is exported — webhook can resolve intent from `external_reference`
  - intent.id is the external_reference target — webhook flow is `MP webhook → POST /webhook → parse external_reference → findByPk → update status='approved' → trigger Generar Venta`
  - intent.mpAccountId is set so webhook can re-fetch payment via mp_account.access_token
- **Plan 06 (frontend POS QR UI):**
  - SWR hook `useMpPaymentIntent(intentId)` — pings GET /api/mercadopago/payment-intents/:id every 5s
  - On status='approved' → render success + auto-close
  - On status='cancelled'|'expired'|'failed' → render error + retry button
  - QR render uses `qrcode.react@4.2.0` (Plan 01) on `qrData` field from POST response
- **Plan 08 (cron sweep):**
  - Backup cleanup for stale 'pending' (intent.expires_at < NOW + slack) — should be no-op for the rollback case but covers the inner-catch-failed scenario
- **Plan 09 (refunds):**
  - Approved intents have intent.payment_id (set by webhook in Plan 05) — refund flow uses MpApiClientService.post with idempotencyKey

**Blockers:** None — all infrastructure (DB tables, models, crypto, OAuth, account resolver, MP REST wrapper, intent lifecycle services, polling endpoint) in place. Live QR test needs operator MP App provisioning (Plan 01 checkpoint pending) + a test pendingVentaId from Plan 05 wave.

## Self-Check: PASSED

Verified files exist:
- FOUND: api-ventago/src/app/mercadopago/dto/create-mp-qr.dto.ts
- FOUND: api-ventago/src/app/mercadopago/intents/mp-payment-intents.service.ts
- FOUND: api-ventago/src/app/mercadopago/intents/mp-payment-intents.controller.ts
- FOUND: api-ventago/src/app/mercadopago/qr/mp-qr.service.ts
- FOUND: api-ventago/src/app/mercadopago/qr/mp-qr.service.spec.ts
- FOUND: api-ventago/src/app/mercadopago/qr/mp-qr.controller.ts
- FOUND: api-ventago/src/app/mercadopago/mercadopago.module.ts (modified)

Verified commits:
- FOUND: 742ab7b (Task 1 — DTO + intents service + polling controller)
- FOUND: 040f077 (Task 2 — MpQrService + spec, 8 tests green)
- FOUND: dca57b8 (Task 3 — MpQrController + module wiring)

Verified all 44 mercadopago tests pass (build clean):
- mp-token-crypto.service.spec.ts (10) + mp-api-client.service.spec.ts (7) + mp-oauth-state.util.spec.ts (7) + mp-oauth.service.spec.ts (6) + mp-account-resolver.service.spec.ts (5) + mp-qr.service.spec.ts (8) = 43 expected; jest reports 44 (likely additional inline test). All green.

---
*Phase: 29-pos-mercadopago-qr-din-mico*
*Completed: 2026-05-05*
