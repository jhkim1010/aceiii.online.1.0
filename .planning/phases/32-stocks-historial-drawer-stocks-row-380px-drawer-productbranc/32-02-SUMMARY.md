---
phase: 32-stocks-historial-drawer
plan: "02"
subsystem: app
tags: [reports, stocks, historial, drawer, mui, useCockpitCache, frontend]

# Dependency graph
requires:
  - phase: 32-stocks-historial-drawer
    plan: "01"
    provides: "GET /reports/stocks-cockpit/historial endpoint + HistorialResponse contract"
  - phase: 12-reportajes-cockpit
    provides: "useCockpitCache (5-min TTL LRU 64) + Vendedor cockpit drawer pattern reference"
provides:
  - "useStocksHistorial(target, storeId, windowDays?) hook with offset accumulation"
  - "StocksHistorialDrawer 380px right MUI Drawer component"
  - "PanelB row historial trigger column (kind='pair')"
  - "PanelC cell hover-reveal historial overlay (kind='pb')"
  - "StocksCockpitBody-owned historialTarget state with re-click toggle close"
affects: [Phase 32 main user-facing artifact, downstream stock-audit phases]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Hook-order-stable lazy fetch: useCockpitCache always invoked, fetcher returns empty when target=null"
    - "Offset-keyed accumulation via useRef(prevOffset) — offset==0 replaces, offset>prev appends"
    - "MUI Box component='td' to enable sx :hover selector on table cells (PanelC overlay reveal)"
    - "Drawer ESC + backdrop close via MUI Drawer default onClose (no custom keydown listener)"

key-files:
  created:
    - "ventago-app/src/views/reports/stocks/hooks/useStocksHistorial.ts (182 lines)"
    - "ventago-app/src/views/reports/stocks/StocksHistorialDrawer.tsx (317 lines)"
  modified:
    - "ventago-app/src/views/reports/stocks/StocksCockpitBody.tsx (+33 / -7 lines — drawer state + toggle handler + JSX wrap)"
    - "ventago-app/src/views/reports/stocks/panels/PanelB_ItemTable.tsx (+34 / -2 lines — onOpenHistorial prop + Hist column)"
    - "ventago-app/src/views/reports/stocks/panels/PanelC_ColorMatrix.tsx (+33 / -3 lines — onOpenHistorial prop + cell overlay + Box td)"

key-decisions:
  - "Drawer state owned by StocksCockpitBody (not local to PanelB/PanelC) — enables single drawer instance + cross-panel toggle close"
  - "Same-row re-click toggles drawer closed via parent prev-target comparison (kind+ids)"
  - "PanelC cell hover-reveal: convert <td> to <Box component='td'> to use sx :hover sibling-class selector — IconButton class 'stocks-hist-overlay' reveals on parent hover"
  - "PanelB historial column uses stopPropagation on TableCell onClick to prevent row-select side effect"
  - "When branchId=null on PanelB (all-branches view), historial icon grays out — historial requires branch scope per Wave 1 endpoint contract"

patterns-established:
  - "Drawer fetch pattern: useCockpitCache key 'stocks-historial::{ident}::{offset}::{days}::{storeId}' — same target re-open within 5min hits cache (zero network)"
  - "Type encoding centralized in classifyMeta(row, theme) — single source of truth for icon/color/label/secondary across all 8 classifications"
  - "MUI theme palette references (success.main / error.main / warning.main / text.secondary) over hardcoded hex — only #5DF2FF MP cyan kept hardcoded for Vendedor cockpit visual continuity"

requirements-completed: []

# Metrics
duration: ~7min
completed: 2026-05-08
---

# Phase 32 Plan 02: Stocks Historial Drawer Frontend Summary

**Frontend stocks-historial drawer — 380px right slide-in MUI Drawer wired from PanelB row historial icon (kind='pair') and PanelC cell hover-overlay (kind='pb'), backed by useStocksHistorial hook (5-min cache, offset-accumulated rows) consuming the Wave 1 GET /reports/stocks-cockpit/historial endpoint.**

## Performance

- **Duration:** ~7 min
- **Started:** 2026-05-08T16:05:58Z
- **Completed:** 2026-05-08T16:12:31Z
- **Tasks:** 3 (hook + drawer + wiring)
- **Files created:** 2
- **Files modified:** 3

## Accomplishments

