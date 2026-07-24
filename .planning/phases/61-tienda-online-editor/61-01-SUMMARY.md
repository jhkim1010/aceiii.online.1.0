---
phase: 61-tienda-online-editor
plan: 01
subsystem: api
tags: [nestjs, typescript, jsonb, sanitize, xss, store-theme, jest]

# Dependency graph
requires: []
provides:
  - "store-theme.constants.ts 의 StoreThemeContent 전체 스키마 + DEFAULT_CONTENT + sanitizeContent()"
  - "saveDraft()/getDraft()/getPublicTheme() 3개 지점에 sanitizeContent 배선 완료"
  - "tokensToCssVars() 의 --on-navy CSS 변수"
  - "publish() 유일 쓰기 경로 불변조건 주석 (T-61-05 Elevation 완화)"
affects: [61-02, 61-03, 61-04, 61-05, 61-06, 61-07, 61-08, 61-09, 61-10]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "whitelist+clamp+default sanitize 함수 — 원본 sanitizeTokens()/clamp() 철학을 콘텐츠 확장 키까지 그대로 이어감"
    - "cloneDefaultContent() = JSON.parse(JSON.stringify(DEFAULT_CONTENT)) — 상수 오염 방지 deep clone"
    - "buildThemeResponse() 마지막 옵셔널 파라미터로 하위호환 확장 (rawContent = null 기본값)"

key-files:
  created:
    - api-ventago/src/app/shop-public/store-theme.constants.spec.ts
  modified:
    - api-ventago/src/app/shop-public/store-theme.constants.ts
    - api-ventago/src/app/shop-public/store-theme-admin.service.ts
    - api-ventago/src/app/shop-public/store-theme-admin.controller.ts
    - api-ventago/src/app/shop-public/store-theme.service.ts

key-decisions:
  - "Task 1과 Task 2를 store-theme.constants.ts 에 한해 단일 커밋으로 병합 — 헬퍼(sanitizeHref/clampText/sanitizeFileName)가 Task 1에서 선언되고 Task 2(sanitizeContent)에서 처음 사용되므로, 계획대로 분리하면 Task 1 커밋 시점에 @typescript-eslint/no-unused-vars 에러로 그 자체 acceptance(eslint exit 0)를 통과할 수 없음. 다른 3개 파일(admin.service/controller/service.ts)은 계획대로 Task 2에 포함해 함께 커밋"
  - "productCard.installments 기본값 true — 현행 ProductCard.tsx 의 cuotas() 항상 렌더 무회귀 근거를 주석으로 명문화"
  - "publish() 쿼리 자체는 무변경, saveDraft() 유일 쓰기 경로 불변조건만 주석으로 명문화 (SPEC 경고 그대로 반영)"

patterns-established:
  - "SectionConfig 판별 유니온(discriminated union) + sanitizeSection() switch(r.type) 패턴 — 후속 렌더러(Wave A/B) 가 동일 타입을 그대로 소비"

requirements-completed: [R1, R5, R6, R7, R10, R11, R8]

# Metrics
duration: ~30min
completed: 2026-07-24
---

# Phase 61 Plan 01: 백엔드 콘텐츠 확장 SSOT (sanitizeContent) Summary

**store-theme.constants.ts 에 brand/announce/sections 7종/contact/productCard/catalog/trust/marketing 전체 콘텐츠 스키마 + whitelist·clamp 가드레일(sanitizeContent)을 신설하고 saveDraft/getDraft/getPublicTheme 3개 지점에 배선, `--on-navy` CSS 변수 추가, 28개 유닛테스트로 acceptance 고정**

## Performance

- **Duration:** ~30 min
- **Completed:** 2026-07-24T10:47:45Z
- **Tasks:** 3/3 완료
- **Files modified:** 4 (constants/admin.service/admin.controller/service) + 1 신규(spec)

## Accomplishments
- `StoreThemeContent` 전체 타입(7개 섹션 discriminated union 포함) + `DEFAULT_CONTENT`(현행 index.tsx/Header.tsx 하드코딩 값 그대로 이관 — 기존 매장 무회귀) 신설
- `sanitizeHref`/`clampText`/`sanitizeFileName` 헬퍼 + `sanitizeSection()`(7종) + `sanitizeContent()` 전체 whitelist·clamp·XSS 방어 가드레일 구현
- `buildThemeResponse()` → `getPublicTheme`/`getDraft`/`saveDraft` 3개 호출부 배선, `SaveDraftBody`/`SaveThemeBody` 에 `content?` 필드 추가
- `tokensToCssVars()` 에 `--on-navy: '#ffffff'` 고정 변수 추가
- `publish()` 유일 쓰기 경로 불변조건을 주석으로 명문화(쿼리 자체는 무변경 — `git diff` 로 확인)
- `store-theme.constants.spec.ts` 신규(shop-public 모듈 최초 스펙 파일) — 28개 테스트로 R1/R6/R7/R10/R11 acceptance 고정, 전부 통과

## Task Commits

1. **Task 1+2 (병합): 헬퍼/타입/DEFAULT_CONTENT/--on-navy + sanitizeContent 본체 + 배선** - `231e60f` (feat)
2. **Task 3: store-theme.constants.spec.ts 신규** - `bd076d0` (test)

**Root gitlink:** `90be79e` (chore: api-ventago 서브모듈 포인터 갱신)

_두 백엔드 커밋 모두 api-ventago 서브모듈 안에서 이루어졌고, 루트 저장소는 gitlink 포인터 갱신 1개 커밋으로 반영._

