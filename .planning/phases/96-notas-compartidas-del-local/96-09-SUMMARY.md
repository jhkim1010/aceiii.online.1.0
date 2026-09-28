---
phase: 96-notas-compartidas-del-local
plan: 09
subsystem: ui
tags: [react, mui, swr, socket.io, sidebar, notas]

# Dependency graph
requires:
  - phase: 96-04
    provides: "notas-logic.ts pure logic (formatNotasBadge, shouldShowNotaToast, userHasNotasModule), useNotas.ts SWR hooks, notas.api.ts (revalidateNotas)"
  - phase: 96-08
    provides: "/notas screen (NotasView) with ?nota= deep-link selection, consumed by the toast's click target"
provides:
  - "ventago-app/src/navigation/vertical/index.ts — useNavigation(notasUnread) is the first live producer of sidebar badgeContent (D-08/D-20)"
  - "ventago-app/src/layouts/UserLayout.tsx — wires useNotasUnread() into the nav badge and mounts NotaToast globally"
  - "ventago-app/src/components/notas/NotaToast.tsx — always-mounted realtime listener (nota:new/reply/reaction/changed) + route-aware toast, suppressed on /nueva-venta (D-09)"
affects: [96-10]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "First live badgeContent producer in the repo — threaded as an explicit useNavigation(count) argument (not read off `user`) so the memoized nav tree only gets a new reference when the count itself changes"
    - "Always-mounted global listener component (NotaToast, mirrors NoticesBanner) reads the current route through a ref updated in an effect, because useRealtime's handlers are captured once in a ref and would otherwise see the pathname from mount time"

key-files:
  created:
    - ventago-app/src/components/notas/NotaToast.tsx
  modified:
    - ventago-app/src/navigation/vertical/index.ts
    - ventago-app/src/layouts/UserLayout.tsx

key-decisions:
  - "enabled: Boolean(user?.id && hasNotas) on NotaToast's useRealtime call — deliberately NOT gated on a panel-open flag like TeamChatPanel, because D-08 requires the badge/toast to work from any screen, not just while a Notas panel is open"
  - "revalidateNotas(mutate) (96-04's existing helper, ScopedMutator from useSWRConfig) is reused as-is for all four socket events instead of writing a new invalidation path — one call refreshes /notas/unread (the badge, including on POS) plus any open list/detail"

requirements-completed: [D-01, D-08, D-09, D-13, D-20]

# Metrics
duration: ~10min
completed: 2026-09-28
---

# Phase 96 Plan 09: Sidebar badge + global realtime toast (Notas) Summary

**First live `badgeContent` producer in the sidebar wired to `GET /notas/unread`, plus an always-mounted `/realtime` listener that refreshes Notas' SWR caches from any screen and shows a clickable toast — suppressed on `/nueva-venta` so POS keeps its focus and shortcuts (D-09).**

## Performance

- **Duration:** ~10 min
- **Completed:** 2026-09-28T14:11:53Z
- **Tasks:** 2
- **Files modified:** 3 (1 created, 2 modified)

