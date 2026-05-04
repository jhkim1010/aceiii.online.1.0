# Phase 29: POS Mercadopago — QR Dinámico - Research

**Researched:** 2026-05-05
**Domain:** Payments integration (Mercadopago QR Dinámico, OAuth 2.0, webhooks, Socket.io push, encrypted token storage)
**Confidence:** HIGH (Mercadopago APIs verified against official docs + npm registry; codebase patterns verified by Read/Grep)

## Summary

Phase 29 introduces Mercadopago QR Dinámico as a first-class POS payment method in Ventago. The integration spans 5 conceptual surfaces: (1) **OAuth 2.0** account linking with AES-256-GCM encrypted token storage scoped per (store_id, branch_id?), (2) **MP Store + POS REST registration** as a one-time setup per scope so QR generation has a `{user_id}/{external_pos_id}` target, (3) **QR Dinámico generation** via `POST /instore/orders/qr/seller/collectors/{user_id}/pos/{external_pos_id}/qrs` with `external_reference = pendingVentaId`, (4) **Webhook receiver** that re-fetches MP as canonical truth (QR notifications cannot be HMAC-verified per MP docs — `x-signature` exists for non-QR webhooks but the QR pathway must call the MP REST API back to confirm), and (5) **Socket.io push to a single terminal** via a new `emitToTerminal(terminalId, ...)` method so the frontend auto-triggers `handleSubmit("INVOICED", ...)`. A 5-second SWR `refreshInterval` polling fallback covers webhook delays. Refunds call `POST /v1/payments/{id}/refunds` with `X-Idempotency-Key` and a "Caja Mercadopago" virtual wallet stays in sync via `mp_movements`.

Two non-obvious landmines drive the architecture:
1. **MP QR webhooks are NOT signature-verifiable** — the official x-signature HMAC scheme explicitly excludes QR Code notifications [CITED: mercadopago.com.ar/developers/.../webhooks]. Security MUST come from immediately re-fetching the order via the collector's access_token and treating the MP API response as authoritative.
2. **MP Store + POS must be registered out-of-band before any QR can be generated** — `external_pos_id` is required in the QR creation URL [CITED: mercadopago.com.ar/.../create-store-and-pos]. This is a separate REST flow (POST `/users/{user_id}/stores`, POST `/pos`) that runs once per OAuth-connected scope, not per sale. The CONTEXT.md does not mention this — planner must add it as a step after OAuth completes.

**Primary recommendation:** Use **raw axios + dedicated `MercadopagoApiClient` service** (not the official `mercadopago` npm SDK). The SDK v2.12 covers Orders/Payments/OAuth but does NOT wrap the `/instore/orders/qr/...` endpoints, so we'd be mixing SDK calls with raw HTTP anyway — better to standardize on one HTTP client with consistent error handling, logging, retry, and per-request token injection (multiple stores → multiple access_tokens). Use `qrcode.react@4.2.0` (`<QRCodeSVG>`) for frontend rendering. Implement AES-256-GCM directly with Node `crypto` — no library needed.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| OAuth authorize redirect | Frontend (browser) | API (callback) | Browser must follow MP authorize URL (3rd party redirect); API receives the `?code=` callback and exchanges for tokens |
| OAuth token exchange + storage | API | Database | MP `client_secret` is server-only; AES-256-GCM master key in env, never sent to browser |
| MP Store/POS registration | API (one-shot per OAuth) | Database | Background admin operation; result `external_pos_id` stored on `mp_accounts` |
| QR Dinámico generation | API | MP REST | Frontend posts `{ amount, pendingVentaId }` only; API uses correct token + pos_id and returns `qr_data` string |
| QR rendering | Frontend (React) | — | `qrcode.react` SVG; pure client-side, no server image generation |
| Countdown timer (3:00 → 0:00) | Frontend (React) | — | Pure UI state; backend just records `expires_at` for safety |
| Webhook receiver | API | MP REST (re-fetch) | Public endpoint, must re-call `/v1/payments/{id}` or `/merchant_orders/{id}` to verify (signature unavailable for QR) |
| Idempotency lock | API + Database | — | `mp_payment_intents.payment_id UNIQUE` + `SELECT FOR UPDATE` in transaction |
| Real-time push to terminal | API (Socket.io gateway) | Frontend (room subscriber) | New `emitToTerminal(terminalId, ...)` + frontend joins `terminal:{id}` on connect |
| Polling fallback | Frontend (SWR) | API | `useSWR(intentId, { refreshInterval: 5000 })`; backend reads `mp_payment_intents.status` (which webhook already updated, or is still `pending`) |
| Auto Generar Venta trigger | Frontend (PaymentSummaryModal) | — | On `mercadopago:approved` event OR SWR sees status=approved → call existing `handleSubmit("INVOICED", ...)` |
| Refund (devolución) | API | MP REST + Database | `nullifySale` extension calls `POST /v1/payments/{id}/refunds` with idempotency key; on success record `mp_refunds` + debit `mp_movements` |
| "Caja MP" virtual wallet | API | Database | Separate `mp_wallets`/`mp_movements` tables; no `box` table changes |
| MP→Cash transfer | API | Database (transactional) | Atomic: debit `mp_movements`, credit `box` `movements`, adjust both balances |
| Sandbox/production toggle | Database (per mp_account) | API (host selection) | `mp_accounts.environment` ENUM controls which `MP_*` env credentials and which `auth.mercadopago.com.ar` URL to use |

## Standard Stack

### Core (new dependencies for this phase)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `qrcode.react` | 4.2.0 | Frontend QR SVG rendering | Industry-standard React QR component; `<QRCodeSVG>` named export; React 18 in peer deps; ~115KB unpacked [VERIFIED: npm view qrcode.react] |
| `axios` | ^1.4.0 (already installed) | HTTP client for MP REST calls | Already in `api-ventago/package.json`; consistent error model with NestJS exception filter |

### Already Available (no install needed)

| Library | Version | Purpose |
|---------|---------|---------|
| `@nestjs/schedule` | ^6.1.1 | Cron for refresh-token D-7 alert + nightly mp_wallets reconciliation [VERIFIED: api-ventago/package.json] |
| `@nestjs/config` | ^4.0.2 | Reading `MP_PRODUCTION_*` / `MP_SANDBOX_*` / `MP_TOKEN_ENCRYPTION_KEY` / `MP_WEBHOOK_SECRET` env vars |
| `class-validator` | 0.14.1 | DTO validation (CreateMpQrDto, MpWebhookDto, MpRefundDto) |
| `swr` | ^2.4.1 | Frontend `refreshInterval=5000` polling [VERIFIED: ventago-app/package.json] |
| `socket.io-client` | 4.8.3 | Frontend `terminal:{id}` room join [VERIFIED: ventago-app/package.json] |
| `node:crypto` | builtin | AES-256-GCM (`createCipheriv`/`createDecipheriv`/`getAuthTag`) + HMAC-SHA256 |
| `pg` | ^8.13.1 | Existing pool — REUSE, do NOT add a second pool [CLAUDE.md hard rule] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff | Decision |
|------------|-----------|----------|----------|
| Raw axios for MP API | `mercadopago` npm SDK 2.12.0 | SDK wraps Orders/Payments/OAuth/Refunds nicely with `requestOptions.idempotencyKey`, but does NOT wrap `/instore/orders/qr/...` endpoints — we'd mix SDK + raw HTTP [VERIFIED: github.com/mercadopago/sdk-nodejs] | **Use raw axios** — single HTTP layer, consistent error handling, easier to inject per-store access_token |
| `qrcode.react` | `react-qr-code` | Both work; `qrcode.react` has more downloads + better Next.js 13 server-component handling | **qrcode.react** matches CONTEXT.md decision D-A4-01 |
| `sequelize-encrypted` for column encryption | Direct AES-GCM in service layer | Plugin adds dependency for ~30 lines of crypto code; explicit service is clearer for security audit | **Direct `crypto` module** in `MpTokenCryptoService` |
| Redis lock for webhook idempotency | DB UNIQUE + SELECT FOR UPDATE | CONTEXT.md D-A2-04 explicitly forbids extra infra | **DB-only** as decided |

**Installation:**
```bash
# Frontend only — backend has everything already
cd ventago-app && npm install qrcode.react@^4.2.0
```

**Version verification (run during implementation):**
```bash
npm view qrcode.react version  # → 4.2.0 [VERIFIED 2026-05-05]
npm view mercadopago version   # → 2.12.0 (NOT installed; not needed)
```

## Architecture Patterns

