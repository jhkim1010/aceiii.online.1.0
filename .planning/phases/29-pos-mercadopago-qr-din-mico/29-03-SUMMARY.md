---
phase: 29-pos-mercadopago-qr-din-mico
plan: 03
subsystem: payments
tags: [mercadopago, oauth, hmac, axios, aes-gcm, sequelize-tx, nestjs-controller]

# Dependency graph
requires:
  - phase: 29
    provides: 7 mp_* tables (Plan 02) + 7 Sequelize models + MpTokenCryptoService AES-256-GCM (Plan 02b)
  - phase: 29
    provides: 8 MP_* env vars + axios mock helper + qrcode.react@4.2.0 (Plan 01)
provides:
  - MpApiClientService — raw axios MP REST wrapper with per-call access_token + X-Idempotency-Key + env-separated credentials
  - MpStorePosService — idempotent MP Store + POS registration (external_id format ventago-store-{N}/ventago-pos-{N}-{M|0})
  - mp-oauth-state.util — HMAC-SHA256 sign/verify with timing-safe compare and 10-min ts tolerance (CSRF defense)
  - MpOAuthService — full OAuth round-trip (authorize URL → state validation → code exchange → encrypted token storage → MP Store/POS registration → mp_wallets auto-create) in single TX
  - MpAccountResolverService — branch-first lookup with store-level fallback (CONTEXT.md D-A1-02)
  - MpOAuthController — 3 endpoints (GET /oauth/start, GET /oauth/callback @Public, POST /oauth/disconnect/:id @Audit)
  - public.decorator — IS_PUBLIC_KEY marker for documentation + future global guard support
affects: [29-04 webhook, 29-05 QR generation, 29-06 frontend OAuth UI, 29-07 wallet movements, 29-09 refund flow, 30 MP Point, 31 MP online checkout]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Per-call access_token injection (no global tokens) — multi-tenant per-store OAuth"
    - "HMAC-signed OAuth state with embedded ts for stateless CSRF + replay defense (10-min window)"
    - "AES-256-GCM token encryption with iv:tag:ct format (re-used from Plan 02b crypto service)"
    - "Idempotent external_id-based MP Store/POS registration (soft-fail on 4xx — already registered = success)"
    - "Refresh token rotation: re-save BOTH access_token AND refresh_token in same TX (RESEARCH §Pitfall 2)"
    - "Single Sequelize TX for callback side-effects (account upsert + wallet auto-create)"
    - "Token masking in error logs: first 12 chars + length only (RESEARCH §V8)"
    - "@Public() marker decorator pattern (NestJS convention for future global guards)"

key-files:
  created:
    - api-ventago/src/app/mercadopago/api-client/mp-api-client.service.ts
    - api-ventago/src/app/mercadopago/api-client/mp-api-client.service.spec.ts
    - api-ventago/src/app/mercadopago/api-client/mp-store-pos.service.ts
    - api-ventago/src/app/mercadopago/oauth/mp-oauth-state.util.ts
    - api-ventago/src/app/mercadopago/oauth/mp-oauth-state.util.spec.ts
    - api-ventago/src/app/mercadopago/oauth/mp-oauth.service.ts
    - api-ventago/src/app/mercadopago/oauth/mp-oauth.service.spec.ts
    - api-ventago/src/app/mercadopago/oauth/mp-oauth.controller.ts
    - api-ventago/src/app/mercadopago/mp-account-resolver.service.ts
    - api-ventago/src/app/mercadopago/mp-account-resolver.service.spec.ts
    - api-ventago/src/app/auth/decorators/public.decorator.ts
  modified:
    - api-ventago/src/app/mercadopago/mercadopago.module.ts

