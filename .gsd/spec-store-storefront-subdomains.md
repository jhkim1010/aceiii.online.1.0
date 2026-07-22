# SPEC: 공개몰 매장별 서브도메인 자동화 (Phase 2)
생성일: 2026-07-22
관련 스킬: gsd · 선행: Phase 1(store_themes 테마/활성토글 — 배포됨, [[store-homepage-themes-phase1]])

## 목표
매장이 admin 에서 공개몰을 ON 하고 hallmark 템플릿을 고르면, 운영자 개입 없이 `<slug>.coolsistema.com`(예: `mana.coolsistema.com`)으로 그 매장 상품만 자동 공개되게 한다. 와일드카드 서브도메인 멀티테넌시 + slug 라우팅 + tienda-app 운영 배포.

## 배경 및 컨텍스트
- Phase 1 완료: `store_themes(enabled, published_tokens…)` + 공개 조회(readonly+캐시) + 소유자 저장/발행(매직링크) + 관리자 활성 토글/카드. 상품 격리(`WHERE store_id=$1 AND is_published_shop=TRUE`)·hallmark 테마는 이미 동작.
- ★현황(2026-07-22 서버 실측): 공개몰(tienda-app, 포트 3060)이 운영 미배포 — nginx vhost 없음, 3060 미실행, `shop.coolsistema.com` DNS 없음. 운영 도메인=app/new(→5001 관리자), newapi(→5002 API). DNS=GoDaddy(domaincontrol.com). 와일드카드/정규식 vhost 없음.
- `stores` 컬럼: name, alias_name, logo_url — **slug 없음**(신규 추가 필요). 운영 coolsistema=store id 6(게시상품 0 — 별건).
- tienda-app 라우트: `/[storeId]` 숫자만. 도메인=aceiii.online.1.0 repo(root)의 tienda-app.

## 기술 스택
- 프론트: Next.js 13 pages router(tienda-app, root repo). 배포=`next start -p 3060`.
- 백엔드: NestJS(api-ventago). 공개 라우트 `@Public()` + ShopReadonlyDbService.
- 인프라: nginx(정규식 server_name), Let's Encrypt(DNS-01 GoDaddy 와일드카드), GoDaddy DNS.
- DB: PostgreSQL. 마이그=`api-ventago/migrations/*.sql` 수기. slug 는 stores 테이블(운영=coolsistema 소유).

## 데이터 모델
```sql
-- stores.slug: 공개몰 서브도메인/URL 식별자 (고유, 소문자 영숫자·하이픈)
ALTER TABLE stores ADD COLUMN IF NOT EXISTS slug VARCHAR(63);
CREATE UNIQUE INDEX IF NOT EXISTS uq_stores_slug ON stores (slug) WHERE slug IS NOT NULL;
-- 백필: 기존 매장 slug = name 정규화(중복 시 -id 접미). 운영은 수기 검토 권장.
```
- 예약어 블록리스트(코드 상수): api, app, new, newapi, minio, apiminio, deploy, sync, portainer, cooldb, invoice, manager, www, admin, shop, tienda, static, assets, mail 등.
- slug 규칙: `^[a-z0-9](?:[a-z0-9-]{1,61}[a-z0-9])?$`, 소문자화, 예약어·중복 거부.

## 태스크 목록

### A. 백엔드 (api-ventago)
- [ ] TASK-1: 마이그 `2026-07-DD-stores-slug.sql` — slug 컬럼 + 유니크 인덱스(+선택 백필).
- [ ] TASK-2: 공개 라우트 `GET /public/shop/by-slug/:slug` → { storeId } (readonly pool, 캐시). slug 정규화 후 조회, 없으면 404.
- [ ] TASK-3: 소유자 slug 설정 — `GET/PUT /shop/:storeId/slug`(AuthGuard jwt + assertOwner). 예약어/형식/중복 검증(422). store-theme-admin 패턴 재사용.
- [ ] TASK-4: 예약어·slug 검증 유틸(`store-slug.util.ts`, 순수 함수 — 단위 테스트 가능).

