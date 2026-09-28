---
phase: 96-notas-compartidas-del-local
plan: 07
subsystem: api
tags: [nestjs, http, function-guard, multer, minio, notas]

# Dependency graph
requires:
  - phase: 96-05
    provides: NotasQueryService — list/unreadSummary/detail/reads/history/markSeen/ack
  - phase: 96-06
    provides: NotasCommandService — createPersonal/createTodos/edit/archive/pin/reply/react/openAttachment
provides:
  - "api-ventago/src/app/notas/notas.controller.ts — 14-handler HTTP surface matching the 96-04 frontend contract, each with exactly one @FunctionGuard"
  - "api-ventago/src/app/notas/nota-adjuntos.controller.ts — authenticated, visibility-checked attachment download (never @Public)"
  - "api-ventago/src/app/notas/notas.module.ts — wires NOTA_MODELS + Users/Store + WebsocketModule + MinioModule; registered in app.module.ts"
affects: [96-08, 96-09, 96-10]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Controller-level route declaration order encodes route-shadowing safety: static paths (unread) declared before ':id' handlers, proven by a metadata-index assertion in the spec rather than by reading source"
    - "@GetUser() return type is narrowed to a local `{ id: number; storeId: number }` interface per controller file instead of `any` — avoids no-unsafe-argument/no-unsafe-member-access without introducing a shared type outside this plan's file list"
    - "Metadata-only controller spec (no Nest TestingModule, no HTTP call) — imports the controller class directly and reads Reflect.getMetadata(FUNCTION_METADATA_KEY, ...) off each prototype method, proving guard wiring is regression-proof against a future handler added without a decorator"

key-files:
  created:
    - api-ventago/src/app/notas/notas.controller.ts
    - api-ventago/src/app/notas/nota-adjuntos.controller.ts
    - api-ventago/src/app/notas/notas.controller.spec.ts
    - api-ventago/src/app/notas/notas.module.ts
  modified:
    - api-ventago/src/app.module.ts

key-decisions:
  - "Both controllers declare a local `NotasReqUser { id, storeId }` interface instead of importing/exporting a shared type from notas.types.ts — keeps the fix inside this plan's declared files_modified and satisfies NotasQueryService/NotasCommandService's `JwtUser` parameter structurally"
  - "nota-adjuntos.controller.ts uses `@Res() res: Response` (from 'express') instead of `any` — NotasCommandService.openAttachment()'s typed `{ stream: Readable; ... }` return then flows through without any `any` leakage, so eslint's no-unsafe-* rules pass with zero suppressions"
  - "Comment wording in nota-adjuntos.controller.ts avoids the literal substring '@Public' (writes 'jamás exenta de autenticación' instead) so the plan's own `grep -a \"@Public\"` acceptance check isn't defeated by a doc comment — same class of self-inflicted grep collision noted in 96-01/96-04's summaries"

requirements-completed: [D-01, D-03, D-05, D-08, D-10, D-17, D-18, D-19]

# Metrics
duration: ~35min
completed: 2026-09-28
---

# Phase 96 Plan 07: API Notas — controladores, adjuntos, módulo Summary

**14-handler `NotasController` + a never-`@Public()` `NotaAdjuntosController` exposing the 96-04 frontend contract over HTTP, each route carrying exactly one `@FunctionGuard`, proven by a 31-case metadata-only spec rather than by reading source — plus `NotasModule` wired into `app.module.ts` (team-chat untouched).**

## Performance

- **Duration:** ~35 min
- **Completed:** 2026-09-28
- **Tasks:** 2
- **Files modified:** 5 (4 new, 1 modified)

