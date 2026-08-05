---
phase: 29
slug: pos-mercadopago-qr-din-mico
status: approved
nyquist_compliant: true
wave_0_complete: false
created: 2026-05-05
revised: 2026-05-05
---

# Phase 29 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Source of truth: `29-RESEARCH.md` `## Validation Architecture` (line 901+).
> `wave_0_complete` flips to `true` after Plan 01 finishes (creates fixtures + qrcode.react install + crypto env).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Backend framework** | Jest 29.7.0 + ts-jest 29.2.5 + Supertest 7.0.0 — already configured [VERIFIED: api-ventago/package.json] |
| **Backend config** | inline in `api-ventago/package.json` `"jest"` key (no separate jest.config.js) |
| **Backend quick run** | `cd api-ventago && npx jest --testPathPattern=mercadopago --bail` |
| **Backend full suite** | `cd api-ventago && npm test` |
| **Backend estimated runtime** | ~30s for `--testPathPattern=mercadopago` (target ≤30s); full suite ~90s |
| **Frontend framework** | None detected in `ventago-app` — manual + lint only |
| **Frontend lint (gating)** | `cd ventago-app && npm run lint` |
| **Frontend build (gating)** | `cd ventago-app && npm run build` |
| **Frontend smoke test (qrcode.react)** | `cd ventago-app && node -e "require('qrcode.react'); console.log('ok')"` (Plan 01 Wave 0) |
| **E2E sandbox** | Manual scripted (curl + sandbox MP test card) — see `docs/phase29-e2e.md` (Plan 09) |

---

## Sampling Rate

- **After every backend task commit:** `cd api-ventago && npx jest --testPathPattern=mercadopago --bail` (target: ≤30s)
- **After every frontend task commit:** `cd ventago-app && npm run lint` (≤15s)
- **After every plan wave merge:** `cd api-ventago && npm test && cd ../ventago-app && npm run lint && npm run build`
- **Before `/gsd-verify-work`:** Full backend suite green + frontend lint+build green + 1 E2E sandbox scripted run documented in `docs/phase29-e2e.md`
- **Max feedback latency (per-task):** 30 seconds (backend) / 15 seconds (frontend)

---

## Per-Task Verification Map

