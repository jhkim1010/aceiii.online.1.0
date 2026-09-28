---
phase: 96-notas-compartidas-del-local
plan: 03
subsystem: backend
tags: [sequelize, jest, mutation-testing, pure-functions, tenant-isolation]

# Dependency graph
requires:
  - phase: 96-01
    provides: Notas DB schema + ver-notas/notas-enviar-todos permission seed
  - phase: 96-02
    provides: 7 Nota* Sequelize models (NOTA_MODELS) for later service wiring
provides:
  - "api-ventago/src/app/notas/notas-rules.ts — pure rule module: constants, WHERE-builders (visibility/tab/search), expiry, unread/ack/replies-badge, sort, capabilities, reads summary, form parsing, attachment validation/key-building"
  - "api-ventago/src/app/notas/notas-rules.spec.ts — 71 jest cases across 12 describes, including an in-spec evalWhere semantic evaluator over sketch fixtures and two confirmed-killed mutation checks"
affects: [96-05, 96-06, 96-07, 96-08, 96-09]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Business rules live in a dependency-free .ts module (only sequelize Op/WhereOptions + @nestjs/common BadRequestException) so services never re-implement a rule and so mutation-testing/unit-testing works without a DB"
    - "In-spec semantic WHERE evaluator (evalWhere) over literal sketch fixtures (marcos/israel/jungho/lucia/pablo) proves buildVisibilityWhere's real per-row effect, not just its shape"
    - "Mutation checks performed by copying the implementation file to the session scratchpad, mutating in place, confirming the targeted describe block fails, then restoring byte-identical (verified with diff) before committing — used because the file was not yet committed when the mutation step ran"

key-files:
  created:
    - api-ventago/src/app/notas/notas-rules.ts
    - api-ventago/src/app/notas/notas-rules.spec.ts

key-decisions:
  - "buildVisibilityWhere(userId, recipientNotaIds) has no role parameter at all — the structural D-05 guarantee. A doc comment states TenantGuard only ever adds store_id and never recipient filtering, so this WHERE is the only gate for personal-nota visibility."
  - "isExpired/buildTabWhere compare 'YYYY-MM-DD' strings lexicographically and never call the system clock; a fake-timers test (system time set to 2030) proves isExpired's answer doesn't move if 'today' isn't advanced — protects D-16 against store-timezone drift bugs."
  - "notaCapabilities implements the exact boolean algebra from the plan (edit/archive/pin/seeReads/ack/reply as functions of active/mine/todos/ctx) with a named test 'moderator gains nothing on personal nota' asserting D-05/D-10/D-14/D-15 together."
  - "parseNotaForm only reads/validates 'pinned' when audience==='all' (D-15: personal notes are never pinned by the sender); recipientIds are only parsed/required when audience==='users', and the sender's own id is always stripped from the recipient set before the empty-check."

requirements-completed: [D-04, D-05, D-06, D-07, D-10, D-11, D-12, D-14, D-15, D-16, D-17, D-18, D-19]

# Metrics
duration: ~40min
completed: 2026-09-28
---

# Phase 96 Plan 03: notas-rules.ts — pure rule module Summary

**All Notas business rules (visibility, unread/ack, expiry, sort, capabilities, form parsing, attachment validation) implemented as a single dependency-free `notas-rules.ts` module, proven with 71 jest cases and two confirmed-killed mutation checks — no DB, no I/O, so 96-05/96-06 services call these functions instead of re-implementing any rule.**

## Performance

- **Duration:** ~40 min
- **Completed:** 2026-09-28T14:10:00Z (approx.)
- **Tasks:** 2
- **Files modified:** 2 (both new)

