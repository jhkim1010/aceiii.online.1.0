Reading additional input from stdin...
2026-09-23T16:03:38.706051Z ERROR codex_models_manager::cache: failed to load models cache: missing field `base_instructions` at line 139 column 5
OpenAI Codex v0.146.0
--------
workdir: /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
model: gpt-5.6-sol
provider: openai
approval: never
sandbox: read-only
reasoning effort: none
reasoning summaries: none
session id: 01a0cf02-237e-7923-b7fa-4bd1bfaaa97f
--------
user
Revisa este cambio del agente de impresión térmica (Electron, print-agent) de un POS argentino.

CONTEXTO (verificado en el código):
- Hay 2 tickets NO fiscales para la MISMA venta y salían distintos:
  · F2 (venta recién generada): socket `print_temp` -> formatTempTicketHtml
  · "Reimprimir ticket": socket `print_invoice` (sin payload.factura) -> formatInvoiceHtml
- El ticket FISCAL de AFIP es otro módulo (fiscal-formatter.js) y NO se toca:
  razonSocial/CUIT/domicilio son obligatorios por ley ahí.
- Pedido del usuario: (1) el nombre de la tienda NUNCA debe imprimirse en los no-fiscales,
  (2) fecha y hora como filas con etiqueta Fecha/Hora, también en F2,
  (3) unificar el pie.
- formatTempTicketHtml lo comparten también comanda de cocina / cuenta de restaurante
  y /print/temp desde SaleReviewPanel y EnvioTimeline (pedidos online, pueden ser de días atrás).
- El pie configurable por tienda llega del servidor en data.footer.extra
  (branch_agents.printer_config.footerLines); los defaults del agente son el fallback.
- src/index.js es CÓDIGO MUERTO (package.json main = main.js y nadie lo requiere),
  por eso no se tocó formatInvoice (el fallback de texto/ESC-POS).

BUSCO ESPECÍFICAMENTE:
1. ¿Algún camino de impresión que quede inconsistente o que rompa? (regresiones)
2. El cambio de `new Date()` a renderTicketDate(data.invoice?.date) en formatTempTicketHtml:
   ¿en qué payload real esto imprimiría "—" donde antes salía una fecha? ¿Es aceptable?
3. ¿El test nuevo (ticket-uniform.smoke.js) realmente ata el comportamiento,
   o hay mutaciones que sobrevivirían?
4. Riesgos de layout en papel térmico al quitar el bloque de cabecera.
No repitas lo que ya está bien; señalá defectos concretos con archivo y línea.

