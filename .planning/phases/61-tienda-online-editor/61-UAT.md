# Phase 61 — UAT

**Executed:** 2026-07-24T15:11:10Z
**Status:** passed_with_gaps (자동 게이트 전부 PASS · 브라우저 UAT 8개 항목은 오케스트레이터 Chrome 수행 대기)

## 실행 환경 메모
- 이 실행 환경(샌드박스)에는 `./dev.sh`로 기동한 API(5002)/tienda-app(3050~) 서버가 없다. 서버 필요 스모크(theme GET, asset 업로드 curl, 공개 HTML data-macro)는 **SKIP** 처리하고 브라우저 UAT 로 이관했다.
- `api-ventago`/`ventago-app`/`mobile-sales-app`는 각각 **독립 git 저장소**(루트 저장소는 gitlink 로만 참조, `.gitmodules` 없음)이고 `tienda-app`은 루트 저장소에 직접 포함된다. 그래서 PLAN 의 `git status --porcelain api-ventago/migrations/` 명령은 루트 관점에서 항상 0(gitlink 는 파일 단위 diff 미노출)을 반환한다 — 실제 신규 마이그레이션 파일 존재/개수는 `api-ventago` 저장소 내부에서 확인했다(아래 표 참조).

## 자동 게이트 (R8 + 유닛 + lint)

| Gate | Command | Result | Evidence |
|------|---------|--------|----------|
| 마이그레이션 1건만(테이블/컬럼 추가 0) | `ls api-ventago/migrations/2026-07-24-store-themes-macro-4.sql` + `grep -ciE "CREATE TABLE\|ADD COLUMN\|DROP COLUMN"` | ✅ | 파일 존재, CREATE/ADD/DROP COLUMN 매치 0건. `api-ventago` 저장소 내부 `git log --oneline -- migrations/2026-07-24-store-themes-macro-4.sql` → `bbc540c feat(61-04)` 1개 커밋(이미 61-04 에서 로컬 5432+운영 5434 적용·대조 완료, 아래 참조). `ls migrations/ \| grep 2026-07-2[4-9]` → 해당 파일 1개뿐 |
| 신규 Pool/Client 0 | `grep -rn "new Pool(\|new Client(" api-ventago/src/app/shop-public/` | ✅ | `shop-readonly-db.service.ts:23`(기존 격리 pool, 61-01 이전부터 존재) 1건만 검출, 제외 시 0건 |
| doc 잔여 0(스펙 강등 테스트/설명 주석 제외) | `grep -rn "'doc'" tienda-app/src/ api-ventago/src/app/shop-public/ \| grep -v ".spec.ts"` | ✅ | `store-theme.constants.ts:515` 주석 1건만("'doc' 은 2026-07-23 제거됨 — ... marquee 로 강등된다") — 렌더 분기 아님, 제거 사유 설명 주석. 렌더 분기(`index.tsx` 등)에는 `'doc'` 0건 |
| 신규 lib 0 | `git diff main -- tienda-app/package.json` (루트) + `git diff main -- package.json`(api-ventago 내부) | ✅ | 양쪽 0줄 |
| dangerouslySetInnerHTML 0 | `grep -rn "dangerouslySetInnerHTML" tienda-app/src/` | ✅ | 0건 |
| shop-public 유닛 | `cd api-ventago && npx jest src/app/shop-public --silent` | ✅ | `store-theme.constants.spec.ts` + `shop-catalog.service.spec.ts` 2 suites, **45 tests passed** (rails/masonry/doc→marquee/foo→marquee/quiz clamp/reels poster-drop/price sort 매핑 등 포함) |
| api-ventago eslint (shop-public 디렉토리 전체) | `npx eslint src/app/shop-public/` | ⚠️ 1건(사전 존재, out-of-scope) | `store-slug.service.ts:11` prettier import-wrap 오류. **61-01 이전(commit b2887f1/bed98a0, Phase61 태그이나 61-01~14 플랜 대상 아님)부터 반복 확인된 사전 존재 오류**로 61-01~04 SUMMARY 에 이미 기록됨(`deferred-items.md`). SCOPE BOUNDARY 로 미수정 |
| api-ventago eslint (Phase 61 실제 변경 파일만, R8 "변경 파일 기준" 정확 매핑) | `git diff --name-only 231e60f^..HEAD -- src/app/shop-public/ \| grep -v spec \| xargs npx eslint` | ✅ | 9개 파일(shop-catalog.controller/service, shop-public.module, store-theme-admin.controller/service, store-theme-asset.controller/service, store-theme.constants, store-theme.service) 전부 오류 0 |
| tienda-app tsc | `cd tienda-app && npx tsc --noEmit` | ✅ | 오류 0 |
| tienda-app eslint | `cd tienda-app && npx eslint src/` | ✅ | 오류 0, 경고 0 |
| ReelsSection autoplay 금지 | `grep -n "autoplay" tienda-app/src/components/sections/ReelsSection.tsx` | ✅ | 0건, `preload="none"` (68행) 존재 확인 |
| doc/foo → marquee 강등 유닛테스트 | `store-theme.constants.spec.ts` 내 `sanitizeMacrostructure` 케이스 | ✅ | `'doc'→marquee`(377행), `'foo'→marquee`(381행), `undefined→marquee`(385행) 전부 PASS |
| 서버 필요 스모크(`scripts/smoke-shop-theme.sh`) | `bash scripts/smoke-shop-theme.sh` | ⏭️ SKIP | 이 실행 환경에 API 서버(5002) 미기동 → status=000. 업로드 체크(3~7)도 `EDIT_TOKEN` 미설정으로 SKIP. **브라우저 UAT 단계에서 `./dev.sh` 기동 후 재실행 필요**(Task 2 이관) |

