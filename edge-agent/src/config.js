// Phase 58 — edge-agent 설정 로더
// config.json (gitignore) > 환경변수 > 기본값 순서로 병합

const fs = require('fs');
const path = require('path');
const { createLogger } = require('./logger');

const log = createLogger('Config');

const DEFAULTS = {
  cloudApiUrl: 'https://newapi.coolsistema.com/api',
  agentKey: '',
  port: 5010,

  // [Phase 72-01] 바인딩 주소 — 기본은 루프백.
  // 매장 단말(다른 기기)에서 접속해야 하면 EDGE_BIND_HOST=0.0.0.0 로 명시한다.
  // 기본이 안전하고 노출은 의식적인 선택이어야 한다.
  bindHost: '127.0.0.1',

  // 브라우저 CORS 허용 origin. 쉼표 구분.
  // 운영 프론트를 기본에 포함한다 — 빠뜨리면 기존 edge 설치가 EDGE_CORS_ORIGINS 없이 돌 때
  // 브라우저 요청이 티켓 검증 전에 403 으로 죽어 오프라인 기능이 통째로 멈춘다.
  corsOrigins:
    'https://app.coolsistema.com,https://new.coolsistema.com,http://localhost:5001,http://localhost:3050',
  localDb: {
    host: '127.0.0.1',
    port: 5432,
    database: 'ventago_edge',
    user: 'postgres',
    password: '',
  },

  // pull 주기: 참조데이터 5분 / 재고 1분 / prune 1시간 / 클라우드 헬스 15초 / push 20초
  pullIntervalMs: 5 * 60 * 1000,
  stockIntervalMs: 60 * 1000,
  pruneIntervalMs: 60 * 60 * 1000,
  healthProbeIntervalMs: 15 * 1000,
  pushIntervalMs: 20 * 1000,
  logLevel: 'debug',
};

function loadConfig() {
  const configPath = path.join(__dirname, '..', 'config.json');
  let fileConfig = {};

  try {
    if (fs.existsSync(configPath)) {
      fileConfig = JSON.parse(fs.readFileSync(configPath, 'utf8'));
      log.info(`config.json loaded from ${configPath}`);
    } else {
      log.warn(`config.json not found at ${configPath} — using defaults/env`);
    }
  } catch (err) {
    log.error('config.json parse failed — using defaults/env:', err);
  }

  const merged = {
    ...DEFAULTS,
    ...fileConfig,
    localDb: { ...DEFAULTS.localDb, ...(fileConfig.localDb || {}) },
  };

  // 환경변수 오버라이드 (배포/디버깅 편의)
  if (process.env.EDGE_CLOUD_API) merged.cloudApiUrl = process.env.EDGE_CLOUD_API;
  if (process.env.EDGE_AGENT_KEY) merged.agentKey = process.env.EDGE_AGENT_KEY;
  if (process.env.EDGE_PORT) merged.port = Number(process.env.EDGE_PORT);
  if (process.env.EDGE_LOG_LEVEL) merged.logLevel = process.env.EDGE_LOG_LEVEL;
  if (process.env.EDGE_BIND_HOST) merged.bindHost = process.env.EDGE_BIND_HOST;
  if (process.env.EDGE_CORS_ORIGINS) merged.corsOrigins = process.env.EDGE_CORS_ORIGINS;

  // 민감정보 마스킹 후 최종 설정 디버그 출력
  log.debug('effective config:', {
    ...merged,
    agentKey: merged.agentKey ? `${merged.agentKey.slice(0, 10)}...` : '(EMPTY!)',
    localDb: { ...merged.localDb, password: merged.localDb.password ? '***' : '(empty)' },
  });

  if (!merged.agentKey) {
    log.error('agentKey 미설정 — 클라우드 동기화 불가. config.json 또는 EDGE_AGENT_KEY 를 설정하세요.');
  }

  return merged;
}

module.exports = { loadConfig };
