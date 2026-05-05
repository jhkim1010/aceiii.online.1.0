# Phase 29 — Sandbox E2E Test Script

**Purpose:** Manual end-to-end verification that Mercadopago QR Dinámico flow works in sandbox before any production deployment.

**Prerequisites:**
- Phase 29 deployed to dev or staging (all waves complete)
- MP sandbox App credentials provisioned (`MP_SANDBOX_CLIENT_ID` + `MP_SANDBOX_CLIENT_SECRET`)
- MP test user account (Vendedor side) created at https://www.mercadopago.com.ar/developers/panel/test-users
- MP test user account (Comprador side) for paying the QR
- Webhook reachable from MP — for local dev use ngrok or `ssh -R 5002:localhost:5002 jhkim-server`
- At least 1 test user (admin role) in Ventago

## Step 1 — Connect OAuth (sandbox)

1. Login to Ventago as admin → Configuración → Mercadopago
2. Click "Conectar cuenta Mercadopago" with environment toggle = sandbox
3. Browser redirects to `auth.mercadopago.com.ar/authorization?...&state=<HMAC>`
4. Login as MP TEST VENDEDOR account; approve scope
5. Browser returns to `/configuracion/mercadopago?ok=1`
6. **Verify:** Page shows account card with `🧪 SANDBOX` chip + `✓ Conectada`
7. **Verify (DB):** `SELECT id, store_id, branch_id, environment, mp_user_id, external_pos_id FROM mp_accounts;` shows 1 row, `external_pos_id IS NOT NULL`
8. **Verify (DB):** `SELECT * FROM mp_wallets WHERE mp_account_id = <id>;` shows 1 row, balance=0
9. **Verify (DB):** access_token in mp_accounts is NOT plaintext (contains `:` separators per AES-GCM format `iv:tag:ciphertext`)

## Step 2 — Generate QR + observe sandbox banner

1. Navigate to `/nueva-venta`
2. **Verify:** Orange banner "🧪 SANDBOX MERCADOPAGO ACTIVO" mounted at top of page
3. Add a product worth $30,000 ARS to cart
4. Press F2 (or click "Generar Venta") → PaymentSummaryModal opens
5. Select "Mercadopago QR" payment method, enter amount 30000
6. **Verify:** Modal expands to 920px wide, side-panel renders QR code with orange border-left
7. **Verify:** Countdown text shows "3:00" and decrements 1/sec
8. **Verify (DB):** `SELECT id, status, qr_data, expires_at FROM mp_payment_intents ORDER BY id DESC LIMIT 1;` shows status='pending', qr_data IS NOT NULL

## Step 3 — Simulate payment

**Option A (recommended): real MP test app scan**
1. Open MP app on phone, login as MP TEST COMPRADOR
2. Scan QR from screen
3. Approve payment

**Option B (fallback): curl POST /v1/payments**
Use this if MP test app cannot scan QRs. Run from ops machine:
```
curl -X POST https://api.mercadopago.com/v1/payments \
  -H "Authorization: Bearer <COMPRADOR_TEST_USER_ACCESS_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "transaction_amount": 30000,
    "external_reference": "<intent_id>",
    "payment_method_id": "account_money",
    "payer": { "email": "test_comprador@testuser.com" }
  }'
```

## Step 4 — Observe auto Generar Venta

1. Within ~5 seconds (webhook) or ~10 seconds (polling fallback) the modal:
   - Shows "✓ Pago confirmado" green flash
   - Shows "Generando venta…" subtext
   - Auto-closes after ~600ms
2. Toast appears: "✓ Pago Mercadopago recibido — generando venta"
3. Sale row created with paymentMethods including mp_payment_id
4. **Verify (DB):** `SELECT id, payment_id, status, approved_at FROM mp_payment_intents ORDER BY id DESC LIMIT 1;` shows status='approved', payment_id IS NOT NULL
5. **Verify (DB):** `SELECT id, type, amount FROM mp_movements ORDER BY id DESC LIMIT 1;` shows type='credit', amount=30000
6. **Verify (DB):** `SELECT balance FROM mp_wallets WHERE mp_account_id=<id>;` shows balance=30000
7. **Verify (DB):** `SELECT id, payment_methods FROM sales ORDER BY id DESC LIMIT 1;` shows paymentMethods JSONB contains slug='mercadopago' + mp_payment_id

