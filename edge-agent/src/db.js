// Phase 58 — edge-agent 로컬 PostgreSQL 계층
// 미러 저장 전략: 테이블별 DDL 복제 대신 JSONB 제네릭 미러 —
// 서버 스키마가 바뀌어도 edge 는 무중단 (스키마 드리프트 면역).
// pool 안전 규칙: max 5 / idle 30s / connect timeout 5s, 트랜잭션은 finally release.

const { Pool } = require('pg');
const { createLogger } = require('./logger');

const log = createLogger('DB');

let pool = null;

// 스키마 부트스트랩 DDL — IF NOT EXISTS 로 멱등
const BOOTSTRAP_SQL = `
-- 참조데이터 제네릭 미러 (서버 행을 JSONB 그대로 보관)
CREATE TABLE IF NOT EXISTS mirror_rows (
  table_key   TEXT        NOT NULL,
  id          BIGINT      NOT NULL,
  data        JSONB       NOT NULL,
  updated_at  TIMESTAMPTZ,
  synced_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (table_key, id)
);
CREATE INDEX IF NOT EXISTS idx_mirror_rows_table ON mirror_rows (table_key);

-- 재고 스냅샷 (stocks 원장 SUM 결과)
CREATE TABLE IF NOT EXISTS mirror_stock (
  product_branch_id BIGINT PRIMARY KEY,
  product_id        BIGINT NOT NULL,
  branch_id         BIGINT NOT NULL,
  qty               NUMERIC NOT NULL DEFAULT 0,
  snapshot_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 테이블별 동기화 커서/통계
CREATE TABLE IF NOT EXISTS sync_state (
  table_key      TEXT PRIMARY KEY,
  since_cursor   TIMESTAMPTZ,
  after_id       BIGINT NOT NULL DEFAULT 0,
  row_count      BIGINT NOT NULL DEFAULT 0,
  last_pull_at   TIMESTAMPTZ,
  last_prune_at  TIMESTAMPTZ,
  last_error     TEXT
);

-- 오프라인 쓰기 outbox (Wave B 에서 사용 — 스키마만 선반영)
CREATE TABLE IF NOT EXISTS offline_outbox (
  seq         BIGSERIAL PRIMARY KEY,
  op_type     TEXT  NOT NULL,
  uuid        TEXT  NOT NULL UNIQUE,
  payload     JSONB NOT NULL,
  status      TEXT  NOT NULL DEFAULT 'pending',
  attempts    INT   NOT NULL DEFAULT 0,
  last_error  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  pushed_at   TIMESTAMPTZ
);
`;

async function initDb(cfg) {
  // pool 싱글턴 — 재호출 방지
  if (pool) {
    log.warn('initDb called twice — reusing existing pool');

    return pool;
  }

  pool = new Pool({
    host: cfg.localDb.host,
    port: cfg.localDb.port,
    database: cfg.localDb.database,
    user: cfg.localDb.user,
    password: cfg.localDb.password,
    max: 5,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 5000,
  });

  pool.on('error', (err) => {
    // idle client 에러 — 프로세스 죽이지 않고 로그만
    log.error('idle client error:', err);
  });

  const t0 = Date.now();
  await pool.query('SELECT 1');
  log.info(`local PG connected in ${Date.now() - t0}ms (${cfg.localDb.host}:${cfg.localDb.port}/${cfg.localDb.database})`);

  const t1 = Date.now();
  await pool.query(BOOTSTRAP_SQL);
  log.info(`schema bootstrap done in ${Date.now() - t1}ms`);

  return pool;
}

function getPool() {
  if (!pool) throw new Error('DB not initialized — call initDb first');

  return pool;
}

