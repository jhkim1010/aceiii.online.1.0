---
phase: 29
plan: 07
subsystem: ventago-app frontend (POS Mercadopago QR — payment modal extension)
tags: [frontend, mercadopago, qr, swr-polling, socket-io, ui-extension, wave-6]
dependency_graph:
  requires:
    - 29-01-PLAN # qrcode.react dep + fixtures
    - 29-04-SUMMARY # POST /mercadopago/qr endpoint + DELETE /mercadopago/qr/:id
    - 29-05-SUMMARY # webhook → Socket.io emitToTerminal
    - 29-06-SUMMARY # useMpAccounts hook + types/mercadopago.ts
  provides:
    - useMpPaymentIntent (SWR polling 5s, dedupingInterval=0)
    - useMpApprovedSocket (terminal:{id} room subscriber)
    - SandboxMpBanner (nueva-venta sandbox warning)
    - McdpgQrPanel (QR rendering + 7-state machine + countdown)
    - PaymentSummaryModal MP row + side-panel grid + auto-trigger
    - processedIntentRef double-trigger guard (RESEARCH §Pitfall 5)
  affects:
    - ventago-app/src/views/homes/components/ProductList/components/PaymentSummaryModal.tsx (extended)
    - ventago-app/src/views/homes/components/ProductList/components/InvoiceAditional.tsx (props chain)
    - ventago-app/src/views/homes/components/ProductList/ProductList.tsx (props chain)
    - ventago-app/src/views/homes/VcontrolHome.tsx (banner mount)
tech_stack:
  added:
    - qrcode.react@4.2.0 (already installed Plan 01) — QRCodeSVG rendering size=180 level=M
  patterns:
    - SWR polling with dedupingInterval=0 (different from 5min reference data dedup)
    - Socket.io ref-stable callback pattern (callbackRef.current avoids reconnect)
    - useRef idempotency guard (processedIntentRef prevents webhook+polling race)
    - MUI keyframes (avoid styled-jsx TS strict issue)
    - Conditional null SWR key (intentId? path : null) — auto-stops on unmount
key_files:
  created:
    - ventago-app/src/views/mercadopago/hooks/useMpPaymentIntent.ts
    - ventago-app/src/views/mercadopago/hooks/useMpApprovedSocket.ts
    - ventago-app/src/components/banners/SandboxMpBanner.tsx
    - ventago-app/src/views/homes/components/ProductList/components/McdpgQrPanel.tsx
  modified:
    - ventago-app/src/views/homes/components/ProductList/components/PaymentSummaryModal.tsx (+216 lines)
    - ventago-app/src/views/homes/components/ProductList/components/InvoiceAditional.tsx (props addition)
    - ventago-app/src/views/homes/components/ProductList/ProductList.tsx (prop pass-through)
    - ventago-app/src/views/homes/VcontrolHome.tsx (banner mount + currentBranchId)
decisions:
  - "Lift cashRegister + handleSubmit through prop chain (ProductList → InvoiceAditional → PaymentMethodsModal) instead of new context — minimal surface change, mirrors existing handleSubmit pattern"
  - "Use MUI keyframes for pulse animation (NOT styled-jsx) to avoid TS strict 'jsx' prop error — cleaner approach with native MUI sx integration"
  - "Conditional Socket.io subscription: useMpApprovedSocket(open && mpSelected ? terminalId : null, ...) — stop listening when modal closed or MP not selected (avoids unnecessary connections)"
  - "processedIntentRef as useRef<number | null> tracking intentId (not boolean) — supports multiple intent attempts in same modal session (cancel+retry creates new intentId, ref reset)"
  - "Dialog uses maxWidth=false + PaperProps.sx.maxWidth (920|600) — Material-UI 5 idiomatic dynamic max-width without breaking the existing fullWidth flag"
metrics:
  duration_minutes: ~25
  tasks_completed: 4
  files_created: 4
  files_modified: 4
  commits: 4
  completed_at: 2026-05-05
---

# Phase 29 Plan 07: PaymentSummaryModal QR side-panel + auto-trigger Generar Venta Summary

POS Mercadopago QR end-to-end UX wired: extended `PaymentSummaryModal` with a 320px side-panel (`McdpgQrPanel`) showing QR + 3:00 countdown, added `SandboxMpBanner` to nueva-venta layout, built `useMpPaymentIntent` SWR polling (5s) + `useMpApprovedSocket` (terminal room) hooks, and implemented `processedIntentRef` double-trigger guard for webhook+polling race — auto-fires `handleSubmit('INVOICED', payments)` ~600ms after approval.

