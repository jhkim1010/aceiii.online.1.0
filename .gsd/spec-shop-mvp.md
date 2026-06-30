# SPEC: shop.coolsistema.com — 공개 쇼핑몰 MVP

생성일: 2026-06-29
방향: 확장 ① (로드맵 `future proyect/00-expansion-strategy-roadmap.md`)

## 목표

서버의 제품(`products`)을 익명 방문자가 검색·열람하고 장바구니에 담아 MercadoPago로 결제하면, 그 주문이 기존 `online_orders` 파이프라인(재고 hold + POS mirror)으로 흘러들어가는 **공개 B2C 쇼핑몰 MVP**를 완성한다.

## 배경 및 컨텍스트

- **이미 있는 자산**: `online_orders`/`online_order_items` 테이블 + Phase 28 파이프라인(재고 hold·mirror), `@Public()` 데코레이터(`auth/decorators/public.decorator.ts`), MinIO 이미지, MP OAuth·webhook·refund.
- **없는 것 (신규 구축 필요)**:
  - MP **Checkout Pro(preference/init_point)** — 현재 MP는 QR·wallet만 있고 온라인 리디렉션 결제 없음.
  - 공개(비인증) **카탈로그 읽기 API** + **공개 주문 생성 API**.
  - 공개 트래픽용 **DB pool 격리** (운영 POS pool min10/max80 과 절대 공유 금지).
  - 공개 스토어프론트(Next.js, SSR/SEO) — 기존 `ventago-app`은 운영자용 인증 앱.
- **카탈로그 메타데이터 공백**: `products.description`이 varchar(255), slug·SEO·gender·material·공개여부 플래그 없음.

## 기술 스택

- 언어/프레임워크: NestJS 11 (백엔드), Next.js 13 (신규 shop 프론트)
- DB: PostgreSQL (Sequelize, `underscored: true`). 운영 PG10 / 로컬 PG15·18 호환 주의.
- Pool 라이브러리: Sequelize 내장 pool. **공개용 별도 연결 인스턴스(작은 pool) 신설** — 운영 pool 미공유.
- 결제: MercadoPago Checkout Pro (신규)
- ESLint: `ventago-app`은 warning=error (newline-before-return, lines-around-comment, no-unused-vars)

## 태스크 목록

### A. 백엔드 — 카탈로그 & 격리
- [x] TASK-1: `products` 메타데이터 마이그레이션 — `slug`(unique/store), `long_description text`, `gender`, `material`, `is_published_shop bool default false`, `seo_title`, `seo_description`. PG10/15 호환 SQL → `migrations/shop-mvp-product-metadata.sql` + `products.model.ts`. (로컬 적용 완료, 운영 적용 대기)
- [x] TASK-2: **공개 읽기 pool 격리** — read-only role(`shop_readonly`, 최소권한+세션 read-only+statement_timeout) + 별도 `pg.Pool`(max=15) provider. 운영 POS pool 무공유. 파일: `migrations/shop-mvp-readonly-role.sql`, `shop-public/shop-readonly-db.service.ts`, `shop-public/shop-public.module.ts`, app.module 연결, `.env.example`. (로컬 role 적용 + eslint 검증 대기)
- [x] TASK-3: 공개 카탈로그 API (`@Public()`) — `GET /public/shop/:storeId/products`(목록·필터 q/categoryId/gender·페이지 ≤50, window count), `/products/:slug`(상세, 404). `is_published_shop=TRUE`+store 격리. 60초 캐시. 읽기전용 pool 경유. 파일: `shop-public/shop-catalog.controller.ts` + `shop-catalog.service.ts` + 모듈 연결. **런타임 검증 완료** (store25 게시3개 노출 / store6 격리 빈배열 / 상세 OK, 2026-06-29).
- [~] TASK-4: 공개 검색 — MVP 는 `name ILIKE` 단순 검색으로 TASK-3 에 포함. (성능 필요 시 `tsvector`+GIN 인덱스로 업그레이드 — 후속)

