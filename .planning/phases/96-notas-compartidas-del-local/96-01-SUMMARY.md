---
phase: 96-notas-compartidas-del-local
plan: 01
subsystem: database
tags: [postgresql, sequelize, migrations, rbac, sidebar-permissions, multitenant]

# Dependency graph
requires: []
provides:
  - 7 Notas tables in local DB (5432): notas, nota_recipients, nota_reads, nota_replies, nota_reactions, nota_edit_history, nota_attachments
  - sidebar module `notas` (auxiliary, under app `herramientas`) with functions `ver-notas` and `notas-enviar-todos`
  - role_functions/role_function_actions grants for ver-notas (copied from ver-chat-de-equipo read) and notas-enviar-todos (admin role only)
  - regenerated .planning/intel/db-schema-tables.md and db-schema-fks.md reflecting the new tables
  - production (5434) precheck numbers for plan 96-10's approval step
affects: [96-02, 96-03, 96-04, 96-05, 96-06, 96-07, 96-08, 96-09, 96-10]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "row-by-row idempotent permission seed (temp-table previous-state + second-run guard RAISE EXCEPTION, copied from 2026-09-24-phase93-p5 and 2026-09-27-e patterns)"
    - "seed-before-code: menu/permission migration lands before any API/frontend code that reads the slugs"

key-files:
  created:
    - api-ventago/migrations/2026-09-28-a-notas-tablas.sql
    - api-ventago/migrations/2026-09-28-b-notas-permisos.sql
  modified:
    - .planning/intel/db-schema-tables.md
    - .planning/intel/db-schema-fks.md

key-decisions:
  - "D-13 enforced structurally: nota_replies has no parent/self-reference column, so nested replies are impossible by schema, not by app-level validation"
  - "ver-notas grants copied only from role_functions rows carrying ver-chat-de-equipo with action='read' (D-21) — not a blanket copy of the function's role_functions rows"
  - "notas-enviar-todos granted only to roles with slug 'admin' (D-03), verified on first run that no non-admin role received it"
  - "module notas hangs off app 'herramientas' as is_auxiliary=true (D-20) — this app is enabled in 100% of stores and is not used as a screen-gating condition anywhere in the frontend, so this widens nothing"

requirements-completed: [D-03, D-04, D-06, D-12, D-13, D-14, D-15, D-16, D-17, D-20, D-21]

duration: 25min
completed: 2026-09-28
---

# Phase 96 Plan 01: Notas DB tables + menu/permission seed Summary

**7 new store_id-scoped Notas tables plus a `ver-notas`/`notas-enviar-todos` permission seed applied and proven idempotent on local Postgres, with production precheck numbers captured for the 96-10 approval gate.**

## Performance

- **Duration:** ~25 min
- **Completed:** 2026-09-28T13:17:56Z
- **Tasks:** 3
- **Files modified:** 4 (2 new migration files, 2 regenerated intel docs)

## Accomplishments
- Wrote and applied `2026-09-28-a-notas-tablas.sql`: 7 tables (notas, nota_recipients, nota_reads, nota_replies, nota_reactions, nota_edit_history, nota_attachments), all `store_id NOT NULL REFERENCES stores(id)`, owner handed to `coolsistema` for tables + sequences (14 ALTER statements), `nota_replies` has no parent column (D-13 structural enforcement)
- Wrote and applied `2026-09-28-b-notas-permisos.sql`: module `notas` under app `herramientas` (auxiliary), functions `ver-notas`/`notas-enviar-todos`, grants copied from `ver-chat-de-equipo` (read) for ver-notas and restricted to `admin` role for notas-enviar-todos, with a row-by-row verification `DO` block and a second-run guard that aborts if it would restore a revoked grant
- Ran the seed twice on local (5432): first run produced 100 ver-notas grants / 15 notas-enviar-todos grants across 14 local stores and printed `p96 OK`; second run returned `INSERT 0 0` for every statement and printed the same `p96 OK` — idempotency proven
- Captured production (5434) read-only precheck numbers for the 96-10 approval step (see below)
- Regenerated `.planning/intel/db-schema-tables.md` / `db-schema-fks.md` — confirmed all 7 `nota_*`/`notas` tables now appear in the catalog

## Task Commits

Each task was committed atomically (Tasks 1 and 2 produced no independent commit — the plan explicitly bundles both migration files into a single commit at Task 3, since Task 2's file depends on Task 1's tables existing and both had to be verified together before being considered "done"):

