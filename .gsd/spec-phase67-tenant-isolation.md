# SPEC: Phase 67 — 멀티테넌트 절대 격리 (Tenant Isolation Hard Block)

생성일: 2026-07-30

## 목표

타 매장 데이터에 접근·변경하는 것을 **개별 컨트롤러 패치가 아니라 시스템 레이어에서** 원천 차단한다.
컨트롤러가 `storeId` 를 빠뜨려도, 개발자가 새 라우트를 추가하며 실수해도, raw SQL 로 우회해도 막힌다.

---

## 배경 및 컨텍스트 (실측 근거)

### 1) 운영 DB 실측 — 교차매장 오염이 이미 발생함 (PG18 5434, 2026-07-30)

| 항목 | 오염 row | 상세 |
|---|---|---|
| `prices`: product.store ≠ price_type.store | **24** | 타 매장 price_type 으로 가격이 매겨진 상품 |
| `sale_items`: product.store ≠ sale.store | **10** | sale 2,3,4,8,10,14 — store 6↔3, 3↔8, 8↔6 교차 |
| `ProductBranch`: product.store ≠ branch.store | **3** | pb 109/110/111 = store 3 상품이 store 6 지점에 등록 |

`ProductBranch` 109/110/111 은 각각 `stocks` 원장 2행씩(net **-8**) 을 보유 → **store 6 의 재고 원장에 store 3 상품의 마이너스 재고가 살아 있다.**
발생 시점은 2026-03~04 (초기 테스트 구간) 이지만, **구조적으로 지금도 다시 발생 가능**하다.

정상 확인(오염 0건): terminals/boxes/users/cash_registers/active_sessions/terminal_devices/ventas_suspendidas/expenses/box_operations/sales(terminal·client)/product_promotions

### 2) NULL store_id 실측 — 필터 우회 가능 row

- `payment_methods` 13건, `roles` 4건 → **의도된 글로벌 행** (격리 훅에서 허용해야 함)
- `users` 1건 = `superadmin@ventago.test` (id=1) → 의도됨
- 그 외 16개 테이블 전부 0건 → 예상치 못한 NULL 오염 없음
- ⚠ 단 `sales.store_id` 는 스키마상 **NULLABLE** — NULL 이 되면 어떤 `WHERE store_id=X` 도 통과 못 하고 교차검출도 못 한다 (잠복 위험)

### 3) 운영 로그 실측 (`/app/logs/combined-2026-07-30.log`, api_ventago)

- ✅ cron leader 정상: `스케줄러 비리더 — cron/interval 21개 해제 (NODE_APP_INSTANCE=1,2,3)` → 4워커 중 1개만 실행 (중복 4배 없음)
- ⚠ `[ShopReadonlyDb] 공개몰 pool 이 메인 DB 인스턴스로 폴백됨 — 커넥션 격리 미적용. 상한 15 → 5 로 축소` (4회) → **공개몰 트래픽이 POS 와 같은 PG 슬롯 사용**
- ⚠ `[StockDriftService] 4/190 productos con drift (8 unidades)` → 위 ProductBranch 오염과 정합
- `error-2026-07-30.log` 0 byte, `[SLOW]` 항목 없음, `slow_query_log` 7일간 4건(최대 189ms)
- **결론: 현재 병목은 실측상 없다** (sales 110행/312kB — 데이터가 아직 작음). 병목은 잠복 상태이며, **지금 실재하는 위험은 매장 격리 결함이다.**

### 4) 코드 정적분석 — 검증 완료된 격리 결함

