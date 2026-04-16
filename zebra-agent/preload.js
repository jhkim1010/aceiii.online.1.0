// zebra-agent/preload.js
// 보안 IPC 브릿지: renderer ↔ main
const { contextBridge, ipcRenderer } = require('electron');

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
  testPrinterConnection: (host, port) => ipcRenderer.invoke('printer:testConnection', host, port),

  // 셋업
  completeSetup: () => ipcRenderer.invoke('setup:complete'),

  // 이벤트 수신 (main → renderer)
  onConnectionStatus: (cb) => ipcRenderer.on('connection-status', (_e, s) => cb(s)),
  onPrintLog: (cb) => ipcRenderer.on('print-log', (_e, entry) => cb(entry)),
  onDiscoverProgress: (cb) => ipcRenderer.on('discover-progress', (_e, data) => cb(data)),
});