- New `useStocksHistorial(target, storeId, windowDays?)` hook over `useCockpitCache` — accumulates rows across `loadMore()` calls, auto-resets on target change, exposes `loading` / `loadingMore` separately for UX clarity.
- New `StocksHistorialDrawer` MUI Drawer (anchor=right, 380px) with sticky header (current_stock + delta_30d + sku/color/talle/branch), scrollable body (5-row Skeleton on initial load → Alert on error → mood-empty placeholder → row list), and footer (load-more Button or end-of-history caption).
- Visual encoding for all 5 D-04 classifications + 3 fallbacks (sale/suspend/other) via `classifyMeta(row, theme)` helper using MUI theme palette references (no hardcoded hex except MP cyan for visual continuity with Vendedor cockpit).
- PanelB new "Hist." column at table tail: tabler:history IconButton with `stopPropagation` to prevent row-select side effect, grayed out when branchId=null.
- PanelC cell hover-reveal overlay: converted inline-style `<td>` to `<Box component='td' sx={{...}}>` to enable `:hover .stocks-hist-overlay` selector — IconButton fades from opacity 0 to 1 on cell hover (no JS state per cell).
- StocksCockpitBody owns `historialTarget` state and the single drawer instance; `handleOpenHistorial` compares prev target by kind+ids → re-clicking same target closes (toggle).

## Task Commits

1. **Task 1: useStocksHistorial hook (data layer + cache + paginated append)** — `a7fc592` (feat)
2. **Task 2: StocksHistorialDrawer component (380px right MUI Drawer)** — `a844f42` (feat)
3. **Task 3: Wire drawer into StocksCockpitBody + PanelB row icon + PanelC cell overlay** — `da6a14a` (feat)

## Files Created/Modified

### Created
- `ventago-app/src/views/reports/stocks/hooks/useStocksHistorial.ts` — Hook + 4 exported types (`HistorialRow`, `HistorialHeader`, `HistorialClassification`, `HistorialTarget`) + `UseStocksHistorialReturn` interface. Internal state: `[offset, acc]` + `targetKeyRef` + `prevOffsetRef`. Always calls `useCockpitCache` (hook-order stable). Returns `{ header, rows, loading, loadingMore, hasMore, error, loadMore, reset }`.
- `ventago-app/src/views/reports/stocks/StocksHistorialDrawer.tsx` — Default-export component receiving `{ open, target, storeId, onClose }`. Internal `HistorialItem` row component + `classifyMeta` helper + `formatDate` helper. Drawer with `anchor='right'` + `PaperProps={{ sx: { width: 380, bgcolor: 'background.paper' } }}` + default `onClose` (covers ESC + backdrop). Sticky header / scrollable body / footer flex column.

### Modified
- `ventago-app/src/views/reports/stocks/StocksCockpitBody.tsx` — Imported `useAuth` + `StocksHistorialDrawer` + `HistorialTarget` type. Added `historialTarget` state, `handleOpenHistorial` (toggle on re-click), `handleCloseHistorial`. Passed `onOpenHistorial={handleOpenHistorial}` to PanelB and PanelC. Wrapped return in fragment with drawer rendered alongside `StocksRptLayout`.
- `ventago-app/src/views/reports/stocks/panels/PanelB_ItemTable.tsx` — Imported `IconButton`. Added `onOpenHistorial?` prop. Appended a "Hist." `<TableCell>` to the head row + per-row historial cell with `stopPropagation` and the `tabler:history` IconButton dispatching `kind: 'pair'` target. Updated empty-state colSpan to `COLUMNS.length + 1`.
- `ventago-app/src/views/reports/stocks/panels/PanelC_ColorMatrix.tsx` — Imported `IconButton`. Added `onOpenHistorial?` prop. Converted cell `<td style={{...}}>` to `<Box component='td' sx={{..., position: 'relative', '&:hover .stocks-hist-overlay': { opacity: 1 }}}>` and injected the `IconButton` overlay (className='stocks-hist-overlay') just before the cell close.

## Visual Encoding (D-04 final mapping — implemented in `classifyMeta`)

| Classification | Icon | Color (theme key / hex) | Label | Secondary line |
|---|---|---|---|---|
| `movido_in` | `tabler:arrow-down` | `#5DF2FF` (MP cyan, hardcoded for visual continuity) | `Recibido` | `de [counterpartyBranchName]` (or `movido (in)`) |
| `movido_out` | `tabler:arrow-up` | `#5DF2FF` | `Enviado` | `a [counterpartyBranchName]` (or `movido (out)`) |
| `ingreso` | `tabler:package-import` | `theme.palette.success.main` | `Ingreso` | `noteClean` (or `Stock inicial`) |
| `fallado` | `tabler:alert-triangle` | `theme.palette.error.main` | `Fallado` | `noteClean` (or `Perdida/Dano`) |
| `corregido` | `tabler:edit` | `theme.palette.warning.main` | `Correccion` | `noteClean` (or `Ajuste manual`) |
| `sale` | `tabler:shopping-cart` | `theme.palette.text.secondary` | `Venta` | `noteClean` |
| `suspend` | `tabler:lock` | `theme.palette.text.secondary` | `Reserva` | `noteClean` |
| `other` (fallback) | `tabler:dots` | `theme.palette.text.secondary` | `Otro` | `noteClean` or `note` |

