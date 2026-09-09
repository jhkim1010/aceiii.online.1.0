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

// 미러의 terminals 행에서 이 터미널에 매핑된 감열(comandera) 에이전트 id.
// ★ 오프라인에서도 터미널 라우팅이 가능한 이유: `terminals` 는 미러 대상이다
//   (offline-sync/table-registry.ts). 종전에는 이걸 안 쓰고 무조건 지점 전체로
//   뿌려서, comandera 가 둘인 지점은 **판매 한 건에 종이가 두 장** 나왔다.
async function findAgentIdForTerminal(terminalId, tipo) {
  if (!terminalId) return null;

  // ★ 이벤트 종류에 맞는 컬럼을 봐야 한다. 라벨(print_barcode)인데 thermal_agent_id
  //   를 찾으면, 그 id 는 zebra 소켓 목록에 없으므로 zebra 가 붙어 있는데도
  //   agent_offline 이 된다 — 종전에는 broadcast 라 어쨌든 나왔다.
  const columna = tipo === 'zebra' ? 'zebra_agent_id' : 'thermal_agent_id';

  try {
    const res = await db.getPool().query(
      `SELECT data->>'${columna}' AS aid
         FROM mirror_rows
        WHERE table_key = 'terminals' AND data->>'id' = $1
        LIMIT 1`,
      [String(terminalId)],
    );
    const aid = Number(res.rows[0]?.aid);

    return Number.isFinite(aid) && aid > 0 ? aid : null;
  } catch (err) {
    log.warn(`terminal→agent 조회 실패 (terminal ${terminalId}): ${err?.message}`);

    return null;
  }
}

/**
 * print 이벤트를 **정확히 하나의 에이전트**에게 보낸다.
 *
 * ★ 이 함수의 계약은 「한 요청 = 한 장」이다. 종전 `emitToBranch` 는 지점 룸으로
 *   무조건 broadcast 했다 — comandera 가 둘인 지점에서는 오프라인 판매마다
 *   **항상 두 장**이 나왔다. 클라우드(print.controller)는 터미널 매핑으로 이미
 *   그것을 피하고 있었는데 엣지에만 그 규칙이 없었다.
 *
 * 결정 순서:
 *   ① terminalId 에 매핑된 에이전트가 접속해 있으면 → 그 소켓에만
 *   ② 매핑이 없고 지점에 접속한 에이전트가 **정확히 1개** → 그 소켓에만
 *   ③ 매핑이 없고 2개 이상 → **보내지 않는다.** 어느 것이 맞는지 모르는 채로
 *      둘 다에 보내면 중복 발행이다. 사유를 돌려주고 터미널에 comandera 를
 *      배정하게 한다.
 *
 * @returns {{ delivered: number, reason?: 'agent_offline'|'ambiguous_target', candidates?: number }}
 */
async function emitToPrinter(branchId, terminalId, event, payload) {
  if (!state.nsp) {
    log.warn(`emit ${event} skipped — gateway not attached`);

    return { delivered: 0, reason: 'agent_offline' };
  }

  const room = `branch:${branchId}`;
  const todos = await state.nsp.in(room).fetchSockets();

  // ★ 이벤트 종류에 맞는 에이전트만 후보다. 룸에는 zebra(라벨 프린터)도 같이 있다 —
  //   섞어 세면 「감열 1대 + zebra 1대」가 2대로 잡혀 코만다가 안 나가고,
  //   zebra 만 있는 지점에 `print_temp` 가 배달되기도 한다.
  const tipoNecesario = event === 'print_barcode' ? 'zebra' : 'thermal';
  const sockets = todos.filter(
    (sk) => (sk.data?.agentType || 'thermal') === tipoNecesario,
  );

  if (sockets.length === 0) {
    log.warn(`emit ${event} — ${room} 에 접속된 print-agent 없음 (agent_offline)`);

    return { delivered: 0, reason: 'agent_offline' };
  }

  // ① 터미널 매핑
  const mappedAgentId = await findAgentIdForTerminal(terminalId, tipoNecesario);

  if (mappedAgentId) {
    const target = sockets.find((sk) => Number(sk.data?.agentId) === mappedAgentId);

    if (target) {
      state.nsp.to(target.id).emit(event, payload);
      log.info(`emit ${event} → agentId=${mappedAgentId} (terminal ${terminalId}) sid=${target.id}`);

      return { delivered: 1 };
    }

    log.warn(`terminal ${terminalId} → ${tipoNecesario} agentId=${mappedAgentId} 매핑돼 있으나 미접속`);

    return { delivered: 0, reason: 'agent_offline' };
  }

  // ② 후보가 하나뿐이면 모호하지 않다
  if (sockets.length === 1) {
    state.nsp.to(sockets[0].id).emit(event, payload);
    log.info(`emit ${event} → único agente de ${room} sid=${sockets[0].id}`);

    return { delivered: 1 };
  }

  // ③ 둘 이상 — 보내지 않는다
  log.warn(
    `emit ${event} REHUSADO — ${room} 에 에이전트 ${sockets.length}개, terminal ${terminalId ?? '-'} 매핑 없음. ` +
      `broadcast 하면 ${sockets.length}장이 나온다.`,
  );

  return { delivered: 0, reason: 'ambiguous_target', candidates: sockets.length };
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

      // ★ 같은 agentId 로 이미 붙어 있던 소켓을 끊는다 (last-wins) —
      //   클라우드 게이트웨이(print.gateway.ts)가 하던 것을 여기에도 둔다.
      //   좀비 소켓이 룸에 남아 있으면 **한 요청에 두 장**이 나온다:
      //   에이전트가 재접속해도 옛 소켓이 살아 있으면 둘 다 이벤트를 받는다.
      try {
        const abiertos = await nsp.fetchSockets();

        for (const otro of abiertos) {
          if (otro.id !== socket.id && Number(otro.data?.agentId) === Number(info.agentId)) {
            log.warn(`DUPLICADO agentId=${info.agentId} — cierro socket previo sid=${otro.id}`);
            otro.emit('force_disconnect', {
              message: 'Otra sesión se conectó con la misma API Key (edge).',
              reason: 'DUPLICATE_CONNECTION',
            });
            otro.disconnect(true);
            state.connected.delete(otro.id);
          }
        }
      } catch (dupErr) {
        log.warn(`중복 소켓 정리 실패 (agent ${info.agentId}): ${dupErr?.message}`);
      }

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

module.exports = { attachPrintGateway, emitToPrinter, getGatewayStatus };
