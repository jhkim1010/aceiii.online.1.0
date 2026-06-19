---
phase: 42-retail-envios-despacho-cobranza
plan: 06
subsystem: frontend-ventas-online
tags: [despacho, kanban, socket, envios, ventas-online, retail]
requires:
  - "42-05: useStoreConfig().useEnvios, useDespachoBoard, useTransportes, envioLabels"
  - "42-04: /envios gateway (namespace '/envios', event 'envio_updated', join {branchId})"
provides:
  - "Ventas Online 3-tab control center gated by useEnvios"
  - "DespachoBoard: 5-column kanban + /envios socket push (merge by id, no polling) + master-detail shell"
  - "Despachar action (transporte + tracking → PATCH /online-orders/:id/ship) + saldo>0 completion-gate warning"
affects:
  - "ventago-app/src/views/ventas-online/VentasOnlineView.tsx"
  - "ventago-app/src/views/ventas-online/DespachoBoard.tsx"
tech-stack:
  added: []
  patterns:
    - "next/dynamic ssr:false code-split for board view (300ms target)"
    - "mutateRef functional-updater socket merge (no full refetch, no reconnect on cards change)"
    - "useEnvios gate branch keeps legacy code path untouched (RD-12 regression-0)"
key-files:
  created:
    - "ventago-app/src/views/ventas-online/DespachoBoard.tsx"
  modified:
    - "ventago-app/src/views/ventas-online/VentasOnlineView.tsx"
decisions:
  - "Legacy Phase-27 view extracted verbatim into LegacyVentasOnline sub-component (zero edits to legacy paths) — RD-12 #1 gate"
  - "Cuentas/Historial tabs render inline 'Cargando…' placeholder until 42-08 (no stub files to avoid collision with 42-08 real files)"
  - "EnvioTimeline panel rendered as inline placeholder container until 42-07"
requirements: [RD-2, RD-9, RD-12]
metrics:
  tasks: 2
  files: 2
  completed: "2026-06-19"
---

# Phase 42 Plan 06: Ventas Online 3-Tab Upgrade + Despacho Kanban Summary

3-tab Ventas Online control center gated by `useEnvios`, with a real-time `/envios` socket-pushed Despacho kanban (5 columns, count badges, card-merge-by-id, no polling) and a 75/25 master-detail shell — while `useEnvios=false` stores keep the untouched legacy Pedidos/Envíos/Devoluciones tabs.

## What was built

### Task 1 — 3-tab VentasOnlineView gated by useEnvios (commit `81598f3`)
- `VentasOnlineView` is now a thin entry point: `const { useEnvios } = useStoreConfig()` → `true` renders `EnviosControlCenter`, `false` renders `LegacyVentasOnline`.
- `EnviosControlCenter`: 3 tabs — **Despacho** / **Cuentas por cobrar** / **Historial**. Despacho tab renders the full `DespachoBoard`; the other two render an inline `EnviosTabPlaceholder` ("Cargando…") until plan 42-08.
- `DespachoBoard` imported via `next/dynamic(..., { ssr: false })` — code-split for the 300ms target.
- The entire Phase-27 implementation (KPI cards, filters, OrdersTable/ShippingTable/ReturnsTable) was moved verbatim into `LegacyVentasOnline` with **zero edits to legacy logic** — RD-12 #1 regression gate.

### Task 2 — DespachoBoard kanban + /envios socket + master-detail shell (commit `6034965`)
- `WS_HOST`: dev `http://localhost:5002/envios`, prod `https://newapi.coolsistema.com/envios`.
- 5 columns: `nuevo` / `preparando` / `listo` (Listo p/ despacho) / `en_transito` / `entregado`, grouped by `EnvioCard.columnKey`, each with a count badge; cards stack vertically.
- Data via `useDespachoBoard(branchId)` where `branchId = selectedBranchId ?? user.branchId` (BranchContext, no re-fetch).
- Socket: `io(WS_HOST, { transports:['websocket'], auth:{ token: localStorage.getItem('accessToken') } })`; on `connect` → `emit('join', { branchId })`; on `envio_updated` → merge card by id into SWR cache via `mutateRef` functional updater (replace-by-id, `false` = no revalidate). Cleanup: `socket.off('envio_updated')` + `socket.disconnect()`. Effect deps = `[branchId]` only (mutateRef keeps it from reconnecting on every cards change). **No setInterval / refreshInterval (D-11).**
- Card content (spec §5.2): orderNumber, channel chip (`canalLabel`), clientName, address, total (`useFormatPrice`), paymentStatus chip (`paymentStatusLabel` + `paymentStatusColor` — red when saldo>0), transporte+tracking chip when shipped, red `Saldo $X` badge when saldo>0.
- Master-detail: left ~75% kanban (`flex 1 1 75%`), right ~25% timeline panel (`flex 0 0 25%`). Card click sets `selectedCardId` (state owned here); panel shows the selected card header + an inline dashed placeholder container for the timeline (EnvioTimeline lands in 42-07).
- **Despachar** on `listo` cards: dialog with activeOnly transporte dropdown (`useTransportes().filter(isActive)`) + tracking input → `apiConnector.patch('/online-orders/:id/ship', { transporteId, trackingCode })`. When `saldo > 0`, a warning `Alert` ("despachar con saldo / 외상으로 발송") is shown before confirming; the backend enforces the identified-customer credit gate.

