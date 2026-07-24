---
phase: 61-tienda-online-editor
plan: 12
subsystem: ui
tags: [nextjs, react, css-vars, tienda-online, product-card, catalog-filters]

# Dependency graph
requires:
  - phase: 61-tienda-online-editor
    provides: "61-03(priceOrig/stock DTO + minPrice/maxPrice 백엔드 파라미터), 61-05(listProducts 시그니처 + ThemeContentContext), 61-09/61-10(index.tsx macro 분기 + diseno.tsx 아코디언 구조)"
provides:
  - "ProductCard 6옵션(discountBadge/installments/quickAdd/hoverSecondImage/lastUnitsBadge/variantDots) 조건부 렌더, Provider 경유 자동 배선"
  - "공개 목록이 catalog 토큰(pageSize/defaultSort/showOutOfStock)을 SSR+클라이언트 동일 배선"
  - "filters.price 가격 구간 필터 실구현(minPrice/maxPrice → 기존 백엔드 파라미터)"
  - "filters.color/filters.size 정직한 no-op(가짜 필터 미렌더) + 에디터 hint"
  - "에디터 🛍 Tarjeta de producto + 📚 Catálogo y filtros 아코디언 그룹"
affects: [61-13, 61-14, 61-15]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "ProductCard 는 options prop 없으면 useThemeContent().productCard 를 폴백으로 사용 — Carousel/RailsLayout/MasonryLayout 어디서나 prop drilling 없이 옵션 자동 적용"
    - "인라인 스타일 기반 컴포넌트에서 :hover 표현이 필요한 경우 className + globals.css 규칙 1개만 추가(라이브러리 금지 원칙 유지)"
    - "데이터 소스가 없는 옵션(variantDots)과 필터(color/size)는 렌더 자체를 생략하고 한국어 TODO 주석 + 에디터 hint 로 명시(가짜 UI 금지)"

key-files:
  created: []
  modified:
    - tienda-app/src/components/ProductCard.tsx
    - tienda-app/src/styles/globals.css
    - "tienda-app/src/pages/[storeId]/index.tsx"
    - "tienda-app/src/pages/[storeId]/panel/diseno.tsx"

key-decisions:
  - "ProductCard 가 useThemeContent() 를 항상 무조건 호출(rules-of-hooks 준수)한 뒤 options ?? themeProductCard 로 폴백 — 조건부 훅 호출 회피"
  - "가격 필터 UI = 최소/최대 숫자 입력 2개 + Aplicar 버튼 + 적용된 구간 칩(✕ 해제) — 매 키입력마다 재조회하지 않고 명시적 적용 시점에만 minP/maxP state 갱신"
  - "color/size 필터는 index.tsx 에 UI 를 전혀 렌더하지 않고 값만 저장(에디터)/무시(공개몰) — R5 variantDots 예외와 동일 정직성 원칙"

patterns-established:
  - "옵션/필터에 데이터 소스가 없으면 플레이스홀더를 그리지 말고 no-op + TODO + 에디터 hint 3종 세트로 정직하게 명시한다"

requirements-completed: [R5, R6, R8]

# Metrics
duration: ~35min
completed: 2026-07-24
---

# Phase 61 Plan 12: ProductCard 6옵션 + 카탈로그 price 필터 실구현 Summary

**ProductCard 에 6개 표시 옵션을 조건부로 붙이고 공개 목록이 catalog 토큰(정렬/페이지/품절/가격필터)을 따르게 배선, color/size 필터는 데이터 부재로 정직한 no-op 처리**

## Performance

- **Duration:** ~35분
- **Tasks:** 3/3 완료
- **Files modified:** 4

## Accomplishments
- `ProductCard.tsx` 에 `ProductCardOptions` prop 추가 — 6개 옵션(discountBadge/installments/quickAdd/hoverSecondImage/lastUnitsBadge/variantDots) 조건부 렌더, `options` 미지정 시 `useThemeContent().productCard` 폴백으로 Carousel/RailsLayout/MasonryLayout 어디서든 자동 배선(prop drilling 불필요)
- 공개 목록(`index.tsx`)이 SSR·클라이언트 모두 `theme.content.catalog.pageSize/defaultSort/showOutOfStock` 을 따름(기존 하드코딩 `pageSize: 50`/`pageSize: 24` 제거)
- `filters.price` 실구현 — 토글 ON 시에만 가격 구간 필터 UI(최소/최대 입력 + Aplicar + 해제 칩) 노출, `minPrice`/`maxPrice` 를 `listProducts` 에 전달(신규 백엔드 엔드포인트 0 — Plan 61-03 파라미터 재사용)
- `filters.color`/`filters.size` 는 공개 API 에 variant 색상/사이즈 집계가 없어 UI 를 렌더하지 않음(가짜 필터 금지) — 값은 저장되나 렌더 대상 없음을 한국어 TODO 주석으로 명시
- 에디터(`diseno.tsx`)에 `🛍 Tarjeta de producto`(6개 스위치, variantDots 정직한 hint) + `📚 Catálogo y filtros`(정렬/페이지/품절/필터 3종, price 는 "이미 작동" hint · size/color 는 공통 미구현 hint) 그룹 추가
- 상품카드 가격을 heading 20px(`var(--disp-weight)`)로 스냅(기존 `fontSize:18`/하드코딩 `fontWeight:800` → 테마 굵기 통합)

