Reading additional input from stdin...
2026-10-07T19:42:32.384201Z ERROR codex_models_manager::cache: failed to load models cache: missing field `base_instructions` at line 140 column 5
OpenAI Codex v0.146.0
--------
workdir: /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
model: gpt-5.6-sol
provider: openai
approval: never
sandbox: workspace-write [workdir, /tmp, $TMPDIR]
reasoning effort: none
reasoning summaries: none
session id: 01a117e3-9355-7532-a749-7ee89aa374bf
--------
user
Revisá este diff de zebra-agent (Electron, ZPL 203dpi). Pedido del usuario: en el modo Poliamida (etiqueta 25×50mm, 200×400 dots, antes siempre girada 'R') poder elegir vertical u horizontal, para la etiqueta real y la de prueba. Cada orientación con su diseño: custom.layout (vertical, compatible con guardados viejos) y custom.layoutN (horizontal), custom.orientation. modoEfectivo/guardarCustom son puros. Nombre con ^FB en horizontal (lines:3). Prueba angosta nueva (testAngosta). Además se movió el código de barras vertical de x60 a x80 porque los dígitos pisaban el nivel de precio. Buscá errores concretos: guardados viejos, cambiar de modo, Restablecer, drawPreview/buildModeFromForm con orientación, ^FB, QR, Vista Zebra, cualquier lugar que lea mode.orientation o labelLayouts sin pasar por modoEfectivo. No estilo.
diff --git a/zebra-agent/main.js b/zebra-agent/main.js
index 25ef367..781263d 100644
--- a/zebra-agent/main.js
+++ b/zebra-agent/main.js
@@ -8,6 +8,7 @@ const {
   formatBatchLabels, formatQrLabel, formatTestLabel, resolveMode, darknessZpl, speedZpl,
   LABEL_MODES, LEGACY_PRESET_ALIASES,
   formatQrLabelConAvisos, zplADibujo, qrLotePreview, filasDeLoteQrTotal, qrLoteFilas,
+  modoEfectivo, guardarCustom,
 } = require('./src/zpl-formatter');
 const { prepareItems: prepareItemsPure } = require('./src/price-select');
 const { sendZpl: sendZplSinContar, testConnection: testPrinterConnection, listUsbPrinters } = require('./src/zebra-printer');
@@ -122,18 +123,9 @@ function getEffectiveMode() {
   const base = resolveMode(modeKey);
   const custom = (store.get('labelLayouts') || {})[base.key] || {};
 
-  return {
-    ...base,
-    width: custom.width || base.width,
-    height: custom.height || base.height,
-    // duplicado 절반 너비는 커스텀 width 의 절반으로 재계산
-    halfWidth: base.duplicate
-      ? Math.round((custom.width || base.width) / 2)
-      : base.halfWidth,
-    layout: custom.layout ? { ...base.layout, ...custom.layout } : base.layout,
-    // 출력 밀도/속도는 모드가 아닌 프린터 전역 설정
-    ...getPrintSettings(),
-  };
+  // [2026-10-07] orientación elegida (Poliamida) + diseño de esa orientación — src/zpl-formatter.js
+  // 출력 밀도/속도는 모드가 아닌 프린터 전역 설정
+  return modoEfectivo(base, custom, getPrintSettings());
 }
 
 // ─── 출력용 items 전처리 (가격 nivel 필터 적용 — src/price-select.js 공용 로직) ──
@@ -397,6 +389,7 @@ ipcMain.handle('label:presets', () => {
     height: p.height,
     duplicate: !!p.duplicate,
     orientation: p.orientation || 'N',
+    orientable: !!p.orientable,
     layout: p.layout,
   }));
 });
@@ -421,24 +414,35 @@ ipcMain.handle('label:setPreset', (_event, modeKey) => {
 });
 
 // 현재 모드의 커스텀 레이아웃/크기 저장 (null → 해당 모드 초기화)
+// [2026-10-07] guarda sólo el diseño de la orientación actual: el de la otra queda intacto
 ipcMain.handle('label:setLayout', (_event, custom) => {
-  const modeKey = getEffectiveMode().key;
+  const base = resolveMode(getEffectiveMode().key);
   const layouts = store.get('labelLayouts') || {};
 
-  if (custom == null) {
-    delete layouts[modeKey];
-  } else {
-    // 밀도/속도는 모드별이 아닌 전역(printSettings) — 여기서 저장하지 않음
-    layouts[modeKey] = {
-      width: custom.width || undefined,
-      height: custom.height || undefined,
+  // 밀도/속도는 모드별이 아닌 전역(printSettings) — 여기서 저장하지 않음
+  layouts[base.key] = custom == null
+    ? guardarCustom(layouts[base.key], base, { tipo: 'reset' })
+    : guardarCustom(layouts[base.key], base, {
+      tipo: 'diseno',
+      width: custom.width,
+      height: custom.height,
       layout: custom.layout || custom, // { layout } 또는 layout 직접 전달 모두 허용
-    };
-  }
+    });
 
   store.set('labelLayouts', layouts);
 });
 
+// [2026-10-07 usuario] Poliamida: imprimir en vertical ('R') u horizontal ('N')
+ipcMain.handle('label:setOrientation', (_event, orientation) => {
+  const base = resolveMode(getEffectiveMode().key);
+  if (!base.orientable) return { ok: false };
+  const layouts = store.get('labelLayouts') || {};
+  layouts[base.key] = guardarCustom(layouts[base.key], base, { tipo: 'orientacion', orientation: orientation === 'N' ? 'N' : 'R' });
+  store.set('labelLayouts', layouts);
+
+  return { ok: true, orientation: getEffectiveMode().orientation };
+});
+
 // 전역 출력 파라미터 조회 — { darkness, speed } (null = 프린터 기본값)
 ipcMain.handle('print:getSettings', () => getPrintSettings());
 
diff --git a/zebra-agent/preload.js b/zebra-agent/preload.js
index 0e64abd..72ab6b8 100644
--- a/zebra-agent/preload.js
+++ b/zebra-agent/preload.js
@@ -27,6 +27,7 @@ contextBridge.exposeInMainWorld('electronAPI', {
   getLabelConfig: () => ipcRenderer.invoke('label:getConfig'),
   setLabelPreset: (key) => ipcRenderer.invoke('label:setPreset', key),
   setLabelLayout: (layout) => ipcRenderer.invoke('label:setLayout', layout),
+  setLabelOrientation: (o) => ipcRenderer.invoke('label:setOrientation', o),
   setPriceSelection: (selection) => ipcRenderer.invoke('label:setPriceSelection', selection),
 
   // 출력 파라미터 (전역: 모든 모드 + QR 공통) — { darkness 0~30, speed 2~14 }
diff --git a/zebra-agent/renderer/index.html b/zebra-agent/renderer/index.html
index 539ab9e..22db04d 100644
--- a/zebra-agent/renderer/index.html
+++ b/zebra-agent/renderer/index.html
@@ -518,6 +518,15 @@
         <div class="card">
           <div class="card-title">Modo de impresión</div>
           <div class="preset-cards" id="preset-cards"></div>
+          <!-- [2026-10-07 usuario] Poliamida: vertical u horizontal — cada una con su diseño -->
+          <div id="orientacion-box" style="display:none; margin-top:10px;">
+            <div style="font-size:12px; color:#8a8db0; margin-bottom:4px;">Orientación de la impresión</div>
+            <div class="qr-seg">
+              <label><input type="radio" name="orientacion" value="R"><span>Vertical</span></label>
+              <label><input type="radio" name="orientacion" value="N"><span>Horizontal</span></label>
+            </div>
+            <div style="font-size:11px; color:#8a8db0; margin-top:4px;">Cada orientación guarda su propio diseño. Mirala con «Ver cómo sale en la Zebra».</div>
+          </div>
         </div>
 
         <div class="card">
@@ -979,6 +988,7 @@
     currentMode = config.mode || config.preset;
     priceSelection = config.priceSelection || [];
     renderPresetCards();
+    pintarOrientacion();
     loadLayoutEditor();
     await loadPrintSettings();
     renderNivelCombos();
@@ -1009,6 +1019,7 @@
         const cfg = await api.getLabelConfig();
         currentMode = cfg.mode || cfg.preset;
         renderPresetCards();
+        pintarOrientacion();
         loadLayoutEditor();
         updateModeChip();
         drawPreview();
@@ -1017,6 +1028,32 @@
     });
   }
 
