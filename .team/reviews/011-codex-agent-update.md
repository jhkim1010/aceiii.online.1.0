Reading additional input from stdin...
2026-10-06T17:16:07.342141Z ERROR codex_models_manager::cache: failed to load models cache: missing field `base_instructions` at line 140 column 5
OpenAI Codex v0.146.0
--------
workdir: /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
model: gpt-5.6-sol
provider: openai
approval: never
sandbox: workspace-write [workdir, /tmp, $TMPDIR]
reasoning effort: none
reasoning summaries: none
session id: 01a11237-2ad9-7421-a8a3-7238d2da67c5
--------
user
Revisá este cambio (Electron print-agent y zebra-agent, auto-actualización con electron-updater, NSIS oneClick perMachine=false). Objetivo: que las tiendas que dejan el agente prendido todo el día reciban las actualizaciones: instalación automática 03-06 h hora local si no hay impresión en curso y 10 min sin imprimir; botón «Actualizar ahora» en la ventana; «Salir» instala si hay descarga (antes app.exit no disparaba quit). Regla dura: nunca reiniciar durante una impresión, nunca imprimir dos veces. Buscá bugs concretos (archivo:línea, problema, escenario, arreglo). Responde en español, breve. Archivos nuevos:
=== print-agent/src/update-policy.js
// src/update-policy.js — ¿cuándo se puede reiniciar el agente para instalar una actualización?
// (mismo archivo en print-agent y zebra-agent)
//
// ★ Por qué existe (실측 2026-10-06): la descarga ya andaba, pero la instalación sólo
//   ocurría «al salir del agente». Las tiendas lo dejan prendido todo el día y el «Salir»
//   de la bandeja usaba app.exit(), que **no** dispara 'quit' → autoInstallOnAppQuit nunca
//   corría. Resultado: print 1.2.5/1.2.6 en la calle con 1.2.10 publicado, zebra 1.0.28/1.0.30
//   con 1.0.32.
//
// ★ Regla dura: nunca reiniciar con una impresión en curso (un reinicio a mitad de un
//   trabajo puede perderlo o, si el servidor lo reenvía, imprimirlo dos veces).

// Ventana de instalación automática, en hora LOCAL de la PC de la tienda: [desde, hasta)
const VENTANA_DESDE = 3;
const VENTANA_HASTA = 6;

// Sin imprimir nada durante este tiempo = el agente está quieto
const QUIETO_MS = 10 * 60 * 1000;

/**
 * Instalación automática (sin que nadie toque nada).
 * @returns {{ ok: boolean, motivo?: string }}
 */
function puedeInstalarSolo({ listo, ahora, enCurso, ultimaActividad }) {
  if (!listo) return { ok: false, motivo: 'sin-descarga' };

  const hora = new Date(ahora).getHours();
  if (hora < VENTANA_DESDE || hora >= VENTANA_HASTA) return { ok: false, motivo: 'fuera-de-horario' };

  if (enCurso > 0) return { ok: false, motivo: 'imprimiendo' };

  if (ahora - (ultimaActividad || 0) < QUIETO_MS) return { ok: false, motivo: 'actividad-reciente' };

  return { ok: true };
}

/**
 * Botón «Actualizar ahora»: lo pide una persona, así que no importa la hora,
 * pero tampoco se corta una impresión en curso.
 */
function puedeInstalarAMano({ listo, enCurso }) {
  if (!listo) return { ok: false, motivo: 'sin-descarga' };
  if (enCurso > 0) return { ok: false, motivo: 'imprimiendo' };

  return { ok: true };
}

/**
 * Cuenta los trabajos de impresión en curso. `envolver(fn)` devuelve una función que
 * marca inicio y fin (también si falla) — se aplica a la llamada que toca la impresora.
 */
function crearActividad(reloj = () => Date.now()) {
  const estado = { enCurso: 0, ultimaActividad: 0 };

  const envolver = (fn) => async (...args) => {
    estado.enCurso += 1;
    estado.ultimaActividad = reloj();
    try {
      return await fn(...args);
    } finally {
      estado.enCurso -= 1;
      estado.ultimaActividad = reloj();
    }
  };

  return { estado, envolver };
}

module.exports = {
  puedeInstalarSolo,
  puedeInstalarAMano,
  crearActividad,
  VENTANA_DESDE,
  VENTANA_HASTA,
  QUIETO_MS,
};
=== print-agent/src/updater.js
// src/updater.js — electron-updater 기반 자동 업데이트 (Windows 전용)
// (print-agent · zebra-agent 동일 파일 — feed 이름만 다르다)
//
// 동작 원리:
//   1) 부팅 10초 후 + 이후 4시간마다 publish URL(고정 롤링 릴리즈)의 latest.yml 확인
//   2) 새 버전 발견 → 백그라운드 다운로드 (SHA512 검증 포함)
//   3) 설치 — 세 경로:
//      · 새벽 03–06시(PC 현지 시각) + 인쇄 0건 + 10분간 인쇄 없음 → 조용히 재시작·설치
//      · 창의 「Actualizar ahora」 / 트레이 메뉴 → 인쇄 중이 아니면 즉시
//      · 트레이 「Salir」 → 다운로드돼 있으면 설치하고 종료
//   ★ 종전엔 3)이 「앱 종료 시」 하나뿐이었는데 「Salir」가 app.exit() 라 quit 이벤트가
//     안 나서 **한 번도 설치되지 않았다**(update-policy.js 머리 주석 실측 참고).
//
// 스킵 조건:
//   - dev 모드 / 미패키징 (app.isPackaged === false)
//   - macOS/Linux (코드서명 없어 자동 업데이트 불가 — 매장 PC 는 Windows)
//   스킵돼도 컨트롤러는 돌려준다(화면이 「Windows 설치본에서만」 을 표시한다).
const { app } = require('electron');
const { puedeInstalarSolo, puedeInstalarAMano } = require('./update-policy');

// 4시간마다 재확인 — 매장 영업 중 하루 2~3회 체크 수준
const CHECK_INTERVAL_MS = 4 * 60 * 60 * 1000;

// 부팅 직후는 WebSocket 연결 등과 겹치지 않도록 10초 지연
const FIRST_CHECK_DELAY_MS = 10 * 1000;

// 새벽 자동 설치 조건을 보는 주기
const INSTALL_TICK_MS = 5 * 60 * 1000;

const MOTIVO_TEXTO = {
  'sin-descarga': 'Todavía no hay una actualización descargada',
  imprimiendo: 'Hay una impresión en curso — probá de nuevo en unos segundos',
};

