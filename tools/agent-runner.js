#!/usr/bin/env node
/**
 * Agent Runner — Claude 가 Mac 에서 실행할 작업을 큐로 전달하는 러너
 *
 * 사용법 (한 번 켜 두면 됨, Ctrl+C 로 종료):
 *   node tools/agent-runner.js
 *
 * 동작: .planning/run-queue.json 을 3초마다 확인해 pending 작업을 실행하고
 *       결과(stdout/stderr, exit code)를 같은 파일에 기록한다.
 *
 * 보안: 아래 WHITELIST 의 명령만 실행 가능 (임의 셸 명령 불가).
 * 캡처 자격증명: tools/manuales/.env 에 VENTAGO_USER/VENTAGO_PASS 저장 (gitignore 됨).
 */

const fs = require('fs');
const path = require('path');
const { execFile } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const QUEUE = path.join(ROOT, '.planning', 'run-queue.json');
const ENV_FILE = path.join(__dirname, 'manuales', '.env');

// 허용 작업 목록 — tools/agent-runner-jobs.js 에서 매 실행 시 fresh 로드.
// 새 작업을 추가해도 러너 재시작이 필요 없다.
const JOBS_FILE = path.join(__dirname, 'agent-runner-jobs.js');

function loadWhitelist() {
  try {
    delete require.cache[require.resolve(JOBS_FILE)];

    return require(JOBS_FILE);
  } catch (e) {
    console.error(`[runner] 작업 정의 로드 실패: ${e.message}`);

    return {};
  }
}

function loadEnvFile() {
  const env = { ...process.env };
  try {
    const txt = fs.readFileSync(ENV_FILE, 'utf8');
    for (const line of txt.split('\n')) {
      const m = line.match(/^\s*([A-Z_]+)\s*=\s*['"]?([^'"\n]*)['"]?\s*$/);
      if (m) env[m[1]] = m[2];
    }
  } catch {
    // .env 없으면 그대로 (capture 작업은 실패 메시지로 안내됨)
  }

  return env;
}

function readQueue() {
  try {
    return JSON.parse(fs.readFileSync(QUEUE, 'utf8'));
  } catch {
    return { jobs: [] };
  }
}

function writeQueue(q) {
  fs.writeFileSync(QUEUE, JSON.stringify(q, null, 2));
}

let busy = false;

async function tick() {
  if (busy) return;
  const q = readQueue();
  const job = (q.jobs || []).find((j) => j.status === 'pending');
  if (!job) return;

  const spec = loadWhitelist()[job.cmd];
  if (!spec) {
    job.status = 'error';
    job.output = `허용되지 않은 명령: ${job.cmd}`;
    writeQueue(q);

    return;
  }

  busy = true;
  job.status = 'running';
  job.startedAt = new Date().toISOString();
  writeQueue(q);
  console.log(`[runner] 실행: ${job.cmd} ${job.arg || ''}`);

  let args;
  try {
    args = typeof spec.args === 'function' ? spec.args(job.arg) : spec.args;
  } catch (e) {
    job.status = 'error';
    job.output = e.message;
    writeQueue(q);
    busy = false;

    return;
  }

  execFile(spec.file, args, {
    cwd: ROOT,
    env: spec.env ? loadEnvFile() : process.env,
    timeout: 10 * 60 * 1000,
    maxBuffer: 10 * 1024 * 1024,
  }, (err, stdout, stderr) => {
    const q2 = readQueue();
    const j2 = (q2.jobs || []).find((j) => j.id === job.id);
    if (j2) {
      j2.status = err ? 'error' : 'done';
      j2.exitCode = err ? (err.code ?? 1) : 0;
      j2.finishedAt = new Date().toISOString();
      j2.output = ((stdout || '') + (stderr ? `\n--- stderr ---\n${stderr}` : '')).slice(-4000);
      writeQueue(q2);
    }
    console.log(`[runner] ${err ? '실패' : '완료'}: ${job.cmd}`);
    busy = false;
  });
}

console.log('[runner] 시작 — .planning/run-queue.json 감시 중 (Ctrl+C 로 종료)');
console.log(`[runner] 허용 명령: ${Object.keys(loadWhitelist()).join(', ')}`);
setInterval(tick, 3000);
tick();
