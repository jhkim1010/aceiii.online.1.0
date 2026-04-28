---
phase: 26-gastos-categoria-tree-n-niveles
plan: "04"
subsystem: full-stack
tags: [nextjs, nestjs, swr, mui, sequelize, recursive-cte, expense-tree, mru, tdd, korean-ime]
checkpoint_status: pending human verification (Task 26-04-05)
dependency_graph:
  requires:
    - ExpenseCategoryController + tree endpoint (Wave 2)
    - expense_categories table + path/depth triggers (Wave 1)
    - expenses.category_id FK column (Wave 1)
    - useExpenseCategoryTree SWR hook (Wave 3)
    - buildTreeFromFlat / multiKeywordPathMatch utils (Wave 3)
  provides:
    - CategoryTreeSelector frontend component (search/MRU/inline create)
    - GET /reports/gastos/by-category recursive CTE rollup endpoint
    - GastoRollupQueryDto with IsIn whitelist guard
    - GastosByCategoryReport widget + DepthSelector toggle
    - ExpenseCategory association on Expenses model
  affects:
    - ventago-app/src/views/expenses/components/ExpenseModal.tsx
    - ventago-app/src/views/expenses/components/DataConfig.tsx
    - ventago-app/src/views/reports/gastos/GastoCockpitBody.tsx
    - api-ventago/src/app/expenses/expenses.model.ts
    - api-ventago/src/app/expenses/expenses.module.ts
    - api-ventago/src/app/expenses/expenses.service.ts
    - api-ventago/src/app/expenses/dto/create-expenses.dto.ts
    - api-ventago/src/app/reports/reportsGasto.service.ts
    - api-ventago/src/app/reports/reports.controller.ts
    - api-ventago/src/app/reports/reportsGastoCockpit.service.ts
tech_stack:
  added: []
  patterns:
    - SWR 5-min dedup with depth toggle key
    - localStorage MRU per user x store
    - Korean IME isComposing guard on search input
    - Sequelize underscored snake_case mapping in raw SQL
    - WITH RECURSIVE ancestor_chain CTE with DISTINCT ON rollup
    - Optional Sequelize injection (jest mock-friendly constructor)
    - TDD RED -> GREEN with jest.mock query (no real DB)
key_files:
  created:
    - ventago-app/src/views/gastos/components/CategoryTreeSelector.tsx
    - ventago-app/src/views/gastos/components/CategoryTreeSelector.utils.ts
    - api-ventago/src/app/reports/dto/gasto-rollup-query.dto.ts
    - api-ventago/src/app/reports/reportsGastoRollup.spec.ts
    - ventago-app/src/views/reports/gastos/GastosByCategoryReport.tsx
    - ventago-app/src/views/reports/gastos/components/DepthSelector.tsx
  modified:
    - ventago-app/src/views/expenses/components/ExpenseModal.tsx
    - ventago-app/src/views/expenses/components/DataConfig.tsx
    - ventago-app/src/views/reports/gastos/GastoCockpitBody.tsx
    - api-ventago/src/app/expenses/expenses.model.ts
    - api-ventago/src/app/expenses/expenses.module.ts
    - api-ventago/src/app/expenses/expenses.service.ts
    - api-ventago/src/app/expenses/dto/create-expenses.dto.ts
    - api-ventago/src/app/reports/reportsGasto.service.ts
    - api-ventago/src/app/reports/reports.controller.ts
    - api-ventago/src/app/reports/reportsGastoCockpit.service.ts
    - api-ventago/src/app/auth/auth.module.ts
    - api-ventago/src/app/auth/auth.service.ts
