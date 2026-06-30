# SPEC: Phase 51 — Public Storefront (shop.coolsistema.com)
생성일: 2026-06-29
배경: `51-CONTEXT.md`. 원천 스펙: `.gsd/spec-shop-mvp.md`, `.gsd/spec-tienda-app.md`.

## 목표

익명 방문자가 매장 상품을 검색·열람하고 MercadoPago 로 결제하면, 그 주문이 기존
online_orders 파이프라인(재고 hold + POS mirror)으로 흐르는 공개몰을 완성·배포한다.
공개 트래픽은 운영 POS pool 과 격리한다.

## 기술 스택

- 백엔드: NestJS 11 (`api-ventago/src/app/shop-public`, `payments`) — 읽기 전용 격리 pg.Pool
- 프론트: Next.js 13 워크스페이스 `tienda-app/`(포트 3060), SSR/SEO
- 결제: `PaymentProvider` → MercadoPago Checkout Pro
- 카테고리: 공유데이터 `global_categories`

## 태스크 목록 (Waves)

### Wave 51-01 — 카탈로그 백엔드 + 읽기 격리 ✅ 완료
- [x] products 메타 확장(slug/long_description/gender/material/is_published_shop/seo_*) 마이그레이션+모델
- [x] 읽기 전용 role `shop_readonly`(최소권한+read-only+timeout) + 별도 pg.Pool(max=15)
- [x] 공개 카탈로그 API(목록/상세/검색 ILIKE) + 60초 캐시 (런타임 검증)

### Wave 51-02 — 결제·주문 ✅ 완료(웹훅 제외)
- [x] `PaymentProvider` 추상화 + MercadoPago Checkout Pro 어댑터
- [x] 공개 체크아웃(게시상품 DB가격 검증 → OnlineOrdersService.create 재사용 → init_point)
- [x] 검증: 주문 생성·재고 hold·MP_NO_ACCOUNT(로컬 MP 미연결) 정상

### Wave 51-03 — 카테고리 통일 ✅ 완료
- [x] 기존 global_categories 에 이름 병합(대소문자/악센트) + categories.global_category_id backfill
- [x] 공개 API globalCategory 필터 + /categories 내비 (검증)

### Wave 51-04 — 단일 HTML 스토어프론트(MVP) ✅ 완료
- [x] 백엔드 서빙 `GET /:storeId/store` — 카탈로그/검색/장바구니/체크아웃 + 상품별 Probar(Phase 49 연계)

### Wave 51-05 — MP 웹훅(결제 루프 마감) ⬜
- [ ] webhook 확장: 결제 승인 → `online_orders.payment_status='paid'` + mirror 트리거, 멱등
- [ ] source=shop 분기(QR 인텐트와 구분), 로컬 검증 한계(MP 가 localhost 못 닿음 → 스테이징/터널)

### Wave 51-06 — tienda-app 정식 프론트 (spec-tienda-app T1~T11) ⬜ 진행중
- [x] T1 워크스페이스 스캐폴드 + 루트 workspaces/scripts
- [x] T2 API 클라이언트 + 타입
- [x] T4(부분) 카탈로그 홈(SSR) + 루트 리디렉트
- [ ] T3 레이아웃/Header 컴포넌트화, T5 상품 상세(SSR+OG), T6 장바구니+체크아웃(Context), T7 결제 결과 라우트(success/failure/pending), T8 Probar 컴포넌트(from-product)
- [ ] T10 lint 0 + 로컬 e2e + Lighthouse, T11 단일 HTML deprecate

### Wave 51-07 — 배포 ⬜
- [ ] tienda-app Dockerfile(멀티스테이지, output standalone)+docker-compose, shop 서브도메인, Jenkins/CI
- [ ] 운영 DB 마이그레이션 적용(메타/role/카테고리, 사용자 확인 후)

### Wave 51-08 — 검증 ⬜
- [ ] 공개 트래픽 부하 시 운영 POS pool 무영향(pg_stat_activity)
- [ ] 결제 e2e(MP sandbox 계정 연결 후 init_point→webhook→paid)
- [ ] SEO(메타/OG/sitemap) 소스 확인

## 완료 기준

- 익명 방문자: 목록→상세→장바구니→MP결제→결과 완주
- 결제 승인이 webhook 으로 online_orders 반영(재고 hold→mirror)
- 부하 시 운영 POS pool 무영향(격리 입증)
- shop.coolsistema.com 독립 배포

## 금지사항 / 주의사항

- 운영 POS pool 공유 금지. 공개 API 는 store_id+is_published_shop 이중 필터.
- 결제는 PaymentProvider 경유(직접 MP 호출 산재 금지) — CoolPay(50) 대비.
- 카테고리는 global_categories 사용(새 테이블 금지).
- pageSize ≤ 50, 이미지 next/Image, 마이그레이션 PG10/15 호환.
