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

## Step 6 — Test refund

1. Navigate to /ventas, find the test sale
2. Click "Anular venta" → confirm
3. **Verify:** mp_refunds row created with refund_id, amount=30000
4. **Verify:** mp_movements has new debit row, mp_wallets.balance back to 0

## Step 7 — Test refund failure UX

1. Simulate failure: temporarily edit MP App in sandbox panel to revoke OAuth → token decryption succeeds but MP API returns 401
2. Anular another MP sale
3. **Verify:** SalesDetailView shows inline Alert "Devolución MP fallida" + global toast + retry button + MP Dashboard link
4. **Verify (DB):** mp_refund_attempts row with status='failed', error_message populated
5. Restore OAuth, click "🔄 Reintentar devolución"
6. **Verify:** mp_refund_attempts gets attempt_no=2 with status='success', mp_refunds row created

## Pass criteria

All steps 1–7 verified. SPEC §Acceptance Criteria items 1–22 all manually checked off.
