---
phase: 61-tienda-online-editor
plan: 09
subsystem: ui
tags: [nextjs, typescript, react, tienda-app, storefront, css-variables, macrostructure]

# Dependency graph
requires:
  - phase: 61-06
    provides: "components/sections/SectionRenderer.tsx — section.type 단일 분기점"
  - phase: 61-07
    provides: "components/macro/RailsLayout.tsx / MasonryLayout.tsx — rails/masonry 렌더러"
  - phase: 61-05
    provides: "ThemeContentContext.useThemeContent()/ThemeContentProvider, GATED_BY_MACRO SSOT, DEFAULT_CONTENT, minioImageUrl"
provides:
  - "tienda-app/src/pages/[storeId]/index.tsx — content.sections 순회 렌더 + macrostructure 최상위 분기(rails/masonry) + 게이팅 + 파비콘 주입"
  - "tienda-app/src/components/Header.tsx — 공지바/브랜드 로고를 content 데이터에 연결(무회귀 폴백 유지)"
  - "tienda-app/src/components/Footer.tsx — SNS/정책/결제·배송 로고/compra protegida 푸터(신규)"
  - "tienda-app/src/components/WhatsAppFloat.tsx — WhatsApp 플로팅 버튼(신규)"
affects: [61-10, 61-11, 61-12, 61-13, 61-14, 61-15]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "index.tsx 최상위 macrostructure 삼항 분기(rails/masonry/기타) — 그리드 밀도 조정이 아니라 렌더 구조 자체 교체"
    - "게이팅은 순수 Array.filter 로 새 배열만 생성 — theme.content.sections(JSONB) 자체는 절대 mutate 하지 않음"
    - "섹션/레이아웃 컴포넌트가 각자 loading 상태를 소유 — index.tsx 최상위 loading state 는 제거(중복 소유 방지)"

key-files:
  created:
    - tienda-app/src/components/Footer.tsx
    - tienda-app/src/components/WhatsAppFloat.tsx
  modified:
    - tienda-app/src/components/Header.tsx
    - tienda-app/src/pages/[storeId]/index.tsx
    - tienda-app/src/components/sections/Carousel.tsx

key-decisions:
  - "Carousel.tsx 에 initialItems 재동기화 useEffect 추가(계획 외, Rule 1) — index.tsx 의 검색/필터 items state 를 carousel 섹션에 배선하면서, 기존 Carousel 구현(mount 시 1회만 initialItems 반영)이 검색창 타이핑을 화면에 반영하지 못하는 회귀를 유발함을 발견해 즉시 수정"
  - "index.tsx 최상위 loading state/setLoading 제거(계획 외, Rule 3) — 하드코딩 grid/secHead 블록 삭제로 loading 을 읽는 JSX 가 사라져 미사용 변수가 됐고, Carousel/MasonryLayout 이 각자 로딩 표시를 이미 소유하므로 중복 없이 제거"

patterns-established:
  - "무회귀 폴백 3단: content.brand.logoFile → content.brand.displayName → 기존 하드코딩 워드마크(CoolShop). 확장 키 없는 기존 매장은 마지막 단으로 떨어져 현행과 동일하게 렌더"

requirements-completed: [R4, R9, R8]

# Metrics
duration: ~35min
completed: 2026-07-24
---

# Phase 61 Plan 09: 공개 스토어프런트 홈 조립(index.tsx) Summary

**공개 스토어프런트를 하드코딩 레이아웃에서 content.sections 순회 + macrostructure 최상위 분기(rails/masonry) 기반의 데이터 조립으로 전환 — 공지바/헤더 로고/파비콘/WhatsApp 플로팅/푸터 신설, 확장 키 없는 기존 매장은 DEFAULT_CONTENT 덕분에 현행과 동일하게 렌더**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-07-24T12:35:00Z (추정)
- **Completed:** 2026-07-24T13:06:27Z
- **Tasks:** 3/3 완료
- **Files modified:** 3 (Header.tsx, index.tsx, Carousel.tsx) + 2 신규 (Footer.tsx, WhatsAppFloat.tsx)

