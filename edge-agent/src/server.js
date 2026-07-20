// Phase 58 — edge-agent HTTP 서버
// Wave A 범위: 헬스/상태/미러 조회 (프론트 failover 감지 + 오프라인 카탈로그 조회 기반)
// Wave B 에서 판매 API (nueva-venta 계약 호환) 가 추가된다.

const express = require('express');
const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const { createLogger } = require('./logger');
const db = require('./db');
const worker = require('./pull-worker');
const pushWorker = require('./push-worker');
const printGateway = require('./print-gateway');

const log = createLogger('Server');

// JWT payload 디코드 (서명 검증 없음 — LAN 오프라인 한정 신원 힌트)
// ⚠ 보안 메모: edge 는 JWT secret 이 없어 서명 검증 불가. 오프라인 판매의 userId 는
// push 시 서버 원장에 기록되어 사후 감사 가능. Wave C 에서 HMAC 강화 예정.
function decodeJwtPayload(authHeader) {
  try {
    const token = String(authHeader || '').replace(/^Bearer\s+/i, '');
    const parts = token.split('.');

    if (parts.length !== 3) return null;

    return JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
  } catch {
    return null;
  }
}

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

    // userId 해석 우선순위: body.userId → JWT payload.id → x-user-id 헤더
    const jwt = decodeJwtPayload(req.headers.authorization);
    const userId = Number(sale.userId) || Number(jwt?.id) || Number(req.headers['x-user-id']) || null;
    log.debug(`[sale] userId resolved=${userId} (body=${sale.userId || '-'} jwt=${jwt?.id || '-'} header=${req.headers['x-user-id'] || '-'})`);

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

  // ── Wave B2 (TASK-8): 오프라인 로그인 — 미러된 users.password(bcrypt) 로컬 검증 ──
  // 단절 중 브라우저 재시작/재로그인 대응. 발급 토큰은 edge 세션 표식일 뿐이며
  // 복구 후에는 반드시 클라우드 재로그인 (기존 중복로그인 차단 체계 복원).
  app.post('/api/offline/auth/login', async (req, res) => {
    const email = String(req.body?.email || '').trim().toLowerCase();
    const password = String(req.body?.password || '');
    const t0 = Date.now();

    if (!email || !password) {
      return res.status(400).json({ ok: false, error: 'email/password requerido' });
    }

    try {
      const rows = await db.getPool().query(
        `SELECT data FROM mirror_rows WHERE table_key = 'users' AND lower(data->>'email') = $1 LIMIT 1`,
        [email],
      );
      const user = rows.rows[0]?.data;

      if (!user) {
        log.warn(`[auth] login FAIL — email=${email} 미러에 없음 (${Date.now() - t0}ms)`);

        return res.status(401).json({ ok: false, error: 'Credenciales inválidas (offline)' });
      }

      const hash = String(user.password || '');
      const match = hash ? await bcrypt.compare(password, hash) : false;

      if (!match) {
        log.warn(`[auth] login FAIL — email=${email} bcrypt 불일치 (${Date.now() - t0}ms)`);

        return res.status(401).json({ ok: false, error: 'Credenciales inválidas (offline)' });
      }

      const offlineToken = `edge_${crypto.randomUUID().replace(/-/g, '')}`;
      log.info(`[auth] login OK (offline) — userId=${user.id} email=${email} (${Date.now() - t0}ms)`);

      return res.json({
        ok: true,
        offline: true,
        offlineToken,
        user: { id: user.id, name: user.name, email: user.email, storeId: user.store_id, branchId: user.branch_id },
        message: 'Sesión OFFLINE — al volver la conexión deberá iniciar sesión normal',
      });
    } catch (err) {
      log.error('[auth] login error:', err);

      return res.status(500).json({ ok: false, error: err.message });
    }
  });

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
