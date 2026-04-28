---
phase: 26-gastos-categoria-tree-n-niveles
plan: "02"
subsystem: api-ventago
tags: [nestjs, sequelize, tree, expense-categories, seed, soft-delete, audit]
dependency_graph:
  requires: [expense_categories table, ExpenseCategory model, ExpenseCategoryModule (Wave 1)]
  provides: [ExpenseCategoryService, ExpenseCategoryController, ExpenseCategorySeedService, 5 DTOs, unit tests]
  affects: [storeTemplate.service.ts, store.module.ts, expense-categories.module.ts]
tech_stack:
  added: []
  patterns: [NestJS service + controller, class-validator DTOs, jest mock unit tests, soft delete pattern, transaction sharing]
key_files:
  created:
    - api-ventago/src/app/expense-categories/expense-category.service.ts
    - api-ventago/src/app/expense-categories/expense-category.controller.ts
    - api-ventago/src/app/expense-categories/expense-category-seed.service.ts
    - api-ventago/src/app/expense-categories/expense-category.service.spec.ts
    - api-ventago/src/app/expense-categories/dto/create-expense-category.dto.ts
    - api-ventago/src/app/expense-categories/dto/update-expense-category.dto.ts
    - api-ventago/src/app/expense-categories/dto/move-expense-category.dto.ts
    - api-ventago/src/app/expense-categories/dto/delete-expense-category.dto.ts
    - api-ventago/src/app/expense-categories/dto/sort-expense-category.dto.ts
  modified:
    - api-ventago/src/app/expense-categories/expense-categories.module.ts
    - api-ventago/src/app/store/storeTemplate.service.ts
    - api-ventago/src/app/store/store.module.ts
decisions:
  - "Audit action mapping: 'move' and 'restore' do not exist in AuditOptions.action enum — mapped to 'edit' (closest semantic match)"
  - "user.storeId! non-null assertion in controller — @Auth() guarantees authenticated user with storeId"
  - "Unit tests use jest mocks (not real DB) — trigger behavior covered by DB-level guards from Wave 1"
  - "spec file placed under src/app/expense-categories/ (jest rootDir=src, testRegex=*.spec.ts)"
metrics:
  duration: ~13min
  completed_date: "2026-04-28"
  tasks_completed: 5
  files_created: 9
  files_modified: 3
---

# Phase 26 Plan 02: Backend API + Seed + Guards Summary

**One-liner:** ExpenseCategoryService CRUD with cycle/depth/sibling guards + 8-endpoint controller + 6-category store seed wired into createStoreDefaults + 21 passing unit tests.

---

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 26-02-01 | 5 DTOs (create/update/move/delete/sort) | 3185b53 | 5 DTO files |
| 26-02-02 | ExpenseCategoryService | 197d19b | expense-category.service.ts |
| 26-02-03 | Unit tests (21 cases) | 197d19b | expense-category.service.spec.ts |
| 26-02-04 | ExpenseCategoryController + module update | 2b8c0d1 | controller + seed service + module |
| 26-02-05 | Seed integration into storeTemplate | 2eea008 | storeTemplate.service.ts + store.module.ts |

---

## 8-Endpoint Matrix

| Method | Path | Auth Roles | Audit Action |
|--------|------|-----------|--------------|
| GET | `/expense-categories/tree` | admin, superadmin, gerente, **vendedor** | — |
| GET | `/expense-categories/:id/in-use` | admin, superadmin, gerente | — |
| POST | `/expense-categories` | admin, superadmin, gerente | `create` |
| PUT | `/expense-categories/:id` | admin, superadmin, gerente | `edit` |
| PUT | `/expense-categories/:id/move` | **admin, superadmin only** | `edit` |
| PUT | `/expense-categories/:id/sort` | admin, superadmin, gerente | — |
| DELETE | `/expense-categories/:id` | **admin, superadmin only** | `delete` |
| PUT | `/expense-categories/:id/restore` | **admin, superadmin only** | `edit` |

