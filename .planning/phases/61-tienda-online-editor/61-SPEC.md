# Phase 61: Tienda Online 에디터 확장 — Tiendanube급 admin 커스터마이징 — Specification

**Created:** 2026-07-23
**Source:** `.gsd/spec-phase61-tienda-online-editor.md` (2026-07-23 23:13 개정판), 목업 4종 — `tienda-online-editor-mockup.html`, `tienda-online-templates-mockup.html`, `tienda-online-rails-masonry-reels-mockup.html`, `tienda-online-quiz-mockup.html`
**Scope:** Wave A + A2 + B + C (전체)
**Requirements:** 11 locked

## Goal

hallmark 디자인 토큰(hue/sat/paperBand/fontPair/weight/radius/macro)만 조정 가능한 현행 Tienda Online 에디터를, 매장 admin이 **콘텐츠·섹션 구성**(브랜드 로고/파비콘, 공지바, 홈 섹션 순서·표시, 상품 카드 옵션, 카탈로그 정렬/필터, 신뢰 요소, 마케팅 팝업·SEO)까지 직접 결정하는 Tiendanube급 커스터마이저로 확장한다. **신규 테이블·컬럼·커넥션 0개** — `store_themes.draft_tokens`/`published_tokens` JSONB 키 확장만으로 처리한다.

## Background

현행 구현 (검증됨, 2026-07-23):

- **백엔드 SSOT**: `api-ventago/src/app/shop-public/store-theme.constants.ts` — `StoreThemeTokens`는 6개 원자 토큰(accentHue/sat/paperBand/fontPair/weight/radius)뿐. `sanitizeTokens()`가 프리셋 기본값 위에 병합 + `clamp()`로 범위 강제, `tokensToCssVars()`가 CSS 변수 맵 생성, `buildThemeResponse()`가 공개 응답 조립. 알 수 없는 키는 애초에 읽지 않으므로 자연 drop.
- **읽기 경로**: `store-theme.service.ts` (ShopReadonlyDbService), **쓰기 경로**: `store-theme-admin.service.ts` + `store-theme-admin.controller.ts` (`store-theme-edit.guard.ts` magic-link 토큰).
- **에디터 UI**: `tienda-app/src/pages/[storeId]/panel/diseno.tsx` — draft 저장 → 미리보기 → publish 왕복.
- **스토어프런트**: `tienda-app/src/pages/[storeId]/index.tsx` + `src/lib/theme-preset.ts` + `src/components/ProductCard.tsx`.
- **ventago-app 진입 카드**: `src/components/StorefrontDesignCard.tsx`.
- **카탈로그 API**: `api-ventago/src/app/shop-public/shop-catalog.controller.ts`.
- **저장**: `store_themes.draft_tokens` / `published_tokens` (JSONB). 이미지(로고/파비콘/hero/배너)만 MinIO 업로드 필요 — JSONB에는 `fileName`만 저장, 표시는 `{API_HOST}/minio/{fileName}`.
- **legacy 스토어프런트** `shop-storefront.page.ts`는 대상 아님 (tienda-app만).

문제: 매장 admin이 결정할 수 있는 것이 "활성화 토글 + slug + 색/글꼴 프리셋"뿐이라, 로고조차 못 올리고 홈 구성이 전 매장 동일하다. Tiendanube 대비 커스터마이징 격차가 공개몰 상품화의 병목.

## JSONB 스키마 확장 (draft_tokens / published_tokens 공통)

