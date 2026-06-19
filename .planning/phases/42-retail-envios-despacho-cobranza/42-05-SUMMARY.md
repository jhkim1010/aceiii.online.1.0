---
phase: 42-retail-envios-despacho-cobranza
plan: 05
subsystem: frontend (envíos foundation — context + SWR hooks + config card)
tags: [swr, store-config, despacho, kanban-data, cuentas-por-cobrar, navy-gold, soft-toggle]
requires:
  - "42-01 (GET/POST /transportes, PUT /transportes/:id; use_envios column)"
  - "42-04 (GET /online-orders/board/:branchId → EnvioCard[]; GET /online-orders/cuentas-por-cobrar → { rows, totalSaldo })"
provides:
  - "StoreConfig.useEnvios flag (default false, fetched + memoized) — app-wide despacho gate"
  - "useTransportes() SWR hook (5min dedup)"
  - "useDespachoBoard(branchId) SWR hook (null-key gate, no polling)"
  - "useCuentasPorCobrar() SWR hook (5min dedup, clientBalance mapped)"
  - "EnvioCard interface (board card contract for 42-06)"
  - "envioLabels (canalLabel/statusLabel/statusColor/paymentStatus maps)"
  - "TransporteCard (useEnvios-gated CRUD card, soft toggle)"
  - "EnviosConfigView + /configuracion/envios page (toggle + card)"
affects:
  - "42-06 (Despacho kanban consumes useDespachoBoard + EnvioCard + envioLabels)"
  - "42-07 (timeline/cobro consume envioLabels)"
  - "42-08 (Cuentas/Historial consume useCuentasPorCobrar)"
tech-stack:
  added: []
  patterns: ["SWR null-key gate (no fetch until branchId)", "5min dedup for reference data", "no-polling board (socket push only, D-11)", "store-level useEnvios gate (default false, RD-12 regression-0)", "soft toggle (apiConnector.put isActive, no remove)", "double error surface (inline Alert + toast.error)", "next/dynamic ssr:false code-split"]
key-files:
  created:
    - "ventago-app/src/configs/envioLabels.ts"
    - "ventago-app/src/hooks/api/useTransportes.ts"
    - "ventago-app/src/hooks/api/useDespachoBoard.ts"
    - "ventago-app/src/hooks/api/useCuentasPorCobrar.ts"
    - "ventago-app/src/views/configuracion/transporte/TransporteCard.tsx"
    - "ventago-app/src/views/configuracion/transporte/EnviosConfigView.tsx"
    - "ventago-app/src/pages/configuracion/envios.tsx"
  modified:
    - "ventago-app/src/context/StoreConfigContext.tsx"
    - "api-ventago/src/app/store/config/storeConfig.controller.ts"
decisions:
  - "cuentas row per-client balance field mapped as clientBalance (per 42-04-SUMMARY authoritative contract), NOT balance as the 42-05 plan body text stated — deviation documented"
  - "Added EnviosConfigView + /configuracion/envios page (toggle + gated card) mirroring RestauranteConfigView — plan only required 'render the card in a configuración view'; a self-contained page is the cleanest analog placement"
  - "Added 'useEnvios' to backend update-flag whitelist (Patch + Put) — without it the EnviosConfigView toggle would 400, making the card unreachable (Rule 3 blocking)"
  - "channel mapping uses real OnlineOrderChannel enum (webshop→Web, whatsapp→WhatsApp, other→Teléfono, mercadolibre→MercadoLibre, instagram→Instagram)"
  - "envioLabels statusColor/paymentStatusColor return hex strings (navy/gold theme) for direct MUI sx use; saldo>0 → red (#ef5350)"
metrics:
  duration: ~10m
  tasks: 3
  files: 9
  completed: 2026-06-19
---

# Phase 42 Plan 05: Frontend Envíos Foundation Summary

