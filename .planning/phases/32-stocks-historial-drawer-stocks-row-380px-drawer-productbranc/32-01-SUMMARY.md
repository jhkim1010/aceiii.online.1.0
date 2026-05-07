---
phase: 32-stocks-historial-drawer
plan: "01"
subsystem: api
tags: [reports, stocks, cockpit, historial, raw-sql, postgresql, nestjs, sequelize]

# Dependency graph
requires:
  - phase: 12-reportajes-cockpit
    provides: "Cockpit endpoint convention (/reports/{slug}-cockpit/{detail}) + raw SQL CTE single-connection pattern"
provides:
  - "GET /reports/stocks-cockpit/historial endpoint"
  - "ReportsStocksCockpitService.getHistorial(filters) public method"
  - "HistorialFilters / HistorialRow / HistorialHeader types"
  - "SQL classification rules for stocks.note → 7-way ledger type"
  - "Counterparty branch resolution via regex on movido(out→X)/movido(in←Y) pattern"
  - "audit_logs LEFT JOIN with 'Sistema' fallback for actor display"
affects: [32-02 (frontend drawer wiring), future stock-audit phases]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "PostgreSQL regexp_match for embedded-id parsing (movido(out→X) → branchId)"
    - "CTE with params row + cross-join for parameterized window math"
    - "Promise.all of header+rows raw queries on single sequelize instance"

key-files:
  created: []
  modified:
    - "api-ventago/src/app/reports/reportsStocksCockpit.service.ts"
    - "api-ventago/src/app/reports/reports.controller.ts"

key-decisions:
  - "DB schema reality (size_id/sizes table) honored over plan's name (talle_id/talles) — UI label kept as variantTalleName via column alias"
  - "LIMIT 200 hard-cap per request with hasMore hint instead of cursor pagination"
  - "Two queries (header + rows) via Promise.all rather than one mega-CTE — header reuses pb_id once, rows uses params CTE for window math"

patterns-established:
  - "Stocks ledger 7-way classification: movido_in/movido_out > fallado > corregido > sale > suspend > ingreso > other"
  - "Note prefix stripping: regexp_replace removes 'movido(out→X): ' / 'fallado: ' / 'corregido: ' to expose the human-readable trailing reason"
  - "Audit-logs JOIN with COALESCE(u.name, 'Sistema') matches the production reality where bulk paths skip @Audit"

requirements-completed: []

# Metrics
duration: ~25min
completed: 2026-05-08
---

# Phase 32 Plan 01: Stocks Historial Backend Summary

**Backend stocks-historial drawer endpoint — `GET /reports/stocks-cockpit/historial` returning a 7-way classified ledger timeline (movido/ingreso/fallado/corregido/sale/suspend/other) with counterparty sucursal resolution and `Sistema` audit fallback in a single pool connection.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-05-08T (session start)
- **Completed:** 2026-05-08
- **Tasks:** 2 (service + controller)
- **Files modified:** 2

## Accomplishments

- New `ReportsStocksCockpitService.getHistorial(filters)` returning `{ header, rows, hasMore }` with full SQL classification (no client-side note parsing required)
- New `GET /reports/stocks-cockpit/historial` endpoint protected by `@FunctionGuard('reporte-stocks', 'read')`, accepting either `productBranchId` or `productId+branchId` plus `days` (default 30) + `offset` (default 0)
- Window math via CTE-bound params (`offset` and `offset+days` interval bounds) — D-03 1..365 day clamp applied
- Counterparty branch name resolved by regex-extracting the branch id from `movido(out→X)` / `movido(in←Y)` notes and joining `branches`
- Header summary returns `current_stock` (all-time SUM) + `net_delta_30d` (last 30d SUM) + variant identifier (sku, color, talle, branch) for sticky-header rendering
- Header and ledger queries run via `Promise.all` on a single sequelize instance (1 pool connection per drawer open, per Phase 12 pattern)

## Task Commits

1. **Task 1: Add `getHistorial` to `reportsStocksCockpit.service`** — `0626021` (feat)
2. **Task 2: Add `GET /reports/stocks-cockpit/historial` endpoint** — `a77c430` (feat)

## Files Created/Modified

