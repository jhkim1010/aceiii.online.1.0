---
phase: 40-restaurante-delivery-despacho-cobro
plan: 08
subsystem: frontend
tags: [nextjs, mui, swr, socket.io, restaurant-delivery, kanban, rider-settlement, csv-upload, code-split]

# Dependency graph
requires:
  - phase: 40-07
    provides: useDeliveryBoard (no-poll Socket.io merge target) + useRepartidores + NuevoPedidoModal
  - phase: 40-04
    provides: GET /restaurant-delivery/board/:branchId + PATCH /restaurant-delivery/:id/transition + /restaurant Socket.io gateway (delivery_updated)
  - phase: 40-05
    provides: POST /rider-settlement/build + GET /rider-settlement/:id + POST /rider-settlement/:id/rendition
  - phase: 40-06
    provides: POST /restaurant-delivery/payout/reconcile (multipart CSV) + PayoutReconcileResult shape
provides:
  - DeliveryBoard — kanban dispatch board (6 columns), /restaurant Socket.io push merge, Asignar rider → en_camino, status transitions, red Por cobrar (REQ-6)
  - RiderSettlementView — per-rider build/load settlement, rendición → caja, Esperado/Recibido/Diferencia, payout CSV reconcile with red mismatch flags (REQ-7 + REQ-9 frontend)
  - RestauranteShell — code-split Salón/Delivery/Liquidación tab shell mounted in nueva-venta (restaurant mode, Salón default)
