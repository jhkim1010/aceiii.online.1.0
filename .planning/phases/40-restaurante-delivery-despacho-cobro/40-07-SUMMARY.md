---
phase: 40-restaurante-delivery-despacho-cobro
plan: 07
subsystem: frontend
tags: [nextjs, mui, swr, restaurant-delivery, repartidores, order-intake, mode-gated]

# Dependency graph
requires:
  - phase: 40-02
    provides: /repartidores REST (GET/POST/PUT, @Auth storeId-scoped, soft-deactivate)
  - phase: 40-04
    provides: POST /restaurant-delivery/order (single-TX Sale+RestaurantDelivery + comanda emit), GET /restaurant-delivery/board/:branchId
provides:
  - useRepartidores SWR hook — /repartidores, 5min dedup, RepartidorRow export (rider config + dispatch dropdown source)
  - useDeliveryBoard SWR hook — /restaurant-delivery/board/:branchId, conditional null key, NO polling (Socket.io push), DeliveryCard export
  - RepartidoresCard — rider list/create/edit + activo Switch, gated by useStoreConfig().useRestaurantMode (REQ-1)
  - NuevoPedidoModal — Delivery/Takeaway order intake, conditional address+rider, POST /restaurant-delivery/order (REQ-5)
affects: [40-08 (DeliveryBoard consumes useDeliveryBoard + NuevoPedidoModal + useRepartidores dispatch dropdown)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Mode-gated config card: useStoreConfig().useRestaurantMode → return null when false (T-40-25 info-disclosure mitigation + store-level exclusivity)"
    - "Order intake reuses OrderModal menu picker verbatim (pickMenuPrice + CartLine cart) — no menu-logic divergence between mesa and delivery"
    - "Conditional payload assembly: delivery-only fields (address/repartidorId) added to payload only when tipo=delivery (takeaway omits, not just hides)"
    - "useDeliveryBoard has no refreshInterval — board freshness is Socket.io push (plan 08), SWR is the initial-load + merge target only"

key-files:
  created:
    - ventago-app/src/hooks/api/useRepartidores.ts
    - ventago-app/src/hooks/api/useDeliveryBoard.ts
    - ventago-app/src/views/configuracion/restaurante/RepartidoresCard.tsx
    - ventago-app/src/views/restaurante/components/NuevoPedidoModal.tsx
  modified:
    - ventago-app/src/views/configuracion/restaurante/RestauranteConfigView.tsx

key-decisions:
  - "RepartidoresCard wired into RestauranteConfigView as a code-split (next/dynamic) section shown when modo restaurante is ON; the card also self-gates internally (if !useRestaurantMode return null) for defense-in-depth"
  - "Client linkage is phone-lookup-on-blur against /clients?search=; exact phone match sets clientId + autofills name/address, no match falls back to free-text customerName/customerPhone (server handles inline) — avoided building a heavyweight inline-create form"
  - "Takeaway omits address+rider from the payload entirely (conditional assembly), not merely hidden in the UI — backend never receives stale delivery fields for a takeaway order"
  - "externalRef field surfaces when paymentMode=app OR canal=app (배달앱 주문번호 anchor for plan 06 reconciliation)"

patterns-established:
  - "Restaurant-mode-gated config cards return null on the flag, then are additionally rendered only inside the enabled block — two-layer gate so the card can never leak into a retail store"

requirements-completed: [REQ-1, REQ-5]

# Metrics
duration: ~5min
completed: 2026-06-16
---

# Phase 40 Plan 07: Repartidores Card + Nuevo Pedido Modal Summary

**Two SWR hooks (useRepartidores 5-min dedup, useDeliveryBoard no-poll Socket.io-merge target) plus the rider-management config card — gated to restaurant mode and listing/creating/editing riders with an activo soft-toggle — and the Delivery/Takeaway order-intake modal that reuses the OrderModal menu picker, conditionally shows address+rider only for delivery, and POSTs /restaurant-delivery/order; all four files lint-clean with no retail UI regression.**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-06-16T19:16:50Z
- **Completed:** 2026-06-16T19:21:28Z
- **Tasks:** 3
- **Files:** 5 (4 created, 1 modified)

## Accomplishments
- `useRepartidores`: `useApi<RepartidorRow[]>('/repartidores', { dedupingInterval: 300000 })` → `{ repartidores, error, isLoading, mutate }`. 5-min dedup per CLAUDE.md SWR rule; exports `RepartidorRow` for the card + dispatch dropdown.
- `useDeliveryBoard(branchId?)`: `useApi<DeliveryCard[]>(branchId ? '/restaurant-delivery/board/${branchId}' : null)` with NO `refreshInterval` — board updates arrive via the `/restaurant` Socket.io gateway (`delivery_updated`), so the hook is the initial-load + `mutate(card, false)` merge target only. Exports `DeliveryCard`.
- `RepartidoresCard` (REQ-1): gates first (`const { useRestaurantMode } = useStoreConfig(); if (!useRestaurantMode) return null`), then lists riders from `useRepartidores`, inline add-row (`apiConnector.post('/repartidores', { name, phone })`), per-row activo `Switch` (`apiConnector.put('/repartidores/'+id, { isActive })`), and inline name/phone edit. NAVY/GOLD theme from SalonEditor. `mutate()` after every mutation; errors surface inline Alert + toast.
- Wired `RepartidoresCard` into `RestauranteConfigView` as a `next/dynamic` code-split Sección 3, rendered inside the `enabled` block (modo restaurante ON) — two-layer gate.
- `NuevoPedidoModal` (REQ-5): reuses OrderModal's exact menu picker (category tabs + `pickMenuPrice` + `CartLine` cart). Adds Tipo toggle (Delivery shows address+rider / Para llevar omits both), canal chips (whatsapp/telefono/app/otro), phone-based client lookup-on-blur with free-text fallback, Cobro select (Efectivo default / QR / App) with conditional `externalRef`. "Enviar a cocina" builds the payload (delivery-only fields conditionally added) and `apiConnector.post('/restaurant-delivery/order', payload)`; validates address required for delivery.

## Task Commits

Each task committed atomically inside the ventago-app nested repo:

1. **Task 1: useRepartidores + useDeliveryBoard SWR hooks** — `a59ebeb` (feat)
2. **Task 2: RepartidoresCard + RestauranteConfigView wiring** — `67eb84b` (feat)
3. **Task 3: NuevoPedidoModal** — `97c3518` (feat)

## Files Created/Modified
- `hooks/api/useRepartidores.ts` — RepartidorRow + 5-min-dedup SWR hook on /repartidores.
- `hooks/api/useDeliveryBoard.ts` — DeliveryCard + conditional-key SWR hook on /restaurant-delivery/board/:branchId, no polling.
- `views/configuracion/restaurante/RepartidoresCard.tsx` — mode-gated rider management card (list/create/edit/activo toggle), NAVY/GOLD theme.
- `views/restaurante/components/NuevoPedidoModal.tsx` — Delivery/Takeaway order intake modal, conditional fields, POST order endpoint.
- `views/configuracion/restaurante/RestauranteConfigView.tsx` — additive: import RepartidoresCard via next/dynamic + render as Sección 3 inside the enabled block (10 lines, no existing logic changed).

## Decisions Made
- **Two-layer mode gate:** the card returns null on `!useRestaurantMode` AND is only rendered inside the `enabled` block of RestauranteConfigView. Defense-in-depth so the rider card can never appear in a retail store (T-40-25, store-level exclusivity).
- **Phone lookup over full inline-create:** the modal does a `/clients?search=` lookup on phone blur; exact match sets clientId + autofills, no match falls through to free-text customerName/customerPhone (server-side inline handling). Keeps the modal light and avoids duplicating the heavy InfoClient form.
- **Takeaway omits, not hides:** delivery-only fields (address/repartidorId) are conditionally added to the payload only when tipo=delivery; takeaway never sends them — the backend receives no stale fields.
- **No refreshInterval on the board hook:** SWR is the initial fetch + merge surface; live updates are Socket.io push (plan 08). Polling would waste the PG pool and contradict the SPEC constraint.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Plan grep artifact] `refreshInterval` literal in a Korean comment tripped the `! grep -q "refreshInterval"` gate in useDeliveryBoard.ts**
- **Found during:** Task 1 verify
- **Issue:** The explanatory comment originally read "refreshInterval 없음: ...", and the verify assertion requires NO occurrence of `refreshInterval` anywhere in the file (it must never be passed). The word in the comment made the gate fail even though the option is genuinely never set.
- **Fix:** Rephrased the comment to "폴링 옵션은 의도적으로 두지 않음: ...". Behavior unchanged — `useApi` is called without any polling option.
- **Files modified:** ventago-app/src/hooks/api/useDeliveryBoard.ts
- **Commit:** a59ebeb

