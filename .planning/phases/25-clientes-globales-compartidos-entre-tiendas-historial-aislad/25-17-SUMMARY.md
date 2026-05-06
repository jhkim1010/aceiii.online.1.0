---
phase: 25-clientes-globales-compartidos-entre-tiendas-historial-aislad
plan: 17
subsystem: clients-backfill
tags:
  - backfill
  - migration
  - clients-sync
  - operational-tool
  - autonomous-false
dependency_graph:
  requires:
    - 25-16 (ClientsSyncService.syncFromLegacy)
    - 25-09 (CUIT/DNI validators)
    - 25-04 (sales.store_client_id column)
    - 25-02 (global_clients/store_clients tables)
  provides:
    - operational backfill tool (npm run backfill:clients{,:dry})
    - dry-run + postcheck SQL pair
  affects:
    - api-ventago/scripts/ (new dir entry)
    - api-ventago/migrations/ (read-only SQL)
    - dev DB ventago (백필 27 row, sales remap 13 건)
    - 운영 DB (NOT applied — 사용자 승인 대기)
tech_stack:
  added: []
  patterns:
    - NestApplicationContext (NestFactory.createApplicationContext) for standalone scripts
    - require.main === module guard for testable entrypoints
    - Per-row transaction + try/catch isolation (batch resilience)
    - Webcrypto polyfill mirroring main.ts for @nestjs/schedule compat
    - Helper extraction (processOneRow + makeEmptyStats) for jest unit testing
key_files:
  created:
    - api-ventago/migrations/20260505-clients-backfill-stats.sql
    - api-ventago/scripts/backfill-clients-to-global.ts
    - api-ventago/src/app/shared/clients-sync/backfill-clients-to-global.spec.ts
  modified:
    - api-ventago/package.json (scripts.backfill:clients{,:dry})
  pre_existing:
    - api-ventago/migrations/20260505-clients-backfill-dryrun.sql
decisions:
  - Spec located under src/ (rootDir=src) instead of scripts/ — Phase 26 P04 pattern
  - Webcrypto polyfill duplicated from main.ts — standalone scripts skip main bootstrap
  - getModelToken(Class) over getModelToken('Name') string — type-safe and avoids TS2345
  - storeOwnerCache.has() guard over undefined check — Map<number, number|null> doesn't accept undefined
  - require.main === module guard — allows spec to import without auto-running main()
  - processOneRow extracted for unit testability — Plan 16 ClientsSyncService 재사용 + new sales remap
metrics:
  duration_minutes: 13
  completed_date: 2026-05-06
  tasks_total: 3
  tasks_executed: 2
  tasks_gated: 1
---

# Phase 25 Plan 17: Backfill B (legacy clients → global) — Summary

**One-liner:** Operational standalone NestJS script + dry-run/postcheck SQL pair that backfills legacy `clients` rows into `global_clients` + `store_clients` and remaps `sales.client_id → sales.store_client_id`, all idempotent and gated for explicit production approval.

## Tasks Executed

| # | Task | Status | Commit |
|---|------|--------|--------|
| 1 | dry-run + postcheck SQL | done | 4cbbd47 |
| 2 | backfill 스크립트 + spec + npm 스크립트 + dev 검증 | done | 7be6bba |
| 3 | 운영 DB 적용 | **GATED** — awaiting explicit user approval | — |

## Self-Check: PASSED

- ✅ `api-ventago/migrations/20260505-clients-backfill-stats.sql` exists
- ✅ `api-ventago/scripts/backfill-clients-to-global.ts` exists
- ✅ `api-ventago/src/app/shared/clients-sync/backfill-clients-to-global.spec.ts` exists
- ✅ `api-ventago/package.json` contains `backfill:clients` + `backfill:clients:dry`
- ✅ Both SQL files are statement-level read-only (verified with grep -vE '^\s*--' + keyword scan)
- ✅ Spec passes (8/8 cases) — `npm test -- --testPathPattern=backfill-clients-to-global`
- ✅ Build green — `npm run build`
- ✅ Commit `4cbbd47` (Task 1) verified in git log
- ✅ Commit `7be6bba` (Task 2) verified in git log

## Dev Environment Verification

### dry-run on dev `ventago` DB (host PG18)

| Bucket | Count | Notes |
|--------|-------|-------|
| total_candidates | 31 | clients with `document IS NOT NULL AND TRIM <> ''` |
| dry_invalid_or_temp | 4 | length not in {7,8,11} (e.g., `24727247438160`, `307708352957`) |
| dry_already_mapped | 10 | GC + SC both exist |
| dry_will_create | 17 | will sync new GC and/or SC |
| errors | 0 | — |

dryrun SQL Section 3 results (independent verification):

