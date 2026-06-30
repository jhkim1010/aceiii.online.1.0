# SPEC: Phase 51 — Public Storefront (포인터)

생성일: 2026-06-29

> 정식 스펙: `.planning/phases/51-public-storefront/51-CONTEXT.md` + `51-SPEC.md`
> 원천 스펙(상세): `.gsd/spec-shop-mvp.md`, `.gsd/spec-tienda-app.md`

## 요약

- **방향 ①** 공개몰 shop.coolsistema.com.
- **완료(✅)**: 카탈로그 백엔드+읽기격리 pool / 결제·체크아웃(PaymentProvider+MP Checkout) / 카테고리 통일(global_categories) / 단일 HTML 스토어프론트 / tienda-app 스캐폴드+카탈로그홈.
- **남음(⬜)**: MP 웹훅(결제승인→주문), tienda-app 정식 페이지(상세/장바구니/결과/Probar)+배포, 운영 마이그레이션, 부하·결제 e2e·SEO 검증.
- **불변 규약**: 운영 POS pool 격리, 결제는 PaymentProvider 경유, 카테고리는 global_categories.