### B. 백엔드 — 결제 & 주문
- [x] TASK-5: MP **Checkout Pro preference** 생성 — **PaymentProvider 추상화**(CoolPay 대비) + MercadoPago 어댑터. 기존 MP resolver/crypto/api-client 재사용, `POST /checkout/preferences` → `init_point` 반환. 파일: `payments/payment-provider.interface.ts`, `payments/mercadopago-checkout.provider.ts`, `payments/payments.module.ts`, `.env.example`. (런타임 검증은 TASK-6 주문생성과 함께)
- [x] TASK-6: 공개 주문 생성 API (`@Public()`) — `POST /public/shop/:storeId/checkout`. 게시상품 검증(가격은 DB 권위값, 클라 불신) → **`OnlineOrdersService.create()` 재사용**(channel=`webshop`, pending → 재고 hold 자동) → `PaymentProvider.createCheckout` → init_point. 파일: `shop-public/dto/shop-checkout.dto.ts`, `shop-order.service.ts`, `shop-order.controller.ts`, 모듈 연결. (로컬 mp_accounts 비어있어 결제단계 `MP_NO_ACCOUNT` 까지 검증 가능; init_point 는 MP 계정 연결 필요)
- [ ] TASK-7: MP webhook 확장 — 결제 승인 시 해당 `online_orders.payment_status` 갱신 + mirror 트리거(기존 `mp-webhook.service` 재사용/분기). 멱등 처리 필수 — 파일: `mercadopago/webhook/mp-webhook.service.ts`

### C. 프론트엔드 — shop 스토어프론트 (신규 Next.js)
- [ ] TASK-8: shop 앱 스캐폴드 + 목록/필터 페이지 (SSR, next/Image, 코드스플리팅)
- [ ] TASK-9: 상품 상세 + 장바구니(클라이언트 상태)
- [ ] TASK-10: 체크아웃 → 주문 API 호출 → MP `init_point` 리디렉션 → 결과(success/failure/pending) 페이지
- [ ] TASK-11: SEO(메타·OG·sitemap.xml·robots), 반응형, 로딩 스켈레톤

### D. 인프라 & 검증
- [ ] TASK-12: shop 서브도메인 라우팅 + Docker(멀티스테이지) + 이미지 CDN/프록시
- [ ] TASK-13: ESLint 검증 (`npx eslint . --fix`) — 오류 0
- [ ] TASK-14: PostgreSQL pool 안전 점검 — 공개 트래픽 부하 시 `pg_stat_activity` / Pool 모니터 로그로 운영 pool 무영향 확인
- [ ] TASK-15: 결제 e2e (MP sandbox) — 주문→결제→webhook→online_orders 갱신 검증

## 완료 기준

- ESLint 오류 0개
- 익명 사용자가 목록→상세→장바구니→MP결제→결과까지 end-to-end 완주
- 결제 승인이 webhook으로 `online_orders`에 반영(재고 hold→mirror)
- 부하 시 운영 POS pool 사용률 영향 없음 (격리 입증)
- `is_published_shop=true` 상품만 공개 노출 (멀티테넌트 store 격리 유지)

## 금지사항 / 주의사항

- **운영 pool(min10/max80) 공유 금지** — 공개 트래픽은 반드시 별도 연결.
- 공개 API는 절대 인증 데이터/타 store 데이터 노출 금지 (`store_id` + `is_published_shop` 이중 필터).
- 기존 `online_orders` 파이프라인·MP QR/wallet 코드 변경 최소화 (재사용 우선, 분기로 확장).
- **별개 기존 버그**: `products.routing_template` 컬럼 미존재 500 에러(2026-06-29 로그) — 본 스펙 범위 밖, 별도 처리.
- 결제 추상화: TASK-5는 향후 CoolPay를 위해 `PaymentProvider` 인터페이스 형태로 얇게 감싸 구현(메모리 `project_expansion_sequencing`).

## 예상 개발 시간 (1인 기준)

| 블록 | 태스크 | 추정 |
|---|---|---|
| A 카탈로그·격리 | 1–4 | 3–4일 |
| B 결제·주문 | 5–7 | 4–6일 (MP Checkout Pro 신규가 최대 변수) |
| C 프론트엔드 | 8–11 | 7–10일 |
| D 인프라·검증 | 12–15 | 4–5일 |
| 통합·버퍼 | — | 2–3일 |
| **합계** | | **약 20–28 작업일 ≈ 4–6주** |

- 얇은 MVP(단일 store, 기본 검색, MP만, 폴리시 최소)로 줄이면 **~2.5–3주** 가능.
- 최대 리스크: ① MP Checkout Pro 신규 연동(샌드박스 테스트 포함), ② pool 격리 검증.
