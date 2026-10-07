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
  setLabelOrientation: (o) => ipcRenderer.invoke('label:setOrientation', o),
  setPriceSelection: (selection) => ipcRenderer.invoke('label:setPriceSelection', selection),

  // 출력 파라미터 (전역: 모든 모드 + QR 공통) — { darkness 0~30, speed 2~14 }
  getPrintSettings: () => ipcRenderer.invoke('print:getSettings'),
  setPrintSettings: (settings) => ipcRenderer.invoke('print:setSettings', settings),

  fetchPriceTypes: () => ipcRenderer.invoke('priceTypes:fetch'),

  // 상품 조회 + 직접 출력
  fetchProductsByDate: (date, branchId) => ipcRenderer.invoke('products:fetchByDate', date, branchId),
  searchProducts: (query, branchId) => ipcRenderer.invoke('products:search', query, branchId),
  fetchBranches: () => ipcRenderer.invoke('branches:fetch'),
  // opciones: { simbolo: 'barras'|'qr', porEtiqueta: 1|2 } — ausente = barras (como siempre)
  printLabels: (items, opciones) => ipcRenderer.invoke('print:labels', items, opciones),

  // QR 배치 델타 (Phase 38 TAB3) — 델타 조회 + 항목별 출력(성공분 스냅샷)
  qrFetch: (args) => ipcRenderer.invoke('qr:fetch', args),
  qrPrint: (args) => ipcRenderer.invoke('qr:print', args),
  // [v1.0.29] vista previa exacta (mismo ZPL que se imprime)
  qrPreviewLote: (items, opciones) => ipcRenderer.invoke('qr:previewLote', items, opciones),
  qrPreviewTab: (args) => ipcRenderer.invoke('qr:previewTab', args),
  // [2026-10-07] «Vista Zebra» — imagen del emulador con el mismo ZPL
  vistaZebra: (args) => ipcRenderer.invoke('vista:zebra', args),

  // 업데이트 — 창 상단 띠 (renderer/update-banner.js)
  getUpdateEstado: () => ipcRenderer.invoke('update:estado'),
  buscarUpdate: () => ipcRenderer.invoke('update:buscar'),
  instalarUpdate: () => ipcRenderer.invoke('update:instalar'),
  onUpdateEstado: (cb) => ipcRenderer.on('update-estado', (_e, estado) => cb(estado)),

  // 이벤트 수신 (main → renderer)
  onConnectionStatus: (cb) => ipcRenderer.on('connection-status', (_e, s) => cb(s)),
  onPrintLog: (cb) => ipcRenderer.on('print-log', (_e, entry) => cb(entry)),
  onDiscoverProgress: (cb) => ipcRenderer.on('discover-progress', (_e, data) => cb(data)),
  onAgentInfo: (cb) => ipcRenderer.on('agent-info', (_e, info) => cb(info)),
  // 동일 API Key 로 다른 기기가 접속 → 이 기기가 대체됨 (서버 force_disconnect)
  onForceDisconnect: (cb) => ipcRenderer.on('force-disconnect', (_e, payload) => cb(payload)),
});