| # | 위치 | 결함 | 상태 |
|---|---|---|---|
| A1 | `common/crud/crud.service.ts:41` | `if (!isSuperAdmin && storeId && ...)` — 컨트롤러가 storeId 를 안 넘기면 검사 자체가 **무효화(fail-open)**. category/sizes/colors/season/origin/subcategory/supplier/envio 등 CRUD 스캐폴드 전체 영향 | VERIFIED |
| A2 | `app/branch/branch.service.ts:21` | `findOne(id)` 1-인자 오버라이드로 base 의 소유 검사 무력화 → 타 매장 지점 PUT/DELETE | VERIFIED |
| A3 | `app/reports/reports.controller.ts` | `query.storeId` 사용 **50건** vs `user.storeId` 1건, `scope.helper.ts` 사용 **0건(죽은 코드)**. 타 매장 리포트 전체 열람 + storeId 생략 시 전 매장 합산 | VERIFIED |
| A4 | `app/reports/reportsStocks.service.ts:29`, `reportsProducts.service.ts:24` | `storeId` 를 아예 읽지 않음 → 전 매장 재고/상품 노출 | VERIFIED |
| A5 | `app/sales/sales.controller.ts:339` | `findOneAdmin` 만 store 검사 누락 (형제 라우트는 있음) | VERIFIED |
| A6 | `app/sales/sales.service.ts:157` | `buildDateFilter` 가 `startDate` 를 `literal()` 에 문자열 보간 + 컨트롤러가 DTO 검증 없는 `@Query()` → SQLi 및 storeId 조건 무력화 | VERIFIED |
| A7 | `app/print/print.controller.ts` | agent CRUD/`apiKey` 노출/출력 라우팅 전부 branch 소유 검사 없음 | VERIFIED |
| A8 | `app/users/user-role/user-role.controller.ts` | 가드 전무 → 임의 roleId 자기부여(**권한 상승**) | VERIFIED |
| A9 | `app/payment-methods/payment-methods.controller.ts:76` | PUT/DELETE 무스코프 → 공용 글로벌 행 파괴 가능 | VERIFIED |
| A10 | `app/suspended-sales/suspended-sales.controller.ts:46` | `:id` 3라우트 무스코프 (vendedor 권한으로 타 매장 보류판매 열람/삭제, 삭제 시 타 매장 재고 원장 변동) | VERIFIED |
| A11 | `app/session/session.service.ts:483` | `registerTerminalAndCreateSession` 만 `Box.findByPk(boxId)` — storeId 미검증 → 타 매장 branch 가 내 매장 terminal_devices/active_sessions 에 박힘 | VERIFIED |
| A12 | `app/products/products.controller.ts:329` | `@GetUser()` 주입만 하고 서비스에 미전달 → `productsPrice.service.ts:34` 가 productId 만으로 타 매장 가격 변경 | VERIFIED |
| A13 | `app/promotions/promotions.controller.ts` | `@UseGuards(AuthGuard('jwt'))` 만 — FunctionGuard 조차 없음. update/toggle/remove 가 `findByPk(id)` | VERIFIED |
| A14 | `app/subcon/envios/envio.controller.ts:94` | `findOne`/`cancel` 무스코프 + `envio.service.ts:92` lote 수량 read-modify-write 에 FOR UPDATE 없음(lost update) | VERIFIED |
| A15 | `app/terminal/terminal.controller.ts:81`, `caja-fuerte.controller.ts:46`, `box-operation.controller.ts:15`, `subcon/vendors`, `subcon/subcon-orders` | `:id`/`:storeId` 무스코프 조회 | VERIFIED |
| A16 | `app/permissions/guards/permission.guard.ts:74` | PRIVILEGED role-slug 허용목록이 storeId 비교 없이 무조건 우회 | VERIFIED |
| A17 | `app/auth/guards/function-permission.guard.ts:44` | `user.roles.some(r => r.slug==='superadmin')` — 그런데 `users.service.ts:158` 이 `roles` 를 **string[]** 로 반환 → `r.slug` 는 항상 undefined → **superadmin 우회가 작동하지 않음** (신규 발견) | VERIFIED |
| A18 | `app/boxes/*` (복수형) | 무스코프 컨트롤러이지만 `BoxesModule` 을 import 하는 곳이 없음 → **죽은 코드**(라우트 미마운트). 향후 실수로 등록될 위험 | VERIFIED(비활성) |

### 5) DB 구조적 근본 원인

`store_id` 컬럼을 가진 테이블 **121개** / `storeId` 속성 모델 **106개**.
FK 는 `product_id → products`, `branch_id → branches` 를 각각 검증할 뿐 **"둘이 같은 매장인가"는 DB 어디에서도 보장하지 않는다.** → 오염 37건의 근본 원인.

### 6) 기존 인프라 현황

