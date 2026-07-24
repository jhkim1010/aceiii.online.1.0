---
phase: 61-tienda-online-editor
plan: 06
subsystem: ui
tags: [nextjs, typescript, react, tienda-app, storefront, css-variables]

# Dependency graph
requires:
  - phase: 61-05
    provides: "tienda-app types/shop.ts 의 SectionConfig 7종 discriminated union, shop-api.ts::listProducts sort/categoryId 파라미터, minioImageUrl"
provides:
  - "tienda-app/src/components/sections/Hero.tsx — hero 섹션 렌더 + 이미지 0/1/N장 분기(그라데이션만/정지이미지/자동캐러셀)"
  - "tienda-app/src/components/sections/Benefits.tsx — benefits 배열 렌더"
  - "tienda-app/src/components/sections/Carousel.tsx — source(newest|bestseller|category)→listProducts 매핑 + SSR initialItems 재사용"
  - "tienda-app/src/components/sections/DuoBanners.tsx — 2열 배너, href sanitizeHref 신뢰(SSOT)"
  - "tienda-app/src/components/sections/Newsletter.tsx — 로컬 표시만(백엔드 구독 엔드포인트 없음)"
  - "tienda-app/src/components/sections/SectionRenderer.tsx — section.type → 컴포넌트 switch 단일 분기점"
affects: [61-09, 61-11, 61-14]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "components/sections/*.tsx 파일 하단 const s: Record<string, CSSProperties> 상수 + var(--*) 테마 변수 — ProductCard.tsx/index.tsx 기존 관례 그대로 이어감"
    - "SectionRenderer 의 switch(section.type) 는 exhaustiveness 강제 안 함 — reels/quiz 는 default 로 떨어져 컴파일이 막히지 않음(후속 플랜이 case 추가)"

key-files:
  created:
    - tienda-app/src/components/sections/Hero.tsx
    - tienda-app/src/components/sections/Benefits.tsx
    - tienda-app/src/components/sections/Carousel.tsx
    - tienda-app/src/components/sections/DuoBanners.tsx
    - tienda-app/src/components/sections/Newsletter.tsx
    - tienda-app/src/components/sections/SectionRenderer.tsx
  modified: []

key-decisions:
  - "Hero.tsx 캐러셀 인디케이터 클릭 이동(수동 넘기기) 미구현 — 플랜에 명시되지 않았고 자동 순환만 요구됨. 후속 플랜에서 UX 피드백 있으면 추가 가능."

patterns-established:
  - "duoBanners href — 백엔드 sanitizeHref() 통과값만 저장되므로 프런트 재검증 없이 <a> 로 직접 감싼다(SSOT). 근거를 컴포넌트 내 한국어 주석으로 고정."

requirements-completed: [R4, R8]

# Metrics
duration: ~20min
completed: 2026-07-24
---

# Phase 61 Plan 06: 스토어프런트 섹션 컴포넌트(hero/benefits/carousel/duoBanners/newsletter) Summary

**content.sections 배열의 5개 기본 타입을 렌더하는 컴포넌트 6개(SectionRenderer 포함) 신규 작성 — index.tsx 하드코딩 레이아웃을 데이터 기반 섹션 조립으로 전환하기 위한 부품 확보**

## Performance

- **Duration:** ~20 min
- **Started:** 2026-07-24T12:08:00Z (추정)
- **Completed:** 2026-07-24T12:28:59Z
- **Tasks:** 3/3 완료
- **Files modified:** 6 신규

## Accomplishments
- `Hero.tsx` — `images.length` 0/1/N 분기(그라데이션만 / 정지 이미지 오버레이 / 5초 자동순환 캐러셀+인디케이터 점), `useEffect` cleanup 에서 인터벌 해제, title/subtitle 둘 다 빈값이면 `null`
- `Benefits.tsx` — `items` 배열을 그라데이션 밴드 그리드로 렌더, 이모지 아이콘 `aria-hidden`, 빈 배열이면 `null`
- `Carousel.tsx` — `source`(`newest`/`bestseller`/`category`) → `listProducts()` 파라미터 매핑, `source==='newest'` 이고 SSR `initialItems` 있으면 재조회 없이 재사용, `alive` 가드로 fetch cleanup, 로딩/빈 상태 카피는 기존 `index.tsx` 문구(`Cargando...`/`No hay productos.`) 재사용
- `DuoBanners.tsx` — 2열 그리드, 2번째(index 1) 배너는 세일 강조 그라데이션(`--hero-from`→`--gold`), `href` 는 백엔드 `sanitizeHref()` 통과값만 온다는 근거를 주석으로 남기고 프런트 재검증 없이 `<a>` 렌더
- `Newsletter.tsx` — 백엔드 구독 저장 엔드포인트가 없으므로 `onSubmit` 은 `preventDefault()` 후 로컬 state 로 성공 문구만 표시, 한국어 TODO 주석으로 후속 연동 필요성 명시
- `SectionRenderer.tsx` — `enabled=false` 는 DOM 자체를 만들지 않고, `switch(section.type)` 로 5종 컴포넌트에 분기. `reels`/`quiz` 는 `TODO(Plan 61-11)`/`TODO(Plan 61-14)` 주석과 함께 `default: return null` 로 안전하게 처리(exhaustiveness 강제 안 함, 후속 플랜이 컴파일 안 깨지고 case 추가 가능)
- 6개 파일 전부 `Record<string, CSSProperties>` 관례, 색은 CSS 변수만(`var(--on-navy)`/`var(--gold)`/`var(--muted)` 등), `dangerouslySetInnerHTML` 0건