key-decisions:
  - "@Public() marker decorator created at api-ventago/src/app/auth/decorators/public.decorator.ts (was referenced by plan but didn't exist) — current project has no global JWT guard so semantically the marker is documentation-only, but using it preserves future-proofing if global guard is later introduced (NestJS standard pattern)"
  - "MpOAuthService spec instantiates the service via positional constructor args (bypassing NestJS DI) — works because @InjectModel/@InjectConnection are metadata-only decorators; allowed faster TDD without TestingModule overhead"
  - "MpStorePosService swallows 4xx errors from MP Store/POS POST and only logs warn — MP returns 4xx if external_id already registered, which is the desired idempotent outcome (no separate GET-check needed)"
  - "Audit getDescription closure signature uses 3-arg form (_result, _body, _user) per AuditOptions interface (not single body arg as plan stated)"

patterns-established:
  - "MP REST integration pattern: raw axios wrapper + per-call token (downstream Plans 04/05/09 will reuse MpApiClientService directly)"
  - "OAuth callback transaction pattern: state verify → external API call → DB upsert + dependent record auto-create — all post-state-verify side effects inside single sequelize.transaction"
  - "Soft-disconnect via disconnectedAt column (not row delete) — preserves history for audit + reconnect via UPDATE"
  - "Branch-first scope resolution as injectable service — used as the universal MP account lookup throughout downstream plans"

requirements-completed: [MP-POS-01, MP-POS-06]

# Metrics
duration: 16min
completed: 2026-05-05
---

# Phase 29 Plan 03: OAuth + MP API Foundation Summary

**Per-call axios MP REST wrapper, HMAC-signed stateless CSRF OAuth state, end-to-end OAuth callback (code → encrypted tokens → MP Store/POS register → wallet auto-create) in single transaction, branch-first account resolver, and 3 REST endpoints (start/callback/disconnect)**

## Performance

- **Duration:** ~16 min
- **Started:** 2026-05-05T11:08:58Z
- **Completed:** 2026-05-05T11:24:14Z
- **Tasks:** 3 (all auto, 2 TDD)
- **Files modified/created:** 12 (11 new, 1 updated)

## Accomplishments

- Per-call MP REST wrapper (`MpApiClientService`) with environment-separated credentials (sandbox/production), opt-in `X-Idempotency-Key`, and PII-safe token masking in error logs
- HMAC-SHA256 OAuth state utility with timing-safe verification + 10-min ts tolerance — full anti-CSRF defense without server-side state storage
- Single-TX OAuth callback flow: state verify → `/oauth/token` exchange → MP Store/POS registration → encrypted token upsert → `mp_wallets` auto-create — partial failure rolls back
- Re-OAuth idempotency: same `(storeId, branchId)` updates existing `mp_account` row and clears `disconnected_at` (no duplicate inserts)
- Refresh token rotation handles MP's NEW refresh_token correctly (both columns re-encrypted in TX, RESEARCH §Pitfall 2 mitigation)
- Branch-first lookup precedence (`MpAccountResolverService.resolveForScope`) ready for Plans 04/05/09 dispatch
- 3 OAuth REST endpoints wired with proper role gating (admin/superadmin) + `@Public()` callback + `@Audit()` disconnect
- `MercadopagoModule` exports MpApiClientService + MpAccountResolverService + MpTokenCryptoService for downstream plans

## Task Commits

Each task was committed atomically in `api-ventago` repo:

1. **Task 1: MP api client + store/POS registration + HMAC OAuth state util** — `49b9620` (feat)
2. **Task 2: MP OAuth service + branch-first account resolver** — `e980621` (feat)
3. **Task 3: MP OAuth controller (start/callback/disconnect) + module wiring** — `a07b4b3` (feat)

## Files Created/Modified

### Created (11 files in api-ventago)

