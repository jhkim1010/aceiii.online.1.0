---
phase: 61-tienda-online-editor
plan: 13
subsystem: ui
tags: [nextjs, typescript, react, tienda-app, storefront, marketing, seo, pixel, sessionstorage]

# Dependency graph
requires:
  - phase: 61-09
    provides: "index.tsx sections 순회 + macrostructure 분기 + Footer(trust 렌더) 조립"
  - phase: 61-12
    provides: "diseno.tsx 아코디언 그룹 8·9·10(💬 Contacto & redes) 구조"
provides:
  - "tienda-app/src/components/MarketingPopup.tsx — 세션 1회 웰컴 팝업(제목 + 선택적 쿠폰 표시)"
  - "index.tsx — SEO title/description SSR 주입 + 조건부 Meta Pixel(next/script) + 팝업 마운트"
  - "diseno.tsx 그룹 11(🛡 Confianza, pagos y envíos) + 그룹 12(📈 Marketing & SEO) — 12그룹 아코디언 완성"
  - "PanelPrimitives.TextField 선택적 hint prop(공용 컴포넌트 확장)"
affects: [61-14, 61-15]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "next/script strategy='afterInteractive' 로 조건부 3rd-party 스크립트 삽입(프로젝트 신규 패턴, tienda-app 사용례 0건 → 1건)"
    - "diseno.tsx 배열 편집 시 '기존 항목 + 빈 add-slot' 을 하나의 배열로 합쳐 단일 JSX 호출 지점에서 map() — kind='payment'/kind='shipping' 리터럴이 소스에 정확히 1회만 나타나면서도 런타임엔 N+1개 슬롯을 렌더(acceptance grep 카운트 계약과 반복 UI 를 동시에 만족)"

key-files:
  created:
    - tienda-app/src/components/MarketingPopup.tsx
  modified:
    - tienda-app/src/pages/[storeId]/index.tsx
    - tienda-app/src/pages/[storeId]/panel/diseno.tsx
    - tienda-app/src/components/panel/PanelPrimitives.tsx

key-decisions:
  - "PanelPrimitives.TextField 에 선택적 hint prop 추가(Rule 2) — SwitchField 는 이미 hint 를 지원했으나 TextField 엔 없어, 계획이 요구한 쿠폰/SEO/pixel 안내 문구(예: 'El código se muestra pero todavía no se valida automáticamente.')를 표시할 방법이 없었다. 기존 모든 TextField 호출부는 선택적 prop 이라 하위호환 유지."
  - "paymentLogos/shippingLogos 배열 편집을 '기존 로고들 + 빈 add-slot' 결합 배열의 단일 map() 으로 구현 — acceptance 기준(kind=\"payment\"/kind=\"shipping\" 소스 내 정확히 1회)과 최대 8개 반복 업로드 슬롯 요구를 동시에 충족하기 위한 설계."

patterns-established:
  - "3rd-party pixel 삽입은 next/script(afterInteractive) + 백엔드 화이트리스트 필터링된 값만 템플릿 리터럴에 삽입(T-61-64 완화) — 후속 3rd-party 스크립트(예: GA)도 동일 패턴 재사용 가능"

requirements-completed: [R7, R6, R8]

# Metrics
duration: ~30min
completed: 2026-07-24
---

# Phase 61 Plan 13: 마케팅 웰컴 팝업 + SEO/pixel + 신뢰 요소 에디터 Summary

**세션당 1회 뜨는 웰컴 팝업(sessionStorage) + SSR SEO title/description 오버라이드 + 조건부 Meta Pixel(next/script) + 결제/배송 로고·정책 링크·compra protegida 에디터 그룹 2개로 12그룹 아코디언 완성**

## Performance

- **Duration:** ~30 min
- **Started:** 2026-07-24T (이어서 실행, 정확한 시작 타임스탬프 미기록)
- **Completed:** 2026-07-24
- **Tasks:** 3/3 완료
- **Files modified:** 3 (index.tsx, diseno.tsx, PanelPrimitives.tsx) + 1 신규 (MarketingPopup.tsx)

