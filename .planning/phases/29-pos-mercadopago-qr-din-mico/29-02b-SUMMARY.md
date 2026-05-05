---
phase: 29-pos-mercadopago-qr-din-mico
plan: 02b
subsystem: payments
tags: [mercadopago, sequelize, sequelize-typescript, nestjs, aes-256-gcm, crypto, oauth, models, jest, tdd]

# Dependency graph
requires:
  - phase: 29-pos-mercadopago-qr-din-mico
    provides: "Plan 02 — 7 mp_* tables in PostgreSQL (mp_accounts, mp_payment_intents, mp_wallets, mp_movements, mp_refunds, mp_refund_attempts, mp_transfers) with payment_id UNIQUE idempotency lock + 2 partial UNIQUE on mp_accounts + cross-table FKs"
provides:
  - "7 sequelize-typescript models in api-ventago/src/app/mercadopago/models/ (camelCase props → snake_case DB cols via underscored:true global)"
  - "MpTokenCryptoService — AES-256-GCM encrypt/decrypt with 96-bit random IV per call, format 'iv_b64:tag_b64:ct_b64'"
  - "Boot validation gate: throws if MP_TOKEN_ENCRYPTION_KEY missing/wrong-length/non-hex (constructor-time, fail-fast)"
  - "MercadopagoModule registered in src/app.module.ts — exports MpTokenCryptoService + SequelizeModule for downstream injection"
  - "11 unit tests on crypto service (4 boot validation + 3 round-trip + 4 tamper detection) — all green"
  - "Backend builds clean (npm run build exits 0) with all 7 models compiled under TS strict mode"
affects: [29-03, 29-04, 29-05, 29-06, 29-07, 29-08, 29-09]

# Tech tracking
tech-stack:
  added:
    - "@nestjs/sequelize SequelizeModule.forFeature for mp_* models (existing in repo, first use under mercadopago/)"
    - "node:crypto createCipheriv/createDecipheriv aes-256-gcm (no new dependency)"
  patterns:
    - "Constructor-time env validation pattern (throw on missing/invalid MP_TOKEN_ENCRYPTION_KEY → fail-fast at app boot)"
    - "AES-256-GCM token storage: 96-bit IV regenerated per encrypt call (NEVER reused with same key) + auth tag verification on decrypt"
    - "Model-as-DB-mirror pattern: 7 models 1:1 with 7 mp_* tables, decorators only describe schema (no business logic)"
    - "TDD RED → GREEN → tamper-resistant test design (flip first base64 char to avoid padding-bit collision false-negative)"

key-files:
  created:
    - "api-ventago/src/app/mercadopago/crypto/mp-token-crypto.service.ts (87 lines)"
    - "api-ventago/src/app/mercadopago/crypto/mp-token-crypto.service.spec.ts (115 lines)"
    - "api-ventago/src/app/mercadopago/models/mp-account.model.ts (68 lines)"
    - "api-ventago/src/app/mercadopago/models/mp-payment-intent.model.ts (63 lines)"
    - "api-ventago/src/app/mercadopago/models/mp-wallet.model.ts (47 lines)"
    - "api-ventago/src/app/mercadopago/models/mp-movement.model.ts (53 lines)"
    - "api-ventago/src/app/mercadopago/models/mp-refund.model.ts (33 lines)"
    - "api-ventago/src/app/mercadopago/models/mp-refund-attempt.model.ts (40 lines)"
    - "api-ventago/src/app/mercadopago/models/mp-transfer.model.ts (43 lines)"
    - "api-ventago/src/app/mercadopago/mercadopago.module.ts (32 lines)"
  modified:
    - "api-ventago/src/app.module.ts (+4 lines — Phase 29 import + array entry)"