- `src/app/mercadopago/api-client/mp-api-client.service.ts` — Raw axios wrapper, per-call token, X-Idempotency-Key opt-in, env-separated credentials, token masking
- `src/app/mercadopago/api-client/mp-api-client.service.spec.ts` — 7 tests (env separation 4 + GET/POST 2 + error 1)
- `src/app/mercadopago/api-client/mp-store-pos.service.ts` — Idempotent MP Store + POS registration with `ventago-store-{N}` / `ventago-pos-{N}-{M|0}` external_id
- `src/app/mercadopago/oauth/mp-oauth-state.util.ts` — HMAC-SHA256 sign/verify, timing-safe, 10-min ts tolerance
- `src/app/mercadopago/oauth/mp-oauth-state.util.spec.ts` — 7 tests (round-trip 2 + HMAC mismatch + tampered + expired + malformed + invalid env)
- `src/app/mercadopago/oauth/mp-oauth.service.ts` — Full OAuth flow: buildAuthorizeUrl, handleCallback (single-TX), refreshAccount (rotation), disconnect (soft)
- `src/app/mercadopago/oauth/mp-oauth.service.spec.ts` — 6 tests (buildUrl + new account + re-OAuth + bad HMAC + expired state + refresh rotation)
- `src/app/mercadopago/oauth/mp-oauth.controller.ts` — 3 endpoints: GET /start (admin), GET /callback (@Public), POST /disconnect/:id (admin + @Audit)
- `src/app/mercadopago/mp-account-resolver.service.ts` — Branch-first → store-fallback lookup
- `src/app/mercadopago/mp-account-resolver.service.spec.ts` — 5 tests (branch wins + store fallback + null branch + no match + skip-disconnected)
- `src/app/auth/decorators/public.decorator.ts` — `IS_PUBLIC_KEY` marker decorator (no-op now, future-proofs against global JWT guard)

### Modified (1 file)

- `src/app/mercadopago/mercadopago.module.ts` — Register MpOAuthController + 4 new providers (MpApiClientService, MpStorePosService, MpOAuthService, MpAccountResolverService); export MpAccountResolverService + MpApiClientService

## Test Results

- **5 spec files, 36 tests, all green**
  - `mp-token-crypto.service.spec.ts` (Plan 02b): 10 tests
  - `mp-api-client.service.spec.ts`: 7 tests
  - `mp-oauth-state.util.spec.ts`: 7 tests
  - `mp-oauth.service.spec.ts`: 6 tests
  - `mp-account-resolver.service.spec.ts`: 5 tests
- TDD RED → GREEN cycle confirmed for Tasks 1 and 2 (specs failed first, then passed after impl)
- `npm run build` clean (no TypeScript errors)

## Decisions Made

1. **`@Public()` decorator created** — Plan referenced `import { Public } from '../../auth/decorators/public.decorator'` but the file didn't exist. The project has no global JWT guard (so unguarded routes are public by default). I created a no-op marker decorator with `IS_PUBLIC_KEY` metadata so the callback's intent is explicit and ready for future global guard adoption — standard NestJS pattern.
2. **Spec uses positional constructor args** — `new MpOAuthService(accountModel, walletModel, sequelize, crypto, mpApi, storePos)` works because `@InjectModel` / `@InjectConnection` are metadata-only decorators. Avoids `Test.createTestingModule` boilerplate while still verifying business logic.
3. **MpStorePosService swallows MP 4xx** — MP returns 4xx if `external_id` is already registered. Soft-fail (warn only) keeps the OAuth callback non-blocking. The plan called this idempotent design. No separate GET-then-POST-or-PUT logic needed.
4. **Audit getDescription signature** — Plan example used `(params: any) => ...`, but actual `AuditOptions.getDescription` interface is `(result, body, user) => string`. Used the correct 3-arg form.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking] Created missing `public.decorator.ts`**
- **Found during:** Task 3 (controller import)
- **Issue:** Plan instructed `import { Public } from '../../auth/decorators/public.decorator'`, but no such file existed in the repo (no `@Public()` usage anywhere in api-ventago).
- **Fix:** Created `src/app/auth/decorators/public.decorator.ts` exporting `IS_PUBLIC_KEY` constant + `Public()` factory using `SetMetadata`. No-op semantically (no global guard reads it yet) but documents intent + future-proofs.
- **Verification:** Build passes, `@Public()` applied to callback, `grep "@Public"` returns 2.
- **Committed in:** `a07b4b3` (Task 3 commit)

