---
phase: 29-pos-mercadopago-qr-din-mico
plan: 08b
subsystem: payments
tags: [mercadopago, frontend, swr, mui, control-de-caja, caja-virtual, transfer-modal]

# Dependency graph
requires:
  - phase: 29
    provides: "Plan 08 backend endpoints (GET /mercadopago/wallets, GET /mercadopago/wallets/:id/movements, POST /mercadopago/transfers); Plan 06 useMpAccounts hook pattern; existing useApi SWR wrapper + apiConnector"
provides:
  - useMpWallets — SWR hook fetching GET /mercadopago/wallets?storeId
  - useMpMovements — SWR hook fetching GET /mercadopago/wallets/:walletId/movements (conditional on walletId)
  - McdpgWalletRow — cyan-tinted MUI TableRow with MP badge + VIRTUAL chip + role-gated Transferir/Detalle buttons
  - McdpgTransferModal — Dialog with target box select + amount + 25/50/100% quick fills + note + balance preview Alert
  - McdpgDetailModal — movements timeline with REFUND chip on refund_debit + sale_id Link + footer "Transferir saldo" CTA
  - CashControlList integration — MP wallet rows rendered above existing FullTable inside the same CardFilter
  - Mercadopago domain types extended (McdpgWalletRow, McdpgMovementRow, McdpgTransferRequest)
affects: [29-09, future-cash-control-ui, control-de-caja-page]

# Tech tracking
tech-stack:
  added: []  # 모든 deps 기존 (MUI 5, SWR via useApi, react-hot-toast, next/Link)
  patterns:
    - "SWR 5min dedup for reference data via shared useApi wrapper (CLAUDE.md performance 규약)"
    - "Conditional SWR fetching with null key (skips request when storeId/walletId 미존재)"
    - "React.memo on row component to avoid re-renders when parent state updates"
    - "Role-gated UX: admin/superadmin/gerente check via user.roles array (UI hint only — backend @Auth is the security boundary)"
    - "Inline Alert + react-hot-toast for errors (CLAUDE.md feedback_error_visibility)"
    - "Modal chain: Detail → close + open Transfer (same selectedWallet state)"
    - "Defensive shape handling for hooks returning either plain array or {data} paginated object"

key-files:
  created:
    - ventago-app/src/views/mercadopago/hooks/useMpWallets.ts
    - ventago-app/src/views/mercadopago/hooks/useMpMovements.ts
    - ventago-app/src/views/cash-control/components/McdpgWalletRow.tsx
    - ventago-app/src/views/cash-control/components/McdpgTransferModal.tsx
    - ventago-app/src/views/cash-control/components/McdpgDetailModal.tsx
  modified:
    - ventago-app/src/types/mercadopago.ts
    - ventago-app/src/views/cash-control/list/components/CashControlList.tsx

key-decisions:
  - "MP wallet rows rendered inside CashControlList CardFilter (above FullTable), NOT merged into FullTable (DataGrid). Reason: FullTable is paginated MUI X DataGrid; the highlighted-row visual + custom action buttons + chip + tooltip do not map cleanly to DataGrid's renderCell column model. A small adjacent MUI Table preserves the Variant A 'highlighted row above the same area' design while keeping the existing DataGrid pristine."
  - "useBox(storeId, {pageSize:50}) used to source availableBoxes for transfer modal. Pageable but capped at 50 (CLAUDE.md ≤50 규약). For >50 boxes a search-select would be needed in the future."
  - "branchName lookup uses defensive Array.isArray(branches) || branches.data — useBranch returns plain array, but other hooks in the codebase return {data,total}; defensive shape handling avoids runtime crash if hook is later changed."
  - "Type re-exports from hooks (McdpgWalletRow, McdpgMovementRow) enable single-import usage in components — no need to import from both hook + types."
  - "React.memo applied only to McdpgWalletRow (high-frequency re-render risk via parent state). Modals are mounted/unmounted on open — no memo needed."

patterns-established:
  - "Caja MP UI integration pattern reusable for Phase 30 MP Point (1 wallet per mp_account, payment-method agnostic)"
  - "MUI Table inside FullTable's parent CardFilter — works for adding 'special rows' that don't fit DataGrid cell-renderer model"
  - "Conditional SWR fetch for modal-driven detail data (movements only fetched when modal open)"

