---
phase: 61-tienda-online-editor
plan: 05
subsystem: ui
tags: [nextjs, typescript, react-context, tienda-app, store-theme]

# Dependency graph
requires:
  - phase: 61-01
    provides: "store-theme.constants.ts 의 StoreThemeContent 전체 스키마 + sanitizeContent()"
  - phase: 61-03
    provides: "priceOrig/stock DTO + sort/showOutOfStock/minPrice/maxPrice 카탈로그 쿼리 파라미터"
  - phase: 61-04
    provides: "Macrostructure 4종(marquee|bento|rails|masonry) + macroSettings 스키마"
provides:
  - "tienda-app/src/types/shop.ts 의 StoreThemeContent/SectionConfig 7종/MacroSettings/CatalogSort 백엔드 미러"
  - "tienda-app/src/lib/theme-preset.ts 의 MACRO_OPTIONS 4종 + GATED_BY_MACRO SSOT + DEFAULT_CONTENT"
  - "shop-api.ts 의 listProducts 정렬/필터 파라미터, uploadThemeAsset, withContentFallback 안전망"
  - "ThemeContentProvider/useThemeContent() 단일 진입점 (Provider 밖에서도 DEFAULT_CONTENT 반환)"
  - "tienda-app 전체에서 'doc' 렌더 분기 제거 완료(R9)"
affects: [61-06, 61-07, 61-08, 61-09, 61-10, 61-11, 61-12, 61-13, 61-14, 61-15]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "ThemeContentContext — createContext(DEFAULT_CONTENT) 기본값으로 Provider 밖 호출도 안전. Provider value 는 useMemo."
    - "GATED_BY_MACRO 단일 소유지를 theme-preset.ts 로 고정 — 후속 플랜(index.tsx 렌더 게이팅, SectionGatingChips.tsx 에디터 안내)이 동일 상수를 import"
    - "withContentFallback() — 구버전/오류 응답에 content 누락 시 DEFAULT_CONTENT 로 채우는 얇은 .then() 래퍼, 3개 API 호출 지점에 배선"

key-files:
  created:
    - tienda-app/src/context/ThemeContentContext.tsx
  modified:
    - tienda-app/src/types/shop.ts
    - tienda-app/src/lib/theme-preset.ts
    - tienda-app/src/services/shop-api.ts
    - tienda-app/src/pages/[storeId]/index.tsx
    - tienda-app/src/pages/[storeId]/panel/diseno.tsx

key-decisions:
  - "diseno.tsx 에 content state 신설(계획에 없던 추가) — Task 2 에서 SaveThemeBody.content 를 필수 필드로 만들었기 때문에, 색/토큰만 저장하는 이 화면이 초안 로드 시 받은 content 를 보존하지 않으면 저장할 때마다 매장의 섹션 설정이 DEFAULT_CONTENT 로 덮어써지는 데이터 손실 버그가 발생함(Rule 1). 편집 UI는 추가하지 않고 통과만 시킴 — content 편집 UI 자체는 Plan 61-08/61-11 범위 그대로 유지."

patterns-established:
  - "GATED_BY_MACRO: Record<Macrostructure, SectionType[]> — 구조별 비활성 섹션 규칙의 단일 소유지, 렌더 게이팅과 에디터 안내가 이 상수 하나로 항상 일치하도록 강제"

requirements-completed: [R1, R2, R5, R6, R9, R8]

# Metrics
duration: ~25min
completed: 2026-07-24
---

# Phase 61 Plan 05: tienda-app 타입/API/컨텍스트 미러 + doc 제거 Summary

**tienda-app 의 types/shop.ts·theme-preset.ts·shop-api.ts 를 백엔드 store-theme.constants.ts 계약(StoreThemeContent 전체 스키마·Macrostructure 4종·priceOrig/stock·sort/filter 파라미터·에셋 업로드)과 필드 단위로 동일하게 미러링하고, ThemeContentContext 단일 진입점을 신설하며 tienda-app 전체에서 'doc' 렌더 분기를 제거**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-07-24T12:00:00Z (추정)
- **Completed:** 2026-07-24T12:22:04Z
- **Tasks:** 3/3 완료
- **Files modified:** 5 (types/lib/services/index.tsx/diseno.tsx) + 1 신규 (ThemeContentContext.tsx)

