---
phase: 96-notas-compartidas-del-local
plan: 05
subsystem: api
tags: [nestjs, sequelize, jest, tenant-isolation, notas]

# Dependency graph
requires:
  - phase: 96-01
    provides: Notas DB schema + ver-notas/notas-enviar-todos permission seed
  - phase: 96-02
    provides: 7 Nota* Sequelize models (NOTA_MODELS)
  - phase: 96-03
    provides: notas-rules.ts — pure visibility/unread/ack/capabilities/search rule functions
provides:
  - "api-ventago/src/app/notas/notas-query.service.ts — NotasQueryService: resolveViewer, findVisibleOrFail, list, unreadSummary, detail, reads, history, markSeen, ack"
  - "api-ventago/src/app/notas/notas.types.ts — Viewer + response DTO shapes mirroring the frontend contract from 96-04"
affects: [96-06, 96-07, 96-08, 96-09]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Viewer resolved once per request (resolveViewer) via Promise.all of 4 independent lookups (Users.findByPk for userCreatedAt, Store.findByPk for timezone, NotaRecipient.findAll for recipientNotaIds/myPins, isAllowedStrict for canModerateTodos) and threaded through every method — unreadSummary accepts an optional pre-resolved Viewer so list() never resolves it twice"
    - "findVisibleOrFail is the single by-id gate: Nota.findOne with [Op.and] of {id} + buildVisibilityWhere — every by-id method (detail/reads/history/markSeen/ack) calls it first and never queries Nota.findOne any other way, so D-05 cannot be bypassed by adding a new by-id route later"
    - "Model classes declare their real column types (e.g. Nota.audience: 'all'|'users', NotaRead.seenAt: Date), so raw:true list/scan queries stay fully typed without any `any` — only the two base-Model-inherited fields (createdAt on each Nota* class) needed an explicit `as Date` cast"
    - "Read-tracking races (markSeen/ack) use findOne-then-create with a UniqueConstraintError catch that falls through to update — mirrors the box/cash_register concurrent-insert pattern from CLAUDE.md rather than assuming single-writer"

key-files:
  created:
    - api-ventago/src/app/notas/notas.types.ts
    - api-ventago/src/app/notas/notas-query.service.ts
    - api-ventago/src/app/notas/notas-query.service.spec.ts

key-decisions:
  - "unreadSummary(user, v?) takes an optional already-resolved Viewer — list() calls it internally to compute counts.mi without a second resolveViewer() round-trip (4 extra queries per list() call avoided)"
  - "reads()/detail() both call NotaRecipient.findAll for the target nota unconditionally (needed for isRecipient in notaCapabilities regardless of audience), then reads() only queries the full active-user roster when audience==='all' — avoids fetching all store users for personal notas"
  - "ack() checks in the exact order the plan specified — archivedAt, then sender, then needsAck(importance), then (only for audience='users') recipient membership — so an archived nota, a self-ack attempt, and a normal-importance ack all fail with the earliest applicable reason rather than a generic one"
  - "markSeen() never writes ackAt (that's exclusively ack()'s job) — a Normal nota's 'read' state is just the NotaRead row existing; an existing row's seenAt is never overwritten on repeat opens, only repliesSeenAt advances"

requirements-completed: [D-05, D-07, D-10, D-11, D-16, D-18, D-19]

# Metrics
duration: ~55min
completed: 2026-09-28
---

# Phase 96 Plan 05: NotasQueryService — lado de lectura Summary

**`NotasQueryService` (9 methods) implementing every Notas read path — list/search/unread/detail/reads/history/seen/ack — with D-05 visibility enforced structurally through a single `findVisibleOrFail` gate and `buildVisibilityWhere` (no role parameter, ever), proven by 20 new jest cases (97/97 in the module) plus a confirmed-and-restored mutation kill.**

## Performance

- **Duration:** ~55 min
- **Started:** 2026-09-28T13:35:00Z (approx.)
- **Completed:** 2026-09-28T14:28:02Z
- **Tasks:** 2
- **Files modified:** 3 (all new)