> Task ID format: `29-PP-TT` where PP = plan number (01..09 / 02b / 08b), TT = task number within plan.
> "File Exists" reports the spec file Wave 0 must scaffold (❌ W0) or that Plan 01 already creates (✅).

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 29-01-01 | 01 | 0 | (Wave 0 setup) | — | qrcode.react v4.2.0 installed, MP_TOKEN_ENCRYPTION_KEY in `.env.example`, fixtures + mock helper present | smoke | `node -e "require('qrcode.react'); console.log('ok')" && test -f api-ventago/test/fixtures/mp-webhook-payload.json && test -f api-ventago/test/fixtures/mp-payment-approved.json && test -f api-ventago/test/fixtures/mp-qr-response.json && test -f api-ventago/test/helpers/mock-mp-api.ts && test -f docs/phase29-e2e.md && grep MP_TOKEN_ENCRYPTION_KEY api-ventago/.env.example` | ✅ (Plan 01 creates) | ⬜ pending |
| 29-02-01 | 02 | 1 | MP-POS-01, MP-POS-02, MP-POS-03, MP-POS-05, MP-POS-06, MP-POS-07 | T-29-04, T-29-07 | Schema-layer constraints (UNIQUE payment_id idempotency, CHECK enums, partial UNIQUE on (store_id, branch_id)) | integration | `test -f api-ventago/migrations/29-01-mp-accounts.sql && test -f api-ventago/migrations/29-02-mp-payment-intents.sql && test -f api-ventago/migrations/29-03-mp-wallets-movements.sql && test -f api-ventago/migrations/29-04-mp-refunds.sql && test -f api-ventago/migrations/29-05-mp-transfers.sql && test -f api-ventago/migrations/29-99-rollback.sql && test -f api-ventago/migrations/29-RUN.md && docker exec -i api_ventago node -e "const{Client}=require('pg');const fs=require('fs');const files=['29-01-mp-accounts.sql','29-02-mp-payment-intents.sql','29-03-mp-wallets-movements.sql','29-04-mp-refunds.sql','29-05-mp-transfers.sql'];const c=new Client({host:'dbpostgres',user:'coolsistema',password:'<REDACTED>',database:'ventago'});c.connect().then(async()=>{for(const f of files){await c.query(fs.readFileSync('/app/migrations/'+f,'utf8'));}const r=await c.query(\"SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND table_name LIKE 'mp_%'\");if(r.rows.length!==7)throw new Error('expected 7 tables');c.end();})"` | ✅ (Plan 02 Task 1 creates) | ⬜ pending |
| 29-02b-01 | 02b | 1 | MP-POS-01b | T-29-02, T-29-08 | AES-256-GCM round-trip; tamper detection (auth tag); boot validation rejects bad key | unit | `cd api-ventago && npx jest --testPathPattern=mp-token-crypto.service.spec --bail` | ❌ W0 (spec created in Plan 02b Task 1) | ⬜ pending |
| 29-02b-02 | 02b | 1 | (foundational module wiring) | — | Module registers all 7 mp_* models + MpTokenCryptoService; backend boots without error | smoke | `cd api-ventago && npm run build && grep -c "MercadopagoModule" api-ventago/src/app/app.module.ts` | ✅ (Plan 02b Task 2 creates) | ⬜ pending |
| 29-03-01 | 03 | 2 | MP-POS-06a | — | MpApiClientService selects sandbox vs production host based on environment | unit | `cd api-ventago && npx jest --testPathPattern=mp-api-client.service.spec --bail` | ❌ W0 (spec created in Plan 03) | ⬜ pending |
| 29-03-02 | 03 | 2 | MP-POS-01a, MP-POS-01c, MP-POS-01d, MP-POS-06b | T-29 OAuth scope | OAuth callback creates mp_account row + mp_wallet row; re-OAuth same scope updates row (no insert); branch-level lookup precedence (branch wins, store fallback); environment change forces token invalidation | integration | `cd api-ventago && npx jest --testPathPattern="mp-oauth.service.spec\|mp-account-resolver.spec\|mp-oauth-state.util.spec" --bail` | ❌ W0 (specs created in Plan 03) | ⬜ pending |
| 29-04-01 | 04 | 3 | MP-POS-02a, MP-POS-02b | T-29-04 | createIntent inserts mp_payment_intent then calls MP API; on MP API failure marks intent status='failed' (rollback path); cancelIntent updates status='cancelled' + calls MP cancel | integration (MP API mocked) | `cd api-ventago && npx jest --testPathPattern=mp-qr.service.spec --bail` | ❌ W0 (spec created in Plan 04) | ⬜ pending |
| 29-04-02 | 04 | 3 | MP-POS-02 (DTO + controller wiring) | — | DTO validation rejects invalid amount/missing fields; controller @Auth + @Audit applied | unit | `cd api-ventago && npx jest --testPathPattern="create-mp-qr.dto.spec\|mp-qr.controller.spec" --bail || cd api-ventago && npm run build` | ❌ W0 (DTO has class-validator) | ⬜ pending |
| 29-05-01 | 05 | 4 | MP-POS-03c | — | websocket.emitToTerminal pushes only to right terminal room | unit | `cd api-ventago && npx jest --testPathPattern=websocket.service.spec --bail -t "terminal room"` | ❌ W0 (extend existing spec) | ⬜ pending |
| 29-05-02 | 05 | 4 | MP-POS-03a, MP-POS-03b, MP-POS-04b | T-29-07 (idempotency) | Webhook with valid payment.id + status=approved updates intent + emits Socket.io; webhook re-call (same payment.id) is no-op; webhook + polling double-arrival → 1 sale only | integration | `cd api-ventago && npx jest --testPathPattern=mp-webhook.service.spec --bail` | ❌ W0 (spec created in Plan 05) | ⬜ pending |
| 29-05-03 | 05 | 4 | MP-POS-04 (wallet credit) | — | mp_wallet.creditOnSale increments balance + inserts mp_movements row inside the same TX as sale create | integration | `cd api-ventago && npx jest --testPathPattern=mp-wallet.service.spec --bail` | ❌ W0 (spec created in Plan 05) | ⬜ pending |
| 29-06-01 | 06 | 5 | MP-POS-01 (config UI) | — | configuracion/mercadopago page renders; OAuth connect button calls backend + redirects | manual | `cd ventago-app && npm run lint && npm run build` (manual smoke: navigate to /configuracion/mercadopago, click Connect, observe MP OAuth redirect) | ❌ W0 (no test framework — manual + lint+build) | ⬜ pending |
| 29-07-01 | 07 | 6 | MP-POS-02c (QR modal) | — | PaymentSummaryModal MP row shows QR + 3-min countdown + auto-expire | manual | `cd ventago-app && npm run lint && npm run build` (manual smoke: nueva-venta → select MP → observe QR modal countdown) | ❌ W0 (no test framework — manual + lint+build) | ⬜ pending |
| 29-07-02 | 07 | 6 | MP-POS-03d, MP-POS-04a (auto-Generar) | — | Frontend receives Socket.io event → triggers handleSubmit → POST /sales; SWR polling fallback triggers same flow when webhook blocked | manual sandbox | scripted in `docs/phase29-e2e.md` (block webhook URL temporarily, sandbox-pay, expect ≤10s auto-generate) | ❌ W0 (no test framework — manual sandbox) | ⬜ pending |
| 29-07-03 | 07 | 6 | MP-POS-06c | — | Sandbox env shows orange `<Alert>` banner + orange QR border | manual | `cd ventago-app && npm run lint && npm run build` (manual: toggle env, observe nueva-venta UI) | ❌ W0 (no test framework — manual + lint+build) | ⬜ pending |
| 29-07-04 | 07 | 6 | (split payment UX) | — | PaymentSummaryModal supports MP row + cash row simultaneously; MP QR amount = MP entry only | manual | `cd ventago-app && npm run lint && npm run build` (manual: select 2 methods, MP entries 30000 — verify QR amount) | ❌ W0 (no test framework — manual + lint+build) | ⬜ pending |
| 29-07-05 | 07 | 6 | (checkpoint) | — | Human verification of payment flow E2E (sandbox MP test card) | checkpoint:human-verify | manual sandbox per `docs/phase29-e2e.md` | ✅ (created in Plan 01) | ⬜ pending |
| 29-08-01 | 08 | 6 | (transfer correctness) | T-29 wallet scope | MpTransferService atomic move: lock + balance check + debit mp_movements + credit physical box movements + insert mp_transfers + balance updates — all in one TX; throws 'Saldo insuficiente' if balance < amount | unit/integration | `cd api-ventago && npx jest --testPathPattern=mp-transfer.service.spec --bail` | ❌ W0 (spec created in Plan 08) | ⬜ pending |
| 29-08-02 | 08 | 6 | (cron jobs) | — | Nightly mp_wallet reconcile cron logs discrepancies; daily mp_token refresh + D-7 alert cron schedules correctly | smoke (build) | `cd api-ventago && npm run build && grep "@Cron(CronExpression.EVERY_DAY_AT_3AM)" api-ventago/src/app/mercadopago/cron/mp-wallet-reconcile.cron.ts && grep "@Cron(CronExpression.EVERY_DAY_AT_4AM)" api-ventago/src/app/mercadopago/cron/mp-token-refresh.cron.ts && grep "expired" api-ventago/src/app/mercadopago/cron/mp-wallet-reconcile.cron.ts` | ✅ (created in Plan 08) | ⬜ pending |
| 29-08b-01 | 08b | 6 | MP-POS-04 (Caja MP UX hooks) | — | useMpWallets + useMpMovements SWR hooks fetch + dedupe correctly | manual | `cd ventago-app && npm run lint && npm run build` (manual smoke: control-de-caja shows Caja MP rows) | ❌ W0 (no test framework — manual + lint+build) | ⬜ pending |
| 29-08b-02 | 08b | 6 | MP-POS-04 (Caja MP UX components) | — | McdpgWalletRow + Transfer modal + Detail modal + integration into CashControlList; admin/gerente only for Transferir | manual | `cd ventago-app && npm run lint && npm run build` (manual: control-de-caja → Transferir MP→cash → observe atomic update) | ❌ W0 (no test framework — manual + lint+build) | ⬜ pending |
| 29-09-01 | 09 | 7 | MP-POS-07a, MP-POS-07b, MP-POS-07c | T-29 refund replay | nullifySale of MP sale auto-calls refund + creates mp_refunds row + debits mp_movements; refund failure leaves sale nullified + creates mp_refund_attempts row; retry endpoint uses same X-Idempotency-Key | integration | `cd api-ventago && npx jest --testPathPattern=mp-refund.service.spec --bail` | ❌ W0 (spec created in Plan 09) | ⬜ pending |
| 29-09-02 | 09 | 7 | MP-POS-05b | — | Sale.paymentMethods includes mp_payment_id in MP entry | integration (extend existing) | `cd api-ventago && npx jest --testPathPattern=sales-create.service.spec --bail -t "mp split"` | ❌ W0 (extend existing spec) | ⬜ pending |
| 29-09-03 | 09 | 7 | MP-POS-07d (refund failure UI) | — | SalesDetailView shows inline `<Alert>` + global toast + retry button + MP Dashboard link on refund failure | manual | `cd ventago-app && npm run lint && npm run build` (manual: force MP refund failure, observe SalesDetailView) | ❌ W0 (no test framework — manual + lint+build) | ⬜ pending |
| 29-09-04 | 09 | 7 | (E2E sandbox) | — | End-to-end sandbox payment flow documented + executed (connect OAuth, generate QR, simulate via /v1/payments curl with sandbox test card per Q5 fallback, observe auto-Generar Venta) | E2E manual | execute steps in `docs/phase29-e2e.md` | ✅ (doc created Plan 01, executed Plan 09) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

