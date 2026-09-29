#!/usr/bin/env node
/**
 * 출력 부하 결과 대조 — 판매(burst-print 결과) × 수신(agent-sim 기록).
 *
 *   분실 = 판매는 성공했는데 어떤 에이전트도 `sale-invoice:<id>` 를 받지 못함
 *   중복 = 같은 printJobId 를 두 번 이상 받음 (다른 에이전트 포함)
 *   오배송 = 받은 에이전트가 그 판매 매장의 에이전트가 아님
 *
 * 사용: node analyze.js <RUN> [received.jsonl] [agent-keys.txt]
 * ★ 수신이 0 이면 「분실 100%」로 보인다 — 시뮬레이터가 안 붙은 것일 수도 있으니 connect 수를 같이 본다.
 */
const fs = require('fs')
const path = require('path')

const RUN = process.argv[2]
const REC = process.argv[3] || path.join(__dirname, 'received.jsonl')
const OUT_DIR = path.join(__dirname, 'out')
if (!RUN) {
  console.error('uso: node analyze.js <RUN> [received.jsonl]')
  process.exit(2)
}

const sales = JSON.parse(fs.readFileSync(path.join(OUT_DIR, `${RUN}-sales.json`), 'utf8'))
const rec = fs
  .readFileSync(REC, 'utf8')
  .split('\n')
  .filter(Boolean)
  .map(l => JSON.parse(l))

const t0 = Math.min(...sales.map(s => s.t))
const inWindow = rec.filter(r => r.t >= t0 - 1000)
const prints = inWindow.filter(r => r.ev === 'print_invoice' && typeof r.job === 'string' && r.job.startsWith('sale-invoice:'))
const byJob = new Map()
for (const r of prints) {
  const k = r.job
  byJob.set(k, (byJob.get(k) || []).concat(r))
}

const lost = []
const lat = []
for (const s of sales) {
  const got = byJob.get(`sale-invoice:${s.saleId}`)
  if (!got) lost.push(s)
  else lat.push(got[0].t - s.t)
}
const dups = [...byJob.entries()].filter(([, v]) => v.length > 1)
const pct = (arr, p) => {
  if (!arr.length) return null
  const x = [...arr].sort((a, b) => a - b)

  return x[Math.min(x.length - 1, Math.floor((p / 100) * x.length))]
}

const churn = inWindow.filter(r => r.ev === 'churn_down').length
const connects = inWindow.filter(r => r.ev === 'connect').length
const res = {
  run: RUN,
  ventas_ok: sales.length,
  recibidos: prints.length,
  perdidos: lost.length,
  perdidos_pct: sales.length ? Math.round((lost.length / sales.length) * 10000) / 100 : null,
  duplicados: dups.length,
  venta_a_agente_ms: { p50: pct(lat, 50), p95: pct(lat, 95), p99: pct(lat, 99), max: pct(lat, 100) },
  churn_cortes: churn,
  reconexiones: connects,
  ejemplo_perdido: lost[0] || null
}
fs.writeFileSync(path.join(OUT_DIR, `${RUN}-analysis.json`), JSON.stringify(res, null, 2))
console.log(JSON.stringify(res, null, 2))