## Issues Encountered
- The per-session temp filesystem (`/private/tmp/claude-501/.../tasks`) reported transient ENOSPC during verification; worked around by re-running verify greps directly (disk itself had 328Gi free). No code impact.
- Per the plan guardrails and 40-04 summary, the local dev DB does not have the `restaurant_deliveries`/`repartidores` runtime data wired through (migrations unapplied locally); verification relied on ESLint (build-blocker gate, clean), `tsc --noEmit` (no new errors in the 4 files), and the per-task grep blocks. No browser runtime smoke test was performed (UAT is the phase-level gate).

## Threat Surface
No new trust-boundary surface beyond the plan's `<threat_model>`. RepartidoresCard is gated by `useRestaurantMode` and never renders in a retail store (T-40-25); all hooks hit storeId-scoped endpoints with storeId never sent from the client (T-40-27); the order total in NuevoPedidoModal is display-only — the server recomputes totalAmount from items (T-40-26, plan 04 T-40-12).

## User Setup Required
None for this plan. (Operator must apply the Wave-1 migrations and run the backend with restaurant mode enabled to exercise these screens at runtime — standard phase setup.)

## Next Phase Readiness
- Plan 08 (DeliveryBoard) consumes `useDeliveryBoard` for the kanban columns, `useRepartidores` (filtered isActive) for the "Asignar" dropdown, and mounts `NuevoPedidoModal` for order intake. All three exports are ready.

## Self-Check: PASSED

- FOUND: ventago-app/src/hooks/api/useRepartidores.ts
- FOUND: ventago-app/src/hooks/api/useDeliveryBoard.ts
- FOUND: ventago-app/src/views/configuracion/restaurante/RepartidoresCard.tsx
- FOUND: ventago-app/src/views/restaurante/components/NuevoPedidoModal.tsx
- FOUND: ventago-app/src/views/configuracion/restaurante/RestauranteConfigView.tsx (modified)
- FOUND: commit a59ebeb (Task 1)
- FOUND: commit 67eb84b (Task 2)
- FOUND: commit 97c3518 (Task 3)
- ESLint: clean on all 4 new files + the modified config view (build-blocker gate)
- tsc --noEmit: no new errors in the 5 files
- all 3 task verify grep blocks: PASS
- scope: only 4 new files + 10-line additive config wiring — no retail UI regression

---
*Phase: 40-restaurante-delivery-despacho-cobro*
*Completed: 2026-06-16*
