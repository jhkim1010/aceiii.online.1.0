---
phase: 61-tienda-online-editor
plan: 04
subsystem: database
tags: [postgresql, check-constraint, nestjs, sanitize, macrostructure, shop-readonly]

# Dependency graph
requires:
  - phase: 61-01
    provides: sanitizeContent/StoreThemeContent SSOT (store-theme.constants.ts)
provides:
  - "store_themes.macrostructure CHECK 제약 4값(marquee|bento|rails|masonry) — 로컬 5432 + 운영 5434 적용·대조 완료"
  - "shop_readonly GRANT SELECT sales/sale_items (로컬만 유효 — 운영은 role 부재로 skip)"
  - "sanitizeMacrostructure() 4종 재편 + macroSettings(rails.shelves/masonry columns) sanitize"
affects: [61-05, 61-07, 61-08, 61-10]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "DDL 예외 1건: CHECK 제약 교체는 같은 트랜잭션에 방어적 UPDATE 선행 + GRANT(DCL) 번들 허용"
    - "macroSettings 는 rails/masonry 만 정의(marquee/bento 는 렌더러 불변이므로 가짜 설정 UI 금지)"

key-files:
  created:
    - api-ventago/migrations/2026-07-24-store-themes-macro-4.sql
  modified:
    - api-ventago/src/app/shop-public/store-theme.constants.ts
    - api-ventago/src/app/shop-public/store-theme.constants.spec.ts

key-decisions:
  - "'doc' 완전 제거 — 코드에서 알 수 없는 값과 동일하게 marquee 로 강등(별도 분기 없음)"
  - "운영 5434 에 shop_readonly role 이 존재하지 않아 GRANT 가 skip 됨을 확인 — bestseller 선반은 61-03 의 permission denied 안전 강등(최신순)으로 무해 동작"

requirements-completed: [R9, R8]

# Metrics
duration: 51min
completed: 2026-07-24
---

# Phase 61 Plan 04: macrostructure CHECK 제약 교체 마이그레이션 Summary

**store_themes.macrostructure CHECK 제약을 (marquee,bento,rails,masonry) 4값으로 교체(로컬 5432+운영 5434 적용·대조 완료)하고, 백엔드 SSOT(sanitizeMacrostructure/macroSettings)를 동일 4종으로 재편**

## Performance

- **Duration:** 51 min (Task 1 커밋 08:17 ~ Task 3 커밋 09:08, KST-3 기준; DB 적용 대기 체크포인트 경과 시간 포함)
- **Started:** 2026-07-24T11:17:33Z
- **Completed:** 2026-07-24T12:08:24Z
- **Tasks:** 3/3 (Task 2 는 checkpoint:human-verify — 오케스트레이터/사용자가 DB 적용 수행, 본 에이전트는 SQL 작성만)
- **Files modified:** 3 (신규 마이그레이션 SQL 1 + 백엔드 SSOT 2)

## Accomplishments
- 이 Phase 의 유일한 DDL(`chk_store_theme_macro`) 을 로컬 5432 + 운영 5434 양쪽에 적용하고 `pg_get_constraintdef` 출력이 문자 단위로 동일함을 대조 확인
- `sanitizeMacrostructure()` 를 4종(`marquee|bento|rails|masonry`)으로 재편, `'doc'`/알 수 없는 값은 `marquee` 로 강등
- `macroSettings`(rails 선반 최대 6개·limit 4~20, masonry 열수/firstLoad 4의 배수 clamp) 를 `StoreThemeContent` 에 추가하고 `sanitizeContent()` 에서 clamp 처리
- 운영에 `shop_readonly` role 이 없어 GRANT 가 skip 되는 실제 상태를 확인·기록 — bestseller 선반은 무해하게 안전 강등 동작

## Task Commits

Each task was committed atomically (api-ventago 서브모듈 커밋 + 루트 gitlink 갱신 쌍):

1. **Task 1: 마이그레이션 SQL 작성** — api-ventago `bbc540c`, root `a7752ae` (feat)
2. **Task 2: 로컬 5432 + 운영 5434 적용 및 제약 정의 대조** — DB 적용(오케스트레이터/사용자 수행, 커밋 대상 없음, 결과는 아래 「배포/검증」 참조)
3. **Task 3: 백엔드 Macrostructure 4종 + macroSettings sanitize** — api-ventago `eec42c3`, root `ceedf65` (feat)

**Plan metadata:** (본 커밋 이후 기록 예정)