key-decisions:
  - "DataType.DECIMAL(14,2) instead of DataType.NUMERIC(14,2) — sequelize exports only DECIMAL (NUMERIC is a PG-side alias, identical semantics; existing codebase uses DECIMAL in credit-payment.model.ts / sale-senia.model.ts)"
  - "Module location: src/app.module.ts (NOT src/app/app.module.ts as the plan specified) — actual NestJS convention in this codebase; import path adjusted to './app/mercadopago/mercadopago.module'"
  - "Tamper test design: flip FIRST base64 char (full byte significance) instead of LAST (padding bit collision risk made decryption sometimes succeed on tampered input — fragile)"
  - "All 7 models declare camelCase property names — Sequelize underscored:true global setting maps to snake_case DB cols automatically (consistent with branch-agent.model.ts pattern)"
  - "MercadopagoModule exports BOTH MpTokenCryptoService AND SequelizeModule (forFeature) — enables downstream plans to inject any model via @InjectModel as well as the crypto service"
  - "Crypto spec colocated with service (mp-token-crypto.service.spec.ts) — matches jest config testRegex '.*\\\\.spec\\\\.ts$' and existing pattern (products.controller.spec.ts, sales.controller.spec.ts)"

patterns-established:
  - "MP encryption pipeline pattern: tokens NEVER touch DB plaintext; downstream services (Plan 03 OAuth) MUST pass through MpTokenCryptoService.encrypt before INSERT and .decrypt after SELECT"
  - "Boot-time crypto validation pattern: MP_TOKEN_ENCRYPTION_KEY is read once in constructor, validated for hex-length AND decoded-byte-length (catches non-hex strings of correct char-length)"
  - "mp_* model wiring pattern: all models bundled in MercadopagoModule via SequelizeModule.forFeature in single forFeature([...]) call (not split across waves)"
  - "Inheritance gap pattern: model has BelongsTo declarations but related models do NOT need HasMany back-refs unless future plans require eager-loading (avoid bidirectional decorator clutter)"

requirements-completed: [MP-POS-01, MP-POS-02, MP-POS-03, MP-POS-05, MP-POS-06, MP-POS-07]

# Metrics
duration: 11min
completed: 2026-05-05
---

# Phase 29 Plan 02b: MP Sequelize Models + Crypto Service Summary

**7 sequelize-typescript models (mp_account/intent/wallet/movement/refund/refund-attempt/transfer) + AES-256-GCM token crypto service with 11 passing unit tests + MercadopagoModule registered in app.module.ts — backend builds clean and is wired for downstream OAuth/QR/webhook/refund plans (03-09).**

## Performance

- **Duration:** 11 min
- **Started:** 2026-05-05T10:53:39Z
- **Completed:** 2026-05-05T11:04:23Z
- **Tasks:** 2 (1 TDD with RED+GREEN, 1 standard)
- **Files created:** 10 (1 service + 1 spec + 7 models + 1 module)
- **Files modified:** 1 (src/app.module.ts)

## Accomplishments

- **Crypto service operational:** MpTokenCryptoService passes 11 unit tests covering 4 boot-validation paths (valid/missing/short/non-hex), 3 round-trip cases (ASCII / UTF-8 multi-byte / random-IV uniqueness), and 4 tamper-detection cases (ciphertext / auth tag / malformed format / empty string)
- **Threat T-29-02 mitigated:** mp_accounts.access_token + refresh_token columns are TEXT, written/read exclusively via MpTokenCryptoService — auth tag verification detects any DB-level tampering
- **Threat T-29-08 mitigated:** App will NOT boot without MP_TOKEN_ENCRYPTION_KEY of correct length + valid hex — fail-fast at constructor time
- **All 7 models compile under TS strict:** `npm run build` exits 0 with `nest build` (no errors, no warnings)
- **MercadopagoModule wired into app.module.ts:** appears at line 177 of imports array (after OnlineOrdersModule), import declaration at line 83
- **Sequelize model-DDL alignment confirmed:** all 7 tableName decorators ('mp_accounts', 'mp_payment_intents', 'mp_wallets', 'mp_movements', 'mp_refunds', 'mp_refund_attempts', 'mp_transfers') match Plan 02 migrations exactly
- **TDD discipline followed:** RED commit (ce4c502, test only — confirmed failing) precedes GREEN commit (bf30369, test passes after impl)

