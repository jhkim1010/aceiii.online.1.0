---
phase: 29
plan: 09
subsystem: mercadopago-refunds
tags:
  - mercadopago
  - refunds
  - nullify-sale
  - idempotency
  - error-ux
  - phase-29-final
requirements_covered:
  - MP-POS-07
dependency_graph:
  requires:
    - 29-02 (mp_refunds + mp_refund_attempts tables)
    - 29-02b (MpRefund + MpRefundAttempt + MpPaymentIntent + MpAccount models)
    - 29-03 (MpApiClientService + MpTokenCryptoService + OAuth tokens)
    - 29-05 (MpWalletService.debitOnRefund inside TX)
    - 29-07 (PaymentSummaryModal MP entries + frontend toast pattern)
  provides:
    - MpRefundService.refundForSale (auto-call inside nullifySale)
    - MpRefundService.retryAttempt (idempotent MP API call with X-Idempotency-Key)
    - MpRefundService.listAttempts (attempt history feed)
    - POST /mercadopago/refunds/:saleId/retry endpoint
    - GET /mercadopago/refunds/sale/:saleId/attempts endpoint
    - SalesDetailView refund failure UX (Surface 5)
  affects:
    - sales-create.service.ts nullifySale() — extended with mpRefundService.refundForSale()
    - SalesModule.imports — adds MercadopagoModule
    - MercadopagoModule — adds MpRefundController + MpRefundService
tech-stack:
  added:
    - none (re-used existing MP API client + crypto + wallet services)
  patterns:
    - X-Idempotency-Key per attempt — `refund-{saleId}-{attemptNo}` prevents replay double-debit
    - Non-throwing failure path (D-A4-03) — sale always nullified, MP failure surfaces via mpRefundResults
    - mp_payment_intents.pendingVentaId reverse-lookup — SalePaymentMethod has no mpPaymentId column
    - Inline Alert + Toast + Retry button + Dashboard link + History grid (UI-SPEC Surface 5)
key-files:
  created:
    - api-ventago/src/app/mercadopago/dto/retry-refund.dto.ts
    - api-ventago/src/app/mercadopago/refunds/mp-refund.service.ts
    - api-ventago/src/app/mercadopago/refunds/mp-refund.service.spec.ts
    - api-ventago/src/app/mercadopago/refunds/mp-refund.controller.ts
    - ventago-app/src/views/mercadopago/hooks/useMpRefundAttempts.ts
    - ventago-app/src/views/mercadopago/components/McdpgRefundFailureSection.tsx
  modified:
    - api-ventago/src/app/mercadopago/mercadopago.module.ts (registered MpRefundController + service + export)
    - api-ventago/src/app/sales/sales.module.ts (imported MercadopagoModule)
    - api-ventago/src/app/sales/sales-create.service.ts (nullifySale extension)
    - ventago-app/src/views/sales/details/SalesDetailView.tsx (wired refund failure section)
    - docs/phase29-e2e.md (expanded Step 6/7 + Phase 29 acceptance section)
decisions:
  - 'refundForSale signature: takes { id } only — looks up MP intents via pendingVentaId reverse FK (not paymentMethods JSONB) since SalePaymentMethod has no mpPaymentId column'
  - 'X-Idempotency-Key format: refund-{saleId}-{attemptNo} — saleId+attemptNo monotonically uniquely identifies each retry; same attempt repeat returns same MP refund object'
  - 'Failure path NEVER throws — sale stays nullified per D-A4-03; PerPaymentResult.success=false signals UI'
  - 'attempt_no derived as max(existing)+1 — supports unlimited user-driven retries'
  - 'McdpgRefundFailureSection extracted as separate component — keeps SalesDetailView modification surgical (3-line addition + 1 import)'
  - 'Retry button per failed payment (split MP support) — multiple MP entries can each fail/retry independently'
  - 'Historial de intentos always visible when attempts exist — UX rule: operator must debug failures'
metrics:
  duration: 12min
  tasks_completed: 4
  files_changed: 11
  tests_added: 8 (existing — written in pre-execution by previous agent run)
  tests_total_phase29: 79 (all passing)
  deferred_e2e: true (sandbox MP App provisioning required by operator)