- `api-ventago/src/app/reports/reportsStocksCockpit.service.ts` — Added `HistorialFilters` / `HistorialRow` / `HistorialHeader` types and `async getHistorial(filters)` method with parameterized CTE-based ledger SQL, counterparty branch JOIN, and audit_logs JOIN with `Sistema` fallback. Imported `BadRequestException` from `@nestjs/common`.
- `api-ventago/src/app/reports/reports.controller.ts` — Added `getStocksCockpitHistorial(@Query)` handler immediately after `postStocksCockpitAdjust`, reusing the already-injected `reportsStocksCockpitService` and the existing `@FunctionGuard('reporte-stocks', 'read')` decorator.

## Final SQL Shape

**Header SQL** (`reportsStocksCockpit.service.ts` line ~810):
```sql
SELECT pb.id, pb.product_id, pb.branch_id, b.name AS branch_name,
       p.name, p.sku, col.name AS variant_color_name, sz.name AS variant_talle_name,
       COALESCE((SELECT SUM(stock) FROM stocks WHERE product_branch_id = pb.id), 0) AS current_stock,
       COALESCE((SELECT SUM(stock) FROM stocks WHERE product_branch_id = pb.id
                 AND created_at >= NOW() - INTERVAL '30 days'), 0) AS net_delta_30d
FROM "ProductBranch" pb
JOIN products p ON p.id = pb.product_id
LEFT JOIN branches b ON b.id = pb.branch_id
LEFT JOIN colors col ON col.id = p.color_id
LEFT JOIN sizes sz ON sz.id = p.size_id
WHERE pb.id = :pbId LIMIT 1;
```

**Rows SQL** (line ~840) — CTE-based window + classification:
```sql
WITH params AS (SELECT :pbId AS pb_id, :offset AS p_offset, :days AS p_days),
parsed AS (
  SELECT s.id, s.created_at, s.operation_date, s.stock, s.type, s.note,
         CASE
           WHEN s.note ~ '^movido\(out→[0-9]+\)' THEN 'movido_out'
           WHEN s.note ~ '^movido\(in←[0-9]+\)'  THEN 'movido_in'
           WHEN s.note ~ '^fallado'              THEN 'fallado'
           WHEN s.note ~ '^corregido'            THEN 'corregido'
           WHEN s.type = 'sale'                  THEN 'sale'
           WHEN s.type = 'suspend'               THEN 'suspend'
           WHEN s.stock > 0                      THEN 'ingreso'
           ELSE 'other'
         END AS classification,
         (regexp_match(s.note, '^movido\((?:out→|in←)([0-9]+)\)'))[1]::int AS counterparty_branch_id,
         /* note_clean strip-prefix logic ... */
  FROM stocks s, params
  WHERE s.product_branch_id = params.pb_id
    AND s.created_at <  NOW() - (params.p_offset || ' days')::interval
    AND s.created_at >= NOW() - ((params.p_offset + params.p_days) || ' days')::interval
)
SELECT pr.*, cb.name AS counterparty_branch_name,
       al.user_id, COALESCE(u.name, 'Sistema') AS user_name
FROM parsed pr
LEFT JOIN branches cb ON cb.id = pr.counterparty_branch_id
LEFT JOIN audit_logs al ON al.entity_type = 'stock' AND al.entity_id = pr.id
LEFT JOIN users u ON u.id = al.user_id
ORDER BY pr.created_at DESC, pr.id DESC
LIMIT 200;
```

## Classification Rules (5 patterns + 2 type-fallbacks + 1 catch-all)

| Pattern | Trigger | Output | Counterparty? |
|---------|---------|--------|---------------|
| `^movido\(out→[0-9]+\)` | note prefix | `movido_out` | yes (regex extract) |
| `^movido\(in←[0-9]+\)` | note prefix | `movido_in` | yes (regex extract) |
| `^fallado` | note prefix | `fallado` | no |
| `^corregido` | note prefix | `corregido` | no |
| `s.type = 'sale'` | type column | `sale` | no |
| `s.type = 'suspend'` | type column (Reserved hold/release) | `suspend` | no |
| `s.stock > 0` (no prefix) | positive delta | `ingreso` | no |
| else | catch-all | `other` | no |

## Decisions Made

