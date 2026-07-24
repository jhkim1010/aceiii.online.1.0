# SPEC: Phase 61 — Tienda Online 에디터 확장 (Tiendanube급 admin 커스터마이징)
생성일: 2026-07-23

## 목표
hallmark 디자인 토큰만 제공하는 현행 Tienda Online 에디터를, 매장 admin이 **콘텐츠·섹션 구성**(로고, 공지바, 홈 섹션, 상품 카드, 푸터/신뢰 요소, 마케팅)까지 직접 결정하는 Tiendanube급 커스터마이저로 확장한다.

## 배경 및 컨텍스트
- 목업(승인 기준): `tienda-online-editor-mockup.html` (레포 루트)
- 현행 admin 결정 항목: 활성화 토글 + slug + hallmark 12프리셋 토큰(hue/sat/paperBand/fontPair/weight/macro/radius)뿐
- 관련 파일:
  - 백엔드 SSOT: `api-ventago/src/app/shop-public/store-theme.constants.ts` (`sanitizeTokens`/`clamp` 가드레일)
  - 백엔드 서비스: `store-theme.service.ts`(읽기, ShopReadonlyDbService), `store-theme-admin.service.ts`(쓰기), `store-theme-admin.controller.ts`
  - 에디터 UI: `tienda-app/src/pages/[storeId]/panel/diseno.tsx` (magic-link 토큰, draft→publish)
  - 스토어프런트: `tienda-app/src/pages/[storeId]/index.tsx`, `src/lib/theme-preset.ts`, `src/components/ProductCard.tsx`
  - admin 카드: `ventago-app/src/components/StorefrontDesignCard.tsx`
- 저장 구조: `store_themes.draft_tokens` / `published_tokens` (JSONB) — **신규 테이블·컬럼 없이 JSONB 키 확장으로 처리** → 마이그레이션 불필요, pool 부담 없음
- 이미지(로고/파비콘/hero)만 MinIO 업로드 필요 (`MinioService` 재사용, JSONB에는 fileName만 저장)

## 기술 스택
- 언어/프레임워크: NestJS 11 (api-ventago) + Next.js (tienda-app, ventago-app)
- DB: PostgreSQL 18 — `store_themes` JSONB 확장, raw parameterized SQL 유지. 읽기=ShopReadonlyDbService, 쓰기=기존 admin 경로. **신규 커넥션/풀 생성 금지**
- ESLint: 각 워크스페이스 기존 설정 (`newline-before-return`, `lines-around-comment`, `no-unused-vars` 주의). ※ device VM에서 타입체크 OOM 이력 → 최종 게이트는 Jenkins