1. **Task 1: Write DDL migration for the 7 Notas tables** — verified via `migration-conventions.spec.ts` (9/9 passed), committed together with Task 2 in `24c0aed4`
2. **Task 2: Write menu/permission seed migration with verification block** — verified via `migration-conventions.spec.ts` (9/9 passed), committed together with Task 1 in `24c0aed4`
3. **Task 3: Apply both migrations to LOCAL 5432, prod read-only precheck, regen intel, commit** — `24c0aed4` (api-ventago, feat) + `b302b63` (root repo, docs)

**Plan metadata:** this SUMMARY.md itself will be committed as part of the standard executor final-commit step.

## Files Created/Modified
- `api-ventago/migrations/2026-09-28-a-notas-tablas.sql` - DDL for the 7 Notas tables, indexes, owner grants
- `api-ventago/migrations/2026-09-28-b-notas-permisos.sql` - module/function/role_functions/role_function_actions seed + idempotent verification block
- `.planning/intel/db-schema-tables.md` - regenerated, now includes `notas`, `nota_recipients`, `nota_reads`, `nota_replies`, `nota_reactions`, `nota_edit_history`, `nota_attachments`
- `.planning/intel/db-schema-fks.md` - regenerated, now includes FKs for the 7 new tables

## Production (5434) Precheck Numbers — READ-ONLY, captured for plan 96-10

Query run via `ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -At -c ..."` (no writes):

| Metric | Value |
|---|---|
| `stores` count | 18 |
| `store_apps` rows with app `herramientas` enabled | 18 |
| `role_functions` + `role_function_actions` rows for `ver-chat-de-equipo` with action `read` | 126 |
| `roles` with `slug='admin'` | 19 |
| `modules` with `slug='notas'` (pre-migration) | 0 |
| `information_schema.tables` matching `notas`/`nota_recipients` (pre-migration) | 0 |

Interpretation: `herramientas` is enabled in all 18 production stores (18=18, matches the assumption in the migration header that no store would lose the menu group). No `notas` module or tables exist yet in production — the migration is a clean additive change with no pre-existing rows to conflict with. These numbers (and the local seed run's grant counts) are the basis for the "expected affected rows" shown to the user before the 96-10 production apply.

## Decisions Made
- Confirmed via plan's own acceptance criteria and threat-model checks: no deviation from the exact DDL/seed structure specified in the plan was needed — the SQL in the plan action blocks was implementable verbatim.
- One naming collision was caught before verification: an early draft of the DDL file's header comment contained the literal string "w4-exempt" inside prose explaining *why* the exemption wasn't needed, which the plain-text `grep -ac "w4-exempt"` acceptance check (expecting 0) would have flagged as a false positive. Reworded the comment to avoid the literal token — no semantic or SQL change, purely a comment wording fix caught during self-verification before commit.

## Deviations from Plan

None - plan executed exactly as written. The only adjustment was the comment wording fix described above, which was corrected in-place before the first jest verification run and is not a deviation from the plan's SQL/behavioral requirements (Rule 1, auto-fixed: a comment string collided with a grep-based acceptance check regex; fixed inline, re-verified, no separate commit needed since it was caught pre-commit).

## Issues Encountered
None. SSH connectivity to `jhkim-server` for the production precheck worked on the first attempt (no passphrase issue this time). Local psql commands (5432) ran without incident.

## User Setup Required

None - no external service configuration required. Production (5434) migration application is intentionally deferred to plan 96-10, which requires explicit user approval per CLAUDE.md's DML/DDL-on-production rule.

## Next Phase Readiness
- Local DB (5432) now has the full Notas schema and permission seed — plans 96-02 through 96-09 (models, services, controllers, frontend) can be built and tested against it.
- `.planning/intel/db-schema-tables.md`/`db-schema-fks.md` are current — later plans should reference these directly rather than guessing column names.
- Plan 96-10 has the exact production precheck numbers needed to show the user "expected affected rows" before applying `2026-09-28-a-notas-tablas.sql` and `2026-09-28-b-notas-permisos.sql` to 5434.
- No blockers identified for downstream plans in this phase.

---
*Phase: 96-notas-compartidas-del-local*
*Completed: 2026-09-28*

## Self-Check: PASSED

All created files found on disk (2 migrations, 2 regenerated intel docs, this SUMMARY). Both commit hashes (`24c0aed4` in api-ventago, `b302b63` in root repo) verified present in git log.