| metric | value |
|--------|-------|
| total_legacy_with_doc | 31 |
| valid_doc_count | 27 (= 7+8+11 length) |
| already_mapped_to_store | 10 |
| will_be_synced | 17 |
| sales_remap_candidates | 13 |

All numbers cross-validated.

### execute on dev DB — first run

```json
{
  "args": { "dryRun": false, "batchSize": 100 },
  "stats": {
    "total_candidates": 31,
    "skipped_invalid": 4,
    "synced_new": 17,
    "synced_existing": 10,
    "sales_remapped": 13,
    "errors": []
  },
  "elapsed_ms": 3378
}
```

### execute on dev DB — second run (idempotency)

```json
{
  "stats": {
    "total_candidates": 31,
    "skipped_invalid": 4,
    "synced_new": 0,
    "synced_existing": 27,
    "sales_remapped": 0,
    "errors": []
  },
  "elapsed_ms": 2218
}
```

✅ **Idempotent** — second run creates 0 new GCs and remaps 0 sales (all already mapped).

### Postcheck SQL on dev DB

| metric | value | expected | result |
|--------|-------|----------|--------|
| clients_with_doc | 31 | unchanged | ✅ |
| clients_unmapped_after_backfill | 4 | = invalid_length count | ✅ |
| sales_with_store_client_id | 13 | = sales_remap_candidates from dryrun | ✅ |
| sales_legacy_only | 1 | document NULL row only | ✅ (reason=A_no_document) |

Cross-store cluster check (Section 3): 0 rows where same doc maps to different GC IDs — clean.

Sales remap reason breakdown (Section 4):
- A_no_document: 1 sale (legacy fallback expected — Pitfall 4 read precedence)
- B_invalid_doc_format: 0
- C_valid_doc_unmapped: 0 (no missed valid rows)

## Code Highlights

### Standalone NestJS Entrypoint Pattern

```typescript
// Webcrypto polyfill — mirrors main.ts for @nestjs/schedule compat
import { webcrypto as nodeWebCrypto } from 'node:crypto';
if (!(globalThis as any).crypto) {
  (globalThis as any).crypto = nodeWebCrypto;
}

// require.main guard — spec imports without auto-run
if (require.main === module) {
  main().catch((err) => {
    console.error('[Backfill 25-17] FATAL:', err?.stack || err);
    process.exit(2);
  });
}
```

### Testable Helper Extraction

```typescript
export async function processOneRow(
  legacy, syncService, saleModel, sequelize, stats,
): Promise<void> {
  const t = await sequelize.transaction();
  try {
    const result = await syncService.syncFromLegacy(legacy, { ownerGroupId: null }, t);
    if (!result) { stats.skipped_invalid++; await t.commit(); return; }
    const [n] = await saleModel.update(
      { storeClientId: result.storeClientId },
      { where: { clientId: legacy.id, storeId: legacy.storeId, storeClientId: null }, transaction: t },
    );
    stats.sales_remapped += n;
    if (result.alreadyExisted) stats.synced_existing++; else stats.synced_new++;
    await t.commit();
  } catch (err) {
    await t.rollback().catch(() => undefined);
    stats.errors.push({ clientId: legacy.id, ... });
  }
}
```

Spec covers: null result / new sync / existing sync / sync throw / sales.update throw / 3-row mixed scenario / 0-sales remap.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocker] TS compile errors blocked spec run**
- **Found during:** Task 2 first `npm test` run
- **Issue:** `getModelToken('Name')` (string) → TS2345 (expects `Function`); `storeOwnerCache.set(id, undefined)` → TS2345
- **Fix:** Switched to `getModelToken(Class)` with imported model classes (GlobalClient/StoreClient/Store); refactored cache to `has()` guard returning `number | null`
- **Files modified:** `api-ventago/scripts/backfill-clients-to-global.ts`
- **Commit:** 7be6bba

**2. [Rule 3 - Blocker] `crypto is not defined` runtime error**
- **Found during:** Task 2 dry-run smoke test
- **Issue:** `@nestjs/schedule` calls `globalThis.crypto.randomUUID()` during module init; standalone scripts bypass `main.ts` polyfill
- **Fix:** Replicated webcrypto polyfill from `main.ts` at script top
- **Files modified:** `api-ventago/scripts/backfill-clients-to-global.ts`
- **Commit:** 7be6bba

**3. [Rule 1 - Bug] Spec misplaced under `scripts/` — jest rootDir mismatch**
- **Found during:** Task 2 first `npm test` (No tests found)
- **Issue:** Jest config has `rootDir: "src"` so `scripts/*.spec.ts` is invisible
- **Fix:** Moved spec to `src/app/shared/clients-sync/backfill-clients-to-global.spec.ts` (Phase 26 P04 precedent)
- **Files modified:** spec relocated; import path adjusted to `../../../../scripts/...`
- **Commit:** 7be6bba