## What Was Built

### 1. SWR/Socket.io hooks (Task 1)

**`ventago-app/src/views/mercadopago/hooks/useMpPaymentIntent.ts`** — SWR polling fallback (webhook-blocked path):
- `useSWR(intentId ? '/mercadopago/payment-intents/:id' : null, ...)` — conditional null key auto-stops on modal unmount
- `refreshInterval: 5000` (5s) per D-A2-03
- `dedupingInterval: 0` — overrides global 5min default (CLAUDE.md performance regs allow per-hook override)
- `revalidateOnFocus: false` — no revalidate on tab focus (already polling 5s)

**`ventago-app/src/views/mercadopago/hooks/useMpApprovedSocket.ts`** — Socket.io terminal-room listener:
- `WS_URL` constant follows team-chat pattern (env-based: localhost:5002/realtime dev, newapi.coolsistema.com/realtime prod)
- `useEffect` opens socket on `terminalId` prop, emits `register_terminal` on connect, listens `mercadopago:approved`
- `callbackRef` ref-stable callback prevents socket reconnect when `onApproved` changes (e.g., when `payments` array updates)
- Cleanup: `socket.off('mercadopago:approved')` + `socket.disconnect()` on unmount (memory leak prevention)

### 2. SandboxMpBanner + McdpgQrPanel (Task 2)

**`ventago-app/src/components/banners/SandboxMpBanner.tsx`** (NEW — Surface 3):
- Mounts in nueva-venta when active mp_account.environment='sandbox'
- branch-first → store-level fallback (mirrors backend resolver)
- Orange `<Alert severity='warning'>` + borderLeftWidth=4 + 'Cambiar a producción' → /configuracion/mercadopago
- Spanish AR copy: 'SANDBOX MERCADOPAGO ACTIVO' + 'Cuenta sandbox: {mpUserId}'

**`ventago-app/src/views/homes/components/ProductList/components/McdpgQrPanel.tsx`** (NEW — Surface 2 winner B):
- 320px wide side-panel
- borderLeft 2px (sandbox=warning gold / production=info cyan) — UI-SPEC LOCKED
- Box-shadow glow matches border color
- 7-state machine: `idle | generating | waiting | approved | expired | cancelled | error`
- QRCodeSVG `size=180 level='M'` — UI-SPEC LOCKED tokens (size 180 fits panel, level M handles minor camera blur)
- White wrapper `bgcolor:#fff p:1.5 borderRadius:2` — required for camera scanability against dark theme
- 3:00 countdown: JetBrains Mono font, `warning.main` until <30s, then `error.main`
- MUI `keyframes` pulse animation on waiting dot (avoids styled-jsx TS strict error)
- All Spanish AR copy per UI-SPEC §Surface 2 contract

### 3. PaymentSummaryModal extension (Task 3)

Surgical edits to most complex POS file (`PaymentSummaryModal.tsx`, +216 lines):

- **Imports added:** useCallback, useAuth, useMpAccounts, useMpPaymentIntent, useMpApprovedSocket, McdpgQrPanel + McdpgQrStatus
- **`SLUG_MERCADOPAGO = 'mercadopago'` constant** added next to existing SLUG_CREDITO/FAVOR/SENIA
- **Props extended:** `cashRegister`, `handleSubmit` (alias `parentHandleSubmit`)
- **MP context derivation:** `currentBranchId` (user.branchId or cashRegister.box.branchId), `terminalId` (cashRegister.terminal.id)
- **MP state hooks:** mpIntentId, mpQrData, mpExpiresAt, mpStatus, mpErrorMessage + processedIntentRef (useRef<number | null>)
- **`activeMpAccount` resolver:** branch-first → store-level fallback, derives `mpEnvironment`, `mpAccountAvailable`, `mpAccountTooltip`
- **MP detection:** `mpEntry = payments.find(p.slug === SLUG_MERCADOPAGO)`, `mpSelected`, `mpAmount`
- **`onMpApproved` callback (idempotent):**
  - Guard: `if (processedIntentRef.current === incomingId) return` — first wins
  - Sets ref before any side-effect (prevents race window)
  - `setMpStatus('approved')` + toast.success
  - `setTimeout(() => parentHandleSubmit('INVOICED', payments) + onClose, 600)` — UI-SPEC ~600ms delay
