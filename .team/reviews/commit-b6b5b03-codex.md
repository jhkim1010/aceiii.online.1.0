OpenAI Codex v0.146.0
--------
workdir: /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago
model: gpt-5.6-sol
provider: openai
approval: never
sandbox: read-only
reasoning effort: none
reasoning summaries: none
session id: 019fdbea-f272-7cd2-8650-ea58c566b3f1
--------
user
commit b6b5b03
exec
/bin/zsh -lc 'git status --short && find .. -name AGENTS.md -o -name AGENTS.override.md && git show --stat --oneline --decorate --no-renames b6b5b0356d1450326b10aa31b43a33b0d6ee9b22 && git diff --no-ext-diff --unified=80 b6b5b0356d1450326b10aa31b43a33b0d6ee9b22''^ b6b5b0356d1450326b10aa31b43a33b0d6ee9b22 --' in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago
 succeeded in 4378ms:
2026-08-07 08:10:43.270 xcodebuild[24515:969330]  DVTFilePathFSEvents: Failed to start fs event stream.
2026-08-07 08:10:43.371 xcodebuild[24515:969329] [MT] DVTDeveloperPaths: Failed to get length of DARWIN_USER_CACHE_DIR from confstr(3), error = Error Domain=NSPOSIXErrorDomain Code=5 "Input/output error". Using NSCachesDirectory instead.
git: warning: confstr() failed with code 5: couldn't get path of DARWIN_USER_TEMP_DIR; using /tmp instead
git: error: couldn't create cache file '/tmp/xcrun_db-EdVSl8qo' (errno=Operation not permitted)
2026-08-07 08:10:43.686 xcodebuild[24523:969348]  DVTFilePathFSEvents: Failed to start fs event stream.
2026-08-07 08:10:43.785 xcodebuild[24523:969347] [MT] DVTDeveloperPaths: Failed to get length of DARWIN_USER_CACHE_DIR from confstr(3), error = Error Domain=NSPOSIXErrorDomain Code=5 "Input/output error". Using NSCachesDirectory instead.
 M commit-wave1-security.sh
 M src/app/products/productStock.service.spec.ts
 M src/app/products/productStock.service.ts
?? migrations/000-bootstrap-ventago-database.sql
?? migrations/000-bootstrap-ventago-grants.sql
?? migrations/2026-08-07-daily-ingreso-include-correccion.sql
../node_modules/ts-loader/AGENTS.md
../AGENTS.md
git: warning: confstr() failed with code 5: couldn't get path of DARWIN_USER_TEMP_DIR; using /tmp instead
git: error: couldn't create cache file '/tmp/xcrun_db-8iKcBg8u' (errno=Operation not permitted)
2026-08-07 08:10:45.343 xcodebuild[24535:969387]  DVTFilePathFSEvents: Failed to start fs event stream.
2026-08-07 08:10:45.442 xcodebuild[24535:969386] [MT] DVTDeveloperPaths: Failed to get length of DARWIN_USER_CACHE_DIR from confstr(3), error = Error Domain=NSPOSIXErrorDomain Code=5 "Input/output error". Using NSCachesDirectory instead.
git: warning: confstr() failed with code 5: couldn't get path of DARWIN_USER_TEMP_DIR; using /tmp instead
git: error: couldn't create cache file '/tmp/xcrun_db-IIVJZNMy' (errno=Operation not permitted)
2026-08-07 08:10:45.757 xcodebuild[24543:969404]  DVTFilePathFSEvents: Failed to start fs event stream.
2026-08-07 08:10:45.856 xcodebuild[24543:969403] [MT] DVTDeveloperPaths: Failed to get length of DARWIN_USER_CACHE_DIR from confstr(3), error = Error Domain=NSPOSIXErrorDomain Code=5 "Input/output error". Using NSCachesDirectory instead.
b6b5b03 (HEAD -> main) feat(75-W6-4): API_REPLICA_COUNT + 커넥션 예산 단일 출처
 ecosystem.config.js                        | 16 +++++
 src/app/diagnostics/diagnostics.service.ts | 34 +++++++----
 src/common/config/connection-budget.ts     | 95 ++++++++++++++++++++++++++++++
 src/database/database.module.ts            | 59 ++++---------------
 4 files changed, 144 insertions(+), 60 deletions(-)
git: warning: confstr() failed with code 5: couldn't get path of DARWIN_USER_TEMP_DIR; using /tmp instead
git: error: couldn't create cache file '/tmp/xcrun_db-Hr8XFJyY' (errno=Operation not permitted)
2026-08-07 08:10:46.553 xcodebuild[24547:969441]  DVTFilePathFSEvents: Failed to start fs event stream.
2026-08-07 08:10:46.655 xcodebuild[24547:969440] [MT] DVTDeveloperPaths: Failed to get length of DARWIN_USER_CACHE_DIR from confstr(3), error = Error Domain=NSPOSIXErrorDomain Code=5 "Input/output error". Using NSCachesDirectory instead.
git: warning: confstr() failed with code 5: couldn't get path of DARWIN_USER_TEMP_DIR; using /tmp instead
git: error: couldn't create cache file '/tmp/xcrun_db-ppGlRk6b' (errno=Operation not permitted)
2026-08-07 08:10:46.964 xcodebuild[24555:969458]  DVTFilePathFSEvents: Failed to start fs event stream.
2026-08-07 08:10:47.063 xcodebuild[24555:969457] [MT] DVTDeveloperPaths: Failed to get length of DARWIN_USER_CACHE_DIR from confstr(3), error = Error Domain=NSPOSIXErrorDomain Code=5 "Input/output error". Using NSCachesDirectory instead.
diff --git a/ecosystem.config.js b/ecosystem.config.js
index 04f2143..34fa78c 100644
--- a/ecosystem.config.js
+++ b/ecosystem.config.js
@@ -1,58 +1,74 @@
 // [Phase 75 W6-8] 워커 수 **단일 출처**.
 //
 // 이전에는 `instances` 와 `WEB_CONCURRENCY` 가 따로 하드코딩돼 있었고, 주석이
 // "instances 값을 바꾸면 이 값도 함께 갱신할 것"이라고 사람에게 동기화를 맡겼다.
 // 갈라지면 예산 로그가 **조용히 틀린 값**을 찍는다 — 커넥션이 실제로는 6워커치인데
 // 로그는 4워커치를 보여주는 식이라, 문제를 볼 수 있어야 할 계기판이 문제를 가린다.
 // G3(워커 4→6 증설로 β 감소 실증)이 바로 이 값을 바꾸는 실험이라 특히 위험했다.
 //
 // 바꿀 때는 여기 하나만 바꾼다. `API_WORKERS` 로 재빌드 없이 덮어쓸 수도 있다.
 const WORKERS = Number(process.env.API_WORKERS ?? 4);
 