## Task Commits

| # | Task | Commit (api-ventago) | Files | Type |
|---|------|----------------------|-------|------|
| 1 (RED)   | Add failing tests for MpTokenCryptoService | `ce4c502` | 1 (spec) | test |
| 1 (GREEN) | Implement MpTokenCryptoService AES-256-GCM | `bf30369` | 2 (service + improved spec) | feat |
| 2         | Add 7 mp_* Sequelize models + register MercadopagoModule | `1c10ea0` | 9 (7 models + module + app.module.ts) | feat |

**Plan metadata commit (root):** TBD — created by `/gsd-execute-phase` final step (bundles SUMMARY.md + STATE.md + ROADMAP.md + api-ventago submodule pointer)

## Files Created/Modified

### Created (api-ventago)

- `api-ventago/src/app/mercadopago/crypto/mp-token-crypto.service.ts` (87 lines) — AES-256-GCM encrypt/decrypt with constructor-time MP_TOKEN_ENCRYPTION_KEY validation
- `api-ventago/src/app/mercadopago/crypto/mp-token-crypto.service.spec.ts` (115 lines) — 11 jest tests (boot validation 4, round-trip 3, tamper detection 4)
- `api-ventago/src/app/mercadopago/models/mp-account.model.ts` (68 lines) — MpAccount → mp_accounts (storeId, branchId nullable, mpUserId, accessToken/refreshToken TEXT-encrypted, environment ENUM, externalPosId, expiresAt, connectedAt, disconnectedAt)
- `api-ventago/src/app/mercadopago/models/mp-payment-intent.model.ts` (63 lines) — MpPaymentIntent → mp_payment_intents (FK to MpAccount/Store/Branch/Terminal, paymentId UNIQUE, status enum, amount DECIMAL(14,2))
- `api-ventago/src/app/mercadopago/models/mp-wallet.model.ts` (47 lines) — MpWallet → mp_wallets (mpAccountId UNIQUE, balance DECIMAL(14,2) default 0, currency CHAR(3) 'ARS', lastSyncedAt)
- `api-ventago/src/app/mercadopago/models/mp-movement.model.ts` (53 lines) — MpMovement → mp_movements (append-only — updatedAt:false, type 5-value enum, amount DECIMAL(14,2), refundId/transferId nullable INT for cross-table FK split-add)
- `api-ventago/src/app/mercadopago/models/mp-refund.model.ts` (33 lines) — MpRefund → mp_refunds (saleId FK, mpPaymentId, refundId UNIQUE, amount, status default 'approved')
- `api-ventago/src/app/mercadopago/models/mp-refund-attempt.model.ts` (40 lines) — MpRefundAttempt → mp_refund_attempts (saleId FK, attemptNo, status enum, errorMessage, attemptedAt)
- `api-ventago/src/app/mercadopago/models/mp-transfer.model.ts` (43 lines) — MpTransfer → mp_transfers (mpWalletId/targetBoxId/userId FKs, amount, note, transferredAt)
- `api-ventago/src/app/mercadopago/mercadopago.module.ts` (32 lines) — registers all 7 models via SequelizeModule.forFeature, provides MpTokenCryptoService, exports MpTokenCryptoService + SequelizeModule

### Modified (api-ventago)

- `api-ventago/src/app.module.ts` (+4 lines) — added `import { MercadopagoModule } from './app/mercadopago/mercadopago.module';` at line 83 (after OnlineOrdersModule import) AND `MercadopagoModule,` entry in `@Module({ imports: [...] })` array at line 177 (last entry, with Korean comment marker for Phase 29)

## Decisions Made

1. **DataType.DECIMAL(14,2) over DataType.NUMERIC(14,2)** — `sequelize` package exports `DataType.DECIMAL` only; `NUMERIC` is a PostgreSQL-side alias for `DECIMAL` with identical semantics. Existing codebase convention confirmed (`credit-payment.model.ts`, `sale-senia.model.ts`, `credit-ledger.model.ts` all use DECIMAL). PG migration column type was `NUMERIC(14, 2)` in 29-02 — equivalent at SQL level.

