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

-- 오프라인 쓰기 outbox (Wave B: 판매 캡처 → 복구 시 push)
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

-- Wave B 증분 컬럼 (기존 설치 호환 — IF NOT EXISTS 멱등)
ALTER TABLE offline_outbox ADD COLUMN IF NOT EXISTS offline_number TEXT;
ALTER TABLE offline_outbox ADD COLUMN IF NOT EXISTS original_at TIMESTAMPTZ;
ALTER TABLE offline_outbox ADD COLUMN IF NOT EXISTS result JSONB;

-- [P0-2 2026-10-20] ningún error es final: se reintenta con espera creciente (next_attempt_at).
ALTER TABLE offline_outbox ADD COLUMN IF NOT EXISTS next_attempt_at TIMESTAMPTZ;
-- [P0-3 2026-10-20] Idempotency-Key del POS: el mismo cobro reenviado a la Guardia no crea otra op,
--   y el servidor lo usa para ver si la venta ya entró por la nube antes del corte.
ALTER TABLE offline_outbox ADD COLUMN IF NOT EXISTS idempotency_key TEXT;
-- [CODEX] misma clave con OTRA venta no se descarta en silencio: se compara el hash del cuerpo.
ALTER TABLE offline_outbox ADD COLUMN IF NOT EXISTS body_hash TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS uq_offline_outbox_idem
  ON offline_outbox (idempotency_key) WHERE idempotency_key IS NOT NULL;