```jsonc
{
  // 기존 유지 (하위호환 — 키 부재 시 전부 현행 동작과 동일)
  // ★ macrostructure 4종으로 재편: marquee | bento | rails | masonry (doc 제거, 확정 2026-07-23)
  "baseTheme": "Studio", "macrostructure": "marquee",
  "accentHue": 32, "sat": 90, "paperBand": "light", "fontPair": "serif", "weight": 700, "radius": 10,

  // Wave A (P1)
  "brand": { "displayName": "", "logoFile": null, "faviconFile": null },
  "announce": { "enabled": false, "text": "", "href": null },
  "sections": [                       // 순서 = 배열 순서, 표시 = enabled
    { "type": "hero", "enabled": true, "title": "", "subtitle": "", "cta": "", "images": [] },
    { "type": "benefits", "enabled": true, "items": [{ "icon": "", "text": "" }] },
    { "type": "carousel", "enabled": true, "source": "newest|bestseller|category", "categoryId": null },
    { "type": "duoBanners", "enabled": false, "banners": [{ "image": null, "title": "", "subtitle": "", "href": null }] },
    { "type": "newsletter", "enabled": false, "title": "" },
    { "type": "reels", "enabled": false, "title": "", "items": [{ "videoFile": null, "posterFile": null, "productId": null }] },  // ★ Wave B
    { "type": "quiz", "enabled": false, "banner": { "title": "", "subtitle": "" }, "questions": [   // ★ Wave B
      { "key": "quien", "text": "", "options": [{ "value": "", "label": "", "sub": "", "emoji": "" }] }
    ], "mapping": { "que": "categoryId", "presu": "priceRange" } }
  ],
  "contact": { "whatsapp": null, "instagram": null, "facebook": null, "footerText": null },

  // Wave B (P2)
  "productCard": { "discountBadge": true, "installments": null, "quickAdd": false, "hoverSecondImage": true, "lastUnitsBadge": false, "variantDots": false },
  "catalog": { "defaultSort": "newest", "pageSize": 24, "showOutOfStock": true, "filters": { "size": true, "color": true, "price": true } },
  "trust": { "paymentLogos": [], "shippingLogos": [], "protectedBadge": false, "policyLinks": [] },

  // Wave C (P3)
  "marketing": { "popup": { "enabled": false, "title": "", "coupon": null }, "seoTitle": null, "seoDescription": null, "pixelId": null }
}
```

Clamp/whitelist 규칙: sections 최대 8개, hero images 최대 5개, **quiz 질문 최대 4개 · 질문당 선택지 최대 4개**, 텍스트 필드 최대 200자, `catalog.pageSize` ≤ 48, 알 수 없는 키는 drop (기존 가드레일 철학 유지).

## Requirements

1. **JSONB 스키마 확장 + sanitize 가드레일 (Wave A)**: 확장 키가 SSOT를 통해서만 저장·노출된다.
   - Current: `StoreThemeTokens`는 6개 원자 토큰뿐. `sanitizeTokens()`는 brand/announce/sections/contact/productCard/catalog/trust/marketing을 모르므로 전부 drop.
   - Target: `store-theme.constants.ts`에 확장 타입 + `sanitizeTokens()` 확장(키별 whitelist·길이/개수 clamp·default). `buildThemeResponse()`가 확장 키를 응답에 포함. href는 `http(s)://` 또는 `/`로 시작하는 상대경로만 허용, 그 외 null.
   - Acceptance: 확장 키가 전혀 없는 기존 `published_tokens`로 `buildThemeResponse()`를 호출하면 현행과 동일한 응답 + 확장 키 default가 나오고, `sections`에 9개/텍스트 300자/`javascript:` href를 넣어 저장하면 8개·200자·null로 clamp되어 저장된다.

2. **테마 이미지 업로드 (Wave A)**: 로고/파비콘/hero/배너 이미지를 admin이 직접 올린다.
   - Current: 테마 이미지 업로드 경로 없음. 로고를 넣을 방법이 없다.
   - Target: `POST /shop/:storeId/theme/asset` (StoreThemeEditGuard, MinioService 재사용). 용도별(logo/favicon/hero/banner) 확장자·크기 검증(png/jpg/webp + svg는 로고만, 2MB 제한), 파일명 UUID 재부여, `{ fileName }` 반환. JSONB에는 fileName만 저장.
   - Acceptance: 에디터에서 2MB 이하 png 로고를 업로드하면 `{fileName}`을 받아 draft에 저장되고, 공개 페이지에서 `{API_HOST}/minio/{fileName}`으로 로고가 렌더된다. 3MB 파일 또는 `.exe`는 400으로 거부된다.

3. **에디터 패널 — 브랜드·공지바·홈 섹션·연락처 (Wave A)**: admin이 콘텐츠를 편집한다.
   - Current: `diseno.tsx`는 프리셋/토큰 슬라이더만 제공하는 단일 패널.
   - Target: 아코디언 레이아웃으로 전환 + 브랜드(로고/파비콘/표시명) + 공지바(활성/문구/링크) + 홈 섹션 리스트(▲▼ 순서 이동, 표시 토글, hero 텍스트·이미지, carousel source, benefits 항목 편집) + 연락처(WhatsApp/Instagram/Facebook/푸터 문구). 섹션 리스트는 `components/panel/SectionListEditor.tsx`로 분리.
   - Acceptance: 에디터에서 hero를 benefits 아래로 내리고 newsletter를 켠 뒤 draft 저장 → 미리보기에 순서·토글이 반영되고, publish 후 공개 페이지에도 동일하게 반영된다.