2. **app.module.ts location is `src/app.module.ts`, NOT `src/app/app.module.ts`** as the plan stated — verified via `find`. NestJS convention places AppModule at the src root. Import path in app.module.ts is `'./app/mercadopago/mercadopago.module'` (consistent with sibling imports like `'./app/online-orders/online-orders.module'`).

3. **Tamper test design improvement** — initial spec flipped the LAST base64 character of ct/tag, but base64 padding can leave the decoded bytes unchanged when the last character's significant bits are within the padding (2 of 11 tests failed on first GREEN run). Refactored to flip the FIRST char (full byte significance) — both tamper tests now reliably throw, no other test changes needed.

4. **camelCase model properties + global underscored:true** — followed `branch-agent.model.ts` pattern (mpUserId → mp_user_id, accessToken → access_token, etc.). No explicit `field:` overrides needed — Sequelize handles all snake_case mapping automatically per global config.

5. **Cross-table FK columns declared without sequelize FK decorators** for `mp_movements.refundId` and `mp_movements.transferId` — these are added as actual DB FKs in migrations 29-04 / 29-05 (cross-table FK split-add pattern), but the Sequelize model treats them as plain INTEGER columns to avoid forward-reference issues at module init. Code that needs to navigate these relationships will use direct `findByPk(refundId)` lookups (acceptable — these are rarely-traversed audit fields).

6. **MercadopagoModule exports SequelizeModule (in addition to MpTokenCryptoService)** — per [@nestjs/sequelize docs](https://docs.nestjs.com/recipes/sql-sequelize), re-exporting SequelizeModule allows downstream plans (03-09) to inject any of the 7 mp_* models via `@InjectModel(MpAccount)` etc. without re-importing them in each downstream module.

7. **Spec file colocated with service** (`mp-token-crypto.service.spec.ts` next to `mp-token-crypto.service.ts`) — matches jest config `testRegex: '.*\\.spec\\.ts$'` and existing convention (`products.controller.spec.ts`, `sales.controller.spec.ts`).

8. **All BelongsTo declarations omit explicit `foreignKey:`** for child→parent FKs except mp-account.model.ts (where `foreignKey: 'storeId'` is explicit on Store/Branch belongs-to to match the camelCase declared FK column). This matches branch-agent.model.ts style — Sequelize infers the FK from the `@ForeignKey(() => RelatedModel)` decorator above the column.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Wrong app.module.ts path in plan**

- **Found during:** Task 2 (Step 9 — `Edit api-ventago/src/app/app.module.ts`)
- **Issue:** Plan instructed editing `api-ventago/src/app/app.module.ts`, but `find` confirmed the actual file is at `api-ventago/src/app.module.ts` (NestJS standard layout). Editing the wrong path would have created a NEW unused file and left MercadopagoModule unregistered.
- **Fix:** Used the correct path `src/app.module.ts`. Import path adjusted from `'./mercadopago/mercadopago.module'` (would-be relative if AppModule were under src/app/) to `'./app/mercadopago/mercadopago.module'` (correct relative to src/).
- **Files modified:** `api-ventago/src/app.module.ts` (intended file)
- **Verification:** `grep -c MercadopagoModule src/app.module.ts` returns 2 (import + array entry); `grep MercadopagoModule src/app/app.module.ts` returns nothing (file does not exist).
- **Committed in:** `1c10ea0`

**2. [Rule 3 - Blocking] DataType.NUMERIC not exported by sequelize**

- **Found during:** Task 2 (Step 2 — writing mp-payment-intent.model.ts amount column)
- **Issue:** Plan code spec used `DataType.NUMERIC(14, 2)` but sequelize-typescript / sequelize do NOT export `NUMERIC` — only `DECIMAL`. Build would fail with `Property 'NUMERIC' does not exist on type 'typeof DataTypes'`.
- **Investigation:** Checked existing codebase — `credit-payment.model.ts`, `sale-senia.model.ts`, `credit-ledger.model.ts` all use `DataType.DECIMAL(12, 2)` for monetary fields. PostgreSQL treats `DECIMAL` and `NUMERIC` as identical types at the SQL level (per PG docs). The Plan 02 migration files use `NUMERIC(14, 2)` in DDL — Sequelize's DECIMAL maps to the same column type.
- **Fix:** Used `DataType.DECIMAL(14, 2)` everywhere (mp-payment-intent, mp-wallet, mp-movement, mp-refund, mp-refund-attempt, mp-transfer — 6 columns total).
- **Files modified:** all 6 model files with monetary columns
- **Verification:** `npm run build` exits 0, no TypeScript errors. Column type maps to PG `numeric(14,2)` at runtime (equivalent to migration DDL).
- **Committed in:** `1c10ea0`

**3. [Rule 1 - Bug] Tamper test design flaky**

- **Found during:** Task 1 GREEN verification (`npx jest --testPathPattern=mp-token-crypto`)
- **Issue:** Tests "throws when ciphertext is tampered" and "throws when auth tag is tampered" both used `${string.slice(0, -1)}A` to flip the LAST base64 character. Because base64 encodes 3 bytes per 4 chars (with padding), the last character's significant bits sometimes fall within padding bits, leaving the decoded bytes unchanged. Result: encrypted payload "decrypts" successfully on tampered input → test fails (didn't throw).
- **Fix:** Refactored both tamper tests to use a `flipFirstChar` helper that swaps the FIRST base64 character (`first === 'A' ? 'B' : 'A'`). The first base64 char encodes a full 6 bits at a non-padding position, so a flip ALWAYS changes the decoded bytes → auth tag verification reliably fails → throws.
- **Files modified:** `api-ventago/src/app/mercadopago/crypto/mp-token-crypto.service.spec.ts`
- **Verification:** Re-ran spec — 11/11 tests now pass deterministically. Production crypto service code (`mp-token-crypto.service.ts`) was NOT modified — the bug was test-only, the auth tag verification itself works correctly.
- **Committed in:** `bf30369` (combined with GREEN impl, since the spec change was a refinement of the RED design that was committed together with the fix)

