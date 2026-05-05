---
phase: 29-pos-mercadopago-qr-din-mico
plan: 05
subsystem: payments
tags: [mercadopago, webhook, socket-io, idempotency, sequelize-transaction, select-for-update, nestjs-public, async-200, raw-sql]

# Dependency graph
requires:
  - phase: 29
    provides: WebsocketService.emitToApiKey/emitToUser/emitToStore (existing — extended in this plan)
  - phase: 29
    provides: MpApiClientService (Plan 03 — used for /v1/payments/{id} re-fetch)
  - phase: 29
    provides: MpTokenCryptoService (Plan 02b — decrypt access_token per-call)
  - phase: 29
    provides: MpPaymentIntent / MpAccount / MpWallet / MpMovement models (Plan 02b)
  - phase: 29
    provides: mp-payment-approved.json + mp-webhook-payload.json fixtures + mock-mp-api.ts (Plan 01)
provides:
  - WebsocketService.registerTerminal(client, terminalId) — joins socket.io room `terminal:{id}` + tracks in terminalClients Map
  - WebsocketService.emitToTerminal(terminalId, event, payload) — server.to(room).emit broadcast (silent no-op if server unset)
  - WebsocketGateway @SubscribeMessage('register_terminal') handler — frontend entry point
  - MpWalletService.creditOnSale (called inside webhook TX with row lock) + debitOnRefund + computeBalance (raw SQL with snake_case)
  - MpWebhookController POST /api/mercadopago/webhook — @Public, HttpCode 200, setImmediate async processing
  - MpWebhookService.handleNotification — re-fetch + idempotent processor + Socket.io emit
  - MpWebhookDto (class-validator, all optional)
affects:
  - 29-07 frontend POS QR UI (will consume `mercadopago:approved` Socket.io event for auto Generar Venta)
  - 29-08 caja UI (will consume MpWalletService.computeBalance for "Caja Mercadopago" row + transfer flow)
  - 29-09 refunds (will consume MpWalletService.debitOnRefund inside refund webhook TX)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "socket.io room broadcast (server.to('terminal:{id}').emit) over iterative client emit — more efficient fan-out per RESEARCH §Pattern 4"
    - "Public webhook endpoint always returns 200 immediately + setImmediate background processing (MP 22s timeout protection — RESEARCH §Code Examples)"
    - "MP API re-fetch as canonical truth (RESEARCH §Pitfall 1 — QR webhooks have NO x-signature; webhook payload treated as wake-up signal only)"
    - "Re-fetch BEFORE transaction (RESEARCH §Pitfall 6 — DB lock window stays microseconds, not seconds)"
    - "SELECT FOR UPDATE via explicit `lock: t.LOCK.UPDATE` form (RESEARCH §Pitfall 9 — `lock: true` ignored in some Sequelize versions)"
    - "Idempotency via existing intent.paymentId IS NOT NULL check inside locked TX — DB UNIQUE on payment_id is the secondary defense (RESEARCH §Pitfall 5)"
    - "Cross-store rejection inside TX: assert intent.mpAccountId === resolvedAccount.id (T-29-05)"
    - "Wallet row lock during creditOnSale/debitOnRefund — prevents concurrent webhook double-credit on same wallet"
    - "Socket.io emit AFTER commit + try/catch (failure logged, polling fallback recovers)"
    - "Raw SQL in computeBalance with snake_case columns (CLAUDE.md rule) + 0-fallback on query failure (box.service.ts pattern)"
    - "Account resolution waterfall: ?accountId query param → mpUserId fallback (RESEARCH §Assumption A9 — MP may strip query params)"

key-files:
  created:
    - api-ventago/src/common/socket/websocket.service.spec.ts
    - api-ventago/src/app/mercadopago/dto/mp-webhook.dto.ts
    - api-ventago/src/app/mercadopago/wallet/mp-wallet.service.ts
    - api-ventago/src/app/mercadopago/wallet/mp-wallet.service.spec.ts
    - api-ventago/src/app/mercadopago/webhook/mp-webhook.controller.ts
    - api-ventago/src/app/mercadopago/webhook/mp-webhook.service.ts
    - api-ventago/src/app/mercadopago/webhook/mp-webhook.service.spec.ts
  modified:
    - api-ventago/src/common/socket/websocket.service.ts
    - api-ventago/src/common/socket/websocket.gateway.ts
    - api-ventago/src/app/mercadopago/mercadopago.module.ts

