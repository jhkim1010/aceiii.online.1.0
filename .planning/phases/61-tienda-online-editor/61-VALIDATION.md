---
phase: 61
slug: tienda-online-editor
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-23
---

# Phase 61 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> 출처: `61-RESEARCH.md` § Validation Architecture

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Jest (api-ventago 전용 — `package.json` `"test": "jest"`). **tienda-app 은 테스트 프레임워크 전무** (jest/vitest 없음, `*.test.*`/`*.spec.*` 0건) |
| **Config file** | api-ventago: `package.json` 내 jest 설정 / tienda-app: 없음 |
| **Quick run command** | `cd api-ventago && npx jest src/app/shop-public --silent` |
| **Full suite command** | `cd api-ventago && npm test` |
| **Estimated runtime** | ~30초 (shop-public 스코프), 전체 스위트 ~2분 |

**중요:** tienda-app 에 신규 테스트 프레임워크 도입은 **이 Phase 범위 밖**(SPEC 미요구, 임의 확장 금지). 프런트 검증은 `curl` 스모크 + HTML grep + 브라우저 UAT 로 대체한다.

---

## Sampling Rate

- **After every task commit:** 순수함수 변경 시 `cd api-ventago && npx jest src/app/shop-public --silent`. 그 외에는 `npx eslint <변경파일>` + `curl` 스모크.
- **After every plan wave:** `cd api-ventago && npm test` + `npx eslint` (변경 워크스페이스) + `grep -rn "new Pool(\|new Client(" <diff 파일>` (0건 기대)
- **Before `/gsd-verify-work`:** api-ventago 전체 스위트 green + ESLint 0 + 브라우저 UAT 체크리스트
- **Max feedback latency:** 60초 (유닛), 스모크 포함 시 ~3분

---

## Per-Task Verification Map

> Task ID 는 PLAN.md 생성 후 채운다. 현재는 요구사항 단위 계약.

| Req | Behavior | Test Type | Automated Command / 관찰 신호 | File Exists | Status |
|-----|----------|-----------|-------------------------------|-------------|--------|
| R1 | 확장 키 없는 `published_tokens` → `buildThemeResponse()` 현행과 동일 + 확장 default | unit | `npx jest store-theme.constants` | ❌ W0 | ⬜ pending |
| R1 | sections 9개 / 텍스트 300자 / `javascript:` href → 8개 / 200자 / null clamp | unit | 동일 스펙 파일 케이스 | ❌ W0 | ⬜ pending |
| R2 | 2MB 이하 png → `{fileName}` 반환 · 3MB / `.exe` → 400 | smoke | `curl -F file=@logo.png <API>/shop/:id/theme/asset` (edit-link 토큰 선발급) | ❌ W0 | ⬜ pending |
| R3 | 에디터 아코디언에서 브랜드/공지바/섹션 편집 후 draft 저장 | browser UAT | `diseno.tsx` 조작 → `GET /shop/:id/theme?draft=1` 응답에 확장 키 존재 | N/A | ⬜ pending |
| R4 | draft→publish 왕복 후 공개 페이지에 섹션 순서/토글 반영 | browser UAT + smoke | 공개 URL HTML 소스에서 섹션 DOM 순서 확인 | N/A | ⬜ pending |
| R4 | 확장 키 없는 기존 매장 공개 페이지 회귀 0 | smoke | 변경 전/후 공개 HTML diff (기존 store 대상) | N/A | ⬜ pending |
| R5 | `productCard.discountBadge=false` → 배지 미노출 | smoke + UAT | `curl /public/shop/:id/products` 에 `priceOrig` 필드 존재 확인 후 브라우저 | ❌ W0 (DTO 필드 신규) | ⬜ pending |
| R6 | `pageSize=999` 저장 → 48 clamp | unit | sanitize 스펙 케이스 | ❌ W0 | ⬜ pending |
| R6 | `catalog.pageSize=12` · `sort=price_asc` 반영 | smoke | `curl "/public/shop/:id/products?pageSize=12&sort=price_asc"` 개수/정렬 확인 | ❌ W0 (sort 신규) | ⬜ pending |
| R6 | `filters.price=false` → 가격 필터 UI 숨김 · `true`+구간 → 목록 좁힘(minPrice/maxPrice) | smoke | `curl "/public/shop/:id/products?minPrice=10000&maxPrice=30000"` 구간 확인 + 브라우저 UI 표시/숨김 | ❌ W0 (price 파라미터 신규) | ⬜ pending |
| R6 | `filters.color`/`filters.size` → 필터 UI 미렌더(예외, 저장만) | browser UAT | 토글 후 공개몰에 색상/사이즈 필터 없음 + 값 저장 확인 (variant 집계 부재로 확정 no-op) | N/A | ⬜ pending |
| R7 | 팝업 첫 방문 1회 · 재방문 미표시 | browser UAT | `sessionStorage` 키 확인 | N/A | ⬜ pending |
| R7 | `seoTitle` → `<title>` 반영 · `pixelId=null` → 스크립트 태그 없음 | smoke | `curl` 후 HTML grep `<title>` / `script id="meta-pixel"` | ❌ W0 | ⬜ pending |
| R8 | 신규 Pool/Client 0건 · ESLint 0 · 신규 테이블/컬럼 0 | automated grep | `grep -rn "new Pool(\|new Client(" <변경파일>` + `npx eslint <변경파일>` + `git diff --stat api-ventago/migrations/` (CHECK SQL 1개만) | ✓ | ⬜ pending |
| R9 | `rails` / `masonry` publish → 해당 뼈대 렌더 · `marquee`/`bento` 회귀 0 | browser UAT + smoke | `curl /public/shop/:id/theme` 의 `macrostructure` 확인 + 시각 확인 | N/A | ⬜ pending |
| R9 | `doc` 잔여 코드 0 | automated grep | `grep -rn "'doc'" tienda-app/src api-ventago/src/app/shop-public` 0건 | ✓ | ⬜ pending |
| R9 | `'doc'` / 알 수 없는 값 → `marquee` 강등 | unit | `sanitizeMacrostructure('doc') === 'marquee'` 및 `('foo') === 'marquee'` | ❌ W0 | ⬜ pending |
| R9 | 로컬 5432 / 운영 5434 `chk_store_theme_macro` 정의 동일(4값) | manual DB | 로컬 psql + 운영 `mcp-ssh` 로 `pg_get_constraintdef` 대조 | N/A | ⬜ pending |
| R9 | 구조 전환 후 되돌리면 비활성됐던 섹션 값 복귀 | browser UAT | rails→marquee 전환 왕복 후 carousel 설정 보존 확인 | N/A | ⬜ pending |
| R10 | reels `preload="none"` + poster 렌더 · autoplay 없음 | smoke | 공개 HTML grep `preload="none"` · `autoplay` 0건 | ❌ W0 | ⬜ pending |
| R10 | 21MB / `.mov` → 400 · poster 없는 item drop | unit + smoke | sanitize 스펙 케이스 + `curl` 업로드 | ❌ W0 | ⬜ pending |
| R11 | quiz 3문항 → 추천 3개(MATCH 배지 + 매칭 이유) 표시 | browser UAT | 공개 홈에서 배너 → 3문항 응답 → 결과 화면 확인 | N/A | ⬜ pending |
| R11 | quiz 진행 중 **신규 백엔드 엔드포인트 호출 0건** (기존 카탈로그 쿼리만) | browser UAT (네트워크 탭) | DevTools Network 에서 요청 URL 이 기존 카탈로그 엔드포인트뿐인지 확인 | N/A | ⬜ pending |
| R11 | 질문 5개 / 선택지 5개 저장 → 4개로 clamp | unit | sanitize 스펙 케이스 | ❌ W0 | ⬜ pending |
| R11 | `Ver catálogo completo` → 선택 필터가 적용된 카탈로그로 이동 | smoke | 이동 URL 의 쿼리 파라미터가 응답 매핑과 일치하는지 확인 | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `api-ventago/src/app/shop-public/store-theme.constants.spec.ts` — 신규. 확장 `sanitizeTokens()` / 신규 `sanitizeContent()` / 확장 `sanitizeMacrostructure()` 유닛 테스트. **이 모듈에 현재 스펙 파일 0개** — 이 Phase 검증의 핵심 자산.
- [ ] `api-ventago/src/app/shop-public/shop-catalog.service.spec.ts` — sort / showOutOfStock / pageSize clamp 매핑 테스트 (신규 로직 한정, 권장)
- [ ] `scripts/smoke-shop-theme.sh` — `curl` 기반 스모크 (테마 조회 / asset 업로드 거부 케이스 / 공개 HTML grep). tienda-app 에 테스트 프레임워크가 없으므로 재현 가능한 검증 수단 확보용 (권장, 강제 아님)
- [x] Framework install 불필요 — Jest 는 api-ventago 에 이미 존재. tienda-app 신규 프레임워크 도입은 **범위 밖**.