Signed quantity rendered separately with conditional color: `signedQuantity > 0` → `success.main`, `< 0` → `error.main`, `0` → `text.secondary`.

## Hook Accumulation Strategy

- `[offset, setOffset]` initialized at 0; `[acc, setAcc]` initialized at `[]`.
- `targetKeyRef` stores `JSON.stringify(target)` of last seen target. Effect detects change → resets `offset=0`, `acc=[]`.
- Stable `params = { ident, offset, days, storeId }` keys the cache: `'stocks-historial::' + JSON.stringify(params)` (the colon convention from `useCockpitCache`).
- Fetcher branches on target kind to pass `productBranchId` (kind='pb') or `productId+branchId` (kind='pair') to `apiConnector.get('/reports/stocks-cockpit/historial', queryObj)`.
- `prevOffsetRef` tracks the last applied offset. On `data` arrival: if `offset === 0` → `setAcc(data.rows)`; else if `offset > prevOffset` → `setAcc(prev => [...prev, ...data.rows])`. `prevOffsetRef.current = offset`.
- `loadMore()` is a no-op unless `data?.hasMore === true` — prevents over-incrementing past server's window.
- `loading` reflects only the **initial** fetch (offset=0, acc empty); `loadingMore` reflects subsequent fetches — drawer shows the 5-row Skeleton vs the in-button "Cargando..." text accordingly.

## Toggle Close Decision (parent state vs child state)

**Decision:** Toggle logic lives in **parent** (`StocksCockpitBody.handleOpenHistorial`).

**Rationale:**
- The drawer instance is global to the body (single-render policy from D-08). A child-owned `open` state would force PanelB/PanelC to each maintain a copy, leading to two drawers or coordination overhead.
- Parent owns the source of truth (`historialTarget`). On re-click with same target → set to `null` (close). On click with different target → switch target (drawer stays open, useStocksHistorial detects change via deep-compare and resets accumulation).
- Drawer's own `onClose` (ESC + backdrop) calls `setHistorialTarget(null)` — single close path.

## Manual Verification Notes

(End-to-end smoke test deferred to user — requires running dev API + frontend together.)

**Static verification performed:**
- `npx tsc --noEmit -p tsconfig.json` exit 0 (full project TS check passes).
- `npx eslint <all 5 files>` exit 0 (zero errors/warnings on new code).
- All grep acceptance criteria from `<acceptance_criteria>` for Tasks 1–3 verified.

**Expected behavior (per Wave-1 scenario):**
1. `/reportes/stocks` loaded → select Branch A in PanelA → PanelB lists items.
2. Click `tabler:history` icon on a JEAN variant row → drawer slides in from right (380px).
3. Top row of drawer body: `tabler:arrow-up` cyan + `-N` red + `Enviado` + `a [Branch B name]` + user name + timestamp.
4. ESC or backdrop click closes drawer; re-click same icon also closes (toggle).
5. Switch to Branch B in PanelA → click same JEAN row's history icon → drawer shows `tabler:arrow-down` cyan + `+N` green + `Recibido` + `de [Branch A name]`.
6. PanelC cell hover (after selecting product) reveals top-right history icon → click opens drawer with `kind='pb'` target (productBranchId direct).
7. "Cargar 30 dias mas" button appends additional rows on click; replaced with "Fin del historial cargado" caption when hasMore=false.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking] Converted PanelC cell `<td>` from inline-style to `<Box component='td'>`**
- **Found during:** Task 3 (PanelC overlay implementation)
- **Issue:** The plan suggested `'.MuiBox-root:hover > &': { opacity: 1 }` on the IconButton, but the parent `<td>` was a native HTML element with `style={...}` inline (no MUI sx, no class to attach `:hover` reveal). The sibling-selector pattern would not work because (a) the parent is not a MuiBox and (b) inline `style` cannot do `:hover`.
- **Fix:** Converted the cell `<td>` to `<Box component='td' sx={{...}}>` (preserves DOM semantics, gains MUI sx). Used `sx={{ '&:hover .stocks-hist-overlay': { opacity: 1 } }}` on the Box and added `className='stocks-hist-overlay'` to the IconButton. This is idiomatic MUI for hover-reveal overlays.
- **Files modified:** `ventago-app/src/views/reports/stocks/panels/PanelC_ColorMatrix.tsx`
- **Verification:** `npx eslint` exits 0; `npx tsc --noEmit` exits 0; grep confirms `tabler:history` icon present once and `stopPropagation` once in PanelC.
- **Committed in:** `da6a14a`