**2. [Rule 1 — Bug] Audit `getDescription` signature mismatch**
- **Found during:** Task 3 (controller writing)
- **Issue:** Plan example used `getDescription: (params: any) => ...` but actual `AuditOptions` interface signature is `(result, body, user) => string`.
- **Fix:** Used 3-arg form `(_result, _body, _user) => string` matching the type definition.
- **Verification:** Build passes (would fail with 1-arg form due to type incompatibility).
- **Committed in:** `a07b4b3` (Task 3 commit)

---

**Total deviations:** 2 auto-fixed (1 blocking missing file, 1 type bug)
**Impact on plan:** Both fixes were strictly required for the controller to compile and run. No scope creep.

## Issues Encountered

- One unrelated pre-existing modification to `src/app/sales/sales.service.ts` (3 insertions, 2 deletions) was present at start of plan and left untouched (out of scope per scope-boundary rule).

## User Setup Required

None new for this plan. Plan 01 (Wave 0) checkpoint already covers the MP_* env vars and operator-side MP App provisioning. The OAuth round-trip CANNOT be live-tested until `MP_SANDBOX_CLIENT_ID`, `MP_SANDBOX_CLIENT_SECRET`, `MP_OAUTH_STATE_SECRET`, `MP_TOKEN_ENCRYPTION_KEY`, and `MP_NOTIFICATION_BASE_URL` are populated in deployment env (see `.planning/phases/29-pos-mercadopago-qr-din-mico/29-USER-SETUP.md` from Plan 01).

## Next Phase Readiness

**Ready for downstream plans:**
- Plan 04 (webhook handling): can `@Inject MpAccountResolverService + MpApiClientService` immediately
- Plan 05 (QR Dinámico generation): `mpApi.put('/instore/qr/seller/.../pos/.../orders', ..., accessToken)` works as soon as scope is OAuth'd
- Plan 06 (frontend OAuth UI): GET `/api/mercadopago/oauth/start?storeId=N&environment=sandbox` returns 302 to MP authorize page; success returns to `/configuracion/mercadopago?ok=1&accountId=N`
- Plan 07 (wallet movements): `mp_wallets` row is auto-created on OAuth — Plan 07 only needs to insert `mp_movements` and recompute `balance`
- Plan 09 (refund): can call `MpApiClientService.post('/v1/payments/.../refunds', ..., token, { idempotencyKey })` directly

**Blockers:** None — all required infrastructure (DB tables, Sequelize models, crypto service, OAuth flow, REST endpoints) in place. Live OAuth needs operator MP App provisioning (Plan 01 checkpoint pending).

## Self-Check: PASSED

Verified files exist:
- FOUND: api-ventago/src/app/mercadopago/api-client/mp-api-client.service.ts
- FOUND: api-ventago/src/app/mercadopago/api-client/mp-store-pos.service.ts
- FOUND: api-ventago/src/app/mercadopago/oauth/mp-oauth.service.ts
- FOUND: api-ventago/src/app/mercadopago/oauth/mp-oauth.controller.ts
- FOUND: api-ventago/src/app/mercadopago/oauth/mp-oauth-state.util.ts
- FOUND: api-ventago/src/app/mercadopago/mp-account-resolver.service.ts
- FOUND: api-ventago/src/app/auth/decorators/public.decorator.ts

Verified commits:
- FOUND: 49b9620 (Task 1)
- FOUND: e980621 (Task 2)
- FOUND: a07b4b3 (Task 3)

---
*Phase: 29-pos-mercadopago-qr-din-mico*
*Completed: 2026-05-05*