requirements-completed:
  - MP-POS-01

# Metrics
duration: 8 min
completed: 2026-05-05
---

# Phase 29 Plan 08b: Caja MP Frontend (Wallet Row + Transfer/Detail Modals) Summary

**Frontend Caja MP UX consuming Plan 08 endpoints — 2 SWR hooks + 3 React components + integration into Control de Caja page.**

## Performance

- **Duration:** 8 min
- **Started:** 2026-05-05T15:16:25Z
- **Completed:** 2026-05-05T15:24:39Z
- **Tasks:** 3
- **Files created:** 5
- **Files modified:** 2

## Accomplishments

- **2 SWR hooks** (`useMpWallets`, `useMpMovements`) under `src/views/mercadopago/hooks/` — both use the project's shared `useApi` wrapper (SWR 5-min dedup config). Both implement conditional fetch (null key when key data missing) so they never burn a network round-trip when `storeId` or `walletId` is unavailable.
- **3 components** under `src/views/cash-control/components/` matching UI-SPEC Surface 4 exactly: cyan-tinted highlighted row (`rgba(0, 177, 234, 0.12)` bg + 28×28 MP badge + VIRTUAL chip), Transfer Modal with 25/50/100% quick-fill + balance Alert + role-gated Confirmar transferencia CTA, Detail Modal with movements table sorted DESC, REFUND chip on refund_debit rows + warning.dark bg, sale_id linked to /ventas/:id, footer chain-action "Transferir saldo".
- **CashControlList integration**: MP wallet section rendered above the existing FullTable (cash registers) inside the same CardFilter — preserves single-page UX while keeping the Variant A "highlighted row" design from sketch findings. Transfer modal `onTransferred` callback mutates `useMpWallets` SWR cache AND refetches the cash register list (so new `box_operations` row from the backend is visible immediately).
- **Type extensions**: `McdpgWalletRow`, `McdpgMovementRow`, `McdpgTransferRequest` added to `src/types/mercadopago.ts`. Re-exported from each hook for ergonomic single-import usage.
- **Threat mitigations**: T-29-vendedor-bypass (frontend tooltip + backend @Auth — defense in depth), T-29-stale-cache (mutate after onTransferred), T-29-double-submit (busy state disables Confirmar transferencia button).
- **All Spanish (AR) copy** verified by grep — matches UI-SPEC Surface 4 (Caja Mercadopago / VIRTUAL / Transferir saldo Mercadopago a caja física / Movimientos Caja Mercadopago / Confirmar transferencia / etc.).

## Task Commits

Each task was committed atomically:

1. **Task 1 — Hooks + types** — `17dcc21` (feat)
2. **Task 2 — 3 components** — `905156c` (feat)
3. **Task 3 — CashControlList integration** — `4573468` (feat)

## Files Created/Modified

### Created (5)

- `ventago-app/src/views/mercadopago/hooks/useMpWallets.ts` — SWR hook GET /mercadopago/wallets?storeId, type re-export
- `ventago-app/src/views/mercadopago/hooks/useMpMovements.ts` — SWR hook GET /mercadopago/wallets/:id/movements, conditional on walletId, default limit=50
- `ventago-app/src/views/cash-control/components/McdpgWalletRow.tsx` — memoized MUI TableRow with cyan tint + 28px MP badge + VIRTUAL chip + role-gated Transferir/Detalle buttons (vendedor → disabled with tooltip)
- `ventago-app/src/views/cash-control/components/McdpgTransferModal.tsx` — Dialog with target box select, amount input (mono right-aligned), 25/50/100% quick-fill buttons, optional note, info Alert (saldo + accounting-only disclaimer), inline error Alert + toast on failure, busy state on Confirmar transferencia
- `ventago-app/src/views/cash-control/components/McdpgDetailModal.tsx` — Dialog with movements timeline (sorted by createdAt DESC), JetBrains Mono timestamps, sale_id linked to /ventas/:id via next/Link, REFUND chip on refund_debit + warning.dark bg, footer "Transferir saldo" CTA chains to transfer modal