+// [Phase 75 W6-4] API 노드(=서버) 수. 커넥션 예산은 `노드 × 워커 × (메인+공개몰)` 이라
+//   노드 수를 모르면 예산이 노드 배수만큼 과소 표기된다. 단독 운영이면 1.
+//   Phase 76 병렬 리허설에서 **스위치가 양 노드에 이 값을 함께 올린다**(한쪽만 올리면 예산이 틀린다).
+//
+//   ★ codex 검토(2026-08-07): **기본값을 여기서 주입하지 않는다.**
+//     `API_REPLICA_COUNT: Number(env ?? 1)` 로 두면 아무도 선언하지 않아도 앱은 항상 "1로 선언됨"을
+//     보게 되어 `(미선언)` 경고가 **영원히 뜨지 않는다.** 그러면 2노드 운영 중 스위치가 이 값을
+//     빠뜨렸을 때 예산이 절반으로 찍히는데도 **확정값처럼 보인다** — 계기판이 문제를 가리는
+//     W6-8 과 같은 실패 형태다. 선언이 있을 때만 전달하고, 없으면 앱이 1로 가정하되 '(미선언)'을 찍는다.
+const REPLICAS_RAW = process.env.API_REPLICA_COUNT;
+const REPLICAS_DECLARED = REPLICAS_RAW != null && REPLICAS_RAW !== '';
+
 // [Phase 75 W6-9] pgbouncer 의 `ventago` 풀 크기 — **실측값**이다(추정 아님).
 //   출처: 운영 `/etc/pgbouncer/pgbouncer.ini:118`
 //         `ventago = host=127.0.0.1 port=5434 dbname=ventago pool_size=50`
 //   미설정이면 예산 로그가 `50(추정)` 을 찍는데, **추정값으로는 G5 게이트가 성립하지 않는다.**
 //   ※ pgbouncer 의 pool_size 는 **(db, user) 쌍마다** 적용된다. 이 50 은 앱 계정(coolsistema)
 //     기준이고, `ventago` DB 에는 shop_readonly · ventago_watcher 풀이 별도로 더 붙는다.
 //   pgbouncer.ini 를 바꾸면 이 값도 바꾼다.
 const PGBOUNCER_POOL_SIZE = Number(process.env.PGBOUNCER_POOL_SIZE ?? 50);
 
 module.exports = {
   apps: [
     {
       name: 'api-ventago',
       script: 'dist/main.js',
       // [2026-07-25] instances 1→4. 2026-06-30 stopgap 해제.
       //   당시 문제: socket.io HTTP long-polling 은 한 sid 의 모든 요청이 같은 워커로
       //   가야 하는데 pm2 는 sticky 를 지원하지 않아 "Session ID unknown"(400) 발생 +
       //   워커간 emit 누락.
       //   해제 조건 (모두 충족):
       //     1) print-agent v1.1.0 websocket 전용 (zebra/프론트는 이미 ws 전용)
       //        → 연결이 한 워커에 고정되어 sticky 불필요
       //     2) socket.io Redis 어댑터 (ventago_redis) → 워커간 emit 중계
       //     3) cron/부팅 1회성 작업 리더 가드 (NODE_APP_INSTANCE=0)
       //     4) pool max 80→20 (4워커 × 20 = 80, pgbouncer pool_size=50 과 균형)
       //   8코어 중 4개만 사용 — PG/nginx/기타 컨테이너에 여유를 남긴다.
       //   롤백: WORKERS 를 1 로 되돌리고 재빌드 (구버전 print-agent 사용 중이면 필요).
       instances: WORKERS,
       exec_mode: 'cluster', // 클러스터 모드 유지 (추후 instances 복귀 대비)
       // [2026-07-25] 512M → 2G. 단일 워커라 이 상한에 걸리면 API 전체가 끊기고
       //   모든 WebSocket 이 떨어진다. 평상시 RSS 232MB, 호스트 31GB 중 18GB 유휴라
       //   여유를 크게 준다. 누수 감지용 안전망 역할은 유지.
       max_memory_restart: '2G',
       env: {
         NODE_ENV: 'production',
         PORT: 5002,
 
         // [Phase 66 W6] 워커 총 개수 — database.module 의 커넥션 예산 로그/진단이
         // 이 값으로 워커수×pool 을 계산한다(미설정 시 1로 오인해 예산이 1/4 로 표기됨).
         // ※ pool max 자체는 sequelize 설정(워커당 20)이며 이 값과 무관 — 표기용.
         WEB_CONCURRENCY: WORKERS,
 
+        // [Phase 75 W6-4] 노드 수 — 예산 산식의 첫 항.
+        // 선언이 있을 때만 전달한다(위 주석 참조). 없으면 앱이 1로 가정하고 '(미선언)'을 찍는다.
+        ...(REPLICAS_DECLARED ? { API_REPLICA_COUNT: Number(REPLICAS_RAW) } : {}),
+
         // [Phase 75 W6-9] 예산 로그의 pgbouncer 슬롯 표기 — 위 상수 참조.
         PGBOUNCER_POOL_SIZE,
       },
     },
   ],
 };
diff --git a/src/app/diagnostics/diagnostics.service.ts b/src/app/diagnostics/diagnostics.service.ts
index cd40869..6ed4070 100644
--- a/src/app/diagnostics/diagnostics.service.ts
+++ b/src/app/diagnostics/diagnostics.service.ts
@@ -1,247 +1,257 @@
 import { Injectable, Logger } from '@nestjs/common';
 import { InjectConnection } from '@nestjs/sequelize';
 import { Sequelize } from 'sequelize-typescript';
 import { QueryTypes } from 'sequelize';
