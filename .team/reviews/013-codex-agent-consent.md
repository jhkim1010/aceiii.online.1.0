Reading additional input from stdin...
OpenAI Codex v0.146.0
--------
workdir: /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
model: gpt-5.6-sol
provider: openai
approval: never
sandbox: workspace-write [workdir, /tmp, $TMPDIR]
reasoning effort: none
reasoning summaries: none
session id: 01a11249-322e-7070-b7c0-4018419bfbcb
--------
user
Revisá este cambio (Electron print/zebra agent, electron-updater). Requisito del usuario: el agente NUNCA se actualiza solo; sólo cuando la persona acepta (pregunta al terminar la descarga, botón en la ventana o la bandeja). Descargar en segundo plano está bien. Nunca reiniciar con impresión en curso. Buscá bugs concretos (archivo:línea, escenario, arreglo). Español, breve.
diff --git a/print-agent/main.js b/print-agent/main.js
index d26ff60..f1fb35d 100644
--- a/print-agent/main.js
+++ b/print-agent/main.js
@@ -283,12 +283,9 @@ function updateTrayMenu() {
   tray.setContextMenu(contextMenu);
 }
 
-// 「Salir」: 업데이트가 받아져 있으면 설치하고 끝낸다. 어느 쪽이든 인쇄가 끝난 뒤에.
-// ★ 종전 app.exit(0) 는 'quit' 이벤트를 내지 않아 autoInstallOnAppQuit 가 한 번도 안 돌았다.
+// 「Salir」: 인쇄가 끝난 뒤에 끝낸다. 업데이트는 설치하지 않는다(사용자가 OK 할 때만).
 function salir() {
-  if (updaterRef && updaterRef.instalarAlSalir()) return;
-
-  // ★ sin actualización igual se espera a que termine la impresión en curso (y su ACK) —
+  // ★ se espera a que termine la impresión en curso (y su ACK) —
   //   cortar a mitad de un trabajo lo pierde o, si el servidor lo reenvía, sale dos veces.
   actividadImpresion.esperarQuieto({ plazoMs: 30 * 1000 }).finally(() => app.exit(0));
 }
diff --git a/print-agent/renderer/update-banner.js b/print-agent/renderer/update-banner.js
index a40ca6e..7ae67ea 100644
--- a/print-agent/renderer/update-banner.js
+++ b/print-agent/renderer/update-banner.js
@@ -3,7 +3,7 @@
 //
 // Muestra la versión instalada y el estado de la actualización:
 //   al día · buscando · descargando N% · lista (botón «Actualizar ahora») · error (reintentar)
