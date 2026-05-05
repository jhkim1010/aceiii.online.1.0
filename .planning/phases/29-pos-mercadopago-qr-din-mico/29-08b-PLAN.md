---
phase: 29
plan: 08b
type: execute
wave: 6
depends_on: [08]
files_modified:
  - ventago-app/src/views/mercadopago/hooks/useMpWallets.ts
  - ventago-app/src/views/mercadopago/hooks/useMpMovements.ts
  - ventago-app/src/views/cash-control/components/McdpgWalletRow.tsx
  - ventago-app/src/views/cash-control/components/McdpgTransferModal.tsx
  - ventago-app/src/views/cash-control/components/McdpgDetailModal.tsx
  - ventago-app/src/views/cash-control/list/components/CashControlList.tsx
autonomous: true
requirements:
  - MP-POS-01

must_haves:
  truths:
    - "control-de-caja page renders 'Caja Mercadopago' row(s) above physical caja table — cyan tint + MP badge + VIRTUAL chip + Transferir + Detalle buttons"
    - "Transfer modal: amount input + 25/50/100% quick-fill + target box select + note field + balance preview"
    - "Detail modal: mp_movements table sorted by created_at DESC + 'Transferir saldo' footer CTA"
    - "Vendedor sees disabled Transferir button with explanatory tooltip"
    - "All Spanish (AR) copy matches UI-SPEC Surface 4"
    - "Successful transfer triggers refetch of useMpWallets + box list (UI updates without manual refresh)"
  artifacts:
    - path: "ventago-app/src/views/mercadopago/hooks/useMpWallets.ts"
      provides: "SWR hook to GET /mercadopago/wallets"
      contains: "useApi"
    - path: "ventago-app/src/views/mercadopago/hooks/useMpMovements.ts"
      provides: "SWR hook to GET /mercadopago/wallets/:id/movements"
      contains: "useApi"
    - path: "ventago-app/src/views/cash-control/components/McdpgWalletRow.tsx"
      provides: "Highlighted Caja MP row with badge + chips + actions"
      contains: "Caja Mercadopago"
    - path: "ventago-app/src/views/cash-control/components/McdpgTransferModal.tsx"
      provides: "Transfer form with quick-fill + balance preview"
      contains: "Transferir saldo Mercadopago"
    - path: "ventago-app/src/views/cash-control/components/McdpgDetailModal.tsx"
      provides: "Movements detail modal"
      contains: "Movimientos Caja Mercadopago"
  key_links:
    - from: "ventago-app/src/views/cash-control/list/components/CashControlList.tsx"
      to: "McdpgWalletRow rendered above physical table"
      via: "useMpWallets() loop"
      pattern: "McdpgWalletRow"
    - from: "ventago-app/src/views/cash-control/components/McdpgTransferModal.tsx"
      to: "POST /mercadopago/transfers"
      via: "apiConnector.post"
      pattern: "/mercadopago/transfers"
    - from: "ventago-app/src/views/cash-control/components/McdpgDetailModal.tsx"
      to: "GET /mercadopago/wallets/:id/movements"
      via: "useMpMovements hook"
      pattern: "useMpMovements"
---

<objective>
Wave 6 part B — Frontend Caja MP UX: 2 SWR hooks (useMpWallets, useMpMovements) + 3 components (McdpgWalletRow, McdpgTransferModal, McdpgDetailModal) + integration into existing CashControlList.

Purpose: Plan 08 ships the backend wallet/transfer/cron infrastructure; this plan consumes it from the frontend. Splitting from Plan 08 keeps each plan within the 15-file budget and aligns with backend/frontend deploy boundaries (Jenkins front-coolsistema vs api-coolsistema jobs).

Output: 6 frontend files. After this plan, an admin/gerente sees their MP balance accumulating on control-de-caja, can transfer to a physical caja with full audit trail, and sees movement history with REFUND chips.
</objective>

