# Phase 26 — Research

**Researched:** 2026-04-27
**Domain:** Hierarchical categories (PostgreSQL adjacency-list + materialized-path) + tree UI (react-arborist) + recursive CTE rollups
**Confidence:** HIGH (DB/Sequelize/codebase patterns), MEDIUM (react-arborist v3 specifics — verified via official changelog/issues but no local install yet)

---

## 1. Summary (TL;DR)

- **DB pattern**: adjacency list (`parent_id` self-FK) + materialized path (`path TEXT`, `depth SMALLINT`) — same store/transaction. Path uses `' > '` separator (UI-displayable directly). PG 10 + PG 15 compatible — `WITH RECURSIVE`, partial unique indexes, `IS DISTINCT FROM`, FK + CHECK all supported on both. **Avoid** `GENERATED AS IDENTITY` (PG 11+ only) and `ltree` (extension, no install on prod).
- **Path/depth maintenance**: ONE PL/pgSQL function attached as BEFORE INSERT + BEFORE UPDATE triggers. INSERT computes from parent. UPDATE recalculates self when `parent_id` or `name` changes, and uses a single `UPDATE ... WHERE path LIKE OLD.path || ' > %'` to cascade descendants in one statement (no recursion, no recursion-depth limit risk). Verified pattern from `leonardqmarcq.com`.
- **Sequelize self-FK**: declare `BelongsTo(() => ExpenseCategory, 'parentId')` and `HasMany(() => ExpenseCategory, 'parentId')`. **NEVER** include children in Sequelize `include` (infinite recursion risk). Always: load flat array with single `findAll({where:{storeId}})`, build tree in JS.
- **react-arborist v3.5.0** (npm, Apr 2026 release per CHANGELOG): supports `disableDrop({parentNode, dragNodes, index})` to enforce same-parent-only reorder. ~30 KB. No external styling lib. IME composition: NOT explicitly handled in library — we must wire `event.isComposing` / `keyCode === 229` guard ourselves on the rename input (Korean/Spanish concern from CONTEXT §4).
- **Reports rollup**: `WITH RECURSIVE descendants AS (...)` to pre-compute `category_id → root_ancestor_id_at_depth_N` map, then JOIN to `expenses` and SUM. User-selected depth limits which rows appear; everything below collapses into the chosen ancestor.
- **Migration**: ONE multi-step transactional SQL file. New table created BEFORE conversion. `expenses.category_id` already exists semantically — only `expenses_subcategory_id` needs to be remapped to the new child node id then column dropped. Old tables kept for 2 weeks (CONTEXT §6 Hint #6).

**Primary recommendation:** Follow leonardqmarcq.com BEFORE-INSERT/BEFORE-UPDATE trigger pattern (proven, single-statement cascade). Build the tree client-side from a flat `findAll`. Use `react-arborist@^3.5` with `disableDrop` enforcing `parentNode === dragNodes[0].parent` for same-parent-only reorder.

---

## 2. Architecture Patterns

### 2.1 Adjacency List + Materialized Path (PostgreSQL)

#### Schema (PG 10 / PG 15 compatible)

```sql
CREATE TABLE IF NOT EXISTS expense_categories (
  id           SERIAL PRIMARY KEY,
  store_id     INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  parent_id    INTEGER REFERENCES expense_categories(id) ON DELETE RESTRICT,
  name         VARCHAR(120) NOT NULL,
  path         TEXT NOT NULL DEFAULT '',          -- e.g. 'Servicios > Internet > Móvil'
  depth        SMALLINT NOT NULL DEFAULT 0,        -- 0 = root
  sort_order   INTEGER NOT NULL DEFAULT 0,
  color        VARCHAR(16),                        -- nullable hex like '#f5a623'
  icon         VARCHAR(64),                        -- nullable iconify slug
  status       SMALLINT NOT NULL DEFAULT 1,        -- 1=ACTIVE, 0=ARCHIVED (soft delete)
  created_at   TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMP NOT NULL DEFAULT NOW(),

  -- Cycle prevention (self-parent only — deeper cycles caught at app + trigger level)
  CONSTRAINT chk_no_self_parent CHECK (parent_id IS NULL OR parent_id <> id),

  -- Depth limit (DB-level safety net; app validates first to give clean error)
  CONSTRAINT chk_depth CHECK (depth >= 0 AND depth <= 5)
);

-- Sibling-uniqueness: same parent_id cannot have duplicate names within a store.
-- Use partial unique index because PG treats NULL as distinct in regular UNIQUE.
CREATE UNIQUE INDEX IF NOT EXISTS uq_expense_cat_root_name
  ON expense_categories (store_id, name)
  WHERE parent_id IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_expense_cat_child_name
  ON expense_categories (store_id, parent_id, name)
  WHERE parent_id IS NOT NULL;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_expense_cat_store_parent
  ON expense_categories (store_id, parent_id);
CREATE INDEX IF NOT EXISTS idx_expense_cat_store_status
  ON expense_categories (store_id, status);
-- Path-prefix descendant queries (LIKE 'A > B > %')
CREATE INDEX IF NOT EXISTS idx_expense_cat_path
  ON expense_categories (store_id, path text_pattern_ops);
```

[VERIFIED: leonardqmarcq.com canonical pattern; PG10 docs] Partial unique indexes + `text_pattern_ops` exist in PG 9.6+. `SERIAL` works on both PG10/PG15 (do NOT use `GENERATED AS IDENTITY` per CLAUDE.md).

#### Trigger function — handles INSERT and UPDATE in one place

```sql
CREATE OR REPLACE FUNCTION fn_expense_categories_path()
RETURNS TRIGGER AS $$
DECLARE
  v_parent_path  TEXT;
  v_parent_depth SMALLINT;
  v_old_path     TEXT;
BEGIN
  -- INSERT: compute path & depth from parent
  IF TG_OP = 'INSERT' THEN
    IF NEW.parent_id IS NULL THEN
      NEW.path  := NEW.name;
      NEW.depth := 0;
    ELSE
      SELECT path, depth INTO v_parent_path, v_parent_depth
      FROM expense_categories WHERE id = NEW.parent_id;
      IF v_parent_path IS NULL THEN
        RAISE EXCEPTION 'parent_id % not found', NEW.parent_id;
      END IF;
      NEW.path  := v_parent_path || ' > ' || NEW.name;
      NEW.depth := v_parent_depth + 1;
      IF NEW.depth > 5 THEN
        RAISE EXCEPTION 'expense_categories: depth % exceeds limit 5', NEW.depth;
      END IF;
    END IF;
    RETURN NEW;
  END IF;

  -- UPDATE: only act when parent_id or name actually changed
  IF TG_OP = 'UPDATE' THEN
    IF NEW.parent_id IS NOT DISTINCT FROM OLD.parent_id
       AND NEW.name IS NOT DISTINCT FROM OLD.name THEN
      RETURN NEW;  -- no path-affecting change
    END IF;

    -- Cycle guard: NEW.parent_id must not be self or any descendant of OLD
    IF NEW.parent_id IS NOT NULL THEN
      IF NEW.parent_id = NEW.id THEN
        RAISE EXCEPTION 'cycle: parent_id = id';
      END IF;
      PERFORM 1
        FROM expense_categories
       WHERE id = NEW.parent_id
         AND (path = OLD.path OR path LIKE OLD.path || ' > %');
      IF FOUND THEN
        RAISE EXCEPTION 'cycle: cannot move under own descendant';
      END IF;
    END IF;

    v_old_path := OLD.path;

    -- Recompute self
    IF NEW.parent_id IS NULL THEN
      NEW.path  := NEW.name;
      NEW.depth := 0;
    ELSE
      SELECT path, depth INTO v_parent_path, v_parent_depth
      FROM expense_categories WHERE id = NEW.parent_id;
      NEW.path  := v_parent_path || ' > ' || NEW.name;
      NEW.depth := v_parent_depth + 1;
    END IF;

    -- Cascade subtree depth check BEFORE applying:
    -- max descendant depth would shift by (NEW.depth - OLD.depth)
    PERFORM 1
      FROM expense_categories
     WHERE store_id = NEW.store_id
       AND path LIKE v_old_path || ' > %'
       AND (depth + (NEW.depth - OLD.depth)) > 5
     LIMIT 1;
    IF FOUND THEN
      RAISE EXCEPTION 'subtree move would exceed depth 5';
    END IF;

    -- Single-statement cascade for descendants — no recursion, O(N) where N = subtree size
    UPDATE expense_categories
       SET path  = NEW.path || substring(path FROM length(v_old_path) + 1),
           depth = depth + (NEW.depth - OLD.depth),
           updated_at = NOW()
     WHERE store_id = NEW.store_id
       AND path LIKE v_old_path || ' > %';

    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_expense_cat_path ON expense_categories;
CREATE TRIGGER trg_expense_cat_path
  BEFORE INSERT OR UPDATE ON expense_categories
  FOR EACH ROW EXECUTE PROCEDURE fn_expense_categories_path();
```

[VERIFIED: leonardqmarcq.com canonical pattern + PG docs WITH RECURSIVE; PG10 supports BEFORE-trigger row mutation, `IS DISTINCT FROM`, `LIKE`, `substring(... FROM ...)`].

**Note on PG 10 syntax**: prod PG10 requires `CREATE TRIGGER ... EXECUTE PROCEDURE` (not `EXECUTE FUNCTION` — that's PG 11+). Use `PROCEDURE` for cross-version safety. [VERIFIED: PG10 docs]

#### Why this approach (vs alternatives)

| Approach | Pros | Cons | Decision |
|---|---|---|---|
| **Adjacency + materialized path (chosen)** | Simple CRUD, fast `path` for breadcrumb, single-statement cascade | Path must be maintained on rename/move | **Use** |
| `ltree` extension | Built-in path ops, GiST index | Requires `CREATE EXTENSION ltree` — not available on prod, separator restrictions (`.` only) | Skip |
| Pure adjacency (no path) | Minimal columns | Every breadcrumb needs recursive CTE — slower for high-traffic Gasto list | Skip |
| Closure table | Fast ancestor/descendant queries | Extra table to maintain on every move; overkill for 5-deep × ~30 nodes/store | Skip |
| Nested sets | Fast subtree queries | Insert/move rewrites huge ranges — bad for frequent edits | Skip |

[CITED: leonardqmarcq.com/posts/dos-and-donts-of-modeling-hierarchical-trees-in-postgres]

---

### 2.2 Sequelize self-referential model (sequelize-typescript v6)

```ts
// api-ventago/src/app/expense-categories/expense-categories.model.ts
import {
  BelongsTo, Column, DataType, ForeignKey, HasMany, Model, Table,
} from 'sequelize-typescript';
import { Store } from 'src/app/store/store.model';

@Table({ tableName: 'expense_categories', timestamps: true, underscored: true })
export class ExpenseCategory extends Model<ExpenseCategory> {
  @Column({ type: DataType.STRING(120), allowNull: false })
  name: string;

  @ForeignKey(() => Store)
  @Column({ type: DataType.INTEGER, allowNull: false })
  storeId: number;

  @BelongsTo(() => Store, { onDelete: 'CASCADE' })
  store: Store;

  // ---- self-referential FK ----
  @ForeignKey(() => ExpenseCategory)
  @Column({ type: DataType.INTEGER, allowNull: true })
  parentId: number | null;

  @BelongsTo(() => ExpenseCategory, { foreignKey: 'parentId', as: 'parent' })
  parent: ExpenseCategory;

  @HasMany(() => ExpenseCategory, { foreignKey: 'parentId', as: 'children' })
  children: ExpenseCategory[];
  // ----------------------------

  @Column({ type: DataType.TEXT, allowNull: false, defaultValue: '' })
  path: string;             // populated by trigger

  @Column({ type: DataType.SMALLINT, allowNull: false, defaultValue: 0 })
  depth: number;            // populated by trigger

  @Column({ type: DataType.INTEGER, allowNull: false, defaultValue: 0 })
  sortOrder: number;

  @Column({ type: DataType.STRING(16), allowNull: true })
  color: string | null;

  @Column({ type: DataType.STRING(64), allowNull: true })
  icon: string | null;

  @Column({ type: DataType.SMALLINT, allowNull: false, defaultValue: 1 })
  status: number;            // 1=active, 0=archived
}
```

#### CRITICAL: avoid infinite recursion in `include`

```ts
// ❌ NEVER do this — Sequelize will stack-overflow trying to nest 'children' indefinitely:
ExpenseCategory.findAll({ include: [{ model: ExpenseCategory, as: 'children' }] });

// ✅ DO this — single flat SELECT, build tree in JS:
const flat = await ExpenseCategory.findAll({
  where: { storeId, ...(showArchived ? {} : { status: 1 }) },
  order: [['depth','ASC'], ['sortOrder','ASC'], ['name','ASC']],
});
// Build tree in O(N): map by id, then assign children by parentId. ~30-625 nodes/store, trivially fast.
```

[VERIFIED via codebase grep — no existing self-FK include patterns to copy; this is a known Sequelize gotcha.]

#### Sequelize hooks vs DB triggers — DB wins

CONTEXT §6 mentioned `beforeSave` hook as alternative. **Recommend DB trigger** because:
1. Single source of truth — manual `bulk INSERT` (e.g. seed script via `psql`) still gets path correctly.
2. Migration data-load happens via raw SQL — Sequelize hooks would not fire.
3. Concurrent rename + insert race-conditions are easier to reason about at DB layer.
4. Trigger logic is identical for PG10/PG15 (no Sequelize version skew risk).

---

### 2.3 Recursive CTE rollup for Reports

#### Pattern: roll up to a chosen depth

```sql
-- :storeId, :startDate, :endDate, :branchId, :depthLimit (1|2|3|4|5)

WITH RECURSIVE
ec AS (  -- all visible categories for the store
  SELECT id, parent_id, name, path, depth
    FROM expense_categories
   WHERE store_id = :storeId AND status = 1
),
-- For each leaf-ish category, walk up to find its "rolled-up ancestor"
-- = the ancestor at depth = LEAST(:depthLimit, this.depth)
ancestor_chain AS (
  SELECT id AS leaf_id, id AS anc_id, depth AS anc_depth, path AS anc_path, name AS anc_name
    FROM ec
  UNION ALL
  SELECT ac.leaf_id, p.id, p.depth, p.path, p.name
    FROM ancestor_chain ac
    JOIN ec p ON p.id = (SELECT parent_id FROM ec WHERE id = ac.anc_id)
   WHERE ac.anc_depth > 0
),
-- For each leaf, pick the ancestor at the cap depth
rollup_map AS (
  SELECT DISTINCT ON (leaf_id) leaf_id, anc_id AS rollup_id, anc_path AS rollup_path
    FROM ancestor_chain
   WHERE anc_depth <= :depthLimit
   ORDER BY leaf_id, anc_depth DESC  -- pick deepest ancestor still <= limit
)
SELECT rm.rollup_id      AS category_id,
       rm.rollup_path    AS category_path,
       SUM(e.amount)::numeric AS total_amount,
       COUNT(*)::int     AS expense_count
  FROM expenses e
  JOIN rollup_map rm ON rm.leaf_id = e.category_id
 WHERE e.store_id = :storeId
   AND (:branchId::int IS NULL OR e.branch_id = :branchId::int)
   AND e.date >= :startDate::date
   AND e.date <  (:endDate::date + INTERVAL '1 day')
 GROUP BY rm.rollup_id, rm.rollup_path
 ORDER BY total_amount DESC;
```

[VERIFIED: PG10 supports `WITH RECURSIVE`, `DISTINCT ON`, `LIMIT`. Pattern follows `reportsGastoCockpit.service.ts` SQL style — raw query, parametrized, parallel-able with `Promise.all`.]

**Why this is correct:**
- Every expense's `category_id` is mapped to the closest ancestor whose `depth <= depthLimit`.
- Rolling up at a leaf (depth ≥ limit) collapses into the limit-depth ancestor.
- Rolling up at depth ≤ limit stays as-is (the leaf IS its own rollup).
- `SUM` over expenses joined through `rollup_map` gives parent = sum(self + descendants).

**Performance:** with 5-level × ~30 nodes/store ≈ 30 rows in `ec`. The CTE explodes to ~5×30 = 150 rows max in `ancestor_chain`. Trivial. Index `(store_id, status)` covers the entry.

#### Integration with existing `reportsGastoCockpit.service.ts`

The current cockpit JOINs `expenses → expenses_subcategories → expenses_categories`. Replace with:

```sql
LEFT JOIN expense_categories ec ON ec.id = e.category_id
-- (optionally: WITH RECURSIVE rollup_map ... and JOIN to it)
```

The pre-existing `getCockpit` summary/trend queries do NOT need the rollup CTE — they only filter by store/branch/date and sum. The category-breakdown chart is the one that benefits from `:depthLimit`.

---

### 2.4 react-arborist v3.5.0 integration

[VERIFIED: GitHub CHANGELOG, v3.5.0 latest as of Apr 2026]

#### Install

```bash
# Workspace install at repo root or under ventago-app — npm workspaces will handle hoisting
npm install --workspace ventago-app react-arborist@^3
```

Verify version before locking the plan: `npm view react-arborist version`. Bundle is ~30 KB minified (CONTEXT §D1.1 budget). No CSS framework dependency — fully renders via custom `Node` component (MUI-friendly).

#### Critical props for Phase 26

```tsx
import { Tree, type NodeRendererProps, type NodeApi } from 'react-arborist';

<Tree<TreeNode>
  data={treeData}                    // array of root nodes with .children recursive
  openByDefault={false}
  width="100%"
  height={600}
  rowHeight={36}
  indent={24}
  searchTerm={search}                // multi-keyword full-path search → see custom searchMatch
  searchMatch={multiKeywordPathMatch}
  disableDrag={false}
  // SAME-PARENT-ONLY enforcement (CONTEXT D1.2):
  disableDrop={({ parentNode, dragNodes }) => {
    if (!parentNode) return true;                              // disallow drop at root level
    return parentNode.id !== dragNodes[0].parent?.id;           // only same-parent reorder
  }}
  onMove={async ({ dragIds, parentId, index }) => {
    // calls PUT /expense-categories/:id/sort with {sortOrder} computed from siblings
  }}
  onRename={async ({ id, name }) => {
    // calls PUT /expense-categories/:id with {name}
  }}
  onCreate={async ({ parentId, type }) => {
    // not used — we open a Dialog instead for color/icon at create time
    return null;
  }}
  onDelete={async ({ ids }) => {
    // calls DELETE /expense-categories/:id with body {childPolicy}
  }}
>
  {ExpenseCategoryNode}
</Tree>
```

**`disableDrop` signature** (verified from v3 changelog): `({ parentNode, dragNodes, index }) => boolean`. Returning `true` blocks the drop. [VERIFIED: react-arborist v3.0.0 changelog]

**Multi-keyword path search** (CONTEXT D4.1):
```ts
const multiKeywordPathMatch = (node: NodeApi<TreeNode>, term: string) => {
  const haystack = `${node.data.path} ${node.data.name}`.toLowerCase();
  const tokens = term.toLowerCase().split(/\s+/).filter(Boolean);
  return tokens.every(t => haystack.includes(t));
};
```

[VERIFIED: react-arborist `searchMatch` prop is a function `(node, term) => boolean` — README]

#### IME (Korean / 한글) handling on rename input — CRITICAL

react-arborist does NOT solve IME composition for us. The default rename input fires Enter → commit, which is broken for Korean/Japanese/Chinese during composition. Solution: **provide a custom `Node` renderer for edit mode** with explicit `onKeyDown` that respects `event.nativeEvent.isComposing`:

```tsx
// In custom Node renderer when node.isEditing === true:
<input
  defaultValue={node.data.name}
  onKeyDown={(e) => {
    if (e.nativeEvent.isComposing || e.keyCode === 229) return; // IME mid-composition
    if (e.key === 'Enter') node.submit((e.target as HTMLInputElement).value);
    if (e.key === 'Escape') node.reset();
  }}
  onBlur={(e) => node.submit(e.target.value)}
/>
```

[CITED: dev.to/yukimi-inu/why-16-billion-east-asians; react/react#8683 — `keyCode === 229` is the cross-browser fallback when `isComposing` lies (Safari edge case)]

#### Virtualization

react-arborist always virtualizes via `react-window`. For our scale (≤ 625 nodes typical, often < 50), virtualization is harmless overhead — measure but do not pre-optimize. **No need to disable.** [ASSUMED — typical react-arborist behavior; not verified for our scale via benchmarks. Recommend a quick perf measurement on the largest test store during Wave 3.]

#### MUI compatibility

react-arborist is layout-only; you provide your own row component using MUI primitives (`Box`, `Typography`, `IconButton`, etc.). No CSS conflicts. The codebase's existing `RolePermissionsDrawer.tsx` uses `@mui/lab/TreeView` — that is a SEPARATE library and stays where it is. Both can coexist.

---

## 3. Migration Strategy

### 3.1 Sequence (single transactional SQL file per step, idempotent)

Recommended: 4 numbered SQL files, run in order. Pattern follows Phase 25 (`20260424-phase25-stepN-*.sql`).

| Step | File | Action | Idempotency |
|---|---|---|---|
| 1 | `20260501-phase26-step1-schema.sql` | `CREATE TABLE expense_categories` + indexes + trigger function + trigger | `IF NOT EXISTS`, `CREATE OR REPLACE` |
| 2 | `20260501-phase26-step2-migrate-data.sql` | INSERT roots from `expenses_categories`, INSERT children from `expenses_subcategories`, **then** rewire `expenses.category_id` (= existing `category_id` for rows w/o subcat, OR new child node id for rows w/ subcat) | `ON CONFLICT DO NOTHING` + `WHERE NOT EXISTS` + temp lookup table |
| 3 | `20260501-phase26-step3-add-fk.sql` | Add `expenses.category_id → expense_categories.id` FK + drop `expenses.expenses_subcategory_id` column | `IF EXISTS` checks |
| 4 | `20260501-phase26-step4-verify.sql` | Verification queries (counts match, no orphans, no NULL `category_id`). **No writes.** | Read-only |

Old tables (`expenses_categories`, `expenses_subcategories`) are LEFT IN PLACE for 2 weeks per CONTEXT §6 Hint #6. A separate cleanup phase drops them later.

### 3.2 Concrete migration shape (Step 2 sketch)

```sql
BEGIN;

-- (A) Build a temp mapping: old (categoryId, subcategoryId) -> new expense_categories.id
CREATE TEMP TABLE tmp_cat_map (
  old_cat_id INT, old_subcat_id INT, new_cat_id INT
);

-- (B) Insert legacy categories as roots. Trigger computes path/depth.
WITH ins AS (
  INSERT INTO expense_categories (store_id, parent_id, name, sort_order, status)
  SELECT store_id, NULL, name, 0, COALESCE(status, 1)
    FROM expenses_categories
  ON CONFLICT DO NOTHING
  RETURNING id, store_id, name
)
INSERT INTO tmp_cat_map (old_cat_id, old_subcat_id, new_cat_id)
SELECT ec_old.id, NULL, ec_new.id
  FROM expenses_categories ec_old
  JOIN ins ec_new ON ec_new.store_id = ec_old.store_id AND ec_new.name = ec_old.name;

-- (C) Insert legacy subcategories as children of the new root with same name as old category.
WITH ins AS (
  INSERT INTO expense_categories (store_id, parent_id, name, sort_order, status)
  SELECT sub.store_id, m.new_cat_id, sub.name, 0, COALESCE(sub.status, 1)
    FROM expenses_subcategories sub
    JOIN tmp_cat_map m ON m.old_cat_id = sub.expenses_category_id  -- snake_case in DB
   WHERE m.old_subcat_id IS NULL
  ON CONFLICT DO NOTHING
  RETURNING id, store_id, parent_id, name
)
INSERT INTO tmp_cat_map (old_cat_id, old_subcat_id, new_cat_id)
SELECT sub.expenses_category_id, sub.id, ins.id
  FROM expenses_subcategories sub
  JOIN ins ON ins.store_id = sub.store_id
          AND ins.name     = sub.name
          AND ins.parent_id = (SELECT new_cat_id FROM tmp_cat_map
                                WHERE old_cat_id = sub.expenses_category_id
                                  AND old_subcat_id IS NULL);

-- (D) Rewire expenses.category_id (currently NULL or pointing to legacy expenses_categories.id?
-- IMPORTANT: from expenses.model.ts, expenses currently links via expenses_subcategory_id.
-- expenses table has NO category_id column today. We must:
-- 1) ADD column expenses.category_id INTEGER
-- 2) Backfill: if subcat present -> map to new child id; else -> NULL (ambiguous, will need handling)

ALTER TABLE expenses ADD COLUMN IF NOT EXISTS category_id INTEGER;

UPDATE expenses e
   SET category_id = m.new_cat_id
  FROM tmp_cat_map m
 WHERE m.old_subcat_id = e.expenses_subcategory_id
   AND e.category_id IS NULL;

-- Rows with NULL expenses_subcategory_id: leave category_id = NULL (legitimately uncategorized).
-- ROADMAP REQ-5 says: "기존에 subcategory_id가 있던 row → 새 자식 노드 id로 매핑,
-- 없던 row → 새 루트 노드 id로 유지" — but expenses today has NO category_id, so
-- "유지" means: there is NOTHING to keep — these rows had no category at all.
-- Recommendation: leave NULL. Reports treat them as "Sin categoría" (already does).

-- (E) Add FK and drop the legacy column
ALTER TABLE expenses
  ADD CONSTRAINT IF NOT EXISTS fk_expenses_category
  FOREIGN KEY (category_id) REFERENCES expense_categories(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_expenses_category ON expenses(category_id);

ALTER TABLE expenses DROP COLUMN IF EXISTS expenses_subcategory_id;

COMMIT;
```

> **CRITICAL DISCOVERY** (deviates slightly from CONTEXT §6 Hint #4 wording):
> CONTEXT/ROADMAP say "expenses.category_id 재배선" but the live `expenses.model.ts` has only `expensesSubcategoryId` — there is **no current `category_id` column on `expenses`**. The migration must ADD the column, not rebind it. ROADMAP REQ-5's wording "기존에 subcategory_id가 있던 row → 새 자식 노드 id로 매핑, 없던 row → 새 루트 노드 id로 유지" — the "유지" clause has nothing to keep. Decision: NULL (Sin categoría). Planner should confirm this with user but NULL is the only honest mapping.

### 3.3 Rollback strategy

If Step 3 needs reverting before the 2-week cleanup:
1. `ALTER TABLE expenses ADD COLUMN expenses_subcategory_id INTEGER`.
2. Re-derive from `tmp_cat_map`-equivalent join: `UPDATE expenses SET expenses_subcategory_id = m.old_subcat_id FROM tmp_cat_map m WHERE m.new_cat_id = expenses.category_id`. This requires keeping the `tmp_cat_map` rows in a non-temp table — recommend converting `tmp_cat_map` → `_phase26_cat_map` (regular table, kept for the 2-week window).
3. Old `expenses_categories` / `expenses_subcategories` are still intact, so foreign key reattaches.

**Rollback checklist file**: `phase26-rollback.sql` should accompany the migration set, not in `migrations/` (so it isn't auto-run).

### 3.4 Verification queries (Step 4)

```sql
-- 1. Every legacy category produced a new root
SELECT COUNT(*) FROM expenses_categories;
SELECT COUNT(*) FROM expense_categories WHERE parent_id IS NULL;
-- These should match (or new ≥ old if any new stores already used the new flow).

-- 2. Every legacy subcategory produced a child node
SELECT COUNT(*) FROM expenses_subcategories;
SELECT COUNT(*) FROM expense_categories WHERE parent_id IS NOT NULL;

-- 3. No orphan expenses (category_id pointing to non-existent row)
SELECT COUNT(*) FROM expenses e
  LEFT JOIN expense_categories ec ON ec.id = e.category_id
 WHERE e.category_id IS NOT NULL AND ec.id IS NULL;
-- Must be 0.

-- 4. Path & depth integrity (trigger sanity)
SELECT id, name, parent_id, path, depth FROM expense_categories
 WHERE depth > 5 OR depth < 0
    OR (parent_id IS NULL AND depth <> 0)
    OR (parent_id IS NOT NULL AND depth = 0);
-- Must be empty.

-- 5. Cycle detection
WITH RECURSIVE walk(id, parent_id, depth_walked) AS (
  SELECT id, parent_id, 0 FROM expense_categories WHERE parent_id IS NULL
  UNION ALL
  SELECT c.id, c.parent_id, w.depth_walked + 1
    FROM expense_categories c JOIN walk w ON c.parent_id = w.id
   WHERE w.depth_walked < 10
)
SELECT id FROM expense_categories WHERE id NOT IN (SELECT id FROM walk);
-- Must be empty (no unreachable / cycle nodes).
```

---

## 4. Codebase Patterns to Reuse

### 4.1 Backend NestJS module location & wiring

Create new module: `api-ventago/src/app/expense-categories/`. Mirror `materials/` or `expenses/categories/`. Import into `expenses.module.ts` (replacing the now-deleted `ExpensesCategoriesModule` and `ExpensesSubcategoriesModule`).

```ts
// api-ventago/src/app/expense-categories/expense-categories.module.ts
@Module({
  imports: [SequelizeModule.forFeature([ExpenseCategory])],
  providers: [ExpenseCategoryService, ExpenseCategorySeedService],
  controllers: [ExpenseCategoryController],
  exports: [ExpenseCategoryService, ExpenseCategorySeedService],
})
export class ExpenseCategoryModule {}
```

Register in `app.module.ts` (next to `ExpensesModule`). Delete `ExpensesCategoriesModule` and `ExpensesSubcategoriesModule` in the same Wave to avoid stale imports.

### 4.2 Auth pattern — copy from existing categories controller

```ts
@Controller('expense-categories')
export class ExpenseCategoryController {
  // Read endpoints — open to vendedor + gerente (they need to pick categories on Gasto form):
  @Get('tree')
  @Auth(ValidRoles.admin, ValidRoles.superadmin, ValidRoles.vendedor, ValidRoles.gerente)
  async tree(@GetUser() user: Users) { ... }

  // Mutating endpoints — admin/gerente only (same as existing expenses-categories.controller.ts):
  @Post()
  @Auth(ValidRoles.admin, ValidRoles.superadmin, ValidRoles.gerente)
  @Audit({ entityType: 'ExpenseCategory', action: 'create',
           getDescription: (b: any) => `Categoría creada: ${b.name}` })
  async create(@Body() body: CreateDto) { ... }

  @Put(':id/move')
  @Auth(ValidRoles.admin, ValidRoles.superadmin)   // structural changes admin-only per CONTEXT §6
  @Audit({ entityType: 'ExpenseCategory', action: 'move', ... })
  async move(@Param('id') id: number, @Body() body: { newParentId: number | null }) { ... }
}
```

Existing pattern verified in `api-ventago/src/app/expenses/categories/expenses-categories.controller.ts`. The `@Audit` decorator is registered globally via `AuditInterceptor` ([VERIFIED via codebase grep at `api-ventago/src/common/decorators/audit.decorator.ts` and `api-ventago/src/common/interceptors/audit.interceptor.ts`]).

### 4.3 Seed function — `storeTemplate.service.ts`

Add a method that runs at the end of `createStoreDefaults` and ALSO can be called in the migration to backfill empty stores. CONTEXT §6 Hint #5: only seed when category count == 0 (idempotent for existing stores).

```ts
// In ExpenseCategorySeedService (separate provider, called from StoreTemplateService):
async seedDefaults(storeId: number, transaction?: Transaction): Promise<void> {
  const existing = await ExpenseCategory.count({ where: { storeId }, transaction });
  if (existing > 0) return;   // never re-seed
  const defaults = ['Servicios', 'Comida', 'Transporte', 'Insumos', 'Sueldos', 'Otros'];
  for (let i = 0; i < defaults.length; i++) {
    await ExpenseCategory.create(
      { storeId, parentId: null, name: defaults[i], sortOrder: i, status: 1 },
      { transaction },
    );
  }
}
```

Wire into `StoreTemplateService.createStoreDefaults()` after `createDefaultSubcategory`. CONTEXT §D2.2 says **do NOT** auto-seed existing stores — only the migration backfill respects the existing 2-level data, and only NEW stores get the 6 defaults.

### 4.4 Frontend SWR hook

```ts
// ventago-app/src/hooks/api/useExpenseCategoryTree.ts
import { useApi } from 'src/hooks/useApi'
export function useExpenseCategoryTree(showArchived = false) {
  const url = `/expense-categories/tree${showArchived ? '?showArchived=1' : ''}`
  return useApi<TreeNode[]>(url)
}
```

Pattern matches `useCategoriesByStore`, `useMaterialCategories` (verified in `ventago-app/src/hooks/api/`). The `useApi` wrapper provides 5-min dedup per CLAUDE.md SWR rules.

### 4.5 Navigation entry

Add a child under the `admin` or `configuracion` app in user.structure (DB-driven). For the "Configuración → Categorías de Gastos" page:

- DB seed: insert into `apps`/`modules` table (if applicable to the role-functions infra) OR add as a hardcoded admin child (CLAUDE.md: superadmin admin uses hardcoded). Given CONTEXT path `/configuracion/categorias-gastos`, the **simpler approach** is to add the link inline in the existing Gastos page header (avoid sidebar churn) and **separately** add a sidebar entry via the `apps/modules` migration. Planner decides; both paths exist in this codebase.
- Pages router file: `ventago-app/src/pages/configuracion/categorias-gastos.tsx`.

### 4.6 Existing tree UI reference

`ventago-app/src/views/users/roles/RolePermissionsDrawer.tsx` uses `@mui/lab/TreeView`. **DO NOT replicate that pattern** for Phase 26 — it pre-renders all `TreeItem`s (no virtualization), no D&D, no search. CONTEXT §D1.1 explicitly chose `react-arborist` for this reason. Reference only for: visual style (Card + colored left border per app), state management split (Map<id, ...>), header gradient.

---

## 5. Risks / Pitfalls

### Pitfall 1: DB trigger does not fire on raw bulk SQL with COPY
**What goes wrong:** `COPY ... FROM` bypasses BEFORE-row triggers in some PG versions and tools.
**Why:** trigger overhead is exactly what bulk loaders skip.
**Mitigation:** Use `INSERT ... SELECT` (not `COPY`) in the migration. Trigger fires per-row. Performance for ~100 rows total per store × 4 stores is trivial. [VERIFIED: PG 10/15 docs — `INSERT` always fires BEFORE/AFTER triggers]

### Pitfall 2: Partial unique index NULL trap on root rename collisions
**What goes wrong:** Two roots with same name and parent_id=NULL would slip past `UNIQUE (store_id, parent_id, name)` because PG treats NULLs as distinct.
**Mitigation:** Two partial indexes (one for `parent_id IS NULL`, one for `parent_id IS NOT NULL`) — already in §2.1 schema. [VERIFIED: PG10/15 docs]

### Pitfall 3: Sequelize `include: 'children'` infinite recursion
**What goes wrong:** Sequelize stack-overflow trying to nest the self-FK association.
**Mitigation:** NEVER use `include` for `children`. Always flat `findAll` + JS tree-build. Document this in service-layer comments. [VERIFIED via Sequelize v6 docs + codebase pattern absence — no existing self-FK includes to copy]

### Pitfall 4: react-arborist `disableDrop` — disables reordering too if returns true blindly
**What goes wrong:** Issue brimdata/react-arborist#168 — "Reordering does not work when drop is disabled".
**Mitigation:** The `disableDrop` predicate in §2.4 returns `true` ONLY when `parentNode.id !== dragNodes[0].parent?.id`, allowing same-parent reorder. Test cross-parent and same-parent cases in Wave 3. [CITED: github.com/brimdata/react-arborist/issues/168]

### Pitfall 5: IME composition Enter on Korean / 한글 input
**What goes wrong:** Pressing Enter to confirm 한글 conversion submits a half-written category name.
**Mitigation:** `event.nativeEvent.isComposing || keyCode === 229` guard on the rename input (§2.4). Test in Korean keyboard mode on Chrome AND Safari. [CITED: dev.to/yukimi-inu, react#8683]

### Pitfall 6: Soft-deleted parent + active children visibility
**What goes wrong:** CONTEXT §9 "Risks" flags this as needing planner decision. If parent.status=0 and children.status=1, default tree query (`WHERE status=1`) shows orphan children with broken path.
**Mitigation (recommended)**: archive does NOT cascade by default. Tree query filters by `status=1`. Mostrar archivados toggle = show all status. The "broken-path" concern is moot: each row stores its own `path`, which still includes the (now-archived) ancestor name as a string. Reports filter `WHERE status=1` on the JOIN — archived parent + its active children are simply not visible together. **Planner: confirm this with user** OR introduce "cascade archive" toggle in the delete dialog. Lean toward NOT cascading.

### Pitfall 7: `expenses` has no `category_id` column today (only `expensesSubcategoryId`)
**What goes wrong:** ROADMAP REQ-5 says "expenses.category_id 재배선" but the column does not yet exist; the migration must `ADD COLUMN`, not rebind.
**Mitigation:** Migration Step 2 (§3.2) explicitly adds the column. Rows with no prior subcategory get `category_id = NULL` ("Sin categoría"). [VERIFIED via direct read of `api-ventago/src/app/expenses/expenses.model.ts`]

### Pitfall 8: Reports `WITH RECURSIVE` performance regression on huge expense volumes
**What goes wrong:** If a store accumulates 100k expenses, the rollup CTE may need indexing help.
**Mitigation:** existing `expenses(date)` and the new `expenses(category_id)` indexes plus tight date filter (the CTE only joins `rollup_map` which has ≤ 30 rows × store) keep cost low. Measure on the largest live store after deploy. [ASSUMED — not benchmarked; flag for performance check in Wave 4.]

### Pitfall 9: PG10 syntax difference — `EXECUTE FUNCTION` vs `EXECUTE PROCEDURE`
**What goes wrong:** Trigger DDL using `EXECUTE FUNCTION` fails on PG10 ("syntax error at or near FUNCTION").
**Mitigation:** Use `EXECUTE PROCEDURE` (works on both PG10 and PG15). [VERIFIED: PG10 CREATE TRIGGER docs]

### Pitfall 10: MRU localStorage key collision across stores
**What goes wrong:** A superadmin who switches stores sees stale MRU from previous store.
**Mitigation:** Key format `expense_category_mru_user_${userId}_store_${storeId}`. Cleanup: keep only the 5 most recent IDs, prune on write. [Already noted CONTEXT §9].

### Pitfall 11: Trigger error swallowed by silent rollback
**What goes wrong:** A trigger `RAISE EXCEPTION` aborts the transaction and Sequelize sees a generic `SequelizeDatabaseError`.
**Mitigation:** App-level pre-validation (`depth + subtree.maxDepth <= 5`, cycle check) in `ExpenseCategoryService.move()` BEFORE issuing UPDATE. Trigger remains the safety net but app gives the clean 400 error. UI shows it through the existing GlobalErrorBanner (ROADMAP REQ-18).

---

## 6. Open Questions for Planner

1. **`category_id` column add semantics** — confirm with user that legacy rows with no `expensesSubcategoryId` map to `category_id = NULL` (not to a "Sin categoría" auto-created root). Planner decision impact: migration Step 2 logic. **Recommendation:** NULL (matches current behavior — current cockpit already shows "Sin categoría").

2. **Soft-delete cascade behavior** — does archiving a parent also archive children? **Recommendation:** NO cascade (children stay active, just become invisible while parent collapsed). Add a "cascade" checkbox in the delete dialog as future enhancement.

3. **MRU storage location** — localStorage (CONTEXT §D4.2 first-cut) or `users.preferences` (multi-device sync)? **Recommendation:** localStorage for Phase 26. Add `users.preferences` JSON column in a separate phase if needed.

4. **Inline create (CONTEXT §D4.3)** UX detail — the parent-picker mini-dialog is itself a tree. Use the same `react-arborist` instance (read-only, no drag) or a flat dropdown of paths? **Recommendation:** flat searchable list of paths (smaller dialog, faster). The user is one-click away from typing the name and saving.

5. **Audit log entityType naming convention** — `ExpenseCategory` (singular, English) or `Categoría de Gastos` (Spanish, matches existing audit decorator strings like "Categoría de gastos creada")? **Recommendation:** stay consistent with existing `Categoria` entityType so audit reports don't fragment.

6. **Existing reports `reportsGastoCockpit.service.ts`** — replace with rolling-up CTE OR keep current `LEFT JOIN expense_categories ec` (no rollup) and add rollup as a SEPARATE endpoint `/reports/gasto-tree`? **Recommendation (TBD by planner):** keep cockpit's "top 8 categories" as flat (uses leaf `category_id` directly) and add a new `getRollup(depthLimit)` method for the new "expand by depth" Reports widget. Less risk to existing chart.

---

## 7. References

### HIGH confidence (verified or directly inspected)

- `/Users/marcoskim/Trabajos_Programming/ACE_online_1.0/.planning/phases/26-gastos-categoria-tree-n-niveles/26-CONTEXT.md` — locked decisions
- `/Users/marcoskim/Trabajos_Programming/ACE_online_1.0/.planning/ROADMAP.md` (Phase 26 §575-619) — 18 requirements + 11 success criteria
- `/Users/marcoskim/Trabajos_Programming/ACE_online_1.0/CLAUDE.md` — PG 10/15 compat, Sequelize underscored, ESLint, npm workspaces
- `/Users/marcoskim/Trabajos_Programming/ACE_online_1.0/api-ventago/src/app/expenses/expenses.model.ts` — current `expensesSubcategoryId` (no `category_id` column today)
- `/Users/marcoskim/Trabajos_Programming/ACE_online_1.0/api-ventago/src/app/expenses/categories/expenses-categories.{model,controller,service}.ts` — current 2-level model + auth/audit pattern to copy
- `/Users/marcoskim/Trabajos_Programming/ACE_online_1.0/api-ventago/src/app/reports/reportsGastoCockpit.service.ts` — raw-SQL JOIN pattern + `Promise.all` parallelism
- `/Users/marcoskim/Trabajos_Programming/ACE_online_1.0/api-ventago/src/app/store/storeTemplate.service.ts` (`createStoreDefaults`) — where to wire the 6-default seed
- `/Users/marcoskim/Trabajos_Programming/ACE_online_1.0/api-ventago/migrations/20260424-phase25-step5-data-migration.sql` — idempotent-migration template (BEGIN/temp table/ON CONFLICT/COMMIT) to mimic
- `/Users/marcoskim/Trabajos_Programming/ACE_online_1.0/api-ventago/migrations/wave11-rework.sql` — table+FK+index style guide
- `/Users/marcoskim/Trabajos_Programming/ACE_online_1.0/api-ventago/src/common/{decorators/audit.decorator.ts,interceptors/audit.interceptor.ts}` — `@Audit` integration
- `/Users/marcoskim/Trabajos_Programming/ACE_online_1.0/ventago-app/src/views/users/roles/RolePermissionsDrawer.tsx` — existing `@mui/lab/TreeView` (do NOT copy for Phase 26; reference only)
- `/Users/marcoskim/Trabajos_Programming/ACE_online_1.0/ventago-app/src/views/expenses/components/ExpenseModal.tsx` — current 2-dropdown cascading select to be replaced with tree dropdown
- `/Users/marcoskim/Trabajos_Programming/ACE_online_1.0/ventago-app/src/hooks/{api/useCategoriesByStore.ts,useApi.ts}` — SWR hook template
- `/Users/marcoskim/Trabajos_Programming/ACE_online_1.0/ventago-app/src/navigation/vertical/index.ts` — sidebar entry pattern (note: `/gastos` is currently hidden — line 41)

### MEDIUM confidence (web sources, multiple sources cross-referenced)

- [react-arborist GitHub](https://github.com/brimdata/react-arborist) — v3.5.0, `disableDrop` signature, `searchMatch`
- [react-arborist CHANGELOG](https://github.com/brimdata/react-arborist/blob/main/CHANGELOG.md) — v3.0.0 breaking changes (disableDrop function param), v3.5.0 latest
- [react-arborist Issue #168](https://github.com/brimdata/react-arborist/issues/168) — "Reordering does not work when drop is disabled" (handle return-false carefully)
- [PostgreSQL Materialized Path canonical pattern](https://leonardqmarcq.com/posts/modeling-hierarchical-tree-data) — BEFORE-INSERT/UPDATE trigger source
- [PostgreSQL hierarchical do's and don'ts](https://leonardqmarcq.com/posts/dos-and-donts-of-modeling-hierarchical-trees-in-postgres) — adjacency vs path tradeoffs
- [PostgreSQL 18 WITH Queries (CTE)](https://www.postgresql.org/docs/current/queries-with.html) — `WITH RECURSIVE` semantics (PG10 supported)
- [dev.to: IME `isComposing` Enter handler trap](https://dev.to/yukimi-inu/why-16-billion-east-asians-are-quietly-raging-at-your-enter-key-handler-1po0) — Korean composition gotcha
- [react/react#8683](https://github.com/facebook/react/issues/8683) — `keyCode === 229` cross-browser fallback
- [Junhyunny: Korean keyboardEvent in React](https://junhyunny.github.io/react/typescript/korean-keyboard-event-error/) — same fix pattern

### LOW confidence (assumed)

- react-arborist bundle size ~30 KB minified — CONTEXT §D1.1 stated; not independently verified via bundlephobia in this session.
- Virtualization overhead negligible at < 50 nodes — assumed from typical react-window behavior; not benchmarked for our exact case.
- Reports CTE performance for 100k+ expenses — not benchmarked; recommend instrumented timing during Wave 4.

---

## 8. Confidence Assessment

| Area | Confidence | Reason |
|---|---|---|
| DB schema + trigger pattern | **HIGH** | PG docs + leonardqmarcq.com canonical pattern + verified PG10 syntax (`EXECUTE PROCEDURE`) |
| Sequelize self-FK + flat-load pattern | **HIGH** | Sequelize v6 docs + verified by absence of include-recursion in codebase |
| Migration sequence | **HIGH** | Mirrors Phase 25 step pattern (verified files); discovered & resolved `expenses.category_id` column-add detail by direct file read |
| Recursive CTE rollup | **HIGH** | PG10 supports all features used; pattern follows existing `reportsGastoCockpit.service.ts` |
| react-arborist v3 APIs | **MEDIUM** | Verified via official changelog + issues; not yet installed locally — exact prop type imports may need adjustment in plan |
| Korean IME handling | **MEDIUM** | Standard `isComposing` + 229 fallback pattern; not yet integration-tested with react-arborist v3 |
| Performance assumptions (virtualization, CTE) | **LOW** | Not benchmarked; flag for Wave 3-4 measurement |

**Research date:** 2026-04-27
**Valid until:** 2026-05-27 (react-arborist is on a frequent minor-release cadence; recheck v3.x patch version before lock)
