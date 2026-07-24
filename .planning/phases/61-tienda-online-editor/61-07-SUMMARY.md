---
phase: 61-tienda-online-editor
plan: 07
subsystem: ui
tags: [nextjs, typescript, css-columns, intersection-observer, tienda-app, macrostructure]

# Dependency graph
requires:
  - phase: 61-05
    provides: "tienda-app types/shop.ts 의 RailShelf/MacroSettings/HeroSection 타입, ThemeContentContext.useThemeContent(), shop-api.ts 의 listProducts 정렬/필터 파라미터"
provides:
  - "tienda-app/src/components/macro/RailsLayout.tsx — rails macrostructure 렌더러(Netflix식 선반 + IntersectionObserver lazy load + 좌우 화살표)"
  - "tienda-app/src/components/macro/MasonryLayout.tsx — masonry macrostructure 렌더러(CSS columns 그리드 + 페이지네이션 재사용 더 보기)"
  - "tienda-app/src/styles/globals.css 의 .sf-rail/.sf-masonry 클래스(미디어쿼리/의사요소/break-inside — 인라인 스타일로 표현 불가한 부분)"
affects: [61-09, 61-12, 61-13]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "행/카드 lazy load — useState<T[]|null>(null) null=미조회, []=조회완료 0건 구분 + IntersectionObserver(rootMargin) + typeof IntersectionObserver==='undefined' SSR/구형 폴백"
    - "스크롤 끝 도달 판정 — React state 재렌더 대신 scroll 이벤트에서 ref.current.style 직접 조작(passive:true 리스너 + cleanup)"
    - "CSS columns 열 수 admin 설정 주입 — 컴포넌트가 --sf-mas-cols-mobile/desktop CSS 변수만 넘기고 실제 열 배치(column-count/column-width, breakpoint)는 전부 globals.css 가 소유"

key-files:
  created:
    - tienda-app/src/components/macro/RailsLayout.tsx
    - tienda-app/src/components/macro/MasonryLayout.tsx
  modified:
    - tienda-app/src/styles/globals.css

key-decisions:
  - "MasonryLayout 이 initialItems(상위 activeCat 재조회 결과) 변경 시 items/page/done 내부 페이지네이션 상태를 useEffect 로 재동기화하도록 추가(계획에 없던 배선) — 그렇지 않으면 카테고리 필터를 바꿔도 이전 목록·이전 done 플래그가 남아 더 보기가 오작동함"
  - "globals.css :root 에 --on-navy: #ffffff 폴백을 추가(계획에 없던 추가) — 테마 조회 실패 시 cssVars 가 비어 :root 기본값만 적용되는 defaultTheme() 폴백 경로에서, RailsLayout/MasonryLayout 이 새로 참조하는 var(--on-navy) 가 미정의라 var(--navy) 배경 위 텍스트가 사라지는 것을 방지"

patterns-established:
  - "macro/*.tsx 컴포넌트는 useThemeContent() 로 macroSettings 를 직접 읽는다(props 로 내려받지 않음) — index.tsx 는 storeId/heroSection/initialItems/categories/activeCat/onCat 등 macroSettings 밖의 값만 전달"

requirements-completed: [R9, R8]

# Metrics
duration: ~20min
completed: 2026-07-24
---

# Phase 61 Plan 07: macrostructure 렌더러 RailsLayout + MasonryLayout Summary

**신규 macrostructure `rails`(Netflix식 가로 스크롤 선반 + IntersectionObserver lazy load)와 `masonry`(CSS columns 비정형 그리드 + 기존 페이지네이션 재사용 더 보기) 렌더러 2종을, 코드베이스 analog 0건 상태에서 승인 목업(`tienda-online-rails-masonry-reels-mockup.html`)과 RESEARCH 코드 스케치만 근거로 신규 구현**

## Performance

- **Duration:** ~20 min
- **Tasks:** 3/3 완료
- **Files modified:** 1 (globals.css) + 2 신규 (RailsLayout.tsx, MasonryLayout.tsx)

