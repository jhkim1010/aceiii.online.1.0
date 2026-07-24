# Phase 61: Tienda Online 에디터 확장 — Context

**Gathered:** 2026-07-23
**Status:** Ready for planning
**Source:** PRD Express Path (`.planning/phases/61-tienda-online-editor/61-SPEC.md`, 원본 `.gsd/spec-phase61-tienda-online-editor.md`)

<domain>
## Phase Boundary

**포함 (Wave A + A2 + B + C 전체):**
- **macrostructure 4종 재편** (`rails` Netflix식 선반 + `masonry` CSS columns 추가, `doc` 제거) + 전용 렌더러 2종 + doc 렌더 경로 삭제 + 에디터 선택 UI 4종(성격 설명 + 구조별 섹션 게이팅) + `store_themes.macrostructure` CHECK 제약 교체 마이그레이션 (본 Phase 유일 DDL, 5432+5434)
- **`reels` 섹션 타입** (세로 영상 카드 + 상품 연결, mp4/webm ≤20MB + poster 필수, autoplay 금지)
- **`quiz` 섹션 타입 — asesor guiado** (홈 배너 → 질문 3개 → 매칭 이유 붙은 추천 3개 + WhatsApp/전체카탈로그 출구). 답변→필터 변환은 **프런트에서 기존 catálogo 쿼리 파라미터로 매핑** — 신규 백엔드 쿼리·엔드포인트·테이블 0, pool 무부담
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

</domain>

<decisions>
## Implementation Decisions

### 저장 구조 (LOCKED)
- 확장은 전부 `store_themes.draft_tokens` / `published_tokens` JSONB 키 추가로만 처리. **신규 테이블·컬럼·마이그레이션 0개.**
- 이미지는 MinIO 에 업로드하고 JSONB 에는 `fileName` 문자열만 저장. 표시는 `{API_HOST}/minio/{fileName}`.
- 확장 키 전체 스키마는 61-SPEC.md 「JSONB 스키마 확장」 블록이 정본. Wave A = brand/announce/sections/contact, Wave B = productCard/catalog/trust, Wave C = marketing.

### 가드레일 (LOCKED)
- 모든 쓰기는 `sanitizeTokens()` 를 반드시 경유. 미경유 raw 토큰 저장 경로 금지.
- 키별 whitelist + clamp: `sections` 최대 8개, hero `images` 최대 5개, quiz 질문 최대 4개·선택지 최대 4개, 텍스트 필드 최대 200자, `catalog.pageSize` ≤ 48. 알 수 없는 키는 drop (기존 `clamp()` 철학 유지).
- href 계열(`announce.href`, `duoBanners[].href`, `trust.policyLinks[]`)은 `http(s)://` 또는 `/` 시작 상대경로만 허용, 그 외 null 로 강등 (XSS 차단).
- 텍스트는 렌더 시 이스케이프 — `dangerouslySetInnerHTML` 사용 금지.

### 하위호환 (LOCKED)
- 확장 키가 전혀 없는 기존 `published_tokens` 로도 `buildThemeResponse()` 가 현행과 동일하게 동작해야 한다. 모든 확장 키에 default 존재.
- 기존 매장 공개 페이지 렌더 회귀 0 이 완료 게이트.

### DB / 커넥션 (LOCKED)
- 읽기 = `ShopReadonlyDbService`, 쓰기 = 기존 `store-theme-admin.service.ts` 경로만 사용.
- **새 `Pool` / `Client` 인스턴스 생성 금지.** raw parameterized SQL 유지.

### 업로드 검증 (LOCKED)
- 허용 확장자: png / jpg / webp, `svg` 는 로고 전용.
- 최대 2MB. 파일명은 UUID 로 재부여.
- 인가는 기존 `store-theme-edit.guard.ts` (magic-link 토큰) 재사용.
- `MinioModule` 을 `shop-public.module.ts` imports 에 추가하고 `MinioService.uploadFile()` 재사용.

### 에디터 UX (LOCKED)
- 승인된 목업: 레포 루트 `tienda-online-editor-mockup.html` — 아코디언 레이아웃/섹션 리스트 조작 방식의 기준.
- 홈 섹션 리스트는 ▲▼ 버튼으로 순서 이동 + 표시 토글. 순서 = 배열 순서.
- 섹션 리스트 편집기는 `components/panel/SectionListEditor.tsx` 로 분리.
- 기존 draft 저장 → 미리보기 → publish 왕복 흐름 유지 (신규 발행 흐름 만들지 않음).

### Wave 순서 (LOCKED)
- Wave A(브랜드·공지바·홈 섹션·연락처) → Wave A2(macrostructure rails/masonry + CHECK 마이그레이션) → Wave B(상품카드·카탈로그·신뢰요소·reels) → Wave C(마케팅·SEO).
- A 의 sanitize 확장 + sections 렌더 골격이 A2/B/C 의 선행조건. A2 의 마이그레이션은 `sanitizeMacrostructure` 확장보다 **먼저** 적용돼야 한다(제약 위반 방지) → A2 내부에서 마이그레이션 태스크를 `[BLOCKING]` 으로 앞세운다.
- reels(TASK-B5)는 R2 에셋 업로드 엔드포인트(Wave A)의 확장이므로 A2 이후 Wave B 에 배치.

