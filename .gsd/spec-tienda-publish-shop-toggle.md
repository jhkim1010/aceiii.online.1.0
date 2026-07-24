# SPEC: Tienda Online 상품별 web 노출(is_published_shop) 토글
생성일: 2026-07-24

## 목표
자체 Tienda Online(공개몰)이 활성화된 매장에서, 상품(código madre)별로 웹 노출 여부를
화면에서 켜고 끌 수 있게 한다. 현재는 읽기(공개 카탈로그)만 구현되어 있고 쓰기 경로가 0개.

## 배경 및 컨텍스트
- `products.is_published_shop` (boolean NOT NULL default false) — 컬럼은 로컬/운영 모두 존재. **마이그레이션 불필요.**
- 공개 카탈로그(`shop-catalog.service.ts`)는 `is_published_shop=TRUE` 필터. 상세 페이지는 `slug` 필수
  → **게시 ON 시 slug 없으면 자동 생성 필요** (`slugify(name)-{id}`, store 단위 unique 인덱스 존재).
- coolsistema 8개 madre는 shop-mvp 당시 SQL 시드 — UI 는 어느 매장에도 없음.
- tienda 활성 여부: `GET /shop/{storeId}/theme/settings` → `{ enabled }` (front: `storeThemeService.getStatus`).
- `updateProducts()` 는 DTO 스프레드로 저장 → DTO 필드 추가만으로 단건 저장 경로 완성.
- POST /products payload 는 product state 스프레드 → create DTO 에도 필드 필요 (forbidNonWhitelisted 400 방지).

## 기술 스택
- 백엔드: NestJS 11 + Sequelize (api-ventago)
- 프론트: Next.js 13 + MUI (ventago-app), SWR 훅 패턴 (src/hooks/api/)
- DB: PostgreSQL — Sequelize pool min10/max80. **신규 쿼리는 모델/`sequelize.query` 사용 → pool 자동 반환, 신규 connect 없음**
- ESLint: 프론트 warning=error (newline-before-return, lines-around-comment, no-unused-vars)

## 태스크 목록
- [x] TASK-1: DTO 필드 추가 — `isPublishedShop?: boolean` (create/update) + `BulkPublishShopDto` — 파일: api-ventago/src/app/products/dto/create-products.dto.ts, updated-products.dto.ts
- [x] TASK-2: `products.service.ts` — ① updateProducts/create: 게시 ON & slug 없으면 slug 생성 ② 신규 `bulkSetPublishedShop()` — 단일 UPDATE(store 격리) + slug backfill 단일 UPDATE (총 2쿼리, pool 안전)
- [x] TASK-3: `products.controller.ts` — `PUT /products/publish-shop` (admin/superadmin/gerente, storeId 스코프, @Put(':id') 보다 앞에 선언)
- [x] TASK-4: `productStock.service.ts` findByParentFlag(parent=false) + inventory-by-date 2종 parent 응답에 `isPublishedShop` 포함
- [x] TASK-5: 신규 `src/hooks/api/useShopStatus.ts` — SWR, `/shop/{storeId}/theme/settings`
- [x] TASK-6: `BasicDataCard.tsx` — tienda 활성 시 'Tienda Web' ToggleChip. 신규상품=POST payload, 기존 madre=즉시 PUT publish-shop (재입고 flow 는 parent PUT 안 하므로)
- [x] TASK-7: `DataConfig.tsx` — `columnsParentWithWeb(onToggleWeb)` 팩토리로 Web 컬럼(아이콘 토글) 추가
- [x] TASK-8: `ProductParentList.tsx` — Web 컬럼 클릭 토글(낙관적 갱신+실패 원복). ※일괄 버튼은 checkboxSelection=false(행클릭=폼채움 UX)와 충돌해 제외 — 후속 후보
- [x] TASK-9: 백엔드 prettier 통과. 프론트 ESLint 는 VM 프로세스 강제종료로 미실행 → 규칙 3종 수동검토 통과, Jenkins 빌드가 최종 게이트 (기존 세션 관례)
- [x] TASK-10: 리뷰 — pool 체크리스트 통과(신규 connect/Pool 없음, bulk 2쿼리), error 로그 깨끗

## 완료 기준
- ESLint 오류 0개
- STOCK 매장에서 tienda 활성 시: 상품 폼과 madre 목록에서 웹 게시 토글 가능
- 게시된 상품이 slug 를 갖고 공개 카탈로그/상세에 노출
- tienda 비활성 매장에서는 UI 미노출 (기존 화면 무변화)

## 금지사항 / 주의사항
- 상품 create/update 의 기존 필드·동작 무변경 (특히 publishMarketplace / product_visibility 로직)
- 신규 Pool 생성 금지 — 기존 Sequelize 인스턴스만 사용
- 루프 내 per-row UPDATE 금지 — bulk 는 단일 UPDATE
- shop 카탈로그 캐시는 TTL 로 자연 만료 — 캐시 무효화 로직 추가하지 않음 (범위 밖)
- commit/push 는 사용자가 Mac 에서 직접 (2026-07-23 워크플로우 규칙)
