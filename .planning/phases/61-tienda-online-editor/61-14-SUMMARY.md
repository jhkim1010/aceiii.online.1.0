---
phase: 61-tienda-online-editor
plan: 14
subsystem: ui
tags: [nextjs, typescript, react, tienda-app, storefront, panel-editor, quiz]

# Dependency graph
requires:
  - phase: 61-tienda-online-editor
    provides: "61-05(QuizSection/QuizQuestion 타입, listProducts 시그니처), 61-06(SectionRenderer 단일 분기점), 61-08(SectionListEditor/PanelPrimitives), 61-12(ProductCard 관례, --on-navy)"
provides:
  - "tienda-app/src/components/sections/QuizSection.tsx — 배너/질문/결과 4상태 인라인 위저드 + 답변→카탈로그 필터 매칭 + 접근성"
  - "SectionRenderer.tsx case 'quiz' — switch 7종 전부 처리"
  - "SectionListEditor.tsx quiz 편집 서브폼 — 질문/선택지 최대 4개 추가·삭제·매핑 편집"
  - "shop-api.ts listProducts()에 gender 쿼리 파라미터 지원 추가(백엔드 기존 지원 재사용)"
affects: [61-15]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "quiz 4상태는 useState 유니온 타입(QuizState) + 조건부 렌더로만 구현 — 상태머신/애니메이션 라이브러리 도입 없음(SPEC LOCKED)"
    - "표면 B 컴포넌트에서 반응형(:hover/:focus-visible/@media)이 필요할 때 globals.css 대신 Next.js 내장 styled-jsx(<style jsx>)로 컴포넌트 스코프 CSS 처리 — 신규 의존성 0, globals.css(61-12 소유) 무변경 유지"
    - "질문 key는 crypto.randomUUID().slice(0,8)로 자동 생성해 mapping과 연결, 사용자에게 노출하지 않음"

key-files:
  created:
    - tienda-app/src/components/sections/QuizSection.tsx
  modified:
    - tienda-app/src/components/sections/SectionRenderer.tsx
    - tienda-app/src/components/panel/SectionListEditor.tsx
    - tienda-app/src/services/shop-api.ts

key-decisions:
  - "listProducts()에 gender 쿼리 파라미터 타입/전달 추가 — 백엔드 shop-catalog.controller.ts가 이미 지원하는 기존 파라미터이므로 신규 엔드포인트 아님(Rule 3, 블로킹 타입 오류 해소)"
  - "quiz 결과 카드는 ProductCard.tsx 재사용 대신 UI-SPEC이 명시한 전용 DOM(MATCH 배지/매칭 이유 3줄)으로 QuizSection.tsx 내부에 직접 구현 — ProductCard는 6옵션 범용 카드이고 quiz 카드는 계약이 달라 재사용 시 옵션 우회 코드가 더 복잡해짐"
  - "포커스 링/hover/모바일 1열 그리드는 onFocus·onBlur state 대신 컴포넌트 스코프 styled-jsx로 구현(:hover, :focus-visible, @media 그대로 사용) — plan 제안(JS state 토글)보다 UI-SPEC 문구(:focus-visible{outline:2px solid var(--gold)})를 더 정확히 충족하고 globals.css는 그대로 무변경 유지"

patterns-established:
  - "styled-jsx는 globals.css를 건드리지 않고도 :hover/:focus-visible/@media를 표면 B 컴포넌트에 적용할 수 있는 합법적 탈출구(Next.js 내장, package.json 변경 없음) — 향후 플랜도 동일 패턴 재사용 가능"

requirements-completed: [R11, R8]

# Metrics
duration: ~40min
completed: 2026-07-24
---

# Phase 61 Plan 14: quiz 섹션(QuizSection.tsx) — asesor guiado 4상태 + 에디터 편집 UI Summary

**배너→질문 3개→추천 3개(MATCH 단조감소 배지)→출구 3종 흐름의 QuizSection.tsx를 신규 작성하고, 답변을 기존 listProducts 파라미터로만 변환하는 단계적 완화 매칭 로직과 에디터 질문/선택지 편집 서브폼을 구현**

