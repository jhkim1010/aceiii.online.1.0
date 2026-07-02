# SPEC: sync_outbox 인덱스 검증 + 판매 생성 트랜잭션화

생성일: 2026-07-02
작성: GSD PLAN 단계

## 목표

500명 동시접속 시 pool 점유 시간을 줄이고 데이터 정합성을 확보한다.
(1) 로그에서 관측된 sync_outbox / online_orders slow query의 인덱스 실제 적용을 검증·보강하고,
(2) 판매 생성(`create()`)을 단일 트랜잭션으로 묶어 커넥션 획득 20~25회 → 1회로 줄이고 부분 커밋을 제거한다.

## 배경 및 컨텍스트

### 로그 실측 근거 (`api-ventago/logs/combined-2026-07-01.log`)
- `sync_outbox` SELECT가 반복적으로 SlowQuery: 567ms → 718ms → 1459ms → 1673ms (worker tick 폴링 쿼리)
- `online_orders` SELECT **3749ms** (OnlineOrdersExpiryCron, `WHERE status='pending' AND created_at < cutoff`)
- 현재 pool은 유휴(`size=3 using=0`) — 문제는 pool "개수"가 아니라 느린 쿼리가 커넥션을 **오래 붙잡는 시간**

### 인덱스 현황 (이미 정의됨 — 적용 여부가 관건)
- `migrations/phase43-sync-outbox.sql:35` → `sync_outbox_due_idx ON (status, next_retry_at) WHERE status='pending'` — worker tick 쿼리(`outbox.service.ts:124`)를 정확히 커버
- `migrations/phase28-full-online-integration.sql:90,200` → `online_orders_store_created_idx`, `online_orders_pending_old_idx`
- **가설:** 로컬 dev DB(PG15) 및/또는 운영 DB(PG10)에 위 인덱스가 실제 생성돼 있지 않아 seq scan 발생 → slow query. `phase43`/`phase28` 마이그레이션이 해당 환경에 미적용된 것으로 의심.

### 판매 생성 현황 (`api-ventago/src/app/sales/sales-create.service.ts:110~428`)
`create()`는 **트랜잭션 없이** 순차 실행:
- `sale.create()` (308) → `createSaleItems()` bulkCreate (333) → stock 이동 for-loop: `ProductBranch.findOne/create` + `Stocks.create` (350~376) → `processPaymentMethods()` (378) → `createDiscountReasons/SaleDiscounts/SaleRecharges` (379~381)
- 이후는 **커밋 후 best-effort**여야 하는 것들: `attachCreditLedgerForSale()`(383, 이미 자체 트랜잭션), `sendToprinters()`(395), outbox/WP push(401~425), 최종 `findOne()`(427)
- `sequelize`는 `@InjectConnection`으로 이미 주입됨(38~39행) → 트랜잭션 사용 가능
- 헬퍼 메서드(`createSaleItems`, `processPaymentMethods`, `createDiscountReasons`, `createSaleDiscounts`, `createSaleRecharges`)는 현재 `transaction` 인자를 받지 않음 → 시그니처 확장 필요

**리스크:** 현재 `sale` 행 커밋 후 `Stocks.create()` 실패 시 재고 누락된 판매가 영구 잔존(정합성 파괴).

## 기술 스택
- 언어/프레임워크: NestJS 11 + TypeScript, Sequelize + sequelize-typescript
- DB: PostgreSQL (로컬 dev PG15 Docker `dbpostgres` / 운영 PG10 호스트 `sudo -u postgres psql`)
- ESLint: 프로젝트 규칙 엄격(Warning=빌드 실패). `newline-before-return`, `lines-around-comment`, `no-unused-vars` 특히 주의
- Pool: `database.module.ts` min=10 max=80 (변경하지 않음)

## 태스크 목록

### Wave 1 — 인덱스 실제 적용 검증·보강 (DB, 낮은 위험)
- [ ] TASK-1: 로컬 dev DB(PG15) 에서 `sync_outbox`, `online_orders` 인덱스 실존 확인
      (`\d sync_outbox`, `\d online_orders` 또는 `pg_indexes` 조회) — **조회성, 확인 불필요**