### Modified (2)

- `ventago-app/src/types/mercadopago.ts` — added McdpgWalletRow, McdpgMovementRow, McdpgTransferRequest interfaces
- `ventago-app/src/views/cash-control/list/components/CashControlList.tsx` — imports for new hooks/components, useBox to source availableBoxes for transfer destination, MP rows section above the FullTable (rendered only when wallets exist), Transfer + Detail modals at end of return JSX, onTransferred refetches both useMpWallets + cashRegisters list, onTransferClick chains detail → transfer

## Decisions Made

1. **MP rows above FullTable, not merged into DataGrid** — FullTable is a paginated MUI X DataGrid; the Variant A highlighted-row visual + chip + role-gated buttons + tooltip do not map cleanly to DataGrid's column-renderer model. A small adjacent MUI Table inside the same CardFilter preserves the design + keeps the cash register grid pristine. (Plan text said "above the existing physical caja TableBody / table rows, inject" — interpreted as "above the existing table area" within the same Card.)
2. **useBox for availableBoxes** — `useBox(user.storeId, {page:0, pageSize:50})` returns paginated `{data, total}`. pageSize capped at 50 (CLAUDE.md performance 규약). Sufficient for typical store sizes; future stores with >50 cajas would need search-select.
3. **branchName defensive shape handling** — `useBranch` returns plain `any[]`, but other hooks in the codebase return `{data, total}`. Map-builder uses `Array.isArray(branches) || (branches as any).data ?? []` so a future `useBranch` change to paginated shape doesn't crash.
4. **Type re-exports from hooks** — `useMpWallets` re-exports `McdpgWalletRow` type so consumers can `import { useMpWallets, type McdpgWalletRow }` without an additional `from 'src/types/mercadopago'` line.
5. **React.memo only on McdpgWalletRow** — Row receives parent state-change re-renders; modals mount/unmount on open and don't need memo.
6. **JetBrains Mono via inline `sx={{ fontFamily: '"JetBrains Mono", monospace' }}`** — matches existing PaymentSummaryModal pattern (no global theme typography utility exists for this in the project; inline sx keeps changes local + reviewable).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] TypeScript build error: `branches?.data` access on `any[]` type**
- **Found during:** Task 3 build (npm run build → tsc fails)
- **Issue:** Initial code used `(branches?.data ?? branches ?? []).forEach` based on plan's "boxList ?? []" hint, but `useBranch` returns `any[]` plain (no `.data` property). TS rejected: `Property 'data' does not exist on type 'any[]'`.
- **Fix:** Replaced with `Array.isArray(branches) ? branches : ((branches as any)?.data ?? [])` — defensive against either shape.
- **Files modified:** `CashControlList.tsx` (branchNameById useMemo)
- **Committed in:** `4573468` (Task 3 — fix included before commit)

**2. [Rule 1 - Bug] ESLint `lines-around-comment` error in onTransferred callback**
- **Found during:** Task 3 first lint pass
- **Issue:** Inline comment `// refresh cash register list (reflects box_operations 신규 행)` followed `mutateMpWallets();` without a blank line — violates project's `lines-around-comment` rule (CLAUDE.md ESLint 규약).
- **Fix:** Added blank line before the comment.
- **Files modified:** `CashControlList.tsx`
- **Committed in:** `4573468`

---

**Total deviations:** 2 auto-fixed (both bugs caught by tooling). Plan executed largely as written; design contract from caja-virtual-wallet.md skill was the canonical source for visual values.

**Impact on plan:** None — both fixes were tooling-driven (TS + ESLint). Plan deliverables fully met.

## Issues Encountered

- `npm run lint` script runs over the full `src/**` glob and reports 31 pre-existing `react-hooks/exhaustive-deps` warnings across unrelated files. These warnings existed before Plan 08b and are out of scope (per executor SCOPE BOUNDARY rule). Targeted lint via `npx eslint --max-warnings=0 <files>` confirms all 6 Plan 08b files are warning-free.
- `npm run build` (Next.js) passes — full type-check + production bundle compile succeed. CashControlList compiled into the appropriate dynamic chunk.