## R1~R11 검증 결과

| Req | Behavior | Type | Result | Note |
|-----|----------|------|--------|------|
| R1 | 확장 키 없는 `published_tokens` → `buildThemeResponse()` 현행과 동일 + 확장 default | unit | ✅ | "확장 키 없는 published_tokens 는 기존 토큰 응답을 그대로 유지한다", "확장 키가 없으면 content 는 DEFAULT_CONTENT 로 채워진다" PASS |
| R1 | sections 9개/텍스트 300자/`javascript:` href → 8개/200자/null clamp | unit | ✅ | "sections 9개는 8개로 clamp", "텍스트 300자는 200자로 clamp", "announce.href 의 javascript: 는 null 로 강등" 등 PASS |
| R2 | 2MB 이하 png → `{fileName}` · 3MB/`.exe` → 400 | smoke | ⏭️ SKIP(서버 미기동) | `smoke-shop-theme.sh` 체크 3/4/6 대상. 코드 검토로 로직 존재 확인(`store-theme-asset.service.ts` kind별 확장자/크기 검증). 브라우저 UAT 이관 |
| R3 | 에디터 아코디언 브랜드/공지바/섹션 편집 → draft 저장 | browser UAT | ⬜ 미실행 | 브라우저 UAT 항목 2 |
| R4 | draft→publish 왕복 → 공개 페이지 섹션 순서/토글 반영 | browser UAT + smoke | ⬜ 미실행 | 브라우저 UAT 항목 2 |
| R4 | 확장 키 없는 기존 매장 공개 페이지 회귀 0 | smoke | ⬜ 미실행(서버 필요) | 브라우저 UAT 항목 1(최우선) |
| R5 | `productCard.discountBadge=false` → 배지 미노출 | smoke+UAT | ⚠️ 부분(코드만 확인) | `ProductCard.tsx` 6옵션 조건부 렌더 코드 존재(61-12 커밋 b842d4e) + `ShopProductDto.priceOrig`/`stock` 필드 추가(61-03) 확인. 실제 렌더 확인은 브라우저 UAT |
| R6 | `pageSize=999` → 48 clamp | unit | ✅ | "catalog.pageSize=999 는 48 로 clamp 된다" PASS |
| R6 | `catalog.pageSize=12`·`sort=price_asc` 반영 | smoke | ✅(단위) / ⏭️(smoke) | 단위 테스트로 `resolveOrderBy` 매핑 확인(price_asc→`p.price ASC`, price_desc→`p.price DESC`, SQL 인젝션 시도 강등) PASS. curl smoke 는 서버 미기동으로 SKIP |
| R6 | `filters.price=false/true`+구간 → UI 숨김/좁힘(minPrice/maxPrice) | smoke+UAT | ⬜ 미실행 | 브라우저 UAT 항목 10b(코드 존재는 61-12 커밋 03dc93a 확인) |
| R6 | `filters.color`/`filters.size` → UI 미렌더(예외, 저장만) | browser UAT | ⬜ 미실행 | 브라우저 UAT 항목 10c |
| R7 | 팝업 첫 방문 1회·재방문 미표시 | browser UAT | ⬜ 미실행 | 브라우저 UAT 항목 9(코드는 `MarketingPopup.tsx`, 61-13 커밋 5dd32ad 확인 — sessionStorage 키 사용) |
| R7 | `seoTitle`→`<title>` 반영·`pixelId=null`→스크립트 없음 | smoke | ⬜ 미실행(서버 필요) | 브라우저 UAT 항목 9(코드는 `index.tsx` SEO Head 주입, 61-13 커밋 d45687e 확인) |
| R8 | 신규 Pool/Client 0·ESLint 0·신규 테이블/컬럼 0 | automated grep | ✅ | 위 자동 게이트 표 전항목 PASS(변경 파일 기준 eslint 0, pool 0, 마이그레이션 1건) |
| R9 | `rails`/`masonry` publish → 해당 뼈대 렌더·`marquee`/`bento` 회귀 0 | browser UAT+smoke | ⬜ 미실행 | 브라우저 UAT 항목 4 |
| R9 | `doc` 잔여 코드 0 | automated grep | ✅ | 렌더 분기 0건(설명 주석 1건만, 위 표 참조) |
| R9 | `'doc'`/알 수 없는 값 → `marquee` 강등 | unit | ✅ | `sanitizeMacrostructure('doc')==='marquee'`, `('foo')==='marquee'` PASS |
| R9 | 로컬 5432/운영 5434 `chk_store_theme_macro` 정의 동일(4값) | manual DB | ✅ **이미 완료** | 61-04-SUMMARY.md 「배포/검증」 섹션에 문자 단위 동일 대조 결과 기록됨: 양쪽 `CHECK (((macrostructure)::text = ANY ((ARRAY['marquee','bento','rails','masonry'])::text[])))`. 브라우저 UAT 항목 6 은 재확인만 필요(신규 적용 불필요) |
| R9 | 구조 전환 후 되돌리면 비활성 섹션 값 복귀 | browser UAT | ⬜ 미실행 | 브라우저 UAT 항목 5 |
| R10 | reels `preload="none"`+poster 렌더·autoplay 없음 | smoke | ✅(코드 grep) / ⬜(HTML) | `ReelsSection.tsx` autoplay 0건 + `preload="none"` 확인(위 표). 공개 HTML grep 은 서버 필요 → 브라우저 UAT 항목 7 |
| R10 | 21MB/`.mov` → 400·poster 없는 item drop | unit+smoke | ✅(unit) / ⏭️(smoke) | "poster 없는 item 은 drop 된다", "video 없는 item 은 drop 된다" PASS. curl 크기/확장자 거부는 서버 미기동으로 SKIP |
| R11 | quiz 3문항 → 추천 3개(MATCH 배지+이유) | browser UAT | ⬜ 미실행 | 브라우저 UAT 항목 8 |
| R11 | quiz 진행 중 신규 백엔드 엔드포인트 호출 0건 | browser UAT(Network) | ⬜ 미실행 | 브라우저 UAT 항목 8. 코드 검토: `QuizSection.tsx` 는 카탈로그 파라미터(`categoryId`/`minPrice`/`maxPrice`)만 구성해 기존 `/public/shop/*/products`·`router.push` 사용, 신규 fetch 없음(그렙 확인) |
| R11 | 질문 5개/선택지 5개 → 4개로 clamp | unit | ✅ | "quiz 질문 5개는 4개로 clamp 된다", "quiz 선택지 5개는 4개로 clamp 된다" PASS |
| R11 | `Ver catálogo completo`→선택 필터 적용 이동 | smoke | ✅(코드 확인) | `QuizSection.tsx`(373행) `router.push(catalogHref)`가 `categoryId`/`minPrice`/`maxPrice` 쿼리로 인코딩(94~110행), `index.tsx`(117~151행, 61-14 후속 커밋 476996e)가 마운트 시 이 쿼리를 읽어 `activeCat`/`minP`/`maxP` 초기 state 로 시드. **61-14 deferred-items.md 에 기록됐던 갭이 후속 커밋으로 이미 해소됨** — 실제 브라우저 왕복 확인은 UAT 항목 8 |