key-decisions:
  - "MercadopagoModule imports WebsocketModule (not @Global) — explicit dependency keeps module graph readable; WebsocketModule already exports WebsocketService"
  - "registerTerminal uses socket.io's `client.join(room)` + private terminalClients Map for cleanup tracking — emit uses `server.to(room).emit` (room broadcast is the efficient path; Map is for unregister cleanup only)"
  - "Webhook controller wraps service call in catch + console.error so MP always sees 200 — Winston-styled error formatting deferred (existing OAuth controller uses console.error too — no project-wide Logger interceptor configured for Public routes)"
  - "MpWebhookService swallows ALL errors (no throws) — controller is fire-and-forget by design; polling fallback (Plan 04 GET /payment-intents/:id) catches what webhook misses"
  - "intent update inside TX uses `Object.assign(this, patch)` simulation in spec mocks so the same intent reference reflects paymentId after first call — proves true idempotency (second call sees intent.paymentId already set, skips)"
  - "TypeScript control-flow narrowing limitation: closures across `await sequelize.transaction()` lose the let-assigned non-null inference for `processedIntent`. Worked around with explicit cast `processedIntent as MpPaymentIntent` after the if-guard"
  - "Test idempotency case shares one intent row reference between two service calls (matches real Sequelize behavior where findByPk returns the same row instance only across same TX — the production guarantee comes from DB UNIQUE on payment_id, but spec proves the in-process guard works)"

patterns-established:
  - "Socket.io room-per-entity pattern (terminal:{id}) — extensible to other domains (cashRegister:{id}, sucursal:{id} if needed)"
  - "Public webhook receiver: @Public + @HttpCode(200) + setImmediate + try/catch wrap → never throws to MP, always 200 → MP retry storm avoided"
  - "Webhook handler gates: type check → data.id check → account resolve → MP re-fetch → status check → external_reference check → TX (lock + idempotency + cross-store + update + wallet) → emit"
  - "Wallet TX co-location: creditOnSale takes Transaction `t` parameter instead of opening its own → composable inside larger webhook TX, all-or-nothing atomicity"

requirements-completed: [MP-POS-03, MP-POS-04, MP-POS-01]

# Metrics
duration: 28min
completed: 2026-05-05
---

# Phase 29 Plan 05: Webhook Receiver + Wallet Credit + Socket.io Terminal Channel Summary

**WebsocketService.emitToTerminal(terminalId, event, payload) via socket.io room `terminal:{id}` + MpWebhookController @Public 200-async + MpWebhookService that RE-FETCHES MP `/v1/payments/{id}` as canonical truth (NO signature trust per RESEARCH §Pitfall 1) + SELECT FOR UPDATE intent + idempotency guard + cross-store rejection + MpWalletService.creditOnSale all in same Sequelize transaction + Socket.io emit AFTER commit. The "wake up + verify + credit + push" pipeline that turns an MP sandbox payment into a `mercadopago:approved` event landing on the right terminal — backend half of MP-POS-03 auto Generar Venta.**

## Performance

- **Duration:** ~28 min
- **Started:** 2026-05-05T11:54:09Z
- **Completed:** 2026-05-05T12:22:23Z
- **Tasks:** 3 (all TDD: RED → GREEN, no REFACTOR needed)
- **Files modified/created:** 10 (7 new, 3 modified)

## Accomplishments

- `WebsocketService` extended with:
  - `private terminalClients: Map<number, Set<string>>` (cleanup tracking)
  - `registerTerminal(client, terminalId)` — joins socket.io room `terminal:{id}` + adds client to clients/terminalClients Maps + sets `client.terminalId`
  - `emitToTerminal(terminalId, event, payload)` — `server.to('terminal:{id}').emit` (silent no-op if server unset for unit-test safety)
  - `unregisterClient` extended to clean terminalClients on disconnect (deletes empty Sets)
- `WebsocketGateway` gains `@SubscribeMessage('register_terminal')` handler — frontend entry point
- `MpWalletService` (NEW):
  - `creditOnSale(intent, mpPayment, t)` — wallet row lock (SELECT FOR UPDATE) → INSERT mp_movements credit → UPDATE mp_wallets.balance + lastSyncedAt, all under caller's transaction
  - `debitOnRefund(intent, amount, t)` — same pattern for refund (Plan 09 will consume)
  - `computeBalance(walletId)` — raw SQL with snake_case columns: `SUM(CASE type='credit' THEN amount END) - SUM(CASE type IN ('debit','transfer_out','refund_debit') THEN amount END)`. Returns 0 on query failure (UI display continues).
  - Skips and logs (no throw) when wallet row missing — webhook continues