## Step 5 — Test polling fallback

1. Block webhook by adding firewall rule (or stop nginx for /api/mercadopago/webhook)
2. Repeat Steps 2–3
3. **Verify:** Modal still auto-closes within ~10 seconds (SWR poll detects status='approved')
4. Restore webhook

## Step 6 — Test refund (happy path)

1. Navigate to `/ventas`, find the test MP sale (status='Facturado')
2. Open detail view → click "Anular venta" button → confirm modal
3. **Verify (UI):** Sale status flips to "Anulado"; reversal sale appears with `[ANULACIÓN]` notes
4. **Verify (DB):**
   ```sql
   SELECT id, refund_id, amount, status FROM mp_refunds ORDER BY id DESC LIMIT 1;
   -- Expect: refund_id IS NOT NULL, amount=30000, status='approved'
   ```
5. **Verify (DB):**
   ```sql
   SELECT type, amount FROM mp_movements ORDER BY id DESC LIMIT 1;
   -- Expect: type='refund_debit', amount=30000
   ```
6. **Verify (DB):**
   ```sql
   SELECT balance FROM mp_wallets WHERE mp_account_id=<id>;
   -- Expect: balance=0 (back to zero)
   ```
7. **Verify (DB):**
   ```sql
   SELECT attempt_no, status FROM mp_refund_attempts
   WHERE sale_id=<original_sale_id> ORDER BY attempt_no;
   -- Expect: attempt_no=1, status='success'
   ```

## Step 7 — Test refund failure UX (inline Alert + Toast + Retry + Dashboard + History)

**Force failure:**
1. Simulate failure — pick one:
   - **Option A:** In MP sandbox panel, temporarily revoke the App OAuth grant for that test user → token still decrypts but MP API returns 401
   - **Option B:** Block outbound HTTPS to `api.mercadopago.com` from the api-ventago Docker container (network firewall) → axios timeout/connection error
2. Create a new MP sale (Steps 2–4 in this doc)
3. Anular the new sale → confirm

**Verify all 5 UX elements visible (UI-SPEC Surface 5):**
4. **Inline Alert** — SalesDetailView shows `<Alert severity="error">` with title "⚠️ Devolución MP fallida"
5. **Error code block** — monospace inline `<code>` shows "MP API: ..." with the actual error message (red backdrop)
6. **Action buttons (3, in row):**
   - "🔄 Reintentar devolución" (red filled button)
   - "↗ Abrir MP Dashboard" (outlined, opens https://www.mercadopago.com.ar/activities in new tab)
   - "Ver historial (N intentos)" (text button, scrolls to attempt list)
7. **Global toast** — react-toastify error toast at bottom-right (auto-dismiss 5s)
8. **Historial de intentos** — always-visible attempt grid below Alert with mono rows: `#1 | FAILED | error_message | HH:mm:ss`

**Verify backend state:**
9. **Verify (DB):**
   ```sql
   SELECT attempt_no, status, error_message FROM mp_refund_attempts
   WHERE sale_id=<sale_id> ORDER BY attempt_no;
   -- Expect: attempt_no=1, status='failed', error_message populated
   ```
10. **Verify (DB):** `mp_refunds` for this sale_id has NO row (no successful refund INSERT)
11. **Verify (DB):** `mp_wallets.balance` UNCHANGED from before nullify (no debit applied)
12. **Verify (Sale):** Original sale status STILL 'Anulado' (sale always nullified, D-A4-03)

**Test retry path:**
13. Restore OAuth (revert revocation) or unblock network
14. Click "🔄 Reintentar devolución" → button shows "⏳ Procesando…" briefly
15. Toast: "✓ Devolución Mercadopago completada"
16. Historial de intentos updates: `#2 | SUCCESS | — | HH:mm:ss` (new row, attempt_no=2)
17. **Verify (DB):**
    ```sql
    SELECT refund_id FROM mp_refunds WHERE sale_id=<sale_id>;
    -- Expect: 1 row, refund_id IS NOT NULL
    ```
18. **Verify (DB):** `mp_wallets.balance` decremented to original − refund amount
19. **Verify (idempotency):** Click retry again → backend uses NEW idempotency-key
    `refund-{saleId}-3` → MP returns existing refund object → `mp_refunds.refund_id` UNIQUE
    constraint blocks duplicate INSERT → attempt #3 marked failed (or success, depending on
    how you wired). Either way: `mp_wallets.balance` does NOT double-debit.