### 코드 규약 (LOCKED)
- ESLint: 워크스페이스별 기존 설정 준수 — `newline-before-return`, `lines-around-comment`, `no-unused-vars`. 변경 파일 오류 0.
- 프런트에서 삭제 호출은 `apiConnector.remove()` (`.delete()` 아님).
- 주석은 한국어, 함수/변수명은 영어 (프로젝트 전역 규약).
- device VM 타입체크 OOM 이력 → 로컬 전체 타입체크 강행 금지, 최종 게이트는 Jenkins.

### 건드리지 말 것 (LOCKED)
- Mac 워킹트리 미커밋 WIP `afip-issuer.service.ts`.
- legacy `shop-storefront.page.ts`.

### 템플릿 다양성 — LOCKED (사용자 확정 2026-07-23 22:52)
문제 인식: **현행 hallmark 프리셋(12개 색/글꼴 조합) + macrostructure 3종(marquee/bento/doc)만으로는 결과물이 너무 뻔하다.** 다른 venta online 홈페이지와 차별점이 없다. 색/글꼴만 바뀌고 레이아웃 뼈대가 사실상 하나인 게 원인.

확정된 대응 (SPEC R9 / R10):
- **macrostructure 4종 재편**: `marquee | bento | rails | masonry` — `rails`/`masonry` 추가, **`doc` 제거**(사용자 확정 2026-07-23. 스토리형은 Lookbook 아키타입과 역할 중복. 로컬 5432·운영 5434 모두 `doc` 사용 0건 확인 → 데이터 마이그레이션 불필요)
  - `rails` = Netflix식 선반. 소스별 가로 스크롤 행(Novedades / Más vendidos / 카테고리별), 행 단위 lazy load, 스크롤 스냅 + 좌우 화살표
  - `masonry` = CSS `columns` 기반 비정형 그리드. 세로 사진 비율 유지, 모바일 2열 / 데스크톱 4열. **JS masonry 라이브러리 도입 금지**
- **`reels` 섹션 타입 신설** (Wave B): 세로 영상 카드 가로 스크롤 + 상품 연결(가격/CTA 오버레이). `<video muted playsInline preload="none" poster>` — **autoplay 금지, 탭 시 재생**(모바일 데이터 배려)
- **DDL 예외 1건 허용**: `store_themes.macrostructure` CHECK 제약을 `('marquee','bento','rails','masonry')`로 교체하는 마이그레이션(같은 트랜잭션에 `UPDATE ... SET macrostructure='marquee' WHERE macrostructure='doc'` 방어적 포함 — 현재 0행). 본 Phase의 **유일한** DDL. 기존 테이블 ALTER라 owner 이전 불필요. **로컬 5432 + 운영 5434 동시 적용 + 대조 확인** 필수 (`--single-transaction -v ON_ERROR_STOP=1`)
- 영상 업로드 검증: mp4/webm만, **20MB 제한, poster 이미지 필수**, UUID 파일명 — 미검증 업로드로 MinIO 용량 폭발 방지
- **`quiz` 섹션 타입 신설** (Wave B, 목업 `tienda-online-quiz-mockup.html`): 홈 진입 배너 → 질문 3개(진행 표시 + 뒤로가기) → 추천 3개(MATCH 배지 + 매칭 이유) → 출구 3종(WhatsApp 상담 / 다시하기 / 전체 카탈로그). 질문·선택지·매핑·매칭 이유 문구 전부 admin 편집. **답변→필터는 프런트가 기존 카탈로그 쿼리 파라미터로 변환** — 신규 백엔드 엔드포인트 0. quiz 질문 최대 4개·선택지 최대 4개 clamp.
- 나머지 확장은 종전대로 JSONB 키 확장만. 신규 테이블/컬럼 0 유지.

