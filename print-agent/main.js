// print-agent/main.js
// VentaGO Print Agent — Electron 메인 프로세스
const { app, BrowserWindow, Tray, Menu, ipcMain, nativeImage, shell } = require('electron');
const path = require('path');
const fs = require('fs');
const os = require('os');
const Store = require('electron-store');
const { printTicket }       = require('./src/print-pipeline');
const { formatFiscalHtml }  = require('./src/fiscal-formatter');
const { formatQrHtml }      = require('./src/qr-formatter');
const { formatTempTicketHtml } = require('./src/formatter');
const { renderHtmlToPng }   = require('./src/renderer-engine');
const { printImage, testConnection: testPrinterConnection } = require('./src/printer');
const { discoverPrinters: discoverPrintersImpl } = require('./src/printer-discovery');
const { listSystemPrinters } = require('./src/win-printer');

// ─── 개발 모드 감지 ─────────────────────────────────────────────────────────
// `npm run dev` (= electron . --dev) 실행 시 process.argv 에 '--dev' 가 포함됨.
// dev 모드에서는:
//   1) SERVER_URL 을 로컬 NestJS (localhost:5002) 로 전환
//   2) printer.js 의 printImage 가 실 프린터 대신 ~/Desktop/print-debug-*.png 로 저장 (PNG 미리보기 모드)
const IS_DEV = process.argv.includes('--dev') || process.env.PRINT_AGENT_DEV === '1';

// 다른 모듈(printer.js 등) 에서 동일하게 인식하도록 env var 도 함께 세팅
if (IS_DEV) process.env.PRINT_AGENT_DEV = '1';

// ─── 고정 서버 URL (운영 = 도메인 경유, dev = 로컬 백엔드) ───────────────────
const SERVER_URL = IS_DEV
  ? 'http://localhost:5002/api'
  : 'https://newapi.coolsistema.com/api';

