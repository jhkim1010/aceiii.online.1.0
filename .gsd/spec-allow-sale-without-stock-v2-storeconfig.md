# SPEC: allowSaleWithoutStock 을 StoreConfig 로 이전 (매장 관리자 토글) + update-flag 권한 가드

생성일: 2026-06-22 (v2 — v1 stores 테이블 구현을 StoreConfig 로 재설계)

## 목표

재고 0 이하 상품 판매 차단 설정을, **매장 관리자(admin)가 자기 매장의 configuración 에서 직접 토글**하게 한다. superadmin 은 각 매장의 상태를 **보기만** 하면 충분(편집 불필요). useRestaurantMode(Phase 39) 와 동일한 StoreConfig 패턴으로 통일하고, update-flag 엔드포인트에 누락된 권한 가드도 보강한다.

## 배경 / v1 과의 차이

v1(2026-06-22 오전, commit api b85853a / app 88a8c68)은 `stores.allow_sale_without_stock` + superadmin 전용 ModalStore 토글로 구현 → **매장 관리자가 못 바꿈**. 운영 배포까지 됨(컬럼 + 코드 Up). v2 는 이를 StoreConfig 로 옮긴다.

### 참조 아키텍처 (useRestaurantMode 전 경로 — Explore 확인)
- StoreConfig 모델: `api-ventago/src/app/store/config/storeConfig.model.ts:69-71` (`use_restaurant_mode` BOOLEAN default false, storeId FK → stores)
- 마이그레이션 예시: `migrations/39-03-store-config-restaurant.sql` (ALTER store_configs ADD COLUMN IF NOT EXISTS)
- update-flag 화이트리스트: `storeConfig.controller.ts:49-93` (PATCH + PUT 둘 다, allowedFields 배열). **@Auth 없음 — 보강 대상**
- service upsert: `storeConfig.service.ts:40-48` (findOrCreate + update, 1회 쿼리)
- 프론트 Context: `ventago-app/src/context/StoreConfigContext.tsx` (useStoreConfig 훅, user.storeId 로 자동 fetch)
- 토글 UI 패턴: `views/configuracion/restaurante/RestauranteConfigView.tsx` (Switch → apiConnector.put update-flag → reload + toast)
- 권한 게이트: `pages/configuracion/restaurante.tsx` (`<WithAccess allowedApps={['admin']}>` + acl subject 'configuracion')
- 판매 검증: `sales-create.service.ts:111-118`(store 조회) + `536-550`(processSaleItems 차단). v1 은 stores 에서 읽음.

## 기술 스택
- 백엔드 NestJS+Sequelize, 프론트 Next.js+MUI+SWR/Context. PG10/15/18.
- pool: 신규 쿼리 추가 금지 — 판매 로직은 `Store.findByPk(..., include:[StoreConfig])` JOIN 1회로 유지.

## 태스크 목록

- [ ] TASK-1: 마이그레이션 — `migrations/add-allow-sale-without-stock-to-store-configs.sql`: `ALTER TABLE store_configs ADD COLUMN IF NOT EXISTS allow_sale_without_stock BOOLEAN NOT NULL DEFAULT TRUE` + COMMENT + 검증. (기존 stores 컬럼은 TASK-8 에서 처리)
- [ ] TASK-2: StoreConfig 모델 — `storeConfig.model.ts` 에 allowSaleWithoutStock 추가 (field: allow_sale_without_stock, default true).
- [ ] TASK-3: update-flag 화이트리스트 — controller PATCH+PUT allowedFields 양쪽에 'allowSaleWithoutStock' 추가.
- [ ] TASK-4: **권한 가드 보강** — store-config 변경 엔드포인트(update-flag/update-digits/update-currency/PUT/POST/DELETE)에 `@Auth(admin, superadmin)` 추가. + storeId 가 본인 매장인지 검증(타 매장 변경 차단). GET 은 읽기라 별도 검토(매장 관리자 read 허용 유지).
- [ ] TASK-5: 판매 검증 이전 — `sales-create.service.ts`: Store.findByPk attributes 에서 allowSaleWithoutStock 제거, `include: [{ model: StoreConfig, attributes:['allowSaleWithoutStock'] }]` 로 변경. `store?.storeConfig?.allowSaleWithoutStock ?? true`. processSaleItems 시그니처 유지. **쿼리 순증 0 (JOIN)**.
- [ ] TASK-6: 프론트 Context — `StoreConfigContext.tsx` state + fetchConfig 에 allowSaleWithoutStock 추가 (default true).
- [ ] TASK-7: 프론트 토글 UI — configuración 에 토글 추가. RestauranteConfigView 패턴 복제 (Switch → PUT update-flag field:'allowSaleWithoutStock' → reload + toast). 위치: configuración 적절한 섹션(신규 페이지 or 기존 카드). `<WithAccess allowedApps={['admin']}>`.
- [ ] TASK-8: v1 정리 — superadmin ModalStore 토글을 **읽기 전용(disabled Switch, 상태 표시만)**으로 변경 + 값을 StoreConfig 에서 읽도록. stores.allow_sale_without_stock 컬럼은 즉시 DROP 하지 말고 deprecated 주석 후 별도 정리(운영 안전). v1 의 store.controller.ts FormData 변환 제거.
- [ ] TASK-9: ESLint(0 new) + pool 점검(JOIN 1회 확인) + 로그 확인.

## 완료 기준
- 매장 관리자(admin)가 configuración 에서 토글 ON/OFF → 자기 매장만 반영
- superadmin 은 ModalStore 에서 상태 확인만 (수정 불가)
- 판매 차단은 store_configs.allow_sale_without_stock=false + 재고≤0 + 비제네릭일 때
- update-flag 가 인증/매장소유 검증됨 (타 매장 변경 차단)
- 기본값 TRUE (기존 동작 유지), 신규 쿼리 0, ESLint new 0

## 금지/주의
- 기본 동작(허용) 불변 — [[feedback-ventago-stock-never-blocks-sale]]. 매장 명시 OFF 시만 차단.
- 판매 로직 신규 쿼리 추가 금지 (JOIN).
- stores 컬럼 즉시 DROP 금지 (운영 v1 배포본이 아직 읽을 수 있음 — 단계적 폐기).
- 마이그레이션 운영 적용은 사용자 확인.
- Phase 42/restaurante 경로 무관 — 건드리지 말 것.
- v1 브랜치(feat/allow-sale-without-stock) 는 이미 운영 배포됨 → v2 는 그 위에 쌓되, stores→storeconfig 전환이 운영에 안전하게 순차 적용되도록 (먼저 store_configs 컬럼+읽기 폴백, 그다음 stores 폐기).