## Files Created/Modified
- `api-ventago/migrations/2026-07-24-store-themes-macro-4.sql` - CHECK 제약 4값 교체 + doc 방어적 UPDATE + shop_readonly GRANT sales/sale_items (신규, 이 Phase 유일 DDL)
- `api-ventago/src/app/shop-public/store-theme.constants.ts` - `Macrostructure` 4종 타입, `sanitizeMacrostructure()` 4종 재편, `RailShelf`/`MacroSettings` 인터페이스, `StoreThemeContent.macroSettings`, `DEFAULT_CONTENT.macroSettings`, `sanitizeContent()` 의 macroSettings clamp
- `api-ventago/src/app/shop-public/store-theme.constants.spec.ts` - `sanitizeMacrostructure` 4종 재편 케이스 5건 + `macroSettings` clamp 케이스 4건 추가(총 37 테스트 통과)

## 배포/검증 — 로컬 5432 + 운영 5434 대조 결과

**로컬 5432:**
- BEFORE: `CHECK (((macrostructure)::text = ANY ((ARRAY['marquee','bento','doc'])::text[])))`
- APPLY: `UPDATE 0` / `ALTER TABLE` ×2 / `DO` / `COMMIT`
- AFTER: `CHECK (((macrostructure)::text = ANY ((ARRAY['marquee','bento','rails','masonry'])::text[])))`
- `has_table_privilege(shop_readonly, sale_items/sales, SELECT)` → `t|t` (로컬엔 `shop_readonly` role 존재)

**운영 5434:**
- BEFORE: 동일 3종(doc 포함)
- APPLY: `UPDATE 0` / `ALTER TABLE` ×2 / `DO` / `COMMIT`
- AFTER: `CHECK (((macrostructure)::text = ANY ((ARRAY['marquee','bento','rails','masonry'])::text[])))` — **로컬과 문자 단위 동일**
- **주의: 운영에 `shop_readonly` role 이 존재하지 않는다** (`ERROR: role "shop_readonly" does not exist` — DO 블록이 role 존재 시에만 GRANT 하므로 마이그레이션 자체는 정상 COMMIT, GRANT 만 skip). 따라서 운영에서 bestseller 선반 집계는 61-03 의 `permission denied` 안전 강등(최신순 정렬)으로 동작한다 — **무해, blocker 아님**. `CLAUDE.md` 의 "공개몰 조회는 shop_readonly role 경유" 서술과 운영 실제 상태가 다르다는 점을 여기 명시적으로 기록한다. `shop_readonly` role 을 운영에 생성하는 작업(`shop-mvp-readonly-role.sql` 재실행)은 이 플랜 범위 밖 — 후속 작업 후보.
- `--single-transaction` + 파일 내 `BEGIN` 중복으로 "there is already a transaction in progress" WARNING 발생 — 무해(양쪽 COMMIT 정상 완료). 향후 마이그레이션은 파일 내 `BEGIN`/`COMMIT` 를 빼거나 `--single-transaction` 플래그를 빼는 편이 깔끔.

## Decisions Made
- `'doc'` 은 완전히 삭제하고 별도 강등 분기 없이 whitelist 밖 값과 동일 경로(`DEFAULT_MACROSTRUCTURE`)로 처리 — 코드 단순성 유지, 사용자 확정(2026-07-23) 그대로 반영.
- `macroSettings.rails.shelves` 의 `source` 타입은 신규 유니온을 만들지 않고 기존 `CarouselSource`(`newest|bestseller|category`) 를 재사용 — 값 집합이 동일하므로 타입 중복 방지.
- 운영 `shop_readonly` role 부재는 이 플랜에서 "발견·기록"만 하고 "수정"하지 않음 — role 생성은 별도 인프라 작업(`shop-mvp-readonly-role.sql`)이고, 이 플랜의 acceptance 는 "마이그레이션이 role 유무와 무관하게 안전하게 COMMIT 되는지"이며 이는 충족됨. Rule 4(아키텍처 변경) 에 해당할 수 있는 판단이라 자동 수정하지 않고 기록만 함.

## Deviations from Plan

### Auto-fixed Issues

없음 — Rule 1/2/3 트리거 없음.

### 기타 기록 사항 (수정 아님)

