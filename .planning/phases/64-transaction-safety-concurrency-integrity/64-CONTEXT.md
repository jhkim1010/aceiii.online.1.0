# Phase 64: 트랜잭션 안전성 · 동시성 · 데이터 정합성 — Context

**Gathered:** 2026-07-27
**Status:** Ready for planning
**Source:** 외부 코드 리뷰 12건 (사용자 제공, 2026-07-27) + 본 문서의 코드 재검증(전 항목 file:line 확인 완료)

<domain>
## Phase Boundary

**포함 (결함 12건):**

| # | 결함 | 심각도 | Wave |
|---|------|--------|------|
| 1 | 판매 커밋 성공 후 API 500 반환 가능 + 멱등키 부재 → 이중 판매 | 치명 | W1 |
| 2 | 판매 취소(nullifySale) 부분 저장 + 동시 이중 취소 | 치명 | W2 |
| 4 | 보류 판매(suspended-sales) 부분 저장 | 치명 | W3 |
| 3 | 생산 완료(completeWorkOrder) 가 재고 스키마와 불일치 (productId vs productBranchId) | 치명 | W4 |
| 5 | outbox enqueue 가 판매 트랜잭션과 원자적이지 않음 | 높음 | W5 |
| 6 | outbox claim/장애 복구 불안전 (FOR UPDATE SKIP LOCKED · lease 부재) | 높음 | W5 |
| 7 | 오프라인 판매 멱등 처리 비원자적 (check-then-insert) | 높음 | W6 |
| 8 | 판매 요청의 상품/판매원/지점 매장 검증 부족 (cross-tenant) | 높음 | W7 |
| 9 | 기본 재고 CRUD 불안정 (원장 가변 + 존재하지 않는 컬럼 참조) | 높음 | W7 |
| 10 | 재고 부족 검사가 동시 판매를 막지 못함 (TOCTOU) | 중 | W8 |
| 11 | 백데이트 판매의 번호 채번 오류 | 중 | W8 |
| 12 | 공개 쇼핑몰 pool 예산 초과 위험 | 중 | W8 |

**제외:**
- Phase 63 이 이미 해결한 항목 재작업 금지 — dailyNumber 원자 채번(advisory lock), 재고 차감 락 순서/lock_timeout, global_clients SAVEPOINT 직렬화는 **현행 유지**하고 그 위에 얹는다.
- 판매 생성 경로의 성능 재튜닝(pgbouncer pool_size, PG 파라미터) — Phase 63 스케일 작업 소관. 본 Phase 는 정합성만.
- 프런트엔드 UX 변경 — 단, W1 멱등키는 POS 클라이언트가 키를 보내야 하므로 ventago-app / mobile-sales-app 송신부 최소 변경 포함.
- 신규 기능 추가 없음. 전 Wave 가 무회귀 교정.

</domain>

<current-code>
## 현재 코드 위치 (2026-07-27 main 기준, 전부 재확인됨)

### 결함 1 — 판매 커밋 후 500 + 멱등키 부재
- `api-ventago/src/app/sales/sales-create.service.ts:136` — `create(createSaleDto)`
- `:354`–`:483` — 판매 원자 트랜잭션 (sale/items/stocks/결제/할인/재고차감). **이 구간은 건전함.**
- `:486` — 커밋 **후** `await attachCreditLedgerForSale(...)` (별도 트랜잭션, `:1588`)
- `:496`–`:498` — 커밋 후 `await this.sendToprinters(sale.id)`
- `:590` — 커밋 후 `return this.salesService.findOne(sale.id)`
- → 486/496/590 중 하나라도 throw 하면 **판매는 DB 에 있는데 클라이언트는 500** 수신. POS 는 재시도 → 같은 판매 2건.
- 요청 멱등키는 전 코드베이스에 없음. 유일한 멱등키 사용처는 외부 API 호출 쪽: `app/mercadopago/refunds/mp-refund.service.ts:123` (`refund-${saleId}-${attemptNo}`), `app/mercadopago/api-client/mp-api-client.service.ts:89` (`X-Idempotency-Key`).