- `AsyncLocalStorage` / nestjs-cls / RequestContext: **전무** (0건) → 새로 만들어야 함
- `database.module.ts`: `define: { underscored, timestamps }` 만 있고 **`hooks:` 옵션 없음** → 전역 훅 삽입 지점 확보됨
- 전역 가드: `app.module.ts:337` `APP_GUARD: JwtGlobalGuard`, 우회는 `@Public()` 33개 파일 (로그인/공개몰/웹훅/헬스/minio/offline-sync/onboarding)
- print/zebra agent 는 Socket.io + `branch_agents.api_key` 핸드셰이크 → HTTP 가드 스코프 밖

---

## 기술 스택

- NestJS 11 + Sequelize(sequelize-typescript), `underscored: true`
- PostgreSQL 18 (로컬 5432 / 운영 5434, pgbouncer 5432 transaction mode)
- pool: min=2 max=20 **워커당**, 4워커 → 80 클라이언트, pgbouncer pool_size=50
- ESLint: warning 도 빌드 차단 (`newline-before-return`, `lines-around-comment`, `no-unused-vars`)

---

## 설계: 4중 방어 (Defense in Depth)

```
요청 ──▶ [L1] TenantContext (AsyncLocalStorage)   ← 요청당 storeId/superadmin 확정
          │
          ├──▶ [L2] Sequelize 전역 훅              ← ORM 106모델 일괄 강제 (컨트롤러 무관)
          │        beforeFind/Count/BulkUpdate/BulkDestroy → where.storeId 주입
          │        beforeCreate/Update/Destroy(instance)   → 교차매장 쓰기 throw
          │        afterFind                              → 반환 row 검증(warn→enforce)
          │
          ├──▶ [L3] CrudService fail-closed         ← 공용 CRUD 스캐폴드 fail-open 제거
          │
          └──▶ [L4] DB 교차매장 트리거              ← raw SQL·수동 psql 까지 차단
```

**핵심 원칙: L2 는 컨텍스트가 없으면 no-op** 이다. 크론/워커/공개몰/로그인/웹훅은 컨텍스트가 없으므로 영향 없음 → 회귀 위험 최소화.

---

## 태스크 목록

### Wave A — 시스템 레이어 (컨트롤러 무관하게 일괄 차단)

- [ ] TASK-A1: `common/tenant/tenant-context.ts` — AsyncLocalStorage 컨텍스트 (`run`/`get`/`resolve`/`runSystem`/`runAsStore`)
- [ ] TASK-A2: `common/tenant/tenant-scope.registry.ts` — 모델 분류(글로벌허용 27개 / 완전면제 / 강제대상), 환경변수 모드(`off|warn|enforce`)
- [ ] TASK-A3: `common/tenant/tenant-hooks.ts` — Sequelize 전역 훅 팩토리 (where 주입 + 쓰기 차단 + afterFind 검증). **pool 무영향**(훅은 커넥션을 새로 열지 않음)
- [ ] TASK-A4: `common/tenant/tenant-context.middleware.ts` — 전 요청에 mutable 컨텍스트 심기 (가드보다 먼저 실행)
- [ ] TASK-A5: `database/database.module.ts` — `hooks: buildTenantHooks()` 배선
- [ ] TASK-A6: `app/auth/guards/jwt-global.guard.ts` — JWT 통과 후 컨텍스트 확정(`resolve`). superadmin 판정은 **string[] / object[] 양쪽 shape 방어**
- [ ] TASK-A7: `app.module.ts` — 미들웨어 전역 등록
- [ ] TASK-A8: `common/crud/crud.service.ts` — fail-closed 전환 (`storeId` 미전달 = 차단, 컨텍스트 폴백)
- [ ] TASK-A9: `app/branch/branch.service.ts` — `findOne` 시그니처 복원 + 소유 검증
- [ ] TASK-A10: `migrations/2026-07-30-tenant-crossstore-triggers.sql` — 교차매장 트리거 (prices/sale_items/ProductBranch/product_promotions/terminals/boxes/cash_registers/users/active_sessions/terminal_devices) + owner DO 블록
- [ ] TASK-A11: `app/boxes/` 죽은 코드 제거 (향후 오배선 방지)

### Wave B — raw SQL·개별 IDOR (훅이 못 막는 경로)