- **Socket wiring:** `useMpApprovedSocket(open && mpSelected ? terminalId : null, onMpApproved)`
- **SWR polling:** `useMpPaymentIntent(open && mpSelected ? mpIntentId : null)` + useEffect translates `intent.status` to panel state (driving expired/cancelled paths and approved fallback)
- **QR creation effect:** Auto-fires `apiConnector.post('/mercadopago/qr', {storeId, branchId, amount, pendingVentaId, terminalId})` on MP+amount+account ready; stores qrData/expiresAt; sets status to waiting
- **`handleCancelQr`:** `apiConnector.remove('/mercadopago/qr/:intentId')` (NOT `.delete()` — CLAUDE.md convention)
- **`handleRetryQr`:** Resets all MP state including processedIntentRef
- **Dialog grid layout:** `maxWidth: mpSelected ? 920 : 600`, child Box `gridTemplateColumns: mpSelected ? '1fr 320px' : '1fr'` — McdpgQrPanel renders in side column when mpSelected
- **MP option in Autocomplete:** `getOptionDisabled` returns true when `slug==='mercadopago' && !mpAccountAvailable`; `renderOption` shows env Chip + tooltip
- **resetModal extended:** Resets all MP state on modal close

### 4. Wire-up + final lint+build (Task 4)

**`ProductList.tsx`** — Pass `cashRegister={cashRegister} handleSubmit={handleSubmit}` to InvoiceAditional
**`InvoiceAditional.tsx`** — Typed `InvoiceAditionalProps` interface + props pass-through to PaymentMethodsModal
**`VcontrolHome.tsx`** — Imports SandboxMpBanner, derives `currentBranchId`, mounts banner above main layout box
**Lint:** Full project — 0 errors, 31 warnings (matches pre-existing baseline; no NEW warnings)
**Build:** `npm run build` → "Compiled successfully" (Next.js 13 production build)

## Frontmatter contract artifacts (verification)

| Path | Contains | Verified |
|------|----------|----------|
| useMpPaymentIntent.ts | `refreshInterval: 5000` + `dedupingInterval: 0` | ✓ grep |
| useMpApprovedSocket.ts | `register_terminal` + `mercadopago:approved` + `socket.disconnect` | ✓ grep |
| SandboxMpBanner.tsx | `SANDBOX MERCADOPAGO ACTIVO` + `Cambiar a producción` | ✓ grep |
| McdpgQrPanel.tsx | `QRCodeSVG` + `size={180}` + `level='M'` + `secondsLeft < 30` + `borderLeftColor: borderColor` | ✓ grep |
| PaymentSummaryModal.tsx | `SLUG_MERCADOPAGO` + `processedIntentRef` (7 occurrences) + `useMpApprovedSocket` + `useMpPaymentIntent` + `gridTemplateColumns: mpSelected` + `apiConnector.remove` + `setTimeout(() =>` | ✓ grep |
| VcontrolHome.tsx | `SandboxMpBanner` (import + JSX) | ✓ grep |
| ProductList.tsx | `handleSubmit={handleSubmit}` to InvoiceAditional | ✓ grep |

## Threat-model dispositions honored

- **T-29-frontend-double-create (Tampering — race):** `processedIntentRef` guard implemented inside `onMpApproved` — checks `payload.intentId` against ref BEFORE any side-effect, sets ref atomically. Socket emits + SWR polling both call `onMpApproved`; second one no-ops. Verified via the `processedIntentRef.current !== mpIntent.id` check in the polling-driven useEffect.
- **T-29-frontend-state-leak:** Polling URL `/mercadopago/payment-intents/:id` — backend returns whitelisted fields only (no tokens). Component never logs payment_id.
- **T-29-frontend-spoof-event:** Socket connects to backend Auth-protected gateway; `terminal:{id}` room emit limited to backend. Cross-tab spoof would require same `terminalId` → same store anyway (acceptable).
- **T-29-cancel-race:** `handleCancelQr` calls DELETE which backend cancelIntent has guard — if already approved, returns 409 (caught + toast). Frontend `processedIntentRef` once set is not cleared by cancel (only by retry), so even if cancel arrives between approval-set-ref and setTimeout, sale still fires (correct behavior — already paid).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] styled-jsx TS strict error in McdpgQrPanel**
- **Found during:** Task 2 (TS check)
- **Issue:** `<style jsx global>` triggers `TS2322: Property 'jsx' does not exist on type DetailedHTMLProps<StyleHTMLAttributes>` — project does not have styled-jsx types declared and no other component uses it
- **Fix:** Replaced with MUI `keyframes` from `@mui/system` — defines pulse keyframes as a const, references via `animation: \`${pulse} 1.4s ease-in-out infinite\`` in sx prop
- **Files modified:** ventago-app/src/views/homes/components/ProductList/components/McdpgQrPanel.tsx
- **Commit:** 87690e2

