---
phase: 96-notas-compartidas-del-local
plan: 08
subsystem: ui
tags: [react, mui, next-dynamic, swr, notas]

# Dependency graph
requires:
  - phase: 96-04
    provides: "notas.types.ts (HTTP contract), notas-logic.ts (pure UI logic), useNotas.ts (SWR hooks), notas.api.ts (mutations)"
provides:
  - "ventago-app/src/pages/notas/index.tsx — route /notas (next/dynamic ssr:false, WithAccess allowedModules=['notas'])"
  - "ventago-app/src/views/notas/NotasView.tsx — tabs + debounced search + 340px/1fr split layout + pagination + ?nota= deep-link selection"
  - "ventago-app/src/views/notas/NotaInboxList.tsx — memoized inbox row (importance border, unread dot, pin/audience/time/excerpt)"
  - "ventago-app/src/views/notas/NotaDetailPane.tsx — Entendido gate, 5 fixed reactions (nota + per-reply), reads accordion, one-level reply thread, pin/edit/archive actions"
  - "ventago-app/src/views/notas/NotaAttachmentView.tsx — authenticated blob → object URL rendering (image thumb + dialog, PDF chip), revoked on unmount"
  - "ventago-app/src/views/notas/ComposeNotaDialog.tsx — create/edit dialog: Todos vs personas, título/mensaje/importancia/vencimiento, adjuntos ≤5, fijar"
affects: [96-09, 96-10]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Detail pane's markNotaSeen fires once per selection via a useRef guard keyed on notaId — not a dependency-array trick, so it survives mutate()/onChanged() identity changes between renders"
    - "Reactions rendered by a shared ReactionsRow subcomponent parameterized by an optional replyId, reused identically for the nota body and every reply (D-12/D-13)"
    - "Blob attachments use useEffect (not SWR) — a per-binary fetch, not reference data — with an alive-flag + URL.revokeObjectURL cleanup to avoid leaking object URLs across selection changes"

key-files:
  created:
    - ventago-app/src/pages/notas/index.tsx
    - ventago-app/src/views/notas/NotasView.tsx
    - ventago-app/src/views/notas/NotaInboxList.tsx
    - ventago-app/src/views/notas/NotaDetailPane.tsx
    - ventago-app/src/views/notas/NotaAttachmentView.tsx
    - ventago-app/src/views/notas/ComposeNotaDialog.tsx
  modified: []

key-decisions:
  - "Single commit for all 3 tasks (page+list, detail+attachments, compose+wiring) — the plan explicitly deferred the commit to the end of Task 3 ('commit happens at the end of Task 3'), overriding the default one-commit-per-task protocol for this tightly-coupled screen"
  - "Header (title/search/＋ Nueva nota) and Tabs live above the split grid at the NotasView page level (not inside the left Card) — matches the sketch's `.head` → `.tabs` → `.content` (`.split`) structure rather than nesting them in the inbox Card"
  - "ComposeNotaDialog disables the audience ToggleButtonGroup and recipient chips entirely in edit mode (audience is immutable after creation per D-14 — only title/body/importance/expiresOn are editable)"

requirements-completed: [D-02, D-03, D-04, D-05, D-06, D-10, D-11, D-12, D-13, D-14, D-15, D-16, D-17, D-18, D-19]

# Metrics
duration: ~20min
completed: 2026-09-28
---

# Phase 96 Plan 08: Notas screen — bandeja, detalle, redactar Summary

**MUI 5 two-column «Bandeja» screen (layout B) — tabbed/searchable inbox, detail pane with the Entendido confirmation gate, 5 fixed reactions on notas and replies, a capability-gated reads accordion, one-level reply thread, and a create/edit compose dialog, all wired against the 96-04 frontend contract.**

## Performance

- **Duration:** ~20 min
- **Completed:** 2026-09-28T13:46:21Z
- **Tasks:** 3
- **Files modified:** 6 (all new)

