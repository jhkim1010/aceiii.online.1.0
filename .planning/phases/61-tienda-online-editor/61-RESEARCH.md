# Phase 61: Tienda Online 에디터 확장 — Research

**Researched:** 2026-07-23
**Domain:** NestJS 11 (api-ventago) + Next.js 13 Pages Router (tienda-app) — JSONB 콘텐츠 스키마 확장, macrostructure 렌더러, MinIO 영상 업로드
**Confidence:** HIGH (전 항목 실제 코드 읽기로 검증. `[ASSUMED]` 표기된 소수 항목만 배포 환경 확인 필요)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**포함 (Wave A + A2 + B + C 전체):**
- **macrostructure 5종 확장** (`rails` Netflix식 선반 + `masonry` CSS columns) + 전용 렌더러 2종 + 에디터 선택 UI 5종 + `store_themes.macrostructure` CHECK 제약 교체 마이그레이션 (본 Phase 유일 DDL, 5432+5434)
- **`reels` 섹션 타입** (세로 영상 카드 + 상품 연결, mp4/webm ≤20MB + poster 필수, autoplay 금지)
- `store_themes.draft_tokens` / `published_tokens` JSONB 스키마 확장 + `sanitizeTokens()` 가드레일 확장 (SSOT = `store-theme.constants.ts`)
- 테마 이미지 업로드 엔드포인트 (`POST /shop/:storeId/theme/asset`, MinIO 재사용)
- 에디터 패널(`tienda-app/src/pages/[storeId]/panel/diseno.tsx`) 아코디언 전환 + 브랜드/공지바/홈 섹션/연락처/상품카드/카탈로그/신뢰요소/마케팅 편집 UI
- 스토어프런트(`tienda-app/src/pages/[storeId]/index.tsx`) sections 배열 순회 렌더 + 공지바 + 로고 + WhatsApp 플로팅 + 푸터
- `ProductCard.tsx` 6개 표시 옵션 조건부 렌더
- `shop-catalog.controller.ts` 정렬/pageSize/품절표시 쿼리 파라미터 + 프런트 필터 토글
- 마케팅 웰컴 팝업(세션 1회) + SEO title/description `<Head>` 주입 + 조건부 pixel 스크립트

**제외:**
- legacy 스토어프런트 `shop-storefront.page.ts` — 무변경
- 팝업 쿠폰 코드 ↔ Campañas discounts 실검증 — TODO 주석만 (Phase 61 범위 외)
- 신규 테이블 / 신규 컬럼 — 금지. DDL 은 macrostructure CHECK 제약 교체 **1건만** 허용
- ventago-app `StorefrontDesignCard.tsx` 는 진입 카드일 뿐 — 필요 시 링크만, 편집 UI 이식 아님

**저장 구조:** 확장은 전부 `store_themes.draft_tokens`/`published_tokens` JSONB 키 추가로만 처리(신규 테이블·컬럼·마이그레이션 0개). 이미지는 MinIO 업로드 후 JSONB 엔 `fileName` 문자열만. 표시는 `{API_HOST}/minio/{fileName}`.

**가드레일:** 모든 쓰기는 `sanitizeTokens()` 경유 필수. `sections` 최대 8개, hero `images` 최대 5개, 텍스트 최대 200자, `catalog.pageSize` ≤ 48. 알 수 없는 키는 drop. href 는 `http(s)://` 또는 `/` 상대경로만, 그 외 null. 텍스트는 렌더 시 이스케이프, `dangerouslySetInnerHTML` 금지.

**하위호환:** 확장 키 없는 기존 `published_tokens` 로도 `buildThemeResponse()` 가 현행과 동일 동작. 모든 확장 키에 default 존재. 기존 매장 공개 페이지 렌더 회귀 0 이 완료 게이트.

**DB/커넥션:** 읽기=`ShopReadonlyDbService`, 쓰기=기존 `store-theme-admin.service.ts` 경로만. 새 `Pool`/`Client` 인스턴스 생성 금지.

**업로드 검증:** png/jpg/webp, svg 는 로고 전용, 최대 2MB, 파일명 UUID 재부여. 인가는 기존 `store-theme-edit.guard.ts`(magic-link). `MinioModule` 을 `shop-public.module.ts` imports 에 추가.

**에디터 UX:** 승인된 목업 `tienda-online-editor-mockup.html` 기준(아코디언 레이아웃). 홈 섹션 리스트 ▲▼ 순서 이동 + 표시 토글, 순서=배열 순서. `components/panel/SectionListEditor.tsx` 로 분리. 기존 draft→미리보기→publish 왕복 흐름 유지.

**Wave 순서:** A(브랜드·공지바·홈섹션·연락처) → A2(macrostructure rails/masonry + CHECK 마이그레이션, 마이그레이션 태스크 `[BLOCKING]`) → B(상품카드·카탈로그·신뢰요소·reels) → C(마케팅·SEO). reels(B5)는 A2 이후 배치.

**코드 규약:** ESLint `newline-before-return`/`lines-around-comment`/`no-unused-vars` 준수(단, 실제 강제 범위는 워크스페이스별 상이 — 아래 Pitfall 참조). `apiConnector.remove()`. 주석 한국어/식별자 영어. device VM 타입체크 OOM 이력 → 로컬 전체 타입체크 강행 금지, 최종 게이트는 Jenkins.

**건드리지 말 것:** Mac 워킹트리 미커밋 WIP `afip-issuer.service.ts`. legacy `shop-storefront.page.ts`.

**템플릿 다양성 확정 (2026-07-23 22:52):**
- macrostructure 5종: `marquee | bento | doc | rails | masonry`. `rails`=Netflix식 선반(소스별 가로 스크롤 행, 행 단위 lazy load, 스크롤 스냅+좌우 화살표). `masonry`=CSS `columns` 기반(세로 사진 비율 유지, 모바일 2열/데스크톱 4열, **JS masonry 라이브러리 금지**).
- `reels` 섹션 타입 신설(Wave B): 세로 영상 카드 가로 스크롤 + 상품 연결. `<video muted playsInline preload="none" poster>` — autoplay 금지, 탭 시 재생.
- DDL 예외 1건: `store_themes.macrostructure` CHECK 제약을 5값으로 교체. 본 Phase 유일 DDL. 기존 테이블 ALTER 라 owner 이전 불필요. 로컬 5432 + 운영 5434 동시 적용 + 대조 확인 필수.
- 영상 업로드 검증: mp4/webm만, 20MB 제한, poster 이미지 필수, UUID 파일명.

### Claude's Discretion
- 확장 타입의 TypeScript 인터페이스 명명/분해 방식 (`StoreThemeContent` 등 별도 인터페이스로 뺄지, `StoreThemeTokens` 확장할지)
- 섹션 렌더 컴포넌트 파일 분해 단위 (`components/sections/Hero.tsx` 등)
- 아코디언 구현 수단 (기존 tienda-app 스타일 체계 내에서 선택)
- 업로드 엔드포인트의 용도 구분 전달 방식 (query param vs body field)
- 캐러셀 `source: bestseller` 의 집계 쿼리 구현 방식 (기존 카탈로그 서비스 재사용 우선)
- 팝업 세션 1회 판정 저장소 (sessionStorage 등)

### Deferred Ideas (OUT OF SCOPE)
- 팝업 쿠폰 코드 ↔ Campañas discounts 실제 검증/발급 연동 — TODO 주석만 (TASK-C3)
- ventago-app 내 storefront 편집 UI 이식 — `StorefrontDesignCard.tsx` 진입 링크 유지
- legacy `shop-storefront.page.ts` 의 확장 키 대응 — 대상 아님
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| R1 | JSONB 스키마 확장 + sanitize 가드레일 | §"핵심 발견 1" — 실제 쓰기 퍼널은 `saveDraft()`, 응답 조립은 `buildThemeResponse()`. 두 지점 모두 확장 필요, `publish()`는 재검증 안 함 |
| R2 | 테마 이미지 업로드 엔드포인트 | §"MinIO 업로드 패턴" — `store.controller.ts` 기존 예시 인용, FileInterceptor 검증 패턴 |
| R3 | 에디터 패널 — 브랜드·공지바·홈섹션·연락처 | §"diseno.tsx 현재 구조" — state/patch/save/publish 흐름 그대로 확장 |
| R4 | 스토어프런트 섹션 렌더 | §"index.tsx 현재 렌더 구조" — sections 배열 순회 삽입 지점 |
| R5 | 상품 카드 옵션 | §"핵심 발견 2" — `ShopProductDto`에 `priceOrig`/`stock` 필드 자체가 없음, 백엔드 확장 필수 |
| R6 | 카탈로그 정렬·페이지·필터 + 신뢰 요소 | §"shop-catalog 쿼리 구조" — 현재 `ORDER BY p.updated_at DESC` 하드코딩, sort 파라미터 부재 |
| R7 | 마케팅 팝업 + SEO/pixel | §"SEO/pixel/팝업 구현 패턴" — `getServerSideProps` + `next/head` + `next/script` |
| R8 | 무회귀 게이트 | §"핵심 발견 1"의 하위호환 설계, §Pitfalls 전체 |
| R9 | macrostructure 5종 확장 (rails+masonry+DDL) | §"마이그레이션 안전성", §"rails/masonry 렌더 구현 패턴" |
| R10 | reels 섹션 타입 | §"reels 영상 렌더 패턴", §"MinIO 업로드 패턴"(영상 확장) |
</phase_requirements>

## Summary

Phase 61 은 신규 라이브러리 도입이 전혀 없는 **순수 확장 작업**이다 — api-ventago(NestJS 11 + pg 8 + minio-js 8 + sequelize-typescript 2)와 tienda-app(Next.js 13.3.2 Pages Router + React 18, 의존성은 `next`/`react`/`react-dom` 3개뿐)의 기존 스택 안에서 JSONB 스키마·렌더 컴포넌트·업로드 엔드포인트만 늘린다. rails/masonry/reels 는 순수 CSS(`scroll-snap-type`, `columns`) + vanilla React(`IntersectionObserver`)로 구현해야 하며 캐러셀·masonry 전용 npm 패키지는 프로젝트에 없고 도입도 금지돼 있다.