decisions:
  - "Spec file placed under src/app/reports/ (jest rootDir=src + testRegex=*.spec.ts) — same as Wave 2 ExpenseCategoryService spec, not under api-ventago/test/"
  - "ReportsGastoService.constructor with sequelize? optional — preserves existing instantiation (Excel-only generalReport call sites unchanged) while letting NestJS DI inject the real Sequelize at runtime"
  - "depth='all' maps to depthLimit=5 (leaf preserved) — RECURSIVE CTE uses anc_parent_id chain with DISTINCT ON (leaf_id) ORDER BY anc_depth DESC to pick the deepest ancestor still <= depthLimit"
  - "Cockpit's existing top-N flat 8-row breakdown preserved unchanged (RESEARCH §6 Q6) — new rollup card is additive, not a replacement"
  - "DataConfig.tsx column renderer falls back to legacy expensesSubcategory.category > subcategory string when expenseCategory.path is missing — maintains display continuity for any expenses still wholly on the legacy column"
  - "ExpenseModal sends expensesSubcategoryId: null on every submit (Wave 5 drop prep) — backend DTO accepts both fields as optional"
  - "MRU localStorage key format: expense_category_mru_user_${userId}_store_${storeId} — matches CONTEXT D4.2"
  - "DepthSelector default = '2' (matches plan must_have); switching does not refetch tree, only the rollup endpoint"
metrics:
  duration: ~28min (tasks 1-4)
  completed_date: "2026-04-28"
  tasks_completed: 4
  tasks_total: 5
  files_created: 6
  files_modified: 11
---

# Phase 26 Plan 04: Gasto Form + Reports Tree Rollup Summary

**One-liner:** CategoryTreeSelector with search/MRU/inline create wired into ExpenseModal + recursive CTE rollup endpoint + depth-toggle reports widget — backend boots, frontend builds, 6/6 jest specs green; manual UI verification pending (Task 26-04-05).

---

## Tasks Completed

| Task | Name | Commits | Files |
|------|------|---------|-------|
| 26-04-01 | CategoryTreeSelector + utils | ventago-app:9b149d5 / outer:1601cff | CategoryTreeSelector.tsx + utils.ts |
| 26-04-02 | ExpenseModal + ExpensesListView migration | api-ventago:ca6c651 / ventago-app:566168a / outer:57b616d | ExpenseModal.tsx, DataConfig.tsx, expenses.model.ts, expenses.module.ts, expenses.service.ts, create-expenses.dto.ts, auth.module/service.ts |
| 26-04-03 | Backend reports rollup CTE (TDD) | api-ventago:1cc6e1c (RED) + 49c6ea1 (GREEN) / outer:8adccd7 | reportsGastoRollup.spec.ts, reportsGasto.service.ts, reports.controller.ts, gasto-rollup-query.dto.ts, reportsGastoCockpit.service.ts |
| 26-04-04 | Reports UI depth toggle + rollup widget | ventago-app:dba42d1 / outer:126b002 | GastosByCategoryReport.tsx, DepthSelector.tsx, GastoCockpitBody.tsx |

## Pending

| Task | Name | Status |
|------|------|--------|
| 26-04-05 | Manual integration verification | checkpoint:human-verify — awaiting approval |

---

## Verification Results

- **api-ventago `npm run build`**: PASSED (nest build, 0 TS errors)
- **api-ventago `npx jest reportsGastoRollup`**: PASSED 6/6
  - depth=1 rollup to root
  - depth=5 leaf preserved (Móvil path intact)
  - depth='all' equivalent to 5 (depthLimit=5)
  - depth=2 mid-tier rollup
  - branchId filter passthrough
  - branchId null passthrough
- **ventago-app `npm run build`**: PASSED (Next.js 13 build, 0 ESLint errors in new files)
- **ESLint**: 0 errors. Pre-existing react-hooks/exhaustive-deps warnings in unrelated files.

---

## Architecture Highlights

### CategoryTreeSelector

```typescript
<CategoryTreeSelector
  value={form.watch('categoryId') ?? null}
  onChange={(id) => setValue('categoryId', id)}
  userId={user.id}
  storeId={user.storeId}
  required
  label="Categoría"
/>
```

- Click box → MUI Popover opens (360px wide, 480px max-height)
- Search input with `isComposing` Korean IME guard
- "Recientes" section (top 5 from localStorage MRU) when search empty
- Multi-keyword AND filter on `${path} ${name}` haystack
- "Crear ... en..." button when search has text → opens parent-picker dialog (filters depth < 5)

### Recursive CTE rollup SQL