<execution_context>
@/Users/marcoskim/Trabajos_Programming/ACE_online_1.0/.claude/get-shit-done/workflows/execute-plan.md
@/Users/marcoskim/Trabajos_Programming/ACE_online_1.0/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@.planning/phases/29-pos-mercadopago-qr-din-mico/29-CONTEXT.md
@.planning/phases/29-pos-mercadopago-qr-din-mico/29-UI-SPEC.md
@.planning/phases/29-pos-mercadopago-qr-din-mico/29-PATTERNS.md
@.planning/phases/29-pos-mercadopago-qr-din-mico/29-08-SUMMARY.md
@.claude/skills/sketch-findings-ace-online/references/caja-virtual-wallet.md
@CLAUDE.md
@ventago-app/src/views/cash-control/list/components/CashControlList.tsx
@ventago-app/src/views/cash-control/list/components/ModalCashRegister.tsx
@ventago-app/src/hooks/useApi.ts
@ventago-app/src/services/api.service.ts
@ventago-app/src/types/mercadopago.ts
</context>

<interfaces>
```typescript
// Backend endpoints (from Plan 08, ready to consume):
GET    /api/mercadopago/wallets?storeId=N             → McdpgWalletRow[]
GET    /api/mercadopago/wallets/:walletId/movements   → McdpgMovementRow[]
POST   /api/mercadopago/transfers                     → { transferId, mpWalletBalanceAfter, boxBalanceAfter }

// Hook contracts (this plan creates):
export function useMpWallets(): SWRResponse<McdpgWalletRow[]>;
export function useMpMovements(walletId: number | null, limit?: number): SWRResponse<McdpgMovementRow[]>;

// Component contracts:
<McdpgWalletRow wallet={...} branchName={...} onTransfer={...} onDetail={...} />
<McdpgTransferModal open={...} wallet={...} availableBoxes={...} onClose={...} onTransferred={...} />
<McdpgDetailModal open={...} wallet={...} onClose={...} onTransferClick={...} />
```
</interfaces>

<tasks>

<task type="auto" tdd="false">
  <name>Task 1: Create 2 SWR hooks (useMpWallets, useMpMovements) + types</name>
  <read_first>
    - ventago-app/src/hooks/useApi.ts (SWR wrapper signature + dedup defaults)
    - ventago-app/src/services/api.service.ts (apiConnector pattern)
    - ventago-app/src/views/mercadopago/hooks/useMpAccounts.ts (analog hook from Plan 06)
    - ventago-app/src/types/mercadopago.ts (existing types from Plan 06)
  </read_first>
  <behavior>
    - useMpWallets fetches GET /mercadopago/wallets?storeId — SWR with 60s dedup (referenced data)
    - useMpMovements(walletId) fetches paginated movements — auto-refetches on transfer success via mutate
    - Conditional fetching: hooks return null key if storeId/walletId missing (skips fetch)
  </behavior>
  <action>
    1. Create `ventago-app/src/views/mercadopago/hooks/useMpWallets.ts`:
       ```typescript
       import { useApi } from 'src/hooks/useApi'
       import { useAuth } from 'src/hooks/useAuth'

       export interface McdpgWalletRow {
         id: number
         mpAccountId: number
         storeId: number
         branchId: number | null
         balance: number
         rawBalance: number
         currency: string
         lastSyncedAt: string | null
       }

       export function useMpWallets() {
         const { user } = useAuth()
         const storeId = user?.storeId

         return useApi<McdpgWalletRow[]>(storeId ? `/mercadopago/wallets?storeId=${storeId}` : null)
       }
       ```
    2. Create `ventago-app/src/views/mercadopago/hooks/useMpMovements.ts`:
       ```typescript
       import { useApi } from 'src/hooks/useApi'

       export interface McdpgMovementRow {
         id: number
         mpWalletId: number
         type: 'credit' | 'debit' | 'transfer_out' | 'transfer_in' | 'refund_debit'
         amount: number
         saleId: number | null
         refundId: number | null
         mpPaymentId: string | null
         transferId: number | null
         note: string | null
         createdAt: string
       }

       export function useMpMovements(walletId: number | null, limit = 50) {
         return useApi<McdpgMovementRow[]>(walletId ? `/mercadopago/wallets/${walletId}/movements?limit=${limit}` : null)
       }
       ```
    3. Lint check: `cd ventago-app && npm run lint -- --max-warnings=0 src/views/mercadopago/hooks/useMpWallets.ts src/views/mercadopago/hooks/useMpMovements.ts`
  </action>
  <verify>
    <automated>cd ventago-app &amp;&amp; npm run lint -- --max-warnings=0 src/views/mercadopago/hooks/useMpWallets.ts src/views/mercadopago/hooks/useMpMovements.ts 2&gt;&amp;1 | tail -5 &amp;&amp; test -f ventago-app/src/views/mercadopago/hooks/useMpWallets.ts &amp;&amp; test -f ventago-app/src/views/mercadopago/hooks/useMpMovements.ts</automated>
  </verify>
  <acceptance_criteria>
    - Both hook files exist
    - Lint exits 0 for both files
    - `grep "useApi<McdpgWalletRow\[\]>" ventago-app/src/views/mercadopago/hooks/useMpWallets.ts` returns 1 line
    - `grep "useApi<McdpgMovementRow\[\]>" ventago-app/src/views/mercadopago/hooks/useMpMovements.ts` returns 1 line
    - Both hooks export TypeScript interfaces (McdpgWalletRow, McdpgMovementRow) for downstream component imports
  </acceptance_criteria>
  <done>2 SWR hooks ready for component consumption.</done>