## Performance

- **Duration:** ~40 min
- **Tasks:** 3/3 완료
- **Files modified:** 4 (신규 1 + 수정 3)

## Accomplishments
- `QuizSection.tsx` — `QuizState`(`banner`/`question`/`result`) 유니온 + `useState`만으로 4상태 인라인 위저드 구현. 같은 섹션 슬롯 안에서 상태 교체(전면 오버레이 아님), 질문 3단계는 `minHeight:432` 공유 컨테이너로 세로 점프 방지
- **매칭 로직**: `section.mapping`으로 답변을 `globalCategoryId`/`gender`(서버 파라미터) + `priceRange`(클라이언트 필터)로 변환 → `listProducts()` 1회 호출 → 3단계 완화(정확 매치 → 가격 조건만 완화 → 카테고리/성별까지 완화, 최대 1회 추가 호출)로 3개 채움. 신규 백엔드 엔드포인트 0건(기존 카탈로그 쿼리만 재사용)
- **MATCH 배지**: `Math.max(60, 98 - i * 6)` 순위 기반 단조감소 공식(난수 금지, 정렬 순서와 배지 숫자 일관)
- **접근성**: 질문/결과 전환 시 헤딩에 `tabIndex={-1}` + `focus()`, 진행 텍스트 `aria-live="polite"`(진행바 자체는 `aria-hidden`), 선택지는 실제 `<button>` + `aria-label="{label}. {sub}"`, `:focus-visible` 아웃라인은 컴포넌트 스코프 `<style jsx>`로 처리
- **모바일 반응형**: 질문 선택지 그리드는 `<640px`에서 1열 스택, 결과 그리드는 `≥640px`에서 정확히 3열 — 둘 다 styled-jsx `@media` 사용(globals.css 무변경)
- **출구 3종**: WhatsApp(`#25d366` 고정 예외, `contact.whatsapp` 없으면 미렌더) / Repetir quiz(상태+답변 리셋) / Ver catálogo completo(선택된 필터를 querystring으로 인코딩해 `router.push`)
- **빈 매칭(0개)**: 헤딩을 `Por ahora no tenemos algo que combine exacto`로 교체, 그리드 대신 안내문, WhatsApp 유지, 카탈로그 CTA 시각 격상(`altBtnPrimary`)
- `SectionRenderer.tsx` — `case 'quiz'` 추가로 switch 7종 전부 처리(default는 방어용으로만 남음)
- `SectionListEditor.tsx` — quiz 서브폼: 배너 제목/부제(CTA·이모지는 고정, 필드 없음), 질문 목록(최대 4, 텍스트+매핑 대상 select: `Categoría`/`Rango de precio`/`Género`), 선택지 목록(질문당 최대 4, emoji/label/sub/value — `categoryId` 매핑이면 카테고리 select, 그 외 텍스트), 질문/선택지 `✕` 삭제(확인 다이얼로그 없음, draft 단계), hint 배너
- `shop-api.ts` — `listProducts()`에 `gender` 쿼리 파라미터 지원 추가(백엔드가 이미 처리하는 기존 파라미터 재사용, quiz `gender` 매핑용)

## Task Commits

Each task was committed atomically:

1. **Task 1: QuizSection.tsx — 4상태 위저드 + 매칭 로직** - `ff0da09` (feat, shop-api.ts gender 파라미터 동반 수정)
2. **Task 2: SectionRenderer 에 case 'quiz' 추가** - `2fa18f0` (feat)
3. **Task 3: SectionListEditor quiz 편집 서브폼** - `96fc5cc` (feat)

## Files Created/Modified
- `tienda-app/src/components/sections/QuizSection.tsx` (신규) - 4상태 위저드 + 매칭 로직 + 접근성
- `tienda-app/src/components/sections/SectionRenderer.tsx` - `case 'quiz'` 분기 추가
- `tienda-app/src/components/panel/SectionListEditor.tsx` - quiz 편집 서브폼(질문/선택지 추가·삭제·매핑)
- `tienda-app/src/services/shop-api.ts` - `listProducts()` `gender` 파라미터 추가

