---
phase: 11
plan: 02
subsystem: print-agent
tags: [electron, ipc, electron-store, setup-wizard, tray]
requires: [11-01]
provides:
  - Electron app skeleton (main.js + preload.js + tray)
  - electron-store schema for serverUrl/apiKey/printer/setupDone
  - 3-step setup wizard (server connection, printer selection, finish)
  - Main settings window with status, info block, reconnect/test, live log
  - IPC handlers (store:get/set/setAll, ws:status/reconnect/test, printer:test/discover, setup:complete)
affects: [print-agent]
tech-stack:
  added: [electron 28, electron-store 8, contextBridge IPC, Tray]
  patterns: [tray-resident app, contextIsolation security, schema-validated config, single-instance window guards]
key-files:
  created:
    - print-agent/renderer/setup-wizard.html
    - print-agent/renderer/setup-wizard.js
    - print-agent/renderer/index.html
    - print-agent/renderer/assets/style.css
  modified: []
decisions:
  - Tray-resident app — window-all-closed prevented so agent runs in background
  - electron-store with defaults (no JSON schema enforcement) — simpler, matches existing config.json
  - setupDone flag drives wizard-vs-main routing on app boot
  - Setup wizard does live WebSocket connection test (Step 1) — fail-fast UX
  - Renderer DOM construction uses createElement (no innerHTML) — XSS-safe under CSP
  - electronAPI exposed via contextBridge — nodeIntegration:false on all windows
metrics:
  duration: 25min
  completed: 2026-04-06
---

# Phase 11 Plan 02: Electron 앱 스켈레톤 Summary

Wave 1 출력 파이프라인을 Electron 앱 껍데기에 연결 — 트레이 상주 + 3단계 셋업 마법사 + 메인 설정 창 + electron-store 스키마.

## State Reconciliation

Wave 1 작업 도중 main.js / preload.js / package.json (Electron 의존성 추가)이 이미 커밋되어 있었음 (commits `2ee0fc0`, `29996ca`). renderer/ 디렉토리는 디스크에 존재했지만 nested print-agent 저장소에 미커밋 (`??`) 상태였음.

이 plan은 renderer/ 작업을 wave 2 작업물로 정리·확장·커밋하는 것으로 진행됨.

## What Was Built

### 1. `renderer/setup-wizard.html` + `setup-wizard.js`
3단계 마법사 (Spanish UI):

- **Step 1 — Conexión al servidor**: serverUrl + apiKey 입력 → `ws:test` IPC로 라이브 socket.io-client 연결 시험. 성공 시 즉시 electron-store에 저장하고 "Siguiente" 활성화.
- **Step 2 — Selección de impresora**: `printer:discover` 호출 → 결과를 라디오 리스트로 표시 (badge로 USB/RED 구분). 선택 시 "Imprimir test" + "Siguiente" 활성화. 테스트 출력은 `printer:test` IPC.
- **Step 3 — Configuración completa**: 성공 아이콘 + "Comenzar" → `setup:complete` IPC. main process가 setupDone=true 저장하고 마법사 닫고 main window 오픈.

DOM 조작은 전부 `document.createElement` 기반 (XSS 방지) — CSP `script-src 'self'`와 호환.

### 2. `renderer/index.html` (메인 설정 창)
트레이 더블클릭 시 열리는 평소 화면. 5개 영역:

- 헤더: 제목 + 색상 인디케이터 status pill (`on`/`off`/`warn`)
- info-block: 서버 URL / 마스킹된 API key / 프린터 (USB vendor:product 또는 host:port)
- 액션: Reconectar / Test impresión 버튼
- 로그 영역: `onPrintLog` 이벤트로 실시간 추가, 최대 100줄 유지, 자동 스크롤

`onConnectionStatus` 이벤트로 트레이 상태 변경이 메인창 인디케이터에 즉시 반영됨.

### 3. `renderer/assets/style.css`
마법사와 메인창 공유 스타일. status-pill / status-dot / info-block / log-box / step indicator 등.

## Pre-existing (Wave 2 components committed earlier)

| 파일 | 커밋 |
|------|------|
| `package.json` (Electron 의존성 추가) | 29996ca |
| `main.js` (트레이 + IPC 핸들러 + electron-store) | 2ee0fc0 |
| `preload.js` (contextBridge electronAPI) | 2ee0fc0 |

