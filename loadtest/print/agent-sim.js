#!/usr/bin/env node
/**
 * 가상 print-agent N대 — 출력 부하 시험용 (2026-09-29).
 *
 * 실제 print-agent(main.js)와 같은 방식으로 접속한다:
 *   io(`${origin}/print-agent`, { auth: { token: apiKey }, transports: ['websocket'] })
 * 받은 print_invoice / print_temp 를 전부 JSONL 로 기록한다 — 시험 뒤 DB 의 판매와
 * 대조해 **분실**(판매는 있는데 아무도 못 받음)과 **중복**(같은 printJobId 를 두 번 받음)을 센다.
 *
 * 교란(CHURN): 매 CHURN_EVERY_MS 마다 에이전트의 CHURN_PCT% 를 끊었다가 CHURN_DOWN_MS 뒤
 *   다시 붙인다 — 매장 PC 의 와이파이 끊김·재시작을 흉내 낸다. 지금 구조의 분실은 주로 여기서 난다.
 *
 * 환경변수:
 *   API_ORIGIN     예) http://api-staging:5012   (/api 없이 origin 만 — 실제 에이전트와 같다)
 *   KEYS_FILE      한 줄에 "agentId,apiKey"
 *   OUT            수신 기록 JSONL 경로 (기본 ./received.jsonl)
 *   PRINT_MS       가짜 인쇄 소요 (기본 300ms) — ack 는 그 뒤에 보낸다
 *   CHURN_PCT / CHURN_EVERY_MS / CHURN_DOWN_MS   (기본 0 / 10000 / 3000)
 *   DURATION_S     이 시간이 지나면 요약을 쓰고 끝낸다 (기본 0 = 무한)
 */
const fs = require('fs')
const { io } = require('socket.io-client')

const ORIGIN = process.env.API_ORIGIN || 'http://localhost:5012'
const KEYS_FILE = process.env.KEYS_FILE || './agent-keys.txt'
const OUT = process.env.OUT || './received.jsonl'
const PRINT_MS = Number(process.env.PRINT_MS || 300)
const CHURN_PCT = Number(process.env.CHURN_PCT || 0)
const CHURN_EVERY_MS = Number(process.env.CHURN_EVERY_MS || 10000)
const CHURN_DOWN_MS = Number(process.env.CHURN_DOWN_MS || 3000)
const DURATION_S = Number(process.env.DURATION_S || 0)

const keys = fs
  .readFileSync(KEYS_FILE, 'utf8')
  .split('\n')
  .map(l => l.trim())
  .filter(Boolean)
  .map(l => {
    const [agentId, apiKey] = l.split(',')

    return { agentId: Number(agentId), apiKey }
  })

const out = fs.createWriteStream(OUT, { flags: 'a' })
const stats = { connected: 0, authErrors: 0, disconnects: 0, received: 0, byEvent: {} }
const agents = []

function log(rec) {
  out.write(JSON.stringify(rec) + '\n')
}

function connect(a) {
  const s = io(`${ORIGIN}/print-agent`, {
    auth: { token: a.apiKey },
    reconnection: true,
    reconnectionAttempts: Infinity,
    reconnectionDelay: 2000,
    reconnectionDelayMax: 30000,
    randomizationFactor: 0.5,
    timeout: 10000,
    transports: ['websocket'],
    upgrade: false
  })
  a.socket = s
  s.on('connect', () => {
    stats.connected++
    log({ t: Date.now(), ev: 'connect', agentId: a.agentId, sid: s.id })
  })
  s.on('disconnect', reason => {
    stats.disconnects++
    log({ t: Date.now(), ev: 'disconnect', agentId: a.agentId, reason })
  })
  s.on('auth_error', m => {
    stats.authErrors++
    log({ t: Date.now(), ev: 'auth_error', agentId: a.agentId, m })
  })
  for (const ev of ['print_invoice', 'print_temp', 'print_fiscal']) {
    s.on(ev, payload => {
      stats.received++
      stats.byEvent[ev] = (stats.byEvent[ev] || 0) + 1
      const job = payload?.printJobId ?? null
      const saleId = payload?.saleId ?? payload?.id ?? payload?.sale?.id ?? null
      log({ t: Date.now(), ev, agentId: a.agentId, job, saleId })
      setTimeout(() => {
        if (s.connected) s.emit('print_ack', { printJobId: job, status: 'ok', ts: Date.now() })
      }, PRINT_MS)
    })
  }
}

for (const a of keys) {
  agents.push(a)
  connect(a)
}

if (CHURN_PCT > 0) {
  setInterval(() => {
    const n = Math.max(1, Math.round((agents.length * CHURN_PCT) / 100))
    for (let i = 0; i < n; i++) {
      const a = agents[Math.floor(Math.random() * agents.length)]
      if (!a.socket?.connected) continue
      log({ t: Date.now(), ev: 'churn_down', agentId: a.agentId })
      a.socket.disconnect()
      setTimeout(() => a.socket.connect(), CHURN_DOWN_MS)
    }
  }, CHURN_EVERY_MS)
}

const tick = setInterval(() => {
  const online = agents.filter(a => a.socket?.connected).length
  console.log(
    `[sim] online=${online}/${agents.length} received=${stats.received} ` +
      `disconnects=${stats.disconnects} authErrors=${stats.authErrors} ${JSON.stringify(stats.byEvent)}`
  )
}, 5000)

if (DURATION_S > 0) {
  setTimeout(() => {
    clearInterval(tick)
    const online = agents.filter(a => a.socket?.connected).length
    const summary = { t: Date.now(), ev: 'summary', online, total: agents.length, ...stats }
    log(summary)
    console.log('[sim] fin', JSON.stringify(summary))
    out.end(() => process.exit(0))
  }, DURATION_S * 1000)
}