-// [Phase 64 W8/R12] 공개몰 pool 실효 상한을 같은 산식으로 계산
-import { resolveShopPoolBudget } from '../shop-public/shop-readonly-db.service';
+// [Phase 75 W6-4] 커넥션 예산 단일 출처 — 부팅 로그와 이 엔드포인트가 같은 값을 쓴다
+import { resolveConnectionBudget } from '../../common/config/connection-budget';
 import {
   drainSlowQueries,
   clearSlowQueryBuffer,
   pendingBufferSize,
   droppedBufferCount,
 } from './slow-query-buffer';
 
 // 진단 데이터 조회/영속 서비스 (superadmin 관측 페이지).
 // - flushBuffer: 인메모리 느린쿼리 버퍼를 배치로 slow_query_log 에 INSERT (cron 10초).
 // - pruneOld: 보존기간 초과 행 삭제 (cron 일 1회).
 // - getSlowQueries / getPoolStatus / getOutboxStatus: 조회 API.
 // pool 규칙: 조회는 raw SELECT, pool 상태는 인메모리 카운터 — 추가 커넥션 미점유.
 
 export interface SlowQueryRow {
   id: number;
   qid: number;
   duration_ms: number;
   query_type: string;
   table_name: string | null;
   sql: string;
   instance: string | null;
   created_at: Date;
 }
 
 export interface PoolStatus {
   size: number;
   using: number;
   available: number;
   waiting: number;
   min: number;
   max: number;
   usagePct: number;
   bufferPending: number;
   bufferDropped: number;
   // [Phase 64 W8/R12] 앱 전체 커넥션 예산 — 공개몰 pool 을 포함한 합산치.
   // 부하 시 병목은 앱 pool 이 아니라 pgbouncer 서버 슬롯이므로 예산을 눈으로 확인해야 한다.
   budget: {
+    /** [Phase 75 W6-4] API 노드 수 — 2호기 도입 시 예산이 노드 배수로 늘어난다 */
+    replicas: number;
     workers: number;
     mainMax: number;
     shopMax: number;
+    /** 노드 1대가 쓰는 클라이언트 수 */
+    perNode: number;
     totalClients: number;
     shopIsolated: boolean;
+    /** 미선언이면 추정값이라 G5 판정 근거가 되지 못한다 */
+    replicasDeclared: boolean;
+    workersDeclared: boolean;
+    pgbouncerPoolSize: string;
   };
 }
 
 export interface OutboxStatus {
   counts: Record<string, number>;
   oldestPendingSecs: number | null;
   failed: {
     id: number;
     channel_id: number;
     op_type: string;
     attempts: number;
     max_attempts: number;
     last_error: string | null;
   }[];
 }
 
 interface PoolLike {
   size?: number;
   available?: number;
   using?: number;
   waiting?: number;
 }
 
 // slow_query_log INSERT 컬럼 수 (bind 오프셋 계산용)
 const INSERT_COLS = 7;
 // 보존 기간(일) — 초과 행은 prune
 const RETENTION_DAYS = 7;
 
 @Injectable()
 export class DiagnosticsService {
   private readonly logger = new Logger('Diagnostics');
 
   constructor(@InjectConnection() private readonly sequelize: Sequelize) {}
 
   // 버퍼 → slow_query_log 배치 INSERT. 반환: 기록한 행 수.
   async flushBuffer(): Promise<number> {
     const entries = drainSlowQueries();
     if (!entries.length) return 0;
 
     const placeholders = entries
       .map((_, i) => {
         const b = i * INSERT_COLS;
 
         return `($${b + 1},$${b + 2},$${b + 3},$${b + 4},$${b + 5},$${b + 6},$${b + 7})`;
       })
       .join(',');
 
     const bind: (string | number | Date | null)[] = [];
     for (const e of entries) {
       bind.push(
         e.qid,
         e.durationMs,
         e.queryType,
         e.tableName,
         e.sql,
         e.instance,
         e.createdAt,
       );
     }
 
     try {
       await this.sequelize.query(
         `INSERT INTO slow_query_log
            (qid, duration_ms, query_type, table_name, sql, instance, created_at)
          VALUES ${placeholders}`,
         { bind, type: QueryTypes.INSERT },
       );
 
       return entries.length;
     } catch (e: unknown) {
       // 진단 데이터라 소실 허용 — 판매/운영 흐름 막지 않음
       const msg = e instanceof Error ? e.message : String(e);
       this.logger.warn(
         `slow_query_log flush 실패 (${entries.length}건 소실): ${msg}`,
       );
 
       return 0;
     }
   }
 
   // 보존기간 초과 행 삭제. 반환: 삭제 행 수.
   async pruneOld(): Promise<number> {
     const [, meta] = await this.sequelize.query(
       `DELETE FROM slow_query_log WHERE created_at < now() - interval '${RETENTION_DAYS} days'`,
     );
     const rowCount = (meta as { rowCount?: number })?.rowCount ?? 0;
     if (rowCount > 0) {
       this.logger.log(
         `slow_query_log prune: ${rowCount}건 삭제 (>${RETENTION_DAYS}일)`,
       );
     }
 
     return rowCount;
   }
 
   // 느린쿼리 목록 조회 (테이블/최소지속시간 필터, 최신순).
   // 느린쿼리 로그 완전 삭제 (사용자 수동 clear — 이후 새로 쌓이는 것만 보이도록).
   // 인메모리 버퍼도 함께 비워 직후 flush 로 되살아나지 않게 한다.
   async clearSlowQueries(): Promise<{ ok: boolean; bufferCleared: number }> {
     const bufferCleared = clearSlowQueryBuffer();
     await this.sequelize.query('DELETE FROM slow_query_log', {
       type: QueryTypes.RAW,
     });
     this.logger.log(
       `slow_query_log 수동 clear (버퍼 ${bufferCleared}건 폐기 + 전체 삭제)`,
     );
 
     return { ok: true, bufferCleared };
   }
 
   async getSlowQueries(opts: {
     table?: string;
     minMs?: number;
     limit?: number;
   }): Promise<SlowQueryRow[]> {
     const limit = Math.min(Math.max(opts.limit ?? 100, 1), 500);
     const minMs = opts.minMs ?? 100;
     const table = opts.table?.trim() || null;
 
     return this.sequelize.query<SlowQueryRow>(
       `SELECT id, qid, duration_ms, query_type, table_name, sql, instance, created_at
          FROM slow_query_log
         WHERE (:table::text IS NULL OR table_name = :table)
           AND duration_ms >= :minMs
         ORDER BY created_at DESC
         LIMIT :limit`,
       { replacements: { table, minMs, limit }, type: QueryTypes.SELECT },
     );
   }
 
   // 커넥션 pool 실시간 상태 (인메모리 — 추가 커넥션 미점유).
   getPoolStatus(): PoolStatus {
     const cm = this.sequelize.connectionManager as unknown as {
       pool?: PoolLike;
     };
     const pool = cm.pool ?? {};
     const cfg = this.sequelize.config as unknown as {
       pool?: { max?: number; min?: number };
     };
 
     const size = pool.size ?? 0;
     const using = pool.using ?? 0;
     const available = pool.available ?? 0;
     const waiting = pool.waiting ?? 0;
     const max = cfg.pool?.max ?? 80;
     const min = cfg.pool?.min ?? 10;
     const usagePct = max > 0 ? Math.round((using / max) * 100) : 0;
 
-    // [Phase 64 W8/R12] 공개몰 pool 은 메인과 별도 예산이라 합산해서 노출한다
-    const shop = resolveShopPoolBudget();
-    const workers = Number(
-      process.env.WEB_CONCURRENCY ?? process.env.PM2_INSTANCES ?? 1,
-    );
+    // [Phase 75 W6-4] 예산은 단일 출처에서 가져온다 — 부팅 로그와 같은 숫자여야 한다.
+    const budget = resolveConnectionBudget(max);
 
     return {
       size,
       using,
       available,
       waiting,
       min,
       max,
       usagePct,
       bufferPending: pendingBufferSize(),
       bufferDropped: droppedBufferCount(),
       budget: {
-        workers,
-        mainMax: max,
-        shopMax: shop.effectiveMax,
-        totalClients: workers * (max + shop.effectiveMax),
-        shopIsolated: shop.isolated,
+        replicas: budget.replicas,
+        workers: budget.workers,
+        mainMax: budget.mainMax,
+        shopMax: budget.shopMax,
+        perNode: budget.perNode,
+        totalClients: budget.totalClients,
+        shopIsolated: budget.shopIsolated,
+        replicasDeclared: budget.replicasDeclared,
+        workersDeclared: budget.workersDeclared,
+        pgbouncerPoolSize: budget.pgbouncerPoolSize,
       },
     };
   }
 
   // sync_outbox 상태 (status별 건수 + 최고령 pending 나이 + failed 목록).
   async getOutboxStatus(): Promise<OutboxStatus> {
     const rows = await this.sequelize.query<{ status: string; count: number }>(
       `SELECT status, count(*)::int AS count FROM sync_outbox GROUP BY status`,
       { type: QueryTypes.SELECT },
     );
     const counts: Record<string, number> = {};
     for (const r of rows) counts[r.status] = r.count;
 
     const [oldest] = await this.sequelize.query<{ secs: number | null }>(
       `SELECT EXTRACT(EPOCH FROM (now() - min(next_retry_at)))::int AS secs
          FROM sync_outbox WHERE status = 'pending'`,
       { type: QueryTypes.SELECT },
     );
 
     const failed = await this.sequelize.query<OutboxStatus['failed'][number]>(
       `SELECT id, channel_id, op_type, attempts, max_attempts, last_error
          FROM sync_outbox WHERE status = 'failed'
         ORDER BY id DESC LIMIT 50`,
       { type: QueryTypes.SELECT },
     );
 
     return { counts, oldestPendingSecs: oldest?.secs ?? null, failed };
   }
 }