4. **스토어프런트 섹션 렌더 (Wave A)**: 공개 페이지가 sections 배열을 따라 렌더된다.
   - Current: `index.tsx`가 고정 레이아웃을 렌더. 공지바·로고·WhatsApp 버튼·SNS 푸터 없음.
   - Target: sections 배열 순회 렌더(hero 캐러셀 / benefits / carousel / duoBanners / newsletter — `components/sections/*` 신규), 상단 공지바, 헤더 로고, WhatsApp 플로팅 버튼, 푸터(SNS 링크 + 문구). 텍스트는 렌더 시 이스케이프.
   - Acceptance: 확장 키가 없는 기존 매장의 공개 페이지가 회귀 없이 현행과 동일하게 렌더되고, sections를 설정한 매장은 배열 순서대로 섹션이 나타난다.

5. **상품 카드 옵션 (Wave B)**: 카드 표시 요소를 admin이 켜고 끈다.
   - Current: `ProductCard.tsx`는 고정 표시. 할인 배지/cuotas/quickAdd/hover 2번째 사진/últimas unidades/색상 점이 하드코딩 또는 부재.
   - Target: `productCard` 토큰을 받아 6개 옵션(discountBadge, installments, quickAdd, hoverSecondImage, lastUnitsBadge, variantDots)을 조건부 렌더.
   - **선행 (리서치 발견)**: `ShopProductDto`/`toDto()` 에 `priceOrig`(할인 배지용)·`stock`(últimas unidades용) 필드가 없다 — `products.price_orig`/`stock` 컬럼은 실존하나 공개 카탈로그 SELECT 에서 누락. 프런트 작업 전에 DTO + SELECT 확장이 선행돼야 한다.
   - **`variantDots`**: 공개 API 에 variant 색상 집계 데이터가 없다. 기존 공개 응답으로 색상 목록을 얻을 수 없으면 **플레이스홀더를 렌더하지 말고** 해당 옵션을 no-op 으로 두고 TODO 주석을 남긴다 (가짜 UI 금지).
   - Acceptance: `productCard.discountBadge=false`, `hoverSecondImage=false`로 publish하면 공개 목록의 카드에서 할인 배지가 사라지고 hover 시 두 번째 이미지로 바뀌지 않는다.

6. **카탈로그 정렬·페이지·필터 + 신뢰 요소 (Wave B)**: 목록 동작과 푸터 신뢰 요소를 admin이 결정한다.
   - Current: 정렬/페이지 크기/품절 표시/필터가 고정. 결제·배송 로고, compra protegida, 정책 링크 없음.
   - Target: `shop-catalog.controller.ts`가 sort/pageSize/showOutOfStock 쿼리 파라미터 수용(현재 `ORDER BY p.updated_at DESC` 하드코딩 + 정렬 파라미터 없음 — 신규. pageSize clamp 은 **48 로 통일**하고 컨트롤러 기존 상한 50 도 48 로 맞춘다. 정렬 값은 whitelist 매핑으로만 SQL 에 반영 — 문자열 보간 금지, 기존 파라미터라이즈드 쿼리 유지) + 프런트 목록이 `catalog` 토큰을 기본값으로 사용, size/color/price 필터 표시 토글. 푸터에 결제/배송 로고 chips + compra protegida 배지 + 정책 링크 렌더 + 해당 에디터 아코디언.
   - Acceptance: `catalog.pageSize=12`, `defaultSort='price_asc'`, `filters.color=false`로 publish하면 공개 목록이 12개씩 가격 오름차순으로 나오고 색상 필터가 숨겨진다. `pageSize=999`를 저장해도 48로 clamp된다.

7. **마케팅 팝업 + SEO/pixel (Wave C)**: 웰컴 팝업과 검색 메타를 admin이 설정한다.
   - Current: 팝업 없음. `<Head>`에 매장별 SEO title/description 주입 없음. pixel 삽입 경로 없음.
   - Target: 웰컴 팝업(세션당 1회, 제목 + 선택적 쿠폰 코드 표시) 렌더 + 에디터. `getServerSideProps`에서 `seoTitle`/`seoDescription`을 `<Head>`에 주입, `pixelId`는 값이 있을 때만 스크립트 삽입. 쿠폰 코드 ↔ Campañas discounts 실검증은 Phase 61 범위 외 — TODO 주석만.
   - Acceptance: `marketing.popup.enabled=true`로 publish 후 공개 페이지 첫 방문에 팝업이 1회 뜨고 같은 세션 재방문에는 뜨지 않는다. `seoTitle` 설정 시 페이지 소스의 `<title>`이 해당 값이고, `pixelId`가 null이면 pixel 스크립트 태그가 없다.

