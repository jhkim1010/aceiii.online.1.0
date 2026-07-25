# SPEC: superadmin revenue-summary 할인 미반영 + soft-delete 매장 포함 버그 수정
생성일: 2026-07-24

## 목표
superadmin 웹의 "Resumen de Ingresos Mensuales"(GET /subscription-config/revenue-summary)에
① soft-delete 매장 제외, ② store_billing_discounts(상시+이번달 일회성, referral 포함) 할인 반영.

## 배경 및 컨텍스트
- 화면: `ventago-app/src/views/admin/subscription/SubscriptionConfigView.tsx` (revenueSummary 테이블)
- 백엔드: `api-ventago/src/app/subscription-config/subscription-config.service.ts` → `getRevenueSummary()`
- **버그 원인**:
  - `Store.findAll()` 에 `deletedAt IS NULL` 필터 없음 (stores.deleted_at 은 수동 soft-delete 컬럼, paranoid 아님)
  - 할인 테이블 `store_billing_discounts` 를 전혀 조회하지 않음
- **정답 레퍼런스**: `admin-console.service.ts` (모바일 superadmin) — `WHERE st.deleted_at IS NULL`,
  recurring(최신 active 1건) + one_time(active, applies_ym = 이번달) 합산, `net = max(0, gross - rec - one)`
- ⚠️ `store_billing_discounts` 는 마이그레이션(2026-07-24-referral-apodo.sql) 미적용 환경 존재 가능
  → 조회는 try/catch 로 감싸 미배포 환경에서도 요약 자체는 동작 (기존 referralCredits 패턴과 동일)

## 기술 스택
- NestJS 11 + Sequelize (pool min=10/max=80 — database.module.ts, 변경 금지)
- ESLint: newline-before-return, lines-around-comment, no-unused-vars 주의

## 태스크 목록
- [x] TASK-1: `getRevenueSummary()` 수정 — 파일: `subscription-config.service.ts`
  - `Store.findAll({ where: { deletedAt: null } })`
  - N+1 제거: 매장별 branch/terminal COUNT 루프 쿼리 → `GROUP BY store_id` 배치 2쿼리 (pool 부담 축소)
  - StoreApps 도 전 매장 1회 조회 후 JS 그룹핑
  - 할인 배치 1쿼리: recurring(active 최신 1건/매장, DISTINCT ON) + one_time(active, applies_ym=이번달) 합산
  - 응답에 `recurringDiscount`, `oneTimeDiscount`, `discountTotal`, `grossTotal` 추가, `storeTotal = max(0, gross - 할인)`
- [x] TASK-2: 프론트 테이블에 "Descuento" 컬럼 추가 — 파일: `SubscriptionConfigView.tsx`
  - 할인 있으면 −금액(warning색) 표시, Total Mensual 은 순액
- [x] TASK-3: 검증 — prettier 통과(백엔드 2파일). 타입 ESLint 는 이 VM 에서 실행 불가(기존 확인된 제약) → Jenkins 빌드가 최종 게이트
- [x] TASK-4: PostgreSQL pool 안전 점검 — sequelize.query(자동 반환)만 사용, 매장별 루프 쿼리(2N+N회) → 고정 5회 배치 쿼리로 축소
- [x] TASK-5 (추가, 사용자 요청): 웹 Registros 목록 'Borrada' 칩 — `store.service.ts` findAllStoresWithAdmin 에 deletedAt 노출 + `DataConfig.tsx` Estado 셀에서 deletedAt 우선 표시 (purge/복원 접근 유지 위해 목록에서 숨기지 않음 — 사용자 확정)

## 완료 기준
- ESLint 오류 0개
- soft-delete 매장 미표시, 할인 반영된 순액/총계
- store_billing_discounts 미존재 환경에서도 500 없이 동작

## 금지사항 / 주의사항
- pool 설정(database.module.ts) 변경 금지
- 판매용 `discounts` 테이블 사용 금지 (구독 할인은 `store_billing_discounts` 전용)
- admin-console.service(모바일용) 로직은 건드리지 않음
- getStoreBilling(단일 매장 상세)은 이번 범위 밖