StoreConfig now exposes a `useEnvios` flag (default false, fetched + memoized) that gates the entire retail despacho machine; the three SWR hooks (`useTransportes` 5min dedup, `useDespachoBoard` branchId-gated no-polling, `useCuentasPorCobrar` 5min dedup) bind to the concrete 42-01/42-04 backend contracts; `envioLabels` provides channel/columnKey-status/payment label+color maps; and `TransporteCard` (a phone-less RepartidoresCard clone with soft toggle + double error surface) is mounted behind the `useEnvios` toggle on a new `/configuracion/envios` page — so the board/timeline/cobro plans (42-06/07/08) receive ready data contracts.

## What Was Built

### Task 1 — useEnvios context + envioLabels  (commit 20ee42b, ventago-app)
- `StoreConfigContext.tsx`: `useEnvios: boolean` added to the type + `defaultState` (false) + fetch→state mapping (`res?.useEnvios ?? false`), mirroring the `useRestaurantMode` pattern exactly. Provider value stays `useMemo`-wrapped — `useEnvios` lives inside `state`, which is already a memo dependency, so reactivity is covered.
- `envioLabels.ts`: `canalLabel` (webshop→Web / whatsapp→WhatsApp / other→Teléfono / mercadolibre→MercadoLibre / instagram→Instagram), `statusLabel` (nuevo/preparando/listo→'Listo p/ despacho'/en_transito/entregado/cerrado), `statusColor` (hex, navy/gold), and `paymentStatusLabel`/`paymentStatusColor` (Pagado/Parcial/Sin pagar; saldo>0 → red).

### Task 2 — SWR hooks  (commit e054609, ventago-app)
- `useTransportes.ts`: `TransporteRow { id, name, isActive }`; `useApi('/transportes', { dedupingInterval: 300000 })`; returns `{ transportes, error, isLoading, mutate }`.
- `useDespachoBoard.ts`: exports `EnvioCard` (id, orderNumber, channel, clientName, address, total, paymentStatus, saldo, transporteName, trackingCode, branchId, columnKey); `useApi(branchId ? '/online-orders/board/${branchId}' : null)` — null-key gate, **no `refreshInterval`** (socket push only, D-11).
- `useCuentasPorCobrar.ts`: `useApi('/online-orders/cuentas-por-cobrar', { dedupingInterval: 300000 })`; maps `{ rows, totalSaldo }`; returns `{ rows, totalSaldo, error, isLoading, mutate }`.

### Task 3 — TransporteCard + config placement  (commit edc9ca9 ventago-app, 536521b api-ventago)
- `TransporteCard.tsx`: RepartidoresCard clone with the phone field removed. `const { useEnvios } = useStoreConfig(); if (!useEnvios) return null;`. Add (name only) / edit name / `apiConnector.put('/transportes/'+id, { isActive: !r.isActive })` activo toggle — **no remove/delete** (soft toggle, D-04). Double error surface (inline MUI `Alert` + `toast.error` via `reportError`). Navy `#0f0f1e` + gold `#f5a623`, gold Switch.
- `EnviosConfigView.tsx`: `useEnvios` toggle (PUT `/store-config/:id/update-flag` field=`useEnvios`) + `next/dynamic(ssr:false)` TransporteCard rendered only when enabled (double gate: page-level `enabled` + card-internal `if (!useEnvios)`).
- `pages/configuracion/envios.tsx`: `WithAccess allowedApps={['admin']}` + dynamic EnviosConfigView, acl `read/configuracion`.
- `storeConfig.controller.ts` (api-ventago): `'useEnvios'` added to both `updateFlagPatch` and `updateFlagPut` `allowedFields` (Rule 3 — see Deviations).

## Verification

### Automated grep (all PASS)
- Task 1: `useEnvios` in StoreConfigContext + `useMemo` present + `statusLabel`/`canalLabel`/`statusColor` + `Listo p/ despacho` in envioLabels → OK
- Task 2: `dedupingInterval: 300000` in useTransportes + `export interface EnvioCard` + `branchId ?` + NO `refreshInterval` in useDespachoBoard + `cuentas-por-cobrar` + `totalSaldo` in useCuentasPorCobrar → OK
- Task 3: `useEnvios` + `if (!useEnvios) return null` + NO `phone` + `apiConnector.put` + NO `apiConnector.remove/delete` + `Alert` + `toast.error` in TransporteCard → OK