## Accomplishments
- `MarketingPopup.tsx`(신규) — `useThemeContent().marketing.popup` 을 읽어 `enabled && title` 일 때만 세션당 1회 노출. `sessionStorage` 키 `popup_shown_{storeId}` 로 판정(useEffect 내부에서만 접근해 SSR-safe). 오버레이/`✕`(`aria-label="Cerrar"`)/ESC 3경로로 닫힘, 박스 내부 클릭은 `stopPropagation`. 쿠폰은 점선 gold pill 로 표시 전용(파일 상단 한국어 TODO 주석으로 Campañas discounts 실검증이 범위 외임을 명시)
- `index.tsx` — 하드코딩 `<title>`을 `theme.content.marketing.seoTitle || 기존 기본값` 으로, `<meta description>`도 동일 패턴으로 override. `getServerSideProps` 가 이미 SSR 로 `theme` 을 넘기므로 크롤러가 보는 최초 HTML 에 바로 반영됨(추가 API 호출 없음). `pixelId` 있을 때만 `next/script id="meta-pixel" strategy="afterInteractive"` 로 Meta Pixel 삽입 — `pixelId` 는 백엔드 `PIXEL_ID_RE`(영숫자/하이픈/언더스코어)로 이미 걸러진 값이라 템플릿 리터럴 삽입이 안전함을 주석으로 남김(T-61-64). `<MarketingPopup storeId={storeId} />` 를 `WhatsAppFloat` 옆에 마운트
- `diseno.tsx` — 그룹 11 `🛡 Confianza, pagos y envíos`(결제/배송 로고 각 최대 8개 `AssetUploadField kind="payment"`/`kind="shipping"`, `protectedBadge` 스위치, `policyLinks` 최대 6행 label+href+✕) + 그룹 12 `📈 Marketing & SEO`(popup enabled/title/coupon, seoTitle, seoDescription, pixelId) 추가 — 12그룹 아코디언 완성. 로고 배열 편집은 "기존 항목 + 빈 add-slot" 을 하나의 배열로 합쳐 단일 `AssetUploadField` 호출 지점에서 `.map()` 하는 패턴으로, 소스 내 `kind="payment"`/`kind="shipping"` 리터럴이 정확히 1회만 나타나면서도 런타임엔 반복 슬롯을 렌더
- `PanelPrimitives.tsx`(Rule 2 확장) — `TextField` 에 선택적 `hint` prop 추가(기존 `SwitchField` 패턴과 동일한 `st.hintText` 스타일 재사용), 쿠폰/SEO/pixel 안내 문구 표시에 사용
- `tienda-app/src` 전체 `npx tsc --noEmit`/`npx eslint src/` exit 0, `dangerouslySetInnerHTML` 0건(전 파일 기준)

## Task Commits

Each task was committed atomically:

1. **Task 1: MarketingPopup.tsx — 세션 1회 웰컴 팝업** - `5dd32ad` (feat)
2. **Task 2: index.tsx — SEO `<Head>` 주입 + 조건부 pixel + 팝업 마운트** - `d45687e` (feat)
3. **Task 3: diseno.tsx — 🛡 Confianza + 📈 Marketing & SEO 그룹 (+ PanelPrimitives.TextField hint prop)** - `62a08db` (feat)

_이 플랜은 `tienda-app` 을 루트 저장소가 직접 추적(서브모듈 아님)하므로 별도 gitlink 커밋이 없다._

## Files Created/Modified
- `tienda-app/src/components/MarketingPopup.tsx`(신규) - 세션 1회 웰컴 팝업(제목 + 쿠폰 표시 전용)
- `tienda-app/src/pages/[storeId]/index.tsx` - SEO `<Head>` SSR 오버라이드 + 조건부 Meta Pixel(`next/script`) + `MarketingPopup` 마운트
- `tienda-app/src/pages/[storeId]/panel/diseno.tsx` - 그룹 11(Confianza) + 그룹 12(Marketing & SEO) 아코디언 추가
- `tienda-app/src/components/panel/PanelPrimitives.tsx` - `TextField` 에 선택적 `hint` prop 추가