## Decisions Made
- `listProducts()`에 `gender` 파라미터 타입 추가 — 플랜의 매칭 로직 예시가 `params.gender`를 직접 사용하는데 기존 시그니처엔 없어 컴파일이 깨짐(Rule 3). 백엔드(`shop-catalog.controller.ts`)가 이미 지원하는 파라미터이므로 신규 엔드포인트가 아니며 위협모델 T-61-71/T-61-72와 충돌하지 않음
- quiz 결과 카드는 `ProductCard.tsx`(6옵션 범용 카드) 재사용 대신 UI-SPEC 전용 DOM(MATCH 배지 + 매칭 이유 3줄 + 항상 어두운 "Agregar al carrito")으로 `QuizSection.tsx` 내부에 직접 구현
- 포커스/hover/반응형 그리드는 plan이 제안한 `onFocus`/`onBlur` state 토글 대신 컴포넌트 스코프 `<style jsx>`(Next.js 내장 styled-jsx, 신규 의존성 아님)로 구현 — UI-SPEC이 명시한 실제 `:focus-visible{outline:2px solid var(--gold); outline-offset:2px}` 셀렉터를 그대로 쓸 수 있고, `globals.css`(Plan 61-12 소유)는 전혀 건드리지 않음(diff 0줄 확인됨)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `listProducts()`에 `gender` 파라미터 타입 누락**
- **Found during:** Task 1 (QuizSection.tsx 매칭 로직 작성 중 `params.gender`를 `listProducts()`에 전달하려는데 기존 파라미터 타입에 `gender`가 없어 `npx tsc --noEmit` 실패 예상)
- **Issue:** 플랜의 매칭 로직 pseudocode가 `{ globalCategoryId?: number; gender?: string }` 파라미터를 `listProducts(storeId, { ...params, pageSize: 24 })`로 넘기지만, `shop-api.ts`의 실제 `listProducts()` 시그니처에는 `gender` 키가 없었음(백엔드는 이미 지원, 프런트 미러만 누락)
- **Fix:** `listProducts()` 파라미터 타입에 `gender?: string` 추가 + 쿼리스트링 빌드에 `if (params.gender) qs.set('gender', params.gender);` 추가. 백엔드 `shop-catalog.controller.ts`가 이미 처리하는 기존 파라미터이므로 신규 엔드포인트 0건 요구사항 위반 아님
- **Files modified:** tienda-app/src/services/shop-api.ts
- **Verification:** `npx tsc --noEmit` / `npx eslint src/` 전체 exit 0
- **Committed in:** `ff0da09` (Task 1 commit)

**2. [Rule 1 - Bug] HintBanner 텍스트 줄바꿈으로 인한 acceptance grep 실패**
- **Found during:** Task 3 (`grep -c "no se agregan productos nuevos"` 검증 시 카운트 0, 기대값 1)
- **Issue:** JSX 안에서 hint 문구를 가독성을 위해 두 줄로 나눠 썼더니(`...— no se\n              agregan productos nuevos.`) 렌더 결과는 동일하지만 소스 파일 리터럴 문자열이 줄바꿈으로 끊겨 grep이 매칭하지 못함
- **Fix:** 문구 전체를 한 줄로 합침
- **Files modified:** tienda-app/src/components/panel/SectionListEditor.tsx
- **Verification:** `grep -c "no se agregan productos nuevos"` == 1, `npx tsc --noEmit`/`npx eslint` 재확인 통과
- **Committed in:** `96fc5cc` (Task 3 commit)

---

**Total deviations:** 2 auto-fixed (1 Rule 3 — 블로킹 타입 누락, 1 Rule 1 — acceptance grep 정합성 버그, 기능 영향 없음)
**Impact on plan:** 둘 다 이 플랜의 성공 기준을 충족하기 위한 최소 수정. 스코프 크립 없음.

## Issues Encountered

