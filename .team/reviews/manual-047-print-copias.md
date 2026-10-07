Reading additional input from stdin...
2026-10-07T19:36:16.398425Z ERROR codex_models_manager::cache: failed to load models cache: missing field `base_instructions` at line 140 column 5
OpenAI Codex v0.146.0
--------
workdir: /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
model: gpt-5.6-sol
provider: openai
approval: never
sandbox: workspace-write [workdir, /tmp, $TMPDIR]
reasoning effort: none
reasoning summaries: none
session id: 01a117dd-d676-7dd1-a4cf-0cf064432eb8
--------
user
Revisá este diff de print-agent (Electron, impresora térmica ESC/POS). Regla absoluta del dueño: un pedido de impresión NUNCA debe salir duplicado sin querer. Se agrega «Copias por venta» (1–3): sólo para print_invoice con printJobId 'sale-invoice:<id>' (ticket automático al vender); reimpresión 'sale-reprint:…' y factura AFIP salen 1. El trabajo se registra una vez en el ledger (claimPrintJob) antes de imprimir; el pipeline dibuja una vez y llama printImage N veces. Buscá errores concretos: caminos donde salgan más copias de las pedidas (reintentos, reenvíos del servidor, edge/offline, error a mitad), qué pasa si falla la copia 2, otros caminos que usen printTicket, y la UI. No estilo.
diff --git a/print-agent/main.js b/print-agent/main.js
index 8e44121..c1823ca 100644
--- a/print-agent/main.js
+++ b/print-agent/main.js
@@ -7,6 +7,7 @@ const os = require('os');
 const Store = require('electron-store');
 const printDedup = require('./src/print-dedup');
 const { printTicket: printTicketSinContar } = require('./src/print-pipeline');
+const { copiasDelTicket } = require('./src/ticket-copias');
 const { formatFiscalHtml }  = require('./src/fiscal-formatter');
 const { formatQrHtml }      = require('./src/qr-formatter');
 const { formatTempTicketHtml, formatInvoiceHtml } = require('./src/formatter');
@@ -60,6 +61,7 @@ const store = new Store({
     },
     printControl: true,   // 판매 확정 시 컨트롤 티켓 출력
     printFiscal: true,    // AFIP 발행 시 영수증 출력
+    ticketCopias: 1,      // [2026-10-07] copias del ticket de venta automático (1–3, src/ticket-copias.js)
     ticketFont: ticketSettings.DEFAULT_FONT_ID,   // 티켓 폰트 (기본 Arial — 가독성)
     ticketFontScale: ticketSettings.DEFAULT_SCALE, // 티켓 폰트 크기 배율
     // 오른쪽 여백(px) — 프린터의 인쇄 가능 폭이 576 보다 좁아 끝이 잘릴 때만 올린다.
@@ -1189,7 +1191,10 @@ function initWebSocket() {
       }
 
       // broadcastLog 를 파이프라인에 주입 → 각 단계가 메인창/콘솔에 실시간 표시
-      await printTicket(payload, printerCfg, broadcastLog);
+      // [2026-10-07] copias: sólo el ticket automático de la venta (no la reimpresión)
+      const copias = copiasDelTicket(payload, store.get('ticketCopias'));
+      if (copias > 1) broadcastLog(`🧾 print_invoice #${num} — ${copias} copias`);
+      await printTicket(payload, printerCfg, broadcastLog, { copias });
       const elapsed = Date.now() - start;
 
       broadcastLog(`✅ print_invoice #${num} — OK (${elapsed}ms)`);
diff --git a/print-agent/renderer/index.html b/print-agent/renderer/index.html
index 1a18682..2f39f09 100644
--- a/print-agent/renderer/index.html
+++ b/print-agent/renderer/index.html
@@ -78,6 +78,18 @@
       <span id="marginValue" style="min-width:46px;text-align:right;font-size:12px;color:#f5a623;font-weight:bold;">0 px</span>
     </div>
     <p class="hint" style="margin:6px 2px 0;font-size:11px;color:#8a8db0;">Se aplica a la próxima impresión (ticket, control, fiscal y prueba).</p>
+    <!-- ── Copias del ticket de venta (2026-10-07) ──
+         Sólo el ticket que sale solo al vender. La reimpresión desde la web sale 1;
+         factura AFIP, comanda y prueba no cambian (src/ticket-copias.js). -->
+    <div class="info-row" style="align-items:center;margin-top:10px;">
+      <span class="info-label">🧾 Copias por venta</span>
+      <select id="copiasSelect" style="flex:1;max-width:220px;padding:5px 8px;background:#12122a;color:#e0e0e0;border:1px solid #33335a;border-radius:6px;font-size:12px;">
+        <option value="1">1 copia</option>
+        <option value="2">2 copias</option>
+        <option value="3">3 copias</option>
+      </select>
+    </div>
+    <p class="hint" style="margin:4px 2px 0;font-size:11px;color:#8a8db0;">Ticket de venta al cobrar. La reimpresión sale 1; la factura AFIP no cambia.</p>
     <p class="hint" style="margin:2px 2px 0;font-size:11px;color:#8a8db0;">
       Subilo sólo si el borde derecho sale cortado. Hasta 12&nbsp;px no cambia nada más;
       más que eso, las descripciones largas ocupan un renglón extra (nunca se cortan).
@@ -792,6 +804,18 @@
         console.error('[renderer] font settings init error:', e);
       }
 
+      // ── Copias del ticket de venta ──
+      try {
+        const copiasSel = document.getElementById('copiasSelect');
+        const guardadas = Number(await window.electronAPI.getConfig('ticketCopias'));
+        copiasSel.value = [1, 2, 3].includes(guardadas) ? String(guardadas) : '1';
+        copiasSel.addEventListener('change', async () => {
+          await window.electronAPI.setConfig('ticketCopias', Number(copiasSel.value) || 1);
+        });
+      } catch (e) {
+        console.error('[renderer] copias init error:', e);
+      }
+
       // ── Pie de impresión ──────────────────────────────────────────────────
       const footerText  = document.getElementById('footerText');
       const footerHint  = document.getElementById('footerHint');
diff --git a/print-agent/src/print-pipeline.js b/print-agent/src/print-pipeline.js
index d759867..aefe578 100644
--- a/print-agent/src/print-pipeline.js
+++ b/print-agent/src/print-pipeline.js
@@ -19,8 +19,10 @@ const { printImage }        = require('./printer');
  * @param {object} data         - formatInvoiceHtml() 입력 데이터
  * @param {object} printerCfg   - printer 설정 (type, host, port, ...)
  * @param {function} log        - 단계별 디버그 로그 콜백 (운영 추적용, 선택)
+ * @param {{copias?: number}} o - [2026-10-07] copias del MISMO ticket (src/ticket-copias.js).
+ *                                Se dibuja una vez y se manda N veces: las N salen iguales.
  */
