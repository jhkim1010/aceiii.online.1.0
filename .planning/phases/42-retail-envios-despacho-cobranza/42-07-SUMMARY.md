---
phase: 42-retail-envios-despacho-cobranza
plan: 07
subsystem: frontend-ventas-online (timeline + cobro + nuevo envío)
tags: [despacho, timeline, cobro, split, cancel, favor, print, ventas-online, retail]
requires:
  - "42-06: DespachoBoard master-detail shell + selectedCardId + placeholder panel slot"
  - "42-04: GET /online-orders/:id merged timeline ({order,events,saldo}) + POST :id/nota"
  - "42-02: POST :id/cobro (CobroOnlineOrderDto) + PATCH :id/cancel { refundAction }"
provides:
  - "CobroModal: props-injected split/partial cobro (no POS coupling) → POST :id/cobro"
  - "EnvioTimeline: right-panel merged timeline + Ticket/Recibo/Nota + cobro + cancel fork"
  - "NuevoEnvioModal: +Nuevo envío console → POST /online-orders"
  - "DespachoBoard wired to real EnvioTimeline + Nuevo envío button"
affects:
  - "ventago-app/src/views/ventas-online/DespachoBoard.tsx (placeholder replaced)"
  - "42-08 (cobro decrements saldo → order leaves Cuentas por cobrar tab)"
tech-stack:
  added: []
  patterns:
    - "props-injection (D-09): CobroModal takes { open, onClose, orderId, saldoPendiente, paymentMethods, favorBalance, onCobroDone } — zero POS context coupling"
    - "frontend sorts backend-merged events by `at`, never re-derives the event set"
    - "print via existing POST /print/temp emitPrintTemp fire-and-forget (no online-order print route exists)"
    - "onChanged callback → board mutate() for immediate re-validation alongside socket push"
key-files:
  created:
    - "ventago-app/src/views/ventas-online/components/CobroModal.tsx"
    - "ventago-app/src/views/ventas-online/components/EnvioTimeline.tsx"
    - "ventago-app/src/views/ventas-online/components/NuevoEnvioModal.tsx"
  modified:
    - "ventago-app/src/views/ventas-online/DespachoBoard.tsx"
decisions:
  - "Ticket/Recibo print wired to POST /print/temp (the existing fire-and-forget temp-receipt route) — there is NO dedicated online-order print endpoint on the backend; emitPrintTemp is no-op if no agent (not a regression)"
  - "Cancel route confirmed as PATCH /online-orders/:id/cancel with body { refundAction: 'devolver'|'favor' } (controller L154-168) — not POST"
  - "favorBalance sourced from useCreditClientSummary(order.clientId) since order.clientId IS the storeClientId; the 'Aplicar saldo a favor' chip is a UI convenience only (NOT sent as a cobro payment line — backend has no favor payment method)"
  - "payment methods fetched via GET /payment-methods (same source as PaymentSummaryModal), filtering out virtual slugs (credito/favor/senia) so cobro only lists real fund sources"
  - "address persisted/read via metadata.address (createOrder only consumes dto.metadata)"
requirements: [RD-5, RD-6, RD-11]
metrics:
  tasks: 4
  files: 4
  completed: "2026-06-19"
---

# Phase 42 Plan 07: EnvioTimeline + Split CobroModal + NuevoEnvioModal Summary

Right-panel `EnvioTimeline` master-detail (renders the backend-merged `GET /online-orders/:id` timeline, Ticket/Recibo/Nota actions, and a cobro/cancel control surface), a delivery-specific props-injected split/partial `CobroModal` (no POS coupling per D-09), and a `+Nuevo envío` creation console — all wired into `DespachoBoard`, consuming the concrete plan-42-02/42-04 routes as-is.

## What was built

### Task 1 — CobroModal (split/partial, props-injected) — commit `2a3de3f`
- Props: `{ open, onClose, orderId, saldoPendiente, paymentMethods, favorBalance, onCobroDone }`. **No `useSaleProducts` / no POS sale context** (D-09 wrapper decision). Reuses PaymentSummaryModal's split-row visual layout only.
- Multiple payment lines (add/remove): each `{ paymentMethodId, amount }`; **Cheque** method shows `banco` + `N.º de cheque` inputs (validated required). Live sum vs `saldoPendiente`, with a "Restante luego de este cobro" figure.
- **Partial allowed:** if the sum < saldoPendiente, an info Alert announces the remaining amount stays `외상` (por cobrar); submit is not blocked.
- "Aplicar saldo a favor" chip when `favorBalance > 0` (explicit click only). The favor line (`paymentMethodId: -3`) is filtered OUT of the POST payload — backend has no favor payment-method; favor is resolved server-side via credit module, not as a cobro fund source.
- Submit → `apiConnector.post('/online-orders/' + orderId + '/cobro', { payments, receiptNo })` → `onCobroDone()` → `onClose()`.
- **Double error surface:** inline `Alert variant="filled"` + `toast.error` on failure (error handling 필수). Navy/gold theme.