-- edge 메타 저장 (manifest 영속 — 오프라인 재기동 시 branch/store 식별 유지)
CREATE TABLE IF NOT EXISTS edge_meta (
  key        TEXT PRIMARY KEY,
  value      JSONB NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
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
    // [2026-10-20] dos reemplazos a la vez chocaban en la PK — el segundo espera al primero.
    await client.query('LOCK TABLE mirror_stock IN EXCLUSIVE MODE');
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

// ── edge 메타 (manifest 영속) ──
async function saveMeta(key, value) {
  await getPool().query(
    `INSERT INTO edge_meta (key, value, updated_at) VALUES ($1, $2, now())
     ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()`,
    [key, JSON.stringify(value)],
  );
}

async function loadMeta(key) {
  const res = await getPool().query('SELECT value FROM edge_meta WHERE key = $1', [key]);

  return res.rows[0]?.value ?? null;
}

// ── Wave B: offline_outbox 헬퍼 ──

// 판매 op 기록 — seq 반환 (오프라인 영수증 번호 재료)
// [P0-3] idempotencyKey 가 이미 있으면 새 op 를 만들지 않고 그 op 를 돌려준다(existing=true).
async function insertOutboxOp({ opType, uuid, payload, offlineNumber, originalAt, idempotencyKey, bodyHash }) {
  const res = await getPool().query(
    `INSERT INTO offline_outbox (op_type, uuid, payload, offline_number, original_at, idempotency_key, body_hash)
     VALUES ($1, $2, $3, $4, $5, $6, $7)
     ON CONFLICT (idempotency_key) WHERE idempotency_key IS NOT NULL DO NOTHING
     RETURNING seq`,
    [
      opType,
      uuid,
      JSON.stringify(payload),
      offlineNumber || null,
      originalAt || new Date(),
      idempotencyKey || null,
      bodyHash || null,
    ],
  );

  if (res.rows.length === 0) {
    const prev = await getPool().query(
      `SELECT seq, uuid, offline_number, original_at, body_hash FROM offline_outbox WHERE idempotency_key = $1`,
      [idempotencyKey],
    );
    const row = prev.rows[0];

    // misma clave, otra venta: no se devuelve la anterior como si fuera ésta (se perdería)
    if (row && row.body_hash && bodyHash && row.body_hash !== bodyHash) {
      log.error(`[outbox] Idempotency-Key reutilizada con otra venta — rechazada (seq=${row.seq})`);

      return { conflict: true };
    }
    log.warn(`[outbox] same Idempotency-Key — reusing op seq=${row?.seq} uuid=${row?.uuid}`);

    return {
      seq: Number(row?.seq),
      existing: true,
      uuid: row?.uuid,
      offlineNumber: row?.offline_number,
      originalAt: row?.original_at,
    };
  }

  const seq = Number(res.rows[0].seq);
  log.info(`[outbox] +op seq=${seq} type=${opType} uuid=${uuid} num=${offlineNumber || '-'}`);

  return { seq, existing: false, uuid, offlineNumber, originalAt };
}

// push 대기 op — seq 순서, 대기 시간이 지난 것만.
// [P0-2 2026-10-20] 종전 `status='pending' AND attempts < 8` 은 거부 1번(error) 또는 실패 8번이면
//   그 판매를 **영영** 안 보냈다 — 물건은 나갔는데 장부에 없는 판매. 이제 error 도 다시 보내고
//   상한 대신 next_attempt_at(최대 30분 간격)으로 늦춘다. 'unsupported'(서버가 모르는 op)만 멈춘다.
async function getPendingOutbox(limit = 20) {
  const res = await getPool().query(
    `SELECT seq, op_type, uuid, payload, attempts, offline_number, original_at, idempotency_key
     FROM offline_outbox
     WHERE status IN ('pending', 'error')
       AND (next_attempt_at IS NULL OR next_attempt_at <= now())
     ORDER BY seq ASC LIMIT $1`,
    [limit],
  );

  return res.rows;
}

// 다음 재시도까지 대기 — attempts(이번 실패 **전**의 값) 기준 20s·40s·80s… 최대 30분.
// (UPDATE 의 SET 안에서 attempts 는 증가 전 값이다.)
// SQL 의 next_attempt_at 계산과 같은 식이다(시험은 이 함수로 한다).
const BACKOFF_BASE_S = 20;
const BACKOFF_MAX_S = 30 * 60;

function backoffMs(attempts) {
  const n = Math.max(0, Math.min(Number(attempts) || 0, 10));

  return Math.min(BACKOFF_BASE_S * 2 ** n, BACKOFF_MAX_S) * 1000;
}

// push 결과 반영 — 실패(bumpAttempt)면 attempts+1 과 함께 다음 시도 시각을 늦춘다.
async function markOutboxResult(uuid, { status, result, error, bumpAttempt }) {
  await getPool().query(
    `UPDATE offline_outbox SET
       status = COALESCE($2, status),
       result = COALESCE($3, result),
       last_error = $4,
       attempts = attempts + $5,
       next_attempt_at = CASE WHEN $5 = 1
         THEN now() + make_interval(secs => LEAST($6 * power(2, LEAST(attempts, 10)), $7))
         ELSE next_attempt_at END,
       pushed_at = CASE WHEN $2 = 'done' THEN now() ELSE pushed_at END
     WHERE uuid = $1`,
    [
      uuid,
      status || null,
      result ? JSON.stringify(result) : null,
      error || null,
      bumpAttempt ? 1 : 0,
      BACKOFF_BASE_S,
      BACKOFF_MAX_S,
    ],
  );
  log.debug(`[outbox] mark uuid=${uuid} status=${status || '(keep)'} err=${error || '-'}`);
}

// [2026-10-24] actualización: ventas offline que todavía tienen que subir (bloquean el cambio de versión)
async function countPendingOutbox() {
  const res = await getPool().query(`SELECT count(*)::int AS n FROM offline_outbox WHERE status = 'pending'`);

  return res.rows[0].n;
}

// [P0-2] 사람이 보는 목록과 「지금 다시 보내기」 — 끝나지 않은 op 전부.
async function listUnfinishedOutbox(limit = 200) {
  const res = await getPool().query(
    `SELECT seq, uuid, op_type, status, attempts, last_error, offline_number, original_at, next_attempt_at
       FROM offline_outbox WHERE status <> 'done' ORDER BY seq ASC LIMIT $1`,
    [limit],
  );

  return res.rows;
}

async function retryOutboxNow(uuid) {
  const res = await getPool().query(
    `UPDATE offline_outbox SET status = 'pending', next_attempt_at = NULL
      WHERE uuid = $1 AND status <> 'done' RETURNING uuid`,
    [uuid],
  );

  return res.rowCount > 0;
}

// 로컬 재고 차감 (best-effort — 서버가 push 재적용 시 진실 재계산)
async function applyLocalStockDelta(items) {
  let applied = 0;

  for (const item of items || []) {
    const pbId = Number(item.productBranchId ?? item.product_branch_id);
    const qty = Number(item.quantity ?? item.qty ?? 0);

    if (!pbId || !qty) {
      log.warn(`[stock-delta] skipped item (productBranchId/quantity 없음): ${JSON.stringify(item).slice(0, 120)}`);
      continue;
    }

    const res = await getPool().query(
      `UPDATE mirror_stock SET qty = qty - $2, snapshot_at = now() WHERE product_branch_id = $1`,
      [pbId, qty],
    );
    if (res.rowCount === 0) {
      log.warn(`[stock-delta] mirror_stock 에 pb=${pbId} 없음 — 차감 생략 (pull 미완?)`);
    } else {
      applied += 1;
      log.debug(`[stock-delta] pb=${pbId} -${qty}`);
    }
  }

  return applied;
}

async function closeDb() {
  if (pool) {
    log.info('closing local PG pool...');
    await pool.end();
    pool = null;
  }
}

module.exports = {
  countPendingOutbox,
  initDb,
  getPool,
  upsertMirrorRows,
  replaceStockSnapshot,
  pruneMirror,
  getSyncState,
  saveSyncState,
  saveMeta,
  loadMeta,
  insertOutboxOp,
  getPendingOutbox,
  markOutboxResult,
  backoffMs,
  listUnfinishedOutbox,
  retryOutboxNow,
  applyLocalStockDelta,
  closeDb,
};
