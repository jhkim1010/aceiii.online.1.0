Reading additional input from stdin...
2026-10-07T19:25:42.578522Z ERROR codex_models_manager::cache: failed to load models cache: missing field `base_instructions` at line 140 column 5
OpenAI Codex v0.146.0
--------
workdir: /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
model: gpt-5.6-sol
provider: openai
approval: never
sandbox: workspace-write [workdir, /tmp, $TMPDIR]
reasoning effort: none
reasoning summaries: none
session id: 01a117d4-2af7-7c90-a2e9-0eff132db258
--------
user
Revisá este diff de zebra-agent (Electron 28, main+preload+renderer con contextIsolation). Agrega «Vista Zebra»: botones que arman el MISMO ZPL que se imprimiría (diseño en pantalla sin guardar, primer producto del lote, etiqueta de test) y lo mandan a api.labelary.com para mostrar el PNG en un modal. En el renderer se extrajo armarItemsLote() de imprimirLoteFlujo (verificá que imprimir siga igual). Buscá errores concretos: equivalencia con print:labels (prueba), datos que viajan por IPC, XSS en el modal, fetch/AbortSignal en Electron 28 main, doble clic, límites de Labelary. No estilo.
diff --git a/zebra-agent/main.js b/zebra-agent/main.js
index 604fafc..25ef367 100644
--- a/zebra-agent/main.js
+++ b/zebra-agent/main.js
@@ -12,6 +12,7 @@ const {
 const { prepareItems: prepareItemsPure } = require('./src/price-select');
 const { sendZpl: sendZplSinContar, testConnection: testPrinterConnection, listUsbPrinters } = require('./src/zebra-printer');
 const { crearActividad } = require('./src/update-policy');
+const { renderizarZpl, armarZplVista } = require('./src/vista-zebra');
 
 // 인쇄 진행 추적 — 업데이트 재시작은 인쇄 중엔 절대 하지 않는다(update-policy.js).
 // 프린터에 닿는 호출(sendZpl)을 전부 이 래퍼로 감싼다.
@@ -595,6 +596,27 @@ ipcMain.handle('print:labels', async (_event, items, opciones) => {
   }
 });
 
