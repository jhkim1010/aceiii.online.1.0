# Phase 61: Tienda Online 에디터 확장 — Tiendanube급 admin 커스터마이징 — Specification

**Created:** 2026-07-23
**Source:** `.gsd/spec-phase61-tienda-online-editor.md` (2026-07-23), 목업 `tienda-online-editor-mockup.html`
**Scope:** Wave A + B + C (전체)
**Requirements:** 8 locked

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
    { "type": "newsletter", "enabled": false, "title": "" }
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

Clamp/whitelist 규칙: sections 최대 8개, hero images 최대 5개, 텍스트 필드 최대 200자, `catalog.pageSize` ≤ 48, 알 수 없는 키는 drop (기존 가드레일 철학 유지).

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
   - Acceptance: `productCard.discountBadge=false`, `hoverSecondImage=false`로 publish하면 공개 목록의 카드에서 할인 배지가 사라지고 hover 시 두 번째 이미지로 바뀌지 않는다.

6. **카탈로그 정렬·페이지·필터 + 신뢰 요소 (Wave B)**: 목록 동작과 푸터 신뢰 요소를 admin이 결정한다.
   - Current: 정렬/페이지 크기/품절 표시/필터가 고정. 결제·배송 로고, compra protegida, 정책 링크 없음.
   - Target: `shop-catalog.controller.ts`가 sort/pageSize/showOutOfStock 쿼리 파라미터 수용(pageSize clamp ≤ 48, 기존 파라미터라이즈드 쿼리 유지) + 프런트 목록이 `catalog` 토큰을 기본값으로 사용, size/color/price 필터 표시 토글. 푸터에 결제/배송 로고 chips + compra protegida 배지 + 정책 링크 렌더 + 해당 에디터 아코디언.
   - Acceptance: `catalog.pageSize=12`, `defaultSort='price_asc'`, `filters.color=false`로 publish하면 공개 목록이 12개씩 가격 오름차순으로 나오고 색상 필터가 숨겨진다. `pageSize=999`를 저장해도 48로 clamp된다.

7. **마케팅 팝업 + SEO/pixel (Wave C)**: 웰컴 팝업과 검색 메타를 admin이 설정한다.
   - Current: 팝업 없음. `<Head>`에 매장별 SEO title/description 주입 없음. pixel 삽입 경로 없음.
   - Target: 웰컴 팝업(세션당 1회, 제목 + 선택적 쿠폰 코드 표시) 렌더 + 에디터. `getServerSideProps`에서 `seoTitle`/`seoDescription`을 `<Head>`에 주입, `pixelId`는 값이 있을 때만 스크립트 삽입. 쿠폰 코드 ↔ Campañas discounts 실검증은 Phase 61 범위 외 — TODO 주석만.
   - Acceptance: `marketing.popup.enabled=true`로 publish 후 공개 페이지 첫 방문에 팝업이 1회 뜨고 같은 세션 재방문에는 뜨지 않는다. `seoTitle` 설정 시 페이지 소스의 `<title>`이 해당 값이고, `pixelId`가 null이면 pixel 스크립트 태그가 없다.

8. **무회귀·무마이그레이션 게이트 (전 Wave)**: 확장이 기존 운영을 건드리지 않는다.
   - Current: 운영 매장들의 `published_tokens`는 확장 키가 없는 상태.
   - Target: `store_themes` DDL 변경 0, 신규 테이블/컬럼 0, 신규 Pool/Client 인스턴스 0 (읽기=ShopReadonlyDbService, 쓰기=기존 admin 서비스만). `sanitizeTokens` 미경유 raw 토큰 저장 경로 없음. legacy `shop-storefront.page.ts` 무변경. 변경 파일 ESLint 오류 0.
   - Acceptance: `git diff`에 `api-ventago/migrations/` 신규 파일이 없고, 변경 파일 전체에서 `new Pool(`/`pool.connect(` 신규 호출이 0건이며, 변경 파일 `npx eslint`가 오류 0으로 통과한다. 확장 키 없는 기존 매장 공개 페이지가 회귀 없이 렌더된다.

## 기술 스택

- NestJS 11 (api-ventago) + Next.js (tienda-app 스토어프런트/에디터, ventago-app admin 카드)
- PostgreSQL 18 — `store_themes` JSONB 확장만, raw parameterized SQL 유지
- MinIO — `MinioService` 재사용 (`shop-public.module.ts`에 `MinioModule` import)
- ESLint: 각 워크스페이스 기존 설정 (`newline-before-return`, `lines-around-comment`, `no-unused-vars`)

## 금지사항 / 주의사항

- `store_themes` DDL 변경 금지 (JSONB 키 확장만) — 마이그레이션 이슈 원천 차단
- 새 Pool/Client 인스턴스 생성 금지
- legacy 스토어프런트(`shop-storefront.page.ts`) 무변경 — 대상은 tienda-app만
- `sanitizeTokens` 미경유 raw 토큰 저장 금지 (XSS: 텍스트 렌더 시 이스케이프, href는 http(s)/상대경로만)
- 업로드 검증: png/jpg/webp/svg(로고만), 2MB 제한, 파일명 UUID 재부여
- `apiConnector.remove()` 사용 (`.delete()` 아님)
- Mac 워킹트리 미커밋 WIP(`afip-issuer.service.ts`)는 건드리지 말 것
- device VM 타입체크 OOM 이력 → 최종 게이트는 Jenkins

## 완료 기준

- ESLint 오류 0개 (변경 파일 기준)
- 기존 store(확장 키 없는 `published_tokens`)의 스토어프런트가 회귀 없이 렌더
- draft→publish 왕복 후 공개 페이지에 섹션 순서/토글 반영
- 이미지 업로드가 MinIO 경유(`/api/minio/<fileName>`)로 표시
- 신규 테이블/컬럼/커넥션 0개 (JSONB만)
