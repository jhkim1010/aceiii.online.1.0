// Driver CDP para las capturas de 119-16. Reescribe localhost:5002 -> localhost:5012 (API con DB local)
// sin tocar el dev server del usuario. Node 26: WebSocket global.
import { spawn } from 'node:child_process'
import fs from 'node:fs'

const OUT = process.argv[2]
const TOKEN = fs.readFileSync(process.argv[3], 'utf8').trim()
const PORT = 9333
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
const profile = process.argv[4]
const sleep = ms => new Promise(r => setTimeout(r, ms))

const chrome = spawn(CHROME, [
  '--headless=new', `--remote-debugging-port=${PORT}`, `--user-data-dir=${profile}`,
  '--window-size=1680,1050', '--hide-scrollbars', '--no-first-run', '--disable-gpu', 'about:blank'
], { stdio: 'ignore' })

let ver
for (let i = 0; i < 50; i++) {
  try { ver = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json(); if (ver.length) break } catch {}
  await sleep(300)
}
const page = ver.find(t => t.type === 'page')
const ws = new WebSocket(page.webSocketDebuggerUrl)
await new Promise(r => (ws.onopen = r))
let id = 0
const pend = new Map()
const handlers = []
ws.onmessage = e => {
  const m = JSON.parse(e.data)
  if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id) } else handlers.forEach(h => h(m))
}
const send = (method, params = {}) => new Promise(res => { const i = ++id; pend.set(i, res); ws.send(JSON.stringify({ id: i, method, params })) })
const ev = async expr => (await send('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true })).result?.result?.value

let rewritten = 0
handlers.push(async m => {
  if (m.method === 'Fetch.requestPaused') {
    const u = m.params.request.url
    if (u.startsWith('http://localhost:5002/')) {
      rewritten++
      await send('Fetch.continueRequest', { requestId: m.params.requestId, url: u.replace('localhost:5002', 'localhost:5012') })
    } else await send('Fetch.continueRequest', { requestId: m.params.requestId })
  }
})
await send('Page.enable'); await send('Runtime.enable'); await send('Network.enable')
const urls = new Map()
handlers.push(m => {
  if (m.method === 'Network.requestWillBeSent') { urls.set(m.params.requestId, m.params.request.url); if (!/_next|\.(js|css|png|svg|woff2?)(\?|$)/.test(m.params.request.url)) console.log('REQ', m.params.request.method, m.params.request.url.slice(0, 100)) }
  if (m.method === 'Network.responseReceived' && /:(5002|5012)/.test(m.params.response.url)) console.log('RESP', m.params.response.status, m.params.response.url.slice(0, 90))
  if (m.method === 'Runtime.consoleAPICalled' && ['error','warning'].includes(m.params.type)) console.log('CONSOLE', m.params.type, m.params.args.map(a => (a.value ?? a.description ?? '')).join(' ').slice(0, 200))
  if (m.method === 'Runtime.exceptionThrown') console.log('EXC', (m.params.exceptionDetails.exception?.description || m.params.exceptionDetails.text).slice(0, 300))
  if (m.method === 'Network.loadingFailed') console.log('FAIL', m.params.errorText, (urls.get(m.params.requestId) || '').slice(0, 90))
})
await send('Fetch.enable', { patterns: [{ urlPattern: 'http://localhost:5002/*' }] })
await send('Emulation.setDeviceMetricsOverride', { width: 1680, height: 1050, deviceScaleFactor: 1, mobile: false })

const selByLabel = async (label, opt) => {
  const idx = await ev(`[...document.querySelectorAll('.MuiSelect-select')].findIndex(e=>(e.closest('.MuiFormControl-root')?.innerText||'').trim().startsWith(${JSON.stringify(label)}))`)
  if (idx < 0) { console.log('NO SELECT', label); return }
  await click('.MuiSelect-select', idx); await click('[role="option"]', opt); await sleep(1800)
}
const dismiss = async () => {
  for (let i = 0; i < 3; i++) {
    if (/Selecciona Caja y Terminal/.test((await ev('document.body.innerText')) || '')) { await click('button', 0, 'Cancelar'); await sleep(1200) } else break
  }
}
const goto = async url => { await send('Page.navigate', { url }); await sleep(2500) }
const shot = async (name, clip) => {
  const r = await send('Page.captureScreenshot', { format: 'png', ...(clip ? { clip: { ...clip, scale: 1 } } : {}) })
  fs.writeFileSync(`${OUT}/${name}.png`, Buffer.from(r.result.data, 'base64'))
  console.log('shot', name)
}
const click = async (sel, idx = 0, text) => {
  const pos = await ev(`(()=>{let els=[...document.querySelectorAll(${JSON.stringify(sel)})];${text ? `els=els.filter(e=>e.textContent.trim().startsWith(${JSON.stringify(text)}));` : ''}const e=els[${idx}];if(!e)return null;e.scrollIntoView({block:'center'});const r=e.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})()`)
  if (!pos) { console.log('NOT FOUND', sel, text); return false }
  await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: pos.x, y: pos.y })
  await send('Input.dispatchMouseEvent', { type: 'mousePressed', x: pos.x, y: pos.y, button: 'left', clickCount: 1 })
  await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x: pos.x, y: pos.y, button: 'left', clickCount: 1 })
  await sleep(1800)
  return true
}