### 결함 2 — 판매 취소 부분 저장 + 이중 취소
- `sales-create.service.ts:672` — `nullifySale(saleId, userId)`
- `:673`–`:684` — `findOne` 후 status 검사. **트랜잭션 밖 · 락 없음** → 두 요청이 동시에 통과.
- `:697`–`:728` — 트랜잭션은 **채번 + 역분개 sale INSERT 만** 감쌈 (Phase 63 B-0 이 최소 범위로 도입, 주석 `:696` 이 "전체 트랜잭션화는 별도 과제"라고 명시).
- `:735`–`:793` — 역분개 items + `products.stock` increment + `Stocks` 복원 (트랜잭션 밖)
- `:813`–`:822` 결제수단, `:825`–`:833` 할인, `:836`–`:844` 추가요금 (트랜잭션 밖)
- `:847`–`:850` — 원본 `status=NULLIFIED` + `nullifiedBySaleId` (트랜잭션 밖, 맨 마지막)
- → 중간 실패 시 "역분개 sale 은 있는데 items/재고/원본 상태는 미반영" 상태로 영구 잔존.

### 결함 3 — 생산 완료 ↔ 재고 스키마 불일치
- `api-ventago/src/app/production/work-orders/work-order.service.ts:67` — `completeWorkOrder(...)`
- `:92` — `status === COMPLETED` 검사 (락 없음, 트랜잭션 없음)
- `:123`–`:125`, `:137`–`:139`, `:152`–`:154` — `this.stockModel.findOne({ where: { productId } })`
- `:159`–`:162` — `this.stockModel.create({ productId, stock })`
- `:127`–`:130`, `:141`–`:144`, `:156`–`:157` — `stock.update({ stock: <절대값> })` (원장을 잔액처럼 갱신)
- 실제 스키마: `app/stocks/stocks.model.ts:24` — `productBranchId` FK. **`productId` 컬럼 자체가 없음** (`underscored:true` → `product_id` 로 번역되어 SQL 오류).
- → 이 경로는 현재 **런타임에서 깨져 있거나**(column does not exist) 조용히 아무 것도 못 찾고 재고를 갱신하지 않음. 어느 쪽이든 생산 재고는 반영 안 됨. `products.stock` 잔액 캐시도 손대지 않음.
- 정상 패턴 참조: `app/stocks/stocks.service.ts:98` `createStockMovement` (트랜잭션 + `findOrCreateProductBranch` + 원장 INSERT), `sales-create.service.ts:422`–`:443`.

### 결함 4 — 보류 판매 부분 저장
- `api-ventago/src/app/suspended-sales/suspended-sales.service.ts:137` — `create(dto, userId)` — 트랜잭션 **없음**
  - `:146` 헤더 INSERT → `:168` items bulkCreate → `:182` `recordReservationMoves(items, branch, -1)` → `:187` 할인 → `:198` 추가요금
- `:59`–`:134` — `recordReservationMoves` (ProductBranch 조회/생성 + `Stocks.create` 반복, 트랜잭션 인자 없음)
- `:265` — `update(...)`: `:283` 예약 +1 복원 → `:290` 헤더 update → `:304`–`:306` items/discount/recharge **destroy** → 재생성 → `:323` 예약 -1 재적용. 트랜잭션 없음 → 중간 실패 시 **아이템이 사라진 보류 판매** 또는 예약 재고 중복/유실.
- `:350` — `remove(...)`: `:363` 예약 복원 → `:366` 헤더 destroy. 트랜잭션 없음.

### 결함 5 · 6 — outbox
- enqueue 호출부: `sales-create.service.ts:508`–`:526` — 커밋 **후** `this.syncOrchestrator.enqueuePush(...).catch(warn)` — fire-and-forget.
- `api-ventago/src/app/integrations/core/outbox.service.ts:52` — `enqueue(params)` 는 이미 `params.transaction` 을 지원(`:65`)하나 **호출부가 넘기지 않음**.
- `:104` — `tick()`; `:124`–`:131` — `findAll({status:'pending', nextRetryAt<=now}, limit 20)` — **락 없음**
- `:138`–`:141` — `job.update({status:'processing'})` — 조회와 갱신이 분리 → 두 워커가 같은 job 을 잡을 수 있음
- `:37` — `private running = false` — **프로세스 내부 플래그**. pm2 멀티워커/2인스턴스면 무효.
- `processing` 상태로 죽은 job 을 회수하는 경로 없음 → 영구 정체.
- cron: `app/integrations/core/outbox.cron.ts`

