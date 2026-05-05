---
phase: 29-pos-mercadopago-qr-din-mico
plan: 02
subsystem: database
tags: [postgresql, mercadopago, migrations, ddl, pg10-compat, sequelize, schema]

# Dependency graph
requires:
  - phase: 29-pos-mercadopago-qr-din-mico
    provides: "Plan 01 Wave 0 — qrcode.react@4.2.0 installed, MP_* env vars in .env.example, MP test fixtures + axios mock helper, docs/phase29-e2e.md"
provides:
  - "7 mp_* tables in PostgreSQL: mp_accounts, mp_payment_intents, mp_wallets, mp_movements, mp_refunds, mp_refund_attempts, mp_transfers"
  - "DB-level idempotency lock for MP webhook+polling (mp_payment_intents.payment_id UNIQUE)"
  - "Two partial UNIQUE indexes on mp_accounts (PG10-compatible alternative to COALESCE-in-UNIQUE)"
  - "CHECK constraints enforcing status enums + amount > 0 + currency whitelist"
  - "Cross-table FKs deferred (mp_movements.refund_id and .transfer_id added in 29-04/29-05 to avoid circular dependency)"
  - "Idempotent migration files (re-run safe via CREATE TABLE IF NOT EXISTS + DO blocks)"
  - "29-RUN.md with three execution paths (Docker / host PG / prod ssh) and full verification queries"
  - "29-99-rollback.sql DROP TABLE CASCADE in reverse FK order"
affects: [29-02b, 29-03, 29-04, 29-05, 29-08, 29-09, ops-prod-deploy]

# Tech tracking
tech-stack:
  added:
    - "PostgreSQL DDL migration files (PG10/PG15 compat)"
  patterns:
    - "Phase 26-style migration header (목적/실행순서/Idempotency/PG10-호환/보안 5-section block)"
    - "DO $$ ... END$$ blocks guard ALTER TABLE / ADD CONSTRAINT for re-runnable migrations"
    - "Two partial UNIQUE indexes (WHERE branch_id IS NULL / WHERE branch_id IS NOT NULL) — PG10 alternative to COALESCE in UNIQUE constraint"
    - "Cross-table FKs added in later step files via DO-guarded ADD CONSTRAINT to avoid forward-reference circular dependency in migration order"
    - "VARCHAR + CHECK constraint instead of PG ENUM type (avoids ALTER TYPE ADD VALUE PG10 limitation)"

key-files:
  created:
    - "api-ventago/migrations/29-01-mp-accounts.sql"
    - "api-ventago/migrations/29-02-mp-payment-intents.sql"
    - "api-ventago/migrations/29-03-mp-wallets-movements.sql"
    - "api-ventago/migrations/29-04-mp-refunds.sql"
    - "api-ventago/migrations/29-05-mp-transfers.sql"
    - "api-ventago/migrations/29-99-rollback.sql"
    - "api-ventago/migrations/29-RUN.md"
  modified: []

key-decisions:
  - "Two partial UNIQUE indexes on mp_accounts (uniq_mp_accounts_store_only WHERE branch_id IS NULL + uniq_mp_accounts_store_branch WHERE branch_id IS NOT NULL) — PATTERNS line 512 PG10-friendly alternative to COALESCE in UNIQUE constraint"
  - "VARCHAR + CHECK over PG ENUM type for status fields (PG10 ALTER TYPE ADD VALUE limitations, easier Sequelize migration)"
  - "Cross-table FKs (mp_movements.refund_id → mp_refunds, mp_movements.transfer_id → mp_transfers) added in 29-04 / 29-05 after target tables exist — avoids circular forward-reference"
  - "TIMESTAMP WITH TIME ZONE everywhere (PG10/PG15 both support; consistent UTC handling)"
  - "mp_movements has no updated_at — append-only audit log (CONTEXT D-A3-02)"
  - "amount > 0 CHECK on intents/movements/refunds/transfers — direction encoded in 'type' column, not sign"
  - "currency whitelist CHECK ('ARS' only) per Phase 29 scope — multi-currency deferred"
  - "29-RUN.md added two local-dev execution paths (Docker exec AND host psql) — host PG path needed when Docker not running locally"

patterns-established:
  - "Phase 29 migration file layout: BEGIN; CREATE TABLE IF NOT EXISTS; DO blocks (CHECK + cross-FK); CREATE INDEX IF NOT EXISTS (UNIQUE + partial + general); COMMIT; verification comment block"
  - "Cross-table FK split-add pattern: child table forward-declares column without FK, dependent table's migration adds the FK via ALTER TABLE in DO block"

