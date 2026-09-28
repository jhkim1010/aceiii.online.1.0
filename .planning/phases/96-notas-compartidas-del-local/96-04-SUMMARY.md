---
phase: 96-notas-compartidas-del-local
plan: 04
subsystem: ui
tags: [react, typescript, swr, jest, notas]

# Dependency graph
requires:
  - phase: 96-01
    provides: Notas DB tables + ver-notas/notas-enviar-todos permission seed (local 5432)
provides:
  - "ventago-app/src/views/notas/notas.types.ts — full HTTP contract types for Notas (list/detail/unread/reads/history/reactions/replies/attachments)"
  - "ventago-app/src/views/notas/notas-logic.ts — pure, React-free UI logic: toast suppression on POS, badge label/injection, tab defs, reaction emoji, ack gate state, audience label, store-timezone time formatting, SWR key builder"
  - "ventago-app/src/__tests__/notas-logic.spec.ts — 25 app-jest cases covering D-01/D-07/D-08/D-09/D-11/D-12/D-19"
  - "ventago-app/src/hooks/api/useNotas.ts — SWR hooks: useNotasList, useNotaDetail, useNotasUnread, useNotaReads, useNotaHistory, useNotasRecipients"
  - "ventago-app/src/services/notas.api.ts — mutation calls: createNota/editNota/archiveNota/pinNota/markNotaSeen/ackNota/replyNota/toggleNotaReaction/fetchNotaAttachmentBlob/revalidateNotas"
affects: [96-08, 96-09]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "pure UI logic lives in a .ts file (not .tsx) so app jest — which cannot import .tsx (jsx:preserve) — can test every screen decision before any screen exists"
    - "SWR conditional-key gating (key => null) to suppress polling for users whose structure lacks a module, following the useBranchByStore.ts / useNotices.ts precedent"
    - "manual padStart() zero-padding after Intl.DateTimeFormat.formatToParts(), because CLDR es/es-AR silently drops the leading zero on month when day+month are combined even with month:'2-digit'"

key-files:
  created:
    - ventago-app/src/views/notas/notas.types.ts
    - ventago-app/src/views/notas/notas-logic.ts
    - ventago-app/src/__tests__/notas-logic.spec.ts
    - ventago-app/src/hooks/api/useNotas.ts
    - ventago-app/src/services/notas.api.ts
  modified: []

key-decisions:
  - "withNotasBadge is a non-generic function (NotasNavItem[] -> NotasNavItem[]) rather than <T extends NotasNavItem>(items: T[]) — a generic inferred T from a plain-object test literal doesn't statically expose badgeContent/badgeColor even though NotasNavItem declares them optional; the fixed signature makes the declared return type (not caller-site inference) the source of truth"
  - "gateState() priority order: sender (can.edit) -> none; !needsAck -> none; myRead.ackAt set -> done; can.ack -> pending; else none. Placing the ackAt check before can.ack matters — once a user has confirmed, 'done' must win even if the server's can.ack capability flag hasn't been recomputed to false yet"
  - "revalidateNotas takes ScopedMutator imported directly from 'swr' (available in swr 2.4.1's public index, not just swr/_internal as the plan allowed as a fallback)"

requirements-completed: [D-01, D-07, D-08, D-09, D-11, D-12, D-19]

# Metrics
duration: ~20min
completed: 2026-09-28
---

# Phase 96 Plan 04: Notas frontend contract, pure logic, SWR hooks, mutation service Summary

**Typed HTTP contract, a React-free pure-logic module with 25 passing app-jest cases (POS toast suppression, badge label/injection, tab order, reaction set, ack-gate state machine, store-timezone formatting, SWR key builder), plus the SWR read hooks and apiConnector mutation service that will back the Notas screens built in 96-08/96-09.**

## Performance

- **Duration:** ~20 min
- **Completed:** 2026-09-28T13:27:24Z
- **Tasks:** 2
- **Files modified:** 5 (all new)

