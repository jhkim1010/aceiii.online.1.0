// Phase 58 — edge-agent HTTP 서버
// Wave A 범위: 헬스/상태/미러 조회 (프론트 failover 감지 + 오프라인 카탈로그 조회 기반)
// Wave B 에서 판매 API (nueva-venta 계약 호환) 가 추가된다.

const express = require('express');
const crypto = require('crypto');
const { createLogger } = require('./logger');
const db = require('./db');
const worker = require('./pull-worker');
const pushWorker = require('./push-worker');
const printGateway = require('./print-gateway');

const log = createLogger('Server');

// [Phase 72-01] 서명 검증 없는 JWT payload 디코드를 제거했다.
//
// 예전에는 `decodeJwtPayload` 가 Bearer 토큰의 payload 를 **검증 없이** 읽어 신원을 정했다.
// edge 에 JWT secret 이 없다는 이유였지만, 결과적으로 누구나 userId 를 위조해 타인 명의의
// 오프라인 판매를 만들 수 있었다(동기화 대기열에 들어가 서버 원장까지 간다).
//
// 이제는 서버가 agentKey 로 HMAC 서명한 edge 티켓만 받는다 — edge 는 자기 키로 오프라인에서
// 검증할 수 있다. 검증 로직은 edge-ticket.js, 발급은 서버의 GET /offline-sync/edge-ticket.
const { verifyEdgeTicket } = require('./edge-ticket');

