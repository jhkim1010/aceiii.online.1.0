# Phase 51 — Public Storefront (shop.coolsistema.com) (CONTEXT)

> **유형**: 신규 기능 (확장 로드맵 방향 ①)
> **선행**: online_orders 백본(Phase 27/28), MercadoPago(Phase 29), 공유데이터(global_categories)
> **연계**: Phase 49(AI Try-On, 상품 입어보기), Phase 50(CoolPay, 향후 결제)
> **관련 문서**: `.gsd/spec-shop-mvp.md`, `.gsd/spec-tienda-app.md`, `future proyect/00-expansion-strategy-roadmap.md`(방향 ①)
> **작성일**: 2026-06-29
> **번호 주의**: 46~48=멀티플랫폼 싱크 예약, 49=AI, 50=CoolPay → Public Storefront = **51**.

---

## 1. 왜 이 phase 인가 (다층 분석)

- **표면**: 서버의 모든 제품을 방문자가 검색·구매하는 공개몰(shop.coolsistema.com).
- **구조적 원인**: 기존 Ventago 는 *내부 운영자(POS/ERP)* 용 인증 시스템. 익명 공개 트래픽이라는 정반대 접근 패턴이 들어설 자리가 없고, 운영 DB pool(min10/max80)을 공유하면 공개 트래픽이 POS 를 멈출 수 있다.
- **본질**: "페이지 추가"가 아니라 **읽기 위주·고트래픽·익명·SEO 친화**의 *두 번째 종(種)* 시스템을 *같은 데이터* 위에 얹는 일. 핵심은 **읽기 경로(공개)와 쓰기 경로(운영)의 분리**.

## 2. 이미 구현된 것 (이번 세션, ✅)

- **카탈로그 백엔드** (`api-ventago/src/app/shop-public/`):
  - products 메타 확장(slug/long_description/gender/material/is_published_shop/seo_*) — `migrations/shop-mvp-product-metadata.sql`
  - **읽기 전용 격리 pool**(`shop_readonly` role, 최소권한+read-only+statement_timeout, 별도 pg.Pool max=15) — 운영 POS pool 무공유 (검증됨)
  - 공개 API: `GET /api/public/shop/:storeId/products`(필터 q/categoryId/globalCategoryId), `/products/:slug`, `/categories`. is_published_shop+store 격리, 60초 캐시. (런타임 검증됨)
- **결제·주문** (`shop-public/` + `payments/`):
  - `PaymentProvider` 추상화 + MercadoPago Checkout Pro 어댑터(CoolPay 대비)
  - 공개 체크아웃 `POST /:storeId/checkout` — 게시상품 검증(DB 가격), `OnlineOrdersService.create` 재사용(webshop, pending+재고hold), preference→init_point. (검증: 주문/재고/MP_NO_ACCOUNT까지)
- **카테고리 통일** — 기존 공유데이터 `global_categories` 에 이름 병합 + `categories.global_category_id` 매핑(`migrations/shop-category-unify.sql`). (검증됨)
- **스토어프론트(MVP)**: 백엔드가 서빙하는 단일 HTML `GET /:storeId/store`(카탈로그·검색·장바구니·체크아웃 + 상품별 Probar). 즉시 테스트용.
- **tienda-app 워크스페이스(승격 시작)**: Next.js 13 워크스페이스 스캐폴드 + API 클라이언트 + 카탈로그 홈(SSR). (`tienda-app/`, 포트 3060)

## 3. 아키텍처 결정

- **pool 격리 1순위**: 공개 읽기는 운영 POS pool 과 분리(read-only role + 별도 pool). 타협 금지.
- **결제 추상화**: 모든 결제는 `PaymentProvider` 경유 → 향후 CoolPay(Phase 50) 어댑터 교체.
- **카테고리**: 새 테이블 금지, 기존 공유데이터 시스템(global_categories) 사용.
- **프론트 분리**: 백엔드는 api-ventago 유지, 프론트만 tienda-app 워크스페이스(별도 repo 아님).

## 4. 남은 것 (요약)

- MP 웹훅(결제 승인 → online_orders.payment_status + mirror)
- tienda-app 정식 페이지(상세/장바구니/체크아웃/결과/Probar) + 배포(서브도메인·Docker·CI)
- 운영 DB 마이그레이션 적용(확인 후), 검색 고도화(tsvector/GIN, 선택)

## 5. 주의

- 공개 API 가 인증/타store 데이터 노출 금지(store_id + is_published_shop 이중 필터).
- 단일 HTML 은 MVP 폴백 — tienda-app 검증 후 deprecate.
- 운영 마이그레이션은 PG10/PG15 호환·사용자 확인 후 적용.