### System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              SETUP PATH (one-time per scope)                     │
│                                                                                  │
│  ventago-app                  api-ventago                  Mercadopago           │
│  ───────────                  ───────────                  ───────────           │
│  configuracion/      →  GET /api/mp/oauth/start            (state HMAC sign)     │
│   mercadopago               (storeId, branchId?)                                 │
│        │                          │                                              │
│        ↓                  redirect 302                                           │
│  auth.mercadopago.com.ar/authorization?client_id=...&state=...                   │
│        │                                                                          │
│        ↓ user logs in to MP, approves                                            │
│  GET /api/mp/oauth/callback?code=...&state=...                                   │
│                                   │                                              │
│                                   ↓ POST /oauth/token (auth code grant)          │
│                                   ↓ POST /users/{user_id}/stores  (one-time)     │
│                                   ↓ POST /pos                     (one-time)     │
│                                   ↓ encrypt tokens AES-GCM, INSERT mp_accounts  │
│                                   ↓ INSERT mp_wallets (balance=0)                │
│                                   ↓ redirect to configuracion/mercadopago?ok=1   │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                              SALE PATH (per QR payment)                          │
│                                                                                  │
│  PaymentSummaryModal           api-ventago                Mercadopago             │
│  ──────────────────           ───────────                ───────────             │
│  user picks "MP QR"     POST /api/mp/qr                                          │
│  amount=30000        →  { storeId, branchId, amount, pendingVentaId, terminalId }│
│                                   │                                              │
│                                   ↓ lookup mp_account (branch first, store fb)   │
│                                   ↓ INSERT mp_payment_intents (status=pending)  │
│                                   ↓ POST /instore/orders/.../qrs                 │
│                                   │   external_reference=intentId,               │
│                                   │   notification_url=/api/mp/webhook,          │
│                                   │   total_amount, items[]                      │
│                                   ↓                  ← { qr_data, in_store_order_id }
│                                   ↓ UPDATE intent.qr_data, mp_order_id          │
│                              ←  { intentId, qrData, expiresAt }                  │
│  render <QRCodeSVG>                                                              │
│  countdown 3:00 → 0:00                                                           │
│  start SWR poll every 5s ─→ GET /api/mp/payment-intents/:id  ──┐                 │
│                                                                 │                │
│  ╔═══ customer scans + pays in MP app ═══╗                     │                │
│                          │                                      │                │
│                          ↓                                      │                │
│                  Mercadopago sends webhook                      │                │
│                          ↓                                      │                │
│         POST /api/mp/webhook { type:"payment", data.id }                         │
│                                   ↓ NO signature for QR — re-fetch as truth     │
│                                   ↓ GET /v1/payments/{id} (collector token)      │
│                                   ↓ status === 'approved'?                       │
│                                   ↓ BEGIN TX                                     │
│                                   ↓   SELECT FOR UPDATE intent WHERE id=...      │
│                                   ↓   if intent.payment_id IS NULL:              │
│                                   ↓     UPDATE intent SET payment_id=$1, status='approved'
│                                   ↓     INSERT mp_movements (credit, sale_id NULL yet)
│                                   ↓     UPDATE mp_wallets.balance += amount      │
│                                   ↓   else: skip (already processed)             │
│                                   ↓ COMMIT                                       │
│                                   ↓ websocket.emitToTerminal(terminalId,         │
│                                   │   'mercadopago:approved', { intentId, amount, paymentId })
│                              ←  return 200 OK to MP                              │
│                                                                 │                │
│  socket.on('mercadopago:approved') ──┐                          │                │
│  OR SWR sees status='approved'  ─────┴──→ both paths same:      │                │
│  handleSubmit("INVOICED", paymentMethods)  ←──── (already idempotent — UI state) │
│         │                                                                         │
│         ↓ POST /sales (existing endpoint, unchanged contract)                    │
│         ↓ sale row created with paymentMethods including mp_payment_id           │
│         ↓ if autoImpTiq: emit print job                                          │
│  toast "Venta creada"                                                            │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                            REFUND PATH (nullifySale)                             │
│                                                                                  │
│  SalesDetailView         api-ventago                      Mercadopago             │
│  ───────────────         ───────────                      ───────────             │
│  click "Anular"  →  POST /api/sales/:id/nullify                                  │
│                              ↓ existing nullifySale logic                        │
│                              ↓ for each payment slug==='mercadopago':            │
│                              ↓   INSERT mp_refund_attempts (attempt_no=1, status='pending')
│                              ↓   POST /v1/payments/{mp_payment_id}/refunds       │
│                              ↓     X-Idempotency-Key: refund-{saleId}-{attempt}  │
│                              ↓     body: { amount } (omit for full)              │
│                              ↓   if 200/201:                                     │
│                              ↓     INSERT mp_refunds (refund_id, amount)         │
│                              ↓     INSERT mp_movements (debit, refund_id)        │
│                              ↓     UPDATE mp_wallets.balance -= amount           │
│                              ↓     UPDATE mp_refund_attempts.status='success'    │
│                              ↓   else:                                           │
│                              ↓     UPDATE mp_refund_attempts.status='failed',    │
│                              ↓                                  error_message=..  │
│                              ↓     return { saleNullified: true, mpRefundFailed: true, errorMsg }
│  if mpRefundFailed:                                                              │
│    show inline <Alert severity="error">                                          │
│    show toast.error                                                              │
│    show <Button>Reintentar</Button> → POST /api/mp/refunds/retry/:attemptId      │
│    show <Link href="https://www.mercadopago.com.ar/activities">                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Recommended Project Structure

```
api-ventago/src/app/
├── mercadopago/                  ← NEW MODULE
│   ├── mercadopago.module.ts     ← imports SequelizeModule.forFeature([7 models])
│   ├── mercadopago.controller.ts ← /api/mercadopago/* HTTP endpoints
│   ├── mercadopago.service.ts    ← orchestrator (called by sales for refunds)
│   ├── oauth/
│   │   ├── mp-oauth.service.ts        ← state signing, token exchange, refresh
│   │   └── mp-oauth.controller.ts     ← /oauth/start, /oauth/callback, /disconnect
│   ├── api-client/
│   │   ├── mp-api-client.service.ts   ← raw axios wrapper, per-call token injection
│   │   └── mp-store-pos.service.ts    ← Store/POS registration (one-time)
│   ├── crypto/
│   │   └── mp-token-crypto.service.ts ← AES-256-GCM encrypt/decrypt
│   ├── webhook/
│   │   ├── mp-webhook.controller.ts   ← /webhook
│   │   └── mp-webhook.service.ts      ← re-fetch MP, idempotent intent update, emit Socket.io
│   ├── qr/
│   │   ├── mp-qr.controller.ts        ← /qr (create), /qr/:id (cancel)
│   │   └── mp-qr.service.ts           ← intent lifecycle
│   ├── intents/
│   │   ├── mp-payment-intents.controller.ts  ← /payment-intents/:id (polling endpoint)
│   │   └── mp-payment-intents.service.ts     ← shared intent lookups
│   ├── wallet/
│   │   ├── mp-wallet.service.ts       ← balance + reconciliation cron
│   │   ├── mp-wallet.controller.ts    ← /wallets, /movements, /transfers
│   │   └── mp-transfer.service.ts     ← MP→cash transactional move
│   ├── refunds/
│   │   ├── mp-refund.service.ts       ← called by sales nullifySale extension
│   │   └── mp-refund.controller.ts    ← /refunds/retry/:attemptId
│   ├── models/
│   │   ├── mp-account.model.ts
│   │   ├── mp-payment-intent.model.ts
│   │   ├── mp-wallet.model.ts
│   │   ├── mp-movement.model.ts
│   │   ├── mp-refund.model.ts
│   │   ├── mp-refund-attempt.model.ts
│   │   └── mp-transfer.model.ts
│   ├── dto/
│   │   ├── create-mp-qr.dto.ts
│   │   ├── mp-webhook.dto.ts
│   │   ├── transfer-mp-to-cash.dto.ts
│   │   └── retry-refund.dto.ts
│   ├── guards/
│   │   └── mp-webhook-public.guard.ts ← marks endpoint as @Public (no JWT)
│   └── cron/
│       ├── mp-token-refresh.cron.ts   ← daily check expires_at, refresh + D-7 alert
│       └── mp-wallet-reconcile.cron.ts ← nightly recompute balance from movements

api-ventago/migrations/
├── 29-01-mp-accounts.sql              ← mp_accounts table
├── 29-02-mp-payment-intents.sql       ← + UNIQUE(payment_id)
├── 29-03-mp-wallets-movements.sql     ← mp_wallets + mp_movements
├── 29-04-mp-refunds.sql               ← mp_refunds + mp_refund_attempts
├── 29-05-mp-transfers.sql             ← mp_transfers
└── 29-99-rollback.sql

ventago-app/src/
├── pages/configuracion/mercadopago/index.tsx    ← NEW PAGE
├── views/mercadopago/
│   ├── McdpgConfigView.tsx                       ← OAuth connect/disconnect UI
│   ├── components/
│   │   ├── McdpgAccountCard.tsx                  ← store/branch row
│   │   ├── McdpgBranchToggleTable.tsx
│   │   └── McdpgEnvironmentBadge.tsx
│   └── hooks/
│       ├── useMpAccounts.ts                      ← SWR /api/mercadopago/accounts
│       └── useMpPaymentIntent.ts                 ← SWR refreshInterval=5000
├── views/cash-control/components/
│   └── McdpgWalletRow.tsx                        ← "Caja Mercadopago" row + transfer button
├── views/homes/components/ProductList/components/
│   ├── PaymentSummaryModal.tsx (MODIFY)          ← add MP row + QR display
│   └── McdpgQrPanel.tsx                          ← NEW <QRCodeSVG> + countdown + cancel button
└── components/banners/
    └── SandboxMpBanner.tsx                       ← orange Alert at top of nueva-venta

api-ventago/src/common/socket/
└── websocket.service.ts (MODIFY)                  ← add terminalClients Map + emitToTerminal
└── websocket.gateway.ts  (MODIFY)                 ← add @SubscribeMessage('register_terminal')
```