## Files Created/Modified
- `api-ventago/src/app/shop-public/store-theme.constants.ts` - StoreThemeContent 스키마 + DEFAULT_CONTENT + sanitizeSection/sanitizeContent + buildThemeResponse content 배선 + --on-navy
- `api-ventago/src/app/shop-public/store-theme-admin.service.ts` - saveDraft()에 sanitizeContent 경유 + flat 병합(`...tokens, ...content`) + getDraft() content 배선 + publish() 불변조건 주석
- `api-ventago/src/app/shop-public/store-theme-admin.controller.ts` - `SaveThemeBody.content?` 필드 추가 (라우트 로직 무변경)
- `api-ventago/src/app/shop-public/store-theme.service.ts` - `getPublicTheme()` 성공/폴백/에러 3개 경로 모두 content 배선
- `api-ventago/src/app/shop-public/store-theme.constants.spec.ts` (신규) - 28개 유닛테스트 (하위호환/clamp/XSS/화이트리스트/reels poster/불변조건 6개 그룹)

## Decisions Made
- Task 1·2 커밋 병합(store-theme.constants.ts 한정) — 계획된 3-task 분리는 헬퍼 선언과 사용 시점이 다른 두 태스크로 나뉘어 있어, Task 1 단독 커밋 시점에 `no-unused-vars` 에러로 그 자체 verify(`npx eslint` exit 0)를 통과할 수 없는 구조적 문제 발견. 두 태스크가 논리적으로 한 함수(`sanitizeContent`)를 완성하는 과정이라는 계획 목적("왜 한 플랜에 전 키를 넣는가")과도 일치해 병합이 타당하다고 판단
- `sanitizeMacrostructure()`는 계획 지시대로 무변경(여전히 `marquee|bento|doc` 3종) — 4종 재편은 Plan 61-04 범위

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Task 1/2 커밋 경계를 store-theme.constants.ts 한정으로 병합**
- **Found during:** Task 1 완료 직후 verify (`npx eslint src/app/shop-public/store-theme.constants.ts`)
- **Issue:** 계획대로 Task 1만 커밋하면 `PIXEL_ID_RE`/`sanitizeHref`/`clampText`/`sanitizeFileName` 이 아직 미사용 상태라 `@typescript-eslint/no-unused-vars` 에러 4건 발생 — Task 1 자체의 acceptance criteria(`eslint exit 0`)를 통과할 수 없음
- **Fix:** store-theme.constants.ts 에 한해 Task 1+2 코드를 모두 작성한 뒤 단일 커밋으로 처리. 다른 3개 파일(admin.service/controller/theme.service)은 원래 Task 2 소속 그대로 같은 커밋에 포함
- **Files modified:** store-theme.constants.ts, store-theme-admin.service.ts, store-theme-admin.controller.ts, store-theme.service.ts
- **Verification:** `npx eslint src/app/shop-public/store-theme.constants.ts src/app/shop-public/store-theme-admin.service.ts src/app/shop-public/store-theme-admin.controller.ts src/app/shop-public/store-theme.service.ts` exit 0, Task 1/2 acceptance criteria 전체(grep 9건) 통과
- **Committed in:** `231e60f`

**2. [Rule 1 - Bug] store-theme-admin.service.ts:70 불필요한 타입 단언 제거**
- **Found during:** Task 2 verify (`npx eslint src/app/shop-public/`)
- **Issue:** `cfg as Record<string, unknown> | null` — `cfg` 가 이미 `Record<string, unknown> | null` 로 추론되어 `@typescript-eslint/no-unnecessary-type-assertion` 에러 발생
- **Fix:** 불필요한 캐스트 제거, `cfg` 그대로 전달
- **Files modified:** store-theme-admin.service.ts
- **Verification:** `npx eslint` exit 0
- **Committed in:** `231e60f`

---

**Total deviations:** 2 auto-fixed (1 블로킹 커밋경계 조정, 1 lint 버그)
**Impact on plan:** 코드 내용은 계획과 100% 동일(전 필드·전 헬퍼·전 배선 지점 구현). 커밋 경계만 파일 단위로 재조정. 스코프 크립 없음.

## Issues Encountered
- `api-ventago/.git/index.lock` stale lock (관련 없는 시스템 프로세스가 보유, 활성 git 프로세스 없음 확인 후 제거) — 알려진 패턴(레포 메모리 `reference_git_lock_contention.md`)과 일치, 작업에 실질적 영향 없음

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `sanitizeContent()` 이 SSOT 에 존재하고 saveDraft가 이를 경유 — Wave A/B/C 의 모든 후속 플랜(61-02~61-15)이 이 계약 위에서 렌더러/에디터 UI를 구현 가능
- `--on-navy` CSS 변수가 SSOT 에서 방출되므로 후속 프런트 플랜이 하드코딩 없이 재사용 가능
- 확장 키 없는 legacy `published_tokens` 로 `buildThemeResponse()` 호출 시 현행과 완전 동일 + content default — 61-SPEC.md R1/R4/R8 무회귀 게이트 충족
- `sanitizeMacrostructure()` 는 여전히 3종(`marquee|bento|doc`) — Plan 61-04 가 4종 재편 + DB CHECK 마이그레이션을 담당해야 함(이 플랜은 건드리지 않음, 계획대로)
- `api-ventago/src/app/shop-public/store-slug.service.ts:11` 의 pre-existing prettier 에러는 이 플랜 범위 밖 — `.planning/phases/61-tienda-online-editor/deferred-items.md` 에 기록

---
*Phase: 61-tienda-online-editor*
*Completed: 2026-07-24*

## Self-Check: PASSED

- 모든 생성/수정 파일 존재 확인 (5개 소스 + SUMMARY + deferred-items)
- 모든 커밋 해시 확인 (api-ventago: 231e60f, bd076d0 / 루트: 90be79e)