## Task Commits

Each task was committed atomically:

1. **Task 1: Hero.tsx + Benefits.tsx** - `827a967` (feat)
2. **Task 2: Carousel.tsx + DuoBanners.tsx + Newsletter.tsx** - `f475fe9` (feat)
3. **Task 3: SectionRenderer.tsx — section.type 단일 분기점** - `2b165aa` (feat)

_이 플랜은 tienda-app 을 루트 저장소가 직접 추적(서브모듈 아님)하므로 별도 gitlink 커밋이 없다._

## Files Created/Modified
- `tienda-app/src/components/sections/Hero.tsx` (신규) - hero 섹션, 이미지 0/1/N 분기 캐러셀
- `tienda-app/src/components/sections/Benefits.tsx` (신규) - benefits 배열 렌더
- `tienda-app/src/components/sections/Carousel.tsx` (신규) - source 별 listProducts 조회 + 그리드
- `tienda-app/src/components/sections/DuoBanners.tsx` (신규) - 2열 배너(2번째 세일 강조)
- `tienda-app/src/components/sections/Newsletter.tsx` (신규) - 로컬 표시 전용(백엔드 엔드포인트 없음)
- `tienda-app/src/components/sections/SectionRenderer.tsx` (신규) - section.type switch 분기점

## Decisions Made
- Hero 캐러셀은 자동 순환만 구현(수동 이전/다음 버튼 없음) — 플랜 요구사항 그대로, 인디케이터 점은 표시용
- SectionRenderer 의 switch 는 TypeScript exhaustiveness 를 의도적으로 강제하지 않음 — reels/quiz 케이스가 아직 없어도 `npx tsc --noEmit` 이 깨지지 않도록(플랜 명시 요구사항)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Hero.tsx `clearInterval` 관련 acceptance grep 카운트 초과 → 주석 문구 수정**
- **Found during:** Task 1 (`grep -c "clearInterval"` 검증 시 카운트 2, 기대값 1)
- **Issue:** 코드 주석에 "clearInterval" 단어를 그대로 써서 실제 호출 1건 + 주석 1건 = 총 2줄 매칭
- **Fix:** 주석 문구를 "인터벌을 해제한다"로 바꿔 리터럴 텍스트 중복 제거
- **Files modified:** tienda-app/src/components/sections/Hero.tsx
- **Verification:** `grep -c "clearInterval"` == 1, `npx tsc --noEmit`/`npx eslint` 재확인 통과
- **Committed in:** `827a967` (Task 1 commit)

**2. [Rule 1 - Bug] SectionRenderer.tsx `case '` acceptance grep 카운트 초과 → TODO 주석 문구 수정**
- **Found during:** Task 3 (`grep -c "case '"` 검증 시 카운트 7, 기대값 5)
- **Issue:** reels/quiz 안내 TODO 주석에 `case 'reels'`/`case 'quiz'` 리터럴을 그대로 써서 실제 switch case 5건 + 주석 2건 = 총 7줄 매칭
- **Fix:** TODO 주석을 "reels 타입 분기 추가"/"quiz 타입 분기 추가"로 바꿔 `case '` 리터럴 제거(의미는 동일하게 유지)
- **Files modified:** tienda-app/src/components/sections/SectionRenderer.tsx
- **Verification:** `grep -c "case '"` == 5, `npx tsc --noEmit`/`npx eslint` 재확인 통과
- **Committed in:** `2b165aa` (Task 3 commit)

---

**Total deviations:** 2 auto-fixed (2 Rule 1 — acceptance grep 카운트 정합성 버그, 기능 영향 없음)
**Impact on plan:** 둘 다 코드 동작에는 영향 없는 주석 문구 조정. 스코프 크립 없음.

## Issues Encountered
None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- `SectionRenderer.tsx` 가 준비되어 있어 Plan 61-09 가 `index.tsx` 의 하드코딩 hero/promo/aistrip 블록을 `theme.content.sections.filter(s => s.enabled).map(s => <SectionRenderer storeId={storeId} section={s} initialItems={...} />)` 순회로 즉시 교체 가능
- Plan 61-11(ReelsSection)/61-14(QuizSection) 은 `SectionRenderer.tsx` 의 `TODO` 주석 위치에 `case` 만 추가하면 됨 — switch 구조 변경 불필요
- `tienda-app/src` 전체 `npx tsc --noEmit`/`npx eslint src/` exit 0 확인 — 이후 플랜이 컴파일 실패 없는 상태에서 시작 가능
- Carousel 의 `bestseller` 소스는 백엔드 `sort=bestseller` 쿼리 파라미터가 이미 Plan 61-05 에서 타입 미러됨을 전제로 함 — 실제 백엔드 집계 로직 존재 여부는 이 플랜 범위 밖(그룹 B, 별도 플랜 확인 필요)

---
*Phase: 61-tienda-online-editor*
*Completed: 2026-07-24*

## Self-Check: PASSED

- FOUND: tienda-app/src/components/sections/Hero.tsx
- FOUND: tienda-app/src/components/sections/Benefits.tsx
- FOUND: tienda-app/src/components/sections/Carousel.tsx
- FOUND: tienda-app/src/components/sections/DuoBanners.tsx
- FOUND: tienda-app/src/components/sections/Newsletter.tsx
- FOUND: tienda-app/src/components/sections/SectionRenderer.tsx
- FOUND commit: 827a967
- FOUND commit: f475fe9
- FOUND commit: 2b165aa