// 미러 배치 upsert — 한 트랜잭션으로 처리, 실패 시 롤백
async function upsertMirrorRows(tableKey, rows) {
  if (!rows.length) return 0;

  const client = await getPool().connect();
  const t0 = Date.now();

  try {
    await client.query('BEGIN');

    for (const row of rows) {
      await client.query(
        `INSERT INTO mirror_rows (table_key, id, data, updated_at, synced_at)
         VALUES ($1, $2, $3, $4, now())
         ON CONFLICT (table_key, id)
         DO UPDATE SET data = EXCLUDED.data, updated_at = EXCLUDED.updated_at, synced_at = now()`,
        [tableKey, row.id, JSON.stringify(row), row.updated_at || null],
      );
    }

    await client.query('COMMIT');
    log.debug(`[upsert] ${tableKey}: ${rows.length} rows in ${Date.now() - t0}ms`);

    return rows.length;
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    log.error(`[upsert] ${tableKey} failed after ${Date.now() - t0}ms:`, err);
    throw err;
  } finally {
    // pool 고갈 방지 — 에러 여부와 무관하게 반드시 반환
    client.release();
  }
}

// 재고 스냅샷 전체 교체 — 트랜잭션 (DELETE+INSERT)
async function replaceStockSnapshot(rows) {
  const client = await getPool().connect();
  const t0 = Date.now();

  try {
    await client.query('BEGIN');
    await client.query('DELETE FROM mirror_stock');

    for (const r of rows) {
      await client.query(
        `INSERT INTO mirror_stock (product_branch_id, product_id, branch_id, qty, snapshot_at)
         VALUES ($1, $2, $3, $4, $5)`,
        [r.product_branch_id, r.product_id, r.branch_id, r.qty, r.snapshot_at],
      );
    }

    await client.query('COMMIT');
    log.debug(`[stock] snapshot replaced: ${rows.length} rows in ${Date.now() - t0}ms`);

    return rows.length;
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    log.error(`[stock] snapshot replace failed:`, err);
    throw err;
  } finally {
    client.release();
  }
}

// 서버 id 목록에 없는 로컬 미러 행 삭제 (hard delete 전파)
async function pruneMirror(tableKey, serverIds) {
  const t0 = Date.now();

  // 서버 목록이 비면 오작동 방지 위해 skip (전체 삭제 사고 방지 가드)
  if (!serverIds.length) {
    log.warn(`[prune] ${tableKey}: server returned 0 ids — skip (safety guard)`);

    return 0;
  }

  const res = await getPool().query(
    `DELETE FROM mirror_rows WHERE table_key = $1 AND NOT (id = ANY($2::bigint[]))`,
    [tableKey, serverIds],
  );
  if (res.rowCount > 0) {
    log.info(`[prune] ${tableKey}: removed ${res.rowCount} stale rows in ${Date.now() - t0}ms`);
  } else {
    log.debug(`[prune] ${tableKey}: nothing to remove (${Date.now() - t0}ms)`);
  }

  return res.rowCount;
}

// 커서 저장/조회
async function getSyncState(tableKey) {
  const res = await getPool().query('SELECT * FROM sync_state WHERE table_key = $1', [tableKey]);

  return res.rows[0] || null;
}

async function saveSyncState(tableKey, patch) {
  await getPool().query(
    `INSERT INTO sync_state (table_key, since_cursor, after_id, row_count, last_pull_at, last_prune_at, last_error)
     VALUES ($1, $2, $3, $4, $5, $6, $7)
     ON CONFLICT (table_key) DO UPDATE SET
       since_cursor  = COALESCE(EXCLUDED.since_cursor, sync_state.since_cursor),
       after_id      = COALESCE(EXCLUDED.after_id, sync_state.after_id),
       row_count     = COALESCE(EXCLUDED.row_count, sync_state.row_count),
       last_pull_at  = COALESCE(EXCLUDED.last_pull_at, sync_state.last_pull_at),
       last_prune_at = COALESCE(EXCLUDED.last_prune_at, sync_state.last_prune_at),
       last_error    = EXCLUDED.last_error`,
    [
      tableKey,
      patch.since_cursor ?? null,
      patch.after_id ?? null,
      patch.row_count ?? null,
      patch.last_pull_at ?? null,
      patch.last_prune_at ?? null,
      patch.last_error ?? null,
    ],
  );
}

async function closeDb() {
  if (pool) {
    log.info('closing local PG pool...');
    await pool.end();
    pool = null;
  }
}

module.exports = {
  initDb,
  getPool,
  upsertMirrorRows,
  replaceStockSnapshot,
  pruneMirror,
  getSyncState,
  saveSyncState,
  closeDb,
};