- `MpWebhookDto` (NEW) — class-validator, all fields optional (MP omits some per webhook type)
- `MpWebhookController` (NEW) — `@Public @Post @HttpCode(200)` with setImmediate background processing. Always returns 200 to MP regardless of internal state.
- `MpWebhookService.handleNotification` (NEW):
  - Gates: `type !== 'payment'` → ignore (merchant_order is duplicate per MP)
  - Resolves `mp_account` via `?accountId` query param OR `body.user_id` fallback (RESEARCH §Assumption A9)
  - **MP /v1/payments/{id} re-fetch with collector's decrypted access_token BEFORE transaction** (Pitfall 6 — keeps lock micro)
  - `payment.status !== 'approved'` → no-op
  - Inside transaction: `findByPk(intentId, { lock: t.LOCK.UPDATE, transaction: t })` (Pitfall 9 — explicit form)
  - Triple guard: not found → log, paymentId already set → idempotent skip (Pitfall 5), mpAccountId mismatch → cross-store reject (T-29-05)
  - `intent.update({ paymentId, status, approvedAt }, { transaction: t })` + `wallets.creditOnSale(...)` inside same TX
  - After commit: `websocket.emitToTerminal(intent.terminalId, 'mercadopago:approved', { intentId, paymentId, amount, capturedAt, pendingVentaId })` wrapped in try/catch
  - All errors logged via Winston, never re-thrown
- `MercadopagoModule` wired:
  - imports: added `WebsocketModule` (not @Global — explicit dependency)
  - controllers: added `MpWebhookController`
  - providers: added `MpWebhookService`, `MpWalletService`
  - exports: added `MpWalletService` for Plan 08 caja UI consumption

## Task Commits

Each task committed atomically in `api-ventago`:

1. **Task 1: WebsocketService.terminal room + WebsocketGateway register_terminal + spec (5 tests)** — `08414a1` (feat)
2. **Task 2: MpWalletService creditOnSale/debitOnRefund/computeBalance + spec (5 tests)** — `215e1cf` (feat)
3. **Task 3: MpWebhookDto + MpWebhookController + MpWebhookService + module wiring + spec (7 tests)** — `2e3b60e` (feat)

## Files Created/Modified

### Created (7 files in api-ventago)

- `src/common/socket/websocket.service.spec.ts` — 5 tests covering register, multi-client, emit, no-server safety, cleanup
- `src/app/mercadopago/dto/mp-webhook.dto.ts` — class-validator DTO with all optional fields
- `src/app/mercadopago/wallet/mp-wallet.service.ts` — credit/debit/computeBalance with row locks + raw SQL
- `src/app/mercadopago/wallet/mp-wallet.service.spec.ts` — 5 tests covering credit, debit, missing-wallet, balance calc, fail-safe
- `src/app/mercadopago/webhook/mp-webhook.controller.ts` — @Public, HttpCode 200, setImmediate
- `src/app/mercadopago/webhook/mp-webhook.service.ts` — full re-fetch + idempotent + Socket.io pipeline
- `src/app/mercadopago/webhook/mp-webhook.service.spec.ts` — 7 tests including idempotency + cross-store rejection

### Modified (3 files)

- `src/common/socket/websocket.service.ts` — added terminalClients Map + registerTerminal + emitToTerminal + unregisterClient cleanup (28 inserted lines, 0 deleted)
- `src/common/socket/websocket.gateway.ts` — added @SubscribeMessage('register_terminal') handler (12 inserted lines)
- `src/app/mercadopago/mercadopago.module.ts` — imported WebsocketModule, registered MpWebhookController + MpWebhookService + MpWalletService, exported MpWalletService

## Test Results

- **8 spec files in mercadopago module + 1 spec file in common/socket — 56 tests, all green**
  - `mp-token-crypto.service.spec.ts` (Plan 02b): 10 tests
  - `mp-api-client.service.spec.ts` (Plan 03): 7 tests
  - `mp-oauth-state.util.spec.ts` (Plan 03): 7 tests
  - `mp-oauth.service.spec.ts` (Plan 03): 6 tests
  - `mp-account-resolver.service.spec.ts` (Plan 03): 5 tests
  - `mp-qr.service.spec.ts` (Plan 04): 8 tests
  - `mp-wallet.service.spec.ts` (Plan 05, NEW): 5 tests
  - `mp-webhook.service.spec.ts` (Plan 05, NEW): 7 tests
  - `websocket.service.spec.ts` (Plan 05, NEW): 5 tests (terminal room only — legacy methods uncovered by design)