## Verification

| Check | Result |
|-------|--------|
| `npx next lint` on both touched files | ✔ No ESLint warnings or errors |
| `tsc --noEmit` (filtered to touched files) | ✔ No type errors in touched files |
| Task 1 greps (useEnvios / Despacho / Cuentas por cobrar / dynamic / legacy tabs) | ✔ all match |
| Task 2 greps (/envios / envio_updated / Listo p/ despacho / join / Saldo / completion-gate / NO setInterval) | ✔ all match |

## Stub approach (per plan instruction — no collision with waves 07/08)

- **Cuentas por cobrar / Historial tabs** → rendered via an **inline** `EnviosTabPlaceholder` ("Cargando…") component inside `VentasOnlineView.tsx`. No `CuentasPorCobrarTab.tsx` / `HistorialTab.tsx` files were created, so wave 42-08's real files will not collide. When 42-08 lands, swap the two placeholder branches for `next/dynamic` imports of the real views.
- **EnvioTimeline panel** → rendered as an **inline** dashed placeholder container inside `DespachoBoard.tsx`'s right master-detail panel. No `EnvioTimeline.tsx` file was created, so wave 42-07's real file will not collide. When 42-07 lands, mount `<EnvioTimeline orderId={selectedCardId} />` in that slot.

## Deviations from Plan

None — plan executed as written. The two stubs above are explicitly mandated by the plan/prompt (inline placeholders, guarded so the build passes now without pre-creating 42-07/42-08 files).

## Known Stubs

| Stub | File | Reason / Resolved by |
|------|------|----------------------|
| Cuentas por cobrar tab → "Cargando…" placeholder | `VentasOnlineView.tsx` (`EnviosTabPlaceholder`) | Real view created in plan 42-08 |
| Historial tab → "Cargando…" placeholder | `VentasOnlineView.tsx` (`EnviosTabPlaceholder`) | Real view created in plan 42-08 |
| Timeline panel → inline dashed "disponible próximamente" container | `DespachoBoard.tsx` (master-detail right panel) | `EnvioTimeline` mounts here in plan 42-07 |

These stubs do not block the plan's goal (RD-2/RD-9/RD-12 = Despacho board + real-time socket + legacy no-regression), which are all fully implemented. The cobrar/historial/timeline content is explicitly scoped to later waves.

## Task 3 — Browser UAT: PENDING USER VERIFICATION

Task 3 is a `checkpoint:human-verify` requiring a live browser + dev stack, which cannot be run in this environment. The **automated** portion (lint on both files) was executed and is clean. The code is complete; the following manual UAT remains **PENDING user verification** (mirrors the project's "code complete, UAT pending" pattern):

1. `./dev.sh` (or `npm run dev:api` + `npm run dev:app`). Enable `use_envios` on a test store (Configuración → Transporte card visible; add a transporte).
2. Open **Ventas Online** → confirm 3 tabs (Despacho / Cuentas por cobrar / Historial). Confirm the Despacho kanban shows 5 columns + count badges.
3. Create/advance an order via the existing flow → confirm the card appears/moves **in real time WITHOUT page refresh** (socket `envio_updated` push).
4. Ship a `listo` card → transporte dropdown + tracking → confirm move to **En tránsito**. With a partial-paid order, confirm the **"despachar con saldo / 외상으로 발송"** warning shows before shipping.
5. Switch to a `use_envios=FALSE` store → confirm Ventas Online shows the **legacy** tabs (Pedidos / Envíos / Devoluciones) working normally (**RD-12 — no regression**).

**Resume signal:** Type "approved" or describe issues (board not updating / legacy tabs broken / gate missing).

## Commits

- `6034965` — feat(42-06): DespachoBoard 칸반 + /envios 소켓 + master-detail 셸
- `81598f3` — feat(42-06): Ventas Online 3-탭 업그레이드 (useEnvios 게이트)

(Committed inside the `ventago-app` submodule on branch `fix/pos-precio-base-fallback`, where the rest of Phase 42 wave 05 frontend work lives.)

## Self-Check: PASSED
- FOUND: ventago-app/src/views/ventas-online/DespachoBoard.tsx
- FOUND: ventago-app/src/views/ventas-online/VentasOnlineView.tsx
- FOUND commit: 6034965
- FOUND commit: 81598f3