- [ ] TASK-B1: `reports/scope.helper.ts` 를 `reports.controller.ts` 50개 지점에 배선 (query.storeId 신뢰 제거)
- [ ] TASK-B2: `reportsStocks.service.ts` / `reportsProducts.service.ts` storeId 필터 추가
- [ ] TASK-B3: `sales.service.ts buildDateFilter` — `replacements` 파라미터 바인딩 + DTO `@IsDateString()` (SQLi)
- [ ] TASK-B4: `print.controller.ts` — branch→store 소유 검증 + `apiKey` 응답 마스킹
- [ ] TASK-B5: `user-role.controller.ts` — `@Auth(admin, superadmin)` + 대상 유저 store 검증
- [ ] TASK-B6: `payment-methods.controller.ts` — PUT/DELETE 스코프 + 글로벌 행(store_id NULL) 변경 금지
- [ ] TASK-B7: `suspended-sales.controller.ts` `:id` 3라우트 + `dto.storeId` 무시
- [ ] TASK-B8: `session.service.ts:483` Box storeId 검증 + 등록 플로우 단일 트랜잭션 + active_sessions UPSERT(`ON CONFLICT`)
- [ ] TASK-B9: `productsPrice.service.ts` storeId 강제 + `products.controller.ts` user 전달
- [ ] TASK-B10: `promotions` — FunctionGuard 추가 + `user.storeId` 강제 + update/toggle/remove 스코프
- [ ] TASK-B11: `envio` findOne/cancel 스코프 + lote `lock: LOCK.UPDATE`
- [ ] TASK-B12: `sales.controller.ts:339` findOneAdmin 스코프
- [ ] TASK-B13: `terminal`/`caja-fuerte`/`box-operation`/`subcon vendors·orders` 스코프
- [ ] TASK-B14: `permission.guard.ts` PRIVILEGED 우회에 storeId 비교 추가
- [ ] TASK-B15: `function-permission.guard.ts:44` superadmin 판정 shape 버그 수정

### Wave C — 검증 + 데이터 보정

- [ ] TASK-C1: ESLint 검증 (오류 0)
- [ ] TASK-C2: 격리 훅 단위 테스트 (교차매장 read 0건 / write throw / 글로벌 행 통과 / 컨텍스트 없음 no-op)
- [ ] TASK-C3: 운영 오염 37건 보정 DML **(사용자 승인 필요)** — prices 24 / sale_items 10(과거 판매는 감사 이력이므로 보정 대상 여부 판단 필요) / ProductBranch 3 + stocks 반대부호 보정
- [ ] TASK-C4: 마이그레이션 로컬(5432)+운영(5434) 양쪽 적용
- [ ] TASK-C5: push → Jenkins 빌드 성공 + 컨테이너 재생성 확인

---

## 완료 기준

- ESLint 오류 0개
- 타 매장 id 로 read → 빈 결과 또는 403 (200 + 타 매장 데이터 **불가**)
- 타 매장 id 로 write → `ForbiddenException`
- DB 레벨: 교차매장 INSERT/UPDATE 가 raw SQL 로도 트리거에서 거부
- 글로벌 행(payment_methods 13, roles 4) 정상 조회 유지 → **POS 결제 회귀 없음**
- 크론/공개몰/로그인/웹훅 경로 무영향 (컨텍스트 없음 → no-op)
- pool 사용률 변화 없음 (훅은 커넥션 미소비)

---

## 금지사항 / 주의사항

- ❌ pool `max` 상향 금지 — 실질 병목은 pgbouncer 서버슬롯 큐잉(Phase 63 실측)
- ❌ `afterFind` 를 처음부터 `enforce` 로 배포 금지 — include 경로 오탐으로 POS 가 멈출 수 있다. `TENANT_GUARD_MODE=warn` 로 배포 → 로그 관찰 → `enforce` 전환
- ❌ `stocks` 는 append-only — UPDATE/DELETE 금지, 반대부호 보정행으로만 상쇄. 조회는 `product_branch_id` 기준 (**`product_id` 컬럼 없음**)
- ❌ 트랜잭션 내부 외부 I/O(HTTP/프린터/소켓) 금지
- ❌ `@Public()` 33개 경로에 컨텍스트 강제 주입 금지 (공개몰/웹훅 파괴)
- ❌ 운영 DML 은 SQL + 영향 row 수 사용자 승인 후에만 실행
- ⚠ 신규 테이블 마이그레이션은 `ALTER TABLE/SEQUENCE ... OWNER TO coolsistema` DO 블록 필수
- ⚠ superadmin 판정: `request.user.roles` 는 **string[]** (`users.service.ts:158`) — object[] 를 가정하면 안 됨