await goto('http://localhost:3050/login/')
await ev(`localStorage.setItem('accessToken', ${JSON.stringify(TOKEN)}); true`)
await goto('http://localhost:3050/reportes-v2/prediccion-produccion/')
for (let i = 0; i < 60; i++) { const t = await ev('document.body.innerText'); if (/Análisis/.test(t || '') && /Atributos/.test(t || '')) break; await sleep(2000) }
await sleep(3000)
if (/login/.test(await ev('location.pathname'))) {
  console.log('stuck at login; next.router:', await ev('window.next && window.next.router && window.next.router.asPath'))
  await ev("window.next.router.replace('/reportes-v2/prediccion-produccion/'); true")
  for (let i = 0; i < 40; i++) { const t = await ev('document.body.innerText'); if (/Análisis/.test(t || '') && /Atributos/.test(t || '')) break; await sleep(2000) }
  console.log('after manual replace', await ev('location.pathname'))
}
console.log('title', await ev('document.title'), 'rewritten', rewritten, 'url', await ev('location.href'))
console.log('ls', await ev('Object.keys(localStorage).join(",")'))
console.log('body', (await ev('document.body.innerText')).slice(0, 400).replace(/\n/g, ' | '))
await dismiss()
await shot('01-analisis')
const rowSel = '.MuiDataGrid-row, .ag-row, [role="row"][data-id], tbody tr'
// Ⓑ Fundamento: click primera fila
if (await click(rowSel, 0)) { await sleep(2500); await ev(`[...document.querySelectorAll('h6,.MuiTypography-subtitle2')].find(e=>/^Fundamento ·/.test(e.textContent))?.scrollIntoView({block:'start'}); true`); await sleep(800); await shot('02-analisis-fundamento-B') }
// Datos usados (línea A)
const lineaA = await ev(`(()=>{const e=[...document.querySelectorAll('*')].find(x=>x.children.length<8&&/Datos usados|tickets/i.test(x.textContent)&&x.textContent.length<400&&x.getBoundingClientRect().height>0);if(!e)return null;const r=e.getBoundingClientRect();return {x:0,y:Math.max(0,r.y-6),width:1680,height:r.height+12}})()`)
console.log('lineaA', JSON.stringify(lineaA))
if (lineaA) await shot('03-datos-usados-A', lineaA)
const tabs = [['Atributos', '04-atributos'], ['Backtest', '05-backtest'], ['Simulación', '07-simulacion'], ['Configuración', '09-configuracion']]
for (const [t, name] of tabs) {
  await click('button[role="tab"]', 0, t)
  await sleep(2500)
  await dismiss()
  await shot(name)
  if (t === 'Backtest') {
    if (await click(rowSel, 0)) { await sleep(3000); console.log('sel', await ev(`[...document.querySelectorAll('.MuiSelect-select')].map(e=>e.closest('.MuiFormControl-root')?.innerText.replace(/\\n/g,'/'))`)); await selByLabel('Modelo', 2); await sleep(2500); await shot('06-backtest-grafico-C') }
  }
  if (t === 'Simulación') {
    // Ⓓ: botón "Ver cuenta" habilitado
    if (await click('button:not([disabled])', 0, 'Ver cuenta')) { await sleep(1500); const cbs = await ev(`[...document.querySelectorAll('[role=combobox]')].map(e=>e.textContent.trim())`); console.log('combos', JSON.stringify(cbs)); console.log('sel', await ev(`[...document.querySelectorAll('.MuiSelect-select')].map(e=>e.closest('.MuiFormControl-root')?.innerText.replace(/\\n/g,'/'))`)); await selByLabel('Modelo', 0); await selByLabel('Origen', 1); await sleep(2500); await shot('08-simulacion-cuenta-D') }
  }
}
console.log('rewritten', rewritten)
ws.close(); chrome.kill()
process.exit(0)