```sql
WITH RECURSIVE ec AS (...),
ancestor_chain AS (
  SELECT id AS leaf_id, id AS anc_id, depth AS anc_depth, path AS anc_path, parent_id AS anc_parent_id
    FROM ec
  UNION ALL
  SELECT ac.leaf_id, p.id, p.depth, p.path, p.parent_id
    FROM ancestor_chain ac
    JOIN ec p ON p.id = ac.anc_parent_id
   WHERE ac.anc_parent_id IS NOT NULL
),
rollup_map AS (
  SELECT DISTINCT ON (leaf_id) leaf_id, anc_id AS rollup_id, anc_path, anc_depth
    FROM ancestor_chain
   WHERE anc_depth <= :depthLimit
   ORDER BY leaf_id, anc_depth DESC
)
SELECT rm.rollup_id, rm.rollup_path, rm.rollup_depth, SUM(e.amount), COUNT(*)
  FROM expenses e JOIN rollup_map rm ON rm.leaf_id = e.category_id
 WHERE e.store_id = :storeId AND ...
 GROUP BY rm.rollup_id, rm.rollup_path, rm.rollup_depth
 ORDER BY "totalAmount" DESC
```

PG10 + PG15 호환. 모든 변수는 `:replacements` 로 binding (T-26-16 SQL injection 방지).

### Endpoint

```
GET /reports/gastos/by-category?startDate=YYYY-MM-DD&endDate=YYYY-MM-DD&branchId=N&depth=1|2|3|4|5|all
Authorization: admin / superadmin / gerente
Response: [{ categoryId, categoryPath, depth, totalAmount, expenseCount }, ...]  // sorted totalAmount DESC
```

### DepthSelector + Reports widget

- 6-option ToggleButtonGroup (1, 2, 3, 4, 5, Todas) — default '2'
- Indented rows by `depth` via `pl: 2 + depth * 2`
- % column per row + Total footer row
- SWR key auto-invalidates on depth change (5-min dedup)

---

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Lint] CategoryTreeSelector.tsx: lines-around-comment failure**
- **Found during:** Task 26-04-01 first build
- **Issue:** `useMemo` mid-block `// anchor 가 dependency...` comment had no preceding blank line, violating ESLint `lines-around-comment`.
- **Fix:** Restructured the `mruIds` `useMemo` so the comment line has a blank line above it.
- **Files modified:** CategoryTreeSelector.tsx
- **Commit:** 9b149d5 (initial)

**2. [Rule 3 - Blocking] Spec file placement for Task 26-04-03**
- **Found during:** Task 26-04-03 TDD RED preflight
- **Issue:** Plan suggested `api-ventago/test/reports-gasto-rollup.spec.ts` but jest config in package.json sets `rootDir=src` and `testRegex=*.spec.ts$` — anything under `test/` would not be discovered.
- **Fix:** Moved spec to `src/app/reports/reportsGastoRollup.spec.ts` (same convention as Wave 2 `expense-category.service.spec.ts`).
- **Commit:** 1cc6e1c

**3. [Rule 2 - Critical] Sequelize injection on ReportsGastoService**
- **Found during:** Task 26-04-03 service implementation
- **Issue:** Existing `ReportsGastoService` constructor only injected `ExcelService`. New `getByCategoryRollup` requires raw SQL via Sequelize.
- **Fix:** Added optional `private readonly sequelize?: Sequelize` parameter. NestJS DI auto-wires the global Sequelize when running in container; jest mock can inject any object via `(service as any).sequelize = mock`.
- **Files modified:** reportsGasto.service.ts
- **Commit:** 49c6ea1

**4. [Rule 1 - Bug] DataConfig column renderer left dangling fallback**
- **Found during:** Task 26-04-02 (data display continuity)
- **Issue:** Plan suggested simple `params.row.expenseCategory?.path ?? '(Sin categoría)'`. But pre-existing rows that haven't been backfilled cleanly might still surface only via `expensesSubcategory`.
- **Fix:** Renderer now does `expenseCategory.path ?? (legacy join string) ?? '(Sin categoría)'` — preserves correct display through any partial data state.
- **Files modified:** DataConfig.tsx
- **Commit:** 566168a