### 결함 7 — 오프라인 판매 멱등 비원자
- `api-ventago/src/app/offline-sync/offline-push.service.ts:89` — `processOne(...)`
- `:100` — `findOne({ where: { opUuid } })` → `:115` — `create({...status:'received'})` → `:129`~ 적용
- DB 에는 UNIQUE 존재: `api-ventago/migrations/phase58-offline-sync-ops.sql:7` `op_uuid VARCHAR(64) NOT NULL UNIQUE`, 모델 `offline-sync-op.model.ts:9`
- → 동시 중복 batch 는 UNIQUE 위반으로 **500** (duplicate 로 정상 처리되지 않음). insert 후 apply 전에 죽으면 status 가 `received` 로 굳고, 재전송 시 `:108` 이 그대로 `received` 를 돌려줘 **판매가 영원히 생성되지 않음**(edge 는 정산 완료로 간주).

### 결함 8 — 테넌트 검증 부족
- `sales-create.service.ts:163` — `Seller.findByPk(sellerId)` — storeId 스코프 없음
- `:194`, `:302` — `Clients.findByPk(clientId)` — storeId 스코프 없음
- `:963` — `processSaleItems` 의 `productModel.findByPk(item.productId)` — **storeId 검증 없음** → 타 매장 상품으로 판매 생성 가능
- `:337`–`:347` — `dtoBranchId` 를 그대로 사용, `branch.storeId === storeId` 검증 없음 (지점 미지정 시에만 storeId 로 조회)
- 참고: 이미 store 격리를 강제하는 선례 — `app/products/*` (Phase: store_isolation_products), `work-order.service.ts:86`(storeId 불일치 시 404)

### 결함 9 — 기본 재고 CRUD
- `api-ventago/src/app/stocks/stocks.service.ts:62` — `create(data)`: `data.productId` 로 Product 검증 후 `stockModel.create({...data})` — Stocks 에 `productId` 없음
- `:73` — `updateStock(id, data)`: 원장 행을 그대로 UPDATE (`products.stock` 잔액 캐시 미조정)
- `:81` — `findByProduct(productId)`: `where: { productId }` → `product_id` 컬럼 부재로 실패
- `:85` — `delete(id)`: 원장 행 DELETE (잔액 캐시 미조정 → 영구 드리프트)
- 정상 경로 대비: `:98` `createStockMovement` 는 트랜잭션 + ProductBranch 경유 + append-only

### 결함 10 — 재고 TOCTOU
- `sales-create.service.ts:981` — `if (!product.isGeneric && !allowSaleWithoutStock && product.stock <= 0) throw`
- 실제 차감은 `:467` `applyStockDecrements(...)` (`:912` 정의) — 같은 트랜잭션이지만 **검사 시점에 행 락을 잡지 않음**
- → 재고 1개를 두 터미널이 동시에 검사 통과 후 각각 -1 → `products.stock = -1`

### 결함 11 — 백데이트 채번
- `sales-create.service.ts:258` — `const now = dtoSaleDate ? new Date(dtoSaleDate) : new Date()` (Alt+F2 로 과거 날짜 등록)
- `:610` `reserveDailyNumber(storeId, tz, t)` — 인자에 날짜 없음. `:618` advisory lock 키와 `:630` `saleDayLocal` 둘 다 **`NOW()`** 기준
- → 백데이트 판매가 "오늘"의 번호를 소비하고 `sale_day_local = 오늘`, `sale_date = 과거` 로 저장 → 일자별 번호 연속성/보고서 불일치
- 관련 인덱스: `migrations/2026-07-27-phase63-sale-day-local-2-index.sql` (UNIQUE partial on `store_id, sale_day_local, daily_number`)

### 결함 12 — 공개몰 pool 예산
- `api-ventago/src/app/shop-public/shop-readonly-db.service.ts:23`–`:40` — 별도 `pg.Pool`, `max = SHOP_DB_POOL_MAX || 15`, `SHOP_DB_*` 미설정 시 **메인 DB 호스트로 폴백**
- `api-ventago/src/database/database.module.ts:52`–`:58` — 메인 Sequelize `min:2, max:20` (워커당)
- 주석 상 예산: pgbouncer `ventago pool_size=50`, PG `max_connections=200`, 워커 4 → 메인 4×20=80 클라이언트
- 공개몰 pool 은 이 예산 밖에서 워커당 +15 (4워커면 +60). 폴백 시 **같은 pgbouncer/PG** 를 겨냥 → 총 140 클라이언트가 50 서버슬롯을 두고 경합. 공개 트래픽 급증이 POS 를 굶길 수 있음.
- `shop-readonly-db.service.ts:12`–`:13` 주석은 메인 pool 을 `min=10/max=80` 이라고 서술 — **현행(20)과 불일치**, 문서 교정 대상.