### Pattern 1: Per-call MP API access_token injection

**What:** Each MP API call gets its own decrypted access_token from the matching `mp_account` row. No global "current token" — it's always passed in.

**When to use:** Every call into `MpApiClientService` from any service.

**Example:**
```typescript
// api-ventago/src/app/mercadopago/api-client/mp-api-client.service.ts
// Source: pattern derived from axios docs + multi-tenant requirement
@Injectable()
export class MpApiClientService {
  private readonly logger = new Logger(MpApiClientService.name);

  async post<T>(
    path: string,
    body: any,
    accessToken: string,
    opts?: { idempotencyKey?: string; baseUrl?: string },
  ): Promise<T> {
    const baseUrl = opts?.baseUrl ?? 'https://api.mercadopago.com';
    const headers: Record<string, string> = {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    };

    if (opts?.idempotencyKey) {
      headers['X-Idempotency-Key'] = opts.idempotencyKey;
    }

    try {
      const res = await axios.post<T>(`${baseUrl}${path}`, body, {
        headers,
        timeout: 10_000,
      });

      return res.data;
    } catch (err: any) {
      // 에러 사용자 노출 정책 (CLAUDE.md 메모리): inline + toast 모두
      const status = err?.response?.status;
      const mpError = err?.response?.data;

      this.logger.error(
        `MP API ${path} failed: ${status} ${JSON.stringify(mpError)}`,
      );
      throw new BadRequestException({
        message: 'Mercadopago API error',
        mpStatus: status,
        mpError,
      });
    }
  }
  // ... get, put, delete with same per-call token pattern
}
```

### Pattern 2: AES-256-GCM token encryption

**What:** Encrypt access_token / refresh_token before storing; decrypt at read time.

**Example:**
```typescript
// api-ventago/src/app/mercadopago/crypto/mp-token-crypto.service.ts
// Source: Node crypto docs + OWASP key-management recommendation [CITED: nodejs.org/api/crypto]
import { Injectable } from '@nestjs/common';
import { createCipheriv, createDecipheriv, randomBytes } from 'crypto';

const ALGO = 'aes-256-gcm';
const IV_LEN = 12;     // 96-bit, GCM standard
const TAG_LEN = 16;

@Injectable()
export class MpTokenCryptoService {
  private readonly key: Buffer;

  constructor() {
    const hex = process.env.MP_TOKEN_ENCRYPTION_KEY;
    if (!hex || hex.length !== 64) {
      throw new Error(
        'MP_TOKEN_ENCRYPTION_KEY must be 32 bytes hex (64 hex chars)',
      );
    }
    this.key = Buffer.from(hex, 'hex');
  }

  encrypt(plaintext: string): string {
    // 96-bit IV — NEVER reuse with same key (GCM security collapses)
    const iv = randomBytes(IV_LEN);
    const cipher = createCipheriv(ALGO, this.key, iv);
    const ct = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
    const tag = cipher.getAuthTag();

    // 형식: base64(iv) : base64(tag) : base64(ciphertext)
    return [iv.toString('base64'), tag.toString('base64'), ct.toString('base64')].join(':');
  }

  decrypt(encoded: string): string {
    const [ivB64, tagB64, ctB64] = encoded.split(':');
    if (!ivB64 || !tagB64 || !ctB64) {
      throw new Error('Invalid encrypted token format');
    }
    const decipher = createDecipheriv(ALGO, this.key, Buffer.from(ivB64, 'base64'));
    decipher.setAuthTag(Buffer.from(tagB64, 'base64'));
    const pt = Buffer.concat([
      decipher.update(Buffer.from(ctB64, 'base64')),
      decipher.final(),
    ]);

    return pt.toString('utf8');
  }
}
```

### Pattern 3: Idempotent webhook processing with SELECT FOR UPDATE

**Example:**
```typescript
// api-ventago/src/app/mercadopago/webhook/mp-webhook.service.ts
// Source: pattern derived from Postgres docs + CONTEXT.md D-A2-04
async processPayment(mpPaymentId: string, mpAccountId: number) {
  // 1) Re-fetch from MP (canonical truth — QR webhook signature unavailable)
  const account = await this.mpAccountModel.findByPk(mpAccountId);
  const accessToken = this.crypto.decrypt(account.accessToken);
  const payment = await this.mpApi.get<MpPayment>(
    `/v1/payments/${mpPaymentId}`,
    accessToken,
  );

  if (payment.status !== 'approved') {
    this.logger.log(`Payment ${mpPaymentId} status=${payment.status}, skipping`);

    return;
  }

  const intentId = Number(payment.external_reference);

  // 2) Atomic intent transition (SELECT FOR UPDATE inside transaction)
  await this.sequelize.transaction(async (t) => {
    const intent = await this.intentModel.findByPk(intentId, {
      lock: t.LOCK.UPDATE, // Sequelize-typescript SELECT ... FOR UPDATE
      transaction: t,
    });
    if (!intent) {
      this.logger.warn(`Intent ${intentId} not found for payment ${mpPaymentId}`);

      return;
    }
    if (intent.paymentId) {
      // Already processed by webhook or polling — no-op
      this.logger.log(`Intent ${intentId} already has payment_id, skip`);

      return;
    }
    await intent.update(
      { paymentId: mpPaymentId, status: 'approved', approvedAt: new Date() },
      { transaction: t },
    );
    // mp_movements credit + mp_wallets balance update inside same TX
    await this.walletService.creditOnSale(intent, payment, t);
  });

  // 3) Emit to terminal — outside transaction, fine if it fails (polling will catch)
  await this.websocket.emitToTerminal(intent.terminalId, 'mercadopago:approved', {
    intentId,
    paymentId: mpPaymentId,
    amount: payment.transaction_amount,
    capturedAt: payment.date_approved,
  });
}
```

### Pattern 4: Socket.io terminal room join

**Example:**
```typescript
// api-ventago/src/common/socket/websocket.service.ts (extension)
private terminalClients: Map<number, Set<string>> = new Map();

registerTerminal(client: Socket, terminalId: number) {
  this.clients.set(client.id, client);
  (client as any).terminalId = terminalId;
  client.join(`terminal:${terminalId}`); // socket.io room

  if (!this.terminalClients.has(terminalId)) {
    this.terminalClients.set(terminalId, new Set());
  }
  this.terminalClients.get(terminalId)!.add(client.id);
}

emitToTerminal(terminalId: number, event: string, payload: any) {
  // 두 가지 방식 중 socket.io room broadcast 가 더 효율적
  this.server.to(`terminal:${terminalId}`).emit(event, payload);
}
```

```typescript
// websocket.gateway.ts (extension)
@SubscribeMessage('register_terminal')
handleRegisterTerminal(
  @ConnectedSocket() client: Socket,
  @MessageBody() data: { terminalId: number },
) {
  if (data?.terminalId) {
    this.websocketService.registerTerminal(client, data.terminalId);
  }
}
```

```typescript
// ventago-app: hooks/useMpRealtime.ts
// Frontend joins terminal room when cashRegister.terminal.id is known
useEffect(() => {
  const terminalId = cashRegister?.terminal?.id;
  if (!terminalId) return;
  const socket = io(WS_URL, { transports: ['websocket'] });
  socket.on('connect', () => {
    socket.emit('register_terminal', { terminalId });
  });
  socket.on('mercadopago:approved', (payload) => {
    onMpApproved(payload);
  });

  return () => { socket.disconnect(); };
}, [cashRegister?.terminal?.id]);
```

### Pattern 5: SWR polling fallback that auto-stops on unmount

**Example:**
```typescript
// ventago-app/src/views/mercadopago/hooks/useMpPaymentIntent.ts
import useSWR from 'swr'

// SWR refreshInterval=5000 → 5초 polling
// QR 모달 unmount 시 자동 정리, mutate() 로 즉시 갱신 가능
export function useMpPaymentIntent(intentId: number | null) {
  const { data, mutate } = useSWR(
    intentId ? `/api/mercadopago/payment-intents/${intentId}` : null, // null key → fetch 스킵
    {
      refreshInterval: 5000,
      revalidateOnFocus: false,
      dedupingInterval: 0, // polling 시엔 dedup 무력화 (5초 간격 보장)
    }
  )

  return { intent: data, mutate }
}
```

### Anti-Patterns to Avoid