-async function printTicket(data, printerCfg, log = () => {}) {
+async function printTicket(data, printerCfg, log = () => {}, { copias = 1 } = {}) {
   const t0 = Date.now();
 
   // 0. 프린터 설정 검증 — 설정 누락이면 이후 단계 진입 전에 명확히 실패
@@ -43,10 +45,13 @@ async function printTicket(data, printerCfg, log = () => {}) {
   const pngBuffer = await renderHtmlToPng(html, 576, 10000, log);
   log(`🖼️ [2/3] PNG 렌더 완료 (${pngBuffer ? pngBuffer.length : 0} bytes, ${Date.now() - t1}ms)`);
 
-  // 3. PNG → ESC/POS → 프린터
-  const t2 = Date.now();
-  await printImage(pngBuffer, printerCfg, log);
-  log(`🧾 [3/3] 프린터 전송 완료 (${Date.now() - t2}ms, 총 ${Date.now() - t0}ms)`);
+  // 3. PNG → ESC/POS → 프린터 (copias: una tras otra, cada una con su corte)
+  const n = Number.isInteger(copias) && copias > 1 ? copias : 1;
+  for (let i = 1; i <= n; i += 1) {
+    const t2 = Date.now();
+    await printImage(pngBuffer, printerCfg, log);
+    log(`🧾 [3/3] 프린터 전송 완료${n > 1 ? ` (copia ${i}/${n})` : ''} (${Date.now() - t2}ms, 총 ${Date.now() - t0}ms)`);
+  }
 }
 
 module.exports = { printTicket };
=== NEW src/ticket-copias.js
/**
 * ticket-copias.js — cuántas copias del ticket de venta (2026-10-07 usuario).
 *
 * > «Print agent가 매번 티켓을 몇 카피를 출력할지 결정할 수 있어야 하는데»
 *   → ajuste del agente (1–3), sólo el ticket de venta.
 *
 * ★ Sólo el ticket que sale SOLO al vender (`printJobId = sale-invoice:<id>`). La reimpresión
 *   (`sale-reprint:…`) la pide una persona y sale 1: si pide una, no le salen tres.
 *   Factura AFIP, comanda, presupuesto y prueba no pasan por acá.
 * ★ Sin printJobId (servidor viejo) → 1, como siempre. Ante cualquier duda, 1.
 * ★ Las copias son UN trabajo: el registro de «ya impreso» (print-dedup) se toma una vez antes de
 *   imprimir. Si el servidor reenvía el mismo trabajo, se rechaza entero — nunca 2×N.
 */
const MAX_COPIAS = 3;

/** Lo guardado → 1..MAX_COPIAS (cualquier cosa rara = 1). */
function normalizarCopias(v) {
  const n = Number(v);

  return Number.isInteger(n) && n >= 1 && n <= MAX_COPIAS ? n : 1;
}

/** Copias para ESTE trabajo de print_invoice. */
function copiasDelTicket(payload, configurado) {
  const job = payload && typeof payload.printJobId === 'string' ? payload.printJobId : '';
  if (!job.startsWith('sale-invoice:')) return 1;
  if (payload && payload.factura) return 1;

  return normalizarCopias(configurado);
}

module.exports = { copiasDelTicket, normalizarCopias, MAX_COPIAS };
warning: `--dangerously-bypass-hook-trust` is enabled. Enabled hooks may run without review for this invocation.
warning: `--dangerously-bypass-hook-trust` is enabled. Enabled hooks may run without review for this invocation.
hook: SessionStart
hook: SessionStart
hook: SessionStart
hook: SessionStart Failed
hook: SessionStart Failed
hook: SessionStart Completed
hook: UserPromptSubmit
hook: UserPromptSubmit Completed
codex
Voy a contrastar el diff con el flujo real de deduplicación, los emisores `print_invoice` y todos los usos de `printTicket`. No modificaré archivos; entregaré sólo hallazgos concretos.
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
exec
/bin/zsh -lc "sed -n '1,240p' .team/REVIEW-PROTOCOL.md; rg -n \"claimPrintJob|printTicket\\(|print_invoice|sale-invoice:|sale-reprint:|printJobId|ticketCopias\" print-agent --glob '"'!node_modules/**'"'" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
# cmux team 협업 프로토콜 — Claude Code(구현) ↔ codex(보안 검토)

역할 경계는 [`AGENTS.md`](../AGENTS.md) 가 정의한다. 이 문서는 **두 에이전트가 어디서 만나는지**만 정한다.

## 원칙

| | Claude Code | codex |
|---|---|---|
| 코드 수정 | **한다** | 하지 않는다 (보고서만) |
| 커밋·push | 한다 | 하지 않는다 |
| 마이그레이션 | 새 파일 작성·적용 | 초안 제안만, 기존 파일 수정 금지 |
| 운영 DB | 조회 허용(CLAUDE.md 규칙) | **접속 금지** |
| 최종 판단 | **한다** — 검토 지적의 수용/반박을 결정 | 하지 않는다 |

**codex 의 지적은 입력이지 명령이 아니다.** Claude 는 각 지적에 대해 수용하거나 근거를 대고 반박한다.
반박도 기록으로 남긴다 — 다음 검토에서 같은 지적이 반복되는 것을 막는다.

## 디렉터리 규약

```
.team/
├── config.json              # 모델 설정 (추적됨)
├── REVIEW-PROTOCOL.md       # 이 문서
├── tasks/NNN-<slug>/
│   └── task.md              # 구현 태스크 정의 (Claude 가 집행)
└── reviews/
    ├── NNN-codex.md         # codex 검토 보고서 (codex 가 생성)
    └── NNN-resolution.md    # 지적별 수용/반박 결정 (Claude 가 생성)
```

`reviews/` 는 추적한다 — 무엇을 왜 수용/반박했는지가 다음 phase 의 근거가 된다.

## 흐름

```
1. Claude   구현 → 커밋 (아직 push 안 함)
2. Claude   scripts/codex-review.sh --task NNN   ← 변경 diff 를 codex 에 넘긴다
3. codex    .team/reviews/NNN-codex.md 생성 (AGENTS.md 보고 형식)
4. Claude   지적별 판단 → .team/reviews/NNN-resolution.md
              - 수용 → 수정 커밋
              - 반박 → 근거 기록 (코드 그대로)
5. Claude   CRITICAL/HIGH 가 모두 해소·반박된 뒤에만 push
```

**게이트:** `CRITICAL` 또는 `HIGH` 가 미해소 상태로 남아 있으면 push 하지 않는다.
`MEDIUM`/`LOW` 는 resolution 에 기록만 하고 넘어갈 수 있다.

## 검토 입력에서 제외하는 것

`scripts/codex-review.sh` 가 diff 를 만들 때 아래를 제외한다. codex 가 값을 보지 못하게 하는 것이 목적이다.

- `.env`, `.env.*` (AGENTS.md 금지 항목)
- `*.pem`, `*.key`, `id_*`
- `package-lock.json`, `node_modules/` (노이즈)

## 실행

```bash
# 태스크 단위 검토 — main 대비 현재 브랜치 diff
scripts/codex-review.sh --task 001

# 워킹트리 검토 — 커밋 전 빠른 점검
scripts/codex-review.sh --working

# 특정 경로만
scripts/codex-review.sh --task 002 --paths api-ventago/src/app/products
```

cmux team 으로 병렬 실행할 때:

```bash
cmux claude-teams     # 구현 측 (기존 .team/tasks 집행)
cmux codex-teams      # 검토 측
```

> **codex 미설치 상태면 `cmux codex-teams` 가 `codex not found in PATH` 로 실패한다.**
> `npm i -g @openai/codex` 후 `codex login` 을 한 번 거쳐야 한다.

## 검토 대상 우선순위 (이 저장소 기준)

AGENTS.md 의 일반 기준 위에, 이 프로젝트에서 실제로 사고가 났던 지점을 얹는다.

1. **쓰기 경로의 트랜잭션 누락** — 여러 모델을 순차 호출하며 `transaction` 인자를 빠뜨리면 그 문장만 별도 커밋돼 부분 저장이 된다 (Phase 64 결함 2·3·4)
2. **`stocks` 원장 규약** — append-only. UPDATE/DELETE 금지, 조회·기록은 `product_branch_id` 기준 (`product_id` 컬럼은 없다)
3. **테넌트 경계** — 사용자가 준 `branchId`/`variantId`/`storeId` 를 소유권 확인 없이 쓰는 경로 (Phase 69 CR-02 유형)
4. **fail-open** — 권한·역할 판정에 실패했을 때 *더 주는* 분기 (Phase 65 W6 6-2 유형)
5. **트랜잭션 안 외부 I/O** — HTTP·프린터·소켓 호출은 커밋 후에 (pool 고갈)
print-agent/src/ticket-copias.js:7: * ★ Sólo el ticket que sale SOLO al vender (`printJobId = sale-invoice:<id>`). La reimpresión
print-agent/src/ticket-copias.js:8: *   (`sale-reprint:…`) la pide una persona y sale 1: si pide una, no le salen tres.
print-agent/src/ticket-copias.js:10: * ★ Sin printJobId (servidor viejo) → 1, como siempre. Ante cualquier duda, 1.
print-agent/src/ticket-copias.js:23:/** Copias para ESTE trabajo de print_invoice. */
print-agent/src/ticket-copias.js:25:  const job = payload && typeof payload.printJobId === 'string' ? payload.printJobId : '';
print-agent/src/ticket-copias.js:26:  if (!job.startsWith('sale-invoice:')) return 1;
print-agent/src/print-pipeline.js:9: *   await printTicket(invoiceData, printerConfig);
print-agent/src/print-pipeline.js:25:async function printTicket(data, printerCfg, log = () => {}, { copias = 1 } = {}) {
print-agent/main.js:64:    ticketCopias: 1,      // [2026-10-07] copias del ticket de venta automático (1–3, src/ticket-copias.js)
print-agent/main.js:796:// 서버 이벤트(`print_invoice`, `print_fiscal`) 수신 → 출력 파이프라인 연동.
print-agent/main.js:1110:  wsConnection.on('print_invoice', async (payload) => {
print-agent/main.js:1112:      broadcastLog('ℹ️ print_invoice 무시 — printControl=false');
print-agent/main.js:1131:    if (printerCfg?.type && puertaAbierta && !claimPrintJob('print_invoice', payload)) {
print-agent/main.js:1137:    broadcastLog(`🖨 print_invoice #${num} — imprimiendo...`);
print-agent/main.js:1144:    console.log('[print_invoice] ← payload received', {
print-agent/main.js:1153:      broadcastLog(`❌ print_invoice #${num} — ${msg}`);
print-agent/main.js:1154:      console.error('[print_invoice] ✗', msg, '— printerCfg=', printerCfg);
print-agent/main.js:1171:          broadcastLog('ℹ️ print_invoice(fiscal) 무시 — printFiscal=false');
print-agent/main.js:1176:        broadcastLog('🖨 print_invoice(fiscal) — renderizando comprobante AFIP...');
print-agent/main.js:1183:        broadcastLog(`✅ print_invoice(fiscal) — OK (${fiscalElapsed}ms)`);
print-agent/main.js:1195:      const copias = copiasDelTicket(payload, store.get('ticketCopias'));
print-agent/main.js:1196:      if (copias > 1) broadcastLog(`🧾 print_invoice #${num} — ${copias} copias`);
print-agent/main.js:1197:      await printTicket(payload, printerCfg, broadcastLog, { copias });
print-agent/main.js:1200:      broadcastLog(`✅ print_invoice #${num} — OK (${elapsed}ms)`);
print-agent/main.js:1208:      broadcastLog(`❌ print_invoice #${num} — ${err.message}`);
print-agent/main.js:1209:      console.error('[print_invoice] ✗ pipeline threw', {
print-agent/main.js:1232:    if (printerCfg?.type && !claimPrintJob('print_fiscal', payload)) return;
print-agent/main.js:1266:    if (printerCfg?.type && !claimPrintJob('print_qr', payload)) return;
print-agent/main.js:1354:    if (!claimPrintJob('print_temp', payload)) return;
print-agent/main.js:1410:function claimPrintJob(event, payload) {
print-agent/main.js:1411:  const jobId = payload?.printJobId;
print-agent/main.js:1415:  console.warn(`[${event}] DUPLICADO ignorado — printJobId=${jobId} ya impreso`);
print-agent/main.js:1478:    await printTicket(sample, printerCfg, broadcastLog);
print-agent/src/formatter.js:354://     는 그대로 둔다 — `claimPrintJob('print_invoice', payload)` 의 중복 인쇄 판정이
print-agent/src/index.js:3: * WebSocket으로 백엔드에서 print_invoice 이벤트를 수신하고
print-agent/src/index.js:42:socket.on('print_invoice', async (invoiceData) => {
print-agent/renderer/index.html:810:        const guardadas = Number(await window.electronAPI.getConfig('ticketCopias'));
print-agent/renderer/index.html:813:          await window.electronAPI.setConfig('ticketCopias', Number(copiasSel.value) || 1);
print-agent/test/offline-ticket.smoke.js:74:// ── ⑥ print_invoice(서버 재인쇄) 경로도 참조를 muestra ──
print-agent/test/offline-ticket.smoke.js:82:  'print_invoice muestra la referencia');
print-agent/test/ticket-copias.smoke.js:8:const venta = { printJobId: 'sale-invoice:42' };
print-agent/test/ticket-copias.smoke.js:11:assert.strictEqual(copiasDelTicket({ printJobId: 'sale-reprint:42:abc' }, 3), 1, 'reimpresión: 1');
print-agent/test/ticket-copias.smoke.js:12:assert.strictEqual(copiasDelTicket({ printJobId: 'sale-invoice:42', factura: {} }, 3), 1, 'factura AFIP: 1');
print-agent/test/ticket-copias.smoke.js:13:assert.strictEqual(copiasDelTicket({}, 3), 1, 'sin printJobId (servidor viejo): 1');
print-agent/test/ticket-copias.smoke.js:39:  await printTicket({}, cfg, () => {}, { copias: 3 });
print-agent/test/ticket-copias.smoke.js:43:  await printTicket({}, cfg, () => {});
print-agent/test/ticket-copias.smoke.js:47:  await printTicket({}, cfg, () => {}, { copias: 0 });
print-agent/test/print-dedup.smoke.js:18:assert.strictEqual(dedup.claimJob('sale-reprint:42:abc'), true, '재인쇄는 새 작업이다');
print-agent/test/ticket-uniform.smoke.js:5: * 「티켓 다시 출력」(`print_invoice` → `formatInvoiceHtml`)이 서로 다른 종이를 냈다.

hook: PostToolUse
hook: PostToolUse
hook: PostToolUse Failed
hook: PostToolUse Completed
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
exec
/bin/zsh -lc "sed -n '760,840p' print-agent/main.js; sed -n '1080,1435p' print-agent/main.js; sed -n '1,240p' print-agent/src/print-dedup.js; sed -n '1,120p' print-agent/src/index.js; sed -n '1,140p' print-agent/test/ticket-copias.smoke.js; rg -n \"offline|edge|enqueue|queue|reconnect|print_temp|printTicketSinContar|function printTicket|const printTicket\" print-agent/main.js print-agent/src print-agent/renderer --glob '"'!node_modules/**'"'" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
        transports:   ['websocket'],
        upgrade:      false,
      });

      const timer = setTimeout(() => {
        testSocket.disconnect();
        resolve({ success: false, error: 'Timeout: no se pudo conectar en 5s' });
      }, 5000);

      testSocket.on('connect', () => {
        clearTimeout(timer);
        // 연결 성공 시 즉시 종료 (auth_error 도착 가능성 있어 짧게 대기)
        setTimeout(() => {
          testSocket.disconnect();
          resolve({ success: true });
        }, 500);
      });

      // PrintGateway 인증 실패 시 auth_error emit 후 disconnect
      testSocket.on('auth_error', (payload) => {
        clearTimeout(timer);
        testSocket.disconnect();
        resolve({ success: false, error: payload?.message || 'API Key inválida' });
      });

      testSocket.on('connect_error', (err) => {
        clearTimeout(timer);
        resolve({ success: false, error: err.message });
      });
    } catch (err) {
      resolve({ success: false, error: err.message });
    }
  });
}

// ─── WebSocket 메인 루프 (Phase 11-03) ──────────────────────────────────────
// 서버 이벤트(`print_invoice`, `print_fiscal`) 수신 → 출력 파이프라인 연동.
function initWebSocket() {
  // 활성 프로파일 우선 사용, 없으면 기존 단일 설정 폴백
  const profiles        = store.get('profiles') || [];
  const activeProfileId = store.get('activeProfileId');
  const activeProfile   = profiles.find(p => p.id === activeProfileId);

  const url    = SERVER_URL;
  const apiKey = activeProfile ? activeProfile.apiKey : store.get('apiKey');

  // ─── host와 namespace 분리 ─────────────────────────────────────────────────
  // NestJS global prefix(/api)는 HTTP REST에만 적용되고 socket.io namespace에는 적용 안 됨.
  // 따라서 apiUrl이 ".../api"여도 namespace는 /print-agent (prefix 없음) 그대로여야 함.
  // 해결: URL에서 origin만 추출하고, namespace는 별도로 붙임.
  let originOnly = url;
  try {
    const u = new URL(url);
    originOnly = `${u.protocol}//${u.host}`;
  } catch (_) { /* 파싱 실패 시 원본 사용 */ }
  const nsUrl = `${originOnly}/print-agent`;

  // ─── 디버깅: 실제 사용되는 config 값 모두 노출 ─────────────────────────────
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('[initWebSocket] config 검사');
  console.log('  apiUrl(저장값):', JSON.stringify(url));
  console.log('  origin(추출):', originOnly);
  console.log('  apiKey:', apiKey ? `${apiKey.slice(0, 12)}...(len=${apiKey.length})` : 'EMPTY');
  console.log('  최종 namespace URL =>', nsUrl);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  broadcastLog(`🔍 connecting to ${nsUrl}`);

  if (!url || !apiKey) {
    broadcastLog('⚠️ apiUrl/apiKey 미설정 — 셋업 마법사를 먼저 완료하세요');

    return;
  }

  // 기존 연결 정리
  // ★ failover 를 **소켓보다 먼저** 멈춘다. 소켓을 먼저 끊으면 그 'disconnect' 가
  //   옛 failover 의 유예 타이머를 켜서, 정리한 직후에 edge 로 붙어 버린다.
  if (edgeFailoverHandle) {
    try { edgeFailoverHandle.stop(); } catch (_e) { /* ignore */ }
    edgeFailoverHandle = null;
  }
  if (wsConnection) {
        '| via=', res.headers.get('via'));
      broadcastLog(`🩺 handshake ${res.status}: ${body.slice(0, 90)}`);
    } catch (e) {
      console.log('[diag-400] fetch ERROR:', e.message);
      broadcastLog(`🩺 diag falló: ${e.message}`);
    }
  }

  wsConnection.on('connect_error', (err) => {
    setConnectionStatus('reconnecting');
    // 풍부한 디버그 정보 노출
    console.log('[connect_error] message=', err?.message);
    console.log('[connect_error] type=',    err?.type);
    console.log('[connect_error] description=', err?.description);
    console.log('[connect_error] context=', err?.context);
    console.log('[connect_error] data=',    err?.data);
    console.log('[connect_error] stack=',   err?.stack);
    const detail = err?.description?.message || err?.description || err?.context?.message || '';
    broadcastLog(`❌ connect_error: ${err?.message} ${detail ? '| ' + detail : ''}`);

    // xhr poll error 또는 400 이면 핸드셰이크 본문을 직접 캡처해 engine.io code 확인.
    const isPoll400 = /xhr poll error/i.test(err?.message || '') ||
      err?.description === 400 ||
      err?.context?.status === 400;
    if (isPoll400) {
      diagnose400();
    }
  });

  // ── 컨트롤 티켓 출력 ─────────────────────────────────────────────────────
  wsConnection.on('print_invoice', async (payload) => {
    if (!store.get('printControl')) {
      broadcastLog('ℹ️ print_invoice 무시 — printControl=false');

      return;
    }

    const printerCfg = getActivePrinterCfg();

    // ★ 작업 소비는 **인쇄를 실제로 할 수 있다고 확인한 뒤**에 한다.
    //   설정이 꺼져 있거나 프린터가 없어서 못 찍은 것까지 «찍음» 으로 기록하면,
    //   설정을 고치고 다시 보내도 원장이 거절해 **영영 안 나온다.**
    //
    // ★ 이 이벤트는 두 갈래다: `payload.factura` 가 있으면 fiscal 경로로 가고
    //   그쪽은 `printFiscal` 로 다시 막힌다. 그 스위치까지 여기서 같이 본다 —
    //   안 그러면 printFiscal=false 인 상태에서 job 만 소비되고, 스위치를 켠 뒤
    //   재전송해도 안 나온다.
    const puertaAbierta = payload?.factura
      ? store.get('printFiscal')
      : store.get('printControl');

    if (printerCfg?.type && puertaAbierta && !claimPrintJob('print_invoice', payload)) {
      return;
    }
    const start      = Date.now();
    const num        = payload?.invoice?.number || payload?.invoiceId || '?';

    broadcastLog(`🖨 print_invoice #${num} — imprimiendo...`);

    // ── 디버그: payload / printerCfg 요약 (운영 출력 오류 추적용) ──
    broadcastLog(
      `   ↳ payload: items=${Array.isArray(payload?.items) ? payload.items.length : '?'} ` +
        `branch=${payload?.branchId ?? '?'} invoiceId=${payload?.invoiceId ?? '?'}`,
    );
    console.log('[print_invoice] ← payload received', {
      invoiceId: payload?.invoiceId,
      branchId:  payload?.branchId,
      items:     Array.isArray(payload?.items) ? payload.items.length : undefined,
    });

    // 프린터 설정 누락이면 파이프라인 진입 전에 명확히 실패 (원인 즉시 노출)
    if (!printerCfg || !printerCfg.type) {
      const msg = 'printer no configurado (setup wizard 미완료 또는 활성 프로파일 없음)';
      broadcastLog(`❌ print_invoice #${num} — ${msg}`);
      console.error('[print_invoice] ✗', msg, '— printerCfg=', printerCfg);
      wsConnection.emit('print_ack', {
        invoiceId: payload?.invoiceId,
        status:    'error',
        error:     msg,
        ts:        Date.now(),
      });

      return;
    }

    try {
      // ── AFIP 재정(fiscal) 분기 — WIRING GAP #1 (Phase 57 W1) ─────────────
      // payload.factura (shape D-02) 가 있으면 fiscal path 로 렌더 (letra/IVA/CAE/QR).
      // 없으면 아래 printTicket (control ticket) path 그대로 — 비-AFIP 무회귀.
      if (payload.factura) {
        if (!store.get('printFiscal')) {
          broadcastLog('ℹ️ print_invoice(fiscal) 무시 — printFiscal=false');

          return;
        }

        broadcastLog('🖨 print_invoice(fiscal) — renderizando comprobante AFIP...');
        const fiscalHtml = await formatFiscalHtml(payload.factura);
        const fiscalPng  = await renderHtmlToPng(fiscalHtml, 576, 10000, broadcastLog);

        await printImage(fiscalPng, printerCfg, broadcastLog);
        const fiscalElapsed = Date.now() - start;

        broadcastLog(`✅ print_invoice(fiscal) — OK (${fiscalElapsed}ms)`);
        wsConnection.emit('print_ack', {
          invoiceId: payload?.invoiceId,
          status:    'ok',
          ts:        Date.now(),
        });

        return;
      }

      // broadcastLog 를 파이프라인에 주입 → 각 단계가 메인창/콘솔에 실시간 표시
      // [2026-10-07] copias: sólo el ticket automático de la venta (no la reimpresión)
      const copias = copiasDelTicket(payload, store.get('ticketCopias'));
      if (copias > 1) broadcastLog(`🧾 print_invoice #${num} — ${copias} copias`);
      await printTicket(payload, printerCfg, broadcastLog, { copias });
      const elapsed = Date.now() - start;

      broadcastLog(`✅ print_invoice #${num} — OK (${elapsed}ms)`);
      wsConnection.emit('print_ack', {
        invoiceId: payload?.invoiceId,
        status:    'ok',
        ts:        Date.now(),
      });
    } catch (err) {
      // fire-and-forget: 출력 실패가 판매 트랜잭션에 영향 없도록 ack만 전송
      broadcastLog(`❌ print_invoice #${num} — ${err.message}`);
      console.error('[print_invoice] ✗ pipeline threw', {
        message: err?.message,
        stack:   err?.stack,
      });
      wsConnection.emit('print_ack', {
        invoiceId: payload?.invoiceId,
        status:    'error',
        error:     err.message,
        ts:        Date.now(),
      });
    }
  });

  // ── AFIP 영수증 출력 ──────────────────────────────────────────────────────
  wsConnection.on('print_fiscal', async (payload) => {
    if (!store.get('printFiscal')) {
      broadcastLog('ℹ️ print_fiscal 무시 — printFiscal=false');

      return;
    }

    const printerCfg = getActivePrinterCfg();
    // 위와 같은 이유 — 못 찍는 상태에서 작업을 소비하지 않는다.
    if (printerCfg?.type && !claimPrintJob('print_fiscal', payload)) return;
    const start      = Date.now();
    const caeTail    = payload?.afip?.cae ? String(payload.afip.cae).slice(-6) : '?';

    broadcastLog(`🖨 print_fiscal CAE:${caeTail} — imprimiendo...`);

    try {
      // formatFiscalHtml 는 async + shape D-02 (Phase 57 W1) — payload.factura 우선, 폴백 payload.
      const html = await formatFiscalHtml(payload.factura || payload);
      const png  = await renderHtmlToPng(html, 576, 10000, broadcastLog);

      await printImage(png, printerCfg, broadcastLog);
      const elapsed = Date.now() - start;

      broadcastLog(`✅ print_fiscal CAE:${caeTail} — OK (${elapsed}ms)`);
      wsConnection.emit('print_ack', {
        invoiceId: payload?.invoiceId,
        status:    'ok',
        ts:        Date.now(),
      });
    } catch (err) {
      broadcastLog(`❌ print_fiscal CAE:${caeTail} — ${err.message}`);
      wsConnection.emit('print_ack', {
        invoiceId: payload?.invoiceId,
        status:    'error',
        error:     err.message,
        ts:        Date.now(),
      });
    }
  });

  // Phase 38 — CodigoMadre QR 라벨 출력
  wsConnection.on('print_qr', async (payload) => {
    const printerCfg = getActivePrinterCfg();
    if (printerCfg?.type && !claimPrintJob('print_qr', payload)) return;
    const start = Date.now();
    const code = payload?.code || '?';

    broadcastLog(`🖨 print_qr ${code} — imprimiendo...`);

    try {
      const html = await formatQrHtml(payload);
      const png = await renderHtmlToPng(html, 576, 10000, broadcastLog);

      await printImage(png, printerCfg, broadcastLog);
      broadcastLog(`✅ print_qr ${code} — OK (${Date.now() - start}ms)`);
      wsConnection.emit('print_ack', { code, status: 'ok', ts: Date.now() });
    } catch (err) {
      broadcastLog(`❌ print_qr ${code} — ${err.message}`);
      wsConnection.emit('print_ack', { code, status: 'error', error: err.message, ts: Date.now() });
    }
  });

  // ── 원격 테스트 인쇄 ─────────────────────────────────────────────────────
  // 관리 페이지 "Imprimir prueba" → POST /print/agents/:id/test → print_test emit.
  // 기존 로컬 printTest() 파이프라인 재사용 후 print_ack{testId} 로 결과 회신.
  wsConnection.on('print_test', async (payload) => {
    const testId = payload?.testId;
    const start = Date.now();

    broadcastLog('🖨 print_test — prueba remota solicitada desde el panel...');

    try {
      const result = await printTest();

      wsConnection.emit('print_ack', {
        testId,
        status: result?.success ? 'ok' : 'error',
        error: result?.success ? undefined : result?.error,
        elapsedMs: Date.now() - start,
        ts: Date.now(),
      });
    } catch (err) {
      // printTest 는 자체 try/catch 가 있지만 안전망으로 한 번 더 감싼다
      wsConnection.emit('print_ack', {
        testId,
        status: 'error',
        error: err.message,
        ts: Date.now(),
      });
    }
  });

  // ── 임시(견적) 티켓 출력 ─────────────────────────────────────────────────
  // POS 'Imprimir Temp' 버튼 → 백엔드 POST /print/temp → branch:{id} 룸으로 emit
  // 판매번호/Forma de Pago 없는 견적용 티켓. fire-and-forget (ack 불필요).
  wsConnection.on('print_temp', async (payload) => {
    // ─── DEBUG(11-08): UI 로그에도 수신 사실을 즉시 노출 ──────────────────────
    // print_temp 가 agent 에 실제 도달했는지 한눈에 확인용 (콘솔 + 메인창 로그).
    broadcastLog(`📥 print_temp recibido (items=${Array.isArray(payload?.items) ? payload.items.length : '?'}, branch=${payload?.branchId ?? '?'})`);

    // ─── DEBUG(11-06) ───────────────────────────────────────────────────────
    console.log('[print_temp] ← payload received', {
      hasPayload: !!payload,
      keys:       payload ? Object.keys(payload) : null,
      itemsCount: Array.isArray(payload?.items) ? payload.items.length : 'not-array',
      branchId:   payload?.branchId,
      totals:     payload?.totals,
    });
    // full payload 덤프는 dev 전용 — 운영에서 판매내역 콘솔 노출/성능 저하 방지
    if (IS_DEV) {
      console.log('[print_temp] full payload:', JSON.stringify(payload, null, 2));
    }

    const printerCfg = getActivePrinterCfg();

    console.log('[print_temp] printerCfg:', printerCfg);
    const start = Date.now();

    broadcastLog('🖨 print_temp — imprimiendo presupuesto...');

    if (!printerCfg) {
      const msg = 'printer no configurado (setup wizard 미완료)';

      console.error('[print_temp] ✗', msg);
      broadcastLog(`❌ print_temp — ${msg}`);

      return;
    }

    // ★ 프린터가 있다고 확인한 뒤에 작업을 소비한다 — 못 찍은 것을 «찍음» 으로
    //   기록하면 설정을 고치고 재전송해도 영영 안 나온다.
    if (!claimPrintJob('print_temp', payload)) return;

    try {
      console.log('[print_temp] → formatTempTicketHtml()');
      const html = formatTempTicketHtml(payload);

      console.log('[print_temp] html length =', html?.length);

      console.log('[print_temp] → renderHtmlToPng()');
      const png = await renderHtmlToPng(html, 576, 10000, broadcastLog);

      console.log('[print_temp] png bytes =', png?.length);

      // ─── DEBUG(11-06): PNG 디스크 덤프 — dev 전용 (운영 디스크 누적 방지) ────
      // virtual-printer.js 는 GS v 0 래스터 바이트를 "[이미지 WxH]" 로만 치환하므로
      // 그래픽 모드 출력물을 눈으로 검증할 수 없음 → dev 에서만 PNG 원본을 덤프
      if (IS_DEV) {
        try {
          const dumpDir = path.join(os.tmpdir(), 'ventago-print');

          fs.mkdirSync(dumpDir, { recursive: true });
          const dumpPath = path.join(dumpDir, `temp-${Date.now()}.png`);

          fs.writeFileSync(dumpPath, png);
          console.log(`[print_temp] 💾 PNG 덤프 → ${dumpPath}`);
          broadcastLog(`💾 PNG 저장: ${dumpPath}`);
        } catch (dumpErr) {
          console.warn('[print_temp] PNG 덤프 실패:', dumpErr.message);
        }
      }

      console.log('[print_temp] → printImage()');
      await printImage(png, printerCfg, broadcastLog);
      const elapsed = Date.now() - start;

      console.log(`[print_temp] ✓ done in ${elapsed}ms`);
      broadcastLog(`✅ print_temp — OK (${elapsed}ms)`);
    } catch (err) {
      console.error('[print_temp] ✗ pipeline threw', {
        message: err?.message,
        stack:   err?.stack,
        name:    err?.name,
      });
      broadcastLog(`❌ print_temp — ${err.message}`);
    }
  });
}

// ★ **한 인쇄 작업은 한 번만 인쇄된다** — 마지막 관문.
//
// 중복 배달은 여러 층에서 생긴다: 같은 POST 두 번, 클라우드와 엣지가 겹치는
// failover 순간, 소켓 재접속, 지점 브로드캐스트, 사용자의 더블클릭. 층마다 막아도
// 새 층이 생기면 다시 뚫린다. 여기서 「이미 찍은 작업」을 거절하면 어느 경로로 두 번
// 오든 종이는 한 장이다.
//
// jobId 가 없는 이벤트는 통과시킨다 — 구버전 서버/엣지와 섞여 돌기 때문이다.
function claimPrintJob(event, payload) {
  const jobId = payload?.printJobId;

  if (printDedup.claimJob(jobId)) return true;

  console.warn(`[${event}] DUPLICADO ignorado — printJobId=${jobId} ya impreso`);
  broadcastLog(`🚫 ${event} duplicado ignorado (job ${String(jobId).slice(-8)})`);

  return false;
}

// ─── 출력 로그 브로드캐스트 (메인창 + 콘솔) ──────────────────────────────────
// renderer는 { ts, ok, message } 객체 형식을 기대 — 형식 일치 필수
function broadcastLog(msg) {
  const ts   = new Date().toLocaleTimeString('es-AR');
  const line = `${ts}  ${msg}`;
  // 메시지 첫 글자로 성공/실패 판단 (✅ ⚠️ ❌ ℹ️ 🖨)
  const ok   = !/^(❌|⚠️)/.test(String(msg).trim());

  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send('print-log', { ts, ok, message: String(msg) });
  }
  console.log(line);
}

// ─── 활성 프로파일의 프린터 설정 반환 헬퍼 ──────────────────────────────────
'use strict';

// **한 인쇄 작업은 한 번만 인쇄된다.** 이 파일이 그 불변식을 지킨다.
//
// 왜 여기인가: 중복은 여러 층에서 생긴다 — 같은 POST 두 번, 클라우드와 엣지가
// 겹치는 failover 순간, 소켓 재접속, 지점 브로드캐스트, 사용자의 더블클릭.
// 각 층을 하나씩 막아도 **다음 층이 새로 생기면 다시 뚫린다.** 마지막 관문인
// 에이전트가 「이 작업은 이미 찍었다」를 알면, 어느 경로로 두 번 오든 종이는 한 장이다.
//
// ★ 기록은 **인쇄 전에** 한다(at-most-once). 인쇄 도중 죽으면 그 작업은 안 나온
//   채로 끝난다 — 사용자가 요구한 것이 그 방향이다: 「한 장이 빠지는 것」보다
//   「두 장이 나가는 것」이 나쁘다. 빠진 것은 사람이 재인쇄할 수 있다.
//
// ★ jobId 가 **없는** 이벤트는 막지 않는다. 구버전 서버·엣지와 섞여 돌기 때문이다
//   (그 경우는 종전과 똑같이 동작한다 — 이 파일이 회귀를 만들지 않는다).

// ★ 상한과 만료를 넉넉히 잡는 이유: 여기서 잊는 순간 **그 작업은 다시 인쇄된다.**
//   하루 1,000건을 넘는 지점이면 24h·1000건으로는 같은 날 안에 밀려난다.
//   30일 · 50,000건이면 사람이 재전송을 시도할 수 있는 어떤 창보다 길다.
//   (한 항목이 문자열 40자 + 숫자 → 50,000건이라도 수 MB 수준이다.)
const MAX_ENTRIES = 50000;
const TTL_MS = 30 * 24 * 60 * 60 * 1000;

// jobId → 처리 시각(ms)
const seen = new Map();

let persist = null; // { get(key), set(key, value) } — electron-store 등

function prune(now) {
  for (const [id, ts] of seen) {
    if (now - ts > TTL_MS) seen.delete(id);
  }

  // TTL 로도 안 줄면 오래된 것부터 버린다 (Map 은 삽입 순서를 지킨다)
  while (seen.size > MAX_ENTRIES) {
    const oldest = seen.keys().next().value;

    if (oldest === undefined) break;
    seen.delete(oldest);
  }
}

// 디스크 저장이 실패한 사실을 **알린다**. 조용히 넘어가면 재기동 뒤 그 작업이
// 다시 인쇄되는데, 아무도 이유를 모른다.
let onPersistError = null;

function save() {
  if (!persist) return;

  try {
    persist.set('printJobsSeen', Array.from(seen.entries()));
  } catch (err) {
    // ★ 인쇄 자체는 막지 않는다 — 지금 이 장은 나가야 한다. 다만 「재기동을 넘어선
    //   보장이 지금 깨져 있다」를 남긴다.
    if (typeof onPersistError === 'function') {
      try { onPersistError(err); } catch (_e) { /* 알림 실패는 무시 */ }
    } else {
      console.error('[print-dedup] 원장 저장 실패 — 재기동 시 중복 인쇄 가능:', err?.message);
    }
  }
}

/**
 * 재기동 후에도 기억하게 한다. 에이전트가 재시작하는 사이에 같은 작업이 다시
 * 배달될 수 있다(서버 재전송·소켓 재연결). 메모리만 쓰면 그때 두 장이 나온다.
 */
function attachStore(store, onError) {
  persist = store;
  onPersistError = typeof onError === 'function' ? onError : null;

  try {
    const saved = store.get('printJobsSeen');

    if (Array.isArray(saved)) {
      const now = Date.now();

      for (const [id, ts] of saved) {
        if (typeof id === 'string' && typeof ts === 'number' && now - ts <= TTL_MS) {
          seen.set(id, ts);
        }
      }
    }
  } catch (_e) { /* 손상된 저장값은 무시 — 빈 원장으로 시작 */ }
}

/**
 * 이 작업을 지금 인쇄해도 되는가. **부작용이 있다** — true 를 돌려주는 순간
 * 그 jobId 는 「처리됨」으로 기록된다. 호출부는 곧바로 인쇄해야 한다.
 *
 * @param {*} jobId 서버/엣지가 실은 작업 식별자. 없으면 항상 true(구버전 호환).
 * @returns {boolean} 인쇄해야 하면 true, 이미 찍은 작업이면 false
 */
function claimJob(jobId) {
  if (!jobId || typeof jobId !== 'string') return true;

  const now = Date.now();

  prune(now);

  if (seen.has(jobId)) return false;

  seen.set(jobId, now);
  save();

  return true;
}

/** 시험용 — 원장을 비운다. */
function _reset() {
  seen.clear();
  persist = null;
  onPersistError = null;
}

module.exports = { claimJob, attachStore, _reset, MAX_ENTRIES, TTL_MS };
/**
 * VentaGO 프린트 에이전트
 * WebSocket으로 백엔드에서 print_invoice 이벤트를 수신하고
 * ESC/POS로 열감지 프린터에 출력
 */
const { io } = require('socket.io-client');
const config = require('../config.json');
const { formatInvoice, formatTempTicketHtml } = require('./formatter');
const { printReceipt, printImage, testConnection } = require('./printer');
const { renderHtmlToPng } = require('./renderer-engine');

// WebSocket 연결
// 69-01 handshake 인증 — auth.token 으로 apiKey 를 실어 유예(10초) 없이 즉시 인증된다.
// register_api_key emit 은 구버전 서버(핸드셰이크 인증 미도입) 호환을 위해 그대로 유지한다.
const socket = io(`${config.apiUrl}/realtime`, {
  reconnection: true,
  reconnectionDelay: 3000,
  reconnectionAttempts: Infinity,
  auth: { token: config.apiKey },
});

// 연결 성공
socket.on('connect', () => {
  console.log(`✅ WebSocket 연결 성공 (id: ${socket.id})`);
  // apiKey로 지점 등록 (레거시 유예 경로 — 이중 안전)
  socket.emit('register_api_key', { apiKey: config.apiKey });
  // apiKey 전체를 로그에 남기지 않도록 마스킹
  console.log(`🔑 API Key 등록: ${String(config.apiKey).slice(0, 8)}…`);
});

// handshake 인증 실패 통보 — 무한 재연결 루프에서 원인 불명 상태가 되는 것을 막는다
socket.on('auth_error', (data) => {
  console.error(`❌ 인증 실패: ${data?.message || '알 수 없는 오류'}`);
});

// 환영 메시지
socket.on('welcome', (data) => {
  console.log(`👋 ${data.message}`);
});

// 영수증 출력 이벤트 수신
socket.on('print_invoice', async (invoiceData) => {
  const ticketNum = invoiceData?.invoice?.number || 'desconocido';
  console.log(`🖨️  영수증 출력 요청 수신: ${ticketNum}`);

  try {
    // JSON → ESC/POS 포맷 변환
    const formatted = formatInvoice(invoiceData, config.printer.width);
    // 프린터에 출력
    await printReceipt(formatted, config.printer);
    console.log(`✅ 출력 완료: ${ticketNum}`);
    // 성공 확인 전송
    socket.emit('print_confirmation', {
      success: true,
      invoiceNumber: ticketNum,
      printedAt: new Date().toISOString(),
    });
  } catch (error) {
    console.error(`❌ 출력 실패: ${ticketNum}`, error.message);
    // 실패 확인 전송
    socket.emit('print_confirmation', {
      success: false,
      invoiceNumber: ticketNum,
      error: error.message,
    });
  }
});

// Phase 39: 식당 comanda(주방 전표) + resumen(cuenta/영수증) 출력
// backend print.service.emitPrintTemp(branchId, data) 가 보내는 print_temp 수신
// formatTempTicketHtml → renderHtmlToPng(576px) → printImage 파이프라인 (print-pipeline.js 동일 흐름)
// fire-and-forget: backend 는 응답을 기다리지 않으므로 에러는 console 로만 남긴다 (T-39-06 mitigation)
socket.on('print_temp', async (tempData) => {
  console.log(`🍽️  식당 임시전표 출력 요청 수신 (mesa: ${tempData?.tableName || '?'})`);

  try {
    // comanda/resumen HTML 생성 (items/variants/totals 렌더)
    const html = formatTempTicketHtml(tempData);

    // HTML → PNG (80mm @ 203dpi = 576px), Phase 38 print_qr 와 동일 파이프라인
    const pngBuffer = await renderHtmlToPng(html, 576);

    // PNG → 감열 프린터 출력 (dev 시 ~/Desktop/print-debug-*.png 저장)
    await printImage(pngBuffer, config.printer);

    console.log('✅ 식당 임시전표 출력 완료');
  } catch (error) {
    console.error('❌ 식당 임시전표 출력 실패:', error.message);
  }
});

// 연결 끊김
socket.on('disconnect', (reason) => {
  console.log(`🔴 WebSocket 연결 끊김: ${reason}`);
});

// 재연결 시도
socket.on('reconnect_attempt', (attempt) => {
  console.log(`🔄 재연결 시도 #${attempt}...`);
});

// 에러 처리
socket.on('connect_error', (error) => {
  console.error(`❌ 연결 오류: ${error.message}`);
});

// 시작 시 프린터 연결 테스트
(async () => {
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('  VentaGO 프린트 에이전트 v1.0');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log(`📡 서버: ${config.apiUrl}`);
  console.log(`🖨️  프린터: ${config.printer.type} (${config.printer.type === 'network' ? config.printer.host + ':' + config.printer.port : 'USB'})`);
  console.log('');

  try {
    await testConnection(config.printer);
    console.log('✅ 프린터 연결 테스트 성공');
  } catch (error) {
    console.warn(`⚠️  프린터 연결 테스트 실패: ${error.message}`);
// Copias del ticket de venta (2026-10-07) — sólo el automático de la venta; nunca 2×N.
// 실행: node print-agent/test/ticket-copias.smoke.js
const assert = require('assert');
const path = require('path');
const { copiasDelTicket, normalizarCopias } = require('../src/ticket-copias');

// ── ① qué trabajos llevan copias ──
const venta = { printJobId: 'sale-invoice:42' };
assert.strictEqual(copiasDelTicket(venta, 3), 3, 'ticket automático de la venta: lo configurado');
assert.strictEqual(copiasDelTicket(venta, 2), 2);
assert.strictEqual(copiasDelTicket({ printJobId: 'sale-reprint:42:abc' }, 3), 1, 'reimpresión: 1');
assert.strictEqual(copiasDelTicket({ printJobId: 'sale-invoice:42', factura: {} }, 3), 1, 'factura AFIP: 1');
assert.strictEqual(copiasDelTicket({}, 3), 1, 'sin printJobId (servidor viejo): 1');
assert.strictEqual(copiasDelTicket(null, 3), 1);

// ── ② lo guardado raro nunca multiplica ──
for (const raro of [undefined, null, 0, -1, 4, 99, 1.5, '2x', NaN, {}]) {
  assert.strictEqual(normalizarCopias(raro), 1, `copias(${String(raro)}) = 1`);
}
assert.strictEqual(normalizarCopias('2'), 2, 'el select guarda número; texto numérico también sirve');

// ── ③ la tubería: se dibuja una vez y se manda N veces ──
const dir = path.join(__dirname, '..', 'src');
let dibujos = 0;
let envios = 0;
require.cache[require.resolve(path.join(dir, 'renderer-engine'))] = {
  exports: { renderHtmlToPng: async () => { dibujos += 1; return Buffer.from('png'); } },
};
require.cache[require.resolve(path.join(dir, 'printer'))] = {
  exports: { printImage: async () => { envios += 1; } },
};
require.cache[require.resolve(path.join(dir, 'formatter'))] = {
  exports: { formatInvoiceHtml: () => '<html></html>' },
};
const { printTicket } = require('../src/print-pipeline');
const cfg = { type: 'network', host: 'x', port: 9100 };

(async () => {
  await printTicket({}, cfg, () => {}, { copias: 3 });
  assert.deepStrictEqual([dibujos, envios], [1, 3], '3 copias = 1 dibujo, 3 envíos');

  dibujos = 0; envios = 0;
  await printTicket({}, cfg, () => {});
  assert.deepStrictEqual([dibujos, envios], [1, 1], 'sin opción: 1 (como antes)');

  dibujos = 0; envios = 0;
  await printTicket({}, cfg, () => {}, { copias: 0 });
  assert.deepStrictEqual([dibujos, envios], [1, 1], 'copias inválidas: 1');

  console.log('ticket-copias.smoke OK');
})().catch((e) => { console.error(e); process.exit(1); });
print-agent/main.js:9:const { printTicket: printTicketSinContar } = require('./src/print-pipeline');
print-agent/main.js:25:const printTicket = actividadImpresion.envolver(printTicketSinContar);
print-agent/main.js:123:// ★ edge failover 핸들. **반드시 하나만 살아 있어야 한다.**
print-agent/main.js:129:// "끊긴 상태"로 보고 edge 에 접속한 뒤 **다시는 끊지 않는다**(disconnectEdge 는
print-agent/main.js:132:let edgeFailoverHandle = null;
print-agent/main.js:133:let connectionStatus = 'disconnected'; // 'connected' | 'disconnected' | 'reconnecting' | 'displaced'
print-agent/main.js:176:    // 수동 트리거(ws:reconnect, setup:complete, profile:switch)는 지연 없이 즉시 연결.
print-agent/main.js:243:    reconnecting: '🟡 Reconectando...',
print-agent/main.js:539:ipcMain.handle('ws:reconnect', () => {
print-agent/main.js:757:        reconnection: false,
print-agent/main.js:835:  //   옛 failover 의 유예 타이머를 켜서, 정리한 직후에 edge 로 붙어 버린다.
print-agent/main.js:836:  if (edgeFailoverHandle) {
print-agent/main.js:837:    try { edgeFailoverHandle.stop(); } catch (_e) { /* ignore */ }
print-agent/main.js:838:    edgeFailoverHandle = null;
print-agent/main.js:849:  setConnectionStatus('reconnecting');
print-agent/main.js:925:    reconnection:          true,
print-agent/main.js:926:    reconnectionAttempts:  Infinity,  // 무한 재시도 (백엔드 부팅 대기)
print-agent/main.js:927:    reconnectionDelay:     2000,
print-agent/main.js:931:    reconnectionDelayMax:  30000,
print-agent/main.js:939:    //   (구버전 주석의 "upgrade 실패 시 무한 reconnecting" 우려는 reconnection
print-agent/main.js:945:  // ─── Phase 58 Wave B2 (TASK-B0): edge failover ─────────────────────────────
print-agent/main.js:946:  // 클라우드 소켓이 끊기면 지점 edge-agent(LAN)로 2차 접속해 오프라인 인쇄 유지.
print-agent/main.js:947:  // 기존 print_temp/print_barcode/print_qr 핸들러를 listeners() 로 재사용 (무리팩터).
print-agent/main.js:948:  // edgeUrl 미설정 시 localhost:5010 기본 — 설정창에서 store.set('edgeUrl') 로 변경 가능.
print-agent/main.js:950:    const { attachEdgeFailover } = require('./src/edge-failover');
print-agent/main.js:951:    const edgeUrl = store.get('edgeUrl') || 'http://localhost:5010';
print-agent/main.js:953:    edgeFailoverHandle = attachEdgeFailover(wsConnection, {
print-agent/main.js:954:      edgeUrl,
print-agent/main.js:960:    console.log('[edge-failover] attach 실패 (본 연결엔 영향 없음):', efErr?.message);
print-agent/main.js:968:  wsConnection.io.on('reconnect_attempt', (n) => {
print-agent/main.js:969:    console.log(`[socket.io.io] reconnect_attempt #${n}`);
print-agent/main.js:1001:    // 여기 apiKey 가 의도한 지점의 것인지가 print_temp 수신 여부를 결정한다.
print-agent/main.js:1035:  // 방어적으로 reconnection 을 끄고 displaced 플래그를 세워 상태/사유를 고정한다.
print-agent/main.js:1039:      wsConnection.io.opts.reconnection = false;
print-agent/main.js:1089:    setConnectionStatus('reconnecting');
print-agent/main.js:1318:  wsConnection.on('print_temp', async (payload) => {
print-agent/main.js:1320:    // print_temp 가 agent 에 실제 도달했는지 한눈에 확인용 (콘솔 + 메인창 로그).
print-agent/main.js:1321:    broadcastLog(`📥 print_temp recibido (items=${Array.isArray(payload?.items) ? payload.items.length : '?'}, branch=${payload?.branchId ?? '?'})`);
print-agent/main.js:1324:    console.log('[print_temp] ← payload received', {
print-agent/main.js:1333:      console.log('[print_temp] full payload:', JSON.stringify(payload, null, 2));
print-agent/main.js:1338:    console.log('[print_temp] printerCfg:', printerCfg);
print-agent/main.js:1341:    broadcastLog('🖨 print_temp — imprimiendo presupuesto...');
print-agent/main.js:1346:      console.error('[print_temp] ✗', msg);
print-agent/main.js:1347:      broadcastLog(`❌ print_temp — ${msg}`);
print-agent/main.js:1354:    if (!claimPrintJob('print_temp', payload)) return;
print-agent/main.js:1357:      console.log('[print_temp] → formatTempTicketHtml()');
print-agent/main.js:1360:      console.log('[print_temp] html length =', html?.length);
print-agent/main.js:1362:      console.log('[print_temp] → renderHtmlToPng()');
print-agent/main.js:1365:      console.log('[print_temp] png bytes =', png?.length);
print-agent/main.js:1378:          console.log(`[print_temp] 💾 PNG 덤프 → ${dumpPath}`);
print-agent/main.js:1381:          console.warn('[print_temp] PNG 덤프 실패:', dumpErr.message);
print-agent/main.js:1385:      console.log('[print_temp] → printImage()');
print-agent/main.js:1389:      console.log(`[print_temp] ✓ done in ${elapsed}ms`);
print-agent/main.js:1390:      broadcastLog(`✅ print_temp — OK (${elapsed}ms)`);
print-agent/main.js:1392:      console.error('[print_temp] ✗ pipeline threw', {
print-agent/main.js:1397:      broadcastLog(`❌ print_temp — ${err.message}`);
print-agent/src/serial-queue.js:5:// ★ 종전 renderer-engine 의 큐는 `queue = queue.then(fn)` 이었다. fn 이 한 번 reject
print-agent/src/serial-queue.js:6://   하면 queue 자체가 rejected 로 남고, 이후 모든 `.then(fn)` 은 fn 을 **부르지도 않고**
print-agent/src/printer.js:9:const { createSerialQueue } = require('./serial-queue');
print-agent/src/printer.js:351://   (직렬화 전보다 나빠지지 않게 — serial-queue.js 참고).
print-agent/src/print-pipeline.js:25:async function printTicket(data, printerCfg, log = () => {}, { copias = 1 } = {}) {
print-agent/renderer/index.html:218:      else if (s === 'reconnecting') dot.classList.add('warn');
print-agent/renderer/index.html:263:        setStatus('reconnecting');
print-agent/renderer/index.html:264:        await window.electronAPI.reconnectWs();
print-agent/renderer/index.html:404:      setStatus('reconnecting');
print-agent/renderer/index.html:462:          setStatus('reconnecting');
print-agent/renderer/index.html:875:        setStatus('reconnecting');
print-agent/renderer/index.html:876:        await window.electronAPI.reconnectWs();
print-agent/src/index.js:16:  reconnection: true,
print-agent/src/index.js:17:  reconnectionDelay: 3000,
print-agent/src/index.js:18:  reconnectionAttempts: Infinity,
print-agent/src/index.js:70:// backend print.service.emitPrintTemp(branchId, data) 가 보내는 print_temp 수신
print-agent/src/index.js:73:socket.on('print_temp', async (tempData) => {
print-agent/src/index.js:98:socket.on('reconnect_attempt', (attempt) => {
print-agent/src/renderer-engine.js:18:const { createSerialQueue } = require('./serial-queue');
print-agent/src/renderer-engine.js:22:// 직렬 큐 — 한 번의 실패(타임아웃)가 이후 렌더를 전부 실패시키지 않는다(serial-queue.js).
print-agent/src/formatter.js:377:  const raw = typeof data?.offlineNumber === 'string' ? data.offlineNumber.trim() : '';
print-agent/src/formatter.js:390:  const offline = readOfflineNumber(data);
print-agent/src/formatter.js:786:  ${offline ? `
print-agent/src/formatter.js:789:    <span class="meta-val">${offline.full}</span>
print-agent/src/formatter.js:910:  const offline = readOfflineNumber(data);
print-agent/src/formatter.js:912:  const offlineCapture = offline && !hasSaleNumber;
print-agent/src/formatter.js:1038:  .offline-ref {
print-agent/src/formatter.js:1044:  .offline-ref-label { font-size: 16px; letter-spacing: 2px; }
print-agent/src/formatter.js:1045:  .offline-ref-short {
print-agent/src/formatter.js:1053:  .offline-ref-full { font-size: 15px; letter-spacing: 0.5px; word-break: break-all; }
print-agent/src/formatter.js:1179:${offlineCapture
print-agent/src/formatter.js:1201:${offlineCapture ? `<!-- [A-2] 손님이 전화로 불러 줄 참조 — 큰 글씨는 뒤 6자.
print-agent/src/formatter.js:1203:<div class="offline-ref">
print-agent/src/formatter.js:1204:  <div class="offline-ref-label">REFERENCIA DE SU COMPRA</div>
print-agent/src/formatter.js:1205:  <div class="offline-ref-short">${offline.ref}</div>
print-agent/src/formatter.js:1206:  <div class="offline-ref-full">${offline.full}</div>
print-agent/src/formatter.js:1211:  ${offlineCapture
print-agent/src/formatter.js:1227:  ${offline && !offlineCapture ? `<!-- [A-2] 동기화된 오프라인 판매의 재인쇄 — 손님 종이의 참조와 잇는다 -->
print-agent/src/formatter.js:1230:    <span class="meta-val">${offline.full}</span>
print-agent/src/formatter.js:1280:  ${offlineCapture
print-agent/src/formatter.js:1284:       Conserve la referencia ${offline.ref} para cualquier consulta.</div>`
print-agent/src/edge-failover.js:1:// Phase 58 Wave B2 (TASK-B0) — print-agent edge failover
print-agent/src/edge-failover.js:2:// 클라우드 /print-agent 소켓이 끊기면 지점 edge-agent(LAN)로 2차 접속해
print-agent/src/edge-failover.js:5:// 무리팩터 설계: main.js 의 기존 print_temp/print_barcode/print_qr 핸들러(클로저)를
print-agent/src/edge-failover.js:7:// 클라우드가 복구되면 edge 소켓은 즉시 종료 (단일 소스 원칙).
print-agent/src/edge-failover.js:11:// 클라우드 단절 후 edge 접속까지 유예 (순간 끊김에 과민반응 방지)
print-agent/src/edge-failover.js:14:// edge 로 위임(재디스패치)할 이벤트 — 출력 계열만
print-agent/src/edge-failover.js:15:const RELAY_EVENTS = ['print_temp', 'print_barcode', 'print_qr', 'print_test', 'force_disconnect'];
print-agent/src/edge-failover.js:18:  const { edgeUrl, apiKey, log } = opts;
print-agent/src/edge-failover.js:21:  if (!edgeUrl || !apiKey) {
print-agent/src/edge-failover.js:22:    console.log('[edge-failover] edgeUrl/apiKey 없음 — failover 비활성');
print-agent/src/edge-failover.js:27:  const nsUrl = `${edgeUrl.replace(/\/$/, '')}/print-agent`;
print-agent/src/edge-failover.js:28:  let edgeSocket = null;
print-agent/src/edge-failover.js:33:    if (stopped || edgeSocket) return;
print-agent/src/edge-failover.js:36:    console.log(`[edge-failover] 클라우드 단절 지속 → edge 접속 시도: ${nsUrl}`);
print-agent/src/edge-failover.js:39:    edgeSocket = io(nsUrl, {
print-agent/src/edge-failover.js:41:      reconnection: true,
print-agent/src/edge-failover.js:42:      reconnectionDelay: 3000,
print-agent/src/edge-failover.js:43:      reconnectionDelayMax: 10000,
print-agent/src/edge-failover.js:47:      // edge-agent 이고 단일 프로세스라 sticky 문제가 없다. 열악한 LAN 환경에서
print-agent/src/edge-failover.js:52:    edgeSocket.on('connect', () => {
print-agent/src/edge-failover.js:53:      console.log(`[edge-failover] ✅ edge 연결됨 sid=${edgeSocket.id}`);
print-agent/src/edge-failover.js:55:      edgeSocket.emit('agent_online', { source: 'edge-failover' });
print-agent/src/edge-failover.js:58:    edgeSocket.on('agent_info', (info) => {
print-agent/src/edge-failover.js:59:      console.log('[edge-failover] agent_info (edge):', JSON.stringify(info));
print-agent/src/edge-failover.js:62:    edgeSocket.on('auth_error', (err) => {
print-agent/src/edge-failover.js:63:      console.log('[edge-failover] ❌ edge 인증 실패:', err?.message);
print-agent/src/edge-failover.js:64:      say(`❌ edge auth: ${err?.message} (edge 의 branch_agents 미러 동기화 확인)`);
print-agent/src/edge-failover.js:67:    edgeSocket.on('connect_error', (err) => {
print-agent/src/edge-failover.js:68:      console.log('[edge-failover] edge connect_error:', err?.message);
print-agent/src/edge-failover.js:74:      edgeSocket.on(ev, (payload, ack) => {
print-agent/src/edge-failover.js:76:        console.log(`[edge-failover] 📥 ${ev} via EDGE → ${handlers.length} handler(s) 재디스패치`);
print-agent/src/edge-failover.js:80:          console.log(`[edge-failover] ⚠ ${ev} 핸들러 없음 — main.js 등록 순서 확인`);
print-agent/src/edge-failover.js:89:              r.catch((err) => console.log(`[edge-failover] ${ev} handler async error:`, err?.message));
print-agent/src/edge-failover.js:92:            console.log(`[edge-failover] ${ev} handler error:`, err?.message);
print-agent/src/edge-failover.js:98:    // print_ack 를 edge 로도 전달할 수 있도록 프록시 emit 훅 제공:
print-agent/src/edge-failover.js:102:    if (!cloudSocket.__edgeEmitPatched) {
print-agent/src/edge-failover.js:103:      cloudSocket.__edgeEmitPatched = true;
print-agent/src/edge-failover.js:105:        if (event === 'print_ack' && !cloudSocket.connected && edgeSocket?.connected) {
print-agent/src/edge-failover.js:106:          console.log('[edge-failover] print_ack → edge 로 미러링');
print-agent/src/edge-failover.js:107:          edgeSocket.emit(event, ...args);
print-agent/src/edge-failover.js:120:    if (edgeSocket) {
print-agent/src/edge-failover.js:121:      console.log(`[edge-failover] edge 연결 종료 (${reason})`);
print-agent/src/edge-failover.js:124:        edgeSocket.disconnect();
print-agent/src/edge-failover.js:126:      edgeSocket = null;
print-agent/src/edge-failover.js:132:    console.log(`[edge-failover] 클라우드 disconnect (${reason}) — ${FAILOVER_GRACE_MS}ms 유예 후 edge 시도`);
print-agent/src/edge-failover.js:142:    disconnectEdge('cloud reconnected');
print-agent/src/edge-failover.js:145:  console.log(`[edge-failover] armado — edge=${nsUrl} grace=${FAILOVER_GRACE_MS}ms`);

hook: PostToolUse
hook: PostToolUse
hook: PostToolUse Failed
hook: PostToolUse Completed
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
exec
/bin/zsh -lc "cat print-agent/src/print-dedup.js; sed -n '1,180p' print-agent/src/edge-failover.js; sed -n '1,70p' print-agent/main.js; rg -n \"emit\\(['\\\"]print_invoice|print_invoice['\\\"]|sale-invoice:|sale-reprint:\" api-ventago ventago-app edge-agent print-agent --glob '"'!**/node_modules/**'"' --glob '"'!**/dist/**'"' 2>/dev/null" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 168ms:
api-ventago/src/app/print/print-jobs.itest.ts:101:    const id = `itest-sale-invoice:${tag}:1`;
api-ventago/src/app/print/print-jobs.itest.ts:112:    expect(sent[0][0]).toBe('print_invoice');
api-ventago/src/app/print/print-jobs.itest.ts:125:    const id = `itest-sale-invoice:${tag}:2`;
api-ventago/src/app/print/print-jobs.itest.ts:135:      await enqueue(`itest-sale-invoice:${tag}:3`, { agentId: otraAgentId }),
api-ventago/src/app/print/print-jobs.itest.ts:139:      await enqueue(`itest-sale-invoice:${tag}:3b`, {
api-ventago/src/app/print/print-jobs.itest.ts:147:    const id = `itest-sale-invoice:${tag}:4`;
api-ventago/src/app/print/print-jobs.itest.ts:163:    const id = `itest-sale-invoice:${tag}:old`;
api-ventago/src/app/print/print-jobs.itest.ts:180:      await enqueue(`itest-sale-invoice:${tag}:c${i}`);
api-ventago/src/app/print/print-jobs.itest.ts:189:      [0, 1, 2, 3, 4].map((i) => `itest-sale-invoice:${tag}:c${i}`).sort(),
api-ventago/src/app/restaurant-delivery/restaurant-delivery.service.ts:55://     통과하므로 배달만 중복 인쇄 방어에서 빠져 있었다(판매 경로는 `sale-invoice:<id>`
api-ventago/dist-lt-old/app/print/print.service.js:96:                this.gateway.server?.to(targetSocketId).emit('print_invoice', data);
api-ventago/dist-lt-old/app/print/print.service.js:101:                    .emit('print_invoice', data);
api-ventago/dist-lt-old/app/print/print.service.js:856:       SELECT $1, $2, a.id, $4, 'print_invoice', $5::jsonb,
api-ventago/dist-pl/app/sales/sales-create.service.js:1650:                    jobId: `sale-invoice:${saleId}`,
api-ventago/dist-pl/app/sales/sales-create.service.js:1653:                        printJobId: `sale-invoice:${saleId}`,
api-ventago/dist-pl/app/sales/sales-create.service.js:1676:        this.printService.emitPrintInvoice(branchId, (0, ticket_footer_1.applyTicketFooter)({ ...invoiceData, printJobId: `sale-invoice:${saleId}` }, target.footerLines), target.socketId);
api-ventago/dist-pl/app/sales/sales-create.service.js:1704:            printJobId: `sale-reprint:${saleId}:${(0, crypto_1.randomUUID)()}`,
api-ventago/dist-pl/app/print/print.service.js:96:                this.gateway.server?.to(targetSocketId).emit('print_invoice', data);
api-ventago/dist-pl/app/print/print.service.js:101:                    .emit('print_invoice', data);
api-ventago/dist-pl/app/print/print.service.js:856:       SELECT $1, $2, a.id, $4, 'print_invoice', $5::jsonb,
api-ventago/dist-lt/app/sales/sales-create.service.js:1650:                    jobId: `sale-invoice:${saleId}`,
api-ventago/dist-lt/app/sales/sales-create.service.js:1653:                        printJobId: `sale-invoice:${saleId}`,
api-ventago/dist-lt/app/sales/sales-create.service.js:1676:        this.printService.emitPrintInvoice(branchId, (0, ticket_footer_1.applyTicketFooter)({ ...invoiceData, printJobId: `sale-invoice:${saleId}` }, target.footerLines), target.socketId);
api-ventago/dist-lt/app/sales/sales-create.service.js:1704:            printJobId: `sale-reprint:${saleId}:${(0, crypto_1.randomUUID)()}`,
api-ventago/dist-lt/app/print/print.service.js:96:                this.gateway.server?.to(targetSocketId).emit('print_invoice', data);
api-ventago/dist-lt/app/print/print.service.js:101:                    .emit('print_invoice', data);
api-ventago/dist-lt/app/print/print.service.js:856:       SELECT $1, $2, a.id, $4, 'print_invoice', $5::jsonb,

hook: PostToolUse
hook: PostToolUse
hook: PostToolUse Failed
hook: PostToolUse Completed
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
exec
/bin/zsh -lc "sed -n '330,470p' print-agent/src/printer.js; sed -n '3670,3870p' api-ventago/src/app/sales/sales-create.service.ts; sed -n '130,180p' api-ventago/src/app/print/print.service.ts; sed -n '1620,1705p' api-ventago/src/app/print/print.service.ts; rg -n \"ipcMain\\.handle\\('config:|getConfig|setConfig|contextBridge|electronAPI\" print-agent/main.js print-agent/preload.js print-agent/renderer/index.html" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
            })
            .catch((imgErr) => {
              log(`❌ [printImage] 이미지 래스터 오류: ${imgErr.message}`);
              failAfterOpen(new Error(`이미지 래스터 오류: ${imgErr.message}`));
            });
        } catch (printError) {
          log(`❌ [printImage] 출력 중 오류: ${printError.message}`);
          failAfterOpen(new Error(`출력 중 오류: ${printError.message}`));
        }
      });
    } catch (deviceError) {
      log(`❌ [printImage] 디바이스 생성 실패: ${deviceError.message}`);
      reject(new Error(`디바이스 생성 실패: ${deviceError.message}`));
    }
  });
};

// ★ 같은 프린터에 두 작업이 **동시에** 들어가지 않게 한 줄로 세운다.
//   동시에 열면 9100 포트는 두 번째 연결을 거절하거나(USB 는 LIBUSB_ERROR_BUSY)
//   두 래스터가 섞인다 — 판매가 몰리는 순간(판매 + 자동 fiscal 출력) 실제로 겹친다.
//   슬롯 상한 45초: escpos close 콜백이 안 오면 큐가 멈추므로, 그때는 다음 작업을 보낸다
//   (직렬화 전보다 나빠지지 않게 — serial-queue.js 참고).
const printQueue = createSerialQueue({ slotTimeoutMs: 45000 });

const printImage = (pngBuffer, printerConfig, log = () => {}) =>
  printQueue.run(() => printImageNow(pngBuffer, printerConfig, log));

module.exports = { printReceipt, printImage, testConnection };
      const msg = err instanceof Error ? err.message : String(err);

      console.warn(
        `[resolveInvoiceTargetSocketId] 대상 해석 실패 (terminal ${terminalId ?? '-'}): ${msg}`,
      );

      // ★ 실패하면 **보내지 않는다.** 종전에는 undefined 를 돌려줘 broadcast 로
      //   떨어졌다 — 조회가 실패했다는 이유로 종이가 여러 장 나가면 안 된다.
      return { refuse: 'resolve_failed' };
    }
  }

  private async sendToprinters(
    saleId: number,
    printerAgentId?: number | null,
  ): Promise<void> {
    const completeSale = await this.saleModel.findByPk(saleId, {
      include: this.buildPrintInvoiceInclude(),
    });
    if (!completeSale) return;
    const branchId = await this.resolveSaleBranchId(completeSale);
    if (!branchId) return;
    const invoiceData = this.buildInvoiceData(completeSale);

    // 터미널 매핑 comandera 로만 emit — 매핑 없으면 기존 지점 broadcast fallback
    const target = await this.resolveInvoiceTargetSocketId(
      completeSale.terminalId,
      branchId,
      { agentId: printerAgentId, storeId: completeSale.storeId },
    );

    // ★ [2026-09-29] 꺼져 있지만 대상이 한 대로 분명하면 **쌓아 두고** 재접속 때 보낸다.
    //   재인쇄(reprintSale)는 쌓지 않는다 — 사람이 결과(agent_offline)를 보고 다시 누르므로,
    //   쌓으면 그 사람의 두 번째 누름과 합쳐 두 장이 된다.
    if (
      'refuse' in target &&
      target.refuse === 'agent_offline' &&
      target.queueAgentId
    ) {
      try {
        const queued = await this.printService.enqueueOfflinePrintJob({
          storeId: completeSale.storeId,
          branchId,
          agentId: target.queueAgentId,
          jobId: `sale-invoice:${saleId}`,
          payload: {
            ...(invoiceData as Record<string, unknown>),
            printJobId: `sale-invoice:${saleId}`,
          },

          // 판매가 **만들어진** 시각 — sale_date 는 사람이 과거로 둘 수 있어 쓰지 않는다
          issuedAt:
            completeSale.createdAt instanceof Date
              ? completeSale.createdAt
              : new Date(),
        });

        this.logger.warn(
          `[sendToprinters] 에이전트 오프라인 — saleId=${saleId} agent=${target.queueAgentId} ` +
            (queued
              ? '대기열에 넣음(재접속 시 출력)'
              : '대기열 미적재(이미 있음/매장 불일치)'),
        );
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);

        this.logger.error(
          `[sendToprinters] 대기열 적재 실패 saleId=${saleId}: ${msg}`,
        );
      }

      return;
    }

    if ('refuse' in target) {
      this.logger.warn(
        `[sendToprinters] 출력하지 않음 saleId=${saleId} branch=${branchId} ` +
          `motivo=${target.refuse}${target.candidates ? ` candidatos=${target.candidates}` : ''} ` +
          `— 대상이 하나로 좁혀지지 않으면 보내지 않는다(중복 발행 금지).`,
      );

      return;
    }

    // ★ **판매에 묶인** 작업 id — 자동 출력은 판매당 한 장이다. 같은 판매에 대해
    //   이 경로가 두 번 돌아도(재시도·동기화 재적용) print-agent 가 두 번째를 거절한다.
    //   사람이 누르는 재인쇄는 아래에서 **매번 새 id** 를 쓴다(사본이 목적이므로).
    this.printService.emitPrintInvoice(
      branchId,
      applyTicketFooter(
        { ...invoiceData, printJobId: `sale-invoice:${saleId}` },
        target.footerLines,
      ),
      target.socketId,
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Reprint — 기존 판매를 같은 포맷으로 재인쇄.
  // sendToprinters 와 동일한 buildInvoiceData 결과 (=variant 매트릭스 포함) 를
  // 동일한 print_invoice 이벤트로 emit. 신규 판매든 reprint 든 영수증 외형 동일.
  // 호출 측 (SalesController) 가 store 격리 검증 (sale.storeId === user.storeId).
  // 반환: 인쇄 가능 여부 + 사용된 apiKey (디버깅용, 토큰은 노출 X).
  public async reprintSale(
    saleId: number,

    // [2026-09-27] 재인쇄도 고른 comandera 로 — 없으면 판매 터미널의 기본
    printerAgentId?: number | null,
  ): Promise<{
    sent: boolean;
    reason?:
      | 'sale_not_found'
      | 'sale_nullified'
      | 'no_branch'
      | 'no_api_key'
      | 'agent_offline'
      | 'ambiguous_target'
      | 'printer_not_allowed'
      | 'resolve_failed';
    candidates?: number;
  }> {
    const completeSale = await this.saleModel.findByPk(saleId, {
      include: this.buildPrintInvoiceInclude(),
    });
    if (!completeSale) return { sent: false, reason: 'sale_not_found' };

    // ★ 취소된 판매는 재출력하지 않는다 (codex P1).
    //   재출력 티켓은 정상 판매와 **똑같이 생겼다** — 취소된 뒤에 다시 뽑아 손님에게
    //   주면 그 종이는 존재하지 않는 매출의 영수증이다. Alt+T 는 12시간 전 판매를
    //   기억하므로, 「기억한 뒤 취소된」 경우가 실제로 생긴다.
    //   역분개 행(Anulación)도 막는다 — 그것은 판매가 아니라 취소 처리건이다.
    if (
      completeSale.status === SaleStatus.NULLIFIED ||
      completeSale.status === SaleStatus.NULLIFICATION ||
      completeSale.nullifiedBySaleId ||
      completeSale.nullifiedSaleId
    ) {
      return { sent: false, reason: 'sale_nullified' };
    }

    const branchId = await this.resolveSaleBranchId(completeSale);
    if (!branchId) return { sent: false, reason: 'no_branch' };

    const invoiceData = this.buildInvoiceData(completeSale);

    // 신규 판매(sendToprinters)와 **동일한** 라우팅 규칙 — 대상이 하나로 좁혀질 때만.
    const target = await this.resolveInvoiceTargetSocketId(
      completeSale.terminalId,
      branchId,
      { agentId: printerAgentId, storeId: completeSale.storeId },
    );

    if ('refuse' in target) {
      return {
        sent: false,
        reason: target.refuse as
          | 'ambiguous_target'
          | 'agent_offline'
          | 'printer_not_allowed',
        candidates: target.candidates,
      };
    }

    // ★ 재인쇄는 **매번 새 작업**이다 — 사람이 사본을 원해서 누른 것이므로
    //   중복 방지가 걸리면 안 된다. (같은 HTTP 요청이 재전송되는 경우까지 막으려면
    //   호출부가 작업 id 를 보내야 하는데, 그건 별도 항목이다.)
    this.printService.emitPrintInvoice(
      branchId,
      applyTicketFooter(
        {
          ...invoiceData,
          printJobId: `sale-reprint:${saleId}:${randomUUID()}`,
        },
        target.footerLines,
      ),
      target.socketId,
    );

    return { sent: true };
  }

  // saleId 로 store_id 만 빠르게 조회 — controller 의 store 격리 검증용.
  /**
   * [2026-09-27] 재인쇄에서 고를 수 있는 comandera — **그 판매의 터미널** 기준.
   * 재인쇄의 대상 해석(reprintSale)이 판매 터미널의 허용 목록으로 판정하므로, 화면에
   * 보여 주는 목록도 같은 출처여야 고른 것이 거절되지 않는다.
   * 터미널이 없는 판매(온라인 등)는 빈 목록 — 화면은 선택 없이 종전대로 보낸다.
   */
  public async listReprintPrinters(saleId: number, storeId: number) {
    const sale = await this.saleModel.findOne({
      where: { id: saleId, storeId },
      attributes: ['id', 'terminalId'],
    });
    if (!sale?.terminalId) return { terminalId: null, printers: [] };

    return {
      terminalId: Number(sale.terminalId),
      printers: await this.printService.listTerminalPrinters(
        Number(sale.terminalId),
        storeId,
      ),
  }

  // ── emit 메서드 (fire-and-forget) ──

  // 임시(견적) 티켓 출력 — targetSocketId 지정 시 해당 에이전트로만 전송,
  // 없으면 기존 지점 broadcast (터미널-에이전트 매핑 미설정 fallback)
  emitPrintTemp(branchId: number, data: any, targetSocketId?: string): void {
    try {
      if (targetSocketId) {
        this.gateway.server?.to(targetSocketId).emit('print_temp', data);
      } else {
        this.gateway.server?.to(`branch:${branchId}`).emit('print_temp', data);
      }
    } catch (err) {
      console.error('[PrintService] emitPrintTemp 실패:', err);
    }
  }

  // 판매 확정 시 컨트롤 티켓 출력 — targetSocketId 지정 시 해당 에이전트로만
  // 전송(터미널별 라우팅), 없으면 기존 지점 broadcast (하위 호환 fallback)
  emitPrintInvoice(branchId: number, data: any, targetSocketId?: string): void {
    try {
      if (targetSocketId) {
        this.gateway.server?.to(targetSocketId).emit('print_invoice', data);
      } else {
        this.gateway.server
          ?.to(`branch:${branchId}`)
          .emit('print_invoice', data);
      }
    } catch (err) {
      console.error('[PrintService] emitPrintInvoice 실패:', err);
    }
  }

  // AFIP fiscal 영수증 출력
  emitFiscalReceipt(branchId: number, data: any): void {
    try {
      this.gateway.server?.to(`branch:${branchId}`).emit('print_fiscal', data);
    } catch (err) {
      console.error('[PrintService] emitFiscalReceipt 실패:', err);
    }
  }

  // 바코드 라벨 출력 — 특정 에이전트 또는 지점 전체 broadcast
  emitPrintBarcode(branchId: number, data: any, agentId?: number): void {
    try {
      if (agentId) {
        // 특정 zebra 에이전트의 socketId로 직접 emit
        this.agentRepo.findByPk(agentId).then((agent) => {
          if (agent?.socketId) {
            this.gateway.server?.to(agent.socketId).emit('print_barcode', data);
  private async getSoleThermalAgentAnyState(
    branchId: number,
  ): Promise<number | null> {
    const agents = await this.agentRepo.findAll({
      where: { branchId, agentType: 'thermal' },
      attributes: ['id'],
      limit: 2,
    });

    return agents.length === 1 ? Number(agents[0].id) : null;
  }

  // ── [2026-09-29] print_jobs — 에이전트가 끊긴 사이의 판매 티켓 ──────────────────
  //
  // 로컬 부하 시험(300매장 · 에이전트 5% 재접속)에서 판매 티켓 2.94% 가 사라졌다 — 전부
  // `agent_offline` 으로 **보내지도 않은** 것. 재접속은 몇 초면 끝나는데 그 사이 판매는
  // 종이가 없다. 그래서 대상이 분명한 경우에만 쌓아 두고 에이전트가 돌아오면 보낸다.
  //
  // ★ 중복 없음: 쌓는 것은 **한 번도 emit 하지 않은** 작업뿐이고, 꺼낼 때 sent 로 바꾼 뒤에만
  //   emit 한다(한 번만 꺼내진다 — SKIP LOCKED). 에이전트 원장도 같은 printJobId 를 거절한다.
  // ★ 15분 뒤엔 보내지 않는다 — 한참 늦게 나온 영수증은 도움보다 혼란이다.
  // ★ 원시 SQL 인 이유: 모델 훅(테넌트 가드)은 요청 맥락이 없는 소켓 경로에서 판정할 수 없다.
  //   매장 경계는 INSERT 에서 에이전트→지점→매장 조인으로 건다.

  /** 대기열에 넣는다. 에이전트가 이 매장 것이 아니면 넣지 않는다. 넣었으면 true. */
  async enqueueOfflinePrintJob(opts: {
    storeId: number;
    branchId: number;
    agentId: number;
    jobId: string;
    payload: Record<string, any>;

    /**
     * 문서가 생긴 시각(판매 시각). 만료는 **이 시각 + 15분**이다 — 적재 시각이 아니다.
     * ★ [codex P1] 끝난 행은 7일 뒤 지워지므로 그 뒤엔 `ON CONFLICT(job_id)` 가 막아 주지
     *   못한다. 늦게 같은 작업이 다시 들어와도 **처음부터 만료**라 보내지지 않는다.
     */
    issuedAt: Date;
  }): Promise<boolean> {
    const rows = await this.agentRepo.sequelize!.query<{ id: number }>(
      `INSERT INTO print_jobs (store_id, branch_id, agent_id, job_id, event, payload, expires_at)
       SELECT $1, $2, a.id, $4, 'print_invoice', $5::jsonb,
              LEAST(now(), $6::timestamptz) + interval '${PRINT_JOB_TTL_MIN} minutes'
         FROM branch_agents a
         JOIN branches b ON b.id = a.branch_id AND b.store_id = $1
        WHERE a.id = $3 AND a.agent_type = 'thermal'
       ON CONFLICT (job_id) DO NOTHING
       RETURNING id`,
      {
        bind: [
          opts.storeId,
          opts.branchId,
          opts.agentId,
          opts.jobId,
          JSON.stringify(opts.payload),
          opts.issuedAt,
        ],
        type: QueryTypes.SELECT,
      },
    );

    return rows.length > 0;
  }

  /** 주어진 에이전트 중 보낼 작업이 있는 것 — 하트비트가 한 번의 조회로 거른다. */
  async agentsWithPendingPrintJobs(agentIds: number[]): Promise<number[]> {
    if (agentIds.length === 0) return [];

    const rows = await this.agentRepo.sequelize!.query<{ agent_id: number }>(
      `SELECT DISTINCT agent_id FROM print_jobs
        WHERE status = 'pending' AND agent_id = ANY($1::int[])`,
      { bind: [agentIds], type: QueryTypes.SELECT },
    );

    return rows.map((r) => Number(r.agent_id));
  }

  /**
   * 이 에이전트의 대기 작업을 꺼내 보낸다. **sent 로 커밋한 뒤에** emit 한다 —
   * 트랜잭션 안에서 소켓을 부르지 않는다(규약), 그리고 두 워커가 같은 작업을 꺼내지 않는다.
   * 반환: 보낸 건수.
   */
  async drainPrintJobs(
    agentId: number,
    emit: (event: string, payload: any) => void,
  ): Promise<number> {
print-agent/renderer/index.html:264:        await window.electronAPI.reconnectWs();
print-agent/renderer/index.html:346:      if (!el || !window.electronAPI?.probePrinter) return;
print-agent/renderer/index.html:349:        const r = await window.electronAPI.probePrinter();
print-agent/renderer/index.html:374:      const profiles      = await window.electronAPI.getProfiles();
print-agent/renderer/index.html:375:      const activeId      = await window.electronAPI.getActiveProfileId();
print-agent/renderer/index.html:405:      await window.electronAPI.switchProfile(profileId);
print-agent/renderer/index.html:407:      const profiles = await window.electronAPI.getProfiles();
print-agent/renderer/index.html:432:      const profiles = await window.electronAPI.getProfiles();
print-agent/renderer/index.html:433:      const activeId = await window.electronAPI.getActiveProfileId();
print-agent/renderer/index.html:463:          await window.electronAPI.switchProfile(id);
print-agent/renderer/index.html:473:          const profiles = await window.electronAPI.getProfiles();
print-agent/renderer/index.html:485:          await window.electronAPI.deleteProfile(id);
print-agent/renderer/index.html:519:        const printers = await window.electronAPI.listSystemPrinters();
print-agent/renderer/index.html:551:        const printers = await window.electronAPI.listUsbPrinters();
print-agent/renderer/index.html:653:      await window.electronAPI.saveProfile(profile);
print-agent/renderer/index.html:663:    console.log('[renderer] window.electronAPI =', typeof window.electronAPI);
print-agent/renderer/index.html:664:    if (typeof window.electronAPI !== 'object' || window.electronAPI === null) {
print-agent/renderer/index.html:666:      console.error('[renderer] preload missing — window.electronAPI is undefined');
print-agent/renderer/index.html:674:      const status = await window.electronAPI.getWsStatus();
print-agent/renderer/index.html:679:        const dev = await window.electronAPI.isDev?.();
print-agent/renderer/index.html:687:        const saved = await window.electronAPI.getConfig('_lastAgentInfo');
print-agent/renderer/index.html:701:      window.electronAPI.onConnectionStatus(setStatus);
print-agent/renderer/index.html:702:      window.electronAPI.onPrintLog(appendLog);
print-agent/renderer/index.html:705:      window.electronAPI.onForceDisconnect?.((payload) => {
print-agent/renderer/index.html:711:      window.electronAPI.onAgentInfo((info) => {
print-agent/renderer/index.html:731:        const opts = await window.electronAPI.getFontOptions();
print-agent/renderer/index.html:769:          await window.electronAPI.setConfig('ticketFont', fontSel.value);
print-agent/renderer/index.html:773:          await window.electronAPI.setConfig('ticketFontScale', parseFloat(sizeSel.value) || 1);
print-agent/renderer/index.html:800:          await window.electronAPI.setConfig('ticketMarginRight', Number(marginRange.value) || 0);
print-agent/renderer/index.html:810:        const guardadas = Number(await window.electronAPI.getConfig('ticketCopias'));
print-agent/renderer/index.html:813:          await window.electronAPI.setConfig('ticketCopias', Number(copiasSel.value) || 1);
print-agent/renderer/index.html:843:        try { pintarFooter(await window.electronAPI.getFooter()); }
print-agent/renderer/index.html:854:        const r = await window.electronAPI.setFooter(lineas);
print-agent/renderer/index.html:876:        await window.electronAPI.reconnectWs();
print-agent/renderer/index.html:880:        const r = await window.electronAPI.testPrint();
print-agent/renderer/index.html:889:        const r = await window.electronAPI.previewTicket();
print-agent/preload.js:3:const { contextBridge, ipcRenderer } = require('electron');
print-agent/preload.js:5:// renderer에서 window.electronAPI.xxx() 로 호출
print-agent/preload.js:6:contextBridge.exposeInMainWorld('electronAPI', {
print-agent/preload.js:8:  getConfig: (key) => ipcRenderer.invoke('store:get', key),
print-agent/preload.js:9:  setConfig: (key, value) => ipcRenderer.invoke('store:set', key, value),

hook: PostToolUse
hook: PostToolUse
hook: PostToolUse Failed
hook: PostToolUse Completed
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
exec
/bin/zsh -lc "sed -n '1,355p' print-agent/src/printer.js; sed -n '1,45p' print-agent/preload.js; rg -n \"ipcMain\\.handle\\('store:(get|set)'\" -C 4 print-agent/main.js; nl -ba print-agent/src/ticket-copias.js; nl -ba print-agent/src/print-pipeline.js | sed -n '20,70p'; nl -ba print-agent/renderer/index.html | sed -n '800,820p'" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
/**
 * 프린터 드라이버
 * USB 또는 네트워크 열감지 프린터로 ESC/POS 출력
 */
const escpos = require('escpos');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { createSerialQueue } = require('./serial-queue');

// ─── 개발 모드 감지 ─────────────────────────────────────────────────────────
// main.js 가 process.env.PRINT_AGENT_DEV='1' 을 세팅함.
// dev 일 때 printImage 는 실 프린터 대신 ~/Desktop/print-debug-*.png 로 저장.
const isDevMode = () => process.env.PRINT_AGENT_DEV === '1';

// PNG 미리보기 저장 경로 — 데스크톱 우선, 없으면 홈 디렉토리
const getPreviewDir = () => {
  const desktop = path.join(os.homedir(), 'Desktop');
  try {
    if (fs.existsSync(desktop) && fs.statSync(desktop).isDirectory()) return desktop;
  } catch (_) {}

  return os.homedir();
};

// PNG 버퍼를 파일로 저장하고 절대경로 반환
const savePreviewPng = (pngBuffer) => {
  const dir = getPreviewDir();
  const stamp = new Date()
    .toISOString()
    .replace(/[-:]/g, '')
    .replace(/\..+/, '')
    .replace('T', '_');
  const filePath = path.join(dir, `print-debug-${stamp}.png`);
  fs.writeFileSync(filePath, pngBuffer);

  return filePath;
};

// USB/네트워크 어댑터 로드 (설치 실패 시 graceful fallback)
let USB, Network;
try { USB = require('escpos-usb'); } catch (e) { USB = null; }
try { Network = require('escpos-network'); } catch (e) { Network = null; }

/**
 * 프린터 디바이스 생성
 */
const createDevice = (printerConfig) => {
  if (printerConfig.type === 'usb') {
    if (!USB) throw new Error('escpos-usb 패키지가 설치되지 않았습니다');
    return new USB(
      parseInt(printerConfig.vendorId, 16) || undefined,
      parseInt(printerConfig.productId, 16) || undefined
    );
  }

  if (printerConfig.type === 'network') {
    if (!Network) throw new Error('escpos-network 패키지가 설치되지 않았습니다');
    return new Network(printerConfig.host, printerConfig.port || 9100);
  }

  throw new Error(`지원하지 않는 프린터 타입: ${printerConfig.type}`);
};

/**
 * 영수증 출력
 * @param {string[]} lines - 포맷된 텍스트 라인 배열
 * @param {object} printerConfig - config.json의 printer 설정
 */
const printReceipt = (lines, printerConfig) => {
  return new Promise((resolve, reject) => {
    try {
      const device = createDevice(printerConfig);

      device.open((err) => {
        if (err) {
          return reject(new Error(`프린터 연결 실패: ${err.message}`));
        }

        try {
          const printer = new escpos.Printer(device);

          // ESC/POS 명령으로 출력
          printer
            .font('a')
            .align('lt')
            .style('normal')
            .size(1, 1);

          // 각 라인 출력
          for (const line of lines) {
            printer.text(line);
          }

          // 용지 절단 + 닫기
          printer
            .cut()
            .close(() => {
              resolve();
            });
        } catch (printError) {
          reject(new Error(`출력 중 오류: ${printError.message}`));
        }
      });
    } catch (deviceError) {
      reject(new Error(`디바이스 생성 실패: ${deviceError.message}`));
    }
  });
};

/**
 * 프린터 연결 테스트
 */
const testConnection = (printerConfig) => {
  // DEV 모드: 실 프린터 없어도 셋업 마법사가 진행되도록 가짜 성공 반환
  if (isDevMode()) {
    console.log(`[testConnection:DEV] 🟢 가짜 성공 — config: ${JSON.stringify(printerConfig)}`);

    return Promise.resolve({ devPreview: true });
  }

  // ── Windows/시스템 프린터: 이름이 목록에 존재하는지로 연결 확인 ──
  if (printerConfig.type === 'windows') {
    const { listSystemPrinters } = require('./win-printer');

    return listSystemPrinters().then((list) => {
      const found = list.some((p) => p.name === printerConfig.deviceName);

      if (!found) {
        throw new Error(`프린터 "${printerConfig.deviceName || '(sin nombre)'}" 를 찾을 수 없음`);
      }

      return {};
    });
  }

  return new Promise((resolve, reject) => {
    try {
      const device = createDevice(printerConfig);
      device.open((err) => {
        if (err) {
          return reject(new Error(`프린터 연결 불가: ${err.message}`));
        }
        // 연결 성공 → 바로 닫기
        try {
          const printer = new escpos.Printer(device);
          printer.close(() => resolve());
        } catch (e) {
          resolve(); // 닫기 실패해도 연결은 성공
        }
      });
    } catch (error) {
      reject(error);
    }
  });
};

/**
 * PNG 이미지 버퍼 → ESC/POS 래스터 이미지 출력
 *
 * 파이프라인:
 *   PNG Buffer (Electron offscreen BrowserWindow에서 캡처)
 *   → escpos.Image.load()
 *   → printer.image() 래스터 명령
 *   → cut()
 *
 * @param {Buffer} pngBuffer - PNG 바이너리 버퍼
 * @param {object} printerConfig - printer 설정
 */
// escpos.Image.load 를 Promise 로 감싸기 — 시그니처: load(url, type, callback).
// Buffer 입력의 경우 get-pixels 가 MIME 타입을 요구하므로 'image/png' 명시.
// callback 을 생략하면 get-pixels 내부에서 "callback is not a function" 오류 발생.
const loadImageFromBuffer = (pngBuffer) => {
  return new Promise((resolve, reject) => {
    try {
      escpos.Image.load(pngBuffer, 'image/png', (result) => {
        // escpos 는 성공/실패 모두 단일 콜백으로 반환 — Error instance 로 분기
        if (result instanceof Error) {
          return reject(new Error(`이미지 로드 실패: ${result.message}`));
        }

        resolve(result);
      });
    } catch (loadErr) {
      reject(new Error(`이미지 로드 throw: ${loadErr.message}`));
    }
  });
};

/**
 * 네트워크 프린터 TCP preflight — escpos-network 의 device.open 은 connect
 * 타임아웃이 없어 프린터 다운 시 OS TCP 타임아웃(수십 초)까지 hang 된다.
 * 인쇄 전 짧은 TCP 연결로 도달성을 확인해 빠르고 명확하게 실패시킨다.
 *
 * @param {string} host
 * @param {number} port
 * @param {number} timeoutMs
 */
const preflightTcp = (host, port, timeoutMs = 2500) => {
  return new Promise((resolve, reject) => {
    const net = require('net');
    const sock = new net.Socket();
    let settled = false;

    const finish = (err) => {
      if (settled) return;
      settled = true;
      try { sock.destroy(); } catch (_e) { /* ignore */ }
      if (err) reject(err); else resolve();
    };

    const timer = setTimeout(
      () => finish(new Error(`프린터 도달 불가 (${host}:${port} — ${timeoutMs}ms 타임아웃)`)),
      timeoutMs,
    );

    sock.once('connect', () => { clearTimeout(timer); finish(); });
    sock.once('error', (e) => {
      clearTimeout(timer);
      finish(new Error(`프린터 도달 불가 (${host}:${port} — ${e.code || e.message})`));
    });

    try {
      sock.connect({ host, port });
    } catch (e) {
      clearTimeout(timer);
      finish(new Error(`프린터 도달 불가 (${host}:${port} — ${e.message})`));
    }
  });
};

const printImageNow = async (pngBuffer, printerConfig, log = () => {}) => {
  // ── DEV 모드: 실 프린터 호출 없이 PNG 만 저장 (PNG 미리보기 모드) ──
  // 80mm = 576px @ 203dpi 로 렌더된 이미지를 그대로 저장.
  // 운영 모드에서는 escpos 디바이스로 전송.
  if (isDevMode()) {
    return new Promise((resolve, reject) => {
      try {
        const filePath = savePreviewPng(pngBuffer);
        console.log(`[printImage:DEV] 🖼️  실 프린터 출력 스킵 — PNG 저장: ${filePath}`);
        console.log(`[printImage:DEV]    프린터 설정: ${JSON.stringify(printerConfig)}`);
        resolve({ devPreview: true, path: filePath });
      } catch (err) {
        reject(new Error(`PNG 미리보기 저장 실패: ${err.message}`));
      }
    });
  }

  // ── Windows/시스템 프린터: OS 드라이버 무음 인쇄 (libusb 불필요) ──
  // deviceName 으로 특정 프린터 고정 선택. 절단/용지폭은 드라이버 설정 따름.
  if (printerConfig.type === 'windows') {
    log(`🪟 [printImage] windows 드라이버 무음 인쇄 — device="${printerConfig.deviceName || '-'}"`);
    const { printImageSilent } = require('./win-printer');

    return printImageSilent(pngBuffer, printerConfig, log);
  }

  // 네트워크 프린터: 인쇄 전 TCP preflight — escpos open hang 대신 2.5초 내 명확한 실패
  if (printerConfig.type === 'network') {
    const pfT = Date.now();

    await preflightTcp(printerConfig.host, Number(printerConfig.port) || 9100);
    log(`🔎 [printImage] preflight OK (${Date.now() - pfT}ms)`);
  }

  return new Promise((resolve, reject) => {
    try {
      log(
        `🔌 [printImage] 디바이스 생성 type=${printerConfig.type} ` +
          `${printerConfig.host || ''}:${printerConfig.port || 9100}`,
      );
      const device  = createDevice(printerConfig);
      const openT   = Date.now();

      device.open(async (err) => {
        if (err) {
          // 가장 흔한 실패 지점 — 프린터 오프라인/IP·포트 오류/방화벽
          log(`❌ [printImage] 프린터 연결 실패 (${Date.now() - openT}ms): ${err.message}`);

          return reject(new Error(`프린터 연결 실패: ${err.message}`));
        }
        log(`🔗 [printImage] 프린터 연결 성공 (${Date.now() - openT}ms)`);

        // ★ 연결된 뒤 실패하면 **장치를 닫고** reject 한다. 안 닫으면 USB 는 BUSY,
        //   TCP 는 프린터 쪽 연결이 남아 다음 작업들이 연달아 실패한다.
        const failAfterOpen = (error) => {
          // close 콜백을 기다리지 않는다 — 콜백이 안 오는 경로가 있으면 이 작업이 영영 안 끝난다.
          try { device.close(); } catch (_closeErr) { /* 닫기 실패는 원래 오류를 가리지 않는다 */ }
          reject(error);
        };

        try {
          const printer = new escpos.Printer(device);
          const image   = await loadImageFromBuffer(pngBuffer);

          log(`🖼️ [printImage] 이미지 로드 완료 size=${JSON.stringify(image ? image.size : null)}`);
          console.log('[printImage] image loaded, size=', image?.size);

          // ── 백지 진단(최종 방어선): escpos 가 실제 래스터화할 잉크 픽셀 수 측정 ──
          // image.data 는 픽셀당 0(백색)/1(잉크) 플랫 배열. 이 값이 0 이면 프린터로
          // 전부 백색만 전송 → 종이는 나오지만 아무것도 안 찍힘(빈 종이) 확정.
          try {
            const inkCount = Array.isArray(image?.data)
              ? image.data.reduce((sum, v) => sum + (v ? 1 : 0), 0)
              : -1;

            if (inkCount === 0) {
              log('🟥 [printImage] 경고: 래스터 잉크 픽셀 0 — 빈 종이 확정(렌더 백지). 프린터 아닌 렌더 단계 문제');
            } else {
              log(`🔬 [printImage] 래스터 잉크 픽셀=${inkCount} (0 이면 빈 종이)`);
            }
          } catch (inkErr) {
            log(`🔬 [printImage] 잉크 측정 실패: ${inkErr.message}`);
          }

          // image() 는 Promise 반환
          const rasterT = Date.now();
          printer
            .align('ct')
            .image(image, 'D24')
            .then(() => {
              log(`📤 [printImage] 래스터 전송 완료 (${Date.now() - rasterT}ms) → feed/cut`);
              printer
                .feed(4)
                .cut()
                .close(() => {
                  log('✂️ [printImage] cut/close 완료');
                  resolve();
                });
            })
            .catch((imgErr) => {
              log(`❌ [printImage] 이미지 래스터 오류: ${imgErr.message}`);
              failAfterOpen(new Error(`이미지 래스터 오류: ${imgErr.message}`));
            });
        } catch (printError) {
          log(`❌ [printImage] 출력 중 오류: ${printError.message}`);
          failAfterOpen(new Error(`출력 중 오류: ${printError.message}`));
        }
      });
    } catch (deviceError) {
      log(`❌ [printImage] 디바이스 생성 실패: ${deviceError.message}`);
      reject(new Error(`디바이스 생성 실패: ${deviceError.message}`));
    }
  });
};

// ★ 같은 프린터에 두 작업이 **동시에** 들어가지 않게 한 줄로 세운다.
//   동시에 열면 9100 포트는 두 번째 연결을 거절하거나(USB 는 LIBUSB_ERROR_BUSY)
//   두 래스터가 섞인다 — 판매가 몰리는 순간(판매 + 자동 fiscal 출력) 실제로 겹친다.
//   슬롯 상한 45초: escpos close 콜백이 안 오면 큐가 멈추므로, 그때는 다음 작업을 보낸다
//   (직렬화 전보다 나빠지지 않게 — serial-queue.js 참고).
const printQueue = createSerialQueue({ slotTimeoutMs: 45000 });

const printImage = (pngBuffer, printerConfig, log = () => {}) =>
  printQueue.run(() => printImageNow(pngBuffer, printerConfig, log));
// print-agent/preload.js
// 보안 IPC 브릿지: renderer ↔ main
const { contextBridge, ipcRenderer } = require('electron');

// renderer에서 window.electronAPI.xxx() 로 호출
contextBridge.exposeInMainWorld('electronAPI', {
  // 설정
  getConfig: (key) => ipcRenderer.invoke('store:get', key),
  setConfig: (key, value) => ipcRenderer.invoke('store:set', key, value),
  setAllConfig: (config) => ipcRenderer.invoke('store:setAll', config),

  // WebSocket
  getWsStatus: () => ipcRenderer.invoke('ws:status'),
  reconnectWs: () => ipcRenderer.invoke('ws:reconnect'),
  testConnection: (url, apiKey) => ipcRenderer.invoke('ws:test', url, apiKey),

  // 프린터
  testPrint: () => ipcRenderer.invoke('printer:test'),
  // 티켓 미리보기 (렌더 PNG 를 OS 이미지 뷰어로 열기 — 프린터 불필요)
  previewTicket: () => ipcRenderer.invoke('printer:preview'),
  discoverPrinters: () => ipcRenderer.invoke('printer:discover'),
  listUsbPrinters: () => ipcRenderer.invoke('printer:listUsb'),
  // 시스템(OS) 프린터 목록 — Windows 이름 기반 선택용
  listSystemPrinters: () => ipcRenderer.invoke('printer:listSystem'),
  // 활성 프로파일의 프린터 reachability 점검 — 주기 호출용
  probePrinter: () => ipcRenderer.invoke('printer:probe'),

  // 에이전트 환경
  isDev: () => ipcRenderer.invoke('agent:isDev'),
  // 고정 서버 URL 조회 (셋업 마법사 표시/연결용 — 사용자 입력 불필요)
  getServerUrl: () => ipcRenderer.invoke('agent:serverUrl'),

  // 티켓 폰트 옵션/현재값 조회
  getFontOptions: () => ipcRenderer.invoke('fonts:options'),

  // 티켓 하단 문구 — 서버가 단일 출처다(읽기: agent_info, 쓰기: set_footer)
  getFooter: () => ipcRenderer.invoke('footer:get'),
  setFooter: (footerLines) => ipcRenderer.invoke('footer:set', footerLines),

  // 셋업
  completeSetup: () => ipcRenderer.invoke('setup:complete'),

  // ─── 다중 프로파일 (sucursal 연결 관리) ────────────────────────────────────
  // 프로파일 목록 조회
  getProfiles: () => ipcRenderer.invoke('profile:list'),
391-
392-// ─── IPC 핸들러 (renderer → main) ────────────────────────────────────────────
393-
394-// 설정 읽기
395:ipcMain.handle('store:get', (_event, key) => store.get(key));
396-
397-// ─── 프로파일 IPC 핸들러 ─────────────────────────────────────────────────────
398-
399-// 프로파일 목록 조회
--
438-  return profileId;
439-});
440-
441-// 설정 저장
442:ipcMain.handle('store:set', (_event, key, value) => {
443-  store.set(key, value);
444-
445-  // 티켓 조정값 변경 시 즉시 반영 (다음 출력부터 적용)
446-  //
     1	/**
     2	 * ticket-copias.js — cuántas copias del ticket de venta (2026-10-07 usuario).
     3	 *
     4	 * > «Print agent가 매번 티켓을 몇 카피를 출력할지 결정할 수 있어야 하는데»
     5	 *   → ajuste del agente (1–3), sólo el ticket de venta.
     6	 *
     7	 * ★ Sólo el ticket que sale SOLO al vender (`printJobId = sale-invoice:<id>`). La reimpresión
     8	 *   (`sale-reprint:…`) la pide una persona y sale 1: si pide una, no le salen tres.
     9	 *   Factura AFIP, comanda, presupuesto y prueba no pasan por acá.
    10	 * ★ Sin printJobId (servidor viejo) → 1, como siempre. Ante cualquier duda, 1.
    11	 * ★ Las copias son UN trabajo: el registro de «ya impreso» (print-dedup) se toma una vez antes de
    12	 *   imprimir. Si el servidor reenvía el mismo trabajo, se rechaza entero — nunca 2×N.
    13	 */
    14	const MAX_COPIAS = 3;
    15	
    16	/** Lo guardado → 1..MAX_COPIAS (cualquier cosa rara = 1). */
    17	function normalizarCopias(v) {
    18	  const n = Number(v);
    19	
    20	  return Number.isInteger(n) && n >= 1 && n <= MAX_COPIAS ? n : 1;
    21	}
    22	
    23	/** Copias para ESTE trabajo de print_invoice. */
    24	function copiasDelTicket(payload, configurado) {
    25	  const job = payload && typeof payload.printJobId === 'string' ? payload.printJobId : '';
    26	  if (!job.startsWith('sale-invoice:')) return 1;
    27	  if (payload && payload.factura) return 1;
    28	
    29	  return normalizarCopias(configurado);
    30	}
    31	
    32	module.exports = { copiasDelTicket, normalizarCopias, MAX_COPIAS };
    20	 * @param {object} printerCfg   - printer 설정 (type, host, port, ...)
    21	 * @param {function} log        - 단계별 디버그 로그 콜백 (운영 추적용, 선택)
    22	 * @param {{copias?: number}} o - [2026-10-07] copias del MISMO ticket (src/ticket-copias.js).
    23	 *                                Se dibuja una vez y se manda N veces: las N salen iguales.
    24	 */
    25	async function printTicket(data, printerCfg, log = () => {}, { copias = 1 } = {}) {
    26	  const t0 = Date.now();
    27	
    28	  // 0. 프린터 설정 검증 — 설정 누락이면 이후 단계 진입 전에 명확히 실패
    29	  if (!printerCfg || !printerCfg.type) {
    30	    throw new Error('printer no configurado (printerCfg 없음 또는 type 누락)');
    31	  }
    32	  log(
    33	    `🔧 [pipeline] printerCfg type=${printerCfg.type} ` +
    34	      `host=${printerCfg.host || '-'}:${printerCfg.port || '-'} ` +
    35	      `device=${printerCfg.deviceName || '-'}`,
    36	  );
    37	
    38	  // 1. HTML 생성
    39	  const html = formatInvoiceHtml(data);
    40	  log(`📝 [1/3] HTML 생성 완료 (${html ? html.length : 0} chars, ${Date.now() - t0}ms)`);
    41	
    42	  // 2. HTML → PNG (Electron offscreen)
    43	  //    80mm @ 203dpi = 576px
    44	  const t1 = Date.now();
    45	  const pngBuffer = await renderHtmlToPng(html, 576, 10000, log);
    46	  log(`🖼️ [2/3] PNG 렌더 완료 (${pngBuffer ? pngBuffer.length : 0} bytes, ${Date.now() - t1}ms)`);
    47	
    48	  // 3. PNG → ESC/POS → 프린터 (copias: una tras otra, cada una con su corte)
    49	  const n = Number.isInteger(copias) && copias > 1 ? copias : 1;
    50	  for (let i = 1; i <= n; i += 1) {
    51	    const t2 = Date.now();
    52	    await printImage(pngBuffer, printerCfg, log);
    53	    log(`🧾 [3/3] 프린터 전송 완료${n > 1 ? ` (copia ${i}/${n})` : ''} (${Date.now() - t2}ms, 총 ${Date.now() - t0}ms)`);
    54	  }
    55	}
    56	
    57	module.exports = { printTicket };
   800	          await window.electronAPI.setConfig('ticketMarginRight', Number(marginRange.value) || 0);
   801	          updateMargin();
   802	        });
   803	      } catch (e) {
   804	        console.error('[renderer] font settings init error:', e);
   805	      }
   806	
   807	      // ── Copias del ticket de venta ──
   808	      try {
   809	        const copiasSel = document.getElementById('copiasSelect');
   810	        const guardadas = Number(await window.electronAPI.getConfig('ticketCopias'));
   811	        copiasSel.value = [1, 2, 3].includes(guardadas) ? String(guardadas) : '1';
   812	        copiasSel.addEventListener('change', async () => {
   813	          await window.electronAPI.setConfig('ticketCopias', Number(copiasSel.value) || 1);
   814	        });
   815	      } catch (e) {
   816	        console.error('[renderer] copias init error:', e);
   817	      }
   818	
   819	      // ── Pie de impresión ──────────────────────────────────────────────────
   820	      const footerText  = document.getElementById('footerText');

hook: PostToolUse
hook: PostToolUse
hook: PostToolUse Failed
hook: PostToolUse Completed
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
exec
/bin/zsh -lc "cat print-agent/src/serial-queue.js; sed -n '438,465p' print-agent/main.js; nl -ba print-agent/src/serial-queue.js; nl -ba print-agent/src/printer.js | sed -n '300,365p'; nl -ba print-agent/main.js | sed -n '1120,1215p'" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
'use strict';

// **한 번에 하나씩** 돌리되, **한 작업의 실패·멈춤이 다음 작업을 막지 않는다.**
//
// ★ 종전 renderer-engine 의 큐는 `queue = queue.then(fn)` 이었다. fn 이 한 번 reject
//   하면 queue 자체가 rejected 로 남고, 이후 모든 `.then(fn)` 은 fn 을 **부르지도 않고**
//   같은 오류로 끝난다 — 렌더 타임아웃 한 번이면 재시작 전까지 출력이 전부 실패했다.
//   그래서 꼬리(tail)는 결과와 상관없이 항상 fulfilled 로 이어 간다.
//
// ★ slotTimeoutMs: 앞 작업이 **영영 안 끝나면**(escpos close 콜백 누락 등) 큐가 멈춘다.
//   직렬화 전에는 그 경우에도 다음 출력이 나갔으므로, 직렬화가 그보다 나빠지면 안 된다.
//   그래서 앞 작업을 기다리는 시간에 상한을 둔다 — 넘으면 다음 작업을 시작한다.
//   (앞 작업의 promise 는 그대로 호출부에 남는다. 큐만 놓아 준다.)

function createSerialQueue({ slotTimeoutMs = 0 } = {}) {
  let tail = Promise.resolve();

  function run(fn) {
    // ★ 슬롯 시간은 **이 작업이 실제로 시작된 순간부터** 잰다. 등록 시점부터 재면
    //   대기 중인 작업들의 타이머가 한꺼번에 만료돼 여러 개가 동시에 풀린다.
    let markStarted;
    const started = new Promise((resolve) => { markStarted = resolve; });
    const job = tail.then(() => {
      markStarted();

      return fn();
    });

    const settled = job.then(() => undefined, () => undefined);

    // ★ 상한을 넘기면 앞 작업은 **돌고 있는 채로** 다음이 시작된다(겹칠 수 있다).
    //   취소할 수단이 없는 작업(escpos)에서 「절대 안 겹침」과 「절대 안 멈춤」은 함께
    //   보장할 수 없다 — 멈춘 작업 하나가 이후 출력을 영원히 막는 쪽이 더 나쁘다.
    //   직렬화 전에는 항상 겹쳤으므로, 멈춘 경우에만 겹치는 지금이 그보다 나쁘지 않다.
    tail = slotTimeoutMs > 0
      ? started.then(() => Promise.race([
        settled,
        new Promise((resolve) => setTimeout(resolve, slotTimeoutMs)),
      ]))
      : settled;

    return job;
  }

  return { run };
}

module.exports = { createSerialQueue };
  return profileId;
});

// 설정 저장
ipcMain.handle('store:set', (_event, key, value) => {
  store.set(key, value);

  // 티켓 조정값 변경 시 즉시 반영 (다음 출력부터 적용)
  //
  // ★ 세 키를 **한 목록**으로 둔다. 조건을 따로 쓰면 새 키를 더할 때 한쪽만 고쳐
  //   「저장은 되는데 다음 출력에 안 먹는」 상태가 생긴다(재시작하면 먹으니 더 헷갈린다).
  if (['ticketFont', 'ticketFontScale', 'ticketMarginRight'].includes(key)) {
    ticketSettings.configure({
      family:      store.get('ticketFont'),
      scale:       store.get('ticketFontScale'),
      marginRight: store.get('ticketMarginRight'),
    });
    const s = ticketSettings.getSettings();
    broadcastLog(`🅰 Ticket: ${s.family} × ${Math.round(s.scale * 100)}% · margen der. ${s.marginRight}px`);
  }
});

// ─── Pie de impresión ───────────────────────────────────────────────────────
//
// ★★★ [2026-09-25 사용자 요구] 「pie de impresión 의 내용을 print agent 에서 직접
//   수정할 수 있으면 더 편할거 같아」
//
// ★★ **로컬 사본을 두지 않는다.** 이 문구의 단일 출처는 서버의
     1	'use strict';
     2	
     3	// **한 번에 하나씩** 돌리되, **한 작업의 실패·멈춤이 다음 작업을 막지 않는다.**
     4	//
     5	// ★ 종전 renderer-engine 의 큐는 `queue = queue.then(fn)` 이었다. fn 이 한 번 reject
     6	//   하면 queue 자체가 rejected 로 남고, 이후 모든 `.then(fn)` 은 fn 을 **부르지도 않고**
     7	//   같은 오류로 끝난다 — 렌더 타임아웃 한 번이면 재시작 전까지 출력이 전부 실패했다.
     8	//   그래서 꼬리(tail)는 결과와 상관없이 항상 fulfilled 로 이어 간다.
     9	//
    10	// ★ slotTimeoutMs: 앞 작업이 **영영 안 끝나면**(escpos close 콜백 누락 등) 큐가 멈춘다.
    11	//   직렬화 전에는 그 경우에도 다음 출력이 나갔으므로, 직렬화가 그보다 나빠지면 안 된다.
    12	//   그래서 앞 작업을 기다리는 시간에 상한을 둔다 — 넘으면 다음 작업을 시작한다.
    13	//   (앞 작업의 promise 는 그대로 호출부에 남는다. 큐만 놓아 준다.)
    14	
    15	function createSerialQueue({ slotTimeoutMs = 0 } = {}) {
    16	  let tail = Promise.resolve();
    17	
    18	  function run(fn) {
    19	    // ★ 슬롯 시간은 **이 작업이 실제로 시작된 순간부터** 잰다. 등록 시점부터 재면
    20	    //   대기 중인 작업들의 타이머가 한꺼번에 만료돼 여러 개가 동시에 풀린다.
    21	    let markStarted;
    22	    const started = new Promise((resolve) => { markStarted = resolve; });
    23	    const job = tail.then(() => {
    24	      markStarted();
    25	
    26	      return fn();
    27	    });
    28	
    29	    const settled = job.then(() => undefined, () => undefined);
    30	
    31	    // ★ 상한을 넘기면 앞 작업은 **돌고 있는 채로** 다음이 시작된다(겹칠 수 있다).
    32	    //   취소할 수단이 없는 작업(escpos)에서 「절대 안 겹침」과 「절대 안 멈춤」은 함께
    33	    //   보장할 수 없다 — 멈춘 작업 하나가 이후 출력을 영원히 막는 쪽이 더 나쁘다.
    34	    //   직렬화 전에는 항상 겹쳤으므로, 멈춘 경우에만 겹치는 지금이 그보다 나쁘지 않다.
    35	    tail = slotTimeoutMs > 0
    36	      ? started.then(() => Promise.race([
    37	        settled,
    38	        new Promise((resolve) => setTimeout(resolve, slotTimeoutMs)),
    39	      ]))
    40	      : settled;
    41	
    42	    return job;
    43	  }
    44	
    45	  return { run };
    46	}
    47	
    48	module.exports = { createSerialQueue };
   300	          // image.data 는 픽셀당 0(백색)/1(잉크) 플랫 배열. 이 값이 0 이면 프린터로
   301	          // 전부 백색만 전송 → 종이는 나오지만 아무것도 안 찍힘(빈 종이) 확정.
   302	          try {
   303	            const inkCount = Array.isArray(image?.data)
   304	              ? image.data.reduce((sum, v) => sum + (v ? 1 : 0), 0)
   305	              : -1;
   306	
   307	            if (inkCount === 0) {
   308	              log('🟥 [printImage] 경고: 래스터 잉크 픽셀 0 — 빈 종이 확정(렌더 백지). 프린터 아닌 렌더 단계 문제');
   309	            } else {
   310	              log(`🔬 [printImage] 래스터 잉크 픽셀=${inkCount} (0 이면 빈 종이)`);
   311	            }
   312	          } catch (inkErr) {
   313	            log(`🔬 [printImage] 잉크 측정 실패: ${inkErr.message}`);
   314	          }
   315	
   316	          // image() 는 Promise 반환
   317	          const rasterT = Date.now();
   318	          printer
   319	            .align('ct')
   320	            .image(image, 'D24')
   321	            .then(() => {
   322	              log(`📤 [printImage] 래스터 전송 완료 (${Date.now() - rasterT}ms) → feed/cut`);
   323	              printer
   324	                .feed(4)
   325	                .cut()
   326	                .close(() => {
   327	                  log('✂️ [printImage] cut/close 완료');
   328	                  resolve();
   329	                });
   330	            })
   331	            .catch((imgErr) => {
   332	              log(`❌ [printImage] 이미지 래스터 오류: ${imgErr.message}`);
   333	              failAfterOpen(new Error(`이미지 래스터 오류: ${imgErr.message}`));
   334	            });
   335	        } catch (printError) {
   336	          log(`❌ [printImage] 출력 중 오류: ${printError.message}`);
   337	          failAfterOpen(new Error(`출력 중 오류: ${printError.message}`));
   338	        }
   339	      });
   340	    } catch (deviceError) {
   341	      log(`❌ [printImage] 디바이스 생성 실패: ${deviceError.message}`);
   342	      reject(new Error(`디바이스 생성 실패: ${deviceError.message}`));
   343	    }
   344	  });
   345	};
   346	
   347	// ★ 같은 프린터에 두 작업이 **동시에** 들어가지 않게 한 줄로 세운다.
   348	//   동시에 열면 9100 포트는 두 번째 연결을 거절하거나(USB 는 LIBUSB_ERROR_BUSY)
   349	//   두 래스터가 섞인다 — 판매가 몰리는 순간(판매 + 자동 fiscal 출력) 실제로 겹친다.
   350	//   슬롯 상한 45초: escpos close 콜백이 안 오면 큐가 멈추므로, 그때는 다음 작업을 보낸다
   351	//   (직렬화 전보다 나빠지지 않게 — serial-queue.js 참고).
   352	const printQueue = createSerialQueue({ slotTimeoutMs: 45000 });
   353	
   354	const printImage = (pngBuffer, printerConfig, log = () => {}) =>
   355	  printQueue.run(() => printImageNow(pngBuffer, printerConfig, log));
   356	
   357	module.exports = { printReceipt, printImage, testConnection };
  1120	    //   설정이 꺼져 있거나 프린터가 없어서 못 찍은 것까지 «찍음» 으로 기록하면,
  1121	    //   설정을 고치고 다시 보내도 원장이 거절해 **영영 안 나온다.**
  1122	    //
  1123	    // ★ 이 이벤트는 두 갈래다: `payload.factura` 가 있으면 fiscal 경로로 가고
  1124	    //   그쪽은 `printFiscal` 로 다시 막힌다. 그 스위치까지 여기서 같이 본다 —
  1125	    //   안 그러면 printFiscal=false 인 상태에서 job 만 소비되고, 스위치를 켠 뒤
  1126	    //   재전송해도 안 나온다.
  1127	    const puertaAbierta = payload?.factura
  1128	      ? store.get('printFiscal')
  1129	      : store.get('printControl');
  1130	
  1131	    if (printerCfg?.type && puertaAbierta && !claimPrintJob('print_invoice', payload)) {
  1132	      return;
  1133	    }
  1134	    const start      = Date.now();
  1135	    const num        = payload?.invoice?.number || payload?.invoiceId || '?';
  1136	
  1137	    broadcastLog(`🖨 print_invoice #${num} — imprimiendo...`);
  1138	
  1139	    // ── 디버그: payload / printerCfg 요약 (운영 출력 오류 추적용) ──
  1140	    broadcastLog(
  1141	      `   ↳ payload: items=${Array.isArray(payload?.items) ? payload.items.length : '?'} ` +
  1142	        `branch=${payload?.branchId ?? '?'} invoiceId=${payload?.invoiceId ?? '?'}`,
  1143	    );
  1144	    console.log('[print_invoice] ← payload received', {
  1145	      invoiceId: payload?.invoiceId,
  1146	      branchId:  payload?.branchId,
  1147	      items:     Array.isArray(payload?.items) ? payload.items.length : undefined,
  1148	    });
  1149	
  1150	    // 프린터 설정 누락이면 파이프라인 진입 전에 명확히 실패 (원인 즉시 노출)
  1151	    if (!printerCfg || !printerCfg.type) {
  1152	      const msg = 'printer no configurado (setup wizard 미완료 또는 활성 프로파일 없음)';
  1153	      broadcastLog(`❌ print_invoice #${num} — ${msg}`);
  1154	      console.error('[print_invoice] ✗', msg, '— printerCfg=', printerCfg);
  1155	      wsConnection.emit('print_ack', {
  1156	        invoiceId: payload?.invoiceId,
  1157	        status:    'error',
  1158	        error:     msg,
  1159	        ts:        Date.now(),
  1160	      });
  1161	
  1162	      return;
  1163	    }
  1164	
  1165	    try {
  1166	      // ── AFIP 재정(fiscal) 분기 — WIRING GAP #1 (Phase 57 W1) ─────────────
  1167	      // payload.factura (shape D-02) 가 있으면 fiscal path 로 렌더 (letra/IVA/CAE/QR).
  1168	      // 없으면 아래 printTicket (control ticket) path 그대로 — 비-AFIP 무회귀.
  1169	      if (payload.factura) {
  1170	        if (!store.get('printFiscal')) {
  1171	          broadcastLog('ℹ️ print_invoice(fiscal) 무시 — printFiscal=false');
  1172	
  1173	          return;
  1174	        }
  1175	
  1176	        broadcastLog('🖨 print_invoice(fiscal) — renderizando comprobante AFIP...');
  1177	        const fiscalHtml = await formatFiscalHtml(payload.factura);
  1178	        const fiscalPng  = await renderHtmlToPng(fiscalHtml, 576, 10000, broadcastLog);
  1179	
  1180	        await printImage(fiscalPng, printerCfg, broadcastLog);
  1181	        const fiscalElapsed = Date.now() - start;
  1182	
  1183	        broadcastLog(`✅ print_invoice(fiscal) — OK (${fiscalElapsed}ms)`);
  1184	        wsConnection.emit('print_ack', {
  1185	          invoiceId: payload?.invoiceId,
  1186	          status:    'ok',
  1187	          ts:        Date.now(),
  1188	        });
  1189	
  1190	        return;
  1191	      }
  1192	
  1193	      // broadcastLog 를 파이프라인에 주입 → 각 단계가 메인창/콘솔에 실시간 표시
  1194	      // [2026-10-07] copias: sólo el ticket automático de la venta (no la reimpresión)
  1195	      const copias = copiasDelTicket(payload, store.get('ticketCopias'));
  1196	      if (copias > 1) broadcastLog(`🧾 print_invoice #${num} — ${copias} copias`);
  1197	      await printTicket(payload, printerCfg, broadcastLog, { copias });
  1198	      const elapsed = Date.now() - start;
  1199	
  1200	      broadcastLog(`✅ print_invoice #${num} — OK (${elapsed}ms)`);
  1201	      wsConnection.emit('print_ack', {
  1202	        invoiceId: payload?.invoiceId,
  1203	        status:    'ok',
  1204	        ts:        Date.now(),
  1205	      });
  1206	    } catch (err) {
  1207	      // fire-and-forget: 출력 실패가 판매 트랜잭션에 영향 없도록 ack만 전송
  1208	      broadcastLog(`❌ print_invoice #${num} — ${err.message}`);
  1209	      console.error('[print_invoice] ✗ pipeline threw', {
  1210	        message: err?.message,
  1211	        stack:   err?.stack,
  1212	      });
  1213	      wsConnection.emit('print_ack', {
  1214	        invoiceId: payload?.invoiceId,
  1215	        status:    'error',

hook: PostToolUse
hook: PostToolUse
hook: PostToolUse Failed
hook: PostToolUse Completed
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
exec
/bin/zsh -lc "rg -n \"attachStore\" print-agent/main.js; nl -ba print-agent/src/print-dedup.js | sed -n '35,105p'; nl -ba print-agent/src/index.js | sed -n '35,65p'; cat print-agent/package.json | sed -n '1,90p'; rg -n 'src/index.js|main.js' print-agent/package.json print-agent/*.json" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
80:printDedup.attachStore(store, (err) => {
    35	  while (seen.size > MAX_ENTRIES) {
    36	    const oldest = seen.keys().next().value;
    37	
    38	    if (oldest === undefined) break;
    39	    seen.delete(oldest);
    40	  }
    41	}
    42	
    43	// 디스크 저장이 실패한 사실을 **알린다**. 조용히 넘어가면 재기동 뒤 그 작업이
    44	// 다시 인쇄되는데, 아무도 이유를 모른다.
    45	let onPersistError = null;
    46	
    47	function save() {
    48	  if (!persist) return;
    49	
    50	  try {
    51	    persist.set('printJobsSeen', Array.from(seen.entries()));
    52	  } catch (err) {
    53	    // ★ 인쇄 자체는 막지 않는다 — 지금 이 장은 나가야 한다. 다만 「재기동을 넘어선
    54	    //   보장이 지금 깨져 있다」를 남긴다.
    55	    if (typeof onPersistError === 'function') {
    56	      try { onPersistError(err); } catch (_e) { /* 알림 실패는 무시 */ }
    57	    } else {
    58	      console.error('[print-dedup] 원장 저장 실패 — 재기동 시 중복 인쇄 가능:', err?.message);
    59	    }
    60	  }
    61	}
    62	
    63	/**
    64	 * 재기동 후에도 기억하게 한다. 에이전트가 재시작하는 사이에 같은 작업이 다시
    65	 * 배달될 수 있다(서버 재전송·소켓 재연결). 메모리만 쓰면 그때 두 장이 나온다.
    66	 */
    67	function attachStore(store, onError) {
    68	  persist = store;
    69	  onPersistError = typeof onError === 'function' ? onError : null;
    70	
    71	  try {
    72	    const saved = store.get('printJobsSeen');
    73	
    74	    if (Array.isArray(saved)) {
    75	      const now = Date.now();
    76	
    77	      for (const [id, ts] of saved) {
    78	        if (typeof id === 'string' && typeof ts === 'number' && now - ts <= TTL_MS) {
    79	          seen.set(id, ts);
    80	        }
    81	      }
    82	    }
    83	  } catch (_e) { /* 손상된 저장값은 무시 — 빈 원장으로 시작 */ }
    84	}
    85	
    86	/**
    87	 * 이 작업을 지금 인쇄해도 되는가. **부작용이 있다** — true 를 돌려주는 순간
    88	 * 그 jobId 는 「처리됨」으로 기록된다. 호출부는 곧바로 인쇄해야 한다.
    89	 *
    90	 * @param {*} jobId 서버/엣지가 실은 작업 식별자. 없으면 항상 true(구버전 호환).
    91	 * @returns {boolean} 인쇄해야 하면 true, 이미 찍은 작업이면 false
    92	 */
    93	function claimJob(jobId) {
    94	  if (!jobId || typeof jobId !== 'string') return true;
    95	
    96	  const now = Date.now();
    97	
    98	  prune(now);
    99	
   100	  if (seen.has(jobId)) return false;
   101	
   102	  seen.set(jobId, now);
   103	  save();
   104	
   105	  return true;
    35	
    36	// 환영 메시지
    37	socket.on('welcome', (data) => {
    38	  console.log(`👋 ${data.message}`);
    39	});
    40	
    41	// 영수증 출력 이벤트 수신
    42	socket.on('print_invoice', async (invoiceData) => {
    43	  const ticketNum = invoiceData?.invoice?.number || 'desconocido';
    44	  console.log(`🖨️  영수증 출력 요청 수신: ${ticketNum}`);
    45	
    46	  try {
    47	    // JSON → ESC/POS 포맷 변환
    48	    const formatted = formatInvoice(invoiceData, config.printer.width);
    49	    // 프린터에 출력
    50	    await printReceipt(formatted, config.printer);
    51	    console.log(`✅ 출력 완료: ${ticketNum}`);
    52	    // 성공 확인 전송
    53	    socket.emit('print_confirmation', {
    54	      success: true,
    55	      invoiceNumber: ticketNum,
    56	      printedAt: new Date().toISOString(),
    57	    });
    58	  } catch (error) {
    59	    console.error(`❌ 출력 실패: ${ticketNum}`, error.message);
    60	    // 실패 확인 전송
    61	    socket.emit('print_confirmation', {
    62	      success: false,
    63	      invoiceNumber: ticketNum,
    64	      error: error.message,
    65	    });
{
  "name": "ventago-print-agent",
  "version": "1.2.1",
  "description": "VentaGO — Agente de Impresión Térmica",
  "main": "main.js",
  "author": "CoolSistema",
  "scripts": {
    "start": "electron .",
    "dev": "electron . --dev",
    "build:win": "electron-builder --win --x64 --publish never",
    "build:mac": "electron-builder --mac --x64 --arm64 --publish never",
    "rebuild": "electron-builder install-app-deps"
  },
  "dependencies": {
    "electron-store": "^8.1.0",
    "electron-updater": "^6.3.9",
    "escpos": "^3.0.0-alpha.6",
    "escpos-network": "^3.0.0-alpha.4",
    "escpos-usb": "^3.0.0-alpha.4",
    "qrcode": "^1.5.4",
    "socket.io-client": "^4.8.1"
  },
  "devDependencies": {
    "electron": "^28.0.0",
    "electron-builder": "^24.0.0"
  },
  "build": {
    "appId": "com.coolsistema.ventago-print",
    "productName": "VentaGO Print Agent",
    "copyright": "© 2026 CoolSistema",
    "electronVersion": "28.3.3",
    "icon": "renderer/assets/icon-512.png",
    "publish": {
      "provider": "generic",
      "url": "https://github.com/jhkim1010/ventago-downloads/releases/download/print-agent-latest"
    },
    "files": [
      "main.js",
      "preload.js",
      "renderer/**",
      "src/**",
      "!src/**/*.test.js",
      "!ticket-preview.html",
      "package.json"
    ],
    "asar": true,
    "directories": {
      "output": "build"
    },
    "win": {
      "target": [
        {
          "target": "nsis",
          "arch": [
            "x64",
            "ia32"
          ]
        }
      ],
      "artifactName": "VentaGO-Print-Agent-Setup.${ext}"
    },
    "mac": {
      "target": [
        {
          "target": "dmg",
          "arch": [
            "x64",
            "arm64"
          ]
        }
      ],
      "artifactName": "VentaGO-Print-Agent-${arch}.${ext}",
      "category": "public.app-category.business"
    },
    "nsis": {
      "oneClick": true,
      "perMachine": false,
      "runAfterFinish": true,
      "createDesktopShortcut": true,
      "allowToChangeInstallationDirectory": false,
      "include": "installer.nsh"
    },
    "afterPack": "scripts/afterpack-adhoc-sign.js"
  }
}
print-agent/package.json:5:  "main": "main.js",
print-agent/package.json:38:      "main.js",
print-agent/package.json:5:  "main": "main.js",
print-agent/package.json:38:      "main.js",

hook: PostToolUse
hook: PostToolUse
hook: PostToolUse Failed
hook: PostToolUse Completed
codex
[HIGH] `print-agent/src/print-dedup.js:47` — 원장 저장 실패 후에도 인쇄를 진행하여 재시작·재전송 시 동일 판매가 다시 2–3부 출력될 수 있음

  문제: `claimJob()`은 메모리의 `seen`에 작업을 추가한 뒤 영구 저장 실패를 무시하고 `true`를 반환합니다. 예를 들어 3부가 정상 출력된 뒤 `electron-store` 기록이 실패하고 에이전트가 재시작하면, 서버의 동일 `sale-invoice:<id>` 재전송이 다시 3부 출력됩니다. “절대 중복 금지”와 직접 충돌합니다. 시작 시 저장값 읽기 실패도 빈 원장으로 계속 실행합니다.

  근거:

  ```js
  seen.set(jobId, now);
  save();

  return true;
  ```

  ```js
  } catch (err) {
    // 인쇄 자체는 막지 않는다
    ...
  }
  ```

  ```js
  } catch (_e) { /* 손상된 저장값은 무시 — 빈 원장으로 시작 */ }
  ```

  수정: `sale-invoice:*` 자동 인쇄는 영구 원장 저장이 성공한 경우에만 진행하도록 `claimJob()`이 저장 실패를 반환하거나 예외를 던져야 합니다. 원장 로드가 실패한 경우에도 자동 판매 티켓을 fail-closed로 중지하고 명시적인 운영 경고를 보여줘야 합니다.


[HIGH] `print-agent/renderer/index.html:812` — “1 copia” 저장 실패가 UI에 반영되지 않아 실제로는 기존 2–3부가 계속 출력될 수 있음

  문제: 비동기 `change` 콜백의 저장 실패를 처리하지 않습니다. 사용자가 3부에서 1부로 변경했는데 `setConfig`가 실패하면 선택창은 계속 “1 copia”를 표시하지만 저장값은 3입니다. 다음 판매는 사용자가 기대한 것보다 2부 더 출력됩니다. 바깥쪽 `try/catch`는 이벤트 콜백에서 나중에 발생한 rejection을 잡지 못합니다.

  근거:

  ```js
  copiasSel.addEventListener('change', async () => {
    await window.electronAPI.setConfig(
      'ticketCopias',
      Number(copiasSel.value) || 1,
    );
  });
  ```

  수정: 변경 전 값을 보관하고 콜백 내부에서 `try/catch`하십시오. 저장 성공 후에만 선택값을 확정하고, 실패하면 이전 값으로 되돌리며 사용자에게 오류를 표시해야 합니다. 가능하면 main IPC가 정규화되어 실제 저장된 값을 반환하게 하고 UI가 그 값을 다시 표시해야 합니다.


그 외 확인 결과:

- 동일 `printJobId`의 동시 수신, 서버 재전송 및 소켓 재연결은 동기식 `seen.set()` 때문에 현재 프로세스 안에서는 한 번만 통과합니다.
- edge failover는 `print_invoice`를 relay하지 않으므로 이 신규 다중복사 경로가 cloud/edge 양쪽에서 동시에 실행되지는 않습니다.
- 2번째 복사가 실패하면 루프가 즉시 중단되고 error ack가 전송됩니다. 이미 claim된 동일 작업은 재전송되어도 거절되므로 자동으로 1번째 복사부터 다시 출력하지 않습니다. 다만 실제 프린터가 데이터를 받았지만 오류를 반환한 경우에는 몇 부가 물리적으로 나왔는지 확정할 수 없습니다.
- AFIP 경로는 `printImage()` 한 번만 호출하며, `sale-reprint:*`와 `printJobId` 없는 구버전 작업도 1부로 제한됩니다.
- 실제 Electron 진입점은 `main.js`입니다. 별도의 레거시 `src/index.js`에도 `print_invoice` 경로가 있지만 현재 `package.json`에서는 실행되지 않습니다.
- 현재 변경의 smoke test는 정상 1/2/3부만 검증하고 원장 저장 실패 및 UI 저장 실패 시나리오는 검증하지 않습니다.
hook: Stop
hook: Stop
hook: Stop Failed
hook: Stop Completed
tokens used
63,848
[HIGH] `print-agent/src/print-dedup.js:47` — 원장 저장 실패 후에도 인쇄를 진행하여 재시작·재전송 시 동일 판매가 다시 2–3부 출력될 수 있음

  문제: `claimJob()`은 메모리의 `seen`에 작업을 추가한 뒤 영구 저장 실패를 무시하고 `true`를 반환합니다. 예를 들어 3부가 정상 출력된 뒤 `electron-store` 기록이 실패하고 에이전트가 재시작하면, 서버의 동일 `sale-invoice:<id>` 재전송이 다시 3부 출력됩니다. “절대 중복 금지”와 직접 충돌합니다. 시작 시 저장값 읽기 실패도 빈 원장으로 계속 실행합니다.

  근거:

  ```js
  seen.set(jobId, now);
  save();

  return true;
  ```

  ```js
  } catch (err) {
    // 인쇄 자체는 막지 않는다
    ...
  }
  ```

  ```js
  } catch (_e) { /* 손상된 저장값은 무시 — 빈 원장으로 시작 */ }
  ```

  수정: `sale-invoice:*` 자동 인쇄는 영구 원장 저장이 성공한 경우에만 진행하도록 `claimJob()`이 저장 실패를 반환하거나 예외를 던져야 합니다. 원장 로드가 실패한 경우에도 자동 판매 티켓을 fail-closed로 중지하고 명시적인 운영 경고를 보여줘야 합니다.


[HIGH] `print-agent/renderer/index.html:812` — “1 copia” 저장 실패가 UI에 반영되지 않아 실제로는 기존 2–3부가 계속 출력될 수 있음

  문제: 비동기 `change` 콜백의 저장 실패를 처리하지 않습니다. 사용자가 3부에서 1부로 변경했는데 `setConfig`가 실패하면 선택창은 계속 “1 copia”를 표시하지만 저장값은 3입니다. 다음 판매는 사용자가 기대한 것보다 2부 더 출력됩니다. 바깥쪽 `try/catch`는 이벤트 콜백에서 나중에 발생한 rejection을 잡지 못합니다.

  근거:

  ```js
  copiasSel.addEventListener('change', async () => {
    await window.electronAPI.setConfig(
      'ticketCopias',
      Number(copiasSel.value) || 1,
    );
  });
  ```

  수정: 변경 전 값을 보관하고 콜백 내부에서 `try/catch`하십시오. 저장 성공 후에만 선택값을 확정하고, 실패하면 이전 값으로 되돌리며 사용자에게 오류를 표시해야 합니다. 가능하면 main IPC가 정규화되어 실제 저장된 값을 반환하게 하고 UI가 그 값을 다시 표시해야 합니다.


그 외 확인 결과:

- 동일 `printJobId`의 동시 수신, 서버 재전송 및 소켓 재연결은 동기식 `seen.set()` 때문에 현재 프로세스 안에서는 한 번만 통과합니다.
- edge failover는 `print_invoice`를 relay하지 않으므로 이 신규 다중복사 경로가 cloud/edge 양쪽에서 동시에 실행되지는 않습니다.
- 2번째 복사가 실패하면 루프가 즉시 중단되고 error ack가 전송됩니다. 이미 claim된 동일 작업은 재전송되어도 거절되므로 자동으로 1번째 복사부터 다시 출력하지 않습니다. 다만 실제 프린터가 데이터를 받았지만 오류를 반환한 경우에는 몇 부가 물리적으로 나왔는지 확정할 수 없습니다.
- AFIP 경로는 `printImage()` 한 번만 호출하며, `sale-reprint:*`와 `printJobId` 없는 구버전 작업도 1부로 제한됩니다.
- 실제 Electron 진입점은 `main.js`입니다. 별도의 레거시 `src/index.js`에도 `print_invoice` 경로가 있지만 현재 `package.json`에서는 실행되지 않습니다.
- 현재 변경의 smoke test는 정상 1/2/3부만 검증하고 원장 저장 실패 및 UI 저장 실패 시나리오는 검증하지 않습니다.

## 처리
- [HIGH] 원장(print-dedup) 저장 실패 시에도 인쇄 진행 → **이번 범위 밖, 사용자 보고.** 매수와 무관한 기존 설계(저장 실패해도 인쇄는 막지 않음, attachStore 콜백으로 경고)다. 매수를 올리면 그 드문 경우의 피해가 N 배가 되므로 보고하고, fail-closed 전환은 사용자 결정으로 남긴다.
- [HIGH] UI 저장 실패 시 선택값 불일치 → **수용.** 실패하면 저장된 값으로 되돌리고 알린다.
- 레거시 src/index.js 경로는 package.json 진입점이 아니라 미변경.