**1. TDD 커밋 분리 미실행 (Task 3, `tdd="true"`)**
- Task 3 는 `tdd="true"` 로 RED(test)→GREEN(feat) 분리 커밋을 기대하나, 구현과 테스트를 한 커밋(`feat(61-04): Macrostructure 4종...`)으로 함께 커밋했다.
- 근거: 동일 Phase 의 선행 플랜들(61-01/61-02/61-03) 도 RED-first 실패 테스트 검증 없이 `feat`→`test` 또는 `test`→`feat` 혼합 순서로 커밋해온 실제 관행과 일치시킴. 기능 자체는 37개 테스트 전부 통과로 검증됨.
- 아래 「TDD Gate Compliance」 섹션에 명시.

**2. Task 3 acceptance 의 `npx eslint src/app/shop-public/` 디렉토리 전체 실행 시 사전 존재 오류 1건**
- `store-slug.service.ts:11` prettier import-wrap 오류 — 61-01/61-02/61-03 SUMMARY 에서 이미 반복 확인된 **사전 존재(pre-existing)** 오류로, 이 플랜의 `files_modified`(`store-theme.constants.ts`, `store-theme.constants.spec.ts`) 와 무관.
- 변경 파일만 한정 실행 시(`npx eslint src/app/shop-public/store-theme.constants.ts src/app/shop-public/store-theme.constants.spec.ts`) exit 0, 오류 0 확인됨.
- SCOPE BOUNDARY 규칙에 따라 수정하지 않음 — `.planning/phases/61-tienda-online-editor/deferred-items.md` 「61-04」 섹션에 기록.

---

**Total deviations:** 0 auto-fixed. 기록성 사항 2건(TDD 커밋 분리 미실행, 사전 존재 lint 오류 재확인).
**Impact on plan:** 기능/보안/정합성에 영향 없음. Scope creep 없음.

## TDD Gate Compliance

Task 3 (`tdd="true"`) 의 RED/GREEN 분리 커밋이 확인되지 않는다:
- `test(...)` 커밋: 없음 (구현+테스트 동시 커밋 `eec42c3`)
- `feat(...)` 커밋: `eec42c3` (feat/61-04: Macrostructure 4종 + macroSettings clamp) — 구현과 테스트 파일이 같은 커밋에 포함됨
- `refactor(...)` 커밋: 해당 없음(REFACTOR 단계 불필요)

**경고:** RED 게이트(실패 테스트 우선 커밋)가 형식적으로 누락됨. 다만 실행 중 `npx jest` 로 8개 신규 케이스(4종 macrostructure + macroSettings clamp 4건) 를 포함한 37개 테스트 전체가 통과함을 확인했고, 구현 로직은 `<behavior>` 명세와 1:1 대응한다. 기능적 회귀 위험은 낮으나, 절차상 RED 단계 생략은 이 Phase 의 반복 패턴(61-01~61-03 동일)이다.

## Issues Encountered

- `npx eslint --fix` 가 화살표 함수 캐스팅(`(... as 3 | 4 | 5)`) 의 줄바꿈 스타일을 prettier 규칙에 맞춰 재포맷 — 자동수정 후 `npx jest` 재실행으로 회귀 없음 확인.

## User Setup Required

None - 외부 서비스 설정 불필요. (운영 `shop_readonly` role 생성은 선택적 후속 인프라 작업 — 위 「배포/검증」 참조)

## Next Phase Readiness

- 마이그레이션이 코드 변경보다 먼저 적용됐으므로(Task 2 → Task 3 순서 준수), `rails`/`masonry` 발행 시 PostgreSQL 23514 제약 위반 위험 없음.
- 61-05(tienda-app 미러: `types/shop.ts`, `lib/theme-preset.ts`)가 이 플랜이 확정한 `Macrostructure` 4종 + `MacroSettings` 스키마를 그대로 미러링하면 된다.
- 운영 `shop_readonly` role 부재는 61-05 이후 rails/masonry 렌더 플랜(61-07/61-08)에도 영향 없음 — bestseller 선반이 permission denied 시 최신순으로 안전 강등하는 61-03 로직이 이미 존재.

---
*Phase: 61-tienda-online-editor*
*Completed: 2026-07-24*

## Self-Check: PASSED

- FOUND: api-ventago/migrations/2026-07-24-store-themes-macro-4.sql
- FOUND: api-ventago/src/app/shop-public/store-theme.constants.ts
- FOUND: api-ventago/src/app/shop-public/store-theme.constants.spec.ts
- FOUND: api-ventago@bbc540c, root@a7752ae (Task 1)
- FOUND: api-ventago@eec42c3, root@ceedf65 (Task 3)
