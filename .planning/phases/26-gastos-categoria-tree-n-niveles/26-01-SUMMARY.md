---
phase: 26-gastos-categoria-tree-n-niveles
plan: "01"
subsystem: api-ventago
tags: [migration, postgresql, sequelize, tree, expense-categories]
dependency_graph:
  requires: []
  provides: [expense_categories table, ExpenseCategory model, ExpenseCategoryModule]
  affects: [expenses table (category_id column added), app.module.ts]
tech_stack:
  added: []
  patterns: [adjacency-list + materialized-path tree, PG BEFORE INSERT/UPDATE trigger, Sequelize self-FK]
key_files:
  created:
    - api-ventago/migrations/26-01-step1-schema.sql
    - api-ventago/migrations/26-02-step2-data.sql
    - api-ventago/migrations/26-03-step3-fk.sql
    - api-ventago/migrations/26-04-step4-verify.sql
    - api-ventago/migrations/26-99-rollback.sql
    - api-ventago/src/app/expense-categories/expense-category.model.ts
    - api-ventago/src/app/expense-categories/expense-categories.module.ts
  modified:
    - api-ventago/src/app.module.ts
decisions:
  - "PG10/PG15 호환: EXECUTE PROCEDURE (not EXECUTE FUNCTION), SERIAL (not GENERATED AS IDENTITY)"
  - "_phase26_cat_map 은 TEMP 가 아닌 정식 테이블 — 2주 롤백 윈도우 동안 보존"
  - "expenses_subcategory_id 컬럼 Wave 5 까지 유지 (두 컬럼 공존, 롤백 가능)"
  - "subcategory 없던 expenses 행은 category_id = NULL (Sin categoría — 기존 동작 유지)"
  - "Partial UNIQUE INDEX (not 일반 UNIQUE) — NULL 처리 PG 표준 준수"
metrics:
  duration: ~45min
  completed_date: "2026-04-28"
  tasks_completed: 7
  files_created: 7
  files_modified: 1
---

# Phase 26 Plan 01: DB Schema + Migration + Sequelize Model Summary

**One-liner:** expense_categories self-FK adjacency-list 트리 테이블 + BEFORE INSERT/UPDATE PG 트리거 (path/depth 자동 계산) + 기존 2단계 카테고리 데이터 마이그레이션 + Sequelize 모델 등록

---

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 26-01-01 | 스키마 + 트리거 + 인덱스 | 7f03bf4 | 26-01-step1-schema.sql |
| 26-01-02 | 데이터 변환 + category_id 백필 | f4ded5f | 26-02-step2-data.sql |
| 26-01-03 | FK 추가 | 841440a | 26-03-step3-fk.sql |
| 26-01-04 | 검증 SQL | 4aae565 | 26-04-step4-verify.sql |
| 26-01-05 | 롤백 SQL | d8e2b20 | 26-99-rollback.sql |
| 26-01-06 | Sequelize 모델 + 모듈 등록 | d46143a | expense-category.model.ts, expense-categories.module.ts, app.module.ts |
| 26-01-07 | 로컬 DB 적용 + 회귀 sanity | (실행 전용) | — |

---

## SQL 파일별 검증 결과

### 26-01-step1-schema.sql

- `to_regclass('public.expense_categories')` = `expense_categories` ✓
- `pg_trigger WHERE tgname='trg_expense_cat_path'` = 1 ✓
- `pg_proc WHERE proname='fn_expense_categories_path'` = 1 ✓
- Idempotent: 2회 실행 에러 없음 ✓

### 26-02-step2-data.sql

로컬 DB 실제 데이터 (store_id=6):
- 루트 노드: COMIDA, GENERAL, HONORARIO, IMPUESTO — 4개 생성 ✓
- 자식 노드: 0개 (기존 expenses_subcategories 가 0건) ✓
- _phase26_cat_map: 4 루트 매핑, 0 자식 매핑 ✓
- expenses.category_id 컬럼 추가됨 (기존 expenses 0건이므로 백필 0건) ✓
- Idempotent: 2회 실행 에러 없음 (ON CONFLICT DO NOTHING) ✓

### 26-03-step3-fk.sql

- `fk_expenses_category` FK 존재 = 1 ✓
- `idx_expenses_category` 인덱스 존재 = 1 ✓
- `expenses_subcategory_id` 컬럼 아직 살아있음 = 1 ✓ (Wave 5 까지 유지)
- Idempotent: 2회 실행 에러 없음 ✓

### 26-04-step4-verify.sql (6개 검증 쿼리)

| Check | 결과 | 기대값 |
|-------|------|--------|
| roots_match | old=4, new=4 | 일치 ✓ |
| children_match | old=0, new=0 | 일치 ✓ |
| orphan_expenses | 0 | 0 ✓ |
| path_depth_integrity | 0 bad_rows | 0 ✓ |
| cycle_check | 0 unreachable | 0 ✓ |
| map_coverage | old=4, map=4 | 일치 ✓ |

### 26-99-rollback.sql

- 파일 존재 + "수동 실행 전용" 경고 + DROP TABLE IF EXISTS expense_categories 포함 ✓
- 자동 실행 안 함 (99- prefix 명명 + 파일 내 한국어 경고)