diff --git a/src/common/config/connection-budget.ts b/src/common/config/connection-budget.ts
new file mode 100644
index 0000000..e6935b2
--- /dev/null
+++ b/src/common/config/connection-budget.ts
@@ -0,0 +1,95 @@
+import { resolveShopPoolBudget } from '../../app/shop-public/shop-readonly-db.service';
+
+/**
+ * [Phase 75 W6-4] 앱 전체 커넥션 예산 — **단일 출처**.
+ *
+ * 이전에는 같은 계산이 두 곳에 따로 있었다:
+ *   - `database.module.ts` `describeConnectionBudget()` (부팅 로그) / `getConnectionBudget()` (호출부 0곳, 죽은 코드)
+ *   - `diagnostics.service.ts` `getPoolStatus().budget` (실제로 `/diagnostics/pool` 로 노출되는 값)
+ * 한쪽만 고치면 **로그와 진단 화면이 다른 숫자를 말한다.** 예산은 "믿고 판단하는 숫자"라
+ * 두 값이 갈라지는 순간 둘 다 못 믿게 된다.
+ *
+ * 산식: `replicas × workers × (메인 pool.max + 공개몰 pool.max)`
+ *
+ * ★ 비교 대상 주의(W0-10 실측): 이 합계는 **앱 → pgbouncer 클라이언트 커넥션**이고
+ * 상한은 `max_client_conn`(운영 1000)이다. `pool_size`(50)는 **pgbouncer → PG 서버** 커넥션의
+ * (db,user) 쌍별 상한이라 층위가 다르다 — 두 값을 같은 자로 재면 정상 구성을 결함으로 오판한다.
+ * 서버측 포화는 숫자 비교가 아니라 `cl_waiting` 으로 판정한다.
+ */
+export interface ConnectionBudget {
+  replicas: number;
+  workers: number;
+  mainMax: number;
+  shopMax: number;
+  /** 노드 1대가 쓰는 클라이언트 수 = workers × (mainMax + shopMax) */
+  perNode: number;
+  /** 전체 = replicas × perNode */
+  totalClients: number;
+  shopIsolated: boolean;
+  /** env 로 명시 선언됐는가 — 추정값이면 게이트(G5) 판정 근거가 되지 못한다 */
+  replicasDeclared: boolean;
+  workersDeclared: boolean;
+  /** pgbouncer 의 (db,user) 쌍별 서버측 상한 — 표기용 */
+  pgbouncerPoolSize: string;
+}
+
+/**
+ * 양의 정수 env 를 읽는다. 유효하지 않으면 **미선언으로 취급**한다.
+ *
+ * codex 검토(2026-08-07): `Number('')`=0 · `Number('abc')`=NaN 인데 "값이 있으니 선언됨"으로
+ * 처리하면, 예산이 **0 이나 NaN 인 채로 확정값처럼** 노출된다. 0 은 "커넥션을 안 쓴다"로,
+ * NaN 은 화면에서 빈칸으로 보이므로 **둘 다 안전한 것처럼 오독된다.**
+ * 잘못된 선언은 선언이 아니다 — 1 로 가정하고 '(미선언)'을 찍어 눈에 띄게 한다.
+ */
+function readPositiveInt(raw: string | undefined): {
+  value: number;
+  declared: boolean;
+} {
+  const n = Number((raw ?? '').trim());
+  const ok = raw != null && raw.trim() !== '' && Number.isInteger(n) && n > 0;
+
+  return { value: ok ? n : 1, declared: ok };
+}
+
+export function resolveConnectionBudget(mainMax: number): ConnectionBudget {
+  const shop = resolveShopPoolBudget();
+
+  // 미선언이면 1 로 가정한다 — 부팅을 막지 않는다. 이 값은 로그·진단 표기용이라
+  // 여기서 throw 하면 표기 하나 때문에 서비스가 안 뜬다. 대신 '(미선언)'을 드러낸다.
+  const { value: replicas, declared: replicasDeclared } = readPositiveInt(
+    process.env.API_REPLICA_COUNT,
+  );
+  const { value: workers, declared: workersDeclared } = readPositiveInt(
+    process.env.WEB_CONCURRENCY ?? process.env.PM2_INSTANCES,
+  );
+
+  // codex 검토(2026-08-07): `perNode` 는 **노드 1대**가 쓰는 클라이언트 수다 —
+  // 워커를 곱해야 한다. 워커 1개분(25)을 노드 전체(100)로 노출하면 진단 화면이
+  // 예산을 1/4 로 보여준다. 이름이 값과 다른 필드는 읽는 사람을 조용히 속인다.
+  const perWorker = mainMax + shop.effectiveMax;
+  const perNode = workers * perWorker;
+
+  return {
+    replicas,
+    workers,
+    mainMax,
+    shopMax: shop.effectiveMax,
+    perNode,
+    totalClients: replicas * perNode,
+    shopIsolated: shop.isolated,
+    replicasDeclared,
+    workersDeclared,
+    pgbouncerPoolSize: process.env.PGBOUNCER_POOL_SIZE ?? '50(추정)',
+  };
+}
+
+/** 부팅 로그·진단에서 같은 문장을 쓰도록 포맷도 여기서 만든다. */
+export function describeConnectionBudget(b: ConnectionBudget): string {
+  return (
+    `커넥션 예산: 노드 ${b.replicas}${b.replicasDeclared ? '' : '(미선언)'} × ` +
+    `워커 ${b.workers}${b.workersDeclared ? '' : '(미선언)'} × ` +
+    `(메인 ${b.mainMax} + 공개몰 ${b.shopMax}) = ${b.totalClients} 클라이언트 | ` +
+    `pgbouncer pool_size=${b.pgbouncerPoolSize}(db,user 쌍별 서버측 상한) | ` +
+    `공개몰 격리=${b.shopIsolated ? 'yes' : 'no'}`
+  );
+}
diff --git a/src/database/database.module.ts b/src/database/database.module.ts
index 01b234e..81f63c7 100644
--- a/src/database/database.module.ts
+++ b/src/database/database.module.ts
@@ -1,281 +1,244 @@
 import { Module, Logger } from '@nestjs/common';
 import { ConfigModule, ConfigService } from '@nestjs/config';
 import { SequelizeModule } from '@nestjs/sequelize';
 import { Sequelize } from 'sequelize-typescript';
 import { SyncService } from './sync.service';
 import { pushSlowQuery } from '../app/diagnostics/slow-query-buffer';