8. **무회귀 게이트 (전 Wave)**: 확장이 기존 운영을 건드리지 않는다.
   - Current: 운영 매장들의 `published_tokens`는 확장 키가 없는 상태.
   - Target: 신규 테이블/컬럼 0, 신규 Pool/Client 인스턴스 0 (읽기=ShopReadonlyDbService, 쓰기=기존 admin 서비스만). DDL은 R9의 CHECK 제약 교체 1건만 허용. `sanitizeTokens` 미경유 raw 토큰 저장 경로 없음. legacy `shop-storefront.page.ts` 무변경. 변경 파일 ESLint 오류 0.
   - Acceptance: `api-ventago/migrations/` 신규 파일이 R9의 CHECK 교체 SQL 1개뿐이고(테이블/컬럼 추가 0), 변경 파일 전체에서 `new Pool(`/`pool.connect(` 신규 호출이 0건이며, 변경 파일 `npx eslint`가 오류 0으로 통과한다. 확장 키 없는 기존 매장 공개 페이지가 회귀 없이 렌더된다.

9. **macrostructure 4종 재편 — rails + masonry 추가, doc 제거 (Wave A2, ★확정 2026-07-23)**: 색/글꼴만이 아니라 레이아웃 뼈대 자체가 달라진다.
   - Current: `macrostructure`는 `marquee | bento | doc` 3종. `sanitizeMacrostructure()`가 이 3값만 허용하고, DB에는 `api-ventago/migrations/2026-07-22-store-themes.sql:14-15`에서 만든 제약 **`chk_store_theme_macro CHECK (macrostructure IN ('marquee','bento','doc'))`** 이 걸려 있다 (컬럼은 `VARCHAR(40) NOT NULL DEFAULT 'marquee'`). 뼈대가 사실상 하나여서 매장 간 차별화가 색/글꼴에 그친다.
   - **최종 값 집합 (4종)**: `marquee | bento | rails | masonry` — `rails`/`masonry` 추가, **`doc` 제거**(스토리형은 Lookbook 아키타입과 역할 중복 — 사용자 확정 2026-07-23).
   - Target:
     - **DDL (본 Phase 유일)**: `ALTER TABLE store_themes DROP CONSTRAINT chk_store_theme_macro;` + 동일 이름으로 `CHECK (macrostructure IN ('marquee','bento','rails','masonry'))` 재생성하는 마이그레이션.
       - **실측 (2026-07-23 조회 확인)**: 운영 5434 = 9행 전부 `marquee`, 로컬 5432 = 4행 전부 `marquee`. **`doc` 사용 0건** (컬럼 값 + `published_tokens`/`draft_tokens` JSONB 내부 모두 0). 따라서 `doc` 제거는 데이터 마이그레이션 불필요, 제약 교체 시 테이블 재작성 없음, 락 시간 무시 가능.
       - 그래도 **방어적으로** 제약 재생성 **전에** `UPDATE store_themes SET macrostructure='marquee' WHERE macrostructure='doc';` 를 같은 트랜잭션에 포함한다(실행 시점에 데이터가 생겼을 경우 대비 — 현재 기준 0행 영향).
       - `api-ventago/migrations/` 에 SQL 커밋, 로컬 5432 + 운영 5434 양쪽 `--single-transaction -v ON_ERROR_STOP=1` 적용. 기존 테이블 ALTER이므로 owner 이전 불필요.
     - `store-theme.constants.ts`의 `Macrostructure` 타입 + `sanitizeMacrostructure()` 허용값을 **4종으로 재편**(`'doc'` 제거, `'rails'`/`'masonry'` 추가), `tienda-app/src/lib/theme-preset.ts`에 미러. `'doc'` 은 알 수 없는 값과 동일하게 `marquee` 로 강등된다.
     - **doc 렌더 경로 제거**: `index.tsx` 의 `doc` 분기와 전용 스타일을 삭제한다. 남겨두면 도달 불가 코드가 된다.
     - **rails 렌더러**: Netflix식 선반 — 소스별 가로 스크롤 행(Novedades / Más vendidos / 카테고리별 선반), 행 단위 lazy load, 스크롤 스냅 + 좌우 화살표. `tienda-app/src/components/macro/RailsLayout.tsx` 신규.
     - **masonry 렌더러**: CSS `columns` 기반(JS masonry 라이브러리 금지), 세로 사진 비율 유지, 모바일 2열 / 데스크톱 4열, 무한 스크롤은 기존 카탈로그 페이지네이션 재사용. `tienda-app/src/components/macro/MasonryLayout.tsx` 신규.
     - 에디터 macrostructure 선택 UI를 **4종**으로 재편 (각 항목에 미니 와이어프레임 아이콘 + 한 줄 성격 설명 + 적합 매장 안내). 시각 정본: `tienda-online-estructuras-editor-mockup.html`.
     - **구조별 사용 가능 섹션 게이팅**: 구조에 따라 일부 섹션을 자동 비활성화하고 에디터에 사유를 표시한다 — `rails` 는 `carousel`(선반에 흡수), `bento` 는 `hero`(큰 타일과 중복), `masonry` 는 `benefits`/`duoBanners`(그리드 리듬 차단). **비활성 = 삭제 아님** — JSONB 값은 그대로 보존해 구조를 되돌리면 복귀한다.
   - Acceptance: 마이그레이션 적용 후 `macrostructure='rails'`로 publish하면 공개 홈이 가로 스크롤 선반 레이아웃으로 렌더되고, `'masonry'`면 CSS columns 기반 비정형 그리드로 렌더된다. 기존 `marquee`/`bento` 렌더는 회귀 없다. `'doc'` 또는 알 수 없는 값(`'foo'`)을 저장하면 `sanitizeMacrostructure()`가 `marquee`로 강등하고, 코드베이스에 `'doc'` 렌더 분기가 남아있지 않다(`grep -rn "'doc'" tienda-app/src api-ventago/src/app/shop-public` 0건). 로컬 5432와 운영 5434의 CHECK 제약 정의가 동일함을 대조로 확인한다. 구조 전환 후 되돌리면 비활성됐던 섹션 값이 그대로 복귀한다.