### Claude's Discretion
- 확장 타입의 TypeScript 인터페이스 명명/분해 방식 (`StoreThemeContent` 등 별도 인터페이스로 뺄지, `StoreThemeTokens` 확장할지)
- 섹션 렌더 컴포넌트 파일 분해 단위 (`components/sections/Hero.tsx` 등)
- 아코디언 구현 수단 (기존 tienda-app 스타일 체계 내에서 선택)
- 업로드 엔드포인트의 용도 구분 전달 방식 (query param vs body field)
- 캐러셀 `source: bestseller` 의 집계 쿼리 구현 방식 (기존 카탈로그 서비스 재사용 우선)
- 팝업 세션 1회 판정 저장소 (sessionStorage 등) — 스토어프런트는 일반 공개 웹이므로 제약 없음

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### 페이즈 정본
- `.planning/phases/61-tienda-online-editor/61-SPEC.md` — 11개 요구사항(R1~R11) + JSONB 확장 스키마 + 완료 기준 + 금지사항
- `.gsd/spec-phase61-tienda-online-editor.md` — 원본 태스크 분해(Wave A/B/C, TASK-A1~C3, Z1~Z3)
- `tienda-online-editor-mockup.html` (레포 루트) — 승인된 에디터 UI 목업 (아코디언 그룹 구성 기준)
- `tienda-online-templates-mockup.html` (레포 루트) — 템플릿 아키타입 탐색 목업 3종(Catálogo 그리드 직행 / Lookbook 에디토리얼 교차 / Drop 랜딩 원페이지) + 각 아키타입의 적합 매장 설명
- `tienda-online-rails-masonry-reels-mockup.html` (레포 루트) — **rails / masonry / reels 렌더 시각 정본**
- `tienda-online-estructuras-editor-mockup.html` (레포 루트) — **구조 선택 UI + 구조별 편집 필드 + 구조별 섹션 게이팅 시각 정본** (사용자 승인 2026-07-23)
- `tienda-online-quiz-mockup.html` (레포 루트) — **quiz(asesor guiado) 흐름 시각 정본**: 배너 → `1 / 3` 진행 + `← Volver` → 결과 `MATCH NN%` + 매칭 이유 → 출구 3종

### 백엔드 (api-ventago)
- `api-ventago/src/app/shop-public/store-theme.constants.ts` — 토큰 SSOT: `StoreThemeTokens`, `THEME_PRESETS`, `clamp()`, `sanitizeTokens()`, `tokensToCssVars()`, `buildThemeResponse()`
- `api-ventago/src/app/shop-public/store-theme.service.ts` — 읽기 경로 (ShopReadonlyDbService)
- `api-ventago/src/app/shop-public/store-theme-admin.service.ts` — draft/publish 쓰기 경로
- `api-ventago/src/app/shop-public/store-theme-admin.controller.ts` — admin 엔드포인트
- `api-ventago/src/app/shop-public/store-theme-edit.guard.ts` — magic-link 토큰 인가
- `api-ventago/src/app/shop-public/shop-readonly-db.service.ts` — 공개 읽기 전용 DB 서비스
- `api-ventago/src/app/shop-public/shop-catalog.controller.ts` — 카탈로그 목록 API (Wave B 정렬/페이지/필터 대상)
- `api-ventago/src/app/shop-public/shop-public.module.ts` — MinioModule import 추가 지점

### 프런트 (tienda-app)
- `tienda-app/src/pages/[storeId]/panel/diseno.tsx` — 에디터 패널 (아코디언 전환 대상)
- `tienda-app/src/pages/[storeId]/index.tsx` — 스토어프런트 홈 (sections 렌더 대상)
- `tienda-app/src/lib/theme-preset.ts` — 프런트 테마 적용 유틸
- `tienda-app/src/components/ProductCard.tsx` — 상품 카드 (Wave B 옵션 대상)

### 프로젝트 규약
- `CLAUDE.md` (루트) — DB 컬럼 snake_case, ESLint 규칙, pool 절약, MinIO 업로드 패턴, `apiConnector.remove()`
- `.planning/intel/db-schema-tables.md` — `store_themes` 실제 컬럼 확인용 (추측 금지)

</canonical_refs>

<specifics>
## Specific Ideas

- 목업 `tienda-online-editor-mockup.html` 가 아코디언 그룹 구성과 섹션 리스트 조작 UI 의 시각적 기준. 플래너/실행자는 이 파일을 읽고 그룹 명칭과 순서를 맞춘다.
- `sanitizeTokens()` 는 현재 6개 토큰만 처리하고 프리셋 기본값 위에 병합하는 구조 — 확장 시 이 병합 패턴(프리셋 default → raw 병합 → clamp)을 그대로 이어간다.
- `tokensToCssVars()` 는 콘텐츠 키(brand/sections 등)와 무관 — CSS 변수 맵에 콘텐츠를 섞지 않는다. 콘텐츠는 응답의 별도 필드로 노출.
- 카탈로그 `pageSize` 는 프로젝트 성능 규약(pageSize 최대 50)과 정합 — spec 상한 48 유지.
- `carousel.source` 는 `newest | bestseller | category` 3값 whitelist. `category` 일 때만 `categoryId` 유효.

</specifics>

<deferred>
## Deferred Ideas

- 팝업 쿠폰 코드 ↔ Campañas discounts 실제 검증/발급 연동 — Phase 61 범위 외, TODO 주석만 남긴다 (TASK-C3)
- ventago-app 내 storefront 편집 UI 이식 — 현행처럼 `StorefrontDesignCard.tsx` 진입 링크 유지
- legacy `shop-storefront.page.ts` 의 확장 키 대응 — 대상 아님

</deferred>

---

*Phase: 61-tienda-online-editor*
*Context gathered: 2026-07-23 via PRD Express Path*