/**
 * 자동 업데이트 초기화.
 * @param {object}   opts
 * @param {string}   opts.feed       로그 표시용 feed 이름
 * @param {object}   opts.actividad  update-policy.crearActividad() 의 결과 (인쇄 진행 추적)
 * @param {Function} opts.onLog      로그 콜백 (broadcastLog)
 * @param {Function} opts.onEstado   상태 변경 콜백 (estado) — 트레이·창 갱신용
 * @returns {object} 컨트롤러 { estado, buscar, instalarAhora, instalarAlSalir }
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
    instalacionAuto: 'Automática entre las 3 y las 6 h, sin impresiones en curso',
  };

  const cambiar = (parcial) => {
    Object.assign(st, parcial);
    avisar({ ...st });
  };

  const sinActualizador = {
    estado: () => ({ ...st }),
    buscar: async () => ({ ...st }),
    instalarAhora: () => ({ ok: false, motivo: 'Sólo disponible en la versión instalada de Windows' }),
    instalarAlSalir: () => false,
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

  // 안전망으로 남긴다 — 정상 quit 경로(설치 프로그램·OS 재시작 등)에서는 여전히 설치된다
  autoUpdater.autoInstallOnAppQuit = true;
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
    log(`🔄 Actualización v${info.version} lista — se instalará sola de madrugada o con «Actualizar ahora»`);
    cambiar({ fase: 'listo', nueva: info.version, progreso: 100 });
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

  // isSilent=true: 설치 창 없이 / isForceRunAfter: 설치 후 다시 띄울지
  const instalar = (volverAAbrir) => {
    log(`🔄 Reiniciando para instalar v${st.nueva}...`);
    setImmediate(() => autoUpdater.quitAndInstall(true, volverAAbrir));
  };

  const instalarAhora = () => {
    const r = puedeInstalarAMano({ listo: st.fase === 'listo', enCurso: actividad?.estado.enCurso || 0 });
    if (!r.ok) return { ok: false, motivo: MOTIVO_TEXTO[r.motivo] || r.motivo };
    instalar(true);

    return { ok: true };
  };

  // 트레이 「Salir」: 다운로드돼 있고 인쇄 중이 아니면 설치하고 끝낸다(다시 띄우지 않음)
  const instalarAlSalir = () => {
    const r = puedeInstalarAMano({ listo: st.fase === 'listo', enCurso: actividad?.estado.enCurso || 0 });
    if (!r.ok) return false;
    instalar(false);

    return true;
  };

  const vigilar = () => {
    const r = puedeInstalarSolo({
      listo: st.fase === 'listo',
      ahora: Date.now(),
      enCurso: actividad?.estado.enCurso || 0,
      ultimaActividad: actividad?.estado.ultimaActividad || 0,
    });
    if (r.ok) {
      log('🌙 Instalación automática de madrugada (sin impresiones en curso)');
      instalar(true);
    }
  };

  setTimeout(buscar, FIRST_CHECK_DELAY_MS);
  setInterval(buscar, CHECK_INTERVAL_MS);
  setInterval(vigilar, INSTALL_TICK_MS);

  console.log('[updater] initialized — feed:', feed);

  return { estado: () => ({ ...st }), buscar, instalarAhora, instalarAlSalir };
}

module.exports = { initAutoUpdater };
=== print-agent/renderer/update-banner.js
// renderer/update-banner.js — franja de actualización arriba de la ventana
// (mismo archivo en print-agent y zebra-agent)
//
// Muestra la versión instalada y el estado de la actualización:
//   al día · buscando · descargando N% · lista (botón «Actualizar ahora») · error (reintentar)
// La instalación sola ocurre de madrugada sin impresiones en curso (src/update-policy.js).
(function updateBanner() {
  const api = window.electronAPI;
  if (!api || typeof api.getUpdateEstado !== 'function') return;

  const css = document.createElement('style');
  css.textContent = `
    #upd-banner { display:flex; align-items:center; gap:10px; padding:6px 12px; margin:0 0 8px;
      font-size:12px; color:#9a9cb8; background:#16162a; border:1px solid #2a2a4a; border-radius:8px; }
    #upd-banner.listo { color:#1a1a2e; background:#f5a623; border-color:#f5a623; font-weight:600; }
    #upd-banner.error { color:#ffb4a8; border-color:#5a2a2a; }
    #upd-banner .upd-txt { flex:1; min-width:0; }
    #upd-banner button { font-size:12px; padding:3px 10px; border-radius:6px; cursor:pointer;
      border:1px solid #3a3a5a; background:#22223a; color:#e0e0e0; }
    #upd-banner.listo button { background:#1a1a2e; color:#f5a623; border-color:#1a1a2e; }
    #upd-banner button:disabled { opacity:.5; cursor:default; }
  `;
  document.head.appendChild(css);

  const el = document.createElement('div');
  el.id = 'upd-banner';
  el.innerHTML = '<span class="upd-txt"></span><button type="button"></button>';
  const contenedor = document.querySelector('.container') || document.body;
  contenedor.insertBefore(el, contenedor.firstChild);

  const txt = el.querySelector('.upd-txt');
  const btn = el.querySelector('button');
  let aviso = null; // mensaje temporal tras un clic (p.ej. «hay una impresión en curso»)

  const hace = (ms) => {
    if (!ms) return '';
    const min = Math.round((Date.now() - ms) / 60000);

    return min < 1 ? ' · recién' : min < 60 ? ` · hace ${min} min` : ` · hace ${Math.round(min / 60)} h`;
  };

  const pintar = (e) => {
    if (!e) return;
    el.className = e.fase === 'listo' ? 'listo' : e.fase === 'error' ? 'error' : '';
    btn.style.display = '';
    btn.disabled = false;

    if (!e.disponible) {
      txt.textContent = `v${e.actual} · actualización automática sólo en la versión instalada de Windows`;
      btn.style.display = 'none';
    } else if (e.fase === 'listo') {
      txt.textContent = `Nueva versión v${e.nueva} lista (tenés v${e.actual}) · se instala sola de madrugada si no hay impresiones`;
      btn.textContent = 'Actualizar ahora';
      btn.onclick = async () => {
        btn.disabled = true;
        const r = await api.instalarUpdate();
        if (!r || !r.ok) {
          aviso = (r && r.motivo) || 'No se pudo actualizar';
          txt.textContent = aviso;
          setTimeout(() => { aviso = null; api.getUpdateEstado().then(pintar); }, 4000);
          btn.disabled = false;
        } else {
          txt.textContent = `Reiniciando para instalar v${e.nueva}...`;
        }
      };
    } else if (e.fase === 'descargando') {
      txt.textContent = `Descargando v${e.nueva}... ${e.progreso ?? 0}% (tenés v${e.actual})`;
      btn.style.display = 'none';
    } else if (e.fase === 'buscando') {
      txt.textContent = `v${e.actual} · buscando actualización...`;
      btn.textContent = 'Buscar actualización';
      btn.disabled = true;
    } else if (e.fase === 'error') {
      txt.textContent = `v${e.actual} · no se pudo comprobar actualizaciones${hace(e.ultimaBusqueda)}`;
      btn.textContent = 'Reintentar';
      btn.onclick = () => { btn.disabled = true; api.buscarUpdate().then(pintar); };
    } else {
      txt.textContent = `v${e.actual}${e.fase === 'al-dia' ? ' · al día' + hace(e.ultimaBusqueda) : ''}`;
      btn.textContent = 'Buscar actualización';
      btn.onclick = () => { btn.disabled = true; api.buscarUpdate().then(pintar); };
    }

    if (aviso) txt.textContent = aviso;
  };

  api.getUpdateEstado().then(pintar).catch(() => {});
  if (typeof api.onUpdateEstado === 'function') api.onUpdateEstado(pintar);
})();
=== DIFF
diff --git a/print-agent/main.js b/print-agent/main.js
index 2142106..be80ca0 100644
--- a/print-agent/main.js
+++ b/print-agent/main.js
@@ -6,16 +6,24 @@ const fs = require('fs');
 const os = require('os');
 const Store = require('electron-store');
 const printDedup = require('./src/print-dedup');
-const { printTicket }       = require('./src/print-pipeline');
+const { printTicket: printTicketSinContar } = require('./src/print-pipeline');
 const { formatFiscalHtml }  = require('./src/fiscal-formatter');
 const { formatQrHtml }      = require('./src/qr-formatter');
 const { formatTempTicketHtml, formatInvoiceHtml } = require('./src/formatter');
-const { renderHtmlToPng }   = require('./src/renderer-engine');
+const { renderHtmlToPng: renderHtmlToPngSinContar } = require('./src/renderer-engine');
 const ticketSettings        = require('./src/ticket-settings');
-const { printImage, testConnection: testPrinterConnection } = require('./src/printer');
+const { printImage: printImageSinContar, testConnection: testPrinterConnection } = require('./src/printer');
 const { discoverPrinters: discoverPrintersImpl } = require('./src/printer-discovery');
 const { listSystemPrinters } = require('./src/win-printer');
 const { initAutoUpdater }    = require('./src/updater');
+const { crearActividad }     = require('./src/update-policy');
+
+// 인쇄 진행 추적 — 업데이트 재시작은 인쇄 중엔 절대 하지 않는다(update-policy.js).
+// 프린터에 닿는 호출(렌더 → 출력)을 전부 이 래퍼로 감싼다.
+const actividadImpresion = crearActividad();
+const printTicket = actividadImpresion.envolver(printTicketSinContar);
+const printImage = actividadImpresion.envolver(printImageSinContar);
+const renderHtmlToPng = actividadImpresion.envolver(renderHtmlToPngSinContar);
 
 // ─── 개발 모드 감지 ─────────────────────────────────────────────────────────
 // `npm run dev` (= electron . --dev) 실행 시 process.argv 에 '--dev' 가 포함됨.
@@ -128,7 +136,7 @@ let displacedByDuplicate = false;
 
 // 자동 업데이트 상태 — 다운로드 완료 시 트레이에 수동 설치 메뉴 노출용
 let updaterRef = null;
-let updateReadyVersion = null;
+let updateEstado = null;
 
 // ─── 중복 실행 방지 — 두 번째 인스턴스는 기존 창을 앞으로 가져오고 종료 ─────
 // ★ 같은 PC 에서 두 번 뜨면(자동 시작 + 바탕화면 더블클릭) 둘이 **같은 API Key** 로
@@ -180,12 +188,17 @@ app.whenReady().then(() => {
 
   // ─── 자동 업데이트 (Windows packaged 전용 — dev/mac 은 내부에서 스킵) ──────
   updaterRef = initAutoUpdater({
+    feed: 'print-agent-latest (generic)',
+    actividad: actividadImpresion,
     onLog: broadcastLog,
-    onUpdateDownloaded: (info) => {
-      updateReadyVersion = info?.version || null;
-      updateTrayMenu(); // "Reiniciar y actualizar" 메뉴 노출
+    onEstado: (estado) => {
+      const antes = updateEstado?.fase;
+      updateEstado = estado;
+      if (antes !== estado.fase) updateTrayMenu(); // "Actualizar ahora" 메뉴 노출
+      if (mainWindow && !mainWindow.isDestroyed()) mainWindow.webContents.send('update-estado', estado);
     },
   });
+  updateEstado = updaterRef.estado();
 });
 
 // 모든 창 닫혀도 앱 종료하지 않음 (트레이 상주)
@@ -242,12 +255,13 @@ function updateTrayMenu() {
     : [];
 
   // 업데이트 다운로드 완료 시 수동 설치 메뉴 (미완료 시 빈 배열)
-  const updateItems = updateReadyVersion
+  const updateItems = updateEstado?.fase === 'listo'
     ? [
         {
-          label: `🔄 Reiniciar y actualizar a v${updateReadyVersion}`,
+          label: `🔄 Actualizar ahora a v${updateEstado.nueva}`,
           click: () => {
-            if (updaterRef) updaterRef.quitAndInstall(false, true);
+            const r = updaterRef ? updaterRef.instalarAhora() : { ok: false };
+            if (!r.ok && r.motivo) broadcastLog(`⚠️ ${r.motivo}`);
           },
         },
         { type: 'separator' },
@@ -263,12 +277,19 @@ function updateTrayMenu() {
     { label: 'Imprimir test', click: () => printTest() },
     { label: 'Ver log', click: openLogWindow },
     { type: 'separator' },
-    { label: 'Salir', click: () => app.exit(0) },
+    { label: 'Salir', click: salir },
   ]);
 
   tray.setContextMenu(contextMenu);
 }
 
+// 「Salir」: 업데이트가 받아져 있으면 설치하고 끝낸다.
+// ★ 종전 app.exit(0) 는 'quit' 이벤트를 내지 않아 autoInstallOnAppQuit 가 한 번도 안 돌았다.
+function salir() {
+  if (updaterRef && updaterRef.instalarAlSalir()) return;
+  app.exit(0);
+}
+
 // 연결 상태 변경 시 트레이 아이콘 업데이트
 function setConnectionStatus(status) {
   connectionStatus = status;
@@ -526,6 +547,11 @@ ipcMain.handle('setup:complete', () => {
 });
 
 // 프린터 테스트 출력 (Phase 11-02에서 구현)
+// ─── 업데이트 (창의 띠 · 「Buscar actualización」 / 「Actualizar ahora」) ─────
+ipcMain.handle('update:estado', () => (updaterRef ? updaterRef.estado() : updateEstado));
+ipcMain.handle('update:buscar', () => (updaterRef ? updaterRef.buscar() : updateEstado));
+ipcMain.handle('update:instalar', () => (updaterRef ? updaterRef.instalarAhora() : { ok: false, motivo: 'No disponible' }));
+
 ipcMain.handle('printer:test', () => printTest());
 
 // ── 티켓 미리보기 — 프린터/Snagit 없이 렌더 결과 PNG 를 바로 확인 ──────────────
diff --git a/print-agent/preload.js b/print-agent/preload.js
index 5edc86e..efd9b89 100644
--- a/print-agent/preload.js
+++ b/print-agent/preload.js
@@ -52,6 +52,12 @@ contextBridge.exposeInMainWorld('electronAPI', {
   // 프로파일 전환 (WebSocket 재연결 포함)
   switchProfile: (profileId) => ipcRenderer.invoke('profile:switch', profileId),
 
+  // 업데이트 — 창 상단 띠 (renderer/update-banner.js)
+  getUpdateEstado: () => ipcRenderer.invoke('update:estado'),
+  buscarUpdate: () => ipcRenderer.invoke('update:buscar'),
+  instalarUpdate: () => ipcRenderer.invoke('update:instalar'),
+  onUpdateEstado: (cb) => ipcRenderer.on('update-estado', (_e, estado) => cb(estado)),
+
   // 이벤트 수신 (main → renderer)
   onConnectionStatus: (cb) => ipcRenderer.on('connection-status', (_e, s) => cb(s)),
   onPrintLog: (cb) => ipcRenderer.on('print-log', (_e, entry) => cb(entry)),
diff --git a/zebra-agent/main.js b/zebra-agent/main.js
index 98bb4cf..24f0e98 100644
--- a/zebra-agent/main.js
+++ b/zebra-agent/main.js
@@ -10,7 +10,13 @@ const {
   formatQrLabelConAvisos, zplADibujo, qrLotePreview, filasDeLoteQrTotal, qrLoteFilas,
 } = require('./src/zpl-formatter');
 const { prepareItems: prepareItemsPure } = require('./src/price-select');
-const { sendZpl, testConnection: testPrinterConnection, listUsbPrinters } = require('./src/zebra-printer');
+const { sendZpl: sendZplSinContar, testConnection: testPrinterConnection, listUsbPrinters } = require('./src/zebra-printer');
+const { crearActividad } = require('./src/update-policy');
+
+// 인쇄 진행 추적 — 업데이트 재시작은 인쇄 중엔 절대 하지 않는다(update-policy.js).
+// 프린터에 닿는 호출(sendZpl)을 전부 이 래퍼로 감싼다.
+const actividadImpresion = crearActividad();
+const sendZpl = actividadImpresion.envolver(sendZplSinContar);
 const { discoverPrinters: discoverPrintersImpl } = require('./src/printer-discovery');
 const { initAutoUpdater } = require('./src/updater');
 
@@ -163,7 +169,7 @@ let displacedByDuplicate = false;
 
 // 자동 업데이트 상태 — 다운로드 완료 시 트레이에 수동 설치 메뉴 노출용
 let updaterRef = null;
-let updateReadyVersion = null;
+let updateEstado = null;
 
 // ─── 중복 실행 방지 — 두 번째 인스턴스는 기존 창을 앞으로 가져오고 종료 ─────
 const gotSingleLock = app.requestSingleInstanceLock();
@@ -209,12 +215,17 @@ app.whenReady().then(() => {
 
   // ─── 자동 업데이트 (Windows packaged 전용 — dev/mac 은 내부에서 스킵) ──────
   updaterRef = initAutoUpdater({
+    feed: 'zebra-agent-latest (generic)',
+    actividad: actividadImpresion,
     onLog: broadcastLog,
-    onUpdateDownloaded: (info) => {
-      updateReadyVersion = info?.version || null;
-      updateTrayMenu(); // "Reiniciar y actualizar" 메뉴 노출
+    onEstado: (estado) => {
+      const antes = updateEstado?.fase;
+      updateEstado = estado;
+      if (antes !== estado.fase) updateTrayMenu(); // "Actualizar ahora" 메뉴 노출
+      if (mainWindow && !mainWindow.isDestroyed()) mainWindow.webContents.send('update-estado', estado);
     },
   });
+  updateEstado = updaterRef.estado();
 });
 
 app.on('window-all-closed', (e) => {
@@ -242,12 +253,13 @@ function updateTrayMenu() {
   }[connectionStatus] ?? '🔴 Desconectado';
 
   // 업데이트 다운로드 완료 시 수동 설치 메뉴 (미완료 시 빈 배열)
-  const updateItems = updateReadyVersion
+  const updateItems = updateEstado?.fase === 'listo'
     ? [
         {
-          label: `🔄 Reiniciar y actualizar a v${updateReadyVersion}`,
+          label: `🔄 Actualizar ahora a v${updateEstado.nueva}`,
           click: () => {
-            if (updaterRef) updaterRef.quitAndInstall(false, true);
+            const r = updaterRef ? updaterRef.instalarAhora() : { ok: false };
+            if (!r.ok && r.motivo) broadcastLog(`⚠️ ${r.motivo}`);
           },
         },
         { type: 'separator' },
@@ -261,12 +273,19 @@ function updateTrayMenu() {
     { label: 'Abrir configuración', click: openMainWindow },
     { label: 'Imprimir test', click: () => printTest() },
     { type: 'separator' },
-    { label: 'Salir', click: () => app.exit(0) },
+    { label: 'Salir', click: salir },
   ]);
 
   tray.setContextMenu(contextMenu);
 }
 
+// 「Salir」: 업데이트가 받아져 있으면 설치하고 끝낸다.
+// ★ 종전 app.exit(0) 는 'quit' 이벤트를 내지 않아 autoInstallOnAppQuit 가 한 번도 안 돌았다.
+function salir() {
+  if (updaterRef && updaterRef.instalarAlSalir()) return;
+  app.exit(0);
+}
+
 function setConnectionStatus(status) {
   connectionStatus = status;
   updateTrayMenu();
@@ -357,6 +376,11 @@ ipcMain.handle('setup:complete', () => {
 });
 
 // 프린터 테스트
+// ─── 업데이트 (창의 띠 · 「Buscar actualización」 / 「Actualizar ahora」) ─────
+ipcMain.handle('update:estado', () => (updaterRef ? updaterRef.estado() : updateEstado));
+ipcMain.handle('update:buscar', () => (updaterRef ? updaterRef.buscar() : updateEstado));
+ipcMain.handle('update:instalar', () => (updaterRef ? updaterRef.instalarAhora() : { ok: false, motivo: 'No disponible' }));
+
 ipcMain.handle('printer:test', () => printTest());
 
 // USB 프린터 목록 조회
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
변경된 두 에이전트의 실제 호출 경로와 종료·인쇄 경합을 확인하겠습니다. 파일은 수정하지 않고, 구체적으로 재현 가능한 문제만 짧게 보고하겠습니다. 저장소 규칙에 따라 최종 답변은 한국어로 작성하되, 요청하신 `archivo:línea / problema / escenario / arreglo` 형식을 따르겠습니다.
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
exec
/bin/zsh -lc "sed -n '1,240p' .team/REVIEW-PROTOCOL.md && rg -n \"printTicket|printImage|renderHtmlToPng|sendZpl|quitAndInstall|app\\.exit|before-quit|will-quit|update-banner|crearActividad\" print-agent zebra-agent --glob '"'!node_modules/**'"'" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
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
print-agent/src/qr-formatter.js:3:// renderHtmlToPng(html, 576) → printImage 파이프라인용 (fiscal 패턴 동일).
zebra-agent/src/update-policy.js:6://   de la bandeja usaba app.exit(), que **no** dispara 'quit' → autoInstallOnAppQuit nunca
zebra-agent/src/update-policy.js:52:function crearActividad(reloj = () => Date.now()) {
zebra-agent/src/update-policy.js:72:  crearActividad,
print-agent/src/ticket-settings.js:5: * - 모든 출력물(invoice/fiscal/temp/qr/test)은 renderHtmlToPng() 를 거치므로
zebra-agent/main.js:13:const { sendZpl: sendZplSinContar, testConnection: testPrinterConnection, listUsbPrinters } = require('./src/zebra-printer');
zebra-agent/main.js:14:const { crearActividad } = require('./src/update-policy');
zebra-agent/main.js:17:// 프린터에 닿는 호출(sendZpl)을 전부 이 래퍼로 감싼다.
zebra-agent/main.js:18:const actividadImpresion = crearActividad();
zebra-agent/main.js:19:const sendZpl = actividadImpresion.envolver(sendZplSinContar);
zebra-agent/main.js:178:  app.exit(0);
zebra-agent/main.js:283:// ★ 종전 app.exit(0) 는 'quit' 이벤트를 내지 않아 autoInstallOnAppQuit 가 한 번도 안 돌았다.
zebra-agent/main.js:286:  app.exit(0);
zebra-agent/main.js:573:    const result = await sendZpl(zpl, printerCfg);
zebra-agent/main.js:704:// QR 라벨 출력 — 항목별 sendZpl(부분 실패 안전, D-11) → 성공분만 mark_qr_printed 스냅샷
zebra-agent/main.js:716:    const r = await sendZpl(zpl, printerCfg0);
zebra-agent/main.js:746:      const r = await sendZpl(zpl, printerCfg);
zebra-agent/main.js:1048:      const result = await sendZpl(zpl, printerCfg);
zebra-agent/main.js:1120:    const result = await sendZpl(testZpl, printerCfg);
print-agent/src/index.js:9:const { printReceipt, printImage, testConnection } = require('./printer');
print-agent/src/index.js:10:const { renderHtmlToPng } = require('./renderer-engine');
print-agent/src/index.js:71:// formatTempTicketHtml → renderHtmlToPng(576px) → printImage 파이프라인 (print-pipeline.js 동일 흐름)
print-agent/src/index.js:81:    const pngBuffer = await renderHtmlToPng(html, 576);
print-agent/src/index.js:84:    await printImage(pngBuffer, config.printer);
zebra-agent/src/zebra-printer.js:19:function sendZplNetwork(zplString, host, port = DEFAULT_PORT) {
zebra-agent/src/zebra-printer.js:85:function sendZplUsb(zplString, printerName) {
zebra-agent/src/zebra-printer.js:227:  return sendZplUsb('^XA^XZ', printerName).then(r => r.ok);
zebra-agent/src/zebra-printer.js:238:function sendZpl(zplString, config) {
zebra-agent/src/zebra-printer.js:241:    return sendZplNetwork(zplString, config);
zebra-agent/src/zebra-printer.js:245:    return sendZplUsb(zplString, config.printerName);
zebra-agent/src/zebra-printer.js:248:  return sendZplNetwork(zplString, config.host, config.port || DEFAULT_PORT);
zebra-agent/src/zebra-printer.js:271:  sendZpl,
zebra-agent/src/zebra-printer.js:274:  sendZplNetwork,
zebra-agent/src/zebra-printer.js:275:  sendZplUsb,
print-agent/src/renderer-engine.js:12: *   const { renderHtmlToPng } = require('./src/renderer-engine');
print-agent/src/renderer-engine.js:13: *   const pngBuffer = await renderHtmlToPng(htmlString, 576);
print-agent/src/renderer-engine.js:157:function renderHtmlToPng(html, width = 576, timeout = 10000, log = null) {
print-agent/src/renderer-engine.js:281:module.exports = { renderHtmlToPng, destroyRenderer };
print-agent/main.js:9:const { printTicket: printTicketSinContar } = require('./src/print-pipeline');
print-agent/main.js:13:const { renderHtmlToPng: renderHtmlToPngSinContar } = require('./src/renderer-engine');
print-agent/main.js:15:const { printImage: printImageSinContar, testConnection: testPrinterConnection } = require('./src/printer');
print-agent/main.js:19:const { crearActividad }     = require('./src/update-policy');
print-agent/main.js:23:const actividadImpresion = crearActividad();
print-agent/main.js:24:const printTicket = actividadImpresion.envolver(printTicketSinContar);
print-agent/main.js:25:const printImage = actividadImpresion.envolver(printImageSinContar);
print-agent/main.js:26:const renderHtmlToPng = actividadImpresion.envolver(renderHtmlToPngSinContar);
print-agent/main.js:32://   2) printer.js 의 printImage 가 실 프린터 대신 ~/Desktop/print-debug-*.png 로 저장 (PNG 미리보기 모드)
print-agent/main.js:149:  app.exit(0);
print-agent/main.js:287:// ★ 종전 app.exit(0) 는 'quit' 이벤트를 내지 않아 autoInstallOnAppQuit 가 한 번도 안 돌았다.
print-agent/main.js:290:  app.exit(0);
print-agent/main.js:558:// 실제 출력과 100% 동일한 파이프라인(formatInvoiceHtml → renderHtmlToPng, 폰트
print-agent/main.js:563:    const png  = await renderHtmlToPng(html, 576, 10000, broadcastLog);
print-agent/main.js:1166:      // 없으면 아래 printTicket (control ticket) path 그대로 — 비-AFIP 무회귀.
print-agent/main.js:1176:        const fiscalPng  = await renderHtmlToPng(fiscalHtml, 576, 10000, broadcastLog);
print-agent/main.js:1178:        await printImage(fiscalPng, printerCfg, broadcastLog);
print-agent/main.js:1192:      await printTicket(payload, printerCfg, broadcastLog);
print-agent/main.js:1236:      const png  = await renderHtmlToPng(html, 576, 10000, broadcastLog);
print-agent/main.js:1238:      await printImage(png, printerCfg, broadcastLog);
print-agent/main.js:1269:      const png = await renderHtmlToPng(html, 576, 10000, broadcastLog);
print-agent/main.js:1271:      await printImage(png, printerCfg, broadcastLog);
print-agent/main.js:1357:      console.log('[print_temp] → renderHtmlToPng()');
print-agent/main.js:1358:      const png = await renderHtmlToPng(html, 576, 10000, broadcastLog);
print-agent/main.js:1380:      console.log('[print_temp] → printImage()');
print-agent/main.js:1381:      await printImage(png, printerCfg, broadcastLog);
print-agent/main.js:1473:    await printTicket(sample, printerCfg, broadcastLog);
zebra-agent/src/updater.js:11://   ★ 종전엔 3)이 「앱 종료 시」 하나뿐이었는데 「Salir」가 app.exit() 라 quit 이벤트가
zebra-agent/src/updater.js:39: * @param {object}   opts.actividad  update-policy.crearActividad() 의 결과 (인쇄 진행 추적)
zebra-agent/src/updater.js:140:    setImmediate(() => autoUpdater.quitAndInstall(true, volverAAbrir));
print-agent/src/printer.js:13:// dev 일 때 printImage 는 실 프린터 대신 ~/Desktop/print-debug-*.png 로 저장.
print-agent/src/printer.js:232:const printImageNow = async (pngBuffer, printerConfig, log = () => {}) => {
print-agent/src/printer.js:240:        console.log(`[printImage:DEV] 🖼️  실 프린터 출력 스킵 — PNG 저장: ${filePath}`);
print-agent/src/printer.js:241:        console.log(`[printImage:DEV]    프린터 설정: ${JSON.stringify(printerConfig)}`);
print-agent/src/printer.js:252:    log(`🪟 [printImage] windows 드라이버 무음 인쇄 — device="${printerConfig.deviceName || '-'}"`);
print-agent/src/printer.js:253:    const { printImageSilent } = require('./win-printer');
print-agent/src/printer.js:255:    return printImageSilent(pngBuffer, printerConfig, log);
print-agent/src/printer.js:263:    log(`🔎 [printImage] preflight OK (${Date.now() - pfT}ms)`);
print-agent/src/printer.js:269:        `🔌 [printImage] 디바이스 생성 type=${printerConfig.type} ` +
print-agent/src/printer.js:278:          log(`❌ [printImage] 프린터 연결 실패 (${Date.now() - openT}ms): ${err.message}`);
print-agent/src/printer.js:282:        log(`🔗 [printImage] 프린터 연결 성공 (${Date.now() - openT}ms)`);
print-agent/src/printer.js:296:          log(`🖼️ [printImage] 이미지 로드 완료 size=${JSON.stringify(image ? image.size : null)}`);
print-agent/src/printer.js:297:          console.log('[printImage] image loaded, size=', image?.size);
print-agent/src/printer.js:308:              log('🟥 [printImage] 경고: 래스터 잉크 픽셀 0 — 빈 종이 확정(렌더 백지). 프린터 아닌 렌더 단계 문제');
print-agent/src/printer.js:310:              log(`🔬 [printImage] 래스터 잉크 픽셀=${inkCount} (0 이면 빈 종이)`);
print-agent/src/printer.js:313:            log(`🔬 [printImage] 잉크 측정 실패: ${inkErr.message}`);
print-agent/src/printer.js:322:              log(`📤 [printImage] 래스터 전송 완료 (${Date.now() - rasterT}ms) → feed/cut`);
print-agent/src/printer.js:327:                  log('✂️ [printImage] cut/close 완료');
print-agent/src/printer.js:332:              log(`❌ [printImage] 이미지 래스터 오류: ${imgErr.message}`);
print-agent/src/printer.js:336:          log(`❌ [printImage] 출력 중 오류: ${printError.message}`);
print-agent/src/printer.js:341:      log(`❌ [printImage] 디바이스 생성 실패: ${deviceError.message}`);
print-agent/src/printer.js:354:const printImage = (pngBuffer, printerConfig, log = () => {}) =>
print-agent/src/printer.js:355:  printQueue.run(() => printImageNow(pngBuffer, printerConfig, log));
print-agent/src/printer.js:357:module.exports = { printReceipt, printImage, testConnection };
print-agent/renderer/update-banner.js:1:// renderer/update-banner.js — franja de actualización arriba de la ventana
print-agent/src/print-pipeline.js:8: *   const { printTicket } = require('./src/print-pipeline');
print-agent/src/print-pipeline.js:9: *   await printTicket(invoiceData, printerConfig);
print-agent/src/print-pipeline.js:13:const { renderHtmlToPng }   = require('./renderer-engine');
print-agent/src/print-pipeline.js:14:const { printImage }        = require('./printer');
print-agent/src/print-pipeline.js:23:async function printTicket(data, printerCfg, log = () => {}) {
print-agent/src/print-pipeline.js:43:  const pngBuffer = await renderHtmlToPng(html, 576, 10000, log);
print-agent/src/print-pipeline.js:48:  await printImage(pngBuffer, printerCfg, log);
print-agent/src/print-pipeline.js:52:module.exports = { printTicket };
print-agent/src/update-policy.js:6://   de la bandeja usaba app.exit(), que **no** dispara 'quit' → autoInstallOnAppQuit nunca
print-agent/src/update-policy.js:52:function crearActividad(reloj = () => Date.now()) {
print-agent/src/update-policy.js:72:  crearActividad,
print-agent/renderer/index.html:873:  <script src="update-banner.js"></script>
print-agent/src/win-printer.js:13: *   const { listSystemPrinters, printImageSilent } = require('./win-printer');
print-agent/src/win-printer.js:80:function printImageSilent(pngBuffer, cfg = {}, log = () => {}) {
print-agent/src/win-printer.js:200:module.exports = { listSystemPrinters, printImageSilent };
print-agent/preload.js:55:  // 업데이트 — 창 상단 띠 (renderer/update-banner.js)
print-agent/src/updater.js:11://   ★ 종전엔 3)이 「앱 종료 시」 하나뿐이었는데 「Salir」가 app.exit() 라 quit 이벤트가
print-agent/src/updater.js:39: * @param {object}   opts.actividad  update-policy.crearActividad() 의 결과 (인쇄 진행 추적)
print-agent/src/updater.js:140:    setImmediate(() => autoUpdater.quitAndInstall(true, volverAAbrir));
print-agent/test/update-policy.smoke.js:6: *   app.exit() (no dispara 'quit'). En la calle: print 1.2.5/1.2.6 con 1.2.10 publicado.
print-agent/test/update-policy.smoke.js:13:  puedeInstalarSolo, puedeInstalarAMano, crearActividad, QUIETO_MS,
print-agent/test/update-policy.smoke.js:77:    const act = crearActividad(() => t);
print-agent/test/update-policy.smoke.js:100:  await it('★ «Salir» pasa por salir() (instala si hay descarga), no por app.exit directo', () => {
print-agent/test/update-policy.smoke.js:106:    const crudas = esZebra ? ['sendZplSinContar'] : ['printTicketSinContar', 'printImageSinContar', 'renderHtmlToPngSinContar'];
print-agent/test/update-policy.smoke.js:119:    assert.ok(html.includes('<script src="update-banner.js"></script>'));
print-agent/test/ticket-margin.smoke.js:88:  MOTOR.includes('function renderHtmlToPng') && MAIN.includes("ipcMain.handle('store:set'"));
zebra-agent/test/update-policy.smoke.js:6: *   app.exit() (no dispara 'quit'). En la calle: print 1.2.5/1.2.6 con 1.2.10 publicado.
zebra-agent/test/update-policy.smoke.js:13:  puedeInstalarSolo, puedeInstalarAMano, crearActividad, QUIETO_MS,
zebra-agent/test/update-policy.smoke.js:77:    const act = crearActividad(() => t);
zebra-agent/test/update-policy.smoke.js:100:  await it('★ «Salir» pasa por salir() (instala si hay descarga), no por app.exit directo', () => {
zebra-agent/test/update-policy.smoke.js:106:    const crudas = esZebra ? ['sendZplSinContar'] : ['printTicketSinContar', 'printImageSinContar', 'renderHtmlToPngSinContar'];
zebra-agent/test/update-policy.smoke.js:119:    assert.ok(html.includes('<script src="update-banner.js"></script>'));
zebra-agent/renderer/update-banner.js:1:// renderer/update-banner.js — franja de actualización arriba de la ventana
zebra-agent/preload.js:52:  // 업데이트 — 창 상단 띠 (renderer/update-banner.js)
zebra-agent/renderer/index.html:3290:  <script src="update-banner.js"></script>

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
/bin/zsh -lc "nl -ba print-agent/src/updater.js | sed -n '85,185p'; nl -ba print-agent/main.js | sed -n '270,300p'; nl -ba zebra-agent/main.js | sed -n '265,295p'; nl -ba print-agent/src/update-policy.js | sed -n '20,80p'; rg -n 'nsis|oneClick|perMachine|publish|electron-updater|autoUpdater' print-agent/package.json zebra-agent/package.json print-agent/electron-builder.yml zebra-agent/electron-builder.yml 2>/dev/null" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 exited 2 in 0ms:
    85	    return sinActualizador;
    86	  }
    87	
    88	  st.disponible = true;
    89	
    90	  autoUpdater.autoDownload = true;
    91	
    92	  // 안전망으로 남긴다 — 정상 quit 경로(설치 프로그램·OS 재시작 등)에서는 여전히 설치된다
    93	  autoUpdater.autoInstallOnAppQuit = true;
    94	  autoUpdater.allowDowngrade = false;
    95	
    96	  autoUpdater.on('checking-for-update', () => {
    97	    if (st.fase !== 'listo' && st.fase !== 'descargando') cambiar({ fase: 'buscando', error: null });
    98	  });
    99	
   100	  autoUpdater.on('update-not-available', () => {
   101	    if (st.fase !== 'listo') cambiar({ fase: 'al-dia', ultimaBusqueda: Date.now() });
   102	  });
   103	
   104	  autoUpdater.on('update-available', (info) => {
   105	    log(`⬇️ Actualización disponible: v${info.version} — descargando en segundo plano...`);
   106	    cambiar({ fase: 'descargando', nueva: info.version, progreso: 0, ultimaBusqueda: Date.now() });
   107	  });
   108	
   109	  autoUpdater.on('download-progress', (p) => {
   110	    const pct = Math.floor(p?.percent || 0);
   111	    if (pct !== st.progreso) cambiar({ fase: 'descargando', progreso: pct });
   112	  });
   113	
   114	  autoUpdater.on('update-downloaded', (info) => {
   115	    log(`🔄 Actualización v${info.version} lista — se instalará sola de madrugada o con «Actualizar ahora»`);
   116	    cambiar({ fase: 'listo', nueva: info.version, progreso: 100 });
   117	  });
   118	
   119	  autoUpdater.on('error', (err) => {
   120	    // 네트워크 불안정 등은 흔함 — 경고 로그만 남기고 다음 주기에 재시도
   121	    log(`⚠️ auto-update: ${err.message}`);
   122	    if (st.fase !== 'listo') cambiar({ fase: 'error', error: err.message, ultimaBusqueda: Date.now() });
   123	  });
   124	
   125	  const buscar = async () => {
   126	    if (st.fase === 'listo' || st.fase === 'descargando') return { ...st };
   127	    try {
   128	      await autoUpdater.checkForUpdates();
   129	    } catch (err) {
   130	      log(`⚠️ auto-update check: ${err.message}`);
   131	      cambiar({ fase: 'error', error: err.message, ultimaBusqueda: Date.now() });
   132	    }
   133	
   134	    return { ...st };
   135	  };
   136	
   137	  // isSilent=true: 설치 창 없이 / isForceRunAfter: 설치 후 다시 띄울지
   138	  const instalar = (volverAAbrir) => {
   139	    log(`🔄 Reiniciando para instalar v${st.nueva}...`);
   140	    setImmediate(() => autoUpdater.quitAndInstall(true, volverAAbrir));
   141	  };
   142	
   143	  const instalarAhora = () => {
   144	    const r = puedeInstalarAMano({ listo: st.fase === 'listo', enCurso: actividad?.estado.enCurso || 0 });
   145	    if (!r.ok) return { ok: false, motivo: MOTIVO_TEXTO[r.motivo] || r.motivo };
   146	    instalar(true);
   147	
   148	    return { ok: true };
   149	  };
   150	
   151	  // 트레이 「Salir」: 다운로드돼 있고 인쇄 중이 아니면 설치하고 끝낸다(다시 띄우지 않음)
   152	  const instalarAlSalir = () => {
   153	    const r = puedeInstalarAMano({ listo: st.fase === 'listo', enCurso: actividad?.estado.enCurso || 0 });
   154	    if (!r.ok) return false;
   155	    instalar(false);
   156	
   157	    return true;
   158	  };
   159	
   160	  const vigilar = () => {
   161	    const r = puedeInstalarSolo({
   162	      listo: st.fase === 'listo',
   163	      ahora: Date.now(),
   164	      enCurso: actividad?.estado.enCurso || 0,
   165	      ultimaActividad: actividad?.estado.ultimaActividad || 0,
   166	    });
   167	    if (r.ok) {
   168	      log('🌙 Instalación automática de madrugada (sin impresiones en curso)');
   169	      instalar(true);
   170	    }
   171	  };
   172	
   173	  setTimeout(buscar, FIRST_CHECK_DELAY_MS);
   174	  setInterval(buscar, CHECK_INTERVAL_MS);
   175	  setInterval(vigilar, INSTALL_TICK_MS);
   176	
   177	  console.log('[updater] initialized — feed:', feed);
   178	
   179	  return { estado: () => ({ ...st }), buscar, instalarAhora, instalarAlSalir };
   180	}
   181	
   182	module.exports = { initAutoUpdater };
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
   286	// 「Salir」: 업데이트가 받아져 있으면 설치하고 끝낸다.
   287	// ★ 종전 app.exit(0) 는 'quit' 이벤트를 내지 않아 autoInstallOnAppQuit 가 한 번도 안 돌았다.
   288	function salir() {
   289	  if (updaterRef && updaterRef.instalarAlSalir()) return;
   290	  app.exit(0);
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
   265	        { type: 'separator' },
   266	      ]
   267	    : [];
   268	
   269	  const contextMenu = Menu.buildFromTemplate([
   270	    ...updateItems,
   271	    { label: statusLabel, enabled: false },
   272	    { type: 'separator' },
   273	    { label: 'Abrir configuración', click: openMainWindow },
   274	    { label: 'Imprimir test', click: () => printTest() },
   275	    { type: 'separator' },
   276	    { label: 'Salir', click: salir },
   277	  ]);
   278	
   279	  tray.setContextMenu(contextMenu);
   280	}
   281	
   282	// 「Salir」: 업데이트가 받아져 있으면 설치하고 끝낸다.
   283	// ★ 종전 app.exit(0) 는 'quit' 이벤트를 내지 않아 autoInstallOnAppQuit 가 한 번도 안 돌았다.
   284	function salir() {
   285	  if (updaterRef && updaterRef.instalarAlSalir()) return;
   286	  app.exit(0);
   287	}
   288	
   289	function setConnectionStatus(status) {
   290	  connectionStatus = status;
   291	  updateTrayMenu();
   292	  if (mainWindow && !mainWindow.isDestroyed()) {
   293	    mainWindow.webContents.send('connection-status', status);
   294	  }
   295	}
    20	/**
    21	 * Instalación automática (sin que nadie toque nada).
    22	 * @returns {{ ok: boolean, motivo?: string }}
    23	 */
    24	function puedeInstalarSolo({ listo, ahora, enCurso, ultimaActividad }) {
    25	  if (!listo) return { ok: false, motivo: 'sin-descarga' };
    26	
    27	  const hora = new Date(ahora).getHours();
    28	  if (hora < VENTANA_DESDE || hora >= VENTANA_HASTA) return { ok: false, motivo: 'fuera-de-horario' };
    29	
    30	  if (enCurso > 0) return { ok: false, motivo: 'imprimiendo' };
    31	
    32	  if (ahora - (ultimaActividad || 0) < QUIETO_MS) return { ok: false, motivo: 'actividad-reciente' };
    33	
    34	  return { ok: true };
    35	}
    36	
    37	/**
    38	 * Botón «Actualizar ahora»: lo pide una persona, así que no importa la hora,
    39	 * pero tampoco se corta una impresión en curso.
    40	 */
    41	function puedeInstalarAMano({ listo, enCurso }) {
    42	  if (!listo) return { ok: false, motivo: 'sin-descarga' };
    43	  if (enCurso > 0) return { ok: false, motivo: 'imprimiendo' };
    44	
    45	  return { ok: true };
    46	}
    47	
    48	/**
    49	 * Cuenta los trabajos de impresión en curso. `envolver(fn)` devuelve una función que
    50	 * marca inicio y fin (también si falla) — se aplica a la llamada que toca la impresora.
    51	 */
    52	function crearActividad(reloj = () => Date.now()) {
    53	  const estado = { enCurso: 0, ultimaActividad: 0 };
    54	
    55	  const envolver = (fn) => async (...args) => {
    56	    estado.enCurso += 1;
    57	    estado.ultimaActividad = reloj();
    58	    try {
    59	      return await fn(...args);
    60	    } finally {
    61	      estado.enCurso -= 1;
    62	      estado.ultimaActividad = reloj();
    63	    }
    64	  };
    65	
    66	  return { estado, envolver };
    67	}
    68	
    69	module.exports = {
    70	  puedeInstalarSolo,
    71	  puedeInstalarAMano,
    72	  crearActividad,
    73	  VENTANA_DESDE,
    74	  VENTANA_HASTA,
    75	  QUIETO_MS,
    76	};