---

## Service Error Messages (for frontend i18n matching)

| Method | Condition | Error Message |
|--------|-----------|---------------|
| `create` | parentId not found or wrong store | `'parentId 가 존재하지 않거나 다른 매장 소속입니다'` |
| `create` | archived parent | `'archived 부모 밑에 자식을 추가할 수 없습니다'` |
| `create` | depth > 5 | `'depth 5 초과 — 이 부모 밑에 자식을 추가할 수 없습니다 (부모 depth: N)'` |
| `create` | duplicate sibling name | `'같은 부모 밑에 동명 카테고리가 이미 존재합니다'` |
| `rename` | duplicate sibling name | `'같은 부모 밑에 동명 카테고리가 이미 존재합니다'` |
| `move` | self-reference | `'자기 자신을 부모로 지정할 수 없습니다'` |
| `move` | target not found | `'새 부모 카테고리가 존재하지 않거나 다른 매장 소속입니다'` |
| `move` | cycle detected | `'자기 자손을 부모로 지정할 수 없습니다 (사이클 감지)'` |
| `move` | subtree depth > 5 | `'subtree 이동 시 깊이 5 초과 (예상 최대 depth: N)'` |
| `softDelete` | moveTo missing | `'policy=move 일 때 moveTo 가 필수입니다'` |
| `softDelete` | moveTo is descendant | `'자손 노드를 moveTo 로 지정할 수 없습니다'` |
| `softDelete` | child subtree depth > 5 | `'자식 "name" 이동 시 깊이 5 초과 (예상 max depth: N)'` |
| `restore` | already active | `'이미 active 상태인 카테고리입니다'` |
| `restore` | parent is archived | `'부모 카테고리가 archived 상태입니다 — 먼저 부모를 복원하세요'` |
| `getInUseCount` | category not found | `NotFoundException: '카테고리를 찾을 수 없습니다'` |

---

## Seed: 6 Default Categories (신규 매장 전용)

| name | color | icon |
|------|-------|------|
| Servicios | `#3498db` | `tabler:bolt` |
| Comida | `#e67e22` | `tabler:tools-kitchen-2` |
| Transporte | `#2ecc71` | `tabler:bus` |
| Insumos | `#9b59b6` | `tabler:package` |
| Sueldos | `#f1c40f` | `tabler:cash` |
| Otros | `#95a5a6` | `tabler:dots` |

All root nodes (parentId=null, depth=0), sortOrder 0–5. Idempotent: if store already has any categories, seed is skipped.

---

## Wave 3 Interface Contract

Wave 3 (Admin UI) depends on the following from this plan:

### GET /expense-categories/tree response (flat array)

```typescript
// 반환 타입: ExpenseCategory[] (flat array — 클라이언트가 트리 빌드)
[
  {
    id: number,
    storeId: number,
    parentId: number | null,   // null = root node
    name: string,              // 1~120자
    path: string,              // "Parent > Child > Grandchild" (트리거 자동 생성)
    depth: number,             // 0~5
    sortOrder: number,         // 0 이상 정수
    color: string | null,      // "#RRGGBB" 또는 null
    icon: string | null,       // "tabler:bolt" 형식 또는 null
    status: 1 | 0,             // 1=active, 0=archived
    createdAt: string,         // ISO 8601
    updatedAt: string,
  }
]
// archived=true 쿼리 파라미터 없으면 status=1 만 반환
// order: depth ASC, sortOrder ASC, name ASC
```

### DELETE /expense-categories/:id query params

```
DELETE /expense-categories/5?policy=promote
DELETE /expense-categories/5?policy=cascade
DELETE /expense-categories/5?policy=move&moveTo=10
```

---

## Build + Test Verification

- `npm run build` (nest build): PASSED — 0 TypeScript errors
- `npx jest expense-category.service.spec --runInBand`: 21/21 PASSED
- All 5 DTO files exist and TypeScript-valid