completed_date: 2026-05-05T22:38:08Z
---

# Phase 29 Plan 09: Refunds (Auto + Retry + Failure UX) Summary

Closes Phase 29 (final wave). Adds MpRefundService that auto-calls MP /v1/payments/{id}/refunds inside nullifySale per linked mp_payment_intent, idempotent retry endpoint with X-Idempotency-Key=`refund-{saleId}-{attemptNo}`, and SalesDetailView refund failure UX with inline Alert + global toast + retry button + MP Dashboard link + always-visible attempt history (UI-SPEC Surface 5).

## What was built

### Backend (api-ventago)

**MpRefundService** (`refunds/mp-refund.service.ts`):
- `refundForSale({ id })` — looks up `mp_payment_intents` where `pending_venta_id=sale.id AND status='approved'`, iterates each linked intent, calls `retryAttempt` per intent
- `retryAttempt(saleId, mpPaymentId, amount)` — single-payment refund with monotonic attempt_no:
  - Reads intent + mp_account, decrypts access_token
  - Computes `isFull = abs(amount - intent.amount) < 0.01` → empty body for full, `{ amount }` for partial
  - POSTs to `/v1/payments/{id}/refunds` with `X-Idempotency-Key=refund-{saleId}-{attemptNo}` (RESEARCH §Pitfall 10)
  - On success: TX = INSERT mp_refunds + walletSvc.debitOnRefund + UPDATE attempt status='success'
  - On failure: UPDATE attempt status='failed' + error_message (truncated 500), returns success=false WITHOUT throwing (D-A4-03)
- `listAttempts(saleId)` — sorted by attempt_no ASC for UI display

**MpRefundController** (`refunds/mp-refund.controller.ts`):
- `POST /mercadopago/refunds/:saleId/retry` — `@Auth(admin, superadmin, gerente)` + `@Audit('McdpgRefundAttempt', 'create')`, body=RetryRefundDto, calls retryAttempt
- `GET /mercadopago/refunds/sale/:saleId/attempts` — admin/gerente, returns attempt list

**RetryRefundDto** — class-validator: `mpPaymentId: string + amount: number (Min 0.01)`

**SalesCreateService.nullifySale extension** (sales-create.service.ts:422-462):
- After existing reversal sale logic completes, calls `mpRefundService.refundForSale({ id: original.id })`
- Aggregates `perPayment` into `reversalResult.mpRefundResults` (always) + `mpRefundFailed: true` (if any failed)
- Try/catch wrap — even if refundForSale itself throws, sale stays nullified, only `mpRefundError` flag attached
- Attaches via `Object.assign(reversalResult.dataValues, extras)` so toJSON exposes the fields

**MercadopagoModule** wired:
- Imports: MpRefund + MpRefundAttempt models added to SequelizeModule.forFeature
- Controllers: MpRefundController registered
- Providers: MpRefundService registered
- Exports: MpRefundService exported (consumed by SalesModule)

**SalesModule** imports MercadopagoModule (no circular — Mercadopago depends on Webhook+Wallet, not Sales).

### Frontend (ventago-app)

**useMpRefundAttempts hook** (`views/mercadopago/hooks/useMpRefundAttempts.ts`):
- SWR fetch from `/mercadopago/refunds/sale/:id/attempts`
- Returns `{ data, error, isLoading, mutate }`
- Skips fetch when saleId=null
- Type: `McdpgRefundAttempt { id, saleId, mpPaymentId, attemptNo, status, errorMessage, attemptedAt, createdAt }`

