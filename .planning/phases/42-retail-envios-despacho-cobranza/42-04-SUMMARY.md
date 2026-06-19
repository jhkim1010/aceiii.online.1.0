---
phase: 42-retail-envios-despacho-cobranza
plan: 04
subsystem: online-orders (despacho realtime + read-side)
tags: [websocket, gateway, kanban, cuentas-por-cobrar, timeline, idor, multitenant]
requires:
  - "42-02 (model cols: preparedAt/dispatchedAt/transporteId, registerCobro, metadata.shipSaldo)"
  - "42-03 (deliver realignment + sale_credit accrual + RD-12 gate)"
provides:
  - "OnlineOrdersBoardGateway (namespace /envios, event envio_updated, emitEnvioUpdated)"
  - "GET /online-orders/board/:branchId (kanban cards)"
  - "GET /online-orders/cuentas-por-cobrar (RD-7 data source)"
  - "GET /online-orders/:id (auth-scoped merged timeline — replaces simple detail, I-1 fix)"
  - "POST /online-orders/:id/nota (timeline note append)"
  - "post-commit envio_updated emit on every transition + cobro"
affects:
  - "42-05 (board UI consumes /envios + board/:branchId)"
  - "42-07 (timeline drawer consumes GET :id merged events + POST :id/nota)"
  - "42-08 (Cuentas por cobrar tab consumes GET cuentas-por-cobrar)"
tech-stack:
  added: ["@nestjs/websockets gateway (socket.io /envios namespace)"]
  patterns: ["post-commit emit (never inside tx)", "card-level payload (no full re-query)", "storeId-scoped WHERE (multitenant)", "branch room IDOR guard", "JSONB timeline_notes (no new table)"]
key-files:
  created:
    - "api-ventago/src/app/online-orders/online-orders-board.gateway.ts"
    - "api-ventago/src/app/online-orders/online-orders-board.gateway.spec.ts"
    - "api-ventago/src/app/online-orders/dto/nota-online-order.dto.ts"
  modified:
    - "api-ventago/src/app/online-orders/online-orders.service.ts"
    - "api-ventago/src/app/online-orders/online-orders.controller.ts"
    - "api-ventago/src/app/online-orders/online-orders.module.ts"
    - "api-ventago/src/app/online-orders/online-orders.service.spec.ts"
decisions:
  - "Gateway cloned near-verbatim from RestaurantDeliveryGateway; namespace /restaurant→/envios, event delivery_updated→envio_updated (domain separation, Open Q2)"
  - "Emit placement: public transition methods capture runStatusTx post-commit result then emitCard() — never inside the tx (Pattern 4)"
  - "GET :id simple findById detail REPLACED with getOrderTimeline merged events (I-1: @Auth + storeId-scoped)"
  - "columnKey derived from timestamps (preparedAt!=null && dispatchedAt==null → listo), no new enum (Pitfall 5)"
  - "saldo source-of-truth: metadata.shipSaldo when set, else total−received; StoreClient.balance is authoritative per-client figure (credit module owns it)"
metrics:
  duration: ~12m
  tasks: 4
  files: 7
  completed: 2026-06-19
---

# Phase 42 Plan 04: /envios Gateway + Despacho Read-Side Backend Summary

Real-time `/envios` Socket.io gateway (JWT handshake + branch-room IDOR guard) plus post-commit `envio_updated` card emits on every despacho transition/cobro, and the three read/write routes (board kanban, cuentas-por-cobrar, auth-scoped merged timeline GET :id, nota append) that frontend waves 5/7/8 consume as concrete contracts.

## Routes Added (concrete contracts for 42-05/07/08)

### 1. `GET /online-orders/board/:branchId`  (RD-2 — kanban)
- **Auth:** admin/superadmin/gerente/vendedor. `storeId` server-derived from `@GetUser`.
- **Scope:** store + branch (`WHERE storeId, branchId`), active statuses only (pending/confirmed/preparing/shipped/delivered — excludes cancelled/returned). `limit 50`.
- **Response:** `EnvioCard[]`

```ts
EnvioCard = {
  id: number;
  orderNumber: number;
  channel: string;
  clientName: string | null;
  address: string | null;          // from metadata.address
  total: number;
  paymentStatus: string;
  saldo: number;                   // metadata.shipSaldo ?? (total − received), floored at 0
  transporteName: string | null;  // shippingCarrier
  trackingCode: string | null;
  branchId: number | null;
  columnKey: 'nuevo' | 'preparando' | 'listo' | 'en_transito' | 'entregado' | 'cerrado';
}
```
- **columnKey derivation (D-03):** pending/confirmed→`nuevo`; preparing && preparedAt==null→`preparando`; preparedAt!=null && dispatchedAt==null→`listo`; shipped→`en_transito`; delivered→`entregado`; cancelled/returned→`cerrado`.

### 2. `GET /online-orders/cuentas-por-cobrar`  (RD-7 — 외상 tab data source, OWNED HERE)
- **Auth:** admin/superadmin/gerente/vendedor. `storeId` server-derived.
- **Scope:** `WHERE storeId, status IN (shipped, delivered)`, `limit 50`, then filtered to `saldo > 0`. StoreClient join is storeId-scoped.
- **Response:**

```ts
{
  rows: Array<{
    orderId: number;
    orderNumber: number;
    clientId: number | null;
    clientName: string | null;
    total: number;
    recibido: number;             // computeReceivedSoFar
    saldo: number;                // metadata.shipSaldo ?? total−recibido
    branchId: number | null;
    clientBalance: number | null; // StoreClient.balance — authoritative per-client outstanding (credit module owns)
  }>;
  totalSaldo: number;             // aggregate sum of row.saldo
}
```