## Accomplishments
- `globals.css` 끝에 `.sf-rail`(스크롤바 숨김 + 카드 폭 172px/152px 미디어쿼리)과 `.sf-masonry`(CSS `columns`, `--sf-mas-cols-mobile`/`--sf-mas-cols-desktop` 변수 기반 열 수, `break-inside:avoid`) 클래스 추가 — 기존 규칙은 한 줄도 손대지 않고 순수 추가만
- `RailsLayout.tsx` 신규: 콤팩트 히어로 밴드(hero 섹션 콘텐츠 재사용) + 선반(`Rail`)별 `IntersectionObserver`(`rootMargin:'200px'`) lazy load + 좌우 화살표(28×28px, `aria-label="Anterior"`/`"Siguiente"`, 끝 도달 시 DOM 직접 조작으로 숨김) + 상품 0개 행 미노출 + `shelves` 빈 배열이면 컴포넌트 자체가 `null`(상위 그리드 폴백 여지)
- `MasonryLayout.tsx` 신규: CSS `columns` 전용(JS masonry 라이브러리 0), 카테고리 필터 chip(`stickyFilter` 연동, 활성 칩 `var(--navy)`/`var(--on-navy)`), 더 보기는 기존 `listProducts` 페이지네이션 재사용 + 하단 힌트 `IntersectionObserver`(`rootMargin:'300px'`) 트리거, `No hay productos.` 빈 상태
- tienda-app 의존성 `next`/`react`/`react-dom` 3개 그대로 — `package.json` 변경 0줄
- 색 하드코딩 0건(`grep -cE "#[0-9a-fA-F]{3,6}"` 전부 0) — `var(--*)` 토큰만 사용

## Task Commits

Each task was committed atomically:

1. **Task 1: globals.css — .sf-rail / .sf-masonry 클래스** - `9ee5235` (feat)
2. **Task 2: RailsLayout.tsx — 선반 + IntersectionObserver lazy load + 화살표** - `36d228f` (feat)
3. **Task 3: MasonryLayout.tsx — CSS columns 그리드 + 더 보기** - `247c03d` (feat)

_`tienda-app` 은 루트 저장소가 직접 추적(서브모듈 아님)하므로 별도 gitlink 커밋이 없다._

## Files Created/Modified
- `tienda-app/src/styles/globals.css` - `.sf-rail`/`.sf-masonry` 클래스 신설 + `:root` 에 `--on-navy` 폴백 추가(43줄 순수 추가, 삭제 0)
- `tienda-app/src/components/macro/RailsLayout.tsx` (신규) - `RailsLayout`(기본 export) + 내부 `Rail`/`useIsDesktopViewport`/`hrefForShelf`
- `tienda-app/src/components/macro/MasonryLayout.tsx` (신규) - `MasonryLayout`(기본 export)

## Decisions Made
- `MasonryLayout` 의 내부 페이지네이션 상태(`items`/`page`/`done`)를 `initialItems` 변경(상위의 카테고리 필터 재조회 결과)에 맞춰 재동기화하는 `useEffect` 추가 — Key-decisions 참조.
- `globals.css` `:root` 에 `--on-navy` 폴백 추가 — Key-decisions 참조.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] MasonryLayout 내부 페이지네이션 상태가 initialItems 변경에 재동기화되지 않는 문제 사전 차단**
- **Found during:** Task 3 설계 중 (`initialItems`/`activeCat`/`onCat` 이 controlled prop 으로 명시된 인터페이스를 분석하며 발견)
- **Issue:** `items`/`page`/`done` 을 `useState(initialItems...)` 초기값으로만 설정하면, 상위(index.tsx, 향후 Plan 61-09)가 카테고리 필터 변경으로 `initialItems` 를 새로 전달해도 React 는 `useState` 초기값을 재평가하지 않으므로 이전 페이지 목록·이전 `done` 플래그가 그대로 남는다. 필터를 바꿔도 화면에 이전 카테고리 상품이 계속 보이거나, 이미 `done=true` 였던 필터에서 새 필터로 전환해도 더 보기가 트리거되지 않는 버그가 된다.
- **Fix:** `initialItems`/`ms.firstLoad` 를 deps 로 하는 `useEffect` 를 추가해 변경 시 `items`/`page`/`done` 을 초기 상태로 재설정.
- **Files modified:** tienda-app/src/components/macro/MasonryLayout.tsx
- **Verification:** `npx tsc --noEmit` exit 0, `npx eslint src/components/macro/` exit 0
- **Committed in:** `247c03d` (Task 3 commit)

