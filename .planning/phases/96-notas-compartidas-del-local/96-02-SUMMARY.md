---
phase: 96-notas-compartidas-del-local
plan: 02
subsystem: backend
tags: [sequelize, postgresql, tenant-isolation, minio, jest]

# Dependency graph
requires:
  - phase: 96-01
    provides: 7 Notas tables in local DB (5432) + ver-notas/notas-enviar-todos permission seed
provides:
  - "api-ventago/src/app/notas/models/index.ts — NOTA_MODELS array + re-exports of all 7 Nota* classes"
  - "api-ventago/src/app/notas/models/{nota,nota-recipient,nota-read,nota-reply,nota-reaction,nota-edit-history,nota-attachment}.model.ts — 7 Sequelize models matching migration 2026-09-28-a-notas-tablas.sql column-for-column"
  - "api-ventago/src/common/minio/minio-public.util.ts — exported isPubliclyServable + NON_IMAGE_EXTENSIONS, extracted from minio.controller.ts"
affects: [96-03, 96-05, 96-06, 96-07, 96-08, 96-09]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "plain-INTEGER FK columns (storeId/senderId/userId) with no @ForeignKey/@BelongsTo to Users/Store — keeps Nota* models free of the repo's model-cycle pitfall and lets the offline spec register only NOTA_MODELS"
    - "offline Sequelize({ models: [...] }) spec pattern (no DB connection) for model-shape/tenant-policy assertions, per sku-serial.model.spec.ts precedent"
    - "pure code move (isPubliclyServable) into an exported util so a downstream module can prove a security property (control-group spec) about code it does not own"

key-files:
  created:
    - api-ventago/src/app/notas/models/nota.model.ts
    - api-ventago/src/app/notas/models/nota-recipient.model.ts
    - api-ventago/src/app/notas/models/nota-read.model.ts
    - api-ventago/src/app/notas/models/nota-reply.model.ts
    - api-ventago/src/app/notas/models/nota-reaction.model.ts
    - api-ventago/src/app/notas/models/nota-edit-history.model.ts
    - api-ventago/src/app/notas/models/nota-attachment.model.ts
    - api-ventago/src/app/notas/models/index.ts
    - api-ventago/src/app/notas/models/notas-models.spec.ts
    - api-ventago/src/common/minio/minio-public.util.ts
    - api-ventago/src/common/minio/minio-public.util.spec.ts
  modified:
    - api-ventago/src/common/minio/minio.controller.ts

key-decisions:
  - "Every Nota* model declares storeId as a plain (non-@ForeignKey) INTEGER column — matches the plan's explicit design rule to avoid pulling Users/Store into the association graph, which the repo's own model-cycle pitfall (constants/classes becoming undefined via import cycles) warns against"
  - "NotaReply has no parent/self-reference attribute at all (not nullable, not present) — D-13's one-level-thread rule is enforced by the DB schema (96-01's migration) and mirrored structurally in the model, not by a service-side check"
  - "nota.model.ts's importance column uses DataType.STRING (no explicit (12) length) instead of DataType.STRING(12) — the length-qualified version produced an 82-character single-line @Column decorator that exceeded eslint's default 80-char printWidth; since the column already exists as VARCHAR(12) in the DB via migration 96-01 (Sequelize doesn't run sync() against existing tables), dropping the length hint here has no runtime effect, and it kept the decorator on one line as the plan's grep-based acceptance criteria require"
  - "isPubliclyServable moved verbatim (byte-identical logic/comments) into minio-public.util.ts; minio.controller.ts now imports it — pure move, no behavior change, confirmed by running the full existing plus new spec suite green"

requirements-completed: [D-01, D-05, D-13, D-17]

# Metrics
duration: ~35min
completed: 2026-09-28
---

# Phase 96 Plan 02: Notas models + isPubliclyServable extraction Summary

**7 tenant-guarded Sequelize models for Notas (matching migration 96-01 column-for-column, with NotaReply structurally incapable of nested replies) plus `isPubliclyServable` extracted into an exported, control-group-tested util so later plans can prove Notas attachments never leak through the public MinIO route.**

## Performance

- **Duration:** ~35 min
- **Completed:** 2026-09-28T13:38:50Z
- **Tasks:** 2
- **Files modified:** 12 (11 new, 1 modified)