## Accomplishments
- `ShopProduct` 에 `priceOrig`/`stock` 추가, `Macrostructure` 를 4종(`marquee|bento|rails|masonry`)으로 교체(`doc` 삭제), `StoreThemeContent` 전체 스키마(`SectionConfig` 7종 discriminated union·`MacroSettings`) 를 백엔드와 필드명·옵셔널성까지 동일하게 미러
- `theme-preset.ts` 에 `MACRO_OPTIONS` 4종(라벨/태그/설명/적합매장 스페인어 카피), `GATED_BY_MACRO`(구조별 섹션 게이팅 SSOT), `DEFAULT_CONTENT`(백엔드와 문자 단위 동일) export 신설 + `tokensToCssVars()` 에 `--on-navy` 고정 변수 추가
- `shop-api.ts` 의 `listProducts()` 에 `sort`/`showOutOfStock`/`minPrice`/`maxPrice`/`categoryId` optional 파라미터 확장(기존 호출부 무회귀), `uploadThemeAsset()` 신규(FormData, Content-Type 수동 지정 없음), `withContentFallback()` 을 `getStoreTheme`/`getThemeDraft`/`saveThemeDraft` 3개 지점에 배선
- `ThemeContentContext.tsx` 신규 — `useThemeContent()` 가 Provider 밖에서도 `DEFAULT_CONTENT` 반환(공개몰 크래시 방지), value `useMemo` 메모이제이션
- `index.tsx`/`diseno.tsx` 의 `gridStyle`/`grid` 에서 `'doc'` 삼항 분기 제거(marquee/bento 밀도 값은 diff 상 완전 무변경으로 보존), `defaultTheme()`/`DUMMY` 에 신규 필수 필드(`content`/`priceOrig`/`stock`) 배선
- `diseno.tsx` 에 `content` state 신설 — 초안 로드 시 `t.content` 를 보존해 색/레이아웃만 저장해도 기존 매장 섹션 설정이 유실되지 않도록 함(계획에 없던 데이터 손실 방지 수정)

## Task Commits

Each task was committed atomically:

1. **Task 1: types/shop.ts + lib/theme-preset.ts 미러 확장** - `13b0b33` (feat)
2. **Task 2: shop-api.ts content 저장 · sort/showOutOfStock 조회 · uploadThemeAsset** - `eb9ed78` (feat)
3. **Task 3: ThemeContentContext.tsx 신규 + index.tsx/diseno.tsx doc 분기 제거** - `cd0011c` (feat)

_이 플랜은 tienda-app 을 루트 저장소가 직접 추적(서브모듈 아님)하므로 별도 gitlink 커밋이 없다._

## Files Created/Modified
- `tienda-app/src/types/shop.ts` - `ShopProduct.priceOrig/stock`, `Macrostructure` 4종, `CatalogSort`, `StoreThemeContent`/`SectionConfig` 7종/`MacroSettings` 전체 미러, `StoreTheme.content`
- `tienda-app/src/lib/theme-preset.ts` - `MACRO_OPTIONS` 4종(`MacroOption` 인터페이스), `GATED_BY_MACRO` export, `DEFAULT_CONTENT` export, `tokensToCssVars()` `--on-navy` 추가
- `tienda-app/src/services/shop-api.ts` - `listProducts()` 정렬/필터 파라미터 확장, `SaveThemeBody.content`, `uploadThemeAsset()` 신규, `withContentFallback()` 신규 + 3개 지점 배선
- `tienda-app/src/context/ThemeContentContext.tsx` (신규) - `ThemeContentProvider`/`useThemeContent()`
- `tienda-app/src/pages/[storeId]/index.tsx` - `gridStyle` doc 분기 제거, `defaultTheme()` 에 `content: DEFAULT_CONTENT`
- `tienda-app/src/pages/[storeId]/panel/diseno.tsx` - `grid` doc 분기 제거, `DUMMY` 에 `priceOrig`/`stock: null`, `content` state 신설 + 초안 로드/저장/발행 3개 지점 배선