## JSONB 스키마 확장 (draft_tokens / published_tokens 공통)
```jsonc
{
  // 기존 유지 — 단, macrostructure 는 5종으로 확장: marquee | bento | doc | rails | masonry (★확정 2026-07-23)
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
    { "type": "reels", "enabled": false, "title": "", "items": [{ "videoFile": null, "posterFile": null, "productId": null }] },
    { "type": "quiz", "enabled": false, "banner": { "title": "", "subtitle": "" }, "questions": [
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
- `sanitizeTokens` 확장: 각 키 whitelist + 길이/개수 clamp (sections 최대 8, hero images 최대 5, quiz 질문 최대 4·선택지 최대 4, 텍스트 최대 200자). 알 수 없는 키는 drop — 기존 가드레일 철학 유지.
- 하위호환: 키 부재 시 전부 기존 동작과 동일한 default (기존 published_tokens 그대로 유효).

## 태스크 목록

### Wave A — P1 (브랜드·공지바·홈 섹션·연락처)
- [ ] TASK-A1: `store-theme.constants.ts` — 확장 스키마 타입 + `sanitizeTokens` 확장(whitelist/clamp/default) — 파일: api-ventago/src/app/shop-public/store-theme.constants.ts
- [ ] TASK-A2: 테마 이미지 업로드 엔드포인트 `POST /shop/:storeId/theme/asset` (StoreThemeEditGuard, MinioService 재사용, logo/favicon/hero/banner 용도별 확장자·크기 검증, fileName 반환) — 파일: store-theme-admin.controller.ts, store-theme-admin.service.ts, shop-public.module.ts(MinioModule import)
- [ ] TASK-A3: 에디터 패널 확장 1 — 아코디언 레이아웃 전환 + 브랜드(로고/파비콘/표시명) + 공지바 편집 — 파일: tienda-app/src/pages/[storeId]/panel/diseno.tsx (필요시 panel 컴포넌트 분리)
- [ ] TASK-A4: 에디터 패널 확장 2 — 홈 섹션 리스트(▲▼ 순서, 표시 토글, hero 텍스트/이미지, 캐러셀 소스, 베네피시오 항목 편집) — 파일: diseno.tsx + components/panel/SectionListEditor.tsx(신규)
- [ ] TASK-A5: 스토어프런트 렌더 — sections 배열 순회 렌더(hero 캐러셀/benefits/carousel/duoBanners/newsletter), 공지바, 로고, WhatsApp 플로팅 버튼, 푸터(SNS/주소) — 파일: tienda-app/src/pages/[storeId]/index.tsx, components/sections/*(신규), lib/theme-preset.ts
- [ ] TASK-A6: 에디터 미리보기가 확장 키를 반영하는지 확인 (draft 저장→미리보기→publish 왕복)

### Wave A2 — 신규 macrostructure 2종: rails + masonry (★확정 2026-07-23)
- [ ] TASK-A7: 마이그레이션 — `store_themes.macrostructure` CHECK 제약 교체: `('marquee','bento','doc','rails','masonry')` — 파일: api-ventago/migrations/2026-07-XX-store-themes-macro-rails-masonry.sql (※본 Phase의 유일한 DDL. 기존 테이블 ALTER라 owner 이전 불필요. 로컬 5432 + 운영 5434 동시 적용, --single-transaction)
- [ ] TASK-A8: `store-theme.constants.ts` — MACROSTRUCTURES 배열에 rails/masonry 추가 + sanitize 허용값 확장 — 파일: api-ventago/src/app/shop-public/store-theme.constants.ts, tienda-app/src/lib/theme-preset.ts(미러)
- [ ] TASK-A9: **rails 렌더러** — Netflix식 선반: 카테고리/소스별 가로 스크롤 행(Novedades·Más vendidos·카테고리 선반), 행 단위 lazy load, 스크롤 스냅 + 좌우 화살표 — 파일: tienda-app/src/components/macro/RailsLayout.tsx(신규), pages/[storeId]/index.tsx 분기
- [ ] TASK-A10: **masonry 렌더러** — CSS columns 기반(JS 라이브러리 금지), 세로 사진 비율 유지, 모바일 2열/데스크톱 4열, 무한 스크롤은 기존 카탈로그 페이지네이션 재사용 — 파일: tienda-app/src/components/macro/MasonryLayout.tsx(신규)
- [ ] TASK-A11: 에디터 macrostructure 선택 UI를 5종으로 확장(미니 와이어프레임 아이콘 포함) — 파일: diseno.tsx

### Wave B — P2 (상품 카드·카탈로그·신뢰 요소)
- [ ] TASK-B1: ProductCard 옵션 반영(할인 배지·cuotas·quickAdd·hover 2번째 사진·últimas unidades·색상 점) — 파일: tienda-app/src/components/ProductCard.tsx
- [ ] TASK-B2: 카탈로그 정렬/페이지 크기/품절 표시/필터 — 백엔드 `shop-catalog.controller.ts` 쿼리 파라미터 + 프런트 목록 (pageSize clamp ≤ 48)
- [ ] TASK-B3: 푸터 신뢰 요소(결제/배송 로고 chips, compra protegida, 정책 링크) 에디터 + 렌더
- [ ] TASK-B4: 에디터 패널에 Wave B 아코디언 추가 — 파일: diseno.tsx
- [ ] TASK-B5: **reels 섹션 타입** (★확정 2026-07-23) — 세로 영상 카드 가로 스크롤 + 각 카드에 상품 연결(가격/CTA 오버레이). 영상 업로드는 TASK-A2 에셋 엔드포인트 확장(mp4/webm, ≤20MB, poster 이미지 필수), `<video muted playsInline preload="none" poster>` — autoplay 금지·탭 시 재생(모바일 데이터 배려) — 파일: tienda-app/src/components/sections/ReelsSection.tsx(신규), 에디터 reels 편집 UI
- [ ] TASK-B6: **quiz 섹션 타입 (asesor guiado)** (★확정 2026-07-23, 목업 tienda-online-quiz-mockup.html) — 홈 진입 배너 → 질문 3개(진행바+뒤로가기) → 추천 3개(매칭 이유+MATCH 배지) + WhatsApp 상담/전체 카탈로그 출구. **답변→필터 변환은 프런트에서 기존 catálogo 쿼리 파라미터로 매핑** (신규 백엔드 쿼리·테이블 없음 = pool 무부담). 질문/선택지/매핑은 JSONB `quiz` 섹션에서 admin 편집. 결과 카드의 매칭 이유 텍스트도 옵션별 admin 입력 — 파일: tienda-app/src/components/sections/QuizSection.tsx(신규), 에디터 quiz 편집 UI(질문·선택지 추가/삭제)

### Wave C — P3 (마케팅·SEO)
- [ ] TASK-C1: 웰컴 팝업+쿠폰 (세션당 1회, localStorage 금지 조건 없음—스토어프런트는 일반 웹) — 렌더 + 에디터
- [ ] TASK-C2: SEO title/description → `getServerSideProps`에서 `<Head>` 주입, pixelId 스크립트(값 있을 때만)
- [ ] TASK-C3: (연계) 팝업 쿠폰 코드 ↔ Campañas discounts 검증은 Phase 61 범위 외 — TODO 주석만

### 공통 마무리
- [ ] TASK-Z1: ESLint 검증 — api-ventago·tienda-app 변경 파일 `npx eslint --fix`, 오류 0
- [ ] TASK-Z2: PostgreSQL pool 안전 점검 — 신규 쿼리 전부 기존 서비스 경로(파라미터라이즈드) 사용, `pool.connect()` 직접 호출 없음 확인
- [ ] TASK-Z3: 리뷰 리포트 + 로그(`logs/error-*.log`) 재확인

## 완료 기준
- ESLint 오류 0개 (변경 파일 기준)
- 기존 store(확장 키 없는 published_tokens)의 스토어프런트가 회귀 없이 렌더
- draft→publish 왕복 후 공개 페이지에 섹션 순서/토글 반영
- 이미지 업로드가 MinIO 경유(`/api/minio/<fileName>`)로 표시
- macrostructure `rails`/`masonry` 선택 시 스토어프런트가 해당 뼈대로 렌더 (기존 3종 회귀 없음)
- CHECK 제약 마이그레이션이 로컬 5432 + 운영 5434 양쪽 적용·대조 확인
- 신규 테이블/컬럼/커넥션 0개 (유일한 DDL = macrostructure CHECK 교체)

## 금지사항 / 주의사항
- `store_themes` DDL은 TASK-A7의 CHECK 교체 **1건만 허용** — 그 외 컬럼/테이블 추가 금지 (나머지는 전부 JSONB 키 확장)
- 영상 업로드 검증 필수: mp4/webm만, 20MB 제한, poster 필수, UUID 파일명 — 미검증 업로드로 MinIO 용량 폭발 방지
- 새 Pool/Client 인스턴스 생성 금지 — ShopReadonlyDbService(읽기)/기존 admin 서비스(쓰기)만 사용
- legacy 스토어프런트(`shop-storefront.page.ts`)는 건드리지 않음 (대상은 tienda-app만)
- `sanitizeTokens` 미경유 raw 토큰 저장 금지 (XSS: 텍스트는 렌더 시 이스케이프, href는 http(s)/상대경로만 허용)
- 업로드 검증: png/jpg/webp/svg(로고만), 2MB 제한, 파일명 UUID 재부여
- ventago-app ESLint 규칙(newline-before-return 등) 준수, `apiConnector.remove()` 사용
- Mac 워킹트리 미커밋 WIP(`afip-issuer.service.ts`)는 건드리지 말 것
- 개발은 사용자 Mac 로컬에서 진행(2026-07-23 확정 워크플로우) — 이 SPEC은 계획 산출물
