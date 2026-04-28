# Phase 26 — Plan Review

**Verdict:** PASS-WITH-NOTES
**Reviewed:** 2026-04-27 by gsd-plan-checker

## Summary

5개 PLAN.md (31 tasks) 가 CONTEXT.md / RESEARCH.md 에 충실하게 derive 되었고 ROADMAP REQ-1~18 (18/18 커버, 1 partial) 및 Success Criteria 1~11 (11/11 커버) 를 모두 다룬다. RESEARCH 핵심 finding 12개 모두 verbatim 적용. Locked decision 13개 중 12개 완전 honor + 1개 partial (D3.2 — rename/move 흐름에 in-use 경고 누락). Blocking 0건.

## Critical Issues (blocking — must fix before execute)

**없음.**

## Must-Fix Before Execute (4 items — surgical edits, ~30분)

### S1. Wave 4 cockpit JOIN rewire 가 후속 경고로 묻혀 있음 (regression risk)
[26-04-PLAN.md](.planning/phases/26-gastos-categoria-tree-n-niveles/26-04-PLAN.md) Task 26-04-03 마지막에 *"⚠️ 기존 reportsGastoCockpit.service.ts 의 LEFT JOIN expenses_subcategories ec ON ... 를 LEFT JOIN expense_categories ON ... 로 교체"* — top-N flat 차트는 변경 없다고 명시했는데 JOIN 만 silent rewire. cockpit 의 "top categories" 의미가 root-only(depth=0) → 사용자 선택 노드(임의 depth) 로 바뀜.

**수정**: (a) atomic Task 26-04-03b 로 분리 + before/after SQL diff 명시 OR (b) Wave 5 cleanup 으로 미루기 (subcategory_id drop 시까지 기존 JOIN 동작) 중 택일.

### S2. Wave 4 expenses.module.ts 모델 등록 중복 (가능)
[26-04-PLAN.md](.planning/phases/26-gastos-categoria-tree-n-niveles/26-04-PLAN.md) Task 26-04-02 가 `SequelizeModule.forFeature([..., ExpenseCategory])` 로 중복 등록 지시. Wave 2 가 이미 `ExpenseCategoryModule` exports.

**수정**: `imports: [ExpenseCategoryModule]` 로 변경. `@InjectModel(ExpenseCategory)` 가 ExpensesService 에 실제 필요한지 grep 후 결정 (단순 association 이면 model 등록만으로 충분).

### S3. Wave 3 D&D 후 sort_order 충돌
[26-03-PLAN.md](.planning/phases/26-gastos-categoria-tree-n-niveles/26-03-PLAN.md) Task 26-03-04 `handleMove` 가 dragged node 만 새 sort_order 부여, 형제는 기존 값 유지 → 같은 값 충돌 가능.

**수정**: 드래그 후 부모의 형제 전체 fetch + 0..N-1 정규화 sequence 계산 + 단일 `PUT /expense-categories/sort/batch` 엔드포인트(Wave 2 추가) 또는 `Promise.all` 다중 PUT. plan-02 controller 범위에 batch endpoint 추가.

### S8. Wave 3 CASL `'expense-categories'` subject 미정의
[26-03-PLAN.md](.planning/phases/26-gastos-categoria-tree-n-niveles/26-03-PLAN.md) Task 26-03-04 가 `Page.acl = { action: 'manage', subject: 'expense-categories' }` 만 명시하고 register 는 executor 에게 punt. CASL 가 unregistered subject 를 deny 또는 allow 하는지 default 동작 불명확 → admin-only 보장 안 됨.

**수정**: Wave 3 에 (a) `src/configs/acl.ts` 에 `expense-categories` subject 등록 task 추가 OR (b) 기존 admin subject 재사용 결정. punt 안 됨.

## Strongly Recommended (4 items)

### S5. Wave 1 Task 26-01-02 idempotency 결함
`_phase26_cat_map` PRIMARY KEY 가 `RETURNING` 기반 매핑 → 부분 실패 후 재실행 시 두 번째 run 의 ins CTE 가 빈 row 반환, 매핑 안 채움. **수정**: 별도 backfill SELECT…JOIN…ON CONFLICT DO NOTHING 으로 변경.

### S7. PG `LIKE` injection (path 컬럼의 `_`/`%` 문자)
[26-01](.../26-01-PLAN.md) trigger 와 [26-02](.../26-02-PLAN.md) move 메서드 양쪽 `WHERE path LIKE OLD.path \|\| ' > %'` 패턴 — 카테고리 이름에 `_` 또는 `%` 가 들어가면 의도 외 매칭. **수정**: name validation 에서 `_`/`%` 거부 OR `ESCAPE '\\'` + 동적 escape.

### D3.2 partial — rename/move 흐름에 in-use 경고 누락
CONTEXT §D3.2 는 "rename/move/delete 시" 모두 in-use 경고 dialog 명시. 현재 plan 은 delete 만 다이얼로그 표시. **수정**: Wave 3 RenameInput onBlur + MoveDialog onOpen 에서 `getInUseCount` 호출 + count>0 시 confirm.

### OQ-7. Sidebar i18n key 규약
REQ-16 다국어. plan 은 `useTranslation()` 만 언급, 실제 key 명 미정. **수정**: Wave 3 시작 전 `ventago-app/src/navigation/vertical/index.ts` grep → 기존 key 규약 확인 후 plan 업데이트.

## Minor Notes (10 items)

M1 (false TDD label) / M2 (10s sleep verify) / M3 (sidebar i18n) / M4 (Task 26-04-02 atomicity) / M5 (separate-transaction 위험 진술 약함) / M6 (cockpit semantics shift) / M7 (NULL category_id 제외) / M8 (ALTER TABLE in step1 vs step2) / M9 (depth math 주석) / M10 (`null::int` 캐스트 PG10).

상세는 plan-checker 출력 참조.

## REQ Coverage: 18/18 (REQ-16 partial)
## SC Coverage: 11/11
## Locked Decisions: 12/13 (D3.2 partial)
## Research Findings: 12/12 verbatim 적용

## Recommended Action

**4개 must-fix 만 수정 후 `/gsd-execute-phase 26` 권장**. 4개 strongly recommended 도 함께 처리하면 revision loop 0회로 진행 가능성 높음. minor 10개는 execution 중 처리.

수정 영향: ~30분 surgical edit. 5-wave 구조와 dependency graph (`[]→01→02→{03,04}→05`) 는 valid, 31 tasks 적정 scope.

---
*Reviewed by gsd-plan-checker via /gsd-plan-phase 26*