**McdpgRefundFailureSection component** (`views/mercadopago/components/McdpgRefundFailureSection.tsx`):
- Detects failed refunds by union of nullify response (mpRefundResults) + attempt history (last attempt_no per mpPaymentId, status='failed')
- For each failed mpPaymentId, renders `<Alert severity='error'>`:
  - Title: `⚠️ Devolución MP fallida`
  - Body: descriptive text + monospace `<code>` block "MP API: {error_message}" with red backdrop
  - Spanish AR copy with partial-cash-success branch
  - 3 action buttons (row, flex-wrap):
    - `🔄 Reintentar devolución` (red contained, disabled while retrying that payment)
    - `↗ Abrir MP Dashboard` (outlined `<a target=_blank rel=noopener noreferrer>` to mercadopago.com.ar/activities)
    - `Ver historial (N intentos)` (text — scrollIntoView smooth to #refund-attempts)
- Retry handler:
  - POST /mercadopago/refunds/:saleId/retry → `{ success, refundId?, errorMessage? }`
  - Success → toast.success + mutateAttempts + onAfterRetry?.()
  - Failure (success=false or thrown) → toast.error with `Reintento #{nextNo} falló (msg). Revisar manualmente en MP Dashboard.`
- Historial de intentos table — ALWAYS visible when attempts exist (operator debug rule):
  - 4-column mono grid: `#N | STATUS | error_message | HH:mm:ss (es-AR locale)`
  - Color-coded status (red failed / green success / muted pending)

**SalesDetailView wiring** (3-line addition + 1 import):
- Imports `McdpgRefundFailureSection`
- Renders inside Grid item between PaymentMethods and AdditionalInfo
- Passes `saleId={sales?.id}`, `nullifyResult={sales}`, `onAfterRetry={getSales}`

### Documentation

**docs/phase29-e2e.md** — extended Step 6 (refund happy path) with 7 explicit SQL verification queries + Step 7 (failure UX) with 19-step checklist covering all 5 UI elements + retry path + idempotency check. Added "Phase 29 acceptance" section with 11-plan completion table and production deploy checklist (env vars, MP App config, test commands).

## Threat Model Mitigations

| Threat | Mitigation Applied |
|--------|---------------------|
| T-29-06 (refund replay) | `X-Idempotency-Key=refund-{saleId}-{attemptNo}` — verified in test `'happy path … X-Idempotency-Key=refund-1-1'` |
| T-29-double-debit | mp_refunds.refund_id UNIQUE (Plan 02) + walletSvc.debitOnRefund inside TX (Plan 05); test `'idempotency'` covers attempt_no increment |
| T-29-token-leak-in-frontend | error_message truncated to 500 chars; backend MP wrapper masks token in logs (existing) |
| T-29-vendedor-retry | `@Auth(admin, superadmin, gerente)` on retry endpoint — vendedor JWT cannot reach |
| T-29-sale-rollback | Sale ALWAYS nullified per D-A4-03 — MP failure non-fatal, surfaces via mpRefundFailed flag |

## Verification

- `cd api-ventago && npm test -- --testPathPattern=mp-refund.service` — **8/8 pass**
  - Full refund happy path (X-Idempotency-Key=refund-1-1, mp_refunds INSERT, debitOnRefund, attempt success)
  - Partial refund body `{ amount }`
  - attempt_no increments from existing max
  - MP API failure: success=false, NEVER throws, attempt failed
  - NotFound when intent missing
  - refundForSale iterates approved intents
  - empty perPayment when no MP intents
  - Multiple MP intents per sale (split MP)
- `cd api-ventago && npm test -- --testPathPattern=mercadopago` — **79/79 pass** (full Phase 29 backend suite)
- `cd api-ventago && npm run build` — exit 0 (clean SWC build)
- `cd ventago-app && npx eslint <new files>` — clean (0 errors, 0 warnings)
- `cd ventago-app && npm run lint` — only 31 pre-existing warnings (no new ones from this plan)
- `cd ventago-app && npm run build` — exit 0 (Next.js 13 production build, all 71 pages compile)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] refundForSale signature uses sale.id only (not paymentMethods array)**
- **Found during:** Task 1 (per existing service implementation)
- **Issue:** Plan asked refundForSale to iterate `sale.paymentMethods` JSONB array. But SalePaymentMethod table has no `mpPaymentId` column — that data lives in `mp_payment_intents` keyed by `pendingVentaId=sale.id`.
- **Fix:** Service signature simplified to `refundForSale({ id })`; queries `mp_payment_intents WHERE pendingVentaId=sale.id AND status='approved'` and iterates intents.
- **Effect:** Same outcome (one refund per MP payment) but data-canonical.
- **Reflected in:** Service code, spec tests (intents fixture), nullifySale call site.
- **Commit:** `12f6c0c` (api-ventago)

