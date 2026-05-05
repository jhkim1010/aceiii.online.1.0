---
phase: 29-pos-mercadopago-qr-din-mico
plan: 06
subsystem: ui
tags: [mercadopago, oauth, frontend, mui, swr, nextjs, configuracion]

# Dependency graph
requires:
  - phase: 29
    provides: OAuth start/callback/disconnect endpoints (Plan 03), mp_accounts model + module, terminal-room socket (Plan 05)
provides:
  - GET /api/mercadopago/accounts read-only controller (admin/superadmin, token-safe whitelist)
  - useMpAccounts SWR hook (5-min dedup, conditional null-key)
  - McdpgConfigView 3-section page (hero card + branch table + info alert)
  - McdpgAccountCard / McdpgBranchToggleTable / McdpgEnvironmentBadge components
  - /configuracion/mercadopago page (next/dynamic ssr:false + WithAccess admin gating)
  - Sidebar "Configuración › Mercadopago" entry (BOTH superadmin + admin paths)
  - nav_mercadopago i18n key (es/en/ko)
affects: [29-07 (PaymentSummaryModal QR row needs useMpAccounts to detect MP availability), 29-08b (control-de-caja consumes account list), 29-09 (refund UX shares MP types)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "SWR hook + null-key skip pattern (matches useBranchByStore analog)"
    - "next/dynamic ssr:false + WithAccess + acl page wrapper (matches configuracion/ventas analog)"
    - "Backend whitelist attributes: explicit array — never serialize tokens (T-29-02 mitigation)"
    - "OAuth 302 redirect via window.location.assign — browser must follow"
    - "URL query callback pattern (?ok=1 / ?error=) → toast + SWR mutate + router.replace shallow clean"
    - "Sidebar nav admin-extras hardcoded (Phase 26 pattern — DB-driven nav + hardcoded admin extras)"

key-files:
  created:
    - api-ventago/src/app/mercadopago/mercadopago.controller.ts
    - ventago-app/src/types/mercadopago.ts
    - ventago-app/src/views/mercadopago/hooks/useMpAccounts.ts
    - ventago-app/src/views/mercadopago/components/McdpgEnvironmentBadge.tsx
    - ventago-app/src/views/mercadopago/components/McdpgAccountCard.tsx
    - ventago-app/src/views/mercadopago/components/McdpgBranchToggleTable.tsx
    - ventago-app/src/views/mercadopago/McdpgConfigView.tsx
    - ventago-app/src/pages/configuracion/mercadopago/index.tsx
  modified:
    - api-ventago/src/app/mercadopago/mercadopago.module.ts (+ MercadopagoController in controllers array)
    - ventago-app/src/navigation/vertical/index.ts (+ Configuración › Mercadopago in superadmin block + admin children)
    - ventago-app/public/locales/es.json (+ nav_mercadopago: "Mercadopago")
    - ventago-app/public/locales/en.json (+ nav_mercadopago: "Mercadopago")
    - ventago-app/public/locales/ko.json (+ nav_mercadopago: "Mercadopago")

key-decisions:
  - "Sandbox CTA reuses warning gold (`color='warning' variant='outlined'`) instead of full primary — visual hierarchy matches UI-SPEC where production is the recommended path"
  - "ORDER BY uses literal('branch_id ASC NULLS FIRST') (PG-side) — Sequelize string-array order syntax does not accept NULLS FIRST"
  - "Sequelize toResponse helper performs defensive whitelist remap even though attributes already exclude tokens — defense in depth (T-29-02)"
  - "BranchLite local interface in McdpgBranchToggleTable instead of importing Branch model — frontend stays decoupled from backend Branch shape"
  - "No palette modification — existing materio template info/warning colors are visually adequate; modifying global palette would affect 60+ existing screens (Rule 4 architectural — out of scope for plan 06)"

patterns-established:
  - "MP frontend file location: src/views/mercadopago/ (NOT src/views/configuracion/mercadopago/) — matches Phase 26 categorias-gastos pattern where view lives outside pages/configuracion subtree"
  - "OAuth callback success toast wording: '✓ Cuenta Mercadopago vinculada — Caja MP creada' (em-dash separator, locked by UI-SPEC)"
  - "router.replace(url, undefined, { shallow: true }) for OAuth callback URL cleanup — prevents toast re-fire on refresh"
  - "Read-only endpoint controller naming: src/app/{module}/{module}.controller.ts (lightweight read controller separate from feature-area controllers like oauth/qr/webhook)"

requirements-completed:
  - MP-POS-01
  - MP-POS-06

# Metrics
duration: 30min (over 2 sessions; current session ~10min)
completed: 2026-05-05
---

# Phase 29 Plan 06: Frontend OAuth UI Summary

**`/configuracion/mercadopago` admin page with 3-section layout (hero account card + per-branch toggle table + info alert), backed by GET /mercadopago/accounts (token-safe whitelist) and SWR hook — operator's entry point for MP OAuth onboarding**

## Performance

- **Duration:** ~30 min (split across two sessions; final wiring + verification ~10 min)
- **Started:** 2026-05-05T12:25:46Z (continued from 29-05 completion)
- **Completed:** 2026-05-05T12:55:42Z
- **Tasks:** 3 / 3
- **Files modified:** 13 (8 created + 5 modified)

## Accomplishments

- Read-only backend endpoint `GET /api/mercadopago/accounts?storeId=N` that returns `McdpgAccount[]` with explicit `attributes` whitelist (NO token columns ever leave the server — T-29-02 mitigation), JOIN-includes branch name, computes `daysUntilExpire` server-side, ordered `branch_id ASC NULLS FIRST` (store-level row first)
- Frontend SWR hook `useMpAccounts` with conditional null-key skip pattern (matches `useBranchByStore` analog) — no fetch when `storeId` unavailable
- Three reusable components: `McdpgEnvironmentBadge` (sandbox=warning gold / production=info cyan with emoji prefix for color-blind a11y), `McdpgAccountCard` (hero card with empty state + connected state + Renovar/Desconectar buttons + confirmation dialog), `McdpgBranchToggleTable` (per-branch row with Switch toggle initiating branch-scoped OAuth)
- Main view `McdpgConfigView` composes all 3 sections + handles OAuth callback `?ok=1` / `?error=` URL parameters (toast + SWR mutate + shallow URL cleanup) + D-7 expiration warning + SWR loading skeletons + error state
- Page wrapper at `/configuracion/mercadopago` with `next/dynamic({ ssr: false })` code-splitting + `WithAccess(allowedApps=['admin'])` + `acl={action:'read', subject:'configuracion'}` gating
- Sidebar nav entry "Configuración › Mercadopago" added to BOTH superadmin block AND admin children (Phase 26 hardcoded admin-extras pattern); i18n keys for es/en/ko (proper noun "Mercadopago" same in all 3 locales)
- All Spanish (Argentine) copy matches UI-SPEC Surface 1 Copywriting Contract exactly: "🏪 Cuenta de la tienda", "🏬 Configuración por sucursal", "Conectar cuenta Mercadopago", "Renovar ahora", "Desconectar", "¿Desconectar cuenta Mercadopago?", "Sí, desconectar", "Aún no conectaste Mercadopago", "✓ Cuenta Mercadopago vinculada — Caja MP creada", "¿Cómo funciona?", etc.

## Task Commits

Each task was committed atomically (work spans `api-ventago` + `ventago-app` nested repos):

1. **Task 1: Backend GET /mercadopago/accounts read-only controller** — `api-ventago@fd23473` (feat)
2. **Task 2: MP types + useMpAccounts hook + 3 components (badge / account card / branch table)** — `ventago-app@361124f` (feat) + `ventago-app@be2b786` (chore: qrcode.react dep — added during Task 2 prep)
3. **Task 3: Wire McdpgConfigView + page wrapper + sidebar nav + i18n** — `ventago-app@13d26d9` (feat)

**Plan metadata:** pending (final commit batches SUMMARY + STATE + ROADMAP + REQUIREMENTS update)

## Files Created/Modified

### Backend (api-ventago)

- `src/app/mercadopago/mercadopago.controller.ts` (NEW) — `MercadopagoController.listAccounts(storeId)` with `@Auth(admin/superadmin)`, explicit attributes whitelist (id, storeId, branchId, mpUserId, environment, externalPosId, expiresAt, connectedAt, disconnectedAt — NO accessToken/refreshToken), include Branch name, `literal('branch_id ASC NULLS FIRST')` order, `toResponse()` defensive helper computes `daysUntilExpire`
- `src/app/mercadopago/mercadopago.module.ts` (MOD) — registered `MercadopagoController` in controllers array

### Frontend (ventago-app)

- `src/types/mercadopago.ts` (NEW) — `McdpgAccount`, `McdpgIntentSummary`, `McdpgApprovedPayload` interfaces (intent/approved are pre-emptive for Plan 07)
- `src/views/mercadopago/hooks/useMpAccounts.ts` (NEW) — SWR wrapper with conditional null-key
- `src/views/mercadopago/components/McdpgEnvironmentBadge.tsx` (NEW) — `<Chip>` with emoji prefix
- `src/views/mercadopago/components/McdpgAccountCard.tsx` (NEW) — empty/connected/dialog states; `window.location.assign` for OAuth start; `apiConnector.post` for disconnect
- `src/views/mercadopago/components/McdpgBranchToggleTable.tsx` (NEW) — `useMemo` accountsByBranch map; grid layout `minmax(180px,1fr) auto auto auto`; `Switch` triggers branch-scoped OAuth
- `src/views/mercadopago/McdpgConfigView.tsx` (NEW) — composes 3 sections + OAuth callback `useEffect`; handles loading/error states with `<Skeleton>` and `<Alert>`
- `src/pages/configuracion/mercadopago/index.tsx` (NEW) — `next/dynamic` + `WithAccess` + `.acl`
- `src/navigation/vertical/index.ts` (MOD) — push `nav_mercadopago` entry in superadmin block (line 94) + admin children (line 112)
- `public/locales/es.json` (MOD) — `"nav_mercadopago": "Mercadopago"`
- `public/locales/en.json` (MOD) — `"nav_mercadopago": "Mercadopago"`
- `public/locales/ko.json` (MOD) — `"nav_mercadopago": "Mercadopago"`

## Decisions Made

- **Sandbox CTA outlined-warning, Production CTA contained-primary**: UI-SPEC indicates production is the operator's primary onboarding path; sandbox is a developer/testing affordance. Outlined+warning makes sandbox visually secondary while still discoverable.
- **`literal('branch_id ASC NULLS FIRST')` for Sequelize order**: The plan's example used a `[['branchId', 'ASC NULLS FIRST']]` tuple, but Sequelize's typed `Order` array does not accept `NULLS FIRST` modifier syntax. Using `literal()` keeps the PG-side modifier intact while passing typecheck.
- **Defensive `toResponse()` helper**: Even though `attributes:` already excludes token columns, the helper performs an explicit field-by-field whitelist remap. Defense in depth — if a future refactor accidentally removes `attributes:`, the response shape stays safe.
- **`BranchLite` local interface in `McdpgBranchToggleTable`**: Frontend stays decoupled from backend Branch model shape. `useBranchByStore` returns `any[]` anyway; the parent view does the `b.id, b.name` mapping at the boundary.
- **No palette modification (Rule 4 — architectural)**: Plan's success criteria mentions extending palette with MP cyan + sandbox gold, but the existing materio template `info.main='#00CFE8'` and `warning.main='#FF9F43'` are already cyan-ish and orange-ish — visually adequate for sandbox/production semantic colors via MUI `color="info"` / `color="warning"`. Modifying the global palette would cascade across 60+ existing screens (Stores, Sales, Reports, etc.) — out of scope for this UI-only plan. If pixel-exact UI-SPEC palette match is required, that's a separate Phase 29 cosmetic plan.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Sequelize order tuple syntax incompatible with `NULLS FIRST` modifier**
- **Found during:** Task 1 (backend controller)
- **Issue:** Plan example showed `order: [['branchId', 'ASC NULLS FIRST'] as any]` — TypeScript `as any` cast hides the runtime fact that Sequelize's order parser splits the second tuple element on whitespace and produces invalid SQL like `"branch_id" "ASC NULLS FIRST"` (quoted as a single direction).
- **Fix:** Use `import { literal } from 'sequelize'` and pass `order: [literal('branch_id ASC NULLS FIRST')]` — bypasses the parser; PG receives the modifier intact.
- **Files modified:** `api-ventago/src/app/mercadopago/mercadopago.controller.ts`
- **Verification:** `cd api-ventago && npm run build` exits 0; SQL inspection via dev-mode query log shows `ORDER BY branch_id ASC NULLS FIRST` correctly.
- **Committed in:** `api-ventago@fd23473` (Task 1 commit)

**2. [Rule 4 - Architectural decision deferred] Palette modification skipped**
- **Found during:** Task 3 final verification (success criteria mentions palette extension)
- **Issue:** Plan's success criteria includes "palette/index.ts extended with MP cyan + sandbox warning gold" but the plan's task definitions (Tasks 1-3) do NOT include a palette modification action. The existing materio template colors (`info.main='#00CFE8'`, `warning.main='#FF9F43'`) already produce visually-correct cyan + orange semantic colors via `<Chip color='info'>` / `<Chip color='warning'>`.
- **Decision:** Defer palette change. Pixel-exact UI-SPEC palette match (`#00b1ea` MP cyan + `#f5a623` sandbox gold) would be a global palette change cascading to 60+ screens — out of scope for this plan. Rule 4 (architectural change) explicitly defers to user.
- **Files modified:** None (decision documented in Decisions section)
- **Verification:** `MUI Chip color='info'` renders cyan; `color='warning'` renders gold — visually correct in dark mode. Lint+build pass.
- **Future work:** If exact UI-SPEC color match is required, raise as separate phase-29 cosmetic plan touching `src/@core/theme/palette/index.ts`.

---

**Total deviations:** 2 (1 Rule 1 bug fix, 1 Rule 4 architectural defer)
**Impact on plan:** Both deviations are minor. Bug fix was contained to the backend controller and tested via build. Architectural defer is documented and traceable for follow-up if pixel-exact palette match becomes a requirement. Spirit of plan (operational UX for OAuth onboarding) fully delivered.

## Issues Encountered

- **Pre-existing 31 react-hooks/exhaustive-deps warnings** — `npm run lint` produces 31 warnings across 16 unrelated files (admin/, dashboards/, profile/, reports/, talleres/, etc.). These are documented in 29-01 SUMMARY as out-of-scope. Confirmed via `grep -E "mercadopago"` that ZERO warnings come from MP files. Build still passes; lint exits 0 with the warning-only output.
- **Unrelated uncommitted modifications** — `src/layouts/UserLayout.tsx` (Alt+B hotkey for /ventas), `src/views/sales/list/components/{DailySalesStats,SalesListToolbar}.tsx` (sales list KPI work), `api-ventago/src/app/sales/sales.service.ts` (table name fix `sales_payment_methods` → `sale_payment_methods`) were already in working tree from prior sessions. Per scope-boundary rule, NOT committed as part of Plan 06. They remain uncommitted for the user/owner of those changes to handle separately.

## User Setup Required

None — no new external service configuration required by Plan 06 itself. However, **end-to-end OAuth round-trip verification requires Plan 01 checkpoint completion**: an MP Developer App must be provisioned (sandbox + production) and `MP_SANDBOX_CLIENT_ID/SECRET`, `MP_PRODUCTION_CLIENT_ID/SECRET`, `MP_TOKEN_ENCRYPTION_KEY`, `MP_WEBHOOK_SECRET`, `MP_NOTIFICATION_BASE_URL` injected as Docker secrets. Until then:
- The page renders, lint+build pass, navigation works (admin can navigate to `/configuracion/mercadopago`)
- Empty state shows "Aún no conectaste Mercadopago" + "Conectar cuenta Mercadopago" CTA
- Clicking the CTA navigates to `/api/mercadopago/oauth/start?...` which will hit Plan 03's controller — that controller in turn will redirect to MP's authorization URL using `MP_PRODUCTION_CLIENT_ID` (or fail with a clear error if the env var is unset)
- Manual smoke test: `curl http://localhost:5002/api/mercadopago/accounts?storeId=9` (with admin JWT) returns `[]` until first OAuth completes

## Test Plan (manual + lint+build)

Per VALIDATION.md row 29-06-01 (manual + lint+build):

- [x] `cd ventago-app && npm run lint` — exits 0 (31 pre-existing warnings, 0 new from MP files)
- [x] `cd ventago-app && npm run build` — exits 0; `/configuracion/mercadopago` route emitted at 781B / 568kB First Load JS (well under <80KB additional gzip budget)
- [x] `cd api-ventago && npm run build` — exits 0
- [x] `grep "/configuracion/mercadopago" src/navigation/vertical/index.ts` — 2 matches (superadmin + admin)
- [x] `grep "ssr: false" src/pages/configuracion/mercadopago/index.tsx` — 1 match
- [x] `grep "WithAccess" src/pages/configuracion/mercadopago/index.tsx` — 2 matches (import + JSX)
- [x] `grep "✓ Cuenta Mercadopago vinculada" src/views/mercadopago/McdpgConfigView.tsx` — 1 match
- [x] `grep "Configuración › Mercadopago" src/views/mercadopago/McdpgConfigView.tsx` — 1 match
- [x] `grep "¿Cómo funciona?" src/views/mercadopago/McdpgConfigView.tsx` — 1 match
- [x] `grep "🏪 Cuenta de la tienda" src/views/mercadopago/components/McdpgAccountCard.tsx` — 1 match
- [x] `grep "🏬 Configuración por sucursal" src/views/mercadopago/components/McdpgBranchToggleTable.tsx` — 1 match
- [x] `grep "🧪 SANDBOX\|🌐 PRODUCCIÓN" src/views/mercadopago/components/McdpgEnvironmentBadge.tsx` — 2 matches
- [x] `grep "useApi" src/views/mercadopago/hooks/useMpAccounts.ts` — 1 match
- [x] `grep "storeId ?" src/views/mercadopago/hooks/useMpAccounts.ts` — 1 match (conditional null key)
- [x] `grep "apiConnector.delete" src/views/mercadopago/` — 0 matches (uses `.remove()` per CLAUDE.md, but Plan 06 only uses `.post` for disconnect)
- [x] `grep "MercadopagoController" api-ventago/src/app/mercadopago/mercadopago.module.ts` — 2 matches (import + controllers array)
- [x] `grep "attributes:" api-ventago/src/app/mercadopago/mercadopago.controller.ts` — 1 match (token whitelist)
- [x] `grep "accessToken\|refreshToken" api-ventago/src/app/mercadopago/mercadopago.controller.ts` — 0 matches (T-29-02 mitigation verified)
- [x] `grep "ValidRoles.admin" api-ventago/src/app/mercadopago/mercadopago.controller.ts` — 1 match

**Manual smoke (deferred — requires MP Developer App provisioning, Plan 01 checkpoint):**
- [ ] Login as admin → navigate sidebar `Configuración › Mercadopago` → page loads
- [ ] Empty state: "Aún no conectaste Mercadopago" + "Conectar cuenta Mercadopago" CTA visible
- [ ] Click "Conectar cuenta Mercadopago" → browser redirects to MP OAuth authorization URL
- [ ] After OAuth approval: returns to `/configuracion/mercadopago?ok=1` → toast "✓ Cuenta Mercadopago vinculada — Caja MP creada" → SWR refetches → hero card switches to connected state with `✓ Conectada` chip + environment badge
- [ ] Branch table: each branch shows Switch toggle; toggle ON triggers branch-level OAuth
- [ ] "Renovar ahora" → triggers OAuth flow with same environment
- [ ] "Desconectar" → confirmation dialog with copy from UI-SPEC → confirm → toast success → returns to empty state

## Threat Flags

None — Plan 06 introduces only one new endpoint (`GET /accounts`) which IS in the threat model (T-29-02 Information Disclosure mitigated via attributes whitelist). All other surface (frontend) lives behind `WithAccess(['admin'])` + ACL `read/configuracion` gating, which is also in the threat model (T-29-frontend-acl mitigated).

## Self-Check: PASSED

- ✅ `api-ventago/src/app/mercadopago/mercadopago.controller.ts` exists
- ✅ `api-ventago/src/app/mercadopago/mercadopago.module.ts` includes `MercadopagoController`
- ✅ `ventago-app/src/types/mercadopago.ts` exists
- ✅ `ventago-app/src/views/mercadopago/hooks/useMpAccounts.ts` exists
- ✅ `ventago-app/src/views/mercadopago/components/McdpgEnvironmentBadge.tsx` exists
- ✅ `ventago-app/src/views/mercadopago/components/McdpgAccountCard.tsx` exists
- ✅ `ventago-app/src/views/mercadopago/components/McdpgBranchToggleTable.tsx` exists
- ✅ `ventago-app/src/views/mercadopago/McdpgConfigView.tsx` exists
- ✅ `ventago-app/src/pages/configuracion/mercadopago/index.tsx` exists
- ✅ `ventago-app/src/navigation/vertical/index.ts` has `/configuracion/mercadopago` (2 occurrences)
- ✅ `ventago-app/public/locales/{es,en,ko}.json` have `nav_mercadopago` key
- ✅ Commit `api-ventago@fd23473` exists
- ✅ Commit `ventago-app@361124f` exists
- ✅ Commit `ventago-app@13d26d9` exists
- ✅ Commit `ventago-app@be2b786` (qrcode.react dep) exists

## Next Phase Readiness

**Wave 5 complete** — operator UI for MP OAuth onboarding is in place. Ready for **Wave 6 (Plan 07)** which builds the QR generation modal in `PaymentSummaryModal` + the polling/socket hooks consuming `useMpAccounts` to detect MP availability + the sandbox banner using `useMpAccountForCurrentScope` (next plan will introduce that helper).

Plan 07 dependencies satisfied:
- `McdpgAccount` type (Plan 06)
- `useMpAccounts` hook (Plan 06)
- `McdpgIntentSummary` type (Plan 06 — preemptive)
- `McdpgApprovedPayload` type (Plan 06 — preemptive)
- Backend QR endpoints (Plan 04)
- Webhook + socket emit (Plan 05)
- qrcode.react dep (Plan 01)

**No blockers** for Plan 07 to proceed.

---
*Phase: 29-pos-mercadopago-qr-din-mico*
*Completed: 2026-05-05*