### B. 스토어프론트 (tienda-app)
- [ ] TASK-5: `services/shop-api.ts` — `resolveSlug(slug)`; slug→storeId.
- [ ] TASK-6: 서브도메인 라우팅 — `getServerSideProps`에서 `req.headers.host` 의 서브도메인 추출 → by-slug 해석 → 기존 스토어프론트 렌더(활성/enabled 게이트 유지). `pages/index.tsx`(루트 도메인 진입) 또는 미들웨어에서 처리. 숫자 `/[storeId]` 유지.
- [ ] TASK-7: (선택) 경로형 fallback `/t/[slug]` 도 지원(서브도메인 미설정 환경/미리보기용).

### C. 인프라/배포 (일회성 플랫폼 세팅)
- [ ] TASK-8: GoDaddy `*.coolsistema.com` A → 62.72.7.245 (와일드카드 DNS). 예약 서브도메인은 명시 레코드 우선.
- [ ] TASK-9: 와일드카드 SSL — certbot DNS-01(GoDaddy) `*.coolsistema.com` 발급 + 자동갱신. (대안: 매장 ON 시 서브도메인별 HTTP-01 자동발급 훅.)
- [ ] TASK-10: nginx vhost — `server_name ~^(?<sub>[a-z0-9-]+)\.coolsistema\.com$;` → `proxy_pass http://127.0.0.1:3060;` (+ Host/X-Forwarded 전달). 기존 명시 vhost(app/new/newapi 등)가 우선 매칭되도록 배치.
- [ ] TASK-11: tienda-app 운영 실행 — pm2 또는 docker(`next build && next start -p 3060`), 재부팅 생존. Jenkins/deploy 파이프라인에 tienda-app 빌드·기동 추가.

### D. 관리자 (ventago-app)
- [ ] TASK-12: 활성 카드(StorefrontDesignCard)에 slug 입력/검증 + 공개 URL(`https://<slug>.coolsistema.com`) 표시·복사. slug 미설정 시 ON 불가 안내.

### E. 검증
- [ ] TASK-13: api eslint/tsc build, tienda tsc/lint (러너 theme-verify 확장), DI 부팅(theme-di-boot).
- [ ] TASK-14: E2E — 임시 slug 로 `curl -H "Host: <slug>.coolsistema.com" http://127.0.0.1:3060/` → 해당 매장 렌더, 예약어/미존재 slug → 404, 비활성(enabled=false) → 404.
- [ ] TASK-15: pool 안전 — by-slug 조회 readonly+캐시, 공개 라우트 캐시헤더.

## 완료 기준
- mana 매장: admin ON + slug=mana + 템플릿 선택 → `mana.coolsistema.com` 이 mana 상품만 hallmark 테마로 렌더(운영자 개입 0).
- 예약어/중복 slug 거부, 미존재·비활성 매장 404.
- 새 매장 기본 비활성(Phase 1 정책) 유지 — 결제/ON 후에만 서브도메인 공개.
- ESLint/tsc 0, DI 부팅 정상, 공개 조회 pool 무영향(캐시헤더 존재).

## 금지사항 / 주의사항
- 예약/시스템 서브도메인(api/app/new/newapi/minio/deploy/sync/portainer/cooldb/invoice/manager 등) slug 취득 절대 금지 — 블록리스트 하드코딩.
- 와일드카드 nginx 가 기존 명시 vhost 를 가로채지 않도록 우선순위/정규식 범위 주의(정확 매칭 vhost 먼저).
- GoDaddy API 키를 서버에 둘 경우 권한 최소화·시크릿 관리(gitignore). 대안 HTTP-01 경로도 문서화.
- 상품 격리·enabled 게이트는 Phase 1 로직 재사용, 재구현 금지.
- 마이그 로컬(5432)→검증→운영(5434) 승인 게이트. slug 백필은 운영 수기 검토.
- 주석 한국어 / 함수·변수명 영어 / async try-catch.

## 로드맵 메모
- 이후: 커스텀 도메인(매장 자체 도메인 CNAME→플랫폼) + 자동 SSL, 공개몰 SEO(sitemap/OG), slug 변경 시 301.