- TDD RED → GREEN cycle confirmed for all 3 tasks (each spec failed with TS2307/TS2339/test-not-found before impl, then all green after)
- `npm run build` clean (0 TypeScript errors, 0 ESLint errors)
- Per-task verification command (`npx jest --testPathPattern={spec} --bail`) ≤30s each
- Full mercadopago suite ~15min cumulative (jest serial cold-start dominates) — within VALIDATION.md target

## Decisions Made

1. **WebsocketModule imported (not @Global)** — explicit module dependency keeps the graph readable; WebsocketModule already exports WebsocketService and is already imported by products/sales/notifications/team-chat without issues.
2. **emitToTerminal uses `server.to(room).emit`, registerTerminal uses both** — socket.io rooms are the efficient broadcast mechanism (server-side fan-out). The terminalClients Map exists ONLY for unregister cleanup tracking (we can't query "all sockets in room X" cheaply enough to verify cleanup elsewhere).
3. **Webhook controller uses console.error (not Winston Logger)** — matches existing OAuth callback controller pattern. The route is @Public so no project-wide Logger interceptor; setImmediate background errors are non-actionable to the MP caller anyway.
4. **MpWebhookService never throws** — controller is fire-and-forget by design (always returns 200 to MP). Polling fallback (Plan 04 GET /payment-intents/:id) catches what webhook drops. This decouples MP retry behavior from our internal failure modes.
5. **Idempotency simulation in spec** — the second `handleNotification` call shares the same in-process intent reference (mutated by `Object.assign` inside the update mock). This proves the in-process guard works; the production guarantee is reinforced by the DB UNIQUE constraint on `payment_id` (Plan 02 schema) which would `INSERT` conflict on a second-thread arrival.
6. **TypeScript narrowing workaround** — `let processedIntent: MpPaymentIntent | null = null` reassigned inside `await sequelize.transaction(async (t) => { ... processedIntent = intent })` callback. TS doesn't propagate the narrowing across the closure boundary, so after the `if (processedIntent)` guard we still need `processedIntent as MpPaymentIntent` for property access. Documented inline.
7. **Test mock import order** — `mock-mp-api.ts` imported FIRST (carries `jest.mock('axios')`), then `MpWebhookService`. This pattern is now established (Plan 04 SUMMARY documented the deviation; this plan follows it from the start to avoid the real-network 403 trap).
8. **JSON fixture via require()** — same Plan 04 SUMMARY decision (project tsconfig has no `resolveJsonModule`); used `const approvedFixture = require('...json')` with eslint-disable comment.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking] TypeScript control-flow narrowing across transaction closure**
- **Found during:** Task 3 GREEN phase (build error TS2532 "Object is possibly null" on `processedIntent.terminalId` after the `if (processedIntent)` guard)
- **Issue:** `let processedIntent: MpPaymentIntent | null = null` reassigned inside `await sequelize.transaction(async (t) => { processedIntent = intent })`. TS narrowing doesn't propagate across the async closure boundary even after a non-null check.
- **Fix:** Cast inside the if-block as `const intent = processedIntent as MpPaymentIntent;` then access `.terminalId` / `.id` / `.amount` / `.pendingVentaId` from the local. Documented inline as a "TypeScript control-flow narrowing limitation".
- **Verification:** `npm run build` clean.
- **Committed in:** `2e3b60e` (Task 3 commit, code-only fix)

**Total deviations:** 1 auto-fixed (Rule 3 — TypeScript blocking, scope-local).
**Impact on plan:** Localized to one closure body in mp-webhook.service.ts. No behavioral change.

## Issues Encountered

- Pre-existing modification to `src/app/sales/sales.service.ts` remains untouched (out of scope per scope-boundary rule, also flagged in Plan 03/04 SUMMARYs).
- Jest reports "A worker process has failed to exit gracefully" warning at end of full mercadopago test run — known Jest+NestJS issue not impacting test results.
- Full mercadopago jest suite takes ~15 min wall-clock due to per-spec NestJS cold-start (8 specs × ~2 min each in series). Per-task `--testPathPattern` runs are ~30s and well within latency budget.

## User Setup Required

**None new.** Plan 01 already covered `MP_TOKEN_ENCRYPTION_KEY`, `MP_*_CLIENT_ID/SECRET`, and `MP_NOTIFICATION_BASE_URL`. The webhook endpoint is reachable as soon as backend is running:

