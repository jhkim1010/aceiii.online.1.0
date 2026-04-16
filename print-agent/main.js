// print-agent/main.js
// VentaGO Print Agent — Electron 메인 프로세스
const { app, BrowserWindow, Tray, Menu, ipcMain, nativeImage, shell } = require('electron');
const path = require('path');
const fs = require('fs');
const os = require('os');
const Store = require('electron-store');
const { printTicket }       = require('./src/print-pipeline');
const { formatFiscalHtml }  = require('./src/fiscal-formatter');
const { formatTempTicketHtml } = require('./src/formatter');
const { renderHtmlToPng }   = require('./src/renderer-engine');
const { printImage, testConnection: testPrinterConnection } = require('./src/printer');
const { discoverPrinters: discoverPrintersImpl } = require('./src/printer-discovery');

// ─── 설정 저장소 (electron-store) ───────────────────────────────────────────
// 저장 위치: Windows %APPDATA%/ventago-print-agent/config.json
const store = new Store({
  defaults: {
    apiUrl: '',
    apiKey: '',
    printer: {
      type: 'network',
      host: '192.168.1.100',
      port: 9100,
      vendorId: '0x0',
      productId: '0x0',
      width: 48,
    },
    printControl: true,   // 판매 확정 시 컨트롤 티켓 출력
    printFiscal: true,    // AFIP 발행 시 영수증 출력
    openAtLogin: true,
    setupDone: false,     // false 이면 마법사 먼저 표시
    // ─── 다중 프로파일 (sucursal 연결 저장) ──────────────────────────────────
    profiles: [],         // [{ id, label, apiUrl, apiKey, printer }]
    activeProfileId: null,
  },
});

// ─── 기존 단일 설정 → 프로파일 자동 마이그레이션 ────────────────────────────
// 업그레이드 시 기존 apiUrl/apiKey가 있으면 "Sucursal Principal"로 변환
function migrateProfiles() {
  const profiles = store.get('profiles');
  const apiUrl   = store.get('apiUrl');
  const apiKey   = store.get('apiKey');

  // 기존 설정이 있고 프로파일이 비어있으면 마이그레이션
  if ((!profiles || profiles.length === 0) && apiUrl && apiKey) {
    const firstProfile = {
      id:      `profile_${Date.now()}`,
      label:   'Sucursal Principal',
      apiUrl,
      apiKey,
      printer: store.get('printer'),
    };
    store.set('profiles', [firstProfile]);
    store.set('activeProfileId', firstProfile.id);
    console.log('[migrateProfiles] 기존 설정 → 프로파일 마이그레이션 완료:', firstProfile.id);
  }
}
migrateProfiles();

// ─── 전역 상태 ────────────────────────────────────────────────────────────────
let tray = null;
let mainWindow = null;
let setupWindow = null;
let wsConnection = null; // WebSocket 연결 (Phase 11-02에서 구현)
let connectionStatus = 'disconnected'; // 'connected' | 'disconnected' | 'reconnecting'

// ─── 앱 준비 완료 ─────────────────────────────────────────────────────────────
app.whenReady().then(() => {
  createTray();

  // 최초 실행 시 셋업 마법사, 이후에는 메인창 + WebSocket 시작
  if (!store.get('setupDone')) {
    openSetupWizard();
  } else {
    openMainWindow();
    initWebSocket();
  }

  // Windows 시작 시 자동 실행 설정
  if (store.get('openAtLogin')) {
    try {
      app.setLoginItemSettings({ openAtLogin: true, openAsHidden: true });
    } catch (err) {
      console.error('setLoginItemSettings error:', err);
    }
  }
});

// 모든 창 닫혀도 앱 종료하지 않음 (트레이 상주)
app.on('window-all-closed', (e) => {
  e.preventDefault();
});

// ─── 트레이 생성 ──────────────────────────────────────────────────────────────
function createTray() {
  // 트레이 아이콘 (16x16 PNG). 파일이 없으면 빈 이미지 사용 (개발 단계)
  const iconPath = path.join(__dirname, 'renderer/assets/tray-icon.png');
  let image = nativeImage.createFromPath(iconPath);
  if (image.isEmpty()) {
    image = nativeImage.createEmpty();
  }
  tray = new Tray(image);
  tray.setToolTip('VentaGO Print Agent');
  updateTrayMenu();

  // 더블클릭 시 설정 창 열기
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
    { label: 'Ver log', click: openLogWindow },
    { type: 'separator' },
    { label: 'Salir', click: () => app.exit(0) },
  ]);

  tray.setContextMenu(contextMenu);
}

