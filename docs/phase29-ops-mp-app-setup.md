# Phase 29 — Mercadopago App Setup (Ops Procedure)

**Audience:** Operations engineer provisioning the Ventago production environment.
**Estimated time:** 30 minutes (assumes pre-existing MP business account).
**Required before:** Phase 29 Wave 1 deployment.

## Step 1 — Create MP Production App

1. Login to https://www.mercadopago.com.ar/developers/panel as the Ventago business MP owner.
2. Click "Tus integraciones" → "Crear aplicación".
3. Fill in:
   - Name: `Ventago POS`
   - Solution: `Pagos online y presenciales`
   - Product: `QR Dinámico` + `Checkout` (forward-compat for Phase 31)
4. Save. Note the resulting `Client ID` and `Client Secret` for production.

## Step 2 — Create MP Sandbox App

1. Same panel → click `Test users` → create a test seller.
2. The test seller automatically gets sandbox `Client ID` / `Client Secret` (different from prod).
3. Note these as sandbox credentials.

## Step 3 — Configure Redirect URI (production app + sandbox app)

1. In each MP App settings → OAuth section
2. Add redirect URI: `https://newapi.coolsistema.com/api/mercadopago/oauth/callback`
3. Save

## Step 4 — Configure Webhook URL

1. In production MP App settings → Notifications/Webhooks section
2. Add URL: `https://newapi.coolsistema.com/api/mercadopago/webhook`
3. Subscribe to `payment` events (ignore merchant_order — RESEARCH §Open Q3)
4. Note: QR webhook signature is unavailable per MP docs — Ventago re-fetches via API

## Step 5 — Generate AES-256-GCM master key

Run on ops local machine (NOT on production server, NOT in CI):
```
openssl rand -hex 32
```
Output is a 64-char hex string (32 bytes). This becomes `MP_TOKEN_ENCRYPTION_KEY`.

**CRITICAL:** Save this in a secure password vault (1Password, Bitwarden). If lost, all stored MP tokens become unrecoverable and all stores must re-OAuth.

## Step 6 — Generate OAuth state HMAC secret

Same as Step 5:
```
openssl rand -hex 32
```
This becomes `MP_OAUTH_STATE_SECRET`. Same vault discipline.

## Step 7 — Provision env vars on production (srv803182)

1. SSH to production: `ssh jhkim-server`
2. Edit api-ventago Docker Compose env file (location: `/opt/api-ventago/.env` or compose `environment:` block — verify with team).
3. Add the 8 MP_* vars:
   ```
   MP_PRODUCTION_CLIENT_ID=<from Step 1>
   MP_PRODUCTION_CLIENT_SECRET=<from Step 1>
   MP_SANDBOX_CLIENT_ID=<from Step 2>
   MP_SANDBOX_CLIENT_SECRET=<from Step 2>
   MP_TOKEN_ENCRYPTION_KEY=<from Step 5>
   MP_OAUTH_STATE_SECRET=<from Step 6>
   MP_WEBHOOK_SECRET=<from MP App Webhooks page if available, else empty>
   MP_NOTIFICATION_BASE_URL=https://newapi.coolsistema.com/api
   ```
4. `docker compose up -d --no-recreate api_ventago` — restart api container with new env

## Step 8 — Verify boot

Backend will fail-fast at boot if `MP_TOKEN_ENCRYPTION_KEY` length is wrong:
```
Error: MP_TOKEN_ENCRYPTION_KEY must be 32 bytes hex (64 hex chars)
```
Check: `docker logs api_ventago | tail -30`

Successful boot = no `MP_TOKEN_ENCRYPTION_KEY` errors. Service is ready for first OAuth.

## Rollback / Key rotation

Out of scope for Phase 29 (RESEARCH §Assumption A8). If rotation needed in future:
1. Decrypt all access_tokens with old key → re-encrypt with new key (single SQL transaction)
2. Update env var → restart container
3. NEVER swap key without re-encrypt — all tokens become unrecoverable
