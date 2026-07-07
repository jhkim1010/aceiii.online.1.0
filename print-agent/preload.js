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

  // 셋업
  completeSetup: () => ipcRenderer.invoke('setup:complete'),

  // ─── 다중 프로파일 (sucursal 연결 관리) ────────────────────────────────────
  // 프로파일 목록 조회
  getProfiles: () => ipcRenderer.invoke('profile:list'),
  // 활성 프로파일 ID 조회
  getActiveProfileId: () => ipcRenderer.invoke('profile:getActiveId'),
  // 프로파일 저장 (신규: id 없이, 수정: id 포함)
  saveProfile: (profile) => ipcRenderer.invoke('profile:save', profile),
  // 프로파일 삭제
  deleteProfile: (profileId) => ipcRenderer.invoke('profile:delete', profileId),
  // 프로파일 전환 (WebSocket 재연결 포함)
  switchProfile: (profileId) => ipcRenderer.invoke('profile:switch', profileId),

  // 이벤트 수신 (main → renderer)
  onConnectionStatus: (cb) => ipcRenderer.on('connection-status', (_e, s) => cb(s)),
  onPrintLog: (cb) => ipcRenderer.on('print-log', (_e, entry) => cb(entry)),
  onAgentInfo: (cb) => ipcRenderer.on('agent-info', (_e, info) => cb(info)),
  // 동일 API Key 로 다른 기기가 접속 → 이 기기가 대체됨 (서버 force_disconnect)
  onForceDisconnect: (cb) => ipcRenderer.on('force-disconnect', (_e, payload) => cb(payload)),
});
