// Phase 58 — edge-agent 파일+콘솔 이중 로거
// 디버깅 우선 설계: 모든 모듈이 태그([PullWorker] 등) 단위로 남기고,
// 로그 파일은 일자별 분리 (logs/edge-agent-YYYY-MM-DD.log)

const fs = require('fs');
const path = require('path');

const LEVELS = { debug: 10, info: 20, warn: 30, error: 40 };
const LOG_DIR = path.join(__dirname, '..', 'logs');

let currentLevel = LEVELS.debug;

function setLevel(name) {
  currentLevel = LEVELS[name] ?? LEVELS.debug;
}

// 로그 디렉터리 보장 — 실패해도 콘솔 로깅은 유지
function ensureLogDir() {
  try {
    if (!fs.existsSync(LOG_DIR)) fs.mkdirSync(LOG_DIR, { recursive: true });

    return true;
  } catch (err) {
    console.error('[Logger] log dir create failed:', err?.message);

    return false;
  }
}

function logFilePath() {
  const day = new Date().toISOString().slice(0, 10);

  return path.join(LOG_DIR, `edge-agent-${day}.log`);
}

function write(levelName, tag, args) {
  if (LEVELS[levelName] < currentLevel) return;

  const ts = new Date().toISOString();
  const msg = args
    .map((a) => {
      if (a instanceof Error) return `${a.message}\n${a.stack}`;
      if (typeof a === 'object') {
        try {
          return JSON.stringify(a);
        } catch {
          return String(a);
        }
      }

      return String(a);
    })
    .join(' ');
  const line = `${ts} [${levelName.toUpperCase()}] [${tag}] ${msg}`;

  // 콘솔 출력
  if (levelName === 'error') console.error(line);
  else if (levelName === 'warn') console.warn(line);
  else console.log(line);

  // 파일 출력 (append) — 파일 실패는 콘솔에만 1회성 경고
  if (ensureLogDir()) {
    fs.appendFile(logFilePath(), line + '\n', (err) => {
      if (err) console.error('[Logger] file append failed:', err?.message);
    });
  }
}

// 태그별 로거 팩토리 — 사용법: const log = createLogger('PullWorker')
function createLogger(tag) {
  return {
    debug: (...args) => write('debug', tag, args),
    info: (...args) => write('info', tag, args),
    warn: (...args) => write('warn', tag, args),
    error: (...args) => write('error', tag, args),
  };
}

module.exports = { createLogger, setLevel };