console.log(`[print-agent] 모드: ${IS_DEV ? 'DEV (로컬 백엔드 + PNG 미리보기)' : 'PROD'}`);
console.log(`[print-agent] SERVER_URL: ${SERVER_URL}`);

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
      deviceName: '',   // Windows/시스템 프린터 이름 (type='windows' 일 때 사용)
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

  // DEV 모드: 툴팁 + macOS 메뉴바 텍스트 라벨로 명시
  if (IS_DEV) {
    tray.setToolTip('VentaGO Print Agent — 🛠️ DEV MODE (PNG preview)');

    // macOS 만 setTitle 이 메뉴바 아이콘 옆 텍스트로 표시됨 (Windows/Linux 는 noop)
    if (process.platform === 'darwin' && typeof tray.setTitle === 'function') {
      tray.setTitle('DEV');
    }
  } else {
    tray.setToolTip('VentaGO Print Agent');
  }

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

  // DEV 모드 배지: 메뉴 최상단에 비활성화된 라벨로 항상 노출
  const devBadge = IS_DEV
    ? [
        {
          label: `🛠️  DEV MODE — PNG preview → ${path.join(os.homedir(), 'Desktop')}`,
          enabled: false,
        },
        { label: `   API: ${SERVER_URL}`, enabled: false },
        { type: 'separator' },
      ]
    : [];

  const contextMenu = Menu.buildFromTemplate([
    ...devBadge,
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

// dev 모드 여부 노출 — renderer 의 DEV 배너 표시용
ipcMain.handle('agent:isDev', () => IS_DEV);

// 에이전트 고정 서버 URL 반환 (셋업 마법사 — 사용자 입력 불필요, 단일 출처)
ipcMain.handle('agent:serverUrl', () => SERVER_URL);

// 활성 프로파일의 프린터 reachability 점검 (renderer 가 주기 호출).
//   - network 타입 → host:port 에 TCP socket connect (2s timeout)
//   - usb 타입     → escpos-usb 로 vendor/product id 매칭 시도
//   - dev 모드     → 항상 ok=true + devPreview=true (실 프린터 점검 안 함)
// 반환 shape: { ok, ms?, error?, devPreview?, type, endpoint }
ipcMain.handle('printer:probe', async () => {
  const profiles = store.get('profiles') || [];
  const activeProfileId = store.get('activeProfileId');
  const active = profiles.find((p) => p.id === activeProfileId);
  const printer = active?.printer || store.get('printer') || {};
  const type = printer.type || 'network';

  // endpoint 문자열 미리 만들어두기 — renderer 표시용
  let endpoint;
  if (type === 'usb') {
    endpoint = `USB ${printer.vendorId || '0x?'}:${printer.productId || '0x?'}`;
  } else if (type === 'windows') {
    endpoint = printer.deviceName || '(sin nombre)';
  } else {
    endpoint = `${printer.host || '(sin host)'}:${printer.port || 9100}`;
  }

  if (IS_DEV) {
    return { ok: true, devPreview: true, type, endpoint };
  }

  // Windows/시스템 프린터: 이름이 OS 프린터 목록에 존재하는지 확인
  if (type === 'windows') {
    try {
      const list = await listSystemPrinters();
      const match = list.find((p) => p.name === printer.deviceName);

      return match
        ? { ok: true, type, endpoint }
        : { ok: false, error: 'impresora_no_encontrada', type, endpoint };
    } catch (e) {
      return { ok: false, error: e.message || 'windows_error', type, endpoint };
    }
  }

  if (type === 'network') {
    const host = printer.host;
    const port = Number(printer.port) || 9100;
    if (!host) {
      return { ok: false, error: 'sin_host_configurado', type, endpoint };
    }
    const net = require('net');
    const t0 = Date.now();

    return await new Promise((resolve) => {
      const s = new net.Socket();
      const finish = (res) => {
        try { s.destroy(); } catch (_e) { /* ignore */ }
        resolve(res);
      };
      const timer = setTimeout(() => finish({ ok: false, error: 'timeout', type, endpoint }), 2000);
      s.once('connect', () => {
        clearTimeout(timer);
        finish({ ok: true, ms: Date.now() - t0, type, endpoint });
      });
      s.once('error', (e) => {
        clearTimeout(timer);
        finish({ ok: false, error: e.code || e.message || 'error', type, endpoint });
      });
      try {
        s.connect({ host, port });
      } catch (e) {
        clearTimeout(timer);
        finish({ ok: false, error: e.message || 'connect_throw', type, endpoint });
      }
    });
  }

  // USB
  if (type === 'usb') {
    try {
      const usbLib = require('escpos-usb');
      const vid = parseInt(printer.vendorId, 16);
      const pid = parseInt(printer.productId, 16);
      const list = usbLib.findPrinter ? usbLib.findPrinter() : [];
      const match = list.find(
        (d) =>
          (!vid || d.deviceDescriptor?.idVendor === vid) &&
          (!pid || d.deviceDescriptor?.idProduct === pid),
      );

      return match
        ? { ok: true, type, endpoint }
        : { ok: false, error: 'usb_no_encontrado', type, endpoint };
    } catch (e) {
      return { ok: false, error: e.message || 'usb_error', type, endpoint };
    }
  }

  return { ok: false, error: `tipo_no_soportado:${type}`, type, endpoint };
});

// 프린터 탐색 (Phase 11-02에서 구현)
ipcMain.handle('printer:discover', () => discoverPrinters());

// 시스템(OS) 프린터 목록 조회 — Windows 이름 기반 선택용.
// getPrintersAsync 결과 반환: { name, displayName, status, isDefault }
ipcMain.handle('printer:listSystem', async () => {
  try {
    return await listSystemPrinters();
  } catch (err) {
    broadcastLog(`❌ listSystemPrinters: ${err.message}`);

    return [];
  }
});

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
  if (wsConnection) {
    try { wsConnection.disconnect(); } catch (_e) { /* ignore */ }
    wsConnection = null;
  }

  setConnectionStatus('reconnecting');

  // ─── 디버깅: 다층 probe — 어느 layer에서 막히는지 정확히 가림 ─────────────
  // ─── 연결 전 진단 probe (운영-aware) ────────────────────────────────────────
  // 기존 probe 는 localhost:5002 를 하드코딩해 운영(https)에서는 무의미했음.
  // → 실제 접속 대상(originOnly)에서 host·port·protocol 을 추출해 도달성과
  //   engine.io 핸드셰이크 응답(상태/본문/헤더)을 캡처한다. 400 의 진짜 원인
  //   (engine.io code, 응답 출처가 nginx/cloudflare/backend 인지)을 가린다.
  (async () => {
    const net   = require('net');
    const http  = require('http');
    const https = require('https');

    // probe-0) origin 파싱 — host/port/protocol 추출 (하드코딩 제거)
    let probeHost = '';
    let probePort = 0;
    let isHttps   = false;
    try {
      const pu  = new URL(originOnly);
      probeHost = pu.hostname;
      isHttps   = pu.protocol === 'https:';
      probePort = pu.port ? Number(pu.port) : (isHttps ? 443 : 80);
      console.log(`[probe-0] origin=${originOnly} host=${probeHost} port=${probePort} https=${isHttps}`);
    } catch (e) {
      console.log('[probe-0] URL parse error:', e.message);
      broadcastLog(`❌ origin URL inválida: ${e.message}`);

      return;
    }

    // probe-1) Raw TCP 도달성 (방화벽/네트워크 차단 확인)
    const tcpProbe = () => new Promise((resolve) => {
      const s = new net.Socket();
      const t = setTimeout(() => { s.destroy(); resolve({ ok: false, err: 'timeout' }); }, 2500);
      s.on('connect', () => { clearTimeout(t); s.destroy(); resolve({ ok: true }); });
      s.on('error',   (e) => { clearTimeout(t); resolve({ ok: false, err: e.code || e.message }); });
      try { s.connect({ host: probeHost, port: probePort }); }
      catch (e) { clearTimeout(t); resolve({ ok: false, err: e.message }); }
    });
    const tcp = await tcpProbe();
    console.log(`[probe-1 TCP ${probeHost}:${probePort}]`, tcp);
    broadcastLog(`🔍 TCP ${probeHost}:${probePort} ${tcp.ok ? 'OK' : tcp.err}`);

    // probe-2) engine.io polling 핸드셰이크 직접 호출 — status + body(code/message) + 헤더.
    //   응답 출처 식별 헤더(server/via/cf-ray) + sticky 쿠키 유무로 400 원인을 좁힌다.
    const lib = isHttps ? https : http;
    const handshakeProbe = () => new Promise((resolve) => {
      const url = `${originOnly}/socket.io/?EIO=4&transport=polling&t=probe${Date.now()}`;
      const req = lib.get(url, { timeout: 4000 }, (res) => {
        let body = '';
        res.on('data', (c) => { body += c; });
        res.on('end',  ()  => resolve({
          status:    res.statusCode,
          body:      body.slice(0, 200),
          server:    res.headers['server'],
          via:       res.headers['via'],
          cfRay:     res.headers['cf-ray'],
          setCookie: res.headers['set-cookie'] ? 'present' : 'absent',
          poweredBy: res.headers['x-powered-by'],
        }));
      });
      req.on('error',   (e) => resolve({ err: e.code || e.message }));
      req.on('timeout', ()  => { req.destroy(); resolve({ err: 'timeout' }); });
    });
    const hs = await handshakeProbe();
    console.log('[probe-2 handshake]', hs);
    broadcastLog(`🔍 handshake ${hs.status || hs.err}${hs.body ? ' · ' + hs.body.slice(0, 60) : ''}`);
    broadcastLog(`🔍 resp origen: server=${hs.server || '?'} cookie=${hs.setCookie || '?'}${hs.cfRay ? ' cf-ray=' + hs.cfRay : ''}`);
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

    // polling 먼저 → upgrade to websocket. websocket-only 로 두면 일부 환경에서
    // upgrade 실패 시 무한 reconnecting 으로 빠짐. polling fallback 으로 항상 연결 보장.
    transports:            ['polling', 'websocket'],
    upgrade:               true,
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

  // ─── 디버깅: engine transport 생명주기 — 어느 transport(polling/websocket)에서
  //     끊기는지, sid 가 발급되는지 추적. 400 이 polling 단계에서 나는지 확인용. ──
  wsConnection.io.on('open', () => {
    const eng = wsConnection.io.engine;
    console.log(`[engine open] transport=${eng?.transport?.name} sid=${eng?.id}`);
    broadcastLog(`🔧 engine open · ${eng?.transport?.name || '?'}`);

    eng?.on?.('upgrade', (t) => {
      console.log(`[engine upgrade] → ${t?.name}`);
      broadcastLog(`🔧 upgrade → ${t?.name}`);
    });
    eng?.on?.('upgradeError', (e) => {
      console.log('[engine upgradeError(open)]', e?.message);
    });
    eng?.on?.('close', (reason) => {
      console.log(`[engine close] reason=${reason} transport=${eng?.transport?.name}`);
    });
  });

  // ── 연결 이벤트 ──────────────────────────────────────────────────────────
  wsConnection.on('connect', () => {
    setConnectionStatus('connected');
    broadcastLog('✅ Conectado al servidor');

    // DEBUG(11-08): socket id + 사용 중인 apiKey prefix 노출 — 어느 agent(=branch)로
    // 인증됐는지 확인. branch 룸 join 은 서버(handleConnection)가 apiKey 기준으로 하므로,
    // 여기 apiKey 가 의도한 지점의 것인지가 print_temp 수신 여부를 결정한다.
    const _activeProfiles = store.get('profiles') || [];
    const _activeId       = store.get('activeProfileId');
    const _active         = _activeProfiles.find((p) => p.id === _activeId);
    const _key            = _active ? _active.apiKey : store.get('apiKey');
    console.log(`[connect] socket.id=${wsConnection.id} apiKey=${_key ? _key.slice(0, 12) + '…' : 'EMPTY'} profile=${_active?.label || '(single)'}`);
    broadcastLog(`🔌 socket ${wsConnection.id} · perfil "${_active?.label || '—'}"`);

    // PrintGateway는 handshake로 인증 완료 → agent_online으로 isOnline 업데이트
    wsConnection.emit('agent_online', {
      branchId: store.get('branchId') || null,
      version:  app.getVersion(),
      ts:       Date.now(),
    });
  });

  // 인증 성공 시 매장/지점 정보 수신 → UI 전달 + 로그
  wsConnection.on('agent_info', (info) => {
    console.log('[agent_info]', info);
    store.set('_lastAgentInfo', info);
    broadcastLog(`🏪 ${info.storeName || ''} — ${info.branchName || ''} (${info.label || ''})`);
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('agent-info', info);
    }
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

  // ─── 400 진단: polling 핸드셰이크 원본 응답 1회 캡처 ────────────────────────
  // socket.io 의 connect_error 는 description=400(숫자)만 주고 본문은 숨긴다.
  // engine.io 400 본문 {"code":N,"message":"..."} 의 code 가 원인을 확정한다:
  //   0=Transport unknown, 1=Session ID unknown(다중 인스턴스/재시작),
  //   2=Bad handshake method, 3=Bad request(프록시가 쿼리 변형), 5=프로토콜 불일치.
  // 재연결 폭주로 로그가 도배되지 않도록 5초 throttle.
  let _lastDiag = 0;
  async function diagnose400() {
    const now = Date.now();
    if (now - _lastDiag < 5000) {
      return;
    }
    _lastDiag = now;
    try {
      const url = `${originOnly}/socket.io/?EIO=4&transport=polling&t=diag${now}`;
      const res = await fetch(url);
      const body = await res.text();
      console.log(`[diag-400] status=${res.status} body=${body.slice(0, 200)}`);
      console.log('[diag-400] server=', res.headers.get('server'),
        '| set-cookie=', res.headers.get('set-cookie'),
        '| cf-ray=', res.headers.get('cf-ray'),
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

  // Phase 38 — CodigoMadre QR 라벨 출력
  wsConnection.on('print_qr', async (payload) => {
    const printerCfg = getActivePrinterCfg();
    const start = Date.now();
    const code = payload?.code || '?';

    broadcastLog(`🖨 print_qr ${code} — imprimiendo...`);

    try {
      const html = await formatQrHtml(payload);
      const png = await renderHtmlToPng(html, 576);

      await printImage(png, printerCfg);
      broadcastLog(`✅ print_qr ${code} — OK (${Date.now() - start}ms)`);
      wsConnection.emit('print_ack', { code, status: 'ok', ts: Date.now() });
    } catch (err) {
      broadcastLog(`❌ print_qr ${code} — ${err.message}`);
      wsConnection.emit('print_ack', { code, status: 'error', error: err.message, ts: Date.now() });
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
