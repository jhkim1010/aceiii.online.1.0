---
phase: 96-notas-compartidas-del-local
plan: 06
subsystem: api
tags: [nestjs, sequelize, jest, transactions, minio, socket-io, notas]

# Dependency graph
requires:
  - phase: 96-01
    provides: Notas DB schema + ver-notas/notas-enviar-todos permission seed
  - phase: 96-02
    provides: 7 Nota* Sequelize models (NOTA_MODELS)
  - phase: 96-03
    provides: notas-rules.ts — pure visibility/unread/ack/capabilities/attachment rule functions
  - phase: 96-05
    provides: NotasQueryService — resolveViewer, findVisibleOrFail, detail (write-side reuses both)
provides:
  - "api-ventago/src/app/notas/notas-command.service.ts — NotasCommandService: createPersonal, createTodos, edit, archive, pin, reply, react, openAttachment"
affects: [96-07, 96-08, 96-09, 96-10]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "uploadAll()/compensate(): MinIO uploads always happen BEFORE sequelize.transaction() opens; any tx failure removes every already-uploaded key via Promise.allSettled — no I/O inside the transaction, no orphaned objects on rollback (Phase 64 write rule)"
    - "emitForAudience() wraps every socket emit in try/catch + Logger.warn and is only ever called after tx.commit() — a post-commit failure (socket, MinIO) never changes the response ('커밋 후 = 성공')"
    - "Every by-id mutation (edit/archive/pin/reply/react/openAttachment) calls NotasQueryService.findVisibleOrFail FIRST — the command service never queries Nota by id any other way, so D-05 visibility cannot be bypassed by a future write path"
    - "openAttachment checks visibility strictly before calling minio.getObjectStream — proven, not just asserted, by a mutation check (swap order → test fails) performed and reverted before the commit"

key-files:
  created:
    - api-ventago/src/app/notas/notas-command.service.ts
    - api-ventago/src/app/notas/notas-command.service.spec.ts

key-decisions:
  - "createTodos re-checks isAllowedStrict(user, { functionSlug: 'notas-enviar-todos', action: 'create' }) inside the service itself (D-03 defense in depth) — even though the HTTP route guard (96-07) will also enforce it, a ForbiddenException here fires before any transaction opens or any file uploads"
  - "edit() calls parseNotaForm with audience:'all' regardless of the nota's real audience — this is solely to reuse the title/body/importance/expiresOn validation without requiring recipientIds; edit never touches audience or recipients (D-14 scope)"
  - "Reply body length cap is a local NOTA_REPLY_BODY_MAX=5000 constant, distinct from notas-rules.ts's NOTA_BODY_MAX=10000 (top-level nota body) — the plan specified 5000 for replies explicitly, so it is not reused from notas-rules.ts"
  - "pin() only emits 'nota:changed' for audience='all' (Todos) — a personal-nota pin only updates the viewer's own nota_recipients row and never touches anyone else's view, so no emit exists on that branch (D-15)"

requirements-completed: [D-01, D-03, D-04, D-05, D-06, D-08, D-12, D-13, D-14, D-15, D-17]

# Metrics
duration: ~65min
completed: 2026-09-28
---

# Phase 96 Plan 06: NotasCommandService — lado de escritura Summary

**`NotasCommandService` (8 methods) implementing every Notas write path — create (personal/Todos with attachments), edit with history, soft archive, pin, reply with photo, reaction toggle, and a visibility-first attachment opener — all inside single transactions with MinIO uploads before the tx and socket emits only after commit, proven by 38 jest cases plus a confirmed-and-reverted mutation kill on `openAttachment`.**

## Performance

- **Duration:** ~65 min
- **Completed:** 2026-09-28
- **Tasks:** 2
- **Files modified:** 2 (both new)