## Accomplishments
- `notas.controller.ts` — `list`, `unread`, `createPersonal` (`POST /notas`), `createTodos` (`POST /notas/todos`), `detail`, `reads`, `history`, `edit`, `archive`, `pin`, `seen`, `ack`, `reply`, `react`: 14 handlers, each decorated with exactly one `@FunctionGuard('ver-notas', 'read')` except `createTodos`, which requires `@FunctionGuard('notas-enviar-todos', 'create')` (D-03). Static route `unread` is declared before the `:id` handlers so it never falls into `ParseIntPipe` (T-96-36).
- `nota-adjuntos.controller.ts` — `GET /nota-adjuntos/:attachmentId` streams via `NotasCommandService.openAttachment()`, which re-checks `findVisibleOrFail` before touching MinIO (96-06's mutation-proven ordering); response sets `Content-Type` (stored mime), `X-Content-Type-Options: nosniff`, `Cache-Control: private, max-age=300`, and `Content-Disposition: inline` — never `@Public()`.
- `notas.controller.spec.ts` — 31 passing cases: a control assertion that the controller exposes ≥14 handlers (fails loudly if the spec reads nothing), one case per handler proving `FUNCTION_METADATA_KEY` metadata is defined, an exact-match assertion that `createTodos` carries `{ functionSlug: 'notas-enviar-todos', action: 'create' }`, an exact-match assertion that every other handler carries `{ functionSlug: 'ver-notas', action: 'read' }`, a route-order assertion (`unread` index < `detail` index), and an assertion that `NotaAdjuntosController.download` carries `ver-notas/read` and has no `IS_PUBLIC_KEY` metadata on either the handler or the class.
- `notas.module.ts` — `SequelizeModule.forFeature([...NOTA_MODELS, Users, Store])`, imports `WebsocketModule` and `MinioModule`; does not re-provide `FunctionPermissionService` (comes from the `@Global` `MemoryCacheModule`, per 96-06's own constructor injection of it).
- `app.module.ts` — `NotasModule` imported and registered immediately after `TeamChatModule`; `git diff HEAD~1 --stat -- src/app/team-chat` confirms zero touch to Team Chat.
- Full verification: `tsc --noEmit` clean, `npx eslint src/app/notas --max-warnings=0` → 0 problems, `jest src/app/notas --maxWorkers=1` → **166/166 passed** (5 suites: controller spec + both service specs + models spec + rules spec).

## Task Commits

Each task was committed atomically (api-ventago submodule):

1. **Task 1: NotasController + NotaAdjuntosController + guard metadata spec** — `e606d42d` (feat)
2. **Task 2: NotasModule + app.module.ts registration** — `f1a3cf93` (feat)

**Plan metadata:** this SUMMARY.md + STATE.md/ROADMAP.md update committed as the standard executor final-commit step (root repo, not pushed — per this plan's explicit no-push override, seed → api → app deploy ordering is handled in 96-10 after user approval).

## Files Created/Modified
- `api-ventago/src/app/notas/notas.controller.ts` - 14-handler HTTP surface (list/unread/create×2/detail/reads/history/edit/archive/pin/seen/ack/reply/react)
- `api-ventago/src/app/notas/nota-adjuntos.controller.ts` - authenticated attachment download, visibility-checked before MinIO read
- `api-ventago/src/app/notas/notas.controller.spec.ts` - 31 metadata-only permission cases
- `api-ventago/src/app/notas/notas.module.ts` - module wiring (models + WebsocketModule + MinioModule)
- `api-ventago/src/app.module.ts` - `NotasModule` import + registration (2-line addition next to `TeamChatModule`)

## Decisions Made
- See `key-decisions` in frontmatter: local `NotasReqUser` interface per controller (not a new shared export), `Response`-typed `@Res()` in the attachment controller, and a grep-safe comment wording in `nota-adjuntos.controller.ts`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `@GetUser() user: any` failed the plan's own eslint gate**
- **Found during:** Task 1, first `npx eslint --max-warnings=0` run before commit
- **Issue:** The plan's action text used `@GetUser() user: any` implicitly (interface style consistent with `team-chat.controller.ts`'s existing `any`-typed params), but `--max-warnings=0` on this specific file set surfaces `@typescript-eslint/no-unsafe-argument`/`no-unsafe-call`/`no-unsafe-member-access` on every call into the strongly-typed `NotasQueryService`/`NotasCommandService` methods (whose params are typed `JwtUser`, not `any`) and on every `res.setHeader(...)` call in the attachment controller (`res: any`). Confirmed this is a real gap, not an existing-code false positive, by running the same lint command against `team-chat.controller.ts` — it fails identically (13 errors), meaning that file predates this strictness and was never a clean precedent to copy verbatim.
- **Fix:** Declared a local `NotasReqUser { id: number; storeId: number }` interface in each controller file and typed every `@GetUser()` parameter with it; typed `nota-adjuntos.controller.ts`'s `@Res()` parameter as `Response` (from `'express'`) instead of `any`, which also resolved all `res.*` unsafe-call/member-access errors since `openAttachment()`'s return type is already fully typed.
- **Files modified:** `notas.controller.ts`, `nota-adjuntos.controller.ts`
- **Verification:** `npx eslint src/app/notas --max-warnings=0` → 0 problems; `tsc --noEmit` clean; `jest src/app/notas` still 166/166.
- **Committed in:** `e606d42d` (Task 1), `f1a3cf93` (Task 2, re-verified after module wiring)

**2. [Rule 1 - Bug] A doc comment collided with the plan's own `grep -a "@Public"` acceptance check**
- **Found during:** Task 1, acceptance-criteria grep before commit
- **Issue:** The first draft of `nota-adjuntos.controller.ts`'s header comment explained "Nunca @Public —" (explaining why the route is never public), which contains the literal substring the acceptance grep expects to find zero matches of — the same self-defeating-comment class already documented in 96-01/96-04's summaries (`w4-exempt`/`/minio` collisions).
- **Fix:** Reworded to "Ruta siempre autenticada y jamás exenta de autenticación" — same meaning, no `@Public` substring.
- **Files modified:** `nota-adjuntos.controller.ts`
- **Verification:** `grep -a "@Public" nota-adjuntos.controller.ts` now prints nothing (exit 1, as required).
- **Committed in:** `e606d42d` (Task 1)

**3. [Rule 1 - Bug] Metadata spec's helper functions failed tsc/eslint on prototype-object typing**
- **Found during:** Task 1, first `jest` run for the RED phase of the metadata spec
- **Issue:** `metaOf(proto, handler)` needed to accept `NotasController.prototype`/`NotaAdjuntosController.prototype` and index into them by a dynamic string key. Typing `proto` as `Record<string, unknown>` fails `tsc` at every call site (`Argument of type 'NotasController' is not assignable to parameter of type 'Record<string, unknown>' — Index signature ... is missing`); typing it as `any` passes `tsc` but fails eslint's `no-unsafe-member-access` on `proto[handler]`, and referencing `NotaAdjuntosController.prototype.download` directly as a value (to pass to a second `Reflect.getMetadata` call) triggers `@typescript-eslint/unbound-method`.
- **Fix:** Added a single `asHandlerRecord()` helper that does one explicit `proto as unknown as Record<string, unknown>` cast per class prototype (not per call), and casts `proto[handler]` to `object` at the `Reflect.getMetadata` call site — eliminating `any` from the spec entirely while keeping both `tsc` and eslint's strict rule set satisfied.
- **Files modified:** `notas.controller.spec.ts`
- **Verification:** `tsc --noEmit` clean, `npx eslint ... --max-warnings=0` → 0 problems, spec 31/31 passing.
- **Committed in:** `e606d42d` (Task 1)

---

**Total deviations:** 3 auto-fixed (all Rule 1 — bugs caught by the plan's own verification commands before any commit landed with the defect)
**Impact on plan:** All three were lint/type-strictness gaps in the plan's literal code sketch, not behavior changes — the resulting HTTP surface, guard assignments, and route shapes match the plan's table exactly. No scope creep.

## Issues Encountered
None beyond the three auto-fixed items above.

## User Setup Required
None — no external service configuration required. The seed migration (`ver-notas`/`notas-enviar-todos` functions) was already applied locally in 96-01; production seed application is deferred to 96-10 per this plan's no-push override (seed → api → app ordering, pending user approval).

## Next Phase Readiness
- The full Notas HTTP surface (`GET/POST /notas`, `GET /notas/unread`, `GET/PATCH /notas/:id`, `GET /notas/:id/{reads,history}`, `POST /notas/:id/{archive,pin,seen,ack,replies,reactions}`, `GET /nota-adjuntos/:attachmentId`) is implemented, guarded, and wired into `app.module.ts` — ready for 96-08/96-09's screens to consume once mounted behind a running API.
- **Not pushed** — per this plan's explicit instruction, the production DB seed (`ver-notas`/`notas-enviar-todos` functions + role_functions grants) is not yet applied in production, so pushing this API now would register routes whose `FunctionGuard` slugs don't exist there (denying everyone, including admins) and whose models query tables that may not exist in prod. `git status -sb` in `api-ventago` shows the branch ahead of its remote by these 2 commits, confirming nothing was pushed.
- 96-10 is the designated plan for the ordered deploy: seed migration → api → app, after user approval.
- No blockers identified for 96-08/96-09 (frontend screens) or 96-10 (deploy sequencing).

---
*Phase: 96-notas-compartidas-del-local*
*Completed: 2026-09-28*

## Self-Check: PASSED

All 4 created source files + this SUMMARY.md found on disk. Both commit hashes
(`e606d42d`, `f1a3cf93`, api-ventago submodule) verified present in
`git -C api-ventago log --oneline --all`.