-// [Phase 64 W8/R12] 공개몰 pool 예산을 같은 산식으로 계산하기 위해 재사용
-import { resolveShopPoolBudget } from '../app/shop-public/shop-readonly-db.service';
+// [Phase 75 W6-4] 커넥션 예산 계산·문장 생성의 단일 출처 (로그와 /diagnostics/pool 이 공유)
+import {
+  resolveConnectionBudget,
+  describeConnectionBudget,
+} from '../common/config/connection-budget';
 // [Phase 67] 멀티테넌트 격리 훅 — 모델 전량에 부팅 시 1회 설치
 import { installTenantGuard } from '../common/tenant/tenant-hooks';
 
 // 메인 pool 상한 (아래 pool 설정과 같은 값 — 로그/진단 폴백용)
 const DEFAULT_POOL_MAX = 20;
 
 // Pool 모니터링 인터벌 (ms) — 운영 환경에서는 60초, 개발에서는 30초
 const POOL_MONITOR_INTERVAL =
   process.env.NODE_ENV === 'production' ? 60_000 : 30_000;
 
 // 쿼리 고유번호(QID) 시퀀스 — 프로세스 시작부터 실행되는 모든 쿼리에 1씩 증가하는 번호를 부여.
 // beforeQuery 에서 발급하고 afterQuery 에서 같은 번호로 소요시간을 기록해, 동일 SQL 이
 // 여러 곳에서 호출돼도 어느 실행이 느렸는지 로그에서 개별 추적 가능.
 let querySeq = 0;
 
 @Module({
   imports: [
     SequelizeModule.forRootAsync({
       imports: [ConfigModule],
       inject: [ConfigService],
       useFactory: (configService: ConfigService) => ({
         dialect: 'postgres',
         host: configService.get<string>('host'),
         port: configService.get<number>('port'),
         username: configService.get<string>('username'),
         password: configService.get<string>('password'),
         database: configService.get<string>('database'),
         autoLoadModels: true,
         define: {
           underscored: true,
           timestamps: true,
         },
         synchronize: false,
 
         // ── 세션 TZ 설정 ──
         // 기본값 UTC 시 '2026-04-19'::date + 1 day = UTC 자정 경계가 되어
         // 아르헨티나 21:00 이후 판매(UTC 익일 00:00~)가 보고서 날짜 필터에서 누락됨.
         // DATABASE_TZ env 로 overrride 가능 (운영: 매장 TZ, 개발: 로컬 TZ)
         timezone: process.env.DATABASE_TZ || '-03:00',
 
         // ── PostgreSQL 커넥션 풀 설정 (pgbouncer transaction pooling 경유) ──
         // 앱은 pgbouncer(5432, transaction mode)를 경유해 PG18(5434)에 접속한다.
         // 실제 백엔드 연결 수는 pgbouncer 의 ventago pool_size(2026-07-13: 20→50 상향)로
         // 상한이 걸리므로, 아래 max 는 "앱→pgbouncer" 클라이언트측 상한일 뿐이다.
         // 백엔드는 pgbouncer 가 캡핑 → PG max_connections(2026-07-25: 100→200) 초과 없음.
         // 부하 시 실질 병목은 pgbouncer 서버슬롯 큐잉이며, pool_size 로 조정한다.
         //
         // [2026-07-25] max 80 → 20. 워커 4개 기준 앱 전체 상한 = 4×20 = 80 클라이언트로
         //   pgbouncer ventago pool_size=50 와 균형을 맞춘다. 워커당 80 이면 한 워커가
         //   서버슬롯을 독식해 다른 워커가 acquire 타임아웃(15초)에 걸릴 수 있다.
         pool: {
           min: 2, // 최소 유지 커넥션 (유휴 시 상시 점유 축소 — 실사용 using=1, cold start 무영향)
           max: 20, // 워커당 앱→pgbouncer 클라이언트측 상한 (백엔드는 pool_size=50 으로 캡핑)
           idle: 10000, // 유휴 커넥션 해제 대기 시간 (10초)
           acquire: 15000, // 커넥션 획득 최대 대기 시간 (15초 — 빠른 실패로 UX 개선)
           evict: 1000, // 유휴 커넥션 검사 주기 (1초)
         },
 
         // ── 재연결 설정 ──
         retry: {
           max: 3, // 연결 실패 시 최대 재시도 횟수
         },
 
         // ── 느린 쿼리 디버깅 로그 (100ms 초과 시만, 쿼리별 고유 QID 부여) ──
         // logging 콜백은 실행되는 모든 쿼리마다 호출되므로 여기서 QID 를 1씩 발급한다.
         // 같은 SQL 이 여러 호출부에서 실행돼도 QID 로 로그에서 개별 식별 가능.
         // 500ms 이상은 파라미터까지 보이도록 SQL 전체를, 그 이하는 200자만 기록.
         benchmark: true,
         logging: (sql: string, timing?: number) => {
           // 모든 쿼리에 순번 부여 (100ms 이하도 번호는 소비 — QID 가 실제 실행 순서를 반영)
           const qid = ++querySeq;
           if (!timing || timing <= 100) return;
 
           // 부팅/introspection/DDL 잡음 제외 — 사용자 요청과 무관한 1회성 쿼리가
           // slow_query_log 를 오염시켜 "느린 쿼리 많음"처럼 보이게 하는 것을 방지.
           const _head = sql.trimStart().slice(0, 60).toLowerCase();
           if (
             sql.includes('pg_temp.') ||
             sql.includes('pg_catalog') ||
             sql.includes('information_schema') ||
             /^(create|alter|drop)\b/.test(_head)
           ) {
             return;
           }
 
           const logger = new Logger('SlowQuery');
 
           // 쿼리 유형 분류 (SELECT/INSERT/UPDATE/DELETE/ALTER)
           const upperSql = sql.trimStart().toUpperCase();
           const queryType = upperSql.startsWith('SELECT')
             ? 'SELECT'
             : upperSql.startsWith('INSERT')
               ? 'INSERT'
               : upperSql.startsWith('UPDATE')
                 ? 'UPDATE'
                 : upperSql.startsWith('DELETE')
                   ? 'DELETE'
                   : upperSql.startsWith('ALTER')
                     ? 'ALTER'
                     : upperSql.startsWith('EXECUTED')
                       ? 'EXEC'
                       : 'OTHER';
 
           // 주요 테이블명 추출 (FROM/INTO/UPDATE 뒤 첫 번째 토큰)
           const tableMatch = sql.match(/(?:FROM|INTO|UPDATE)\s+"?(\w+)"?/i);
           const tableName = tableMatch ? tableMatch[1] : '?';
 
           // 500ms 이상은 전체 SQL(파라미터 포함), 그 이하는 200자만
           const sqlOut = timing >= 500 ? sql : sql.slice(0, 200);
           const msg = `[QID=${qid}] [${timing}ms] [${queryType}] table=${tableName} | ${sqlOut}`;
           if (timing >= 500) {
             logger.warn(`🔴 ${msg}`);
           } else {
             logger.warn(msg);
           }
 
           // superadmin 진단 페이지용 버퍼 적재 (10초마다 배치 flush).
           // slow_query_log 자기 자신 INSERT 는 제외 — 재귀 적재/무한 증식 방지.
           if (tableName !== 'slow_query_log') {
             pushSlowQuery({
               qid,
               durationMs: timing,
               queryType,
               tableName: tableName === '?' ? null : tableName,
               sql: sqlOut,
               instance: process.env.NODE_APP_INSTANCE ?? null,
               createdAt: new Date(),
             });
           }
         },
       }),
     }),
   ],
   providers: [SyncService],
   exports: [SequelizeModule],
 })
 export class DatabaseModule {
   private readonly logger = new Logger('DatabasePool');
   private monitorInterval: NodeJS.Timeout;
 
   constructor(private readonly sequelize: Sequelize) {}
 
-  // [Phase 64 W8/R12] 앱 전체 커넥션 예산 산식.
-  //   워커수 × (메인 max + 공개몰 max) ≤ pgbouncer 가 감당하는 클라이언트 수
-  // 공개몰 pool 은 메인과 별도 예산이므로 여기 합산해서 보여준다.
-  //
-  // [Phase 75 W0-10] 비교 대상을 헷갈리지 말 것. 이 합계는 **앱→pgbouncer 클라이언트 수**이고
-  // 상한은 `max_client_conn`(운영 1000) 이다. `pool_size`(50) 는 **pgbouncer→PG 서버 커넥션**의
-  // (db,user) 쌍별 상한이라 다른 층위다. 따라서 `100 > 50` 은 위반이 아니라 설계다 —
-  // pgbouncer 가 다중화하는 지점이 바로 거기다. 이 둘을 같은 자로 재면
-  // 정상 구성을 결함으로 오판한다.
+  // [Phase 75 W6-4] 예산 계산·문장 생성은 `common/config/connection-budget.ts` **단일 출처**다.
+  // 이전에는 여기(로그)와 `diagnostics.service`(/diagnostics/pool)에 같은 산식이 따로 있었고,
+  // 그중 이 클래스의 `getConnectionBudget()` 은 **호출부가 0곳인 죽은 코드**였다.
+  // 한쪽만 고치면 로그와 진단 화면이 다른 숫자를 말한다 — 예산은 믿고 판단하는 숫자라
+  // 두 값이 갈라지는 순간 둘 다 못 믿게 된다.
   private describeConnectionBudget(): string {
     const mainMax = Number(
       (this.sequelize as any).config?.pool?.max ?? DEFAULT_POOL_MAX,
     );
-    const shop = resolveShopPoolBudget();
-    const workersRaw =
-      process.env.WEB_CONCURRENCY ?? process.env.PM2_INSTANCES ?? null;
-    const workers = Number(workersRaw ?? 1);
-    const total = workers * (mainMax + shop.effectiveMax);
-    const poolSize = process.env.PGBOUNCER_POOL_SIZE ?? '50(추정)';
 
-    return (
-      `커넥션 예산: 워커 ${workers}${workersRaw ? '' : '(추정)'} × ` +
-      `(메인 ${mainMax} + 공개몰 ${shop.effectiveMax}) = ${total} 클라이언트 | ` +
-      `pgbouncer pool_size=${poolSize}(db,user 쌍별 서버측 상한) | ` +
-      `공개몰 격리=${shop.isolated ? 'yes' : 'no'}`
-    );
-  }
-
-  // 진단 엔드포인트 노출용 — 로그와 같은 값을 구조화해서 돌려준다
-  getConnectionBudget(): {
-    mainMax: number;
-    shopMax: number;
-    workers: number;
-    totalClients: number;
-    shopIsolated: boolean;
-  } {
-    const mainMax = Number(
-      (this.sequelize as any).config?.pool?.max ?? DEFAULT_POOL_MAX,
-    );
-    const shop = resolveShopPoolBudget();
-    const workers = Number(
-      process.env.WEB_CONCURRENCY ?? process.env.PM2_INSTANCES ?? 1,
-    );
-
-    return {
-      mainMax,
-      shopMax: shop.effectiveMax,
-      workers,
-      totalClients: workers * (mainMax + shop.effectiveMax),
-      shopIsolated: shop.isolated,
-    };
+    return describeConnectionBudget(resolveConnectionBudget(mainMax));
   }
 
   // 앱 시작 시 Pool 상태 모니터링 시작
   onModuleInit() {
     this.logger.log(
       `Pool 설정: min=${(this.sequelize as any).config?.pool?.min ?? '?'}, ` +
         `max=${(this.sequelize as any).config?.pool?.max ?? '?'}, ` +
         `idle=${(this.sequelize as any).config?.pool?.idle ?? '?'}ms`,
     );
 
     // [Phase 64 W8/R12] 총 커넥션 예산을 한 줄로 보이게 한다.
     // 부하 시 실질 병목은 앱 pool 이 아니라 pgbouncer 서버 슬롯 큐잉이다(Phase 63 실측) —
     // 그래서 앱 max 를 올리는 대응은 금물이고, 예산을 눈으로 확인할 수 있어야 한다.
     this.logger.log(this.describeConnectionBudget());
 
     // ── [DEBUG] Sequelize 에 실제 등록된 모델 전량 덤프 ──
     // VendorEtapa 같은 association 에러의 근본 원인을 찾기 위한 진단 로그
     try {
       const modelsMap = (this.sequelize as any).models ?? {};
       const modelNames = Object.keys(modelsMap).sort();
       const debugLogger = new Logger('SequelizeModels');
       debugLogger.log(`총 등록된 모델 수: ${modelNames.length}`);
       debugLogger.log(`등록된 모델 목록: ${modelNames.join(', ')}`);
 
       // subcon 도메인 관련 모델이 실제 올라왔는지 개별 체크
       const criticalModels = [
         'Vendor',
         'Etapa',
         'VendorEtapa',
         'SubconOrder',
         'Envio',
         'Lote',
       ];
       for (const name of criticalModels) {
         const exists = modelNames.includes(name);
         if (exists) {
           debugLogger.log(`  ✓ ${name} 등록됨`);
         } else {
           debugLogger.error(`  ✗ ${name} 누락! — association 에러 원인 가능`);
         }
       }
     } catch (err) {
       this.logger.error('모델 덤프 실패:', err);
     }
 
     // ── [Phase 67] 멀티테넌트 격리 훅 설치 ──
     // storeId 를 가진 모델 전량에 read/write 훅을 건다. 컨트롤러가 storeId 를
     // 빠뜨려도 ORM 레이어에서 차단된다. 훅은 커넥션을 새로 열지 않으므로 pool 무영향.
     try {
       const guard = installTenantGuard(this.sequelize);
       const guardLogger = new Logger('TenantGuard');
       const msg =
         `격리 훅 설치 완료 — mode=${guard.mode} 보호모델=${guard.guarded} ` +
         `(글로벌행 허용 ${guard.globalRowTables}) 제외=${guard.skipped} ` +
         `| 파생스코프 derivedMode=${guard.derivedMode} 대상=${guard.derived}`;
 
       if (guard.mode === 'enforce') {
         guardLogger.log(msg);
       } else {
         guardLogger.warn(`${msg} ⚠️ enforce 아님 — 타 매장 접근이 차단되지 않음`);
       }
     } catch (err) {
       // 격리 훅 설치 실패는 보안 결함이므로 조용히 넘기지 않고 크게 남긴다
       this.logger.error('❌ 멀티테넌트 격리 훅 설치 실패:', err);
     }
 
     // 주기적 Pool 상태 로깅
     this.monitorInterval = setInterval(() => {
       const pool = (this.sequelize as any).connectionManager?.pool;
       if (!pool) return;
 
       const size = pool.size ?? 0;
       const available = pool.available ?? 0;
       const using = pool.using ?? 0;
       const waiting = pool.waiting ?? 0;
       // pool.max는 sequelize config 값 사용 (오류 방지용 fallback 80)
       const maxConn = (this.sequelize as any).config?.pool?.max ?? 80;
       const usagePct = maxConn > 0 ? Math.round((using / maxConn) * 100) : 0;
 
       const stat = `size=${size} using=${using}(${usagePct}%) available=${available} waiting=${waiting} max=${maxConn}`;

exec
/bin/zsh -lc "cat ../AGENTS.md; cat package.json; grep -R \"PoolStatus\\|budget\\.\" -n src test 2>/dev/null | head -100; sed -n '1,240p' src/app/shop-public/shop-readonly-db.service.ts; git show b6b5b035"'^:ecosystem.config.js | head -80' in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago
 succeeded in 1212ms:
git: warning: confstr() failed with code 5: couldn't get path of DARWIN_USER_TEMP_DIR; using /tmp instead
git: error: couldn't create cache file '/tmp/xcrun_db-LGPbngUH' (errno=Operation not permitted)
2026-08-07 08:10:53.753 xcodebuild[24640:969678]  DVTFilePathFSEvents: Failed to start fs event stream.
2026-08-07 08:10:53.853 xcodebuild[24640:969677] [MT] DVTDeveloperPaths: Failed to get length of DARWIN_USER_CACHE_DIR from confstr(3), error = Error Domain=NSPOSIXErrorDomain Code=5 "Input/output error". Using NSCachesDirectory instead.
git: warning: confstr() failed with code 5: couldn't get path of DARWIN_USER_TEMP_DIR; using /tmp instead
git: error: couldn't create cache file '/tmp/xcrun_db-X4gRz5n8' (errno=Operation not permitted)
2026-08-07 08:10:54.162 xcodebuild[24642:969686]  DVTFilePathFSEvents: Failed to start fs event stream.
2026-08-07 08:10:54.261 xcodebuild[24642:969685] [MT] DVTDeveloperPaths: Failed to get length of DARWIN_USER_CACHE_DIR from confstr(3), error = Error Domain=NSPOSIXErrorDomain Code=5 "Input/output error". Using NSCachesDirectory instead.
// [Phase 75 W6-8] 워커 수 **단일 출처**.
//
// 이전에는 `instances` 와 `WEB_CONCURRENCY` 가 따로 하드코딩돼 있었고, 주석이
// "instances 값을 바꾸면 이 값도 함께 갱신할 것"이라고 사람에게 동기화를 맡겼다.
// 갈라지면 예산 로그가 **조용히 틀린 값**을 찍는다 — 커넥션이 실제로는 6워커치인데
// 로그는 4워커치를 보여주는 식이라, 문제를 볼 수 있어야 할 계기판이 문제를 가린다.
// G3(워커 4→6 증설로 β 감소 실증)이 바로 이 값을 바꾸는 실험이라 특히 위험했다.
//
// 바꿀 때는 여기 하나만 바꾼다. `API_WORKERS` 로 재빌드 없이 덮어쓸 수도 있다.
const WORKERS = Number(process.env.API_WORKERS ?? 4);

// [Phase 75 W6-9] pgbouncer 의 `ventago` 풀 크기 — **실측값**이다(추정 아님).
//   출처: 운영 `/etc/pgbouncer/pgbouncer.ini:118`
//         `ventago = host=127.0.0.1 port=5434 dbname=ventago pool_size=50`
//   미설정이면 예산 로그가 `50(추정)` 을 찍는데, **추정값으로는 G5 게이트가 성립하지 않는다.**
//   ※ pgbouncer 의 pool_size 는 **(db, user) 쌍마다** 적용된다. 이 50 은 앱 계정(coolsistema)
//     기준이고, `ventago` DB 에는 shop_readonly · ventago_watcher 풀이 별도로 더 붙는다.
//   pgbouncer.ini 를 바꾸면 이 값도 바꾼다.
const PGBOUNCER_POOL_SIZE = Number(process.env.PGBOUNCER_POOL_SIZE ?? 50);

module.exports = {
  apps: [
    {
      name: 'api-ventago',
      script: 'dist/main.js',
      // [2026-07-25] instances 1→4. 2026-06-30 stopgap 해제.
      //   당시 문제: socket.io HTTP long-polling 은 한 sid 의 모든 요청이 같은 워커로
      //   가야 하는데 pm2 는 sticky 를 지원하지 않아 "Session ID unknown"(400) 발생 +
      //   워커간 emit 누락.
      //   해제 조건 (모두 충족):
      //     1) print-agent v1.1.0 websocket 전용 (zebra/프론트는 이미 ws 전용)
      //        → 연결이 한 워커에 고정되어 sticky 불필요
      //     2) socket.io Redis 어댑터 (ventago_redis) → 워커간 emit 중계
      //     3) cron/부팅 1회성 작업 리더 가드 (NODE_APP_INSTANCE=0)
      //     4) pool max 80→20 (4워커 × 20 = 80, pgbouncer pool_size=50 과 균형)
      //   8코어 중 4개만 사용 — PG/nginx/기타 컨테이너에 여유를 남긴다.
      //   롤백: WORKERS 를 1 로 되돌리고 재빌드 (구버전 print-agent 사용 중이면 필요).
      instances: WORKERS,
      exec_mode: 'cluster', // 클러스터 모드 유지 (추후 instances 복귀 대비)
      // [2026-07-25] 512M → 2G. 단일 워커라 이 상한에 걸리면 API 전체가 끊기고
      //   모든 WebSocket 이 떨어진다. 평상시 RSS 232MB, 호스트 31GB 중 18GB 유휴라
      //   여유를 크게 준다. 누수 감지용 안전망 역할은 유지.
      max_memory_restart: '2G',
      env: {
        NODE_ENV: 'production',
        PORT: 5002,

        // [Phase 66 W6] 워커 총 개수 — database.module 의 커넥션 예산 로그/진단이
        // 이 값으로 워커수×pool 을 계산한다(미설정 시 1로 오인해 예산이 1/4 로 표기됨).
        // ※ pool max 자체는 sequelize 설정(워커당 20)이며 이 값과 무관 — 표기용.
        WEB_CONCURRENCY: WORKERS,

        // [Phase 75 W6-9] 예산 로그의 pgbouncer 슬롯 표기 — 위 상수 참조.
        PGBOUNCER_POOL_SIZE,
      },
    },
  ],
};

codex
변경된 커넥션 예산 계산은 노드·워커·메인/공개몰 풀을 일관되게 합산하며, 부팅 로그와 진단 엔드포인트가 동일한 계산 경로를 사용합니다. 기존 동작을 깨뜨릴 명확한 정확성, 보안 또는 성능 결함은 확인되지 않았습니다.