가장 중요한 발견은 **저장/응답 퍼널이 두 갈래**라는 점이다. `store-theme.constants.ts`의 `sanitizeTokens()`는 `StoreThemeAdminService.saveDraft()`에서 "쓰기 전" JSONB 를 만드는 데 쓰이고, `buildThemeResponse()`는 읽기(`getPublicTheme`)와 초안 조회(`getDraft`) 양쪽에서 "응답 조립"에 쓰인다. `publish()`는 `draft_tokens`를 그대로 `published_tokens`로 복사할 뿐 재검증하지 않는다. 즉 확장 키의 가드레일 유효성은 **saveDraft() 경유가 유일한 진입점**이라는 사실에 전적으로 의존한다 — 이 경로를 벗어나는 저장 코드(예: A2 마이그레이션 시드, 관리자 백필 스크립트)가 생기면 즉시 XSS/오염 벡터가 된다.

두 번째 중요한 발견은 R5(ProductCard 옵션)가 프런트 전용 작업이 아니라는 점이다. 공개 API DTO(`ShopProductDto`/`toDto()`)가 현재 `priceOrig`(할인 배지용)와 `stock`(últimas unidades 배지용) 필드를 아예 노출하지 않는다 — `products` 테이블엔 `price_orig`/`stock` 컬럼이 실존하지만 SELECT/DTO 매핑에서 누락돼 있다. TASK-B1 을 "ProductCard.tsx 파일만" 건드리는 작업으로 계획하면 실행 중 데이터 부재로 막힌다.

세 번째, `.planning/intel/db-schema-tables.md`(CLAUDE.md 가 "추측 금지, 이 파일 참조" 라 명시한 파일)가 **stale** 하다 — `products.slug`/`long_description`/`gender`/`material`/`is_published_shop`/`seo_title`/`seo_description` 컬럼이 실제 DB(및 `shop-catalog.service.ts`의 실제 SQL)엔 존재하지만 이 문서엔 없다. Wave B 에서 products 컬럼을 참조할 때 이 문서만 믿지 말고 `shop-mvp-product-metadata.sql` + `shop-catalog.service.ts`의 실제 쿼리를 함께 봐야 한다.

**Primary recommendation:** `sanitizeTokens()` 옆에 `sanitizeContent(raw)` 같은 새 함수를 추가해 확장 키 전용 whitelist/clamp/default 를 처리하고, `saveDraft()`에서 `{ ...tokens, ...content }`로 합쳐 저장하며, `buildThemeResponse()` 시그니처에 `rawContent` 파라미터를 추가해 3개 호출부(getPublicTheme/getDraft/saveDraft) 모두 동일한 raw JSONB 객체를 토큰용과 컨텐츠용으로 함께 전달하도록 통일한다. R5 는 백엔드(DTO 확장) → 프런트(ProductCard) 순서로 태스크를 쪼갠다.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| JSONB 확장 키 검증(whitelist/clamp/href XSS 방어) | API/Backend (`store-theme.constants.ts`) | — | 유일한 신뢰 경계 — 프런트 검증은 UX 보조일 뿐 신뢰 불가 |
| draft/publish 쓰기 | API/Backend (`store-theme-admin.service.ts`) | — | 기존 Sequelize 연결 재사용, 신규 Pool 금지 |
| 공개 테마/카탈로그 읽기 | API/Backend (`ShopReadonlyDbService`) | CDN(캐시 TTL) | 이미 격리된 read-only pool + `MemoryCacheService` 60s~5min TTL |
| 에디터 UI 상태관리(아코디언, 섹션 순서, 미리보기) | Browser/Client (`diseno.tsx`) | — | React state, 서버 상태 없음 — 저장 시점에만 API 호출 |
| 이미지/영상 파일 저장 | API/Backend → MinIO(S3 호환) | — | `MinioService.uploadFile()`, JSONB 엔 fileName 문자열만 |
| rails/masonry/reels 렌더 | Frontend Server(SSR) + Browser(hydration) | — | `getServerSideProps`로 초기 HTML, 스크롤/lazy load/video는 클라이언트 hydration 후 동작 |
| SEO title/description/pixel | Frontend Server(SSR) | Browser(next/script) | `<Head>`는 SSR에서 주입돼야 크롤러가 봄. pixel은 클라이언트 조건부 로드 |
| 카탈로그 정렬/필터 쿼리 | API/Backend (`shop-catalog.controller.ts`) | Database | pageSize clamp·ORDER BY 매핑은 백엔드가 소유(프런트가 신뢰할 수 없는 sort 문자열을 직접 SQL에 꽂으면 안 됨) |

## Standard Stack

### Core (기존 스택 재사용 — 신규 라이브러리 0)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `@nestjs/core`/`@nestjs/platform-express` | ^11.0.1 | API 프레임워크, `FileInterceptor` | [VERIFIED: api-ventago/package.json] 기존 |
| `minio` | ^8.0.6 | MinIO S3 호환 클라이언트 | [VERIFIED: package.json] `MinioService` 가 이미 래핑 |
| `pg` | ^8.13.1 | `ShopReadonlyDbService` 전용 Pool | [VERIFIED] 신규 Pool 생성 금지 — 이 기존 인스턴스만 재사용 |
| `sequelize`/`sequelize-typescript` | ^6.37.5 / ^2.1.6 | 쓰기 경로(`@InjectConnection`) | [VERIFIED] `store-theme-admin.service.ts`가 이미 사용 |
| `next` | 13.3.2 | tienda-app Pages Router | [VERIFIED: tienda-app/package.json] |
| `react`/`react-dom` | 18.2.0 | UI | [VERIFIED] |

### Supporting
tienda-app 의존성은 `next`/`react`/`react-dom` 3개뿐이며 devDependencies 도 타입/eslint/typescript 뿐이다 — 캐러셀·masonry·비디오 플레이어 라이브러리가 전혀 없다. **이것이 정상 상태이며, Phase 61 이후에도 유지해야 한다** (masonry 는 SPEC 이 JS 라이브러리 도입을 명시적으로 금지).

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| CSS `columns` masonry(확정) | `react-masonry-css`, `masonic` 등 JS 라이브러리 | SPEC 이 명시적으로 금지(TASK-A10, 금지사항 목록) — 번들 증가 + Pages Router SSR 비호환 이슈 회피 목적으로 이미 결정됨 |
| 순수 CSS 스크롤 스냅(확정) | `embla-carousel`, `swiper` | 의존성 0 유지 원칙과 상충. rails 는 네이티브 `overflow-x:auto; scroll-snap-type:x mandatory`로 충분 |
| `<video>` 네이티브(확정) | `video.js`, `plyr` | reels 는 단순 탭-재생/일시정지만 필요 — 라이브러리 오버킬 |

**Installation:** 없음 — Phase 61 은 `npm install` 대상 패키지가 없다.

## Architecture Patterns

### 핵심 발견 1 — 저장/응답 퍼널이 두 갈래다 (가장 중요)

`api-ventago/src/app/shop-public/store-theme.constants.ts`:
```typescript
// 원시 토큰(부분/오염 가능)을 프리셋 기본값 위에 병합하고 범위를 강제한다.
export function sanitizeTokens(
  baseTheme: string,
  raw: Partial<StoreThemeTokens> | null | undefined,
): { baseTheme: string; tokens: StoreThemeTokens } { /* clamp 6개 원자 토큰만 */ }

export function buildThemeResponse(
  storeId: number,
  baseTheme: string,
  rawMacro: unknown,
  rawTokens: Partial<StoreThemeTokens> | null | undefined,
  enabled = false,
): StoreThemeResponse {
  const { baseTheme: safeBase, tokens } = sanitizeTokens(baseTheme, rawTokens);
  return { storeId, baseTheme: safeBase, macrostructure: sanitizeMacrostructure(rawMacro), tokens, cssVars: tokensToCssVars(tokens), enabled };
}
```

`store-theme-admin.service.ts`의 실제 쓰기 경로:
```typescript
// saveDraft() — 유일한 draft_tokens 쓰기 진입점
async saveDraft(storeId: number, body: SaveDraftBody): Promise<StoreThemeResponse> {
  const { baseTheme, tokens } = sanitizeTokens(body.baseTheme ?? 'Studio', body.tokens);
  const macro = sanitizeMacrostructure(body.macrostructure);
  const draft = { baseTheme, macrostructure: macro, ...tokens };   // ← 여기서 flat 병합 후 INSERT
  await this.sequelize.query(
    `INSERT INTO store_themes (store_id, draft_tokens, updated_at)
     VALUES ($1, $2::jsonb, NOW())
     ON CONFLICT (store_id) DO UPDATE SET draft_tokens = EXCLUDED.draft_tokens, updated_at = NOW()`,
    { bind: [storeId, JSON.stringify(draft)], type: QueryTypes.INSERT },
  );
  return buildThemeResponse(storeId, baseTheme, macro, tokens);
}

// publish() — draft_tokens 를 published_tokens 로 "그대로" 복사, 재검증 없음
async publish(storeId: number): Promise<{ published: boolean }> {
  await this.sequelize.query(
    `UPDATE store_themes SET
        base_theme = COALESCE(draft_tokens->>'baseTheme', base_theme),
        macrostructure = COALESCE(draft_tokens->>'macrostructure', macrostructure),
        published_tokens = COALESCE(draft_tokens, published_tokens),
        published_at = NOW(), updated_at = NOW()
      WHERE store_id = $1 AND draft_tokens IS NOT NULL`,
    { bind: [storeId], type: QueryTypes.UPDATE },
  );
  this.readSvc.invalidate(storeId);
  return { published: true };
}
```