- [ ] TASK-2: 로컬에서 실제 worker 쿼리/expiry 쿼리 `EXPLAIN (ANALYZE, BUFFERS)` 실행 → seq scan 여부 확정
- [ ] TASK-3: 인덱스 누락 시, 멱등 재적용 마이그레이션 `migrations/2026-07-02-verify-hotpath-indexes.sql` 작성
      (`CREATE INDEX IF NOT EXISTS` 로 sync_outbox_due_idx / online_orders_pending_old_idx 재보장 + `ANALYZE`)
      → **로컬 적용은 조회성 아님(DDL)이나 dev 환경이므로 진행, 운영 적용은 사용자 확인 후**
- [ ] TASK-4: 운영 PG10 에서 동일 인덱스 실존 확인(조회) → 누락 시 사용자 확인 받고 `CONCURRENTLY` 로 적용
      (운영은 락 최소화 위해 `CREATE INDEX CONCURRENTLY`, 트랜잭션 밖 실행)

### Wave 2 — 판매 생성 트랜잭션화 (코드, 중간 위험)
- [ ] TASK-5: 헬퍼 메서드에 `transaction?: Transaction` 인자 추가 및 내부 `.create/.bulkCreate` 에 전파
      — 파일: `sales-create.service.ts` (`createSaleItems`, `processPaymentMethods`, `createDiscountReasons`, `createSaleDiscounts`, `createSaleRecharges`)
- [ ] TASK-6: `create()` 의 트랜잭션 경계 재구성 — 파일: `sales-create.service.ts:110~428`
      - **트랜잭션 IN:** `sale.create` → `createSaleItems` → stock 이동 for-loop(ProductBranch/Stocks) → `processPaymentMethods` → discountReasons/saleDiscounts/saleRecharges
      - **트랜잭션 OUT(커밋 후):** `attachCreditLedgerForSale`(자체 tx 유지), `sendToprinters`, outbox/WP push, 최종 `findOne`
      - `this.sequelize.transaction(async (t) => { ... })` 콜백 사용 → 자동 커밋/롤백(= `finally` 없이 pool 안전)
      - 트랜잭션 콜백 내부에 **외부 I/O(프린터/HTTP/socket) 절대 금지** (pool 점유 시간 폭증 방지)
- [ ] TASK-7: `processPaymentMethods` 내부 현금 이동(`registerCashOperation` → CashRegister/box)이 동일 `t` 를 전파받는지 확인. 전파 불가한 외부 서비스면 경계에서 제외하고 스펙에 사유 기록
- [ ] TASK-8: ESLint 검증 (`npx eslint api-ventago/src/app/sales/sales-create.service.ts`) 오류 0개

### Wave 3 — 검증
- [ ] TASK-9: 판매 생성 스모크 (정상 1건 + 의도적 실패 주입 시 전체 롤백 확인)
- [ ] TASK-10: 최신 로그 재확인 — sync_outbox/online_orders slow query 소멸 여부, 신규 에러 없음 확인

## 완료 기준
- ESLint 오류 0개
- sync_outbox / online_orders 핫패스 쿼리가 인덱스 사용(EXPLAIN 에 Index Scan)
- 판매 생성이 단일 트랜잭션으로 원자적 처리(중간 실패 시 sale/items/stock/payment 전부 롤백)
- 트랜잭션 콜백 내부에 외부 I/O 없음 (pool 점유 시간 최소)
- 판매 생성 커넥션 획득 횟수 대폭 감소(20~25 → 트랜잭션 1)

## 금지사항 / 주의사항
- **pool 설정(min/max) 변경 금지** — 이번 범위 아님
- 트랜잭션 콜백 안에서 프린터 전송·HTTP·socket emit 호출 금지 (커밋 후로 유지)
- 운영 DB DDL 은 반드시 사용자 확인 후 실행 (CLAUDE.md 규칙). 운영 인덱스는 `CONCURRENTLY`
- `dailyNumber` 동시성(race) 은 이번 범위에서 트랜잭션 안으로 옮기되, row-lock 기반 완전 해결은 **후속 이슈로 분리** (스펙 확대 방지)
- `attachCreditLedgerForSale` 은 이미 자체 트랜잭션 → 이중 트랜잭션 방지 위해 메인 tx 밖 유지
- `underscored: true` — raw SQL/인덱스는 snake_case 컬럼명 사용
- 마이그레이션은 PG10/PG15 호환 문법만 (PG10 미지원 기능 금지)
