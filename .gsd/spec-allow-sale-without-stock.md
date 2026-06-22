# SPEC: 재고 없는 상품 판매 허용 여부 (매장별 설정)

생성일: 2026-06-22

## 목표

매장(store) 관리자가 "재고가 없는(0 이하) 상품의 판매를 허용할지" 여부를 admin 설정에서 직접 토글할 수 있게 한다. 설정 OFF 시 판매 시점에 재고 0 이하인 상품은 판매를 차단한다.

## 배경 및 컨텍스트

- 현재는 재고 검증이 전혀 없어 항상 판매 허용 (재고 음수 가능). 이는 의도된 기본 동작이며 유지가 기본값.
- 차단 기준(사용자 확정): 설정 OFF일 때 **재고 0 이하면 차단** (요청 수량 차감 후 음수가 되는 게 아니라, 차감 전 현재 stock ≤ 0 이면 차단).
- 설정 단위(사용자 확정): **store 단위** boolean 1개.
- 권위 있는 재고: `products.stock` 컬럼 (판매 시 sales-create.service.ts:608 에서 직접 차감).

### 관련 파일 (탐색 완료)

- 판매 재고 차감: `api-ventago/src/app/sales/sales-create.service.ts:606-618` (`product.stock -= item.quantity`)
- store 조회 이미 존재: 같은 파일 201줄 `Store.findByPk(storeId, { attributes: ['timezone'] })` — attributes 에 신규 컬럼만 추가하면 추가 쿼리 없음 (pool 절약)
- Store 모델: `api-ventago/src/app/store/store.model.ts:71-72` (useVariants BOOLEAN @Column 패턴)
- Store 수정 API: `store.controller.ts` PUT /store/:id (FormData boolean 처리 193-201 기존재)
- Admin UI 토글: `ventago-app/src/views/admin/stores/list/components/ModalStore.tsx:299-319` (useVariants Switch 패턴), FormData append 115줄, getInitialValues 32-51줄
- 마이그레이션 패턴: `api-ventago/migrations/add-use-variants-to-stores.sql`

## 기술 스택

- 백엔드: NestJS 11 + Sequelize (underscored:true → DB snake_case). PostgreSQL 10(운영)/15(dev).
- 프론트: Next.js 13 + MUI 5 + React Hook Form. ESLint 빌드 차단(Warning=Error).
- DB: pool min=10/max=80. **신규 store 조회 추가 금지** — 기존 201줄 findByPk attributes 에 컬럼 추가로 해결.

## 명명 결정

- DB 컬럼: `allow_sale_without_stock` BOOLEAN NOT NULL DEFAULT TRUE
- 모델 속성: `allowSaleWithoutStock`
- **기본값 TRUE** = 현재 동작(항상 허용) 유지 → 기존 매장 판매 안 막힘. 매장이 명시적으로 OFF 해야 차단 시작.
- (Explore 가 제안한 allowNegativeStock 은 의미 반대라 채택 안 함)

## 태스크 목록

- [x] TASK-1: 마이그레이션 SQL — `migrations/add-allow-sale-without-stock-to-stores.sql` 작성 완료 (idempotent, DEFAULT TRUE, COMMENT + 검증). 운영/dev 적용은 사용자 확인 후 대기.
- [x] TASK-2: Store 모델 — `store.model.ts` `allowSaleWithoutStock` BOOLEAN @Column 추가 (field: allow_sale_without_stock, default true).
- [x] TASK-3: 판매 검증 로직 — store 조회를 processSaleItems 호출 앞으로 이동(쿼리 순증 0) + attributes 에 allowSaleWithoutStock 추가. processSaleItems(items, allowSaleWithoutStock) 시그니처 확장, 재고차감 직전 `!allowSaleWithoutStock && product.stock <= 0` 이면 BadRequestException (ES 메시지). 제네릭 제외.
- [x] TASK-4: store 수정 API — `store.controller.ts` FormData boolean 변환에 allowSaleWithoutStock 추가 (useVariants 패턴).
- [x] TASK-5: Admin UI 토글 — `ModalStore.tsx` Switch "Permitir venta sin stock" + 캡션 + FormData append + getInitialValues 기본값 true (2곳).
- [x] TASK-6: ESLint — 변경분 새 에러/경고 0개 (검출된 것은 전부 pre-existing `body:any` no-unsafe-* 및 exhaustive-deps warning). sandbox OOM 회피 위해 파일별 검사.
- [x] TASK-7: pool 안전 점검 — Store.findByPk 순증 0 (이동만), 재고 검증은 메모리 product.stock 비교 (쿼리 0), 신규 connection/transaction 없음.

## 잔여 (사용자 확인 필요)
- 마이그레이션 운영(PG10) + dev 적용 (DDL — 사용자 confirm 후). DEFAULT TRUE 라 lock 짧음.
- 빌드/배포는 push-both.sh → Jenkins.

## 완료 기준

- ESLint 오류 0개
- 신규 DB 쿼리/connection 증가 0 (pool 영향 없음)
- 기본값 TRUE 로 기존 매장 동작 불변 (회귀 없음)
- 설정 OFF + 재고 ≤ 0 일 때만 판매 차단, 그 외 전부 기존대로 허용
- 제네릭 상품(isGeneric)은 재고 개념 없으므로 항상 허용 (검증 제외)

## 금지사항 / 주의사항

- 재고 차단 기본 동작을 바꾸지 말 것 (기본 TRUE=허용). [[feedback-ventago-stock-never-blocks-sale]] 정신 유지 — 매장이 명시 OFF 한 경우에만 차단.
- 판매 생성 경로에 store 조회용 쿼리를 새로 추가하지 말 것 (기존 findByPk attributes 확장).
- migrations 운영(PG10) 적용은 사용자 확인 필수 (CLAUDE.md DDL 규칙). DEFAULT TRUE 라 기존 행 자동 채움 — lock 짧음.
- fallado/movido (activity_type) 경로는 이 검증과 무관 (stocks.service.ts 별도) — 건드리지 말 것.