</task>

<task type="auto" tdd="false">
  <name>Task 2: Create 3 components (McdpgWalletRow + McdpgTransferModal + McdpgDetailModal) per UI-SPEC Surface 4</name>
  <read_first>
    - .planning/phases/29-pos-mercadopago-qr-din-mico/29-UI-SPEC.md (Surface 4 entire — row visual, transfer modal, detail modal, copy table)
    - .claude/skills/sketch-findings-ace-online/references/caja-virtual-wallet.md (LOCKED — winner A, highlighted row design, transfer modal, detail modal)
    - ventago-app/src/views/cash-control/list/components/ModalCashRegister.tsx (modal pattern + Dialog usage)
    - ventago-app/src/services/api.service.ts (apiConnector.post signature)
    - .planning/phases/29-pos-mercadopago-qr-din-mico/29-PATTERNS.md (lines 660-695 — transfer modal patterns)
  </read_first>
  <behavior>
    - McdpgWalletRow: cyan-tinted row (`rgba(0, 177, 234, 0.12)`) with 28px MP badge + "Caja Mercadopago" label + VIRTUAL chip + balance + Transferir/Detalle buttons (admin/gerente only — vendedor sees disabled tooltip "Solo administradores y gerentes pueden transferir saldos MP.")
    - McdpgTransferModal: amount input + 25/50/100% quick-fill buttons + target box select + note field + balance preview Alert + submit calls POST /mercadopago/transfers
    - McdpgDetailModal: movements table sorted by created_at DESC + REFUND chip on refund_debit rows + footer "Transferir saldo" CTA → opens transfer modal
    - All Spanish (AR) copy matches UI-SPEC Surface 4
    - Error handling: inline Alert + toast on failure (per CLAUDE.md feedback_error_visibility)
  </behavior>
  <action>
    1. Create `ventago-app/src/views/cash-control/components/McdpgWalletRow.tsx` (per UI-SPEC Surface 4 visual locks — cyan tint, 28px MP badge, VIRTUAL chip, role-gated Transferir button with tooltip on vendedor). Use the exact JSX/sx values from the prior version of Plan 08 Task 3 (locked design from caja-virtual-wallet.md).

    2. Create `ventago-app/src/views/cash-control/components/McdpgTransferModal.tsx`:
       - Dialog title: "Transferir saldo Mercadopago a caja física"
       - Alert: "Saldo disponible en Caja MP: $X. La transferencia es solo registro contable — el dinero ya está en tu cuenta MP real."
       - TextField (select): caja destino
       - TextField: monto + 25/50/100% quick-fill Stack
       - TextField: nota opcional
       - On submit: validate amount > 0 + ≤ balance, POST /mercadopago/transfers with { mpWalletId, targetBoxId, amount, note }, success toast "✓ Transferencia registrada — $X de Caja MP a {targetName}", error inline Alert + toast
       - On success: call onTransferred() (parent will mutate SWR keys)

       (Use full JSX from prior version of Plan 08 Task 3 — quick-fill setQuickFill(pct), submit busy state, error display, useEffect reset on open.)

    3. Create `ventago-app/src/views/cash-control/components/McdpgDetailModal.tsx`:
       - Dialog title: "Movimientos Caja Mercadopago"
       - useMpMovements(wallet?.id ?? null) for data
       - Empty state: "Aún no hay movimientos en Caja Mercadopago."
       - Table: Fecha (JetBrains Mono) | Descripción | Crédito (success.main) | Débito (error.main)
       - REFUND chip (color='warning', label='REFUND') next to note when type === 'refund_debit'; row bgcolor warning.dark
       - Footer: Cerrar + "Transferir saldo" (color='warning', triggers onTransferClick)

       (Use full JSX from prior version of Plan 08 Task 3 — formatARS helper, conditional cell rendering, refund row styling.)

    4. Lint check: `cd ventago-app && npm run lint -- --max-warnings=0 src/views/cash-control/components/`
  </action>
  <verify>
    <automated>cd ventago-app &amp;&amp; npm run lint -- --max-warnings=0 src/views/cash-control/components/McdpgWalletRow.tsx src/views/cash-control/components/McdpgTransferModal.tsx src/views/cash-control/components/McdpgDetailModal.tsx 2&gt;&amp;1 | tail -5 &amp;&amp; grep "Caja Mercadopago" ventago-app/src/views/cash-control/components/McdpgWalletRow.tsx &amp;&amp; grep "Transferir saldo Mercadopago a caja física" ventago-app/src/views/cash-control/components/McdpgTransferModal.tsx &amp;&amp; grep "Movimientos Caja Mercadopago" ventago-app/src/views/cash-control/components/McdpgDetailModal.tsx</automated>
  </verify>
  <acceptance_criteria>
    - All 3 component files exist
    - Lint exits 0 for all 3 files
    - `grep "Caja Mercadopago" ventago-app/src/views/cash-control/components/McdpgWalletRow.tsx` returns 1 line (UI-SPEC copy)
    - `grep "VIRTUAL" ventago-app/src/views/cash-control/components/McdpgWalletRow.tsx` returns 1 line (UI-SPEC chip)
    - `grep "rgba(0, 177, 234, 0.12)" ventago-app/src/views/cash-control/components/McdpgWalletRow.tsx` returns 1 line (UI-SPEC cyan tint)
    - `grep "Solo administradores y gerentes" ventago-app/src/views/cash-control/components/McdpgWalletRow.tsx` returns 1 line (vendedor disabled tooltip)
    - `grep "Transferir saldo Mercadopago a caja física" ventago-app/src/views/cash-control/components/McdpgTransferModal.tsx` returns 1 line (UI-SPEC modal title)
    - `grep "Movimientos Caja Mercadopago" ventago-app/src/views/cash-control/components/McdpgDetailModal.tsx` returns 1 line (UI-SPEC modal title)
    - `grep "/mercadopago/transfers" ventago-app/src/views/cash-control/components/McdpgTransferModal.tsx` returns 1 line (POST endpoint)
  </acceptance_criteria>
  <done>3 components implement UI-SPEC Surface 4 visuals + Spanish AR copy + role gating.</done>