## Accomplishments
- `Header.tsx` — `useThemeContent()` 로 `announce`/`brand` 를 읽어 하드코딩 공지바를 완전 대체(`enabled=false`/빈 텍스트면 JSX 자체 미렌더), 브랜드 로고는 `logoFile → displayName → 기존 CoolShop 워드마크` 3단 폴백으로 무회귀 보장. 공지바 텍스트 색을 `#fff` 리터럴에서 `var(--on-navy)` 로 교체
- `Footer.tsx`(신규) — 브랜드/Redes/Políticas/Pagos y envíos 4열 grid(`auto-fit`), `contact`/`trust` 데이터가 전무하면 `return null`(기존 매장은 `<footer>` 자체가 없던 현행 유지), Instagram/Facebook 은 handle/전체 URL 둘 다 받아 조립하고 전부 `rel="noopener noreferrer"`, `trust.protectedBadge` 시 상단 구분선 + "🛡 Compra protegida" 배지
- `WhatsAppFloat.tsx`(신규) — `contact.whatsapp` 없으면 렌더 안 함, 숫자만 추출해 `wa.me` 링크 조립, `aria-label="Contactar por WhatsApp"`, `#25d366` 브랜드 고정색(UI-SPEC 허용 예외), `z-index:30`(Header 20 위·마케팅 팝업 예정 50 아래)
- `index.tsx` — 최상위를 `ThemeContentProvider` 로 감싸고, `theme.content.brand.faviconFile` 있으면 `<Head>` 에 `<link rel="icon">` 주입. `GATED_BY_MACRO`(`lib/theme-preset.ts` SSOT)로 구조별 비활성 섹션을 순수 `filter` 로 걸러(JSONB mutate 0건) `rails=RailsLayout`, `masonry=MasonryLayout`, 그 외(marquee/bento)=`SectionRenderer` 순회로 최상위 분기. 하드코딩 hero/promo/secHead/그리드/aistrip 블록 전부 삭제(카피는 `DEFAULT_CONTENT` 로 이미 이관돼 있음, Plan 61-05)
- `Carousel.tsx`(범위 내 Rule 1 수정) — index.tsx 의 검색/필터 `items` state 가 `carousel` 섹션에 `initialItems` 로 배선되는데, 기존 구현이 mount 시 1회만 반영해 검색창 타이핑이 화면에 반영되지 않는 회귀를 유발함을 발견 → `initialItems` 변경 시 재동기화하는 `useEffect` 추가
- `tienda-app/src` 전체 `npx tsc --noEmit`/`npx eslint src/` exit 0, `dangerouslySetInnerHTML` 0건, `components/sections|macro/` 하드코딩 hex 0건, `#25d366` 정확히 1건(WhatsAppFloat 전용)

## Task Commits

Each task was committed atomically:

1. **Task 1: Header.tsx — 공지바 + 브랜드 로고 데이터 연결** - `8dcc477` (feat)
2. **Task 2: Footer.tsx + WhatsAppFloat.tsx 신규** - `3bc67f7` (feat)
3. **Task 3: index.tsx — sections 순회 + macrostructure 분기 + 게이팅 + 파비콘 (+ Carousel.tsx Rule 1 수정)** - `8ecfd51` (feat)

_이 플랜은 `tienda-app` 을 루트 저장소가 직접 추적(서브모듈 아님)하므로 별도 gitlink 커밋이 없다._

## Files Created/Modified
- `tienda-app/src/components/Header.tsx` - 공지바/로고를 `useThemeContent()` 데이터에 연결, 무회귀 폴백 유지
- `tienda-app/src/components/Footer.tsx` (신규) - SNS/정책/결제·배송 로고/compra protegida 푸터
- `tienda-app/src/components/WhatsAppFloat.tsx` (신규) - WhatsApp 플로팅 버튼
- `tienda-app/src/pages/[storeId]/index.tsx` - sections 순회 + macrostructure 최상위 분기 + 게이팅 + 파비콘, 하드코딩 레이아웃 삭제
- `tienda-app/src/components/sections/Carousel.tsx` - initialItems 재동기화 useEffect 추가(검색 필터 회귀 방지)