## Accomplishments
- `resolveViewer(user)` resolves the viewer's `userCreatedAt` from `Users.findByPk` (never the JWT — D-07 depends on the real hire date), the store's timezone from `Store.findByPk` (falling back to `DEFAULT_STORE_TZ` when null), `recipientNotaIds`/`myPins` from `NotaRecipient.findAll`, and `canModerateTodos` from `FunctionPermissionService.isAllowedStrict({ functionSlug: 'notas-enviar-todos', action: 'create' })` — all four independent lookups run via `Promise.all`.
- `findVisibleOrFail(notaId, v)` is the **only** place `Nota.findOne` is called by id anywhere in the service: `where: { [Op.and]: [{ id }, buildVisibilityWhere(v.userId, v.recipientNotaIds)] }`, throwing `NotFoundException` (never 403) when invisible or cross-store — `detail`, `reads`, `history`, `markSeen`, and `ack` all route through it, so D-05 cannot be silently skipped by a future by-id endpoint.
- `list()` builds `where = { [Op.and]: [buildVisibilityWhere, buildTabWhere, ...searchWhere?] }`, scans up to `NOTAS_SCAN_CAP` rows with minimal attributes, computes `unread`/`hasNewReplies`/effective-`pinned` per row via the pure rules from 96-03, sorts with `sortNotas` (pinned → unread → newest), slices by clamped `pageSize` (≤ 50), then loads full title/body/editedAt + sender/recipient names + reply/attachment counts only for the page's ids (never the full scan) via `Promise.all`.
- `unreadSummary(user, v?)` accepts an already-resolved `Viewer` to avoid `list()` calling `resolveViewer` twice; scans the `'todas'` tab and splits `mi` (unread, D-07/D-11 aware) from `replies` (new-replies-only) using the exact same `isUnread`/`hasNewReplies` functions `list()` uses — no duplicated logic.
- `detail()` composes `can` via `notaCapabilities`, groups reactions by `NOTA_REACTIONS` order (only non-empty emoji groups, each with `mine`/`userNames`), orders replies by `createdAt ASC` (delegated to the DB via the `order` option, asserted directly in the spec), attaches each reply's own attachment (matched by `replyId`) and reactions, and excludes reply-scoped attachments from the top-level `attachments` array.
- `reads()` throws `ForbiddenException` unless `can.seeReads` (sender, or moderator on a Todos nota — never a moderator on a personal nota, since `isRecipient` there is false and `notaCapabilities` structurally denies it); for `audience='all'` it computes the roster as active store users minus the sender (`Users.findAll({ where: { storeId, status: 'active' } })`), for `audience='users'` it uses the actual `NotaRecipient` rows — then delegates to `readsSummary` for the done/pending split.
- `markSeen()`/`ack()` write only the viewer's own `NotaRead` row (`userId` always from the resolved JWT-backed viewer, never a parameter — T-96-24); both use a `findOne` → (missing) `create` → `catch UniqueConstraintError` → fall through to `update` pattern to survive a concurrent first-open race, matching the box/cash_register concurrent-insert precedent from CLAUDE.md rather than assuming exclusivity.
- `ack()` rejects in order — archived nota, sender acking own nota, non-`needsAck` importance, then (only for `audience='users'`) non-recipient — each with a distinct `BadRequestException` message.
- 20 new jest cases across `visibility` (×4, including the detail-invisible no-query-leak case), `search`, `expiry`, `unread` (D-07 4-candidate fixture), `list sort` (pinned→unread→newest + pageSize clamp), `reads` (×3), `ack` (×5), `seen` (×3), `detail` (composition + ordering) — full `src/app/notas` suite: **97/97 passed**. `tsc --noEmit`: clean. `eslint`: 0 problems on all 3 files.
- Mutation check on `findVisibleOrFail`: replaced the `[Op.and]` visibility clause with a bare `{ id: notaId }` where — the `visibility` describe failed (`Cannot read properties of undefined (reading '0')` on the now-absent `Op.and` assertion, confirming the test actually exercises the clause) — restored byte-identical via `diff` against a pre-mutation copy before committing.

## Task Commits

Both tasks were implemented together and committed in a single commit (per the plan's explicit instruction — Task 1 has no separate commit step; the commit happens after Task 2's mutation check):