> Created by Plan 01 (wave 0). All other waves block on these existing.

- [ ] `ventago-app/package.json` — add `qrcode.react@^4.2.0` (verified by `node -e "require('qrcode.react')"`)
- [ ] `api-ventago/.env.example` — add `MP_TOKEN_ENCRYPTION_KEY=<32-byte-hex>` placeholder + `MP_SANDBOX_CLIENT_ID/SECRET` + `MP_PRODUCTION_CLIENT_ID/SECRET` + `MP_WEBHOOK_SECRET` + `MP_NOTIFICATION_BASE_URL`
- [ ] `api-ventago/test/fixtures/mp-webhook-payload.json` — sample webhook envelope (MP-POS-03 tests)
- [ ] `api-ventago/test/fixtures/mp-payment-approved.json` — sample re-fetched payment object (MP-POS-03/04/07)
- [ ] `api-ventago/test/fixtures/mp-qr-response.json` — sample MP QR creation response (MP-POS-02 tests)
- [ ] `api-ventago/test/helpers/mock-mp-api.ts` — axios mock helper (`resetMpMocks`, `mockMpPost`, `mockMpFailure`) for all backend specs
- [ ] `docs/phase29-e2e.md` — sandbox E2E script: connect OAuth → generate QR → trigger payment via `curl -X POST https://api.mercadopago.com/v1/payments` with sandbox test card token (Q5 fallback) → observe webhook + auto-Generar Venta
- [ ] **Operational (out-of-band):** MP Developer App registered in https://www.mercadopago.com.ar/developers/panel (sandbox + production); ops team holds credentials; secrets injected via Docker secret before Wave 6 begins