## Pass criteria

All steps 1–7 verified. SPEC §Acceptance Criteria items 1–22 all manually checked off.

## Phase 29 acceptance — all 22 SPEC criteria

After all E2E steps pass, walk through `.planning/phases/29-pos-mercadopago-qr-din-mico/29-SPEC.md` Acceptance Criteria checklist (lines 113–138). All 22 items should be checkable.

**Plans completed:**

| Plan | Wave | Description |
|------|------|-------------|
| 29-01 | 0 | Pre-flight (qrcode.react@4.2.0 + 8 MP_* env vars + 3 fixtures + axios mock helper + 2 ops docs) |
| 29-02 | 1 | DB migrations — 7 mp_* tables (PG10/PG15 compat, partial UNIQUE indexes, VARCHAR+CHECK over ENUM) |
| 29-02b | 1 | 7 Sequelize-typescript models + MercadopagoModule re-exports SequelizeModule |
| 29-03 | 2 | OAuth (HMAC state) + MP API client + Store/POS registration + account resolver |
| 29-04 | 3 | QR Dinámico generation + intent polling endpoint |
| 29-05 | 4 | Webhook receiver + Socket.io emitToTerminal + wallet credit on success |
| 29-06 | 5 | Frontend OAuth UI page (configuracion/mercadopago) — store + branch toggle |
| 29-07 | 6 | Frontend POS UI — orange sandbox banner + PaymentSummaryModal MP QR side-panel + auto-trigger |
| 29-08 | 6 | Caja MP backend — transfer service + 2 cron jobs (wallet reconcile + token refresh) |
| 29-08b | 6 | Caja MP frontend — useMpWallets/useMpMovements + 3 components + CashControlList integration |
| 29-09 | 7 | Refunds — auto-call on nullifySale + retry endpoint + SalesDetailView refund failure UX |

**Production deploy checklist:**

1. Migrations 29-01 through 29-05 ready to run on srv803182 via the procedure documented in `api-ventago/migrations/29-RUN.md`
2. Production env vars provisioned per `docs/phase29-ops-mp-app-setup.md`:
   - `MP_PRODUCTION_CLIENT_ID` / `MP_PRODUCTION_CLIENT_SECRET`
   - `MP_SANDBOX_CLIENT_ID` / `MP_SANDBOX_CLIENT_SECRET`
   - `MP_TOKEN_ENCRYPTION_KEY` (64-char hex AES-256-GCM master key)
   - `MP_WEBHOOK_SECRET` (global webhook HMAC SHA256 secret)
   - `MP_OAUTH_STATE_SECRET` (HMAC for OAuth state CSRF protection)
   - `MP_OAUTH_REDIRECT_URI` = `https://newapi.coolsistema.com/api/mercadopago/oauth/callback`
3. MP Developer App configured with notification URL `https://newapi.coolsistema.com/api/mercadopago/webhook` (no per-store webhook secret needed — single global)
4. Run final test suite before deploy:
   ```bash
   cd api-ventago && npm test -- --testPathPattern=mercadopago
   cd ventago-app && npm run lint
   cd ventago-app && npm run build
   cd api-ventago && npm run build
   ```
   All must exit 0.

**Acceptance result:** record below after walkthrough.

```
[ ] 22/22 SPEC items pass
[ ] All E2E Steps 1–7 verified
[ ] Production migration plan reviewed
[ ] Phase 29 sign-off
```