1. **Task 1: Types + NotasQueryService list/unread/visibility with harness spec** — verified via `jest -t "visibility|search|unread|expiry|list sort"` (9/9 of those named cases passed as part of the full run)
2. **Task 2: detail, reads, history, markSeen, ack + spec; commit** — verified via full `jest src/app/notas` (97/97 passed), `tsc --noEmit` clean, mutation check performed and reverted

Combined commit: **`20ab6478`** (api-ventago, feat) — `feat(96-05): NotasQueryService — lista, búsqueda, no leídas, detalle, lecturas, entendido`

**Plan metadata:** this SUMMARY.md + STATE.md/ROADMAP.md update committed as the standard executor final-commit step (root repo).

## Files Created/Modified
- `api-ventago/src/app/notas/notas.types.ts` - `Viewer` + all response DTO interfaces (NotaListItem, NotasListResponse, NotaDetail, NotaReadsResponse, NotaHistoryEntry, NotasUnread), field-for-field aligned with the frontend contract from 96-04-PLAN.md
- `api-ventago/src/app/notas/notas-query.service.ts` - the 9-method read-side service described above
- `api-ventago/src/app/notas/notas-query.service.spec.ts` - 20 jest cases using the `Test.createTestingModule` + `getModelToken` harness (no `new NotasQueryService(...)` anywhere), plus a `setupViewer`/`makeNota` fixture-builder pair

## Decisions Made
- `unreadSummary`'s optional pre-resolved `Viewer` parameter (see key-decisions above) — avoids a second `resolveViewer()` round-trip from `list()`.
- Grouped-count queries (`NotaReply.count`/`NotaAttachment.count` with `group: ['notaId']`) use Sequelize's typed `GroupedCountResultItem[]` return (index-signature `unknown` values, `Number(item.notaId)` cast) rather than casting the whole result to `any[]` — keeps `no-unsafe-*` eslint rules satisfied without a blanket `any`.
- `.create()` calls on `NotaRead` pass plain object literals with no type assertion — the `Nota*` model classes extend bare `Model` (no `Model<Attrs, CreationAttrs>` generics), so `CreationAttributes` defaults to `any` and a cast would trigger `@typescript-eslint/no-unnecessary-type-assertion` (a hard error in this repo's `recommendedTypeChecked` config).

## Deviations from Plan

None — plan executed exactly as written. All behaviors, method signatures, and acceptance-criteria greps (`buildVisibilityWhere(` ×3, no `roles`, no `new NotasQueryService`, no `sequelize.query`/`QueryTypes`, `ForbiddenException` present, `UniqueConstraintError` present) matched on the first implementation pass; no auto-fixes were needed.

## Issues Encountered
None. The only iteration needed was a single `eslint --fix` pass for prettier formatting (object literals that needed multi-line wrapping) — no logic changes.

## User Setup Required
None — no external service configuration, no new DB objects (96-01 already created the tables this plan reads/writes).

## Next Phase Readiness
- `NotasQueryService` is ready for 96-06 to wire into `notas.module.ts` (`SequelizeModule.forFeature(NOTA_MODELS)` + `Users`/`Store` + `FunctionPermissionService`) and expose via a controller — every route in the 96-04 HTTP contract (`GET /notas`, `/notas/unread`, `/notas/:id`, `/notas/:id/reads`, `/notas/:id/history`, `POST /notas/:id/seen`, `POST /notas/:id/ack`) has a corresponding service method with the exact response shape already typed in `notas.types.ts`.
- Write paths (create/edit/archive/pin/reply/reaction/attachment upload) are **not** in this plan — 96-06/96-07 build those and should follow the same `findVisibleOrFail`-first pattern established here for any by-id mutation.
- No blockers identified for 96-06/96-07/96-08/96-09.

---
*Phase: 96-notas-compartidas-del-local*
*Completed: 2026-09-28*

## Self-Check: PASSED

All 3 created files found on disk (`notas.types.ts`, `notas-query.service.ts`, `notas-query.service.spec.ts`). Commit hash `20ab6478` verified present in `git -C api-ventago log --oneline`.
