// Phase 58 — edge-agent HTTP 서버
// Wave A 범위: 헬스/상태/미러 조회 (프론트 failover 감지 + 오프라인 카탈로그 조회 기반)
// Wave B 에서 판매 API (nueva-venta 계약 호환) 가 추가된다.

const express = require('express');
const { createLogger } = require('./logger');
const db = require('./db');
const worker = require('./pull-worker');

const log = createLogger('Server');

function buildServer(cfg) {
  const app = express();
  app.use(express.json({ limit: '2mb' }));

  // CORS — 프론트(브라우저)가 LAN 의 edge 로 직접 호출하므로 필수
  app.use((req, res, next) => {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, x-session-token, x-branch-id, x-device-token, x-api-key');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    if (req.method === 'OPTIONS') return res.sendStatus(204);

    return next();
  });

  // 요청 로깅 미들웨어 — 모든 요청의 메서드/경로/상태/소요시간
  app.use((req, res, next) => {
    const t0 = Date.now();
    res.on('finish', () => {
      log.debug(`${req.method} ${req.originalUrl} → ${res.statusCode} (${Date.now() - t0}ms)`);
    });
    next();
  });

  // ── 헬스체크 — 프론트 failover 감지용 (인증 없음, 초경량) ──
  app.get('/api/health', (req, res) => {
    res.json({
      ok: true,
      service: 'ventago-edge-agent',
      version: '0.1.0',
      cloudOnline: worker.isOnline(),
      time: new Date().toISOString(),
    });
  });

  // ── 동기화 상태 대시보드 JSON ──
  app.get('/api/edge/status', async (req, res) => {
    try {
      const syncRows = await db.getPool().query('SELECT * FROM sync_state ORDER BY table_key');
      const stockCount = await db.getPool().query('SELECT COUNT(*)::int AS c FROM mirror_stock');
      const outbox = await db
        .getPool()
        .query(`SELECT status, COUNT(*)::int AS c FROM offline_outbox GROUP BY status`);

      res.json({
        worker: worker.getWorkerStatus(),
        tables: syncRows.rows,
        stockRows: stockCount.rows[0].c,
        outbox: outbox.rows,
        time: new Date().toISOString(),
      });
    } catch (err) {
      log.error('/api/edge/status failed:', err);
      res.status(500).json({ ok: false, error: err.message });
    }
  });

  // ── 수동 동기화 트리거 (디버깅/현장 지원용) ──
  app.post('/api/edge/sync-now', async (req, res) => {
    log.info('manual sync requested via /api/edge/sync-now');
    try {
      await worker.runPullCycle();
      await worker.runStockCycle();
      res.json({ ok: true });
    } catch (err) {
      log.error('manual sync failed:', err);
      res.status(500).json({ ok: false, error: err.message });
    }
  });

  // ── 미러 데이터 조회 (Wave A 읽기 오프라인) ──
  // GET /api/offline/table/:key?limit=&offset= — 제네릭 미러 목록
  app.get('/api/offline/table/:key', async (req, res) => {
    const key = req.params.key;
    const limit = Math.min(Number(req.query.limit) || 100, 1000);
    const offset = Number(req.query.offset) || 0;

    try {
      const rows = await db.getPool().query(
        `SELECT data FROM mirror_rows WHERE table_key = $1 ORDER BY id LIMIT $2 OFFSET $3`,
        [key, limit, offset],
      );
      const count = await db
        .getPool()
        .query(`SELECT COUNT(*)::int AS c FROM mirror_rows WHERE table_key = $1`, [key]);

      res.json({ table: key, count: count.rows[0].c, data: rows.rows.map((r) => r.data) });
    } catch (err) {
      log.error(`/api/offline/table/${key} failed:`, err);
      res.status(500).json({ ok: false, error: err.message });
    }
  });

  // GET /api/offline/product-lookup?q= — 바코드/코드/이름으로 상품+가격+재고 조회
  // JSONB 미러 위에서 동작하는 오프라인 판매 화면의 핵심 조회
  app.get('/api/offline/product-lookup', async (req, res) => {
    const q = String(req.query.q || '').trim();

    if (!q) return res.status(400).json({ ok: false, error: 'q requerido' });

    const t0 = Date.now();
    try {
      const rows = await db.getPool().query(
        `SELECT p.data AS product,
                COALESCE(pr.prices, '[]'::jsonb)  AS prices,
                COALESCE(st.qty, 0)               AS stock_qty
         FROM mirror_rows p
         LEFT JOIN LATERAL (
           SELECT jsonb_agg(x.data) AS prices
           FROM mirror_rows x
           WHERE x.table_key = 'prices' AND (x.data->>'product_id')::bigint = p.id
         ) pr ON true
         LEFT JOIN LATERAL (
           SELECT SUM(ms.qty) AS qty
           FROM mirror_rows pb
           JOIN mirror_stock ms ON ms.product_branch_id = pb.id
           WHERE pb.table_key = 'product_branch' AND (pb.data->>'product_id')::bigint = p.id
         ) st ON true
         WHERE p.table_key = 'products'
           AND (p.data->>'barcode' = $1 OR p.data->>'code' = $1 OR p.data->>'name' ILIKE '%' || $1 || '%')
         LIMIT 20`,
        [q],
      );

      log.debug(`product-lookup q="${q}" → ${rows.rows.length} hits (${Date.now() - t0}ms)`);
      res.json({ ok: true, q, results: rows.rows });
    } catch (err) {
      log.error(`product-lookup q="${q}" failed:`, err);
      res.status(500).json({ ok: false, error: err.message });
    }
  });

  // 미정의 라우트 — 명시적 404 로그 (프론트가 잘못된 경로로 failover 하는지 탐지)
  app.use((req, res) => {
    log.warn(`404 ${req.method} ${req.originalUrl}`);
    res.status(404).json({ ok: false, error: `not found: ${req.originalUrl}` });
  });

  return app;
}

module.exports = { buildServer };