affects: [phase-40 UAT checkpoint (full delivery lifecycle + control invariant + retail no-regression)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Socket.io card-merge (not polling): io(HOST+'/restaurant', { auth:{token} }) → emit('join',{branchId}) → on('delivery_updated', card) merges into SWR cache via mutate(updater, false) keyed on [branchId] with mutateRef so card changes never re-open the socket (D-04, pool 절약)"
    - "Por cobrar column = control-core highlight: RED 2px border + RED header; holds only cash delivered-but-unsettled (backend keeps efectivo Entregado in por_cobrar) — QR/app never land there"
    - "Tab shell code-split: RestauranteShell mounts Salón/Delivery/Liquidación via next/dynamic ssr:false; nueva-venta swaps direct SalonView mount for the shell (Salón default tab preserves Phase 39 mesa flow); retail VcontrolHome branch untouched"
    - "CSV reconcile UI: apiConnector.sendFile(payout/reconcile?branchId=, FormData) → matched (green) vs flagged (red) row rendering by PayoutFlagReason"

key-files:
  created:
    - ventago-app/src/views/restaurante/DeliveryBoard.tsx
    - ventago-app/src/views/restaurante/components/RiderSettlementView.tsx
    - ventago-app/src/views/restaurante/RestauranteShell.tsx
  modified:
    - ventago-app/src/pages/nueva-venta/index.tsx

key-decisions:
  - "Socket.io connects to base host + /restaurant namespace (localhost:5002/restaurant dev, newapi.coolsistema.com/restaurant prod) — distinct namespace from the existing /realtime sockets; token via localStorage.getItem('accessToken') in handshake auth (matches backend gateway handshake.auth.token + join {branchId})"
  - "Card merge via functional mutate updater (replace by id, else append) with a mutateRef so the socket effect depends only on [branchId] — avoids reconnect churn on every card update"
  - "RestauranteShell mounted in nueva-venta replacing the direct SalonView mount; Salón is tab index 0 (default) so Phase 39 mesa flow is reachable and unchanged; retail path (VcontrolHome) is a sibling branch and was not touched"
  - "rendition default-checks all not-yet-rendido items (full settlement default); Guardar parcial sends the same checked subset — partial vs closed is decided server-side; backend's 'Abrí la caja' block surfaces via toast"

patterns-established:
  - "Browser-JWT Socket.io subscription with ref-stable callback + namespace base-host resolution — first browser consumer of the /restaurant gateway"

requirements-completed: []
requirements-pending: [REQ-6, REQ-7, REQ-9]

# Metrics
duration: ~5min
completed: 2026-06-16
status: code-complete-uat-pending
---

# Phase 40 Plan 08: Delivery Board + Rider Settlement + Shell Wiring Summary

**The visible delivery control surface: a DeliveryBoard kanban (Nuevo·En cocina·Listo·En camino·Por cobrar[RED]·Conciliación) that subscribes to the `/restaurant` Socket.io gateway and merges `delivery_updated` card payloads into the SWR cache without polling, assigns active riders on Listo cards and advances status via PATCH transition (En camino blocked server-side without a rider); a RiderSettlementView that builds/loads a rider's cash settlement, registers rendición into caja (POST /rider-settlement/:id/rendition) with Esperado/Recibido/Diferencia and red un-rendido rows, and reconciles the delivery-app payout CSV (apiConnector.sendFile → /payout/reconcile) flagging mismatches red; all wired beside Salón as a code-split RestauranteShell tab (Salón default, Phase 39 mesa flow preserved, retail untouched). All three new files + the page edit are ESLint-clean and tsc-clean. Code-complete — the phase-level browser UAT (plan Task 4) remains as a blocking human-verify checkpoint because the local dev DB lacks the Wave-1 delivery tables and no dev server is running.**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-06-16T19:25:59Z
- **Completed:** 2026-06-16T19:30:43Z (code tasks)
- **Tasks:** 3 code (auto) executed + committed; 1 human-verify checkpoint pending
- **Files:** 4 (3 created, 1 modified)

## Accomplishments

### Task 1 — DeliveryBoard kanban + Socket.io push + Asignar + transitions (REQ-6)
- Branch resolution mirrors SalonView (`selectedBranchId ?? user.branchId`). `useDeliveryBoard(branchId)` for initial load + merge target; `useRepartidores()` filtered `isActive` for the Asignar dropdown.
- 6 columns: `Nuevo · En cocina · Listo · En camino · Por cobrar · Conciliación`. **Por cobrar** styled RED (2px border + red header) as the control-core highlight. Cards grouped by `status` via `useMemo`.
- Card shows order number (`dailyNumber ?? id`), customer, delivery address (delivery only), elapsed-time minutes from `orderedAt` (amber ≥30m / red ≥60m, display-only), total, paymentMode chip (color by mode), and a rider chip once assigned.
- **Socket.io (D-04, no polling):** `io(${WS_HOST}/restaurant, { transports:['websocket'], auth:{ token: localStorage.getItem('accessToken') } })`; on connect `emit('join', { branchId })`; on `delivery_updated` merges the card into the SWR cache via a functional `mutate(updater, false)` (replace by id / append). A `mutateRef` keeps the effect dependency at `[branchId]` only, so card updates never reconnect the socket. Cleanup disconnects on unmount/branch-change.
- Actions: status-advance button (`PATCH /restaurant-delivery/:id/transition { status }`); Listo card **Asignar** opens an active-rider menu → transition to `en_camino` with `{ status:'en_camino', repartidorId }`. Backend BadRequest ("Asigná un repartidor") surfaces via the global banner + a board toast fallback. "Nuevo pedido" opens `NuevoPedidoModal`.

### Task 2 — RiderSettlementView: rendición → caja + payout CSV (REQ-7 + REQ-9 frontend)
- Active-rider chip row (`useRepartidores` filtered `isActive`). Selecting a rider runs `POST /rider-settlement/build { repartidorId }` then `GET /rider-settlement/:id` for the item-bearing settlement.
- Cash-order list with a `rendido` checkbox per row; **un-rendido rows stay RED**, already-liquidado rows show a green "Liquidado" chip and a disabled checked box. Esperado (Σ checked) / Recibido (contado input) / Diferencia (faltante red / sobrante cyan / 0 green).
- "Registrar rendición en caja" and "Guardar parcial" both `POST /rider-settlement/:id/rendition { itemIds, note }` (the checked subset). On success it re-fetches the settlement, re-seeds the still-pending checks, and toasts. The backend "Abrí la caja antes de registrar la rendición" block surfaces via toast.
- **Payout CSV (REQ-9):** file input → `apiConnector.sendFile('/restaurant-delivery/payout/reconcile?branchId='+branchId, FormData)`. Renders `matched` rows green (auto-conciliado) and `flagged` rows RED with a localized reason (`no_match` / `amount_mismatch` / `malformed_row`).

### Task 3 — RestauranteShell tab wiring (code-split entry point)
- `RestauranteShell` tab-switches `Salón` (existing SalonView) / `Delivery` (DeliveryBoard) / `Liquidación` (RiderSettlementView). All three heavy views imported via `next/dynamic(() => import(...), { ssr:false })` with a Skeleton loader (CLAUDE.md 300ms code-split rule).
- `nueva-venta/index.tsx` swaps the direct `<SalonView />` mount for `<RestauranteShell />` inside the `useRestaurantMode` branch. **Salón is tab index 0 (default)** so the Phase 39 mesa flow is reachable and unchanged. The retail `<VcontrolHome />` branch was not touched.

## Task Commits

Each task committed atomically inside the ventago-app nested repo:

1. **Task 1: DeliveryBoard kanban + Socket.io push + Asignar + transitions** — `3e6bc17` (feat)
2. **Task 2: RiderSettlementView rendición a caja + payout CSV reconcile** — `86d42fa` (feat)
3. **Task 3: RestauranteShell + nueva-venta wiring** — `dede8ba` (feat)

## Files Created/Modified
- `views/restaurante/DeliveryBoard.tsx` — kanban dispatch board, /restaurant Socket.io merge, Asignar/transition actions, red Por cobrar column.
- `views/restaurante/components/RiderSettlementView.tsx` — rider settlement (rendición → caja) + payout CSV reconcile with red mismatch flags.
- `views/restaurante/RestauranteShell.tsx` — code-split Salón/Delivery/Liquidación tab shell.
- `pages/nueva-venta/index.tsx` — additive: dynamic import swap (SalonView → RestauranteShell) + render-branch swap inside the restaurant-mode block (retail path unchanged).

## Decisions Made
- **Namespace base-host resolution:** the existing app sockets use the `/realtime` namespace; the delivery gateway is `/restaurant`. The board connects to `http://localhost:5002/restaurant` (dev) / `https://newapi.coolsistema.com/restaurant` (prod) with the JWT in `auth.token`, matching the backend gateway's `handshake.auth.token` + `join {branchId}` contract (which authorizes the branch room by store ownership server-side — T-40-28/T-40-29).
- **Ref-stable merge effect:** the socket effect depends only on `[branchId]`; the latest `mutate` is held in `mutateRef` so per-card updates never tear down and re-open the connection.
- **Salón-default shell:** mounting the shell in place of the direct SalonView keeps Salón as the default tab, so Phase 39 mesa flow is preserved; the retail VcontrolHome branch is a sibling and untouched (no retail regression in the routing).
- **Full-settlement default checks:** on load, all not-yet-rendido items are pre-checked; both rendición buttons send the checked subset and the backend decides closed vs partial.

## Deviations from Plan

None for the code tasks — plan Tasks 1-3 executed as written. (Task 3 in the plan body is the `auto` shell-wiring task; the blocking `checkpoint:human-verify` is plan Task 4, handled below.)

## Authentication / Checkpoint Gates

**Plan Task 4 — `checkpoint:human-verify` (gate=blocking) — PENDING.** This is the phase-level end-to-end UAT (full delivery lifecycle + the Entregado≠closed control invariant + retail no-regression). It was intentionally NOT executed by the executor: the local dev DB lacks the Wave-1 delivery tables (`repartidores` / `restaurant_deliveries` / `rider_settlements` — migrations 40-01..40-04 unapplied locally, per 40-04/05/06/07 summaries) and no dev server is running. The UAT requires `./dev.sh` against a restaurant-mode store with the migrations applied. See the "Awaiting UAT" section below for the exact steps.

## Verification Performed (code tasks)
- **Task verify greps:** all 3 PASS (DeliveryBoard: delivery_updated / /restaurant / Por cobrar / Conciliación / transition / Asignar / useDeliveryBoard; RiderSettlementView: rider-settlement / rendición / payout/reconcile / sendFile / Esperado-Recibido-Diferencia; RestauranteShell: DeliveryBoard / next/dynamic / Delivery-Liquidación).
- **ESLint (build-blocker gate):** clean (exit 0, zero warnings) on all 3 new files + the modified page.
- **tsc --noEmit:** no errors in DeliveryBoard, RiderSettlementView, RestauranteShell, or nueva-venta.
- **Deletion check:** no files deleted across the 3 commits. No untracked files left.

## Threat Surface
No new trust-boundary surface beyond the plan's `<threat_model>`. The board connects with the JWT in the Socket.io handshake auth (T-40-28) and only requests its own branch room (server authorizes by store ownership — T-40-29); all status changes go through the PATCH transition endpoint (UI cannot force an invalid state — T-40-30); the CSV file leaves the browser to the server-validated reconcile endpoint; cash rendición is blocked server-side without an open caja and the UI surfaces that error (T-40-31).

## Retail No-Regression
The change to `nueva-venta/index.tsx` is confined to the `useRestaurantMode === true` branch (SalonView → RestauranteShell). The retail `<VcontrolHome />` branch is byte-for-byte unchanged. No existing clothing/retail POS view was modified. (Functional retail-report no-regression — that a delivery sale with `source='delivery'` appears in 매출 reports while retail sales still work — is part of the pending UAT step 10.)

## Awaiting UAT (plan Task 4, blocking human-verify)

Run `./dev.sh` (migrations 40-01..40-04 applied) in a restaurant-mode store, then:
1. Configuración → "Repartidores" card visible; add a rider; toggle activo. Switch to a NON-restaurant store → card hidden.
2. Restaurante → Delivery tab → "Nuevo pedido": Delivery (efectivo) order with address + items → expect comanda print + card in "En cocina".
3. Takeaway order → address/rider NOT required.
4. Advance En cocina → Listo → Asignar rider → En camino (try En camino without rider first → expect "Asigná un repartidor") → Entregado.
5. efectivo Entregado card lands in red "Por cobrar" (NOT closed).
6. Liquidación tab → build settlement → check rendido → "Registrar rendición en caja" (caja closed → expect "Abrí la caja" block; open caja and retry) → order → Liquidado; box movement appears in control-de-caja.
7. Second browser/tab on the board → a status change in tab A pushes to tab B via Socket.io (no refresh).
8. QR order → confirm MP payment → card closes without Por cobrar.
9. App order with externalRef → lands in Conciliación → matching payout CSV → row auto-conciliado; mismatching row → stays red.
10. RETAIL NO-REGRESSION: in a retail (의류) store, normal POS sale + ventas report works and includes it; delivery sale (source='delivery') also appears in 매출 reports.

**Resume signal:** Type "approved" or describe issues (which step, expected vs actual).

## Self-Check: PASSED

- FOUND: ventago-app/src/views/restaurante/DeliveryBoard.tsx
- FOUND: ventago-app/src/views/restaurante/components/RiderSettlementView.tsx
- FOUND: ventago-app/src/views/restaurante/RestauranteShell.tsx
- FOUND: ventago-app/src/pages/nueva-venta/index.tsx (modified)
- FOUND: commit 3e6bc17 (Task 1)
- FOUND: commit 86d42fa (Task 2)
- FOUND: commit dede8ba (Task 3)
- ESLint: clean on all 3 new files + the modified page (build-blocker gate)
- tsc --noEmit: no errors in the 4 files
- all 3 task verify grep blocks: PASS
- scope: 3 new files + 1 additive page edit (restaurant-mode branch only) — no retail UI regression
- NOTE: code-complete; plan Task 4 (browser UAT, blocking human-verify) is intentionally pending — not a failure (the code tasks passed).

---
*Phase: 40-restaurante-delivery-despacho-cobro*
*Status: code-complete, UAT checkpoint pending*
*Completed (code): 2026-06-16*