## Decisions Made
- Carousel.tsx 재동기화 fix — Key-decisions 참조. 이 플랜이 새로 만든 배선(검색 필터 → carousel initialItems)이 드러낸 버그라 스코프 내로 판단.
- index.tsx 최상위 `loading` state 제거 — Key-decisions 참조. 하드코딩 grid 삭제로 사실상 죽은 변수가 됐고, 각 섹션/레이아웃 컴포넌트가 이미 자체 로딩 표시를 소유해 중복 없음.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Carousel.tsx 가 검색/필터 변경을 반영하지 못함(index.tsx 배선 중 발견)**
- **Found during:** Task 3 (index.tsx 가 검색 필터링된 `items` state 를 `carousel` 섹션에 `initialItems` 로 전달하도록 배선하며 발견)
- **Issue:** `Carousel.tsx`(Plan 61-06)의 `items` state 는 `useState(canUseInitial ? initialItems : null)` 초기값으로만 설정되고, 이후 `useEffect` 는 `canUseInitial` 이 참이면 항상 `return` 해 재조회하지 않는다. `source==='newest'`(DEFAULT_CONTENT 기본값)일 때 이 조건이 항상 참이 되므로, Header 검색창에 타이핑해 index.tsx 의 `items` 가 바뀌어도 화면의 상품 그리드가 갱신되지 않는 회귀가 된다.
- **Fix:** `canUseInitial`/`initialItems` 를 deps 로 하는 `useEffect` 를 추가해 `initialItems` 변경 시 `items` 를 재동기화(재조회 없이 prop 그대로 반영).
- **Files modified:** tienda-app/src/components/sections/Carousel.tsx
- **Verification:** `npx tsc --noEmit`/`npx eslint src/` exit 0
- **Committed in:** `8ecfd51` (Task 3 commit)

**2. [Rule 3 - Blocking issue] index.tsx 최상위 loading state 가 미사용 변수가 됨**
- **Found during:** Task 3 (하드코딩 hero/promo/secHead/grid/aistrip 블록을 삭제하며 `loading` 을 읽던 유일한 JSX 가 사라짐을 확인)
- **Issue:** `loading`/`setLoading` 을 그대로 두면 `loading` 변수가 어디서도 읽히지 않아 `eslint`(`no-unused-vars`)가 실패해 태스크를 완료할 수 없음.
- **Fix:** `loading` state 전체 제거(각 섹션/레이아웃 컴포넌트가 이미 자체 로딩 표시를 소유하므로 기능 손실 없음).
- **Files modified:** tienda-app/src/pages/[storeId]/index.tsx
- **Verification:** `npx eslint "src/pages/[storeId]/index.tsx"` exit 0
- **Committed in:** `8ecfd51` (Task 3 commit)

---

**Total deviations:** 2 auto-fixed (1 Rule 1 검색 필터 회귀 버그, 1 Rule 3 미사용 변수로 인한 빌드 차단)
**Impact on plan:** 둘 다 이 플랜이 신설한 배선이 드러낸 문제를 즉시 해소한 것으로, 계획 스코프 크립 없음.

### Acceptance-grep 카운트 불일치(기능 영향 없음, 기록용)

Plan 61-06/61-07 의 선례와 동일한 성격의 사소한 acceptance 문구 오차 2건 — 코드는 계획 의도 그대로 구현됐고 `tsc`/`eslint` 는 모두 통과했다:

1. `grep -c "brand.logoFile" tienda-app/src/components/Header.tsx` — 최초 초안(플랜 예시 코드 그대로)은 조건문/`<img src>` 두 곳에 리터럴이 나타나 카운트 2였다. 로컬 변수(`logoFile = brand.logoFile`)로 리팩터해 정확히 1로 맞췄다(실행자가 자체 조정, 별도 이슈 아님 — 참고용 기록).
2. `grep -c "ThemeContentProvider" tienda-app/src/pages/[storeId]/index.tsx` — 기대값 2(import 1 + 사용 1)지만 실제 3(import 1 + JSX 여는 태그 1 + 닫는 태그 1). JSX 는 여는/닫는 태그가 필연적으로 별도 줄에 위치하므로 구조적으로 2로 줄일 수 없다 — 계획 예시 코드를 그대로 따른 결과이며 기능에 영향 없음(Provider 는 정상적으로 1회만 트리 최상위를 감쌈).

## Issues Encountered

- `tienda-online-rails-masonry-reels-mockup.html` 목업 파일이 레포 루트에 아직 커밋되지 않은 워킹트리 상태(`?? tienda-online-rails-masonry-reels-mockup.html`)로 남아 있었다 — 이 플랜의 `read_first` 참고용으로만 사용, 이 플랜에서 커밋하지 않음(다른 플랜/사용자 책임 범위로 판단).
- `scripts/smoke-shop-theme.sh`(운영 매장 무회귀 스모크) 는 로컬 dev 서버(`localhost:3060`)와 백엔드 API 가 떠 있어야 실행 가능 — 이 클라우드 실행 환경은 Mac 로컬 서버에 도달할 수 없어(CLAUDE.md "로컬 dev PG18 Mac 브리지" 제약과 동일 성격) 이번 플랜에서 실행하지 못했다. `tsc --noEmit`/`eslint src/` 정적 검증으로 대체했으며, 실제 브라우저/서버 기반 무회귀 확인은 로컬 환경에서 사용자가 수행해야 한다.

## User Setup Required

None for code — 단, 위 "Issues Encountered" 의 `smoke-shop-theme.sh` 는 사용자가 로컬(Mac)에서 `./dev.sh` 로 tienda-app(3060)+api-ventago 를 띄운 뒤 직접 실행해 확장 키 없는 운영 매장(예: STORE_ID=9)의 공개 페이지가 변경 전/후 동일한지 확인할 것을 권장.

## Next Phase Readiness
- `index.tsx` 가 `content.sections`/`macrostructure` 를 완전히 따르므로, Plan 61-10(에디터 구조 선택 UI)부터는 에디터에서 저장한 값이 실제 공개 페이지에 바로 반영된다.
- `GATED_BY_MACRO` 는 여전히 `lib/theme-preset.ts` 단일 소유지 — Plan 61-10(`SectionGatingChips.tsx`)이 동일 상수를 import 하면 렌더 게이팅과 에디터 안내가 자동으로 일치한다.
- `Carousel.tsx` 의 재동기화 fix 는 masonry(`MasonryLayout`, Plan 61-07 에서 이미 동일 패턴 적용)와 이제 marquee/bento(`Carousel`) 모두에서 검색/필터가 정상 동작함을 의미 — 후속 플랜이 이 배선을 그대로 재사용 가능.
- Plan 61-11(ReelsSection)/61-14(QuizSection) 은 `SectionRenderer.tsx` 의 기존 `TODO` 위치에 `case` 만 추가하면 되며, 이 플랜은 `SectionRenderer.tsx` 자체를 수정하지 않았다.
- `scripts/smoke-shop-theme.sh` 무회귀 스모크는 로컬 환경에서 미실행 상태로 남아 있음 — 다음 검증 단계(verifier 또는 사용자)가 로컬에서 실행 권장.

---
*Phase: 61-tienda-online-editor*
*Completed: 2026-07-24*

## Self-Check: PASSED

- FOUND: tienda-app/src/components/Header.tsx
- FOUND: tienda-app/src/components/Footer.tsx
- FOUND: tienda-app/src/components/WhatsAppFloat.tsx
- FOUND: tienda-app/src/pages/[storeId]/index.tsx
- FOUND: tienda-app/src/components/sections/Carousel.tsx
- FOUND commit: 8dcc477
- FOUND commit: 3bc67f7
- FOUND commit: 8ecfd51