---

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Audit action enum mismatch**
- **Found during:** Task 26-02-04 (controller implementation)
- **Issue:** Plan specified `action: 'move'` and `action: 'restore'` in `@Audit` decorators, but `AuditOptions.action` union type does not include those values — TypeScript would reject them
- **Fix:** Mapped `move` → `'edit'` and `restore` → `'edit'` (closest semantic match within the enum). No behavioral change to audit logging.
- **Files modified:** expense-category.controller.ts
- **Commit:** 2b8c0d1

**2. [Rule 1 - Bug] user.storeId type mismatch**
- **Found during:** Task 26-02-04 (TypeScript check)
- **Issue:** `Users.storeId` is typed `number | null` but service methods require `number` — TypeScript error TS2345
- **Fix:** Added `!` non-null assertion (`user.storeId!`) in all controller methods. Valid because `@Auth()` decorator ensures only authenticated users with valid storeId reach the handler.
- **Files modified:** expense-category.controller.ts
- **Commit:** 2b8c0d1

**3. [Rule 1 - Bug] Test mock for sibling-check had extra findOne call**
- **Found during:** Task 26-02-03 (test run)
- **Issue:** Test mock set up two `findOne` calls (one for missing parent, one for sibling) when `parentId` is undefined — but the service skips parent lookup when no parentId, so the mock sequence was wrong
- **Fix:** Reduced to single `findOne` mock for the sibling check
- **Files modified:** expense-category.service.spec.ts
- **Commit:** 197d19b

---

## Known Stubs

None. All service methods are fully implemented. The seed service creates real categories with colors and icons.

---

## Threat Flags

None beyond the plan's threat model. All T-26-05 through T-26-11 mitigations applied:
- T-26-05 (cross-store access): every service method filters by `storeId`
- T-26-06 (cycle): `validateNoCycle` via path.startsWith check + DB trigger backup
- T-26-07 (depth overflow): subtree max depth calculation before UPDATE + DB CHECK constraint
- T-26-08 (repudiation): `@Audit` on all mutating endpoints
- T-26-10 (elevation): `@Auth` roles enforced per endpoint

---

## Self-Check

### Files Verified

- `api-ventago/src/app/expense-categories/expense-category.service.ts` — FOUND
- `api-ventago/src/app/expense-categories/expense-category.controller.ts` — FOUND
- `api-ventago/src/app/expense-categories/expense-category-seed.service.ts` — FOUND
- `api-ventago/src/app/expense-categories/expense-category.service.spec.ts` — FOUND
- `api-ventago/src/app/expense-categories/dto/create-expense-category.dto.ts` — FOUND
- `api-ventago/src/app/expense-categories/dto/update-expense-category.dto.ts` — FOUND
- `api-ventago/src/app/expense-categories/dto/move-expense-category.dto.ts` — FOUND
- `api-ventago/src/app/expense-categories/dto/delete-expense-category.dto.ts` — FOUND
- `api-ventago/src/app/expense-categories/dto/sort-expense-category.dto.ts` — FOUND
- `api-ventago/src/app/store/storeTemplate.service.ts` (modified) — FOUND
- `api-ventago/src/app/store/store.module.ts` (modified) — FOUND

### Commits Verified (api-ventago)

- `3185b53` feat(phase-26-02): add 5 expense category DTOs
- `197d19b` feat(phase-26-02): add ExpenseCategoryService + unit tests (21 passing)
- `2b8c0d1` feat(phase-26-02): add ExpenseCategoryController (8 endpoints) + SeedService + update module
- `2eea008` feat(phase-26-02): wire ExpenseCategorySeedService into StoreTemplateService + import module

### Outer Repo

- `84b740a` chore: bump api-ventago for phase 26 wave 2 (tasks 1-5)

## Self-Check: PASSED