- **Storing tokens plaintext:** `mp_accounts.access_token TEXT` raw — NEVER. Always AES-256-GCM. Master key in env, rotated via separate process.
- **Trusting QR webhook payload directly:** MP docs explicitly state QR Code notifications cannot be HMAC-verified. Always re-fetch `/v1/payments/{id}` with the collector's access_token before mutating any state. The webhook is just a "wake up and check" signal.
- **Using a global access_token:** `MercadoPagoConfig({ accessToken: ... })` SDK pattern. We have N stores, each with own token — pass accessToken per call.
- **Reusing the same IV for AES-GCM encryptions:** GCM security collapses entirely if (key, IV) pair repeats. Always `randomBytes(12)` per encryption.
- **Webhook handler creating sale directly:** Sale creation is the frontend's job (handleSubmit). Webhook only flips intent status + emits Socket.io. This keeps the existing /sales contract untouched and the auto-trigger uses the proven path.
- **Polling without `intentId` guard:** `useSWR(url, ...)` without conditional null key keeps firing after modal closes. Always `intentId ? url : null`.
- **Hardcoded `external_pos_id`:** Different stores need different POS — store it on `mp_accounts` after registration.
- **Calling MP refund endpoint without `X-Idempotency-Key`:** Network retries can create duplicate refunds. Use `refund-{saleId}-{attemptNo}` as the key.
- **Hand-rolling QR rendering:** Don't generate QR images on the backend — `qrcode.react` does it client-side with zero server cost.
- **Adding a second pg pool for MP:** CLAUDE.md hard rule — pool max=50 stays. Reuse the existing Sequelize connection.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| QR image generation | Server-side QR PNG via `qrcode` lib + base64 | `qrcode.react` `<QRCodeSVG>` client-side | Zero server cost, scalable SVG, error correction built-in |
| AES-256-GCM crypto | Custom cipher chains, third-party "encryption" packages | Node `crypto.createCipheriv('aes-256-gcm', ...)` | Stdlib is FIPS-grade, audited, zero deps; libraries add risk |
| HMAC-SHA256 webhook verification | Custom hash | `crypto.createHmac('sha256', secret).update(manifest).digest('hex')` | Stdlib; constant-time comparison via `crypto.timingSafeEqual` |
| OAuth state signing | Random strings stored in session | HMAC-SHA256 of `{storeId, branchId, nonce, ts}` with server-side secret | Stateless verification, no session storage |
| Idempotency lock | Application-level mutex / Redis SET NX | DB UNIQUE constraint + SELECT FOR UPDATE | CLAUDE.md forbids extra infra; Postgres handles natively |
| Polling library | Custom setInterval + fetch + cleanup | SWR `refreshInterval` | Already installed; auto-stops on unmount |
| MP REST SDK | Custom HTTP wrapper from scratch | Raw axios with shared client service | axios already installed; SDK doesn't cover QR endpoints anyway |
| Socket.io room targeting | Iterate clients map | `server.to('terminal:{id}').emit(...)` | Native socket.io API; existing pattern in print.gateway.ts |
| Cron scheduling | setInterval at app start | `@nestjs/schedule` `@Cron(...)` | Already installed; survives module reload |

**Key insight:** Every single primitive Phase 29 needs (HMAC, AES-GCM, HTTP, idempotency, polling, sockets, cron) already exists either in Node stdlib or installed deps. The phase is integration plumbing, not algorithm work. The only NEW package is `qrcode.react` (frontend-only, ~115KB).

## Runtime State Inventory

> N/A — this is a greenfield phase (NEW module, NEW tables, NEW UI page). No existing strings/IDs being renamed, no live MP integration to migrate from. The only existing state touched is the `mercadopago` slug placeholder in `payment_methods` seed (CONTEXT.md `code_context` confirms this is reused, not modified).

**Stored data:** None — Phase 29 creates new tables only. Existing `payment_methods.slug='mercadopago'` is reused as-is.
**Live service config:** None at start — first OAuth connection creates first MP App configuration. New external dependency: Mercadopago developer panel App registration (one-off manual step by ops).
**OS-registered state:** None.
**Secrets/env vars:** **NEW** env vars to provision (Docker secret recommended): `MP_PRODUCTION_CLIENT_ID`, `MP_PRODUCTION_CLIENT_SECRET`, `MP_SANDBOX_CLIENT_ID`, `MP_SANDBOX_CLIENT_SECRET`, `MP_TOKEN_ENCRYPTION_KEY` (32-byte hex), `MP_WEBHOOK_SECRET` (global, optional — only useful for non-QR webhooks if added later), `MP_OAUTH_STATE_SECRET` (HMAC for state param), `MP_NOTIFICATION_BASE_URL` (defaults to `https://newapi.coolsistema.com/api`).
**Build artifacts:** None.

## Common Pitfalls

### Pitfall 1: QR webhooks have no x-signature verification path
**What goes wrong:** Implementer trusts MP docs's "x-signature" HMAC pattern, computes the manifest, gets a passing signature for non-QR webhooks but failing signatures for QR webhooks. Or worse, accepts unsigned QR webhooks blindly and a malicious actor forges payment-approved events.
**Why it happens:** The official webhooks doc shows the signature algorithm, but a quiet line states "QR Code notifications cannot be verified using the secret signature." [CITED: mercadopago.com.ar/.../webhooks]
**How to avoid:** Treat the webhook payload as a "wake up" signal only. Always GET `/v1/payments/{data.id}` (or `/v1/orders/{data.id}` for new Orders API path) with the collector's `access_token` and trust ONLY the API response's `status` field.
**Warning signs:** Sale gets created from webhook payload alone before MP API confirms; integration tests pass with mocked webhook bodies but never simulate the API re-fetch.

### Pitfall 2: refresh_token rotation breaks if not re-saved
**What goes wrong:** App refreshes access_token, gets back a new refresh_token in the same response, but only saves the new access_token. Next time the access_token expires (180 days later), the old refresh_token may no longer work.
**Why it happens:** "Every time you refresh the access_token, the refresh_token will also be refreshed, so you will need to store it again." [CITED: mercadopago.com/.../oauth renewal]
**How to avoid:** In `refreshAccount()` always UPDATE both `accessToken` AND `refreshToken` columns. Wrap in a single transaction so partial failure doesn't leave the row half-updated.
**Warning signs:** OAuth works after first connection but breaks after 180 days; users must re-OAuth every cycle.

### Pitfall 3: external_pos_id missing → 400 invalid_externalPosId
**What goes wrong:** Implementer connects OAuth and immediately tries `POST /instore/orders/qr/seller/collectors/{user_id}/pos/{???}/qrs` without first registering a Store + POS via `POST /users/{user_id}/stores` and `POST /pos`. MP returns 400.
**Why it happens:** OAuth gives you `user_id` but NOT a POS — they're separate REST flows. CONTEXT.md doesn't mention them.
**How to avoid:** OAuth callback handler MUST register Store + POS as part of the same atomic flow. Save the resulting `external_id` (which we set, e.g. `ventago-{storeId}-{branchId}`) on `mp_accounts.external_pos_id`. Idempotent: re-registration of same external_id should not fail.
**Warning signs:** First QR generation attempt returns 400; tests pass with mocked MP responses that always include qr_data.

### Pitfall 4: PG10 missing GENERATED AS IDENTITY
**What goes wrong:** Migration uses `id INTEGER GENERATED ALWAYS AS IDENTITY` and works locally on PG15, fails on production PG10 with syntax error.
**Why it happens:** GENERATED AS IDENTITY is technically PG10+, but some clauses (OVERRIDING, restart options) and `ALTER COLUMN ADD GENERATED ... AS IDENTITY` are PG12+. CLAUDE.md mandates SERIAL.
**How to avoid:** Use `id SERIAL PRIMARY KEY`. For UUID columns: `uuid UUID DEFAULT gen_random_uuid()` — but PG10 needs `CREATE EXTENSION IF NOT EXISTS pgcrypto;` first (`gen_random_uuid` only moved to core in PG13). [CITED: postgresql.org/docs/10/pgcrypto]
**Warning signs:** Migration runs cleanly on local Docker PG15 but fails on `ssh jhkim-server` ops Postgres.

### Pitfall 5: Webhook + polling double-create the sale
**What goes wrong:** Webhook arrives at t=2s, emits Socket.io; frontend triggers handleSubmit. Polling at t=5s ALSO sees status=approved, ALSO triggers handleSubmit. POST /sales runs twice → duplicate sale.
**Why it happens:** Two trigger paths, no client-side guard.
**How to avoid:** (a) Frontend keeps an `isSubmitting` ref; both triggers check it. (b) Backend's POST /sales already needs idempotency for this case — but better: don't ship double creates. Use a `processedIntentId` ref in PaymentSummaryModal — first trigger marks it, second is a no-op.
**Warning signs:** Sales table has 2x identical rows for the same intent_id during integration tests.

### Pitfall 6: Webhook handler holding DB lock too long → other QRs starve
**What goes wrong:** SELECT FOR UPDATE on intent row, then call MP API inside the lock (slow), then update. Other webhooks for unrelated intents queue behind.
**Why it happens:** Misconception that lock must wrap the API call.
**How to avoid:** Step 1: GET `/v1/payments/{id}` BEFORE the transaction. Step 2: BEGIN TX, SELECT FOR UPDATE intent, check + update, COMMIT. Step 3: Emit Socket.io after COMMIT. The lock window is microseconds, not seconds.
**Warning signs:** Slow query log shows transactions held >100ms (CLAUDE.md performance budget violation).

### Pitfall 7: Sandbox QR gets paid with real-money production token
**What goes wrong:** mp_account.environment='sandbox' but a stale env var or wrong client_id/secret picks up production credentials → real money charged in test scenario.
**Why it happens:** Two MP Apps (sandbox + prod) but ambiguous credential lookup.
**How to avoid:** Strict env naming `MP_SANDBOX_CLIENT_ID` vs `MP_PRODUCTION_CLIENT_ID`. Lookup function must throw if mp_account.environment doesn't match credentials selected. Add an integration test that deliberately mismatches and asserts throw.
**Warning signs:** "It works for me" reports where sandbox transactions succeed but show in production MP dashboard.