## Accomplishments
- `create()` (shared by `createPersonal`/`createTodos`) runs `parseNotaForm` + `validateAttachmentFiles` first, validates recipient ids against `Users.findAll({ id, storeId, status: 'active' })` for personal notas, uploads all attachments to MinIO with `uploadAll()` (keys via `buildAttachmentKey(storeId, mimetype, randomUUID(), 'n')`), then in a **single transaction** creates the `Nota` row, `NotaRecipient.bulkCreate` (personal only), `NotaAttachment.bulkCreate` (if any files), and the sender's own `NotaRead` row with `seenAt=ackAt=repliesSeenAt=now` — commits, then emits `nota:new` (`emitToStore` for Todos, `emitToUser` per sender+recipient for personal) only after `tx.commit()` succeeds.
- `createTodos` throws `ForbiddenException` from `isAllowedStrict(user, { functionSlug: 'notas-enviar-todos', action: 'create' })` **before** any transaction opens or file uploads happen — verified by a dedicated test asserting `sequelize.transaction` and `minio.uploadFile` were never called.
- On any failure inside the create transaction (e.g. `NotaAttachment.bulkCreate` rejecting), the transaction is rolled back and every already-uploaded MinIO key is removed via `compensate()` (`Promise.allSettled`) before the original error is rethrown — verified with a test that injects a bulkCreate rejection and asserts both `tx.rollback` and `minio.removeFile` (×2) were called.
- `edit()` requires the caller to be the nota's sender (`ForbiddenException` otherwise), rejects archived notas, and — in one transaction — creates a `NotaEditHistory` snapshot of the previous title/body/importance/expiresOn **before** calling `nota.update(...)` (verified via `invocationCallOrder`), then emits `nota:changed` after commit.
- `archive()` and `pin()` both compute `notaCapabilities` (from 96-03) via a shared `capsFor()` helper after `findVisibleOrFail` — a moderator gains `archive`/`pin` power only on Todos notas, never on personal notas (which the moderator typically can't even see, since `findVisibleOrFail` 404s first). Personal-nota pin writes only the viewer's own `NotaRecipient.pinned` and emits nothing (D-15); Todos pin writes `nota.pinned` and emits `nota:changed`.
- `reply()` validates in order (archived → `validateAttachmentFiles(max=1, imagesOnly=true)` → empty-body-and-no-photo → length>5000), uploads the optional photo before the transaction, then in one transaction creates the `NotaReply`, the optional `NotaAttachment` (linked via `replyId`), `Nota.update({ lastReplyAt, lastReplyBy })`, and upserts the replier's own `NotaRead.repliesSeenAt` — commits, then emits `nota:reply` with `{ notaId, notaTitle, replyId, userId, userName }`. The method signature (`user, id, body, photos`) has no parent/reply-to parameter anywhere (D-13), confirmed by `grep -ai "parentReply|replyTo"` printing nothing.
- `react()` validates the emoji against the fixed `NOTA_REACTIONS` set, validates an optional `replyId` belongs to the same nota (`NotFoundException` otherwise), and toggles: first call creates a `NotaReaction`, an identical second call `destroy()`s it — a `UniqueConstraintError` race on create is treated as `active: true` rather than propagated. Emits `nota:reaction { notaId, replyId }` after the write.
- `openAttachment()` — the single highest-risk method (T-96-27) — looks up the attachment by id, then calls `NotasQueryService.findVisibleOrFail(att.notaId, viewer)` **before** touching `minio.getObjectStream`. A deliberate mutation (swapping the two calls) was applied, confirmed to fail the "adjunto de nota invisible" test (which asserts `minio.getObjectStream` was never called), and then reverted byte-identical via the original file (`diff` confirmed) before the commit.
- 38 jest cases across the 9 required describes (`permission`, `create`, `attachment` ×2, `edit`, `archive`, `pin`, `reply`, `reaction`) plus the pre-existing 97 in `src/app/notas` → **135/135 passing**. `tsc --noEmit`: clean. `eslint`: 0 problems on both new files.

## Task Commits

Both tasks were implemented together and committed in a single commit (per the plan's explicit instruction — the commit happens after Task 2's mutation check):

1. **Task 1: create (personal + Todos) with attachments, edit, archive, pin** — verified via `jest -t "permission|create|attachment|edit|archive|pin"` (23/23 of those cases passed as part of the full run)
2. **Task 2: reply, react, openAttachment + mutation check; commit** — verified via full `jest src/app/notas` (135/135 passed), `tsc --noEmit` clean, mutation check on `openAttachment` performed and reverted

Combined commit: **`f12c0ec7`** (api-ventago, feat) — `feat(96-06): NotasCommandService — crear, editar, archivar, fijar, responder, reaccionar, adjuntos`

**Plan metadata:** this SUMMARY.md + STATE.md/ROADMAP.md update committed as the standard executor final-commit step (root repo, not pushed).

## Files Created/Modified
- `api-ventago/src/app/notas/notas-command.service.ts` - the 8-method write-side service described above (create/createPersonal/createTodos, edit, archive, pin, reply, react, openAttachment) plus private helpers (`uploadAll`, `compensate`, `emitForAudience`, `recipientIdsOf`, `toFacts`, `capsFor`, `formatUserName`)
- `api-ventago/src/app/notas/notas-command.service.spec.ts` - 38 jest cases using the `Test.createTestingModule` + `getModelToken`/`getConnectionToken` harness (no `new NotasCommandService(...)` anywhere), with `NotasQueryService`/`WebsocketService`/`MinioService`/`FunctionPermissionService` all provided as plain mock objects

## Decisions Made
- See `key-decisions` in frontmatter (createTodos defense-in-depth ordering, edit's audience:'all' reuse of parseNotaForm, the local 5000-char reply cap distinct from the 10000-char nota body cap, and pin's emit-only-for-Todos rule).
- `openAttachment`'s `findVisibleOrFail` call uses the attachment's `notaId` (not the attachment id) — the only identifier that visibility rules understand — after confirming the attachment itself exists via `findByPk`.

## Deviations from Plan

None — plan executed exactly as written. All behaviors, method signatures, and acceptance-criteria greps (`isAllowedStrict` present, `transaction: tx` ≥6, no `roles`, no `team-chat`, no `parentReply`/`replyTo`, 4 distinct `nota:*` event names) matched on the first implementation pass. Two minor eslint/tsc frictions were resolved during verification, not scope changes:
- Initial `makeFile()` test helper typed as `any` passed eslint's `--fix` pass but then failed `tsc --noEmit` when tightened to a `FakeFile` interface (missing Multer.File properties) — resolved by having `makeFile()` return a real `FakeFile` object internally and cast it to `Express.Multer.File` at the return boundary, keeping both eslint's `no-unsafe-*` rules and `tsc` satisfied simultaneously.
- One `eslint --fix` pass was needed for prettier formatting (multi-line object/array wrapping) — no logic changes.

## Issues Encountered
None beyond the lint/tsc friction documented above.

## User Setup Required
None — no external service configuration, no new DB objects (96-01 already created the tables this plan writes to).

## Next Phase Readiness
- `NotasCommandService` is ready for 96-07 to wire into `notas.module.ts` (alongside `NotasQueryService`) and expose via a controller with multipart file handling (`@UseInterceptors(FilesInterceptor(...))` for create/reply) and the `@FunctionGuard('notas-enviar-todos', 'create')` route guard that 96-06's `createTodos` defends in depth against.
- Every write method this plan implements follows the same `findVisibleOrFail`-first pattern established by 96-05's read side — 96-07's controller does not need to add any additional visibility checks, only route/DTO/multipart plumbing.
- No blockers identified for 96-07/96-08/96-09/96-10.

---
*Phase: 96-notas-compartidas-del-local*
*Completed: 2026-09-28*

## Self-Check: PASSED

Both created files found on disk (`api-ventago/src/app/notas/notas-command.service.ts`, `api-ventago/src/app/notas/notas-command.service.spec.ts`). Commit hash `f12c0ec7` verified present in `git -C api-ventago log --oneline`.
