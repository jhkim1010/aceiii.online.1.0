// Phase 58 — Pull 동기화 워커
// 역할: 온라인 상태 감시 + 참조데이터 증분 pull + 재고 스냅샷 + prune.
// 상태 머신: ONLINE ↔ OFFLINE (manifest 성공/네트워크 실패 기준)
// 지점 PC 시계 오차 대비: 커서는 항상 서버가 준 nextCursor/serverTime 만 사용.

const { createLogger } = require('./logger');
const cloud = require('./cloud-client');
const db = require('./db');

const log = createLogger('PullWorker');

// 재고 스냅샷은 별도 주기 — 레지스트리 목록에서 분리 처리
const STOCK_TABLE = 'stock_snapshot';

const state = {
  online: false,
  lastManifest: null,
  lastOnlineAt: null,
  lastOfflineAt: null,
  consecutiveFailures: 0,
  cycleCount: 0,
  running: false,
  timers: [],

  // Wave B: 복구 시 실행할 훅 (push 워커 drain — 순환 의존 방지 위해 주입식)
  onRecovered: null,
};

function isOnline() {
  return state.online;
}

function getWorkerStatus() {
  return {
    online: state.online,
    lastOnlineAt: state.lastOnlineAt,
    lastOfflineAt: state.lastOfflineAt,
    consecutiveFailures: state.consecutiveFailures,
    cycleCount: state.cycleCount,
    storeId: state.lastManifest?.storeId ?? null,
    branchId: state.lastManifest?.branchId ?? null,
    tables: state.lastManifest?.tables ?? [],
  };
}

// 온라인/오프라인 전이 — 전이 시점마다 명시적 로그 (현장 디버깅 핵심 지표)
// 반환값: 실제 전이가 발생했는지 (복구 즉시 pull 트리거 판단용)
function setOnline(value, reason) {
  if (state.online === value) return false;

  state.online = value;
  if (value) {
    state.lastOnlineAt = new Date().toISOString();
    state.consecutiveFailures = 0;
    log.info(`>>> ONLINE (${reason})`);
  } else {
    state.lastOfflineAt = new Date().toISOString();
    log.warn(`>>> OFFLINE (${reason})`);
  }

  return true;
}

// 클라우드 헬스 프로브 — manifest 호출로 인증까지 함께 검증
async function probeCloud() {
  try {
    const manifest = await cloud.fetchManifest();
    state.lastManifest = manifest;

    // manifest 영속 — 오프라인 재기동 시에도 branch/store 식별 유지 (영수증 번호 정합)
    db.saveMeta('manifest', manifest).catch((err) =>
      log.warn('manifest persist failed (non-fatal):', err?.message),
    );

    const becameOnline = setOnline(true, 'manifest ok');

    // 복구 전이 즉시 pull — 다음 정기 사이클(최대 5분)을 기다리지 않음
    // (오프라인 중 서버에서 바뀐 가격/상품을 최대한 빨리 반영)
    if (becameOnline) {
      log.info('recovered — triggering immediate pull+stock cycle');
      runPullCycle().catch((err) => log.error('recovery pull failed:', err));
      runStockCycle().catch((err) => log.error('recovery stock failed:', err));

      // Wave B: 복구 즉시 오프라인 판매 push (index.js 가 주입한 훅)
      if (state.onRecovered) {
        state.onRecovered().catch((err) => log.error('recovery hook failed:', err));
      }
    }

    return true;
  } catch (err) {
    state.consecutiveFailures += 1;

    // 401 은 네트워크가 아니라 키 문제 — 오프라인 전환하지 않고 크게 경고
    if (err.status === 401) {
      log.error('agentKey UNAUTHORIZED — config.json 의 agentKey 확인 필요 (오프라인 전환 아님)');

      return false;
    }

    setOnline(false, `probe fail #${state.consecutiveFailures}: ${err.message}`);

    return false;
  }
}

// 단일 테이블 증분 pull — hasMore 동안 페이지 반복
async function pullTable(tableKey) {
  const st = (await db.getSyncState(tableKey)) || {};
  let since = st.since_cursor ? new Date(st.since_cursor).toISOString() : undefined;
  let afterId = st.after_id || 0;
  let total = 0;
  let pages = 0;
  const t0 = Date.now();

  log.debug(`[pull:${tableKey}] start cursor since=${since || 'EPOCH'} afterId=${afterId}`);

  // 무한 루프 방지 상한 — 한 사이클 최대 50 페이지 (25k 행)
  for (let page = 0; page < 50; page++) {
    const res = await cloud.fetchPull(tableKey, since, afterId, 500);
    pages += 1;

    if (res.rows.length > 0) {
      await db.upsertMirrorRows(tableKey, res.rows);
      total += res.rows.length;
    }

    if (res.nextCursor) {
      since = res.nextCursor.since;
      afterId = res.nextCursor.afterId;
    }

    if (!res.hasMore) break;

    log.debug(`[pull:${tableKey}] page ${page + 1} done (+${res.rows.length}), continuing...`);
  }

  // 커서/통계 영속화 — 다음 사이클은 여기서 이어감
  const countRes = await db
    .getPool()
    .query('SELECT COUNT(*)::bigint AS c FROM mirror_rows WHERE table_key = $1', [tableKey]);

  await db.saveSyncState(tableKey, {
    since_cursor: since || null,
    after_id: afterId,
    row_count: Number(countRes.rows[0].c),
    last_pull_at: new Date().toISOString(),
    last_error: null,
  });

  const ms = Date.now() - t0;
  if (total > 0) {
    log.info(`[pull:${tableKey}] +${total} rows / ${pages} pages / ${ms}ms (local total=${countRes.rows[0].c})`);
  } else {
    log.debug(`[pull:${tableKey}] no changes (${ms}ms)`);
  }

  return total;
}

