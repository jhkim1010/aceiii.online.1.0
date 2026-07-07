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
  listUsbPrinters: () => ipcRenderer.invoke('printer:listUsb'),

  // 셋업
  completeSetup: () => ipcRenderer.invoke('setup:complete'),

  // 라벨 모드 / 레이아웃 / precio nivel
  getLabelPresets: () => ipcRenderer.invoke('label:presets'),
  getLabelConfig: () => ipcRenderer.invoke('label:getConfig'),
  setLabelPreset: (key) => ipcRenderer.invoke('label:setPreset', key),
  setLabelLayout: (layout) => ipcRenderer.invoke('label:setLayout', layout),
  setPriceSelection: (selection) => ipcRenderer.invoke('label:setPriceSelection', selection),
  fetchPriceTypes: () => ipcRenderer.invoke('priceTypes:fetch'),

  // 상품 조회 + 직접 출력
  fetchProductsByDate: (date) => ipcRenderer.invoke('products:fetchByDate', date),
  printLabels: (items) => ipcRenderer.invoke('print:labels', items),

  // 이벤트 수신 (main → renderer)
  onConnectionStatus: (cb) => ipcRenderer.on('connection-status', (_e, s) => cb(s)),
  onPrintLog: (cb) => ipcRenderer.on('print-log', (_e, entry) => cb(entry)),
  onDiscoverProgress: (cb) => ipcRenderer.on('discover-progress', (_e, data) => cb(data)),
  onAgentInfo: (cb) => ipcRenderer.on('agent-info', (_e, info) => cb(info)),
  // 동일 API Key 로 다른 기기가 접속 → 이 기기가 대체됨 (서버 force_disconnect)
  onForceDisconnect: (cb) => ipcRenderer.on('force-disconnect', (_e, payload) => cb(payload)),
});