### Pitfall 8: ESLint warning fails build (Frontend)
**What goes wrong:** New `McdpgQrPanel.tsx` has missing newline-before-return → frontend Docker build fails on production deploy.
**Why it happens:** CLAUDE.md: "Frontend ESLint treats warnings as errors during build."
**How to avoid:** Every `return` statement in any new tsx file MUST have a blank line above it. Same for `//` comments. Use eslint subagent or `npm run lint` in ventago-app before committing.
**Warning signs:** Local `next dev` works but Jenkins build fails on lint step.

### Pitfall 9: Missing Sequelize lock option syntax
**What goes wrong:** `findByPk(id, { lock: true })` doesn't actually emit `SELECT ... FOR UPDATE` in some Sequelize versions.
**Why it happens:** Correct syntax is `lock: t.LOCK.UPDATE` (where `t` is the transaction object) AND `transaction: t`.
**How to avoid:** Use the explicit form. Verify by enabling `logging: console.log` temporarily during dev.
**Warning signs:** Concurrent webhook + polling both succeed in updating intent row → race condition logged.

### Pitfall 10: Refund without idempotency key on retry
**What goes wrong:** User clicks "Reintentar" twice quickly → two refunds dispatched to MP for the same payment → MP rejects second OR (worse) accepts both.
**Why it happens:** Retry endpoint doesn't pass X-Idempotency-Key.
**How to avoid:** Always pass `X-Idempotency-Key: refund-{saleId}-{attemptNo}` where attemptNo is a counter from `mp_refund_attempts`. Same key = MP returns the same response (proven idempotency).
**Warning signs:** mp_refunds table has duplicate refund_ids; balance double-debited.

## Code Examples

### Sequelize-typescript model with snake_case mapping

```typescript
// api-ventago/src/app/mercadopago/models/mp-payment-intent.model.ts
// Source: pattern from api-ventago/src/app/print/branch-agent.model.ts
import { Table, Column, Model, DataType, ForeignKey, BelongsTo } from 'sequelize-typescript';
import { Store } from '../../store/store.model';
import { Branch } from '../../branch/branch.model';
import { Terminal } from '../../terminal/terminal.model';
import { MpAccount } from './mp-account.model';

@Table({ tableName: 'mp_payment_intents', timestamps: true })
export class MpPaymentIntent extends Model {
  @ForeignKey(() => MpAccount) @Column({ type: DataType.INTEGER, allowNull: false })
  declare mpAccountId: number;
  @BelongsTo(() => MpAccount) mpAccount?: MpAccount;

  @ForeignKey(() => Store) @Column({ type: DataType.INTEGER, allowNull: false })
  declare storeId: number;

  @ForeignKey(() => Branch) @Column({ type: DataType.INTEGER, allowNull: true })
  declare branchId: number | null;

  @ForeignKey(() => Terminal) @Column({ type: DataType.INTEGER, allowNull: false })
  declare terminalId: number; // emitToTerminal target

  // 임시 venta ID (sale 생성 전)
  @Column({ type: DataType.INTEGER, allowNull: false })
  declare pendingVentaId: number;

  @Column({ type: DataType.NUMERIC(14, 2), allowNull: false })
  declare amount: number;

  // MP 응답
  @Column({ type: DataType.STRING(64), allowNull: true })
  declare mpOrderId: string | null;        // in_store_order_id from MP

  @Column({ type: DataType.TEXT, allowNull: true })
  declare qrData: string | null;           // EMVCo string for QR

  // 결제 완료 후 채워짐 — UNIQUE 보장 (idempotency)
  @Column({ type: DataType.STRING(32), allowNull: true, unique: true })
  declare paymentId: string | null;

  @Column({
    type: DataType.ENUM('pending', 'approved', 'cancelled', 'expired', 'failed'),
    allowNull: false,
    defaultValue: 'pending',
  })
  declare status: 'pending' | 'approved' | 'cancelled' | 'expired' | 'failed';

  @Column({ type: DataType.DATE, allowNull: false })
  declare expiresAt: Date;

  @Column({ type: DataType.DATE, allowNull: true })
  declare approvedAt: Date | null;
}
```

### Migration SQL (PG10/PG15 compatible)

```sql
-- api-ventago/migrations/29-02-mp-payment-intents.sql
-- PG10/15 호환: SERIAL 사용 (CLAUDE.md 규칙), gen_random_uuid 미사용
CREATE TABLE IF NOT EXISTS mp_payment_intents (
  id              SERIAL PRIMARY KEY,
  mp_account_id   INTEGER NOT NULL REFERENCES mp_accounts(id) ON DELETE CASCADE,
  store_id        INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  branch_id       INTEGER NULL REFERENCES branches(id) ON DELETE SET NULL,
  terminal_id     INTEGER NOT NULL REFERENCES terminals(id) ON DELETE CASCADE,
  pending_venta_id INTEGER NOT NULL,
  amount          NUMERIC(14, 2) NOT NULL,
  mp_order_id     VARCHAR(64) NULL,
  qr_data         TEXT NULL,
  payment_id      VARCHAR(32) NULL UNIQUE,            -- 멱등성 핵심
  status          VARCHAR(20) NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending','approved','cancelled','expired','failed')),
  expires_at      TIMESTAMPTZ NOT NULL,
  approved_at     TIMESTAMPTZ NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_mp_intents_status_expires
  ON mp_payment_intents (status, expires_at)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_mp_intents_terminal
  ON mp_payment_intents (terminal_id, status);

CREATE INDEX IF NOT EXISTS idx_mp_intents_pending_venta
  ON mp_payment_intents (pending_venta_id);
```

### Webhook controller with @Public guard

```typescript
// api-ventago/src/app/mercadopago/webhook/mp-webhook.controller.ts
import { Body, Controller, Headers, HttpCode, Post } from '@nestjs/common';
import { Public } from '../../auth/decorators/public.decorator';
import { MpWebhookService } from './mp-webhook.service';

// MP webhook는 외부에서 호출되므로 JWT 미적용 (@Public)
// 보안: x-signature 검증은 QR notification에 적용 불가 → 항상 MP API re-fetch로 검증
@Controller('mercadopago/webhook')
export class MpWebhookController {
  constructor(private readonly svc: MpWebhookService) {}

  @Public()
  @Post()
  @HttpCode(200) // MP는 200 또는 201 기대 — 22초 timeout
  async handle(
    @Headers('x-signature') signature: string | undefined,
    @Headers('x-request-id') requestId: string | undefined,
    @Body() body: any,
  ): Promise<{ ok: true }> {
    // 비동기 처리 (MP timeout 회피) + 항상 200 반환
    // 처리 실패도 200 — MP의 15분 retry는 불필요한 부하만 줌. 실패는 polling으로 회복
    setImmediate(() => {
      this.svc.handleNotification(body, signature, requestId).catch((err) => {
        // 이 에러는 사용자에게 노출되지 않음 (MP→백엔드) — Winston 로그로만
        console.error('[MP Webhook] background processing failed', err);
      });
    });

    return { ok: true };
  }
}
```

### Refund with idempotency key

