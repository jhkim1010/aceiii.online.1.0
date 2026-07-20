// Phase 58 Wave B2 (TASK-B0) — edge 로컬 print 게이트웨이
// 클라우드 PrintGateway(/print-agent 네임스페이스)와 동일 계약의 축소판:
//  - 인증: handshake.auth.token = branch_agents.api_key (미러 대조 — 오프라인 검증)
//  - 룸: branch:{branchId} / 이벤트: print_temp·print_barcode·print_qr emit, print_ack 수신
//  - zebra 전용 조회(ack)류는 오프라인 제한 응답 (코만다/라벨 출력이 목적)
// print-agent 는 클라우드 소켓이 끊기면 이곳으로 failover 접속한다.

const { Server } = require('socket.io');
const { createLogger } = require('./logger');
const db = require('./db');

const log = createLogger('PrintGW');

const state = {
  nsp: null,

  // sid → { agentId, branchId, agentType, label } (상태 조회용)
  connected: new Map(),
};

// 미러에서 api_key 로 에이전트 조회 (서버 원본 행은 snake_case)
async function findAgentByKey(apiKey) {
  if (!apiKey || typeof apiKey !== 'string') return null;

  const res = await db.getPool().query(
    `SELECT data FROM mirror_rows WHERE table_key = 'branch_agents' AND data->>'api_key' = $1 LIMIT 1`,
    [apiKey],
  );

  return res.rows[0]?.data ?? null;
}

function getGatewayStatus() {
  return {
    agents: Array.from(state.connected.values()),
    count: state.connected.size,
  };
}

// 지점 룸으로 print 이벤트 emit — 수신 소켓 수 반환 (0 이면 agent_offline)
async function emitToBranch(branchId, event, payload) {
  if (!state.nsp) {
    log.warn(`emit ${event} skipped — gateway not attached`);

    return 0;
  }

  const room = `branch:${branchId}`;
  const sockets = await state.nsp.in(room).fetchSockets();
  state.nsp.to(room).emit(event, payload);
  log.info(`emit ${event} → ${room} (${sockets.length} agente(s)) items=${Array.isArray(payload?.items) ? payload.items.length : '-'}`);

  if (sockets.length === 0) {
    log.warn(`emit ${event} — ${room} 에 접속된 print-agent 없음 (agent_offline)`);
  }

  return sockets.length;
}

function attachPrintGateway(httpServer) {
  const io = new Server(httpServer, {
    cors: { origin: '*', methods: ['GET', 'POST'] },
    transports: ['polling', 'websocket'],
  });

  const nsp = io.of('/print-agent');
  state.nsp = nsp;

  nsp.on('connection', async (socket) => {
    const token = socket.handshake.auth?.token || socket.handshake.headers['x-api-key'];
    const preview = typeof token === 'string' ? `${token.slice(0, 12)}...` : 'NONE';
    log.info(`CONNECTION ATTEMPT sid=${socket.id} token=${preview} ip=${socket.handshake.address}`);

    try {
      const agent = await findAgentByKey(token);

      if (!agent) {
        log.warn(`AUTH FAIL — api_key 미러에 없음 (token=${preview}) → disconnect. ` +
          `(branch_agents pull 이 아직 안 됐다면 온라인 상태에서 1회 동기화 필요)`);
        socket.emit('auth_error', { message: 'Invalid API key (edge mirror)' });
        socket.disconnect(true);

        return;
      }

      const info = {
        agentId: agent.id,
        branchId: agent.branch_id,
        agentType: agent.agent_type,
        label: agent.label,
      };
      socket.data = info;
      socket.join(`branch:${agent.branch_id}`);
      state.connected.set(socket.id, { ...info, sid: socket.id, connectedAt: new Date().toISOString() });

      log.info(`AUTH OK (edge) — agentId=${info.agentId} type=${info.agentType} label="${info.label}" branch=${info.branchId} sid=${socket.id}`);

      // 클라우드 계약과 동일한 agent_info + edge 표식 (에이전트 UI 가 모드 표시 가능)
      socket.emit('agent_info', {
        ...info,
        branchName: `sucursal ${info.branchId}`,
        storeName: 'EDGE (modo sin conexión)',
        terminals: [],
        edge: true,
      });
    } catch (err) {
      log.error('AUTH ERROR (edge):', err);
      socket.emit('auth_error', { message: `Edge error: ${err.message}` });
      socket.disconnect(true);

      return;
    }

    socket.on('agent_online', (payload) => {
      log.debug(`agent_online sid=${socket.id} branch=${payload?.branchId ?? '-'} version=${payload?.version ?? '-'}`);
    });

    socket.on('print_ack', (payload) => {
      log.info(`print_ack sid=${socket.id} status=${payload?.status} invoiceId=${payload?.invoiceId ?? '-'} error=${payload?.error ?? '-'}`);
    });

    // zebra 조회류 — 오프라인 제한 명시 응답 (에이전트가 명확한 사유를 UI 에 표시)
    const limited = ['get_price_types', 'get_branches', 'get_stock_today', 'search_products', 'get_qr_pending', 'mark_qr_printed'];
    for (const ev of limited) {
      socket.on(ev, (_payload, ack) => {
        log.debug(`${ev} → EDGE_OFFLINE_LIMITED (sid=${socket.id})`);
        if (typeof ack === 'function') ack({ ok: false, error: 'EDGE_OFFLINE_LIMITED' });
      });
    }

    socket.on('disconnect', (reason) => {
      state.connected.delete(socket.id);
      log.info(`DISCONNECT sid=${socket.id} agentId=${socket.data?.agentId ?? '-'} reason=${reason}`);
    });
  });

  log.info('print gateway attached — namespace /print-agent');

  return io;
}

module.exports = { attachPrintGateway, emitToBranch, getGatewayStatus };
