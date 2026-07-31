# PostgreSQL 점검 결과 (2026-07-31)

범위: `api-ventago` 정적 코드 및 최신 로컬 로그의 읽기 전용 점검. 운영 DB에는 접속하지 않았고 DDL/DML도 실행하지 않았다. 현재 기준은 로컬/운영 PostgreSQL 18 통일 상태다.

## Pool 안전성

- Pool size: 메인 Sequelize `min=2`, `max=20` (`src/database/database.module.ts:59-65`) ✓. 절대 상한 50을 변경하지 않았으며 증설도 권장하지 않는다.
- Leak risk: **LOW**. 런타임 코드에서 직접 `pool.connect()`/`Client` 사용은 없고, 공개몰은 `pool.query()` 자동 반환(`src/app/shop-public/shop-readonly-db.service.ts:118-125`)이다. 수동 Sequelize 트랜잭션 25개 경로는 모두 commit/rollback 경로가 확인됐다. 신규 코드는 관리형 transaction을 우선할 것을 권장한다.
- 로그 증거: 최신 API 로그 `api-ventago/logs/combined-2026-07-29.log`의 마지막 구간은 반복적으로 `size=2 using=0 available=2 waiting=0 max=20`이었다. `ConnectionAcquireTimeout`, `too many clients`, pool waiting 경고는 발견되지 않았다.
- **HIGH — 공개몰 격리 오판 가능**: `src/app/shop-public/shop-readonly-db.service.ts:19-39`. 주석은 `172.17.0.1`이 같은 호스트 PG라고 명시하지만, 구현은 host 문자열이 다르면 `isolated=true`로 판정한다. 따라서 동일 PG/pgbouncer를 Docker 브리지 주소로 가리킬 때 기본 `max=15`가 적용된다. 4 worker이면 메인 80 + shop 60 = 앱 클라이언트 최대 140개가 pgbouncer server pool 50 슬롯을 경쟁한다. 안전 조치: host 비교가 아닌 명시적 `SHOP_DB_ISOLATED=true`(별도 PG/별도 pgbouncer pool이 검증된 경우만)로 판정하고, 그 외에는 기존 fallback 5를 유지한다. 메인 max는 변경하지 않는다.
- **MEDIUM — 예산 산식이 프로세스 수를 과소 추정할 수 있음**: `src/database/database.module.ts:159-168,184-192`. `WEB_CONCURRENCY`/`PM2_INSTANCES`가 없으면 1로 계산하지만 실제 Docker replica 수는 알 수 없다. 컨테이너별 1 worker × replica N 환경에서 로그가 실제 총량을 축소 표시한다. 배포 시 `WEB_CONCURRENCY`뿐 아니라 `API_REPLICA_COUNT`를 필수로 넣고 `replicas × workers × (main+shop)`을 표시하도록 권장한다.

## 쿼리 효율

- **HIGH — outbox claim 3.015초**: `src/app/integrations/core/outbox.service.ts:222-240`; 로그 QID 937. 같은 `sync_outbox` UPDATE가 2.064초, 1.925초, 1.445초, 1.042초 등 반복됐다. pool 슬롯을 오래 점유한다. `EXPLAIN (ANALYZE, BUFFERS)`로 `WHERE status='pending' AND next_retry_at<=now() ORDER BY next_retry_at LIMIT ...` 경로를 확인하고, partial index `(next_retry_at, id) WHERE status='pending'` 존재/사용 여부와 dead tuples/analyze 상태를 우선 검증한다. SQL 의미를 바꾸거나 pool을 늘리지 않는다.
- **HIGH — campaign claim 2.171초**: `src/app/campaigns/services/campaign-sender.service.ts:189-210`; 로그 QID 936. 933ms, 667ms, 544ms 등도 반복됐다. 동일하게 partial index `(next_retry_at, id) WHERE status='pending'` 사용 여부를 EXPLAIN으로 확인한다. 현재 `IN (SELECT ... FOR UPDATE SKIP LOCKED)`은 PG18 호환이다.
- **MEDIUM — 온라인 주문 만료 조회 876ms**: `src/app/online-orders/online-orders-expiry.cron.ts:56-64`; 로그 QID 1078. `(status, created_at)` 인덱스 및 통계 사용 여부를 확인한다. 50건 순차 cancel(`:73-87`)은 connection 동시 점유를 제한해 pool에는 안전하지만 한 tick이 길 수 있다.
- **MEDIUM — 느린 쿼리 자체 기록이 2.069초**: `src/app/diagnostics/diagnostics.service.ts:83-125`; `slow_query_log` INSERT가 2.069초/1.305초 등 반복됐다. 관측 기능이 pool 슬롯을 오래 점유한다. 버퍼 상한을 유지하고, flush batch 크기 상한/짧은 statement timeout을 적용하며 테이블 인덱스·autovacuum 상태를 조회성 진단으로 확인한다.
- **MEDIUM — 판매 재고 경로에 품목 수 비례 쿼리**: `src/app/sales/sales-create.service.ts:1176-1190,1205-1220`. 재고 검증은 상품별 `SELECT ... FOR UPDATE`, 이후 ProductBranch find/create와 Stocks insert가 품목별 순차 실행된다. 잠금 순서 고정은 deadlock 예방에 적절하지만 큰 장바구니는 트랜잭션/pool 점유가 길다. 단일 `SELECT id,stock FROM products WHERE id IN (...) ORDER BY id FOR UPDATE`로 검증하고, ProductBranch를 bulk 조회/생성한 뒤 Stocks bulkCreate하는 방식을 권장한다.
- N+1 의심: 위 판매 재고 경로 외에 확정적인 connection 폭증 패턴은 찾지 못했다. 크론의 외부 I/O는 대체로 트랜잭션 밖이며 outbox는 순차 처리한다.