requirements-completed: [MP-POS-01, MP-POS-02, MP-POS-03, MP-POS-05, MP-POS-06, MP-POS-07]

# Metrics
duration: 6min
completed: 2026-05-05
---

# Phase 29 Plan 02: MP Database Schema Summary

**7 mp_* tables created (PG10/PG15 compat) — OAuth accounts, payment intents with idempotency lock, virtual Caja MP wallet+movements, refunds with attempt audit, MP→cash transfers — all verified clean apply + idempotent re-run + clean rollback on local PostgreSQL 18.**

## Performance

- **Duration:** 6 min
- **Started:** 2026-05-05T10:41:41Z
- **Completed:** 2026-05-05T10:48:01Z
- **Tasks:** 1 (single-task plan)
- **Files created:** 7

## Accomplishments

- All 7 mp_* tables exist in dev DB with correct columns, indexes, and CHECK constraints
- `mp_payment_intents.payment_id` UNIQUE partial index in place — DB-level idempotency lock for webhook + polling double-arrival (T-29-07 mitigation)
- `mp_accounts` has two partial UNIQUE indexes (store-only + store-branch) — PG10-friendly alternative to COALESCE in UNIQUE (D-A1-02 implementation)
- `mp_wallets` UNIQUE(mp_account_id) — 1:1 wallet-per-account guarantee (T-29-05 boundary)
- `mp_refunds.refund_id` UNIQUE — second refund INSERT with same MP refund.id fails (replay protection)
- 5 step migrations applied cleanly + idempotent on re-run + rollback drops all 7 tables cleanly
- 29-RUN.md documents three execution paths (Docker / host PG / prod ssh) with full verification queries

## Task Commits

| # | Task | Commit (api-ventago) | Files | Type |
|---|------|----------------------|-------|------|
| 1 | Write 6 SQL + RUN.md (Phase 29 schema) | `00aa97e` | 7 (29-01..29-05, 29-99-rollback, 29-RUN.md) | feat |

**Plan metadata commit (root):** TBD (created by `/gsd-execute-phase` final step — bundles SUMMARY.md + STATE.md + ROADMAP.md + api-ventago submodule pointer)

## Files Created/Modified

### Created (api-ventago)

- `api-ventago/migrations/29-01-mp-accounts.sql` (94 lines) — mp_accounts table; OAuth tokens (AES-GCM cipher format), environment ENUM CHECK, two partial UNIQUE indexes on (store_id, branch_id|NULL)
- `api-ventago/migrations/29-02-mp-payment-intents.sql` (109 lines) — mp_payment_intents table; payment_id UNIQUE partial index (idempotency lock), status enum CHECK (5 values), amount > 0 CHECK, FK chain to mp_accounts/stores/branches/terminals
- `api-ventago/migrations/29-03-mp-wallets-movements.sql` (138 lines) — mp_wallets (UNIQUE mp_account_id, balance >= 0 CHECK, currency='ARS' CHECK) + mp_movements (5-value type CHECK, amount > 0 CHECK, append-only — no updated_at)
- `api-ventago/migrations/29-04-mp-refunds.sql` (138 lines) — mp_refunds (refund_id UNIQUE) + mp_refund_attempts (no UNIQUE — multiple attempts allowed, attempt_no >= 1 CHECK, status enum CHECK 3 values) + adds fk_mp_movements_refund FK
- `api-ventago/migrations/29-05-mp-transfers.sql` (114 lines) — mp_transfers (FK to mp_wallets, boxes ON DELETE RESTRICT, users ON DELETE RESTRICT, amount > 0, status enum 3 values) + adds fk_mp_movements_transfer FK
- `api-ventago/migrations/29-99-rollback.sql` (66 lines) — DROP cross-table FKs first, then DROP TABLE CASCADE in reverse FK order: transfers → refund_attempts → refunds → movements → wallets → payment_intents → accounts
- `api-ventago/migrations/29-RUN.md` (225 lines) — execution guide (Docker dev / host PG dev / prod ssh), verification queries, idempotency check, rollback procedure, troubleshooting table, next steps for Plan 02b

### Modified

None — DB-only plan, no code changes.

## Decisions Made