```typescript
// api-ventago/src/app/mercadopago/refunds/mp-refund.service.ts
async refundForNullifiedSale(saleId: number, paymentEntry: SalePayment) {
  const intent = await this.intentModel.findOne({
    where: { paymentId: paymentEntry.mpPaymentId },
    include: [MpAccount],
  });
  if (!intent) throw new BadRequestException('MP intent not found');

  const account = intent.mpAccount;
  const accessToken = this.crypto.decrypt(account.accessToken);

  // 시도 회차 계산 (재시도 카운터)
  const lastAttempt = await this.attemptModel.findOne({
    where: { saleId },
    order: [['attemptNo', 'DESC']],
  });
  const attemptNo = (lastAttempt?.attemptNo ?? 0) + 1;

  const attempt = await this.attemptModel.create({
    saleId,
    mpPaymentId: paymentEntry.mpPaymentId,
    attemptNo,
    status: 'pending',
  });

  try {
    // X-Idempotency-Key 동일 → MP가 동일 응답 반환 (안전한 재시도)
    const refund = await this.mpApi.post<MpRefundResponse>(
      `/v1/payments/${paymentEntry.mpPaymentId}/refunds`,
      paymentEntry.amount === intent.amount
        ? {} // 전액 환불 — body 없음
        : { amount: paymentEntry.amount }, // 부분 환불
      accessToken,
      { idempotencyKey: `refund-${saleId}-${attemptNo}` },
    );

    // 성공 → mp_refunds + mp_movements debit + wallet 잔액 감소 (TX)
    await this.sequelize.transaction(async (t) => {
      await this.refundModel.create({
        saleId,
        mpPaymentId: paymentEntry.mpPaymentId,
        refundId: String(refund.id),
        amount: paymentEntry.amount,
      }, { transaction: t });

      await this.walletService.debitOnRefund(intent, paymentEntry.amount, t);
      await attempt.update({ status: 'success' }, { transaction: t });
    });

    return { success: true };
  } catch (err: any) {
    await attempt.update({
      status: 'failed',
      errorMessage: err?.message?.slice(0, 500) ?? 'unknown',
    });
    // sale은 nullified 처리되, 환불은 실패 표시 → 프론트가 prominent UX 표시
    return { success: false, attemptId: attempt.id, error: err?.message };
  }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Server-side QR PNG generation | Client-side `<QRCodeSVG>` | qrcode.react 3.x → 4.x (2024+) | Zero server cost; SVG scales perfectly |
| `mercadopago` SDK 1.x callback-style | `mercadopago` SDK 2.x promise/async | 2023 release | Cleaner API but doesn't cover QR endpoints — we use raw axios |
| AES-256-CBC for token encryption | AES-256-GCM | OWASP 2018+ | Authenticated encryption; tamper detection built-in |
| Webhook payload trusted directly | Webhook is "wake-up" + API re-fetch | MP docs current state | QR Code path has no signature, mandatory re-fetch |
| Single OAuth account per app | Per-store OAuth (multi-tenant) | MP marketplace patterns | Multi-tenant SaaS standard |
| Polling-only (no websockets) | Webhook + polling fallback | Industry standard since 2015 | Sub-second UX without sacrificing reliability |
| `gen_random_uuid()` from pgcrypto | Built into PG13+ core | PG13 release 2020 | PG10 still needs `CREATE EXTENSION pgcrypto` — relevant to ops migration [CITED: postgresql.org/docs/10/pgcrypto] |

**Deprecated/outdated:**
- **`mercadopago` SDK 1.x** — replaced by 2.x; even 2.x doesn't cover QR Dinámico → use raw HTTP for that path.
- **MP "in-store payments v1" (`/instore/orders/qr/seller/...`)** vs new "Orders API" (`/v1/orders` with QR integration) — MP launched a new Orders API in late 2025 [CITED: mercadopago.com.ar/.../news/2025/09/24/QR-Code-Integration-with-Orders-API]. The legacy v1 endpoint is still supported and is the documented standard for QR Dinámico Modelo. Phase 29 uses v1 (legacy) for stability; migrating to Orders API can be a future phase.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | MP App configuration (single client_id / client_secret per environment) is created out-of-band by ops before this phase ships | Standard Stack / env vars | Phase blocked at deploy time; MP App registration is manual web UI |
| A2 | `cashRegister.terminal.id` is reliably populated when PaymentSummaryModal opens | Pattern 4 (Socket.io) | Frontend can't join right room → fall back to polling; degrades but doesn't break |
| A3 | `pendingVentaId` is a unique integer the frontend can generate before sale creation (e.g. `Date.now()` + terminalId hash, or backend mints it on QR creation) | Architecture diagram | Need to add a small `POST /api/mercadopago/intents/reserve` or use intent.id directly as external_reference |
| A4 | Mercadopago QR Dinámico `qr_data` is a single EMVCo string under ~500 chars suitable for SVG QR rendering at 256px | Pattern 5 / qrcode.react | qrcode.react may need higher error-correction level or larger size; cosmetic only |
| A5 | The new MP "Orders API" (Sept 2025) is OPTIONAL — legacy `/instore/orders/qr/...` still works for QR Dinámico | State of the Art | If MP deprecates legacy endpoint mid-development, must migrate to Orders API (similar shape, different URL) |
| A6 | Existing `payment_methods.slug='mercadopago'` row is keyed by slug only (no FK from sales pointing at it that breaks if we change `is_active` logic) | Code Context | Existing sales using placeholder MP slug may need backfill — CONTEXT.md confirms migration is OUT OF SCOPE |
| A7 | `SessionGuard` does NOT need to apply to `/api/mercadopago/webhook` (MP can't send sessionToken) — `@Public()` decorator suffices | Webhook controller | Webhook returns 401 if SessionGuard runs; trivial to fix but must remember |
| A8 | `MP_TOKEN_ENCRYPTION_KEY` will be provisioned as a 32-byte hex string (64 chars) before deploy; key rotation is out of scope for Phase 29 | Pattern 2 (AES-GCM) | App throws at boot if key is missing/wrong size — that's intentional fail-fast |
| A9 | Webhook `notification_url` will be configured per-QR (in QR creation body) rather than globally on MP App. Reason: per-account `mp_account_id` extraction needs URL like `/api/mercadopago/webhook?accountId=X` | Pattern 3 (idempotent webhook) | If MP strips query params from notification_url, must look up mp_account_id via payment.collector.id from re-fetched payment object — viable fallback |
| A10 | `postgres` user on production server has CREATE TABLE / CREATE INDEX permission; if not, ops must run as superuser | PG10/15 migrations | Migration fails at execution; manual ops step |
| A11 | Operational matter: only one MP webhook URL needs to be registered per MP App — receiving notifications for any of its OAuth-connected accounts. The `data.user_id` field in webhook payload identifies which MP account | Webhook architecture | If MP requires URL per OAuth account, ops complexity increases (still feasible but more env config) |

## Open Questions

1. **External ID format for MP Store / POS registration**
   - What we know: must be unique, alphanumeric, ≤60 chars (store) and ≤40 chars (POS) [CITED: mercadopago.com.ar/.../create-store-and-pos]
   - What's unclear: collision risk if user re-installs OR removes mp_account and re-connects with same `external_id`
   - Recommendation: format `ventago-store-{storeId}` and `ventago-pos-{storeId}-{branchId|0}` — deterministic, idempotent (PUT-style; if already exists, MP returns same record). Verify in sandbox.

2. **MP Orders API v2 migration timing**
   - What we know: MP launched new Orders API for QR in Sept 2025; legacy `/instore/orders/qr/...` still documented and listed as standard
   - What's unclear: deprecation timeline (no announced sunset date)
   - Recommendation: Phase 29 ships on legacy. Add a smoke test that hits legacy weekly so we catch deprecation. Migration is a 1-plan future phase.

3. **Webhook re-fetch endpoint: `/v1/payments/{id}` vs `/v1/orders/{id}`**
   - What we know: legacy QR webhook includes `topic=payment` AND `topic=merchant_order`; new Orders API uses `topic=order` and `GET /v1/orders/{id}`
   - What's unclear: which is the authoritative one for legacy QR Dinámico — both arrive
   - Recommendation: For Phase 29 (legacy path), listen for `type=payment` only (ignore merchant_order — it duplicates), call `GET /v1/payments/{id}`. Verified in sandbox during Wave 5 E2E test.

4. **Branch-level OAuth `redirect_uri` mismatch risk**
   - What we know: `redirect_uri` must exactly match the value configured in MP App
   - What's unclear: if we use ONE callback URL `/api/mercadopago/oauth/callback` for both store-level and branch-level, the `state` param differentiates — but does MP enforce only one redirect_uri per App?
   - Recommendation: ONE callback URL, encode (storeId, branchId, nonce) in HMAC-signed `state` — exactly as CONTEXT.md D-A1-03 already mandates. Verified pattern via OAuth standards.

5. **Sandbox testing without real customer phone**
   - What we know: MP provides test credentials, test cards
   - What's unclear: whether QR Dinámico can be "scanned" without a real MP app on a phone (sandbox simulation)
   - Recommendation: Investigate during Wave 0 — MP provides a QR sandbox test page. If not available, fall back to: (a) calling `POST /v1/payments` directly with test credentials to simulate the payment, then manually triggering the webhook via `curl`. Document in test fixtures.

6. **Time skew tolerance for HMAC `state` param**
   - What we know: state should include timestamp to prevent replay
   - What's unclear: tolerance window (5 min? 10 min?) before user is forced to restart OAuth
   - Recommendation: 10 minutes — covers slow OAuth flows on bad mobile networks. Reject older.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Node.js | All backend code | ✓ (Docker node:20) | 20.x | — |
| PostgreSQL local | Dev migrations | ✓ (Docker dbpostgres) | 15 | — |
| PostgreSQL prod | Live | ✓ (host pg) | 10 | — (mandatory PG10/15 SQL compat) |
| qrcode.react@4.2.0 | Frontend QR rendering | ✗ (not installed) | — | npm install during Wave 1 |
| `mercadopago` SDK 2.12.0 | NOT NEEDED — using raw axios | n/a | — | — |
| Mercadopago Developer App (sandbox) | OAuth + QR API | ✗ (assumed not yet created) | — | Ops creates manually before Wave 6 E2E test |
| Mercadopago Developer App (production) | OAuth + QR API | ✗ (assumed not yet created) | — | Ops creates before phase 29 production deploy |
| ngrok or equivalent tunnel | Local webhook testing | ✗ | — | Use `ssh -R` reverse port forward through jhkim-server, or test webhooks via SSH-pasted curl from server |
| openssl (for generating `MP_TOKEN_ENCRYPTION_KEY`) | One-off key generation | ✓ (macOS / Linux stdlib) | — | `openssl rand -hex 32` |

**Missing dependencies with no fallback:**
- **MP Developer App registrations (sandbox + production)**: BLOCKING for E2E test. Ops must create both MP Apps in https://www.mercadopago.com.ar/developers/panel before Wave 6 begins. Assignable as task in Wave 0.

**Missing dependencies with fallback:**
- `qrcode.react` — npm install in Wave 1 (frontend wave).
- Local webhook tunnel — use ssh reverse forward or simulate webhook with curl from prod server during dev.

## Validation Architecture

> Nyquist validation enabled (config.json has no `nyquist_validation: false`).

### Test Framework

| Property | Value |
|----------|-------|
| Backend framework | Jest 29.7.0 + ts-jest 29.2.5 + Supertest 7.0.0 (already configured) [VERIFIED: api-ventago/package.json] |
| Backend config | inline in `api-ventago/package.json` `"jest"` key |
| Backend quick run | `cd api-ventago && npm test -- --testPathPattern=mercadopago` |
| Backend full suite | `cd api-ventago && npm test` |
| Frontend test framework | None detected in ventago-app — manual + lint only |
| Frontend lint (gating) | `cd ventago-app && npm run lint` |
| Frontend build (gating) | `cd ventago-app && npm run build` |
| E2E sandbox | Manual scripted (curl + manual MP app payment) — see Wave 0 fixture below |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| MP-POS-01a | OAuth callback creates mp_account row + mp_wallet row | integration | `cd api-ventago && npm test -- mercadopago/oauth/mp-oauth.service.spec.ts` | ❌ Wave 0 |
| MP-POS-01b | Tokens are stored encrypted (assert NOT plaintext) | unit | `cd api-ventago && npm test -- mercadopago/crypto/mp-token-crypto.service.spec.ts` | ❌ Wave 0 |
| MP-POS-01c | Re-OAuth same scope updates row, doesn't insert | integration | `cd api-ventago && npm test -- mercadopago/oauth/mp-oauth.service.spec.ts -t "re-connect"` | ❌ Wave 0 |
| MP-POS-01d | Branch-level lookup precedence (branch wins, store fallback) | unit | `cd api-ventago && npm test -- mercadopago/mp-account-resolver.spec.ts` | ❌ Wave 0 |
| MP-POS-02a | POST /api/mercadopago/qr creates intent + returns qr_data + expires_at 3 min | integration (MP API mocked) | `cd api-ventago && npm test -- mercadopago/qr/mp-qr.service.spec.ts` | ❌ Wave 0 |
| MP-POS-02b | DELETE /api/mercadopago/qr/:id sets intent.status='cancelled' + calls MP cancel | integration | `cd api-ventago && npm test -- mercadopago/qr/mp-qr.service.spec.ts -t "cancel"` | ❌ Wave 0 |
| MP-POS-02c | Frontend countdown decrements 1/sec; auto expires at 0 | manual smoke | open dev nueva-venta, select MP, observe modal | manual |
| MP-POS-03a | Webhook with valid payment.id + status=approved updates intent + emits Socket.io | integration | `cd api-ventago && npm test -- mercadopago/webhook/mp-webhook.service.spec.ts` | ❌ Wave 0 |
| MP-POS-03b | Webhook re-call (same payment.id) is no-op (idempotent) | integration | `cd api-ventago && npm test -- mercadopago/webhook/mp-webhook.service.spec.ts -t "idempotent"` | ❌ Wave 0 |
| MP-POS-03c | websocket.emitToTerminal pushes only to right terminal room | unit | `cd api-ventago && npm test -- common/socket/websocket.service.spec.ts -t "terminal room"` | ❌ Wave 0 |
| MP-POS-03d | Frontend receives Socket.io event → triggers handleSubmit → POST /sales | manual sandbox | scripted in `docs/phase29-e2e.md` | ❌ Wave 0 |
| MP-POS-04a | SWR polling triggers Generar Venta when webhook is blocked | manual sandbox | block webhook URL temporarily, sandbox-pay, expect ≤10s auto-generate | manual |
| MP-POS-04b | Webhook + polling double-arrival → 1 sale only | integration + manual | `cd api-ventago && npm test -- mercadopago/webhook/mp-webhook.service.spec.ts -t "double trigger"` | ❌ Wave 0 |
| MP-POS-05a | Split payment: MP=30000 + Efectivo=20000 → MP QR shows 30000 only | manual smoke | select 2 methods in modal, MP enters 30000 — verify backend QR amount | manual |
| MP-POS-05b | Sale.paymentMethods includes mp_payment_id in MP entry | integration | `cd api-ventago && npm test -- sales/sales-create.service.spec.ts -t "mp split"` | ❌ Wave 0 (extend existing) |
| MP-POS-06a | sandbox account vs production account use different MP API hosts/credentials | unit | `cd api-ventago && npm test -- mercadopago/api-client/mp-api-client.service.spec.ts -t "env separation"` | ❌ Wave 0 |
| MP-POS-06b | Environment change forces token invalidation | integration | `cd api-ventago && npm test -- mercadopago/oauth/mp-oauth.service.spec.ts -t "environment change"` | ❌ Wave 0 |
| MP-POS-06c | Sandbox UI shows orange banner + orange QR border | manual smoke | toggle env, observe nueva-venta UI | manual |
| MP-POS-07a | nullifySale of MP sale auto-calls refund + creates mp_refunds row + debits mp_movements | integration | `cd api-ventago && npm test -- mercadopago/refunds/mp-refund.service.spec.ts` | ❌ Wave 0 |
| MP-POS-07b | Refund failure leaves sale nullified + creates mp_refund_attempts row | integration | `cd api-ventago && npm test -- mercadopago/refunds/mp-refund.service.spec.ts -t "MP API failure"` | ❌ Wave 0 |
| MP-POS-07c | Retry endpoint dispatches refund with same idempotency key | integration | `cd api-ventago && npm test -- mercadopago/refunds/mp-refund.service.spec.ts -t "retry idempotent"` | ❌ Wave 0 |
| MP-POS-07d | Frontend renders inline Alert + toast + retry button + MP Dashboard link on refund failure | manual smoke | force MP refund failure, observe SalesDetailView | manual |

### Sampling Rate

- **Per task commit:** `cd api-ventago && npm test -- --testPathPattern=mercadopago --bail` (target: ≤30s)
- **Per wave merge:** `cd api-ventago && npm test && cd ../ventago-app && npm run lint && npm run build` (full backend Jest + frontend lint + build)
- **Phase gate:** Full backend suite green + frontend lint+build green + 1 E2E sandbox scripted run documented in `docs/phase29-e2e.md`

### Wave 0 Gaps

- [ ] `api-ventago/src/app/mercadopago/crypto/mp-token-crypto.service.spec.ts` — covers MP-POS-01b
- [ ] `api-ventago/src/app/mercadopago/oauth/mp-oauth.service.spec.ts` — covers MP-POS-01a/c, MP-POS-06b
- [ ] `api-ventago/src/app/mercadopago/mp-account-resolver.spec.ts` — covers MP-POS-01d (branch→store precedence)
- [ ] `api-ventago/src/app/mercadopago/qr/mp-qr.service.spec.ts` — covers MP-POS-02a/b
- [ ] `api-ventago/src/app/mercadopago/webhook/mp-webhook.service.spec.ts` — covers MP-POS-03a/b, MP-POS-04b
- [ ] `api-ventago/src/app/mercadopago/api-client/mp-api-client.service.spec.ts` — covers MP-POS-06a
- [ ] `api-ventago/src/app/mercadopago/refunds/mp-refund.service.spec.ts` — covers MP-POS-07a/b/c
- [ ] `api-ventago/src/common/socket/websocket.service.spec.ts` — extend with MP-POS-03c terminal room test
- [ ] `api-ventago/src/app/sales/sales-create.service.spec.ts` — extend for MP-POS-05b (mp_payment_id in paymentMethods)
- [ ] Test fixtures: `api-ventago/test/fixtures/mp-webhook-payload.json`, `api-ventago/test/fixtures/mp-payment-approved.json`, `api-ventago/test/fixtures/mp-qr-response.json`
- [ ] E2E doc: `docs/phase29-e2e.md` — step-by-step sandbox script (connect OAuth, generate QR, simulate payment via MP test app or curl /v1/payments, observe UI)
- [ ] Test helper: `api-ventago/test/helpers/mock-mp-api.ts` — axios mock for MP REST in unit tests

## Security Domain

> security_enforcement absent → enabled.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | OAuth 2.0 (MP) + existing Ventago JWT for our config UI |
| V3 Session Management | yes | Existing SessionGuard for all configuracion/mercadopago endpoints |
| V4 Access Control | yes | CASL `mercadopago_admin` function or reuse `configuracion_admin`; vendedor cannot transfer MP→cash |
| V5 Input Validation | yes | class-validator on all DTOs (CreateMpQrDto, MpWebhookDto, RetryRefundDto, TransferMpToCashDto) |
| V6 Cryptography | yes | AES-256-GCM (token storage), HMAC-SHA256 (state param), TLS (axios → MP, MP → webhook); NO hand-rolled crypto |
| V7 Error Handling & Logging | yes | All MP API errors logged via Winston; no token bytes in logs (mask access_token to first 12 chars) |
| V8 Data Protection | yes | mp_accounts.access_token / refresh_token NEVER returned in API responses; redact in serializer |
| V9 Communications | yes | All outbound MP calls over HTTPS; webhook URL must be HTTPS (newapi.coolsistema.com is) |
| V10 Malicious Code | n/a | No file uploads in this phase |
| V11 Business Logic | yes | Refund attempts logged; MP→cash transfer requires admin/gerente role |
| V12 Files & Resources | n/a | — |
| V13 API & Web Service | yes | Webhook is public (no JWT) — must be guarded by MP API re-fetch verification |
| V14 Configuration | yes | All MP secrets in env (Docker secret); no client_secret in git, no MP_TOKEN_ENCRYPTION_KEY in git |

### Known Threat Patterns for Mercadopago QR Integration

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Forged webhook payload claiming payment approved | Spoofing | Re-fetch `/v1/payments/{id}` with stored access_token; trust only MP API response. Pre-CONTEXT.md believed signature alone sufficed — actually QR webhooks have NO signature, re-fetch is mandatory |
| OAuth state replay attack | Tampering | HMAC-SHA256 state with timestamp; reject if older than 10 min |
| OAuth code injection (attacker pastes MP code into victim's browser) | Spoofing | state param ties (storeId, branchId, nonce) to a session-bound value verified at callback |
| Encrypted token storage compromise | Information Disclosure | AES-256-GCM with master key in env (Docker secret); column-level encryption isolates blast radius from DB-only dump |
| Refund replay (double-spend prevention loophole) | Tampering | `X-Idempotency-Key: refund-{saleId}-{attemptNo}`; mp_refund_attempts log per attempt |
| Webhook DoS (flood) | DoS | Webhook responds 200 immediately (setImmediate); processing async; idempotent on payment_id UNIQUE so flooding same id is no-op |
| MP API rate limit hit | DoS (self-inflicted) | Cache mp_account lookups in MemoryCacheService (60s TTL — already in stack); avoid re-fetching same payment on every webhook retry |
| SQL injection on intentId path param | Tampering | NestJS ParseIntPipe + Sequelize parameterized queries (existing) |
| Token leak in logs | Information Disclosure | Winston log filter masks any field matching `/access_token|refresh_token|client_secret/i` to first 12 chars + len |
| Cross-store token reuse (branch-A token used to query branch-B sale) | Authorization | Strict mp_account scope check: token decrypted only when payment_intent.mp_account_id matches |
| Sandbox token used in production payment flow | Tampering / Repudiation | mp_account.environment is the source of truth; selects MP_*_CLIENT_ID + axios baseUrl; integration test asserts mismatch throws |

## Sources

### Primary (HIGH confidence — VERIFIED)
- `npm view qrcode.react version` → 4.2.0 [VERIFIED: 2026-05-05]
- `npm view qrcode.react peerDependencies` → React 16.8/17/18/19 supported [VERIFIED]
- `npm view mercadopago version` → 2.12.0 [VERIFIED]
- `api-ventago/package.json` — @nestjs/schedule@^6.1.1, @nestjs/config@^4.0.2, axios@^1.4.0, pg@^8.13.1 [VERIFIED via Read]
- `ventago-app/package.json` — swr@^2.4.1, socket.io-client@4.8.3, axios@1.4.0 [VERIFIED via Read]
- `api-ventago/src/common/socket/websocket.gateway.ts` + `websocket.service.ts` — emitToApiKey/User/Store patterns [VERIFIED via Read]
- `api-ventago/src/app/print/branch-agent.model.ts` — Sequelize-typescript model template [VERIFIED via Read]
- `api-ventago/src/app/payment-methods/seed/payment-methods.seed.ts` — `mercadopago` slug already seeded [VERIFIED via Read]
- `api-ventago/src/app/sales/sales-create.service.ts:300` — `nullifySale` extension point [VERIFIED via Read]
- `ventago-app/src/views/homes/components/ProductList/ProductList.tsx:1154` — `handleSubmit("INVOICED", ...)` trigger location [VERIFIED via Grep]
- `ventago-app/src/components/team-chat/TeamChatPanel.tsx` — io(WS_URL, { transports: ['websocket'] }) pattern [VERIFIED via Read]

### Secondary (MEDIUM-HIGH confidence — CITED official MP docs)
- [MP QR Dynamic API Reference](https://www.mercadopago.com.ar/developers/es/reference/qr-dynamic/_instore_orders_qr_seller_collectors_user_id_pos_external_pos_id_qrs/post) — full request/response schema, error codes
- [MP Create Store and POS](https://www.mercadopago.com.ar/developers/en/docs/qr-code/create-store-and-pos) — POST /users/{user_id}/stores, POST /pos
- [MP Webhooks (with critical "QR cannot be verified" note)](https://www.mercadopago.com.ar/developers/en/docs/your-integrations/notifications/webhooks) — HMAC algorithm, retry behavior
- [MP QR Code Notifications](https://www.mercadopago.com.ar/developers/en/docs/qr-code/notifications) — order topic + status enums
- [MP OAuth creation](https://www.mercadopago.com.ar/developers/en/docs/security/oauth/creation) — authorize URL + token exchange
- [MP OAuth refresh](https://www.mercadopago.com.co/developers/en/docs/subscriptions/additional-content/security/oauth/renewal) — 180-day TTL, refresh_token rotation
- [MP Refunds API](https://www.mercadopago.com.br/developers/en/reference/chargebacks/_payments_id_refunds/post) — partial vs full refund, X-Idempotency-Key
- [MP Node.js SDK GitHub](https://github.com/mercadopago/sdk-nodejs) — confirms QR endpoints NOT wrapped, SDK not chosen for this phase
- [MP QR Code Integration with Orders API (2025-09)](https://www.mercadopago.com.ar/developers/en/news/2025/09/24/QR-Code-Integration-with-Orders-API) — new Orders API exists; legacy still supported

### Secondary (Postgres / Node)
- [PostgreSQL 10 pgcrypto docs](https://www.postgresql.org/docs/10/pgcrypto.html) — gen_random_uuid() requires extension on PG10
- [SWR Mutation & Revalidation docs](https://swr.vercel.app/docs/mutation) — refreshInterval + mutate semantics
- [SWR Conditional Fetching](https://swr.vercel.app/docs/conditional-fetching) — null key skips fetch
- [qrcode.react npm](https://www.npmjs.com/package/qrcode.react) — QRCodeSVG, props
- [Node crypto AES-GCM example](https://gist.github.com/rjz/15baffeab434b8125ca4d783f4116d81) — IV/AuthTag pattern reference

### Tertiary (LOW confidence — flagged in Open Questions / Assumptions)
- A4 (qr_data length) — not explicitly documented, assumed from EMVCo standard
- A11 (one webhook URL per MP App vs per OAuth account) — needs sandbox confirmation in Wave 0

## Project Constraints (from CLAUDE.md)

These are MUST-honor directives extracted from `CLAUDE.md` (project root) and `~/.claude/CLAUDE.md` (global):

1. **PostgreSQL pool 변경 금지** — `max=50` stays. Reuse existing Sequelize connection. No second pool for MP. Optimize via query efficiency, not pool size. [global + project]
2. **DB 컬럼 snake_case (raw SQL)** — Sequelize models camelCase, DB columns snake_case via `underscored: true`. All migration SQL uses snake_case. [project]
3. **PG10/PG15 SQL 호환 필수** — `SERIAL` not `GENERATED AS IDENTITY`; if `gen_random_uuid()` needed, prefix migration with `CREATE EXTENSION IF NOT EXISTS pgcrypto;`. [project]
4. **ESLint Warning = build error (frontend)** — `newline-before-return`, `lines-around-comment`, `import/newline-after-import`, `no-unused-vars` all block builds. Run `cd ventago-app && npm run lint` before commits. [project]
5. **`apiConnector.remove()` not `.delete()`** — for DELETE requests. [memory + project]
6. **에러 메시지 prominent 노출** — every MP error: inline Alert + global toast. No silent failures. [memory feedback_error_visibility]
7. **모든 작업 시 최신 로그 파일 우선 확인** — when debugging, check Winston daily-rotate logs first. [global]
8. **Korean code comments, Spanish UI strings, English identifiers** — see existing patterns. [project]
9. **`@Audit()` decorator** — apply to mutating MP endpoints (OAuth disconnect, transfer MP→cash, refund retry). [project]
10. **Multi-tenant `storeId` filter** — every query must scope by storeId; CrudService handles automatically when extended. [project]
11. **DTO validation in Spanish** — `@IsString({ message: 'El monto es requerido' })`. [project convention]
12. **Migration files in `api-ventago/migrations/`** — naming `29-NN-{description}.sql` per Phase 26 precedent. [project]
13. **`commit_docs: true`** is set — RESEARCH.md should be committed by orchestrator. [planning config]

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — qrcode.react@4.2.0 verified via `npm view`; all backend deps already installed
- MP API contracts: HIGH — verified via official MP developer docs (multiple URLs)
- MP webhook security model: HIGH — official docs explicitly state QR cannot use x-signature, mandate API re-fetch
- Codebase integration points: HIGH — verified via Read/Grep on actual files
- AES-256-GCM crypto pattern: HIGH — Node stdlib, documented in nodejs.org/api/crypto
- PG10 vs PG15 compat: HIGH — verified via PostgreSQL official docs (pgcrypto, identity columns)
- Refund idempotency: HIGH — MP docs explicitly support X-Idempotency-Key
- Socket.io terminal room: HIGH — extending existing pattern from print.gateway.ts
- E2E sandbox testing tooling: MEDIUM — depends on MP sandbox QR scan capability (Open Question 5)

**Research date:** 2026-05-05
**Valid until:** 2026-06-05 (30 days — MP API stable, but Orders API migration could shift landscape; revisit if delayed)