---

**Total deviations:** 3 auto-fixed (2 blocking — wrong path / unexported type; 1 test bug)
**Impact on plan:** All 3 fixes were necessary for correctness (path fix prevents silent no-op; DECIMAL fix prevents TS compile failure; tamper test fix prevents flaky CI). Zero scope change — the AES-GCM crypto algorithm, the model schemas, and the module wiring are all exactly as planned. Only the host-language type (DECIMAL vs NUMERIC), the host filesystem location (src/app.module.ts vs src/app/app.module.ts), and the test tampering technique differed.

## Issues Encountered

None beyond the 3 auto-fixed deviations above. Build went green on first attempt after Task 2; crypto tests went green on first attempt after the tamper-test refactor (which was caught and fixed during the same GREEN cycle).

## User Setup Required

None for this plan. The `MP_TOKEN_ENCRYPTION_KEY` env var slot is already in `api-ventago/.env.example` (placeholder from Plan 01). At deploy time, ops must:

1. Generate a 32-byte key: `openssl rand -hex 32` (produces 64 hex chars)
2. Add to production `.env` as `MP_TOKEN_ENCRYPTION_KEY=<hex>`
3. Restart API container

Without a valid key, the API will fail to boot (intentional fail-fast — better than running with broken token storage).

## Next Phase Readiness

**Plan 03 (OAuth flow — mp-oauth.service, mp-store-pos.service, OAuth callback controller) can now proceed:**