### Pre-existing changes carried in commit ca6c651
- `src/app/auth/auth.module.ts` and `src/app/auth/auth.service.ts` had pending modifications from a prior AuthModule DI fix (ownerGroupId via StoreService) — unstaged before Task 2 began. Carried in the Task 2 commit since they're required for backend to boot. Documented in commit message as "pre-existing AuthModule DI fix".

---

## Rollback Notes for Wave 5

When Wave 5 drops `expenses_subcategory_id`:
1. Remove `expensesSubcategoryId` field from `Expenses` model + `ExpensesSubcategories` association
2. Remove from `expenses/dto/create-expenses.dto.ts`
3. Remove ExpenseModal payload override (`expensesSubcategoryId: null`)
4. Remove DataConfig column fallback chain — keep only `expenseCategory.path`
5. Remove the `LEFT JOIN expenses_subcategories sc` in `reportsGastoCockpit.service.ts` (3 SQL blocks) and replace with `LEFT JOIN expense_categories ON expense_categories.id = e.category_id`
6. Drop `expenses_subcategory_id` column DDL (after backfill verification)
7. `_phase26_cat_map` table cleanup (per Phase 26 STATE.md decision)

---

## Known Stubs

None. CategoryTreeSelector wires to live `/expense-categories/tree` SWR endpoint, real `apiConnector.post('/expense-categories', ...)` for inline create, real `useSWR('/reports/gastos/by-category')` in the rollup widget. Backend rollup uses the actual `expenses.category_id + expense_categories` data — no mock data path remains in production code.

---

## Threat Flags

None beyond plan threat model.
- T-26-16 (SQL injection on depth) → mitigated: `IsIn(['1','2','3','4','5','all'])` whitelist + sequelize replacements
- T-26-17 (cross-store reports) → mitigated: `service.getByCategoryRollup(user.storeId!, ...)` enforces JWT-derived storeId
- T-26-18 (CTE perf) → accepted: ~30 nodes/store, idx_expenses_category active
- T-26-19 (MRU tampering) → accepted: UX boost only, backend ignores

---

## Next Steps for Human Verifier (Task 26-04-05)

**Environment startup:**

```bash
# Start backend (separate terminal)
cd /Users/marcoskim/Trabajos_Programming/ACE_online_1.0/api-ventago
npm run start:dev   # http://localhost:5002/api

# Start frontend (separate terminal)
cd /Users/marcoskim/Trabajos_Programming/ACE_online_1.0/ventago-app
npm run dev         # http://localhost:3050
```

**Verification checklist (resume signal: "approved" or list issues):**

1. **Login** — admin or superadmin user.
2. **Gasto 등록** (페이지: `/gastos`)
   - "Crear" 버튼 클릭 → Crear gasto 모달 열림
   - "Categoría" 박스 클릭 → 패널 펼쳐짐
   - 빈 검색 → "Todas las categorías" 에 평면 path 리스트 보임 (Servicios, Comida, Transporte 등)
   - "serv" 입력 → "Servicios" 매칭만 보임
   - "serv internet" 입력 → "Servicios > Internet" + 자손 노드 매칭
   - 존재하지 않는 키워드 ("zzz xyz") → "Sin resultados" 박스 + 하단 [Crear "zzz xyz" en...] 버튼 노출
   - 버튼 클릭 → 부모 선택 다이얼로그 열림 → "(Raíz)" 또는 기존 노드 선택 가능 (depth ≥5 필터됨) → "Crear" → 성공 토스트 "Categoría creada" + 자동 선택됨
   - 비용 저장 → "Gasto creado" 토스트
3. **MRU 동작 확인**
   - 같은 모달 다시 열기 → "Recientes" 섹션에 방금 선택한 카테고리 path 보임
   - 다른 카테고리 선택 → 다음 모달에서 그것이 Recientes 최상단으로 (선입선출)
   - 브라우저 localStorage 에 키 `expense_category_mru_user_<userId>_store_<storeId>` 가 JSON 배열로 저장됨
4. **Gasto 리스트 컬럼**
   - `/gastos` 화면의 "Categoría" 컬럼이 한 줄 path (예: "Servicios > Internet > Móvil")
   - 기존 expense (legacy 마이그레이션됨) 도 정상 표시