</current-code>

<relations>
## 기존 Phase 와의 관계

### Phase 63 (스케일 복원력) — 직속 선행, roadmap 미등재
`.planning/ROADMAP.md` 에는 없고 코드/마이그레이션에만 존재한다(`grep "Phase 63" api-ventago/src`).
이미 적용된 것 — **본 Phase 는 이것들을 유지·확장하고 되돌리지 않는다**:
- `B-0` dailyNumber 원자 채번: `pg_advisory_xact_lock(storeId, YYYYMMDD)` + 같은 트랜잭션 INSERT (`sales-create.service.ts:610`)
- `B-0d` `sales.sale_day_local` 컬럼 + 타임존 독립 UNIQUE 인덱스 (`migrations/2026-07-27-phase63-sale-day-local-{1,2}-*.sql`)
- `B-0c` 재고 차감을 트랜잭션 끝으로 이동 + `productId` 오름차순 정렬(교착 방지) + `SET LOCAL lock_timeout='3s'` (`:355`–`:363`, `:912`)
- `T-1` `global_clients` SAVEPOINT 직렬화 (`app/clients/clients.model.ts:147`, `clients.service.ts:653`)
- `F-7` rate-limit storage Redis 공유 (`app.module.ts:155`)
- 부하 하네스 `loadtest/` (pos-scenario.js, burst-multistore.js, login-capacity.js, run-300-stages.sh)

Phase 63 은 **"같은 판매 안에서의 경합"** 을 잡았고, Phase 64 는 **"판매 경계 밖(취소·보류·생산·outbox·오프라인)"** 과 **"요청 단위 멱등"** 을 잡는다. 겹침 없음.

### Phase 54 (observability) — 존재하지 않음
`.planning/phases/` · ROADMAP · STATE 어디에도 Phase 54 없음. 병목/관측 관련 실제 산출물은:
- `app/diagnostics/*` + `migrations/slow-query-log.sql` (superadmin `/admin/diagnostics`, 느린 쿼리 QID 로깅 + pool/outbox 조회)
- `database.module.ts:184`–`:201` pool 사용률 80% 경고
→ W10 의 검증 게이트에서 **재사용**한다(신규 관측 인프라 만들지 않음).

### 그 외 관련 Phase
- **Phase 43 (commerce connector core)** — outbox 도입 주체. W5 는 이 설계(`OutboxProcessor`, `dedupeKey` 부분 UNIQUE, BATCH_SIZE=20)를 유지한 채 claim 만 교체.
- **Phase 58 (offline sync)** — W6 대상. `op_uuid` UNIQUE 는 이미 있음, 코드가 못 쓰고 있을 뿐.
- **Phase 51 (public storefront)** — W8 결함 12 대상. 격리 pool 자체는 Phase 51 의 올바른 설계, 예산 합산만 미검토.
- **store_isolation_products** (2026-06-18) — W7 테넌트 검증의 선례 패턴.
</relations>

<constraints>
## 제약

### DB / 마이그레이션
- 로컬(Mac PG18 :5432) + 운영(srv803182 PG18 :5434) **동시 적용** 필수. 한쪽만 적용 금지(장애 전례 다수).
- 신규 테이블은 마이그레이션 SQL 끝에 role 존재체크 DO 블록으로 `ALTER TABLE ... OWNER TO coolsistema` + `ALTER SEQUENCE ... OWNER TO coolsistema` 둘 다 필수.
- 운영 인덱스 생성은 `CREATE INDEX CONCURRENTLY` (테이블 락 회피). `--single-transaction` 과 함께 쓸 수 없으므로 별도 파일로 분리.
- DDL/DML 변경성 SQL 은 실행 전 사용자 확인. 본 Phase 문서 단계에서는 **SQL 파일 작성·커밋만**, 실행하지 않는다.

### Pool
- 메인 pool `max=20/워커` 상향 금지. 정합성 수정이 커넥션을 추가로 오래 잡으면 안 됨 — 트랜잭션 안에서 외부 I/O(HTTP·프린터·소켓) **절대 금지**.
- 새 트랜잭션을 여는 Wave(2/3/4)는 기존 커넥션 수를 늘리지 않고 **기존 순차 호출을 하나의 트랜잭션으로 묶는** 방향이어야 한다(오히려 점유 시간 감소).