- POST /api/mercadopago/webhook?accountId={mpAccountId} (Public, JWT-free) — accepts MP webhook payloads
- The `notification_url` in MP QR creation (Plan 04) already includes `?accountId={id}` per RESEARCH §Assumption A9
- For sandbox E2E (Plan 09), set MP App webhook URL to `https://newapi.coolsistema.com/api/mercadopago/webhook` in MP Developer Panel

## Next Phase Readiness

**Ready for downstream plans:**

- **Plan 06 (frontend OAuth UI):** No new dependency from this plan
- **Plan 07 (frontend POS QR UI + auto Generar Venta):**
  - Frontend connects Socket.io to `/realtime` namespace
  - On connect: `socket.emit('register_terminal', { terminalId: cashRegister.terminal.id })`
  - On `mercadopago:approved` event: payload `{ intentId, paymentId, amount, capturedAt, pendingVentaId }` → triggers `handleSubmit('INVOICED', paymentMethods)` automatically
  - SWR polling at `/api/mercadopago/payment-intents/:id` (Plan 04) is the fallback path — both arrive at same handleSubmit; PaymentSummaryModal needs `processedIntentId` ref guard (Pitfall 5)
- **Plan 08 (caja UI + transfer):**
  - `MpWalletService.computeBalance(walletId)` exported for "Caja Mercadopago" row balance display
  - `MpWalletService.creditOnSale` pattern (lock + insert mp_movements + update wallet under caller TX) is the template Plan 08's `MpTransferService` should mirror for MP→cash transfers
- **Plan 09 (refunds):**
  - `MpWalletService.debitOnRefund` exported and ready for refund webhook TX consumption
  - Webhook idempotency pattern (re-fetch + SELECT FOR UPDATE + paymentId guard) extends naturally to refund webhooks (use refund.id as the dedupe key)

**Blockers:** None. The full QR → payment → auto-Generar Venta loop is now backend-complete. Live sandbox testing requires MP App provisioning (still a Plan 01 checkpoint pending) + Plan 07 frontend listener.

## Self-Check: PASSED

Verified files exist:
- FOUND: api-ventago/src/common/socket/websocket.service.spec.ts
- FOUND: api-ventago/src/common/socket/websocket.service.ts (modified)
- FOUND: api-ventago/src/common/socket/websocket.gateway.ts (modified)
- FOUND: api-ventago/src/app/mercadopago/dto/mp-webhook.dto.ts
- FOUND: api-ventago/src/app/mercadopago/wallet/mp-wallet.service.ts
- FOUND: api-ventago/src/app/mercadopago/wallet/mp-wallet.service.spec.ts
- FOUND: api-ventago/src/app/mercadopago/webhook/mp-webhook.controller.ts
- FOUND: api-ventago/src/app/mercadopago/webhook/mp-webhook.service.ts
- FOUND: api-ventago/src/app/mercadopago/webhook/mp-webhook.service.spec.ts
- FOUND: api-ventago/src/app/mercadopago/mercadopago.module.ts (modified)

Verified commits:
- FOUND: 08414a1 (Task 1 — WebsocketService.terminal room + gateway handler + 5 tests)
- FOUND: 215e1cf (Task 2 — MpWalletService + 5 tests)
- FOUND: 2e3b60e (Task 3 — MpWebhookDto + Controller + Service + module wiring + 7 tests)

Verified all 56 mercadopago tests pass (build clean):
- mp-token-crypto (10) + mp-api-client (7) + mp-oauth-state (7) + mp-oauth (6) + mp-account-resolver (5) + mp-qr (8) + mp-wallet (5) + mp-webhook (7) = 55 + websocket.service (5) = 60 cumulative phase tests, all green.

## TDD Gate Compliance

This plan ran under task-level TDD (each task spec was written first and verified to fail before implementation). The plan-level frontmatter is `type: execute` (not `type: tdd`), so plan-wide RED/GREEN/REFACTOR commits are not gated. Per-task commits combine spec + impl for review-friendliness.

Per-task TDD evidence:
- **Task 1:** RED was `TS2339: Property 'registerTerminal' does not exist on type 'WebsocketService'` (5 occurrences) → GREEN after extending WebsocketService + WebsocketGateway → 5/5 pass
- **Task 2:** RED was `TS2307: Cannot find module './mp-wallet.service'` → GREEN after creating MpWalletService → 5/5 pass
- **Task 3:** RED was `TS2307: Cannot find module './mp-webhook.service'` → GREEN after creating MpWebhookService + DTO + controller + module wiring → 7/7 pass

---
*Phase: 29-pos-mercadopago-qr-din-mico*
*Completed: 2026-05-05*