5. **편집 흐름**
   - 기존 expense의 연필 아이콘 → 모달 → 카테고리 변경 → 저장 → 리스트에서 새 path 표시
6. **Reports**
   - `/reportes/gastos` (또는 cockpit 진입 경로) 이동
   - KPI strip 아래 새 카드 "Gastos por categoría (rollup)" 노출
   - 기본 depth 토글이 "2" 선택됨
   - "1" 클릭 → 모든 expense 가 루트(Servicios, Comida 등)로 롤업, 행 수 줄어듦
   - "Todas" 클릭 → leaf 노드 path 그대로, 행 수 가장 많음
   - 합계 행 100%, 행마다 % 정확히 계산 (e.g., 30%, 25%, ...)
   - depth 변경 시 SWR 가 재조회 (네트워크 탭에서 `/reports/gastos/by-category?depth=N` 확인 가능)
7. **회귀 검증**
   - 기존 GastoCockpit 의 "Por Categoría" 랭킹 (top-N 플랫) 이 그대로 보임 (Wave 4 신규 카드와 별개로)
   - 기존 트렌드 차트, KPI 모두 정상
8. **다른 매장 (superadmin)**
   - 매장 전환 → MRU 가 새 매장 ID 의 키로 자동 분리 (이전 매장 MRU 노출 안 됨)
9. **에러 케이스**
   - inline create 에서 같은 부모에 같은 이름 두 번 시도 → 에러 토스트 "같은 부모 밑에 동명 카테고리가 이미 존재합니다"

---

## Self-Check

### Files Verified

- `ventago-app/src/views/gastos/components/CategoryTreeSelector.tsx` — FOUND
- `ventago-app/src/views/gastos/components/CategoryTreeSelector.utils.ts` — FOUND
- `ventago-app/src/views/expenses/components/ExpenseModal.tsx` — FOUND
- `ventago-app/src/views/expenses/components/DataConfig.tsx` — FOUND
- `api-ventago/src/app/reports/dto/gasto-rollup-query.dto.ts` — FOUND
- `api-ventago/src/app/reports/reportsGasto.service.ts` — FOUND (modified)
- `api-ventago/src/app/reports/reports.controller.ts` — FOUND (modified)
- `api-ventago/src/app/reports/reportsGastoRollup.spec.ts` — FOUND
- `ventago-app/src/views/reports/gastos/GastosByCategoryReport.tsx` — FOUND
- `ventago-app/src/views/reports/gastos/components/DepthSelector.tsx` — FOUND
- `api-ventago/src/app/expenses/expenses.model.ts` — FOUND (modified)
- `api-ventago/src/app/expenses/expenses.module.ts` — FOUND (modified)
- `api-ventago/src/app/expenses/expenses.service.ts` — FOUND (modified)
- `api-ventago/src/app/expenses/dto/create-expenses.dto.ts` — FOUND (modified)

### Commits Verified

**ventago-app:**
- `9b149d5` feat(phase-26-04): add CategoryTreeSelector with search/MRU/inline create
- `566168a` feat(phase-26-04): migrate ExpenseModal + list to CategoryTreeSelector
- `dba42d1` feat(phase-26-04): add GastosByCategoryReport with depth toggle + integrate into cockpit

**api-ventago:**
- `ca6c651` feat(phase-26-04): wire ExpenseCategory association into expenses + persist categoryId
- `1cc6e1c` test(phase-26-04): add failing spec for getByCategoryRollup CTE rollup
- `49c6ea1` feat(phase-26-04): add /reports/gastos/by-category recursive CTE rollup endpoint

**Outer repo bumps:**
- `1601cff` chore: bump ventago-app for phase 26 wave 4 task 1 (CategoryTreeSelector)
- `57b616d` chore: bump api-ventago + ventago-app for phase 26 wave 4 task 2 (expense tree migration)
- `8adccd7` chore: bump api-ventago for phase 26 wave 4 task 3 (gastos rollup CTE endpoint + tests)
- `126b002` chore: bump ventago-app for phase 26 wave 4 task 4 (depth toggle reports UI)

## Self-Check: PASSED

All target files exist, all 10 commits in git history, builds green, jest spec 6/6 green.
Checkpoint Task 26-04-05 awaits human approval.