*Status: ⬜ pending(브라우저 필요) · ✅ green(자동/코드 확인) · ⚠️ flaky/부분 · ❌ red · ⏭️ SKIP(서버 미기동)*

## 브라우저 UAT 체크리스트 (오케스트레이터 Chrome 수행)

61-15-PLAN.md Task 2 원문 그대로. `./dev.sh` 로 로컬 기동 후 진행.

1. **무회귀(최우선)**: 확장 키 없는 기존 매장(storeId=9 ACE) 공개 페이지가 변경 전과 시각적으로 동일(hero/Destacados/AI strip 이 DEFAULT_CONTENT 로 재현).
2. **R3/R4**: `/{storeId}/panel/diseno?t=<edit-link 토큰>` 아코디언 12그룹 확인 → hero 를 benefits 아래로 이동 + newsletter 켬 → Guardar borrador → 미리보기 반영 → Publicar → 공개 페이지 순서/토글 반영. 로고 png 업로드 → 헤더 로고 이미지, 3MB/.exe 거부 문구.
3. **R9 rails/masonry**: 구조 카드에서 Rails 선택 → 미리보기 즉시 선반 레이아웃 → Publicar → 공개 홈 가로 스크롤 선반. Masonry 동일. marquee/bento 회귀 없음.
4. Rails → Marquee 되돌린 뒤 carousel 설정 보존 확인.
5. **운영 5434 마이그레이션**: 61-04 에서 이미 적용·대조 완료(위 R9 행 참조) — 재확인만.
6. **R10 reels**: 영상 2개(poster 포함) 업로드 → publish → 공개 홈 세로 카드, DevTools Network 초기 로드 영상 바이트 0(poster 만) → 탭 재생, 다른 영상 탭 시 이전 정지. 21MB/.mov 거부.
7. **R11 quiz**: 질문 3개 설정 → publish → 공개 홈 배너 → 3문항 → 추천 3개(MATCH 배지+이유). DevTools Network 요청 URL 이 `/public/shop/*/products` 뿐. Ver catálogo completo 필터 적용 이동.
8. **R7 마케팅**: 팝업 켜고 publish → 첫 방문 1회 표시, 재방문 안 뜸(sessionStorage). seoTitle 설정 → 페이지 소스 `<title>` 확인. pixelId null → `<script id="meta-pixel">` 없음.
9. **R5/R6**: `productCard.discountBadge=false` → 배지 사라짐. `catalog.pageSize=12&sort=price_asc` → 12개 가격 오름차순.
10. **가격 필터(R6 실구현)**: `filters.price=false` publish → 가격 필터 UI 없음. `filters.price=true` publish → 가격 필터 UI 표시 → 구간(예: 10000~30000) 지정 시 목록이 좁혀지고 요청 URL 에 `minPrice`/`maxPrice` 반영(DevTools Network).
11. **color/size 필터(no-op 예외)**: `filters.color`/`filters.size` 켜고 꺼도 공개몰에 색상/사이즈 필터 UI 렌더 안 됨. 토글 값은 draft/published JSONB 에 저장만(에디터 재로드 시 값 유지).