### ESLint (BUILD GATE — frontend)
`npx eslint` on all 8 touched frontend files (StoreConfigContext, envioLabels, 3 hooks, TransporteCard, EnviosConfigView, envios.tsx) → **exit 0, zero violations** (newline-before-return, lines-around-comment, no-unused-vars all clean).

### Backend
`npx tsc --noEmit` → no storeConfig.controller errors. `npx jest storeConfig.controller` → **5/5 PASS** (existing whitelist + restaurant tests, regression-0).

## Deviations from Plan

### Auto-fixed / Adjusted

**1. [Contract correction] cuentas row per-client balance field = `clientBalance`, not `balance`**
- **Found during:** Task 2 (reading 42-04-SUMMARY.md as instructed)
- **Issue:** The 42-05 plan body text described the cuentas row as `{ …, branchId, balance }`, but the authoritative 42-04-SUMMARY (Route 2 — the route's actual owner) defines the field as `clientBalance: number | null` (StoreClient.balance, credit module owned).
- **Fix:** Mapped `clientBalance` in `CuentaPorCobrarRow`. This matches the live backend contract; mapping `balance` would have yielded `undefined`.
- **Files:** `useCuentasPorCobrar.ts`  •  **Commit:** e054609

**2. [Rule 3 - Blocking] Added `useEnvios` to backend update-flag whitelist**
- **Found during:** Task 3 (wiring the EnviosConfigView toggle)
- **Issue:** `storeConfig.controller.ts` `updateFlagPatch`/`updateFlagPut` `allowedFields` did not include `useEnvios` → any toggle PUT/PATCH would throw `BadRequestException('Campo no permitido')`, making it impossible to ever enable the gate from the UI (the card would be permanently unreachable). The `use_envios` column itself already exists (42-01).
- **Fix:** Added `'useEnvios'` to both whitelists. storeConfig.controller spec still 5/5 PASS.
- **Files:** `api-ventago/.../storeConfig.controller.ts`  •  **Commit:** 536521b

**3. [Scope clarification] Added EnviosConfigView + /configuracion/envios page**
- **Found during:** Task 3 (card placement)
- **Issue:** The plan said "render the card in a configuración view" but the retail config home (Preferencias) is a fixed resizable 3-panel layout with no envíos slot, and `RestauranteConfigView` (the cited analog) is itself a dedicated toggle+card view mounted on its own page.
- **Fix:** Created a self-contained `EnviosConfigView` (toggle + gated TransporteCard) and a `/configuracion/envios` admin page, mirroring the RestauranteConfigView/restaurante.tsx pattern exactly. The card is double-gated (page `enabled` + card-internal `useEnvios`).
- **Files:** `EnviosConfigView.tsx`, `pages/configuracion/envios.tsx`  •  **Commit:** edc9ca9

## Known Stubs
None — all hooks bind to live backend routes (42-01/42-04), the context fetches a real flag, and the card performs real CRUD. envioLabels is pure presentation data (intentional static maps, not stubs).

## Self-Check: PASSED
- FOUND: ventago-app/src/configs/envioLabels.ts
- FOUND: ventago-app/src/hooks/api/useTransportes.ts
- FOUND: ventago-app/src/hooks/api/useDespachoBoard.ts
- FOUND: ventago-app/src/hooks/api/useCuentasPorCobrar.ts
- FOUND: ventago-app/src/views/configuracion/transporte/TransporteCard.tsx
- FOUND: ventago-app/src/views/configuracion/transporte/EnviosConfigView.tsx
- FOUND: ventago-app/src/pages/configuracion/envios.tsx
- FOUND: ventago-app/src/context/StoreConfigContext.tsx (useEnvios)
- FOUND: api-ventago/.../storeConfig.controller.ts (useEnvios whitelist)
- FOUND commits: 20ee42b (Task 1), e054609 (Task 2), edc9ca9 (Task 3 frontend), 536521b (Task 3 backend)