- **Schema reality over plan SQL** (Rule 1 deviation, see below) — products table uses `size_id` referring to `sizes` table, not `talle_id`/`talles`. Plan SQL would have failed at runtime; fixed at SQL level while keeping `variantTalleName` as the contract field name (the UI/Spanish-domain label) via column alias.
- **No standalone migration** — endpoint is read-only, no schema changes, `audit_logs` index `(entity_type, entity_id)` already exists per `audit-log.model.ts`.
- **`Sistema` user fallback** — production currently has zero `audit_logs` rows for `entity_type='stock'` (bulk movido/fallado/corregido paths skip the `@Audit` decorator). The COALESCE is therefore the norm, not the exception. A future audit-backfill phase is captured in `<deferred>` (Phase 22+).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Bug] Replaced `talles tal ON tal.id = p.talle_id` with `sizes sz ON sz.id = p.size_id`**
- **Found during:** Task 1 (writing the header SQL)
- **Issue:** Plan's SQL referenced `talles` table and `p.talle_id` column. Schema verification (psql `information_schema.columns`) confirmed: `products` has `size_id` (not `talle_id`), and the reference table is `sizes` (no `talles` table exists). The existing `getMatrix` method in the same file already uses the correct `sizes sz ON sz.id = p.size_id` pattern.
- **Fix:** Updated header SQL to `LEFT JOIN sizes sz ON sz.id = p.size_id` and aliased `sz.name AS variant_talle_name` so the UI-facing contract field name (`variantTalleName`) is preserved while the underlying SQL uses real schema.
- **Files modified:** `api-ventago/src/app/reports/reportsStocksCockpit.service.ts`
- **Verification:** Smoke-tested header SQL on local ventago DB with `pb.id=99` — returned `variant_color_name=GRIS, variant_talle_name=XS, current_stock=26` (real data).
- **Committed in:** `0626021` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** The fix was required for runtime correctness; SQL would have raised `relation "talles" does not exist` on first call. No scope creep.

## Issues Encountered

- ESLint typed-rules (`@typescript-eslint/no-unsafe-member-access`, `no-unsafe-assignment`) emit ~12 net new warnings on the new method's `query<any>(...)` row mapping. **These are pre-existing patterns in the same file (138 baseline errors of identical kind on `getCockpit`/`getStocks`/`getMatrix`/etc.)** — the project clearly does not block CI on these typed warnings. CLAUDE.md's listed blocking rules (`newline-before-return`, `lines-around-comment`, `no-unused-vars`) are all clean. `npx tsc --noEmit` exits 0.

## Verification

**TypeScript:** `cd api-ventago && npx tsc --noEmit -p tsconfig.json` → 0 errors.

**Acceptance grep:**
```
grep -c "async getHistorial"        ... 1 ✓
grep -c "type HistorialFilters"     ... 1 ✓
grep -c "audit_logs"                ... 3 (≥1 required) ✓
grep -c "movido"                    ... 7 occurrences ✓
grep -c "Sistema"                   ... 3 (≥1 required) ✓
grep -c "stocks-cockpit/historial"  ... 1 ✓
grep -c "getStocksCockpitHistorial" ... 1 ✓
grep -cE "@FunctionGuard\('reporte-stocks', 'read'\)" ... 10 (≥6 required) ✓
```

**SQL smoke-tests against local DB:**
- `pb.id=99` (11 stock rows): returned 10 rows, classifications include `suspend`, `other` — JOINs and `Sistema` fallback working.
- `pb.id=292` (2 movido rows): returned `movido_out` × 2 with `counterparty_branch_id=10/11` resolved to `HELGUERA` / `DEPOSITO (FABRICA)` — counterparty regex+JOIN working.

**Curl smoke-test:** Not executed in this session because dev API server is not running; endpoint is registered (TSC verifies the decorator + route binding) and TypeScript signatures match the contract. Frontend wiring (Plan 32-02) will exercise the live endpoint.

## Next Phase Readiness

- Endpoint contract is locked: `{ header: HistorialHeader | null, rows: HistorialRow[], hasMore: boolean }`
- Plan 32-02 (frontend drawer) can consume this directly with no backend changes anticipated
- Future audit-backfill phase deferred (per `32-CONTEXT.md` `<deferred>`)

## Self-Check: PASSED

**Commits verified:**
```
0626021 feat(32-01): add getHistorial to reportsStocksCockpit.service  ✓
a77c430 feat(32-01): add GET /reports/stocks-cockpit/historial endpoint ✓
```

**Files verified:**
- `api-ventago/src/app/reports/reportsStocksCockpit.service.ts` — FOUND, contains `async getHistorial`, `type HistorialFilters`, `audit_logs`, regex patterns, `Sistema` fallback
- `api-ventago/src/app/reports/reports.controller.ts` — FOUND, contains `stocks-cockpit/historial`, `getStocksCockpitHistorial`, `@FunctionGuard('reporte-stocks', 'read')`

---
*Phase: 32-stocks-historial-drawer*
*Completed: 2026-05-08*