## Cron / worker 배수 위험

- **HIGH — 다중 컨테이너 리더 중복**: `src/common/cron/cron-leader.ts:14-20`. `NODE_APP_INSTANCE`가 없는 컨테이너는 모두 리더다. `CRON_ENABLED=false`를 replica마다 수동 설정하지 않으면 outbox, campaign, 정리 작업이 replica 수만큼 실행된다. DB의 `SKIP LOCKED`가 일부 중복을 막아도 claim 쿼리와 pool 부하는 배수로 증가한다. 안전 조치: 전용 scheduler deployment 1개 + API replica는 `CRON_ENABLED=false`, 또는 PG advisory lock 기반 lease를 사용한다. transaction-pooling 환경에서는 session lock이 아니라 짧은 transaction-scoped advisory lock을 사용해야 한다.
- **MEDIUM — slow-query 버퍼 유실**: `src/app/diagnostics/diagnostics.cron.ts:14-23`은 `@Cron`이라 리더에서만 실행되지만 버퍼는 프로세스 로컬(`src/app/diagnostics/slow-query-buffer.ts`)이다. 비리더 worker의 slow query가 flush되지 않는다. `AdminConsoleCron`과 같은 per-worker `setInterval` flush 패턴을 적용하고 prune만 리더에 남기는 것이 안전하다.
- 크론 중첩 방어: campaign sender, outbox, online-order expiry, segment refresh는 프로세스 내 `running/finally` 가드가 확인됐다. 다만 이 가드는 컨테이너 간 중복 실행을 막지 않는다.

## Snake_case 일관성

- 전역 `underscored: true`: `src/database/database.module.ts:37-40` ✓.
- 점검한 raw SQL은 snake_case를 사용했다. 확인된 camelCase 직접 SQL 위반은 없다.

## PostgreSQL 18 호환성

- 점검한 `ON CONFLICT`, `FOR UPDATE SKIP LOCKED`, CTE, `bool_or`, transaction-scoped 쿼리는 PG18 호환이다.
- 과거 PG10 제약을 전제로 한 변경은 필요 없다. 이번 점검에서는 마이그레이션/DDL 변경 없음.
- `synchronize:false`는 안전하다(`src/database/database.module.ts:41`). 다만 최신 error 로그에 과거 `sequelize.sync`의 view 의존 컬럼 alter 실패가 반복되어, `SyncService`가 어떤 조건에서 sync를 호출하는지는 별도 운영 설정 확인이 필요하다.

## 최신 로그 관찰

- `api-ventago/logs/error-2026-07-29.log`: `sequelize.sync`가 view/rule 의존 컬럼 타입을 변경하려다 반복 실패했고, `client_segments.store_id NOT NULL` 위반 및 `Store.telegram_chat_id` 불일치가 기록됐다. 이는 직접 pool leak은 아니지만 반복 startup sync/cron 실패로 불필요한 DB 작업을 만든다.
- `ventago-app/logs/error-2026-07-30.log`: webpack deprecation warning뿐이며 DB 관련 내용 없음.
- 로그상 pool 고갈은 없지만, 관측 기간의 유휴 상태만으로 피크 안전성을 보장할 수 없다.

## 권장 조치

1. 공개몰 격리를 명시적 검증 플래그로 바꾸고 동일 PG이면 shop pool 상한 5를 유지한다. 메인 pool max는 그대로 둔다.
2. 운영에서 읽기 전용으로 outbox/campaign/online_orders 쿼리의 `EXPLAIN (ANALYZE, BUFFERS)`와 `pg_stat_statements`를 수집해 partial index 사용 여부를 검증한다.
3. cron을 전용 단일 scheduler로 분리하거나 transaction advisory lock으로 리더를 보장한다.
4. slow-query flush는 worker별로 수행하고 prune만 리더에서 수행한다.
5. 판매 재고 쿼리를 정렬 bulk lock/bulk insert로 바꿔 트랜잭션 점유 시간을 줄인다.
6. 운영 설정에서 자동 `sequelize.sync`를 완전히 비활성화하고 migration-only 정책을 검증한다.

## 변경/실행 여부

- 애플리케이션 코드 변경 없음.
- DB 조회/변경 SQL 실행 없음.
- pool max 변경 없음.
