// Phase 58 Wave B — Push 워커
// offline_outbox 의 pending op 를 seq 순서로 클라우드 /offline-sync/push 에 배치 전송.
// 서버는 uuid 멱등 — 네트워크 재시도로 중복 전송돼도 안전하다.
// 상태 규칙: applied|duplicate → done / error|unsupported → error(재시도 중단, 관리자 확인)
//            네트워크 실패 → attempts+1 후 pending 유지 (최대 8회)

const { createLogger } = require('./logger');
const cloud = require('./cloud-client');
const db = require('./db');

const log = createLogger('PushWorker');

const state = {
  draining: false,
  lastDrainAt: null,
  totalPushed: 0,
  timers: [],
  isOnlineFn: () => false,
};

function getPushStatus() {
  return {
    draining: state.draining,
    lastDrainAt: state.lastDrainAt,
    totalPushed: state.totalPushed,
  };
}

// outbox 배출 — 온라인일 때만, 동시 실행 방지
async function drainOutbox(reason = 'interval') {
  if (!state.isOnlineFn()) {
    log.debug(`[drain] skipped — offline (${reason})`);

    return { pushed: 0 };
  }
  if (state.draining) {
    log.warn(`[drain] already draining — skipped (${reason})`);

    return { pushed: 0 };
  }

  state.draining = true;
  const t0 = Date.now();
  let pushedTotal = 0;

  try {
    // 여러 배치 반복 — 한 번의 drain 으로 최대 10배치(200 op)
    for (let batch = 0; batch < 10; batch++) {
      const pending = await db.getPendingOutbox(20);

      if (pending.length === 0) {
        if (batch === 0) log.debug(`[drain] outbox empty (${reason})`);
        break;
      }

      log.info(`[drain] batch ${batch + 1}: ${pending.length} ops (seq ${pending[0].seq}..${pending[pending.length - 1].seq})`);

      const ops = pending.map((p) => ({
        uuid: p.uuid,
        opType: p.op_type,
        payload: p.payload,
        originalAt: p.original_at,
        offlineNumber: p.offline_number,
      }));

      let response;
      try {
        response = await cloud.pushOps(ops);
      } catch (err) {
        // 네트워크/서버 실패 — 배치 전체 attempts+1 후 중단 (다음 drain 재시도)
        log.warn(`[drain] push batch failed (${err.message}) — attempts+1, will retry`);
        for (const p of pending) {
          await db.markOutboxResult(p.uuid, { bumpAttempt: true, error: err.message }).catch(() => {});
        }
        break;
      }

      // 서버 per-op 결과 반영
      for (const r of response.results || []) {
        if (r.status === 'applied' || r.status === 'duplicate') {
          await db.markOutboxResult(r.uuid, {
            status: 'done',
            result: { serverId: r.resultId, status: r.status },
          });
          pushedTotal += 1;
          log.info(`[drain] ✓ uuid=${r.uuid} → serverId=${r.resultId}${r.status === 'duplicate' ? ' (dup)' : ''}`);
        } else {
          // 서버가 명시 거부 (error/unsupported) — 재시도 무의미, 관리자 확인 대상
          await db.markOutboxResult(r.uuid, {
            status: 'error',
            error: r.error || r.status,
            bumpAttempt: true,
          });
          log.error(`[drain] ✗ uuid=${r.uuid} status=${r.status} error=${r.error || '-'}`);
        }
      }
    }
  } catch (err) {
    log.error('[drain] unexpected failure:', err);
  } finally {
    state.draining = false;
    state.lastDrainAt = new Date().toISOString();
    state.totalPushed += pushedTotal;
    if (pushedTotal > 0) {
      log.info(`[drain] done — pushed ${pushedTotal} ops in ${Date.now() - t0}ms (total ${state.totalPushed})`);
    }
  }

  return { pushed: pushedTotal };
}

// 워커 기동 — isOnline 판정 함수는 주입 (pull-worker 와 순환 의존 방지)
function startPushWorker(cfg, isOnlineFn) {
  state.isOnlineFn = isOnlineFn;
  const interval = cfg.pushIntervalMs || 20000;
  state.timers.push(setInterval(() => drainOutbox('interval').catch(() => {}), interval));
  log.info(`push worker started — interval=${interval}ms`);
}

function stopPushWorker() {
  state.timers.forEach((t) => clearInterval(t));
  state.timers = [];
  log.info('push worker stopped');
}

module.exports = { startPushWorker, stopPushWorker, drainOutbox, getPushStatus };