10. **reels 섹션 타입 (Wave B, ★확정 2026-07-23)**: 세로 영상으로 상품을 판다.
    - Current: `sections` 타입에 영상이 없다. 영상 업로드 경로도 없다.
    - Target: `reels` 섹션 타입 — 세로 영상 카드 가로 스크롤, 각 카드에 상품 연결(가격 + CTA 오버레이). 업로드는 R2의 에셋 엔드포인트를 확장해 처리(mp4/webm만, 20MB 제한, **poster 이미지 필수**, UUID 파일명). 렌더는 `<video muted playsInline preload="none" poster>` — **autoplay 금지, 탭 시 재생**(모바일 데이터 배려). `tienda-app/src/components/sections/ReelsSection.tsx` 신규 + 에디터 reels 편집 UI.
    - Acceptance: reels 섹션에 영상 2개를 올려 publish하면 공개 홈에서 세로 카드 가로 스크롤로 나오고, 초기 로드 시 영상 바이트가 요청되지 않으며(`preload="none"`, poster만 표시), 탭하면 재생된다. 21MB 파일 또는 `.mov`는 400으로 거부된다. poster 없이 저장하면 sanitize가 해당 item을 drop한다.

11. **quiz 섹션 타입 — asesor guiado (Wave B, ★확정 2026-07-23)**: 방문자가 3문항에 답하면 맞는 상품을 추천받는다.
    - Current: 홈에 가이드형 진입점이 없다. 비회원 첫 방문자는 카탈로그를 스스로 뒤져야 한다.
    - Target (목업 `tienda-online-quiz-mockup.html` 이 시각 정본):
      - **흐름**: 홈 진입 배너("Respondé 3 preguntas y te mostramos lo tuyo · 30 segundos" + `Empezar el quiz →`) → 질문 3개(상단 `1 / 3` 진행 표시 + `← Volver` 뒤로가기, 선택지는 label + sub 설명 + emoji) → 결과("TU SELECCIÓN / Esto es lo tuyo") 추천 3개(각 카드에 `MATCH NN%` 배지 + 매칭 이유 텍스트) → 출구 3종(`💬 Asesorame por WhatsApp` / `↺ Repetir quiz` / `Ver catálogo completo →`)
      - **답변→필터 변환은 프런트에서 기존 catálogo 쿼리 파라미터로 매핑**. `mapping` 이 각 질문 key 를 카탈로그 파라미터(`categoryId` / `priceRange` 등)에 연결한다. **신규 백엔드 쿼리·테이블·엔드포인트 0 — pool 무부담.**
      - 질문 텍스트 / 선택지(value·label·sub·emoji) / 매핑 / 옵션별 매칭 이유 문구는 전부 JSONB `quiz` 섹션에서 admin 이 편집(에디터에 질문·선택지 추가/삭제 UI).
      - `MATCH NN%` 는 매칭 이유와 함께 표시되는 **표시용 스코어** — 실제 추천 순위와 모순되지 않게 산출한다(내림차순). 가짜 난수 금지.
      - 파일: `tienda-app/src/components/sections/QuizSection.tsx`(신규) + 에디터 quiz 편집 UI.
    - Acceptance: quiz 섹션을 켜고 질문 3개를 설정해 publish하면 공개 홈에 배너가 뜨고, 3문항 응답 후 추천 3개가 매칭 이유와 함께 표시된다. 이때 **네트워크 요청은 기존 카탈로그 엔드포인트만** 사용한다(신규 엔드포인트 호출 0건). 질문 5개 / 선택지 5개를 저장하면 sanitize 가 4개로 clamp한다. `Ver catálogo completo` 는 선택된 필터가 적용된 카탈로그로 이동한다.