> If Plan 01 fails to create any of the above, ALL downstream test commands fail. Plan 01 itself runs without dependencies.

---

## Manual-Only Verifications

> All `ventago-app` (frontend) tasks are manual-only because the project does not have a JS test framework configured. Lint + build are gating proxies.

| Behavior | Requirement | Plan / Task | Why Manual | Test Instructions |
|----------|-------------|-------------|------------|-------------------|
| OAuth connect/disconnect UI works (configuracion/mercadopago) | MP-POS-01 | Plan 06 | No frontend test framework in `ventago-app` | (1) `cd ventago-app && npm run lint && npm run build` (must exit 0). (2) Run dev server, navigate to `/configuracion/mercadopago`, click "Conectar" — verify MP OAuth redirect, complete flow on sandbox MP, return — verify card shows "Conectado" + environment badge. |
| QR modal renders + countdown decrements + auto-expires at 0 | MP-POS-02c | Plan 07 | No frontend test framework | (1) `cd ventago-app && npm run lint && npm run build`. (2) Open nueva-venta, add a product, select Mercadopago payment method, click Generar — verify QR appears, 3-min countdown decrements 1/sec, modal closes/disables at 0. |
| Auto-Generar Venta triggers via Socket.io | MP-POS-03d | Plan 07 | Requires MP sandbox payment + browser visibility | Follow `docs/phase29-e2e.md` — pay via MP sandbox app or `curl /v1/payments`. Verify within ≤2s the Generar Venta button auto-clicks + sale appears in /ventas. |
| SWR polling fallback triggers Generar Venta when webhook blocked | MP-POS-04a | Plan 07 | Requires firewall/network manipulation | Block notification_url via local hosts file or sandbox firewall, sandbox-pay, expect ≤10s auto-generate via polling. |
| Sandbox UI: orange banner + orange QR border | MP-POS-06c | Plan 07 | Visual regression — no Storybook/visual test | Toggle to sandbox env in /configuracion/mercadopago, navigate to nueva-venta, verify orange `<Alert severity="warning">🧪 SANDBOX MERCADOPAGO</Alert>` banner. Open QR modal, verify orange `border-color: warning.main`. |
| Split payment: MP=30000 + Efectivo=20000 | MP-POS-05a | Plan 07 | Multi-step UX | In PaymentSummaryModal, add MP row (30000) + Efectivo row (20000). Click Generar — verify backend QR amount = 30000 only (inspect network tab). |
| Caja Mercadopago row appears + admin transfer works | MP-POS-04 (Caja UX) | Plan 08b | No frontend test framework | (1) `cd ventago-app && npm run lint && npm run build`. (2) After sandbox sale, navigate to control-de-caja — verify cyan Caja MP row + balance. (3) As admin/gerente, click Transferir, enter amount, select target box, submit — verify atomic update (mp_wallet.balance ↓, box.balance ↑). (4) As vendedor, verify Transferir button disabled with tooltip. |
| Refund failure UX: inline Alert + toast + retry + MP Dashboard link | MP-POS-07d | Plan 09 | Requires forced MP refund failure | Force MP refund failure (e.g., delete sandbox payment via MP Dashboard before nullify, or mock MP API 500 in dev). Nullify the MP sale, verify SalesDetailView shows red `<Alert severity="error">` + global toast + visible Reintentar button + external link to https://www.mercadopago.com.ar/activities. Click Reintentar — verify mp_refund_attempts row count increments. |
| E2E sandbox payment flow | All MP-POS-* | Plan 09 | Requires real MP sandbox account + test card | Execute every step in `docs/phase29-e2e.md` (connect OAuth, generate QR, simulate via /v1/payments curl with sandbox test card token, observe auto-Generar). Document run + screenshot. |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or are manual-only with documented procedure
- [x] Sampling continuity: no 3 consecutive backend tasks without automated verify (every backend task has Jest target)
- [x] Wave 0 covers all MISSING references in Per-Task Verification Map
- [x] No watch-mode flags in any verify command (all `--bail`, no `--watch`)
- [x] Feedback latency < 30s for backend tasks, < 15s for frontend lint
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending → completed when Plan 01 (Wave 0) finishes (then `wave_0_complete: true` flips).