- **`Ver catálogo completo →`가 실제로 필터를 적용하지 않는 사전 존재 구조 공백을 발견** — `tienda-app/src/pages/[storeId]/index.tsx`는 Plan 61-09/61-12 때부터 URL 쿼리스트링(`categoryId`/`gender`/`minPrice`/`maxPrice`)을 전혀 읽지 않는 순수 클라이언트 state 구조다. `QuizSection.tsx`는 플랜 지시대로 선택된 필터를 querystring으로 정확히 인코딩해 `router.push()`하지만, `index.tsx`가 마운트 시 이를 읽어 초기 state로 반영하는 로직이 없어 현재는 필터 미적용 상태로 카탈로그만 열린다. 이 플랜의 `files_modified`(QuizSection.tsx/SectionRenderer.tsx/SectionListEditor.tsx) 범위 밖이고 이 플랜이 만든 버그가 아니므로(SCOPE BOUNDARY) `index.tsx`는 수정하지 않고 `.planning/phases/61-tienda-online-editor/deferred-items.md`의 `## 61-14` 항목으로 기록했다. 후속 플랜에서 `index.tsx`에 초기 쿼리 읽기 배선이 필요하다(성공 기준 "Ver catálogo completo 는 선택된 필터가 적용된 카탈로그로 이동한다"의 완전한 충족을 위해).

## Known Stubs

- `tienda-app/src/pages/[storeId]/index.tsx` — quiz의 `Ver catálogo completo →` 이동 시 querystring은 올바르게 생성되지만 목적지 페이지가 이를 읽지 않아 시각적으로는 "필터 없는 일반 카탈로그"로 보인다. 원인/해결 방향은 위 "Issues Encountered" 및 `deferred-items.md` `## 61-14` 참조. 이 스텁은 이 플랜의 산출물(QuizSection.tsx)이 아니라 하위 페이지(index.tsx, 61-09/61-12 소유)의 사전 공백이므로 QuizSection.tsx 자체의 목표(4상태 위저드 동작·매칭·접근성)는 완전히 달성됐다.

## User Setup Required

None - no external service configuration required.

## Verification Notes

- `cd tienda-app && npx tsc --noEmit` — PASS (전체)
- `cd tienda-app && npx eslint src/` — PASS (전체, 0 warning/error)
- `grep -rn "Math.random" tienda-app/src/components/sections/QuizSection.tsx` — 0건
- `grep -rn "dangerouslySetInnerHTML" tienda-app/src/` — 0건
- `git diff tienda-app/src/styles/globals.css | wc -l` — 0 (이 플랜 무변경 확인)
- 브라우저 UAT(실제 quiz publish → 홈 배너 → 3문항 → 추천 3개, DevTools Network에서 `/public/shop/*/products` 요청만 있는지 확인)는 로컬 API 서버가 이 실행 환경에 기동돼 있지 않아 미실행 — 로컬/운영 UAT 시 수행 필요

## Next Phase Readiness
- `QuizSection.tsx`/`SectionRenderer.tsx`/`SectionListEditor.tsx` 완료 — Plan 61-15가 이어서 나머지 표면(marketing/trust 등) 작업 진행 가능, quiz는 이 플랜으로 완결
- 남은 게이트: 브라우저 UAT(quiz 4상태 실동작·MATCH 배지·매핑 편집 시각 확인) + `deferred-items.md` `## 61-14` 항목(`index.tsx` 쿼리 읽기 배선) 후속 처리 + 로컬/운영 API 서버 기동 후 네트워크 탭 스모크 확인

---
*Phase: 61-tienda-online-editor*
*Completed: 2026-07-24*

## Self-Check: PASSED

- FOUND: tienda-app/src/components/sections/QuizSection.tsx
- FOUND: tienda-app/src/components/sections/SectionRenderer.tsx
- FOUND: tienda-app/src/components/panel/SectionListEditor.tsx
- FOUND: tienda-app/src/services/shop-api.ts
- FOUND: .planning/phases/61-tienda-online-editor/61-14-SUMMARY.md
- FOUND: .planning/phases/61-tienda-online-editor/deferred-items.md
- FOUND commit: ff0da09
- FOUND commit: 2fa18f0
- FOUND commit: 96fc5cc