+  // [2026-10-07] orientación (sólo modos `orientable`, hoy Poliamida)
+  function pintarOrientacion() {
+    const base = modes.find(m => m.key === currentModeKey);
+    const box = $('#orientacion-box');
+    box.style.display = base && base.orientable ? 'block' : 'none';
+    const actual = currentMode?.orientation === 'N' ? 'N' : 'R';
+    document.querySelectorAll('input[name="orientacion"]').forEach(r => { r.checked = r.value === actual; });
+  }
+
+  document.querySelectorAll('input[name="orientacion"]').forEach(r => {
+    r.addEventListener('change', async () => {
+      if (!r.checked) return;
+      try {
+        await api.setLabelOrientation(r.value);
+      } catch (err) {
+        addLocalLog('No se pudo cambiar la orientación: ' + err.message);
+      }
+      // lo que quedó guardado manda (si no se pudo, vuelve el radio)
+      currentMode = (await api.getLabelConfig()).mode;
+      pintarOrientacion();
+      loadLayoutEditor();
+      drawPreview();
+      addLocalLog('Orientación: ' + (currentMode?.orientation === 'N' ? 'horizontal' : 'vertical'));
+    });
+  });
+
   // ── 레이아웃 편집기 ──
   const LAYOUT_FIELDS = [
     ['#lay-name-x', 'name', 'x'], ['#lay-name-y', 'name', 'y'], ['#lay-name-fs', 'name', 'fontSize'],
@@ -1090,6 +1127,8 @@
 
     return {
       ...base,
+      // [2026-10-07] la orientación elegida (no la de fábrica del modo)
+      orientation: currentMode?.orientation || base.orientation,
       width,
       height,
       halfWidth: base.duplicate ? Math.round(width / 2) : undefined,
diff --git a/zebra-agent/src/zpl-formatter.js b/zebra-agent/src/zpl-formatter.js
index 17ea2b7..f5c31ee 100644
--- a/zebra-agent/src/zpl-formatter.js
+++ b/zebra-agent/src/zpl-formatter.js
@@ -81,17 +81,90 @@ const LABEL_MODES = {
     height: 400,
     duplicate: false,
     orientation: 'R',
+    // [2026-10-07 usuario] «출력을 가로로 할지 세로로 할지도 결정할 수 있어야» — la persona elige.
+    //   Cada orientación tiene su diseño (los x/y de una no sirven para la otra).
+    orientable: true,
     layout: {
       priceCount: 1,
       name:    { x: 160, y: 10,  fontSize: 20 },
-      barcode: { x: 60,  y: 10,  height: 45, moduleWidth: 3 },
+      // [2026-10-07] x 60→80: los números del código (debajo de las barras, girados) pisaban
+      //   la palabra del nivel de precio (visto con la Vista Zebra)
+      barcode: { x: 80,  y: 10,  height: 45, moduleWidth: 3 },
       price1:  { x: 20,  y: 10,  fontSize: 24, bold: true },
       price2:  { x: 20,  y: 200, fontSize: 18, bold: false },
       price3:  { x: 20,  y: 300, fontSize: 18, bold: false },
     },
+    // horizontal: 25 mm de ancho → el nombre en hasta 3 renglones, el código abajo y el precio
+    //   al pie (autoPrices). El código entra achicado (autoFit) — con SKU largos puede quedar fino.
+    layoutHorizontal: {
+      priceCount: 1,
+      name:    { x: 10, y: 12,  fontSize: 22, lines: 3 },
+      barcode: { x: 10, y: 100, height: 80, moduleWidth: 3 },
+      price1:  { x: 10, y: 330, fontSize: 40, bold: true },
+      price2:  { x: 10, y: 280, fontSize: 22, bold: false },
+      price3:  { x: 10, y: 240, fontSize: 22, bold: false },
+    },
   },
 };
 
+/**
+ * [2026-10-07] Modo efectivo = modo base + lo guardado por la persona (labelLayouts[modo]).
+ *   custom: { width, height, layout, orientation?, layoutN? }
+ *   ★ `layout` es el diseño de la orientación de fábrica (el que existía antes: los guardados
+ *     viejos siguen valiendo); `layoutN` el de horizontal, sólo en modos `orientable`.
+ */
+function modoEfectivo(base, custom = {}, extra = {}) {
+  const c = custom || {};
+  const horizontal = !!(base.orientable && base.layoutHorizontal && c.orientation === 'N');
+  const baseLayout = horizontal ? base.layoutHorizontal : base.layout;
+  const propio = horizontal ? c.layoutN : c.layout;
+  const width = c.width || base.width;
+
+  return {
+    ...base,
+    orientation: horizontal ? 'N' : base.orientation,
+    width,
+    height: c.height || base.height,
+    // duplicado 절반 너비는 커스텀 width 의 절반으로 재계산
+    halfWidth: base.duplicate ? Math.round(width / 2) : base.halfWidth,
+    layout: propio ? { ...baseLayout, ...propio } : baseLayout,
+    ...extra,
+  };
+}
+
+/**
+ * [2026-10-07] Lo que se guarda al tocar «Guardar diseño» / «Restablecer» / la orientación,
+ *   sin perder el diseño de la OTRA orientación.
+ * @param {object} prev  lo guardado hasta ahora (labelLayouts[modo])
+ * @param {object} base  el modo de fábrica
+ * @param {{ tipo:'diseno'|'reset'|'orientacion', width?, height?, layout?, orientation? }} cambio
+ */
+function guardarCustom(prev, base, cambio) {
+  const p = { ...(prev || {}) };
+  const horizontal = !!(base.orientable && base.layoutHorizontal && p.orientation === 'N');
+  if (cambio.tipo === 'orientacion') {
+    if (!base.orientable || !base.layoutHorizontal) return p;
+    if (cambio.orientation === 'N') p.orientation = 'N';
+    else delete p.orientation;
+
+    return p;
+  }
+  if (cambio.tipo === 'reset') {
+    delete p.width;
+    delete p.height;
+    if (horizontal) delete p.layoutN;
+    else delete p.layout;
+
+    return p;
+  }
+  p.width = cambio.width || undefined;
+  p.height = cambio.height || undefined;
+  if (horizontal) p.layoutN = cambio.layout;
+  else p.layout = cambio.layout;
+
+  return p;
+}
+
 // 구버전 프리셋 키 → 신규 모드 키 매핑 (설정 마이그레이션용)
 const LEGACY_PRESET_ALIASES = {
   '50x25-simple': 'simple-face',
@@ -340,7 +413,12 @@ function renderCopy(item, layout, orientation, offsetX = 0, region = { width: 40
   // 상품명 (제품 설명)
   const nm = layout.name || { x: 10, y: 5, fontSize: 20 };
   if (item.name) {
-    lines.push(`^FO${nm.x + offsetX},${nm.y}${font},${nm.fontSize},${nm.fontSize}^FD${sanitize(item.name)}^FS`);
+    // [2026-10-07] `lines` > 1: el nombre se parte en renglones dentro del ancho (^FB) —
+    //   en una etiqueta angosta en horizontal no entra en uno
+    const renglones = Number(nm.lines) > 1 ? Math.min(5, Number(nm.lines)) : 0;
+    const ancho = orientation === 'R' ? region.height - nm.y - 10 : region.width - nm.x - 10;
+    const fb = renglones && ancho > 0 ? `^FB${ancho},${renglones},0,L,0` : '';
+    lines.push(`^FO${nm.x + offsetX},${nm.y}${font},${nm.fontSize},${nm.fontSize}${fb}^FD${sanitize(item.name)}^FS`);
   }
 
   // 바코드 (SKU를 바코드 값으로 사용)
@@ -1069,6 +1147,9 @@ function zplADibujo(zpl) {
  *   etiqueta izquierda y la derecha en blanco. Ahora sigue el modo como `formatLabel`:
  *   ^PW = ancho del modo y, si es doble banda, la misma prueba en las dos mitades.
  * ★ Los demás modos salen igual que antes (50×25, a la izquierda).
+ * ★ [2026-10-07] Etiqueta angosta (Poliamida, 25×50): la prueba sigue la orientación elegida —
+ *   vertical = girada (^A0R/^BCR, como la etiqueta real), horizontal = 25 mm de ancho con un
+ *   código corto que entra entero. Antes salía la de 50×25 y se cortaba («…TES»).
  *
  * @param {Object} mode - modo efectivo (getEffectiveMode): width, halfWidth, duplicate, name
  * @param {{darkness?: number|null, speed?: number|null}} ajustes
@@ -1076,6 +1157,8 @@ function zplADibujo(zpl) {
  */
 function formatTestLabel(mode, { darkness = null, speed = null } = {}) {
   const doble = !!(mode && mode.duplicate && mode.halfWidth);
+  const angosta = !doble && mode && mode.width && mode.width < 400;
+  if (angosta) return testAngosta(mode, { darkness, speed });
   const ancho = doble ? mode.width : 400;
   // ★ [codex 041] el código se achica a su etiqueta, igual que `renderCopy`: con ^BY3 mide
   //   435 dots. En doble banda la izquierda se metía en la derecha; en una cara (400 dots)
@@ -1110,7 +1193,49 @@ function formatTestLabel(mode, { darkness = null, speed = null } = {}) {
     .join('\n');
 }
 
+function testAngosta(mode, { darkness, speed }) {
+  const ancho = mode.width;
+  const alto = mode.height || 400;
+  const girada = mode.orientation === 'R';
+  const pie = `D:${darkness ?? 'auto'} V:${speed ?? 'auto'}`;
+  let campos;
+  if (girada) {
+    // el texto corre a lo largo de la etiqueta (+y); x = de afuera hacia adentro
+    const by = effectiveModuleWidth({ x: 0, y: 10, moduleWidth: 3 }, '1234567890', 'CODE128', 'R', { width: ancho, height: alto });
+    campos = [
+      `^FO${ancho - 34},10^A0R,22,22^FDVENTAGO ZEBRA TEST^FS`,
+      `^FO${ancho - 120},10^BY${by}^BCR,60,Y,N,N^FD1234567890^FS`,
+      `^FO26,10^A0R,28,28^FD$0.00^FS`,
+      `^FO6,10^A0R,16,16^FD${pie} · VERTICAL^FS`,
+    ];
+  } else {
+    const by = effectiveModuleWidth({ x: 10, moduleWidth: 3 }, '1234', 'CODE128', 'N', { width: ancho, height: alto });
+    campos = [
+      `^FO10,10^A0N,22,22^FB${ancho - 20},2,0,L,0^FDVENTAGO ZEBRA TEST^FS`,
+      `^FO10,70^BY${by}^BCN,60,Y,N,N^FD1234^FS`,
+      `^FO10,170^A0N,28,28^FD$0.00^FS`,
+      `^FO10,210^A0N,16,16^FD${pie}^FS`,
+      `^FO10,232^A0N,16,16^FDHORIZONTAL^FS`,
+    ];
+  }
+
+  return [
+    darknessZpl(darkness),
+    '^XA',
+    `^PW${ancho}`,
+    `^LL${alto}`,
+    '^CI28',
+    speedZpl(speed),
+    ...campos,
+    '^XZ',
+  ]
+    .filter(Boolean)
+    .join('\n');
+}
+
 module.exports = {
+  modoEfectivo,
+  guardarCustom,
   formatLabel,
   formatTestLabel,
   formatBatchLabels,
diff --git a/zebra-agent/test/test-label.test.js b/zebra-agent/test/test-label.test.js
index 6f3b8e4..de8a078 100644
--- a/zebra-agent/test/test-label.test.js
+++ b/zebra-agent/test/test-label.test.js
@@ -70,11 +70,18 @@ for (const key of ['simple-face', 'doble-face']) {
   const byK = Number(/\^BY(\d+)/.exec(z)[1]);
   ok(`${key}: el código entra en 400 dots (^BY${byK})`, 10 + code128Modules('1234567890') * byK <= 400);
 }
-// poliamida (200 de ancho): el código se achica a lo que entra, nunca más ancho que antes
-const zPoli = formatTestLabel(resolveMode('poliamida-vertical'), {});
-const byPoli = Number(/\^BY(\d+)/.exec(zPoli)[1]);
-ok(`poliamida: ^BY${byPoli} → entra en 200`, 10 + code128Modules('1234567890') * byPoli <= 200);
-ok('poliamida: resto igual que antes', zPoli.replace(`^BY${byPoli}`, '^BY3') === ANTES(null, null));
+// [2026-10-07] poliamida (25×50): la prueba sigue la orientación elegida — ya no la de 50×25 cortada
+const { modoEfectivo } = require('../src/zpl-formatter');
+const poli = resolveMode('poliamida-vertical');
+const zV = formatTestLabel(modoEfectivo(poli, {}), {});
+ok('poliamida vertical: ^PW200 ^LL400, texto y código girados', zV.includes('^PW200') && zV.includes('^LL400') && zV.includes('^A0R') && /\^BCR/.test(zV) && !zV.includes('^A0N'));
+const byV = Number(/\^BY(\d+)/.exec(zV)[1]);
+ok(`poliamida vertical: el código (^BY${byV}) entra a lo largo de los 400`, 10 + code128Modules('1234567890') * byV <= 400 && byV >= 2);
+const zH = formatTestLabel(modoEfectivo(poli, { orientation: 'N' }), {});
+const byH = Number(/\^BY(\d+)/.exec(zH)[1]);
+ok('poliamida horizontal: derecho, en 200 de ancho', zH.includes('^PW200') && zH.includes('^A0N') && /\^BCN/.test(zH) && !zH.includes('^A0R'));
+ok(`poliamida horizontal: código corto entero y legible (^BY${byH})`, zH.includes('^FD1234^FS') && 10 + code128Modules('1234') * byH <= 190 && byH >= 2);
+ok('poliamida horizontal: el título se parte en el ancho (^FB) — antes salía «…TES»', /\^FB180,2/.test(zH));
 // una cara con ancho personalizado mayor: la prueba sigue en ^PW400, así que el código también
 ok('una cara ancha: el código sigue ajustado a 400', formatTestLabel({ ...resolveMode('simple-face'), width: 832 }, {}) === ANTES_BY2);
 // sin modo (por si acaso): como una cara
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
검토 범위를 확인했습니다. 제공된 diff뿐 아니라 실제 `zebra-agent`의 호출 경로와 협업 프로토콜을 읽어, 요청하신 회귀 지점을 줄 단위 근거로 점검하겠습니다. 파일 수정은 하지 않습니다.
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
exec
/bin/zsh -lc "sed -n '1,240p' .team/REVIEW-PROTOCOL.md && rg -n \"getEffectiveMode|labelLayouts|\\.orientation|drawPreview|buildModeFromForm|setLayout|setOrientation|formatQr|Vista|zplADibujo|formatTestLabel|guardarCustom|modoEfectivo\" zebra-agent --glob '"'!node_modules/**'"'" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
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
zebra-agent/src/zpl-formatter.js:91:      //   la palabra del nivel de precio (visto con la Vista Zebra)
zebra-agent/src/zpl-formatter.js:111: * [2026-10-07] Modo efectivo = modo base + lo guardado por la persona (labelLayouts[modo]).
zebra-agent/src/zpl-formatter.js:116:function modoEfectivo(base, custom = {}, extra = {}) {
zebra-agent/src/zpl-formatter.js:118:  const horizontal = !!(base.orientable && base.layoutHorizontal && c.orientation === 'N');
zebra-agent/src/zpl-formatter.js:125:    orientation: horizontal ? 'N' : base.orientation,
zebra-agent/src/zpl-formatter.js:138: * @param {object} prev  lo guardado hasta ahora (labelLayouts[modo])
zebra-agent/src/zpl-formatter.js:142:function guardarCustom(prev, base, cambio) {
zebra-agent/src/zpl-formatter.js:144:  const horizontal = !!(base.orientable && base.layoutHorizontal && p.orientation === 'N');
zebra-agent/src/zpl-formatter.js:147:    if (cambio.orientation === 'N') p.orientation = 'N';
zebra-agent/src/zpl-formatter.js:148:    else delete p.orientation;
zebra-agent/src/zpl-formatter.js:532:  const orientation = m.orientation === 'R' ? 'R' : 'N';
zebra-agent/src/zpl-formatter.js:625:  const r = formatQrLabelConAvisos({ ...base, layout: { ...layout, mode: porEtiqueta === 2 ? 'doble' : 'simple' } });
zebra-agent/src/zpl-formatter.js:627:  return { ...r, porFila, dibujo: zplADibujo(r.zpl) };
zebra-agent/src/zpl-formatter.js:660:      ...formatQrLabelConAvisos({ ...fila[0], layout: { ...layout, mode: modo, celdas: fila } }),
zebra-agent/src/zpl-formatter.js:695:  // ★ QR 경로에서는 `formatQrLabel` 이 라벨마다 ~SD 를 동봉하므로 여기서 또 넣지 않는다.
zebra-agent/src/zpl-formatter.js:1017:function formatQrLabel(args = {}) {
zebra-agent/src/zpl-formatter.js:1018:  return formatQrLabelConAvisos(args).zpl;
zebra-agent/src/zpl-formatter.js:1022: * Igual que `formatQrLabel`, pero devuelve también los avisos (nombre cortado).
zebra-agent/src/zpl-formatter.js:1032:function formatQrLabelConAvisos({ contenido, name, price, priceLabel, layout } = {}) {
zebra-agent/src/zpl-formatter.js:1110:function zplADibujo(zpl) {
zebra-agent/src/zpl-formatter.js:1154: * @param {Object} mode - modo efectivo (getEffectiveMode): width, halfWidth, duplicate, name
zebra-agent/src/zpl-formatter.js:1158:function formatTestLabel(mode, { darkness = null, speed = null } = {}) {
zebra-agent/src/zpl-formatter.js:1199:  const girada = mode.orientation === 'R';
zebra-agent/src/zpl-formatter.js:1237:  modoEfectivo,
zebra-agent/src/zpl-formatter.js:1238:  guardarCustom,
zebra-agent/src/zpl-formatter.js:1240:  formatTestLabel,
zebra-agent/src/zpl-formatter.js:1242:  formatQrLabel,
zebra-agent/src/zpl-formatter.js:1265:  formatQrLabelConAvisos,
zebra-agent/src/zpl-formatter.js:1266:  zplADibujo,
zebra-agent/src/vista-zebra.js:2: * [2026-10-07 usuario] «Vista Zebra» — cómo sale de verdad la etiqueta.
zebra-agent/src/vista-zebra.js:15:const { formatBatchLabels, formatTestLabel } = require('./zpl-formatter');
zebra-agent/src/vista-zebra.js:89: * @param {object} ctx   { ajustes:{darkness,speed}, modoEfectivo, modoImpresion, seleccion, qrLayout }
zebra-agent/src/vista-zebra.js:92:function armarZplVista({ tipo, mode, sku, items, opciones } = {}, ctx) {
zebra-agent/src/vista-zebra.js:95:    return { zpl: formatTestLabel(ctx.modoEfectivo, { darkness, speed }), mode: ctx.modoEfectivo };
zebra-agent/src/vista-zebra.js:100:    const m = { ...(mode || ctx.modoEfectivo), darkness, speed };
zebra-agent/src/vista-zebra.js:130:module.exports = { renderizarZpl, armarZplVista, urlLabelary, tamanoDeZpl, LABELARY };
zebra-agent/preload.js:29:  setLabelLayout: (layout) => ipcRenderer.invoke('label:setLayout', layout),
zebra-agent/preload.js:30:  setLabelOrientation: (o) => ipcRenderer.invoke('label:setOrientation', o),
zebra-agent/preload.js:52:  // [2026-10-07] «Vista Zebra» — imagen del emulador con el mismo ZPL
zebra-agent/main.js:8:  formatBatchLabels, formatQrLabel, formatTestLabel, resolveMode, darknessZpl, speedZpl,
zebra-agent/main.js:10:  formatQrLabelConAvisos, zplADibujo, qrLotePreview, filasDeLoteQrTotal, qrLoteFilas,
zebra-agent/main.js:11:  modoEfectivo, guardarCustom,
zebra-agent/main.js:16:const { renderizarZpl, armarZplVista } = require('./src/vista-zebra');
zebra-agent/main.js:42:    labelLayouts: {},              // 신규: 모드별 커스텀 { [modeKey]: { width, height, layout } }
zebra-agent/main.js:51:// ─── 구버전 설정 마이그레이션 (labelPreset/labelLayout → labelMode/labelLayouts) ──
zebra-agent/main.js:64:      const layouts = store.get('labelLayouts') || {};
zebra-agent/main.js:66:      store.set('labelLayouts', layouts);
zebra-agent/main.js:97:    const layouts = store.get('labelLayouts') || {};
zebra-agent/main.js:114:    if (touched) store.set('labelLayouts', layouts);
zebra-agent/main.js:121:function getEffectiveMode() {
zebra-agent/main.js:124:  const custom = (store.get('labelLayouts') || {})[base.key] || {};
zebra-agent/main.js:128:  return modoEfectivo(base, custom, getPrintSettings());
zebra-agent/main.js:136:    getEffectiveMode().layout || {},
zebra-agent/main.js:142:  const mode = getEffectiveMode();
zebra-agent/main.js:391:    orientation: p.orientation || 'N',
zebra-agent/main.js:399:  const mode = getEffectiveMode();
zebra-agent/main.js:410:// 모드 변경 (모드별 커스텀은 labelLayouts 에 남아 있어 전환해도 유실 없음)
zebra-agent/main.js:418:ipcMain.handle('label:setLayout', (_event, custom) => {
zebra-agent/main.js:419:  const base = resolveMode(getEffectiveMode().key);
zebra-agent/main.js:420:  const layouts = store.get('labelLayouts') || {};
zebra-agent/main.js:424:    ? guardarCustom(layouts[base.key], base, { tipo: 'reset' })
zebra-agent/main.js:425:    : guardarCustom(layouts[base.key], base, {
zebra-agent/main.js:432:  store.set('labelLayouts', layouts);
zebra-agent/main.js:436:ipcMain.handle('label:setOrientation', (_event, orientation) => {
zebra-agent/main.js:437:  const base = resolveMode(getEffectiveMode().key);
zebra-agent/main.js:439:  const layouts = store.get('labelLayouts') || {};
zebra-agent/main.js:440:  layouts[base.key] = guardarCustom(layouts[base.key], base, { tipo: 'orientacion', orientation: orientation === 'N' ? 'N' : 'R' });
zebra-agent/main.js:441:  store.set('labelLayouts', layouts);
zebra-agent/main.js:443:  return { ok: true, orientation: getEffectiveMode().orientation };
zebra-agent/main.js:603:// [2026-10-07 usuario] «Vista Zebra» — la primera etiqueta, del MISMO ZPL que se imprimiría,
zebra-agent/main.js:610:    const { zpl, mode } = armarZplVista(args || {}, {
zebra-agent/main.js:612:      modoEfectivo: getEffectiveMode(),
zebra-agent/main.js:624:// [v1.0.29] Vista previa EXACTA del lote QR (pestaña Etiquetas) — el mismo ZPL que se
zebra-agent/main.js:655:      dibujo: muestra ? zplADibujo(muestra.zpl) : primero.dibujo,
zebra-agent/main.js:673:// [v1.0.29] Vista previa EXACTA de la pestaña QR (enlace para clientes).
zebra-agent/main.js:677:    const hacer = (it) => formatQrLabelConAvisos({
zebra-agent/main.js:684:      ok: true, dibujo: zplADibujo(r.zpl), avisos: r.avisos, bandas: r.bandas,
zebra-agent/main.js:738:    const zpl = formatQrLabel({
zebra-agent/main.js:761:      const zpl = formatQrLabel({
zebra-agent/main.js:1133:    const testZpl = formatTestLabel(getEffectiveMode(), { darkness, speed });
zebra-agent/test/vista-zebra.test.js:2: * «Vista Zebra» (2026-10-07) — el ZPL que se muestra es el que se imprimiría, y el emulador
zebra-agent/test/vista-zebra.test.js:7:const { armarZplVista, renderizarZpl, urlLabelary } = require('../src/vista-zebra');
zebra-agent/test/vista-zebra.test.js:8:const { formatBatchLabels, formatTestLabel, resolveMode } = require('../src/zpl-formatter');
zebra-agent/test/vista-zebra.test.js:24:  modoEfectivo: modo,
zebra-agent/test/vista-zebra.test.js:42:    const { zpl } = armarZplVista({ tipo: 'lote', items: [prod('AAA111'), prod('BBB222')], opciones: {} }, ctx(simple));
zebra-agent/test/vista-zebra.test.js:53:    const { zpl } = armarZplVista({ tipo: 'lote', items: [prod('AAA111')], opciones: {} }, ctx(simple));
zebra-agent/test/vista-zebra.test.js:58:    const { zpl } = armarZplVista({ tipo: 'lote', items: [prod('AAA111')], opciones: { simbolo: 'qr', porEtiqueta: 2 } }, ctx(dup));
zebra-agent/test/vista-zebra.test.js:64:    const { zpl } = armarZplVista({ tipo: 'lote', items: [prod('AAA111')], opciones: { simbolo: 'qr' } }, c);
zebra-agent/test/vista-zebra.test.js:65:    const sinCfg = armarZplVista({ tipo: 'lote', items: [prod('AAA111')], opciones: { simbolo: 'qr' } }, ctx(simple)).zpl;
zebra-agent/test/vista-zebra.test.js:72:    const { zpl, mode } = armarZplVista({ tipo: 'diseno', mode: enPantalla, sku: 'MUESTRA9' }, ctx(simple));
zebra-agent/test/vista-zebra.test.js:81:    const { zpl } = armarZplVista({ tipo: 'test' }, ctx(dup));
zebra-agent/test/vista-zebra.test.js:82:    assert.strictEqual(zpl, formatTestLabel(dup, { darkness: 15, speed: 4 }));
zebra-agent/test/vista-zebra.test.js:86:    assert.strictEqual(armarZplVista({ tipo: 'lote', items: [] }, ctx(simple)).zpl, null);
zebra-agent/test/vista-zebra.test.js:87:    assert.strictEqual(armarZplVista({ tipo: 'otro' }, ctx(simple)).zpl, null);
zebra-agent/test/vista-zebra.test.js:104:    const zpl = formatTestLabel(dup, {});
zebra-agent/test/vista-zebra.test.js:114:    const z = formatTestLabel(simple, {});
zebra-agent/test/vista-zebra.test.js:129:    const html = await renderizarZpl(formatTestLabel(simple, {}), {
zebra-agent/renderer/index.html:204:    /* [2026-10-07] «Vista Zebra»: la imagen del emulador, a escala, sobre blanco */
zebra-agent/renderer/index.html:386:                title="Cómo sale la etiqueta del primer producto, sin imprimir">Vista Zebra</button>
zebra-agent/renderer/index.html:533:          <div class="card-title">Vista previa</div>
zebra-agent/renderer/index.html:677:          <div class="card-title">Vista previa de etiqueta QR</div>
zebra-agent/renderer/index.html:832:      if (btn.dataset.tab === 'label') drawPreview();
zebra-agent/renderer/index.html:996:    drawPreview();
zebra-agent/renderer/index.html:1025:        drawPreview();
zebra-agent/renderer/index.html:1036:    const actual = currentMode?.orientation === 'N' ? 'N' : 'R';
zebra-agent/renderer/index.html:1052:      drawPreview();
zebra-agent/renderer/index.html:1053:      addLocalLog('Orientación: ' + (currentMode?.orientation === 'N' ? 'horizontal' : 'vertical'));
zebra-agent/renderer/index.html:1088:  $('#lay-auto-prices').addEventListener('change', () => { togglePriceXY(); drawPreview(); });
zebra-agent/renderer/index.html:1089:  $('#lay-bc-autofit').addEventListener('change', drawPreview);
zebra-agent/renderer/index.html:1114:  function buildModeFromForm() {
zebra-agent/renderer/index.html:1131:      orientation: currentMode?.orientation || base.orientation,
zebra-agent/renderer/index.html:1140:  LAYOUT_FIELDS.forEach(([sel]) => $(sel).addEventListener('input', drawPreview));
zebra-agent/renderer/index.html:1141:  ['#lay-w', '#lay-h', '#sample-sku'].forEach(s => $(s).addEventListener('input', drawPreview));
zebra-agent/renderer/index.html:1144:    const m = buildModeFromForm();
zebra-agent/renderer/index.html:1152:    drawPreview();
zebra-agent/renderer/index.html:1207:    drawPreview();
zebra-agent/renderer/index.html:1248:  function drawPreview() {
zebra-agent/renderer/index.html:1251:    const mode = buildModeFromForm();
zebra-agent/renderer/index.html:1279:    const rotated = mode.orientation === 'R';
zebra-agent/renderer/index.html:1495:      drawPreview();
zebra-agent/renderer/index.html:1503:    drawPreview();
zebra-agent/renderer/index.html:1982:  // [2026-10-07] «Vista Zebra» del lote: el primer producto, como «Imprimir 1 de prueba».
zebra-agent/renderer/index.html:1992:    mostrarVistaZebra('Vista Zebra · ' + (items[0].name || items[0].sku || ''), {
zebra-agent/renderer/index.html:2974:  // [v1.0.29] Vista previa EXACTA — se dibuja lo que devuelve el proceso principal leyendo
zebra-agent/renderer/index.html:2975:  //   el MISMO ZPL que se imprime (zplADibujo). No hay una segunda cuenta en la pantalla.
zebra-agent/renderer/index.html:3064:  // [2026-10-07 usuario] «Vista Zebra» — la imagen que devuelve el emulador de Zebra (Labelary)
zebra-agent/renderer/index.html:3067:  async function mostrarVistaZebra(titulo, args) {
zebra-agent/renderer/index.html:3102:    mostrarVistaZebra('Vista Zebra · diseño actual', { tipo: 'diseno', mode: buildModeFromForm(), sku: sampleSku() });
zebra-agent/renderer/index.html:3105:    mostrarVistaZebra('Vista Zebra · Imprimir test', { tipo: 'test' });
zebra-agent/renderer/index.html:3382:  function qrItemsParaVista() {
zebra-agent/renderer/index.html:3391:      const lista = qrItemsParaVista();
zebra-agent/renderer/index.html:3405:  $('#qr-pv-prev')?.addEventListener('click', () => { const n = qrItemsParaVista().length || 1; qrPvIdx = (qrPvIdx - 1 + n) % n; qrPintarExacta(); });
zebra-agent/renderer/index.html:3406:  $('#qr-pv-next')?.addEventListener('click', () => { const n = qrItemsParaVista().length || 1; qrPvIdx = (qrPvIdx + 1) % n; qrPintarExacta(); });
zebra-agent/test/test-label.test.js:2: * formatTestLabel — «Imprimir test» sigue el modo elegido (2026-10-07).
zebra-agent/test/test-label.test.js:9:const { formatTestLabel, resolveMode } = require('../src/zpl-formatter');
zebra-agent/test/test-label.test.js:18:console.log('formatTestLabel — prueba según el modo\n');
zebra-agent/test/test-label.test.js:40:const zDup = formatTestLabel(dup, {});
zebra-agent/test/test-label.test.js:59:ok('doble banda: alto personalizado', formatTestLabel({ ...dup, height: 240 }, {}).includes('^LL240'));
zebra-agent/test/test-label.test.js:61:// ancho personalizado del modo (getEffectiveMode recalcula halfWidth)
zebra-agent/test/test-label.test.js:62:const zCustom = formatTestLabel({ ...dup, width: 832, halfWidth: 416 }, {});
zebra-agent/test/test-label.test.js:68:  const z = formatTestLabel(resolveMode(key), {});
zebra-agent/test/test-label.test.js:74:const { modoEfectivo } = require('../src/zpl-formatter');
zebra-agent/test/test-label.test.js:76:const zV = formatTestLabel(modoEfectivo(poli, {}), {});
zebra-agent/test/test-label.test.js:80:const zH = formatTestLabel(modoEfectivo(poli, { orientation: 'N' }), {});
zebra-agent/test/test-label.test.js:86:ok('una cara ancha: el código sigue ajustado a 400', formatTestLabel({ ...resolveMode('simple-face'), width: 832 }, {}) === ANTES_BY2);
zebra-agent/test/test-label.test.js:88:ok('sin modo: como una cara', formatTestLabel(null, {}) === ANTES_BY2);
zebra-agent/test/test-label.test.js:91:const conAjustes = formatTestLabel(resolveMode('simple-face'), { darkness: 15, speed: 4 });
zebra-agent/test/test-label.test.js:93:ok('densidad/velocidad en doble banda', /~SD15/.test(formatTestLabel(dup, { darkness: 15, speed: 4 })));
zebra-agent/test/qr-label.test.js:2: * formatQrLabel 단위 테스트 — QR 배치 델타 라벨
zebra-agent/test/qr-label.test.js:15:  formatQrLabel,
zebra-agent/test/qr-label.test.js:30:console.log('formatQrLabel — QR 배치 델타 라벨 (QR 자동맞춤 폭에서 역산한 좌우 분할)\n');
zebra-agent/test/qr-label.test.js:42:const zplA = formatQrLabel(base);
zebra-agent/test/qr-label.test.js:63://    여기서는 그 공식이 formatQrLabel 실물 출력에도 그대로 배선돼 있는지만 확인한다.
zebra-agent/test/qr-label.test.js:75:ok('D: 텍스트 X 좌표가 formatQrLabel 실물에서도 qrRight+gap 공식과 일치 (배선 확인)',
zebra-agent/test/qr-label.test.js:88:const zplD2cap6 = formatQrLabel({ ...base, layout: tallLayout(6) });
zebra-agent/test/qr-label.test.js:89:const zplD2cap10 = formatQrLabel({ ...base, layout: tallLayout(10) });
zebra-agent/test/qr-label.test.js:107:const zplE = formatQrLabel({
zebra-agent/test/qr-label.test.js:129:const zplF = formatQrLabel({ ...base, layout: { mode: 'doble' } });
zebra-agent/test/qr-label.test.js:183:const zplFw = formatQrLabel({ ...base, layout: { mode: 'doble', widthMm: 50, heightMm: 50 } });
zebra-agent/test/qr-label.test.js:197:const zplFs = formatQrLabel({ ...base, layout: { mode: 'simple' } });
zebra-agent/test/qr-label.test.js:204:const zplG = formatQrLabel({ ...base, layout: { mode: 'simple' } });
zebra-agent/test/qr-label.test.js:209:const zplH = formatQrLabel({ ...base, name: 'CARGO ^RARO~ AZUL' });
zebra-agent/test/qr-label.test.js:214:const zplI = formatQrLabel({ ...base, name: longName });
zebra-agent/test/qr-label.test.js:222:const zplJ = formatQrLabel({ contenido: qrUrl, name: '', price: null, priceLabel: '' });
zebra-agent/test/qr-label.test.js:226:const zplK = formatQrLabel({ ...base, layout: { darkness: 22, speed: 4 } });
zebra-agent/test/qr-label.test.js:233:const zplK2 = formatQrLabel({ ...base, layout: { darkness: 99, speed: 0 } });
zebra-agent/test/qr-label.test.js:238:const zplL = formatQrLabel({ ...base, layout: { splitRatio: 0.5 } });
zebra-agent/test/qr-label.test.js:239:const zplLNoSplit = formatQrLabel({ ...base, layout: {} });
zebra-agent/test/qr-lote-cableado.smoke.js:79:  /formatQrLabel\(\{[\s\S]{0,120}contenido: item\.qrUrl/.test(MAIN));
zebra-agent/mockups/etiqueta-2panel-mockup.html:218:            <div class="card-title">Vista previa</div>
zebra-agent/mockups/etiqueta-2panel-mockup.html:468:    const rot = mode.orientation === 'R';
zebra-agent/test/orientacion.test.js:6:const { modoEfectivo, guardarCustom, formatLabel, resolveMode } = require('../src/zpl-formatter');
zebra-agent/test/orientacion.test.js:20:ok('sin elegir nada: vertical (como siempre)', modoEfectivo(poli, {}).orientation === 'R');
zebra-agent/test/orientacion.test.js:21:const h = modoEfectivo(poli, { orientation: 'N' });
zebra-agent/test/orientacion.test.js:22:ok('horizontal: orientación N y el diseño horizontal', h.orientation === 'N' && h.layout === poli.layoutHorizontal);
zebra-agent/test/orientacion.test.js:23:ok('un modo no orientable ignora la orientación guardada', modoEfectivo(simple, { orientation: 'R' }).orientation === 'N');
zebra-agent/test/orientacion.test.js:25:  modoEfectivo(poli, { orientation: 'N', layout: { name: { x: 999, y: 1, fontSize: 9 } } }).layout.name.x === poli.layoutHorizontal.name.x);
zebra-agent/test/orientacion.test.js:27:  modoEfectivo(poli, { orientation: 'N', layoutN: { name: { x: 33, y: 1, fontSize: 9 } } }).layout.name.x === 33);
zebra-agent/test/orientacion.test.js:28:ok('densidad/velocidad (extra) siguen entrando', modoEfectivo(poli, {}, { darkness: 12 }).darkness === 12);
zebra-agent/test/orientacion.test.js:31:let c = guardarCustom({ layout: { a: 1 } }, poli, { tipo: 'orientacion', orientation: 'N' });
zebra-agent/test/orientacion.test.js:32:ok('elegir horizontal no borra el diseño vertical', c.orientation === 'N' && c.layout.a === 1);
zebra-agent/test/orientacion.test.js:33:c = guardarCustom(c, poli, { tipo: 'diseno', width: 200, height: 400, layout: { b: 2 } });
zebra-agent/test/orientacion.test.js:35:c = guardarCustom(c, poli, { tipo: 'reset' });
zebra-agent/test/orientacion.test.js:36:ok('restablecer en horizontal borra sólo el horizontal', !c.layoutN && c.layout.a === 1 && c.orientation === 'N');
zebra-agent/test/orientacion.test.js:37:c = guardarCustom(c, poli, { tipo: 'orientacion', orientation: 'R' });
zebra-agent/test/orientacion.test.js:38:ok('volver a vertical', !c.orientation && modoEfectivo(poli, c).orientation === 'R');
zebra-agent/test/orientacion.test.js:40:  JSON.stringify(guardarCustom({ layout: { a: 1 } }, simple, { tipo: 'orientacion', orientation: 'N' })) === JSON.stringify({ layout: { a: 1 } }));
zebra-agent/test/orientacion.test.js:43:const zV = formatLabel(item, modoEfectivo(poli, {}));
zebra-agent/test/orientacion.test.js:44:const zH = formatLabel(item, modoEfectivo(poli, { orientation: 'N' }));
zebra-agent/test/orientacion.test.js:49:ok('[Vista Zebra] vertical: el código ya no pisa el nivel de precio (x 80)', zV.includes('^FO80,10^BY'));
zebra-agent/test/orientacion.test.js:52:ok('otros modos no cambian (sin ^FB)', !formatLabel(item, modoEfectivo(simple, {})).includes('^FB'));
zebra-agent/test/qr-v1029.test.js:11:  formatBatchLabels, formatQrLabelConAvisos, zplADibujo, qrLotePreview, filasDeLoteQr, LABEL_MODES,
zebra-agent/test/qr-v1029.test.js:82:  const largo = formatQrLabelConAvisos({
zebra-agent/test/qr-v1029.test.js:88:  const corto = formatQrLabelConAvisos({
zebra-agent/test/qr-texto.test.js:6:const { formatQrLabel, formatBatchLabels } = require('../src/zpl-formatter');
zebra-agent/test/qr-texto.test.js:24:  const def = formatQrLabel({ ...base, layout: { mode } });
zebra-agent/test/qr-texto.test.js:27:  const sinPrecio = formatQrLabel({ ...base, layout: { mode, mostrarPrecio: false } });
zebra-agent/test/qr-texto.test.js:30:  const sinNombre = formatQrLabel({ ...base, layout: { mode, mostrarNombre: false } });
zebra-agent/test/qr-texto.test.js:33:  const nada = formatQrLabel({ ...base, layout: { mode, mostrarNombre: false, mostrarPrecio: false } });
zebra-agent/test/qr-texto.test.js:37:  const pos = formatQrLabel({ ...base, layout: { mode, precioX: 5, precioY: 12 } });
zebra-agent/test/qr-texto.test.js:58:  mod(formatQrLabel({ ...base, layout: { mode: 'doble', mostrarNombre: false, mostrarPrecio: false } })) >=
zebra-agent/test/qr-texto.test.js:59:    mod(formatQrLabel({ ...base, layout: { mode: 'doble' } })),
zebra-agent/test/qr-lote-corrido.test.js:12:const { formatBatchLabels, qrLoteFilas, filasDeLoteQrTotal, zplADibujo } = require('../src/zpl-formatter');
zebra-agent/test/qr-lote-corrido.test.js:44:const dib = zplADibujo(f[4].zpl);
zebra-agent/test/qr-diseno-texto.test.js:10:const { formatQrLabel, formatQrLabelConAvisos, formatBatchLabels, zplADibujo, qrLotePreview } = require('../src/zpl-formatter');
zebra-agent/test/qr-diseno-texto.test.js:26:  const def = formatQrLabel({ ...base, layout: { mode } });
zebra-agent/test/qr-diseno-texto.test.js:29:  const grande = formatQrLabel({ ...base, layout: { mode, nombreFs: 24, precioFs: 30 } });
zebra-agent/test/qr-diseno-texto.test.js:33:    alto(linea(formatQrLabel({ ...base, layout: { mode, nombreFs: '' } }), 'REMERA')) === alto(linea(def, 'REMERA')));
zebra-agent/test/qr-diseno-texto.test.js:36:  const centro = formatQrLabel({ ...base, layout: { mode, nombreAlign: 'C', precioAlign: 'R' } });
zebra-agent/test/qr-diseno-texto.test.js:40:    !formatQrLabel({ ...base, layout: { mode, nombreAlign: 'L' } }).includes('^FB'));
zebra-agent/test/qr-diseno-texto.test.js:41:  ok(`${mode}: valor raro de alineación → Izq`, !formatQrLabel({ ...base, layout: { mode, nombreAlign: 'X' } }).includes('^FB'));
zebra-agent/test/qr-diseno-texto.test.js:44:  const r = formatQrLabelConAvisos({ ...base, layout: { mode, nombreX: 3, nombreY: 15, nombreAlign: 'C' } });
zebra-agent/test/qr-diseno-texto.test.js:52:  const d = zplADibujo(centro).elementos.find((e) => e.tipo === 'texto' && e.texto.startsWith('REMERA'));
zebra-agent/test/qr-diseno-texto.test.js:58:  const auto = formatQrLabelConAvisos({ ...base, layout: { mode: 'doble' } });
zebra-agent/test/qr-diseno-texto.test.js:59:  const grande = formatQrLabelConAvisos({ ...base, layout: { mode: 'doble', nombreFs: 30, precioFs: 30 } });
zebra-agent/test/qr-diseno-texto.test.js:61:  ok('sin elegir sigue el tope 12–16 (fuente 22 → 16)', alto(linea(formatQrLabel({ ...base, layout: { mode: 'doble', fontSize: 22 } }), 'REMERA')) === 16);
zebra-agent/test/qr-diseno-texto.test.js:64:  const lado = zplADibujo(grande.zpl).elementos.find((e) => e.tipo === 'qr').lado;
zebra-agent/test/qr-diseno-texto.test.js:67:  const enorme = formatQrLabelConAvisos({ ...base, layout: { mode: 'doble', nombreFs: 60, precioFs: 60 } });
zebra-agent/test/qr-diseno-texto.test.js:69:  const chica = formatQrLabelConAvisos({ ...base, layout: { mode: 'doble', nombreFs: 12, precioFs: 12 } });
zebra-agent/mockups/qr-vista-previa-real-mockup.html:5:<title>Zebra Agent — Vista previa real (mockup)</title>
zebra-agent/mockups/qr-vista-previa-real-mockup.html:68:        <div class="ct">Vista previa de etiqueta QR <span class="new">NUEVO</span></div>
zebra-agent/mockups/qr-v1029-revisado-mockup.html:55:   <div class="ct">Vista previa <span class="new">EXACTA (ZPL)</span></div>
zebra-agent/mockups/qr-v1029-revisado-mockup.html:103:   <div><b>①</b> Vista exacta con el producto real · aviso si el texto se corta</div>
zebra-agent/mockups/qr-v1029-posiciones-mockup.html:44:   <div class="ct">Vista previa <span class="new">EXACTA (ZPL)</span></div>
zebra-agent/mockups/etiqueta-config-mockup.html:125:        <div class="card-title">Vista previa</div>
zebra-agent/mockups/etiqueta-config-mockup.html:435:    const rot = mode.orientation === 'R';

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
/bin/zsh -lc "sed -n '35,155p' zebra-agent/main.js; sed -n '380,455p' zebra-agent/main.js; sed -n '580,625p' zebra-agent/main.js; sed -n '1060,1170p' zebra-agent/renderer/index.html; sed -n '1230,1325p' zebra-agent/renderer/index.html; sed -n '80,150p' zebra-agent/src/vista-zebra.js; sed -n '500,570p' zebra-agent/src/zpl-formatter.js; sed -n '380,470p' zebra-agent/src/zpl-formatter.js; sed -n '1,120p' zebra-agent/test/orientacion.test.js" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
      host: '',
      port: 9100,
      printerName: '',     // USB 프린터 이름 (OS에 등록된)
    },
    labelPreset: '50x25-simple',   // 구버전 키 (마이그레이션용으로만 유지)
    labelLayout: null,             // 구버전 키 (마이그레이션용으로만 유지)
    labelMode: '',                 // 신규: 출력 모드 (simple-face 등 4종)
    labelLayouts: {},              // 신규: 모드별 커스텀 { [modeKey]: { width, height, layout } }
    priceSelection: [],            // 신규: 출력할 precio nivel [{ id, name }] 최대 3개
    // 출력 파라미터 — 모드/QR 구분 없이 프린터 전역 적용 (null = 프린터 기본값)
    printSettings: { darkness: null, speed: null },
    openAtLogin: true,
    setupDone: false,
  },
});

// ─── 구버전 설정 마이그레이션 (labelPreset/labelLayout → labelMode/labelLayouts) ──
function migrateLegacyLabelConfig() {
  try {
    if (store.get('labelMode')) return; // 이미 신규 구조 사용 중

    const legacyPreset = store.get('labelPreset') || '50x25-simple';
    const modeKey = LEGACY_PRESET_ALIASES[legacyPreset] || legacyPreset;
    const finalMode = LABEL_MODES[modeKey] ? modeKey : 'simple-face';

    store.set('labelMode', finalMode);

    const legacyLayout = store.get('labelLayout');
    if (legacyLayout) {
      const layouts = store.get('labelLayouts') || {};
      layouts[finalMode] = { layout: legacyLayout };
      store.set('labelLayouts', layouts);
    }
  } catch (err) {
    console.error('migrateLegacyLabelConfig error:', err);
  }
}

// ─── 출력 파라미터 (전역) ───────────────────────────────────────────────────
// 범위 밖/빈값은 null = 프린터 기본값
function clampSetting(value, min, max) {
  const n = parseInt(value, 10);

  return Number.isFinite(n) && n >= min && n <= max ? n : null;
}

function getPrintSettings() {
  const s = store.get('printSettings') || {};

  return {
    darkness: clampSetting(s.darkness, 0, 30),   // ~SD 절대값 0~30
    speed: clampSetting(s.speed, 2, 14),         // ^PR 2~14 ips
  };
}

// ─── 모드별 darkness/speed → 전역 printSettings 승격 (1회) ──────────────────
// 구버전은 모드마다 밀도/속도를 따로 저장 → 첫 유효값을 전역으로 올리고 모드에서 제거
function migratePrintSettings() {
  try {
    const current = store.get('printSettings');
    if (current && (current.darkness != null || current.speed != null)) return;

    const layouts = store.get('labelLayouts') || {};
    let darkness = null;
    let speed = null;
    let touched = false;

    for (const cfg of Object.values(layouts)) {
      if (!cfg) continue;
      if (darkness == null) darkness = clampSetting(cfg.darkness, 0, 30);
      if (speed == null) speed = clampSetting(cfg.speed, 2, 14);
      if ('darkness' in cfg || 'speed' in cfg) {
        delete cfg.darkness;
        delete cfg.speed;
        touched = true;
      }
    }

    store.set('printSettings', { darkness, speed });
    if (touched) store.set('labelLayouts', layouts);
  } catch (err) {
    console.error('migratePrintSettings error:', err);
  }
}

// ─── 현재 유효 모드 계산 (프리셋 + 모드별 커스텀 + 전역 출력 파라미터 병합) ──
function getEffectiveMode() {
  const modeKey = store.get('labelMode') || 'simple-face';
  const base = resolveMode(modeKey);
  const custom = (store.get('labelLayouts') || {})[base.key] || {};

  // [2026-10-07] orientación elegida (Poliamida) + diseño de esa orientación — src/zpl-formatter.js
  // 출력 밀도/속도는 모드가 아닌 프린터 전역 설정
  return modoEfectivo(base, custom, getPrintSettings());
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
ipcMain.handle('printer:listUsb', () => listUsbPrinters());

// 출력 모드 목록 (4종)
ipcMain.handle('label:presets', () => {
  return Object.values(LABEL_MODES).map(p => ({
    key: p.key,
    name: p.name,
    description: p.description || '',
    width: p.width,
    height: p.height,
    duplicate: !!p.duplicate,
    orientation: p.orientation || 'N',
    orientable: !!p.orientable,
    layout: p.layout,
  }));
});

// 현재 모드 + 커스텀 병합 설정 + precio nivel 선택 가져오기
ipcMain.handle('label:getConfig', () => {
  const mode = getEffectiveMode();

  return {
    presetKey: mode.key,       // 하위 호환 필드명 유지
    modeKey: mode.key,
    preset: mode,              // 하위 호환 필드명 유지
    mode,
    priceSelection: store.get('priceSelection') || [],
  };
});

// 모드 변경 (모드별 커스텀은 labelLayouts 에 남아 있어 전환해도 유실 없음)
ipcMain.handle('label:setPreset', (_event, modeKey) => {
  const resolved = resolveMode(modeKey);
  store.set('labelMode', resolved.key);
});

// 현재 모드의 커스텀 레이아웃/크기 저장 (null → 해당 모드 초기화)
// [2026-10-07] guarda sólo el diseño de la orientación actual: el de la otra queda intacto
ipcMain.handle('label:setLayout', (_event, custom) => {
  const base = resolveMode(getEffectiveMode().key);
  const layouts = store.get('labelLayouts') || {};

  // 밀도/속도는 모드별이 아닌 전역(printSettings) — 여기서 저장하지 않음
  layouts[base.key] = custom == null
    ? guardarCustom(layouts[base.key], base, { tipo: 'reset' })
    : guardarCustom(layouts[base.key], base, {
      tipo: 'diseno',
      width: custom.width,
      height: custom.height,
      layout: custom.layout || custom, // { layout } 또는 layout 직접 전달 모두 허용
    });

  store.set('labelLayouts', layouts);
});

// [2026-10-07 usuario] Poliamida: imprimir en vertical ('R') u horizontal ('N')
ipcMain.handle('label:setOrientation', (_event, orientation) => {
  const base = resolveMode(getEffectiveMode().key);
  if (!base.orientable) return { ok: false };
  const layouts = store.get('labelLayouts') || {};
  layouts[base.key] = guardarCustom(layouts[base.key], base, { tipo: 'orientacion', orientation: orientation === 'N' ? 'N' : 'R' });
  store.set('labelLayouts', layouts);

  return { ok: true, orientation: getEffectiveMode().orientation };
});

// 전역 출력 파라미터 조회 — { darkness, speed } (null = 프린터 기본값)
ipcMain.handle('print:getSettings', () => getPrintSettings());

// 전역 출력 파라미터 저장 — 범위 밖/빈값은 null 로 정규화되어 프린터 기본값 사용
ipcMain.handle('print:setSettings', (_event, settings) => {
  const next = {
    darkness: clampSetting(settings?.darkness, 0, 30),
    speed: clampSetting(settings?.speed, 2, 14),
  };

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
      qrLayout: store.get('qrLayout') || {},
    });

    return await renderizarZpl(zpl, { mode });
  } catch (err) {
    return { ok: false, error: err.message || 'No se pudo armar la etiqueta' };
  }
});

// [v1.0.29] Vista previa EXACTA del lote QR (pestaña Etiquetas) — el mismo ZPL que se
//   imprime, leído como dibujo. Devuelve además el resumen para la confirmación.
    ['#lay-bc-x', 'barcode', 'x'], ['#lay-bc-y', 'barcode', 'y'], ['#lay-bc-h', 'barcode', 'height'],
    ['#lay-bc-mw', 'barcode', 'moduleWidth'],
    ['#lay-p1-x', 'price1', 'x'], ['#lay-p1-y', 'price1', 'y'], ['#lay-p1-fs', 'price1', 'fontSize'],
    ['#lay-p2-x', 'price2', 'x'], ['#lay-p2-y', 'price2', 'y'], ['#lay-p2-fs', 'price2', 'fontSize'],
    ['#lay-p3-x', 'price3', 'x'], ['#lay-p3-y', 'price3', 'y'], ['#lay-p3-fs', 'price3', 'fontSize'],
  ];

  function loadLayoutEditor() {
    const layout = currentMode?.layout;
    if (!layout) return;
    LAYOUT_FIELDS.forEach(([sel, elem, prop]) => {
      const val = layout[elem]?.[prop];
      if (val != null) $(sel).value = val;
    });
    $('#lay-w').value = sizeToDisplay(currentMode.width);
    $('#lay-h').value = sizeToDisplay(currentMode.height);
    $('#lay-auto-prices').checked = layout.autoPrices !== false;
    $('#lay-bc-autofit').checked = layout.barcode?.autoFit !== false;
    togglePriceXY();
  }

  // 자동 배치 시 가격 X/Y 는 비활성 (폰트 크기는 계속 편집 가능)
  function togglePriceXY() {
    const auto = $('#lay-auto-prices').checked;
    ['#lay-p1-x', '#lay-p1-y', '#lay-p2-x', '#lay-p2-y', '#lay-p3-x', '#lay-p3-y']
      .forEach(s => { $(s).disabled = auto; });
  }

  $('#lay-auto-prices').addEventListener('change', () => { togglePriceXY(); drawPreview(); });
  $('#lay-bc-autofit').addEventListener('change', drawPreview);

  // ── 라벨 크기 단위 (dots ↔ mm, 203dpi: 1mm = 8 dots) — 저장은 항상 dots ──
  const DOTS_PER_MM = 8;
  let sizeUnit = 'dots';

  function sizeToDisplay(dots) {
    return sizeUnit === 'mm' ? Math.round((dots / DOTS_PER_MM) * 10) / 10 : dots;
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
      // [2026-10-07] la orientación elegida (no la de fábrica del modo)
      orientation: currentMode?.orientation || base.orientation,
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

    niveles.slice(0, 3).forEach((nv, i) => {
      const slot = layout[`price${i + 1}`];
      if (!slot) return;
      const aFs = slot.fontSize || 24;
      blocks.push({
        slot,
        labelText: nv,
        amountText: amounts[i] || '$0,00',
        aFs,
        lFs: Math.max(12, Math.round(aFs / 4)),
        bold: !!slot.bold || i === 0,
      });
    });

    return blocks;
  }

  function drawPreview() {
    const canvas = $('#preview-canvas');
    if (!canvas) return;
    const mode = buildModeFromForm();
    if (!mode.width) return;

    const maxW = 400, maxH = 300;
    const scale = Math.min(maxW / mode.width, maxH / mode.height);
    canvas.width = Math.round(mode.width * scale);
    canvas.height = Math.round(mode.height * scale);

    const ctx = canvas.getContext('2d');
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    drawCopy(ctx, mode, scale, 0);

    if (mode.duplicate && mode.halfWidth) {
      ctx.strokeStyle = '#bbb';
      ctx.setLineDash([4, 4]);
      ctx.beginPath();
      ctx.moveTo(mode.halfWidth * scale, 0);
      ctx.lineTo(mode.halfWidth * scale, canvas.height);
      ctx.stroke();
      ctx.setLineDash([]);
      drawCopy(ctx, mode, scale, mode.halfWidth);
    }
  }

  function drawCopy(ctx, mode, scale, offsetX) {
    const layout = mode.layout;
    const rotated = mode.orientation === 'R';
    const region = {
      width: mode.duplicate && mode.halfWidth ? mode.halfWidth : mode.width,
      height: mode.height,
    };
    ctx.fillStyle = '#111';

    // 상품 설명
    drawZplText(ctx, layout.name, SAMPLE_NAME, scale, offsetX, rotated, false);

    // 바코드 (의사 막대 패턴 + SKU, auto-fit 반영)
    drawBarcode(ctx, layout.barcode, scale, offsetX, rotated, region);

    // 가격 블록 — formatter renderCopy 와 동일 배치 로직
    const blocks = samplePriceBlocks(layout);
    const auto = layout.autoPrices !== false;

    if (auto && !rotated) {
      // 오른쪽 하단부터 왼쪽으로 (Precio 1 = 맨 오른쪽)
      const marginR = 10, marginB = 8, gap = 18;
      let rightEdge = region.width - marginR;

      for (const b of blocks) {
        const aW = estW(b.amountText, b.aFs);
        const lW = b.labelText ? estW(b.labelText, b.lFs) : 0;
        const w = Math.max(aW, lW);
        const x = Math.max(0, rightEdge - w);
        const amountY = Math.max(0, region.height - marginB - b.aFs);
        const labelY = Math.max(0, amountY - b.lFs - 2);

        if (b.labelText) drawZplText(ctx, { x: x + (w - lW), y: labelY, fontSize: b.lFs }, b.labelText, scale, offsetX, rotated, false);
        drawZplText(ctx, { x: x + (w - aW), y: amountY, fontSize: b.aFs }, b.amountText, scale, offsetX, rotated, b.bold);
        rightEdge = x - gap;
      }
    } else if (auto && rotated) {
      // 세로 리본 — price1 기점으로 리본 방향 순차 배치
      const gap = 16;
      const x0 = layout.price1?.x ?? 20;
      let y = layout.price1?.y ?? 10;

      for (const b of blocks) {
        if (b.labelText) drawZplText(ctx, { x: x0 + b.aFs + 2, y, fontSize: b.lFs }, b.labelText, scale, offsetX, rotated, false);
        drawZplText(ctx, { x: x0, y, fontSize: b.aFs }, b.amountText, scale, offsetX, rotated, b.bold);
        y += Math.max(estW(b.amountText, b.aFs), b.labelText ? estW(b.labelText, b.lFs) : 0) + gap;
      }
    } else {
      // 수동 — 슬롯 위치 = 금액, nivel 라벨은 위(가로)/옆(세로)
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
      y += len + gap;
    }
  } else {
    // 수동 배치 — 슬롯 x/y = 금액 위치, nivel 라벨은 금액 위(N)/옆(R)에 소형 표시
    for (const b of blocks) {
      const { slot } = b;

      if (b.labelText) {
        if (orientation === 'R') {
          lines.push(`^FO${slot.x + b.aFs + 2 + offsetX},${slot.y}${font},${b.lFs},${b.lFs}^FD${sanitize(b.labelText)}^FS`);
        } else {
          const labelY = Math.max(0, slot.y - b.lFs - 2);
          lines.push(`^FO${slot.x + offsetX},${labelY}${font},${b.lFs},${b.lFs}^FD${sanitize(b.labelText)}^FS`);
        }
      }
      const fw = b.bold ? Math.round(b.aFs * 1.2) : b.aFs;
      lines.push(`^FO${slot.x + offsetX},${slot.y}${font},${b.aFs},${fw}^FD${sanitize(b.amountText)}^FS`);
    }
  }

  return lines;
}

/**
 * 단일 상품 라벨 ZPL 생성
 * @param {Object} item - { name, sku, barcodeType, prices: [{ label, amount }] }
 * @param {Object} mode - LABEL_MODES 중 하나 (커스텀 layout/width/height 오버라이드 가능)
 * @returns {string} ZPL 문자열
 */
function formatLabel(item, mode) {
  const m = mode || LABEL_MODES['simple-face'];
  const layout = m.layout || LABEL_MODES['simple-face'].layout;
  const orientation = m.orientation === 'R' ? 'R' : 'N';

  const lines = [
    '^XA',
    `^PW${m.width}`,
    `^LL${m.height}`,
    '^CI28',
  ];

  // 출력 속도 (^PR — 2~14 ips, 미설정 시 프린터 기본값)
  const pr = speedZpl(m.speed);
  if (pr) lines.push(pr);

  // 복제본 영역 크기 (duplicado 는 절반 폭 기준으로 auto 배치)
  const region = {
    width: m.duplicate && m.halfWidth ? m.halfWidth : m.width,
    height: m.height,
  };

  // 왼쪽 (또는 단일) 복제본
  lines.push(...renderCopy(item, layout, orientation, 0, region));

  // modo-duplicado: 오른쪽 복제본
  if (m.duplicate && m.halfWidth) {
    lines.push(...renderCopy(item, layout, orientation, m.halfWidth, region));
  }

  lines.push('^XZ');

  return lines.join('\n');
}

/**
 * 여러 상품 라벨 일괄 생성 (qty 반복 포함)
 * @param {Array} items - [{ name, sku, barcodeType, prices, qty }]
 * @param {Object} mode - 출력 모드 (LABEL_MODES 항목 또는 커스텀)
 * @returns {string} 전체 ZPL 문자열
 */
/**
function darknessZpl(value) {
  const d = parseInt(value, 10);
  if (!Number.isFinite(d) || d < 0 || d > 30) return null;

  return `~SD${String(d).padStart(2, '0')}`;
}

/**
 * 출력 속도 명령 (^PR) — 라벨 포맷 내부 명령
 * @param {number|string} value - 2~14 ips
 * @returns {string|null} 범위 밖/미설정 시 null (프린터 기본값 사용)
 */
function speedZpl(value) {
  const s = parseInt(value, 10);
  if (!Number.isFinite(s) || s < 2 || s > 14) return null;

  return `^PR${s}`;
}

/**
 * 단일 복제본 ZPL 라인 생성 (오프셋 적용 가능)
 * @param {Object} item - { name, sku, barcodeType, prices: [{ label, amount }] }
 * @param {Object} layout - 위치/크기 설정 (priceCount, autoPrices 포함)
 * @param {string} orientation - 'N' | 'R'
 * @param {number} offsetX - X축 오프셋 (duplicado 오른쪽 복제본용)
 * @param {Object} region - 복제본 영역 { width, height } (auto 배치 기준)
 * @returns {string[]} ZPL 라인 배열
 */
function renderCopy(item, layout, orientation, offsetX = 0, region = { width: 400, height: 200 }) {
  const lines = [];
  const font = orientation === 'R' ? '^A0R' : '^A0N';
  const barcodeType = (item.barcodeType || 'CODE128').toUpperCase();

  // 상품명 (제품 설명)
  const nm = layout.name || { x: 10, y: 5, fontSize: 20 };
  if (item.name) {
    // [2026-10-07] `lines` > 1: el nombre se parte en renglones dentro del ancho (^FB) —
    //   en una etiqueta angosta en horizontal no entra en uno
    const renglones = Number(nm.lines) > 1 ? Math.min(5, Number(nm.lines)) : 0;
    const ancho = orientation === 'R' ? region.height - nm.y - 10 : region.width - nm.x - 10;
    const fb = renglones && ancho > 0 ? `^FB${ancho},${renglones},0,L,0` : '';
    lines.push(`^FO${nm.x + offsetX},${nm.y}${font},${nm.fontSize},${nm.fontSize}${fb}^FD${sanitize(item.name)}^FS`);
  }

  // 바코드 (SKU를 바코드 값으로 사용)
  const bc = layout.barcode || { x: 10, y: 30, height: 45, moduleWidth: 3 };
  const barcodeValue = item.sku || item.barcode || '';
  if (barcodeValue) {
    const mw = effectiveModuleWidth(bc, barcodeValue, barcodeType, orientation, region);
    lines.push(barcodeZpl(barcodeType, bc.x + offsetX, bc.y, barcodeValue, bc.height, mw, orientation));
  }

  // 가격 0~3개 — priceCount로 출력 개수 제한 (0이면 미출력)
  const rawCount = layout.priceCount;
  const priceCount = Math.max(0, Math.min(3, rawCount == null ? 3 : parseInt(rawCount, 10) || 0));
  const prices = item.prices || [];

  // 가격 블록 구성 — nivel 라벨(1/4 크기)은 금액 위에 별도 표시
  const blocks = [];
  for (let i = 0; i < priceCount; i++) {
    const slot = layout[`price${i + 1}`] || { x: 10, y: 100, fontSize: 24 };
    const priceData = prices[i];
    if (!priceData) continue;

    const amountText = formatPrice(priceData.amount);
    if (!amountText) continue;

    const aFs = slot.fontSize || 24;
    blocks.push({
      slot,
      amountText,
      labelText: priceData.label || '',
      aFs,
      lFs: nivelFontSize(aFs),
      bold: !!slot.bold,
    });
  }

  const auto = layout.autoPrices !== false;

  if (auto && orientation === 'N') {
    // 자동 배치 — 오른쪽 하단부터 왼쪽으로 (Precio 1 이 맨 오른쪽)
    const marginR = 10;
    const marginB = 8;
    const gap = 18;
    let rightEdge = region.width - marginR;

    for (const b of blocks) {
      const aW = estTextWidth(b.amountText, b.aFs);
      const lW = b.labelText ? estTextWidth(b.labelText, b.lFs) : 0;
      const w = Math.max(aW, lW);
/**
 * Poliamida vertical / horizontal (2026-10-07) — la persona elige; cada orientación con su diseño.
 * 실행: node test/orientacion.test.js
 */
const assert = require('assert');
const { modoEfectivo, guardarCustom, formatLabel, resolveMode } = require('../src/zpl-formatter');

let passed = 0;
function ok(name, cond) {
  assert.ok(cond, name);
  passed += 1;
  console.log('  ✓', name);
}

const poli = resolveMode('poliamida-vertical');
const simple = resolveMode('simple-face');
const item = { name: 'REMERA OVERSIZE NEGRA M', sku: '259423611017', barcodeType: 'CODE128', prices: [{ label: 'Lista', amount: 15999 }] };

// ── modo efectivo ──
ok('sin elegir nada: vertical (como siempre)', modoEfectivo(poli, {}).orientation === 'R');
const h = modoEfectivo(poli, { orientation: 'N' });
ok('horizontal: orientación N y el diseño horizontal', h.orientation === 'N' && h.layout === poli.layoutHorizontal);
ok('un modo no orientable ignora la orientación guardada', modoEfectivo(simple, { orientation: 'R' }).orientation === 'N');
ok('el diseño guardado de vertical (guardados viejos) no se mezcla con horizontal',
  modoEfectivo(poli, { orientation: 'N', layout: { name: { x: 999, y: 1, fontSize: 9 } } }).layout.name.x === poli.layoutHorizontal.name.x);
ok('el diseño horizontal guardado se aplica en horizontal',
  modoEfectivo(poli, { orientation: 'N', layoutN: { name: { x: 33, y: 1, fontSize: 9 } } }).layout.name.x === 33);
ok('densidad/velocidad (extra) siguen entrando', modoEfectivo(poli, {}, { darkness: 12 }).darkness === 12);

// ── guardar ──
let c = guardarCustom({ layout: { a: 1 } }, poli, { tipo: 'orientacion', orientation: 'N' });
ok('elegir horizontal no borra el diseño vertical', c.orientation === 'N' && c.layout.a === 1);
c = guardarCustom(c, poli, { tipo: 'diseno', width: 200, height: 400, layout: { b: 2 } });
ok('guardar en horizontal escribe layoutN, deja layout', c.layoutN.b === 2 && c.layout.a === 1);
c = guardarCustom(c, poli, { tipo: 'reset' });
ok('restablecer en horizontal borra sólo el horizontal', !c.layoutN && c.layout.a === 1 && c.orientation === 'N');
c = guardarCustom(c, poli, { tipo: 'orientacion', orientation: 'R' });
ok('volver a vertical', !c.orientation && modoEfectivo(poli, c).orientation === 'R');
ok('orientación en un modo no orientable: no cambia nada',
  JSON.stringify(guardarCustom({ layout: { a: 1 } }, simple, { tipo: 'orientacion', orientation: 'N' })) === JSON.stringify({ layout: { a: 1 } }));

// ── la etiqueta ──
const zV = formatLabel(item, modoEfectivo(poli, {}));
const zH = formatLabel(item, modoEfectivo(poli, { orientation: 'N' }));
ok('vertical: todo girado', zV.includes('^A0R') && zV.includes('^BCR') && !zV.includes('^A0N'));
ok('horizontal: todo derecho', zH.includes('^A0N') && zH.includes('^BCN') && !zH.includes('^A0R'));
ok('horizontal: el nombre se parte en hasta 3 renglones dentro de 200 (^FB180,3)', /\^FO10,12\^A0N,22,22\^FB180,3,0,L,0\^FDREMERA/.test(zH));
ok('vertical: el nombre sigue en un renglón (sin ^FB)', !zV.includes('^FB'));
ok('[Vista Zebra] vertical: el código ya no pisa el nivel de precio (x 80)', zV.includes('^FO80,10^BY'));
const by = Number(/\^BY(\d+)/.exec(zH)[1]);
ok(`horizontal: el código se achica para entrar (^BY${by})`, by >= 1 && by < 3);
ok('otros modos no cambian (sin ^FB)', !formatLabel(item, modoEfectivo(simple, {})).includes('^FB'));

console.log(`\n${passed} ok`);

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
/bin/zsh -lc "rg -n \"btn-reset|Restablecer|setLabelLayout\\(null|currentModeKey|function renderPresetCards|const modes|let modes\" zebra-agent/renderer/index.html; sed -n '950,1035p' zebra-agent/renderer/index.html; sed -n '1170,1220p' zebra-agent/renderer/index.html; nl -ba zebra-agent/src/zpl-formatter.js | sed -n '108,175p;405,435p;1150,1235p'; nl -ba zebra-agent/renderer/index.html | sed -n '1028,1060p;1108,1160p;1190,1220p'" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
639:            <button class="btn btn-secondary" id="btn-reset-layout">Restablecer</button>
978:  let modes = [];
979:  let currentModeKey = 'simple-face';
987:    currentModeKey = config.modeKey || config.presetKey;
1006:  function renderPresetCards() {
1011:      card.className = 'preset-card' + (p.key === currentModeKey ? ' active' : '');
1017:        currentModeKey = p.key;
1033:    const base = modes.find(m => m.key === currentModeKey);
1115:    const base = modes.find(m => m.key === currentModeKey) || modes[0] || {};
1203:  $('#btn-reset-layout').addEventListener('click', async () => {
1204:    await api.setLabelLayout(null);
      const t = d.querySelector('.ts'); const m = d.querySelector('.msg');
      return ((t && t.textContent) || '') + '  ' + ((m && m.textContent) || '');
    }).join('\n').trim();

    const feedback = () => {
      const b = $('#btn-copy-log');
      if (!b) return;
      const prev = b.textContent; b.textContent = 'Copiado ✓';
      setTimeout(() => { b.textContent = prev; }, 1200);
    };
    const fallback = () => {
      const ta = document.createElement('textarea');
      ta.value = text; ta.style.position = 'fixed'; ta.style.opacity = '0';
      document.body.appendChild(ta); ta.focus(); ta.select();
      try { document.execCommand('copy'); } catch (_) {}
      document.body.removeChild(ta); feedback();
    };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(feedback).catch(fallback);
    } else {
      fallback();
    }
  }
  { const b = $('#btn-copy-log'); if (b) b.addEventListener('click', copyLog); }

  // ═══════════════════════════════════════════════════════════════════════
  // 출력 모드 + 레이아웃 + precio nivel 상태
  // ═══════════════════════════════════════════════════════════════════════
  let modes = [];
  let currentModeKey = 'simple-face';
  let currentMode = null;
  let priceSelection = [];
  let availableNiveles = [];

  async function loadLabelConfig() {
    modes = await api.getLabelPresets();
    const config = await api.getLabelConfig();
    currentModeKey = config.modeKey || config.presetKey;
    currentMode = config.mode || config.preset;
    priceSelection = config.priceSelection || [];
    renderPresetCards();
    pintarOrientacion();
    loadLayoutEditor();
    await loadPrintSettings();
    renderNivelCombos();
    updateModeChip();
    drawPreview();
  }

  function updateModeChip() {
    $('#current-mode-chip').textContent = currentMode?.name || '-';
    $('#current-niveles').textContent = priceSelection.length > 0
      ? priceSelection.map(s => s.name).join(' / ')
      : 'sin precios (o 1º del servidor)';
  }

  function renderPresetCards() {
    const container = $('#preset-cards');
    container.textContent = '';
    modes.forEach(p => {
      const card = document.createElement('div');
      card.className = 'preset-card' + (p.key === currentModeKey ? ' active' : '');
      const name = document.createElement('div'); name.className = 'preset-name'; name.textContent = p.name;
      const size = document.createElement('div'); size.className = 'preset-size';
      size.textContent = p.description || `${p.width}x${p.height} dots`;
      card.appendChild(name); card.appendChild(size);
      card.addEventListener('click', async () => {
        currentModeKey = p.key;
        await api.setLabelPreset(p.key);
        const cfg = await api.getLabelConfig();
        currentMode = cfg.mode || cfg.preset;
        renderPresetCards();
        pintarOrientacion();
        loadLayoutEditor();
        updateModeChip();
        drawPreview();
      });
      container.appendChild(card);
    });
  }

  // [2026-10-07] orientación (sólo modos `orientable`, hoy Poliamida)
  function pintarOrientacion() {
    const base = modes.find(m => m.key === currentModeKey);
    const box = $('#orientacion-box');
    box.style.display = base && base.orientable ? 'block' : 'none';
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
   108	};
   109	
   110	/**
   111	 * [2026-10-07] Modo efectivo = modo base + lo guardado por la persona (labelLayouts[modo]).
   112	 *   custom: { width, height, layout, orientation?, layoutN? }
   113	 *   ★ `layout` es el diseño de la orientación de fábrica (el que existía antes: los guardados
   114	 *     viejos siguen valiendo); `layoutN` el de horizontal, sólo en modos `orientable`.
   115	 */
   116	function modoEfectivo(base, custom = {}, extra = {}) {
   117	  const c = custom || {};
   118	  const horizontal = !!(base.orientable && base.layoutHorizontal && c.orientation === 'N');
   119	  const baseLayout = horizontal ? base.layoutHorizontal : base.layout;
   120	  const propio = horizontal ? c.layoutN : c.layout;
   121	  const width = c.width || base.width;
   122	
   123	  return {
   124	    ...base,
   125	    orientation: horizontal ? 'N' : base.orientation,
   126	    width,
   127	    height: c.height || base.height,
   128	    // duplicado 절반 너비는 커스텀 width 의 절반으로 재계산
   129	    halfWidth: base.duplicate ? Math.round(width / 2) : base.halfWidth,
   130	    layout: propio ? { ...baseLayout, ...propio } : baseLayout,
   131	    ...extra,
   132	  };
   133	}
   134	
   135	/**
   136	 * [2026-10-07] Lo que se guarda al tocar «Guardar diseño» / «Restablecer» / la orientación,
   137	 *   sin perder el diseño de la OTRA orientación.
   138	 * @param {object} prev  lo guardado hasta ahora (labelLayouts[modo])
   139	 * @param {object} base  el modo de fábrica
   140	 * @param {{ tipo:'diseno'|'reset'|'orientacion', width?, height?, layout?, orientation? }} cambio
   141	 */
   142	function guardarCustom(prev, base, cambio) {
   143	  const p = { ...(prev || {}) };
   144	  const horizontal = !!(base.orientable && base.layoutHorizontal && p.orientation === 'N');
   145	  if (cambio.tipo === 'orientacion') {
   146	    if (!base.orientable || !base.layoutHorizontal) return p;
   147	    if (cambio.orientation === 'N') p.orientation = 'N';
   148	    else delete p.orientation;
   149	
   150	    return p;
   151	  }
   152	  if (cambio.tipo === 'reset') {
   153	    delete p.width;
   154	    delete p.height;
   155	    if (horizontal) delete p.layoutN;
   156	    else delete p.layout;
   157	
   158	    return p;
   159	  }
   160	  p.width = cambio.width || undefined;
   161	  p.height = cambio.height || undefined;
   162	  if (horizontal) p.layoutN = cambio.layout;
   163	  else p.layout = cambio.layout;
   164	
   165	  return p;
   166	}
   167	
   168	// 구버전 프리셋 키 → 신규 모드 키 매핑 (설정 마이그레이션용)
   169	const LEGACY_PRESET_ALIASES = {
   170	  '50x25-simple': 'simple-face',
   171	  '50x25-doble': 'doble-face',
   172	  '100x25-cartulina': 'modo-duplicado',
   173	};
   174	
   175	/**
   405	 * @param {Object} region - 복제본 영역 { width, height } (auto 배치 기준)
   406	 * @returns {string[]} ZPL 라인 배열
   407	 */
   408	function renderCopy(item, layout, orientation, offsetX = 0, region = { width: 400, height: 200 }) {
   409	  const lines = [];
   410	  const font = orientation === 'R' ? '^A0R' : '^A0N';
   411	  const barcodeType = (item.barcodeType || 'CODE128').toUpperCase();
   412	
   413	  // 상품명 (제품 설명)
   414	  const nm = layout.name || { x: 10, y: 5, fontSize: 20 };
   415	  if (item.name) {
   416	    // [2026-10-07] `lines` > 1: el nombre se parte en renglones dentro del ancho (^FB) —
   417	    //   en una etiqueta angosta en horizontal no entra en uno
   418	    const renglones = Number(nm.lines) > 1 ? Math.min(5, Number(nm.lines)) : 0;
   419	    const ancho = orientation === 'R' ? region.height - nm.y - 10 : region.width - nm.x - 10;
   420	    const fb = renglones && ancho > 0 ? `^FB${ancho},${renglones},0,L,0` : '';
   421	    lines.push(`^FO${nm.x + offsetX},${nm.y}${font},${nm.fontSize},${nm.fontSize}${fb}^FD${sanitize(item.name)}^FS`);
   422	  }
   423	
   424	  // 바코드 (SKU를 바코드 값으로 사용)
   425	  const bc = layout.barcode || { x: 10, y: 30, height: 45, moduleWidth: 3 };
   426	  const barcodeValue = item.sku || item.barcode || '';
   427	  if (barcodeValue) {
   428	    const mw = effectiveModuleWidth(bc, barcodeValue, barcodeType, orientation, region);
   429	    lines.push(barcodeZpl(barcodeType, bc.x + offsetX, bc.y, barcodeValue, bc.height, mw, orientation));
   430	  }
   431	
   432	  // 가격 0~3개 — priceCount로 출력 개수 제한 (0이면 미출력)
   433	  const rawCount = layout.priceCount;
   434	  const priceCount = Math.max(0, Math.min(3, rawCount == null ? 3 : parseInt(rawCount, 10) || 0));
   435	  const prices = item.prices || [];
  1150	 * ★ [2026-10-07] Etiqueta angosta (Poliamida, 25×50): la prueba sigue la orientación elegida —
  1151	 *   vertical = girada (^A0R/^BCR, como la etiqueta real), horizontal = 25 mm de ancho con un
  1152	 *   código corto que entra entero. Antes salía la de 50×25 y se cortaba («…TES»).
  1153	 *
  1154	 * @param {Object} mode - modo efectivo (getEffectiveMode): width, halfWidth, duplicate, name
  1155	 * @param {{darkness?: number|null, speed?: number|null}} ajustes
  1156	 * @returns {string} ZPL
  1157	 */
  1158	function formatTestLabel(mode, { darkness = null, speed = null } = {}) {
  1159	  const doble = !!(mode && mode.duplicate && mode.halfWidth);
  1160	  const angosta = !doble && mode && mode.width && mode.width < 400;
  1161	  if (angosta) return testAngosta(mode, { darkness, speed });
  1162	  const ancho = doble ? mode.width : 400;
  1163	  // ★ [codex 041] el código se achica a su etiqueta, igual que `renderCopy`: con ^BY3 mide
  1164	  //   435 dots. En doble banda la izquierda se metía en la derecha; en una cara (400 dots)
  1165	  //   se cortaba el final (2026-10-07 «맞춰줘»). Nunca más ancho que los 400 de antes.
  1166	  const region = doble ? mode.halfWidth : Math.min(400, (mode && mode.width) || 400);
  1167	  const by = effectiveModuleWidth({ x: 10, moduleWidth: 3 }, '1234567890', 'CODE128', 'N', {
  1168	    width: region,
  1169	    height: (mode && mode.height) || 200,
  1170	  });
  1171	  const copia = (dx) => [
  1172	    `^FO${10 + dx},5^A0N,22,22^FDVENTAGO ZEBRA TEST^FS`,
  1173	    `^FO${10 + dx},30^BY${by}^BCN,50,Y,N,N^FD1234567890^FS`,
  1174	    `^FO${10 + dx},100^A0N,28,28^FD$0.00^FS`,
  1175	    `^FO${10 + dx},135^A0N,16,16^FDD:${darkness ?? 'auto'} V:${speed ?? 'auto'}^FS`,
  1176	    // en doble banda, cuál es cuál: así se ve si la derecha salió corrida
  1177	    ...(doble ? [`^FO${10 + dx},158^A0N,16,16^FD${dx === 0 ? 'IZQ' : 'DER'} · ${sanitize(mode.name || '')}^FS`] : []),
  1178	  ];
  1179	
  1180	  return [
  1181	    darknessZpl(darkness),
  1182	    '^XA',
  1183	    `^PW${ancho}`,
  1184	    // [codex 041] el alto del modo (puede estar personalizado), como la etiqueta real
  1185	    `^LL${doble && mode.height ? mode.height : 200}`,
  1186	    '^CI28',
  1187	    speedZpl(speed),
  1188	    ...copia(0),
  1189	    ...(doble ? copia(mode.halfWidth) : []),
  1190	    '^XZ',
  1191	  ]
  1192	    .filter(Boolean)
  1193	    .join('\n');
  1194	}
  1195	
  1196	function testAngosta(mode, { darkness, speed }) {
  1197	  const ancho = mode.width;
  1198	  const alto = mode.height || 400;
  1199	  const girada = mode.orientation === 'R';
  1200	  const pie = `D:${darkness ?? 'auto'} V:${speed ?? 'auto'}`;
  1201	  let campos;
  1202	  if (girada) {
  1203	    // el texto corre a lo largo de la etiqueta (+y); x = de afuera hacia adentro
  1204	    const by = effectiveModuleWidth({ x: 0, y: 10, moduleWidth: 3 }, '1234567890', 'CODE128', 'R', { width: ancho, height: alto });
  1205	    campos = [
  1206	      `^FO${ancho - 34},10^A0R,22,22^FDVENTAGO ZEBRA TEST^FS`,
  1207	      `^FO${ancho - 120},10^BY${by}^BCR,60,Y,N,N^FD1234567890^FS`,
  1208	      `^FO26,10^A0R,28,28^FD$0.00^FS`,
  1209	      `^FO6,10^A0R,16,16^FD${pie} · VERTICAL^FS`,
  1210	    ];
  1211	  } else {
  1212	    const by = effectiveModuleWidth({ x: 10, moduleWidth: 3 }, '1234', 'CODE128', 'N', { width: ancho, height: alto });
  1213	    campos = [
  1214	      `^FO10,10^A0N,22,22^FB${ancho - 20},2,0,L,0^FDVENTAGO ZEBRA TEST^FS`,
  1215	      `^FO10,70^BY${by}^BCN,60,Y,N,N^FD1234^FS`,
  1216	      `^FO10,170^A0N,28,28^FD$0.00^FS`,
  1217	      `^FO10,210^A0N,16,16^FD${pie}^FS`,
  1218	      `^FO10,232^A0N,16,16^FDHORIZONTAL^FS`,
  1219	    ];
  1220	  }
  1221	
  1222	  return [
  1223	    darknessZpl(darkness),
  1224	    '^XA',
  1225	    `^PW${ancho}`,
  1226	    `^LL${alto}`,
  1227	    '^CI28',
  1228	    speedZpl(speed),
  1229	    ...campos,
  1230	    '^XZ',
  1231	  ]
  1232	    .filter(Boolean)
  1233	    .join('\n');
  1234	}
  1235	
  1028	    });
  1029	  }
  1030	
  1031	  // [2026-10-07] orientación (sólo modos `orientable`, hoy Poliamida)
  1032	  function pintarOrientacion() {
  1033	    const base = modes.find(m => m.key === currentModeKey);
  1034	    const box = $('#orientacion-box');
  1035	    box.style.display = base && base.orientable ? 'block' : 'none';
  1036	    const actual = currentMode?.orientation === 'N' ? 'N' : 'R';
  1037	    document.querySelectorAll('input[name="orientacion"]').forEach(r => { r.checked = r.value === actual; });
  1038	  }
  1039	
  1040	  document.querySelectorAll('input[name="orientacion"]').forEach(r => {
  1041	    r.addEventListener('change', async () => {
  1042	      if (!r.checked) return;
  1043	      try {
  1044	        await api.setLabelOrientation(r.value);
  1045	      } catch (err) {
  1046	        addLocalLog('No se pudo cambiar la orientación: ' + err.message);
  1047	      }
  1048	      // lo que quedó guardado manda (si no se pudo, vuelve el radio)
  1049	      currentMode = (await api.getLabelConfig()).mode;
  1050	      pintarOrientacion();
  1051	      loadLayoutEditor();
  1052	      drawPreview();
  1053	      addLocalLog('Orientación: ' + (currentMode?.orientation === 'N' ? 'horizontal' : 'vertical'));
  1054	    });
  1055	  });
  1056	
  1057	  // ── 레이아웃 편집기 ──
  1058	  const LAYOUT_FIELDS = [
  1059	    ['#lay-name-x', 'name', 'x'], ['#lay-name-y', 'name', 'y'], ['#lay-name-fs', 'name', 'fontSize'],
  1060	    ['#lay-bc-x', 'barcode', 'x'], ['#lay-bc-y', 'barcode', 'y'], ['#lay-bc-h', 'barcode', 'height'],
  1108	    sizeUnit = $('#lay-size-unit').value;
  1109	    $('#lay-w').value = sizeToDisplay(wDots);
  1110	    $('#lay-h').value = sizeToDisplay(hDots);
  1111	  });
  1112	
  1113	  // 편집 필드 → 현재 폼 값 기준 모드 객체 구성 (미리보기/저장 공용)
  1114	  function buildModeFromForm() {
  1115	    const base = modes.find(m => m.key === currentModeKey) || modes[0] || {};
  1116	    const layout = {};
  1117	    LAYOUT_FIELDS.forEach(([sel, elem, prop]) => {
  1118	      if (!layout[elem]) layout[elem] = { ...(currentMode?.layout?.[elem] || base.layout?.[elem] || {}) };
  1119	      layout[elem][prop] = int(sel);
  1120	    });
  1121	    const width = displayToDots('#lay-w') || base.width;
  1122	    const height = displayToDots('#lay-h') || base.height;
  1123	
  1124	    // 자동 배치 / 바코드 auto-fit 플래그
  1125	    layout.autoPrices = $('#lay-auto-prices').checked;
  1126	    if (layout.barcode) layout.barcode.autoFit = $('#lay-bc-autofit').checked;
  1127	
  1128	    return {
  1129	      ...base,
  1130	      // [2026-10-07] la orientación elegida (no la de fábrica del modo)
  1131	      orientation: currentMode?.orientation || base.orientation,
  1132	      width,
  1133	      height,
  1134	      halfWidth: base.duplicate ? Math.round(width / 2) : undefined,
  1135	      layout,
  1136	    };
  1137	  }
  1138	
  1139	  // 입력 변경 → 실시간 미리보기
  1140	  LAYOUT_FIELDS.forEach(([sel]) => $(sel).addEventListener('input', drawPreview));
  1141	  ['#lay-w', '#lay-h', '#sample-sku'].forEach(s => $(s).addEventListener('input', drawPreview));
  1142	
  1143	  $('#btn-save-layout').addEventListener('click', async () => {
  1144	    const m = buildModeFromForm();
  1145	    await api.setLabelLayout({
  1146	      width: m.width,
  1147	      height: m.height,
  1148	      layout: m.layout,
  1149	    });
  1150	    currentMode = (await api.getLabelConfig()).mode;
  1151	    updateModeChip();
  1152	    drawPreview();
  1153	    addLocalLog('Diseño guardado');
  1154	  });
  1155	
  1156	  // ── 출력 파라미터 (전역 — 모든 모드 + QR 공통) ──
  1157	  // 슬라이더 ↔ 숫자 입력 양방향. 빈 숫자 = auto(프린터 기본값)
  1158	  function bindPrintSlider(numSel, rangeSel) {
  1159	    $(rangeSel).addEventListener('input', () => { $(numSel).value = $(rangeSel).value; });
  1160	    $(numSel).addEventListener('input', () => {
  1190	    });
  1191	    showPrintSettings(saved);
  1192	    currentMode = (await api.getLabelConfig()).mode;
  1193	    addLocalLog(`Impresión guardada — oscuridad ${saved.darkness ?? 'auto'}, velocidad ${saved.speed ?? 'auto'}`);
  1194	  });
  1195	
  1196	  $('#btn-clear-print').addEventListener('click', async () => {
  1197	    const saved = await api.setPrintSettings({ darkness: null, speed: null });
  1198	    showPrintSettings(saved);
  1199	    currentMode = (await api.getLabelConfig()).mode;
  1200	    addLocalLog('Impresión: valores por defecto de la impresora');
  1201	  });
  1202	
  1203	  $('#btn-reset-layout').addEventListener('click', async () => {
  1204	    await api.setLabelLayout(null);
  1205	    currentMode = (await api.getLabelConfig()).mode;
  1206	    loadLayoutEditor();
  1207	    drawPreview();
  1208	    addLocalLog('Diseño restablecido');
  1209	  });
  1210	
  1211	  function int(sel) { return parseInt($(sel).value) || 0; }
  1212	
  1213	  // ═══════════════════════════════════════════════════════════════════════
  1214	  // 실시간 미리보기 (canvas — ZPL dot 좌표계를 스케일 변환)
  1215	  // ═══════════════════════════════════════════════════════════════════════
  1216	  const SAMPLE_NAME = 'REMERA OVERSIZE NEGRA M';
  1217	
  1218	  function sampleSku() {
  1219	    return ($('#sample-sku')?.value || '').trim() || 'VG00123456';
  1220	  }

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
/bin/zsh -lc "sed -n '560,710p' zebra-agent/src/zpl-formatter.js; rg -n \"formatBatchLabels\\(|print:labels|simbolo\" zebra-agent/main.js | head -40; nl -ba zebra-agent/src/zpl-formatter.js | sed -n '580,680p'; node zebra-agent/test/orientacion.test.js; node zebra-agent/test/test-label.test.js" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:

  return lines.join('\n');
}

/**
 * 여러 상품 라벨 일괄 생성 (qty 반복 포함)
 * @param {Array} items - [{ name, sku, barcodeType, prices, qty }]
 * @param {Object} mode - 출력 모드 (LABEL_MODES 항목 또는 커스텀)
 * @returns {string} 전체 ZPL 문자열
 */
/**
 * QR 라벨 규칙 — 수량을 라벨 수로 옮긴다(지금은 `qrLoteFilas` 가 지킨다).
 *
 * ★★★ [2026-09-25 사용자 요구] 「바코드 대신 QR code 출력으로 선택」 +
 *   「티켓 하나당 1개를 출력할지 2개를 출력할지 선택」
 *
 * ★★ QR 에 담는 것은 **SKU** 다(사용자 결정: 「A 로 해야 바코드 리더기로 사용하겠지」).
 *   딥링크는 세 번째 탭(QR pendientes)에 그대로 남는다 — 그쪽은 손님이 휴대폰으로
 *   찍는 용도고, 이쪽은 매장 리더가 읽는 용도다. **같은 화면에 섞지 않는다.**
 *
 * ★ 수량은 **단위 수**이지 라벨 수가 아니다. 2개/라벨이면 9개 = 2장짜리 4장 + 1장짜리 1장.
 *   `ceil` 로 반올림해 2장짜리로만 찍으면 스티커가 하나 남는다.
 *
 * (qrLabelsDeItem — una fila por producto — se reemplazó por qrLoteFilas el 2026-10-03:
 *  las filas se llenan de corrido entre productos. Ver qrLoteFilas.)
 */

/**
 * [v1.0.29] Lo común a imprimir y a la vista previa del lote QR: el mismo diseño.
 * ★ Rollo: del modo elegido (doble banda si `duplicate`). Texto y QR: de la pestaña QR.
 */
function qrLoteBase(item, mode, opciones) {
  const porEtiqueta = opciones && opciones.porEtiqueta === 2 ? 2 : 1;
  const bandas = mode && mode.duplicate && mode.halfWidth ? 2 : 1;
  const anchoDots = mode && mode.width ? (bandas === 2 ? mode.halfWidth : mode.width) : 400;

  // 가격은 사용자가 고른 니벨의 첫 줄 — QR 라벨은 한 줄만 그린다.
  const primera = Array.isArray(item.prices) && item.prices.length > 0 ? item.prices[0] : null;
  const base = {
    contenido: String(item.sku || ''),
    name: item.name,
    price: primera ? primera.amount : item.price,
    priceLabel: primera ? primera.label : '',
  };
  const layout = {
    widthMm: anchoDots / 8,
    heightMm: mode && mode.height ? mode.height / 8 : 25,
    darkness: mode ? mode.darkness : undefined,
    speed: mode ? mode.speed : undefined,
    bandas,

    // qué texto y dónde + posición/tamaño del QR — lo guardado en la pestaña QR (qrLayout)
    ...[...TEXTO_KEYS, ...DISENO_QR_KEYS].reduce((o, k) => {
      if (opciones && opciones.texto && opciones.texto[k] !== undefined && opciones.texto[k] !== null && opciones.texto[k] !== '') o[k] = opciones.texto[k];

      return o;
    }, {}),
  };

  return { layout, base, porEtiqueta, bandas, porFila: bandas * porEtiqueta };
}

/** [v1.0.29] Una fila del lote QR para la vista previa / avisos (mismo camino que imprimir). */
function qrLotePreview(item, mode, opciones) {
  const { layout, base, porEtiqueta, porFila } = qrLoteBase(item, mode, opciones);
  const r = formatQrLabelConAvisos({ ...base, layout: { ...layout, mode: porEtiqueta === 2 ? 'doble' : 'simple' } });

  return { ...r, porFila, dibujo: zplADibujo(r.zpl) };
}

/**
 * ★★ [2026-10-03 · usuario] **Las filas se llenan de corrido entre productos.**
 *
 *   Antes cada producto empezaba fila nueva: con doble banda + 2 QR (4 por fila), 1 de
 *   19 + 4 de 1 salían en 9 filas con **13 casilleros en blanco** — con muchos productos
 *   de a 1 se tiraban 3 de cada 4 adhesivos. Ahora: 6 filas, 1 en blanco.
 *   Decisión del usuario: un adhesivo puede llevar QR de dos productos (se cortan).
 *
 *   Para que no se confundan al cortar, en la celda donde **empieza** otro producto:
 *     · una **raya vertical** a su izquierda (si no es la primera celda de la fila)
 *     · la **descripción siempre**, aunque en la pestaña QR esté apagada
 */
function qrLoteFilas(items, mode, opciones) {
  const lista = Array.isArray(items) ? items : [];
  if (lista.length === 0) return [];

  const { layout, porEtiqueta, porFila } = qrLoteBase(lista[0], mode, opciones);
  const modo = porEtiqueta === 2 ? 'doble' : 'simple';

  const celdas = [];
  for (const it of lista) {
    const { base } = qrLoteBase(it, mode, opciones);
    const qty = Math.max(1, it.qty || 1);
    for (let i = 0; i < qty; i++) celdas.push({ ...base, nuevo: i === 0 });
  }

  const filas = [];
  for (let i = 0; i < celdas.length; i += porFila) {
    const fila = celdas.slice(i, i + porFila);
    filas.push({
      ...formatQrLabelConAvisos({ ...fila[0], layout: { ...layout, mode: modo, celdas: fila } }),
      porFila,
    });
  }

  return filas;
}

/** [2026-10-03] Filas del lote entero, llenando de corrido (lo mismo que qrLoteFilas imprime). */
function filasDeLoteQrTotal(items, mode, opciones) {
  const porEtiqueta = opciones && opciones.porEtiqueta === 2 ? 2 : 1;
  const bandas = mode && mode.duplicate && mode.halfWidth ? 2 : 1;
  const unidades = (Array.isArray(items) ? items : []).reduce((s, it) => s + Math.max(1, (it && it.qty) || 1), 0);

  return Math.ceil(unidades / (bandas * porEtiqueta));
}

/** [v1.0.29] Cuántas filas (pasadas de la impresora) salen para `qty` unidades. */
function filasDeLoteQr(qty, mode, opciones) {
  const porEtiqueta = opciones && opciones.porEtiqueta === 2 ? 2 : 1;
  const bandas = mode && mode.duplicate && mode.halfWidth ? 2 : 1;

  return Math.ceil(Math.max(1, qty || 1) / (bandas * porEtiqueta));
}

/**
 * @param {Object} [opciones] - { simbolo: 'barras'|'qr', porEtiqueta: 1|2 }
 *   미지정이면 바코드 — 기존 호출부의 동작이 바뀌지 않는다.
 */
function formatBatchLabels(items, mode, opciones) {
  const labels = [];
  const esQr = !!(opciones && opciones.simbolo === 'qr');

  // 출력 밀도 (~SD — 절대값 00~30, 미설정 시 프린터 기본값)
  // ~SD 는 라벨 포맷(^XA..^XZ) 밖의 전역 명령이라 배치 앞에 1회만 전송
  // ★ QR 경로에서는 `formatQrLabel` 이 라벨마다 ~SD 를 동봉하므로 여기서 또 넣지 않는다.
  const sd = mode && !esQr ? darknessZpl(mode.darkness) : null;
  if (sd) labels.push(sd);

  // ★ [2026-10-03] QR: todas las unidades de todos los productos, de corrido (qrLoteFilas)
  if (esQr) {
    for (const f of qrLoteFilas(items, mode, opciones)) labels.push(f.zpl);

    return labels.join('\n');
  }

  for (const item of items) {

    const qty = Math.max(1, item.qty || 1);
    const zpl = formatLabel(item, mode);

552:ipcMain.handle('print:labels', async (_event, items, opciones) => {
560:  const esQr = !!(opciones && opciones.simbolo === 'qr');
571:    const zpl = formatBatchLabels(prepareItems(items), mode, {
572:      simbolo: esQr ? 'qr' : 'barras',
631:    //   guardado (print:labels → store.get('qrLayout')), y el editor guarda antes de imprimir.
1073:      const zpl = formatBatchLabels(prepareItems(payload.items), mode);
   580	 * ★ 수량은 **단위 수**이지 라벨 수가 아니다. 2개/라벨이면 9개 = 2장짜리 4장 + 1장짜리 1장.
   581	 *   `ceil` 로 반올림해 2장짜리로만 찍으면 스티커가 하나 남는다.
   582	 *
   583	 * (qrLabelsDeItem — una fila por producto — se reemplazó por qrLoteFilas el 2026-10-03:
   584	 *  las filas se llenan de corrido entre productos. Ver qrLoteFilas.)
   585	 */
   586	
   587	/**
   588	 * [v1.0.29] Lo común a imprimir y a la vista previa del lote QR: el mismo diseño.
   589	 * ★ Rollo: del modo elegido (doble banda si `duplicate`). Texto y QR: de la pestaña QR.
   590	 */
   591	function qrLoteBase(item, mode, opciones) {
   592	  const porEtiqueta = opciones && opciones.porEtiqueta === 2 ? 2 : 1;
   593	  const bandas = mode && mode.duplicate && mode.halfWidth ? 2 : 1;
   594	  const anchoDots = mode && mode.width ? (bandas === 2 ? mode.halfWidth : mode.width) : 400;
   595	
   596	  // 가격은 사용자가 고른 니벨의 첫 줄 — QR 라벨은 한 줄만 그린다.
   597	  const primera = Array.isArray(item.prices) && item.prices.length > 0 ? item.prices[0] : null;
   598	  const base = {
   599	    contenido: String(item.sku || ''),
   600	    name: item.name,
   601	    price: primera ? primera.amount : item.price,
   602	    priceLabel: primera ? primera.label : '',
   603	  };
   604	  const layout = {
   605	    widthMm: anchoDots / 8,
   606	    heightMm: mode && mode.height ? mode.height / 8 : 25,
   607	    darkness: mode ? mode.darkness : undefined,
   608	    speed: mode ? mode.speed : undefined,
   609	    bandas,
   610	
   611	    // qué texto y dónde + posición/tamaño del QR — lo guardado en la pestaña QR (qrLayout)
   612	    ...[...TEXTO_KEYS, ...DISENO_QR_KEYS].reduce((o, k) => {
   613	      if (opciones && opciones.texto && opciones.texto[k] !== undefined && opciones.texto[k] !== null && opciones.texto[k] !== '') o[k] = opciones.texto[k];
   614	
   615	      return o;
   616	    }, {}),
   617	  };
   618	
   619	  return { layout, base, porEtiqueta, bandas, porFila: bandas * porEtiqueta };
   620	}
   621	
   622	/** [v1.0.29] Una fila del lote QR para la vista previa / avisos (mismo camino que imprimir). */
   623	function qrLotePreview(item, mode, opciones) {
   624	  const { layout, base, porEtiqueta, porFila } = qrLoteBase(item, mode, opciones);
   625	  const r = formatQrLabelConAvisos({ ...base, layout: { ...layout, mode: porEtiqueta === 2 ? 'doble' : 'simple' } });
   626	
   627	  return { ...r, porFila, dibujo: zplADibujo(r.zpl) };
   628	}
   629	
   630	/**
   631	 * ★★ [2026-10-03 · usuario] **Las filas se llenan de corrido entre productos.**
   632	 *
   633	 *   Antes cada producto empezaba fila nueva: con doble banda + 2 QR (4 por fila), 1 de
   634	 *   19 + 4 de 1 salían en 9 filas con **13 casilleros en blanco** — con muchos productos
   635	 *   de a 1 se tiraban 3 de cada 4 adhesivos. Ahora: 6 filas, 1 en blanco.
   636	 *   Decisión del usuario: un adhesivo puede llevar QR de dos productos (se cortan).
   637	 *
   638	 *   Para que no se confundan al cortar, en la celda donde **empieza** otro producto:
   639	 *     · una **raya vertical** a su izquierda (si no es la primera celda de la fila)
   640	 *     · la **descripción siempre**, aunque en la pestaña QR esté apagada
   641	 */
   642	function qrLoteFilas(items, mode, opciones) {
   643	  const lista = Array.isArray(items) ? items : [];
   644	  if (lista.length === 0) return [];
   645	
   646	  const { layout, porEtiqueta, porFila } = qrLoteBase(lista[0], mode, opciones);
   647	  const modo = porEtiqueta === 2 ? 'doble' : 'simple';
   648	
   649	  const celdas = [];
   650	  for (const it of lista) {
   651	    const { base } = qrLoteBase(it, mode, opciones);
   652	    const qty = Math.max(1, it.qty || 1);
   653	    for (let i = 0; i < qty; i++) celdas.push({ ...base, nuevo: i === 0 });
   654	  }
   655	
   656	  const filas = [];
   657	  for (let i = 0; i < celdas.length; i += porFila) {
   658	    const fila = celdas.slice(i, i + porFila);
   659	    filas.push({
   660	      ...formatQrLabelConAvisos({ ...fila[0], layout: { ...layout, mode: modo, celdas: fila } }),
   661	      porFila,
   662	    });
   663	  }
   664	
   665	  return filas;
   666	}
   667	
   668	/** [2026-10-03] Filas del lote entero, llenando de corrido (lo mismo que qrLoteFilas imprime). */
   669	function filasDeLoteQrTotal(items, mode, opciones) {
   670	  const porEtiqueta = opciones && opciones.porEtiqueta === 2 ? 2 : 1;
   671	  const bandas = mode && mode.duplicate && mode.halfWidth ? 2 : 1;
   672	  const unidades = (Array.isArray(items) ? items : []).reduce((s, it) => s + Math.max(1, (it && it.qty) || 1), 0);
   673	
   674	  return Math.ceil(unidades / (bandas * porEtiqueta));
   675	}
   676	
   677	/** [v1.0.29] Cuántas filas (pasadas de la impresora) salen para `qty` unidades. */
   678	function filasDeLoteQr(qty, mode, opciones) {
   679	  const porEtiqueta = opciones && opciones.porEtiqueta === 2 ? 2 : 1;
   680	  const bandas = mode && mode.duplicate && mode.halfWidth ? 2 : 1;
  ✓ sin elegir nada: vertical (como siempre)
  ✓ horizontal: orientación N y el diseño horizontal
  ✓ un modo no orientable ignora la orientación guardada
  ✓ el diseño guardado de vertical (guardados viejos) no se mezcla con horizontal
  ✓ el diseño horizontal guardado se aplica en horizontal
  ✓ densidad/velocidad (extra) siguen entrando
  ✓ elegir horizontal no borra el diseño vertical
  ✓ guardar en horizontal escribe layoutN, deja layout
  ✓ restablecer en horizontal borra sólo el horizontal
  ✓ volver a vertical
  ✓ orientación en un modo no orientable: no cambia nada
  ✓ vertical: todo girado
  ✓ horizontal: todo derecho
  ✓ horizontal: el nombre se parte en hasta 3 renglones dentro de 200 (^FB180,3)
  ✓ vertical: el nombre sigue en un renglón (sin ^FB)
  ✓ [Vista Zebra] vertical: el código ya no pisa el nivel de precio (x 80)
  ✓ horizontal: el código se achica para entrar (^BY1)
  ✓ otros modos no cambian (sin ^FB)

18 ok
formatTestLabel — prueba según el modo

  ✓ doble banda: ^PW800 (las dos etiquetas)
  ✓ doble banda: la prueba sale dos veces
  ✓ doble banda: la derecha empieza en la mitad (x = 400 + 10)
  ✓ doble banda: el código de barras derecho también corrido
  ✓ doble banda: cada mitad dice cuál es
  ✓ doble banda: un solo ^XA/^XZ (una etiqueta física)
  ✓ doble banda: el código entra en su mitad (^BY2 → 300 ≤ 400)
  ✓ doble banda: ^LL del modo
  ✓ doble banda: alto personalizado
  ✓ ancho personalizado: ^PW832 y la derecha en x = 426
  ✓ simple-face: el ZPL de antes con ^BY2
  ✓ simple-face: el código entra en 400 dots (^BY2)
  ✓ doble-face: el ZPL de antes con ^BY2
  ✓ doble-face: el código entra en 400 dots (^BY2)
  ✓ poliamida vertical: ^PW200 ^LL400, texto y código girados
  ✓ poliamida vertical: el código (^BY2) entra a lo largo de los 400
  ✓ poliamida horizontal: derecho, en 200 de ancho
  ✓ poliamida horizontal: código corto entero y legible (^BY2)
  ✓ poliamida horizontal: el título se parte en el ancho (^FB) — antes salía «…TES»
  ✓ una cara ancha: el código sigue ajustado a 400
  ✓ sin modo: como una cara
  ✓ densidad/velocidad: ~SD y ^PR presentes
  ✓ densidad/velocidad en doble banda

23 ok

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
/bin/zsh -lc "rg -n \"function drawZplText\" zebra-agent/renderer/index.html; sed -n '1325,1395p' zebra-agent/renderer/index.html; nl -ba zebra-agent/renderer/index.html | sed -n '1268,1290p;1370,1415p'; nl -ba zebra-agent/main.js | sed -n '545,580p'" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
1337:  function drawZplText(ctx, slot, text, scale, offsetX, rotated, bold) {
      // 수동 — 슬롯 위치 = 금액, nivel 라벨은 위(가로)/옆(세로)
      for (const b of blocks) {
        const slot = b.slot;
        if (b.labelText) {
          if (rotated) drawZplText(ctx, { x: slot.x + b.aFs + 2, y: slot.y, fontSize: b.lFs }, b.labelText, scale, offsetX, rotated, false);
          else drawZplText(ctx, { x: slot.x, y: Math.max(0, slot.y - b.lFs - 2), fontSize: b.lFs }, b.labelText, scale, offsetX, rotated, false);
        }
        drawZplText(ctx, slot, b.amountText, scale, offsetX, rotated, b.bold);
      }
    }
  }

  function drawZplText(ctx, slot, text, scale, offsetX, rotated, bold) {
    if (!slot) return;
    const px = Math.max(4, (slot.fontSize || 20) * scale);
    ctx.save();
    ctx.font = `${bold ? '700' : '400'} ${px}px Arial, sans-serif`;
    ctx.textBaseline = 'top';
    ctx.fillStyle = '#111';
    ctx.translate((slot.x + offsetX) * scale, slot.y * scale);
    if (rotated) ctx.rotate(Math.PI / 2);
    ctx.fillText(text, 0, 0);
    ctx.restore();
  }

  // SKU 길이는 사용자마다 다름 — 현재 설정으로 이 SKU 가 라벨에 들어가는지 알려준다.
  // 출력을 막지는 않고, 어떤 값을 조절하면 되는지만 안내.
  const MIN_SCANNABLE_MODULE_WIDTH = 2;

  function showBarcodeFitWarning(value, modules, mw, avail) {
    const el = $('#bc-fit-warning');
    if (!el) return;

    const totalW = modules * mw;
    const mm = (dots) => Math.round((dots / DOTS_PER_MM) * 10) / 10;

    if (totalW > avail) {
      el.style.color = '#c62828';
      el.textContent = `⚠ SKU "${value}" no entra: ${mm(totalW)}mm sobre ${mm(avail)}mm disponibles.`
        + ' Ampliá la etiqueta, bajá X del código, o acortá el SKU.';
    } else if (mw < MIN_SCANNABLE_MODULE_WIDTH) {
      el.style.color = '#ef6c00';
      el.textContent = `⚠ SKU "${value}" entra pero muy fino (módulo ${mw} dot = ${mm(mw)}mm).`
        + ' Debajo de 2 dots el escáner suele fallar: ampliá la etiqueta o acortá el SKU.';
    } else {
      el.style.color = '#2e7d32';
      el.textContent = `✓ Código: módulo ${mw} dot · ${mm(totalW)}mm de ${mm(avail)}mm disponibles.`;
    }
  }

  function drawBarcode(ctx, bc, scale, offsetX, rotated, region) {
    if (!bc) return;
    const value = sampleSku();

    // CODE128 모듈 수 추정 + auto-fit 양방향 (formatter effectiveModuleWidth 와 동일)
    // moduleWidth = 사용자 상한. autoFit 이면 상한까지 확대 / 안 들어가면 축소.
    const MAX_MODULE_WIDTH = 10;
    const modules = (value.length + 2) * 11 + 13;
    const avail = rotated
      ? region.height - (bc.y || 0) - 10
      : region.width - (bc.x || 0) - 10;
    let mw = Math.max(1, Math.min(MAX_MODULE_WIDTH, bc.moduleWidth || 3));
    if (bc.autoFit !== false && modules > 0) {
      mw = Math.max(1, Math.min(mw, Math.floor(avail / modules)));
    }
    showBarcodeFitWarning(value, modules, mw, avail);

    const h = (bc.height || 45) * scale;
    const totalW = modules * mw * scale;

    ctx.save();
  1268	      ctx.beginPath();
  1269	      ctx.moveTo(mode.halfWidth * scale, 0);
  1270	      ctx.lineTo(mode.halfWidth * scale, canvas.height);
  1271	      ctx.stroke();
  1272	      ctx.setLineDash([]);
  1273	      drawCopy(ctx, mode, scale, mode.halfWidth);
  1274	    }
  1275	  }
  1276	
  1277	  function drawCopy(ctx, mode, scale, offsetX) {
  1278	    const layout = mode.layout;
  1279	    const rotated = mode.orientation === 'R';
  1280	    const region = {
  1281	      width: mode.duplicate && mode.halfWidth ? mode.halfWidth : mode.width,
  1282	      height: mode.height,
  1283	    };
  1284	    ctx.fillStyle = '#111';
  1285	
  1286	    // 상품 설명
  1287	    drawZplText(ctx, layout.name, SAMPLE_NAME, scale, offsetX, rotated, false);
  1288	
  1289	    // 바코드 (의사 막대 패턴 + SKU, auto-fit 반영)
  1290	    drawBarcode(ctx, layout.barcode, scale, offsetX, rotated, region);
  1370	      el.style.color = '#2e7d32';
  1371	      el.textContent = `✓ Código: módulo ${mw} dot · ${mm(totalW)}mm de ${mm(avail)}mm disponibles.`;
  1372	    }
  1373	  }
  1374	
  1375	  function drawBarcode(ctx, bc, scale, offsetX, rotated, region) {
  1376	    if (!bc) return;
  1377	    const value = sampleSku();
  1378	
  1379	    // CODE128 모듈 수 추정 + auto-fit 양방향 (formatter effectiveModuleWidth 와 동일)
  1380	    // moduleWidth = 사용자 상한. autoFit 이면 상한까지 확대 / 안 들어가면 축소.
  1381	    const MAX_MODULE_WIDTH = 10;
  1382	    const modules = (value.length + 2) * 11 + 13;
  1383	    const avail = rotated
  1384	      ? region.height - (bc.y || 0) - 10
  1385	      : region.width - (bc.x || 0) - 10;
  1386	    let mw = Math.max(1, Math.min(MAX_MODULE_WIDTH, bc.moduleWidth || 3));
  1387	    if (bc.autoFit !== false && modules > 0) {
  1388	      mw = Math.max(1, Math.min(mw, Math.floor(avail / modules)));
  1389	    }
  1390	    showBarcodeFitWarning(value, modules, mw, avail);
  1391	
  1392	    const h = (bc.height || 45) * scale;
  1393	    const totalW = modules * mw * scale;
  1394	
  1395	    ctx.save();
  1396	    ctx.translate((bc.x + offsetX) * scale, bc.y * scale);
  1397	    if (rotated) ctx.rotate(Math.PI / 2);
  1398	
  1399	    // 의사 난수 막대 패턴 (SKU 기반 결정적) — 실제 예상 폭만큼 그림
  1400	    let pos = 0;
  1401	    let i = 0;
  1402	    while (pos < totalW) {
  1403	      const w = ((value.charCodeAt(i % value.length) + i * 7) % 3) + 1;
  1404	      if (i % 2 === 0) {
  1405	        ctx.fillStyle = '#111';
  1406	        ctx.fillRect(pos, 0, Math.min(w * mw * scale, totalW - pos), h);
  1407	      }
  1408	      pos += w * mw * scale;
  1409	      i += 1;
  1410	    }
  1411	
  1412	    // human-readable SKU
  1413	    const fsPx = Math.max(4, 14 * scale);
  1414	    ctx.font = `400 ${fsPx}px monospace`;
  1415	    ctx.fillStyle = '#111';
   545	    return res || { ok: false, error: 'Sin respuesta' };
   546	  } catch (err) {
   547	    return { ok: false, error: err.message || 'Timeout' };
   548	  }
   549	});
   550	
   551	// Zebra Agent에서 직접 출력 (WebSocket 우회, 로컬 직접 출력)
   552	ipcMain.handle('print:labels', async (_event, items, opciones) => {
   553	  const printerCfg = store.get('printer');
   554	  if (!isPrinterConfigured(printerCfg)) return { ok: false, error: 'Impresora no configurada' };
   555	
   556	  const mode = getPrintMode();
   557	
   558	  // ★ [2026-09-25] Símbolo elegido en la pantalla. Ausente = barras, o sea el
   559	  //   comportamiento de siempre: esta opción no puede cambiar lo que ya salía.
   560	  const esQr = !!(opciones && opciones.simbolo === 'qr');
   561	  const porEtiqueta = opciones && opciones.porEtiqueta === 2 ? 2 : 1;
   562	
   563	  // [v1.0.29] «Imprimir 1 de prueba» — una sola fila del primer producto, para ver
   564	  //   dónde caen QR y texto antes de gastar el rollo. (Con barras: una etiqueta.)
   565	  if (opciones && opciones.prueba && Array.isArray(items) && items.length > 0) {
   566	    const porFila = esQr ? (mode.duplicate && mode.halfWidth ? 2 : 1) * porEtiqueta : 1;
   567	    items = [{ ...items[0], qty: porFila }];
   568	  }
   569	
   570	  try {
   571	    const zpl = formatBatchLabels(prepareItems(items), mode, {
   572	      simbolo: esQr ? 'qr' : 'barras',
   573	      porEtiqueta,
   574	
   575	      // [2026-10-02] qué texto lleva la etiqueta QR y dónde — lo guardado en la pestaña QR
   576	      texto: store.get('qrLayout') || {},
   577	    });
   578	    const result = await sendZpl(zpl, printerCfg);
   579	
   580	    // ★★ Lo que se informa son **etiquetas**, no unidades. Con 2 por etiqueta las

hook: PostToolUse
hook: PostToolUse
hook: PostToolUse Failed
hook: PostToolUse Completed
codex
[HIGH] `zebra-agent/src/zpl-formatter.js:591` — Poliamida의 QR 출력은 선택한 방향을 완전히 무시함

  문제: `qrLoteBase()`는 `mode.width`, `mode.height`, `duplicate`만 사용하고 `mode.orientation`을 전달하지 않는다. 따라서 Poliamida가 세로(`R`)여도 QR 실제 출력과 “Vista Zebra”는 항상 회전되지 않은 동일한 레이아웃으로 생성된다. “실제 라벨도 세로/가로 선택 가능” 요구가 바코드 출력에서만 충족된다.

  근거:

  ```js
  const anchoDots = mode && mode.width
    ? (bandas === 2 ? mode.halfWidth : mode.width)
    : 400;

  const layout = {
    widthMm: anchoDots / 8,
    heightMm: mode && mode.height ? mode.height / 8 : 25,
    ...
  };
  ```

  이후 `formatQrLabelConAvisos()`에 이 `layout`만 전달한다. `orientation`은 읽지도 전달하지도 않는다. `Vista Zebra`의 lote 경로 역시 같은 `formatBatchLabels()` → `qrLoteFilas()` 경로를 사용하므로 같은 결함을 재현한다.

  수정: QR formatter가 유효 모드의 `orientation`을 받아 `R`일 때 QR·텍스트 좌표와 회전을 적용하도록 하거나, Poliamida 전용으로 회전된 QR 레이아웃을 구성해야 한다. 세로/가로 QR 실제 ZPL과 Vista Zebra가 같은지 회귀 테스트도 필요하다.

[MEDIUM] `zebra-agent/renderer/index.html:1286` — 가로 Poliamida의 일반 미리보기가 `^FB` 3줄 디자인을 표시하지 못함

  문제: 실제 ZPL은 `name.lines: 3`을 `^FB180,3`으로 출력하지만, canvas `drawPreview()`는 이름을 항상 한 줄로 그린다. 따라서 새 가로 디자인의 핵심인 3줄 상품명이 일반 “Vista previa”에서 잘리거나 라벨 밖으로 나가며, 실제 출력과 다르게 보인다.

  근거:

  ```js
  drawZplText(ctx, layout.name, SAMPLE_NAME, scale, offsetX, rotated, false);
  ```

  ```js
  function drawZplText(...) {
    ...
    ctx.fillText(text, 0, 0);
  }
  ```

  `slot.lines`, 가용 폭, 줄바꿈 처리가 없다. 반면 실제 출력은 `renderCopy()`에서 다음을 생성한다.

  ```js
  ^FB${ancho},${renglones},0,L,0
  ```

  수정: 이름 미리보기에서 `layout.name.lines`와 `region.width - x - 10`을 기준으로 텍스트를 최대 3줄로 나누거나, 정확한 출력 확인은 Vista Zebra만 담당한다는 UI 구분을 명확히 해야 한다.

[MEDIUM] `zebra-agent/src/zpl-formatter.js:1160` — `testAngosta`가 Poliamida가 아닌 모든 폭 400 미만 커스텀 모드에도 적용됨

  문제: 새 테스트 라벨은 Poliamida용으로 추가됐지만 판별 조건이 모드 종류가 아니라 `width < 400`뿐이다. 사용자가 `simple-face`나 다른 비중복 모드의 폭을 399 이하로 저장하면 기존 테스트 대신 Poliamida 전용 문구·좌표의 `testAngosta()`가 출력된다.

  근거:

  ```js
  const angosta = !doble && mode && mode.width && mode.width < 400;
  if (angosta) return testAngosta(mode, { darkness, speed });
  ```

  수정: `mode.key === 'poliamida-vertical'` 또는 명시적인 모드 capability를 기준으로 분기해야 한다.

그 외 확인 결과:

- 구형 `custom.layout`은 세로 디자인으로 유지되고 `layoutN`과 섞이지 않는다.
- 모드 변경과 `Restablecer`의 현재 방향별 `layout/layoutN` 선택은 정상이다.
- `buildModeFromForm()`은 유효 방향을 유지한다.
- 가로 실제 ZPL의 상품명에는 `^FB(...),3`이 정상 적용된다.
- 세로 기본 바코드 X 좌표는 80으로 변경됐다. 단, 사용자가 예전에 직접 저장한 barcode X 값은 커스텀 값이 우선하는 것이 기존 저장 호환 동작이다.
- 방향 관련 테스트 18개와 테스트 라벨 테스트 23개는 통과했다. 위 결함들은 현재 테스트 범위에 포함되지 않는다.
hook: Stop
hook: Stop
hook: Stop Failed
hook: Stop Completed
tokens used
54,636
[HIGH] `zebra-agent/src/zpl-formatter.js:591` — Poliamida의 QR 출력은 선택한 방향을 완전히 무시함

  문제: `qrLoteBase()`는 `mode.width`, `mode.height`, `duplicate`만 사용하고 `mode.orientation`을 전달하지 않는다. 따라서 Poliamida가 세로(`R`)여도 QR 실제 출력과 “Vista Zebra”는 항상 회전되지 않은 동일한 레이아웃으로 생성된다. “실제 라벨도 세로/가로 선택 가능” 요구가 바코드 출력에서만 충족된다.

  근거:

  ```js
  const anchoDots = mode && mode.width
    ? (bandas === 2 ? mode.halfWidth : mode.width)
    : 400;

  const layout = {
    widthMm: anchoDots / 8,
    heightMm: mode && mode.height ? mode.height / 8 : 25,
    ...
  };
  ```

  이후 `formatQrLabelConAvisos()`에 이 `layout`만 전달한다. `orientation`은 읽지도 전달하지도 않는다. `Vista Zebra`의 lote 경로 역시 같은 `formatBatchLabels()` → `qrLoteFilas()` 경로를 사용하므로 같은 결함을 재현한다.

  수정: QR formatter가 유효 모드의 `orientation`을 받아 `R`일 때 QR·텍스트 좌표와 회전을 적용하도록 하거나, Poliamida 전용으로 회전된 QR 레이아웃을 구성해야 한다. 세로/가로 QR 실제 ZPL과 Vista Zebra가 같은지 회귀 테스트도 필요하다.

[MEDIUM] `zebra-agent/renderer/index.html:1286` — 가로 Poliamida의 일반 미리보기가 `^FB` 3줄 디자인을 표시하지 못함

  문제: 실제 ZPL은 `name.lines: 3`을 `^FB180,3`으로 출력하지만, canvas `drawPreview()`는 이름을 항상 한 줄로 그린다. 따라서 새 가로 디자인의 핵심인 3줄 상품명이 일반 “Vista previa”에서 잘리거나 라벨 밖으로 나가며, 실제 출력과 다르게 보인다.

  근거:

  ```js
  drawZplText(ctx, layout.name, SAMPLE_NAME, scale, offsetX, rotated, false);
  ```

  ```js
  function drawZplText(...) {
    ...
    ctx.fillText(text, 0, 0);
  }
  ```

  `slot.lines`, 가용 폭, 줄바꿈 처리가 없다. 반면 실제 출력은 `renderCopy()`에서 다음을 생성한다.

  ```js
  ^FB${ancho},${renglones},0,L,0
  ```

  수정: 이름 미리보기에서 `layout.name.lines`와 `region.width - x - 10`을 기준으로 텍스트를 최대 3줄로 나누거나, 정확한 출력 확인은 Vista Zebra만 담당한다는 UI 구분을 명확히 해야 한다.

[MEDIUM] `zebra-agent/src/zpl-formatter.js:1160` — `testAngosta`가 Poliamida가 아닌 모든 폭 400 미만 커스텀 모드에도 적용됨

  문제: 새 테스트 라벨은 Poliamida용으로 추가됐지만 판별 조건이 모드 종류가 아니라 `width < 400`뿐이다. 사용자가 `simple-face`나 다른 비중복 모드의 폭을 399 이하로 저장하면 기존 테스트 대신 Poliamida 전용 문구·좌표의 `testAngosta()`가 출력된다.

  근거:

  ```js
  const angosta = !doble && mode && mode.width && mode.width < 400;
  if (angosta) return testAngosta(mode, { darkness, speed });
  ```

  수정: `mode.key === 'poliamida-vertical'` 또는 명시적인 모드 capability를 기준으로 분기해야 한다.

그 외 확인 결과:

- 구형 `custom.layout`은 세로 디자인으로 유지되고 `layoutN`과 섞이지 않는다.
- 모드 변경과 `Restablecer`의 현재 방향별 `layout/layoutN` 선택은 정상이다.
- `buildModeFromForm()`은 유효 방향을 유지한다.
- 가로 실제 ZPL의 상품명에는 `^FB(...),3`이 정상 적용된다.
- 세로 기본 바코드 X 좌표는 80으로 변경됐다. 단, 사용자가 예전에 직접 저장한 barcode X 값은 커스텀 값이 우선하는 것이 기존 저장 호환 동작이다.
- 방향 관련 테스트 18개와 테스트 라벨 테스트 23개는 통과했다. 위 결함들은 현재 테스트 범위에 포함되지 않는다.