## Accomplishments
- `notas-rules.ts` exports the exact API specified by the plan: constants (`NOTA_IMPORTANCES`, `NOTA_AUDIENCES`, `NOTA_REACTIONS` in D-12 emoji order, `NOTAS_TABS`, attachment/size/length caps), `needsAck`, `buildVisibilityWhere`, `buildTabWhere`, `buildSearchWhere`, `isExpired`, `isUnread`, `hasNewReplies`, `sortNotas`, `notaCapabilities`, `readsSummary`, `parseRecipientIds`, `parseNotaForm`, `validateAttachmentFiles`, `attachmentKind`, `buildAttachmentKey` — all pure, synchronous, no imports beyond `sequelize`'s `Op`/`WhereOptions` types and `@nestjs/common`'s `BadRequestException`.
- `buildVisibilityWhere` takes **no role parameter** — verified both structurally (signature) and semantically: an in-spec `evalWhere(where, row)` evaluator (supports `Op.or`/`Op.and`/`Op.in`/equality, ~20 lines) runs the WHERE against the sketch's own fixtures (marcos=admin, israel, jungho=admin, lucia, pablo) and confirms `jungho` — a store admin who is neither sender nor recipient — sees only the Todos nota (`#1`), never the personal ones (`#3`, `#4`). Named test: "admin who is neither sender nor recipient cannot see a personal nota".
- `isUnread` implements D-07 (Todos created before hire is unread only if pinned) and D-11 (importante/urgente require `ackAt`, not just `seenAt`) exactly per the plan's boolean formula; `isExpired` never reads the system clock (proven with `jest.useFakeTimers().setSystemTime(new Date('2030-01-01'))` still returning the pre-fake-time answer).
- `notaCapabilities` reproduces the plan's exact active/mine/todos algebra; the case "moderator gains nothing on personal nota" (canModerateTodos=true, not sender/recipient, audience='users') asserts `archive/seeReads/pin/edit` are all `false` — the single highest-risk composition point per the phase's threat register (T-96-11).
- `readsSummary`, `sortNotas`, `parseNotaForm`/`parseRecipientIds`, `validateAttachmentFiles`/`attachmentKind`/`buildAttachmentKey` all match the plan's case tables verbatim, including: dedup + sender-removal in `parseRecipientIds` (empty result throws), strict-but-real-date validation for `expiresOn` (`2026-02-30` rejected via a UTC round-trip check, not just regex), and attachment keys built only from `storeId + server uuid + MIME-derived extension` (never the user's filename — T-96-13).
- Two mutation checks performed by copying the (uncommitted) file to the session scratchpad, mutating, re-running, then restoring byte-identical (confirmed with `diff`) before the single commit:
  1. Disabled the `{ id: { [Op.in]: ids } }` clause in `buildVisibilityWhere` (guarded with `false &&`) → the `visibility` describe failed 3/11 tests (lucia/marcos/israel cases that depend on the recipient-id clause). **Killed.**
  2. Disabled the D-07 hire-date guard in `isUnread` (guarded with `false &&`) → the `unread` describe failed on "D-07: Todos not pinned created before hire, no read → false" (expected `false`, got `true`). **Killed.**
- 71/71 jest passing across the required 12 named describes (`visibility`, `tab`, `search`, `expiry`, `unread`, `ack`, `replies-badge`, `sort`, `capabilities`, `reads`, `form`, `attachment`); `tsc --noEmit` clean; `eslint` clean on both files.

## Task Commits

Both tasks were implemented together and committed in a single commit (per the plan's explicit instruction — Task 1 has no separate commit step; Task 2's action says "Commit (separate commands)" once, after the mutation checks):

1. **Task 1: Constants, where-builders, expiry, form + attachment rules** — verified via `jest -t "visibility|tab|search|expiry|form|attachment"` (44/44 passed)
2. **Task 2: unread, ack, replies-badge, sort, capabilities, reads + mutation check + commit** — verified via full `jest` run (71/71 passed), two mutation checks (both killed), `tsc --noEmit` clean

Combined commit: **`0f540673`** (api-ventago, feat) — `feat(96-03): reglas Notas puras (visibilidad, no leídas, vencimiento, permisos)`

**Plan metadata:** this SUMMARY.md + STATE.md/ROADMAP.md update committed as the standard executor final-commit step (root repo).

## RED Evidence

Per the plan's instruction, the RED state was not committed — the commit gate runs jest on the changed module directory and would block a failing commit. After writing the full spec (all 12 describes) and the real `notas-rules.ts`, RED was reproduced deliberately for the record: the real implementation file was swapped out for a stub (every exported function's body replaced with `throw new Error('not implemented')`, all types/constants kept so the spec still compiles), the full spec was run against that stub, and the real implementation was restored via `git checkout -- notas-rules.ts` immediately after (verified byte-identical with `diff` against a pre-swap backup copy). Actual tail of that run:

```
Test Suites: 1 failed, 1 total
Tests:       67 failed, 4 passed, 71 total
```

(The 4 passes were the `visibility` describe's four "throws on invalid userId" cases — the stub's `buildVisibilityWhere` also unconditionally throws, so `.toThrow()` trivially holds against any implementation, real or stub. All other 67 cases — including every `.toEqual(...)` shape assertion and every real-value assertion — failed with `Error: not implemented`, confirming the spec exercises real behavior, not tautologies, everywhere except those 4 negative-throw checks.)

## Files Created/Modified
- `api-ventago/src/app/notas/notas-rules.ts` - all pure Notas rules (see Accomplishments)
- `api-ventago/src/app/notas/notas-rules.spec.ts` - 71 tests, 12 describes, `evalWhere` semantic evaluator, sketch fixtures, two mutation-check target sites