DIFF Y TEST NUEVO:diff --git a/print-agent/src/formatter.js b/print-agent/src/formatter.js
index b0b5cbe..d67d2b6 100644
--- a/print-agent/src/formatter.js
+++ b/print-agent/src/formatter.js
@@ -417,8 +417,12 @@ const formatInvoiceHtml = (data) => {
     </tr>` : '';
 
   const copyNum = data.invoice?.copy ?? 1;
-  const footer1 = data.footer?.line1 || '★ ¡Gracias x elegirnos! ★';
-  const footer2 = data.footer?.line2 || 'Cambios solo por falla de fábrica · Lun–Vie';
+  // 기본 문구는 temp 티켓(formatTempTicketHtml)과 같은 것을 쓴다 (2026-09-23).
+  // ★ 종전 기본값 'Cambios solo por falla de fábrica · Lun–Vie' 는 **한 매장의 정책**을
+  //   에이전트에 박아 둔 것이었다. 매장별 문구는 `data.footer.extra` 가 담당한다
+  //   (서버 `ticket-footer.ts` 가 branch_agents.printer_config.footerLines 에서 싣는다).
+  const footer1 = data.footer?.line1 || '¡Gracias por su compra!';
+  const footer2 = data.footer?.line2 || 'Conserve este comprobante';
 
   return `<!DOCTYPE html>
 <html lang="es">
@@ -688,13 +692,11 @@ const formatInvoiceHtml = (data) => {
 <!-- 최상단 배너 -->
 <div class="banner">DOCUMENTO NO VÁLIDO COMO FACTURA</div>
 
-<!-- 매장 헤더 -->
-<div class="store-header">
-  <div class="store-name">${data.store?.name || 'TIENDA'}</div>
-  ${data.store?.address ? `<div class="store-sub">${data.store.address}</div>` : ''}
-  ${data.store?.phone   ? `<div class="store-sub">Tel: ${data.store.phone}</div>` : ''}
-  ${data.store?.cuit    ? `<div class="store-cuit">CUIT: ${data.store.cuit}</div>` : ''}
-</div>
+<!-- 매장 헤더 제거됨 (2026-09-23) — 사용자 요구: 비-fiscal 티켓에는 매장 이름을
+     절대 찍지 않는다. temp 티켓(formatTempTicketHtml)이 2026-07-07 에 먼저 뺐고,
+     두 티켓의 모양이 갈라져 있던 원인이 이 블록이었다.
+     ★ AFIP 정식 전표(fiscal-formatter.js)는 예외다 — razonSocial·CUIT·domicilio 는
+       법정 기재사항이라 그쪽에서 빼면 전표가 무효가 된다. -->
 
 ${data.numPedido ? `<!-- WP 주문번호 大자 블록 -->
 <div style="text-align:center; border:3px solid #000; margin:8px 12px; padding:8px 6px; background:#fff;">
@@ -843,13 +845,14 @@ const formatTempTicketHtml = (data) => {
   const hasSaleNumber = !!(data.invoice?.number || data.invoice?.id);
   const offlineCapture = offline && !hasSaleNumber;
 
-  const fecha = new Date();
-  const fechaStr = fecha.toLocaleDateString('es-AR', {
-    day: '2-digit', month: '2-digit', year: 'numeric',
-  });
-  const horaStr = fecha.toLocaleTimeString('es-AR', {
-    hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false,
-  });
+  // 날짜·시각의 출처도 재인쇄 티켓과 같게 맞춘다 (2026-09-23).
+  // ★ 종전에는 **무조건 `new Date()`** 였다 — 인쇄한 시각이지 판매한 시각이 아니다.
+  //   F2 처럼 즉시 찍으면 차이가 안 보이지만, `/print/temp` 를 쓰는 다른 경로
+  //   (SaleReviewPanel · EnvioTimeline 의 온라인 주문)는 며칠 전 판매를 찍을 수
+  //   있어 **그럴듯하지만 틀린 날짜**가 손님 종이에 남았다.
+  //   `renderTicketDate` 가 「없으면 지금 시각 / 있는데 못 읽으면 `—`」를 다룬다 —
+  //   comanda 처럼 date 를 안 싣는 payload 는 종전과 동일하게 지금 시각이다.
+  const { fechaStr, horaStr } = renderTicketDate(data.invoice?.date);
 
   // 가격 숨김 모드 — 선물 영수증 / 교환용 티켓.
   // 선물에는 값을 매길 수 없고, cambio 하러 온 손님에게 원래 가격을 보여줄 이유도 없다.
@@ -1133,10 +1136,21 @@ ${offlineCapture ? `<!-- [A-2] 손님이 전화로 불러 줄 참조 — 큰 글
 <!-- 티켓 메타 — ticketType 에 따라 판매번호 노출 여부 결정 -->
 <div class="ticket-meta">
   ${offlineCapture
-    ? `<div class="presupuesto-title">Venta sin conexión — ${fechaStr} ${horaStr}</div>`
+    ? '<div class="presupuesto-title">Venta sin conexión</div>'
     : data.ticketType === 'invoiced' && (data.invoice?.number || data.invoice?.id)
-      ? `<div class="presupuesto-title">Venta # ${data.invoice.number || data.invoice.id} — ${fechaStr} ${horaStr}</div>`
-      : `<div class="presupuesto-title">Presupuesto — ${fechaStr} ${horaStr}</div>`}
+      ? `<div class="presupuesto-title">Venta # ${data.invoice.number || data.invoice.id}</div>`
+      : '<div class="presupuesto-title">Presupuesto</div>'}
+  <!-- 날짜·시각은 라벨 행으로 (2026-09-23) — 종전에는 제목 줄에 인라인이었고
+       재인쇄 티켓(formatInvoiceHtml)만 Fecha/Hora 행을 갖고 있었다. 사용자가
+       그 형태를 원해서 여기로 맞춘다. comanda·cuenta·presupuesto 도 동일하게. -->
+  <div class="meta-row">
+    <span class="meta-label">Fecha</span>
+    <span class="meta-val">${fechaStr}</span>
+  </div>
+  <div class="meta-row">
+    <span class="meta-label">Hora</span>
+    <span class="meta-val">${horaStr}</span>
+  </div>
   ${offline && !offlineCapture ? `<!-- [A-2] 동기화된 오프라인 판매의 재인쇄 — 손님 종이의 참조와 잇는다 -->
   <div class="meta-row">
     <span class="meta-label">Ref. sin conexión</span>
diff --git a/print-agent/test/offline-ticket.smoke.js b/print-agent/test/offline-ticket.smoke.js
index 01758fb..83ebac2 100644
--- a/print-agent/test/offline-ticket.smoke.js
+++ b/print-agent/test/offline-ticket.smoke.js
@@ -23,8 +23,10 @@ const base = {
 const captura = formatTempTicketHtml({ ...base, offlineNumber: VALIDO });
 assert(captura.includes('VENTA REGISTRADA SIN CONEXIÓN'), 'banner sin conexión');
 assert(captura.includes('NO FISCAL — DOCUMENTO NO VÁLIDO COMO FACTURA'), 'banner no fiscal');
-assert(captura.includes('Venta sin conexión —'), 'título de venta, no presupuesto');
-assert(!captura.includes('Presupuesto —'), 'NUNCA presupuesto: la venta ya se cobró');
+// 2026-09-23: la fecha/hora salió del título y pasó a filas «Fecha»/«Hora»,
+// igual que el ticket de reimpresión. Por eso ya no se busca el guión.
+assert(captura.includes('Venta sin conexión'), 'título de venta, no presupuesto');
+assert(!captura.includes('>Presupuesto<'), 'NUNCA presupuesto: la venta ya se cobró');
 assert(!captura.includes('PRESUPUESTO TEMPORAL'), 'sin banner de presupuesto');
 assert(captura.includes(REF), 'referencia corta visible');
 assert(captura.includes(VALIDO), 'número completo visible');
/**
 * 두 판매 티켓의 **모양이 같은지** 재는 시험 (2026-09-23).
 *
 * 무슨 일이 있었나: 같은 판매인데 F2(`print_temp` → `formatTempTicketHtml`)와
 * 「티켓 다시 출력」(`print_invoice` → `formatInvoiceHtml`)이 서로 다른 종이를 냈다.
 *   · 재인쇄 쪽만 매장 이름·주소·CUIT 를 찍었다
 *   · 날짜·시각이 한쪽은 제목 줄 인라인, 한쪽은 «Fecha»/«Hora» 라벨 행이었다
 *   · 기본 꼬리 문구가 둘 다 달랐다
 *
 * ★ 사용자 지시: **비-fiscal 티켓에는 매장 이름을 절대 찍지 않는다.**
 *   AFIP 정식 전표(`fiscal-formatter.js`)는 예외다 — razonSocial·CUIT·domicilio 는
 *   법정 기재사항이라 그쪽에서 빼면 전표가 무효가 된다. 그래서 이 파일은
 *   `formatTempTicketHtml` 과 `formatInvoiceHtml` 만 잰다.
 *
 * ★ 이 시험은 «없음» 을 단언한다 — 렌더가 통째로 실패해도 «없음» 은 성립한다.
 *   그래서 아래 ⓪ 대조군이 **먼저** 있어야 한다: 같은 payload 의 다른 값이
 *   실제로 종이에 나왔다는 것을 확인하고 나서야 «매장 이름이 없다» 가 의미를 갖는다.
 */
const assert = require('assert');
const { formatTempTicketHtml, formatInvoiceHtml } = require('../src/formatter');

// 매장 정보를 **일부러 전부 채워서** 넘긴다 — 빠뜨린 게 아니라 «찍지 않는다» 를 재려면
// 입력에 값이 있어야 한다. 값이 없으면 이 시험은 아무것도 지키지 않는다.
const STORE = { name: 'NOIX-SMOKE', address: 'MORON 3258', cuit: '20337391916', phone: '1122334455' };

const base = {
  store: STORE,
  items: [{ name: 'Remera', quantity: 2, unitPrice: 1000, subtotal: 2000 }],
  totals: { subtotal: 2000, totalAmount: 2000 },
  seller: { name: 'Vendedor-X' },
  client: { name: 'Cliente-Y' },
  invoice: {
    number: 6,
    date: '2026-09-23T12:21:29',
    seller: 'Vendedor-X',
    client: 'Cliente-Y',
  },
};

const f2      = formatTempTicketHtml({ ...base, ticketType: 'invoiced' });
const reimpre = formatInvoiceHtml(base);

// ── ⓪ 대조군 — 렌더가 실제로 일어났다 ──────────────────────────────────────
// 이게 없으면 아래 «매장 이름 없음» 은 «빈 문자열» 로도 통과한다.
for (const [nombre, html] of [['F2', f2], ['reimpresión', reimpre]]) {
  assert(html.includes('Vendedor-X'), `control: ${nombre} renderizó el vendedor`);
  assert(html.includes('Cliente-Y'), `control: ${nombre} renderizó el cliente`);
  assert(html.includes('Remera'), `control: ${nombre} renderizó los items`);
}

// ── ① 매장 이름·주소·CUIT·teléfono 는 어느 쪽에도 없다 ──────────────────────
for (const [nombre, html] of [['F2', f2], ['reimpresión', reimpre]]) {
  assert(!html.includes(STORE.name), `${nombre}: NUNCA el nombre de la tienda`);
  assert(!html.includes(STORE.address), `${nombre}: sin dirección`);
  assert(!html.includes(STORE.cuit), `${nombre}: sin CUIT`);
  assert(!html.includes('CUIT:'), `${nombre}: sin etiqueta CUIT`);
  assert(!html.includes('class="store-header"'), `${nombre}: sin bloque store-header`);
}

// ── ② 날짜·시각은 둘 다 «Fecha»/«Hora» 라벨 행 ─────────────────────────────
for (const [nombre, html] of [['F2', f2], ['reimpresión', reimpre]]) {
  assert(html.includes('>Fecha<'), `${nombre}: fila Fecha`);
  assert(html.includes('>Hora<'), `${nombre}: fila Hora`);
  // 제목 줄에 다시 인라인으로 붙으면 안 된다 (그게 종전 F2 의 모양이었다).
  assert(!/presupuesto-title">[^<]*—[^<]*\d{2}\/\d{2}\/\d{4}/.test(html),
    `${nombre}: la fecha no vuelve al título`);
}

// ── ③ 같은 판매면 같은 날짜·시각 ────────────────────────────────────────────
// F2 는 종전에 `new Date()`(인쇄 시각)를 썼다 — 즉시 찍으면 안 보이지만
// /print/temp 를 쓰는 다른 경로는 며칠 전 판매를 찍는다.
assert(f2.includes('23/09/2026') && reimpre.includes('23/09/2026'),
  'ambos toman la fecha de invoice.date');
assert(f2.includes('12:21:29') && reimpre.includes('12:21:29'),
  'ambos toman la hora de invoice.date');

// ── ④ 기본 꼬리 문구가 같다 ─────────────────────────────────────────────────
for (const linea of ['¡Gracias por su compra!', 'Conserve este comprobante']) {
  assert(f2.includes(linea), `F2: pie «${linea}»`);
  assert(reimpre.includes(linea), `reimpresión: pie «${linea}»`);
}
// 매장별 문구는 서버가 `footer.extra` 로 싣는다 — 에이전트에 박아 두지 않는다.
assert(!reimpre.includes('falla de fábrica'),
  'la política de una tienda no va hardcodeada en el agente');

// ── ⑤ 대조군 — 매장이 설정한 문구는 여전히 나간다 ───────────────────────────
const conExtra = formatInvoiceHtml({ ...base, footer: { extra: ['@mitienda', 'Cambios: Lun-Vie'] } });
assert(conExtra.includes('@mitienda'), 'control: footer.extra sigue imprimiéndose');

console.log('ticket-uniform smoke OK');
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
Voy a contrastar el diff con los payloads y rutas reales del repositorio, además de ejecutar/inspeccionar los smoke tests. No modificaré archivos: entregaré sólo hallazgos concretos, ordenados por severidad.
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
exec
/bin/zsh -lc "sed -n '1,240p' .team/REVIEW-PROTOCOL.md && rg -n \"formatTempTicketHtml|formatInvoiceHtml|print_temp|print_invoice|/print/temp|renderTicketDate|footer\\.extra|footerLines\" print-agent src api-ventago ventago-app 2>/dev/null" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 exited 2 in 0ms:
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
print-agent/src/print-pipeline.js:12:const { formatInvoiceHtml } = require('./formatter');
print-agent/src/print-pipeline.js:19: * @param {object} data         - formatInvoiceHtml() 입력 데이터
print-agent/src/print-pipeline.js:37:  const html = formatInvoiceHtml(data);
print-agent/src/index.js:3: * WebSocket으로 백엔드에서 print_invoice 이벤트를 수신하고
print-agent/src/index.js:8:const { formatInvoice, formatTempTicketHtml } = require('./formatter');
print-agent/src/index.js:42:socket.on('print_invoice', async (invoiceData) => {
print-agent/src/index.js:70:// backend print.service.emitPrintTemp(branchId, data) 가 보내는 print_temp 수신
print-agent/src/index.js:71:// formatTempTicketHtml → renderHtmlToPng(576px) → printImage 파이프라인 (print-pipeline.js 동일 흐름)
print-agent/src/index.js:73:socket.on('print_temp', async (tempData) => {
print-agent/src/index.js:78:    const html = formatTempTicketHtml(tempData);
print-agent/src/formatter.js:6: *   formatInvoiceHtml(data) → HTML 문자열
print-agent/src/formatter.js:15:// 매장이 정한 티켓 하단 문구(`data.footer.extra`) — 서버가 에이전트 설정에서 싣는다.
print-agent/src/formatter.js:30:  const lines = Array.isArray(footer?.extra) ? footer.extra : [];
print-agent/src/formatter.js:272:function renderTicketDate(raw) {
print-agent/src/formatter.js:325:const formatInvoiceHtml = (data) => {
print-agent/src/formatter.js:332:  const { fechaStr, horaStr } = renderTicketDate(data.invoice?.date);
print-agent/src/formatter.js:420:  // 기본 문구는 temp 티켓(formatTempTicketHtml)과 같은 것을 쓴다 (2026-09-23).
print-agent/src/formatter.js:422:  //   에이전트에 박아 둔 것이었다. 매장별 문구는 `data.footer.extra` 가 담당한다
print-agent/src/formatter.js:423:  //   (서버 `ticket-footer.ts` 가 branch_agents.printer_config.footerLines 에서 싣는다).
print-agent/src/formatter.js:696:     절대 찍지 않는다. temp 티켓(formatTempTicketHtml)이 2026-07-07 에 먼저 뺐고,
print-agent/src/formatter.js:802:  // 실제 출력은 formatInvoiceHtml() 사용 권장
print-agent/src/formatter.js:832:// formatInvoiceHtml과 동일한 80mm(576px) 레이아웃을 재사용하되,
print-agent/src/formatter.js:838:// @param {object} data — formatInvoiceHtml과 동일한 스키마, paymentMethods/invoice.number 무시
print-agent/src/formatter.js:840:const formatTempTicketHtml = (data) => {
print-agent/src/formatter.js:850:  //   F2 처럼 즉시 찍으면 차이가 안 보이지만, `/print/temp` 를 쓰는 다른 경로
print-agent/src/formatter.js:853:  //   `renderTicketDate` 가 「없으면 지금 시각 / 있는데 못 읽으면 `—`」를 다룬다 —
print-agent/src/formatter.js:855:  const { fechaStr, horaStr } = renderTicketDate(data.invoice?.date);
print-agent/src/formatter.js:862:  // 상품 행 — formatInvoiceHtml과 동일한 마크업 + variants 매트릭스 재사용
print-agent/src/formatter.js:1144:       재인쇄 티켓(formatInvoiceHtml)만 Fecha/Hora 행을 갖고 있었다. 사용자가
print-agent/src/formatter.js:1225:  formatInvoiceHtml,
print-agent/src/formatter.js:1227:  formatTempTicketHtml,
print-agent/src/edge-failover.js:5:// 무리팩터 설계: main.js 의 기존 print_temp/print_barcode/print_qr 핸들러(클로저)를
print-agent/src/edge-failover.js:15:const RELAY_EVENTS = ['print_temp', 'print_barcode', 'print_qr', 'print_test', 'force_disconnect'];
ventago-app/src/services/print.service.ts:3:// 임시(견적) 티켓 페이로드 — 백엔드 POST /print/temp 의 body 스키마
ventago-app/src/services/print.service.ts:33:  console.log('[printTempTicket] → POST /print/temp', {
ventago-app/src/services/print.service.ts:41:    const res: any = await apiConnector.post('/print/temp', payload)
ventago-app/src/services/print.service.ts:64:// /print/temp 응답에 fallback:true 가 오면 터미널-comandera 매핑이 없어
ventago-app/src/services/api.service.ts:132:        (config.url === '/print/temp' || config.url === '/print/barcode')
print-agent/main.js:12:const { formatTempTicketHtml, formatInvoiceHtml } = require('./src/formatter');
print-agent/main.js:442:// 실제 출력과 100% 동일한 파이프라인(formatInvoiceHtml → renderHtmlToPng, 폰트
print-agent/main.js:446:    const html = formatInvoiceHtml(buildTestTicketData());
print-agent/main.js:678:// 서버 이벤트(`print_invoice`, `print_fiscal`) 수신 → 출력 파이프라인 연동.
print-agent/main.js:829:  // 기존 print_temp/print_barcode/print_qr 핸들러를 listeners() 로 재사용 (무리팩터).
print-agent/main.js:883:    // 여기 apiKey 가 의도한 지점의 것인지가 print_temp 수신 여부를 결정한다.
print-agent/main.js:992:  wsConnection.on('print_invoice', async (payload) => {
print-agent/main.js:994:      broadcastLog('ℹ️ print_invoice 무시 — printControl=false');
print-agent/main.js:1013:    if (printerCfg?.type && puertaAbierta && !claimPrintJob('print_invoice', payload)) {
print-agent/main.js:1019:    broadcastLog(`🖨 print_invoice #${num} — imprimiendo...`);
print-agent/main.js:1026:    console.log('[print_invoice] ← payload received', {
print-agent/main.js:1035:      broadcastLog(`❌ print_invoice #${num} — ${msg}`);
print-agent/main.js:1036:      console.error('[print_invoice] ✗', msg, '— printerCfg=', printerCfg);
print-agent/main.js:1053:          broadcastLog('ℹ️ print_invoice(fiscal) 무시 — printFiscal=false');
print-agent/main.js:1058:        broadcastLog('🖨 print_invoice(fiscal) — renderizando comprobante AFIP...');
print-agent/main.js:1065:        broadcastLog(`✅ print_invoice(fiscal) — OK (${fiscalElapsed}ms)`);
print-agent/main.js:1079:      broadcastLog(`✅ print_invoice #${num} — OK (${elapsed}ms)`);
print-agent/main.js:1087:      broadcastLog(`❌ print_invoice #${num} — ${err.message}`);
print-agent/main.js:1088:      console.error('[print_invoice] ✗ pipeline threw', {
print-agent/main.js:1195:  // POS 'Imprimir Temp' 버튼 → 백엔드 POST /print/temp → branch:{id} 룸으로 emit
print-agent/main.js:1197:  wsConnection.on('print_temp', async (payload) => {
print-agent/main.js:1199:    // print_temp 가 agent 에 실제 도달했는지 한눈에 확인용 (콘솔 + 메인창 로그).
print-agent/main.js:1200:    broadcastLog(`📥 print_temp recibido (items=${Array.isArray(payload?.items) ? payload.items.length : '?'}, branch=${payload?.branchId ?? '?'})`);
print-agent/main.js:1203:    console.log('[print_temp] ← payload received', {
print-agent/main.js:1212:      console.log('[print_temp] full payload:', JSON.stringify(payload, null, 2));
print-agent/main.js:1217:    console.log('[print_temp] printerCfg:', printerCfg);
print-agent/main.js:1220:    broadcastLog('🖨 print_temp — imprimiendo presupuesto...');
print-agent/main.js:1225:      console.error('[print_temp] ✗', msg);
print-agent/main.js:1226:      broadcastLog(`❌ print_temp — ${msg}`);
print-agent/main.js:1233:    if (!claimPrintJob('print_temp', payload)) return;
print-agent/main.js:1236:      console.log('[print_temp] → formatTempTicketHtml()');
print-agent/main.js:1237:      const html = formatTempTicketHtml(payload);
print-agent/main.js:1239:      console.log('[print_temp] html length =', html?.length);
print-agent/main.js:1241:      console.log('[print_temp] → renderHtmlToPng()');
print-agent/main.js:1244:      console.log('[print_temp] png bytes =', png?.length);
print-agent/main.js:1257:          console.log(`[print_temp] 💾 PNG 덤프 → ${dumpPath}`);
print-agent/main.js:1260:          console.warn('[print_temp] PNG 덤프 실패:', dumpErr.message);
print-agent/main.js:1264:      console.log('[print_temp] → printImage()');
print-agent/main.js:1268:      console.log(`[print_temp] ✓ done in ${elapsed}ms`);
print-agent/main.js:1269:      broadcastLog(`✅ print_temp — OK (${elapsed}ms)`);
print-agent/main.js:1271:      console.error('[print_temp] ✗ pipeline threw', {
print-agent/main.js:1276:      broadcastLog(`❌ print_temp — ${err.message}`);
print-agent/test/ticket-date.smoke.js:3:// 무슨 일이 있었나: `formatInvoiceHtml` 이 `new Date(data.invoice.date)` 로 파싱했고,
print-agent/test/ticket-date.smoke.js:18:const { formatInvoiceHtml } = require('../src/formatter');
print-agent/test/ticket-date.smoke.js:30:  formatInvoiceHtml({ ...base, invoice: { ...base.invoice, date } });
print-agent/test/offline-ticket.smoke.js:9:const { formatTempTicketHtml, formatInvoiceHtml } = require('../src/formatter');
print-agent/test/offline-ticket.smoke.js:23:const captura = formatTempTicketHtml({ ...base, offlineNumber: VALIDO });
print-agent/test/offline-ticket.smoke.js:36:const reimpresion = formatTempTicketHtml({
print-agent/test/offline-ticket.smoke.js:46:const online = formatTempTicketHtml({ ...base, invoice: { ...base.invoice, number: 42 } });
print-agent/test/offline-ticket.smoke.js:52:const presupuesto = formatTempTicketHtml({ ...base, ticketType: 'temp' });
print-agent/test/offline-ticket.smoke.js:69:  const html = formatTempTicketHtml({ ...base, offlineNumber: malo });
print-agent/test/offline-ticket.smoke.js:74:// ── ⑥ print_invoice(서버 재인쇄) 경로도 참조를 muestra ──
print-agent/test/offline-ticket.smoke.js:81:assert(formatInvoiceHtml({ ...invBase, offlineNumber: VALIDO }).includes('Ref. sin conexión'),
print-agent/test/offline-ticket.smoke.js:82:  'print_invoice muestra la referencia');
print-agent/test/offline-ticket.smoke.js:83:assert(!formatInvoiceHtml(invBase).includes('Ref. sin conexión'),
print-agent/test/ticket-uniform.smoke.js:4: * 무슨 일이 있었나: 같은 판매인데 F2(`print_temp` → `formatTempTicketHtml`)와
print-agent/test/ticket-uniform.smoke.js:5: * 「티켓 다시 출력」(`print_invoice` → `formatInvoiceHtml`)이 서로 다른 종이를 냈다.
print-agent/test/ticket-uniform.smoke.js:13: *   `formatTempTicketHtml` 과 `formatInvoiceHtml` 만 잰다.
print-agent/test/ticket-uniform.smoke.js:20:const { formatTempTicketHtml, formatInvoiceHtml } = require('../src/formatter');
print-agent/test/ticket-uniform.smoke.js:40:const f2      = formatTempTicketHtml({ ...base, ticketType: 'invoiced' });
print-agent/test/ticket-uniform.smoke.js:41:const reimpre = formatInvoiceHtml(base);
print-agent/test/ticket-uniform.smoke.js:71:// /print/temp 를 쓰는 다른 경로는 며칠 전 판매를 찍는다.
print-agent/test/ticket-uniform.smoke.js:82:// 매장별 문구는 서버가 `footer.extra` 로 싣는다 — 에이전트에 박아 두지 않는다.
print-agent/test/ticket-uniform.smoke.js:87:const conExtra = formatInvoiceHtml({ ...base, footer: { extra: ['@mitienda', 'Cambios: Lun-Vie'] } });
print-agent/test/ticket-uniform.smoke.js:88:assert(conExtra.includes('@mitienda'), 'control: footer.extra sigue imprimiéndose');
api-ventago/src/app/session/session.service.ts:774:    // 푸터 표시와 /print/temp 프린터 라우팅이 cash_registers.terminal_id 를 따르므로
ventago-app/src/views/branches/components/printer/PrinterConfigTab.tsx:197:  // 저장된 문구 — 서버가 준 printerConfig.footerLines 를 textarea 한 덩어리로.
ventago-app/src/views/branches/components/printer/PrinterConfigTab.tsx:199:    const lines = agent.printerConfig?.footerLines
ventago-app/src/views/branches/components/printer/PrinterConfigTab.tsx:210:      await apiConnector.put(`/print/agents/${agent.id}`, { footerLines: text.split('\n') })
api-ventago/src/app/sales/sales-create.service.ts:2969:    | { socketId: string; footerLines: string[] }
api-ventago/src/app/sales/sales-create.service.ts:2982:      return { socketId: target.socketId, footerLines: target.footerLines };
api-ventago/src/app/sales/sales-create.service.ts:3028:        target.footerLines,
api-ventago/src/app/sales/sales-create.service.ts:3037:  // 동일한 print_invoice 이벤트로 emit. 신규 판매든 reprint 든 영수증 외형 동일.
api-ventago/src/app/sales/sales-create.service.ts:3100:        target.footerLines,
api-ventago/src/app/sales/sales.model.ts:236:  // 영수증/factura 출력 횟수 (POST /print/temp 시 +1)
api-ventago/src/app/offline-sync/offline-push.service.spec.ts:342:      // 순간 afterCreateCommit 이 print_invoice 를 쏴서 이미 손님에게 건넨
api-ventago/src/app/offline-sync/offline-push.service.ts:381:        //   /print/temp 를 엣지로 우회한다). 여기서 또 인쇄하면 인터넷이 돌아온
api-ventago/src/app/print/ticket-footer.ts:4: * 저장 위치는 `branch_agents.printer_config.footerLines` 다(에이전트별, 사용자 선택).
api-ventago/src/app/print/ticket-footer.ts:42:  return normalizeFooterLines(printerConfig?.footerLines);
api-ventago/src/app/print/print.service.ts:117:        this.gateway.server?.to(targetSocketId).emit('print_temp', data);
api-ventago/src/app/print/print.service.ts:119:        this.gateway.server?.to(`branch:${branchId}`).emit('print_temp', data);
api-ventago/src/app/print/print.service.ts:131:        this.gateway.server?.to(targetSocketId).emit('print_invoice', data);
api-ventago/src/app/print/print.service.ts:135:          .emit('print_invoice', data);
api-ventago/src/app/print/print.service.ts:532:    data: { label?: string; agentType?: string; footerLines?: string[] },
api-ventago/src/app/print/print.service.ts:543:    if (data.footerLines !== undefined) {
api-ventago/src/app/print/print.service.ts:546:        footerLines: data.footerLines,
api-ventago/src/app/print/print.service.ts:832:            // 티켓 하단 문구(footerLines) — 여기서 빠지면 resolveSingleThermalTarget 이
api-ventago/src/app/print/print.service.ts:843:  // 지점 내 online 상태의 thermal 에이전트 존재 여부 — /print/temp 게이트용.
api-ventago/src/app/print/print.service.ts:877:   * 서버가 인쇄를 쏘는 경로는 셋이다 — `/print/temp`(견적·판매티켓),
api-ventago/src/app/print/print.service.ts:900:    | { socketId: string; agentLabel?: string; footerLines: string[] }
api-ventago/src/app/print/print.service.ts:903:    // ★ footerLines 를 **여기서** 함께 돌려준다 — 대상 에이전트를 아는 곳은 여기뿐이고,
api-ventago/src/app/print/print.service.ts:917:          footerLines: readAgentFooterLines(mapped.printerConfig),
api-ventago/src/app/print/print.service.ts:929:        footerLines: readAgentFooterLines(sole.printerConfig),
api-ventago/src/app/print/print.module.ts:21:// - Sale: /print/temp 에서 print_count++ 처리
api-ventago/src/app/afip/afip-output.service.ts:116:      // AFIP fiscal 페이로드(D-02) 구성 — print-agent print_invoice 가 payload.factura 있으면
api-ventago/src/app/print/ticket-footer.spec.ts:9:describe('티켓 하단 문구 (branch_agents.printer_config.footerLines)', () => {
api-ventago/src/app/print/ticket-footer.spec.ts:29:    expect(readAgentFooterLines({ footerLines: 42 })).toEqual([]);
api-ventago/src/app/print/ticket-footer.spec.ts:30:    expect(readAgentFooterLines({ footerLines: ['  '] })).toEqual([]);
api-ventago/src/app/print/ticket-footer.spec.ts:45:    expect(out.footer.extra).toEqual(['Configurado por la tienda']);
api-ventago/src/app/print/thermal-target-footer.spec.ts:7: *   **resolveSingleThermalTarget 이 footerLines 를 들고 오는지**를 단언한다.
api-ventago/src/app/print/thermal-target-footer.spec.ts:52:      agente({ printerConfig: { footerLines: ['Gracias', '@mitienda'] } }),
api-ventago/src/app/print/thermal-target-footer.spec.ts:61:    expect(out.footerLines).toEqual(['Gracias', '@mitienda']);
api-ventago/src/app/print/thermal-target-footer.spec.ts:72:    expect(out.footerLines).toEqual([]);
api-ventago/src/app/print/thermal-target-footer.spec.ts:80:        agente({ printerConfig: { footerLines: ['Sucursal centro'] } }),
api-ventago/src/app/print/thermal-target-footer.spec.ts:85:    expect(out.footerLines).toEqual(['Sucursal centro']);
api-ventago/src/app/print/print-no-duplicate.spec.ts:4://   쏘는 세 경로(`/print/temp` · `sendToprinters`/`reprintSale` · AFIP dispatch)가
api-ventago/src/app/print/print-no-duplicate.spec.ts:104:describe('[중복 발행 금지] POST /print/temp 는 거절 시 emit 하지 않는다', () => {
api-ventago/src/app/print/print.controller.ts:233:    @Body() body: { label?: string; agentType?: string; footerLines?: unknown },
api-ventago/src/app/print/print.controller.ts:239:    const footerLines =
api-ventago/src/app/print/print.controller.ts:240:      body.footerLines === undefined
api-ventago/src/app/print/print.controller.ts:242:        : normalizeFooterLines(body.footerLines);
api-ventago/src/app/print/print.controller.ts:247:      footerLines,
api-ventago/src/app/print/print.controller.ts:255:      footerLines: normalizeFooterLines(agent.printerConfig?.footerLines),
api-ventago/src/app/print/print.controller.ts:386:  // POST /print/temp — 임시(견적) 영수증 출력 요청
api-ventago/src/app/print/print.controller.ts:407:    let footerLines: string[] = [];
api-ventago/src/app/print/print.controller.ts:446:      footerLines = target.footerLines;
api-ventago/src/app/print/print.controller.ts:457:      console.error('[POST /print/temp] DB lookup failed', dbErr?.message);
api-ventago/src/app/print/print.controller.ts:471:          footerLines,
api-ventago/src/app/print/print.controller.ts:476:      console.error('[POST /print/temp] emit threw', emitErr?.message);
api-ventago/src/app/print/print.controller.ts:498:          `[POST /print/temp] print_count++ failed for saleId=${saleId}:`,
api-ventago/src/app/print/footer-callsites.spec.ts:9: * 쏘는 경로는 셋이다: `/print/temp`(auto impTiq·Repaso) · `sendToprinters`(판매 자동
api-ventago/src/app/print/footer-callsites.spec.ts:20:describe('POST /print/temp — 설정된 문구를 싣는다', () => {
api-ventago/src/app/print/footer-callsites.spec.ts:31:  const make = (footerLines: string[]) => {
api-ventago/src/app/print/footer-callsites.spec.ts:37:        .mockResolvedValue({ socketId: 'sock-1', footerLines }),
api-ventago/src/app/print/footer-callsites.spec.ts:77:  const make = (footerLines: string[], sale: Record<string, any> = {}) => {
api-ventago/src/app/print/footer-callsites.spec.ts:93:      .mockResolvedValue({ socketId: 'sock-1', footerLines });
ventago-app/src/views/ventas-online/components/EnvioTimeline.tsx:251:  // 🎫 Ticket / 🧾 Recibo 출력 — print-agent emitPrintTemp fire-and-forget(POST /print/temp).
ventago-app/src/views/ventas-online/components/EnvioTimeline.tsx:258:      // ★ print-agent formatTempTicketHtml 은 unitPrice/subtotal 을 읽는다(price 아님).
ventago-app/src/views/ventas-online/components/EnvioTimeline.tsx:280:        await apiConnector.post('/print/temp', {
ventago-app/src/views/homes/components/ProductList/components/PaymentSummary.tsx:70:  // 카트 상태를 그대로 백엔드 /print/temp 로 전달.
ventago-app/src/views/homes/components/SaleReview/SaleReviewPanel.tsx:254:  // currentSale → /print/temp 페이로드 변환.
ventago-app/src/views/homes/components/ProductList/ProductList.tsx:2049:          console.log('[autoImpTiq] → POST /print/temp (invoiced)', printPayload);
ventago-app/src/views/homes/components/ProductList/ProductList.tsx:2050:          const printRes: any = await apiConnector.post('/print/temp', printPayload);
ventago-app/src/views/homes/components/ProductList/ProductList.tsx:2474:                  // print-agent 의 formatTempTicketHtml 은 data.invoice.seller / data.invoice.client
ventago-app/src/views/homes/components/ProductList/ProductList.tsx:2503:                const res: any = await apiConnector.post('/print/temp', payload);
api-ventago/migrations/add-sales-terminal-and-print-count.sql:4:--   2) print_count : 영수증/factura 출력 횟수 (POST /print/temp 시 +1)

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
/bin/zsh -lc "sed -n '1,70p' print-agent/src/formatter.js; sed -n '250,350p' print-agent/src/formatter.js; sed -n '640,735p' print-agent/src/formatter.js; sed -n '830,930p' print-agent/src/formatter.js; sed -n '1080,1195p' print-agent/src/formatter.js; sed -n '380,490p' api-ventago/src/app/print/print.controller.ts; sed -n '240,310p' ventago-app/src/views/ventas-online/components/EnvioTimeline.tsx; sed -n '240,330p' ventago-app/src/views/homes/components/SaleReview/SaleReviewPanel.tsx; sed -n '2020,2060p' ventago-app/src/views/homes/components/ProductList/ProductList.tsx; sed -n '2450,2520p' ventago-app/src/views/homes/components/ProductList/ProductList.tsx" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
/**
 * VentaGO — Ticket de Control (Comprobante Interno)
 * HTML 티켓 생성기
 *
 * 출력 파이프라인:
 *   formatInvoiceHtml(data) → HTML 문자열
 *   → Electron offscreen BrowserWindow → PNG Buffer
 *   → ESC/POS 래스터 이미지 → 감열 프린터
 *
 * 80mm 감열지 = 576px @ 203dpi (표준)
 */

// ─── 유틸 ──────────────────────────────────────────────────────────────────────

// 매장이 정한 티켓 하단 문구(`data.footer.extra`) — 서버가 에이전트 설정에서 싣는다.
//
// ★ 이 값은 **사용자가 웹에서 입력한 문자열**이고 여기서 HTML 로 그려진다.
//   이스케이프하지 않으면 입력한 태그가 그대로 렌더돼 티켓 레이아웃이 깨진다
//   (프린터라 스크립트 실행은 없지만, 깨진 종이는 손님에게 간다).
// ★ 줄 수·길이 제한은 서버(`ticket-footer.ts`)가 건다. 여기서는 배열이 아닌 값,
//   빈 값에 대해서만 방어한다 — 구버전 서버는 이 키를 아예 보내지 않는다.
const escapeHtmlText = (value) =>
  String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');

const renderFooterExtra = (footer) => {
  const lines = Array.isArray(footer?.extra) ? footer.extra : [];
  const clean = lines
    .map((line) => String(line ?? '').trim())
    .filter((line) => line.length > 0);

  if (clean.length === 0) return '';

  return `<div class="footer-extra">${clean
    .map((line) => escapeHtmlText(line))
    .join('<br>')}</div>`;
};

const formatMoney = (amount) => {
  const n = Number(amount || 0);

  return n.toLocaleString('es-AR', {
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  });
};

// ─── 변형 매트릭스 렌더 (color × size) — invoice + temp ticket 공유 ──────────
//
// 백엔드 (sales-create.service.ts::groupItemsForPrint) 가 동봉한 variants 가 있으면
// 헤더 행 아래에 색×사이즈 표(또는 한 줄 inline) 를 그린다.
// 영수증 폭 (576px) 안에 들어가도록 컬럼 6/9 개 기준으로 폰트 단계적 축소.
const renderVariantBlockShared = (v) => {
  if (!v || !v.matrix) return '';
  const colors = Array.isArray(v.colors) ? v.colors : [];
  const sizes  = Array.isArray(v.sizes)  ? v.sizes  : [];

  // '—' = 백엔드가 한쪽 축이 없을 때 채우는 placeholder.
  const colorIsDummy = colors.length === 1 && colors[0] === '—';
  const sizeIsDummy  = sizes.length  === 1 && sizes[0]  === '—';
  if (colorIsDummy && sizeIsDummy) return '';

  // 한 축만 있는 경우 — chip 한 줄 inline
  if (colorIsDummy) {
    const cells = sizes
      .map((s) => {
        const n = v.matrix['—']?.[s] || 0;

    return d;
  }

  // ① ISO 및 Date 가 확실히 아는 형식
  const d = new Date(s);

  return Number.isNaN(d.getTime()) ? null : d;
}

// ★★ [2026-09-09 · codex 지적] **「날짜가 없다」와 「날짜가 깨졌다」는 다르게 다룬다.**
//
//   처음 고칠 때는 파싱 실패를 전부 `new Date()` 로 덮었다. 그러면 «Invalid Date» 는
//   사라지지만 **더 나쁜 것**이 남는다 — 손님 종이에 **그럴듯하지만 틀린 날짜**가
//   찍히고, 아무도 이상하다고 신고하지 않는다. 재인쇄·지연 인쇄에서는 판매일이
//   인쇄일로 바뀌어 버린다.
//
//   그래서:
//     · 날짜 필드가 **없다**(레거시 payload) → 지금 시각. 종전 동작이고 근거도 있다.
//       (서버 `buildInvoiceData` 는 항상 보내므로, 없는 것은 옛 클라이언트뿐이다.)
//     · 날짜가 **있는데 못 읽는다** → 날짜를 **만들어내지 않는다.** `—` 를 찍는다.
//       종이에 빈칸이 보이면 사람이 신고한다. 조용히 틀린 값보다 낫다.
function renderTicketDate(raw) {
  const provided = raw !== undefined && raw !== null && String(raw).trim() !== '';
  const parsed = parseTicketDate(raw);

  if (!parsed) {
    if (!provided) {
      const now = new Date();

      return {
        fechaStr: now.toLocaleDateString('es-AR', {
          day: '2-digit', month: '2-digit', year: 'numeric',
        }),
        horaStr: now.toLocaleTimeString('es-AR', {
          hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false,
        }),
      };
    }

    // 값이 있는데 못 읽었다 — 티켓에는 «—», 콘솔에는 원본을 남긴다(고치려면 원본이 필요하다).
    console.warn('[formatter] invoice.date 를 해석할 수 없다 — 날짜를 비운다:', raw);

    return { fechaStr: '—', horaStr: '—' };
  }

  return {
    fechaStr: parsed.toLocaleDateString('es-AR', {
      day: '2-digit', month: '2-digit', year: 'numeric',
    }),
    horaStr: parsed.toLocaleTimeString('es-AR', {
      hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false,
    }),
  };
}

const OFFLINE_NUMBER_RE = /^OFF-[0-9A-HJKMNP-TV-Z]{26}$/;

/**
 * 검증된 오프라인 번호와 그 짧은 참조를 돌려준다. 아니면 null.
 *
 * ★ 짧은 참조(뒤 6자)는 **전화로 불러 주는 용도**지 키가 아니다. ULID 의 뒤 6자는
 *   난수 30비트라 하루 1,000건이면 0.05%, 10,000건이면 4.5%가 겹친다.
 *   조회는 지점+영업일로 좁혀 유일할 때만 확정하고, 아니면 전체 번호를 묻는다.
 */
function readOfflineNumber(data) {
  const raw = typeof data?.offlineNumber === 'string' ? data.offlineNumber.trim() : '';

  if (!raw || !OFFLINE_NUMBER_RE.test(raw)) {
    return null;
  }

  return { full: raw, ref: raw.slice(-6) };
}

const formatInvoiceHtml = (data) => {
  // [A-2] 인터넷 없이 잡혔던 판매의 참조 (서버 buildInvoiceData 가 실어 보낸다).
  // 이 경로는 **재인쇄**다 — 판매는 이미 동기화돼 세무 순번을 받았으므로 배너를
  // 바꾸지 않고 참조 한 줄만 더한다. 손님 종이의 번호와 잇는 유일한 고리다.
  const offline = readOfflineNumber(data);

  // 날짜 / 시간
  const { fechaStr, horaStr } = renderTicketDate(data.invoice?.date);

  // 변형 매트릭스 → 영수증 HTML 한 줄(들) 생성.
  // 백엔드 (sales-create.service.ts::groupItemsForPrint) 가 동봉한 variants 가 있으면
  // 헤더 행 아래에 색×사이즈 표를 그린다. 영수증 폭 (576px) 안에 들어가도록:
  //   - color 만 / size 만 → 1줄 inline ("Rojo:2 Azul:3")
  //   - color × size → 표 (헤더=sizes, 행=colors). 컬럼이 8개 초과면 폰트 축소.
  // ⤷ renderVariantBlockShared() 와 동일 로직 — temp ticket 과 공유 위해 추출됨.

  // 상품 행 생성 — 항목별 discount 없음 (전부 소계 아래로).
  // 변형 (color/size) 그룹이면 헤더 행 + 매트릭스 행 한 쌍을 생성.
  const itemRows = (data.items || []).map((item) => {
    const qty      = item.quantity  || 1;
    const price    = item.unitPrice || 0;
    const subtotal = item.subtotal  || qty * price;
    const descMain = item.name      || 'Producto';
    const descCode = item.code      ? `<span class="item-code">[${item.code}]</span> ` : '';
    const variantBlock = renderVariantBlockShared(item.variants);

  .payment-section {
    border-top: 1px dashed #000;
    padding: 8px 14px 4px;
  }
  .payment-title {
    font-size: 15px;
    font-weight: bold;
    color: #000;
    letter-spacing: 1px;
    text-transform: uppercase;
    margin-bottom: 4px;
  }
  table.payments { width: 100%; border-collapse: collapse; font-size: 20px; }
  table.payments td { padding: 3px 0; }
  .pay-star { color: #000; font-size: 14px; }
  .pay-label { font-weight: bold; }
  .pay-label.sub { font-size: 16px; color: #000; font-weight: normal; padding-left: 14px; }
  .pay-amount { text-align: right; font-weight: bold; }
  .pay-amount.sub { font-size: 16px; color: #000; font-weight: normal; }

  /* ── 푸터 ── */
  .footer {
    border-top: 3px solid #000;
    margin-top: 10px;
    padding: 10px 14px 14px;
    text-align: center;
  }
  .footer-main {
    font-size: 20px;
    font-weight: bold;
    letter-spacing: 1px;
  }
  .footer-sub {
    font-size: 16px;
    color: #000;
    margin-top: 4px;
    line-height: 1.4;
  }
  /* 매장이 정한 추가 문구 — 기본 문구 아래에 붙는다. */
  .footer-extra {
    font-size: 16px;
    color: #000;
    margin-top: 6px;
    line-height: 1.4;
  }

  /* ── 하단 여백 (용지 절단용) ── */
  .cut-space { height: 40px; }
</style>
</head>
<body>

<!-- 최상단 배너 -->
<div class="banner">DOCUMENTO NO VÁLIDO COMO FACTURA</div>

<!-- 매장 헤더 제거됨 (2026-09-23) — 사용자 요구: 비-fiscal 티켓에는 매장 이름을
     절대 찍지 않는다. temp 티켓(formatTempTicketHtml)이 2026-07-07 에 먼저 뺐고,
     두 티켓의 모양이 갈라져 있던 원인이 이 블록이었다.
     ★ AFIP 정식 전표(fiscal-formatter.js)는 예외다 — razonSocial·CUIT·domicilio 는
       법정 기재사항이라 그쪽에서 빼면 전표가 무효가 된다. -->

${data.numPedido ? `<!-- WP 주문번호 大자 블록 -->
<div style="text-align:center; border:3px solid #000; margin:8px 12px; padding:8px 6px; background:#fff;">
  <div style="font-size:16px; letter-spacing:2px; color:#000;">PEDIDO WEB</div>
  <div style="font-size:40px; font-weight:bold; line-height:1.1;">#${data.numPedido}</div>
</div>` : ''}

<!-- 티켓 메타 -->
<div class="ticket-meta">
  <div class="ticket-num">Copia (${copyNum}) : # ${data.invoice?.number || '0'}</div>
  <div class="meta-row">
    <span class="meta-label">Fecha</span>
    <span class="meta-val">${fechaStr}</span>
  </div>
  <div class="meta-row">
    <span class="meta-label">Hora</span>
    <span class="meta-val">${horaStr}</span>
  </div>
  <div class="meta-row">
    <span class="meta-label">Vendedor</span>
    <span class="meta-val">${data.seller?.name || '—'}</span>
  </div>
  ${offline ? `
  <div class="meta-row">
    <span class="meta-label">Ref. sin conexión</span>
    <span class="meta-val">${offline.full}</span>
  </div>` : ''}
  ${data.client?.name ? `
  <div class="meta-row">
    <span class="meta-label">Cliente</span>
    <span class="meta-val">${data.client.name}</span>
  </div>` : ''}
  ${data.client?.document ? `
  <div class="meta-row">
    <span class="meta-label">Doc.</span>
    <span class="meta-val">${data.client.document}</span>
// ─── 임시(견적) 티켓 HTML 생성 ─────────────────────────────────────────────
//
// formatInvoiceHtml과 동일한 80mm(576px) 레이아웃을 재사용하되,
// 1) 최상단 배너를 'TICKET PROVISORIO'로 교체
// 2) 판매번호(`Copia (N) : # ...`) 행 제거
// 3) Forma de Pago 섹션 전체 생략 (결제 전이므로 의미 없음)
// 4) 하단 푸터를 'Documento de cortesía' 문구로 교체
//
// @param {object} data — formatInvoiceHtml과 동일한 스키마, paymentMethods/invoice.number 무시

const formatTempTicketHtml = (data) => {
  // [A-2] 오프라인 캡처 티켓인가. 두 경우를 구분한다:
  //   ① 캡처 직후 (번호만 있고 판매번호 없음)  → 「NO FISCAL」 티켓 전체
  //   ② 동기화 뒤 재인쇄 (판매번호도 있음)     → 평소 「Venta # N」 + 참조 한 줄
  const offline = readOfflineNumber(data);
  const hasSaleNumber = !!(data.invoice?.number || data.invoice?.id);
  const offlineCapture = offline && !hasSaleNumber;

  // 날짜·시각의 출처도 재인쇄 티켓과 같게 맞춘다 (2026-09-23).
  // ★ 종전에는 **무조건 `new Date()`** 였다 — 인쇄한 시각이지 판매한 시각이 아니다.
  //   F2 처럼 즉시 찍으면 차이가 안 보이지만, `/print/temp` 를 쓰는 다른 경로
  //   (SaleReviewPanel · EnvioTimeline 의 온라인 주문)는 며칠 전 판매를 찍을 수
  //   있어 **그럴듯하지만 틀린 날짜**가 손님 종이에 남았다.
  //   `renderTicketDate` 가 「없으면 지금 시각 / 있는데 못 읽으면 `—`」를 다룬다 —
  //   comanda 처럼 date 를 안 싣는 payload 는 종전과 동일하게 지금 시각이다.
  const { fechaStr, horaStr } = renderTicketDate(data.invoice?.date);

  // 가격 숨김 모드 — 선물 영수증 / 교환용 티켓.
  // 선물에는 값을 매길 수 없고, cambio 하러 온 손님에게 원래 가격을 보여줄 이유도 없다.
  // 품목·수량은 그대로 두고 금액 관련 요소만 전부 뺀다(단가/소계/합계/할인/할증/운송).
  const hidePrices = data.hidePrices === true;

  // 상품 행 — formatInvoiceHtml과 동일한 마크업 + variants 매트릭스 재사용
  const itemRows = (data.items || []).map((item) => {
    const qty      = item.quantity  || 1;
    const price    = item.unitPrice || 0;
    const subtotal = item.subtotal  || qty * price;
    const descMain = item.name      || 'Producto';
    const descCode = item.code      ? `<span class="item-code">[${item.code}]</span> ` : '';
    const variantBlock = renderVariantBlockShared(item.variants);

    // 가격 숨김이면 금액 두 칸을 아예 만들지 않고 설명 칸이 그 폭을 가져간다.
    // 빈 <td> 로 두면 종이에 빈 열이 남아 "값이 잘린 영수증"처럼 보인다.
    const priceCells = hidePrices
      ? ''
      : `
        <td class="unit-cell">${formatMoney(price)}</td>
        <td class="amount-cell">${formatMoney(subtotal)}</td>`;

    return `
      <tr class="item-row${variantBlock ? ' has-variants' : ''}">
        <td class="qty-cell">${qty}</td>
        <td class="desc-cell"${hidePrices ? ' colspan="3"' : ''}>${descCode}${descMain}</td>${priceCells}
      </tr>${variantBlock}`;
  }).join('');

  // 소계 / 가감 행
  const subtotalRow = `
    <tr class="sum-row subtotal-line">
      <td class="sum-label">Subtotal</td>
      <td class="sum-amount">${formatMoney(data.totals?.subtotal ?? data.totals?.totalAmount)}</td>
    </tr>`;

  const recargoRows = (data.recharges || []).map(r => `
    <tr class="sum-row plus">
      <td class="sum-label">+ Recargo — ${r.name}</td>
      <td class="sum-amount">+ ${formatMoney(r.amount)}</td>
    </tr>`).join('');

  const descuentoRows = (data.discounts || []).map(d => `
    <tr class="sum-row minus">
      <td class="sum-label">− Descuento — ${d.name}</td>
      <td class="sum-amount">− ${formatMoney(d.amount)}</td>
    </tr>`).join('');

  const envioRow = (data.totals?.transport > 0) ? `
    <tr class="sum-row plus">
      <td class="sum-label">+ Envío</td>
      <td class="sum-amount">+ ${formatMoney(data.totals.transport)}</td>
    </tr>` : '';

  // Forma de Pago 행 — invoiced 티켓에서만 표시 (temp 견적은 결제 전이므로 생략)
  const paymentRows = (data.paymentMethods || []).map((pm) => {
    const label = pm.option ? `${pm.method} (${pm.option})` : pm.method;

    return `
      <tr class="pay-row">
        <td class="pay-label"><span class="pay-star">★</span> ${label}</td>
        <td class="pay-amount">${formatMoney(pm.amount)}</td>
      </tr>`;
  }).join('');

  const paymentSection = (data.ticketType === 'invoiced' && (data.paymentMethods || []).length > 0) ? `
<div class="payment-section">
  <div class="payment-title">Forma de Pago</div>
  <table class="payments">
    <tbody>
      ${paymentRows}
    </tbody>
  </table>
</div>` : '';
    text-align: center;
    letter-spacing: 1px;
    color: #000;
    margin-bottom: 4px;
  }
  table.payments { width: 100%; border-collapse: collapse; font-size: 19px; }
  table.payments td { padding: 3px 0; }
  .pay-label { color: #111; }
  .pay-star { color: #1565c0; margin-right: 4px; }
  .pay-amount { text-align: right; font-weight: bold; white-space: nowrap; }

  .footer {
    border-top: 3px solid #000;
    margin-top: 10px;
    padding: 10px 14px 14px;
    text-align: center;
  }
  .footer-main { font-size: 20px; font-weight: bold; letter-spacing: 1px; }
  .footer-sub  { font-size: 16px; color: #000; margin-top: 4px; line-height: 1.4; }
  .footer-extra { font-size: 16px; color: #000; margin-top: 6px; line-height: 1.4; }
  .cut-space { height: 40px; }
</style>
</head>
<body>

<!-- 최상단 배너 — ticketType 에 따라 분기 -->
<!-- 'invoiced' = 확정된 판매 (Generar Venta + autoImpTiq 플로우) -->
<!-- 'temp' 또는 생략 = 아직 이루어지지 않은 견적 (Imprimir Temp 플로우) -->
<!-- [A-2] 오프라인 캡처는 둘 다 아니다 — 판매는 확정됐지만 세무 번호가 없다 -->
${offlineCapture
    ? `<div class="banner">VENTA REGISTRADA SIN CONEXIÓN</div>
<div class="banner banner-nofiscal">NO FISCAL — DOCUMENTO NO VÁLIDO COMO FACTURA</div>`
    : data.ticketType === 'invoiced'
      ? ''
      : '<div class="banner">PRESUPUESTO TEMPORAL</div>'}

${data.modified
    ? '<div style="text-align:center; margin:6px 12px; padding:6px; border:3px solid #c62828; color:#c62828; font-size:22px; font-weight:bold; letter-spacing:2px;">*** MODIFICADO ***</div>'
    : ''}

<!-- 매장 헤더 제거됨 — 판매 티켓은 'Venta #' 라인부터 시작 (2026-07-07) -->

${data.numPedido ? `<!-- WP 주문번호 大자 블록 -->
<div style="text-align:center; border:3px solid #000; margin:8px 12px; padding:8px 6px; background:#fff;">
  <div style="font-size:16px; letter-spacing:2px; color:#000;">PEDIDO WEB</div>
  <div style="font-size:40px; font-weight:bold; line-height:1.1;">#${data.numPedido}</div>
</div>` : ''}

${offlineCapture ? `<!-- [A-2] 손님이 전화로 불러 줄 참조 — 큰 글씨는 뒤 6자.
     전체 번호도 같이 찍는다: 6자는 사람용이고 유일성의 근거는 전체다. -->
<div class="offline-ref">
  <div class="offline-ref-label">REFERENCIA DE SU COMPRA</div>
  <div class="offline-ref-short">${offline.ref}</div>
  <div class="offline-ref-full">${offline.full}</div>
</div>` : ''}

<!-- 티켓 메타 — ticketType 에 따라 판매번호 노출 여부 결정 -->
<div class="ticket-meta">
  ${offlineCapture
    ? '<div class="presupuesto-title">Venta sin conexión</div>'
    : data.ticketType === 'invoiced' && (data.invoice?.number || data.invoice?.id)
      ? `<div class="presupuesto-title">Venta # ${data.invoice.number || data.invoice.id}</div>`
      : '<div class="presupuesto-title">Presupuesto</div>'}
  <!-- 날짜·시각은 라벨 행으로 (2026-09-23) — 종전에는 제목 줄에 인라인이었고
       재인쇄 티켓(formatInvoiceHtml)만 Fecha/Hora 행을 갖고 있었다. 사용자가
       그 형태를 원해서 여기로 맞춘다. comanda·cuenta·presupuesto 도 동일하게. -->
  <div class="meta-row">
    <span class="meta-label">Fecha</span>
    <span class="meta-val">${fechaStr}</span>
  </div>
  <div class="meta-row">
    <span class="meta-label">Hora</span>
    <span class="meta-val">${horaStr}</span>
  </div>
  ${offline && !offlineCapture ? `<!-- [A-2] 동기화된 오프라인 판매의 재인쇄 — 손님 종이의 참조와 잇는다 -->
  <div class="meta-row">
    <span class="meta-label">Ref. sin conexión</span>
    <span class="meta-val">${offline.full}</span>
  </div>` : ''}
  <div class="meta-row">
    <span class="meta-label">Vendedor</span>
    <span class="meta-val">${data.invoice?.seller || data.seller?.name || '—'}</span>
  </div>
  ${data.invoice?.client ? `
  <div class="meta-row">
    <span class="meta-label">Cliente</span>
    <span class="meta-val">${data.invoice.client}</span>
  </div>` : ''}
</div>

<!-- 상품 목록 -->
<div class="items-section">
  <div class="col-header">
    <span class="c-qty">Cnt</span>
    <span class="c-desc">Descripcion</span>
    ${hidePrices ? '' : `<span class="c-unit">P.Unit</span>
    <span class="c-amt">SubTot</span>`}
  </div>
  <table class="items">
    <tbody>
      ${itemRows}
    </tbody>
  </table>
</div>

<!-- 소계 구역 (결제수단 섹션 없음).
     가격 숨김이면 통째로 뺀다 — 합계만 남으면 숨긴 의미가 없다. -->
${hidePrices ? '' : `<div class="totals-section">
  <table class="sum-table">
    <tbody>
      ${subtotalRow}
      ${recargoRows}
      ${descuentoRows}
      ${envioRow}
    </tbody>
  </table>
      apiKey: agent.apiKey,
    };
  }

  // ── 임시 영수증 출력 (기존 유지) ──

  // POST /print/temp — 임시(견적) 영수증 출력 요청
  @Post('temp')
  async printTemp(@Body() body: any, @Req() req: any) {
    if (!Array.isArray(body?.items) || body.items.length === 0) {
      return { ok: false, error: 'items requerido (carrito vacío)' };
    }

    const branchId = await this.resolvePrintBranchId(req, body);

    // ── 터미널별 프린터 라우팅 ──
    // terminalId 가 오고 해당 터미널에 thermal 에이전트가 매핑돼 있으면
    // 그 에이전트로만 출력 (지점 내 다중 comandera 중복 출력 방지).
    // 매핑이 없거나 terminalId 미전달(구버전 호출) 시 기존 지점 broadcast fallback.
    const terminalId = Number(body?.terminalId) || null;
    let targetSocketId: string | undefined;

    // 라우팅 결과 명시화 — 프론트가 fallback broadcast 여부를 알 수 있게 응답에 포함
    let targetedAgentLabel: string | undefined;

    // 대상 에이전트에 설정된 티켓 하단 문구. **서버가 정한다** — 화면이 보낸 footer 는
    // applyTicketFooter 가 덮어쓴다(누가 보내든 종이에 나가는 문구는 설정값뿐이다).
    let footerLines: string[] = [];

    try {
      if (terminalId) {
        const mapped =
          await this.printService.getTerminalThermalAgent(terminalId);

        // 매핑된 에이전트가 검증된 대상 지점 소속인지 확인 (terminalId 위조 방어).
        // branchId 는 위에서 이미 매장 소속임을 확인했으므로 추가 쿼리 없이 비교로 충분하다.
        if (mapped && Number(mapped.branchId) !== branchId) {
          throw new ForbiddenException('El agente no pertenece a esa sucursal');
        }
      }

      // ★ 대상 해석은 PrintService.resolveSingleThermalTarget **한 곳**에서만 한다.
      //   종전에는 이 컨트롤러와 sendToprinters 와 AFIP dispatch 가 각자 들고 있었고,
      //   셋 다 매핑이 없으면 지점 broadcast 로 떨어져 comandera 2대면 두 장이 나왔다.
      const target = await this.printService.resolveSingleThermalTarget({
        branchId,
        terminalId,
      });

      if ('refuse' in target) {
        return {
          ok: false,
          reason: target.refuse,
          branchId,
          terminalId,
          candidates: target.candidates,
          message:
            target.refuse === 'ambiguous_target'
              ? 'Esta sucursal tiene varias comanderas y el terminal no tiene ninguna asignada. ' +
                'Asigne una en Sucursales → Terminales para evitar impresiones duplicadas.'
              : undefined,
        };
      }

      targetSocketId = target.socketId;
      targetedAgentLabel = target.agentLabel;
      footerLines = target.footerLines;


    } catch (dbErr: any) {
      if (
        dbErr instanceof ForbiddenException ||
        dbErr instanceof NotFoundException
      ) {
        throw dbErr;
      }

      console.error('[POST /print/temp] DB lookup failed', dbErr?.message);

      return { ok: false, error: `DB: ${dbErr?.message || 'unknown'}` };
    }

    try {
      this.printService.emitPrintTemp(
        branchId,
        applyTicketFooter(
          {
            ...body,
            branchId,
            ts: Date.now(),
          },
          footerLines,
        ),
        targetSocketId,
      );
    } catch (emitErr: any) {
      console.error('[POST /print/temp] emit threw', emitErr?.message);

      return { ok: false, error: `emit: ${emitErr?.message || 'unknown'}` };
    }

    // 영수증 출력 횟수 카운팅: body.saleId 가 있으면 print_count += 1
    // emit 성공 후 비동기로 처리 (실패해도 출력 자체엔 영향 없음)
    // [Phase 67] 매장 스코프 필수 — 타 매장 판매의 print_count 를 올릴 수 없어야 한다.
    const saleId = Number(body?.saleId);
    const callerStore = this.callerStoreId(req);

    if (saleId && Number.isFinite(saleId)) {
      Sale.update(
        { printCount: literal('print_count + 1') as any },
        {
  // 아예 안 떠서 재고만 잠긴 채 남았다 — 백엔드는 그 취소를 지원하고(releaseHold),
  // OrderDetailView 는 결제와 무관하게 버튼을 보여주고 있었다. 화면끼리 어긋난 것이었다.
  const canCancel = useMemo(() => isCancellableStatus(order?.status), [order])

  // 이미 받은 금액 — 취소 다이얼로그 문구(favor 안내 vs 단순 확인) 결정에만 쓴다.
  const paidAmount = useMemo(() => {
    if (!order) return 0

    return Math.max(0, Number(order.total ?? 0) - saldo)
  }, [order, saldo])

  // 🎫 Ticket / 🧾 Recibo 출력 — print-agent emitPrintTemp fire-and-forget(POST /print/temp).
  // 에이전트 미설치면 백엔드가 no-op(에러 아님). branchId 는 order.branchId 동봉.
  const handlePrint = useCallback(
    async (kind: 'ticket' | 'recibo') => {
      if (!order) return

      // print/temp 는 items[] 필수 — 주문 라인으로 구성. 비면 단일 합계 라인으로 대체.
      // ★ print-agent formatTempTicketHtml 은 unitPrice/subtotal 을 읽는다(price 아님).
      //    price 로만 보내면 티켓 금액이 전부 $0 으로 찍힌다.
      const items =
        Array.isArray(order.items) && order.items.length > 0
          ? order.items.map((it) => {
              const quantity = Number(it.quantity ?? 1)
              const unitPrice = Number(it.unitPrice ?? 0)

              return { name: it.productName ?? 'Item', quantity, unitPrice, subtotal: quantity * unitPrice }
            })
          : [
              {
                name: `Pedido #${order.orderNumber}`,
                quantity: 1,
                unitPrice: Number(order.total) || 0,
                subtotal: Number(order.total) || 0,
              },
            ]

      const orderTotal = Number(order.total) || 0

      try {
        await apiConnector.post('/print/temp', {
          branchId: order.branchId ?? undefined,
          docType: kind,

          // ★ 포매터 계약: numPedido(주문번호 大자), invoice.client(고객명), totals.totalAmount.
          //    과거 orderNumber/clientName/total 로 보내 세 값이 모두 티켓에서 누락됐다.
          numPedido: order.orderNumber,
          invoice: { client: order.clientName || 'Consumidor Final' },
          items,
          totals: { subtotal: orderTotal, totalAmount: orderTotal },
        })
        toast.success(kind === 'ticket' ? 'Ticket enviado a impresora' : 'Recibo enviado a impresora')
      } catch (e: any) {
        // 출력 실패는 흐름 차단 아님 — 토스트만(에이전트 미설치 시 no-op).
        const msg = e?.response?.data?.message || e?.message || 'No se pudo imprimir'
        toast.error(typeof msg === 'string' ? msg : 'No se pudo imprimir')
      }
    },
    [order],
  )

  // 📝 Nota 추가 — POST /online-orders/:id/nota { text } → 타임라인 갱신.
  const handleAddNote = useCallback(async () => {
    if (!orderId || !noteText.trim()) return

    setSavingNote(true)
    setActionError(null)
    try {
      await apiConnector.post(`/online-orders/${orderId}/nota`, { text: noteText.trim() })
      setNoteText('')
      toast.success('Nota agregada')

    try {
      await apiConnector.post(`/sales/${currentSale.id}/nullify`, {})
      toast.success(`Venta #${currentSale.dailyNumber || currentSale.id} anulada correctamente`)

      // 목록 새로고침
      await fetchTodaySales()
    } catch (err: any) {
      console.error('Error al anular venta:', err)
      const msg = err?.response?.data?.message || err?.message || 'Error al anular la venta'
      toast.error(msg)
    }
  }

  // currentSale → /print/temp 페이로드 변환.
  // Repaso 패널에서 표시 중인 판매를 Print Agent(ESC/POS)로 보낸다.
  const buildTicketPayload = useCallback((): TempTicketPayload => {
    const items = (currentSale?.items || []).map((it: any) => {
      const quantity = Number(it.quantity || 1)
      const unitPrice = Number(it.price || it.unitPrice || 0)

      return {
        quantity,
        name: String(it.customName || it.product?.name || 'Producto'),
        unitPrice,
        subtotal: Number(it.subtotal ?? quantity * unitPrice),
      }
    })

    const discounts = (currentSale?.saleDiscounts || []).map((d: any) => ({
      name: d.name || 'Descuento',
      amount: Number(d.amountDiscount || 0),
    }))

    const recharges = (currentSale?.saleRecharges || []).map((r: any) => ({
      name: r.name || 'Recargo',
      amount: Number(r.amountRecharge || 0),
    }))

    return {
      branchId: user?.branchId,

      // 확정 판매의 재인쇄이므로 'invoiced' — print-agent 가 'PRESUPUESTO TEMPORAL'
      // 배너 대신 'Venta # …' 제목으로 렌더한다(Trello 6a566b67).
      ticketType: 'invoiced' as const,
      store: {
        name: user?.storeName,
        logoUrl: user?.logoUrl,
      },

      // [A-2] 오프라인에서 잡혔던 판매면 그 참조를 재인쇄에도 남긴다 —
      // 손님이 들고 오는 종이에 적힌 것이 이 번호이지 dailyNumber 가 아니다.
      offlineNumber: currentSale?.offlineNumber || null,
      invoice: {
        // 당일 순번(dailyNumber) 우선, 없으면 전역 id 폴백 — 'Venta #' 에 표시.
        number: currentSale?.dailyNumber || currentSale?.id || undefined,
        seller: currentSale?.seller?.name || currentSale?.user?.name || user?.name,
        client: currentSale?.client?.fullname || 'Consumidor Final',
      },
      items,
      discounts,
      recharges,
      totals: {
        subtotal: Number(currentSale?.subtotal || 0),
        totalAmount: Number(currentSale?.totalAmount || 0),
        transport: Number(currentSale?.transport || 0),
      },
    }
  }, [currentSale, user])

  // 인쇄 — 브라우저 window.print()(페이지 전체 인쇄, 저해상도 흐림) 대신 Print Agent 로 라우팅.
  // Agent 오프라인이어도 throw 하지 않으므로 판매 흐름을 막지 않는다.
  const handlePrint = useCallback(async () => {
    if (printing || !currentSale?.items?.length) return

    setPrinting(true)

    try {
      const res: any = await printTempTicket(buildTicketPayload())
      if (res?.ok) {
        toast.success('Ticket enviado a la impresora')
        warnPrintFallbackOnce(res, (msg) => toast.warning(msg, { autoClose: 6000 }))
      } else {
        const reason = res?.reason || res?.error || 'sin comandera en línea'
        toast.warning(`Print Agent: ${reason}`, { autoClose: 5000 })
      }
    } finally {
      setTimeout(() => setPrinting(false), 1000)
    }
  }, [printing, currentSale, buildTicketPayload])

            },
            items: products.map((p: any) => {
              // parent 행이면 variantQuantities + stockByVariant 로 변형 매트릭스 재구성
              const variants = buildPrintVariants(p);

              return {
                name:      p.name || p.description || '-',
                quantity:  p.quantity ?? 1,
                unitPrice: p.price ?? 0,
                subtotal:  (p.price ?? 0) * (p.quantity ?? 1),
                ...(variants ? { variants } : {}),
              };
            }),

            // Forma de Pago — 확정 판매 영수증에 결제 내역 노출
            paymentMethods: (paymentMethods || []).map((pm: any) => ({
              method: pm.title || pm.name || pm.slug || 'Efectivo',
              option: pm.option || null,
              amount: pm.amount,
            })),
            totals: {
              subtotal,
              discounts:   totalDiscounts,
              recharges:   totalRecharges,
              transport:   transport || 0,
              totalAmount: totalFactura,
            },
          };

          console.log('[autoImpTiq] → POST /print/temp (invoiced)', printPayload);
          const printRes: any = await apiConnector.post('/print/temp', printPayload);
          console.log('[autoImpTiq] ← response', printRes?.data ?? printRes);

          if ((printRes?.data ?? printRes)?.ok === false) {
            const reason = (printRes?.data ?? printRes)?.reason || (printRes?.data ?? printRes)?.error || 'desconocido';
            toast.error(`Print Agent: ${reason}`);
          }

          // 매핑 없는 터미널 → 지점 broadcast 로 출력됨 — 세션당 1회 경고
          warnPrintFallbackOnce(printRes, toast.warning);
        } else {
              if (!resolvedBranchId) {
                toast.error('No se pudo resolver la sucursal. ¿Caja abierta?');

                return;
              }

              try {
                const payload = {
                  branchId: resolvedBranchId,

                  // terminalId: 터미널별 프린터 라우팅용
                  terminalId: cashRegister?.terminalId ?? null,
                  ticketType: 'temp' as const,

                  // 선물/교환용이면 print-agent 가 금액 관련 요소를 전부 뺀다
                  hidePrices,
                  store: {
                    name:    (user as any)?.storeName || 'VENTAGO',
                    address: (user as any)?.storeAddress || '-',
                    cuit:    (user as any)?.storeCuit || '-',
                    phone:   (user as any)?.storePhone || '-',
                  },

                  // ★ seller/client 는 반드시 invoice 안에 넣는다.
                  // print-agent 의 formatTempTicketHtml 은 data.invoice.seller / data.invoice.client
                  // 만 읽는다(top-level seller 는 data.seller?.name 으로 읽혀 문자열이면 undefined).
                  // 과거 이 페이로드는 두 값을 top-level 에 둬서 견적 티켓에 판매원·고객이 아예
                  // 출력되지 않았다. TempTicketPayload 스키마(print.service.ts)와도 일치시킨다.
                  invoice: {
                    seller: selectedSeller?.name || (user as any)?.fullName || (user as any)?.name || '-',

                    // selectedClient 는 fullname 속성을 가진다(InfoClient/useSaleProducts).
                    // 견적 시점엔 고객이 아직 등록 전일 수 있어 clientFormData 도 폴백에 포함.
                    client: selectedClient?.fullname
                      || (selectedClient as any)?.name
                      || (clientFormData?.fullname ? String(clientFormData.fullname).trim() : '')
                      || 'Consumidor Final',
                  },
                  items: products.map((p: any) => ({
                    name:      p.name || p.description || '-',
                    quantity:  p.quantity ?? 1,
                    unitPrice: p.price ?? 0,
                    subtotal:  (p.price ?? 0) * (p.quantity ?? 1),
                  })),
                  totals: {
                    subtotal:    subtotal,
                    discounts:   totalDiscounts,
                    recharges:   totalRecharges,
                    transport:   transport || 0,
                    totalAmount: totalFactura,
                  },
                };

                const res: any = await apiConnector.post('/print/temp', payload);

                if (res?.ok === false) {
                  toast.error(res?.error || 'No se pudo enviar al print-agent');

                  return;
                }
                if (hidePrices) {
                  // 가격 숨김은 **매장 PC 의 print-agent** 가 처리한다. 구버전이면 조용히
                  // 무시돼 가격이 그대로 찍힌다 — 선물 영수증에서 가장 나쁜 실패다.
                  // 그래서 성공 토스트에서 한 번 더 확인을 요청한다.
                  toast.warning('Enviado sin precios. Verificá el ticket: si aparecen precios, actualizá el print-agent.');
                } else {
                  toast.success('Presupuesto enviado al print-agent');
                }

                // 매핑 없는 터미널 → 지점 broadcast — 세션당 1회 경고
                warnPrintFallbackOnce(res, toast.warning);

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
/bin/zsh -lc "sed -n '1980,2035p' ventago-app/src/views/homes/components/ProductList/ProductList.tsx; sed -n '1,90p' ventago-app/src/services/print.service.ts; sed -n '2930,3120p' api-ventago/src/app/sales/sales-create.service.ts; sed -n '200,275p' print-agent/src/formatter.js; rg -n \"invoice:\\s*\\{|date:\\s*["'^,]+" ventago-app/src | head -n 150; rg -n "store-header|'"\\.banner|\\.ticket-meta|presupuesto-title|meta-row\" print-agent/src/formatter.js | head -n 80; cat print-agent/package.json; ls print-agent/test" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
            ticketType: 'invoiced' as const,

            // [A-2] 인터넷 없이 잡힌 판매의 티켓 번호 (엣지가 `OFF-<ULID>` 로 발급).
            //
            // ★ 이게 없으면 오프라인 영수증이 **«PRESUPUESTO TEMPORAL»** 로 찍힌다 —
            //   엣지 응답에는 dailyNumber 도 id 도 없어서 아래 invoice.number 가 null 이
            //   되고, formatter 가 견적 분기로 떨어지기 때문이다. 이미 돈을 받은 판매에
            //   「견적」이라고 적힌 종이를 손님에게 주게 된다.
            //
            // ★ invoice.number 에 넣지 않는다 — 세무 순번과 오프라인 번호는 다른
            //   체계다. 섞으면 둘 중 무엇을 본 것인지 나중에 구분이 안 된다.
            offlineNumber: createdSale?.offlineNumber || null,

            // ★ 이 인쇄 의도의 식별자. print-agent 가 이걸로 **이미 찍은 작업을
            //   거절**한다 — 같은 요청이 두 번 도착해도(재전송·failover 겹침·
            //   소켓 재연결) 종이는 한 장이다.
            //
            // ★ **판매에 묶는다** (호출마다 새로 뽑지 않는다). 그래야 같은 판매의
            //   두 번째 자동출력이 같은 id 를 들고 와 거절된다. 오프라인 판매는
            //   서버 id 가 없으므로 엣지가 준 uuid/번호를 쓴다.
            printJobId: `sale-auto:${createdSale?.id ?? createdSale?.uuid ?? createdSale?.offlineNumber ?? idempotencyKeyRef.current ?? ''}`,
            store: {
              name:    (user as any)?.storeName || 'VENTAGO',
              address: (user as any)?.storeAddress || '-',
              cuit:    (user as any)?.storeCuit || '-',
              phone:   (user as any)?.storePhone || '-',
            },
            invoice: {
              // 티켓에는 당일 순번(dailyNumber)을 인쇄한다. sales.number 컬럼은 존재하지 않아
              // 기존 코드는 항상 전역 PK(id) 로 폴백돼 "Venta # 71" 처럼 찍혔다.
              // 레거시 행(daily_number = 0/null)만 id 로 폴백.
              number: createdSale?.dailyNumber || createdSale?.id || null,
              id:     createdSale?.id || null,
              date:   issuedAt.toLocaleDateString('es-AR'),
              time:   issuedAt.toLocaleTimeString('es-AR'),
              seller: selectedSeller?.name || (user as any)?.fullName || (user as any)?.name || '-',

              // selectedClient 는 fullname 속성을 가진다(InfoClient/useSaleProducts). 과거 .name 만 읽어
              // 항상 'Consumidor Final' 로 폴백돼 티켓에 실제 고객명이 찍히지 않았다. fullname 우선.
              client: selectedClient?.fullname || (selectedClient as any)?.name || 'Consumidor Final',
            },
            items: products.map((p: any) => {
              // parent 행이면 variantQuantities + stockByVariant 로 변형 매트릭스 재구성
              const variants = buildPrintVariants(p);

              return {
                name:      p.name || p.description || '-',
                quantity:  p.quantity ?? 1,
                unitPrice: p.price ?? 0,
                subtotal:  (p.price ?? 0) * (p.quantity ?? 1),
                ...(variants ? { variants } : {}),
              };
            }),

            // Forma de Pago — 확정 판매 영수증에 결제 내역 노출
            paymentMethods: (paymentMethods || []).map((pm: any) => ({
import apiConnector from 'src/services/api.service'

// 임시(견적) 티켓 페이로드 — 백엔드 POST /print/temp 의 body 스키마
export interface TempTicketPayload {
  branchId?: number

  // 'invoiced' = 확정 판매 재인쇄(Venta # …, PRESUPUESTO TEMPORAL 배너 없음)
  // 'temp'/생략 = 견적(presupuesto) — print-agent formatter 가 배너로 분기
  ticketType?: 'invoiced' | 'temp'
  store?: { name?: string; address?: string; phone?: string; cuit?: string; logoUrl?: string }
  invoice?: { seller?: string; client?: string; number?: string | number }

  // [A-2] 오프라인 캡처 티켓 번호 (`OFF-<ULID>`). 있으면 print-agent 가 «NO FISCAL»
  // 배너 + 큰 참조로 렌더한다. 온라인 판매에서는 항상 null.
  offlineNumber?: string | null

  // 이 인쇄 의도의 식별자. print-agent 가 이걸로 **이미 찍은 작업을 거절**한다.
  // 자동출력은 판매에 묶어(같은 판매 = 같은 id) 중복 배달을 흡수하고,
  // 사람이 누르는 재인쇄는 **누를 때마다 새 id** 여야 한다(두 번째 사본이 목적이므로).
  printJobId?: string
  items: Array<{ quantity: number; name: string; unitPrice: number; subtotal: number }>
  totals: { subtotal: number; totalAmount: number; transport?: number }
  discounts?: Array<{ name: string; amount: number }>
  recharges?: Array<{ name: string; amount: number }>
}

// 임시(견적) 티켓 출력 헬퍼
// 백엔드는 지점 Print Agent 룸으로 fire-and-forget emit 만 수행한다.
// Agent 오프라인이거나 네트워크 장애 시에도 throw 하지 말고 { ok: false } 반환 —
// POS 판매 흐름이 절대 차단되지 않도록 호출부에서 안전하게 처리할 수 있게 한다.
export async function printTempTicket(payload: TempTicketPayload) {
  // ─── DEBUG(11-06) ─────────────────────────────────────────────────────────
  console.log('[printTempTicket] → POST /print/temp', {
    branchId: payload?.branchId,
    itemsCount: payload?.items?.length,
    totals: payload?.totals,
    payload,
  })

  try {
    const res: any = await apiConnector.post('/print/temp', payload)

    console.log('[printTempTicket] ← response', {
      status: res?.status,
      data: res?.data,
      fullResponse: res,
    })

    return res?.data ?? { ok: false }
  } catch (err: any) {
    console.error('[printTempTicket] ✗ request failed', {
      message: err?.message,
      status: err?.response?.status,
      responseData: err?.response?.data,
      stack: err?.stack,
      fullError: err,
    })

    return { ok: false, error: err?.message || 'network' }
  }
}

// ─── fallback broadcast 경고 (세션당 1회) ────────────────────────────────────
// /print/temp 응답에 fallback:true 가 오면 터미널-comandera 매핑이 없어
// 지점 전체 broadcast 로 출력된 것 — 다중 프린터 지점에서 중복 출력 위험을 안내.
let fallbackWarned = false

export function warnPrintFallbackOnce(res: any, toastFn: (msg: string) => void) {
  const data = res?.data ?? res
  if (!data || data.ok !== true || data.fallback !== true || fallbackWarned) return

  fallbackWarned = true
  toastFn(
    'Este terminal no tiene comandera asignada — el ticket se imprime en todas las comanderas de la sucursal. Puede asignar una en Sucursales → Terminales.'
  )
}
    //      그것도 조용한 재고 오염이다. 모호하면 null 을 돌려주고, 호출부가 거부한다.
    //    창고(is_warehouse)는 판매가 일어나는 곳이 아니므로 후보에서 뺀다.
    const storeId = completeSale?.storeId;
    if (storeId) {
      try {
        const reales = await Branch.findAll({
          where: { storeId: Number(storeId), isWarehouse: false },
          attributes: ['id'],
          limit: 2,
          transaction,
        });
        if (reales.length === 1) return Number(reales[0].id);
      } catch (e: any) {
        console.warn(`[resolveSaleBranchId] store→branch 실패: ${e?.message}`);
      }
    }

    return null;
  }

  // 인쇄 대상 해석 — **PrintService.resolveSingleThermalTarget 한 곳**에서만 정한다.
  //
  // ★★ 종전 주석은 이렇게 적혀 있었다: "판매 확정 티켓은 어디서든 출력되는 것이
  //   우선이므로 temp 와 달리 거부하지 않는다". 그래서 매핑이 없거나 comandera 가
  //   오프라인이면 `undefined` 를 돌려줬고, `emitPrintInvoice` 가 그것을 받아
  //   **지점 룸 전체로 broadcast** 했다 — comandera 2대인 지점은 한 판매에 두 장.
  //
  // ★★ **그 판단을 뒤집는다**(사장 지시 2026-09-09): 중복 발행은 결단코 없어야 한다.
  //   안 나온 종이는 사람이 재인쇄할 수 있지만, 두 장 나간 종이는 되돌릴 수 없다.
  //
  // ★ 에이전트 쪽 중복 방지 원장(printJobId)은 **기계마다 따로**다 —
  //   서로 다른 두 comandera 가 각자 한 장씩 찍는 것은 거기서 못 막는다.
  //   그래서 대상을 하나로 좁히는 이 단계가 유일한 방어다.
  //
  // @returns 보낼 소켓, 또는 null(=보내지 않는다)
  private async resolveInvoiceTargetSocketId(
    terminalId: number | null | undefined,
    branchId: number,
  ): Promise<
    | { socketId: string; footerLines: string[] }
    | { refuse: string; candidates?: number }
  > {
    try {
      const target = await this.printService.resolveSingleThermalTarget({
        branchId,
        terminalId,
      });

      if ('refuse' in target) {
        return { refuse: target.refuse, candidates: target.candidates };
      }

      return { socketId: target.socketId, footerLines: target.footerLines };
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);

      console.warn(
        `[resolveInvoiceTargetSocketId] 대상 해석 실패 (terminal ${terminalId ?? '-'}): ${msg}`,
      );

      // ★ 실패하면 **보내지 않는다.** 종전에는 undefined 를 돌려줘 broadcast 로
      //   떨어졌다 — 조회가 실패했다는 이유로 종이가 여러 장 나가면 안 된다.
      return { refuse: 'resolve_failed' };
    }
  }

  private async sendToprinters(saleId: number): Promise<void> {
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
    );

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
  public async reprintSale(saleId: number): Promise<{
    sent: boolean;
    reason?:
      | 'sale_not_found'
      | 'sale_nullified'
      | 'no_branch'
      | 'no_api_key'
      | 'agent_offline'
      | 'ambiguous_target'
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
    );

    if ('refuse' in target) {
      return {
        sent: false,
        reason: target.refuse as 'ambiguous_target' | 'agent_offline',
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
  public async getSaleStoreId(saleId: number): Promise<number | null> {
    const sale = await this.saleModel.findByPk(saleId, {
      attributes: ['storeId'],
    });

    return sale?.storeId ?? null;
  }

  public buildInvoiceData(sale: Sale): any {
    return {
      // === INFORMACIÓN DE LA FACTURA ===
      invoice: {
//   ① 아무 문자열이나 오프라인 모드를 켜면 안 된다. 이 값이 있으면 티켓의 문구가
//      「NO FISCAL」로 바뀐다 — 온라인 판매가 실수로 그렇게 찍히면 안 된다.
//   ② 통과한 값은 `[0-9A-Z-]` 뿐이라 HTML 로 그대로 넣어도 안전하다.
//      **이 정규식이 곧 이스케이프다** — 느슨하게 바꾸면 그 보장이 같이 사라진다.
// ─── 티켓 날짜 파싱 ────────────────────────────────────────────────────────────
//
// ★ `new Date(문자열)` 을 그대로 쓰면 안 된다. es-AR 로 포맷된 날짜("13/9/2026")를
//   넣으면 JS 는 그것을 **미국식 M/D/Y 로 읽는다**:
//     · 13~31 일 → 월이 13 이상이라 `Invalid Date` → 손님 종이에 "Invalid Date" 가 찍힌다.
//     · 1~12 일  → **조용히 월과 일이 뒤바뀐다.** "5/9/2026" 은 9월 5일이 아니라
//       5월 9일이 된다. 이쪽이 더 나쁘다 — 틀린 줄 아무도 모른다.
//   실제로 print-agent 의 `buildTestTicketData` 가 그 형식을 보내고 있었다.
//
// 그래서 파싱은 **형식을 명시해서** 한다:
//   ① ISO(서버 `buildInvoiceData` 가 보내는 형식) — 이것이 정상 경로다.
//   ② dd/mm/yyyy[ hh:mm[:ss]] — 옛 클라이언트가 보낸 es-AR 문자열의 구제 경로.
//   ③ 그 외 / 파싱 실패 → `null`.
//
// ★ 폴백을 **호출부에서** 정한다. 이 함수는 "모르겠다" 를 null 로 말할 뿐이다 —
//   여기서 now 로 바꿔 버리면 "날짜가 없었다" 와 "날짜가 깨졌다" 를 구분할 수 없다.
function parseTicketDate(raw) {
  if (raw instanceof Date) {
    return Number.isNaN(raw.getTime()) ? null : raw;
  }
  if (typeof raw === 'number' && Number.isFinite(raw)) {
    const d = new Date(raw);

    return Number.isNaN(d.getTime()) ? null : d;
  }
  if (typeof raw !== 'string') return null;

  const s = raw.trim();
  if (!s) return null;

  // ② dd/mm/yyyy — 슬래시 형식은 **반드시 먼저** 잡는다. Date 생성자에 넘기면
  //    미국식으로 읽히기 때문이다.
  const m = s.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})(?:[ ,]+(\d{1,2}):(\d{2})(?::(\d{2}))?)?$/);
  if (m) {
    const [, dd, mm, yyyy, hh, mi, ss] = m;
    const day = Number(dd), month = Number(mm);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    const d = new Date(
      Number(yyyy), month - 1, day,
      Number(hh || 0), Number(mi || 0), Number(ss || 0),
    );

    // 롤오버 검사 — "31/02/2026" 은 3월 3일로 넘어간다. 넘어갔으면 없는 날짜다.
    if (d.getFullYear() !== Number(yyyy) || d.getMonth() !== month - 1 || d.getDate() !== day) {
      return null;
    }

    return d;
  }

  // ① ISO 및 Date 가 확실히 아는 형식
  const d = new Date(s);

  return Number.isNaN(d.getTime()) ? null : d;
}

// ★★ [2026-09-09 · codex 지적] **「날짜가 없다」와 「날짜가 깨졌다」는 다르게 다룬다.**
//
//   처음 고칠 때는 파싱 실패를 전부 `new Date()` 로 덮었다. 그러면 «Invalid Date» 는
//   사라지지만 **더 나쁜 것**이 남는다 — 손님 종이에 **그럴듯하지만 틀린 날짜**가
//   찍히고, 아무도 이상하다고 신고하지 않는다. 재인쇄·지연 인쇄에서는 판매일이
//   인쇄일로 바뀌어 버린다.
//
//   그래서:
//     · 날짜 필드가 **없다**(레거시 payload) → 지금 시각. 종전 동작이고 근거도 있다.
//       (서버 `buildInvoiceData` 는 항상 보내므로, 없는 것은 옛 클라이언트뿐이다.)
//     · 날짜가 **있는데 못 읽는다** → 날짜를 **만들어내지 않는다.** `—` 를 찍는다.
//       종이에 빈칸이 보이면 사람이 신고한다. 조용히 틀린 값보다 낫다.
function renderTicketDate(raw) {
  const provided = raw !== undefined && raw !== null && String(raw).trim() !== '';
  const parsed = parseTicketDate(raw);

ventago-app/src/components/reminders/MidnightCajaReminder.tsx:57:      localStorage.setItem(STORAGE_KEY, JSON.stringify({ date: getNightKey(), action }));
ventago-app/src/layouts/components/vertical/SidebarFooter.tsx:137:        setUnclosedAlert(t('sidebar_unclosed_cash', { date: res.unclosedPrevious.date }));
ventago-app/src/layouts/components/vertical/SidebarFooter.tsx:418:              {t('sidebar_trial_expires', { date: formattedDate })}
ventago-app/src/@fake-db/types.ts:56:  date: string
ventago-app/src/@fake-db/types.ts:160:  start_date: string
ventago-app/src/pages/herramientas/print-agent/index.tsx:374:  revalidate: number;
ventago-app/src/pages/herramientas/print-agent/index.tsx:416:    revalidate: 300,
ventago-app/src/layouts/components/util.ts:7:  date: string;
ventago-app/src/__tests__/madre-payload.spec.ts:167:    return mod.fetchStockBaseline({ productId: 1, branchId: 2, date: '2026-08-14' })
ventago-app/src/components/team-chat/TeamChatPanel.tsx:134:  const formatTime = (date: string) => {
ventago-app/src/components/modals/SelectBoxTerminalModal.tsx:30:  date: string;
ventago-app/src/hooks/api/useActivity.ts:39:export function useUserActivity(userId: number | null, date: string) {
ventago-app/src/context/types.ts:64:  permissions?: Record<string, { create: boolean; read: boolean; update: boolean; delete: boolean }> | null;
ventago-app/src/hooks/api/useDailySalesStats.ts:22:  date: string
ventago-app/src/hooks/api/useAttendanceQr.ts:6:  date: string
ventago-app/src/hooks/api/useAfipEmitidas.ts:4:export function useAfipEmitidas(date: string) {
ventago-app/src/types/apps/emailTypes.ts:35:  dataToUpdate: { folder?: MailFolderType; isStarred?: boolean; isRead?: boolean; label?: MailLabelType }
ventago-app/src/types/apps/emailTypes.ts:155:  handleLabelUpdate: (id: number | number[], label: MailLabelType) => void
ventago-app/src/types/apps/emailTypes.ts:156:  handleFolderUpdate: (id: number | number[], folder: MailFolderType) => void
ventago-app/src/types/apps/calendarTypes.ts:90:  handleCalendarsUpdate: (val: CalendarFiltersType) => void
ventago-app/src/views/components/NoticesBanner.tsx:23:      { revalidate: false }
ventago-app/src/@core/utils/format.ts:12:const isToday = (date: Date | string) => {
ventago-app/src/views/box/components/CajasOverviewCard.tsx:39:  date: string | null
ventago-app/src/views/talleres/vendors/components/talleres_VendorDetailPanel.tsx:25:  onUpdate: () => void;
ventago-app/src/views/cash-control/list/components/CashControlFilters.tsx:23:      date: '',
ventago-app/src/views/codigo-vista/VariationPanel.tsx:109:        date: new Date().toISOString().slice(0, 10),
ventago-app/src/views/cash-control/detail/box-register/components/BoxControlFilters.tsx:7:    date: string;
ventago-app/src/views/cash-control/detail/box-register/components/BoxControlFilters.tsx:27:            onChange={e => setFilters((f: any) => ({ ...f, date: e.target.value }))}
ventago-app/src/views/cash-control/detail/box-register/BoxControlDetail.tsx:18:  const [filters, setFilters] = useState<{ date: string; userId: string; terminalId: string }>({ date: today, userId: '', terminalId: '' });
ventago-app/src/views/cash-control/detail/box-register/BoxControlDetail.tsx:26:      const params: any = { date: filters.date, page, pageSize };
ventago-app/src/views/talleres/components/constants.ts:219:    date: string
ventago-app/src/views/sales/list/components/DailySalesStats.tsx:133:                  date: startDate,
ventago-app/src/views/ventas-online/components/EnvioTimeline.tsx:287:          invoice: { client: order.clientName || 'Consumidor Final' },
ventago-app/src/views/caja-fuerte/components/CajaFuerteDiario.tsx:23:  date: string;
ventago-app/src/views/caja-fuerte/components/ModalWithdrawal.tsx:143:            setValue('amount', fresh.balance > 0 ? fresh.balance : 0, { shouldValidate: true });
ventago-app/src/views/caja-fuerte/components/ModalWithdrawal.tsx:209:        setValue('amount', Number(body.currentBalance), { shouldValidate: true });
ventago-app/src/views/caja-fuerte/components/ModalWithdrawal.tsx:300:                // shouldValidate: 칩만 눌러도 폼이 유효해져야 한다(사유는 필수 필드다)
ventago-app/src/views/caja-fuerte/components/ModalWithdrawal.tsx:301:                setValue('reason', m, { shouldValidate: true, shouldDirty: true });
ventago-app/src/views/talleres/cut-ticket/CutTicketTab.tsx:184:            // revalidate: true 로 설정해 백그라운드에서 재확인 (stale-while-revalidate)
ventago-app/src/views/talleres/cut-ticket/CutTicketTab.tsx:186:              mutate(data, { revalidate: true })
ventago-app/src/views/homes/components/ProductList/components/PaymentSummary.tsx:106:      invoice: {
ventago-app/src/views/homes/components/SaleReview/SaleReviewPanel.tsx:293:      invoice: {
ventago-app/src/views/profile/components/UserProfileHeader.tsx:20:  const getJoinDate = (date: string) => {
ventago-app/src/views/products/list/stock-baseline.ts:101:  date: string
ventago-app/src/views/homes/components/ProductList/ProductList.tsx:2007:            invoice: {
ventago-app/src/views/homes/components/ProductList/ProductList.tsx:2013:              date:   issuedAt.toLocaleDateString('es-AR'),
ventago-app/src/views/homes/components/ProductList/ProductList.tsx:2478:                  invoice: {
ventago-app/src/views/products/list/components/ProductsList.tsx:25:  setSelectedDate: (date: string) => void;
ventago-app/src/views/products/list/components/ProductsList.tsx:171:      console.log('[ProductsList] delete today stock', { parentId: row.id, date: selectedDate, res })
ventago-app/src/views/facturacion/PartialInvoiceModal.tsx:204:          date: new Date().toLocaleDateString('es-AR'),
ventago-app/src/views/products/list/components/ProductParentList.tsx:257:      const baseline = await fetchStockBaseline({ productId: parentId, branchId, date: checkDate });
ventago-app/src/views/whatsapp/WhatsAppSendDialog.tsx:439:    date: '08/05/2026',
ventago-app/src/views/products/list/ProductsView.tsx:171:            { date: checkDate, branchId: branchScope },
ventago-app/src/views/products/list/ProductsView.tsx:175:            { date: checkDate },
ventago-app/src/views/products/list/ProductsView.tsx:461:      const baseline = await fetchStockBaseline({ productId, branchId, date: selectedDate });
ventago-app/src/views/products/list/ProductsView.tsx:721:    fetchStockBaseline({ productId, branchId: newBranchId, date: selectedDate })
ventago-app/src/views/products/list/ProductsView.tsx:828:        date: selectedDate || new Date().toISOString().slice(0, 10),
ventago-app/src/views/products/list/ProductsView.tsx:1130:          date: selectedDate, // 백엔드가 stocks.operation_date 로 저장 (백데이트 입고 지원)
ventago-app/src/views/products/list/ProductsView.tsx:1215:          date: selectedDate,
ventago-app/src/views/products/list/ProductsView.tsx:1442:          date: selectedDate,
ventago-app/src/views/expenses/components/DataConfig.tsx:62:  date: yup.date() .typeError("La fecha es requerida") .required("La fecha es requerida"),
ventago-app/src/views/expenses/components/DataConfig.tsx:79:  date: localToday,
ventago-app/src/views/expenses/components/ExpenseModal.tsx:287:          date: data.date,
ventago-app/src/views/expenses/components/ExpenseModal.tsx:376:                onChange={(id) => setValue('categoryId', id, { shouldValidate: true, shouldDirty: true })}
ventago-app/src/views/branches/components/wp/WpConfigTab.tsx:308:  const fmt = (date: string | null) => {
ventago-app/src/views/branches/components/agents/DataConfig.tsx:7:const formatLastSeen = (date: string | null): string => {
ventago-app/src/views/admin/audit/components/DataConfig.tsx:158:export const formatDate = (date: string) => {
ventago-app/src/views/admin/audit/components/DataConfig.tsx:162:    date: d.toLocaleDateString('es-ES'),
ventago-app/src/views/users/roles/components/CrudActionRow.tsx:7:  update: { label: 'U', color: 'warning' as const, tooltip: 'Editar', ariaAction: 'UPDATE' },
ventago-app/src/views/branches/components/printer/PrinterConfigTab.tsx:316:  const formatLastSeen = (date: string | null) => {
ventago-app/src/views/users/roles/helpers/groupByResource.ts:24:    update: number[]
ventago-app/src/views/users/roles/helpers/groupByResource.ts:130:      update: [],
ventago-app/src/views/users/roles/helpers/groupByResource.ts:174:      crudMap: { create: [], read: [ba.functionId], update: [], delete: [] },
451:  .banner {
462:  .store-header {
489:  .ticket-meta {
502:  .meta-row {
710:  <div class="meta-row">
714:  <div class="meta-row">
718:  <div class="meta-row">
723:  <div class="meta-row">
728:  <div class="meta-row">
733:  <div class="meta-row">
950:  .banner {
960:  .banner-nofiscal {
985:  .store-header {
995:  .ticket-meta {
1001:  .presupuesto-title {
1008:  .meta-row { display: flex; justify-content: space-between; }
1139:    ? '<div class="presupuesto-title">Venta sin conexión</div>'
1141:      ? `<div class="presupuesto-title">Venta # ${data.invoice.number || data.invoice.id}</div>`
1142:      : '<div class="presupuesto-title">Presupuesto</div>'}
1146:  <div class="meta-row">
1150:  <div class="meta-row">
1155:  <div class="meta-row">
1159:  <div class="meta-row">
1164:  <div class="meta-row">
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
    }
  }
}
offline-ticket.smoke.js
print-dedup.smoke.js
qr-formatter.smoke.js
ticket-date.smoke.js
ticket-uniform.smoke.js

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
/bin/zsh -lc "sed -n '85,125p' ventago-app/src/views/homes/components/ProductList/components/PaymentSummary.tsx; sed -n '3110,3190p' api-ventago/src/app/sales/sales-create.service.ts; sed -n '440,525p' print-agent/src/formatter.js; sed -n '940,1020p' print-agent/src/formatter.js; node print-agent/test/ticket-uniform.smoke.js; node print-agent/test/offline-ticket.smoke.js; node print-agent/test/ticket-date.smoke.js; nl -ba print-agent/src/formatter.js | sed -n '415,430p;685,725p;845,860p;1135,1165p'; nl -ba ventago-app/src/views/homes/components/ProductList/ProductList.tsx | sed -n '2005,2020p'; nl -ba print-agent/test/ticket-uniform.smoke.js | sed -n '60,95p'" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 4ms:
  2005	              phone:   (user as any)?.storePhone || '-',
  2006	            },
  2007	            invoice: {
  2008	              // 티켓에는 당일 순번(dailyNumber)을 인쇄한다. sales.number 컬럼은 존재하지 않아
  2009	              // 기존 코드는 항상 전역 PK(id) 로 폴백돼 "Venta # 71" 처럼 찍혔다.
  2010	              // 레거시 행(daily_number = 0/null)만 id 로 폴백.
  2011	              number: createdSale?.dailyNumber || createdSale?.id || null,
  2012	              id:     createdSale?.id || null,
  2013	              date:   issuedAt.toLocaleDateString('es-AR'),
  2014	              time:   issuedAt.toLocaleTimeString('es-AR'),
  2015	              seller: selectedSeller?.name || (user as any)?.fullName || (user as any)?.name || '-',
  2016	
  2017	              // selectedClient 는 fullname 속성을 가진다(InfoClient/useSaleProducts). 과거 .name 만 읽어
  2018	              // 항상 'Consumidor Final' 로 폴백돼 티켓에 실제 고객명이 찍히지 않았다. fullname 우선.
  2019	              client: selectedClient?.fullname || (selectedClient as any)?.name || 'Consumidor Final',
  2020	            },
    60	// ── ② 날짜·시각은 둘 다 «Fecha»/«Hora» 라벨 행 ─────────────────────────────
    61	for (const [nombre, html] of [['F2', f2], ['reimpresión', reimpre]]) {
    62	  assert(html.includes('>Fecha<'), `${nombre}: fila Fecha`);
    63	  assert(html.includes('>Hora<'), `${nombre}: fila Hora`);
    64	  // 제목 줄에 다시 인라인으로 붙으면 안 된다 (그게 종전 F2 의 모양이었다).
    65	  assert(!/presupuesto-title">[^<]*—[^<]*\d{2}\/\d{2}\/\d{4}/.test(html),
    66	    `${nombre}: la fecha no vuelve al título`);
    67	}
    68	
    69	// ── ③ 같은 판매면 같은 날짜·시각 ────────────────────────────────────────────
    70	// F2 는 종전에 `new Date()`(인쇄 시각)를 썼다 — 즉시 찍으면 안 보이지만
    71	// /print/temp 를 쓰는 다른 경로는 며칠 전 판매를 찍는다.
    72	assert(f2.includes('23/09/2026') && reimpre.includes('23/09/2026'),
    73	  'ambos toman la fecha de invoice.date');
    74	assert(f2.includes('12:21:29') && reimpre.includes('12:21:29'),
    75	  'ambos toman la hora de invoice.date');
    76	
    77	// ── ④ 기본 꼬리 문구가 같다 ─────────────────────────────────────────────────
    78	for (const linea of ['¡Gracias por su compra!', 'Conserve este comprobante']) {
    79	  assert(f2.includes(linea), `F2: pie «${linea}»`);
    80	  assert(reimpre.includes(linea), `reimpresión: pie «${linea}»`);
    81	}
    82	// 매장별 문구는 서버가 `footer.extra` 로 싣는다 — 에이전트에 박아 두지 않는다.
    83	assert(!reimpre.includes('falla de fábrica'),
    84	  'la política de una tienda no va hardcodeada en el agente');
    85	
    86	// ── ⑤ 대조군 — 매장이 설정한 문구는 여전히 나간다 ───────────────────────────
    87	const conExtra = formatInvoiceHtml({ ...base, footer: { extra: ['@mitienda', 'Cambios: Lun-Vie'] } });
    88	assert(conExtra.includes('@mitienda'), 'control: footer.extra sigue imprimiéndose');
    89	
    90	console.log('ticket-uniform smoke OK');

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
/bin/zsh -lc "rg -n \"footer1|footer2|footer-main|renderFooterExtra\" print-agent/src/formatter.js; nl -ba print-agent/test/ticket-uniform.smoke.js | sed -n '35,90p'; nl -ba ventago-app/src/views/homes/components/SaleReview/SaleReviewPanel.tsx | sed -n '285,305p'; nl -ba ventago-app/src/views/ventas-online/components/EnvioTimeline.tsx | sed -n '278,292p'; nl -ba ventago-app/src/services/print.service.ts | sed -n '1,25p'; git diff --check; git status --short" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 3941ms:
2026-09-23 13:04:35.034 xcodebuild[43027:3177356]  DVTFilePathFSEvents: Failed to start fs event stream.
2026-09-23 13:04:35.230 xcodebuild[43027:3177353] [MT] DVTDeveloperPaths: Failed to get length of DARWIN_USER_CACHE_DIR from confstr(3), error = Error Domain=NSPOSIXErrorDomain Code=5 "Input/output error". Using NSCachesDirectory instead.
git: warning: confstr() failed with code 5: couldn't get path of DARWIN_USER_TEMP_DIR; using /tmp instead
git: error: couldn't create cache file '/tmp/xcrun_db-OBZZA4EY' (errno=Operation not permitted)
2026-09-23 13:04:35.713 xcodebuild[43035:3177378]  DVTFilePathFSEvents: Failed to start fs event stream.
2026-09-23 13:04:35.806 xcodebuild[43035:3177377] [MT] DVTDeveloperPaths: Failed to get length of DARWIN_USER_CACHE_DIR from confstr(3), error = Error Domain=NSPOSIXErrorDomain Code=5 "Input/output error". Using NSCachesDirectory instead.
git: warning: confstr() failed with code 5: couldn't get path of DARWIN_USER_TEMP_DIR; using /tmp instead
git: error: couldn't create cache file '/tmp/xcrun_db-bSRawPmr' (errno=Operation not permitted)
2026-09-23 13:04:36.782 xcodebuild[43062:3177498]  DVTFilePathFSEvents: Failed to start fs event stream.
2026-09-23 13:04:36.871 xcodebuild[43062:3177487] [MT] DVTDeveloperPaths: Failed to get length of DARWIN_USER_CACHE_DIR from confstr(3), error = Error Domain=NSPOSIXErrorDomain Code=5 "Input/output error". Using NSCachesDirectory instead.
git: warning: confstr() failed with code 5: couldn't get path of DARWIN_USER_TEMP_DIR; using /tmp instead
git: error: couldn't create cache file '/tmp/xcrun_db-Udw68xvL' (errno=Operation not permitted)
2026-09-23 13:04:37.298 xcodebuild[43091:3177585]  DVTFilePathFSEvents: Failed to start fs event stream.
2026-09-23 13:04:37.390 xcodebuild[43091:3177584] [MT] DVTDeveloperPaths: Failed to get length of DARWIN_USER_CACHE_DIR from confstr(3), error = Error Domain=NSPOSIXErrorDomain Code=5 "Input/output error". Using NSCachesDirectory instead.
 M .claude/hooks/.gsd-snapshot.json
 M .planning/STATE.md
 M print-agent/src/formatter.js
 M print-agent/test/offline-ticket.smoke.js
?? ".planning/ANALISIS-2026-09-17-legacy-vcontrolgrid2-\352\262\251\354\260\250\353\266\204\354\204\235.md"
?? .planning/GUIA-miguel-acceso-servidor2.md
?? ".planning/PLAN-2026-09-16-\354\204\234\353\262\204-\353\266\204\353\246\254\354\231\200-\354\213\240\352\267\234-\354\235\264\354\240\204.md"
?? .planning/SETUP-2026-08-26-servidor2-74.208.60.137.md
?? .team/reviews/.manual-89-diseno.prompt
?? .team/reviews/.manual-money.prompt
?? .team/reviews/auto-.-c44b566.md
?? .team/reviews/auto-api-ventago-0100d26.md
?? .team/reviews/auto-api-ventago-06a888ff_ventago-app-afbcbf3.md
?? .team/reviews/auto-api-ventago-0748b9a2.md
?? .team/reviews/auto-api-ventago-1058cc89.md
?? .team/reviews/auto-api-ventago-1152e1f6.md
?? .team/reviews/auto-api-ventago-18ba95a.md
?? .team/reviews/auto-api-ventago-1a3bcf9.md
?? .team/reviews/auto-api-ventago-21ee29d.md
?? .team/reviews/auto-api-ventago-25f0ecb0.md
?? .team/reviews/auto-api-ventago-282c86d6.md
?? .team/reviews/auto-api-ventago-29480476.md
?? .team/reviews/auto-api-ventago-3504e05.md
?? .team/reviews/auto-api-ventago-35b0727.md
?? .team/reviews/auto-api-ventago-3635b207_ventago-app-375d3f2.md
?? .team/reviews/auto-api-ventago-425a17d.md
?? .team/reviews/auto-api-ventago-4a17657.md
?? .team/reviews/auto-api-ventago-4ec4109.md
?? .team/reviews/auto-api-ventago-50459e81.md
?? .team/reviews/auto-api-ventago-55f92a09.md
?? .team/reviews/auto-api-ventago-580f24a9.md
?? .team/reviews/auto-api-ventago-597bdd21.md
?? .team/reviews/auto-api-ventago-59c7cc5.md
?? .team/reviews/auto-api-ventago-632c6780.md
?? .team/reviews/auto-api-ventago-64564cd6.md
?? .team/reviews/auto-api-ventago-668b650.md
?? .team/reviews/auto-api-ventago-66c67888.md
?? .team/reviews/auto-api-ventago-6a9d579_ventago-app-c98f001.md
?? .team/reviews/auto-api-ventago-6b66516.md
?? .team/reviews/auto-api-ventago-6ee2d011.md
?? .team/reviews/auto-api-ventago-6f0a8f4.md
?? .team/reviews/auto-api-ventago-754af978.md
?? .team/reviews/auto-api-ventago-7731d9bd.md
?? .team/reviews/auto-api-ventago-773e6240.md
?? .team/reviews/auto-api-ventago-777e9de.md
?? .team/reviews/auto-api-ventago-77b88753.md
?? .team/reviews/auto-api-ventago-7fc0a74.md
?? .team/reviews/auto-api-ventago-833aacf2.md
?? .team/reviews/auto-api-ventago-853b72ab.md
?? .team/reviews/auto-api-ventago-857ace55.md
?? .team/reviews/auto-api-ventago-94d8502.md
?? .team/reviews/auto-api-ventago-9eba587.md
?? .team/reviews/auto-api-ventago-9f759f15.md
?? .team/reviews/auto-api-ventago-a306d98.md
?? .team/reviews/auto-api-ventago-a3529d83.md
?? .team/reviews/auto-api-ventago-a36e84f_ventago-app-3cb66fe.md
?? .team/reviews/auto-api-ventago-a4543fb.md
?? .team/reviews/auto-api-ventago-aa2dc54.md
?? .team/reviews/auto-api-ventago-b3d65374_ventago-app-30b1b95.md
?? .team/reviews/auto-api-ventago-b4f34a9a_ventago-app-9573e76.md
?? .team/reviews/auto-api-ventago-bfa7695.md
?? .team/reviews/auto-api-ventago-c02b018.md
?? .team/reviews/auto-api-ventago-c0585fac.md
?? .team/reviews/auto-api-ventago-c0da8ce3.md
?? .team/reviews/auto-api-ventago-c325b48.md
?? .team/reviews/auto-api-ventago-d4d1f715.md
?? .team/reviews/auto-api-ventago-d5b36a0.md
?? .team/reviews/auto-api-ventago-d7f3d10.md
?? .team/reviews/auto-api-ventago-dc80c95.md
?? .team/reviews/auto-api-ventago-dce04cb.md
?? .team/reviews/auto-api-ventago-de4a318f.md
?? .team/reviews/auto-api-ventago-df2ce772.md
?? .team/reviews/auto-api-ventago-e09c69a.md
?? .team/reviews/auto-api-ventago-ea8b563f.md
?? .team/reviews/auto-api-ventago-eb118343.md
?? .team/reviews/auto-api-ventago-f00005c_ventago-app-72564f4.md
?? .team/reviews/auto-api-ventago-f0380fd.md
?? .team/reviews/auto-api-ventago-f30b2ff5.md
?? .team/reviews/auto-api-ventago-f36b3633.md
?? .team/reviews/auto-api-ventago-f45d4ce.md
?? .team/reviews/auto-api-ventago-f770585f.md
?? .team/reviews/auto-api-ventago-fb8b4f6f.md
?? .team/reviews/auto-manual-89-root-bcc975f..694041e_api-ventago-1152e1f6..2c7201a2_ventago-app-fe69bdc..5931ca9.md
?? .team/reviews/auto-root-08c4868_api-ventago-adfe292e.md
?? .team/reviews/auto-root-09a7240_api-ventago-1c9d7abd_ventago-app-8aab1a3.md
?? .team/reviews/auto-root-19ec460_ventago-app-fe69bdc.md
?? .team/reviews/auto-root-22c651d_api-ventago-b4d9ad8.md
?? .team/reviews/auto-root-2a9328a_api-ventago-3138dc48.md
?? .team/reviews/auto-root-33dbd94_api-ventago-3840f54f.md
?? .team/reviews/auto-root-378f116.md
?? .team/reviews/auto-root-3fec244_ventago-app-57d99ec.md
?? .team/reviews/auto-root-411425a.md
?? .team/reviews/auto-root-42ebfa8.md
?? .team/reviews/auto-root-432a75a_api-ventago-0da64b9c.md
?? .team/reviews/auto-root-47a50a0_api-ventago-62f2988.md
?? .team/reviews/auto-root-4854608.md
?? .team/reviews/auto-root-4d715b0.md
?? .team/reviews/auto-root-521a4cf_api-ventago-d1eaa8b6.md
?? .team/reviews/auto-root-5386cbd_api-ventago-7eda8f6e.md
?? .team/reviews/auto-root-5457333.md
?? .team/reviews/auto-root-55e1704_api-ventago-670810d8.md
?? .team/reviews/auto-root-58ff2f0_ventago-app-c14b7c3.md
?? .team/reviews/auto-root-5bfcdc2_ventago-app-964a64f.md
?? .team/reviews/auto-root-5c51654_api-ventago-7058340.md
?? .team/reviews/auto-root-5de413f_api-ventago-7d74ca88.md
?? .team/reviews/auto-root-5e21236_ventago-app-89843d4.md
?? .team/reviews/auto-root-6028fde.md
?? .team/reviews/auto-root-626e9d8_api-ventago-66ad6c9d.md
?? .team/reviews/auto-root-63a228b.md
?? .team/reviews/auto-root-63b6671_api-ventago-94fb796.md
?? .team/reviews/auto-root-68a0f48.md
?? .team/reviews/auto-root-697b267.md
?? .team/reviews/auto-root-6bb77cb_api-ventago-66d3a16b.md
?? .team/reviews/auto-root-6bdfdcb_ventago-app-55ad5d7.md
?? .team/reviews/auto-root-6d486bb_ventago-app-2288179.md
?? .team/reviews/auto-root-6f3fafb_api-ventago-6ce906a_ventago-app-36cdff4.md
?? .team/reviews/auto-root-721fb49_api-ventago-fee04b3f_ventago-app-1443ce1.md
?? .team/reviews/auto-root-73f151f_api-ventago-4a73ab7.md
?? .team/reviews/auto-root-75ba1db_api-ventago-dbd8e417.md
?? .team/reviews/auto-root-7887027.md
?? .team/reviews/auto-root-7e534c9.md
?? .team/reviews/auto-root-7ffa413_api-ventago-b1a5caf_ventago-app-9591702.md
?? .team/reviews/auto-root-8138b91_api-ventago-f8f5c55.md
?? .team/reviews/auto-root-82b4d8c_ventago-app-86e66dd.md
?? .team/reviews/auto-root-83e89ab_ventago-app-3e7aae8.md
?? .team/reviews/auto-root-840bc21.md
?? .team/reviews/auto-root-8dba188_api-ventago-91779fd.md
?? .team/reviews/auto-root-8f898a8.md
?? .team/reviews/auto-root-90589fa_api-ventago-2039a599_ventago-app-d3c93bc.md
?? .team/reviews/auto-root-98313e8_api-ventago-04b7df2.md
?? .team/reviews/auto-root-9bfb6c0.md
?? .team/reviews/auto-root-9d9d384_api-ventago-36838e02.md
?? .team/reviews/auto-root-a111972.md
?? .team/reviews/auto-root-a518fa4_api-ventago-70301b2f.md
?? .team/reviews/auto-root-ab3d9b4_ventago-app-aa9bbb2.md
?? .team/reviews/auto-root-ac27be6_api-ventago-02627644.md
?? .team/reviews/auto-root-b0482ed.md
?? .team/reviews/auto-root-b0ffdc0_api-ventago-14b62419_ventago-app-2127d6e.md
?? .team/reviews/auto-root-b3a0fdf.md
?? .team/reviews/auto-root-b5dc3a9_api-ventago-b92e599d.md
?? .team/reviews/auto-root-b6d5267.md
?? .team/reviews/auto-root-babdf1f.md
?? .team/reviews/auto-root-bbf6d1f_api-ventago-cc15268.md
?? .team/reviews/auto-root-bcc975f.md
?? .team/reviews/auto-root-cbd2c33.md
?? .team/reviews/auto-root-cbecb15_api-ventago-f0c2510c.md
?? .team/reviews/auto-root-cd1aa02.md
?? .team/reviews/auto-root-cdb6d94_api-ventago-b0233b6.md
?? .team/reviews/auto-root-d002590.md
?? .team/reviews/auto-root-d176110_api-ventago-ca25e19.md
?? .team/reviews/auto-root-d178e3d.md
?? .team/reviews/auto-root-d386412_api-ventago-39c3ffb.md
?? .team/reviews/auto-root-d71925e_ventago-app-54e6247.md
?? .team/reviews/auto-root-d914335_api-ventago-2a0fe93f_ventago-app-f9a295b.md
?? .team/reviews/auto-root-de35c1c_api-ventago-c6eb194d_ventago-app-cf8c9e0.md
?? .team/reviews/auto-root-e3a69e0.md
?? .team/reviews/auto-root-e5db900_api-ventago-1fac5fac_ventago-app-231278b.md
?? .team/reviews/auto-root-e73dfed.md
?? .team/reviews/auto-root-ebf072e.md
?? .team/reviews/auto-root-edbc743_api-ventago-2622468.md
?? .team/reviews/auto-root-f2c0b38_ventago-app-c354ba0.md
?? .team/reviews/auto-root-f6ba6ea_api-ventago-2522635.md
?? .team/reviews/auto-root-f952fbb_api-ventago-b9bcfa58.md
?? .team/reviews/auto-root-fe36fb9_api-ventago-c5a709f.md
?? .team/reviews/auto-ventago-app-0f2ff49.md
?? .team/reviews/auto-ventago-app-3219faf.md
?? .team/reviews/auto-ventago-app-3cc1782.md
?? .team/reviews/auto-ventago-app-6a877d5.md
?? .team/reviews/auto-ventago-app-88c7b7c.md
?? .team/reviews/auto-ventago-app-908bd19.md
?? .team/reviews/auto-ventago-app-b0da036.md
?? .team/reviews/auto-ventago-app-b80335b.md
?? .team/reviews/auto-ventago-app-df9dbbe.md
?? .team/reviews/auto-ventago-app-e2bf728.md
?? .team/reviews/auto-ventago-app-fa9e8fc.md
?? .team/reviews/commit-32744e5c-codex.md
?? .team/reviews/manual-57-F1F5-282c86d6.md
?? .team/reviews/manual-57-F3b-F6-833aacf2.md
?? .team/reviews/manual-89-diseno.md
?? .team/reviews/manual-91-05-dp-front-r2.md
?? .team/reviews/manual-91-05-dp-front.md
?? .team/reviews/manual-comanda-e9cf727_c9a9850.md
?? .team/reviews/manual-contract-onboarding-bee7279.md
?? .team/reviews/manual-manuales-06b806d5.md
?? .team/reviews/manual-money-double-52b14e3.md
?? .team/reviews/manual-p2-caja-fuerte-c628bfb.md
?? .team/reviews/manual-phase93-codex.md
?? .team/reviews/manual-pos-footer-f340eaf.md
?? .team/reviews/manual-precio-codex.md
?? .team/reviews/manual-ticket-uniform-codex.md
?? .team/reviews/phase86-partial-upload-codex-2026-08-25.md
?? .team/reviews/phase88-codex.md
?? .team/reviews/phase88-w1w2-codex-prompt.md
?? .team/reviews/phase88-w1w2-codex.md
?? "Claude outputs/"
?? legacy-query-mcp.zip
?? legacy-query-mcp/
?? "manuales/ACE III Online \354\213\234\354\212\244\355\205\234 \354\264\210\352\270\260 \354\205\213\354\227\205\355\225\230\352\270\260.docx"
?? "manuales/ACE III Online \354\213\234\354\212\244\355\205\234 \354\264\210\352\270\260 \354\205\213\354\227\205\355\225\230\352\270\260.pdf"
?? print-agent/test/ticket-uniform.smoke.js
?? scripts/pg-lan-access.sh
?? scripts/server2-setup.sh

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
hook: PostToolUse
hook: PostToolUse
hook: PostToolUse Failed
hook: PostToolUse Completed
codex
[HIGH] [ventago-app/src/views/homes/components/ProductList/ProductList.tsx:2013](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/ventago-app/src/views/homes/components/ProductList/ProductList.tsx:2013) — 실제 F2는 판매 시각 대신 항상 `00:00:00`을 출력한다

  문제: F2 payload는 날짜와 시간을 `invoice.date`, `invoice.time`으로 분리한다. 변경된 formatter는 `invoice.date`만 파싱하므로 `23/09/2026`이 해당 날짜의 자정으로 해석된다. 사용자가 요구한 Hora 행은 생기지만 값이 틀린다.

  근거:

  ```js
  date: issuedAt.toLocaleDateString('es-AR'),
  time: issuedAt.toLocaleTimeString('es-AR'),
  ```

  반면 [formatter.js:857](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/print-agent/src/formatter.js:857)은 다음만 사용한다.

  ```js
  renderTicketDate(data.invoice?.date)
  ```

  실제 payload 형태를 넣으면 `Fecha 23/09/2026`, `Hora 00:00:00`이 된다.

  수정: `renderTicketDate`가 `date`와 `time`을 함께 받게 하거나, F2에서 `invoice.date`를 ISO 문자열 하나로 보내라. 테스트도 현재의 합성 ISO payload가 아니라 실제 `{ date: '23/09/2026', time: '12:21:29' }` 형태로 추가해야 한다.

[MEDIUM] [SaleReviewPanel.tsx:293](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/ventago-app/src/views/homes/components/SaleReview/SaleReviewPanel.tsx:293) — 과거 판매 재출력 경로가 여전히 판매일이 아니라 인쇄일을 출력한다

  문제: 변경 주석은 `SaleReviewPanel`과 `EnvioTimeline`의 과거 판매 날짜를 바로잡는다고 설명하지만, 두 payload 모두 `invoice.date`를 보내지 않는다. 따라서 `renderTicketDate(undefined)`가 현재 시각으로 폴백하며 종전 동작이 그대로 남는다.

  근거:

  ```js
  invoice: {
    number: currentSale?.dailyNumber || currentSale?.id || undefined,
    seller: ...,
    client: ...,
  }
  ```

  [EnvioTimeline.tsx:287](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/ventago-app/src/views/ventas-online/components/EnvioTimeline.tsx:287)도 동일하다.

  ```js
  invoice: { client: order.clientName || 'Consumidor Final' }
  ```

  수정: 각 경로에서 실제 판매/주문 생성시각을 `invoice.date`로 전달해야 한다. 날짜를 알 수 없는 진짜 견적·주방 comanda만 “현재 시각” 폴백을 유지하는 편이 맞다.

  질문 2에 대한 직접 답변: 현재 확인한 실제 callsite 중 `—`가 새로 출력되는 payload는 없다. 날짜 미전달 경로는 현재 시각으로 폴백하고, F2의 `dd/mm/yyyy`도 유효하게 파싱된다. `—`는 비어 있지 않은 잘못된 날짜가 들어올 때만 나온다. 그 경우 틀린 날짜를 만들어내는 것보다 `—`가 적절하다. 실제 회귀는 `—`가 아니라 위의 `00:00:00`과 과거 경로의 “현재 날짜”다.

[LOW] [ticket-uniform.smoke.js:69](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/print-agent/test/ticket-uniform.smoke.js:69) — 테스트의 날짜 fixture가 실제 F2 계약과 달라 핵심 회귀를 놓친다

  문제: 테스트는 `invoice.date: '2026-09-23T12:21:29'` 한 필드만 사용한다. 그래서 실제 F2의 분리된 `date/time` 계약을 깨뜨린 현재 구현도 통과한다.

  수정: 실제 F2 payload를 그대로 사용하는 케이스를 추가하고 `Hora` 행의 값이 `invoice.time`과 같음을 검사하라. `TempTicketPayload.invoice` 타입에도 `date`와 `time`을 선언해야 계약 이탈을 컴파일 단계에서 잡을 수 있다.

[LOW] [ticket-uniform.smoke.js:51](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/print-agent/test/ticket-uniform.smoke.js:51) — 테스트 설명과 달리 전화번호 제거 및 temp의 configurable footer를 묶지 않는다

  문제:

  - “teléfono도 없다”고 쓰지만 `STORE.phone` 부재 assertion이 없다.
  - `footer.extra` 보존은 `formatInvoiceHtml`만 검사한다. `formatTempTicketHtml`에서 `renderFooterExtra`를 삭제하는 mutation은 살아남는다.
  - `>Fecha<`, `>Hora<`와 날짜/시간 값을 각각 전체 HTML 어디서든 찾으므로, 행 연결이 깨지거나 Fecha/Hora 값이 서로 바뀌어도 통과할 수 있다.

  수정: `STORE.phone` 부재, F2의 `footer.extra`, 각 `.meta-row` 안의 정확한 label/value 조합을 검사하라.

레이아웃 측에서는 헤더 제거 자체로 인한 구체적인 파손은 찾지 못했다. 고정 높이나 절대 위치가 없고 뒤의 `.ticket-meta`가 정상적으로 당겨진다. 남은 `.store-header` CSS는 죽은 규칙일 뿐 출력 공간을 차지하지 않는다. 세 smoke test도 모두 통과했지만, 위 실제 F2 payload 불일치는 테스트가 포착하지 못한다.
hook: Stop
hook: Stop
hook: Stop Failed
hook: Stop Completed
tokens used
66,227
[HIGH] [ventago-app/src/views/homes/components/ProductList/ProductList.tsx:2013](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/ventago-app/src/views/homes/components/ProductList/ProductList.tsx:2013) — 실제 F2는 판매 시각 대신 항상 `00:00:00`을 출력한다

  문제: F2 payload는 날짜와 시간을 `invoice.date`, `invoice.time`으로 분리한다. 변경된 formatter는 `invoice.date`만 파싱하므로 `23/09/2026`이 해당 날짜의 자정으로 해석된다. 사용자가 요구한 Hora 행은 생기지만 값이 틀린다.

  근거:

  ```js
  date: issuedAt.toLocaleDateString('es-AR'),
  time: issuedAt.toLocaleTimeString('es-AR'),
  ```

  반면 [formatter.js:857](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/print-agent/src/formatter.js:857)은 다음만 사용한다.

  ```js
  renderTicketDate(data.invoice?.date)
  ```

  실제 payload 형태를 넣으면 `Fecha 23/09/2026`, `Hora 00:00:00`이 된다.

  수정: `renderTicketDate`가 `date`와 `time`을 함께 받게 하거나, F2에서 `invoice.date`를 ISO 문자열 하나로 보내라. 테스트도 현재의 합성 ISO payload가 아니라 실제 `{ date: '23/09/2026', time: '12:21:29' }` 형태로 추가해야 한다.

[MEDIUM] [SaleReviewPanel.tsx:293](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/ventago-app/src/views/homes/components/SaleReview/SaleReviewPanel.tsx:293) — 과거 판매 재출력 경로가 여전히 판매일이 아니라 인쇄일을 출력한다

  문제: 변경 주석은 `SaleReviewPanel`과 `EnvioTimeline`의 과거 판매 날짜를 바로잡는다고 설명하지만, 두 payload 모두 `invoice.date`를 보내지 않는다. 따라서 `renderTicketDate(undefined)`가 현재 시각으로 폴백하며 종전 동작이 그대로 남는다.

  근거:

  ```js
  invoice: {
    number: currentSale?.dailyNumber || currentSale?.id || undefined,
    seller: ...,
    client: ...,
  }
  ```

  [EnvioTimeline.tsx:287](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/ventago-app/src/views/ventas-online/components/EnvioTimeline.tsx:287)도 동일하다.

  ```js
  invoice: { client: order.clientName || 'Consumidor Final' }
  ```

  수정: 각 경로에서 실제 판매/주문 생성시각을 `invoice.date`로 전달해야 한다. 날짜를 알 수 없는 진짜 견적·주방 comanda만 “현재 시각” 폴백을 유지하는 편이 맞다.

  질문 2에 대한 직접 답변: 현재 확인한 실제 callsite 중 `—`가 새로 출력되는 payload는 없다. 날짜 미전달 경로는 현재 시각으로 폴백하고, F2의 `dd/mm/yyyy`도 유효하게 파싱된다. `—`는 비어 있지 않은 잘못된 날짜가 들어올 때만 나온다. 그 경우 틀린 날짜를 만들어내는 것보다 `—`가 적절하다. 실제 회귀는 `—`가 아니라 위의 `00:00:00`과 과거 경로의 “현재 날짜”다.

[LOW] [ticket-uniform.smoke.js:69](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/print-agent/test/ticket-uniform.smoke.js:69) — 테스트의 날짜 fixture가 실제 F2 계약과 달라 핵심 회귀를 놓친다

  문제: 테스트는 `invoice.date: '2026-09-23T12:21:29'` 한 필드만 사용한다. 그래서 실제 F2의 분리된 `date/time` 계약을 깨뜨린 현재 구현도 통과한다.

  수정: 실제 F2 payload를 그대로 사용하는 케이스를 추가하고 `Hora` 행의 값이 `invoice.time`과 같음을 검사하라. `TempTicketPayload.invoice` 타입에도 `date`와 `time`을 선언해야 계약 이탈을 컴파일 단계에서 잡을 수 있다.

[LOW] [ticket-uniform.smoke.js:51](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/print-agent/test/ticket-uniform.smoke.js:51) — 테스트 설명과 달리 전화번호 제거 및 temp의 configurable footer를 묶지 않는다

  문제:

  - “teléfono도 없다”고 쓰지만 `STORE.phone` 부재 assertion이 없다.
  - `footer.extra` 보존은 `formatInvoiceHtml`만 검사한다. `formatTempTicketHtml`에서 `renderFooterExtra`를 삭제하는 mutation은 살아남는다.
  - `>Fecha<`, `>Hora<`와 날짜/시간 값을 각각 전체 HTML 어디서든 찾으므로, 행 연결이 깨지거나 Fecha/Hora 값이 서로 바뀌어도 통과할 수 있다.

  수정: `STORE.phone` 부재, F2의 `footer.extra`, 각 `.meta-row` 안의 정확한 label/value 조합을 검사하라.

레이아웃 측에서는 헤더 제거 자체로 인한 구체적인 파손은 찾지 못했다. 고정 높이나 절대 위치가 없고 뒤의 `.ticket-meta`가 정상적으로 당겨진다. 남은 `.store-header` CSS는 죽은 규칙일 뿐 출력 공간을 차지하지 않는다. 세 smoke test도 모두 통과했지만, 위 실제 F2 payload 불일치는 테스트가 포착하지 못한다.