---

## Manual-Only Verifications

| Behavior | Req | Why Manual | Test Instructions |
|----------|-----|------------|-------------------|
| rails / masonry 시각 렌더 품질 | R9 | 레이아웃 품질은 자동 검증 불가 (스크롤 스냅·열 균형·행 lazy load 체감) | 각 macrostructure 로 publish 후 모바일/데스크톱 폭에서 공개 페이지 확인 |
| reels 탭 재생 동작 | R10 | 미디어 재생은 실제 브라우저 필요 (iOS Safari 인라인 정책 포함) | 초기 로드 시 네트워크 탭에 영상 바이트 0 확인 → 탭 후 재생 확인 |
| 에디터 아코디언 조작감 | R3 | UI 상호작용 | 섹션 ▲▼ 이동 · 토글 후 미리보기 반영 확인 |
| 기존 매장 무회귀 | R4/R8/R9 | 운영 데이터 필요 | 확장 키 없는 실제 store 의 공개 페이지를 변경 전/후 비교 |
| 운영 5434 마이그레이션 적용 | R9 | 운영 DB 접근 필요 (사용자 확인 필수 DDL) | SSH → `psql -p 5434 -d ventago --single-transaction -v ON_ERROR_STOP=1 -f <file>.sql` 후 제약 정의 대조 |
| 운영 nginx 업로드 상한 (20MB 영상) | R10 | 저장소에서 확인 불가 | 배포 후 20MB 영상 업로드 스모크 — 413 나오면 nginx `client_max_body_size` 조정 필요 |

---

## Validation Sign-Off

- [ ] All tasks have automated verify 또는 Wave 0 의존성 명시
- [ ] Sampling continuity: 자동 검증 없는 태스크 3개 연속 금지 (프런트 태스크는 smoke grep 로 대체)
- [ ] Wave 0 가 모든 ❌ 항목 커버
- [ ] watch-mode 플래그 없음
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` 설정

**Approval:** pending