## Accomplishments
- Created all 7 `Nota*` Sequelize models under `api-ventago/src/app/notas/models/`, each with an explicit `type: DataType.X` on every `@Column` (no implicit/union types, per CLAUDE.md's Sequelize boot-crash warning) and every model carrying a plain `storeId: INTEGER` attribute so `TenantGuard`'s `resolveModelPolicy()` auto-detects them as guarded
- `Nota` declares all 6 `@HasMany` associations (`recipients`, `reads`, `replies`, `reactions`, `attachments`, `history`); `NotaReply`/`NotaReaction`/`NotaAttachment` form a 3-way circular import (reply → attachment/reaction, attachment/reaction → reply) resolved safely via sequelize-typescript's lazy `() => Model` association thunks (same pattern used throughout the repo for circular FK associations)
- `notas-models.spec.ts` — 6 offline tests (no DB connection, `new Sequelize({ models: NOTA_MODELS })` per the `sku-serial.model.spec.ts` precedent): `NOTA_MODELS.length === 7` (control), every model `guarded=true`/`allowGlobalRows=false`, correct table names for all 7, `NotaReply` has zero parent-like attributes (D-13) with a positive control that its real attributes do exist, `NotaEditHistory` has `createdAt` but no `updatedAt` (append-only), and `Nota.associations` exposes all 6 keys
- `minio-public.util.ts` — `NON_IMAGE_EXTENSIONS` + `isPubliclyServable` moved verbatim out of `minio.controller.ts`; `minio-public.util.spec.ts` — 8 tests with positive controls first (`store_logo_12.png`, `ABC123_1695000000.jpg` → `true`) followed by negatives covering `notas/3/0b1c.jpg`, nested `notas/3/r/x.png`, `.pdf`, `../x.png`, backslash, and empty string (all → `false`), proving D-17's first privacy layer: any `notas/{storeId}/...`-prefixed attachment key is structurally rejected by the public route's own predicate
- `minio.controller.ts` now imports `isPubliclyServable` from the new util instead of defining it locally; `sanitizeFileName` (which does not reference `NON_IMAGE_EXTENSIONS`) was left in place unchanged, per the plan's instruction

## Task Commits

Both tasks were committed together (Task 2's instructions explicitly bundle the commit for both, since Task 2's verification also re-runs and confirms Task 1's spec):

1. **Task 1: Create the 7 Nota\* models + NOTA_MODELS index + shape/tenant spec** — verified via `notas-models.spec.ts` (6/6 passed)
2. **Task 2: Extract isPubliclyServable into exported util with control-group spec** — verified via `minio-public.util.spec.ts` (8/8 passed) + `tsc --noEmit` clean

Combined commit: **`4c5d9639`** (api-ventago, feat) — `feat(96-02): modelos Notas + isPubliclyServable exportado con grupo de control`

**Plan metadata:** this SUMMARY.md + STATE.md/ROADMAP.md update will be committed as the standard executor final-commit step (root repo).

## Files Created/Modified
- `api-ventago/src/app/notas/models/nota.model.ts` - main Nota model, 14 columns, 6 HasMany associations
- `api-ventago/src/app/notas/models/nota-recipient.model.ts` - audience='users' recipient join table
- `api-ventago/src/app/notas/models/nota-read.model.ts` - seenAt/ackAt/repliesSeenAt (D-11 read vs ack)
- `api-ventago/src/app/notas/models/nota-reply.model.ts` - one-level replies (D-13), no parent column
- `api-ventago/src/app/notas/models/nota-reaction.model.ts` - fixed-5 reactions on nota or reply
- `api-ventago/src/app/notas/models/nota-edit-history.model.ts` - append-only, updatedAt: false
- `api-ventago/src/app/notas/models/nota-attachment.model.ts` - MinIO object keys, nota or reply scoped
- `api-ventago/src/app/notas/models/index.ts` - NOTA_MODELS array + re-exports
- `api-ventago/src/app/notas/models/notas-models.spec.ts` - 6 offline tenant/shape tests
- `api-ventago/src/common/minio/minio-public.util.ts` - exported isPubliclyServable + NON_IMAGE_EXTENSIONS
- `api-ventago/src/common/minio/minio-public.util.spec.ts` - 8 control-group tests
- `api-ventago/src/common/minio/minio.controller.ts` - now imports isPubliclyServable from the util (modified, no behavior change)

## Decisions Made
- Kept every `Nota*` model's cross-references (`senderId`, `userId`, `editedBy`, `uploadedBy`, `archivedBy`, `lastReplyBy`) as plain `INTEGER` columns rather than `@ForeignKey(() => Users)` — matches the plan's explicit design rule and avoids importing `Users`/`Store` into this folder's model graph.
- `nota.model.ts`'s `importance` column dropped the `(12)` length qualifier from `DataType.STRING(12)` to keep its `@Column` decorator on a single line under eslint's 80-char printWidth (see Deviations below) — no functional impact since the table's `VARCHAR(12)` already exists via the 96-01 migration and Sequelize does not run schema sync against existing tables.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Multi-line `@Column` decorator on the `importance` field broke the plan's own single-line grep acceptance check**
- **Found during:** Task 1, first acceptance-criteria grep run (`grep -a "@Column\b" -r ... | grep -av "type:"`)
- **Issue:** Initial implementation wrote `importance`'s `@Column({...})` across 5 lines (readable object-literal style). The plan's context explicitly requires "each `@Column({ ... })` decorator is written on ONE line so the grep check below works" — the multi-line opening `@Column({` line has no `type:` substring on it, so it printed as a false violation.
- **Fix:** Collapsed to a single line. This then exceeded eslint's default 80-char `printWidth` (82 chars with `DataType.STRING(12)`), which would have failed the commit-gate's added-lines eslint check. Resolved by dropping the `(12)` length qualifier (`DataType.STRING` — no functional change against an already-existing DB column) to bring the line to 78 chars while keeping it single-line.
- **Files modified:** `api-ventago/src/app/notas/models/nota.model.ts`
- **Verification:** `npx eslint src/app/notas/models ...` clean (0 problems); `grep -a "@Column\b" -r ... | grep -av "type:"` prints nothing; jest 6/6 still green.
- **Committed in:** `4c5d9639`

**2. [Rule 1 - Bug] `NotaEditHistory.getAttributes() as any` triggered `@typescript-eslint/no-unsafe-*` on newly-added spec lines**
- **Found during:** Task 1, eslint run on the new spec file
- **Issue:** An unnecessary `as any` cast on `NotaEditHistory.getAttributes()` (the same call, used without a cast elsewhere in the same file for `NotaReply`, already type-checks cleanly) triggered 3 `no-unsafe-assignment`/`no-unsafe-member-access` errors.
- **Fix:** Removed the `as any` cast — `getAttributes()`'s return type already supports the `.createdAt`/`.updatedAt` property checks used in the test.
- **Files modified:** `api-ventago/src/app/notas/models/notas-models.spec.ts`
- **Verification:** `npx eslint src/app/notas/models` clean; jest 6/6 still green; `tsc --noEmit` clean.
- **Committed in:** `4c5d9639`

---

**Total deviations:** 2 auto-fixed (both Rule 1 — lint/formatting issues caught by the plan's own acceptance checks and the repo's eslint config before commit)
**Impact on plan:** Neither changed any tested behavior. No scope creep.

## Issues Encountered
None beyond the two auto-fixed items above. The `minio.controller.ts` full-file eslint run also shows several pre-existing `@typescript-eslint/no-unsafe-*` errors on lines I did not touch (`uploadImage`/`getImage`'s untyped `res`/`file`/`err` parameters) — these are pre-existing repo-wide lint debt (confirmed the same class of violation exists unrelated files like `reseller.model.ts`), out of scope per the executor's scope-boundary rule (only fix issues directly caused by this task's changes), and not flagged by the commit-gate's added-lines-only eslint check since those lines were not modified.

## User Setup Required
None - no external service configuration required. No production/database changes in this plan (models only, DB tables already exist from 96-01).

## Next Phase Readiness
- `NOTA_MODELS` (from `api-ventago/src/app/notas/models/index.ts`) is the single source of truth for 96-03's `SequelizeModule.forFeature(NOTA_MODELS)` in `notas.module.ts`.
- `isPubliclyServable` is now importable from `minio-public.util.ts` for any future spec that needs to assert non-public-servability of Notas attachment keys, without needing to import the full `MinioController`.
- No blockers identified for downstream plans (96-03 service/controller, 96-05/06/07 backend routes, 96-08/09 frontend screens).

---
*Phase: 96-notas-compartidas-del-local*
*Completed: 2026-09-28*

## Self-Check: PASSED

All 11 created files found on disk (7 models + index + spec, minio util + its spec) plus the modified `minio.controller.ts`. Commit hash `4c5d9639` verified present in `git -C api-ventago log --oneline`.
