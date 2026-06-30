# SPEC: tienda-app — 공개몰 프론트엔드 워크스페이스 승격

생성일: 2026-06-29
배경: 단일 HTML 스토어프론트(MVP)를 정식 Next.js 워크스페이스로 승격.
원칙(결정됨): **백엔드는 api-ventago 유지**(주문/재고/MP/Minio/공유데이터 재사용), **프론트만 분리**.
별도 repo 아님 → **모노레포 내 새 워크스페이스** `tienda-app/`.

## 목표

`shop.coolsistema.com` 으로 배포되는 독립 Next.js 공개몰 앱을 만든다. 기존 공개 API
(`/api/public/shop/...`)를 그대로 호출하며, SSR/SEO·코드스플리팅·독립 배포를 갖춘다.

## 배경 및 컨텍스트

- 모노레포 workspaces: `api-ventago, ventago-app, print-agent, zebra-agent, vw-agent` → **`tienda-app` 추가**.
- 기준 앱 `ventago-app`: Next.js 13.3.2 (Pages Router) + React 18.2 + MUI 5, dev 포트 3050, Dockerfile + docker-compose 보유.
- API host 패턴: dev `http://localhost:5002/api`, prod `https://newapi.coolsistema.com/api`.
- 이미 동작하는 공개 API: `GET :storeId/store`(HTML, 승격 후 폐기 예정), `GET :storeId/categories`, `GET :storeId/products`(+q/globalCategoryId), `GET :storeId/products/:slug`, `POST :storeId/checkout`, `POST /tryon/from-product/:storeId/:productId`.
- MP back_urls 가 `SHOP_FRONTEND_URL/checkout/{success|failure|pending}` 로 설정됨 → 그 라우트 필요.
- npm workspaces 호이스팅 주의: next.config alias 는 `require.resolve` 사용(루트 node_modules 하드코딩 금지).

## 기술 스택

- Next.js 13 (Pages Router — ventago-app 과 일관). 대안 App Router 는 비채택(일관성 우선).
- React 18, TypeScript.
- 스타일: 경량 CSS Modules + 기존 테마(다크 네이비 #1a1a2e / 골드 #f5a623). MUI 미도입(공개몰 번들 경량화). 추후 필요 시 도입.
- 데이터: SSR(getServerSideProps)로 카탈로그/상세(SEO 메타·OG), 클라이언트는 fetch 래퍼.
- 상태: 장바구니는 클라이언트(useReducer + 메모리; localStorage 금지 규약 아니지만 MVP 는 메모리).
- ESLint/Prettier: ventago-app 규약 준수(newline-before-return 등).

## 태스크 목록

- [ ] T1: 워크스페이스 스캐폴드 — `tienda-app/`(package.json name `tienda-ventago`, dev 포트 3060), tsconfig, next.config.js(require.resolve alias), .env.example(NEXT_PUBLIC_API_HOST), 루트 workspaces + scripts(dev:tienda, build:tienda) 추가
- [ ] T2: API 클라이언트 — `src/services/shop-api.ts`(NEXT_PUBLIC_API_HOST 기반 fetch, 에러 핸들링), 타입(ShopProduct/Category/CheckoutResult)
- [ ] T3: 레이아웃/테마 — Header(매장명·장바구니), 글로벌 CSS(테마 변수), 반응형
- [ ] T4: 카탈로그 페이지 `pages/[storeId]/index.tsx` — getServerSideProps(목록+카테고리), 칩 필터·검색·그리드, next/Image, SEO 메타
- [ ] T5: 상품 상세 `pages/[storeId]/producto/[slug].tsx` — getServerSideProps(상세), OG/메타, 갤러리(imageUrls), 장바구니 담기
- [ ] T6: 장바구니 + 체크아웃 — CartContext(useMemo value), 체크아웃 폼 → POST /checkout → initPoint 리디렉션 / MP_NO_ACCOUNT 처리
- [ ] T7: 결제 결과 라우트 — `pages/checkout/{success,failure,pending}.tsx` (MP back_urls 대응)
- [ ] T8: 가상 피팅 컴포넌트 — 상품 상세/카드의 "Probar" → 사진 업로드 → from-product → 결과 표시(사진 미저장 안내)
- [ ] T9: 배포 — Dockerfile(멀티스테이지), docker-compose, shop 서브도메인, Jenkins front job 패턴(또는 신규 job), push-both/CI 통합
- [ ] T10: 검증 — `npm run lint --workspace=tienda-app` 0, 로컬 `npm run dev:tienda` 로 목록→상세→장바구니→체크아웃(MP_NO_ACCOUNT)→피팅 e2e, Lighthouse(SEO/perf) 스폿
- [ ] T11: 정리 — 백엔드 단일 HTML 스토어프론트(`shop-storefront.*`)는 tienda-app 검증 후 deprecate 표기/제거

## 완료 기준

- `npm run dev:tienda` 로 공개몰이 뜨고 기존 API 로 목록→상세→장바구니→체크아웃→피팅 완주
- SSR 로 상품/목록에 SEO 메타·OG 렌더(소스 보기로 확인)
- ESLint 0, 운영 POS pool 무영향(공개 API 는 기존 읽기 전용 pool 경유)
- 독립 배포(shop.coolsistema.com) 가능한 Docker/CI 구성

## 금지사항 / 주의사항

- **백엔드를 새로 만들지 말 것** — 모든 데이터는 기존 `/api/public/shop/...` 호출.
- localStorage 등 브라우저 스토리지 남용 금지(장바구니는 메모리/Context).
- 운영 pool 공유 금지(이미 백엔드 격리됨 — 프론트는 API만 호출).
- pageSize ≤ 50, 이미지 next/Image, 참조데이터 캐시는 백엔드 60초가 처리.
- npm workspaces alias 는 require.resolve(하드코딩 금지).

## 비고

- 샌드박스에서 dev 서버 실행/검증 불가 → 스캐폴드·코드는 제가 작성, 로컬 실행·Lighthouse 는 사용자가 수행.
- 승격 동안 백엔드 단일 HTML(`:storeId/store`)은 폴백으로 유지, T11 에서 정리.