### 무회귀
- 소매(의류) 판매 경로 회귀 절대 금지 — 식당/배달/온라인 공유 경로 변경 시 소매 별도 검증.
- POS 응답 형식(`findOne(sale.id)` 결과 shape) 유지 — 프런트 파싱 깨짐 방지.
- 오프라인/APK 구버전 클라이언트 호환: 멱등키 헤더는 **선택** 필드로 도입(미전송이면 현행 동작).

### 코드 규약
- 주석 한국어, 함수/변수명 영어.
- ESLint: `newline-before-return`, `lines-around-comment` 위반 시 빌드 차단.
- 프런트 변경 후 eslint-guardian 점검 필수.
</constraints>

<risks>
## 위험

1. **W1 멱등키가 정상 재시도를 막는 오탐** — 키 스코프를 (storeId, terminalId, key) 로 좁히고 TTL(24h) 을 두지 않으면 다음 날 같은 키 재사용 충돌. 응답 본문을 저장해 그대로 재생하는 방식이어야 "성공했는데 500" 을 실제로 없앤다.
2. **W2 트랜잭션 확대로 락 보유 시간 증가** — nullifySale 은 items 수만큼 루프한다. 락 순서를 판매 생성(productId ASC)과 **동일하게 맞추지 않으면 교착**. Phase 63 B-0c 주석의 정렬 규칙을 그대로 따를 것.
3. **W4 생산 경로는 현재 깨져 있어 "실데이터가 없다"** — 수정 후 처음으로 재고가 실제 움직인다. 기존 완료된 work order 의 미반영 재고를 소급 보정할지 여부는 별도 판단(기본: 소급 없음, 문서화만).
4. **W5 outbox claim 교체 시 in-flight job** — 배포 순간 `processing` 상태 job 이 lease 없이 남아 있음. 마이그레이션에 1회성 `UPDATE ... SET status='pending' WHERE status='processing'` 회수 포함 필요.
5. **W7 테넌트 검증이 기존 운영 데이터를 거부할 수 있음** — 매장 경계를 넘는 기존 참조(레거시 import, generic 상품)가 실제로 존재하면 판매가 막힌다. 차단 전 **읽기 전용 조사 쿼리로 위반 건수 0 확인**이 선행 태스크.
6. **W8 백데이트 채번 변경이 기존 인덱스와 충돌** — `sale_day_local` 을 과거 날짜로 쓰면 그 날짜의 기존 번호와 UNIQUE 충돌 가능. 백데이트는 "해당 영업일의 다음 번호"를 잡아야 하며 그 날짜에 이미 최대치가 있으면 정상 증가.
7. **동시성 테스트의 CI 안정성(W9)** — 실제 PG 없이 재현 불가능한 케이스가 많다. 로컬 PG18 + 별도 테스트 DB 를 쓰는 통합 테스트로 두고, 유닛 CI 와 분리(`test:concurrency`)해 플레이키가 전체 빌드를 막지 않게 한다.
</risks>

<open-questions>
## 열린 항목 (계획 단계에서 결정, 기본값 명시)

- **Q1. 멱등키 저장소** — 신규 테이블 `sale_idempotency_keys` (기본) vs Redis. 기본값 = 테이블. 이유: Redis 는 이미 rate-limit 용으로 쓰지만 판매 결과 재생은 유실되면 안 되는 데이터.
- **Q2. 멱등키 발급 주체** — POS 클라이언트(기본, UUID v4) vs 서버 파생 해시. 기본값 = 클라이언트 발급, 서버는 미수신 시 현행 동작 유지.
- **Q3. 생산 완료 소급 보정** — 기본값 = 소급 없음(과거 work order 는 재고 미반영 상태로 인정, acceptable artifact 로 문서화).
- **Q4. 재고 CRUD 원장 불변 강도** — `updateStock`/`delete` 를 (a) 삭제 (b) superadmin 전용 (c) 보정 이동(reversal row) 로 대체. 기본값 = (c) 보정 이동 + 기존 라우트는 410 Gone.
- **Q5. 공개몰 pool 격리 강도** — (a) `SHOP_DB_POOL_MAX` 기본값 하향 (b) 별도 PG 사용자/pgbouncer pool 강제 (c) 폴백 시 경고+상한 자동 축소. 기본값 = (c) + 예산 문서화.
</open-questions>