---

## 트리거 동작 검증 (수동 테스트)

| 테스트 | 결과 |
|--------|------|
| INSERT 루트: path=name, depth=0 | ✓ |
| INSERT 자식: path='parent > child', depth=1 | ✓ |
| UPDATE 이름 변경: 자손 path 캐스케이드 | ✓ |
| depth 6 INSERT 시도: RAISE EXCEPTION 차단 | ✓ |
| 사이클 (자기 자신 parent): RAISE EXCEPTION 차단 | ✓ |

---

## Sequelize 모델

위치: `api-ventago/src/app/expense-categories/expense-category.model.ts`

핵심 associations:
- `@BelongsTo(() => ExpenseCategory, { foreignKey: 'parentId', as: 'parent' })`
- `@HasMany(() => ExpenseCategory, { foreignKey: 'parentId', as: 'children' })`

Wave 2 에서 사용할 인터페이스:
- `ExpenseCategory.findAll({ where: { storeId }, order: [['depth','ASC'],['sortOrder','ASC']] })`
- 주요 컬럼: `parentId`, `path`, `depth`, `sortOrder`, `status`, `color`, `icon`

---

## 빌드 검증

- `npx tsc --noEmit`: 에러 없음 ✓
- `npm run build` (nest build): 성공 ✓

---

## 알려진 제약사항

1. **expenses_subcategory_id 아직 DROP 안 됨**: Wave 5 cleanup 에서 제거. 두 컬럼 공존 중.
2. **기존 ExpensesCategoriesModule / ExpensesSubcategoriesModule 아직 살아있음**: Wave 4 까지 병행 운영.
3. **API/UI 는 아직 새 테이블 미사용**: Wave 2 (backend API) 에서 연결.
4. **_phase26_cat_map 정식 테이블로 남아있음**: Wave 5 cleanup 시 `DROP TABLE _phase26_cat_map`.

---

## 다음 Wave 가 사용할 인터페이스

Wave 2 (Backend API) 에서 사용:
```typescript
// 트리 조회 (flat findAll → 메모리 트리 빌드)
const flat = await ExpenseCategory.findAll({
  where: { storeId, ...(showArchived ? {} : { status: 1 }) },
  order: [['depth','ASC'], ['sortOrder','ASC'], ['name','ASC']],
});

// 모델 컬럼
// parentId, path, depth, sortOrder, status, color, icon
// name, storeId, store (BelongsTo), parent (BelongsTo), children (HasMany)
```

---

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] PRIMARY KEY with COALESCE 표현식 — SQL 문법 오류**
- **Found during:** Task 26-01-02 실행
- **Issue:** 플랜의 `PRIMARY KEY (COALESCE(old_subcat_id, 0), COALESCE(old_cat_id, 0))` 는 유효하지 않은 SQL — 표현식을 PRIMARY KEY 컬럼으로 쓸 수 없음 (PG10/PG15 모두)
- **Fix:** 정식 PK 대신 두 개의 partial UNIQUE INDEX 사용: `uq_phase26_cat_map_root` (old_subcat_id IS NULL 조건), `uq_phase26_cat_map_child` (old_subcat_id IS NOT NULL 조건). 동일한 중복 방지 효과 + ON CONFLICT DO NOTHING 정상 동작.
- **Files modified:** 26-02-step2-data.sql
- **Commit:** f4ded5f

---

## Known Stubs

없음. 이 plan 은 DB 레이어만 다루며 API/UI 는 Wave 2 에서 구현 예정.

---

## Threat Flags

없음. 새 API 엔드포인트/인증 경로/파일 접근 없음. DB 스키마 변경만.

---

## Self-Check

### Files Verified

- `api-ventago/migrations/26-01-step1-schema.sql` — FOUND ✓
- `api-ventago/migrations/26-02-step2-data.sql` — FOUND ✓
- `api-ventago/migrations/26-03-step3-fk.sql` — FOUND ✓
- `api-ventago/migrations/26-04-step4-verify.sql` — FOUND ✓
- `api-ventago/migrations/26-99-rollback.sql` — FOUND ✓
- `api-ventago/src/app/expense-categories/expense-category.model.ts` — FOUND ✓
- `api-ventago/src/app/expense-categories/expense-categories.module.ts` — FOUND ✓

### Commits Verified (api-ventago)

- `7f03bf4` feat(phase-26-01): add expense_categories table schema + trigger + indexes ✓
- `f4ded5f` feat(phase-26-01): data migration — categories → tree roots + subcategories → children ✓
- `841440a` feat(phase-26-01): add FK fk_expenses_category + idx_expenses_category ✓
- `4aae565` feat(phase-26-01): add step4 verification SQL (read-only) ✓
- `d8e2b20` feat(phase-26-01): add rollback SQL (수동 실행 전용) ✓
- `d46143a` feat(phase-26-01): add ExpenseCategory Sequelize model + module registration ✓

### Outer Repo

- `554ae8d` chore: bump api-ventago for phase 26 wave 1 (tasks 1-7) ✓

## Self-Check: PASSED