## Accomplishments
- `pages/notas/index.tsx` — route registered via the repo's standard `next/dynamic(..., { ssr: false })` + `WithAccess allowedModules={['notas']}` pattern (copied from `gastos/index.tsx`)
- `NotasView.tsx` — tabs (`NOTAS_TAB_DEFS`, «Para mí» shows a red count chip), 300ms-debounced search, `useMediaQuery('md')`-gated auto-select-first-on-desktop, `?nota=` query param deep-link selection (for the 96-09 toast), MUI `Pagination` when `total > 50`
- `NotaInboxList.tsx` — `React.memo`-wrapped row: importance-colored left border (gold/error), 7px unread dot, sender→audience/time/title/excerpt exactly per the sketch's `.ib` markup; 6-row `Skeleton` while loading, 📭 empty states
- `NotaDetailPane.tsx` — capability-gated pin/edit/archive buttons (`n.can.*`), `markNotaSeen` fired exactly once per selection via a `useRef` guard, Entendido gate (`gateState()` from 96-04, warning/error/success `Alert`), edit-history `Collapse`, 5-reaction `ReactionsRow` shared between the nota body and every reply, reads `Accordion` gated by `can.seeReads`, one-level reply thread with Enter-to-send + photo attach (client-side 8MB check)
- `NotaAttachmentView.tsx` — `fetchNotaAttachmentBlob` → `URL.createObjectURL`, revoked on unmount/id-change; image thumb opens a `Dialog` with the full image, PDF renders as a `Chip` that opens the blob URL in a new tab
- `ComposeNotaDialog.tsx` — Todos/personas `ToggleButtonGroup` (Todos disabled + lock hint when `!canSendToAll`), recipient chips from `useNotasRecipients` excluding self, exact D-05 privacy hint text, título/mensaje/importancia/vencimiento fields, ≤5 attachment picker with client-side type/size/count validation (hidden in edit mode), «📌 Fijar» checkbox only for Todos, edit mode pre-fills from `useNotaDetail` and locks audience

## Task Commits

Single commit per plan instructions (Task 3 explicitly deferred committing all 3 tasks' files together):

1. **Tasks 1–3: Page route, NotasView/NotaInboxList, NotaDetailPane/NotaAttachmentView, ComposeNotaDialog wiring** — `df838e26` (feat, ventago-app)

**Plan metadata:** this SUMMARY.md + STATE.md/ROADMAP.md update will be committed as the standard executor final-commit step (root repo).

## Files Created/Modified
- `ventago-app/src/pages/notas/index.tsx` - route `/notas`
- `ventago-app/src/views/notas/NotasView.tsx` - tabs + search + split layout + selection/compose state
- `ventago-app/src/views/notas/NotaInboxList.tsx` - memoized inbox row
- `ventago-app/src/views/notas/NotaDetailPane.tsx` - detail body, gate, reactions, reads, thread, actions
- `ventago-app/src/views/notas/NotaAttachmentView.tsx` - authenticated attachment blob rendering
- `ventago-app/src/views/notas/ComposeNotaDialog.tsx` - create/edit dialog

## Decisions Made
- Single commit spanning all 3 tasks, per the plan's own explicit instruction (see key-decisions above).
- Header/search/compose-button and Tabs sit above the split grid at the page level, matching the sketch's DOM order rather than nesting inside the inbox `Card`.
- Edit mode locks audience/recipients (read-only) since D-14 only allows editing title/body/importance/expiresOn.

## Deviations from Plan
None - plan executed exactly as written. The frontend contract, hooks, and mutation service from 96-04 covered every endpoint this screen needed (`/notas`, `/notas/todos`, `/notas/:id`, `/notas/:id/{archive,pin,seen,ack,reactions,replies,reads,history}`, `/nota-adjuntos/:id`) with no gaps.

## Issues Encountered
None. `env -u NODE_OPTIONS npx tsc --noEmit` and `npx eslint src/pages/notas src/views/notas --max-warnings=0` were both clean on the first pass; no auto-fix cycles were needed.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- The screen is complete and will 404 on every mutation/read until 96-05/96-06/96-07 (backend) land — this is expected per the frontend-first sequencing noted in 96-04's SUMMARY; no blocker for 96-08 itself.
- 96-09 (toast + sidebar badge) can rely on `NotasView`'s `router.query.nota` handling to open a specific nota on toast click — already wired in this plan.
- 96-10 (end-to-end wiring/verification) has all 6 screen files to exercise once the backend plans land.
- No blockers identified for downstream plans in this phase.

---
*Phase: 96-notas-compartidas-del-local*
*Completed: 2026-09-28*

## Self-Check: PASSED

All 6 created files found on disk. Commit `df838e26` verified present in `ventago-app`'s `git log --oneline --all`.