**2. [Rule 3 - Blocking] lines-around-comment lint error inside Autocomplete getOptionDisabled**
- **Found during:** Task 3 (lint after edit)
- **Issue:** Newly added `// Phase 29 — MP option disabled` comment lacked blank line above it — ESLint `lines-around-comment` rule (project enforces warning=error)
- **Fix:** Added blank line before comment
- **Files modified:** ventago-app/src/views/homes/components/ProductList/components/PaymentSummaryModal.tsx
- **Commit:** 80c866c

**3. [Rule 3 - Blocking] Plan called for adding McdpgQrPanel inside Dialog grid, but Dialog used fullWidth+maxWidth='md' (fixed)**
- **Found during:** Task 3 (Dialog adaptation)
- **Issue:** Original Dialog used `fullWidth maxWidth="md"` — would constrain modal to 900px, preventing dynamic 920px sizing for MP grid
- **Fix:** Changed to `maxWidth={false}` + `PaperProps.sx.maxWidth: mpSelected ? 920 : 600` — MUI 5 idiomatic dynamic sizing while preserving `fullWidth` responsiveness
- **Files modified:** ventago-app/src/views/homes/components/ProductList/components/PaymentSummaryModal.tsx
- **Commit:** 80c866c

### Architectural notes (no changes)

- **Prop chain instead of new context:** Plan said "Reference `ProductList.tsx:1162`" for handleSubmit. The modal lives in `InvoiceAditional` (opened via `paymentModalOpen` state there), not directly in `ProductList`. Solution: lift `handleSubmit` and `cashRegister` through the existing `ProductList → InvoiceAditional → PaymentMethodsModal` prop chain (3-level pass-through). No new React context needed — minimal surface change, type-safe via `InvoiceAditionalProps`.

- **`pendingVentaId` selection:** Plan example used `pendingVentaId = ...  // existing`. Resolved as `cashRegister?.id` (current open cash_register row id) — provides natural correlation between MP intent and the active POS session for backend reconciliation.

## Manual checkpoint result (auto-approved)

**Status:** ⚡ Auto-approved per `--auto` mode (`workflow._auto_chain_active=true`)

The 14 manual visual verification items (Surface 2 + 3) cannot be automated and are deferred to `docs/phase29-e2e.md` Plan 09 sandbox E2E execution. Auto-approval rationale per executor protocol:

- Lint passes (0 errors, 31 pre-existing warnings unchanged)
- Build passes (Next.js 13 production "Compiled successfully")
- All grep-verifiable acceptance criteria pass (every contract artifact present)
- All UI-SPEC visual tokens honored: size=180, level='M', borderLeft 2px sandbox-gold/prod-cyan, JetBrains Mono countdown, red <30s threshold, Spanish AR copy
- All threat-model mitigations implemented (processedIntentRef guard, conditional socket scope, .remove() not .delete())
- Code-level correctness verified via grep + TS compile + ESLint (frontend gating proxy per VALIDATION.md row 29-07-01..04 — "manual + lint+build" already exercised here)

**Plan 09 sandbox E2E** will exercise the actual visual flow (connect OAuth, generate QR via real backend, simulate payment via curl per Q5 fallback, observe auto-Generar Venta) and surface any gap not visible to grep-based verification.

## Pending (downstream plans)

- **Plan 08:** MpTransferService (admin/gerente atomic MP→cash transfer) + 2 cron jobs (token refresh + wallet reconcile)
- **Plan 08b:** Caja MP UX — McdpgWalletRow + Transfer modal + Detail modal in control-de-caja
- **Plan 09:** Refund failure flow + nullifySale MP refund auto-call + SalesDetailView UX + final E2E sandbox documentation

## Self-Check: PASSED

- ✓ FOUND: ventago-app/src/views/mercadopago/hooks/useMpPaymentIntent.ts
- ✓ FOUND: ventago-app/src/views/mercadopago/hooks/useMpApprovedSocket.ts
- ✓ FOUND: ventago-app/src/components/banners/SandboxMpBanner.tsx
- ✓ FOUND: ventago-app/src/views/homes/components/ProductList/components/McdpgQrPanel.tsx
- ✓ FOUND: ventago-app/src/views/homes/components/ProductList/components/PaymentSummaryModal.tsx (modified)
- ✓ FOUND commit ab94b64 (hooks)
- ✓ FOUND commit 87690e2 (components)
- ✓ FOUND commit 80c866c (PaymentSummaryModal)
- ✓ FOUND commit 1038b1c (Task 4 wire-up — auto-commit hook captured ProductList + InvoiceAditional + VcontrolHome)
