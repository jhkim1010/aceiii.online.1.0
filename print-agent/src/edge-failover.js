// Phase 58 Wave B2 (TASK-B0) — print-agent edge failover
// 클라우드 /print-agent 소켓이 끊기면 지점 edge-agent(LAN)로 2차 접속해
// 오프라인 중에도 코만다/라벨 출력을 유지한다.
//
// 무리팩터 설계: main.js 의 기존 print_temp/print_barcode/print_qr 핸들러(클로저)를
// 건드리지 않고, cloudSocket.listeners(event) 로 같은 핸들러를 재사용해 디스패치한다.
// 클라우드가 복구되면 edge 소켓은 즉시 종료 (단일 소스 원칙).

const { io } = require('socket.io-client');

// 클라우드 단절 후 edge 접속까지 유예 (순간 끊김에 과민반응 방지)
const FAILOVER_GRACE_MS = 15000;

// edge 로 위임(재디스패치)할 이벤트 — 출력 계열만
const RELAY_EVENTS = ['print_temp', 'print_barcode', 'print_qr', 'print_test', 'force_disconnect'];

function attachEdgeFailover(cloudSocket, opts) {
  const { edgeUrl, apiKey, log } = opts;
  const say = typeof log === 'function' ? log : () => {};

  if (!edgeUrl || !apiKey) {
    console.log('[edge-failover] edgeUrl/apiKey 없음 — failover 비활성');

    return { stop: () => {} };
  }

  const nsUrl = `${edgeUrl.replace(/\/$/, '')}/print-agent`;
  let edgeSocket = null;
  let graceTimer = null;
  let stopped = false;

  const connectEdge = () => {
    if (stopped || edgeSocket) return;
    if (cloudSocket.connected) return; // 유예 중 클라우드가 복구된 경우

    console.log(`[edge-failover] 클라우드 단절 지속 → edge 접속 시도: ${nsUrl}`);
    say(`🟠 nube caída — conectando a servidor local ${nsUrl}`);

    edgeSocket = io(nsUrl, {
      auth: { token: apiKey },
      reconnection: true,
      reconnectionDelay: 3000,
      reconnectionDelayMax: 10000,
      timeout: 8000,
      transports: ['polling', 'websocket'],
    });

    edgeSocket.on('connect', () => {
      console.log(`[edge-failover] ✅ edge 연결됨 sid=${edgeSocket.id}`);
      say('🟠 MODO SIN CONEXIÓN — impresión vía servidor local');
      edgeSocket.emit('agent_online', { source: 'edge-failover' });
    });

    edgeSocket.on('agent_info', (info) => {
      console.log('[edge-failover] agent_info (edge):', JSON.stringify(info));
    });

    edgeSocket.on('auth_error', (err) => {
      console.log('[edge-failover] ❌ edge 인증 실패:', err?.message);
      say(`❌ edge auth: ${err?.message} (edge 의 branch_agents 미러 동기화 확인)`);
    });

    edgeSocket.on('connect_error', (err) => {
      console.log('[edge-failover] edge connect_error:', err?.message);
    });

    // 핵심: 출력 이벤트를 클라우드 소켓의 기존 핸들러들로 그대로 재디스패치.
    // 핸들러가 wsConnection 에 등록된 클로저이므로 listeners() 로 재사용 — 무리팩터.
    for (const ev of RELAY_EVENTS) {
      edgeSocket.on(ev, (payload, ack) => {
        const handlers = cloudSocket.listeners(ev);
        console.log(`[edge-failover] 📥 ${ev} via EDGE → ${handlers.length} handler(s) 재디스패치`);
        say(`📥 ${ev} (vía servidor local)`);

        if (handlers.length === 0) {
          console.log(`[edge-failover] ⚠ ${ev} 핸들러 없음 — main.js 등록 순서 확인`);
        }

        for (const fn of handlers) {
          try {
            const r = fn(payload, ack);

            // async 핸들러 에러도 로그로 수거 (침묵 실패 방지)
            if (r && typeof r.catch === 'function') {
              r.catch((err) => console.log(`[edge-failover] ${ev} handler async error:`, err?.message));
            }
          } catch (err) {
            console.log(`[edge-failover] ${ev} handler error:`, err?.message);
          }
        }
      });
    }

    // print_ack 를 edge 로도 전달할 수 있도록 프록시 emit 훅 제공:
    // 기존 핸들러들이 cloudSocket.emit('print_ack', ...) 를 호출하면 클라우드가 죽어
    // 있어 버려진다 → cloudSocket 이 disconnected 인 동안 print_ack emit 을 미러링.
    const origEmit = cloudSocket.emit.bind(cloudSocket);
    if (!cloudSocket.__edgeEmitPatched) {
      cloudSocket.__edgeEmitPatched = true;
      cloudSocket.emit = (event, ...args) => {
        if (event === 'print_ack' && !cloudSocket.connected && edgeSocket?.connected) {
          console.log('[edge-failover] print_ack → edge 로 미러링');
          edgeSocket.emit(event, ...args);
        }

        return origEmit(event, ...args);
      };
    }
  };

  const disconnectEdge = (reason) => {
    if (graceTimer) {
      clearTimeout(graceTimer);
      graceTimer = null;
    }
    if (edgeSocket) {
      console.log(`[edge-failover] edge 연결 종료 (${reason})`);
      say('🟢 nube restablecida — impresión vía servidor principal');
      try {
        edgeSocket.disconnect();
      } catch (_e) { /* ignore */ }
      edgeSocket = null;
    }
  };

  // 클라우드 소켓 상태 감시
  cloudSocket.on('disconnect', (reason) => {
    console.log(`[edge-failover] 클라우드 disconnect (${reason}) — ${FAILOVER_GRACE_MS}ms 유예 후 edge 시도`);
    if (!graceTimer && !stopped) {
      graceTimer = setTimeout(() => {
        graceTimer = null;
        connectEdge();
      }, FAILOVER_GRACE_MS);
    }
  });

  cloudSocket.on('connect', () => {
    disconnectEdge('cloud reconnected');
  });

  console.log(`[edge-failover] armado — edge=${nsUrl} grace=${FAILOVER_GRACE_MS}ms`);

  return {
    stop: () => {
      stopped = true;
      disconnectEdge('stopped');
    },
  };
}

module.exports = { attachEdgeFailover };