## 기술 스택

- NestJS 11 (api-ventago) + Next.js (tienda-app 스토어프런트/에디터, ventago-app admin 카드)
- PostgreSQL 18 — `store_themes` JSONB 확장만, raw parameterized SQL 유지
- MinIO — `MinioService` 재사용 (`shop-public.module.ts`에 `MinioModule` import)
- ESLint: 각 워크스페이스 기존 설정 (`newline-before-return`, `lines-around-comment`, `no-unused-vars`)

## 금지사항 / 주의사항

- `store_themes` DDL은 **R9의 macrostructure CHECK 제약 교체 1건만 허용** — 그 외 컬럼/테이블 추가 금지 (나머지는 전부 JSONB 키 확장). 해당 마이그레이션은 로컬 5432 + 운영 5434 **동시 적용 후 대조 확인** 필수
- 영상 업로드 검증 필수: mp4/webm만, 20MB 제한, poster 필수, UUID 파일명 — 미검증 업로드로 MinIO 용량 폭발 방지. reels autoplay 금지(`preload="none"` + 탭 재생)
- masonry는 CSS `columns` 기반 — JS masonry 라이브러리 도입 금지
- 새 Pool/Client 인스턴스 생성 금지
- legacy 스토어프런트(`shop-storefront.page.ts`) 무변경 — 대상은 tienda-app만
- `sanitizeTokens` 미경유 raw 토큰 저장 금지 (XSS: 텍스트 렌더 시 이스케이프, href는 http(s)/상대경로만)
- **`publish()` 는 현재 `draft_tokens` 를 재검증 없이 복사한다** (리서치 발견) — 확장 키가 늘어나므로 publish 경로에도 sanitize 를 태우거나, `saveDraft()` 가 유일 쓰기 경로임을 테스트로 못박을 것
- 정렬 파라미터를 SQL 에 문자열 보간 금지 — whitelist → 고정 ORDER BY 절 매핑
- 업로드 검증: png/jpg/webp/svg(로고만), 2MB 제한, 파일명 UUID 재부여
- `apiConnector.remove()` 사용 (`.delete()` 아님)
- Mac 워킹트리 미커밋 WIP(`afip-issuer.service.ts`)는 건드리지 말 것
- device VM 타입체크 OOM 이력 → 최종 게이트는 Jenkins

## 완료 기준

- ESLint 오류 0개 (변경 파일 기준)
- 기존 store(확장 키 없는 `published_tokens`)의 스토어프런트가 회귀 없이 렌더
- draft→publish 왕복 후 공개 페이지에 섹션 순서/토글 반영
- 이미지 업로드가 MinIO 경유(`/api/minio/<fileName>`)로 표시
- macrostructure `rails`/`masonry` 선택 시 스토어프런트가 해당 뼈대로 렌더 (`marquee`/`bento` 회귀 없음, `doc` 잔여 코드 0)
- CHECK 제약 마이그레이션이 로컬 5432 + 운영 5434 양쪽 적용·대조 확인
- reels 섹션이 `preload="none"` + poster 로 렌더되고 탭 시 재생 (autoplay 없음)
- quiz 섹션 3문항 → 추천 3개가 표시되고, 그 과정에서 **신규 백엔드 엔드포인트 호출 0건**(기존 카탈로그 쿼리만 사용)
- 신규 테이블/컬럼/커넥션 0개 (유일한 DDL = macrostructure CHECK 교체)
