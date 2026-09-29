#!/usr/bin/env node
/**
 * 출력 부하 발생기 — 초당 RATE 건의 판매를 printTicket=true 로 만든다 (2026-09-29).
 *
 * ★ open-loop: 응답을 기다리지 않고 10ms 마다 정해진 수를 보낸다. 서버가 느려져도 도착률이
 *   RATE 로 유지된다(닫힌 루프는 서버가 느려지면 스스로 속도를 줄여 과부하를 숨긴다).
 * ★ 판매마다 notes 에 `PBURST|<RUN>|<seq>` 를 심는다 — analyze.js 가 DB 와 대조한다.
 *
 * 환경변수: API (기본 http://localhost:5012/api) · STORES ("837-1136" 또는 쉼표 목록)
 *   RATE(기본 100) · DURATION_S(기본 60) · RUN(기본 타임스탬프) · OUT_DIR(기본 ./out)
 *   LT_PASSWORD(기본 loadtest123)
 */
const fs = require('fs')
const path = require('path')

const API = process.env.API || 'http://localhost:5012/api'
const RATE = Number(process.env.RATE || 100)
const DURATION_S = Number(process.env.DURATION_S || 60)
const RUN = process.env.RUN || `r${Date.now()}`
const OUT_DIR = process.env.OUT_DIR || path.join(__dirname, 'out')
const PASSWORD = process.env.LT_PASSWORD || 'loadtest123'

const parseStores = s => {
  const m = /^(\d+)-(\d+)$/.exec(s || '')
  if (m) return Array.from({ length: Number(m[2]) - Number(m[1]) + 1 }, (_, i) => Number(m[1]) + i)

  return String(s || '').split(',').map(Number).filter(Boolean)
}
const STORES = parseStores(process.env.STORES || '837-1136')

fs.mkdirSync(OUT_DIR, { recursive: true })

async function j(method, url, body, headers = {}) {
  const r = await fetch(`${API}${url}`, {
    method,
    headers: { 'Content-Type': 'application/json', ...headers },
    body: body ? JSON.stringify(body) : undefined
  })
  const text = await r.text()
  let data = null
  try {
    data = JSON.parse(text)
  } catch {
    data = text
  }

  return { status: r.status, data }
}

async function boot(store) {
  const username = `lt_s${store}_1`
  const lr = await j('POST', '/auth/login', {
    emailOrUsername: username,
    password: PASSWORD,
    deviceFingerprint: `lt-s${store}-fp-1`
  })
  if (lr.status !== 200 && lr.status !== 201) throw new Error(`login ${store} → ${lr.status} ${JSON.stringify(lr.data).slice(0, 120)}`)
  const h = {
    Authorization: `Bearer ${lr.data.accessToken || lr.data.token}`,
    'x-session-token': lr.data.sessionToken || ''
  }
  const [me, prods, pms, cls] = await Promise.all([
    j('POST', '/auth/me', null, h).then(r => (r.status === 404 ? j('GET', '/auth/me', null, h) : r)),
    j('GET', '/products', null, h),
    j('GET', '/payment-methods', null, h),
    j('GET', '/clients?page=0&pageSize=5', null, h)
  ])
  const list = x => (Array.isArray(x) ? x : x?.data || [])
  const products = list(prods.data).slice(0, 20).map(p => ({ id: p.id, price: Number(p.price || 100) || 100 }))
  const ef = list(pms.data).find(m => String(m.slug || m.name || '').toLowerCase().includes('efectivo'))
  const client = list(cls.data)[0]

  return {
    store,
    h,
    storeId: me.data?.storeId ?? store,
    branchId: me.data?.branchId ?? null,
    products,
    efectivoId: ef?.id ?? 1,
    clientId: client?.id ?? null
  }
}

async function pool(items, n, fn) {
  const out = []
  let i = 0
  await Promise.all(
    Array.from({ length: n }, async () => {
      while (i < items.length) {
        const k = i++
        try {
          out[k] = await fn(items[k])
        } catch (e) {
          out[k] = { error: String(e.message || e) }
        }
      }
    })
  )

  return out
}

const pct = (arr, p) => {
  if (!arr.length) return null
  const s = [...arr].sort((a, b) => a - b)

  return s[Math.min(s.length - 1, Math.floor((p / 100) * s.length))]
}

;(async () => {
  console.log(`[burst] RUN=${RUN} API=${API} stores=${STORES.length} RATE=${RATE}/s DURATION=${DURATION_S}s`)
  const booted = await pool(STORES, 20, boot)
  const ctx = booted.filter(b => b && !b.error && b.products.length && b.clientId)
  const fails = booted.filter(b => b?.error)
  console.log(`[burst] listos=${ctx.length} fallos_boot=${fails.length}${fails[0] ? ' ej: ' + fails[0].error : ''}`)
  if (!ctx.length) process.exit(1)

  const lat = []
  const statuses = {}
  const sales = []
  let seq = 0
  let inflight = 0
  let maxInflight = 0
  const perTick = RATE / 100 // cada 10 ms
  let acc = 0
  const t0 = Date.now()

  await new Promise(resolve => {
    const timer = setInterval(() => {
      if (Date.now() - t0 >= DURATION_S * 1000) {
        clearInterval(timer)
        resolve()

        return
      }
      acc += perTick
      while (acc >= 1) {
        acc -= 1
        const c = ctx[seq % ctx.length]
        const n = ++seq
        const p = c.products[n % c.products.length]
        const body = {
          clientId: c.clientId,
          storeId: c.storeId,
          branchId: c.branchId,
          status: 'Pagado',
          subtotal: p.price,
          totalAmount: p.price,
          notes: `PBURST|${RUN}|${n}`,
          items: [{ productId: p.id, quantity: 1, price: p.price }],
          paymentMethods: [{ paymentMethodId: c.efectivoId, amount: p.price }],
          printTicket: true
        }
        const ts = Date.now()
        inflight++
        maxInflight = Math.max(maxInflight, inflight)
        j('POST', '/sales', body, c.h)
          .then(r => {
            lat.push(Date.now() - ts)
            statuses[r.status] = (statuses[r.status] || 0) + 1
            if (r.status === 201 || r.status === 200) sales.push({ n, saleId: r.data?.id, store: c.store, t: ts })
          })
          .catch(e => {
            statuses[`net:${e.code || e.message}`] = (statuses[`net:${e.code || e.message}`] || 0) + 1
          })
          .finally(() => inflight--)
      }
    }, 10)
  })

  // esperar a los que siguen en vuelo (máx 60 s)
  const tEnd = Date.now()
  while (inflight > 0 && Date.now() - tEnd < 60000) await new Promise(r => setTimeout(r, 200))

  const summary = {
    run: RUN,
    rate: RATE,
    duration_s: DURATION_S,
    sent: seq,
    ok: sales.length,
    statuses,
    maxInflight,
    lat_ms: { p50: pct(lat, 50), p95: pct(lat, 95), p99: pct(lat, 99), max: pct(lat, 100) }
  }
  fs.writeFileSync(path.join(OUT_DIR, `${RUN}-sales.json`), JSON.stringify(sales))
  fs.writeFileSync(path.join(OUT_DIR, `${RUN}-summary.json`), JSON.stringify(summary, null, 2))
  console.log('[burst] fin', JSON.stringify(summary))
})()