- `MpTokenCryptoService` is injectable from MercadopagoModule (already exported) — Plan 03's OAuth service can `constructor(private readonly crypto: MpTokenCryptoService)` and call `crypto.encrypt(accessToken)` before persisting MpAccount
- `MpAccount` model is registered via `SequelizeModule.forFeature` (re-exported from MercadopagoModule) — Plan 03 can `@InjectModel(MpAccount)` directly
- All FK relationships (Store/Branch/Terminal) already declared — Plan 03 OAuth callback can persist MpAccount with full FK chain validated by Sequelize
- `environment` column accepts 'sandbox' | 'production' — Plan 03's OAuth callback distinguishes test-vs-prod MP credentials by writing this column
- `externalPosId` column nullable — Plan 03's mp-store-pos.service writes this column AFTER OAuth completes (Pitfall 3)

**Subsequent waves (Plan 04 QR, 05 webhook, 06 polling, 07 expiry, 08 Caja MP UI, 09 refund):**

- All 6 future plans can inject any model via `@InjectModel(Mp*)` because MercadopagoModule re-exports SequelizeModule
- Plan 05 webhook can use `MpPaymentIntent.findOne({ where: { paymentId } })` directly — DB UNIQUE on payment_id makes this lookup the canonical idempotency check
- Plan 09 refund can use `MpRefundAttempt` to log retries and `MpRefund` (refundId UNIQUE) for the canonical refund record — both ready for `@InjectModel`

---

## Self-Check: PASSED

**Files exist:**
- FOUND: api-ventago/src/app/mercadopago/crypto/mp-token-crypto.service.ts
- FOUND: api-ventago/src/app/mercadopago/crypto/mp-token-crypto.service.spec.ts
- FOUND: api-ventago/src/app/mercadopago/models/mp-account.model.ts
- FOUND: api-ventago/src/app/mercadopago/models/mp-payment-intent.model.ts
- FOUND: api-ventago/src/app/mercadopago/models/mp-wallet.model.ts
- FOUND: api-ventago/src/app/mercadopago/models/mp-movement.model.ts
- FOUND: api-ventago/src/app/mercadopago/models/mp-refund.model.ts
- FOUND: api-ventago/src/app/mercadopago/models/mp-refund-attempt.model.ts
- FOUND: api-ventago/src/app/mercadopago/models/mp-transfer.model.ts
- FOUND: api-ventago/src/app/mercadopago/mercadopago.module.ts
- FOUND: api-ventago/src/app.module.ts (modified)

**Commits exist (api-ventago repo):**
- FOUND: ce4c502 (test: failing tests for MpTokenCryptoService — RED)
- FOUND: bf30369 (feat: implement MpTokenCryptoService AES-256-GCM — GREEN)
- FOUND: 1c10ea0 (feat: 7 mp_* Sequelize models + MercadopagoModule)

**Build state:**
- `cd api-ventago && npm run build` exits 0 (nest build, no TS errors)
- `cd api-ventago && npx jest --testPathPattern=mp-token-crypto --bail` → 11 tests pass, 0 fail

**Module registration:**
- 2 references to MercadopagoModule in `api-ventago/src/app.module.ts` (line 83 import + line 177 array entry) — confirmed via `grep`
- 7 mp_* models registered in `MercadopagoModule.imports[0] = SequelizeModule.forFeature([...])` — confirmed via `grep -E "Mp(Account|PaymentIntent|Wallet|Movement|Refund|RefundAttempt|Transfer)"`

## TDD Gate Compliance

This plan's Task 1 used `tdd="true"`. Gate sequence verified in git log:
- RED commit (`ce4c502`, type=`test`) — spec file added, tests fail (no impl exists)
- GREEN commit (`bf30369`, type=`feat`) — service implemented, tests pass; spec refined inline as Rule 1 bug fix
- REFACTOR — none needed (tamper-test fix was inside GREEN, not a separate cleanup pass)

Both required gates present. RED → GREEN sequence preserved.

---

*Phase: 29-pos-mercadopago-qr-din-mico*
*Plan: 02b (Wave 1b — Sequelize models + crypto service + module wiring)*
*Completed: 2026-05-05*