**Acceptance:**
- 무회귀(1) 확인
- rails/masonry(3) 렌더 + marquee/bento 회귀 없음
- reels(6) 초기 영상 바이트 0 + 탭 재생
- quiz(7) 네트워크 요청이 카탈로그 엔드포인트뿐
- 가격 필터(10): false 시 UI 숨김, true+구간 시 목록 좁힘 + minPrice/maxPrice URL 반영
- color/size 필터(11): UI 미렌더(예외) + 토글 값 저장 확인
- 운영 5434 CHECK 제약 4값(이미 확인 완료, 재검증만)
- 61-UAT.md 브라우저 섹션 작성 완료(오케스트레이터가 이 파일의 "브라우저 UAT 결과" 섹션을 추가/갱신)

## Gaps (자동 게이트 기준)

없음 — 자동 게이트 10종 전부 PASS(`store-slug.service.ts` 사전 존재 lint 오류 1건은 Phase 61 변경 파일 범위 밖으로 gap 아님, deferred-items.md 기록 유지).

## Deferred to Browser UAT (오케스트레이터 수행)

- R2/R7/R10 의 curl 스모크(서버 미기동으로 SKIP) — `EDIT_TOKEN` 발급 후 `scripts/smoke-shop-theme.sh` 재실행 권장
- R3/R4/R5(부분)/R6(filters.price/color/size)/R7(팝업)/R9(rails/masonry 시각+구조 왕복)/R10(탭 재생)/R11(quiz 왕복+네트워크 탭) 전부 — 코드 존재는 확인됐으나 실제 렌더/상호작용은 브라우저 필요