### Plan-Level Adjustments

- **No production execution attempted.** Plan Task 3 is a checkpoint requiring explicit user approval per CLAUDE.md 운영 destructive 규칙. Producer continues to await operator action; this is normal flow, not a deviation.

## Production Application — User-Driven Steps

⚠️ **The script has NOT been run against the production DB.** All commands below must be run by a human operator after they review dev results above.

### Pre-flight (read-only stats)

```bash
ssh jhkim-server "sudo -u postgres psql -d ventago" \
  < api-ventago/migrations/20260505-clients-backfill-dryrun.sql
```

Operator should compare output against dev numbers (especially `valid_doc_count`, `will_be_synced`, `sales_remap_candidates`) to estimate impact. If `will_be_synced` is unexpectedly large (e.g., > 100) or `cross-store` Section 4 shows surprising clusters, **STOP and reconsider**.

### Pre-backfill snapshot (mandatory)

```bash
ssh jhkim-server "sudo -u postgres pg_dump \
  -t global_clients -t store_clients -t clients -t sales \
  ventago > ~/backups/ventago-pre-backfill-25-17-$(date +%Y%m%d).sql"
```

Retain ≥ 30 days. This is the rollback artifact if anything goes wrong.

### Execute backfill

Two options depending on whether `ts-node` is available in the running container:

**Option A — Run inside `api_ventago` container (preferred):**

```bash
ssh jhkim-server "docker exec api_ventago npm run backfill:clients --prefix /app"
```

**Option B — Run dist build (if ts-node not in production image):**

```bash
ssh jhkim-server "docker exec api_ventago node /app/dist/scripts/backfill-clients-to-global.js"
```

Capture the JSON final report. Compare:
- `synced_new + synced_existing` should equal dryrun `valid_doc_count`
- `sales_remapped` should equal dryrun `sales_remap_candidates`
- `errors: []` ideally; if non-empty, investigate per-row before proceeding

### Postcheck (read-only verification)

```bash
ssh jhkim-server "sudo -u postgres psql -d ventago" \
  < api-ventago/migrations/20260505-clients-backfill-stats.sql
```

Verify:
- `clients_unmapped_after_backfill` ≈ count of invalid/temp doc rows (NOT zero — Pitfall 4 expected fallback)
- `sales_with_store_client_id` increased by `sales_remapped` count
- Section 3 shows no rows where same `doc_norm` maps to different `global_client_id` values
- Section 4 reason breakdown — `C_valid_doc_unmapped` should be 0

### Smoke test (operational)

User-driven application-layer verification:

1. Login as매장 6 admin (`coolsistema`) → cliente "Kim, jung ho" 검색 → store_clientId 정상 반환
2. Login as매장 9 admin (`ACE`) → cliente "kim jung ho" 검색 → 같은 globalClientId 매핑 확인
3. 두 매장의 historial 격리 검증 — 한 쪽 sale 이 다른 쪽에 보이지 않음 (Pitfall 4 read precedence)

## Known Stubs / Limitations

- **Invalid-length doc rows (PG10/PG15 dev: 4 rows; production: TBD)** — these clients have `document` like `307708352957` (12 digits) which is neither valid DNI nor valid CUIT. They remain in `clients` table only and `sales` referencing them keep `store_client_id NULL`. Read precedence falls back to `clientId` per Pitfall 4. Future cleanup is policy decision (out of scope).

- **`storeTemplate` Consumidor Final placeholder (`document='00000000'`)** — passes loose DNI check but is매장 placeholder, not human. Already documented as Plan 16 follow-up; backfill will sync it (`isLooseDni` 8-digit pass) but represents fictitious data. Plan 16 SUMMARY notes "향후 정책 결정 필요".

## TDD Gate Compliance

Plan type is `execute` (not `tdd`), so RED/GREEN/REFACTOR commit gate not enforced at plan level. Task 2 inner spec was added concurrently with implementation (spec validates extracted helpers).

## Threat Surface Scan

No new network endpoints, auth paths, or schema changes introduced. The script reads `clients` and writes to `global_clients` / `store_clients` / `sales` — all governed by existing FK + UNIQUE constraints established in Plans 25-02/03/04. ClientsSyncService (Plan 16) `findOrCreate` provides race-safety. No threat flags.

## Follow-up

- [ ] User reviews dev verification numbers above
- [ ] User runs production dryrun SQL → reviews stats
- [ ] User takes pg_dump snapshot
- [ ] User runs production backfill (Option A or B)
- [ ] User runs production postcheck SQL → confirms expected deltas
- [ ] User runs production smoke test (cross-store Kim, jung ho identity)
- [ ] Plan 18 (Safety Net C: Sequelize hook) — `attachClientsHook` + model `@AfterCreate` hook addition