-// La instalación sola ocurre de madrugada sin impresiones en curso (src/update-policy.js).
+// Nunca se instala solo: sólo con «Actualizar ahora» (o «sí» en la pregunta al descargar).
 (function updateBanner() {
   const api = window.electronAPI;
   if (!api || typeof api.getUpdateEstado !== 'function') return;
@@ -49,7 +49,7 @@
       txt.textContent = `v${e.actual} · actualización automática sólo en la versión instalada de Windows`;
       btn.style.display = 'none';
     } else if (e.fase === 'listo') {
-      txt.textContent = `Nueva versión v${e.nueva} lista (tenés v${e.actual}) · se instala sola de madrugada si no hay impresiones`;
+      txt.textContent = `Nueva versión v${e.nueva} lista (tenés v${e.actual}) · se instala sólo si tocás «Actualizar ahora»`;
       btn.textContent = 'Actualizar ahora';
       btn.onclick = async () => {
         btn.disabled = true;
diff --git a/print-agent/src/update-policy.js b/print-agent/src/update-policy.js
index adb8285..6c0eef4 100644
--- a/print-agent/src/update-policy.js
+++ b/print-agent/src/update-policy.js
@@ -2,40 +2,15 @@
 // (mismo archivo en print-agent y zebra-agent)
 //
 // ★ Por qué existe (실측 2026-10-06): la descarga ya andaba, pero la instalación sólo
-//   ocurría «al salir del agente». Las tiendas lo dejan prendido todo el día y el «Salir»
-//   de la bandeja usaba app.exit(), que **no** dispara 'quit' → autoInstallOnAppQuit nunca
-//   corría. Resultado: print 1.2.5/1.2.6 en la calle con 1.2.10 publicado, zebra 1.0.28/1.0.30
-//   con 1.0.32.
+//   ocurría «al salir del agente» y el «Salir» usaba app.exit() (no dispara 'quit') → nunca.
+//   En la calle: print 1.2.5/1.2.6 con 1.2.10 publicado, zebra 1.0.28/1.0.30 con 1.0.32.
+// ★ [2026-10-06 usuario] nunca se actualiza solo: sólo cuando la persona dice que sí.
 //
 // ★ Regla dura: nunca reiniciar con una impresión en curso (un reinicio a mitad de un
 //   trabajo puede perderlo o, si el servidor lo reenvía, imprimirlo dos veces).
 
-// Ventana de instalación automática, en hora LOCAL de la PC de la tienda: [desde, hasta)
-const VENTANA_DESDE = 3;
-const VENTANA_HASTA = 6;
-
-// Sin imprimir nada durante este tiempo = el agente está quieto
-const QUIETO_MS = 10 * 60 * 1000;
-
-/**
- * Instalación automática (sin que nadie toque nada).
- * @returns {{ ok: boolean, motivo?: string }}
- */
-function puedeInstalarSolo({ listo, ahora, enCurso, ultimaActividad }) {
-  if (!listo) return { ok: false, motivo: 'sin-descarga' };
-
-  const hora = new Date(ahora).getHours();
-  if (hora < VENTANA_DESDE || hora >= VENTANA_HASTA) return { ok: false, motivo: 'fuera-de-horario' };
-
-  if (enCurso > 0) return { ok: false, motivo: 'imprimiendo' };
-
-  if (ahora - (ultimaActividad || 0) < QUIETO_MS) return { ok: false, motivo: 'actividad-reciente' };
-
-  return { ok: true };
-}
-
 /**
- * Botón «Actualizar ahora»: lo pide una persona, así que no importa la hora.
+ * «Actualizar ahora» (ventana, bandeja o la pregunta al terminar la descarga).
  * Las impresiones en curso no se miran acá: el reinicio pasa siempre por
  * `esperarQuieto()` (abajo), que espera a que terminen.
  */
@@ -123,11 +98,7 @@ function crearActividad(reloj = () => Date.now()) {
 }
 
 module.exports = {
-  puedeInstalarSolo,
   puedeInstalarAMano,
   crearActividad,
-  VENTANA_DESDE,
-  VENTANA_HASTA,
-  QUIETO_MS,
   ACK_MS,
 };
diff --git a/print-agent/src/updater.js b/print-agent/src/updater.js
index 830b5e9..ffc2e48 100644
--- a/print-agent/src/updater.js
+++ b/print-agent/src/updater.js
@@ -4,19 +4,17 @@
 // 동작 원리:
 //   1) 부팅 10초 후 + 이후 4시간마다 publish URL(고정 롤링 릴리즈)의 latest.yml 확인
 //   2) 새 버전 발견 → 백그라운드 다운로드 (SHA512 검증 포함)
-//   3) 설치 — 세 경로:
-//      · 새벽 03–06시(PC 현지 시각) + 인쇄 0건 + 10분간 인쇄 없음 → 조용히 재시작·설치
-//      · 창의 「Actualizar ahora」 / 트레이 메뉴 → 인쇄 중이 아니면 즉시
-//      · 트레이 「Salir」 → 다운로드돼 있으면 설치하고 종료
-//   ★ 종전엔 3)이 「앱 종료 시」 하나뿐이었는데 「Salir」가 app.exit() 라 quit 이벤트가
-//     안 나서 **한 번도 설치되지 않았다**(update-policy.js 머리 주석 실측 참고).
+//   3) 설치는 **사용자가 OK 할 때만** — 다운로드가 끝나면 묻는 창을 띄운다
+//      (「Actualizar ahora」 / 「Más tarde」). 창의 띠·트레이 메뉴에서도 언제든 누를 수 있다.
+//   ★ [2026-10-06 사용자] 「혼자 막 업데이트 되는 것은 원치 않아. 물어보고 사용자가 ok 할
+//     때만」 → 새벽 자동 설치·종료 시 설치(autoInstallOnAppQuit)·「Salir」 설치를 모두 뺐다.
 //
 // 스킵 조건:
 //   - dev 모드 / 미패키징 (app.isPackaged === false)
 //   - macOS/Linux (코드서명 없어 자동 업데이트 불가 — 매장 PC 는 Windows)
 //   스킵돼도 컨트롤러는 돌려준다(화면이 「Windows 설치본에서만」 을 표시한다).
-const { app } = require('electron');
-const { puedeInstalarSolo, puedeInstalarAMano } = require('./update-policy');
+const { app, dialog } = require('electron');
+const { puedeInstalarAMano } = require('./update-policy');
 
 // 4시간마다 재확인 — 매장 영업 중 하루 2~3회 체크 수준
 const CHECK_INTERVAL_MS = 4 * 60 * 60 * 1000;
@@ -24,9 +22,6 @@ const CHECK_INTERVAL_MS = 4 * 60 * 60 * 1000;
 // 부팅 직후는 WebSocket 연결 등과 겹치지 않도록 10초 지연
 const FIRST_CHECK_DELAY_MS = 10 * 1000;
 
-// 새벽 자동 설치 조건을 보는 주기
-const INSTALL_TICK_MS = 5 * 60 * 1000;
-
 const MOTIVO_TEXTO = {
   'sin-descarga': 'Todavía no hay una actualización descargada',
 };
@@ -38,7 +33,7 @@ const MOTIVO_TEXTO = {
  * @param {object}   opts.actividad  update-policy.crearActividad() 의 결과 (인쇄 진행 추적)
  * @param {Function} opts.onLog      로그 콜백 (broadcastLog)
  * @param {Function} opts.onEstado   상태 변경 콜백 (estado) — 트레이·창 갱신용
- * @returns {object} 컨트롤러 { estado, buscar, instalarAhora, instalarAlSalir }
+ * @returns {object} 컨트롤러 { estado, buscar, instalarAhora }
  */
 function initAutoUpdater({ feed, actividad, onLog, onEstado } = {}) {
   const log = typeof onLog === 'function' ? onLog : () => {};
@@ -52,7 +47,6 @@ function initAutoUpdater({ feed, actividad, onLog, onEstado } = {}) {
     progreso: null,
     error: null,
     ultimaBusqueda: null,
-    instalacionAuto: 'Automática entre las 3 y las 6 h, sin impresiones en curso',
   };
 
   const cambiar = (parcial) => {
@@ -64,7 +58,6 @@ function initAutoUpdater({ feed, actividad, onLog, onEstado } = {}) {
     estado: () => ({ ...st }),
     buscar: async () => ({ ...st }),
     instalarAhora: () => ({ ok: false, motivo: 'Sólo disponible en la versión instalada de Windows' }),
-    instalarAlSalir: () => false,
   };
 
   // dev/미패키징 또는 비 Windows → 스킵
@@ -88,8 +81,8 @@ function initAutoUpdater({ feed, actividad, onLog, onEstado } = {}) {
 
   autoUpdater.autoDownload = true;
 
-  // 안전망으로 남긴다 — 정상 quit 경로(설치 프로그램·OS 재시작 등)에서는 여전히 설치된다
-  autoUpdater.autoInstallOnAppQuit = true;
+  // ★ 종료할 때 몰래 설치하지 않는다 — 설치는 사용자가 OK 할 때만
+  autoUpdater.autoInstallOnAppQuit = false;
   autoUpdater.allowDowngrade = false;
 
   autoUpdater.on('checking-for-update', () => {
@@ -111,8 +104,9 @@ function initAutoUpdater({ feed, actividad, onLog, onEstado } = {}) {
   });
 
   autoUpdater.on('update-downloaded', (info) => {
-    log(`🔄 Actualización v${info.version} lista — se instalará sola de madrugada o con «Actualizar ahora»`);
+    log(`🔄 Actualización v${info.version} lista — se instala sólo si la aceptás («Actualizar ahora»)`);
     cambiar({ fase: 'listo', nueva: info.version, progreso: 100 });
+    preguntar(info.version);
   });
 
   autoUpdater.on('error', (err) => {
@@ -144,7 +138,7 @@ function initAutoUpdater({ feed, actividad, onLog, onEstado } = {}) {
     const quieto = actividad ? await actividad.esperarQuieto() : true;
     if (!quieto) {
       instalando = false;
-      log('⚠️ No se reinició: siguió llegando trabajo de impresión. Se reintentará.');
+      log('⚠️ No se reinició: siguió llegando trabajo de impresión. Probá de nuevo con «Actualizar ahora».');
 
       return false;
     }
@@ -170,36 +164,40 @@ function initAutoUpdater({ feed, actividad, onLog, onEstado } = {}) {
     return { ok: true };
   };
 
-  // 트레이 「Salir」: 다운로드돼 있으면 설치하고 끝낸다(다시 띄우지 않음)
-  const instalarAlSalir = () => {
-    if (st.fase !== 'listo') return false;
-    instalar(false).then((ok) => {
-      if (!ok) app.exit(0);
-    });
-
-    return true;
-  };
-
-  const vigilar = () => {
-    const r = puedeInstalarSolo({
-      listo: st.fase === 'listo',
-      ahora: Date.now(),
-      enCurso: actividad?.estado.enCurso || 0,
-      ultimaActividad: actividad?.estado.ultimaActividad || 0,
-    });
-    if (r.ok && !instalando) {
-      log('🌙 Instalación automática de madrugada (sin impresiones en curso)');
-      instalar(true);
+  // 다운로드가 끝나면 한 번 묻는다(버전마다 1회). 「Más tarde」면 띠·트레이에 남는다.
+  let preguntada = null;
+  const preguntar = (version) => {
+    if (preguntada === version) {
+      return;
     }
+    preguntada = version;
+    dialog
+      .showMessageBox({
+        type: 'question',
+        title: 'Actualización disponible',
+        message: `Hay una versión nueva del agente: v${version} (tenés v${st.actual}).`,
+        detail: 'El agente se reinicia unos segundos. Si hay una impresión en curso, espera a que termine.',
+        buttons: ['Actualizar ahora', 'Más tarde'],
+        defaultId: 0,
+        cancelId: 1,
+        noLink: true,
+      })
+      .then(({ response }) => {
+        if (response === 0) {
+          instalarAhora();
+        } else {
+          log('⏸ Actualización pospuesta — podés instalarla con «Actualizar ahora»');
+        }
+      })
+      .catch(() => {});
   };
 
   setTimeout(buscar, FIRST_CHECK_DELAY_MS);
   setInterval(buscar, CHECK_INTERVAL_MS);
-  setInterval(vigilar, INSTALL_TICK_MS);
 
   console.log('[updater] initialized — feed:', feed);
 
-  return { estado: () => ({ ...st }), buscar, instalarAhora, instalarAlSalir };
+  return { estado: () => ({ ...st }), buscar, instalarAhora };
 }
 
 module.exports = { initAutoUpdater };
diff --git a/print-agent/test/update-policy.smoke.js b/print-agent/test/update-policy.smoke.js
index 47a5343..4f367c3 100644
--- a/print-agent/test/update-policy.smoke.js
+++ b/print-agent/test/update-policy.smoke.js
@@ -10,7 +10,7 @@ const assert = require('assert');
 const fs = require('fs');
 const path = require('path');
 const {
-  puedeInstalarSolo, puedeInstalarAMano, crearActividad, QUIETO_MS, ACK_MS,
+  puedeInstalarAMano, crearActividad, ACK_MS,
 } = require('../src/update-policy');
 
 let pasaron = 0;
@@ -21,49 +21,9 @@ const it = async (nombre, fn) => {
 };
 
 // hora LOCAL de la PC
-const aLas = (h, m = 0) => new Date(2026, 9, 7, h, m).getTime();
 
 (async () => {
-  await it('madrugada + quieto + descargada → instala sola', () => {
-    assert.deepStrictEqual(
-      puedeInstalarSolo({ listo: true, ahora: aLas(3, 30), enCurso: 0, ultimaActividad: aLas(1) }),
-      { ok: true },
-    );
-  });
-
-  await it('bordes de la ventana: 02:59 no · 03:00 sí · 05:59 sí · 06:00 no', () => {
-    const r = (h, m) => puedeInstalarSolo({ listo: true, ahora: aLas(h, m), enCurso: 0, ultimaActividad: 0 }).ok;
-    assert.deepStrictEqual([r(2, 59), r(3, 0), r(5, 59), r(6, 0)], [false, true, true, false]);
-  });
-
-  await it('de día no instala sola aunque esté quieta', () => {
-    assert.strictEqual(
-      puedeInstalarSolo({ listo: true, ahora: aLas(14), enCurso: 0, ultimaActividad: 0 }).motivo,
-      'fuera-de-horario',
-    );
-  });
-
-  await it('★ imprimiendo → de madrugada no arranca', () => {
-    assert.strictEqual(
-      puedeInstalarSolo({ listo: true, ahora: aLas(4), enCurso: 1, ultimaActividad: 0 }).motivo,
-      'imprimiendo',
-    );
-  });
-
-  await it('imprimió hace menos de 10 min → espera; justo 10 min → sí', () => {
-    const ahora = aLas(4);
-    assert.strictEqual(
-      puedeInstalarSolo({ listo: true, ahora, enCurso: 0, ultimaActividad: ahora - QUIETO_MS + 1 }).motivo,
-      'actividad-reciente',
-    );
-    assert.strictEqual(
-      puedeInstalarSolo({ listo: true, ahora, enCurso: 0, ultimaActividad: ahora - QUIETO_MS }).ok,
-      true,
-    );
-  });
-
-  await it('sin descarga → nada (ni sola ni a mano)', () => {
-    assert.strictEqual(puedeInstalarSolo({ listo: false, ahora: aLas(4), enCurso: 0, ultimaActividad: 0 }).ok, false);
+  await it('sin descarga → nada', () => {
     assert.strictEqual(puedeInstalarAMano({ listo: false }).ok, false);
   });
 
@@ -156,11 +116,24 @@ const aLas = (h, m = 0) => new Date(2026, 9, 7, h, m).getTime();
   const MAIN = sinComentarios(fs.readFileSync(path.join(raiz, 'main.js'), 'utf8'));
   const esZebra = fs.existsSync(path.join(raiz, 'src', 'zpl-formatter.js'));
 
-  await it('★ «Salir» pasa por salir() (instala si hay descarga), no por app.exit directo', () => {
+  await it('★ nunca se instala solo: ni al salir, ni de madrugada, ni al cerrar', () => {
+    const UPD = sinComentarios(fs.readFileSync(path.join(raiz, 'src', 'updater.js'), 'utf8'));
+    assert.ok(/autoInstallOnAppQuit\s*=\s*false/.test(UPD), 'autoInstallOnAppQuit debe ser false');
+    // quitAndInstall sólo dentro de instalar(), y instalar() sólo desde instalarAhora()
+    assert.strictEqual((UPD.match(/quitAndInstall\(/g) || []).length, 1);
+    assert.strictEqual((UPD.match(/\binstalar\(/g) || []).length, 1, 'instalar() llamado fuera de instalarAhora');
+    assert.ok(/const instalarAhora = \(\) => {[\s\S]{0,250}?instalar\(true\)/.test(UPD));
+    // instalarAhora sólo desde el botón (IPC), la bandeja o el «sí» de la pregunta
+    assert.strictEqual((UPD.match(/instalarAhora\(\)/g) || []).length, 1, 'instalarAhora sólo desde el «sí»');
+    assert.ok(/if \(response === 0\) \{\s*instalarAhora\(\);/.test(UPD));
+    assert.ok(!/setInterval\([^)]*instal/i.test(UPD), 'hay un temporizador que instala');
+  });
+
+  await it('★ «Salir» espera la impresión en curso y no instala', () => {
     assert.ok(/label:\s*'Salir',\s*click:\s*salir\b/.test(MAIN), 'el menú Salir no llama a salir()');
-    assert.ok(/function salir\(\)\s*\{\s*if \(updaterRef && updaterRef\.instalarAlSalir\(\)\) return;/.test(MAIN));
     assert.ok(/actividadImpresion\.esperarQuieto\(\{ plazoMs: 30 \* 1000 \}\)\.finally\(\(\) => app\.exit\(0\)\)/.test(MAIN),
-      'Salir sin actualización no espera la impresión en curso');
+      'Salir no espera la impresión en curso');
+    assert.ok(!/instalarAlSalir/.test(MAIN));
   });
 
   await it('★ toda llamada a la impresora pasa por el contador', () => {
diff --git a/zebra-agent/main.js b/zebra-agent/main.js
index 7eb9b49..52669af 100644
--- a/zebra-agent/main.js
+++ b/zebra-agent/main.js
@@ -279,12 +279,9 @@ function updateTrayMenu() {
   tray.setContextMenu(contextMenu);
 }
 
-// 「Salir」: 업데이트가 받아져 있으면 설치하고 끝낸다. 어느 쪽이든 인쇄가 끝난 뒤에.
-// ★ 종전 app.exit(0) 는 'quit' 이벤트를 내지 않아 autoInstallOnAppQuit 가 한 번도 안 돌았다.
+// 「Salir」: 인쇄가 끝난 뒤에 끝낸다. 업데이트는 설치하지 않는다(사용자가 OK 할 때만).
 function salir() {
-  if (updaterRef && updaterRef.instalarAlSalir()) return;
-
-  // ★ sin actualización igual se espera a que termine la impresión en curso (y su ACK) —
+  // ★ se espera a que termine la impresión en curso (y su ACK) —
   //   cortar a mitad de un trabajo lo pierde o, si el servidor lo reenvía, sale dos veces.
   actividadImpresion.esperarQuieto({ plazoMs: 30 * 1000 }).finally(() => app.exit(0));
 }
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
Voy a contrastar el diff con el flujo real de IPC, bandeja, cierre y contador de impresión en ambos agentes. No voy a modificar archivos; sólo reportaré fallas reproducibles con línea y arreglo.
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
exec
/bin/zsh -lc "sed -n '1,240p' .team/REVIEW-PROTOCOL.md && sed -n '1,240p' print-agent/src/updater.js && sed -n '1,180p' print-agent/src/update-policy.js" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
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
// src/updater.js — electron-updater 기반 자동 업데이트 (Windows 전용)
// (print-agent · zebra-agent 동일 파일 — feed 이름만 다르다)
//
// 동작 원리:
//   1) 부팅 10초 후 + 이후 4시간마다 publish URL(고정 롤링 릴리즈)의 latest.yml 확인
//   2) 새 버전 발견 → 백그라운드 다운로드 (SHA512 검증 포함)
//   3) 설치는 **사용자가 OK 할 때만** — 다운로드가 끝나면 묻는 창을 띄운다
//      (「Actualizar ahora」 / 「Más tarde」). 창의 띠·트레이 메뉴에서도 언제든 누를 수 있다.
//   ★ [2026-10-06 사용자] 「혼자 막 업데이트 되는 것은 원치 않아. 물어보고 사용자가 ok 할
//     때만」 → 새벽 자동 설치·종료 시 설치(autoInstallOnAppQuit)·「Salir」 설치를 모두 뺐다.
//
// 스킵 조건:
//   - dev 모드 / 미패키징 (app.isPackaged === false)
//   - macOS/Linux (코드서명 없어 자동 업데이트 불가 — 매장 PC 는 Windows)
//   스킵돼도 컨트롤러는 돌려준다(화면이 「Windows 설치본에서만」 을 표시한다).
const { app, dialog } = require('electron');
const { puedeInstalarAMano } = require('./update-policy');

// 4시간마다 재확인 — 매장 영업 중 하루 2~3회 체크 수준
const CHECK_INTERVAL_MS = 4 * 60 * 60 * 1000;

// 부팅 직후는 WebSocket 연결 등과 겹치지 않도록 10초 지연
const FIRST_CHECK_DELAY_MS = 10 * 1000;

const MOTIVO_TEXTO = {
  'sin-descarga': 'Todavía no hay una actualización descargada',
};

/**
 * 자동 업데이트 초기화.
 * @param {object}   opts
 * @param {string}   opts.feed       로그 표시용 feed 이름
 * @param {object}   opts.actividad  update-policy.crearActividad() 의 결과 (인쇄 진행 추적)
 * @param {Function} opts.onLog      로그 콜백 (broadcastLog)
 * @param {Function} opts.onEstado   상태 변경 콜백 (estado) — 트레이·창 갱신용
 * @returns {object} 컨트롤러 { estado, buscar, instalarAhora }
 */
function initAutoUpdater({ feed, actividad, onLog, onEstado } = {}) {
  const log = typeof onLog === 'function' ? onLog : () => {};
  const avisar = typeof onEstado === 'function' ? onEstado : () => {};

  const st = {
    disponible: false,
    actual: app.getVersion(),
    fase: 'inactivo', // inactivo | buscando | al-dia | descargando | listo | error
    nueva: null,
    progreso: null,
    error: null,
    ultimaBusqueda: null,
  };

  const cambiar = (parcial) => {
    Object.assign(st, parcial);
    avisar({ ...st });
  };

  const sinActualizador = {
    estado: () => ({ ...st }),
    buscar: async () => ({ ...st }),
    instalarAhora: () => ({ ok: false, motivo: 'Sólo disponible en la versión instalada de Windows' }),
  };

  // dev/미패키징 또는 비 Windows → 스킵
  if (!app.isPackaged || process.platform !== 'win32') {
    console.log('[updater] skip — packaged:', app.isPackaged, 'platform:', process.platform);

    return sinActualizador;
  }

  let autoUpdater;
  try {
    ({ autoUpdater } = require('electron-updater'));
  } catch (err) {
    // 의존성 누락 등 — 업데이트 실패가 프린트 기능을 막으면 안 됨
    log(`⚠️ auto-update no disponible: ${err.message}`);

    return sinActualizador;
  }

  st.disponible = true;

  autoUpdater.autoDownload = true;

  // ★ 종료할 때 몰래 설치하지 않는다 — 설치는 사용자가 OK 할 때만
  autoUpdater.autoInstallOnAppQuit = false;
  autoUpdater.allowDowngrade = false;

  autoUpdater.on('checking-for-update', () => {
    if (st.fase !== 'listo' && st.fase !== 'descargando') cambiar({ fase: 'buscando', error: null });
  });

  autoUpdater.on('update-not-available', () => {
    if (st.fase !== 'listo') cambiar({ fase: 'al-dia', ultimaBusqueda: Date.now() });
  });

  autoUpdater.on('update-available', (info) => {
    log(`⬇️ Actualización disponible: v${info.version} — descargando en segundo plano...`);
    cambiar({ fase: 'descargando', nueva: info.version, progreso: 0, ultimaBusqueda: Date.now() });
  });

  autoUpdater.on('download-progress', (p) => {
    const pct = Math.floor(p?.percent || 0);
    if (pct !== st.progreso) cambiar({ fase: 'descargando', progreso: pct });
  });

  autoUpdater.on('update-downloaded', (info) => {
    log(`🔄 Actualización v${info.version} lista — se instala sólo si la aceptás («Actualizar ahora»)`);
    cambiar({ fase: 'listo', nueva: info.version, progreso: 100 });
    preguntar(info.version);
  });

  autoUpdater.on('error', (err) => {
    // 네트워크 불안정 등은 흔함 — 경고 로그만 남기고 다음 주기에 재시도
    log(`⚠️ auto-update: ${err.message}`);
    if (st.fase !== 'listo') cambiar({ fase: 'error', error: err.message, ultimaBusqueda: Date.now() });
  });

  const buscar = async () => {
    if (st.fase === 'listo' || st.fase === 'descargando') return { ...st };
    try {
      await autoUpdater.checkForUpdates();
    } catch (err) {
      log(`⚠️ auto-update check: ${err.message}`);
      cambiar({ fase: 'error', error: err.message, ultimaBusqueda: Date.now() });
    }

    return { ...st };
  };

  // 재시작은 전부 여기를 지난다 — 인쇄 중·대기 중·ACK 전이면 기다린다(update-policy.esperarQuieto).
  // isSilent=true: 설치 창 없이 / isForceRunAfter: 설치 후 다시 띄울지
  let instalando = false;
  const instalar = async (volverAAbrir) => {
    if (instalando) return true;
    instalando = true;
    log(`🔄 Instalando v${st.nueva}: espera a que terminen las impresiones...`);

    const quieto = actividad ? await actividad.esperarQuieto() : true;
    if (!quieto) {
      instalando = false;
      log('⚠️ No se reinició: siguió llegando trabajo de impresión. Probá de nuevo con «Actualizar ahora».');

      return false;
    }

    // ★ sin await entre esperarQuieto() y quitAndInstall(): ningún trabajo entra en el medio
    autoUpdater.quitAndInstall(true, volverAAbrir);

    // Si por algo el instalador no arrancó, no dejar la puerta cerrada para siempre
    setTimeout(() => {
      if (actividad) actividad.abrir();
      instalando = false;
      log('⚠️ La instalación no arrancó — el agente sigue con la versión actual');
    }, 60 * 1000);

    return true;
  };

  const instalarAhora = () => {
    const r = puedeInstalarAMano({ listo: st.fase === 'listo' });
    if (!r.ok) return { ok: false, motivo: MOTIVO_TEXTO[r.motivo] || r.motivo };
    instalar(true);

    return { ok: true };
  };

  // 다운로드가 끝나면 한 번 묻는다(버전마다 1회). 「Más tarde」면 띠·트레이에 남는다.
  let preguntada = null;
  const preguntar = (version) => {
    if (preguntada === version) {
      return;
    }
    preguntada = version;
    dialog
      .showMessageBox({
        type: 'question',
        title: 'Actualización disponible',
        message: `Hay una versión nueva del agente: v${version} (tenés v${st.actual}).`,
        detail: 'El agente se reinicia unos segundos. Si hay una impresión en curso, espera a que termine.',
        buttons: ['Actualizar ahora', 'Más tarde'],
        defaultId: 0,
        cancelId: 1,
        noLink: true,
      })
      .then(({ response }) => {
        if (response === 0) {
          instalarAhora();
        } else {
          log('⏸ Actualización pospuesta — podés instalarla con «Actualizar ahora»');
        }
      })
      .catch(() => {});
  };

  setTimeout(buscar, FIRST_CHECK_DELAY_MS);
  setInterval(buscar, CHECK_INTERVAL_MS);

  console.log('[updater] initialized — feed:', feed);

  return { estado: () => ({ ...st }), buscar, instalarAhora };
}

module.exports = { initAutoUpdater };
// src/update-policy.js — ¿cuándo se puede reiniciar el agente para instalar una actualización?
// (mismo archivo en print-agent y zebra-agent)
//
// ★ Por qué existe (실측 2026-10-06): la descarga ya andaba, pero la instalación sólo
//   ocurría «al salir del agente» y el «Salir» usaba app.exit() (no dispara 'quit') → nunca.
//   En la calle: print 1.2.5/1.2.6 con 1.2.10 publicado, zebra 1.0.28/1.0.30 con 1.0.32.
// ★ [2026-10-06 usuario] nunca se actualiza solo: sólo cuando la persona dice que sí.
//
// ★ Regla dura: nunca reiniciar con una impresión en curso (un reinicio a mitad de un
//   trabajo puede perderlo o, si el servidor lo reenvía, imprimirlo dos veces).

/**
 * «Actualizar ahora» (ventana, bandeja o la pregunta al terminar la descarga).
 * Las impresiones en curso no se miran acá: el reinicio pasa siempre por
 * `esperarQuieto()` (abajo), que espera a que terminen.
 */
function puedeInstalarAMano({ listo }) {
  if (!listo) return { ok: false, motivo: 'sin-descarga' };

  return { ok: true };
}

// Después del último envío a la impresora el agente todavía confirma al servidor
// (ACK con timeout de 10 s: mark_qr_printed, print ack). Reiniciar antes = el servidor
// no sabe que se imprimió y lo vuelve a mandar → copia doble.
const ACK_MS = 12 * 1000;

const dormir = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * Cuenta los trabajos de impresión en curso. `envolver(fn)` devuelve una función que
 * marca inicio y fin (también si falla) — se aplica a la llamada que toca la impresora.
 *
 * `cerrar()` deja en la puerta los trabajos nuevos (esperan, no se pierden) mientras se
 * decide reiniciar; `abrir()` los deja pasar. `esperarQuieto()` es el único lugar que
 * decide «se puede reiniciar ya»: sin trabajos en curso, sin trabajos en la puerta y
 * pasado el ACK del último.
 */
function crearActividad(reloj = () => Date.now()) {
  const estado = { enCurso: 0, esperando: 0, ultimaActividad: 0, cerrado: false };
  let soltarPuerta = null;
  let puerta = null;

  const envolver = (fn) => async (...args) => {
    while (estado.cerrado) {
      estado.esperando += 1;
      try {
        await puerta;
      } finally {
        estado.esperando -= 1;
      }
    }
    estado.enCurso += 1;
    estado.ultimaActividad = reloj();
    try {
      return await fn(...args);
    } finally {
      estado.enCurso -= 1;
      estado.ultimaActividad = reloj();
    }
  };

  const cerrar = () => {
    if (estado.cerrado) return;
    estado.cerrado = true;
    puerta = new Promise((r) => { soltarPuerta = r; });
  };

  const abrir = () => {
    if (!estado.cerrado) return;
    estado.cerrado = false;
    soltarPuerta();
  };

  /**
   * Cierra la puerta y espera a que el agente quede quieto. Devuelve true con la puerta
   * CERRADA (el que llama reinicia en el mismo tick, sin await en el medio). Si en el
   * plazo no se logra, la abre y devuelve false.
   */
  const esperarQuieto = async ({ plazoMs = 2 * 60 * 1000, pasoMs = 250, dormirFn = dormir } = {}) => {
    const t0 = reloj();
    while (reloj() - t0 < plazoMs) {
      cerrar();
      if (estado.esperando > 0) {
        // alguien llegó mientras estaba cerrado: que imprima primero
        abrir();
      } else if (estado.enCurso === 0 && reloj() - estado.ultimaActividad >= ACK_MS) {
        return true;
      }
      await dormirFn(pasoMs);
    }
    abrir();

    return false;
  };

  return { estado, envolver, cerrar, abrir, esperarQuieto };
}

module.exports = {
  puedeInstalarAMano,
  crearActividad,
  ACK_MS,
};

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
/bin/zsh -lc "rg -n \"initAutoUpdater|instalarAhora|quitAndInstall|before-quit|will-quit|window-all-closed|esperarQuieto|actividadImpresion|update:install|actualiz\" print-agent zebra-agent --glob '"'!node_modules/**'"' --glob '"'!package-lock.json'"' && diff -u print-agent/src/updater.js zebra-agent/src/updater.js || true && nl -ba print-agent/main.js | sed -n '180,330p' && nl -ba print-agent/src/updater.js | sed -n '85,220p'" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
zebra-agent/src/update-policy.js:1:// src/update-policy.js — ¿cuándo se puede reiniciar el agente para instalar una actualización?
zebra-agent/src/update-policy.js:7:// ★ [2026-10-06 usuario] nunca se actualiza solo: sólo cuando la persona dice que sí.
zebra-agent/src/update-policy.js:15: * `esperarQuieto()` (abajo), que espera a que terminen.
zebra-agent/src/update-policy.js:35: * decide reiniciar; `abrir()` los deja pasar. `esperarQuieto()` es el único lugar que
zebra-agent/src/update-policy.js:80:  const esperarQuieto = async ({ plazoMs = 2 * 60 * 1000, pasoMs = 250, dormirFn = dormir } = {}) => {
zebra-agent/src/update-policy.js:97:  return { estado, envolver, cerrar, abrir, esperarQuieto };
print-agent/src/update-policy.js:1:// src/update-policy.js — ¿cuándo se puede reiniciar el agente para instalar una actualización?
print-agent/src/update-policy.js:7:// ★ [2026-10-06 usuario] nunca se actualiza solo: sólo cuando la persona dice que sí.
print-agent/src/update-policy.js:15: * `esperarQuieto()` (abajo), que espera a que terminen.
print-agent/src/update-policy.js:35: * decide reiniciar; `abrir()` los deja pasar. `esperarQuieto()` es el único lugar que
print-agent/src/update-policy.js:80:  const esperarQuieto = async ({ plazoMs = 2 * 60 * 1000, pasoMs = 250, dormirFn = dormir } = {}) => {
print-agent/src/update-policy.js:97:  return { estado, envolver, cerrar, abrir, esperarQuieto };
zebra-agent/src/updater.js:26:  'sin-descarga': 'Todavía no hay una actualización descargada',
zebra-agent/src/updater.js:36: * @returns {object} 컨트롤러 { estado, buscar, instalarAhora }
zebra-agent/src/updater.js:38:function initAutoUpdater({ feed, actividad, onLog, onEstado } = {}) {
zebra-agent/src/updater.js:60:    instalarAhora: () => ({ ok: false, motivo: 'Sólo disponible en la versión instalada de Windows' }),
zebra-agent/src/updater.js:130:  // 재시작은 전부 여기를 지난다 — 인쇄 중·대기 중·ACK 전이면 기다린다(update-policy.esperarQuieto).
zebra-agent/src/updater.js:138:    const quieto = actividad ? await actividad.esperarQuieto() : true;
zebra-agent/src/updater.js:146:    // ★ sin await entre esperarQuieto() y quitAndInstall(): ningún trabajo entra en el medio
zebra-agent/src/updater.js:147:    autoUpdater.quitAndInstall(true, volverAAbrir);
zebra-agent/src/updater.js:159:  const instalarAhora = () => {
zebra-agent/src/updater.js:187:          instalarAhora();
zebra-agent/src/updater.js:200:  return { estado: () => ({ ...st }), buscar, instalarAhora };
zebra-agent/src/updater.js:203:module.exports = { initAutoUpdater };
print-agent/main.js:18:const { initAutoUpdater }    = require('./src/updater');
print-agent/main.js:23:const actividadImpresion = crearActividad();
print-agent/main.js:24:const printTicket = actividadImpresion.envolver(printTicketSinContar);
print-agent/main.js:25:const printImage = actividadImpresion.envolver(printImageSinContar);
print-agent/main.js:26:const renderHtmlToPng = actividadImpresion.envolver(renderHtmlToPngSinContar);
print-agent/main.js:190:  updaterRef = initAutoUpdater({
print-agent/main.js:192:    actividad: actividadImpresion,
print-agent/main.js:205:app.on('window-all-closed', (e) => {
print-agent/main.js:263:            const r = updaterRef ? updaterRef.instalarAhora() : { ok: false };
print-agent/main.js:290:  actividadImpresion.esperarQuieto({ plazoMs: 30 * 1000 }).finally(() => app.exit(0));
print-agent/main.js:550:// ─── 업데이트 (창의 띠 · 「Buscar actualización」 / 「Actualizar ahora」) ─────
print-agent/main.js:553:ipcMain.handle('update:instalar', () => (updaterRef ? updaterRef.instalarAhora() : { ok: false, motivo: 'No disponible' }));
print-agent/src/updater.js:26:  'sin-descarga': 'Todavía no hay una actualización descargada',
print-agent/src/updater.js:36: * @returns {object} 컨트롤러 { estado, buscar, instalarAhora }
print-agent/src/updater.js:38:function initAutoUpdater({ feed, actividad, onLog, onEstado } = {}) {
print-agent/src/updater.js:60:    instalarAhora: () => ({ ok: false, motivo: 'Sólo disponible en la versión instalada de Windows' }),
print-agent/src/updater.js:130:  // 재시작은 전부 여기를 지난다 — 인쇄 중·대기 중·ACK 전이면 기다린다(update-policy.esperarQuieto).
print-agent/src/updater.js:138:    const quieto = actividad ? await actividad.esperarQuieto() : true;
print-agent/src/updater.js:146:    // ★ sin await entre esperarQuieto() y quitAndInstall(): ningún trabajo entra en el medio
print-agent/src/updater.js:147:    autoUpdater.quitAndInstall(true, volverAAbrir);
print-agent/src/updater.js:159:  const instalarAhora = () => {
print-agent/src/updater.js:187:          instalarAhora();
print-agent/src/updater.js:200:  return { estado: () => ({ ...st }), buscar, instalarAhora };
print-agent/src/updater.js:203:module.exports = { initAutoUpdater };
zebra-agent/main.js:18:const actividadImpresion = crearActividad();
zebra-agent/main.js:19:const sendZpl = actividadImpresion.envolver(sendZplSinContar);
zebra-agent/main.js:21:const { initAutoUpdater } = require('./src/updater');
zebra-agent/main.js:217:  updaterRef = initAutoUpdater({
zebra-agent/main.js:219:    actividad: actividadImpresion,
zebra-agent/main.js:231:app.on('window-all-closed', (e) => {
zebra-agent/main.js:261:            const r = updaterRef ? updaterRef.instalarAhora() : { ok: false };
zebra-agent/main.js:286:  actividadImpresion.esperarQuieto({ plazoMs: 30 * 1000 }).finally(() => app.exit(0));
zebra-agent/main.js:379:// ─── 업데이트 (창의 띠 · 「Buscar actualización」 / 「Actualizar ahora」) ─────
zebra-agent/main.js:382:ipcMain.handle('update:instalar', () => (updaterRef ? updaterRef.instalarAhora() : { ok: false, motivo: 'No disponible' }));
zebra-agent/test/update-policy.smoke.js:30:  await it('a mano: cualquier hora (la espera de impresiones la hace esperarQuieto)', () => {
zebra-agent/test/update-policy.smoke.js:64:    assert.strictEqual(await act.esperarQuieto({ dormirFn: r.dormir }), true);
zebra-agent/test/update-policy.smoke.js:73:    const espera = act.esperarQuieto({ dormirFn: r.dormir, pasoMs: 1000 });
zebra-agent/test/update-policy.smoke.js:93:    const espera = act.esperarQuieto({ dormirFn: r.dormir, pasoMs: 500 });
zebra-agent/test/update-policy.smoke.js:108:    assert.strictEqual(await act.esperarQuieto({ dormirFn: r.dormir, plazoMs: 3000, pasoMs: 1000 }), false);
zebra-agent/test/update-policy.smoke.js:122:    // quitAndInstall sólo dentro de instalar(), y instalar() sólo desde instalarAhora()
zebra-agent/test/update-policy.smoke.js:123:    assert.strictEqual((UPD.match(/quitAndInstall\(/g) || []).length, 1);
zebra-agent/test/update-policy.smoke.js:124:    assert.strictEqual((UPD.match(/\binstalar\(/g) || []).length, 1, 'instalar() llamado fuera de instalarAhora');
zebra-agent/test/update-policy.smoke.js:125:    assert.ok(/const instalarAhora = \(\) => {[\s\S]{0,250}?instalar\(true\)/.test(UPD));
zebra-agent/test/update-policy.smoke.js:126:    // instalarAhora sólo desde el botón (IPC), la bandeja o el «sí» de la pregunta
zebra-agent/test/update-policy.smoke.js:127:    assert.strictEqual((UPD.match(/instalarAhora\(\)/g) || []).length, 1, 'instalarAhora sólo desde el «sí»');
zebra-agent/test/update-policy.smoke.js:128:    assert.ok(/if \(response === 0\) \{\s*instalarAhora\(\);/.test(UPD));
zebra-agent/test/update-policy.smoke.js:134:    assert.ok(/actividadImpresion\.esperarQuieto\(\{ plazoMs: 30 \* 1000 \}\)\.finally\(\(\) => app\.exit\(0\)\)/.test(MAIN),
zebra-agent/test/update-policy.smoke.js:145:      assert.ok(new RegExp(`actividadImpresion\\.envolver\\(${c}\\)`).test(MAIN), `${c} no está envuelta`);
zebra-agent/test/update-policy.smoke.js:147:    assert.ok(/actividad:\s*actividadImpresion/.test(MAIN), 'el updater no recibe el contador');
print-agent/test/update-policy.smoke.js:30:  await it('a mano: cualquier hora (la espera de impresiones la hace esperarQuieto)', () => {
print-agent/test/update-policy.smoke.js:64:    assert.strictEqual(await act.esperarQuieto({ dormirFn: r.dormir }), true);
print-agent/test/update-policy.smoke.js:73:    const espera = act.esperarQuieto({ dormirFn: r.dormir, pasoMs: 1000 });
print-agent/test/update-policy.smoke.js:93:    const espera = act.esperarQuieto({ dormirFn: r.dormir, pasoMs: 500 });
print-agent/test/update-policy.smoke.js:108:    assert.strictEqual(await act.esperarQuieto({ dormirFn: r.dormir, plazoMs: 3000, pasoMs: 1000 }), false);
print-agent/test/update-policy.smoke.js:122:    // quitAndInstall sólo dentro de instalar(), y instalar() sólo desde instalarAhora()
print-agent/test/update-policy.smoke.js:123:    assert.strictEqual((UPD.match(/quitAndInstall\(/g) || []).length, 1);
print-agent/test/update-policy.smoke.js:124:    assert.strictEqual((UPD.match(/\binstalar\(/g) || []).length, 1, 'instalar() llamado fuera de instalarAhora');
print-agent/test/update-policy.smoke.js:125:    assert.ok(/const instalarAhora = \(\) => {[\s\S]{0,250}?instalar\(true\)/.test(UPD));
print-agent/test/update-policy.smoke.js:126:    // instalarAhora sólo desde el botón (IPC), la bandeja o el «sí» de la pregunta
print-agent/test/update-policy.smoke.js:127:    assert.strictEqual((UPD.match(/instalarAhora\(\)/g) || []).length, 1, 'instalarAhora sólo desde el «sí»');
print-agent/test/update-policy.smoke.js:128:    assert.ok(/if \(response === 0\) \{\s*instalarAhora\(\);/.test(UPD));
print-agent/test/update-policy.smoke.js:134:    assert.ok(/actividadImpresion\.esperarQuieto\(\{ plazoMs: 30 \* 1000 \}\)\.finally\(\(\) => app\.exit\(0\)\)/.test(MAIN),
print-agent/test/update-policy.smoke.js:145:      assert.ok(new RegExp(`actividadImpresion\\.envolver\\(${c}\\)`).test(MAIN), `${c} no está envuelta`);
print-agent/test/update-policy.smoke.js:147:    assert.ok(/actividad:\s*actividadImpresion/.test(MAIN), 'el updater no recibe el contador');
zebra-agent/renderer/update-banner.js:1:// renderer/update-banner.js — franja de actualización arriba de la ventana
zebra-agent/renderer/update-banner.js:4:// Muestra la versión instalada y el estado de la actualización:
zebra-agent/renderer/update-banner.js:49:      txt.textContent = `v${e.actual} · actualización automática sólo en la versión instalada de Windows`;
zebra-agent/renderer/update-banner.js:58:          aviso = (r && r.motivo) || 'No se pudo actualizar';
zebra-agent/renderer/update-banner.js:70:      txt.textContent = `v${e.actual} · buscando actualización...`;
zebra-agent/renderer/update-banner.js:71:      btn.textContent = 'Buscar actualización';
zebra-agent/renderer/update-banner.js:74:      txt.textContent = `v${e.actual} · no se pudo comprobar actualizaciones${hace(e.ultimaBusqueda)}`;
zebra-agent/renderer/update-banner.js:79:      btn.textContent = 'Buscar actualización';
zebra-agent/renderer/index.html:2163:    loadServerInfo(); addLocalLog('API Key actualizada');
zebra-agent/mockups/etiqueta-config-mockup.html:127:        <div class="preview-hint">Se actualiza en tiempo real (escala 1:1 con ZPL). Probá cambiar SKU/niveles/valores.</div>
print-agent/renderer/update-banner.js:1:// renderer/update-banner.js — franja de actualización arriba de la ventana
print-agent/renderer/update-banner.js:4:// Muestra la versión instalada y el estado de la actualización:
print-agent/renderer/update-banner.js:49:      txt.textContent = `v${e.actual} · actualización automática sólo en la versión instalada de Windows`;
print-agent/renderer/update-banner.js:58:          aviso = (r && r.motivo) || 'No se pudo actualizar';
print-agent/renderer/update-banner.js:70:      txt.textContent = `v${e.actual} · buscando actualización...`;
print-agent/renderer/update-banner.js:71:      btn.textContent = 'Buscar actualización';
print-agent/renderer/update-banner.js:74:      txt.textContent = `v${e.actual} · no se pudo comprobar actualizaciones${hace(e.ultimaBusqueda)}`;
print-agent/renderer/update-banner.js:79:      btn.textContent = 'Buscar actualización';
   180	  // Windows 시작 시 자동 실행 설정
   181	  if (store.get('openAtLogin')) {
   182	    try {
   183	      app.setLoginItemSettings({ openAtLogin: true, openAsHidden: true });
   184	    } catch (err) {
   185	      console.error('setLoginItemSettings error:', err);
   186	    }
   187	  }
   188	
   189	  // ─── 자동 업데이트 (Windows packaged 전용 — dev/mac 은 내부에서 스킵) ──────
   190	  updaterRef = initAutoUpdater({
   191	    feed: 'print-agent-latest (generic)',
   192	    actividad: actividadImpresion,
   193	    onLog: broadcastLog,
   194	    onEstado: (estado) => {
   195	      const antes = updateEstado?.fase;
   196	      updateEstado = estado;
   197	      if (antes !== estado.fase) updateTrayMenu(); // "Actualizar ahora" 메뉴 노출
   198	      if (mainWindow && !mainWindow.isDestroyed()) mainWindow.webContents.send('update-estado', estado);
   199	    },
   200	  });
   201	  updateEstado = updaterRef.estado();
   202	});
   203	
   204	// 모든 창 닫혀도 앱 종료하지 않음 (트레이 상주)
   205	app.on('window-all-closed', (e) => {
   206	  e.preventDefault();
   207	});
   208	
   209	// ─── 트레이 생성 ──────────────────────────────────────────────────────────────
   210	function createTray() {
   211	  // 트레이 아이콘 (16x16 PNG). 파일이 없으면 빈 이미지 사용 (개발 단계)
   212	  const iconPath = path.join(__dirname, 'renderer/assets/tray-icon.png');
   213	  let image = nativeImage.createFromPath(iconPath);
   214	  if (image.isEmpty()) {
   215	    image = nativeImage.createEmpty();
   216	  }
   217	  tray = new Tray(image);
   218	
   219	  // DEV 모드: 툴팁 + macOS 메뉴바 텍스트 라벨로 명시
   220	  if (IS_DEV) {
   221	    tray.setToolTip('VentaGO Print Agent — 🛠️ DEV MODE (PNG preview)');
   222	
   223	    // macOS 만 setTitle 이 메뉴바 아이콘 옆 텍스트로 표시됨 (Windows/Linux 는 noop)
   224	    if (process.platform === 'darwin' && typeof tray.setTitle === 'function') {
   225	      tray.setTitle('DEV');
   226	    }
   227	  } else {
   228	    tray.setToolTip('VentaGO Print Agent');
   229	  }
   230	
   231	  updateTrayMenu();
   232	
   233	  // 더블클릭 시 설정 창 열기
   234	  tray.on('double-click', openMainWindow);
   235	}
   236	
   237	function updateTrayMenu() {
   238	  const statusLabel = {
   239	    connected: '🟢 Conectado',
   240	    disconnected: '🔴 Desconectado',
   241	    reconnecting: '🟡 Reconectando...',
   242	    displaced: '⛔ Reemplazado (misma API Key)',
   243	  }[connectionStatus] ?? '🔴 Desconectado';
   244	
   245	  // DEV 모드 배지: 메뉴 최상단에 비활성화된 라벨로 항상 노출
   246	  const devBadge = IS_DEV
   247	    ? [
   248	        {
   249	          label: `🛠️  DEV MODE — PNG preview → ${path.join(os.homedir(), 'Desktop')}`,
   250	          enabled: false,
   251	        },
   252	        { label: `   API: ${SERVER_URL}`, enabled: false },
   253	        { type: 'separator' },
   254	      ]
   255	    : [];
   256	
   257	  // 업데이트 다운로드 완료 시 수동 설치 메뉴 (미완료 시 빈 배열)
   258	  const updateItems = updateEstado?.fase === 'listo'
   259	    ? [
   260	        {
   261	          label: `🔄 Actualizar ahora a v${updateEstado.nueva}`,
   262	          click: () => {
   263	            const r = updaterRef ? updaterRef.instalarAhora() : { ok: false };
   264	            if (!r.ok && r.motivo) broadcastLog(`⚠️ ${r.motivo}`);
   265	          },
   266	        },
   267	        { type: 'separator' },
   268	      ]
   269	    : [];
   270	
   271	  const contextMenu = Menu.buildFromTemplate([
   272	    ...devBadge,
   273	    ...updateItems,
   274	    { label: statusLabel, enabled: false },
   275	    { type: 'separator' },
   276	    { label: 'Abrir configuración', click: openMainWindow },
   277	    { label: 'Imprimir test', click: () => printTest() },
   278	    { label: 'Ver log', click: openLogWindow },
   279	    { type: 'separator' },
   280	    { label: 'Salir', click: salir },
   281	  ]);
   282	
   283	  tray.setContextMenu(contextMenu);
   284	}
   285	
   286	// 「Salir」: 인쇄가 끝난 뒤에 끝낸다. 업데이트는 설치하지 않는다(사용자가 OK 할 때만).
   287	function salir() {
   288	  // ★ se espera a que termine la impresión en curso (y su ACK) —
   289	  //   cortar a mitad de un trabajo lo pierde o, si el servidor lo reenvía, sale dos veces.
   290	  actividadImpresion.esperarQuieto({ plazoMs: 30 * 1000 }).finally(() => app.exit(0));
   291	}
   292	
   293	// 연결 상태 변경 시 트레이 아이콘 업데이트
   294	function setConnectionStatus(status) {
   295	  connectionStatus = status;
   296	  updateTrayMenu();
   297	
   298	  // 설정 창이 열려 있으면 상태 전달
   299	  if (mainWindow) {
   300	    mainWindow.webContents.send('connection-status', status);
   301	  }
   302	}
   303	
   304	// ─── 창 관리 ──────────────────────────────────────────────────────────────────
   305	function openSetupWizard() {
   306	  if (setupWindow) {
   307	    setupWindow.focus();
   308	
   309	    return;
   310	  }
   311	
   312	  setupWindow = new BrowserWindow({
   313	    width: 520,
   314	    height: 480,
   315	    resizable: false,
   316	    title: 'VentaGO Print Agent — Configuración inicial',
   317	    webPreferences: {
   318	      preload: path.join(__dirname, 'preload.js'),
   319	      contextIsolation: true,
   320	      nodeIntegration: false,
   321	    },
   322	  });
   323	
   324	  setupWindow.loadFile('renderer/setup-wizard.html');
   325	  setupWindow.on('closed', () => { setupWindow = null; });
   326	}
   327	
   328	function openMainWindow() {
   329	  if (mainWindow) {
   330	    mainWindow.show();
    85	  autoUpdater.autoInstallOnAppQuit = false;
    86	  autoUpdater.allowDowngrade = false;
    87	
    88	  autoUpdater.on('checking-for-update', () => {
    89	    if (st.fase !== 'listo' && st.fase !== 'descargando') cambiar({ fase: 'buscando', error: null });
    90	  });
    91	
    92	  autoUpdater.on('update-not-available', () => {
    93	    if (st.fase !== 'listo') cambiar({ fase: 'al-dia', ultimaBusqueda: Date.now() });
    94	  });
    95	
    96	  autoUpdater.on('update-available', (info) => {
    97	    log(`⬇️ Actualización disponible: v${info.version} — descargando en segundo plano...`);
    98	    cambiar({ fase: 'descargando', nueva: info.version, progreso: 0, ultimaBusqueda: Date.now() });
    99	  });
   100	
   101	  autoUpdater.on('download-progress', (p) => {
   102	    const pct = Math.floor(p?.percent || 0);
   103	    if (pct !== st.progreso) cambiar({ fase: 'descargando', progreso: pct });
   104	  });
   105	
   106	  autoUpdater.on('update-downloaded', (info) => {
   107	    log(`🔄 Actualización v${info.version} lista — se instala sólo si la aceptás («Actualizar ahora»)`);
   108	    cambiar({ fase: 'listo', nueva: info.version, progreso: 100 });
   109	    preguntar(info.version);
   110	  });
   111	
   112	  autoUpdater.on('error', (err) => {
   113	    // 네트워크 불안정 등은 흔함 — 경고 로그만 남기고 다음 주기에 재시도
   114	    log(`⚠️ auto-update: ${err.message}`);
   115	    if (st.fase !== 'listo') cambiar({ fase: 'error', error: err.message, ultimaBusqueda: Date.now() });
   116	  });
   117	
   118	  const buscar = async () => {
   119	    if (st.fase === 'listo' || st.fase === 'descargando') return { ...st };
   120	    try {
   121	      await autoUpdater.checkForUpdates();
   122	    } catch (err) {
   123	      log(`⚠️ auto-update check: ${err.message}`);
   124	      cambiar({ fase: 'error', error: err.message, ultimaBusqueda: Date.now() });
   125	    }
   126	
   127	    return { ...st };
   128	  };
   129	
   130	  // 재시작은 전부 여기를 지난다 — 인쇄 중·대기 중·ACK 전이면 기다린다(update-policy.esperarQuieto).
   131	  // isSilent=true: 설치 창 없이 / isForceRunAfter: 설치 후 다시 띄울지
   132	  let instalando = false;
   133	  const instalar = async (volverAAbrir) => {
   134	    if (instalando) return true;
   135	    instalando = true;
   136	    log(`🔄 Instalando v${st.nueva}: espera a que terminen las impresiones...`);
   137	
   138	    const quieto = actividad ? await actividad.esperarQuieto() : true;
   139	    if (!quieto) {
   140	      instalando = false;
   141	      log('⚠️ No se reinició: siguió llegando trabajo de impresión. Probá de nuevo con «Actualizar ahora».');
   142	
   143	      return false;
   144	    }
   145	
   146	    // ★ sin await entre esperarQuieto() y quitAndInstall(): ningún trabajo entra en el medio
   147	    autoUpdater.quitAndInstall(true, volverAAbrir);
   148	
   149	    // Si por algo el instalador no arrancó, no dejar la puerta cerrada para siempre
   150	    setTimeout(() => {
   151	      if (actividad) actividad.abrir();
   152	      instalando = false;
   153	      log('⚠️ La instalación no arrancó — el agente sigue con la versión actual');
   154	    }, 60 * 1000);
   155	
   156	    return true;
   157	  };
   158	
   159	  const instalarAhora = () => {
   160	    const r = puedeInstalarAMano({ listo: st.fase === 'listo' });
   161	    if (!r.ok) return { ok: false, motivo: MOTIVO_TEXTO[r.motivo] || r.motivo };
   162	    instalar(true);
   163	
   164	    return { ok: true };
   165	  };
   166	
   167	  // 다운로드가 끝나면 한 번 묻는다(버전마다 1회). 「Más tarde」면 띠·트레이에 남는다.
   168	  let preguntada = null;
   169	  const preguntar = (version) => {
   170	    if (preguntada === version) {
   171	      return;
   172	    }
   173	    preguntada = version;
   174	    dialog
   175	      .showMessageBox({
   176	        type: 'question',
   177	        title: 'Actualización disponible',
   178	        message: `Hay una versión nueva del agente: v${version} (tenés v${st.actual}).`,
   179	        detail: 'El agente se reinicia unos segundos. Si hay una impresión en curso, espera a que termine.',
   180	        buttons: ['Actualizar ahora', 'Más tarde'],
   181	        defaultId: 0,
   182	        cancelId: 1,
   183	        noLink: true,
   184	      })
   185	      .then(({ response }) => {
   186	        if (response === 0) {
   187	          instalarAhora();
   188	        } else {
   189	          log('⏸ Actualización pospuesta — podés instalarla con «Actualizar ahora»');
   190	        }
   191	      })
   192	      .catch(() => {});
   193	  };
   194	
   195	  setTimeout(buscar, FIRST_CHECK_DELAY_MS);
   196	  setInterval(buscar, CHECK_INTERVAL_MS);
   197	
   198	  console.log('[updater] initialized — feed:', feed);
   199	
   200	  return { estado: () => ({ ...st }), buscar, instalarAhora };
   201	}
   202	
   203	module.exports = { initAutoUpdater };

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
/bin/zsh -lc "nl -ba print-agent/renderer/update-banner.js | sed -n '1,110p'; nl -ba print-agent/src/update-policy.js | sed -n '40,110p'; nl -ba print-agent/main.js | sed -n '1,80p;530,565p'; nl -ba zebra-agent/main.js | sed -n '1,45p;365,390p'; git diff --check; node print-agent/test/update-policy.smoke.js; node zebra-agent/test/update-policy.smoke.js" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
     1	// renderer/update-banner.js — franja de actualización arriba de la ventana
     2	// (mismo archivo en print-agent y zebra-agent)
     3	//
     4	// Muestra la versión instalada y el estado de la actualización:
     5	//   al día · buscando · descargando N% · lista (botón «Actualizar ahora») · error (reintentar)
     6	// Nunca se instala solo: sólo con «Actualizar ahora» (o «sí» en la pregunta al descargar).
     7	(function updateBanner() {
     8	  const api = window.electronAPI;
     9	  if (!api || typeof api.getUpdateEstado !== 'function') return;
    10	
    11	  const css = document.createElement('style');
    12	  css.textContent = `
    13	    #upd-banner { display:flex; align-items:center; gap:10px; padding:6px 12px; margin:0 0 8px;
    14	      font-size:12px; color:#9a9cb8; background:#16162a; border:1px solid #2a2a4a; border-radius:8px; }
    15	    #upd-banner.listo { color:#1a1a2e; background:#f5a623; border-color:#f5a623; font-weight:600; }
    16	    #upd-banner.error { color:#ffb4a8; border-color:#5a2a2a; }
    17	    #upd-banner .upd-txt { flex:1; min-width:0; }
    18	    #upd-banner button { font-size:12px; padding:3px 10px; border-radius:6px; cursor:pointer;
    19	      border:1px solid #3a3a5a; background:#22223a; color:#e0e0e0; }
    20	    #upd-banner.listo button { background:#1a1a2e; color:#f5a623; border-color:#1a1a2e; }
    21	    #upd-banner button:disabled { opacity:.5; cursor:default; }
    22	  `;
    23	  document.head.appendChild(css);
    24	
    25	  const el = document.createElement('div');
    26	  el.id = 'upd-banner';
    27	  el.innerHTML = '<span class="upd-txt"></span><button type="button"></button>';
    28	  const contenedor = document.querySelector('.container') || document.body;
    29	  contenedor.insertBefore(el, contenedor.firstChild);
    30	
    31	  const txt = el.querySelector('.upd-txt');
    32	  const btn = el.querySelector('button');
    33	  let aviso = null; // mensaje temporal tras un clic (p.ej. «hay una impresión en curso»)
    34	
    35	  const hace = (ms) => {
    36	    if (!ms) return '';
    37	    const min = Math.round((Date.now() - ms) / 60000);
    38	
    39	    return min < 1 ? ' · recién' : min < 60 ? ` · hace ${min} min` : ` · hace ${Math.round(min / 60)} h`;
    40	  };
    41	
    42	  const pintar = (e) => {
    43	    if (!e) return;
    44	    el.className = e.fase === 'listo' ? 'listo' : e.fase === 'error' ? 'error' : '';
    45	    btn.style.display = '';
    46	    btn.disabled = false;
    47	
    48	    if (!e.disponible) {
    49	      txt.textContent = `v${e.actual} · actualización automática sólo en la versión instalada de Windows`;
    50	      btn.style.display = 'none';
    51	    } else if (e.fase === 'listo') {
    52	      txt.textContent = `Nueva versión v${e.nueva} lista (tenés v${e.actual}) · se instala sólo si tocás «Actualizar ahora»`;
    53	      btn.textContent = 'Actualizar ahora';
    54	      btn.onclick = async () => {
    55	        btn.disabled = true;
    56	        const r = await api.instalarUpdate();
    57	        if (!r || !r.ok) {
    58	          aviso = (r && r.motivo) || 'No se pudo actualizar';
    59	          txt.textContent = aviso;
    60	          setTimeout(() => { aviso = null; api.getUpdateEstado().then(pintar); }, 4000);
    61	          btn.disabled = false;
    62	        } else {
    63	          txt.textContent = `Instalando v${e.nueva}: se reinicia en cuanto terminen las impresiones...`;
    64	        }
    65	      };
    66	    } else if (e.fase === 'descargando') {
    67	      txt.textContent = `Descargando v${e.nueva}... ${e.progreso ?? 0}% (tenés v${e.actual})`;
    68	      btn.style.display = 'none';
    69	    } else if (e.fase === 'buscando') {
    70	      txt.textContent = `v${e.actual} · buscando actualización...`;
    71	      btn.textContent = 'Buscar actualización';
    72	      btn.disabled = true;
    73	    } else if (e.fase === 'error') {
    74	      txt.textContent = `v${e.actual} · no se pudo comprobar actualizaciones${hace(e.ultimaBusqueda)}`;
    75	      btn.textContent = 'Reintentar';
    76	      btn.onclick = () => { btn.disabled = true; api.buscarUpdate().then(pintar); };
    77	    } else {
    78	      txt.textContent = `v${e.actual}${e.fase === 'al-dia' ? ' · al día' + hace(e.ultimaBusqueda) : ''}`;
    79	      btn.textContent = 'Buscar actualización';
    80	      btn.onclick = () => { btn.disabled = true; api.buscarUpdate().then(pintar); };
    81	    }
    82	
    83	    if (aviso) txt.textContent = aviso;
    84	  };
    85	
    86	  api.getUpdateEstado().then(pintar).catch(() => {});
    87	  if (typeof api.onUpdateEstado === 'function') api.onUpdateEstado(pintar);
    88	})();
    40	  const estado = { enCurso: 0, esperando: 0, ultimaActividad: 0, cerrado: false };
    41	  let soltarPuerta = null;
    42	  let puerta = null;
    43	
    44	  const envolver = (fn) => async (...args) => {
    45	    while (estado.cerrado) {
    46	      estado.esperando += 1;
    47	      try {
    48	        await puerta;
    49	      } finally {
    50	        estado.esperando -= 1;
    51	      }
    52	    }
    53	    estado.enCurso += 1;
    54	    estado.ultimaActividad = reloj();
    55	    try {
    56	      return await fn(...args);
    57	    } finally {
    58	      estado.enCurso -= 1;
    59	      estado.ultimaActividad = reloj();
    60	    }
    61	  };
    62	
    63	  const cerrar = () => {
    64	    if (estado.cerrado) return;
    65	    estado.cerrado = true;
    66	    puerta = new Promise((r) => { soltarPuerta = r; });
    67	  };
    68	
    69	  const abrir = () => {
    70	    if (!estado.cerrado) return;
    71	    estado.cerrado = false;
    72	    soltarPuerta();
    73	  };
    74	
    75	  /**
    76	   * Cierra la puerta y espera a que el agente quede quieto. Devuelve true con la puerta
    77	   * CERRADA (el que llama reinicia en el mismo tick, sin await en el medio). Si en el
    78	   * plazo no se logra, la abre y devuelve false.
    79	   */
    80	  const esperarQuieto = async ({ plazoMs = 2 * 60 * 1000, pasoMs = 250, dormirFn = dormir } = {}) => {
    81	    const t0 = reloj();
    82	    while (reloj() - t0 < plazoMs) {
    83	      cerrar();
    84	      if (estado.esperando > 0) {
    85	        // alguien llegó mientras estaba cerrado: que imprima primero
    86	        abrir();
    87	      } else if (estado.enCurso === 0 && reloj() - estado.ultimaActividad >= ACK_MS) {
    88	        return true;
    89	      }
    90	      await dormirFn(pasoMs);
    91	    }
    92	    abrir();
    93	
    94	    return false;
    95	  };
    96	
    97	  return { estado, envolver, cerrar, abrir, esperarQuieto };
    98	}
    99	
   100	module.exports = {
   101	  puedeInstalarAMano,
   102	  crearActividad,
   103	  ACK_MS,
   104	};
     1	// print-agent/main.js
     2	// VentaGO Print Agent — Electron 메인 프로세스
     3	const { app, BrowserWindow, Tray, Menu, ipcMain, nativeImage, shell } = require('electron');
     4	const path = require('path');
     5	const fs = require('fs');
     6	const os = require('os');
     7	const Store = require('electron-store');
     8	const printDedup = require('./src/print-dedup');
     9	const { printTicket: printTicketSinContar } = require('./src/print-pipeline');
    10	const { formatFiscalHtml }  = require('./src/fiscal-formatter');
    11	const { formatQrHtml }      = require('./src/qr-formatter');
    12	const { formatTempTicketHtml, formatInvoiceHtml } = require('./src/formatter');
    13	const { renderHtmlToPng: renderHtmlToPngSinContar } = require('./src/renderer-engine');
    14	const ticketSettings        = require('./src/ticket-settings');
    15	const { printImage: printImageSinContar, testConnection: testPrinterConnection } = require('./src/printer');
    16	const { discoverPrinters: discoverPrintersImpl } = require('./src/printer-discovery');
    17	const { listSystemPrinters } = require('./src/win-printer');
    18	const { initAutoUpdater }    = require('./src/updater');
    19	const { crearActividad }     = require('./src/update-policy');
    20	
    21	// 인쇄 진행 추적 — 업데이트 재시작은 인쇄 중엔 절대 하지 않는다(update-policy.js).
    22	// 프린터에 닿는 호출(렌더 → 출력)을 전부 이 래퍼로 감싼다.
    23	const actividadImpresion = crearActividad();
    24	const printTicket = actividadImpresion.envolver(printTicketSinContar);
    25	const printImage = actividadImpresion.envolver(printImageSinContar);
    26	const renderHtmlToPng = actividadImpresion.envolver(renderHtmlToPngSinContar);
    27	
    28	// ─── 개발 모드 감지 ─────────────────────────────────────────────────────────
    29	// `npm run dev` (= electron . --dev) 실행 시 process.argv 에 '--dev' 가 포함됨.
    30	// dev 모드에서는:
    31	//   1) SERVER_URL 을 로컬 NestJS (localhost:5002) 로 전환
    32	//   2) printer.js 의 printImage 가 실 프린터 대신 ~/Desktop/print-debug-*.png 로 저장 (PNG 미리보기 모드)
    33	const IS_DEV = process.argv.includes('--dev') || process.env.PRINT_AGENT_DEV === '1';
    34	
    35	// 다른 모듈(printer.js 등) 에서 동일하게 인식하도록 env var 도 함께 세팅
    36	if (IS_DEV) process.env.PRINT_AGENT_DEV = '1';
    37	
    38	// ─── 고정 서버 URL (운영 = 도메인 경유, dev = 로컬 백엔드) ───────────────────
    39	const SERVER_URL = IS_DEV
    40	  ? 'http://localhost:5002/api'
    41	  : 'https://newapi.coolsistema.com/api';
    42	
    43	console.log(`[print-agent] 모드: ${IS_DEV ? 'DEV (로컬 백엔드 + PNG 미리보기)' : 'PROD'}`);
    44	console.log(`[print-agent] SERVER_URL: ${SERVER_URL}`);
    45	
    46	// ─── 설정 저장소 (electron-store) ───────────────────────────────────────────
    47	// 저장 위치: Windows %APPDATA%/ventago-print-agent/config.json
    48	const store = new Store({
    49	  defaults: {
    50	    apiUrl: '',
    51	    apiKey: '',
    52	    printer: {
    53	      type: 'network',
    54	      host: '192.168.1.100',
    55	      port: 9100,
    56	      vendorId: '0x0',
    57	      productId: '0x0',
    58	      deviceName: '',   // Windows/시스템 프린터 이름 (type='windows' 일 때 사용)
    59	      width: 48,
    60	    },
    61	    printControl: true,   // 판매 확정 시 컨트롤 티켓 출력
    62	    printFiscal: true,    // AFIP 발행 시 영수증 출력
    63	    ticketFont: ticketSettings.DEFAULT_FONT_ID,   // 티켓 폰트 (기본 Arial — 가독성)
    64	    ticketFontScale: ticketSettings.DEFAULT_SCALE, // 티켓 폰트 크기 배율
    65	    // 오른쪽 여백(px) — 프린터의 인쇄 가능 폭이 576 보다 좁아 끝이 잘릴 때만 올린다.
    66	    // 기본 0: 대부분의 프린터는 필요 없고, 올리면 긴 상품명이 한 줄 더 접힌다.
    67	    ticketMarginRight: ticketSettings.DEFAULT_MARGIN_RIGHT,
    68	    openAtLogin: true,
    69	    setupDone: false,     // false 이면 마법사 먼저 표시
    70	    // ─── 다중 프로파일 (sucursal 연결 저장) ──────────────────────────────────
    71	    profiles: [],         // [{ id, label, apiUrl, apiKey, printer }]
    72	    activeProfileId: null,
    73	  },
    74	});
    75	
    76	// ★ 인쇄 작업 원장을 디스크에서 복구한다. 에이전트가 재시작하는 사이에 같은 작업이
    77	//   다시 배달될 수 있는데(서버 재전송·소켓 재연결), 메모리만 쓰면 그때 두 장이 나온다.
    78	printDedup.attachStore(store, (err) => {
    79	  console.error('[print-dedup] 원장 저장 실패 — 재기동 시 중복 인쇄 가능:', err?.message);
    80	  try {
   530	  Object.entries(config).forEach(([k, v]) => store.set(k, v));
   531	});
   532	
   533	// WebSocket 연결 상태 조회
   534	ipcMain.handle('ws:status', () => connectionStatus);
   535	
   536	// WebSocket 재연결 트리거
   537	ipcMain.handle('ws:reconnect', () => {
   538	  initWebSocket(); // Phase 11-02에서 구현
   539	});
   540	
   541	// 셋업 완료 → 마법사 닫고 메인창 + WebSocket 시작
   542	ipcMain.handle('setup:complete', () => {
   543	  store.set('setupDone', true);
   544	  if (setupWindow) setupWindow.close();
   545	  openMainWindow();
   546	  initWebSocket();
   547	});
   548	
   549	// 프린터 테스트 출력 (Phase 11-02에서 구현)
   550	// ─── 업데이트 (창의 띠 · 「Buscar actualización」 / 「Actualizar ahora」) ─────
   551	ipcMain.handle('update:estado', () => (updaterRef ? updaterRef.estado() : updateEstado));
   552	ipcMain.handle('update:buscar', () => (updaterRef ? updaterRef.buscar() : updateEstado));
   553	ipcMain.handle('update:instalar', () => (updaterRef ? updaterRef.instalarAhora() : { ok: false, motivo: 'No disponible' }));
   554	
   555	ipcMain.handle('printer:test', () => printTest());
   556	
   557	// ── 티켓 미리보기 — 프린터/Snagit 없이 렌더 결과 PNG 를 바로 확인 ──────────────
   558	// 실제 출력과 100% 동일한 파이프라인(formatInvoiceHtml → renderHtmlToPng, 폰트
   559	// 설정 포함)으로 PNG 를 만들어 임시 폴더에 저장 후 OS 기본 이미지 뷰어로 연다.
   560	ipcMain.handle('printer:preview', async () => {
   561	  try {
   562	    const html = formatInvoiceHtml(buildTestTicketData());
   563	    const png  = await renderHtmlToPng(html, 576, 10000, broadcastLog);
   564	
   565	    if (!png || png.length === 0) {
     1	// zebra-agent/main.js
     2	// VentaGO Zebra Agent — Electron 메인 프로세스
     3	// Zebra 라벨 프린터에 ZPL II 명령을 TCP Raw Socket으로 전송
     4	const { app, BrowserWindow, Tray, Menu, ipcMain, nativeImage } = require('electron');
     5	const path = require('path');
     6	const Store = require('electron-store');
     7	const {
     8	  formatBatchLabels, formatQrLabel, resolveMode, darknessZpl, speedZpl,
     9	  LABEL_MODES, LEGACY_PRESET_ALIASES,
    10	  formatQrLabelConAvisos, zplADibujo, qrLotePreview, filasDeLoteQrTotal, qrLoteFilas,
    11	} = require('./src/zpl-formatter');
    12	const { prepareItems: prepareItemsPure } = require('./src/price-select');
    13	const { sendZpl: sendZplSinContar, testConnection: testPrinterConnection, listUsbPrinters } = require('./src/zebra-printer');
    14	const { crearActividad } = require('./src/update-policy');
    15	
    16	// 인쇄 진행 추적 — 업데이트 재시작은 인쇄 중엔 절대 하지 않는다(update-policy.js).
    17	// 프린터에 닿는 호출(sendZpl)을 전부 이 래퍼로 감싼다.
    18	const actividadImpresion = crearActividad();
    19	const sendZpl = actividadImpresion.envolver(sendZplSinContar);
    20	const { discoverPrinters: discoverPrintersImpl } = require('./src/printer-discovery');
    21	const { initAutoUpdater } = require('./src/updater');
    22	
    23	// ─── 고정 서버 URL (항상 운영 서버 — 도메인 경유, 5002 포트 직접 접근 불가) ───
    24	const SERVER_URL = 'https://newapi.coolsistema.com/api';
    25	
    26	// ─── 설정 저장소 ────────────────────────────────────────────────────────────
    27	const store = new Store({
    28	  defaults: {
    29	    apiKey: '',
    30	    agentType: 'zebra',
    31	    printer: {
    32	      type: 'network',     // 'network' | 'usb'
    33	      host: '',
    34	      port: 9100,
    35	      printerName: '',     // USB 프린터 이름 (OS에 등록된)
    36	    },
    37	    labelPreset: '50x25-simple',   // 구버전 키 (마이그레이션용으로만 유지)
    38	    labelLayout: null,             // 구버전 키 (마이그레이션용으로만 유지)
    39	    labelMode: '',                 // 신규: 출력 모드 (simple-face 등 4종)
    40	    labelLayouts: {},              // 신규: 모드별 커스텀 { [modeKey]: { width, height, layout } }
    41	    priceSelection: [],            // 신규: 출력할 precio nivel [{ id, name }] 최대 3개
    42	    // 출력 파라미터 — 모드/QR 구분 없이 프린터 전역 적용 (null = 프린터 기본값)
    43	    printSettings: { darkness: null, speed: null },
    44	    openAtLogin: true,
    45	    setupDone: false,
   365	// 연결 테스트 (마법사용 — 서버 URL 고정, API Key만 테스트)
   366	ipcMain.handle('ws:test', async (_event, _url, apiKey) => {
   367	  return testWsConnection(apiKey);
   368	});
   369	
   370	// 셋업 완료
   371	ipcMain.handle('setup:complete', () => {
   372	  store.set('setupDone', true);
   373	  if (setupWindow) setupWindow.close();
   374	  openMainWindow();
   375	  initWebSocket();
   376	});
   377	
   378	// 프린터 테스트
   379	// ─── 업데이트 (창의 띠 · 「Buscar actualización」 / 「Actualizar ahora」) ─────
   380	ipcMain.handle('update:estado', () => (updaterRef ? updaterRef.estado() : updateEstado));
   381	ipcMain.handle('update:buscar', () => (updaterRef ? updaterRef.buscar() : updateEstado));
   382	ipcMain.handle('update:instalar', () => (updaterRef ? updaterRef.instalarAhora() : { ok: false, motivo: 'No disponible' }));
   383	
   384	ipcMain.handle('printer:test', () => printTest());
   385	
   386	// USB 프린터 목록 조회
   387	ipcMain.handle('printer:listUsb', () => listUsbPrinters());
   388	
   389	// 출력 모드 목록 (4종)
   390	ipcMain.handle('label:presets', () => {
  ✓ sin descarga → nada
  ✓ a mano: cualquier hora (la espera de impresiones la hace esperarQuieto)
  ✓ envolver cuenta el trabajo en curso y lo suelta también si falla
  ✓ ★ quieto hace rato → true en el acto, con la puerta CERRADA
  ✓ ★ espera la impresión en curso y después el ACK (12 s)
  ✓ ★ trabajo que llega con la puerta cerrada: imprime primero (no se pierde)
  ✓ plazo vencido → false y la puerta queda ABIERTA (el agente sigue imprimiendo)
  ✓ ★ nunca se instala solo: ni al salir, ni de madrugada, ni al cerrar
  ✓ ★ «Salir» espera la impresión en curso y no instala
  ✓ ★ toda llamada a la impresora pasa por el contador
  ✓ la ventana tiene la franja y el puente IPC
update-policy: 11 pasaron
  ✓ sin descarga → nada
  ✓ a mano: cualquier hora (la espera de impresiones la hace esperarQuieto)
  ✓ envolver cuenta el trabajo en curso y lo suelta también si falla
  ✓ ★ quieto hace rato → true en el acto, con la puerta CERRADA
  ✓ ★ espera la impresión en curso y después el ACK (12 s)
  ✓ ★ trabajo que llega con la puerta cerrada: imprime primero (no se pierde)
  ✓ plazo vencido → false y la puerta queda ABIERTA (el agente sigue imprimiendo)
  ✓ ★ nunca se instala solo: ni al salir, ni de madrugada, ni al cerrar
  ✓ ★ «Salir» espera la impresión en curso y no instala
  ✓ ★ toda llamada a la impresora pasa por el contador
  ✓ la ventana tiene la franja y el puente IPC
update-policy: 11 pasaron

hook: PostToolUse
hook: PostToolUse
hook: PostToolUse Failed
hook: PostToolUse Completed
codex
[MEDIUM] `print-agent/src/updater.js:159` y `renderer/update-banner.js:54` — El botón queda inutilizado si vence la espera de impresión

Escenario: la persona acepta, pero continúan llegando trabajos durante 2 minutos. `instalar()` devuelve `false`, aunque `instalarAhora()` ya respondió `{ ok: true }`. La ventana muestra “Instalando…” y deja el botón deshabilitado permanentemente; sólo puede reintentar desde la bandeja.

Arreglo: hacer `instalarAhora` asíncrona y retornar el resultado de `await instalar(true)`. Si falla, devolver `{ ok:false, motivo:... }` para rehabilitar el botón. Aplica también a `zebra-agent`.

[LOW] `print-agent/src/updater.js:192` — Error del diálogo completamente silenciado

Escenario: `showMessageBox()` falla; no aparece la pregunta y tampoco queda registro del motivo.

Arreglo: registrar el error en el `catch`, sin iniciar instalación.

No encontré una ruta que instale sin aceptación: `autoInstallOnAppQuit=false`, se eliminó la instalación nocturna y `quitAndInstall()` sigue protegido por `esperarQuieto()`. Los smoke tests pasan en ambos agentes.
hook: Stop
hook: Stop
hook: Stop Failed
hook: Stop Completed
tokens used
44,002
[MEDIUM] `print-agent/src/updater.js:159` y `renderer/update-banner.js:54` — El botón queda inutilizado si vence la espera de impresión

Escenario: la persona acepta, pero continúan llegando trabajos durante 2 minutos. `instalar()` devuelve `false`, aunque `instalarAhora()` ya respondió `{ ok: true }`. La ventana muestra “Instalando…” y deja el botón deshabilitado permanentemente; sólo puede reintentar desde la bandeja.

Arreglo: hacer `instalarAhora` asíncrona y retornar el resultado de `await instalar(true)`. Si falla, devolver `{ ok:false, motivo:... }` para rehabilitar el botón. Aplica también a `zebra-agent`.

[LOW] `print-agent/src/updater.js:192` — Error del diálogo completamente silenciado

Escenario: `showMessageBox()` falla; no aparece la pregunta y tampoco queda registro del motivo.

Arreglo: registrar el error en el `catch`, sin iniciar instalación.

No encontré una ruta que instale sin aceptación: `autoInstallOnAppQuit=false`, se eliminó la instalación nocturna y `quitAndInstall()` sigue protegido por `esperarQuieto()`. Los smoke tests pasan en ambos agentes.
