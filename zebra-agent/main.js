// zebra-agent/main.js
// VentaGO Zebra Agent — Electron 메인 프로세스
// Zebra 라벨 프린터에 ZPL II 명령을 TCP Raw Socket으로 전송
const { app, BrowserWindow, Tray, Menu, ipcMain, nativeImage } = require('electron');
const path = require('path');
const Store = require('electron-store');
const { formatBatchLabels, LABEL_PRESETS } = require('./src/zpl-formatter');
const { sendZpl, testConnection: testPrinterConnection } = require('./src/zebra-printer');
const { discoverPrinters: discoverPrintersImpl } = require('./src/printer-discovery');

// ─── 설정 저장소 ────────────────────────────────────────────────────────────
const store = new Store({
  defaults: {
    apiUrl: '',
    apiKey: '',
    agentType: 'zebra',
    printer: {
      host: '',
      port: 9100,
    },
    labelPreset: '50x25-simple',
    labelLayout: null,
    openAtLogin: true,
    setupDone: false,
  },
});

// ─── 전역 상태 ──────────────────────────────────────────────────────────────
let tray = null;
let mainWindow = null;
let setupWindow = null;
let wsConnection = null;
let connectionStatus = 'disconnected';

// ─── 앱 준비 완료 ───────────────────────────────────────────────────────────
app.whenReady().then(() => {
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
  }[connectionStatus] ?? '🔴 Desconectado';

  const contextMenu = Menu.buildFromTemplate([
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

// 연결 테스트 (마법사용)
ipcMain.handle('ws:test', async (_event, url, apiKey) => {
  return testWsConnection(url, apiKey);
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

// 라벨 프리셋 목록
ipcMain.handle('label:presets', () => {
  return Object.values(LABEL_PRESETS).map(p => ({
    key: p.key,
    name: p.name,
    width: p.width,
    height: p.height,
    duplicate: !!p.duplicate,
    layout: p.layout,
  }));
});

// 현재 프리셋 + 커스텀 레이아웃 가져오기
ipcMain.handle('label:getConfig', () => {
  const presetKey = store.get('labelPreset') || '50x25-simple';
  const customLayout = store.get('labelLayout');
  const preset = LABEL_PRESETS[presetKey] || LABEL_PRESETS['50x25-simple'];

  return {
    presetKey,
    preset: { ...preset, layout: customLayout || preset.layout },
  };
});

// 프리셋 변경
ipcMain.handle('label:setPreset', (_event, presetKey) => {
  store.set('labelPreset', presetKey);
  store.set('labelLayout', null);
});

// 커스텀 레이아웃 저장
ipcMain.handle('label:setLayout', (_event, layout) => {
  store.set('labelLayout', layout);
});

// Zebra Agent에서 직접 상품 목록 조회 (서버 REST API 호출)
ipcMain.handle('products:fetchByDate', async (_event, date) => {
  const apiUrl = store.get('apiUrl');
  const apiKey = store.get('apiKey');
  if (!apiUrl) return { ok: false, error: 'apiUrl 미설정' };

  try {
    let origin = apiUrl;
    try { origin = new URL(apiUrl).origin; } catch (_) {}
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
  const printerHost = store.get('printer.host');
  const printerPort = store.get('printer.port') || 9100;
  if (!printerHost) return { ok: false, error: 'Impresora no configurada' };

  const presetKey = store.get('labelPreset') || '50x25-simple';
  const customLayout = store.get('labelLayout');
  const preset = { ...(LABEL_PRESETS[presetKey] || LABEL_PRESETS['50x25-simple']) };
  if (customLayout) preset.layout = customLayout;

  try {
    const zpl = formatBatchLabels(items, preset);
    const result = await sendZpl(zpl, printerHost, printerPort);

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
async function testWsConnection(url, apiKey) {
  return new Promise((resolve) => {
    try {
      const { io } = require('socket.io-client');
      let originOnly = url;
      try {
        const u = new URL(url);
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

      testSocket.on('connect', () => {
        clearTimeout(timer);
        setTimeout(() => {
          testSocket.disconnect();
          resolve({ success: true });
        }, 500);
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
  const url = store.get('apiUrl');
  const apiKey = store.get('apiKey');

  if (!url || !apiKey) {
    broadcastLog('⚠️ apiUrl/apiKey 미설정 — 셋업 마법사를 먼저 완료하세요');

    return;
  }

  // origin 추출 (NestJS global prefix /api 제거)
  let originOnly = url;
  try {
    const u = new URL(url);
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
    transports: ['polling', 'websocket'],
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

  wsConnection.on('auth_error', (payload) => {
    broadcastLog(`❌ Autenticación fallida: ${payload?.message || 'API Key inválida'}`);
    setConnectionStatus('disconnected');
  });

  wsConnection.on('disconnect', (reason) => {
    setConnectionStatus('disconnected');
    broadcastLog(`⚠️ Desconectado: ${reason}`);
  });

  wsConnection.on('connect_error', (err) => {
    setConnectionStatus('reconnecting');
    broadcastLog(`❌ Error de conexión: ${err?.message}`);
  });

  // ── 바코드 라벨 출력 이벤트 ─────────────────────────────────────────────
  wsConnection.on('print_barcode', async (payload) => {
    console.log('[print_barcode] payload:', JSON.stringify(payload, null, 2));

    const printerHost = store.get('printer.host');
    const printerPort = store.get('printer.port') || 9100;

    if (!printerHost) {
      broadcastLog('❌ Impresora no configurada');

      return;
    }

    if (!Array.isArray(payload?.items) || payload.items.length === 0) {
      broadcastLog('❌ print_barcode — items vacío');

      return;
    }

    const presetKey = store.get('labelPreset') || '50x25-simple';
    const customLayout = store.get('labelLayout');
    const preset = { ...(LABEL_PRESETS[presetKey] || LABEL_PRESETS['50x25-simple']) };
    if (customLayout) preset.layout = customLayout;

    const totalLabels = payload.items.reduce((sum, it) => sum + Math.max(1, it.qty || 1), 0);

    broadcastLog(`🖨 Imprimiendo ${totalLabels} etiqueta(s) [${preset.name}]...`);

    try {
      const zpl = formatBatchLabels(payload.items, preset);
      const result = await sendZpl(zpl, printerHost, printerPort);

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

// ─── 테스트 출력 ────────────────────────────────────────────────────────────
async function printTest() {
  const printerHost = store.get('printer.host');
  const printerPort = store.get('printer.port') || 9100;

  if (!printerHost) {
    broadcastLog('❌ Impresora no configurada');

    return { success: false, error: 'Impresora no configurada' };
  }

  broadcastLog('🖨 Imprimiendo etiqueta de prueba...');

  try {
    const testZpl = [
      '^XA',
      '^PW400',
      '^LL236',
      '^CI28',
      '^FO20,10^A0N,28,28^FDVENTAGO ZEBRA TEST^FS',
      '^FO20,45^A0N,22,22^FD$0.00^FS',
      '^FO20,80^BY2^BCN,60,Y,N,N^FD1234567890^FS',
      '^FO20,160^A0N,18,18^FDTest de impresion^FS',
      '^XZ',
    ].join('\n');

    const result = await sendZpl(testZpl, printerHost, printerPort);

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