### 3. `GET /online-orders/:id`  (RD-9 + I-1 — auth-scoped merged timeline; REPLACES simple detail)
- **Auth:** admin/superadmin/gerente/vendedor. `storeId` server-derived. `findById(storeId,id)` → 404 if cross-store (I-1 PII fix, T-42-18).
- **Response:**

```ts
{
  order: OnlineOrder;             // full detail (items + returns included)
  events: TimelineEvent[];        // frontend sorts/renders by `at`
  saldo: number;                  // metadata.shipSaldo ?? total−received, floored at 0
}

TimelineEvent = {
  type: 'created'|'confirmed'|'prepared'|'dispatched'|'delivered'|'cancelled'|'payment'|'credit'|'cobro'|'nota';
  at: string;                     // ISO-8601 (frontend sorts on this)
  label: string;
  amount?: number;
  method?: number | null;         // paymentMethodId (payment events)
}
```
- **Event sources merged:** status timestamps (createdAt/confirmedAt/preparedAt/dispatchedAt||shippedAt/deliveredAt/cancelledAt); `SalePaymentMethod` rows on mirror sale (payment); `CreditLedger` sale_credit/payment_in/favor_in for the order's storeClient scoped to mirrorSaleId (credit); `metadata.timeline_notes` (cobro/nota).

### 4. `POST /online-orders/:id/nota`  (RD-9 — timeline note append, T-42-25)
- **Auth:** admin/superadmin/gerente. `storeId` + `userId` server-derived (body not trusted).
- **Body:** `NotaOnlineOrderDto { text: string }` — `@IsString @IsNotEmpty @MaxLength(1000)`.
- **Behavior:** storeId-scoped load → push `{ type:'nota', text, at: ISO, userId }` onto `metadata.timeline_notes` (JSONB array, init `[]` if absent — no new table, Open Q3) → save → post-save `envio_updated` emit.
- **Response:** updated `OnlineOrder`.

## Realtime: `/envios` gateway (RD-9)
- **Namespace:** `/envios` (domain-separated from `/print-agent` and `/restaurant`).
- **Event:** `envio_updated` (card payload).
- **Handshake (T-42-13):** `handshake.auth.token` → `jwtService.verifyAsync(token, { secret: JWT_SECRET_KEY })`; disconnect on missing/invalid; stores `client.data.storeId/userId`.
- **`@SubscribeMessage('join')` (T-42-14 IDOR):** joins `branch:{branchId}` ONLY if `branch.storeId == client.data.storeId` (else `join_error`, no join — cross-store cards never leaked).
- **`emitEnvioUpdated(branchId, card)`:** `server.to('branch:'+branchId).emit('envio_updated', card)`.
- **Post-commit emits:** `confirmOrder`/`prepareOrder`/`shipOrder`/`deliverOrder`/`cancelOrder` capture `runStatusTx` (which returns AFTER `t.commit()`) result then call `emitCard()`; `registerCobro` emits post-save. NEVER inside a tx (Pattern 4, pool 절약 — card-level payload, no full re-query).

## Verification
- `npx jest online-orders-board.gateway online-orders.service` → **2 suites / 19 tests green**
  - Gateway spec (6): token-missing→disconnect, token-invalid→disconnect, valid→storeId stored, join-own-store→join, join-other-store→NO join (IDOR), emitEnvioUpdated→branch room emit.
- `npx tsc --noEmit` → **no new errors in online-orders** (only pre-existing `mp-webhook.service.spec.ts` TS2554, Phase 29, deferred).
- Route greps: board/:branchId, cuentas-por-cobrar, getCuentasPorCobrar, getOrderTimeline, timeline_notes, nota, nota DTO, module provider/JwtModule/Branch — all present.
- ESLint: plan-required rules (newline-before-return, lines-around-comment, no-unused-vars, prettier/prettier) clean on all new/modified files; new-code region (timeline/board/cuentas) free of no-unsafe.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Updated `online-orders.service.spec.ts` constructor instantiation**
- **Found during:** Task 2 (gateway injection into service constructor)
- **Issue:** Service constructor grew from 13→16 params (boardGateway, salePaymentMethodModel, creditLedgerModel); the existing unit spec instantiated `new OnlineOrdersService(...13 args)` → TS2554.
- **Fix:** Added 3 mocks (`boardGateway.emitEnvioUpdated`, `salePaymentMethodModel.findAll`, `creditLedgerModel.findAll`), `storeClientModel.findAll`, and exposed them on the builder return for future assertions.
- **Files:** `online-orders.service.spec.ts`  •  **Commit:** 54c3fcb

**2. [Rule 1 - Cleanliness] Typed JSONB note + SalePaymentMethod access in getOrderTimeline**
- **Found during:** Task 3 ESLint pass
- **Issue:** Initial implementation used `(p as any)` / untyped `note` access (no-unsafe-* in new code).
- **Fix:** Added `TimelineNote` interface; used `p.get('createdAt')` + declared `SalePaymentMethod` props (`amount`, `paymentMethodId`). New-code region is now no-unsafe-clean.
- **Files:** `online-orders.service.ts`  •  **Commit:** 54c3fcb

### Notes (not deviations)
- The simple `GET :id` detail (`findById`) was intentionally **replaced** by the merged-timeline `getOrderTimeline` handler per plan Task 3 (I-1 fix). Same `@Auth` roles retained.
- Pre-existing `no-unsafe-*` ESLint errors in Wave 2/3 code (service lines 436–1038) are OUT OF SCOPE (already committed; backend build is SWC, not eslint-gated).

## Self-Check: PASSED
- FOUND: online-orders-board.gateway.ts, online-orders-board.gateway.spec.ts, dto/nota-online-order.dto.ts
- FOUND commit d12f041 (gateway + spec), 54c3fcb (board/emits/read-routes/module/dto/spec-fix)