## Decisions Made
- `PanelPrimitives.TextField` hint prop 추가 — Key-decisions 참조. 계획이 요구한 3개 안내 문구(쿠폰/SEO 타이틀/pixel)를 표시할 기존 수단이 없어 공용 컴포넌트를 최소 확장.
- 로고 배열 "기존+add-slot 결합 단일 map()" 설계 — Key-decisions 참조. acceptance 기준의 소스-레벨 리터럴 카운트(`kind="payment"` 정확히 1회)와 최대 8슬롯 반복 업로드 UX 를 동시에 만족.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical Functionality] PanelPrimitives.TextField 에 hint prop 부재**
- **Found during:** Task 3 (그룹 12 Marketing & SEO 작성 중, `popup.coupon`/`seoTitle`/`pixelId` TextField 에 안내 문구를 붙이려는데 `TextField` 시그니처에 `hint` 가 없음을 발견)
- **Issue:** 계획이 `hint 'El código se muestra pero todavía no se valida automáticamente.'` 등 3곳의 안내 문구를 TextField 에 요구했지만, 기존 `TextField` 컴포넌트는 `label/value/onChange/placeholder/maxLength/multiline` 만 지원(hint 는 `SwitchField` 전용)했다.
- **Fix:** `TextField` 에 선택적 `hint?: string` prop 추가, 있으면 `SwitchField` 와 동일한 `st.hintText` 스타일로 렌더. 기존 모든 `TextField` 호출부는 prop 을 안 넘기므로 하위호환 100% 유지.
- **Files modified:** tienda-app/src/components/panel/PanelPrimitives.tsx
- **Verification:** `npx tsc --noEmit`/`npx eslint src/` exit 0, 기존 `TextField` 사용처(브랜드/공지/연락처 등) 회귀 없음(prop 추가만, 기존 호출 시그니처 변경 없음)
- **Committed in:** `62a08db` (Task 3 commit)

---

**Total deviations:** 1 auto-fixed (Rule 2 — 공용 컴포넌트에 누락된 hint 표시 기능 추가)
**Impact on plan:** 계획이 명시한 안내 문구를 렌더하기 위한 최소 확장. 스코프 크립 없음(기존 호출부 전부 하위호환).

### Acceptance-grep 카운트 참고 (기능 영향 없음, 61-09/61-06/61-07 선례와 동일 성격)

`MarketingPopup.tsx` 의 acceptance 기준 `grep -c "popup_shown_" >= 2` 는 실제 1(코드가 `const key = \`popup_shown_${storeId}\`;` 로 한 번만 정의 후 `key` 변수를 `getItem`/`setItem` 양쪽에서 재사용 — 이 방식은 계획의 `<action>` 예시 코드 자체를 그대로 옮긴 것이다. 문자열 리터럴을 매번 새로 쓰지 않고 변수로 재사용하는 편이 더 안전한 패턴(오타로 두 지점의 키가 갈라질 위험 원천 차단)이라 판단해 계획 예시 코드를 그대로 따랐다. 기능(SSR-safe·세션당 1회 판정)엔 영향 없음.

## Issues Encountered

- 로컬 dev 서버(`localhost:3060`)/API 가 이 클라우드 실행 환경에서 접근 불가(선행 플랜들과 동일 제약, CLAUDE.md 로컬 브리지 제약과 동일 성격) — 계획의 `<verification>` 절 `curl` 스모크(`<title>` 개수, `id="meta-pixel"` 존재/부재)는 실행하지 못함. `tsc --noEmit`/`eslint src/` 정적 검증 + acceptance grep 전부로 대체. 실제 브라우저 기반 검증(팝업 세션 1회 동작, SEO 소스뷰, pixel 스크립트 유무)은 사용자가 로컬(Mac, `./dev.sh`)에서 수행 권장.

## User Setup Required

None for code — 단, 위 "Issues Encountered" 의 브라우저 스모크(세션당 팝업 1회, `view-source:` 로 `<title>` 확인, pixelId 설정/미설정 시 `<script id="meta-pixel">` 유무)는 사용자가 로컬 환경에서 직접 확인할 것을 권장.

## Next Phase Readiness
- `content.marketing`/`content.trust` 는 이제 렌더(Plan 61-09, Footer/index.tsx)와 편집(이 플랜) 양쪽이 완전히 연결됨 — R6/R7/R8 요구사항의 UI 계약이 닫혔다.
- `PanelPrimitives.TextField.hint` 는 공용 확장이라 Plan 61-14/61-15 가 추가 필드에 안내 문구가 필요하면 그대로 재사용 가능.
- `next/script` 조건부 삽입 패턴이 이 플랜에서 최초 도입됐으므로, 후속 3rd-party 통합(예: Google Analytics)이 필요하면 동일 패턴(백엔드 화이트리스트 → 조건부 렌더 → 안전 삽입 근거 주석) 재사용 권장.

---
*Phase: 61-tienda-online-editor*
*Completed: 2026-07-24*

## Self-Check: PASSED

- FOUND: tienda-app/src/components/MarketingPopup.tsx
- FOUND: tienda-app/src/pages/[storeId]/index.tsx
- FOUND: tienda-app/src/pages/[storeId]/panel/diseno.tsx
- FOUND: tienda-app/src/components/panel/PanelPrimitives.tsx
- FOUND commit: 5dd32ad
- FOUND commit: d45687e
- FOUND commit: 62a08db