1. **Two partial UNIQUE indexes** on mp_accounts (instead of `UNIQUE(store_id, COALESCE(branch_id, 0))`) — PATTERNS line 512 confirms this is the PG10-preferred pattern. Both indexes ALSO scope on `disconnected_at IS NULL` so historical disconnected accounts don't conflict with new connections.

2. **VARCHAR + CHECK constraint** for all enum-like fields (`environment`, `status`, `type`, `currency`) instead of PG `ENUM` type — avoids PG10's `ALTER TYPE ADD VALUE` limitations and makes Sequelize migrations simpler. Each CHECK is wrapped in a `DO $$ ... END$$` block keyed on `pg_constraint.conname` for re-run safety.

3. **Cross-table FK split-add pattern**: `mp_movements.refund_id` (declared as nullable INTEGER without FK in 29-03, FK added in 29-04 after `mp_refunds` exists) and `mp_movements.transfer_id` (FK added in 29-05). Avoids the circular dependency that would occur if 29-03 forward-referenced tables created in 29-04/29-05.

4. **`TIMESTAMP WITH TIME ZONE`** everywhere — both PG10 and PG15 support this; gives consistent UTC handling across the application.

5. **`mp_movements` is append-only** (no `updated_at`) — audit log semantics per CONTEXT D-A3-02. Balance corrections must be done by inserting an `adjustment` type row, not by editing existing rows.

6. **`amount > 0` CHECK** on every monetary table (intents/movements/refunds/transfers) — direction is encoded in the `type` column ('credit'/'debit'/'transfer_out'/etc.), never via negative amount. Prevents subtle accounting bugs.

7. **`currency` whitelist `IN ('ARS')`** — Phase 29 scope is ARS only; multi-currency was explicitly deferred (CONTEXT "Out of scope"). The CHECK makes it impossible to accidentally insert other currencies before Phase N+ adds support.