## Accomplishments
- `useNavigation()` now takes an explicit `notasUnread` argument and injects `badgeContent`/`badgeColor: 'error'` on the auxiliary «Notas» item (`mod.url === '/notas'`) via `formatNotasBadge` from 96-04's pure logic — the render side (`VerticalNavLink.tsx:182`) already existed with zero producers until now.
- Added `notasUnread` as an explicit dependency of the `useNavigation` `useMemo` (not read off `user`), so the nav tree only gets a new array reference when the unread count actually changes — matches CLAUDE.md's sidebar re-render guard and threat T-96-43's accepted bounded cost.
- `UserLayout.tsx` calls `useNotasUnread()` (96-04's SWR hook, key `null` for users without the `notas` module — no needless polling) and threads `notasUnread?.total ?? 0` into `VerticalNavItems(...)`.
- `NotaToast.tsx` — new always-mounted component (`dynamic(..., { ssr: false })`, mounted next to `NoticesBanner`) subscribing to the shared `/realtime` socket via `useRealtime` for `nota:new`, `nota:reply`, `nota:reaction`, `nota:changed`. Every event calls `revalidateNotas(mutate)` (refreshes the badge everywhere, including POS); `nota:new`/`nota:reply` additionally show a clickable `Snackbar`/`Paper` toast (gold/error left border for urgent) unless the sender is the current user or `shouldShowNotaToast(pathname)` returns false (POS). Clicking navigates to `/notas?nota=<id>`, which 96-08's `NotasView` already handles as a deep-link selector.
- Socket import guard respected: `NotaToast.tsx` never imports `socket.io-client` directly, only `src/realtime`'s `useRealtime`.

## Task Commits

Each task was committed atomically:

1. **Task 1: Sidebar badge producer (navigation + UserLayout)** - `66c154c3` (feat, ventago-app)
2. **Task 2: NotaToast global listener with POS suppression; mount** - `743d409f` (feat, ventago-app)

**Plan metadata:** this SUMMARY.md + STATE.md/ROADMAP.md update committed as the standard executor final-commit step (root repo).

## Files Created/Modified
- `ventago-app/src/navigation/vertical/index.ts` - `useNavigation(notasUnread)` injects `badgeContent` on the `/notas` aux item; `notasUnread` added to the `useMemo` deps
- `ventago-app/src/layouts/UserLayout.tsx` - `useNotasUnread()` wired into `VerticalNavItems(...)`; `NotaToast` dynamic import mounted globally
- `ventago-app/src/components/notas/NotaToast.tsx` - global realtime listener + POS-suppressed toast

## Decisions Made
- `NotaToast`'s `useRealtime` `enabled` flag is `Boolean(user?.id && hasNotas)` only — deliberately diverging from `TeamChatPanel`'s `open`-gated pattern (noted explicitly as required in both the plan and 96-PATTERNS.md), since D-08 requires the listener active on every screen, not just while a panel is open.
- Reused 96-04's `revalidateNotas(mutate)` helper for every socket event rather than writing new mutate-by-key logic — keeps a single source of truth for "what counts as a Notas SWR key" (`isNotasKey`).
- Current route is read through a `pathnameRef` updated in a `useEffect`, since `useRealtime` freezes handlers in a ref at effect-setup time; without this, a user navigating to `/nueva-venta` mid-session would still see a toast (POS suppression would only apply to the route active when the listener last resubscribed).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] ESLint `lines-around-comment` failures in `navigation/vertical/index.ts`**
- **Found during:** Task 1, first `eslint --max-warnings=0` run
- **Issue:** Two new comments (D-20 rationale above the aux-module map, and the `notasUnread` dependency-array rationale above the `useMemo` deps line) were placed without a blank line before them, which this repo's ESLint config treats as an error (per CLAUDE.md's `lines-around-comment` rule).
- **Fix:** Added a blank line before each comment.
- **Files modified:** `ventago-app/src/navigation/vertical/index.ts`
- **Verification:** `npx eslint src/navigation/vertical/index.ts src/layouts/UserLayout.tsx --max-warnings=0` → `LINT_OK`
- **Committed in:** `66c154c3` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 — lint error caught by the plan's own verification step before commit)
**Impact on plan:** Cosmetic only (blank-line placement); no behavior change. No scope creep.

## Issues Encountered
None beyond the lint fix above. `env -u NODE_OPTIONS npx tsc --noEmit` was clean on the whole project after both tasks; both the sidebar-module-contract and notas-logic jest suites stayed green throughout.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- The sidebar badge and global toast are both wired against the 96-04 contract and the 96-08 screen's `?nota=` deep link; they will start reflecting real unread counts once the 96-05/96-06/96-07 backend routes (`GET /notas/unread`, the `nota:*` socket emits) are live in this environment.
- 96-10 (end-to-end wiring/verification) can now exercise the full loop: backend emits `nota:new`/`nota:reply` → `NotaToast` refreshes the badge and (off-POS) shows the toast → click opens `/notas?nota=<id>` in 96-08's `NotasView`.
- No blockers identified for downstream plans in this phase.

---
*Phase: 96-notas-compartidas-del-local*
*Completed: 2026-09-28*

## Self-Check: PASSED

Created file `ventago-app/src/components/notas/NotaToast.tsx` and this SUMMARY.md
both found on disk. Both commit hashes (`66c154c3`, `743d409f`, `ventago-app` submodule)
verified present in `git log --oneline --all`.