function buildServer(cfg) {
  const app = express();
  app.use(express.json({ limit: '2mb' }));

  // [Phase 72-01] CORS — `*` 를 허용목록으로 좁힌다.
  //
  // 전에는 모든 origin 을 허용해, 사용자가 아무 웹페이지를 열어둔 상태에서 그 페이지의
  // 스크립트가 매장 edge 의 미러를 읽거나 판매를 만들 수 있었다(CSRF/CSWSH 표면).
  const allowedOrigins = String(cfg.corsOrigins || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);

  app.use((req, res, next) => {
    const origin = req.headers.origin;

    // origin 이 없는 요청 = 브라우저가 아님(에이전트/스크립트). CORS 는 브라우저 보호 장치라
    // 여기서 막을 대상이 아니다 — 이들은 아래 인증 미들웨어가 티켓으로 거른다.
    if (origin) {
      if (!allowedOrigins.includes(origin)) {
        log.warn(`CORS 거부 — origin=${origin}`);

        return res.status(403).json({ ok: false, error: 'origin not allowed' });
      }
      res.setHeader('Access-Control-Allow-Origin', origin);
      res.setHeader('Vary', 'Origin');
    }
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, x-edge-ticket, x-session-token, x-branch-id, x-device-token, x-api-key');
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

  // [Phase 72-01] 인증 미들웨어 — 헬스체크를 제외한 모든 라우트에 적용한다.
  //
  // 전에는 라우트 10개가 전부 무인증이었다. 같은 LAN 의 아무 기기나
  // `GET /api/offline/table/users` 로 미러를 통째로 읽고, 판매를 만들고, 동기화를 돌릴 수 있었다.
  //
  // 티켓은 서버가 이 지점의 agentKey 로 서명했으므로 클라우드가 끊긴 상태에서도 검증된다.
  // 그게 이 설계의 핵심 — 오프라인 동작이 목적인데 "서버에 물어봐서 인증"하면 요구가 깨진다.
  app.use((req, res, next) => {
    const ticket = req.headers['x-edge-ticket'];
    const identity = verifyEdgeTicket(
      ticket,
      cfg.agentKey,
      Math.floor(Date.now() / 1000),
    );

    if (!identity) {
      log.warn(`인증 거부 — ${req.method} ${req.originalUrl}`);

      return res
        .status(401)
        .json({ ok: false, error: 'x-edge-ticket 유효하지 않음' });
    }

    req.identity = identity;

    return next();
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
        printAgents: printGateway.getGatewayStatus(),
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

  // ── Wave B: 오프라인 판매 캡처 ──
  // POST /api/offline/sales — 클라우드 POST /sales 와 동일 body(CreateSaleDto) 수신.
  // 로컬 outbox 기록 + 오프라인 영수증 번호 발급 + 미러 재고 best-effort 차감.
  app.post('/api/offline/sales', async (req, res) => {
    const t0 = Date.now();
    const sale = req.body;

    // 최소 검증 — 서버 재적용 시 정식 검증이 다시 이뤄진다
    if (!sale || !Array.isArray(sale.items) || sale.items.length === 0) {
      log.warn('[sale] rejected — items 없음');

      return res.status(400).json({ ok: false, error: 'items requerido' });
    }

    // [Phase 72-01] 신원은 **검증된 티켓에서만** 온다.
    //
    // 전에는 body.userId → 미검증 JWT payload → x-user-id 헤더 순으로 골랐다.
    // 셋 다 요청자가 마음대로 정할 수 있는 값이라, 아무나 타인 명의로 판매를 만들 수 있었고
    // 그 판매가 동기화되어 서버 원장에 남았다.
    const userId = Number(req.identity?.u) || null;
    log.debug(`[sale] userId=${userId} (검증된 티켓)`);

    if (!userId) {
      log.warn('[sale] rejected — userId 해석 불가 (body/JWT/header 모두 없음)');

      return res.status(400).json({ ok: false, error: 'userId requerido (sesión no detectada)' });
    }

    try {
      const uuid = crypto.randomUUID();
      const capturedAt = new Date().toISOString();
      const branchId = worker.getWorkerStatus().branchId || 0;
      const nextSeq = await db.peekNextOutboxSeq();
      const offlineNumber = `OFF-${branchId}-${nextSeq}`;

      await db.insertOutboxOp({
        opType: 'sale.create',
        uuid,
        payload: { sale, userId, capturedAt },
        offlineNumber,
        originalAt: capturedAt,
      });

      // 미러 재고 차감 — 실패해도 판매 기록엔 영향 없음 (서버가 진실 재계산)
      const stockApplied = await db.applyLocalStockDelta(sale.items).catch((err) => {
        log.warn('[sale] stock delta failed (non-fatal):', err?.message);

        return 0;
      });

      log.info(
        `[sale] captured ${offlineNumber} uuid=${uuid} items=${sale.items.length} total=${sale.totalAmount ?? '-'} user=${userId} stockDelta=${stockApplied} (${Date.now() - t0}ms)`,
      );

      // 온라인 상태에서 호출됐다면 즉시 push 시도 (백그라운드)
      pushWorker.drainOutbox('sale-captured').catch(() => {});

      return res.status(201).json({
        ok: true,
        offline: true,
        id: null,
        uuid,
        offlineNumber,
        saleDate: capturedAt,
        message: 'Venta registrada sin conexión — se sincronizará automáticamente',
      });
    } catch (err) {
      log.error('[sale] capture FAILED:', err);

      return res.status(500).json({ ok: false, error: err.message });
    }
  });

  // ── Wave B2 (TASK-B0): 오프라인 인쇄 ──
  // POST /api/offline/print/temp — 클라우드 POST /print/temp 동일 body,
  // edge 로컬 소켓의 지점 print-agent 로 emit. 응답 계약도 동일 (agent_offline 등).
  app.post('/api/offline/print/temp', async (req, res) => {
    const body = req.body;

    if (!Array.isArray(body?.items) || body.items.length === 0) {
      return res.json({ ok: false, error: 'items requerido (carrito vacío)' });
    }

    const branchId = Number(body?.branchId) || worker.getWorkerStatus().branchId || 0;

    if (!branchId) {
      log.warn('[print/temp] branchId 해석 불가 (body/manifest 모두 없음)');

      return res.json({ ok: false, error: 'branchId requerido' });
    }

    try {
      const delivered = await printGateway.emitToBranch(branchId, 'print_temp', {
        ...body,
        branchId,
        ts: Date.now(),
        offline: true,
      });

      if (delivered === 0) {
        return res.json({ ok: false, reason: 'agent_offline', branchId, offline: true });
      }

      return res.json({ ok: true, branchId, offline: true, agents: delivered });
    } catch (err) {
      log.error('[print/temp] emit failed:', err);

      return res.status(500).json({ ok: false, error: err.message });
    }
  });

  // POST /api/offline/print/barcode — zebra 라벨 (동일 패턴)
  app.post('/api/offline/print/barcode', async (req, res) => {
    const body = req.body;
    const branchId = Number(body?.branchId) || worker.getWorkerStatus().branchId || 0;

    if (!branchId) return res.json({ ok: false, error: 'branchId requerido' });
    if (!Array.isArray(body?.items) || body.items.length === 0) {
      return res.json({ ok: false, error: 'items requerido' });
    }

    try {
      const delivered = await printGateway.emitToBranch(branchId, 'print_barcode', {
        ...body,
        branchId,
        ts: Date.now(),
        offline: true,
      });

      if (delivered === 0) return res.json({ ok: false, reason: 'agent_offline', branchId });

      return res.json({ ok: true, branchId, offline: true, agents: delivered });
    } catch (err) {
      log.error('[print/barcode] emit failed:', err);

      return res.status(500).json({ ok: false, error: err.message });
    }
  });

  // [Phase 72-01] 오프라인 로그인 제거.
  //
  // 이 엔드포인트는 미러된 users.password(bcrypt 해시)를 로컬에서 검증했다. 그러려면 전 직원의
  // 해시가 매장 LAN 장비에 있어야 하고, 무인증 미러 조회와 결합하면 해시를 통째로 받아
  // 오프라인 크래킹이 가능했다. 시도 제한도 없었다.
  //
  // 제거해도 되는 이유 — 프론트엔드가 이 엔드포인트를 **호출한 적이 없다**(배선되지 않았다).
  // 오프라인 중 신원은 온라인일 때 발급받은 edge 티켓이 담당한다. 티켓이 만료되면
  // 온라인 복구가 필요하다 — 링크가 끊긴 상태에서의 '신규' 로그인은 지원하지 않는다(설계 결정).
  // 서버도 함께 바뀌었다: 미러 payload 에서 password/mobile_pin/api_key 를 제거한다.

  // GET /api/offline/outbox — outbox 목록/상태 (디버깅·동기화 대시보드용)
  app.get('/api/offline/outbox', async (req, res) => {
    try {
      const rows = await db.getPool().query(
        `SELECT seq, op_type, uuid, status, attempts, offline_number, original_at,
                last_error, pushed_at, result
         FROM offline_outbox ORDER BY seq DESC LIMIT 100`,
      );

      res.json({ ok: true, push: pushWorker.getPushStatus(), ops: rows.rows });
    } catch (err) {
      log.error('/api/offline/outbox failed:', err);
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