zebra-agent/package.json:10:    "build:win": "electron-builder --win --x64 --publish never",
zebra-agent/package.json:11:    "build:mac": "electron-builder --mac --x64 --arm64 --publish never",
zebra-agent/package.json:17:    "electron-updater": "^6.3.9"
zebra-agent/package.json:29:    "publish": {
zebra-agent/package.json:47:          "target": "nsis",
zebra-agent/package.json:63:    "nsis": {
zebra-agent/package.json:64:      "oneClick": true,
zebra-agent/package.json:65:      "perMachine": false,
print-agent/package.json:10:    "build:win": "electron-builder --win --x64 --publish never",
print-agent/package.json:11:    "build:mac": "electron-builder --mac --x64 --arm64 --publish never",
print-agent/package.json:16:    "electron-updater": "^6.3.9",
print-agent/package.json:33:    "publish": {
print-agent/package.json:53:          "target": "nsis",
print-agent/package.json:75:    "nsis": {
print-agent/package.json:76:      "oneClick": true,
print-agent/package.json:77:      "perMachine": false,

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
/bin/zsh -lc "nl -ba print-agent/main.js | sed -n '1120,1220p'; nl -ba print-agent/main.js | sed -n '1335,1415p'; nl -ba zebra-agent/main.js | sed -n '680,770p'; nl -ba zebra-agent/main.js | sed -n '1025,1070p'; sed -n '1,180p' print-agent/src/print-dedup.js; rg -n \"printDedup|mark.*print|emit\\(|ack|success|printed\" print-agent/main.js zebra-agent/main.js | tail -80" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
  1120	    //
  1121	    // ★ 이 이벤트는 두 갈래다: `payload.factura` 가 있으면 fiscal 경로로 가고
  1122	    //   그쪽은 `printFiscal` 로 다시 막힌다. 그 스위치까지 여기서 같이 본다 —
  1123	    //   안 그러면 printFiscal=false 인 상태에서 job 만 소비되고, 스위치를 켠 뒤
  1124	    //   재전송해도 안 나온다.
  1125	    const puertaAbierta = payload?.factura
  1126	      ? store.get('printFiscal')
  1127	      : store.get('printControl');
  1128	
  1129	    if (printerCfg?.type && puertaAbierta && !claimPrintJob('print_invoice', payload)) {
  1130	      return;
  1131	    }
  1132	    const start      = Date.now();
  1133	    const num        = payload?.invoice?.number || payload?.invoiceId || '?';
  1134	
  1135	    broadcastLog(`🖨 print_invoice #${num} — imprimiendo...`);
  1136	
  1137	    // ── 디버그: payload / printerCfg 요약 (운영 출력 오류 추적용) ──
  1138	    broadcastLog(
  1139	      `   ↳ payload: items=${Array.isArray(payload?.items) ? payload.items.length : '?'} ` +
  1140	        `branch=${payload?.branchId ?? '?'} invoiceId=${payload?.invoiceId ?? '?'}`,
  1141	    );
  1142	    console.log('[print_invoice] ← payload received', {
  1143	      invoiceId: payload?.invoiceId,
  1144	      branchId:  payload?.branchId,
  1145	      items:     Array.isArray(payload?.items) ? payload.items.length : undefined,
  1146	    });
  1147	
  1148	    // 프린터 설정 누락이면 파이프라인 진입 전에 명확히 실패 (원인 즉시 노출)
  1149	    if (!printerCfg || !printerCfg.type) {
  1150	      const msg = 'printer no configurado (setup wizard 미완료 또는 활성 프로파일 없음)';
  1151	      broadcastLog(`❌ print_invoice #${num} — ${msg}`);
  1152	      console.error('[print_invoice] ✗', msg, '— printerCfg=', printerCfg);
  1153	      wsConnection.emit('print_ack', {
  1154	        invoiceId: payload?.invoiceId,
  1155	        status:    'error',
  1156	        error:     msg,
  1157	        ts:        Date.now(),
  1158	      });
  1159	
  1160	      return;
  1161	    }
  1162	
  1163	    try {
  1164	      // ── AFIP 재정(fiscal) 분기 — WIRING GAP #1 (Phase 57 W1) ─────────────
  1165	      // payload.factura (shape D-02) 가 있으면 fiscal path 로 렌더 (letra/IVA/CAE/QR).
  1166	      // 없으면 아래 printTicket (control ticket) path 그대로 — 비-AFIP 무회귀.
  1167	      if (payload.factura) {
  1168	        if (!store.get('printFiscal')) {
  1169	          broadcastLog('ℹ️ print_invoice(fiscal) 무시 — printFiscal=false');
  1170	
  1171	          return;
  1172	        }
  1173	
  1174	        broadcastLog('🖨 print_invoice(fiscal) — renderizando comprobante AFIP...');
  1175	        const fiscalHtml = await formatFiscalHtml(payload.factura);
  1176	        const fiscalPng  = await renderHtmlToPng(fiscalHtml, 576, 10000, broadcastLog);
  1177	
  1178	        await printImage(fiscalPng, printerCfg, broadcastLog);
  1179	        const fiscalElapsed = Date.now() - start;
  1180	
  1181	        broadcastLog(`✅ print_invoice(fiscal) — OK (${fiscalElapsed}ms)`);
  1182	        wsConnection.emit('print_ack', {
  1183	          invoiceId: payload?.invoiceId,
  1184	          status:    'ok',
  1185	          ts:        Date.now(),
  1186	        });
  1187	
  1188	        return;
  1189	      }
  1190	
  1191	      // broadcastLog 를 파이프라인에 주입 → 각 단계가 메인창/콘솔에 실시간 표시
  1192	      await printTicket(payload, printerCfg, broadcastLog);
  1193	      const elapsed = Date.now() - start;
  1194	
  1195	      broadcastLog(`✅ print_invoice #${num} — OK (${elapsed}ms)`);
  1196	      wsConnection.emit('print_ack', {
  1197	        invoiceId: payload?.invoiceId,
  1198	        status:    'ok',
  1199	        ts:        Date.now(),
  1200	      });
  1201	    } catch (err) {
  1202	      // fire-and-forget: 출력 실패가 판매 트랜잭션에 영향 없도록 ack만 전송
  1203	      broadcastLog(`❌ print_invoice #${num} — ${err.message}`);
  1204	      console.error('[print_invoice] ✗ pipeline threw', {
  1205	        message: err?.message,
  1206	        stack:   err?.stack,
  1207	      });
  1208	      wsConnection.emit('print_ack', {
  1209	        invoiceId: payload?.invoiceId,
  1210	        status:    'error',
  1211	        error:     err.message,
  1212	        ts:        Date.now(),
  1213	      });
  1214	    }
  1215	  });
  1216	
  1217	  // ── AFIP 영수증 출력 ──────────────────────────────────────────────────────
  1218	  wsConnection.on('print_fiscal', async (payload) => {
  1219	    if (!store.get('printFiscal')) {
  1220	      broadcastLog('ℹ️ print_fiscal 무시 — printFiscal=false');
  1335	
  1336	    broadcastLog('🖨 print_temp — imprimiendo presupuesto...');
  1337	
  1338	    if (!printerCfg) {
  1339	      const msg = 'printer no configurado (setup wizard 미완료)';
  1340	
  1341	      console.error('[print_temp] ✗', msg);
  1342	      broadcastLog(`❌ print_temp — ${msg}`);
  1343	
  1344	      return;
  1345	    }
  1346	
  1347	    // ★ 프린터가 있다고 확인한 뒤에 작업을 소비한다 — 못 찍은 것을 «찍음» 으로
  1348	    //   기록하면 설정을 고치고 재전송해도 영영 안 나온다.
  1349	    if (!claimPrintJob('print_temp', payload)) return;
  1350	
  1351	    try {
  1352	      console.log('[print_temp] → formatTempTicketHtml()');
  1353	      const html = formatTempTicketHtml(payload);
  1354	
  1355	      console.log('[print_temp] html length =', html?.length);
  1356	
  1357	      console.log('[print_temp] → renderHtmlToPng()');
  1358	      const png = await renderHtmlToPng(html, 576, 10000, broadcastLog);
  1359	
  1360	      console.log('[print_temp] png bytes =', png?.length);
  1361	
  1362	      // ─── DEBUG(11-06): PNG 디스크 덤프 — dev 전용 (운영 디스크 누적 방지) ────
  1363	      // virtual-printer.js 는 GS v 0 래스터 바이트를 "[이미지 WxH]" 로만 치환하므로
  1364	      // 그래픽 모드 출력물을 눈으로 검증할 수 없음 → dev 에서만 PNG 원본을 덤프
  1365	      if (IS_DEV) {
  1366	        try {
  1367	          const dumpDir = path.join(os.tmpdir(), 'ventago-print');
  1368	
  1369	          fs.mkdirSync(dumpDir, { recursive: true });
  1370	          const dumpPath = path.join(dumpDir, `temp-${Date.now()}.png`);
  1371	
  1372	          fs.writeFileSync(dumpPath, png);
  1373	          console.log(`[print_temp] 💾 PNG 덤프 → ${dumpPath}`);
  1374	          broadcastLog(`💾 PNG 저장: ${dumpPath}`);
  1375	        } catch (dumpErr) {
  1376	          console.warn('[print_temp] PNG 덤프 실패:', dumpErr.message);
  1377	        }
  1378	      }
  1379	
  1380	      console.log('[print_temp] → printImage()');
  1381	      await printImage(png, printerCfg, broadcastLog);
  1382	      const elapsed = Date.now() - start;
  1383	
  1384	      console.log(`[print_temp] ✓ done in ${elapsed}ms`);
  1385	      broadcastLog(`✅ print_temp — OK (${elapsed}ms)`);
  1386	    } catch (err) {
  1387	      console.error('[print_temp] ✗ pipeline threw', {
  1388	        message: err?.message,
  1389	        stack:   err?.stack,
  1390	        name:    err?.name,
  1391	      });
  1392	      broadcastLog(`❌ print_temp — ${err.message}`);
  1393	    }
  1394	  });
  1395	}
  1396	
  1397	// ★ **한 인쇄 작업은 한 번만 인쇄된다** — 마지막 관문.
  1398	//
  1399	// 중복 배달은 여러 층에서 생긴다: 같은 POST 두 번, 클라우드와 엣지가 겹치는
  1400	// failover 순간, 소켓 재접속, 지점 브로드캐스트, 사용자의 더블클릭. 층마다 막아도
  1401	// 새 층이 생기면 다시 뚫린다. 여기서 「이미 찍은 작업」을 거절하면 어느 경로로 두 번
  1402	// 오든 종이는 한 장이다.
  1403	//
  1404	// jobId 가 없는 이벤트는 통과시킨다 — 구버전 서버/엣지와 섞여 돌기 때문이다.
  1405	function claimPrintJob(event, payload) {
  1406	  const jobId = payload?.printJobId;
  1407	
  1408	  if (printDedup.claimJob(jobId)) return true;
  1409	
  1410	  console.warn(`[${event}] DUPLICADO ignorado — printJobId=${jobId} ya impreso`);
  1411	  broadcastLog(`🚫 ${event} duplicado ignorado (job ${String(jobId).slice(-8)})`);
  1412	
  1413	  return false;
  1414	}
  1415	
   680	    return { ok: false, error: 'No conectado al servidor' };
   681	  }
   682	
   683	  const ptId = Number(priceTypeId);
   684	
   685	  if (!ptId) {
   686	    return { ok: false, error: 'Seleccioná un nivel de precio' };
   687	  }
   688	
   689	  try {
   690	    const res = await wsConnection.timeout(10000).emitWithAck('get_qr_pending', {
   691	      priceTypeId: ptId,
   692	      scope: scope === 'all' ? 'all' : 'delta',
   693	      q: String(q || '').trim(),
   694	    });
   695	
   696	    if (!res?.ok) return { ok: false, error: res?.error || 'Sin respuesta' };
   697	
   698	    return { ok: true, items: res.items || [] };
   699	  } catch (err) {
   700	    return { ok: false, error: err.message || 'Timeout' };
   701	  }
   702	});
   703	
   704	// QR 라벨 출력 — 항목별 sendZpl(부분 실패 안전, D-11) → 성공분만 mark_qr_printed 스냅샷
   705	ipcMain.handle('qr:print', async (_event, { items, layout, mode, priceTypeId, prueba } = {}) => {
   706	  // [v1.0.29] «Imprimir 1 de prueba»: sólo el primero, una vez, y SIN marcarlo como impreso
   707	  //   (la prueba no cuenta: si se marcara, desaparecería de «Cambios» sin haberse etiquetado).
   708	  if (prueba && Array.isArray(items) && items.length > 0) {
   709	    const printerCfg0 = store.get('printer');
   710	    if (!isPrinterConfigured(printerCfg0)) return { ok: false, error: 'Impresora no configurada' };
   711	    const it = items[0];
   712	    const zpl = formatQrLabel({
   713	      contenido: it.qrUrl, name: it.name, price: it.price, priceLabel: it.priceLabel,
   714	      layout: { ...(layout || {}), mode, ...getPrintSettings() },
   715	    });
   716	    const r = await sendZpl(zpl, printerCfg0);
   717	    broadcastLog(r.ok ? '🧪 1 etiqueta QR de prueba' : `❌ Prueba: ${r.error}`);
   718	
   719	    return { ok: r.ok, error: r.error, printed: 0, failed: r.ok ? 0 : 1, prueba: true };
   720	  }
   721	
   722	  const printerCfg = store.get('printer');
   723	  if (!isPrinterConfigured(printerCfg)) return { ok: false, error: 'Impresora no configurada' };
   724	
   725	  if (!Array.isArray(items) || items.length === 0) {
   726	    return { ok: false, error: 'Sin ítems para imprimir' };
   727	  }
   728	
   729	  const succeeded = [];
   730	  const failed = [];
   731	
   732	  // 항목별 출력 — 한 항목 실패가 배치 전체를 중단하지 않음
   733	  for (const item of items) {
   734	    try {
   735	      const zpl = formatQrLabel({
   736	        // ★ Esta pestaña manda el **enlace profundo** — lo escanea un cliente con el
   737	        //   teléfono. El lote de «por cantidad» manda el SKU, para el lector de la
   738	        //   tienda. Son dos usos distintos y por eso el parámetro ya no se llama qrUrl.
   739	        contenido: item.qrUrl,
   740	        name: item.name,
   741	        price: item.price,
   742	        priceLabel: item.priceLabel,
   743	        // 밀도/속도는 전역 설정 — QR 도 일반 라벨과 동일하게 적용
   744	        layout: { ...(layout || {}), mode, ...getPrintSettings() },
   745	      });
   746	      const r = await sendZpl(zpl, printerCfg);
   747	
   748	      if (r.ok) {
   749	        // 성공분만 스냅샷에 기록할 최소 필드 수집 (productId/price/name)
   750	        succeeded.push({ productId: item.productId, price: item.price, name: item.name });
   751	      } else {
   752	        failed.push({ productId: item.productId, error: r.error });
   753	        broadcastLog(`❌ QR ${item.name || item.productId}: ${r.error}`);
   754	      }
   755	    } catch (err) {
   756	      failed.push({ productId: item.productId, error: err.message });
   757	      broadcastLog(`❌ QR ${item.name || item.productId}: ${err.message}`);
   758	    }
   759	  }
   760	
   761	  // 성공분만 서버에 스냅샷 upsert — 실패분은 미기록 → 다음 델타에 재등장 (D-11)
   762	  if (succeeded.length > 0 && wsConnection && connectionStatus === 'connected') {
   763	    try {
   764	      await wsConnection.timeout(10000).emitWithAck('mark_qr_printed', {
   765	        priceTypeId,
   766	        items: succeeded,
   767	      });
   768	    } catch (err) {
   769	      // 출력은 이미 완료됐으니 로그만 — 스냅샷 실패 시 다음 델타 재등장이 안전한 방향
   770	      broadcastLog(`⚠️ mark_qr_printed falló: ${err.message || 'Timeout'} (reaparecerá en el próximo lote)`);
  1025	    const printerCfg = store.get('printer');
  1026	
  1027	    if (!isPrinterConfigured(printerCfg)) {
  1028	      broadcastLog('❌ Impresora no configurada');
  1029	
  1030	      return;
  1031	    }
  1032	
  1033	    if (!Array.isArray(payload?.items) || payload.items.length === 0) {
  1034	      broadcastLog('❌ print_barcode — items vacío');
  1035	
  1036	      return;
  1037	    }
  1038	
  1039	    const mode = getPrintMode();
  1040	
  1041	    const totalLabels = payload.items.reduce((sum, it) => sum + Math.max(1, it.qty || 1), 0);
  1042	    const modeLabel = printerCfg.type === 'usb' ? 'USB' : 'TCP';
  1043	
  1044	    broadcastLog(`🖨 Imprimiendo ${totalLabels} etiqueta(s) [${mode.name}] (${modeLabel})...`);
  1045	
  1046	    try {
  1047	      const zpl = formatBatchLabels(prepareItems(payload.items), mode);
  1048	      const result = await sendZpl(zpl, printerCfg);
  1049	
  1050	      if (result.ok) {
  1051	        broadcastLog(`✅ ${totalLabels} etiqueta(s) impresas`);
  1052	        wsConnection.emit('print_ack', {
  1053	          status: 'ok',
  1054	          labels: totalLabels,
  1055	          ts: Date.now(),
  1056	        });
  1057	      } else {
  1058	        broadcastLog(`❌ Error: ${result.error}`);
  1059	        wsConnection.emit('print_ack', {
  1060	          status: 'error',
  1061	          error: result.error,
  1062	          ts: Date.now(),
  1063	        });
  1064	      }
  1065	    } catch (err) {
  1066	      broadcastLog(`❌ ${err.message}`);
  1067	    }
  1068	  });
  1069	}
  1070	
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
zebra-agent/main.js:216:  // ─── 자동 업데이트 (Windows packaged 전용 — dev/mac 은 내부에서 스킵) ──────
zebra-agent/main.js:468:// 서버에서 precio nivel 목록 조회 (WebSocket ack — 연결돼 있어야 함)
zebra-agent/main.js:483:// 상품 목록 조회 — WebSocket ack (get_stock_today, 날짜/지점 필터)
zebra-agent/main.js:504:// 상품 검색 — SKU/이름 부분일치 (search_products WS ack).
zebra-agent/main.js:531:// 매장 지점 목록 조회 — 지점 선택 콤보용 (WebSocket ack)
zebra-agent/main.js:704:// QR 라벨 출력 — 항목별 sendZpl(부분 실패 안전, D-11) → 성공분만 mark_qr_printed 스냅샷
zebra-agent/main.js:719:    return { ok: r.ok, error: r.error, printed: 0, failed: r.ok ? 0 : 1, prueba: true };
zebra-agent/main.js:764:      await wsConnection.timeout(10000).emitWithAck('mark_qr_printed', {
zebra-agent/main.js:770:      broadcastLog(`⚠️ mark_qr_printed falló: ${err.message || 'Timeout'} (reaparecerá en el próximo lote)`);
zebra-agent/main.js:776:  return { ok: failed.length === 0, printed: succeeded.length, failed };
zebra-agent/main.js:820:        //   sticky sessions — el backend corre con 4 workers de PM2, así que el
zebra-agent/main.js:845:        resolve({ success: false, error: 'Timeout: no se pudo conectar en 5s' });
zebra-agent/main.js:855:          resolve({ success: true });
zebra-agent/main.js:862:            success: true,
zebra-agent/main.js:873:        resolve({ success: false, error: payload?.message || 'API Key inválida' });
zebra-agent/main.js:878:        resolve({ success: false, error: err.message });
zebra-agent/main.js:881:      resolve({ success: false, error: err.message });
zebra-agent/main.js:938:    wsConnection.emit('agent_online', {
zebra-agent/main.js:993:  // 기존 로컬 printTest() (ZPL 테스트 라벨) 재사용 후 print_ack{testId} 회신.
zebra-agent/main.js:1003:      wsConnection.emit('print_ack', {
zebra-agent/main.js:1005:        status: result?.success ? 'ok' : 'error',
zebra-agent/main.js:1006:        error: result?.success ? undefined : result?.error,
zebra-agent/main.js:1012:      wsConnection.emit('print_ack', {
zebra-agent/main.js:1052:        wsConnection.emit('print_ack', {
zebra-agent/main.js:1059:        wsConnection.emit('print_ack', {
zebra-agent/main.js:1097:    return { success: false, error: 'Impresora no configurada' };
zebra-agent/main.js:1125:      return { success: true };
zebra-agent/main.js:1129:      return { success: false, error: result.error };
zebra-agent/main.js:1134:    return { success: false, error: err.message };
print-agent/main.js:8:const printDedup = require('./src/print-dedup');
print-agent/main.js:78:printDedup.attachStore(store, (err) => {
print-agent/main.js:189:  // ─── 자동 업데이트 (Windows packaged 전용 — dev/mac 은 내부에서 스킵) ──────
print-agent/main.js:487:    // ★ ack 가 안 오면 **성공으로 치지 않는다.** 저장 안 된 문구를 「저장됨」으로
print-agent/main.js:495:      wsConnection.emit('set_footer', { footerLines }, (res) => {
print-agent/main.js:579:    return { success: true, filePath };
print-agent/main.js:583:    return { success: false, error: err.message };
print-agent/main.js:764:        resolve({ success: false, error: 'Timeout: no se pudo conectar en 5s' });
print-agent/main.js:772:          resolve({ success: true });
print-agent/main.js:780:        resolve({ success: false, error: payload?.message || 'API Key inválida' });
print-agent/main.js:785:        resolve({ success: false, error: err.message });
print-agent/main.js:788:      resolve({ success: false, error: err.message });
print-agent/main.js:854:  //   (engine.io code, 응답 출처가 nginx/cloudflare/backend 인지)을 가린다.
print-agent/main.js:1008:    wsConnection.emit('agent_online', {
print-agent/main.js:1094:    console.log('[connect_error] stack=',   err?.stack);
print-agent/main.js:1153:      wsConnection.emit('print_ack', {
print-agent/main.js:1182:        wsConnection.emit('print_ack', {
print-agent/main.js:1196:      wsConnection.emit('print_ack', {
print-agent/main.js:1202:      // fire-and-forget: 출력 실패가 판매 트랜잭션에 영향 없도록 ack만 전송
print-agent/main.js:1206:        stack:   err?.stack,
print-agent/main.js:1208:      wsConnection.emit('print_ack', {
print-agent/main.js:1242:      wsConnection.emit('print_ack', {
print-agent/main.js:1249:      wsConnection.emit('print_ack', {
print-agent/main.js:1273:      wsConnection.emit('print_ack', { code, status: 'ok', ts: Date.now() });
print-agent/main.js:1276:      wsConnection.emit('print_ack', { code, status: 'error', error: err.message, ts: Date.now() });
print-agent/main.js:1282:  // 기존 로컬 printTest() 파이프라인 재사용 후 print_ack{testId} 로 결과 회신.
print-agent/main.js:1292:      wsConnection.emit('print_ack', {
print-agent/main.js:1294:        status: result?.success ? 'ok' : 'error',
print-agent/main.js:1295:        error: result?.success ? undefined : result?.error,
print-agent/main.js:1301:      wsConnection.emit('print_ack', {
print-agent/main.js:1312:  // 판매번호/Forma de Pago 없는 견적용 티켓. fire-and-forget (ack 불필요).
print-agent/main.js:1389:        stack:   err?.stack,
print-agent/main.js:1408:  if (printDedup.claimJob(jobId)) return true;
print-agent/main.js:1476:    return { success: true };
print-agent/main.js:1480:    return { success: false, error: err.message };

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
/bin/zsh -lc "rg -n \"app\\.(quit|exit)|process\\.exit|window\\.close|mainWindow\\.close\" print-agent zebra-agent --glob '"'!node_modules/**'"'; cmp -s print-agent/src/updater.js zebra-agent/src/updater.js; echo updater_same="'$?; cmp -s print-agent/src/update-policy.js zebra-agent/src/update-policy.js; echo policy_same=$?; nl -ba zebra-agent/src/updater.js | sed -n '"'88,172p'; nl -ba zebra-agent/main.js | sed -n '758,778p'" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
zebra-agent/main.js:178:  app.exit(0);
zebra-agent/main.js:283:// ★ 종전 app.exit(0) 는 'quit' 이벤트를 내지 않아 autoInstallOnAppQuit 가 한 번도 안 돌았다.
zebra-agent/main.js:286:  app.exit(0);
zebra-agent/src/updater.js:11://   ★ 종전엔 3)이 「앱 종료 시」 하나뿐이었는데 「Salir」가 app.exit() 라 quit 이벤트가
zebra-agent/src/update-policy.js:6://   de la bandeja usaba app.exit(), que **no** dispara 'quit' → autoInstallOnAppQuit nunca
print-agent/main.js:149:  app.exit(0);
print-agent/main.js:287:// ★ 종전 app.exit(0) 는 'quit' 이벤트를 내지 않아 autoInstallOnAppQuit 가 한 번도 안 돌았다.
print-agent/main.js:290:  app.exit(0);
print-agent/test/update-policy.smoke.js:6: *   app.exit() (no dispara 'quit'). En la calle: print 1.2.5/1.2.6 con 1.2.10 publicado.
print-agent/test/update-policy.smoke.js:100:  await it('★ «Salir» pasa por salir() (instala si hay descarga), no por app.exit directo', () => {
print-agent/test/update-policy.smoke.js:129:  process.exit(1);
zebra-agent/test/update-policy.smoke.js:6: *   app.exit() (no dispara 'quit'). En la calle: print 1.2.5/1.2.6 con 1.2.10 publicado.
zebra-agent/test/update-policy.smoke.js:100:  await it('★ «Salir» pasa por salir() (instala si hay descarga), no por app.exit directo', () => {
zebra-agent/test/update-policy.smoke.js:129:  process.exit(1);
print-agent/src/updater.js:11://   ★ 종전엔 3)이 「앱 종료 시」 하나뿐이었는데 「Salir」가 app.exit() 라 quit 이벤트가
print-agent/src/update-policy.js:6://   de la bandeja usaba app.exit(), que **no** dispara 'quit' → autoInstallOnAppQuit nunca
print-agent/test/serial-queue.smoke.js:19:    process.exitCode = 1;
print-agent/test/serial-queue.smoke.js:114:})().catch((e) => { console.error(e); process.exit(1); });
print-agent/test/qr-formatter.smoke.js:30:})().catch((e) => { console.error(e); process.exit(1); });
print-agent/test/fiscal-pagos.smoke.js:48:  process.exit(1);
print-agent/test/fiscal-fecha.smoke.js:33:  process.exit(1);
updater_same=0
policy_same=0
    88	  st.disponible = true;
    89	
    90	  autoUpdater.autoDownload = true;
    91	
    92	  // 안전망으로 남긴다 — 정상 quit 경로(설치 프로그램·OS 재시작 등)에서는 여전히 설치된다
    93	  autoUpdater.autoInstallOnAppQuit = true;
    94	  autoUpdater.allowDowngrade = false;
    95	
    96	  autoUpdater.on('checking-for-update', () => {
    97	    if (st.fase !== 'listo' && st.fase !== 'descargando') cambiar({ fase: 'buscando', error: null });
    98	  });
    99	
   100	  autoUpdater.on('update-not-available', () => {
   101	    if (st.fase !== 'listo') cambiar({ fase: 'al-dia', ultimaBusqueda: Date.now() });
   102	  });
   103	
   104	  autoUpdater.on('update-available', (info) => {
   105	    log(`⬇️ Actualización disponible: v${info.version} — descargando en segundo plano...`);
   106	    cambiar({ fase: 'descargando', nueva: info.version, progreso: 0, ultimaBusqueda: Date.now() });
   107	  });
   108	
   109	  autoUpdater.on('download-progress', (p) => {
   110	    const pct = Math.floor(p?.percent || 0);
   111	    if (pct !== st.progreso) cambiar({ fase: 'descargando', progreso: pct });
   112	  });
   113	
   114	  autoUpdater.on('update-downloaded', (info) => {
   115	    log(`🔄 Actualización v${info.version} lista — se instalará sola de madrugada o con «Actualizar ahora»`);
   116	    cambiar({ fase: 'listo', nueva: info.version, progreso: 100 });
   117	  });
   118	
   119	  autoUpdater.on('error', (err) => {
   120	    // 네트워크 불안정 등은 흔함 — 경고 로그만 남기고 다음 주기에 재시도
   121	    log(`⚠️ auto-update: ${err.message}`);
   122	    if (st.fase !== 'listo') cambiar({ fase: 'error', error: err.message, ultimaBusqueda: Date.now() });
   123	  });
   124	
   125	  const buscar = async () => {
   126	    if (st.fase === 'listo' || st.fase === 'descargando') return { ...st };
   127	    try {
   128	      await autoUpdater.checkForUpdates();
   129	    } catch (err) {
   130	      log(`⚠️ auto-update check: ${err.message}`);
   131	      cambiar({ fase: 'error', error: err.message, ultimaBusqueda: Date.now() });
   132	    }
   133	
   134	    return { ...st };
   135	  };
   136	
   137	  // isSilent=true: 설치 창 없이 / isForceRunAfter: 설치 후 다시 띄울지
   138	  const instalar = (volverAAbrir) => {
   139	    log(`🔄 Reiniciando para instalar v${st.nueva}...`);
   140	    setImmediate(() => autoUpdater.quitAndInstall(true, volverAAbrir));
   141	  };
   142	
   143	  const instalarAhora = () => {
   144	    const r = puedeInstalarAMano({ listo: st.fase === 'listo', enCurso: actividad?.estado.enCurso || 0 });
   145	    if (!r.ok) return { ok: false, motivo: MOTIVO_TEXTO[r.motivo] || r.motivo };
   146	    instalar(true);
   147	
   148	    return { ok: true };
   149	  };
   150	
   151	  // 트레이 「Salir」: 다운로드돼 있고 인쇄 중이 아니면 설치하고 끝낸다(다시 띄우지 않음)
   152	  const instalarAlSalir = () => {
   153	    const r = puedeInstalarAMano({ listo: st.fase === 'listo', enCurso: actividad?.estado.enCurso || 0 });
   154	    if (!r.ok) return false;
   155	    instalar(false);
   156	
   157	    return true;
   158	  };
   159	
   160	  const vigilar = () => {
   161	    const r = puedeInstalarSolo({
   162	      listo: st.fase === 'listo',
   163	      ahora: Date.now(),
   164	      enCurso: actividad?.estado.enCurso || 0,
   165	      ultimaActividad: actividad?.estado.ultimaActividad || 0,
   166	    });
   167	    if (r.ok) {
   168	      log('🌙 Instalación automática de madrugada (sin impresiones en curso)');
   169	      instalar(true);
   170	    }
   171	  };
   172	
   758	    }
   759	  }
   760	
   761	  // 성공분만 서버에 스냅샷 upsert — 실패분은 미기록 → 다음 델타에 재등장 (D-11)
   762	  if (succeeded.length > 0 && wsConnection && connectionStatus === 'connected') {
   763	    try {
   764	      await wsConnection.timeout(10000).emitWithAck('mark_qr_printed', {
   765	        priceTypeId,
   766	        items: succeeded,
   767	      });
   768	    } catch (err) {
   769	      // 출력은 이미 완료됐으니 로그만 — 스냅샷 실패 시 다음 델타 재등장이 안전한 방향
   770	      broadcastLog(`⚠️ mark_qr_printed falló: ${err.message || 'Timeout'} (reaparecerá en el próximo lote)`);
   771	    }
   772	  }
   773	
   774	  broadcastLog(`✅ ${succeeded.length} QR impresas${failed.length ? ` — ❌ ${failed.length} fallidas` : ''}`);
   775	
   776	  return { ok: failed.length === 0, printed: succeeded.length, failed };
   777	});
   778	

hook: PostToolUse
hook: PostToolUse
hook: PostToolUse Failed
hook: PostToolUse Completed
codex
[HIGH] `print-agent/main.js:288`, `zebra-agent/main.js:284` — 인쇄 중 «Salir»가 앱을 강제 종료함

  문제: `instalarAlSalir()`가 인쇄 중이면 `false`를 반환하지만, 즉시 `app.exit(0)`으로 진행한다.

  시나리오: 업데이트 다운로드 완료 → 인쇄 진행 중 → 사용자가 «Salir» 클릭 → 인쇄가 중간에 끊김.

  수정: 실패 이유가 `imprimiendo`이면 종료하지 말고 안내를 표시하거나, 인쇄 완료 후 설치·종료를 예약한다.

[HIGH] `print-agent/src/updater.js:138`, `zebra-agent/src/updater.js:138` — 검사와 재시작 사이 경합 조건

  문제: `enCurso === 0` 확인 후 `setImmediate()`에서 `quitAndInstall()`을 실행한다. 그 사이 새 인쇄가 시작될 수 있다.

  시나리오: «Actualizar ahora» 클릭 직후 WebSocket 인쇄 작업 수신 → 프린터 전송 중 updater가 재시작.

  수정: 설치 예약 플래그로 신규 작업 수락을 막고, `quitAndInstall()` 직전에 `enCurso`를 다시 검사한다. 가능하면 인쇄 큐와 동일한 배타 잠금을 사용한다.

[HIGH] `zebra-agent/main.js:761` — 출력 후 서버 기록 구간이 “인쇄 활동”에서 제외됨

  문제: 마지막 `sendZpl()`이 끝나면 `enCurso`가 0이지만, `mark_qr_printed` ACK는 최대 10초 더 기다린다.

  시나리오: 라벨은 출력됨 → 서버 스냅샷 저장 대기 중 수동 업데이트/«Salir» → 재시작 후 동일 라벨이 변경분으로 다시 나타나 재출력될 수 있음.

  수정: 전체 QR 작업을 단일 활동으로 감싸서 `mark_qr_printed` 완료까지 업데이트를 금지하거나, 성공 목록을 로컬에 내구성 있게 기록한 뒤 재시작하도록 한다.
hook: Stop
hook: Stop
hook: Stop Failed
hook: Stop Completed
tokens used
49,369
[HIGH] `print-agent/main.js:288`, `zebra-agent/main.js:284` — 인쇄 중 «Salir»가 앱을 강제 종료함

  문제: `instalarAlSalir()`가 인쇄 중이면 `false`를 반환하지만, 즉시 `app.exit(0)`으로 진행한다.

  시나리오: 업데이트 다운로드 완료 → 인쇄 진행 중 → 사용자가 «Salir» 클릭 → 인쇄가 중간에 끊김.

  수정: 실패 이유가 `imprimiendo`이면 종료하지 말고 안내를 표시하거나, 인쇄 완료 후 설치·종료를 예약한다.

[HIGH] `print-agent/src/updater.js:138`, `zebra-agent/src/updater.js:138` — 검사와 재시작 사이 경합 조건

  문제: `enCurso === 0` 확인 후 `setImmediate()`에서 `quitAndInstall()`을 실행한다. 그 사이 새 인쇄가 시작될 수 있다.

  시나리오: «Actualizar ahora» 클릭 직후 WebSocket 인쇄 작업 수신 → 프린터 전송 중 updater가 재시작.

  수정: 설치 예약 플래그로 신규 작업 수락을 막고, `quitAndInstall()` 직전에 `enCurso`를 다시 검사한다. 가능하면 인쇄 큐와 동일한 배타 잠금을 사용한다.

[HIGH] `zebra-agent/main.js:761` — 출력 후 서버 기록 구간이 “인쇄 활동”에서 제외됨

  문제: 마지막 `sendZpl()`이 끝나면 `enCurso`가 0이지만, `mark_qr_printed` ACK는 최대 10초 더 기다린다.

  시나리오: 라벨은 출력됨 → 서버 스냅샷 저장 대기 중 수동 업데이트/«Salir» → 재시작 후 동일 라벨이 변경분으로 다시 나타나 재출력될 수 있음.

  수정: 전체 QR 작업을 단일 활동으로 감싸서 `mark_qr_printed` 완료까지 업데이트를 금지하거나, 성공 목록을 로컬에 내구성 있게 기록한 뒤 재시작하도록 한다.