8. **`target_box_id` and `user_id` use `ON DELETE RESTRICT`** in mp_transfers — preserves audit history (a deleted box or user can't orphan transfer records). FK target tables confirmed via `information_schema.columns`: `boxes` (plural), `users`, `sales`, `stores`, `branches`, `terminals`, `movements` — all `integer` id types.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Docker not available locally — switched verification to host PG**

- **Found during:** Task 1 (verification step)
- **Issue:** Plan's `<verify><automated>` command uses `docker exec -i api_ventago node -e "..."` to apply migrations against the dev `dbpostgres` container. `docker` CLI is not on PATH in this execution environment, so the canonical verification command fails immediately with `command not found`.
- **Investigation:** Per CLAUDE.md ("postgresql 데이터베이스는 루트에 설치되어 있음" — postgres is host-installed), there's a host PostgreSQL 18 server running on `localhost:5432` with the `ventago` database already populated (125 public tables including `stores`, `branches`, `terminals`, `boxes`, `users`, `sales`, `movements`). All FK target tables exist with `integer` id types matching the migration's `INTEGER` FK columns.
- **Fix:** Verified all 5 step migrations against the host PG using `psql -h localhost -p 5432 -U postgres -d ventago -v ON_ERROR_STOP=1 -f <file>`. Outcomes:
  - 5/5 migrations applied cleanly first run (all `COMMIT` outputs)
  - 5/5 migrations re-applied cleanly second run (idempotency proven — no errors)
  - 7 mp_* tables created exactly as specified
  - `payment_id` UNIQUE partial index confirmed via `pg_indexes`
  - 2 partial UNIQUE indexes on mp_accounts confirmed via `pg_indexes`
  - Cross-table FKs `fk_mp_movements_refund` and `fk_mp_movements_transfer` confirmed via `pg_constraint`
  - Rollback dropped all 7 tables cleanly; final re-apply restored 7 tables
- **Files modified:** None of the migrations needed change — only the verification command path differed
- **Forward-fix:** 29-RUN.md now documents BOTH paths (Docker exec for the canonical Ventago dev workflow AND host psql for environments without Docker). This makes the plan's verification reproducible regardless of operator environment.
- **Verification:** All 8 acceptance criteria from `<acceptance_criteria>` pass — file existence (7/7), no GENERATED AS IDENTITY in non-comment lines (0/0), SERIAL PRIMARY KEY count (7), IF NOT EXISTS occurrences (45+, well over the 15 minimum), BEGIN/COMMIT wrapping (1/1 each in all 6 SQL files), 7 tables produced, idempotent re-run (proven), payment_id UNIQUE present, 2 partial UNIQUE on mp_accounts present.
- **Committed in:** `00aa97e` (the migration files + the augmented 29-RUN.md)

---

**Total deviations:** 1 auto-fixed (1 blocking — environment mismatch)
**Impact on plan:** No scope change. The migration SQL itself is identical to the plan spec. Only the verification harness was adapted, and the adaptation was incorporated into the deliverable (29-RUN.md) so future operators on either environment can reproduce.

## Issues Encountered

None — verification on host PG path went green on first try; idempotency check (re-running all 5 migrations) returned 0 errors; rollback test removed all 7 tables and re-apply restored them.

## Pending: Production Migration

**Action item for ops:** Apply migrations on srv803182 (PostgreSQL 10) **before** code deploy of Plan 02b (Sequelize models). Per 29-RUN.md "운영 (srv803182)" section:

```bash
for f in 29-01-mp-accounts.sql 29-02-mp-payment-intents.sql 29-03-mp-wallets-movements.sql 29-04-mp-refunds.sql 29-05-mp-transfers.sql; do
  ssh jhkim-server "sudo -u postgres psql -d ventago -v ON_ERROR_STOP=1" < api-ventago/migrations/$f
done
```

Then verify with the 4 verification queries in 29-RUN.md "Verification" section. Per CLAUDE.md "운영 서버 직접 접근 규칙", DDL on production requires explicit user confirmation before each step.

## User Setup Required

None — DB-only plan. The `MP_*` env vars (MP_TOKEN_ENCRYPTION_KEY, MP_*_CLIENT_ID/SECRET, MP_WEBHOOK_SECRET, etc.) are placeholder slots in `api-ventago/.env.example` from Plan 01; ops will provision real values before Plan 02b boot validation activates them.

## Next Phase Readiness

**Plan 02b (Sequelize models + crypto service + module wiring) can now proceed:**

- All 7 mp_* tables exist in dev DB → models can `forFeature` register without "table does not exist" errors
- `payment_id` UNIQUE constraint in DB → Sequelize model only needs to mirror it as `unique: true` for documentation
- 2 partial UNIQUE on mp_accounts → Sequelize model should NOT declare `unique: true` on store_id/branch_id columns (per Phase 25 P02 decision: partial UNIQUE managed at index level only)
- VARCHAR + CHECK enums → Sequelize model uses `DataType.STRING` (not `DataType.ENUM`) for these columns
- Cross-table FK pattern documented → models can declare both directions of the BelongsTo/HasMany association without surprising migration ordering issues

**Subsequent waves:**

- Plan 03: OAuth flow (mp-oauth.service, mp-store-pos.service, callback controller)
- Plan 04: QR creation (mp-qr.service, intents controller)
- Plan 05: Webhook + Socket.io push (mp-webhook.service, websocket.gateway extension)
- Plan 08: Caja MP UI (control-de-caja integration)
- Plan 09: Refund flow + nullifySale extension

---

## Self-Check: PASSED

**Files exist:**
- FOUND: api-ventago/migrations/29-01-mp-accounts.sql
- FOUND: api-ventago/migrations/29-02-mp-payment-intents.sql
- FOUND: api-ventago/migrations/29-03-mp-wallets-movements.sql
- FOUND: api-ventago/migrations/29-04-mp-refunds.sql
- FOUND: api-ventago/migrations/29-05-mp-transfers.sql
- FOUND: api-ventago/migrations/29-99-rollback.sql
- FOUND: api-ventago/migrations/29-RUN.md

**Commits exist:**
- FOUND: 00aa97e in api-ventago repo (`feat(phase-29): add MP migrations — 7 mp_* tables (PG10/15 compat)`)

**Database state (host PG localhost:5432, db=ventago):**
- 7 mp_* tables present (mp_accounts, mp_movements, mp_payment_intents, mp_refund_attempts, mp_refunds, mp_transfers, mp_wallets)
- 2 partial UNIQUE on mp_accounts confirmed
- payment_id UNIQUE partial on mp_payment_intents confirmed
- 2 cross-table FKs (fk_mp_movements_refund, fk_mp_movements_transfer) confirmed
- Idempotent re-run proven (zero errors on second apply)
- Rollback proven (all 7 tables dropped cleanly, re-apply restored to final state)

---

*Phase: 29-pos-mercadopago-qr-din-mico*
*Plan: 02 (Wave 1a — DB schema)*
*Completed: 2026-05-05*