## Decisions Made
- Kept `buildVisibilityWhere`'s full signature multi-line (see Deviations below) rather than force a single physical line, since the repo's `eslint.config.mjs` runs `eslint-plugin-prettier/recommended` as hard errors (not warnings) and the full one-line signature is 96 characters, exceeding prettier's default 80-char `printWidth`.
- `readsSummary` iterates only over `recipientUserIds` (not over the raw `reads` array), so reads belonging to a userId outside the recipient list are structurally ignored without an extra filter step.
- `parseNotaForm` reads/validates `pinned` only when `audience==='all'` and reads/requires `recipientIds` only when `audience==='users'` — D-15 (personal notes are never sender-pinned) is enforced by never looking at `pinned` on the personal-nota branch at all, not by a separate check.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Doc comment for `isExpired` contained the literal substring `new Date()`, which the plan's own acceptance grep (`grep -a "new Date()" notas-rules.ts` must print nothing) would have flagged as a false positive**
- **Found during:** Task 2 final acceptance-criteria check
- **Issue:** The comment explaining D-16 ("nunca lee el reloj (nunca `new Date()`)") literally contained the four-character-plus-parens substring the grep checks for, even though the code itself never calls `new Date()` in `isExpired`/`buildTabWhere`.
- **Fix:** Reworded the comment to "nunca instancia la fecha actual del sistema" — same meaning, no longer matches the grep pattern.
- **Files modified:** `api-ventago/src/app/notas/notas-rules.ts`
- **Verification:** `grep -a "new Date()" api-ventago/src/app/notas/notas-rules.ts` now prints nothing; jest 71/71 still green.
- **Committed in:** `0f540673`

### Noted but not auto-fixed (acceptance-criterion conflict, not a code defect)

**`buildVisibilityWhere`'s exact single-line signature (acceptance criterion in the plan) is unsatisfiable together with the repo's hard-error prettier gate.** The full signature `export function buildVisibilityWhere(userId: number, recipientNotaIds: number[]): WhereOptions {` is 96 characters — 16 over prettier's default 80-char `printWidth`. `eslint.config.mjs` runs `eslint-plugin-prettier/recommended`, which reports this as an `error` (not a warning), and the repo's commit gate runs eslint on added lines. Manually forcing the signature onto one line and running `npx eslint --fix` reliably reformats it back to the plan's three-line style (`userId: number,` / `recipientNotaIds: number[],` / `): WhereOptions {`), which is what is committed. The semantic requirement this criterion exists to verify — **no role parameter, ever** — is fully met and is the subject of five dedicated tests (deep-equal shape tests, four invalid-userId throw tests, and five `evalWhere` semantic tests including the named admin test), so the underlying D-05 guarantee is proven even though the literal one-line grep pattern the plan specifies cannot pass without breaking the commit gate. Did not attempt to relax the gate (out of scope, and CLAUDE.md treats the commit gate as authoritative) or rename parameters (would break the plan's exact API contract).
- **Files affected:** `api-ventago/src/app/notas/notas-rules.ts` (lines 66-69, `buildVisibilityWhere` signature)

---

**Total deviations:** 1 auto-fixed (Rule 1 — comment text collided with an acceptance grep) + 1 noted acceptance-criterion conflict (prettier hard-error gate vs. a literal one-line-signature grep; semantics fully tested via other means)
**Impact on plan:** No scope creep, no behavior change, no test coverage gap. The one unsatisfiable literal-grep criterion does not correspond to any untested behavior — D-05's "no role parameter" guarantee has five direct tests plus the semantic `evalWhere` fixture suite.

## Issues Encountered
None beyond the two items documented above.

## User Setup Required
None — pure TypeScript module, no external services, no DB/migration changes (96-01 already created the tables; this plan is read-only rule logic on top of that).

## Next Phase Readiness
- `notas-rules.ts` is import-ready for 96-05 (`notas.service.ts`) and 96-06 (controller/routes) — every visibility/unread/ack/capability/attachment decision those plans need is already implemented and unit-tested here; they should call these functions rather than re-deriving any of the D-04..D-19 logic.
- `buildVisibilityWhere`/`buildTabWhere`/`buildSearchWhere` return `sequelize.WhereOptions` ready to be combined (e.g. `{ [Op.and]: [visibilityWhere, tabWhere, searchWhere] }`) directly in a `Nota.findAll({ where: ... })` call in 96-05.
- `buildAttachmentKey`/`attachmentKind`/`validateAttachmentFiles` are ready for 96-07's MinIO upload endpoint; the key format (`notas/{storeId}/{n|r}/{uuid}{ext}`) already matches the prefix `isPubliclyServable` (96-02) structurally rejects, so 96-07 does not need to invent a new privacy convention.
- No blockers identified for 96-05/96-06/96-07/96-08/96-09.

---
*Phase: 96-notas-compartidas-del-local*
*Completed: 2026-09-28*

## Self-Check: PASSED

Both created files found on disk (`api-ventago/src/app/notas/notas-rules.ts`, `api-ventago/src/app/notas/notas-rules.spec.ts`) plus this SUMMARY.md. Commit hash `0f54067` verified present in `git -C api-ventago log --oneline --all`.