## TDD Gate Compliance

Plan 08b is non-TDD (frontend UI with manual UX verification per VALIDATION.md). No RED/GREEN/REFACTOR gates applicable. Manual verification checklist below covers acceptance.

## User Setup Required

None — Plan 08b consumes Plan 08 backend endpoints which are already deployed/registered in MercadopagoModule. After merging this plan, control-de-caja page will automatically render Caja MP rows when:
1. Store has at least one connected MP account (Plan 06 OAuth flow)
2. mp_wallets table has at least one row (auto-created on OAuth callback per Plan 06)

## Manual Verification Checklist (per VALIDATION.md rows 29-08b-01..03)

After deploy, manually verify on a store with at least one connected MP account:

- [ ] Navigate to `/control-de-caja` — Caja Mercadopago section renders ABOVE the existing cash registers grid
- [ ] Cyan tint visible on MP wallet rows (`rgba(0, 177, 234, 0.12)`); hover deepens to `rgba(0, 177, 234, 0.18)`
- [ ] 28×28 MP badge (cyan bg, white "MP" text, fontWeight 700) renders at left
- [ ] VIRTUAL chip renders to the right of "Caja Mercadopago" label
- [ ] As admin/gerente: Transferir → button is enabled, opens transfer modal
- [ ] As vendedor: Transferir → button is disabled with tooltip "Solo administradores y gerentes pueden transferir saldos MP."
- [ ] Detalle button opens detail modal with movement history
- [ ] Transfer modal: target box select shows store's physical cajas; amount input mono+right-aligned; quick-fill 25/50/100% sets value from current balance
- [ ] Transfer modal: submit with amount > balance shows "Saldo insuficiente en Caja MP. Disponible: $ X."
- [ ] Transfer modal: successful submit shows toast "✓ Transferencia registrada — $ X de Caja MP a {boxName}"; balance updates without manual refresh
- [ ] Detail modal: shows movements sorted by created_at DESC; refund_debit rows have warning.dark bg + REFUND chip
- [ ] Detail modal: footer "Transferir saldo" → closes detail + opens transfer modal with same wallet
- [ ] Spanish (AR) copy throughout (no English fallback strings)

## Next Phase Readiness

- **Plan 09** (refunds — phase last plan): Can now extend McdpgDetailModal REFUND chip presentation to include click-to-detail action linking to refund attempt history (Surface 5).
- **Production deployment**: This plan ships purely frontend assets. After merge, the front-coolsistema Jenkins job builds + deploys; Caja MP UI becomes available immediately on the next page load. No DB migration, no env vars, no backend redeploy.
- **Phase 30 reusability**: The 2 hooks + 3 components are payment-method-agnostic at the wallet layer (mp_wallets is 1-per-mp_account regardless of QR vs Point). Phase 30 MP Point will reuse them as-is.
- **No blockers.**

## Self-Check: PASSED

Files verified:
- FOUND: ventago-app/src/views/mercadopago/hooks/useMpWallets.ts
- FOUND: ventago-app/src/views/mercadopago/hooks/useMpMovements.ts
- FOUND: ventago-app/src/views/cash-control/components/McdpgWalletRow.tsx
- FOUND: ventago-app/src/views/cash-control/components/McdpgTransferModal.tsx
- FOUND: ventago-app/src/views/cash-control/components/McdpgDetailModal.tsx
- FOUND: ventago-app/src/types/mercadopago.ts (modified — McdpgWalletRow / McdpgMovementRow / McdpgTransferRequest added)
- FOUND: ventago-app/src/views/cash-control/list/components/CashControlList.tsx (modified — MP rows + 2 modals integrated)

Commits verified (in ventago-app repo):
- FOUND: 17dcc21 (feat — hooks + types)
- FOUND: 905156c (feat — 3 components)
- FOUND: 4573468 (feat — CashControlList integration)

Lint: All 6 Plan 08b files exit 0 with `--max-warnings=0` (verified via `npx eslint`).
Build: `npm run build` exits 0 (Next.js production bundle compiles successfully).

---
*Phase: 29-pos-mercadopago-qr-din-mico*
*Completed: 2026-05-05*