### Task 2 — EnvioTimeline (merged events + Ticket/Recibo/Nota + cancel fork) — commit `2a3de3f`
- `EnvioTimeline({ orderId, onChanged })`. Fetches `GET /online-orders/:id` → `{ order, events, saldo }`. Frontend **sorts events by `at`** and renders; it does NOT re-derive the event set.
- Header: `#orderNumber`, channel chip (`canalLabel`), clientName, address (`metadata.address`), and a red `Saldo pendiente $X` chip when `saldo > 0`.
- Action buttons: **🎫 Ticket** / **🧾 Recibo** (`POST /print/temp`, fire-and-forget, no-op if no agent), **📝 Nota** (textarea → `POST /online-orders/:id/nota { text }` → refresh + `onChanged`), **Registrar cobro** (opens CobroModal with `saldoPendiente`, `paymentMethods`, `favorBalance` — shown when `saldo>0`), **Cancelar pedido** (shown when payments exist).
- Timeline render: per-event icon/color (created/confirmed/prepared/dispatched/delivered/cancelled/payment/credit/nota), label + amount + localized timestamp; a trailing red "Pendiente de cobro $X" marker when `saldo>0`.
- Cancel fork dialog: **💸 Devolver dinero** / **🎟️ Pasar a favor** → `PATCH /online-orders/:id/cancel { refundAction }` → refresh + `onChanged`. Backend decides accounting (caja reverse vs favor_in).

### Task 3 — NuevoEnvioModal + DespachoBoard wiring — commit `2a3de3f`
- `NuevoEnvioModal`: channel chips (Web/WhatsApp/Teléfono/MercadoLibre/Instagram → enum `webshop|whatsapp|other|mercadolibre|instagram`), phone-based client lookup (`GET /clients` on blur, autofills clientId/name/address), address, category-tabbed product picker (cloned from Phase 40 NuevoPedidoModal: `GET /products/by-parent?parent=false&pageSize=200`, `pickMenuPrice` PRECIO-1 rule), cart panel. Submit → `POST /online-orders` with `items[{productId,productName,quantity,unitPrice}]` + `metadata.address`.
- **Auto-inflow connection point (documented):** the board route returns ALL active online orders regardless of creation path; an order created via nueva-venta "envío necesario" lands in the same `online_orders` table and appears on the board via the `/envios` socket emit — no extra wiring needed.
- DespachoBoard: replaced the plan-42-06 dashed placeholder panel with `<EnvioTimeline orderId={selectedCard ? selectedCard.id : null} onChanged={() => mutate()} />`; added a header **"+Nuevo envío"** button opening NuevoEnvioModal (`onCreated → mutate()`). Card-click selection (`selectedCardId`) drives the timeline.