## Decisions Made
- `diseno.tsx` 에 `content` state 추가(계획 외) — Key-decisions 참조. Rule 1(버그 자동수정): `SaveThemeBody.content` 가 필수가 되며 발생하는 데이터 손실 위험을 저장 시점에 기존 값을 보존하는 방식으로 차단. 섹션 편집 UI 자체는 추가하지 않아 Plan 61-08/61-11 스코프를 침범하지 않음.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] diseno.tsx 에 content state 신설 — 저장 시 매장 섹션 설정 유실 방지**
- **Found during:** Task 3 (`npx tsc --noEmit` 로 Task 2 완료 후 `diseno.tsx` 의 `saveThemeDraft`/`publishTheme` 호출부에서 `SaveThemeBody.content` 누락 TS2345 에러 확인)
- **Issue:** Task 2 에서 `SaveThemeBody.content` 를 필수 필드로 추가했는데, `diseno.tsx` 는 색/토큰/레이아웃만 다루고 content 를 전혀 알지 못함. 계획대로 두면 컴파일이 깨지거나(임시로 `DEFAULT_CONTENT` 를 항상 보내면 컴파일은 통과하지만) 사용자가 색상만 바꿔 저장할 때마다 이미 저장된 hero/섹션/트러스트뱃지 등 콘텐츠가 전부 `DEFAULT_CONTENT` 로 덮어써지는 심각한 데이터 손실 버그가 됨
- **Fix:** `content` state 를 신설하고 `getThemeDraft()` 응답의 `t.content` 로 초기화, `onSave`/`onPublish` 의 `saveThemeDraft` 호출에 그대로 전달. 편집 UI는 추가하지 않음(계획 범위 유지)
- **Files modified:** tienda-app/src/pages/[storeId]/panel/diseno.tsx
- **Verification:** `npx tsc --noEmit` exit 0, `npx eslint src/` exit 0
- **Committed in:** `cd0011c` (Task 3 commit)

---

**Total deviations:** 1 auto-fixed (1 Rule 1 데이터 손실 버그)
**Impact on plan:** 계획이 명시하지 않은 최소 배선만 추가(콘텐츠 편집 UI 없음). 스코프 크립 없음 — Plan 61-08/61-11 이 여전히 이 화면의 콘텐츠 편집 UI 를 담당.

## Issues Encountered
- Acceptance criteria 문구 2건이 실제 코드베이스 상태와 어긋남(둘 다 계획 작성 시점의 사소한 오차, 기능적 영향 없음):
  1. Task 2 acceptance `grep -c "'Content-Type'" ... == 1` — 실제로는 `checkout()` 함수(이 플랜 범위 밖, 기존 코드)에 이미 1건이 있어 총 2건. `uploadThemeAsset()` 에는 여전히 수동 `Content-Type` 이 없음(핵심 의도 충족 확인함).
  2. Task 3 acceptance `git diff | grep -c "^-.*minmax(240px"` == 1 — 실제로는 0. `minmax(240px, 1fr)` 라인 자체는 손대지 않아 git diff 상 완전히 unchanged context 로 처리됨(3줄 컨텍스트 diff 알고리즘 특성). 오히려 계획의 "bento 밀도 값 보존" 의도를 diff 조작 없이 더 강하게 충족한 결과 — `git diff` 를 직접 확인해 minmax(240px) 라인이 +/- 어느 쪽에도 나타나지 않고 완전 동일함을 육안 확인함.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- 후속 프런트 플랜(61-06~61-15) 이 사용할 타입/API/컨텍스트 기반이 모두 준비됨: `StoreThemeContent` 전체 타입, `MACRO_OPTIONS`/`GATED_BY_MACRO`, `uploadThemeAsset`, `useThemeContent()`
- `tienda-app/src` 전체 `npx tsc --noEmit`/`npx eslint src/` 모두 exit 0 확인 — 이후 플랜이 컴파일 실패 없는 상태에서 시작 가능
- `GATED_BY_MACRO` 의 단일 소유지가 `theme-preset.ts` 로 확정됐으므로, Plan 61-09(index.tsx 렌더 게이팅)와 Plan 61-10(`SectionGatingChips.tsx`)는 반드시 이 상수를 import 해야 하며 별도로 재정의하면 안 됨
- `diseno.tsx` 의 `content` state 는 통과용 배선만 존재 — Plan 61-08/61-11 이 실제 편집 UI(아코디언/섹션 리스트 에디터)를 이 state 위에 구현해야 함

---
*Phase: 61-tienda-online-editor*
*Completed: 2026-07-24*

## Self-Check: PASSED

- FOUND: tienda-app/src/types/shop.ts
- FOUND: tienda-app/src/lib/theme-preset.ts
- FOUND: tienda-app/src/services/shop-api.ts
- FOUND: tienda-app/src/context/ThemeContentContext.tsx
- FOUND: tienda-app/src/pages/[storeId]/index.tsx
- FOUND: tienda-app/src/pages/[storeId]/panel/diseno.tsx
- FOUND commit: 13b0b33
- FOUND commit: eb9ed78
- FOUND commit: cd0011c