**2. [Rule 2 - Architecture] McdpgRefundFailureSection extracted as separate component**
- **Found during:** Task 3
- **Issue:** Plan inlined a 90+ LOC JSX block + state hooks directly into SalesDetailView. That violates separation of concerns and triples SalesDetailView complexity for a feature-localized concern.
- **Fix:** New component `views/mercadopago/components/McdpgRefundFailureSection.tsx` owns all state, SWR hook, retry handler, JSX rendering. SalesDetailView gains 3-line addition + 1 import.
- **Effect:** Same UX surface, cleaner code, easier reuse if other detail views ever need refund UX.
- **Commit:** `2983ebb` (ventago-app)

**3. [Rule 1 - ESLint compliance] newline-before-return + lines-around-comment**
- **Found during:** Task 3 lint check
- **Issue:** ESLint reported 4 errors in McdpgRefundFailureSection (interface comment without prior newline, fallback comment between if + return)
- **Fix:** Added blank lines around inline comments in interface props + before/after the fallback comment in `amountForPayment`
- **Effect:** Lint clean
- **Commit:** `2983ebb` (ventago-app, baked in)

### Architectural Deferral

**Sandbox E2E run** — checkpoint requires full MP sandbox flow (OAuth → QR → payment → nullify → observe refund / failure / retry). This depends on operator-provided `MP_SANDBOX_CLIENT_ID` + `MP_SANDBOX_CLIENT_SECRET` + MP test users (Vendedor + Comprador). Per skip-mp-setup mode active since Plan 01, this is **deferred to operator**. Code-level verification (lint/build/tests) auto-approved.

## Auth Gates

None encountered — all auto-fixed at code level.

## Known Stubs

None. All wiring complete.

## Self-Check: PASSED

**Files exist:**
- `api-ventago/src/app/mercadopago/dto/retry-refund.dto.ts` ✓
- `api-ventago/src/app/mercadopago/refunds/mp-refund.service.ts` ✓
- `api-ventago/src/app/mercadopago/refunds/mp-refund.service.spec.ts` ✓
- `api-ventago/src/app/mercadopago/refunds/mp-refund.controller.ts` ✓
- `ventago-app/src/views/mercadopago/hooks/useMpRefundAttempts.ts` ✓
- `ventago-app/src/views/mercadopago/components/McdpgRefundFailureSection.tsx` ✓

**Commits exist:**
- api-ventago `12f6c0c`: feat(29-09) MpRefundService + RetryRefundDto + spec ✓
- api-ventago `3242495`: chore: auto-commit (controller + module + sales-create.service integration) ✓
- ventago-app `2983ebb`: feat(29-09) MP refund failure UX ✓
- root `cf37399`: docs(29-09) E2E + Phase 29 acceptance ✓

## Phase 29 — FINAL PLAN COMPLETE

This is the final plan of Phase 29 (POS Mercadopago — QR Dinámico). All 11 plans executed:

| Plan | Wave | Title |
|------|------|-------|
| 29-01 | 0 | Pre-flight (qrcode.react + env vars + fixtures + axios mock + ops docs) |
| 29-02 | 1 | DB migrations — 7 mp_* tables (PG10/15 compat) |
| 29-02b | 1 | 7 Sequelize-typescript models |
| 29-03 | 2 | OAuth + MP API client + Store/POS registration + account resolver |
| 29-04 | 3 | QR Dinámico generation + intent polling |
| 29-05 | 4 | Webhook + Socket.io emitToTerminal + wallet credit |
| 29-06 | 5 | Frontend OAuth UI page (configuracion/mercadopago) |
| 29-07 | 6 | Frontend POS UI (sandbox banner + PaymentSummaryModal QR) |
| 29-08 | 6 | Caja MP backend (transfer service + 2 cron jobs) |
| 29-08b | 6 | Caja MP frontend (wallets/movements + components) |
| **29-09** | **7** | **Refunds (auto + retry + failure UX) — THIS PLAN** |

**Acceptance:** All code-level deliverables complete. Sandbox E2E test (Step 1–7 of `docs/phase29-e2e.md`) and SPEC §Acceptance Criteria walkthrough are deferred to operator — requires MP sandbox App provisioning per `docs/phase29-ops-mp-app-setup.md`.