**2. [Rule 2 - Missing critical functionality] globals.css :root 에 --on-navy 폴백 누락**
- **Found during:** Task 1 (globals.css 편집 전 `:root` 전체를 읽으며, `RailsLayout`/`MasonryLayout` 이 `var(--on-navy)` 를 신규로 참조하게 될 것을 확인)
- **Issue:** `--on-navy` 는 Plan 61-05 에서 `tokensToCssVars()`(테마 정상 조회 시)에만 추가됐고, `index.tsx` 의 `defaultTheme()` 폴백 경로(`cssVars: {}`)는 `globals.css` `:root` 기본값에 의존한다. `:root` 에 `--on-navy` 가 없으면 테마 조회 실패 시 `var(--navy)` 배경 위 텍스트(예: rails 히어로 밴드 제목, masonry 활성 칩 텍스트)가 미정의 색상으로 렌더되어 사실상 보이지 않는 회귀가 됨(공개몰은 "절대 깨지지 않아야 한다"는 `defaultTheme()` 주석의 불변조건 위반).
- **Fix:** `:root` 에 `--on-navy: #ffffff;` 추가(한 줄, 기존 값 변경 없음).
- **Files modified:** tienda-app/src/styles/globals.css
- **Verification:** `git diff` 로 삭제 0줄(순수 추가) 확인, `npx tsc --noEmit`/`npx eslint src/` 통과
- **Committed in:** `9ee5235` (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (1 Rule 1 필터 상태 재동기화 버그, 1 Rule 2 CSS 변수 폴백 누락)
**Impact on plan:** 계획이 명시하지 않은 최소 배선만 추가. 두 항목 모두 이 플랜이 신설하는 파일/변수 자체의 정합성을 지키기 위한 것으로 스코프 크립 없음.

## Issues Encountered
- Task 1 acceptance criterion `git diff tienda-app/src/styles/globals.css | grep -c "^-"` 는 실제로 1을 반환한다(요구값 0) — 원인은 diff 헤더 줄(`--- a/tienda-app/...`)이 `^-` 패턴에 걸리는 것뿐이고, 실제 콘텐츠 삭제는 0줄이다(diff 본문을 직접 확인해 `+`만 존재함을 검증함). 이 grep 패턴의 알려진 오탐 — 61-05-SUMMARY.md 의 유사 사례(Issues Encountered)와 동일한 성격.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- `RailsLayout`/`MasonryLayout` 컴포넌트는 완성됐으나 **이 플랜 범위에서 `index.tsx` 최상위 렌더 분기에 연결되지 않았다** — `theme.macrostructure === 'rails' ? <RailsLayout .../> : theme.macrostructure === 'masonry' ? <MasonryLayout .../> : ...` 형태의 배선은 후속 플랜(PATTERNS.md 그룹 G, Plan 61-09 추정)이 담당.
- `MasonryLayout` 은 `storeId`/`initialItems`/`categories`/`activeCat`/`onCat` 을 controlled prop 으로 요구 — 배선 플랜은 `index.tsx` 기존 `activeCat`/`items` state 를 그대로 전달하면 된다(신규 state 불필요).
- `RailsLayout` 은 `heroSection`(선택)만 받고 `macroSettings.rails` 는 `useThemeContent()` 로 스스로 읽으므로, 배선 플랜은 `theme.content.sections.find(s => s.type === 'hero')` 를 넘기기만 하면 된다.
- masonry 열 우선(column-major) 정렬 힌트 카피(`El orden en Masonry se ve por columna...`)는 표면 A(에디터) 몫이며 Plan 61-13(구조 선택 UI) 범위 — 이 플랜은 렌더러만 구현.
- `ProductCard.tsx` 는 이 플랜에서 수정하지 않음(`imgwrap` 고정 높이 230px 유지) — masonry `keepRatio=true` 실제 이미지 비율 반영은 Plan 61-12 가 `ProductCard` 를 확장할 때 완성됨(코드에 `TODO(Plan 61-12)` 로 명시).

---
*Phase: 61-tienda-online-editor*
*Completed: 2026-07-24*

## Self-Check: PASSED

- FOUND: tienda-app/src/components/macro/RailsLayout.tsx
- FOUND: tienda-app/src/components/macro/MasonryLayout.tsx
- FOUND: tienda-app/src/styles/globals.css
- FOUND commit: 9ee5235
- FOUND commit: 36d228f
- FOUND commit: 247c03d