## Accomplishments
- `notas.types.ts` — the full HTTP contract (`NotaListItem`, `NotaDetail`, `NotasListResponse`, `NotaReadsResponse`, `NotaHistoryEntry`, `NotasUnread`, `StoreUserOption`, socket event payloads) copied verbatim from the plan's interface spec, so 96-05/96-06/96-07's backend and 96-08/96-09's screens share one source of truth
- `notas-logic.ts` — every UI decision Notas needs to make outside a component: `shouldShowNotaToast` (D-09, POS suppression), `formatNotasBadge`/`withNotasBadge` (D-08, sidebar badge with 99+ clamp and identity-preserving nav-tree injection), `userHasNotasModule` (T-96-18 gate for unread polling), `canSendToAll` (T-96-16 UX hint only), `NOTAS_TAB_DEFS` (D-19 exact tab order), `REACTION_EMOJI`/`REACTION_KEYS` (D-12, 5 fixed reactions), `gateState` (D-11 Entendido state machine), `audienceLabel`, `formatNotaTime` (store-timezone, not browser timezone), `isNotasKey`/`notasListKey` (deterministic SWR cache keys)
- `notas-logic.spec.ts` — 25 tests, all green, covering every behavior bullet in the plan
- `useNotas.ts` — `useNotasList` (keepPreviousData to avoid flicker on tab/page change), `useNotaDetail`, `useNotasUnread` (30s refresh, key `null` when the user's structure lacks module `notas` — no needless 403 polling), `useNotaReads`, `useNotaHistory`, `useNotasRecipients` (reuses `GET /team-chat/users`, normalizes both array and paginated-object response shapes, Team Chat code untouched per D-01)
- `notas.api.ts` — all 9 mutation calls plus `revalidateNotas(mutate)` which invalidates every Notas SWR key via `isNotasKey`; attachments are fetched only through `getBlob('/nota-adjuntos/:id')`, never a direct storage URL (T-96-17)

## Task Commits

Each task was committed atomically:

1. **Task 1: Contract types + pure logic + app jest spec** — `41675810` (feat, ventago-app)
2. **Task 2: SWR hooks + mutation service** — `5bcb33bb` (feat, ventago-app)

**Plan metadata:** this SUMMARY.md + STATE.md/ROADMAP.md update will be committed as the standard executor final-commit step (root repo).

## Files Created/Modified
- `ventago-app/src/views/notas/notas.types.ts` - full Notas HTTP contract types
- `ventago-app/src/views/notas/notas-logic.ts` - pure UI logic (no React/JSX import)
- `ventago-app/src/__tests__/notas-logic.spec.ts` - 25 app-jest cases
- `ventago-app/src/hooks/api/useNotas.ts` - SWR read hooks (list/detail/unread/reads/history/recipients)
- `ventago-app/src/services/notas.api.ts` - apiConnector mutation calls + revalidateNotas helper

## Decisions Made
- `withNotasBadge` is non-generic (see key-decisions above) — chosen after a real tsc failure surfaced the generic-inference gap; keeps the function usable by both the real nav tree (`NavLink`/`NavGroup`, which already declare `badgeContent?`/`badgeColor?`) and by tests without extra type gymnastics at call sites.
- `gateState` evaluates `myRead.ackAt` before `can.ack` so a confirmed nota always reads as `'done'`, independent of whether the backend's `can.ack` flag has been recomputed.
- `revalidateNotas` types its parameter as `ScopedMutator` imported straight from `'swr'` (confirmed exported from `swr@2.4.1`'s public index, not just `swr/_internal`) rather than the plan's fallback inline function type.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `formatNotaTime` produced `28/9` instead of `28/09` for the es-AR locale**
- **Found during:** Task 1, first jest run (RED→GREEN cycle for the `notas-logic.spec.ts` I wrote alongside the implementation)
- **Issue:** `Intl.DateTimeFormat('es-AR', { day:'2-digit', month:'2-digit', ... }).formatToParts()` returns an unpadded 1-digit month (`"9"`) when day and month are combined in the same formatter, even though `month:'2-digit'` was requested — verified this is CLDR-locale-specific (Node 26): `en-US` pads correctly, `es`/`es-AR` do not.
- **Fix:** Manually `padStart(2, '0')` every extracted part instead of trusting Intl's own padding.
- **Files modified:** `ventago-app/src/views/notas/notas-logic.ts`
- **Verification:** `notas-logic.spec.ts`'s `formatNotaTime` test passes (`28/09 10:05`); full suite re-run 25/25 green.
- **Committed in:** `41675810` (Task 1 commit)

**2. [Rule 1 - Bug] `withNotasBadge`'s generic signature failed tsc on its own test**
- **Found during:** Task 1, pre-commit hook (`app tsc` gate)
- **Issue:** `withNotasBadge<T extends NotasNavItem>(items: T[]): T[]` inferred `T` from the test's plain object literals (`{path, title}`), so the returned array's element type didn't statically expose `badgeContent`/`badgeColor` even though they're valid at runtime.
- **Fix:** Changed to a non-generic `withNotasBadge(items: NotasNavItem[], count): NotasNavItem[]` and exported `NotasNavItem` for reuse; the declared return type now carries the optional badge fields regardless of the caller's literal shape.
- **Files modified:** `ventago-app/src/views/notas/notas-logic.ts`
- **Verification:** `env -u NODE_OPTIONS npx tsc --noEmit` — 0 `notas`-related errors; jest 25/25 still green.
- **Committed in:** `41675810` (Task 1 commit)

**3. [Rule 1 - Bug] A code comment in `notas.api.ts` collided with the plan's own `grep -a "/minio"` acceptance check**
- **Found during:** Task 2, acceptance-criteria grep before commit
- **Issue:** A doc comment explaining "attachments are never built as a `/minio/...` URL" contained the literal substring `/minio`, which the plan's grep (expecting zero matches, to prove no direct storage URLs are constructed) would have flagged as a false positive — same class of self-defeating comment noted in 96-01's SUMMARY (`w4-exempt` collision).
- **Fix:** Reworded to "storage de objetos" / "MinIO" (capital, no leading slash) — same meaning, no literal `/minio` substring.
- **Files modified:** `ventago-app/src/services/notas.api.ts`
- **Verification:** `grep -a "/minio" notas.api.ts useNotas.ts` now prints nothing (exit 1); eslint/tsc re-run clean.
- **Committed in:** `5bcb33bb` (Task 2 commit)

---

**Total deviations:** 3 auto-fixed (all Rule 1 — bugs caught by the plan's own verification steps before commit)
**Impact on plan:** All three were caught and fixed within the same task, before any commit landed with the defect. No scope creep — no behavior beyond what the plan specified was added.

## Issues Encountered
None beyond the three auto-fixed items above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- The typed contract in `notas.types.ts` is ready for 96-05/96-06/96-07 (backend) to implement against and for 96-08/96-09 (screens) to consume.
- `notas-logic.ts`'s exports (`NOTAS_TAB_DEFS`, `REACTION_EMOJI`, `gateState`, `formatNotaTime`, etc.) are the tested source of truth screens should import rather than re-deriving.
- `useNotas.ts`/`notas.api.ts` are typed against the contract but will 404 until 96-05/96-06/96-07 land the backend routes — this is expected and by design (frontend-first per the plan's objective).
- No blockers identified for downstream plans in this phase.

---
*Phase: 96-notas-compartidas-del-local*
*Completed: 2026-09-28*

## Self-Check: PASSED

All 5 created source files + this SUMMARY.md found on disk. Both commit hashes
(`41675810`, `5bcb33bb`, ventago-app submodule) verified present in `git log --oneline --all`.