### Task 4 — Browser UAT: PENDING USER VERIFICATION
`checkpoint:human-verify` requiring a live browser + dev stack (money flows: saldo decrement, favor, caja reconcile) — cannot run here. The **automated** portion (ESLint on the 3 component files + DespachoBoard) was executed and is clean. Code complete; manual UAT remains **PENDING** (mirrors the project's "code complete, UAT pending" pattern).

**Manual UAT steps (PENDING):**
1. `./dev.sh`, `use_envios` store. Ventas Online → Despacho. Click a card → timeline panel shows header + chronological events.
2. Ship a partial-paid order (saldo>0) → card shows red Saldo. Click → **Registrar cobro** → split (e.g. Efectivo + Cheque) partial → confirm saldo decrements, timeline gets a Pago event, card updates in real time.
3. Pay the rest → saldo 0 → order leaves Cuentas por cobrar (verify in 42-08 tab).
4. Cancel a paid order → **Pasar a favor** → verify client favorBalance increases. On another → **Devolver dinero** → caja reverse.
5. **🎫 Ticket / 🧾 Recibo** → with print-agent installed, prints; otherwise no-op (no error).
6. **+Nuevo envío** → create an order → appears on the board.
7. control-de-caja → confirm cobro caja movements reconcile.

**Resume signal:** Type "approved" or describe issues (cobro not decrementing / favor not applied / caja mismatch / print error).

## Verification

| Check | Result |
|-------|--------|
| `npx next lint` on all 4 touched files | ✔ No ESLint warnings or errors |
| `tsc --noEmit` (filtered to ventas-online) | ✔ No type errors in touched files |
| Task 1 greps (saldoPendiente / /cobro / NO useSaleProducts / Alert / toast) | ✔ all pass |
| Task 2 greps (Recibo / Registrar cobro / /nota / Pasar a favor / Saldo pendiente / Devolver / /online-orders/) | ✔ all pass |
| Task 3 greps (NuevoEnvioModal / EnvioTimeline / Nuevo envío / /online-orders) | ✔ all pass |

## Deviations from Plan

### Auto-fixed / 조정 사항

**1. [Rule 3 - Blocking] Print endpoint: no online-order print route exists → wired to POST /print/temp**
- **Found during:** Task 2 (reading `print.service.ts` / `print.controller.ts` for the Ticket/Recibo route).
- **Issue:** The plan's interface block referenced an "emitPrintTemp ticket/recibo route" owned by online-orders. The backend has **no** online-order print endpoint; `PrintService.emitPrintTemp(branchId, data)` is internal, and the only frontend-reachable print path is `POST /print/temp` (the same fire-and-forget temp-receipt route the POS uses, `items[]` + `branchId` required).
- **Fix:** Ticket/Recibo call `apiConnector.post('/print/temp', { branchId, docType, orderNumber, clientName, items, total })` built from `order.items` (falls back to a single summary line). No-op if no agent — not a regression.
- **Files:** `EnvioTimeline.tsx`  •  **Commit:** `2a3de3f`

**2. [Rule 3 - Blocking] Exact cancel route is PATCH (not POST)**
- **Issue:** The prompt asked to confirm the exact cancel verb/path. The controller (L154-168) exposes `@Patch(':id/cancel')` with `CancelOnlineOrderDto { refundAction?: 'devolver'|'favor' }`.
- **Fix:** EnvioTimeline uses `apiConnector.patch('/online-orders/' + orderId + '/cancel', { refundAction })`.
- **Files:** `EnvioTimeline.tsx`  •  **Commit:** `2a3de3f`

**3. [조정] favor chip excluded from cobro payload + payment-method virtual-slug filter**
- The "Aplicar saldo a favor" chip is UI-only; the favor virtual line (`paymentMethodId: -3`) is filtered out before POST (backend cobro DTO has no favor method — favor is server-side credit accounting). Real cobro lines (efectivo/transferencia/cheque/tarjeta/QR) are the only ones sent. Payment methods fetched via `GET /payment-methods`, filtering virtual slugs `credito/favor/senia`.

**4. [조정] Comment wording (no literal `useSaleProducts` token)**
- Initial decoupling comments used the literal `useSaleProducts` token, which tripped the "NO useSaleProducts" acceptance grep. Reworded to "POS 판매 컨텍스트 미결합" so the token is fully absent from CobroModal.

### Out-of-scope (NOT touched)
- Cuentas por cobrar / Historial tabs remain inline "Cargando…" placeholders in `VentasOnlineView.tsx` (explicitly scoped to wave 42-08).

## Authentication Gates
None.

## Threat Surface
Within the planned register (T-42-20/21/22). The only new client surface is `POST /print/temp` (pre-existing route, branch-scoped, fire-and-forget). Money/cancel/nota operations all hit `@Auth + storeId/userId server-derived` routes (T-42-20/21 mitigated server-side; client UI is convenience only). `GET /online-orders/:id` is `@Auth + storeId-scoped` (T-42-22 / I-1 closed by 42-04). No new threat surface.

## Known Stubs
None. All three components are fully wired to concrete backend routes. (The cobrar/historial tab placeholders belong to wave 42-08 and are untouched here.)

## Commits
- `2a3de3f` (ventago-app submodule, branch `fix/pos-precio-base-fallback`) — feat(42-07): EnvioTimeline + split CobroModal + NuevoEnvioModal 배선

## Self-Check: PASSED
- FOUND: ventago-app/src/views/ventas-online/components/CobroModal.tsx
- FOUND: ventago-app/src/views/ventas-online/components/EnvioTimeline.tsx
- FOUND: ventago-app/src/views/ventas-online/components/NuevoEnvioModal.tsx
- FOUND: ventago-app/src/views/ventas-online/DespachoBoard.tsx (EnvioTimeline + Nuevo envío wired)
- FOUND commit (submodule): 2a3de3f