## Task Commits

1. **Task 1: ProductCard.tsx — 6개 옵션 조건부 렌더** - `b842d4e` (feat)
2. **Task 2: index.tsx — catalog 토큰 배선 + 가격 필터 실구현** - `03dc93a` (feat)
3. **Task 3: diseno.tsx — 🛍 Tarjeta de producto + 📚 Catálogo y filtros 그룹** - `fc00bd2` (feat)

## Files Created/Modified
- `tienda-app/src/components/ProductCard.tsx` - `ProductCardOptions` prop + 6옵션 조건부 렌더 + Provider 폴백
- `tienda-app/src/styles/globals.css` - `.pc-hover2`/`.pc-hover2:hover .pc-img2` hover 전환 규칙 1개
- `tienda-app/src/pages/[storeId]/index.tsx` - catalog 토큰 배선(SSR+클라이언트) + 가격 필터 UI + state(minP/maxP/minDraft/maxDraft)
- `tienda-app/src/pages/[storeId]/panel/diseno.tsx` - 아코디언 그룹 2개(Tarjeta de producto / Catálogo y filtros) + SelectField/NumberField import 추가

## Decisions Made
- `useThemeContent()` 를 ProductCard 안에서 항상 무조건 호출한 뒤(`const themeProductCard = useThemeContent().productCard;`) `options ?? themeProductCard` 로 결정 — `options ?? useThemeContent()...` 형태로 짧게 쓰면 `??` 단락평가로 훅이 조건부 호출돼 rules-of-hooks 위반이 되므로 회피
- 가격 필터는 입력값을 바로 `minP/maxP` state 에 반영하지 않고 `Aplicar` 버튼으로 확정 — 타이핑마다 재조회를 방지(기존 300ms debounce useEffect 와 결합해 과도한 API 호출 방지)
- 활성 필터 칩 라벨에 `money()` 포맷 재사용(`$0 – ${money(maxP)}` 형태)해 표면 B 통화 표기 규칙과 일관 유지

## Deviations from Plan

None - 계획대로 실행됨. (훅 호출 순서 회피는 계획의 의도(`options ?? useThemeContent().productCard`)를 rules-of-hooks 를 지키며 동등하게 구현한 것으로, 별도 편차로 분류하지 않음 — acceptance criteria grep `useThemeContent().productCard` 도 그대로 충족.)

## Issues Encountered
None

## User Setup Required
None - 외부 서비스 설정 불필요.

## Verification Notes

- `cd tienda-app && npx tsc --noEmit` — PASS (전체)
- `cd tienda-app && npx eslint src/` — PASS (전체, 0 warning/error)
- `grep -rEn "#[0-9a-fA-F]{3,6}" tienda-app/src/components/ProductCard.tsx` — 0건(하드코딩 색상 없음, `boxShadow rgba` 만 존재·허용)
- 백엔드 curl 스모크 테스트(`GET /public/shop/9/products?pageSize=12&sort=price_asc`, `?minPrice=10000&maxPrice=30000`)는 이 실행 환경에 로컬 API 서버가 기동돼 있지 않아 미실행 — 브라우저/로컬 UAT 시 수행 필요(Plan 검증 블록에 기재된 스모크 명령 그대로 사용 가능)

## Next Phase Readiness
- ProductCard 옵션/카탈로그 필터 배선 완료 — Plan 61-13 이후 나머지 표면(trust/marketing 등) 작업에 영향 없음
- 남은 게이트: 브라우저 UAT(가격 필터 실동작·6옵션 시각 확인) + 로컬/운영 API 서버 기동 후 curl 스모크 실행

---
*Phase: 61-tienda-online-editor*
*Completed: 2026-07-24*

## Self-Check: PASSED

- FOUND: tienda-app/src/components/ProductCard.tsx
- FOUND: tienda-app/src/styles/globals.css
- FOUND: tienda-app/src/pages/[storeId]/index.tsx
- FOUND: tienda-app/src/pages/[storeId]/panel/diseno.tsx
- FOUND: .planning/phases/61-tienda-online-editor/61-12-SUMMARY.md
- FOUND commit: b842d4e
- FOUND commit: 03dc93a
- FOUND commit: fc00bd2
