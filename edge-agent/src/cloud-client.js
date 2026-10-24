// Phase 58 — 클라우드 /offline-sync API 클라이언트
// Node 18+ 전역 fetch 사용. 모든 호출에 타임아웃 + 소요시간 디버그 로그.

const { createLogger } = require('./logger');
const { VERSION } = require('./version');

const log = createLogger('CloudClient');

const REQUEST_TIMEOUT_MS = 20000;

let cfg = null;

function initCloudClient(config) {
  cfg = config;
  log.debug(`cloud client init — base=${cfg.cloudApiUrl}`);
}

async function cloudGet(path, params = {}) {
  if (!cfg) throw new Error('cloud client not initialized');

  const url = new URL(`${cfg.cloudApiUrl}${path}`);
  Object.entries(params).forEach(([k, v]) => {
    if (v !== undefined && v !== null) url.searchParams.set(k, String(v));
  });

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  const t0 = Date.now();

  try {
    const res = await fetch(url.toString(), {
      headers: { 'x-agent-key': cfg.agentKey, 'x-agent-version': VERSION },
      signal: controller.signal,
    });
    const ms = Date.now() - t0;

    if (!res.ok) {
      const body = await res.text().catch(() => '');
      log.warn(`GET ${path} → HTTP ${res.status} in ${ms}ms body=${body.slice(0, 200)}`);
      const err = new Error(`HTTP ${res.status} on ${path}`);
      err.status = res.status;
      throw err;
    }

    const json = await res.json();
    log.debug(`GET ${path} → 200 in ${ms}ms params=${JSON.stringify(params)}`);

    return json;
  } catch (err) {
    const ms = Date.now() - t0;

    // AbortError 를 명시적 타임아웃 메시지로 변환 (디버깅 편의)
    if (err.name === 'AbortError') {
      log.error(`GET ${path} TIMEOUT after ${ms}ms`);
      const timeoutErr = new Error(`timeout ${REQUEST_TIMEOUT_MS}ms on ${path}`);
      timeoutErr.isTimeout = true;
      throw timeoutErr;
    }

    if (!err.status) {
      // 네트워크 레벨 실패 (오프라인 판정 근거)
      log.warn(`GET ${path} network error after ${ms}ms: ${err.message}`);
      err.isNetwork = true;
    }
    throw err;
  } finally {
    clearTimeout(timer);
  }
}

// 헬스 겸 인증 확인 — manifest 성공 = 온라인 + 키 유효
// [2026-10-24] + salud para la actualización: outbox pendiente y segundos sin venta offline.
//   La respuesta puede traer `updateOrder` (ver updater.js).
async function fetchManifest(salud = {}) {
  return cloudGet('/offline-sync/manifest', { outbox: salud.outbox, idleSec: salud.idleSec });
}

async function fetchPull(table, since, afterId, limit = 500) {
  return cloudGet('/offline-sync/pull', { table, since, afterId, limit });
}

async function fetchIds(table) {
  return cloudGet('/offline-sync/ids', { table });
}

// Wave B — 오프라인 op 배치 push (POST)
async function pushOps(ops) {
  return postJson('/offline-sync/push', { ops }, `ops=${ops.length}`);
}

// [2026-10-24] estado de la actualización → servidor (la web lo muestra)
async function reportUpdate(orderId, estado, detalle) {
  return postJson('/offline-sync/update-report', { orderId, estado, detalle: detalle ? String(detalle).slice(0, 500) : undefined }, estado);
}

async function postJson(path, payload, nota = '') {
  if (!cfg) throw new Error('cloud client not initialized');

  const url = `${cfg.cloudApiUrl}${path}`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  const t0 = Date.now();

  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'x-agent-key': cfg.agentKey, 'x-agent-version': VERSION, 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
      signal: controller.signal,
    });
    const ms = Date.now() - t0;

    if (!res.ok) {
      const body = await res.text().catch(() => '');
      log.warn(`POST ${path} → HTTP ${res.status} in ${ms}ms body=${body.slice(0, 200)}`);
      const err = new Error(`HTTP ${res.status} on ${path}`);
      err.status = res.status;
      throw err;
    }

    const json = await res.json();
    log.debug(`POST ${path} → 200 in ${ms}ms ${nota}`);

    return json;
  } catch (err) {
    if (err.name === 'AbortError') {
      log.error(`POST ${path} TIMEOUT after ${Date.now() - t0}ms`);
      const timeoutErr = new Error(`timeout on ${path}`);
      timeoutErr.isTimeout = true;
      throw timeoutErr;
    }
    if (!err.status) err.isNetwork = true;
    throw err;
  } finally {
    clearTimeout(timer);
  }
}

module.exports = { initCloudClient, fetchManifest, fetchPull, fetchIds, pushOps, reportUpdate };