</task>

<task type="auto" tdd="false">
  <name>Task 3: Integrate Caja MP into CashControlList (above existing physical caja table)</name>
  <read_first>
    - ventago-app/src/views/cash-control/list/components/CashControlList.tsx (entire file — find existing table structure for row injection above physical caja rows)
    - ventago-app/src/views/cash-control/components/McdpgWalletRow.tsx (just-created — props contract)
    - ventago-app/src/views/cash-control/components/McdpgTransferModal.tsx (props contract)
    - ventago-app/src/views/cash-control/components/McdpgDetailModal.tsx (props contract)
    - ventago-app/src/views/mercadopago/hooks/useMpWallets.ts (just-created)
  </read_first>
  <behavior>
    - Add imports for useMpWallets, McdpgWalletRow, McdpgTransferModal, McdpgDetailModal
    - Add state: `selectedWallet` (McdpgWalletRow | null), `transferModalOpen` (boolean), `detailModalOpen` (boolean)
    - Get availableBoxes from existing box list (whatever variable the file already uses — `boxList` / `cajas` / similar)
    - Above the existing physical caja table rows, render `<McdpgWalletRow>` for each wallet from `useMpWallets()` with onTransfer/onDetail handlers wired to state setters
    - Render `<McdpgTransferModal>` and `<McdpgDetailModal>` at the end of JSX with appropriate state
    - On transfer success: refetch both useMpWallets (mutate) and the existing box list (whatever existing refetch mechanism)
    - On detail modal "Transferir saldo" click: close detail modal + open transfer modal with same wallet
  </behavior>
  <action>
    1. Edit `ventago-app/src/views/cash-control/list/components/CashControlList.tsx` (UPDATE — minimal Edit using surgical inserts):
       - Add imports at top:
         ```typescript
         import { useState } from 'react'
         import { useMpWallets, type McdpgWalletRow as TMpWallet } from 'src/views/mercadopago/hooks/useMpWallets'
         import McdpgWalletRow from 'src/views/cash-control/components/McdpgWalletRow'
         import McdpgTransferModal from 'src/views/cash-control/components/McdpgTransferModal'
         import McdpgDetailModal from 'src/views/cash-control/components/McdpgDetailModal'
         ```
       - Inside the component function, after existing hooks:
         ```typescript
         const { data: mpWallets, mutate: mutateMpWallets } = useMpWallets()
         const [selectedWallet, setSelectedWallet] = useState<TMpWallet | null>(null)
         const [transferModalOpen, setTransferModalOpen] = useState(false)
         const [detailModalOpen, setDetailModalOpen] = useState(false)

         // 기존 box list 에서 transfer modal 의 availableBoxes 추출 (existing var name varies — adapt)
         const availableBoxes = (boxList ?? []).map((b: any) => ({ id: b.id, name: b.name }))
         ```
       - Above the existing physical caja TableBody / table rows, inject:
         ```tsx
         {mpWallets?.map((w) => (
           <McdpgWalletRow
             key={w.id}
             wallet={w}
             onTransfer={(wallet) => { setSelectedWallet(wallet); setTransferModalOpen(true); }}
             onDetail={(wallet) => { setSelectedWallet(wallet); setDetailModalOpen(true); }}
           />
         ))}
         ```
       - Before the closing return tag, append the modals:
         ```tsx
         <McdpgTransferModal
           open={transferModalOpen}
           wallet={selectedWallet}
           availableBoxes={availableBoxes}
           onClose={() => setTransferModalOpen(false)}
           onTransferred={() => {
             mutateMpWallets()
             // existing box list refetch (adapt to local pattern, e.g. mutateBoxList())
           }}
         />
         <McdpgDetailModal
           open={detailModalOpen}
           wallet={selectedWallet}
           onClose={() => setDetailModalOpen(false)}
           onTransferClick={() => { setDetailModalOpen(false); setTransferModalOpen(true); }}
         />
         ```
    2. Lint + build: `cd ventago-app && npm run lint -- --max-warnings=0 && npm run build`
  </action>
  <verify>
    <automated>cd ventago-app &amp;&amp; npm run lint -- --max-warnings=0 src/views/cash-control/list/components/CashControlList.tsx 2&gt;&amp;1 | tail -5 &amp;&amp; npm run build 2&gt;&amp;1 | tail -10 | grep -E "(Compiled|error)" &amp;&amp; grep "McdpgWalletRow" ventago-app/src/views/cash-control/list/components/CashControlList.tsx | wc -l</automated>
  </verify>
  <acceptance_criteria>
    - Lint exits 0 for CashControlList.tsx
    - `npm run build` succeeds (Next.js compiles without errors)
    - `grep "McdpgWalletRow" ventago-app/src/views/cash-control/list/components/CashControlList.tsx | wc -l` returns at least 2 (import + JSX usage)
    - `grep "McdpgTransferModal" ventago-app/src/views/cash-control/list/components/CashControlList.tsx | wc -l` returns at least 2 (import + JSX usage)
    - `grep "McdpgDetailModal" ventago-app/src/views/cash-control/list/components/CashControlList.tsx | wc -l` returns at least 2 (import + JSX usage)
    - `grep "useMpWallets" ventago-app/src/views/cash-control/list/components/CashControlList.tsx` returns at least 1 line
  </acceptance_criteria>
  <done>Caja MP fully integrated into control-de-caja UI; transfer modal + detail modal functional; lint + build pass.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Browser UI ↔ apiConnector → backend | sessionToken header auto-injected by api.service.ts; backend re-validates with @Auth |