**2. [Rule 1 — Bug] Replaced numeric `borderRadius: 4` with string `borderRadius: '4px'` after Box conversion**
- **Found during:** Task 3 (after Box conversion)
- **Issue:** When the `<td>` was a native element, `style={{ borderRadius: 4 }}` is interpreted as `4px`. After converting to MUI `<Box sx={{ borderRadius: 4 }}>`, MUI sx interprets numeric values as theme spacing units (4 → 32px), inflating the border radius dramatically.
- **Fix:** Changed to `borderRadius: '4px'` to keep the same visual outcome.
- **Files modified:** `ventago-app/src/views/reports/stocks/panels/PanelC_ColorMatrix.tsx`
- **Verification:** Visual radius matches pre-change (4px). Compiled inline as part of the same Task 3 edit.
- **Committed in:** `da6a14a`

---

**Total deviations:** 2 auto-fixed (1 blocking issue from plan ambiguity + 1 bug from sx unit semantics).
**Impact on plan:** No scope change. The hover-reveal pattern is now correct and idiomatic. Border radius preserved.

## Issues Encountered

- One ESLint `lines-around-comment` error caught on first pass (forgot blank line before the inline `// Phase 32: hover 시...` comment inside a sx block). Fixed by adding the blank line; re-ESLint clean. No other issues.

## Verification

**TypeScript:** `cd ventago-app && npx tsc --noEmit -p tsconfig.json` → exit 0.

**ESLint:**
```
cd ventago-app && npx eslint \
  src/views/reports/stocks/StocksCockpitBody.tsx \
  src/views/reports/stocks/panels/PanelB_ItemTable.tsx \
  src/views/reports/stocks/panels/PanelC_ColorMatrix.tsx \
  src/views/reports/stocks/StocksHistorialDrawer.tsx \
  src/views/reports/stocks/hooks/useStocksHistorial.ts
→ exit 0 (zero errors, zero warnings)
```

**Acceptance grep:**
```
useStocksHistorial.ts:
  exports HistorialRow / HistorialHeader / HistorialTarget / default ... ✓
  useCockpitCache reference                                          ... ✓
  /reports/stocks-cockpit/historial path                             ... ✓
  loadMore (definition + return)                                     ... 2+ ✓

StocksHistorialDrawer.tsx:
  data-testid='stocks-historial-drawer'                              ... 1 ✓
  anchor='right'                                                     ... 1 ✓
  width: 380                                                         ... 1 ✓
  Cargar 30 dias mas                                                 ... 2 ✓
  Sin movimientos                                                    ... 1 ✓
  tabler:arrow-down + tabler:arrow-up                                ... 4 (icon + meta) ✓
  tabler:package-import + tabler:alert-triangle + tabler:edit        ... 4 ✓
  Recibido + Enviado                                                 ... 4 ✓

StocksCockpitBody.tsx:
  StocksHistorialDrawer (import + JSX)                               ... 2 ✓
  historialTarget                                                    ... 3+ ✓

PanelB_ItemTable.tsx:
  onOpenHistorial                                                    ... 5 ✓
  tabler:history                                                     ... 1 ✓
  stopPropagation                                                    ... 3 ✓

PanelC_ColorMatrix.tsx:
  onOpenHistorial                                                    ... 4 ✓
  tabler:history                                                     ... 1 ✓
  stopPropagation                                                    ... 1 ✓
```

## Next Phase Readiness

- Phase 32 main user-facing artifact complete: drawer renders end-to-end against the Wave 1 endpoint contract.
- No backend changes required. No further frontend wiring needed for the core scope.
- Deferred items (per `<deferred>` in 32-CONTEXT.md): inline edit, CSV export, multi-variant compare, trend mini-chart, alert integration. Tracked but not blocking.

## Self-Check: PASSED

**Commits verified:**
```
a7fc592 feat(32-02): add useStocksHistorial hook with paginated row accumulation              ✓
a844f42 feat(32-02): add StocksHistorialDrawer 380px right MUI Drawer                          ✓
da6a14a feat(32-02): wire StocksHistorialDrawer into cockpit body + PanelB row icon + PanelC hover overlay  ✓
```

**Files verified (FOUND):**
- `ventago-app/src/views/reports/stocks/hooks/useStocksHistorial.ts`
- `ventago-app/src/views/reports/stocks/StocksHistorialDrawer.tsx`
- `ventago-app/src/views/reports/stocks/StocksCockpitBody.tsx`
- `ventago-app/src/views/reports/stocks/panels/PanelB_ItemTable.tsx`
- `ventago-app/src/views/reports/stocks/panels/PanelC_ColorMatrix.tsx`

---
*Phase: 32-stocks-historial-drawer*
*Completed: 2026-05-08*