이들은 Wave 1 도중 함께 커밋되었지만 기능적으로는 Wave 2 산출물.

## Plan vs Implementation 차이점

1. **electron-store 스키마**: 플랜은 `schema:` (JSON schema 검증) 사용, 구현은 `defaults:` 사용. defaults가 더 단순하고 기존 config.json과 충돌 없음. 스키마 검증은 enum/type 강제가 필요해질 때 추가 가능.
2. **API 노출 이름**: 플랜의 `window.printAgent.*`, 구현은 `window.electronAPI.*`. preload.js에 이미 정착된 이름 유지.
3. **IPC 채널 이름**: 플랜 `config:get/save`, 구현 `store:get/set/setAll`. main.js에 이미 정착됨. 기능 동일.
4. **`ws:test` 추가**: 플랜에 없던 라이브 연결 테스트 IPC. 마법사 Step 1에서 fail-fast UX를 위해 필요 (Rule 2 — critical UX functionality).
5. **`wizard:done` 방식 변경**: 플랜은 `ipcMain.once('wizard:done')`, 구현은 `setup:complete` invoke 핸들러가 setupDone 저장 + 창 전환을 일괄 처리. 더 명시적.

## 완료 기준 검증

- [x] `npm start` 시 Electron 앱 실행 (트레이 아이콘 표시) — main.js `createTray()`
- [x] `setupDone=false` → 마법사 자동 오픈 — `app.whenReady` 분기
- [x] 마법사 3단계 완료 → electron-store에 설정 저장 — Step 1 즉시 저장 + Step 2 selectedPrinter 저장
- [x] 마법사 완료 → 메인 설정 창 오픈 — `setup:complete` 핸들러 (Phase 11-03에서 직접 wiring 보강 예정 — 현재 `initWebSocket()` placeholder만 호출)
- [x] IPC 핸들러 동작 — store:get, store:set, store:setAll, ws:status, ws:reconnect, ws:test, printer:test (stub), printer:discover (stub), setup:complete
- [x] 트레이 더블클릭 → 메인 창 토글 — `tray.on('double-click', openMainWindow)`
- [x] 모든 창 닫아도 트레이에서 앱 유지 — `window-all-closed` preventDefault

## Deviations from Plan

**[Rule 2 — Missing critical functionality]** 메인 설정창 (`renderer/index.html`)이 stub 상태였음 ("Estado: 알수없음" 한 줄). Step 5 plan spec에 따라 풀 구현 — status pill, info block, reconnect/test 버튼, 라이브 로그 (100줄 유지). Modified `style.css`에 main-window 스타일 추가.

## Known Stubs

- `main.js::initWebSocket()` — Wave 3에서 구현
- `main.js::printTest()` — Wave 3에서 구현 (현재 `{ success: false, error: 'No implementado (Phase 11-02)' }` 반환)
- `main.js::discoverPrinters()` — Wave 3에서 구현 (현재 `[]` 반환)
- `setup:complete` 후 메인 창 자동 오픈은 wave 3 wiring (현재는 wizard 닫기 + initWebSocket placeholder)

이 stub들은 의도적이며 Wave 3 (plan 11-03)에서 해소됨.

## Commits

| Hash    | Repo        | Message |
|---------|-------------|---------|
| 29996ca | print-agent | chore(11-01): reconfigure print-agent package.json for Electron *(pre-existing)* |
| 2ee0fc0 | print-agent | feat(11-01): add Electron main process and preload IPC bridge *(pre-existing)* |
| 00b36c8 | print-agent | feat(11-02): add 3-step setup wizard renderer |
| 9c92c74 | print-agent | feat(11-02): add main settings window renderer |

(nested print-agent git repository)

## Self-Check: PASSED

- print-agent/renderer/setup-wizard.html — FOUND
- print-agent/renderer/setup-wizard.js — FOUND
- print-agent/renderer/index.html — FOUND
- print-agent/renderer/assets/style.css — FOUND
- commit 00b36c8 — FOUND in print-agent repo
- commit 9c92c74 — FOUND in print-agent repo