+// [2026-10-07 usuario] «Vista Zebra» — la primera etiqueta, del MISMO ZPL que se imprimiría,
+//   dibujada por un emulador de Zebra en línea (src/vista-zebra.js). Sólo a pedido (botón).
+//   tipo 'diseno': el diseño que está en pantalla (aún sin guardar) con un producto de muestra
+//   tipo 'lote'  : el primer producto elegido, como «Imprimir 1 de prueba»
+//   tipo 'test'  : la etiqueta de «Imprimir test»
+ipcMain.handle('vista:zebra', async (_event, args) => {
+  try {
+    const { zpl, mode } = armarZplVista(args || {}, {
+      ajustes: getPrintSettings(),
+      modoEfectivo: getEffectiveMode(),
+      modoImpresion: getPrintMode(),
+      seleccion: store.get('priceSelection') || [],
+      qrLayout: store.get('qrLayout') || {},
+    });
+
+    return await renderizarZpl(zpl, { mode });
+  } catch (err) {
+    return { ok: false, error: err.message || 'No se pudo armar la etiqueta' };
+  }
+});
+
 // [v1.0.29] Vista previa EXACTA del lote QR (pestaña Etiquetas) — el mismo ZPL que se
 //   imprime, leído como dibujo. Devuelve además el resumen para la confirmación.
 ipcMain.handle('qr:previewLote', (_event, items, opciones) => {
diff --git a/zebra-agent/preload.js b/zebra-agent/preload.js
index 2b15ce8..0e64abd 100644
--- a/zebra-agent/preload.js
+++ b/zebra-agent/preload.js
@@ -48,6 +48,8 @@ contextBridge.exposeInMainWorld('electronAPI', {
   // [v1.0.29] vista previa exacta (mismo ZPL que se imprime)
   qrPreviewLote: (items, opciones) => ipcRenderer.invoke('qr:previewLote', items, opciones),
   qrPreviewTab: (args) => ipcRenderer.invoke('qr:previewTab', args),
+  // [2026-10-07] «Vista Zebra» — imagen del emulador con el mismo ZPL
+  vistaZebra: (args) => ipcRenderer.invoke('vista:zebra', args),
 
   // 업데이트 — 창 상단 띠 (renderer/update-banner.js)
   getUpdateEstado: () => ipcRenderer.invoke('update:estado'),
diff --git a/zebra-agent/renderer/index.html b/zebra-agent/renderer/index.html
index 1fda4a7..539ab9e 100644
--- a/zebra-agent/renderer/index.html
+++ b/zebra-agent/renderer/index.html
@@ -201,6 +201,11 @@
     .modal-caja .kv { font-size:12px; line-height:1.8; color:#c8cae0; }
     .modal-caja .kv b { color:#f5a623; }
     .modal-caja .acciones { display:flex; gap:8px; justify-content:flex-end; margin-top:12px; }
+    /* [2026-10-07] «Vista Zebra»: la imagen del emulador, a escala, sobre blanco */
+    .modal-caja.vz { width:auto; min-width:360px; max-width:94vw; }
+    .vz-img { display:flex; justify-content:center; background:#2a2f4a; padding:12px; border-radius:6px; }
+    .vz-img img { background:#fff; max-width:86vw; max-height:60vh; image-rendering:pixelated; box-shadow:0 2px 14px rgba(0,0,0,.55); }
+    .vz-nota { font-size:11px; color:#8a8db0; margin-top:8px; line-height:1.5; }
   </style>
 </head>
 <body>
@@ -377,6 +382,8 @@
                 <label><input type="radio" name="lote-alcance" id="lote-alcance-todos" value="todos" checked><span>Todos</span></label>
                 <label><input type="radio" name="lote-alcance" id="lote-alcance-sel" value="sel"><span>Seleccionados</span></label>
               </div>
+              <button class="btn btn-secondary" id="btn-vista-zebra-lote" disabled
+                title="Cómo sale la etiqueta del primer producto, sin imprimir">Vista Zebra</button>
               <button class="btn btn-primary" id="btn-print-zpl" disabled>Imprimir x ZPL</button>
             </div>
           </div>
@@ -407,6 +414,7 @@
           <div style="display:flex; gap:8px; align-items:center; margin:8px 0;">
             <button class="btn btn-primary" id="btn-scan-printers" style="font-size:11px; padding:5px 12px;">Buscar impresoras</button>
             <button class="btn btn-secondary" id="btn-test-print" style="font-size:11px; padding:5px 12px;">Imprimir test</button>
+            <button class="btn btn-secondary" id="btn-vista-zebra-test" style="font-size:11px; padding:5px 12px;">Ver test</button>
             <span id="printer-scan-status" style="font-size:11px; color:#888;"></span>
           </div>
           <div class="printer-list" id="printer-list"></div>
@@ -516,6 +524,10 @@
           <div class="card-title">Vista previa</div>
           <div class="preview-wrap"><canvas id="preview-canvas" width="400" height="220"></canvas></div>
           <div class="preview-hint">Actualización en tiempo real — escala 1:1 con ZPL</div>
+          <div style="display:flex; justify-content:center; margin-top:6px;">
+            <button class="btn btn-secondary" id="btn-vista-zebra-diseno" style="font-size:11px; padding:5px 12px;"
+              title="Muestra cómo sale de verdad este diseño (sin guardar) con un producto de muestra">Ver cómo sale en la Zebra</button>
+          </div>
           <div class="inline-grid" style="margin-top:8px;">
             <label>SKU test</label>
             <input type="text" id="sample-sku" value="VG00123456" style="text-align:left; grid-column:span 5;">
@@ -1747,6 +1759,7 @@
     $('#selected-count').textContent = idxs.length;
     $('#selected-count-label').textContent = ' producto(s) · ' + unidades + ' u.';
     $('#btn-print-zpl').disabled = idxs.length === 0 || printing;
+    $('#btn-vista-zebra-lote').disabled = idxs.length === 0;
     if ($('#lote-simbolo-qr')?.checked) pintarPreviewLote();
   }
 
@@ -1828,34 +1841,7 @@
 
       return;
     }
-    const items = [];
-
-    idxs.forEach(idx => {
-      const p = products[idx];
-      if (!p) return;
-      const qty = cantDe(idx);
-
-      const itemPrices = (p.prices || [])
-        .filter(pr => pr && pr.amount > 0)
-        .map(pr => ({
-          priceTypeId: pr.priceTypeId ?? pr.priceType?.id ?? null,
-          label: pr.priceType?.name || pr.label || '',
-          amount: pr.amount,
-        }));
-
-      // prices 배열이 없고 단일 price 만 있는 응답 하위 호환
-      if (itemPrices.length === 0 && p.price) {
-        itemPrices.push({ priceTypeId: null, label: '', amount: p.price });
-      }
-
-      items.push({
-        name: p.name,
-        sku: p.sku || '',
-        barcodeType: 'CODE128',
-        prices: itemPrices,
-        qty,
-      });
-    });
+    const items = armarItemsLote(idxs);
 
     if (items.length === 0) return;
 
@@ -1920,6 +1906,55 @@
     }
   }
 
+  // productos de la lista → items para imprimir (todos los precios; main filtra por nivel)
+  function armarItemsLote(idxs) {
+    const items = [];
+
+    idxs.forEach(idx => {
+      const p = products[idx];
+      if (!p) return;
+      const qty = cantDe(idx);
+
+      const itemPrices = (p.prices || [])
+        .filter(pr => pr && pr.amount > 0)
+        .map(pr => ({
+          priceTypeId: pr.priceTypeId ?? pr.priceType?.id ?? null,
+          label: pr.priceType?.name || pr.label || '',
+          amount: pr.amount,
+        }));
+
+      // prices 배열이 없고 단일 price 만 있는 응답 하위 호환
+      if (itemPrices.length === 0 && p.price) {
+        itemPrices.push({ priceTypeId: null, label: '', amount: p.price });
+      }
+
+      items.push({
+        name: p.name,
+        sku: p.sku || '',
+        barcodeType: 'CODE128',
+        prices: itemPrices,
+        qty,
+      });
+    });
+
+    return items;
+  }
+
+  // [2026-10-07] «Vista Zebra» del lote: el primer producto, como «Imprimir 1 de prueba».
+  //   Lee el diseño GUARDADO (igual que imprimir), así que espera los guardados pendientes.
+  $('#btn-vista-zebra-lote').addEventListener('click', async () => {
+    if (!(await dtGuardarPendiente())) {
+      addLocalLog('No se pudo guardar el diseño de la etiqueta. Probá de nuevo.');
+
+      return;
+    }
+    const items = armarItemsLote(idxsAImprimir()).slice(0, 1);
+    if (items.length === 0) return;
+    mostrarVistaZebra('Vista Zebra · ' + (items[0].name || items[0].sku || ''), {
+      tipo: 'lote', items, opciones: leerOpcionesLote(),
+    });
+  });
+
   // ── Símbolo del lote: barras (siempre) o QR con el SKU ────────────────────
   function leerOpcionesLote() {
     const esQr = !!$('#lote-simbolo-qr')?.checked;
@@ -2987,6 +3022,50 @@
   }
 
   // Confirmación propia (no window.confirm). Devuelve 'imprimir' | 'prueba' | 'cancelar'.
+  // [2026-10-07 usuario] «Vista Zebra» — la imagen que devuelve el emulador de Zebra (Labelary)
+  //   para el MISMO ZPL que se imprimiría. Sólo con el botón: manda el contenido de la etiqueta.
+  let vistaZebraAbierta = false;
+  async function mostrarVistaZebra(titulo, args) {
+    if (vistaZebraAbierta) return;
+    vistaZebraAbierta = true;
+    const fondo = document.createElement('div');
+    fondo.className = 'modal-fondo';
+    fondo.innerHTML = `<div class="modal-caja vz">
+      <h3>${escHtml(titulo)}</h3>
+      <div class="vz-img"><span style="color:#c8cae0; font-size:12px;">Generando…</span></div>
+      <div class="vz-nota">Dibujo del emulador de Zebra (labelary.com, 203 dpi) con el mismo ZPL que se imprime.
+        Muestra la primera etiqueta. Necesita internet y envía el contenido de la etiqueta al emulador.</div>
+      <div class="acciones"><button class="btn btn-primary" data-r="cerrar">Cerrar</button></div>
+    </div>`;
+    const cerrar = () => { fondo.remove(); vistaZebraAbierta = false; };
+    fondo.addEventListener('click', (e) => { if (e.target === fondo || e.target.dataset.r === 'cerrar') cerrar(); });
+    document.body.appendChild(fondo);
+    let r = null;
+    try { r = await api.vistaZebra(args); } catch (_) { r = null; }
+    if (!fondo.isConnected) return;
+    const caja = fondo.querySelector('.vz-img');
+    if (r && r.ok && r.png) {
+      const img = document.createElement('img');
+      img.src = r.png;
+      img.alt = 'Etiqueta';
+      caja.replaceChildren(img);
+    } else {
+      const msg = document.createElement('span');
+      msg.style.color = '#ff8a80';
+      msg.style.fontSize = '12px';
+      msg.textContent = (r && r.error) || 'No se pudo generar la vista.';
+      caja.replaceChildren(msg);
+    }
+  }
+
+  // diseño en pantalla (sin guardar) + producto de muestra
+  $('#btn-vista-zebra-diseno').addEventListener('click', () => {
+    mostrarVistaZebra('Vista Zebra · diseño actual', { tipo: 'diseno', mode: buildModeFromForm(), sku: sampleSku() });
+  });
+  $('#btn-vista-zebra-test').addEventListener('click', () => {
+    mostrarVistaZebra('Vista Zebra · Imprimir test', { tipo: 'test' });
+  });
+
   function confirmarImpresion({ titulo, lineas, cortados, dibujo, textoImprimir }) {
     return new Promise((resolve) => {
       const fondo = document.createElement('div');
=== NEW src/vista-zebra.js
/**
 * [2026-10-07 usuario] «Vista Zebra» — cómo sale de verdad la etiqueta.
 *
 * > «Zebra agent 에서 생성한 zpl 코드를 읽으면 어떻게 출력될지 확인할 수 있을텐데..» → opción 2
 *
 * La vista previa del diseño (canvas) es un dibujo aproximado: no sabe cuándo el código de barras
 * se sale de la etiqueta ni cómo queda la fuente de la impresora. Acá se manda el MISMO ZPL que se
 * imprime a Labelary (emulador de Zebra en línea, 203 dpi) y se muestra la imagen que devuelve.
 *
 * ★ Sale a internet el contenido de la etiqueta (nombre, SKU, precio). Por eso es un botón — nunca
 *   automático — y la pantalla lo dice. Sin internet no hay vista: la impresión no depende de esto.
 * ★ Sólo la PRIMERA etiqueta del ZPL (índice 0): es una muestra, no el lote.
 */

const { formatBatchLabels, formatTestLabel } = require('./zpl-formatter');
const { prepareItems } = require('./price-select');

const LABELARY = 'https://api.labelary.com/v1/printers/8dpmm/labels';
const DPI = 203.2; // 8 dpmm
const MAX_PULGADAS = 15; // límite de Labelary

/** Ancho y alto (dots) de la primera etiqueta: lo que dicen ^PW/^LL, si no el modo. */
function tamanoDeZpl(zpl, mode) {
  const pw = /\^PW(\d+)/.exec(zpl);
  const ll = /\^LL(\d+)/.exec(zpl);

  return {
    ancho: pw ? Number(pw[1]) : (mode && mode.width) || 400,
    alto: ll ? Number(ll[1]) : (mode && mode.height) || 200,
  };
}

const pulgadas = (dots) => Math.min(MAX_PULGADAS, Math.max(0.1, dots / DPI)).toFixed(2);

function urlLabelary(ancho, alto) {
  return `${LABELARY}/${pulgadas(ancho)}x${pulgadas(alto)}/0/`;
}

/**
 * ZPL → PNG (data URL). Nunca lanza: devuelve { ok:false, error } con un texto para la persona.
 * @param {string} zpl
 * @param {{ mode?: object, fetchImpl?: Function, timeoutMs?: number }} [o]
 */
async function renderizarZpl(zpl, { mode = null, fetchImpl = globalThis.fetch, timeoutMs = 12000 } = {}) {
  if (!zpl || typeof zpl !== 'string') return { ok: false, error: 'No hay etiqueta para mostrar' };
  const { ancho, alto } = tamanoDeZpl(zpl, mode);
  try {
    const r = await fetchImpl(urlLabelary(ancho, alto), {
      method: 'POST',
      headers: { Accept: 'image/png', 'Content-Type': 'application/x-www-form-urlencoded' },
      body: zpl,
      signal: AbortSignal.timeout(timeoutMs),
    });
    if (r.status === 429) return { ok: false, error: 'Demasiadas vistas seguidas. Esperá unos segundos.' };
    if (!r.ok) {
      const txt = String(await r.text().catch(() => '')).slice(0, 200);

      return { ok: false, error: `El emulador no pudo leer la etiqueta (${r.status})${txt ? `: ${txt}` : ''}` };
    }
    const buf = Buffer.from(await r.arrayBuffer());

    return { ok: true, png: `data:image/png;base64,${buf.toString('base64')}`, ancho, alto };
  } catch (_) {
    return { ok: false, error: 'Sin conexión con el emulador (hace falta internet).' };
  }
}

const MUESTRA_NOMBRE = 'REMERA OVERSIZE NEGRA M';
const MUESTRA_MONTOS = [12999, 9750, 8100];

/**
 * El ZPL que se mostraría — con las MISMAS funciones que imprimen.
 *   tipo 'diseno': el modo armado en pantalla (sin guardar) + un producto de muestra
 *   tipo 'lote'  : el primer producto elegido, como «Imprimir 1 de prueba» (print:labels)
 *   tipo 'test'  : la etiqueta de «Imprimir test»
 * @param {object} args  { tipo, mode?, sku?, items?, opciones? } (viene de la pantalla)
 * @param {object} ctx   { ajustes:{darkness,speed}, modoEfectivo, modoImpresion, seleccion, qrLayout }
 * @returns {{ zpl: string|null, mode: object|null }}
 */
function armarZplVista({ tipo, mode, sku, items, opciones } = {}, ctx) {
  const { darkness = null, speed = null } = ctx.ajustes || {};
  if (tipo === 'test') {
    return { zpl: formatTestLabel(ctx.modoEfectivo, { darkness, speed }), mode: ctx.modoEfectivo };
  }
  const seleccion = Array.isArray(ctx.seleccion) ? ctx.seleccion : [];
  if (tipo === 'diseno') {
    // densidad/velocidad son de la impresora, no del diseño — como al imprimir
    const m = { ...(mode || ctx.modoEfectivo), darkness, speed };
    if (seleccion.length > 0) m.layout = { ...(m.layout || {}), priceCount: seleccion.length };
    const niveles = seleccion.length > 0 ? seleccion : [{ id: null, name: '' }];
    const muestra = {
      name: MUESTRA_NOMBRE,
      sku: String(sku || 'VG00123456'),
      barcodeType: 'CODE128',
      prices: niveles.slice(0, 3).map((s, i) => ({ priceTypeId: s.id ?? null, label: s.name || '', amount: MUESTRA_MONTOS[i] })),
      qty: 1,
    };

    return { zpl: formatBatchLabels(prepareItems([muestra], seleccion, m.layout || {}), m, { simbolo: 'barras' }), mode: m };
  }
  if (tipo !== 'lote' || !Array.isArray(items) || items.length === 0) return { zpl: null, mode: null };
  // lote: igual que print:labels con «prueba» — una fila del primer producto
  const m = ctx.modoImpresion;
  const esQr = !!(opciones && opciones.simbolo === 'qr');
  const porEtiqueta = opciones && opciones.porEtiqueta === 2 ? 2 : 1;
  const porFila = esQr ? (m.duplicate && m.halfWidth ? 2 : 1) * porEtiqueta : 1;

  return {
    zpl: formatBatchLabels(prepareItems([{ ...items[0], qty: porFila }], seleccion, m.layout || {}), m, {
      simbolo: esQr ? 'qr' : 'barras',
      porEtiqueta,
      texto: ctx.qrLayout || {},
    }),
    mode: m,
  };
}

module.exports = { renderizarZpl, armarZplVista, urlLabelary, tamanoDeZpl, LABELARY };
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
Voy a contrastar el diff con las rutas reales de impresión y test, y revisar el contrato IPC/Labelary sin modificar archivos. También leeré el protocolo de revisión del repositorio para entregar el resultado en el formato acordado.
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
exec
/bin/zsh -lc "sed -n '1,240p' .team/REVIEW-PROTOCOL.md && rg -n \"ipcMain.handle\\('print:labels'|formatTestLabel|formatBatchLabels|prepareItems|print:test|test-print|imprimirLoteFlujo|dtGuardarPendiente|function buildModeFromForm|function sampleSku|const api =|electronAPI\" zebra-agent/main.js zebra-agent/renderer/index.html zebra-agent/preload.js zebra-agent/src -g '*.js'" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
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
zebra-agent/preload.js:5:contextBridge.exposeInMainWorld('electronAPI', {
zebra-agent/main.js:8:  formatBatchLabels, formatQrLabel, formatTestLabel, resolveMode, darknessZpl, speedZpl,
zebra-agent/main.js:12:const { prepareItems: prepareItemsPure } = require('./src/price-select');
zebra-agent/main.js:140:function prepareItems(items) {
zebra-agent/main.js:141:  return prepareItemsPure(
zebra-agent/main.js:548:ipcMain.handle('print:labels', async (_event, items, opciones) => {
zebra-agent/main.js:567:    const zpl = formatBatchLabels(prepareItems(items), mode, {
zebra-agent/main.js:631:    const lista = prepareItems(Array.isArray(items) ? items : []);
zebra-agent/main.js:1069:      const zpl = formatBatchLabels(prepareItems(payload.items), mode);
zebra-agent/main.js:1129:    const testZpl = formatTestLabel(getEffectiveMode(), { darkness, speed });
zebra-agent/renderer/index.html:416:            <button class="btn btn-secondary" id="btn-test-print" style="font-size:11px; padding:5px 12px;">Imprimir test</button>
zebra-agent/renderer/index.html:814:  const api = window.electronAPI;
zebra-agent/renderer/index.html:1077:  function buildModeFromForm() {
zebra-agent/renderer/index.html:1179:  function sampleSku() {
zebra-agent/renderer/index.html:1830:      await imprimirLoteFlujo(idxs);
zebra-agent/renderer/index.html:1836:  async function imprimirLoteFlujo(idxs) {
zebra-agent/renderer/index.html:1839:    if (!(await dtGuardarPendiente())) {
zebra-agent/renderer/index.html:1946:    if (!(await dtGuardarPendiente())) {
zebra-agent/renderer/index.html:2112:  $('#btn-test-print').addEventListener('click', async () => {
zebra-agent/renderer/index.html:3202:  async function dtGuardarPendiente() {
zebra-agent/src/vista-zebra.js:15:const { formatBatchLabels, formatTestLabel } = require('./zpl-formatter');
zebra-agent/src/vista-zebra.js:16:const { prepareItems } = require('./price-select');
zebra-agent/src/vista-zebra.js:83:    return { zpl: formatTestLabel(ctx.modoEfectivo, { darkness, speed }), mode: ctx.modoEfectivo };
zebra-agent/src/vista-zebra.js:99:    return { zpl: formatBatchLabels(prepareItems([muestra], seleccion, m.layout || {}), m, { simbolo: 'barras' }), mode: m };
zebra-agent/src/vista-zebra.js:109:    zpl: formatBatchLabels(prepareItems([{ ...items[0], qty: porFila }], seleccion, m.layout || {}), m, {
zebra-agent/src/price-select.js:47:function prepareItems(items, selection, layout) {
zebra-agent/src/price-select.js:56:module.exports = { selectItemPrices, prepareItems };
zebra-agent/src/zpl-formatter.js:611:function formatBatchLabels(items, mode, opciones) {
zebra-agent/src/zpl-formatter.js:1077:function formatTestLabel(mode, { darkness = null, speed = null } = {}) {
zebra-agent/src/zpl-formatter.js:1115:  formatTestLabel,
zebra-agent/src/zpl-formatter.js:1116:  formatBatchLabels,

hook: PostToolUse
hook: PostToolUse
hook: PostToolUse Failed
hook: PostToolUse Completed
codex
Ya confirmé que el archivo nuevo está presente en el árbol. Ahora estoy comparando argumentos y transformaciones exactas de `print:labels`, “Imprimir 1 de prueba” y “Imprimir test”; ahí es donde una vista aparentemente correcta puede divergir del ZPL real.
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
exec
/bin/zsh -lc "sed -n '120,165p' zebra-agent/main.js; sed -n '530,610p' zebra-agent/main.js; sed -n '610,670p' zebra-agent/main.js; sed -n '1040,1085p' zebra-agent/main.js; sed -n '1110,1145p' zebra-agent/main.js; sed -n '1800,1970p' zebra-agent/renderer/index.html; sed -n '2090,2130p' zebra-agent/renderer/index.html; sed -n '1060,1195p' zebra-agent/renderer/index.html; sed -n '1,130p' zebra-agent/src/price-select.js; cat zebra-agent/package.json; rg -n \"vista-zebra|vista:zebra|print:labels\" zebra-agent/test zebra-agent/tests zebra-agent -g '*test*' -g '*.spec.js' 2>/dev/null" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 exited 2 in 0ms:
function getEffectiveMode() {
  const modeKey = store.get('labelMode') || 'simple-face';
  const base = resolveMode(modeKey);
  const custom = (store.get('labelLayouts') || {})[base.key] || {};

  return {
    ...base,
    width: custom.width || base.width,
    height: custom.height || base.height,
    // duplicado 절반 너비는 커스텀 width 의 절반으로 재계산
    halfWidth: base.duplicate
      ? Math.round((custom.width || base.width) / 2)
      : base.halfWidth,
    layout: custom.layout ? { ...base.layout, ...custom.layout } : base.layout,
    // 출력 밀도/속도는 모드가 아닌 프린터 전역 설정
    ...getPrintSettings(),
  };
}

// ─── 출력용 items 전처리 (가격 nivel 필터 적용 — src/price-select.js 공용 로직) ──
function prepareItems(items) {
  return prepareItemsPure(
    items,
    store.get('priceSelection') || [],
    getEffectiveMode().layout || {},
  );
}

// ─── 출력 시점 모드 — nivel 선택이 있으면 priceCount 를 선택 개수로 고정 ────
function getPrintMode() {
  const mode = getEffectiveMode();
  const selection = store.get('priceSelection') || [];

  if (selection.length > 0) {
    mode.layout = { ...mode.layout, priceCount: selection.length };
  }

  return mode;
}

// ─── 전역 상태 ──────────────────────────────────────────────────────────────
let tray = null;
let mainWindow = null;
let setupWindow = null;
let wsConnection = null;
let connectionStatus = 'disconnected';
});

// 매장 지점 목록 조회 — 지점 선택 콤보용 (WebSocket ack)
ipcMain.handle('branches:fetch', async () => {
  if (!wsConnection || connectionStatus !== 'connected') {
    return { ok: false, error: 'No conectado al servidor' };
  }

  try {
    const res = await wsConnection.timeout(7000).emitWithAck('get_branches');

    return res || { ok: false, error: 'Sin respuesta' };
  } catch (err) {
    return { ok: false, error: err.message || 'Timeout' };
  }
});

// Zebra Agent에서 직접 출력 (WebSocket 우회, 로컬 직접 출력)
ipcMain.handle('print:labels', async (_event, items, opciones) => {
  const printerCfg = store.get('printer');
  if (!isPrinterConfigured(printerCfg)) return { ok: false, error: 'Impresora no configurada' };

  const mode = getPrintMode();

  // ★ [2026-09-25] Símbolo elegido en la pantalla. Ausente = barras, o sea el
  //   comportamiento de siempre: esta opción no puede cambiar lo que ya salía.
  const esQr = !!(opciones && opciones.simbolo === 'qr');
  const porEtiqueta = opciones && opciones.porEtiqueta === 2 ? 2 : 1;

  // [v1.0.29] «Imprimir 1 de prueba» — una sola fila del primer producto, para ver
  //   dónde caen QR y texto antes de gastar el rollo. (Con barras: una etiqueta.)
  if (opciones && opciones.prueba && Array.isArray(items) && items.length > 0) {
    const porFila = esQr ? (mode.duplicate && mode.halfWidth ? 2 : 1) * porEtiqueta : 1;
    items = [{ ...items[0], qty: porFila }];
  }

  try {
    const zpl = formatBatchLabels(prepareItems(items), mode, {
      simbolo: esQr ? 'qr' : 'barras',
      porEtiqueta,

      // [2026-10-02] qué texto lleva la etiqueta QR y dónde — lo guardado en la pestaña QR
      texto: store.get('qrLayout') || {},
    });
    const result = await sendZpl(zpl, printerCfg);

    // ★★ Lo que se informa son **etiquetas**, no unidades. Con 2 por etiqueta las
    //   dos cifras difieren, y decir «6 etiquetas» cuando salen 3 hace que el
    //   usuario crea que la impresora se comió la mitad.
    // ★ [v1.0.29] en filas (pasadas): doble banda + 2 QR = 4 unidades por fila
    const unidades = items.reduce((s, it) => s + Math.max(1, it.qty || 1), 0);
    const totalLabels = esQr
      // [2026-10-03] de corrido entre productos — mismo cálculo que qrLoteFilas imprime
      ? filasDeLoteQrTotal(items, mode, { porEtiqueta })
      : unidades;
    if (result.ok) {
      broadcastLog(`✅ ${totalLabels} etiqueta(s) impresas`);
    } else {
      broadcastLog(`❌ Error: ${result.error}`);
    }

    return result;
  } catch (err) {
    broadcastLog(`❌ ${err.message}`);

    return { ok: false, error: err.message };
  }
});

// [2026-10-07 usuario] «Vista Zebra» — la primera etiqueta, del MISMO ZPL que se imprimiría,
//   dibujada por un emulador de Zebra en línea (src/vista-zebra.js). Sólo a pedido (botón).
//   tipo 'diseno': el diseño que está en pantalla (aún sin guardar) con un producto de muestra
//   tipo 'lote'  : el primer producto elegido, como «Imprimir 1 de prueba»
//   tipo 'test'  : la etiqueta de «Imprimir test»
ipcMain.handle('vista:zebra', async (_event, args) => {
  try {
    const { zpl, mode } = armarZplVista(args || {}, {
      ajustes: getPrintSettings(),
      modoEfectivo: getEffectiveMode(),
      modoImpresion: getPrintMode(),
      seleccion: store.get('priceSelection') || [],
      seleccion: store.get('priceSelection') || [],
      qrLayout: store.get('qrLayout') || {},
    });

    return await renderizarZpl(zpl, { mode });
  } catch (err) {
    return { ok: false, error: err.message || 'No se pudo armar la etiqueta' };
  }
});

// [v1.0.29] Vista previa EXACTA del lote QR (pestaña Etiquetas) — el mismo ZPL que se
//   imprime, leído como dibujo. Devuelve además el resumen para la confirmación.
ipcMain.handle('qr:previewLote', (_event, items, opciones) => {
  try {
    const mode = getPrintMode();
    // [PEDIDO 10] el editor de «Diseño del texto» manda lo que se está moviendo (`textoPrevia`)
    //   para ver el cambio al instante. Sólo la VISTA PREVIA lo usa: imprimir lee siempre lo
    //   guardado (print:labels → store.get('qrLayout')), y el editor guarda antes de imprimir.
    const previa = opciones && opciones.textoPrevia;
    const ops = { ...(opciones || {}), texto: previa && typeof previa === 'object' ? previa : (store.get('qrLayout') || {}) };
    delete ops.textoPrevia;
    const lista = prepareItems(Array.isArray(items) ? items : []);
    if (lista.length === 0) return { ok: false, error: 'Sin productos' };

    const primero = qrLotePreview(lista[0], mode, ops);

    // [2026-10-03] la vista previa muestra la primera fila donde CAMBIA de producto (raya +
    //   descripción), si la hay — es lo nuevo que hay que ver antes de imprimir.
    const filasLote = qrLoteFilas(lista, mode, ops);
    const muestra = filasLote.find((f) => f.zpl.includes('^GB')) || filasLote[0];
    const filas = filasLote.length;
    let unidades = 0;
    const cortados = [];
    for (const it of lista) {
      unidades += Math.max(1, it.qty || 1);
      const r = qrLotePreview(it, mode, ops);
      if (r.avisos.some((a) => a.campo === 'nombre')) cortados.push(it.name);
    }

    return {
      ok: true,
      dibujo: muestra ? zplADibujo(muestra.zpl) : primero.dibujo,
      // [codex] dibujo, cajas y avisos de la MISMA fila (la que se muestra)
      avisos: muestra ? muestra.avisos : primero.avisos,
      cajas: muestra ? muestra.cajas : primero.cajas,
      porFila: primero.porFila,
      bandas: primero.bandas,
      anchoEtiqueta: primero.anchoEtiqueta,
      filas,
      unidades,
      cortados,
      modo: mode.name || mode.key,
      impresora: describirImpresora(store.get('printer')),
    };
  } catch (err) {
    return { ok: false, error: err.message };
  }
});

// [v1.0.29] Vista previa EXACTA de la pestaña QR (enlace para clientes).
ipcMain.handle('qr:previewTab', (_event, { item, items, layout, mode } = {}) => {
    }
  });

  // ── 바코드 라벨 출력 이벤트 ─────────────────────────────────────────────
  wsConnection.on('print_barcode', async (payload) => {
    console.log('[print_barcode] payload:', JSON.stringify(payload, null, 2));

    const printerCfg = store.get('printer');

    if (!isPrinterConfigured(printerCfg)) {
      broadcastLog('❌ Impresora no configurada');

      return;
    }

    if (!Array.isArray(payload?.items) || payload.items.length === 0) {
      broadcastLog('❌ print_barcode — items vacío');

      return;
    }

    const mode = getPrintMode();

    const totalLabels = payload.items.reduce((sum, it) => sum + Math.max(1, it.qty || 1), 0);
    const modeLabel = printerCfg.type === 'usb' ? 'USB' : 'TCP';

    broadcastLog(`🖨 Imprimiendo ${totalLabels} etiqueta(s) [${mode.name}] (${modeLabel})...`);

    try {
      const zpl = formatBatchLabels(prepareItems(payload.items), mode);
      const result = await sendZpl(zpl, printerCfg);

      if (result.ok) {
        broadcastLog(`✅ ${totalLabels} etiqueta(s) impresas`);
        wsConnection.emit('print_ack', {
          status: 'ok',
          labels: totalLabels,
          ts: Date.now(),
        });
      } else {
        broadcastLog(`❌ Error: ${result.error}`);
        wsConnection.emit('print_ack', {
          status: 'error',
          error: result.error,
          ts: Date.now(),
        });
}

// ─── 테스트 출력 ────────────────────────────────────────────────────────────
async function printTest() {
  const printerCfg = store.get('printer');

  if (!isPrinterConfigured(printerCfg)) {
    broadcastLog('❌ Impresora no configurada');

    return { success: false, error: 'Impresora no configurada' };
  }

  const modeLabel = printerCfg.type === 'usb' ? `USB: ${printerCfg.printerName}` : `TCP: ${printerCfg.host}:${printerCfg.port || 9100}`;
  broadcastLog(`🖨 Test de impresión (${modeLabel})...`);

  try {
    // 밀도/속도 전역 설정을 그대로 반영 — 테스트 출력으로 보정값을 확인할 수 있어야 함
    // [2026-10-07] la prueba sigue el modo elegido (doble banda → las dos etiquetas)
    const { darkness, speed } = getPrintSettings();
    const testZpl = formatTestLabel(getEffectiveMode(), { darkness, speed });

    const result = await sendZpl(testZpl, printerCfg);

    if (result.ok) {
      broadcastLog('✅ Test de impresión — OK');

      return { success: true };
    } else {
      broadcastLog(`❌ Test — ${result.error}`);

      return { success: false, error: result.error };
    }
  } catch (err) {
    broadcastLog(`❌ Test — ${err.message}`);

    return { success: false, error: err.message };
    $$('#product-list tr').forEach(tr => {
      tr.classList.toggle('fila-sel', filaSel !== null && Number(tr.dataset.idx) === filaSel);
    });
    const inp = $('#lote-fila-cant');
    inp.disabled = filaSel === null;
    if (filaSel === null) inp.value = '';
  }

  $('#lote-fila-cant').addEventListener('input', updateSelection);

  ['#lote-alcance-todos', '#lote-alcance-sel'].forEach((sel) => {
    $(sel)?.addEventListener('change', () => { soltarFila(); updateSelection(); });
  });

  $('#product-list').addEventListener('input', (e) => {
    if (e.target && e.target.type === 'number') updateSelection();
  });

  // ── 출력 — 상품의 nivel 가격 전체를 전달, main 프로세스가 선택 nivel 로 필터 ──
  $('#btn-print-zpl').addEventListener('click', () => {
    imprimirLote(idxsAImprimir());
  });

  // [codex] un solo flujo de impresión a la vez: `printing` se prende recién al mandar, y entre
  //   medio hay esperas (guardado, vista previa, confirmación) — un segundo clic abría otro.
  var flujoImprimir = false;
  async function imprimirLote(idxs) {
    if (printing || flujoImprimir) return;
    flujoImprimir = true;
    try {
      await imprimirLoteFlujo(idxs);
    } finally {
      flujoImprimir = false;
    }
  }

  async function imprimirLoteFlujo(idxs) {
    // [PEDIDO 10] imprimir lee lo GUARDADO: esperar los guardados pendientes del diseño.
    //   Si no se pudo guardar, no imprimir con el diseño viejo sin decirlo.
    if (!(await dtGuardarPendiente())) {
      addLocalLog('No se imprimió: no se pudo guardar el diseño de la etiqueta. Probá de nuevo.');

      return;
    }
    const items = armarItemsLote(idxs);

    if (items.length === 0) return;

    const opciones = leerOpcionesLote();

    // [v1.0.29] QR: confirmar con la etiqueta, filas reales (doble banda × 2 QR = 4 por fila),
    //   nombres cortados y «Imprimir 1 de prueba». Las barras siguen como siempre.
    let filasQr = null;
    if (opciones.simbolo === 'qr') {
      let pv = null;
      try { pv = await api.qrPreviewLote(items, opciones); } catch (_) { pv = null; }
      const eleccion = await confirmarImpresion({
        titulo: `¿Imprimir ${pv?.unidades ?? '?'} QR (${pv?.filas ?? '?'} fila(s) de ${pv?.porFila ?? '?'})?`,
        lineas: [
          `Impresora: <b>${escHtml(pv?.impresora || '?')}</b>`,
          `Rollo: <b>${escHtml(pv?.modo || '')}</b>` + (pv?.bandas === 2 ? ' · doble banda' : '') +
            ` · ${opciones.porEtiqueta === 2 ? '2 QR en 1 etiqueta' : '1 QR por etiqueta'} = <b>${pv?.porFila ?? '?'} por fila</b>`,
        ],
        cortados: pv?.cortados || [],
        dibujo: pv,
        textoImprimir: `Imprimir ${pv?.unidades ?? ''}`.trim(),
      });
      if (eleccion === 'cancelar') return;
      if (eleccion === 'prueba') opciones.prueba = true;
      filasQr = eleccion === 'prueba' ? 1 : (pv?.filas ?? null);
    }
    let unidades = items.reduce((s, it) => s + it.qty, 0);

    // [PEDIDO 9] con Cant. = stock actual, «Todos» puede sumar muchas etiquetas sin que se note.
    //   Más de 200: confirmar (el QR ya pasa por su propia confirmación con la cantidad).
    if (opciones.simbolo !== 'qr' && unidades > 200) {
      const eleccion = await confirmarImpresion({
        titulo: `¿Imprimir ${unidades} etiquetas?`,
        lineas: [`${items.length} producto(s) · <b>${unidades}</b> etiquetas en total.`, 'Revisá la columna Cant. si no querés tantas.'],
        textoImprimir: `Imprimir ${unidades}`,
      });
      if (eleccion === 'cancelar') return;
      if (eleccion === 'prueba') { opciones.prueba = true; unidades = 1; } // main imprime 1 sola
    }

    // ★★ Con 2 por etiqueta las unidades y las etiquetas **no son el mismo número**.
    //   Informar unidades donde salen etiquetas hace pensar que la impresora se comió
    //   la mitad del lote. Se cuenta igual que el proceso principal: por producto,
    //   redondeando hacia arriba (el impar final sale con un solo QR).
    //   [v1.0.29] con QR se cuentan FILAS, del mismo cálculo que main (doble banda × 2 = 4 por fila).
    const totalLabels = opciones.simbolo === 'qr' && filasQr !== null
      ? filasQr
      : unidades;

    addLocalLog('Imprimiendo ' + totalLabels + ' etiqueta(s)...');

    printing = true;
    updateSelection();
    try {
      const result = await api.printLabels(items, opciones);
      if (!result.ok) {
        addLocalLog('Error: ' + result.error);
      }
    } finally {
      printing = false;
      updateSelection();
    }
  }

  // productos de la lista → items para imprimir (todos los precios; main filtra por nivel)
  function armarItemsLote(idxs) {
    const items = [];

    idxs.forEach(idx => {
      const p = products[idx];
      if (!p) return;
      const qty = cantDe(idx);

      const itemPrices = (p.prices || [])
        .filter(pr => pr && pr.amount > 0)
        .map(pr => ({
          priceTypeId: pr.priceTypeId ?? pr.priceType?.id ?? null,
          label: pr.priceType?.name || pr.label || '',
          amount: pr.amount,
        }));

      // prices 배열이 없고 단일 price 만 있는 응답 하위 호환
      if (itemPrices.length === 0 && p.price) {
        itemPrices.push({ priceTypeId: null, label: '', amount: p.price });
      }

      items.push({
        name: p.name,
        sku: p.sku || '',
        barcodeType: 'CODE128',
        prices: itemPrices,
        qty,
      });
    });

    return items;
  }

  // [2026-10-07] «Vista Zebra» del lote: el primer producto, como «Imprimir 1 de prueba».
  //   Lee el diseño GUARDADO (igual que imprimir), así que espera los guardados pendientes.
  $('#btn-vista-zebra-lote').addEventListener('click', async () => {
    if (!(await dtGuardarPendiente())) {
      addLocalLog('No se pudo guardar el diseño de la etiqueta. Probá de nuevo.');

      return;
    }
    const items = armarItemsLote(idxsAImprimir()).slice(0, 1);
    if (items.length === 0) return;
    mostrarVistaZebra('Vista Zebra · ' + (items[0].name || items[0].sku || ''), {
      tipo: 'lote', items, opciones: leerOpcionesLote(),
    });
  });

  // ── Símbolo del lote: barras (siempre) o QR con el SKU ────────────────────
  function leerOpcionesLote() {
    const esQr = !!$('#lote-simbolo-qr')?.checked;

    return {
      simbolo: esQr ? 'qr' : 'barras',
      porEtiqueta: esQr && $('#lote-por-2')?.checked ? 2 : 1,
    };
  }

  function pintarOpcionesLote() {
    const o = leerOpcionesLote();
    const caja = $('#lote-qr-cantidad');
  }

  async function selectPrinter(p) {
    if (p.type === 'usb') {
      await api.setConfig('printer', { type: 'usb', printerName: p.printerName, host: '', port: 9100 });
    } else {
      await api.setConfig('printer', { type: 'network', host: p.host, port: p.port || 9100, printerName: '' });
    }
    await loadPrinterInfo();
    renderPrinterList();
    addLocalLog('Impresora seleccionada: ' + (p.printerName || p.host));
  }

  // 수동 설정 토글 (fallback)
  $('#btn-manual-toggle').addEventListener('click', () => {
    const el = $('#manual-fields');
    const visible = el.style.display !== 'none';
    el.style.display = visible ? 'none' : 'block';
    $('#btn-manual-toggle').textContent = visible ? 'Configuración manual' : 'Ocultar configuración manual';
  });

  // ── Config 이벤트 ──
  $('#btn-test-print').addEventListener('click', async () => {
    const result = await api.testPrint();
    if (!result.success) addLocalLog('Test: ' + (result.error || 'Error'));
  });

  // Network/USB 전환
  $('#cfg-type').addEventListener('change', () => {
    const isUsb = $('#cfg-type').value === 'usb';
    $('#cfg-network-fields').style.display = isUsb ? 'none' : 'block';
    $('#cfg-usb-fields').style.display = isUsb ? 'block' : 'none';
    if (isUsb) refreshUsbList();
  });

  $('#btn-refresh-usb').addEventListener('click', refreshUsbList);

  async function refreshUsbList() {
    const sel = $('#cfg-usb-printer');
    sel.textContent = '';
    const opt0 = document.createElement('option'); opt0.value = ''; opt0.textContent = 'Buscando...';
  }

  function displayToDots(sel) {
    const n = parseFloat($(sel).value) || 0;

    return sizeUnit === 'mm' ? Math.round(n * DOTS_PER_MM) : Math.round(n);
  }

  $('#lay-size-unit').addEventListener('change', () => {
    const wDots = displayToDots('#lay-w');
    const hDots = displayToDots('#lay-h');
    sizeUnit = $('#lay-size-unit').value;
    $('#lay-w').value = sizeToDisplay(wDots);
    $('#lay-h').value = sizeToDisplay(hDots);
  });

  // 편집 필드 → 현재 폼 값 기준 모드 객체 구성 (미리보기/저장 공용)
  function buildModeFromForm() {
    const base = modes.find(m => m.key === currentModeKey) || modes[0] || {};
    const layout = {};
    LAYOUT_FIELDS.forEach(([sel, elem, prop]) => {
      if (!layout[elem]) layout[elem] = { ...(currentMode?.layout?.[elem] || base.layout?.[elem] || {}) };
      layout[elem][prop] = int(sel);
    });
    const width = displayToDots('#lay-w') || base.width;
    const height = displayToDots('#lay-h') || base.height;

    // 자동 배치 / 바코드 auto-fit 플래그
    layout.autoPrices = $('#lay-auto-prices').checked;
    if (layout.barcode) layout.barcode.autoFit = $('#lay-bc-autofit').checked;

    return {
      ...base,
      width,
      height,
      halfWidth: base.duplicate ? Math.round(width / 2) : undefined,
      layout,
    };
  }

  // 입력 변경 → 실시간 미리보기
  LAYOUT_FIELDS.forEach(([sel]) => $(sel).addEventListener('input', drawPreview));
  ['#lay-w', '#lay-h', '#sample-sku'].forEach(s => $(s).addEventListener('input', drawPreview));

  $('#btn-save-layout').addEventListener('click', async () => {
    const m = buildModeFromForm();
    await api.setLabelLayout({
      width: m.width,
      height: m.height,
      layout: m.layout,
    });
    currentMode = (await api.getLabelConfig()).mode;
    updateModeChip();
    drawPreview();
    addLocalLog('Diseño guardado');
  });

  // ── 출력 파라미터 (전역 — 모든 모드 + QR 공통) ──
  // 슬라이더 ↔ 숫자 입력 양방향. 빈 숫자 = auto(프린터 기본값)
  function bindPrintSlider(numSel, rangeSel) {
    $(rangeSel).addEventListener('input', () => { $(numSel).value = $(rangeSel).value; });
    $(numSel).addEventListener('input', () => {
      if ($(numSel).value !== '') $(rangeSel).value = $(numSel).value;
    });
  }

  bindPrintSlider('#lay-dark', '#lay-dark-range');
  bindPrintSlider('#lay-speed', '#lay-speed-range');

  function showPrintSettings(s) {
    $('#lay-dark').value = s?.darkness ?? '';
    $('#lay-speed').value = s?.speed ?? '';
    if (s?.darkness != null) $('#lay-dark-range').value = s.darkness;
    if (s?.speed != null) $('#lay-speed-range').value = s.speed;
    $('#print-settings-status').textContent =
      `Oscuridad: ${s?.darkness ?? 'auto'} · Velocidad: ${s?.speed ?? 'auto'} ips`;
  }

  async function loadPrintSettings() {
    try {
      showPrintSettings(await api.getPrintSettings());
    } catch (err) {
      addLocalLog(`Error al cargar impresión: ${err.message}`);
    }
  }

  $('#btn-save-print').addEventListener('click', async () => {
    // 범위 밖/빈값은 main 에서 null(=프린터 기본값)로 정규화되어 되돌아옴
    const saved = await api.setPrintSettings({
      darkness: $('#lay-dark').value === '' ? null : int('#lay-dark'),
      speed: $('#lay-speed').value === '' ? null : int('#lay-speed'),
    });
    showPrintSettings(saved);
    currentMode = (await api.getLabelConfig()).mode;
    addLocalLog(`Impresión guardada — oscuridad ${saved.darkness ?? 'auto'}, velocidad ${saved.speed ?? 'auto'}`);
  });

  $('#btn-clear-print').addEventListener('click', async () => {
    const saved = await api.setPrintSettings({ darkness: null, speed: null });
    showPrintSettings(saved);
    currentMode = (await api.getLabelConfig()).mode;
    addLocalLog('Impresión: valores por defecto de la impresora');
  });

  $('#btn-reset-layout').addEventListener('click', async () => {
    await api.setLabelLayout(null);
    currentMode = (await api.getLabelConfig()).mode;
    loadLayoutEditor();
    drawPreview();
    addLocalLog('Diseño restablecido');
  });

  function int(sel) { return parseInt($(sel).value) || 0; }

  // ═══════════════════════════════════════════════════════════════════════
  // 실시간 미리보기 (canvas — ZPL dot 좌표계를 스케일 변환)
  // ═══════════════════════════════════════════════════════════════════════
  const SAMPLE_NAME = 'REMERA OVERSIZE NEGRA M';

  function sampleSku() {
    return ($('#sample-sku')?.value || '').trim() || 'VG00123456';
  }

  // 텍스트 폭 추정 (formatter 의 estTextWidth 와 동일 공식 — dots)
  function estW(text, fs) { return Math.ceil(String(text).length * fs * 0.55); }

  // 가격 블록 샘플 — nivel 라벨(1/4 크기) + 금액 분리
  function samplePriceBlocks(layout) {
    const amounts = ['$12.999,00', '$9.750,00', '$8.100,00'];
    const niveles = priceSelection.length > 0 ? priceSelection.map(s => s.name) : [''];
    const blocks = [];

    niveles.slice(0, 3).forEach((nv, i) => {
      const slot = layout[`price${i + 1}`];
      if (!slot) return;
      const aFs = slot.fontSize || 24;
/**
 * 서버 payload 가격 → 설정된 precio nivel 슬롯 매핑 (순수 함수)
 * main.js 와 테스트에서 공용으로 사용 — electron 의존성 없음.
 *
 * 매칭 우선순위: priceTypeId(숫자 비교) → label(이름, 대소문자 무시)
 * selection 이 비어 있으면 하위 호환: payload 순서대로 layout.priceCount 개.
 */

/**
 * 단일 상품의 가격 배열에서 선택된 nivel 만 추출
 * @param {Object} item - { prices: [{ priceTypeId, label, amount }] }
 * @param {Array} selection - [{ id, name }] 최대 3개
 * @param {Object} layout - { priceCount } (selection 미설정 시 fallback 개수)
 * @returns {Array} 슬롯 순서대로 정렬된 가격 배열
 */
function selectItemPrices(item, selection, layout) {
  const sel = Array.isArray(selection) ? selection : [];
  const incoming = Array.isArray(item.prices) ? item.prices : [];

  if (sel.length === 0) {
    const rawCount = layout && layout.priceCount;
    const count = Math.max(0, Math.min(3, rawCount == null ? 1 : parseInt(rawCount, 10) || 0));

    return incoming.slice(0, count);
  }

  const picked = [];
  for (const s of sel.slice(0, 3)) {
    const match = incoming.find(
      (pr) =>
        (s.id != null && pr.priceTypeId != null && Number(pr.priceTypeId) === Number(s.id)) ||
        (s.name && pr.label && String(pr.label).toLowerCase() === String(s.name).toLowerCase()),
    );
    if (match) picked.push(match);
  }

  return picked;
}

/**
 * 출력용 items 전처리 — 각 item 의 prices 를 선택 nivel 로 필터
 * @param {Array} items
 * @param {Array} selection
 * @param {Object} layout
 * @returns {Array}
 */
function prepareItems(items, selection, layout) {
  if (!Array.isArray(items)) return [];

  return items.map((it) => ({
    ...it,
    prices: selectItemPrices(it, selection, layout),
  }));
}

module.exports = { selectItemPrices, prepareItems };
{
  "name": "ventago-zebra-agent",
  "version": "1.0.0",
  "description": "VentaGO — Agente de Impresión Zebra (Código de Barras)",
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
    "socket.io-client": "^4.8.1",
    "electron-store": "^8.1.0",
    "electron-updater": "^6.3.9"
  },
  "devDependencies": {
    "electron": "^28.0.0",
    "electron-builder": "^24.0.0"
  },
  "build": {
    "appId": "com.coolsistema.ventago-zebra",
    "productName": "VentaGO Zebra Agent",
    "copyright": "© 2026 CoolSistema",
    "electronVersion": "28.3.3",
    "icon": "renderer/assets/icon-512.png",
    "publish": {
      "provider": "generic",
      "url": "https://github.com/jhkim1010/ventago-downloads/releases/download/zebra-agent-latest"
    },
    "files": [
      "main.js",
      "preload.js",
      "renderer/**",
      "src/**",
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
          "arch": ["x64"]
        }
      ],
      "artifactName": "VentaGO-Zebra-Agent-Setup.${ext}"
    },
    "mac": {
      "target": [
        {
          "target": "dmg",
          "arch": ["x64", "arm64"]
        }
      ],
      "artifactName": "VentaGO-Zebra-Agent-${arch}.${ext}",
      "category": "public.app-category.business"
    },
    "nsis": {
      "oneClick": true,
      "perMachine": false,
      "runAfterFinish": true,
      "createDesktopShortcut": true,
      "allowToChangeInstallationDirectory": false
    },
    "afterPack": "scripts/afterpack-adhoc-sign.js"
  }
}
zebra-agent/test/vista-zebra.test.js:4: * 실행: node test/vista-zebra.test.js
zebra-agent/test/vista-zebra.test.js:7:const { armarZplVista, renderizarZpl, urlLabelary } = require('../src/vista-zebra');
zebra-agent/test/vista-zebra.test.js:39:  console.log('vista-zebra\n');
zebra-agent/test/vista-zebra.test.js:4: * 실행: node test/vista-zebra.test.js
zebra-agent/test/vista-zebra.test.js:7:const { armarZplVista, renderizarZpl, urlLabelary } = require('../src/vista-zebra');
zebra-agent/test/vista-zebra.test.js:39:  console.log('vista-zebra\n');

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
/bin/zsh -lc "sed -n '1,260p' zebra-agent/test/vista-zebra.test.js; rg -n \"contextIsolation|nodeIntegration|sandbox:|webSecurity|setWindowOpenHandler|will-navigate|new BrowserWindow\" zebra-agent/main.js; nl -ba zebra-agent/src/vista-zebra.js | sed -n '1,180p'; nl -ba zebra-agent/main.js | sed -n '590,625p'; nl -ba zebra-agent/renderer/index.html | sed -n '1900,1970p;3010,3085p'; node zebra-agent/test/vista-zebra.test.js" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
/**
 * «Vista Zebra» (2026-10-07) — el ZPL que se muestra es el que se imprimiría, y el emulador
 * recibe ese ZPL con el tamaño de la etiqueta.
 * 실행: node test/vista-zebra.test.js
 */
const assert = require('assert');
const { armarZplVista, renderizarZpl, urlLabelary } = require('../src/vista-zebra');
const { formatBatchLabels, formatTestLabel, resolveMode } = require('../src/zpl-formatter');
const { prepareItems } = require('../src/price-select');

let passed = 0;
async function ok(name, fn) {
  await fn();
  passed += 1;
  console.log('  ✓', name);
}

const simple = { ...resolveMode('simple-face'), darkness: 15, speed: 4 };
const dup = { ...resolveMode('modo-duplicado'), darkness: null, speed: null };
const sel = [{ id: 1, name: 'Lista' }, { id: 2, name: 'Mayorista' }];
// modoImpresion = getPrintMode() de main: con niveles elegidos, priceCount = cantidad de niveles
const ctx = (modo) => ({
  ajustes: { darkness: 15, speed: 4 },
  modoEfectivo: modo,
  modoImpresion: { ...modo, layout: { ...modo.layout, priceCount: sel.length } },
  seleccion: sel,
  qrLayout: {},
});
const prod = (sku, qty = 5) => ({
  name: `PRODUCTO ${sku}`,
  sku,
  barcodeType: 'CODE128',
  prices: [{ priceTypeId: 2, label: 'Mayorista', amount: 900 }, { priceTypeId: 1, label: 'Lista', amount: 1000 }],
  qty,
});
const cuenta = (s, t) => s.split(t).length - 1;

(async () => {
  console.log('vista-zebra\n');

  await ok('lote: sólo el primer producto y una sola etiqueta — lo mismo que «Imprimir 1 de prueba»', () => {
    const { zpl } = armarZplVista({ tipo: 'lote', items: [prod('AAA111'), prod('BBB222')], opciones: {} }, ctx(simple));
    assert.strictEqual(cuenta(zpl, '^XA'), 1);
    assert.ok(zpl.includes('^FDAAA111') && !zpl.includes('BBB222'));
    const m = ctx(simple).modoImpresion;
    const esperado = formatBatchLabels(prepareItems([{ ...prod('AAA111'), qty: 1 }], sel, m.layout), m, {
      simbolo: 'barras', porEtiqueta: 1, texto: {},
    });
    assert.strictEqual(zpl, esperado);
  });

  await ok('lote: los precios salen en el orden de los niveles elegidos (Lista, Mayorista)', () => {
    const { zpl } = armarZplVista({ tipo: 'lote', items: [prod('AAA111')], opciones: {} }, ctx(simple));
    assert.ok(zpl.indexOf('1.000') > -1 && zpl.indexOf('900') > -1, zpl);
  });

  await ok('lote QR en doble banda con 2 por etiqueta: una fila de 4', () => {
    const { zpl } = armarZplVista({ tipo: 'lote', items: [prod('AAA111')], opciones: { simbolo: 'qr', porEtiqueta: 2 } }, ctx(dup));
    assert.strictEqual(cuenta(zpl, '^BQN'), 4);
  });

  await ok('lote QR: respeta lo guardado en la pestaña QR (sin precio → no sale el precio)', () => {
    const c = { ...ctx(simple), qrLayout: { mostrarPrecio: false } };
    const { zpl } = armarZplVista({ tipo: 'lote', items: [prod('AAA111')], opciones: { simbolo: 'qr' } }, c);
    const sinCfg = armarZplVista({ tipo: 'lote', items: [prod('AAA111')], opciones: { simbolo: 'qr' } }, ctx(simple)).zpl;
    assert.ok(sinCfg.includes('1.000'), 'sin config el precio sale');
    assert.ok(!zpl.includes('1.000'), zpl);
  });

  await ok('diseño: usa el modo de la pantalla (sin guardar) y el SKU de muestra', () => {
    const enPantalla = { ...simple, width: 480, layout: { ...simple.layout, name: { x: 33, y: 7, fontSize: 20 } } };
    const { zpl, mode } = armarZplVista({ tipo: 'diseno', mode: enPantalla, sku: 'MUESTRA9' }, ctx(simple));
    assert.ok(zpl.includes('^PW480'));
    assert.ok(zpl.includes('^FO33,7'));
    assert.ok(zpl.includes('^FDMUESTRA9'));
    assert.ok(/~SD15/.test(zpl), 'densidad de la impresora');
    assert.strictEqual(mode.width, 480);
  });

  await ok('test: exactamente la etiqueta de «Imprimir test»', () => {
    const { zpl } = armarZplVista({ tipo: 'test' }, ctx(dup));
    assert.strictEqual(zpl, formatTestLabel(dup, { darkness: 15, speed: 4 }));
  });

  await ok('sin productos o tipo desconocido: nada que mostrar (no se inventa una etiqueta)', async () => {
    assert.strictEqual(armarZplVista({ tipo: 'lote', items: [] }, ctx(simple)).zpl, null);
    assert.strictEqual(armarZplVista({ tipo: 'otro' }, ctx(simple)).zpl, null);
    const r = await renderizarZpl(null);
    assert.strictEqual(r.ok, false);
  });

  await ok('emulador: tamaño en pulgadas a 203 dpi según ^PW/^LL', () => {
    assert.ok(urlLabelary(400, 200).endsWith('/8dpmm/labels/1.97x0.98/0/'));
    assert.ok(urlLabelary(800, 200).endsWith('/3.94x0.98/0/'));
  });

  await ok('emulador: manda el ZPL tal cual y devuelve la imagen como data URL', async () => {
    let visto = null;
    const fake = async (url, o) => {
      visto = { url, o };

      return { ok: true, status: 200, arrayBuffer: async () => Uint8Array.from([137, 80, 78, 71]).buffer };
    };
    const zpl = formatTestLabel(dup, {});
    const r = await renderizarZpl(zpl, { fetchImpl: fake });
    assert.ok(r.ok);
    assert.ok(r.png.startsWith('data:image/png;base64,iVBORw'));
    assert.strictEqual(visto.o.body, zpl);
    assert.strictEqual(visto.o.method, 'POST');
    assert.ok(visto.url.includes('/3.94x0.98/0/'), visto.url);
  });

  await ok('emulador: límite, error y sin red → mensaje, nunca excepción', async () => {
    const z = formatTestLabel(simple, {});
    const r429 = await renderizarZpl(z, { fetchImpl: async () => ({ ok: false, status: 429, text: async () => '' }) });
    assert.match(r429.error, /Esperá/);
    const r400 = await renderizarZpl(z, { fetchImpl: async () => ({ ok: false, status: 400, text: async () => 'ERROR: bad' }) });
    assert.match(r400.error, /400.*bad/);
    const red = await renderizarZpl(z, { fetchImpl: async () => { throw new Error('ENOTFOUND'); } });
    assert.match(red.error, /internet/);
  });

  console.log(`\n${passed} ok`);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
302:  setupWindow = new BrowserWindow({
309:      contextIsolation: true,
310:      nodeIntegration: false,
322:  mainWindow = new BrowserWindow({
331:      contextIsolation: true,
332:      nodeIntegration: false,
     1	/**
     2	 * [2026-10-07 usuario] «Vista Zebra» — cómo sale de verdad la etiqueta.
     3	 *
     4	 * > «Zebra agent 에서 생성한 zpl 코드를 읽으면 어떻게 출력될지 확인할 수 있을텐데..» → opción 2
     5	 *
     6	 * La vista previa del diseño (canvas) es un dibujo aproximado: no sabe cuándo el código de barras
     7	 * se sale de la etiqueta ni cómo queda la fuente de la impresora. Acá se manda el MISMO ZPL que se
     8	 * imprime a Labelary (emulador de Zebra en línea, 203 dpi) y se muestra la imagen que devuelve.
     9	 *
    10	 * ★ Sale a internet el contenido de la etiqueta (nombre, SKU, precio). Por eso es un botón — nunca
    11	 *   automático — y la pantalla lo dice. Sin internet no hay vista: la impresión no depende de esto.
    12	 * ★ Sólo la PRIMERA etiqueta del ZPL (índice 0): es una muestra, no el lote.
    13	 */
    14	
    15	const { formatBatchLabels, formatTestLabel } = require('./zpl-formatter');
    16	const { prepareItems } = require('./price-select');
    17	
    18	const LABELARY = 'https://api.labelary.com/v1/printers/8dpmm/labels';
    19	const DPI = 203.2; // 8 dpmm
    20	const MAX_PULGADAS = 15; // límite de Labelary
    21	
    22	/** Ancho y alto (dots) de la primera etiqueta: lo que dicen ^PW/^LL, si no el modo. */
    23	function tamanoDeZpl(zpl, mode) {
    24	  const pw = /\^PW(\d+)/.exec(zpl);
    25	  const ll = /\^LL(\d+)/.exec(zpl);
    26	
    27	  return {
    28	    ancho: pw ? Number(pw[1]) : (mode && mode.width) || 400,
    29	    alto: ll ? Number(ll[1]) : (mode && mode.height) || 200,
    30	  };
    31	}
    32	
    33	const pulgadas = (dots) => Math.min(MAX_PULGADAS, Math.max(0.1, dots / DPI)).toFixed(2);
    34	
    35	function urlLabelary(ancho, alto) {
    36	  return `${LABELARY}/${pulgadas(ancho)}x${pulgadas(alto)}/0/`;
    37	}
    38	
    39	/**
    40	 * ZPL → PNG (data URL). Nunca lanza: devuelve { ok:false, error } con un texto para la persona.
    41	 * @param {string} zpl
    42	 * @param {{ mode?: object, fetchImpl?: Function, timeoutMs?: number }} [o]
    43	 */
    44	async function renderizarZpl(zpl, { mode = null, fetchImpl = globalThis.fetch, timeoutMs = 12000 } = {}) {
    45	  if (!zpl || typeof zpl !== 'string') return { ok: false, error: 'No hay etiqueta para mostrar' };
    46	  const { ancho, alto } = tamanoDeZpl(zpl, mode);
    47	  try {
    48	    const r = await fetchImpl(urlLabelary(ancho, alto), {
    49	      method: 'POST',
    50	      headers: { Accept: 'image/png', 'Content-Type': 'application/x-www-form-urlencoded' },
    51	      body: zpl,
    52	      signal: AbortSignal.timeout(timeoutMs),
    53	    });
    54	    if (r.status === 429) return { ok: false, error: 'Demasiadas vistas seguidas. Esperá unos segundos.' };
    55	    if (!r.ok) {
    56	      const txt = String(await r.text().catch(() => '')).slice(0, 200);
    57	
    58	      return { ok: false, error: `El emulador no pudo leer la etiqueta (${r.status})${txt ? `: ${txt}` : ''}` };
    59	    }
    60	    const buf = Buffer.from(await r.arrayBuffer());
    61	
    62	    return { ok: true, png: `data:image/png;base64,${buf.toString('base64')}`, ancho, alto };
    63	  } catch (_) {
    64	    return { ok: false, error: 'Sin conexión con el emulador (hace falta internet).' };
    65	  }
    66	}
    67	
    68	const MUESTRA_NOMBRE = 'REMERA OVERSIZE NEGRA M';
    69	const MUESTRA_MONTOS = [12999, 9750, 8100];
    70	
    71	/**
    72	 * El ZPL que se mostraría — con las MISMAS funciones que imprimen.
    73	 *   tipo 'diseno': el modo armado en pantalla (sin guardar) + un producto de muestra
    74	 *   tipo 'lote'  : el primer producto elegido, como «Imprimir 1 de prueba» (print:labels)
    75	 *   tipo 'test'  : la etiqueta de «Imprimir test»
    76	 * @param {object} args  { tipo, mode?, sku?, items?, opciones? } (viene de la pantalla)
    77	 * @param {object} ctx   { ajustes:{darkness,speed}, modoEfectivo, modoImpresion, seleccion, qrLayout }
    78	 * @returns {{ zpl: string|null, mode: object|null }}
    79	 */
    80	function armarZplVista({ tipo, mode, sku, items, opciones } = {}, ctx) {
    81	  const { darkness = null, speed = null } = ctx.ajustes || {};
    82	  if (tipo === 'test') {
    83	    return { zpl: formatTestLabel(ctx.modoEfectivo, { darkness, speed }), mode: ctx.modoEfectivo };
    84	  }
    85	  const seleccion = Array.isArray(ctx.seleccion) ? ctx.seleccion : [];
    86	  if (tipo === 'diseno') {
    87	    // densidad/velocidad son de la impresora, no del diseño — como al imprimir
    88	    const m = { ...(mode || ctx.modoEfectivo), darkness, speed };
    89	    if (seleccion.length > 0) m.layout = { ...(m.layout || {}), priceCount: seleccion.length };
    90	    const niveles = seleccion.length > 0 ? seleccion : [{ id: null, name: '' }];
    91	    const muestra = {
    92	      name: MUESTRA_NOMBRE,
    93	      sku: String(sku || 'VG00123456'),
    94	      barcodeType: 'CODE128',
    95	      prices: niveles.slice(0, 3).map((s, i) => ({ priceTypeId: s.id ?? null, label: s.name || '', amount: MUESTRA_MONTOS[i] })),
    96	      qty: 1,
    97	    };
    98	
    99	    return { zpl: formatBatchLabels(prepareItems([muestra], seleccion, m.layout || {}), m, { simbolo: 'barras' }), mode: m };
   100	  }
   101	  if (tipo !== 'lote' || !Array.isArray(items) || items.length === 0) return { zpl: null, mode: null };
   102	  // lote: igual que print:labels con «prueba» — una fila del primer producto
   103	  const m = ctx.modoImpresion;
   104	  const esQr = !!(opciones && opciones.simbolo === 'qr');
   105	  const porEtiqueta = opciones && opciones.porEtiqueta === 2 ? 2 : 1;
   106	  const porFila = esQr ? (m.duplicate && m.halfWidth ? 2 : 1) * porEtiqueta : 1;
   107	
   108	  return {
   109	    zpl: formatBatchLabels(prepareItems([{ ...items[0], qty: porFila }], seleccion, m.layout || {}), m, {
   110	      simbolo: esQr ? 'qr' : 'barras',
   111	      porEtiqueta,
   112	      texto: ctx.qrLayout || {},
   113	    }),
   114	    mode: m,
   115	  };
   116	}
   117	
   118	module.exports = { renderizarZpl, armarZplVista, urlLabelary, tamanoDeZpl, LABELARY };
   590	
   591	    return result;
   592	  } catch (err) {
   593	    broadcastLog(`❌ ${err.message}`);
   594	
   595	    return { ok: false, error: err.message };
   596	  }
   597	});
   598	
   599	// [2026-10-07 usuario] «Vista Zebra» — la primera etiqueta, del MISMO ZPL que se imprimiría,
   600	//   dibujada por un emulador de Zebra en línea (src/vista-zebra.js). Sólo a pedido (botón).
   601	//   tipo 'diseno': el diseño que está en pantalla (aún sin guardar) con un producto de muestra
   602	//   tipo 'lote'  : el primer producto elegido, como «Imprimir 1 de prueba»
   603	//   tipo 'test'  : la etiqueta de «Imprimir test»
   604	ipcMain.handle('vista:zebra', async (_event, args) => {
   605	  try {
   606	    const { zpl, mode } = armarZplVista(args || {}, {
   607	      ajustes: getPrintSettings(),
   608	      modoEfectivo: getEffectiveMode(),
   609	      modoImpresion: getPrintMode(),
   610	      seleccion: store.get('priceSelection') || [],
   611	      qrLayout: store.get('qrLayout') || {},
   612	    });
   613	
   614	    return await renderizarZpl(zpl, { mode });
   615	  } catch (err) {
   616	    return { ok: false, error: err.message || 'No se pudo armar la etiqueta' };
   617	  }
   618	});
   619	
   620	// [v1.0.29] Vista previa EXACTA del lote QR (pestaña Etiquetas) — el mismo ZPL que se
   621	//   imprime, leído como dibujo. Devuelve además el resumen para la confirmación.
   622	ipcMain.handle('qr:previewLote', (_event, items, opciones) => {
   623	  try {
   624	    const mode = getPrintMode();
   625	    // [PEDIDO 10] el editor de «Diseño del texto» manda lo que se está moviendo (`textoPrevia`)
  1900	      if (!result.ok) {
  1901	        addLocalLog('Error: ' + result.error);
  1902	      }
  1903	    } finally {
  1904	      printing = false;
  1905	      updateSelection();
  1906	    }
  1907	  }
  1908	
  1909	  // productos de la lista → items para imprimir (todos los precios; main filtra por nivel)
  1910	  function armarItemsLote(idxs) {
  1911	    const items = [];
  1912	
  1913	    idxs.forEach(idx => {
  1914	      const p = products[idx];
  1915	      if (!p) return;
  1916	      const qty = cantDe(idx);
  1917	
  1918	      const itemPrices = (p.prices || [])
  1919	        .filter(pr => pr && pr.amount > 0)
  1920	        .map(pr => ({
  1921	          priceTypeId: pr.priceTypeId ?? pr.priceType?.id ?? null,
  1922	          label: pr.priceType?.name || pr.label || '',
  1923	          amount: pr.amount,
  1924	        }));
  1925	
  1926	      // prices 배열이 없고 단일 price 만 있는 응답 하위 호환
  1927	      if (itemPrices.length === 0 && p.price) {
  1928	        itemPrices.push({ priceTypeId: null, label: '', amount: p.price });
  1929	      }
  1930	
  1931	      items.push({
  1932	        name: p.name,
  1933	        sku: p.sku || '',
  1934	        barcodeType: 'CODE128',
  1935	        prices: itemPrices,
  1936	        qty,
  1937	      });
  1938	    });
  1939	
  1940	    return items;
  1941	  }
  1942	
  1943	  // [2026-10-07] «Vista Zebra» del lote: el primer producto, como «Imprimir 1 de prueba».
  1944	  //   Lee el diseño GUARDADO (igual que imprimir), así que espera los guardados pendientes.
  1945	  $('#btn-vista-zebra-lote').addEventListener('click', async () => {
  1946	    if (!(await dtGuardarPendiente())) {
  1947	      addLocalLog('No se pudo guardar el diseño de la etiqueta. Probá de nuevo.');
  1948	
  1949	      return;
  1950	    }
  1951	    const items = armarItemsLote(idxsAImprimir()).slice(0, 1);
  1952	    if (items.length === 0) return;
  1953	    mostrarVistaZebra('Vista Zebra · ' + (items[0].name || items[0].sku || ''), {
  1954	      tipo: 'lote', items, opciones: leerOpcionesLote(),
  1955	    });
  1956	  });
  1957	
  1958	  // ── Símbolo del lote: barras (siempre) o QR con el SKU ────────────────────
  1959	  function leerOpcionesLote() {
  1960	    const esQr = !!$('#lote-simbolo-qr')?.checked;
  1961	
  1962	    return {
  1963	      simbolo: esQr ? 'qr' : 'barras',
  1964	      porEtiqueta: esQr && $('#lote-por-2')?.checked ? 2 : 1,
  1965	    };
  1966	  }
  1967	
  1968	  function pintarOpcionesLote() {
  1969	    const o = leerOpcionesLote();
  1970	    const caja = $('#lote-qr-cantidad');
  3010	    const avisos = (r && r.avisos) || [];
  3011	    if (avisos.length === 0) { el.style.display = 'none'; return; }
  3012	    el.style.display = 'block';
  3013	    // [PEDIDO 10] además del nombre cortado: cuánto se achicó el QR por letras grandes
  3014	    const qr = avisos.find(a => a.campo === 'qr');
  3015	    el.style.color = qr && qr.chico ? '#ef5350' : '';
  3016	    el.textContent = avisos.map(a => a.campo === 'qr'
  3017	      ? (a.chico
  3018	        ? `⚠ Con este tamaño de letra el QR bajó a ${String(a.mm).replace('.', ',')} mm: puede no leerse. Achicá la letra.`
  3019	        : `⚠ Con este tamaño el QR bajó a ${String(a.mm).replace('.', ',')} mm (sigue legible). Más grande lo achica.`)
  3020	      : `⚠ El nombre no entra completo: sale «${a.mostrado}» (${a.mostrado.length} de ${a.total} letras). Bajá el tamaño o mové la Descripción.`).join('\n');
  3021	    el.style.whiteSpace = 'pre-line';
  3022	  }
  3023	
  3024	  // Confirmación propia (no window.confirm). Devuelve 'imprimir' | 'prueba' | 'cancelar'.
  3025	  // [2026-10-07 usuario] «Vista Zebra» — la imagen que devuelve el emulador de Zebra (Labelary)
  3026	  //   para el MISMO ZPL que se imprimiría. Sólo con el botón: manda el contenido de la etiqueta.
  3027	  let vistaZebraAbierta = false;
  3028	  async function mostrarVistaZebra(titulo, args) {
  3029	    if (vistaZebraAbierta) return;
  3030	    vistaZebraAbierta = true;
  3031	    const fondo = document.createElement('div');
  3032	    fondo.className = 'modal-fondo';
  3033	    fondo.innerHTML = `<div class="modal-caja vz">
  3034	      <h3>${escHtml(titulo)}</h3>
  3035	      <div class="vz-img"><span style="color:#c8cae0; font-size:12px;">Generando…</span></div>
  3036	      <div class="vz-nota">Dibujo del emulador de Zebra (labelary.com, 203 dpi) con el mismo ZPL que se imprime.
  3037	        Muestra la primera etiqueta. Necesita internet y envía el contenido de la etiqueta al emulador.</div>
  3038	      <div class="acciones"><button class="btn btn-primary" data-r="cerrar">Cerrar</button></div>
  3039	    </div>`;
  3040	    const cerrar = () => { fondo.remove(); vistaZebraAbierta = false; };
  3041	    fondo.addEventListener('click', (e) => { if (e.target === fondo || e.target.dataset.r === 'cerrar') cerrar(); });
  3042	    document.body.appendChild(fondo);
  3043	    let r = null;
  3044	    try { r = await api.vistaZebra(args); } catch (_) { r = null; }
  3045	    if (!fondo.isConnected) return;
  3046	    const caja = fondo.querySelector('.vz-img');
  3047	    if (r && r.ok && r.png) {
  3048	      const img = document.createElement('img');
  3049	      img.src = r.png;
  3050	      img.alt = 'Etiqueta';
  3051	      caja.replaceChildren(img);
  3052	    } else {
  3053	      const msg = document.createElement('span');
  3054	      msg.style.color = '#ff8a80';
  3055	      msg.style.fontSize = '12px';
  3056	      msg.textContent = (r && r.error) || 'No se pudo generar la vista.';
  3057	      caja.replaceChildren(msg);
  3058	    }
  3059	  }
  3060	
  3061	  // diseño en pantalla (sin guardar) + producto de muestra
  3062	  $('#btn-vista-zebra-diseno').addEventListener('click', () => {
  3063	    mostrarVistaZebra('Vista Zebra · diseño actual', { tipo: 'diseno', mode: buildModeFromForm(), sku: sampleSku() });
  3064	  });
  3065	  $('#btn-vista-zebra-test').addEventListener('click', () => {
  3066	    mostrarVistaZebra('Vista Zebra · Imprimir test', { tipo: 'test' });
  3067	  });
  3068	
  3069	  function confirmarImpresion({ titulo, lineas, cortados, dibujo, textoImprimir }) {
  3070	    return new Promise((resolve) => {
  3071	      const fondo = document.createElement('div');
  3072	      fondo.className = 'modal-fondo';
  3073	      const cort = (cortados || []).length;
  3074	      fondo.innerHTML = `<div class="modal-caja">
  3075	        <h3>${escHtml(titulo)}</h3>
  3076	        <div class="pv-exacta" style="margin-bottom:8px;"><canvas width="440" height="120"></canvas></div>
  3077	        <div class="kv">${(lineas || []).join('<br>')}${cort ? `<br><span style="color:#ffb74d">⚠ ${cort} producto(s) con el nombre cortado</span>` : ''}</div>
  3078	        <div class="acciones">
  3079	          <button class="btn btn-secondary" data-r="cancelar">Revisar</button>
  3080	          <button class="btn btn-secondary" data-r="prueba">Imprimir 1 de prueba</button>
  3081	          <button class="btn btn-primary" data-r="imprimir">${escHtml(textoImprimir || 'Imprimir')}</button>
  3082	        </div></div>`;
  3083	      document.body.appendChild(fondo);
  3084	      if (dibujo && dibujo.dibujo) dibujarEtiqueta(fondo.querySelector('canvas'), dibujo);
  3085	      else fondo.querySelector('.pv-exacta').style.display = 'none';
vista-zebra

  ✓ lote: sólo el primer producto y una sola etiqueta — lo mismo que «Imprimir 1 de prueba»
  ✓ lote: los precios salen en el orden de los niveles elegidos (Lista, Mayorista)
  ✓ lote QR en doble banda con 2 por etiqueta: una fila de 4
  ✓ lote QR: respeta lo guardado en la pestaña QR (sin precio → no sale el precio)
  ✓ diseño: usa el modo de la pantalla (sin guardar) y el SKU de muestra
  ✓ test: exactamente la etiqueta de «Imprimir test»
  ✓ sin productos o tipo desconocido: nada que mostrar (no se inventa una etiqueta)
  ✓ emulador: tamaño en pulgadas a 203 dpi según ^PW/^LL
  ✓ emulador: manda el ZPL tal cual y devuelve la imagen como data URL
  ✓ emulador: límite, error y sin red → mensaje, nunca excepción

10 ok

hook: PostToolUse
hook: PostToolUse
hook: PostToolUse Failed
hook: PostToolUse Completed
codex
La prueba incluida pasa y sí demuestra equivalencia byte a byte para lote simple, QR y test. Estoy cerrando dos bordes que esa prueba no cubre: validación/volumen del IPC y los límites reales de la API (dimensiones, payload y respuesta), porque pueden convertir una vista en algo distinto o bloquear el proceso principal.
hook: PreToolUse
hook: PreToolUse Completed
web search: 
web search: site:labelary.com service API limits label size request rate ZPL maximum payload ...
hook: PostToolUse
hook: PostToolUse Completed
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
exec
/bin/zsh -lc "rg -n \"id=\\\"lay-(w|h)\\\"|lay-w|lay-h|width.*max|height.*max\" zebra-agent/renderer/index.html zebra-agent/src/zpl-formatter.js; sed -n '280,345p' zebra-agent/main.js; rg -n \"function escHtml|const escHtml\" zebra-agent/renderer/index.html; git diff --check -- zebra-agent/main.js zebra-agent/preload.js zebra-agent/renderer/index.html zebra-agent/src/vista-zebra.js zebra-agent/test/vista-zebra.test.js" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
zebra-agent/renderer/index.html:199:    .modal-caja { background:#16213e; border:1px solid #f5a623; border-radius:12px; padding:16px 18px; width:480px; max-width:92vw; }
zebra-agent/renderer/index.html:205:    .modal-caja.vz { width:auto; min-width:360px; max-width:94vw; }
zebra-agent/renderer/index.html:207:    .vz-img img { background:#fff; max-width:86vw; max-height:60vh; image-rendering:pixelated; box-shadow:0 2px 14px rgba(0,0,0,.55); }
zebra-agent/renderer/index.html:624:            <label>Ancho</label><input type="number" id="lay-w" step="any">
zebra-agent/renderer/index.html:625:            <label>Alto</label><input type="number" id="lay-h" step="any">
zebra-agent/renderer/index.html:695:            <input type="number" id="qr-width-mm" min="20" max="120" step="1" value="50">
zebra-agent/renderer/index.html:697:            <input type="number" id="qr-height-mm" min="10" max="80" step="1" value="25">
zebra-agent/renderer/index.html:1037:    $('#lay-w').value = sizeToDisplay(currentMode.width);
zebra-agent/renderer/index.html:1038:    $('#lay-h').value = sizeToDisplay(currentMode.height);
zebra-agent/renderer/index.html:1069:    const wDots = displayToDots('#lay-w');
zebra-agent/renderer/index.html:1070:    const hDots = displayToDots('#lay-h');
zebra-agent/renderer/index.html:1072:    $('#lay-w').value = sizeToDisplay(wDots);
zebra-agent/renderer/index.html:1073:    $('#lay-h').value = sizeToDisplay(hDots);
zebra-agent/renderer/index.html:1084:    const width = displayToDots('#lay-w') || base.width;
zebra-agent/renderer/index.html:1085:    const height = displayToDots('#lay-h') || base.height;
zebra-agent/renderer/index.html:1102:  ['#lay-w', '#lay-h', '#sample-sku'].forEach(s => $(s).addEventListener('input', drawPreview));
zebra-agent/renderer/index.html:1216:    const scale = Math.min(maxW / mode.width, maxH / mode.height);
zebra-agent/renderer/index.html:2475:          width: Math.max(1, cell - x - QR_MARGIN) * k + 'px', fontSize: Math.max(6, fs * k) + 'px',
  tray.setContextMenu(contextMenu);
}

// 「Salir」: 인쇄가 끝난 뒤에 끝낸다. 업데이트는 설치하지 않는다(사용자가 OK 할 때만).
function salir() {
  // ★ se espera a que termine la impresión en curso (y su ACK) —
  //   cortar a mitad de un trabajo lo pierde o, si el servidor lo reenvía, sale dos veces.
  actividadImpresion.esperarQuieto({ plazoMs: 30 * 1000 }).finally(() => app.exit(0));
}

function setConnectionStatus(status) {
  connectionStatus = status;
  updateTrayMenu();
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send('connection-status', status);
  }
}

// ─── 창 관리 ────────────────────────────────────────────────────────────────
function openSetupWizard() {
  if (setupWindow) { setupWindow.focus(); return; }

  setupWindow = new BrowserWindow({
    width: 520,
    height: 520,
    resizable: false,
    title: 'VentaGO Zebra Agent — Configuración inicial',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  setupWindow.loadFile('renderer/setup-wizard.html');
  setupWindow.on('closed', () => { setupWindow = null; });
}

function openMainWindow() {
  if (mainWindow) { mainWindow.show(); mainWindow.focus(); return; }

  // 2탭 / 2패널 레이아웃 — 가로 확장 고정 크기
  mainWindow = new BrowserWindow({
    width: 1150,
    height: 820,
    resizable: true,
    minWidth: 1000,
    minHeight: 700,
    title: 'VentaGO Zebra Agent',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  mainWindow.loadFile('renderer/index.html');

  mainWindow.webContents.on('did-finish-load', () => {
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('connection-status', connectionStatus);
    }
  });

  // 닫기 → 숨기기 (트레이 상주)
  mainWindow.on('close', (e) => {
2938:  function escHtml(s) {

hook: PostToolUse
hook: PostToolUse
hook: PostToolUse Failed
hook: PostToolUse Completed
codex
[MEDIUM] `zebra-agent/src/vista-zebra.js:33` — 15인치를 초과하는 라벨을 조용히 축소해 실제 출력과 다른 이미지를 표시함

  문제: `^PW`/`^LL` 또는 화면에서 전달된 크기가 15인치를 넘으면 URL 크기만 15인치로 강제한다. ZPL 내부 좌표와 `^PW`/`^LL`은 원래 값 그대로이므로 Labelary 결과가 잘리거나 축소된 것처럼 보일 수 있다. UI의 `lay-w`, `lay-h`에는 `min`/`max`도 없다. “실제로 출력될 모습”이라는 기능 보장과 충돌한다.

  근거:

  ```js
  const pulgadas = (dots) =>
    Math.min(MAX_PULGADAS, Math.max(0.1, dots / DPI)).toFixed(2);
  ```

  Labelary는 라벨 한 변을 최대 15인치로 제한하며 초과 시 HTTP 400을 반환하도록 정의한다. 현재 코드는 그 오류를 숨기고 다른 크기로 요청한다. [Labelary 공식 API 제한](https://labelary.com/service.html)

  수정: clamp하지 말고 `ancho` 또는 `alto`가 `0 < dots <= 15 * DPI` 범위를 벗어나면 `{ ok:false, error:'...' }`를 반환한다. 편집 입력에도 동일한 범위를 적용한다.

[LOW] `zebra-agent/src/vista-zebra.js:60` — 응답 크기와 실제 MIME 검증 없이 전부 main 프로세스 메모리에 적재함

  문제: `arrayBuffer()`가 응답 전체를 메모리에 올린 다음 다시 `Buffer`와 base64 문자열을 만든다. 정상적인 Labelary 응답도 최대 10MB 이미지 버퍼가 허용되므로 IPC 전달 시 약 13.3MB base64 문자열과 복사본들이 생긴다. 또한 HTTP 200이면 `Content-Type` 확인 없이 모두 PNG로 취급한다. 외부 서비스나 프록시의 비정상 대용량 응답은 Electron main 프로세스 메모리를 불필요하게 점유할 수 있다.

  근거:

  ```js
  const buf = Buffer.from(await r.arrayBuffer());

  return {
    ok: true,
    png: `data:image/png;base64,${buf.toString('base64')}`,
  };
  ```

  수정: `Content-Type`이 `image/png`인지 확인하고, `Content-Length` 및 스트리밍 누적 바이트에 합리적인 상한을 둔다. 이 앱의 작은 가격표 크기를 고려하면 10MB보다 훨씬 낮은 상한으로 충분하다.

그 외 확인 결과:

- `armarItemsLote()` 추출 전후 데이터 구성은 동일하며 인쇄 흐름도 그대로다.
- 포함된 `vista-zebra.test.js` 10개 테스트가 모두 통과했다.
- lote의 일반 바코드·QR 및 test ZPL은 실제 `print:labels`/`printTest()` 경로와 byte-for-byte 동일하게 구성된다.
- IPC로 외부에 전달되는 것은 첫 상품의 선택된 가격·이름·SKU가 포함된 ZPL이다. 프린터 설정이나 전체 상품 목록은 Labelary로 전송되지 않는다.
- 모달 제목은 `escHtml`, 오류는 `textContent`, 이미지는 `img.src`로 처리되어 이 diff에서 구체적인 XSS 경로는 발견하지 못했다.
- Electron 28의 main 프로세스에는 Node 18 계열의 `fetch`와 `AbortSignal.timeout()`이 있어 현재 사용법은 호환된다.
- 연속 더블클릭은 `vistaZebraAbierta`를 비동기 호출 전에 설정하므로 동일 모달 요청을 중복 생성하지 않는다. 닫은 뒤 즉시 다시 여는 경우 이전 fetch는 취소되지 않지만 결과는 분리된 DOM에 반영되지 않는다.
- Labelary의 3요청/초, 일 5,000요청, 요청당 50라벨, 본문 1MB 제한 중 현재 생성 경로는 첫 행만 보내므로 50라벨 제한에는 걸리지 않는다. 429 처리도 존재한다. 다만 모달을 닫을 때 요청을 abort하지 않아 빠른 재시도는 3요청/초 제한을 소비할 수 있다. [Labelary 공식 API 제한](https://labelary.com/service.html)
hook: Stop
hook: Stop
hook: Stop Failed
hook: Stop Completed
tokens used
56,548
[MEDIUM] `zebra-agent/src/vista-zebra.js:33` — 15인치를 초과하는 라벨을 조용히 축소해 실제 출력과 다른 이미지를 표시함

  문제: `^PW`/`^LL` 또는 화면에서 전달된 크기가 15인치를 넘으면 URL 크기만 15인치로 강제한다. ZPL 내부 좌표와 `^PW`/`^LL`은 원래 값 그대로이므로 Labelary 결과가 잘리거나 축소된 것처럼 보일 수 있다. UI의 `lay-w`, `lay-h`에는 `min`/`max`도 없다. “실제로 출력될 모습”이라는 기능 보장과 충돌한다.

  근거:

  ```js
  const pulgadas = (dots) =>
    Math.min(MAX_PULGADAS, Math.max(0.1, dots / DPI)).toFixed(2);
  ```

  Labelary는 라벨 한 변을 최대 15인치로 제한하며 초과 시 HTTP 400을 반환하도록 정의한다. 현재 코드는 그 오류를 숨기고 다른 크기로 요청한다. [Labelary 공식 API 제한](https://labelary.com/service.html)

  수정: clamp하지 말고 `ancho` 또는 `alto`가 `0 < dots <= 15 * DPI` 범위를 벗어나면 `{ ok:false, error:'...' }`를 반환한다. 편집 입력에도 동일한 범위를 적용한다.

[LOW] `zebra-agent/src/vista-zebra.js:60` — 응답 크기와 실제 MIME 검증 없이 전부 main 프로세스 메모리에 적재함

  문제: `arrayBuffer()`가 응답 전체를 메모리에 올린 다음 다시 `Buffer`와 base64 문자열을 만든다. 정상적인 Labelary 응답도 최대 10MB 이미지 버퍼가 허용되므로 IPC 전달 시 약 13.3MB base64 문자열과 복사본들이 생긴다. 또한 HTTP 200이면 `Content-Type` 확인 없이 모두 PNG로 취급한다. 외부 서비스나 프록시의 비정상 대용량 응답은 Electron main 프로세스 메모리를 불필요하게 점유할 수 있다.

  근거:

  ```js
  const buf = Buffer.from(await r.arrayBuffer());

  return {
    ok: true,
    png: `data:image/png;base64,${buf.toString('base64')}`,
  };
  ```

  수정: `Content-Type`이 `image/png`인지 확인하고, `Content-Length` 및 스트리밍 누적 바이트에 합리적인 상한을 둔다. 이 앱의 작은 가격표 크기를 고려하면 10MB보다 훨씬 낮은 상한으로 충분하다.

그 외 확인 결과:

- `armarItemsLote()` 추출 전후 데이터 구성은 동일하며 인쇄 흐름도 그대로다.
- 포함된 `vista-zebra.test.js` 10개 테스트가 모두 통과했다.
- lote의 일반 바코드·QR 및 test ZPL은 실제 `print:labels`/`printTest()` 경로와 byte-for-byte 동일하게 구성된다.
- IPC로 외부에 전달되는 것은 첫 상품의 선택된 가격·이름·SKU가 포함된 ZPL이다. 프린터 설정이나 전체 상품 목록은 Labelary로 전송되지 않는다.
- 모달 제목은 `escHtml`, 오류는 `textContent`, 이미지는 `img.src`로 처리되어 이 diff에서 구체적인 XSS 경로는 발견하지 못했다.
- Electron 28의 main 프로세스에는 Node 18 계열의 `fetch`와 `AbortSignal.timeout()`이 있어 현재 사용법은 호환된다.
- 연속 더블클릭은 `vistaZebraAbierta`를 비동기 호출 전에 설정하므로 동일 모달 요청을 중복 생성하지 않는다. 닫은 뒤 즉시 다시 여는 경우 이전 fetch는 취소되지 않지만 결과는 분리된 DOM에 반영되지 않는다.
- Labelary의 3요청/초, 일 5,000요청, 요청당 50라벨, 본문 1MB 제한 중 현재 생성 경로는 첫 행만 보내므로 50라벨 제한에는 걸리지 않는다. 429 처리도 존재한다. 다만 모달을 닫을 때 요청을 abort하지 않아 빠른 재시도는 3요청/초 제한을 소비할 수 있다. [Labelary 공식 API 제한](https://labelary.com/service.html)

## 처리
- [MEDIUM] 15인치 초과를 조용히 축소 → **수용.** 축소하지 않고 오류로 안내, 요청 자체를 안 보낸다(테스트 추가).
- [LOW] 응답 MIME·크기 무검증 → **수용.** `image/png` 이 아니거나 3MB 초과면 오류.
- 모달 닫을 때 fetch abort 안 함 → 결과는 버려지고 429 는 안내되므로 보류.