// 참조데이터 전체 사이클
async function runPullCycle() {
  if (!state.online) {
    log.debug('[cycle] skipped — offline');

    return;
  }
  if (state.running) {
    log.warn('[cycle] previous cycle still running — skipped (overlap guard)');

    return;
  }

  state.running = true;
  state.cycleCount += 1;
  const cycleId = state.cycleCount;
  const t0 = Date.now();
  const tables = (state.lastManifest?.tables || []).filter((t) => t !== STOCK_TABLE);
  log.info(`[cycle#${cycleId}] start — ${tables.length} tables`);

  let totalRows = 0;
  let failed = 0;

  for (const tableKey of tables) {
    try {
      totalRows += await pullTable(tableKey);
    } catch (err) {
      failed += 1;
      log.error(`[cycle#${cycleId}] table ${tableKey} failed:`, err);
      await db
        .saveSyncState(tableKey, { last_error: err.message })
        .catch(() => {});

      // 네트워크 실패면 사이클 중단 (다음 프로브가 오프라인 판정)
      if (err.isNetwork || err.isTimeout) {
        setOnline(false, `pull network fail on ${tableKey}`);
        break;
      }
    }
  }

  state.running = false;
  log.info(`[cycle#${cycleId}] done — +${totalRows} rows, ${failed} failed, ${Date.now() - t0}ms`);
}

// 재고 스냅샷 사이클 (1분 주기 — 빠른 주기라 별도)
async function runStockCycle() {
  if (!state.online) return;

  try {
    const t0 = Date.now();
    const res = await cloud.fetchPull(STOCK_TABLE, undefined, undefined, 100000);
    await db.replaceStockSnapshot(res.rows);
    log.info(`[stock] snapshot ${res.rows.length} rows in ${Date.now() - t0}ms`);
  } catch (err) {
    log.error('[stock] cycle failed:', err);
    if (err.isNetwork || err.isTimeout) setOnline(false, 'stock network fail');
  }
}

// prune 사이클 (1시간 주기 — hard delete 전파)
async function runPruneCycle() {
  if (!state.online) return;

  const tables = (state.lastManifest?.tables || []).filter((t) => t !== STOCK_TABLE);
  log.info(`[prune] start — ${tables.length} tables`);

  for (const tableKey of tables) {
    try {
      const res = await cloud.fetchIds(tableKey);
      await db.pruneMirror(tableKey, res.ids);
      await db.saveSyncState(tableKey, { last_prune_at: new Date().toISOString() });
    } catch (err) {
      log.error(`[prune] ${tableKey} failed:`, err);
      if (err.isNetwork || err.isTimeout) {
        setOnline(false, 'prune network fail');
        break;
      }
    }
  }
}

// 워커 기동 — 프로브 즉시 1회 + 주기 타이머 등록
// hooks.onRecovered: 오프라인→온라인 전이 시 추가 실행 (push drain 등)
async function startWorker(cfg, hooks = {}) {
  state.onRecovered = hooks.onRecovered || null;
  log.info('worker starting...');

  // 저장된 manifest 복원 — 클라우드 없이 재기동해도 지점/스토어/테이블 목록 유지
  try {
    const saved = await db.loadMeta('manifest');
    if (saved) {
      state.lastManifest = saved;
      log.info(`restored persisted manifest — store=${saved.storeId} branch=${saved.branchId} tables=${(saved.tables || []).length}`);
    } else {
      log.debug('no persisted manifest (first boot)');
    }
  } catch (err) {
    log.warn('manifest restore failed (non-fatal):', err?.message);
  }

  const ok = await probeCloud();
  if (ok) {
    // 첫 기동 시 즉시 풀 사이클 (콜드 스타트)
    await runPullCycle();
    await runStockCycle();
  } else {
    log.warn('initial probe failed — will retry on interval (offline start)');
  }

  state.timers.push(setInterval(() => probeCloud().catch(() => {}), cfg.healthProbeIntervalMs));
  state.timers.push(setInterval(() => runPullCycle().catch(() => {}), cfg.pullIntervalMs));
  state.timers.push(setInterval(() => runStockCycle().catch(() => {}), cfg.stockIntervalMs));
  state.timers.push(setInterval(() => runPruneCycle().catch(() => {}), cfg.pruneIntervalMs));

  log.info(
    `worker timers set — probe=${cfg.healthProbeIntervalMs}ms pull=${cfg.pullIntervalMs}ms stock=${cfg.stockIntervalMs}ms prune=${cfg.pruneIntervalMs}ms`,
  );
}

function stopWorker() {
  state.timers.forEach((t) => clearInterval(t));
  state.timers = [];
  log.info('worker stopped');
}

module.exports = { startWorker, stopWorker, isOnline, getWorkerStatus, runPullCycle, runStockCycle };