| McdpgTransferModal submit ↔ POST /mercadopago/transfers | Frontend role check is UX only; backend @Auth(admin, gerente) is the security boundary |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-29-vendedor-bypass | E (EoP) | Vendedor calls /mercadopago/transfers via curl bypassing UI tooltip | accept (handled in Plan 08) | Backend @Auth(admin, superadmin, gerente) on POST endpoint — vendedor JWT cannot reach the endpoint regardless of frontend behavior. Frontend tooltip is UX only. |
| T-29-stale-cache | A (data consistency) | UI shows pre-transfer balance after success | mitigate | mutateMpWallets() called inside onTransferred callback — SWR invalidates cache and refetches. User sees fresh balance immediately. |
| T-29-double-submit | T (Tampering) | User clicks "Confirmar transferencia" twice | mitigate | `busy` state disables button during submit; backend SELECT FOR UPDATE rejects concurrent attempts on same wallet (Plan 08 Task 1). |
</threat_model>

<verification>
- 2 SWR hooks created and lint-clean
- 3 components render UI-SPEC Surface 4 design with exact copy + cyan tint + role gating
- CashControlList renders Caja MP rows above physical caja
- Transfer modal POSTs to /mercadopago/transfers (Plan 08 endpoint)
- Detail modal shows mp_movements with REFUND chip on refund_debit rows
- Lint exits 0 for all touched files
- `npm run build` exits 0
</verification>

<success_criteria>
- Admin/gerente can transfer MP balance to a physical caja from control-de-caja UI
- Vendedor sees disabled button with tooltip
- Detail modal shows movement history with REFUND chip on refund rows
- Successful transfer triggers SWR mutate → balance updates without manual refresh
- All Spanish (AR) copy matches UI-SPEC Surface 4
</success_criteria>

<output>
After completion, create `.planning/phases/29-pos-mercadopago-qr-din-mico/29-08b-SUMMARY.md` with:
- 2 hooks + 3 components + 1 integration site
- UI screenshots checklist (manual verification per VALIDATION.md Manual-Only Verifications)
- Pending: Plan 09 refunds (last plan)
</output>
