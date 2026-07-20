// Phase 58 — Ventago Edge Sync Agent 엔트리포인트
// 기동 순서: 설정 → 로컬 PG → 클라우드 클라이언트 → 워커 → HTTP 서버

const { loadConfig } = require('./config');
const { createLogger, setLevel } = require('./logger');
const db = require('./db');
const cloud = require('./cloud-client');
const worker = require('./pull-worker');
const pushWorker = require('./push-worker');
const { buildServer } = require('./server');

const log = createLogger('Main');

async function main() {
  const cfg = loadConfig();
  setLevel(cfg.logLevel);

  log.info('════════════════════════════════════════');
  log.info('Ventago Edge Sync Agent v0.1.0 starting');
  log.info(`node=${process.version} pid=${process.pid}`);
  log.info('════════════════════════════════════════');

  try {
    await db.initDb(cfg);
  } catch (err) {
    // 로컬 PG 없으면 기동 불가 — 설치 안내 후 종료
    log.error('local PostgreSQL connection FAILED — edge-agent 는 로컬 PG 필수입니다.');
    log.error(`확인: createdb ${cfg.localDb.database} / pg_hba 접근 / config.json localDb 설정`);
    log.error(err);
    process.exit(1);
  }

  cloud.initCloudClient(cfg);

  // Wave B: push 워커 — 온라인 판정은 pull 워커에 위임(주입), 복구 시 즉시 drain
  pushWorker.startPushWorker(cfg, () => worker.isOnline());
  await worker.startWorker(cfg, {
    onRecovered: () => pushWorker.drainOutbox('recovered'),
  });

  const app = buildServer(cfg);
  const httpServer = app.listen(cfg.port, () => {
    log.info(`HTTP listening on :${cfg.port} — health: http://localhost:${cfg.port}/api/health`);
  });

  // Wave B2 (TASK-B0): 같은 HTTP 서버에 /print-agent Socket.io 게이트웨이 부착
  // — 오프라인 중 print/zebra-agent 가 이곳으로 failover 접속해 코만다/라벨 출력 유지
  const printGateway = require('./print-gateway');
  printGateway.attachPrintGateway(httpServer);

  httpServer.on('error', (err) => {
    log.error(`HTTP server error (port ${cfg.port} 사용 중인지 확인):`, err);
    process.exit(1);
  });

  // graceful shutdown — pool 정리 후 종료 (pool 낭비 방지)
  const shutdown = async (signal) => {
    log.info(`${signal} received — shutting down...`);
    worker.stopWorker();
    pushWorker.stopPushWorker();
    httpServer.close();
    await db.closeDb().catch((err) => log.error('pool close failed:', err));
    log.info('bye');
    process.exit(0);
  };
  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));

  // 전역 예외 안전망 — 원인 추적 가능하게 스택 전체 로그
  process.on('unhandledRejection', (reason) => {
    log.error('unhandledRejection:', reason);
  });
  process.on('uncaughtException', (err) => {
    log.error('uncaughtException (process kept alive):', err);
  });
}

main().catch((err) => {
  log.error('fatal on startup:', err);
  process.exit(1);
});