**결론:**
1. JSONB 저장 구조는 **flat** 하다 — `{ baseTheme, macrostructure, accentHue, sat, ..., brand: {...}, sections: [...] }` 처럼 확장 키가 원자 토큰과 같은 레벨에 나란히 들어간다(SPEC 스키마 예시와 일치, DB 컬럼은 `underscored` 규칙과 무관 — JSONB 내부는 camelCase 그대로 저장해도 무방. 기존 코드가 이미 camelCase 로 저장 중).
2. `sanitizeTokens()`를 확장 키까지 처리하도록 억지로 늘리기보다, **별도 함수**(`sanitizeContent()` 등, 명명은 Claude's Discretion)를 만들어 `saveDraft()`에서 `sanitizeTokens()`와 나란히 호출하고 `draft` 객체에 함께 spread 하는 편이 기존 6-토큰 로직을 안 건드려 회귀 위험이 낮다.
3. `buildThemeResponse()` 시그니처에 확장 콘텐츠 raw 를 받는 파라미터를 추가해야 한다 — 이 함수가 호출되는 **3곳**(`StoreThemeService.getPublicTheme`, `StoreThemeAdminService.getDraft`, `StoreThemeAdminService.saveDraft`) 모두 같은 flat JSONB 객체(`row.published_tokens` 또는 `cfg`)를 이미 갖고 있으므로 그 객체를 토큰용과 콘텐츠용으로 동시에 넘기면 된다 — **쿼리 변경은 불필요** (이미 `SELECT ... published_tokens ...`로 전체 JSONB 를 가져오고 있음). `StoreThemeResponse` 인터페이스에 `content: StoreThemeContent` 필드(또는 flat 확장) 추가가 필요.
4. `publish()`는 그대로 두어도 안전하다 — `draft_tokens`가 이미 `saveDraft()`를 거쳐 sanitize 됐으므로 재검증이 필요 없다. **단, 이 불변조건이 깨지면 안 된다**: `draft_tokens`/`published_tokens`에 쓰는 코드 경로가 `saveDraft()`/`publish()` 외에 새로 생기면(예: A2 마이그레이션에서 기존 row 를 UPDATE 하는 시드 스크립트) 반드시 sanitize 를 거치거나 최소한 안전한 리터럴만 넣어야 한다.

### 핵심 발견 2 — ProductCard 옵션(R5)은 백엔드 DTO 확장이 선행되어야 한다

`shop-catalog.service.ts`:
```typescript
export interface ShopProductDto {
  id: number; name: string; slug: string | null; description: string | null;
  longDescription: string | null; price: number; imageUrl: string | null;
  imageUrls: string[] | null; gender: string | null; material: string | null;
  categoryId: number | null;
  // ★ priceOrig(할인 배지)·stock(últimas unidades) 없음
}

private toDto(row: Record<string, unknown>): ShopProductDto { /* price_orig, stock SELECT 자체가 없음 */ }

async listProducts(storeId: number, params: ShopListParams): Promise<ShopListResult> {
  const rows = await this.db.query<Record<string, unknown>>(
    `SELECT p.id, p.name, p.slug, p.description, p.long_description, p.price,
            p.image_url, p.image_urls, p.gender, p.material, p.category_id,
            COUNT(*) OVER() AS total_count
       FROM products p
      WHERE p.store_id = $1 AND p.is_published_shop = TRUE AND COALESCE(p.is_active, TRUE) = TRUE
        AND ($2::text IS NULL OR p.name ILIKE '%' || $2 || '%')
        AND ($3::int  IS NULL OR p.category_id = $3)
        AND ($4::text IS NULL OR p.gender = $4)
        AND ($7::int  IS NULL OR EXISTS (SELECT 1 FROM categories cat WHERE cat.id = p.category_id AND cat.global_category_id = $7))
      ORDER BY p.updated_at DESC
      LIMIT $5 OFFSET $6`,
    [storeId, q ?? null, categoryId ?? null, gender ?? null, pageSize, offset, globalCategoryId ?? null],
  );
```

`products` 테이블엔 `price_orig`(numeric, nullable)와 `stock`(integer, nullable) 컬럼이 실존한다 [VERIFIED: `.planning/intel/db-schema-tables.md:1206-1207,1218`]. `discountBadge` 는 `price_orig > price` 로, `lastUnitsBadge`는 `stock < 3`(mockup 힌트, 정확 임계값은 discretion) 로 판정 가능하지만, 현재 SELECT/DTO 어디에도 이 두 컬럼이 없다. **TASK-B1 을 계획할 때 "SELECT 절 + DTO 확장"을 별도 서브태스크로 명시하지 않으면 프런트가 받을 데이터가 없어 막힌다.**

`variantDots`(색상 점)은 더 어렵다 — 현재 `ShopProductDto`는 단일 상품 row 기준이라 변형(색상별 variant)의 존재 여부/색상 목록을 전혀 노출하지 않는다. `products.parent_id`/`is_parent`로 변형 그룹이 존재하는 것은 스키마상 확인되지만, 공개 목록 쿼리가 variant 를 집계하지 않는다. **`variantDots` 는 이 Phase 안에서 정확 구현이 어려울 수 있음 — Open Questions 참조.**

`installments`(cuotas 표시)는 이미 `ProductCard.tsx`가 `cuotas(product.price)` 유틸로 렌더 중이므로 신규 데이터가 필요 없다 — `productCard.installments` 토큰은 단순 boolean on/off 이거나, 값이 있으면 문구를 override 하는 정도로 낮은 리스크.

### store-theme.service.ts (읽기, ShopReadonlyDbService) 쿼리 형태

```typescript
async getPublicTheme(storeId: number): Promise<StoreThemeResponse> {
  const cached = this.cache.get<StoreThemeResponse>(key);
  if (cached) return cached;
  const rows = await this.db.query<Record<string, unknown>>(
    `SELECT base_theme, macrostructure, published_tokens, enabled
       FROM store_themes WHERE store_id = $1 LIMIT 1`,
    [storeId],
  );
  const row = rows[0];
  const resp = row
    ? buildThemeResponse(storeId, row.base_theme, row.macrostructure, row.published_tokens, row.enabled === true)
    : buildThemeResponse(storeId, DEFAULT_BASE_THEME, DEFAULT_MACROSTRUCTURE, null);
  this.cache.set(key, resp, THEME_TTL_MS); // 5분 TTL
  return resp;
}
```
**확장 키가 늘어나도 이 쿼리 자체는 변경 불필요** — `SELECT published_tokens`가 이미 전체 JSONB(brand/sections/... 포함)를 가져온다. 캐시 TTL(5분)은 그대로 두면 되나, `publish()`가 `this.readSvc.invalidate(storeId)`를 호출해 즉시 무효화하므로 확장 키 publish 후에도 즉시 반영된다.

### diseno.tsx 에디터의 현재 상태관리/저장 흐름

```typescript
const [baseTheme, setBaseTheme] = useState('Studio');
const [macro, setMacro] = useState<Macrostructure>('marquee');
const [tokens, setTokens] = useState<StoreThemeTokens>(DEFAULT_TOKENS);
// ...
const onSave = useCallback(async () => {
  setState('saving');
  await saveThemeDraft(storeId, token, { baseTheme, macrostructure: macro, tokens });
  setState('saved');
}, [storeId, token, baseTheme, macro, tokens]);

const onPublish = useCallback(async () => {
  setState('publishing');
  await saveThemeDraft(storeId, token, { baseTheme, macrostructure: macro, tokens }); // 발행 전 최신 초안 저장
  await publishTheme(storeId, token);
  setState('published');
}, [storeId, token, baseTheme, macro, tokens]);
```
확장 시 그대로 이어갈 패턴: `content` 라는 별도 `useState` (brand/announce/sections/contact/...)를 추가하고, `saveThemeDraft`/`SaveThemeBody`(`shop-api.ts`)의 body 에 `content` 필드를 함께 실어 보내면 된다. **주의**: 현재 `diseno.tsx`는 383줄짜리 단일 컴포넌트에 모든 UI 를 인라인 `CSSProperties` 객체로 그린다(MUI 아님, styled-components 아님) — 아코디언 전환 시 이 스타일 체계를 유지해야 한다(CONTEXT "아코디언 구현 수단은 discretion" 이지만 기존 스타일 체계 안에서).

### index.tsx 스토어프런트의 macrostructure 분기 현황

현재 `index.tsx`는 macrostructure 를 **레이아웃 전용 그리드 밀도**로만 쓴다 — 섹션 자체를 분기하지 않는다:
```typescript
const gridStyle: CSSProperties = {
  display: 'grid',
  gap: theme.macrostructure === 'doc' ? 14 : 18,
  gridTemplateColumns:
    theme.macrostructure === 'bento' ? 'repeat(auto-fill, minmax(240px, 1fr))'
      : theme.macrostructure === 'doc' ? 'repeat(auto-fill, minmax(160px, 1fr))'
      : 'repeat(auto-fill, minmax(200px, 1fr))',
};
// ...
<div style={wrapStyle} data-macro={theme.macrostructure}>
  ...
  <section style={gridStyle}>{items.map(p => <ProductCard key={p.id} product={p} />)}</section>
```
현재 hero/promo/aistrip 섹션은 **하드코딩**돼 있고 `sections` 배열 순회가 전혀 없다(R4 가 신설하는 부분). rails/masonry 분기는 이 `gridStyle` 삼항 분기를 확장하는 게 아니라 **최상위 렌더 분기**로 넣어야 한다 — rails 는 상품 그리드 자체를 가로 스크롤 행들로 바꾸므로 `<section style={gridStyle}>{items.map(...)}</section>` 블록 전체를 `theme.macrostructure === 'rails' ? <RailsLayout .../> : theme.macrostructure === 'masonry' ? <MasonryLayout .../> : <section style={gridStyle}>...</section>` 형태로 교체해야 한다. `data-macro={theme.macrostructure}` 어트리뷰트는 이미 최상위에 있으므로 CSS 훅으로 재사용 가능.

### ProductCard.tsx 현재 props 와 하드코딩된 표시 요소

```typescript
export default function ProductCard({ product }: { product: ShopProduct }) {
  const { add, openTryOn } = useShop();
  return (
    <div style={s.card}>
      <div style={s.imgwrap}>{/* imageUrl 있으면 <img>, 없으면 placeholderGradient */}</div>
      <div style={s.body}>
        <div style={s.name}>{product.name}</div>
        <div style={s.price}>{money(product.price)}</div>
        <div style={s.cuotas}>{cuotas(product.price)}</div>  {/* 항상 표시 — installments 토글 없음 */}
        <div style={s.acts}>
          <button onClick={() => add(product)}>Agregar</button>
          <button onClick={() => openTryOn(product)}>👗 Probar</button>
        </div>
      </div>
    </div>
  );
}
```
할인 배지·hover 2번째 사진·quickAdd·últimas unidades·색상 점 — **전부 부재**(코드에 없음, mockup 에만 있음). props 시그니처를 `{ product, options?: ProductCardOptions }`로 바꾸는 게 자연스럽다. `hoverSecondImage`는 mockup CSS 패턴(`.card .ph .img2{opacity:0} .sf.hover2 .card:hover .ph .img2{opacity:1}`)을 그대로 이식 가능 — `imageUrls[1]`을 두 번째 레이어로 절대위치 오버레이.

### shop-catalog.controller.ts 현재 쿼리 파라미터·페이지네이션·정렬

```typescript
@Get(':storeId/products')
async list(
  @Param('storeId', ParseIntPipe) storeId: number,
  @Query('page') page?: string, @Query('pageSize') pageSize?: string,
  @Query('q') q?: string, @Query('categoryId') categoryId?: string,
  @Query('globalCategoryId') globalCategoryId?: string, @Query('gender') gender?: string,
): Promise<ShopListResult> {
  const safePageSize = Math.min(50, Math.max(1, parseInt(pageSize ?? '24', 10) || 24)); // ★ 컨트롤러 레벨 상한 50
  // sort/showOutOfStock 파라미터 없음
```
**정렬은 서비스 SQL 에 `ORDER BY p.updated_at DESC`로 하드코딩**돼 있고 파라미터화 안 됨. R6 구현 시:
1. 컨트롤러에 `@Query('sort')`, `@Query('showOutOfStock')` 추가.
2. `ShopListParams`에 `sort`/`showOutOfStock` 추가, 화이트리스트(`newest|price_asc|price_desc`— `bestseller` 는 집계 필요라 별도 취급 권장)로 `ORDER BY` 컬럼을 매핑(문자열 SQL 삽입 절대 금지, `switch`로 안전한 `ORDER BY` 리터럴 선택).
3. `showOutOfStock=false` 일 때 `AND p.stock > 0` 조건 추가(SPEC 요구사항 "품절 표시" 토글은 프런트 표시(Agotado 배지)와 서버 필터링(숨김) 둘 다 해석 가능 — CONTEXT 스키마상 `catalog.showOutOfStock: boolean`은 "노출 여부"이므로 서버 WHERE 절이 맞다).
4. **주의**: 컨트롤러의 `pageSize` 상한(50)과 SPEC 의 `catalog.pageSize ≤ 48` clamp 는 **서로 다른 레이어**다 — 프런트가 `theme.catalog.pageSize`(admin 이 설정한 기본값, ≤48)를 쿼리스트링에 넣어 보내면 컨트롤러의 50 상한을 그대로 통과한다. 두 상한이 다른 이유가 명확치 않으므로 confuse 방지를 위해 컨트롤러 상한도 48로 낮추거나(파괴적 변경 아님 — 기존 최대였던 50보다 엄격해지는 방향), 최소한 왜 다른지 주석으로 남길 것.

### shop-public.module.ts — MinioModule import 지점

현재 `providers`/`imports`에 `MinioModule`이 없다. `MinioService`를 쓰려면:
```typescript
import { MinioModule } from 'src/common/minio/minio.module';
@Module({
  imports: [OnlineOrdersModule, PaymentsModule, AuthModule, PassportModule.register({ defaultStrategy: 'jwt' }), MinioModule],
  // StoreThemeAdminController 생성자에 MinioService 주입, StoreThemeAdminService 또는 신규 StoreThemeAssetService 에 위임
```
`MinioModule`의 실제 export 내용은 `src/common/minio/minio.module.ts` 확인 필요(파일은 존재 확인됨, 내용 미인용 — planner 는 실행 전 1회 읽을 것).

## MinIO 업로드 패턴 (기존 예시 인용)

`api-ventago/src/app/store/store.controller.ts`(매장 로고 업로드 — 가장 가까운 기존 패턴):
```typescript
constructor(
  private readonly storeService: StoreService,
  // ...
  private readonly minioService: MinioService,
) {}

@Post('new')
@UseInterceptors(FileInterceptor('logoFile'))
async create(@Body() body: CreateStoreDto, @UploadedFile() logoFile?: Express.Multer.File) {
  if (logoFile) {
    const fileName = `store_logo_${Date.now()}_${logoFile.originalname}`;
    const result = await this.minioService.uploadFile(logoFile, fileName);
    logoUrl = result.fileName;
  }
  // ...
}
```
`MinioService.uploadFile()`:
```typescript
async uploadFile(file: Express.Multer.File, customName?: string): Promise<{ fileName: string }> {
  const fileName = customName || file.originalname;
  await this.client.putObject(this.bucket, fileName, file.buffer, file.size, {
    'Content-Type': file.mimetype || 'application/octet-stream',
  });
  return { fileName };
}
```
`FileInterceptor`는 **memoryStorage**(기본값)를 쓴다 — `file.buffer`가 있어야 `uploadFile()`이 동작하므로 `storage: diskStorage(...)` 로 바꾸면 깨진다. 20MB 영상도 memoryStorage 로 버퍼링되므로(요청당 최대 20MB 는 Node 프로세스 메모리에 감당 가능한 크기 — 문제 없음), 다만 동시 업로드가 많을 경우 메모리 사용량이 늘어남을 감안(운영 규모상 무시 가능한 리스크).

**확장자/크기 검증 필수 패턴** — `legacy-import.controller.ts`에서 실제로 쓰는 `FileInterceptor` limits 옵션:
```typescript
@UseInterceptors(FileInterceptor('file', { limits: { fileSize: MAX_FILE_BYTES } }))
```
Phase 61 에 필요한 검증 로직(현재 `store.controller.ts`엔 확장자/MIME 검증이 **없다** — `store.controller.ts`를 그대로 베끼면 SPEC 의 "png/jpg/webp(+svg 로고만), 2MB" / "mp4/webm, 20MB" 제약이 빠진다. 직접 추가해야 함):
```typescript
const ALLOWED_IMAGE_EXT = ['png', 'jpg', 'jpeg', 'webp'];
const MAX_IMAGE_BYTES = 2 * 1024 * 1024;
const ALLOWED_VIDEO_EXT = ['mp4', 'webm'];
const MAX_VIDEO_BYTES = 20 * 1024 * 1024;

@Post(':storeId/theme/asset')
@UseGuards(StoreThemeEditGuard)
@UseInterceptors(FileInterceptor('file', { limits: { fileSize: MAX_VIDEO_BYTES } })) // 더 큰 쪽으로 상한, 세부검증은 서비스에서
async uploadAsset(
  @Param('storeId', ParseIntPipe) storeId: number,
  @UploadedFile() file: Express.Multer.File,
  @Query('kind') kind: 'logo' | 'favicon' | 'hero' | 'banner' | 'reelVideo' | 'reelPoster',
) {
  // 확장자(originalname) + mimetype 이중 체크(파일명 위조 방어) → 실패 시 BadRequestException(400)
  // UUID 파일명 재부여: `${randomUUID()}.${ext}`
  // logo 만 svg 허용, 나머지 png/jpg/webp
  // reelVideo 는 mp4/webm + 20MB, poster 는 이미지 규칙 재사용
}
```
**Nest 전역 body 제한**: `main.ts:97`에 `app.use(require('express').json({ limit: '50mb' }))` — 이건 JSON body 파서 한도이며 `multipart/form-data`(파일 업로드)엔 적용 안 됨(multer 가 별도로 처리). 20MB 영상 업로드는 이 50mb JSON 제한과 무관하고, `FileInterceptor`의 `limits.fileSize`가 실질 상한이다. **[ASSUMED]** 배포 서버(Jenkins/Docker) 앞단 nginx/pgbouncer 레벨의 `client_max_body_size` 설정은 이 저장소에서 확인 불가(서버 전용 설정 파일) — 운영에 20MB 업로드가 막히면 nginx 쪽 확인 필요(Open Questions 참조).

## rails / masonry 렌더 구현 패턴

### rails (Netflix식 가로 스크롤 선반)

순수 CSS 스크롤 스냅 + 좌우 화살표 버튼(스크롤 위치를 JS 로 제어) + `IntersectionObserver` 기반 행 단위 lazy load. 프로젝트에 기존 예시가 없으므로(`IntersectionObserver`/`scroll-snap`/`next/script` 사용례가 코드베이스에 전무 — grep 검증) 아래는 일반 패턴 [ASSUMED — 표준 웹 기법, 라이브러리 문서 아님]:

```tsx
// components/macro/RailsLayout.tsx (신규, 개념 스케치)
function Rail({ title, fetchItems }: { title: string; fetchItems: () => Promise<ShopProduct[]> }) {
  const ref = useRef<HTMLDivElement>(null);
  const [items, setItems] = useState<ShopProduct[] | null>(null); // null = 아직 미로드

  useEffect(() => {
    if (!ref.current || items !== null) return;
    const io = new IntersectionObserver((entries) => {
      if (entries[0].isIntersecting) {
        fetchItems().then(setItems);
        io.disconnect();
      }
    }, { rootMargin: '200px' }); // 화면 진입 200px 전 미리 로드
    io.observe(ref.current);
    return () => io.disconnect();
  }, [items, fetchItems]);

  return (
    <section ref={ref}>
      <h2>{title}</h2>
      <div style={{ display: 'flex', gap: 12, overflowX: 'auto', scrollSnapType: 'x mandatory', WebkitOverflowScrolling: 'touch' }}>
        {(items ?? []).map((p) => (
          <div key={p.id} style={{ flex: '0 0 200px', scrollSnapAlign: 'start' }}>
            <ProductCard product={p} />
          </div>
        ))}
      </div>
      {/* 좌우 화살표: ref.current.scrollBy({ left: ±width, behavior: 'smooth' }) */}
    </section>
  );
}
```
**함정:**
- 스크롤바 숨김은 `scrollbar-width:none` + `::-webkit-scrollbar{display:none}` — 표준 CSS, 브라우저 접두사 필요.
- 화살표 버튼의 활성/비활성(맨 끝 도달 시 숨김)은 `scroll` 이벤트 리스너로 `scrollLeft`/`scrollWidth`/`clientWidth` 비교 — 매 스크롤마다 리렌더 유발하지 않도록 `useRef` + 직접 DOM 스타일 조작 권장(React state 업데이트 남발 시 버벅임).
- 모바일 터치 스크롤은 네이티브로 잘 동작하나 데스크톱 마우스 휠은 세로 스크롤만 인식 — 화살표 버튼이 데스크톱에서 사실상 유일한 조작 수단(터치패드 가로 스크롤 제외). SPEC 요구사항 "스크롤 스냅+좌우 화살표"가 이미 이를 반영.
- 행 단위 lazy load 데이터 소스 3종(Novedades/Más vendidos/카테고리별) 각각 다른 API 호출 필요 — `bestseller` 는 신규 집계 쿼리(핵심 발견 3 참조), `newest`는 기존 `listProducts(sort=newest)` 재사용, 카테고리별은 `categoryId` 파라미터로 기존 엔드포인트 재사용 가능.

### masonry (CSS columns 기반)

```css
.masonry {
  columns: 2; /* 모바일 기본 */
  column-gap: 12px;
}
@media (min-width: 900px) {
  .masonry { columns: 4; } /* 데스크톱 */
}
.masonry > * {
  break-inside: avoid; /* 카드가 컬럼 경계에서 잘리지 않게 — 필수 */
  margin-bottom: 12px;
  display: inline-block; /* Safari break-inside 버그 회피용 관용구 */
  width: 100%;
}
```
**함정(SPEC 이 명시한 실무 함정과 일치):**
- **이미지 로드 전 열 높이 튐**: `columns` 레이아웃은 각 아이템의 실제 높이를 알아야 배치되므로, 이미지에 `aspect-ratio` CSS 를 인라인으로 미리 지정(예: 상품 세로 사진이면 `aspect-ratio: 3/4`)해 로드 전에도 카드 높이가 확정되게 해야 튐이 최소화된다. `next/Image`의 `width`/`height` prop 또는 CSS `aspect-ratio`로 명시.
- **순서가 열 단위로 흐르는 문제**: `columns` 는 아이템을 "위→아래 채우고 다음 열로" 배치한다(신문 조판 방식) — Grid 의 "행 우선" 순서와 다르다. 상품 목록에서 "최신순"으로 정렬해도 화면상 왼쪽 위→오른쪽 위가 아니라 왼쪽 열 전체→오른쪽 열 순서로 보인다. **이건 masonry 의 본질적 특성이며 버그가 아니다** — 에디터/기획 승인 시 이 시각적 순서 차이를 인지시켜야 함(목업엔 명시적 설명 없음 — Open Questions).
- **모바일 열 수 전환**: `columns: 2`→`columns: 4`처럼 breakpoint 에서 값만 바꾸면 브라우저가 재배치를 알아서 처리(reflow) — JS 개입 불필요, 이게 CSS `columns` 접근의 핵심 장점.
- **무한 스크롤과의 결합**: 새 페이지 아이템을 배열에 append 하면 `columns`가 자동으로 재분배한다(React 재렌더 시 DOM 순서만 바뀌면 브라우저가 자동 재조판) — 기존 카탈로그 페이지네이션(`listProducts` + `page`/`pageSize`) 재사용 가능, 신규 무한스크롤 로직 없이 "더 보기" 버튼 또는 `IntersectionObserver`로 다음 페이지 트리거만 추가하면 됨.

### 행 단위 lazy load — Next.js Pages Router 에서 IntersectionObserver

Pages Router 는 App Router 의 `loading.tsx`/서버 컴포넌트 스트리밍이 없으므로, "행 단위 lazy load"는 **클라이언트 사이드**에서 `IntersectionObserver`로 구현하는 것이 유일한 선택지다(SSR 은 첫 화면만 렌더, 이후 행은 뷰포트 진입 시 클라이언트 fetch). `useEffect` 내 `IntersectionObserver` 생성은 SSR-safe(브라우저 API 이므로 `useEffect`는 클라이언트에서만 실행 — Next 13 Pages Router 기본 동작, 별도 `dynamic(..., {ssr:false})` 불필요).

## reels 영상 렌더 패턴

SPEC 요구사항 그대로:
```tsx
<video
  muted
  playsInline
  preload="none"
  poster={minioImageUrl(item.posterFile)}
  onClick={(e) => {
    const v = e.currentTarget;
    // 다른 재생 중인 video 전부 정지(단일 재생 보장)
    document.querySelectorAll('video').forEach((other) => { if (other !== v) other.pause(); });
    v.paused ? v.play() : v.pause();
  }}
>
  <source src={minioVideoUrl(item.videoFile)} type="video/mp4" />
</video>
```
**핵심 속성 근거:**
- `preload="none"`: 브라우저가 메타데이터조차 미리 받지 않음 — `poster` 이미지만 초기 렌더, 영상 바이트 요청 0 (SPEC acceptance criteria 그대로).
- `muted` + `playsInline`: iOS Safari 는 `muted` 없이 `play()`를 프로그래매틱하게(사용자 제스처 없이) 호출하면 차단한다. Phase 61 은 "탭 시 재생"(사용자 제스처 이벤트 핸들러 내 `play()` 호출)이므로 엄밀히는 muted 없이도 제스처-내 호출은 허용되지만, `autoplay` 정책과 무관하게 iOS 인라인 재생(전체화면 강제 전환 방지)엔 `playsInline`이 필수, `muted`는 SPEC 이 명시적으로 요구하므로 그대로 유지.
- **여러 영상 동시 재생 방지**: 위 코드처럼 클릭 핸들러에서 다른 모든 `<video>`를 `pause()`하는 방식이 가장 단순. React ref 배열로 관리하면 `document.querySelectorAll` 없이도 가능(더 React-idiomatic이지만 기능 동일).
- `<video>`의 `controls` 속성은 SPEC 에 언급 없음 — 탭으로 재생/일시정지만 토글하는 커스텀 UX 라면 `controls` 생략하고 오버레이 아이콘(▶/⏸)을 직접 그리는 편이 mockup 톤(가격/CTA 오버레이)과 일관.

## SEO/pixel/팝업

### getServerSideProps + next/head — 매장별 title/description

현재 `index.tsx`의 `<Head>`는 하드코딩("CoolShop — Tienda online"):
```tsx
<Head>
  <title>CoolShop — Tienda online</title>
  <meta name="description" content="CoolShop — indumentaria online con probador virtual con IA." />
</Head>
```
확장: `theme.content?.marketing?.seoTitle` / `seoDescription`이 있으면 override, 없으면 현재 기본값 유지(하위호환). `getServerSideProps`가 이미 `theme`을 SSR 로 가져오므로 **추가 API 호출 불필요** — `theme` prop 에서 바로 읽으면 된다.

### 조건부 3rd-party 스크립트 삽입 — next/script strategy

프로젝트에 `next/script` 사용례가 전무(grep 결과 0건) — 신규 패턴 도입. Next 13.3.2 는 `next/script` 완전 지원:
```tsx
import Script from 'next/script';
{theme.content?.marketing?.pixelId ? (
  <Script id="meta-pixel" strategy="afterInteractive">
    {`!function(f,b,e,v,n,t,s){...}(window,document,'script','https://connect.facebook.net/en_US/fbevents.js');
      fbq('init', '${theme.content.marketing.pixelId}'); fbq('track', 'PageView');`}
  </Script>
) : null}
```
`strategy="afterInteractive"`(기본값)가 픽셀류엔 적절 — 페이지 인터랙티브 이후 로드돼 초기 렌더 성능에 영향 최소. `pixelId`가 XSS 벡터가 되지 않도록 **템플릿 리터럴에 직접 삽입하는 값은 반드시 `sanitizeContent()`에서 영숫자/하이픈만 허용하는 화이트리스트 정규식으로 걸러야 한다**(href 규칙과 별개로 pixelId 전용 검증 필요 — SPEC 의 href whitelist 규칙은 이 필드에 적용 안 됨, 별도 clamp 규칙 설계 필요).

### 세션 1회 팝업 판정

```tsx
useEffect(() => {
  if (!theme.content?.marketing?.popup?.enabled) return;
  const key = `popup_shown_${storeId}`;
  if (sessionStorage.getItem(key)) return;
  setShowPopup(true);
  sessionStorage.setItem(key, '1');
}, [storeId, theme]);
```
`sessionStorage`는 탭/세션 종료 시 초기화 — SPEC acceptance("같은 세션 재방문엔 안 뜸")과 정확히 일치. `localStorage` 대신 `sessionStorage`를 쓰는 이유가 SPEC 요구사항 자체에 내재(세션당 1회, 영구 아님). SSR 단계에선 `sessionStorage`가 없으므로 반드시 `useEffect`(클라이언트 전용) 안에서 처리.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| 가로 스크롤 캐러셀 | 커스텀 드래그/터치 스와이프 JS | 네이티브 `overflow-x:auto` + `scroll-snap-type` + `scrollBy()` | 브라우저 네이티브 스크롤 관성/터치가 이미 완성도 높음, 라이브러리 금지 조건과도 일치 |
| masonry 배치 | JS 로 각 카드 높이 측정 후 절대위치 배치 | CSS `columns` | SPEC 이 명시적으로 금지, 브라우저 네이티브 reflow 가 breakpoint 전환도 자동 처리 |
| 영상 동시재생 방지 | 커스텀 전역 상태(Redux/Context)로 "현재 재생 중 id" 관리 | DOM 순회(`querySelectorAll('video')`) + `pause()` | 섹션 하나에 국한된 로컬 문제 — 전역 상태 오버킬 |
| href 검증 | 자체 정규식으로 매번 재작성 | `sanitizeTokens()`/`sanitizeContent()`의 단일 헬퍼 함수 재사용 | XSS 방어는 단일 지점에서만 해야 누락을 막음 — SPEC 의 "미경유 raw 토큰 저장 금지" 원칙과 직결 |
| UUID 파일명 | `Date.now()+originalname`(기존 `store.controller.ts` 패턴) | Node `crypto.randomUUID()` | SPEC 이 "UUID 파일명"을 명시 — 기존 로고 업로드 패턴(`store_logo_${Date.now()}_${originalname}`)은 grandfather 코드일 뿐 새 엔드포인트의 기준이 아님. 원본 파일명 노출도 방지 |

**Key insight:** 이 Phase 의 위험은 "새 기술 도입"이 아니라 "기존 가드레일 우회 경로 생성"이다. `sanitizeTokens()`/`buildThemeResponse()`가 SSOT 라는 원칙이 흔들리면(예: 프런트에서 직접 raw JSONB 를 조립해 보내고 백엔드가 그대로 믿는다면) XSS·JSONB 오염이 재현된다.

## Common Pitfalls

### Pitfall 1: ESLint 강제 범위가 워크스페이스마다 다르다
**무엇이 잘못되나:** SPEC/CLAUDE.md 가 "`newline-before-return`/`lines-around-comment`/`no-unused-vars` 준수"를 프로젝트 전역 규칙처럼 명시하지만, 실제로 이 3개 규칙을 ESLint 설정에 **명시적으로 error 등록**한 곳은 `ventago-app/.eslintrc.json` 뿐이다 [VERIFIED: 각 워크스페이스 config 파일 직접 확인].
- `api-ventago/eslint.config.mjs`: `eslint.configs.recommended` + `tseslint.configs.recommendedTypeChecked` + prettier — 위 3개 규칙 없음(`@typescript-eslint`의 기본 `no-unused-vars`는 typed lint 로 켜짐).
- `tienda-app/.eslintrc.json`: `{"extends": "next/core-web-vitals"}` 뿐 — 위 3개 규칙 전무.
**왜 발생하나:** 프로젝트가 점진적으로 여러 워크스페이스를 추가하며 ventago-app 의 스타일 관례가 문서(CLAUDE.md)엔 "전역 규약"처럼 적혀 있지만 다른 워크스페이스 설정엔 이식되지 않았다.
**회피:** 이 Phase 의 변경 파일(api-ventago, tienda-app)은 각 워크스페이스의 **실제 lint 명령**(`npx eslint`)이 기준이다 — 통과는 되지만, `store-theme.constants.ts` 등 기존 파일이 이미 관례적으로 `return`문 앞 빈 줄을 지키고 있으므로(코드 확인됨) 신규 코드도 스타일 일관성을 위해 관례를 따르되, **lint 실패로 게이트가 걸리는 것은 api-ventago/tienda-app 에선 이 3개 규칙 위반이 아니라 typescript-eslint/next 기본 규칙 위반**임을 착오하지 말 것.
**경고 신호:** 계획에 "newline-before-return 오류 0"을 완료 기준으로 넣었는데 실제 `npx eslint` 실행 시 해당 규칙이 아예 로드되지 않아 검증 자체가 무의미해지는 상황.

### Pitfall 2: `.planning/intel/db-schema-tables.md` 가 stale 하다
**무엇이 잘못되나:** CLAUDE.md 는 "SQL 작성 전 반드시 이 파일 참조, 추측 금지"라고 명시하지만, 이 문서엔 `products.slug`/`long_description`/`gender`/`material`/`is_published_shop`/`seo_title`/`seo_description` 컬럼이 아예 없다 — 그러나 이 컬럼들은 `shop-mvp-product-metadata.sql` 마이그레이션으로 실제 DB 에 존재하고 `shop-catalog.service.ts`가 매일 이 컬럼들을 SELECT 한다 [VERIFIED: 마이그레이션 파일 + 서비스 코드 둘 다 확인].
**왜 발생하나:** `db-schema.regen.sh`가 최근 재실행되지 않았거나, shop-mvp 관련 마이그레이션이 재생성 시점 이후 적용됨.
**회피:** Wave B 에서 `products` 컬럼(특히 `price_orig`/`stock` — R5 에 필요)을 참조할 땐 이 문서만 믿지 말고 `grep`으로 관련 마이그레이션 파일(`shop-mvp-product-metadata.sql` 등)과 `shop-catalog.service.ts`의 실제 쿼리를 함께 확인. 가능하면 착수 전 `./.planning/intel/db-schema.regen.sh` 재실행을 권고(로컬 PG18 대상, 사용자 Mac 에서 실행 필요 — 이 세션 환경에선 로컬 DB 접근 불가).
**경고 신호:** "이 컬럼 없음"이라고 판단해 새 마이그레이션을 만들려는 순간 — 실제로는 이미 존재할 가능성 높음, 먼저 실제 쿼리 파일에서 컬럼명 검색.

### Pitfall 3: XSS 방어 3종 세트를 각각 다른 지점에 넣어야 한다
**무엇이 잘못되나:** href whitelist(`http(s)://` 또는 `/`), 텍스트 렌더 이스케이프, pixelId 화이트리스트가 **서로 다른 필드/다른 코드 지점**에 필요하다 — 하나의 정규식으로 퉁칠 수 없다.
**왜 발생하나:** SPEC 의 "href는 http(s)/상대경로만" 규칙을 프런트가 아니라 백엔드 `sanitizeContent()`에서 강제해야 하는데, React 는 기본적으로 텍스트를 자동 이스케이프하므로(JSX `{text}`는 안전) 텍스트 필드 자체엔 별도 이스케이프 코드가 필요 없다 — **단, `dangerouslySetInnerHTML`을 어디서도 쓰지 않는 것 자체가 방어**이므로 "구현하지 않기"가 회피책이다.
**회피:** (1) href 는 백엔드 저장 시점에 정규식 검증 후 실패 시 `null`로 강등. (2) 텍스트는 JSX 렌더만 쓰고 `dangerouslySetInnerHTML` 절대 사용 안 함(현재 코드베이스에 이미 이 패턴이 없음 — grep 으로 사전/사후 확인 권장). (3) `pixelId` 는 스크립트 태그 내부 문자열 삽입이므로 href/텍스트와 별개로 영숫자+하이픈 화이트리스트 정규식 전용 처리.
**경고 신호:** 새 필드(예: `announce.href`)를 추가하면서 기존 href 검증 함수를 재사용하지 않고 그 필드만 검증을 빼먹는 경우.

### Pitfall 4: masonry 의 열 우선(column-major) 순서가 "버그처럼 보임"
**무엇이 잘못되나:** `defaultSort='newest'`로 정렬한 상품 배열을 CSS `columns`에 넣으면 화면상 좌상단부터 좌하단까지 채운 뒤 다음 열로 넘어간다 — "최신순"을 기대한 사용자(매장 admin)가 왼쪽 위→오른쪽 위 순서를 기대하면 혼란.
**회피:** 계획 단계에서 이 특성을 명시적으로 인지하고, 필요하면 에디터 미리보기에 "masonry 는 열 우선 정렬입니다" 같은 힌트를 hint 텍스트로 노출(mockup 의 `.hint` 클래스 패턴 재사용).
**경고 신호:** QA 중 "정렬이 이상하다"는 리포트가 오면 로직 버그가 아니라 CSS columns 의 본질적 특성임을 먼저 확인.

### Pitfall 5: PostgreSQL pool — 이미 3개의 서로 다른 연결 경로가 존재
**무엇이 잘못되나:** "새 Pool 금지" 규칙을 지키려다 오히려 기존 3개 경로(①Sequelize 메인 연결 via `@InjectConnection`, ②`ShopReadonlyDbService`의 전용 `pg.Pool`(max 15), ③`MemoryCacheService`는 DB 아님이지만 캐시 레이어) 를 혼동하기 쉽다.
**회피:** 읽기(공개 API, bestseller 집계 쿼리 포함)는 **반드시** `ShopReadonlyDbService.query()`를 통해서만, 쓰기(draft/publish)는 **반드시** `StoreThemeAdminService`의 `@InjectConnection() Sequelize`를 통해서만. 새 `StoreThemeAssetService`(업로드 전용, 논의 필요)를 만들더라도 DB 접근이 필요하면 이 둘 중 하나를 주입받아야지 `new Pool()`을 호출하면 안 된다.
**경고 신호:** `grep -rn "new Pool(\|new Client(" <변경파일>` 실행 시 1건이라도 나오면 즉시 위반(SPEC 완료기준 R8 acceptance criteria 그대로).

## Code Examples

### sanitizeContent() 스켈레톤 (제안 — 명명/분해는 discretion)
```typescript
// Source: 기존 sanitizeTokens()/clamp() 패턴 확장 (store-theme.constants.ts 참고)
const HREF_RE = /^(https?:\/\/|\/)/;

function sanitizeHref(v: unknown): string | null {
  return typeof v === 'string' && HREF_RE.test(v) ? v.slice(0, 500) : null;
}

function clampText(v: unknown, maxLen = 200): string {
  return typeof v === 'string' ? v.slice(0, maxLen) : '';
}

export interface StoreThemeContent {
  brand: { displayName: string; logoFile: string | null; faviconFile: string | null };
  announce: { enabled: boolean; text: string; href: string | null };
  sections: SectionConfig[]; // 최대 8개
  contact: { whatsapp: string | null; instagram: string | null; facebook: string | null; footerText: string | null };
  // Wave B/C 키는 후속 확장
}

export function sanitizeContent(raw: Record<string, unknown> | null | undefined): StoreThemeContent {
  const r = raw ?? {};

  return {
    brand: {
      displayName: clampText((r.brand as any)?.displayName),
      logoFile: typeof (r.brand as any)?.logoFile === 'string' ? (r.brand as any).logoFile : null,
      faviconFile: typeof (r.brand as any)?.faviconFile === 'string' ? (r.brand as any).faviconFile : null,
    },
    announce: {
      enabled: (r.announce as any)?.enabled === true,
      text: clampText((r.announce as any)?.text),
      href: sanitizeHref((r.announce as any)?.href),
    },
    sections: Array.isArray(r.sections) ? (r.sections as unknown[]).slice(0, 8).map(sanitizeSection) : [],
    contact: { /* ... */ } as StoreThemeContent['contact'],
  };
}
```

### CHECK 제약 교체 마이그레이션 (R9)
```sql
-- Source: 기존 2026-07-22-store-themes.sql 패턴 + PG18 표준 ALTER CONSTRAINT 절차
BEGIN;

ALTER TABLE store_themes DROP CONSTRAINT chk_store_theme_macro;

ALTER TABLE store_themes ADD CONSTRAINT chk_store_theme_macro
  CHECK (macrostructure IN ('marquee', 'bento', 'doc', 'rails', 'masonry'));

COMMIT;
```
`store_themes`는 매장당 1행(PK `store_id`)이라 테이블이 작다(수십~수백 행 규모) — `ADD CONSTRAINT ... CHECK`의 즉시 검증(풀 스캔 + 짧은 ACCESS EXCLUSIVE 락)이 성능 문제가 되지 않는다. 대형 테이블에 쓰는 `NOT VALID` + `VALIDATE CONSTRAINT` 2단계 분리는 이 케이스에 불필요.

## State of the Art

이 Phase 는 "구식 → 신식 전환"이 아니라 순수 확장이라 표에 넣을 만한 항목이 적다. 유일하게 관련 있는 것:

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| macrostructure 3종(marquee/bento/doc) — 그리드 밀도만 다름 | 5종 — rails/masonry 는 그리드 밀도가 아니라 렌더 구조 자체가 다름 | 2026-07-23(본 Phase) | `index.tsx`의 `gridStyle` 삼항 분기 패턴으로는 표현 불가 — 최상위 렌더 분기 필요(Architecture Patterns 참조) |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | 배포 환경(nginx/pgbouncer 등 서버 레벨 프록시)의 `client_max_body_size`가 20MB 영상 업로드를 막지 않는다 | MinIO 업로드 패턴 | 운영에서 21MB 미만 파일도 502/413 으로 거부될 수 있음 — Jenkins 배포 후 실제 업로드 스모크 테스트 필요 |
| A2 | `variantDots`(색상 점) 구현에 필요한 variant 색상 목록 데이터가 공개 API 에 없다는 관찰이 맞다면, 이 옵션은 Phase 61 범위 내 정확 구현이 어렵다 | 핵심 발견 2 | 계획 단계에서 범위를 "toggle UI만 있고 실제 데이터 없이 no-op" 또는 "products.parent_id 기반 신규 집계 쿼리 추가"로 명확히 결정해야 함 — 미결정 시 실행 중 막힘 |
| A3 | `iOS Safari`에서 "탭 이벤트 핸들러 내 `video.play()` 호출"은 `muted` 여부와 무관하게 사용자 제스처로 인정되어 차단되지 않는다 | reels 영상 렌더 패턴 | 만약 iOS 가 이 케이스도 차단한다면 재생 자체가 실패 — 실기기 QA 필수 |
| A4 | `catalog.pageSize ≤ 48`(SPEC) 과 컨트롤러의 기존 상한 50 이 다른 이유는 설계 실수이지 의도적 차이가 아니다 | shop-catalog.controller.ts 쿼리 구조 | 만약 50이 의도적(레거시 프런트 호환 등)이라면 임의로 48로 낮추면 안 됨 — discuss-phase 에서 재확인 권장 |

**빈 항목 없음 — 위 4건 모두 실행 전 확인 또는 계획 시 명시적 결정 필요.**

## Open Questions

1. **`variantDots`(색상 점 표시)의 데이터 소스**
   - What we know: `ProductCard.tsx`는 단일 상품(단일 색상/사이즈 조합으로 보이는 row)만 다룬다. `products.parent_id`/`is_parent`로 부모-변형 관계가 스키마상 존재.
   - What's unclear: 공개 카탈로그 목록 쿼리가 변형을 그룹화해서 "이 상품엔 색상 N개 변형이 있다"는 정보를 만들지 않는다. 이 집계를 Wave B 안에서 새로 만들 것인지, 아니면 이번엔 스위치만 두고 데이터 없으면 렌더 안 함(no-op)으로 둘 것인지 미정.
   - Recommendation: 플래너가 discuss-phase 또는 태스크 설계 시 "정확 구현" vs "플레이스홀더"를 명시적으로 택하게 한다. Claude's Discretion 범위이므로 리서치 단계에서 임의 결정하지 않음.

2. **`bestseller` 캐러셀/rails 소스의 집계 쿼리 — 캐시 전략**
   - What we know: `sale_items`(product_id, quantity) + `sales`(store_id, sale_date, status)를 조인해 기간별(예: 최근 90일) 판매량 합계로 정렬 가능. `ShopReadonlyDbService` 경유, 파라미터 바인딩.
   - What's unclear: 캐시 TTL(카탈로그 60초 vs 테마 5분 중 어느 쪽 컨벤션을 따를지), 판매 취소(`nullified_sale_id`) 반영 여부, 집계 윈도우 길이(SPEC 미명시).
   - Recommendation: 기존 `LIST_TTL_MS = 60_000`(카탈로그 컨벤션) 재사용 권장 — bestseller 도 "카탈로그성 데이터"로 분류. 윈도우 길이는 discretion.

3. **운영 nginx/pgbouncer 프록시의 업로드 크기 상한**
   - What we know: 이 저장소엔 nginx 설정 파일이 없음(서버 전용, repo 밖).
   - What's unclear: 20MB 영상 업로드가 실제 운영 경로(pgbouncer 는 DB 프록시라 무관, nginx reverse proxy 가 관건)를 통과하는지.
   - Recommendation: A2(마이그레이션) 배포 시점과 별개로, Wave B reels 업로드 구현 직후 운영 환경에서 실제 20MB 근접 파일 업로드 스모크 테스트를 계획에 포함.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Node.js | api-ventago 빌드/실행 | ✓ [ASSUMED — Docker 20-alpine 명시, CLAUDE.md] | 20 (운영 Docker) | — |
| PostgreSQL 18 | 로컬 5432 + 운영 5434 | ✓ [VERIFIED: CLAUDE.md DB 마이그레이션 규칙] | 18 | — |
| MinIO | 이미지/영상 저장 | ✓ [VERIFIED: 기존 `MinioService` 운영 중] | — | — |
| npm workspaces | 빌드 | ✓ [VERIFIED: 루트 package.json workspaces] | — | — |

이 Phase 는 신규 외부 서비스/CLI 의존성이 없다(모두 이미 운영 중인 인프라 재사용) — 나머지 항목 생략.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Jest ([VERIFIED: `api-ventago/package.json` `"test": "jest"`]) — api-ventago 만. tienda-app 은 테스트 프레임워크 미설정(package.json 에 jest/vitest 없음, `*.test.*`/`*.spec.*` 파일 0건) |
| Config file | api-ventago: `package.json` 내 jest 설정(별도 jest.config 파일 확인 필요) / tienda-app: 없음 |
| Quick run command | `cd api-ventago && npx jest src/app/shop-public --silent` (해당 폴더 스펙 파일 0건 — Wave 0 갭) |
| Full suite command | `cd api-ventago && npm test` |

**tienda-app 은 자동화 테스트 인프라가 전무하다** — `store-theme.service.ts`/`store-theme.constants.ts` 조차 `*.spec.ts` 파일이 없다(grep 확인, 0건). 이 Phase 의 검증은 대부분 **관찰 가능한 신호(로그/HTTP 응답/DB 쿼리/렌더 결과)** 로 대체해야 하며, 자동 유닛 테스트 커버리지는 api-ventago 신규 `sanitizeContent()` 류 순수함수에 한해 신규 작성이 현실적이다.

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command / 관찰 신호 | File Exists? |
|--------|----------|-----------|-------------------------------|-------------|
| R1 | 확장 키 없는 published_tokens → buildThemeResponse 현행과 동일 응답 | unit | `npx jest store-theme.constants` (신규 스펙 필요) | ❌ Wave 0 |
| R1 | sections 9개/텍스트 300자/`javascript:` href → 8개/200자/null 로 clamp | unit | 위와 동일 파일 내 케이스 추가 | ❌ Wave 0 |
| R2 | 2MB 이하 png 업로드 → `{fileName}` 반환, 3MB/`.exe` → 400 | manual/smoke | `curl -F file=@logo.png ... /shop/:id/theme/asset` (StoreThemeEditGuard 토큰 필요 — edit-link 선발급) | ❌ Wave 0(smoke 스크립트 없음) |
| R3/R4 | draft 저장→미리보기→publish 왕복 후 섹션 순서/토글 반영 | manual browser UAT | `diseno.tsx` 조작 후 공개 URL 재조회, HTML 소스 diff | N/A(브라우저 UAT — 이 프로젝트 관례) |
| R5 | `productCard.discountBadge=false` publish → 목록에서 배지 미노출 | manual/smoke | `curl /public/shop/:id/products` 응답에 `priceOrig` 필드 존재 확인 후 브라우저 확인 | ❌ Wave 0(DTO 필드 자체가 신규) |
| R6 | `pageSize=999` 저장해도 48 clamp | unit | sanitizeContent 스펙 케이스 | ❌ Wave 0 |
| R6 | `catalog.pageSize=12`, `sort=price_asc`, `filters.color=false` → 공개 목록 반영 | manual/smoke | `curl "/public/shop/:id/products?pageSize=12&sort=price_asc"` 응답 개수/정렬 확인 | ❌ Wave 0(sort 파라미터 자체가 신규) |
| R7 | `marketing.popup.enabled=true` → 첫 방문 팝업 1회, 재방문 안 뜸 | manual browser UAT | 브라우저 sessionStorage 확인 | N/A |
| R7 | `seoTitle` 설정 → `<title>` 반영, `pixelId=null` → 스크립트 태그 없음 | smoke | `curl` 후 HTML grep `<title>`/`<script id="meta-pixel"` | ❌ Wave 0 |
| R8 | 신규 Pool/Client 0, ESLint 오류 0 | automated grep | `grep -rn "new Pool(\|new Client(" <변경파일>` (0건 기대) + `npx eslint <변경파일>` | ✓(grep 즉시 실행 가능, 파일 불필요) |
| R9 | rails/masonry publish → 해당 뼈대 렌더, 기존 3종 회귀 없음 | manual browser UAT + smoke | `curl /public/shop/:id/theme` 응답 `macrostructure` 필드 확인 + 브라우저 시각 확인 | N/A |
| R9 | 로컬 5432 / 운영 5434 CHECK 제약 정의 대조 | manual DB 조회 | `\d store_themes` 양쪽 실행 비교(`postgres-ventago` MCP 로컬 / `mcp-ssh` 운영) | N/A(DB 조회, 파일 불필요) |
| R10 | reels `preload="none"`, 21MB/`.mov` 400, poster 없으면 drop | unit(sanitize) + smoke(HTML) | sanitizeContent 케이스 + `curl` HTML grep `preload="none"` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** 신규 `sanitizeContent()`/`sanitizeMacrostructure()` 관련 순수함수는 `npx jest <파일>` 로 즉시 검증(있는 경우). 그 외는 `curl` 스모크 + grep 로 대체(자동 테스트 없음).
- **Per wave merge:** `npx eslint <변경 워크스페이스>` + `grep -rn "new Pool(\|new Client("` 전체 diff.
- **Phase gate:** 브라우저 UAT(기존 매장 무회귀 확인 + rails/masonry/reels 시각 확인) — 이 프로젝트의 관례(대부분 phase 가 "브라우저 UAT 대기" 상태로 종료)를 따름. device VM 타입체크 OOM 이력 때문에 최종 타입체크 게이트는 Jenkins 빌드.

### Wave 0 Gaps
- [ ] `api-ventago/src/app/shop-public/store-theme.constants.spec.ts` — `sanitizeContent()`/확장된 `sanitizeMacrostructure()` 유닛 테스트 (신규 파일, 현재 이 모듈 전체에 스펙 파일 0개)
- [ ] `api-ventago/src/app/shop-public/shop-catalog.service.spec.ts` — sort/showOutOfStock 쿼리 파라미터 매핑 테스트 (선택 — 기존 서비스에도 스펙 없음, 신규 로직만이라도 권장)
- [ ] tienda-app 스모크 스크립트(`curl` 기반, `scripts/` 또는 임시 쉘) — 자동 테스트 프레임워크가 없으므로 최소한의 재현 가능한 검증 스크립트를 Wave 0 에 만들어두면 이후 waves 의 "관찰 가능한 신호" 확보가 쉬워짐(선택, 강제 아님)
- [ ] Framework install: 불필요 — Jest 는 api-ventago 에 이미 있음. tienda-app 에 신규 테스트 프레임워크(Jest/Vitest) 도입은 이 Phase 범위 밖(SPEC 이 요구하지 않음, 임의 확장 금지 원칙과도 상충)

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | 부분(에디터만) | 기존 `StoreThemeEditGuard`(HMAC 매직링크) + `AuthGuard('jwt')`(edit-link 발급/토글) — 신규 인증 메커니즘 도입 없음 |
| V3 Session Management | 아니오 | 공개몰은 세션 없음(팝업 판정은 `sessionStorage`, 인증 세션 아님). 편집 토큰은 15분 TTL HMAC — JWT 세션과 별개 체계, 기존 그대로 |
| V4 Access Control | 예 | `StoreThemeEditGuard`가 토큰의 storeId 와 라우트 storeId 일치를 강제(cross-store 편집 차단) — 신규 asset 업로드 엔드포인트도 동일 가드 재사용 필수 |
| V5 Input Validation | 예(핵심) | `sanitizeTokens()`/`sanitizeContent()` — whitelist+clamp. href 정규식, 텍스트 길이 clamp, 배열 개수 clamp, 파일 확장자/MIME/크기 검증 |
| V6 Cryptography | 아니오 신규 | 기존 HMAC-SHA256 편집 토큰(`store-theme-token.util.ts`) 재사용, 신규 암호화 로직 없음 |

### Known Threat Patterns for 이 stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Stored XSS via `announce.href`/`duoBanners[].href`/`trust.policyLinks[]` | Tampering/Elevation | href whitelist(`http(s)://` 또는 `/` 시작) — 그 외 null 강등. `javascript:`/`data:` 스킴 차단 |
| Stored XSS via 텍스트 필드(제목/설명 등) | Tampering | React JSX 자동 이스케이프에 의존(안전) — `dangerouslySetInnerHTML` 사용 금지를 코드 리뷰로 강제 |
| JSONB 오염(알 수 없는 키/타입 불일치로 렌더 크래시) | Tampering/DoS | 알 수 없는 키 drop, 타입 불일치는 default 로 강등(기존 `clamp()` 철학과 동일) |
| 업로드 확장자 위조(파일명은 `.png`인데 실제 실행파일) | Tampering | 확장자 **+** MIME type 이중 체크(다만 MIME 도 클라이언트가 보낸 값이라 완전 신뢰 불가 — 매직바이트 검증까지는 SPEC 범위 밖으로 보이나, 최소 이중 체크는 권장) |
| cross-store 편집(다른 매장 storeId 로 asset 업로드/draft 저장) | Elevation/Spoofing | `StoreThemeEditGuard`의 storeId 일치 검증이 이미 모든 편집 라우트에 적용 — 신규 `/theme/asset`도 동일 가드 필수 적용(빠뜨리면 즉시 취약점) |
| MinIO 용량 폭발(미검증 대용량 업로드 반복) | DoS | `FileInterceptor` `limits.fileSize` 서버 강제(클라이언트 검증만으론 우회 가능) — SPEC 이 이미 이를 인지하고 20MB/2MB 명시 |

## Sources

### Primary (HIGH confidence — 실제 코드/설정 파일 직접 읽음)
- `api-ventago/src/app/shop-public/store-theme.constants.ts` — SSOT 전체
- `api-ventago/src/app/shop-public/store-theme.service.ts` — 읽기 경로
- `api-ventago/src/app/shop-public/store-theme-admin.service.ts` — 쓰기 경로(draft/publish)
- `api-ventago/src/app/shop-public/store-theme-admin.controller.ts` — admin 엔드포인트
- `api-ventago/src/app/shop-public/store-theme-edit.guard.ts` — 편집 가드
- `api-ventago/src/app/shop-public/store-theme-token.util.ts` — HMAC 토큰
- `api-ventago/src/app/shop-public/shop-catalog.controller.ts` / `shop-catalog.service.ts` — 카탈로그 쿼리
- `api-ventago/src/app/shop-public/shop-public.module.ts` — 모듈 imports
- `api-ventago/src/app/shop-public/shop-readonly-db.service.ts` — 읽기 전용 Pool
- `api-ventago/src/common/minio/minio.service.ts` — MinIO 클라이언트
- `api-ventago/src/app/store/store.controller.ts` — 기존 로고 업로드 패턴
- `api-ventago/src/app/legacy-import/legacy-import.controller.ts` — FileInterceptor limits 패턴
- `api-ventago/src/main.ts` — 전역 body 파서 제한
- `api-ventago/eslint.config.mjs`, `tienda-app/.eslintrc.json`, `ventago-app/.eslintrc.json` — ESLint 강제 범위 대조
- `api-ventago/migrations/2026-07-22-store-themes.sql` — 현행 DDL
- `api-ventago/migrations/shop-mvp-product-metadata.sql` — products 확장 컬럼(문서 stale 확인용)
- `tienda-app/src/pages/[storeId]/panel/diseno.tsx` — 에디터
- `tienda-app/src/pages/[storeId]/index.tsx` — 스토어프런트
- `tienda-app/src/lib/theme-preset.ts` — 프런트 미러
- `tienda-app/src/components/ProductCard.tsx` — 상품 카드
- `tienda-app/src/components/Header.tsx` — 스타일 체계 참고
- `tienda-app/src/services/shop-api.ts`, `tienda-app/src/types/shop.ts` — API 계약
- `tienda-app/package.json`, `api-ventago/package.json` — 의존성 버전
- `.planning/intel/db-schema-tables.md` — products/sales/sale_items 컬럼(stale 부분 있음, 교차검증 완료)
- `tienda-online-editor-mockup.html`, `tienda-online-templates-mockup.html` — 승인 목업
- `.planning/phases/61-tienda-online-editor/61-CONTEXT.md`, `61-SPEC.md`, `.gsd/spec-phase61-tienda-online-editor.md`

### Secondary (MEDIUM confidence)
- 없음 — 외부 웹 검색 없이 전량 리포지토리 내부 코드 검증으로 충분했음(신규 라이브러리 도입이 없는 순수 확장 Phase 특성)

### Tertiary (LOW confidence)
- iOS Safari 인라인 재생/제스처 정책 세부 규칙(A3) — 훈련 지식 기반, 이 세션에서 웹 검색으로 재검증하지 않음

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — 신규 패키지 없음, 기존 package.json 버전 직접 확인
- Architecture: HIGH — 모든 핵심 흐름(sanitize/buildThemeResponse/saveDraft/publish, 카탈로그 쿼리, ProductCard, 에디터 state)을 실제 파일 읽기로 검증, 코드 인용 포함
- Pitfalls: HIGH(코드베이스 내부 사실) / MEDIUM(iOS Safari 재생 정책 등 외부 플랫폼 동작) — 각 항목에 confidence 표기

**Research date:** 2026-07-23
**Valid until:** 이 Phase 착수 전까지 유효(코드베이스 스냅샷 기반, 외부 라이브러리 버전 의존 없음 — 만료 개념이 약함). 단, 이 리서치 이후 `store-theme.constants.ts`/`store-theme-admin.service.ts`가 다른 작업으로 먼저 변경되면 재검증 필요.