// 연결 상태 변경 시 트레이 아이콘 업데이트
function setConnectionStatus(status) {
  connectionStatus = status;
  updateTrayMenu();

  // 설정 창이 열려 있으면 상태 전달
  if (mainWindow) {
    mainWindow.webContents.send('connection-status', status);
  }
}

// ─── 창 관리 ──────────────────────────────────────────────────────────────────
function openSetupWizard() {
  if (setupWindow) {
    setupWindow.focus();

    return;
  }

  setupWindow = new BrowserWindow({
    width: 520,
    height: 480,
    resizable: false,
    title: 'VentaGO Print Agent — Configuración inicial',
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
  if (mainWindow) {
    mainWindow.show();
    mainWindow.focus();

    return;
  }

  mainWindow = new BrowserWindow({
    width: 480,
    height: 600,
    resizable: false,
    title: 'VentaGO Print Agent',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  mainWindow.loadFile('renderer/index.html');

  // ─── 디버깅: DevTools 자동 오픈 ────────────────────────────────────────────
  mainWindow.webContents.openDevTools({ mode: 'detach' });

  // ─── 디버깅: 렌더러 라이프사이클 추적 ──────────────────────────────────────
  mainWindow.webContents.on('did-start-loading', () => console.log('[mainWindow] did-start-loading'));
  mainWindow.webContents.on('did-finish-load',   () => console.log('[mainWindow] did-finish-load'));
  mainWindow.webContents.on('did-fail-load', (_e, code, desc, url) => {
    console.log(`[mainWindow] did-fail-load code=${code} desc=${desc} url=${url}`);
  });
  mainWindow.webContents.on('preload-error', (_e, preloadPath, err) => {
    console.log(`[mainWindow] PRELOAD ERROR path=${preloadPath} err=${err.message}`);
  });
  mainWindow.webContents.on('console-message', (_e, level, message, line, sourceId) => {
    console.log(`[renderer console] [${level}] ${message} (${sourceId}:${line})`);
  });

  // 렌더러 로드 완료 시 현재 연결 상태를 한 번 더 push (초기 동기화 보장)
  mainWindow.webContents.on('did-finish-load', () => {
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('connection-status', connectionStatus);
      console.log(`[mainWindow] pushed initial connection-status=${connectionStatus}`);
    }
  });

  // 닫기 버튼 → 숨기기 (트레이 상주)
  mainWindow.on('close', (e) => {
    e.preventDefault();
    mainWindow.hide();
  });

  mainWindow.on('closed', () => { mainWindow = null; });
}

function openLogWindow() {
  // 로그는 mainWindow의 탭으로 처리 (Phase 11-02에서)
  openMainWindow();
}

// ─── IPC 핸들러 (renderer → main) ────────────────────────────────────────────

// 설정 읽기
ipcMain.handle('store:get', (_event, key) => store.get(key));

// ─── 프로파일 IPC 핸들러 ─────────────────────────────────────────────────────

// 프로파일 목록 조회
ipcMain.handle('profile:list', () => store.get('profiles') || []);

// 활성 프로파일 ID 조회
ipcMain.handle('profile:getActiveId', () => store.get('activeProfileId'));

// 프로파일 저장 (신규 or 수정)
ipcMain.handle('profile:save', (_event, profile) => {
  const profiles = store.get('profiles') || [];
  const idx = profiles.findIndex(p => p.id === profile.id);
  if (idx >= 0) {
    profiles[idx] = profile; // 수정
  } else {
    profile.id = `profile_${Date.now()}`; // 신규
    profiles.push(profile);
  }
  store.set('profiles', profiles);
  return profile;
});

// 프로파일 삭제
ipcMain.handle('profile:delete', (_event, profileId) => {
  const profiles = store.get('profiles') || [];
  const filtered = profiles.filter(p => p.id !== profileId);
  store.set('profiles', filtered);
  // 삭제된 게 활성 프로파일이면 첫 번째로 전환
  if (store.get('activeProfileId') === profileId) {
    const nextId = filtered.length > 0 ? filtered[0].id : null;
    store.set('activeProfileId', nextId);
    if (nextId) initWebSocket();
  }
  return filtered;
});

// 프로파일 전환 → WebSocket 재연결
ipcMain.handle('profile:switch', (_event, profileId) => {
  store.set('activeProfileId', profileId);
  broadcastLog(`🔄 프로파일 전환: ${profileId}`);
  initWebSocket();
  return profileId;
});

// 설정 저장
ipcMain.handle('store:set', (_event, key, value) => {
  store.set(key, value);
});

// 설정 전체 저장 (셋업 마법사 완료 시)
ipcMain.handle('store:setAll', (_event, config) => {
  Object.entries(config).forEach(([k, v]) => store.set(k, v));
});

// WebSocket 연결 상태 조회
ipcMain.handle('ws:status', () => connectionStatus);

// WebSocket 재연결 트리거
ipcMain.handle('ws:reconnect', () => {
  initWebSocket(); // Phase 11-02에서 구현
});

// 셋업 완료 → 마법사 닫고 메인창 + WebSocket 시작
ipcMain.handle('setup:complete', () => {
  store.set('setupDone', true);
  if (setupWindow) setupWindow.close();
  openMainWindow();
  initWebSocket();
});

// 프린터 테스트 출력 (Phase 11-02에서 구현)
ipcMain.handle('printer:test', () => printTest());

// 프린터 탐색 (Phase 11-02에서 구현)
ipcMain.handle('printer:discover', () => discoverPrinters());

// USB 프린터 목록 조회
ipcMain.handle('printer:listUsb', async () => {
  try {
    const { execFile } = require('child_process');
    const _os = require('os');

    return new Promise((resolve) => {
      if (_os.platform() === 'win32') {
        execFile('powershell', ['-NoProfile', '-Command', 'Get-Printer | Select-Object -ExpandProperty Name'], { timeout: 5000 }, (err, stdout) => {
          if (err) { resolve([]); return; }
          resolve(stdout.split('\n').map(s => s.trim()).filter(Boolean));
        });
      } else {
        execFile('lpstat', ['-p'], { timeout: 5000 }, (err, stdout) => {
          if (err) { resolve([]); return; }
          const printers = stdout.split('\n')
            .map(line => { const m = line.match(/^printer\s+(\S+)/); return m ? m[1] : null; })
            .filter(Boolean);
          resolve(printers);
        });
      }
    });
  } catch (err) {
    console.error('[listUsbPrinters] error:', err.message);

    return [];
  }
});

// 연결 테스트 (셋업 마법사 Step 1)
ipcMain.handle('ws:test', async (_event, url, apiKey) => {
  return testConnection(url, apiKey);
});

// ─── WebSocket 연결 테스트 (마법사용) ────────────────────────────────────────
async function testConnection(url, apiKey) {
  return new Promise((resolve) => {
    try {
      const { io } = require('socket.io-client');
      // origin만 추출 — global prefix(/api) 제거하여 namespace 충돌 방지
      let originOnly = url;
      try {
        const u = new URL(url);
        originOnly = `${u.protocol}//${u.host}`;
      } catch (_) { /* ignore */ }

      // PrintGateway 네임스페이스 (/print-agent) + handshake.auth.token 인증
      const testSocket = io(`${originOnly}/print-agent`, {
        auth:         { token: apiKey },
        timeout:      5000,
        reconnection: false,
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

  const url    = activeProfile ? activeProfile.apiUrl : store.get('apiUrl');
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
  if (wsConnection) {
    try { wsConnection.disconnect(); } catch (_e) { /* ignore */ }
    wsConnection = null;
  }

  setConnectionStatus('reconnecting');

  // ─── 디버깅: 다층 probe — 어느 layer에서 막히는지 정확히 가림 ─────────────
  (async () => {
    const dns  = require('dns').promises;
    const net  = require('net');
    const http = require('http');

    // 1) DNS 해석 — localhost / 127.0.0.1 / ::1 각각 어느 family로 해석되는지
    try {
      const u = new URL(originOnly);
      const host = u.hostname;
      console.log(`[probe-1 DNS] hostname="${host}"`);
      try {
        const all = await dns.lookup(host, { all: true });
        console.log(`[probe-1 DNS] lookup all =>`, all);
      } catch (e) {
        console.log(`[probe-1 DNS] lookup ERROR:`, e.message);
      }
    } catch (e) {
      console.log('[probe-1 DNS] URL parse error:', e.message);
    }

    // 2) Raw TCP 연결 시도 — IPv4 (127.0.0.1) 와 IPv6 (::1) 양쪽 모두 시도
    const tcpProbe = (host, family) => new Promise((resolve) => {
      const s = new net.Socket();
      const t = setTimeout(() => { s.destroy(); resolve({ host, family, ok: false, err: 'timeout' }); }, 2000);
      s.on('connect', () => { clearTimeout(t); s.destroy(); resolve({ host, family, ok: true }); });
      s.on('error',   (e) => { clearTimeout(t); resolve({ host, family, ok: false, err: e.code || e.message }); });
      try { s.connect({ host, port: 5002, family }); }
      catch (e) { clearTimeout(t); resolve({ host, family, ok: false, err: e.message }); }
    });
    const r4 = await tcpProbe('127.0.0.1', 4);
    const r6 = await tcpProbe('::1',       6);
    console.log(`[probe-2 TCP IPv4 127.0.0.1:5002]`, r4);
    console.log(`[probe-2 TCP IPv6 ::1:5002]    `, r6);
    broadcastLog(`🔍 TCP v4=${r4.ok ? 'OK' : r4.err} v6=${r6.ok ? 'OK' : r6.err}`);

    // 3) Node http 모듈로 직접 GET — fetch와 다른 stack 사용
    const httpProbe = (host) => new Promise((resolve) => {
      const req = http.get({ host, port: 5002, path: '/socket.io/?EIO=4&transport=polling&t=probe', timeout: 3000 }, (res) => {
        let body = '';
        res.on('data', (c) => body += c);
        res.on('end',  ()  => resolve({ host, status: res.statusCode, body: body.slice(0, 120) }));
      });
      req.on('error',   (e) => resolve({ host, err: e.code || e.message }));
      req.on('timeout', ()  => { req.destroy(); resolve({ host, err: 'timeout' }); });
    });
    const h4 = await httpProbe('127.0.0.1');
    const h6 = await httpProbe('::1');
    console.log(`[probe-3 HTTP v4]`, h4);
    console.log(`[probe-3 HTTP v6]`, h6);
    broadcastLog(`🔍 HTTP v4=${h4.status || h4.err} v6=${h6.status || h6.err}`);

    // 4) socket.io polling 경로 (fetch) — 기존 probe
    try {
      const probeUrl = `${originOnly}/socket.io/?EIO=4&transport=polling&t=probe`;
      console.log('[probe-4 fetch] GET', probeUrl);
      const res = await fetch(probeUrl);
      const body = await res.text();
      console.log(`[probe-4 fetch] status=${res.status} body=`, body.slice(0, 200));
      broadcastLog(`🔍 fetch ${res.status}`);
    } catch (err) {
      console.log('[probe-4 fetch] ERROR:', err.message, err.cause?.message || '');
      broadcastLog(`❌ fetch failed: ${err.message}`);
    }
  })();

  const { io } = require('socket.io-client');

  // PrintGateway 네임스페이스 (/print-agent) — handshake.auth.token으로 API Key 전달
  // origin + namespace 분리 — apiUrl에 /api가 포함되어도 namespace는 prefix 없이 전달
  wsConnection = io(nsUrl, {
    auth:                  { token: apiKey },
    reconnection:          true,
    reconnectionAttempts:  Infinity,  // 무한 재시도 (백엔드 부팅 대기)
    reconnectionDelay:     2000,
    reconnectionDelayMax:  5000,       // 최대 5초로 제한 — 부팅 완료 즉시 잡히도록
    randomizationFactor:   0.3,
    timeout:               10000,
    transports:            ['polling', 'websocket'],
  });

  // ─── 디버깅: socket.io engine 단계 raw 이벤트 노출 ─────────────────────────
  wsConnection.io.on('error', (err) => {
    console.log('[socket.io.io ERROR]', err && err.message, err);
    broadcastLog(`❌ engine error: ${err?.message || err}`);
  });
  wsConnection.io.on('reconnect_attempt', (n) => {
    console.log(`[socket.io.io] reconnect_attempt #${n}`);
  });
  wsConnection.io.engine?.on?.('upgradeError', (err) => {
    console.log('[engine upgradeError]', err);
  });

  // ── 연결 이벤트 ──────────────────────────────────────────────────────────
  wsConnection.on('connect', () => {
    setConnectionStatus('connected');
    broadcastLog('✅ Conectado al servidor');

    // PrintGateway는 handshake로 인증 완료 → agent_online으로 isOnline 업데이트
    wsConnection.emit('agent_online', {
      branchId: store.get('branchId') || null,
      version:  app.getVersion(),
      ts:       Date.now(),
    });
  });

  // PrintGateway 인증 실패 시 emit하는 이벤트 — disconnect 직전에 도착
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
    // 풍부한 디버그 정보 노출
    console.log('[connect_error] message=', err?.message);
    console.log('[connect_error] type=',    err?.type);
    console.log('[connect_error] description=', err?.description);
    console.log('[connect_error] context=', err?.context);
    console.log('[connect_error] data=',    err?.data);
    console.log('[connect_error] stack=',   err?.stack);
    const detail = err?.description?.message || err?.description || err?.context?.message || '';
    broadcastLog(`❌ connect_error: ${err?.message} ${detail ? '| ' + detail : ''}`);
  });

  // ── 컨트롤 티켓 출력 ─────────────────────────────────────────────────────
  wsConnection.on('print_invoice', async (payload) => {
    if (!store.get('printControl')) {
      broadcastLog('ℹ️ print_invoice 무시 — printControl=false');

      return;
    }

    const printerCfg = getActivePrinterCfg();
    const start      = Date.now();
    const num        = payload?.invoice?.number || payload?.invoiceId || '?';

    broadcastLog(`🖨 print_invoice #${num} — imprimiendo...`);

    try {
      await printTicket(payload, printerCfg);
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
    const start      = Date.now();
    const caeTail    = payload?.afip?.cae ? String(payload.afip.cae).slice(-6) : '?';

    broadcastLog(`🖨 print_fiscal CAE:${caeTail} — imprimiendo...`);

    try {
      const html = formatFiscalHtml(payload);
      const png  = await renderHtmlToPng(html, 576);

      await printImage(png, printerCfg);
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

  // ── 임시(견적) 티켓 출력 ─────────────────────────────────────────────────
  // POS 'Imprimir Temp' 버튼 → 백엔드 POST /print/temp → branch:{id} 룸으로 emit
  // 판매번호/Forma de Pago 없는 견적용 티켓. fire-and-forget (ack 불필요).
  wsConnection.on('print_temp', async (payload) => {
    // ─── DEBUG(11-06) ───────────────────────────────────────────────────────
    console.log('[print_temp] ← payload received', {
      hasPayload: !!payload,
      keys:       payload ? Object.keys(payload) : null,
      itemsCount: Array.isArray(payload?.items) ? payload.items.length : 'not-array',
      branchId:   payload?.branchId,
      totals:     payload?.totals,
    });
    console.log('[print_temp] full payload:', JSON.stringify(payload, null, 2));

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

    try {
      console.log('[print_temp] → formatTempTicketHtml()');
      const html = formatTempTicketHtml(payload);

      console.log('[print_temp] html length =', html?.length);

      console.log('[print_temp] → renderHtmlToPng()');
      const png = await renderHtmlToPng(html, 576);

      console.log('[print_temp] png bytes =', png?.length);

      // ─── DEBUG(11-06): 렌더링된 PNG 를 디스크에 저장해서 실제 어떻게 찍힐지 확인 ─
      // virtual-printer.js 는 GS v 0 래스터 바이트를 "[이미지 WxH]" 로만 치환하므로
      // 그래픽 모드 출력물을 눈으로 검증할 수 없음 → PNG 원본을 덤프해서 파일로 열람
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

      console.log('[print_temp] → printImage()');
      await printImage(png, printerCfg);
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
function getActivePrinterCfg() {
  const profiles        = store.get('profiles') || [];
  const activeProfileId = store.get('activeProfileId');
  const activeProfile   = profiles.find(p => p.id === activeProfileId);
  return activeProfile ? activeProfile.printer : store.get('printer');
}

// ─── 프린터 테스트 출력 (Phase 11-03) ───────────────────────────────────────
async function printTest() {
  try {
    const printerCfg = getActivePrinterCfg();
    const sample = {
      store: {
        name:    'VENTAGO TEST',
        address: 'Test address',
        cuit:    '00-00000000-0',
        phone:   '-',
      },
      invoice: {
        number: '00000-00000001',
        copy:   1,
        date:   new Date().toLocaleDateString('es-AR'),
        time:   new Date().toLocaleTimeString('es-AR'),
        seller: 'Print Agent',
        client: 'Test',
      },
      items: [
        { name: 'PRUEBA DE IMPRESIÓN', qty: 1, price: 0, subtotal: 0 },
      ],
      totals:   { subtotal: 0, totalAmount: 0 },
      payments: [{ name: 'Test', amount: 0 }],
    };

    await printTicket(sample, printerCfg);
    broadcastLog('✅ Test de impresión — OK');

    return { success: true };
  } catch (err) {
    broadcastLog(`❌ Test de impresión — ${err.message}`);

    return { success: false, error: err.message };
  }
}

// ─── 프린터 탐색 (Phase 11-03) ──────────────────────────────────────────────
async function discoverPrinters() {
  try {
    return await discoverPrintersImpl();
  } catch (err) {
    broadcastLog(`❌ discoverPrinters: ${err.message}`);

    return [];
  }
}

module.exports = { setConnectionStatus, store };
