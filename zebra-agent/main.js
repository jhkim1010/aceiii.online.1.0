// zebra-agent/main.js
// VentaGO Zebra Agent — Electron 메인 프로세스
// Zebra 라벨 프린터에 ZPL II 명령을 TCP Raw Socket으로 전송
const { app, BrowserWindow, Tray, Menu, ipcMain, nativeImage } = require('electron');
const path = require('path');
const Store = require('electron-store');
const { formatBatchLabels, resolveMode, LABEL_MODES, LEGACY_PRESET_ALIASES } = require('./src/zpl-formatter');
const { prepareItems: prepareItemsPure } = require('./src/price-select');
const { sendZpl, testConnection: testPrinterConnection, listUsbPrinters } = require('./src/zebra-printer');
const { discoverPrinters: discoverPrintersImpl } = require('./src/printer-discovery');
const { initAutoUpdater } = require('./src/updater');

// ─── 고정 서버 URL (항상 운영 서버 — 도메인 경유, 5002 포트 직접 접근 불가) ───
const SERVER_URL = 'https://newapi.coolsistema.com/api';

// ─── 설정 저장소 ────────────────────────────────────────────────────────────
const store = new Store({
  defaults: {
    apiKey: '',
    agentType: 'zebra',
    printer: {
      type: 'network',     // 'network' | 'usb'
      host: '',
      port: 9100,
      printerName: '',     // USB 프린터 이름 (OS에 등록된)
    },
    labelPreset: '50x25-simple',   // 구버전 키 (마이그레이션용으로만 유지)
    labelLayout: null,             // 구버전 키 (마이그레이션용으로만 유지)
    labelMode: '',                 // 신규: 출력 모드 (simple-face 등 4종)
    labelLayouts: {},              // 신규: 모드별 커스텀 { [modeKey]: { width, height, layout } }
    priceSelection: [],            // 신규: 출력할 precio nivel [{ id, name }] 최대 3개
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

// ─── 현재 유효 모드 계산 (프리셋 + 모드별 커스텀 병합) ──────────────────────
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
    // 출력 밀도(0~30)/속도(2~14 ips) — 미설정(null) 시 프린터 기본값 사용
    darkness: custom.darkness ?? null,
    speed: custom.speed ?? null,
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

// 동일 API Key 로 다른 기기가 접속해 서버가 이 소켓을 강제 종료한 경우 true.
// 자동 재연결(및 disconnect 핸들러의 상태 덮어쓰기)을 막기 위한 플래그.
let displacedByDuplicate = false;

// 자동 업데이트 상태 — 다운로드 완료 시 트레이에 수동 설치 메뉴 노출용
let updaterRef = null;
let updateReadyVersion = null;

// ─── 앱 준비 완료 ───────────────────────────────────────────────────────────
app.whenReady().then(() => {
  migrateLegacyLabelConfig();
  createTray();

  if (!store.get('setupDone')) {
    openSetupWizard();
  } else {
    openMainWindow();
    initWebSocket();
  }

  if (store.get('openAtLogin')) {
    try {
      app.setLoginItemSettings({ openAtLogin: true, openAsHidden: true });
    } catch (err) {
      console.error('setLoginItemSettings error:', err);
    }
  }

  // ─── 자동 업데이트 (Windows packaged 전용 — dev/mac 은 내부에서 스킵) ──────
  updaterRef = initAutoUpdater({
    onLog: broadcastLog,
    onUpdateDownloaded: (info) => {
      updateReadyVersion = info?.version || null;
      updateTrayMenu(); // "Reiniciar y actualizar" 메뉴 노출
    },
  });
});

app.on('window-all-closed', (e) => {
  e.preventDefault();
});

// ─── 트레이 ─────────────────────────────────────────────────────────────────
function createTray() {
  const iconPath = path.join(__dirname, 'renderer/assets/tray-icon.png');
  let image = nativeImage.createFromPath(iconPath);
  if (image.isEmpty()) image = nativeImage.createEmpty();

  tray = new Tray(image);
  tray.setToolTip('VentaGO Zebra Agent');
  updateTrayMenu();
  tray.on('double-click', openMainWindow);
}

function updateTrayMenu() {
  const statusLabel = {
    connected: '🟢 Conectado',
    disconnected: '🔴 Desconectado',
    reconnecting: '🟡 Reconectando...',
    displaced: '⛔ Reemplazado (misma API Key)',
  }[connectionStatus] ?? '🔴 Desconectado';

  // 업데이트 다운로드 완료 시 수동 설치 메뉴 (미완료 시 빈 배열)
  const updateItems = updateReadyVersion
    ? [
        {
          label: `🔄 Reiniciar y actualizar a v${updateReadyVersion}`,
          click: () => {
            if (updaterRef) updaterRef.quitAndInstall(false, true);
          },
        },
        { type: 'separator' },
      ]
    : [];

  const contextMenu = Menu.buildFromTemplate([
    ...updateItems,
    { label: statusLabel, enabled: false },
    { type: 'separator' },
    { label: 'Abrir configuración', click: openMainWindow },
    { label: 'Imprimir test', click: () => printTest() },
    { type: 'separator' },
    { label: 'Salir', click: () => app.exit(0) },
  ]);

  tray.setContextMenu(contextMenu);
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

  mainWindow = new BrowserWindow({
    width: 480,
    height: 560,
    resizable: false,
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
    e.preventDefault();
    mainWindow.hide();
  });

  mainWindow.on('closed', () => { mainWindow = null; });
}

// ─── IPC 핸들러 ─────────────────────────────────────────────────────────────

// 설정 읽기/쓰기
ipcMain.handle('store:get', (_event, key) => store.get(key));
ipcMain.handle('store:set', (_event, key, value) => { store.set(key, value); });
ipcMain.handle('store:setAll', (_event, config) => {
  Object.entries(config).forEach(([k, v]) => store.set(k, v));
});

// WebSocket 상태
ipcMain.handle('ws:status', () => connectionStatus);
ipcMain.handle('ws:reconnect', () => { initWebSocket(); });

// 연결 테스트 (마법사용 — 서버 URL 고정, API Key만 테스트)
ipcMain.handle('ws:test', async (_event, _url, apiKey) => {
  return testWsConnection(apiKey);
});

// 셋업 완료
ipcMain.handle('setup:complete', () => {
  store.set('setupDone', true);
  if (setupWindow) setupWindow.close();
  openMainWindow();
  initWebSocket();
});

// 프린터 테스트
ipcMain.handle('printer:test', () => printTest());

// USB 프린터 목록 조회
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
ipcMain.handle('label:setLayout', (_event, custom) => {
  const modeKey = getEffectiveMode().key;
  const layouts = store.get('labelLayouts') || {};

  if (custom == null) {
    delete layouts[modeKey];
  } else {
    // 밀도/속도는 범위 검증 후 저장 (범위 밖/빈값 → null = 프린터 기본값)
    const dk = parseInt(custom.darkness, 10);
    const sp = parseInt(custom.speed, 10);

    layouts[modeKey] = {
      width: custom.width || undefined,
      height: custom.height || undefined,
      darkness: Number.isFinite(dk) && dk >= 0 && dk <= 30 ? dk : null,
      speed: Number.isFinite(sp) && sp >= 2 && sp <= 14 ? sp : null,
      layout: custom.layout || custom, // { layout } 또는 layout 직접 전달 모두 허용
    };
  }

  store.set('labelLayouts', layouts);
});

// precio nivel 선택 저장 ([{ id, name }] 최대 3개, [] = 가격 미출력)
ipcMain.handle('label:setPriceSelection', (_event, selection) => {
  const clean = Array.isArray(selection)
    ? selection
        .filter((s) => s && (s.id != null || s.name))
        .slice(0, 3)
        .map((s) => ({ id: s.id ?? null, name: s.name || '' }))
    : [];

  store.set('priceSelection', clean);
});

// 서버에서 precio nivel 목록 조회 (WebSocket ack — 연결돼 있어야 함)
ipcMain.handle('priceTypes:fetch', async () => {
  if (!wsConnection || connectionStatus !== 'connected') {
    return { ok: false, error: 'No conectado al servidor' };
  }

  try {
    const res = await wsConnection.timeout(7000).emitWithAck('get_price_types');

    return res || { ok: false, error: 'Sin respuesta' };
  } catch (err) {
    return { ok: false, error: err.message || 'Timeout' };
  }
});

// Zebra Agent에서 직접 상품 목록 조회 (서버 REST API 호출)
ipcMain.handle('products:fetchByDate', async (_event, date) => {
  const apiKey = store.get('apiKey');
  if (!apiKey) return { ok: false, error: 'API Key 미설정' };

  try {
    let origin = SERVER_URL;
    try { origin = new URL(SERVER_URL).origin; } catch (_) {}
    const url = `${origin}/api/products/stock-today?date=${date}&page=0&pageSize=500`;

    const res = await fetch(url, {
      headers: { 'x-zebra-agent': apiKey },
    });
    const json = await res.json();

    return { ok: true, data: json };
  } catch (err) {
    return { ok: false, error: err.message };
  }
});

// Zebra Agent에서 직접 출력 (WebSocket 우회, 로컬 직접 출력)
ipcMain.handle('print:labels', async (_event, items) => {
  const printerCfg = store.get('printer');
  if (!isPrinterConfigured(printerCfg)) return { ok: false, error: 'Impresora no configurada' };

  const mode = getPrintMode();

  try {
    const zpl = formatBatchLabels(prepareItems(items), mode);
    const result = await sendZpl(zpl, printerCfg);

    const totalLabels = items.reduce((s, it) => s + Math.max(1, it.qty || 1), 0);
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

// 프린터 탐색
ipcMain.handle('printer:discover', async () => {
  try {
    const ips = await discoverPrintersImpl((scanned, total, found) => {
      if (mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.webContents.send('discover-progress', { scanned, total, found });
      }
    });

    return ips;
  } catch (err) {
    broadcastLog(`❌ discoverPrinters: ${err.message}`);

    return [];
  }
});

// 프린터 연결 테스트
ipcMain.handle('printer:testConnection', async (_event, host, port) => {
  return testPrinterConnection(host, port || 9100);
});

// ─── WebSocket 연결 테스트 (마법사용) ───────────────────────────────────────
async function testWsConnection(apiKey) {
  return new Promise((resolve) => {
    try {
      const { io } = require('socket.io-client');
      let originOnly = SERVER_URL;
      try {
        const u = new URL(SERVER_URL);
        originOnly = `${u.protocol}//${u.host}`;
      } catch (_) { /* ignore */ }

      const testSocket = io(`${originOnly}/print-agent`, {
        auth: { token: apiKey },
        timeout: 5000,
        reconnection: false,
      });

      const timer = setTimeout(() => {
        testSocket.disconnect();
        resolve({ success: false, error: 'Timeout: no se pudo conectar en 5s' });
      }, 5000);

      // 연결 성공 시 agent_info 이벤트 대기 (매장명/터미널명 수신)
      testSocket.on('connect', () => {
        clearTimeout(timer);

        // agent_info 이벤트가 500ms 안에 오면 매장/터미널 정보 포함
        const infoTimer = setTimeout(() => {
          testSocket.disconnect();
          resolve({ success: true });
        }, 800);

        testSocket.on('agent_info', (info) => {
          clearTimeout(infoTimer);
          testSocket.disconnect();
          resolve({
            success: true,
            storeName: info?.storeName || '',
            branchName: info?.branchName || '',
            agentLabel: info?.label || '',
          });
        });
      });

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

// ─── WebSocket 메인 루프 ────────────────────────────────────────────────────
function initWebSocket() {
  const apiKey = store.get('apiKey');

  if (!apiKey) {
    broadcastLog('⚠️ API Key 미설정 — 셋업 마법사를 먼저 완료하세요');

    return;
  }

  // origin 추출 (고정 서버 URL에서)
  let originOnly = SERVER_URL;
  try {
    const u = new URL(SERVER_URL);
    originOnly = `${u.protocol}//${u.host}`;
  } catch (_) { /* ignore */ }

  const nsUrl = `${originOnly}/print-agent`;

  console.log(`[initWebSocket] connecting to ${nsUrl} (apiKey: ${apiKey.slice(0, 12)}...)`);
  broadcastLog(`🔍 Conectando a ${nsUrl}`);

  // 기존 연결 정리
  if (wsConnection) {
    try { wsConnection.disconnect(); } catch (_) { /* ignore */ }
    wsConnection = null;
  }

  // 새 연결 시도 → displaced 플래그 초기화 (수동 재연결/재시작 대비)
  displacedByDuplicate = false;

  setConnectionStatus('reconnecting');

  const { io } = require('socket.io-client');

  wsConnection = io(nsUrl, {
    auth: { token: apiKey },
    reconnection: true,
    reconnectionAttempts: Infinity,
    reconnectionDelay: 2000,
    reconnectionDelayMax: 5000,
    randomizationFactor: 0.3,
    timeout: 10000,
    transports: ['websocket'],
  });

  wsConnection.on('connect', () => {
    setConnectionStatus('connected');
    broadcastLog('✅ Conectado al servidor');

    wsConnection.emit('agent_online', {
      version: app.getVersion(),
      agentType: 'zebra',
      ts: Date.now(),
    });
  });

  // 인증 성공 시 매장/지점 정보 수신 → store에 저장 + UI 전달
  wsConnection.on('agent_info', (info) => {
    console.log('[agent_info]', info);
    store.set('_lastAgentInfo', info);
    broadcastLog(`🏪 ${info.storeName || ''} — ${info.branchName || ''} (${info.label || ''})`);
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('agent-info', info);
    }
  });

  wsConnection.on('auth_error', (payload) => {
    broadcastLog(`❌ Autenticación fallida: ${payload?.message || 'API Key inválida'}`);
    setConnectionStatus('disconnected');
  });

  // 동일 API Key 로 다른 기기가 접속 → 서버(PrintGateway)가 이 소켓을 강제 종료.
  // 서버발 disconnect('io server disconnect')는 자동 재연결이 되지 않지만,
  // 방어적으로 reconnection 을 끄고 displaced 플래그를 세워 상태/사유를 고정한다.
  wsConnection.on('force_disconnect', (payload) => {
    displacedByDuplicate = true;
    if (wsConnection?.io?.opts) {
      wsConnection.io.opts.reconnection = false;
    }
    broadcastLog(
      `⛔ Reemplazado: ${payload?.message || 'otra sesión usó la misma API Key'}`,
    );
    setConnectionStatus('displaced');
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('force-disconnect', payload || {});
    }
  });

  wsConnection.on('disconnect', (reason) => {
    // force_disconnect 로 이미 displaced 처리됐으면 상태/로그를 유지한다.
    if (displacedByDuplicate) {
      return;
    }
    setConnectionStatus('disconnected');
    broadcastLog(`⚠️ Desconectado: ${reason}`);
  });

  wsConnection.on('connect_error', (err) => {
    setConnectionStatus('reconnecting');
    broadcastLog(`❌ Error de conexión: ${err?.message}`);
  });

  // ── 원격 테스트 인쇄 ─────────────────────────────────────────────────────
  // 관리 페이지 "Imprimir prueba" → POST /print/agents/:id/test → print_test emit.
  // 기존 로컬 printTest() (ZPL 테스트 라벨) 재사용 후 print_ack{testId} 회신.
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
      // printTest 는 자체 에러 처리가 있지만 안전망으로 한 번 더 감싼다
      wsConnection.emit('print_ack', {
        testId,
        status: 'error',
        error: err.message,
        ts: Date.now(),
      });
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
    } catch (err) {
      broadcastLog(`❌ ${err.message}`);
    }
  });
}

// ─── 로그 브로드캐스트 ──────────────────────────────────────────────────────
function broadcastLog(msg) {
  const ts = new Date().toLocaleTimeString('es-AR');
  const ok = !/^(❌|⚠️)/.test(String(msg).trim());

  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send('print-log', { ts, ok, message: String(msg) });
  }
  console.log(`${ts}  ${msg}`);
}

// ─── 프린터 설정 검증 헬퍼 ──────────────────────────────────────────────────
function isPrinterConfigured(cfg) {
  if (!cfg) return false;
  if (cfg.type === 'usb') return !!cfg.printerName;

  return !!cfg.host;
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
    const testZpl = [
      '^XA',
      '^PW400',
      '^LL200',
      '^CI28',
      '^FO10,5^A0N,22,22^FDVENTAGO ZEBRA TEST^FS',
      '^FO10,30^BY2^BCN,50,Y,N,N^FD1234567890^FS',
      '^FO10,100^A0N,28,28^FD$0.00^FS',
      '^FO10,135^A0N,16,16^FDTest de impresion^FS',
      '^XZ',
    ].join('\n');

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
  }
}

module.exports = { setConnectionStatus, store };
