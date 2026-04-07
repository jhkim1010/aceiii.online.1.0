---
phase: 11
plan: 03
subsystem: print-agent
tags: [electron, websocket, escpos, afip, printer-discovery, fiscal]
requires: [11-02]
provides:
  - discoverPrinters() — USB (escpos-usb optional) + network subnet 9100 scan
  - formatFiscalHtml(data) — AFIP comprobante HTML (CAE, Vto.CAE, QR URL)
  - initWebSocket() — socket.io-client loop with auto-reconnect, agent_online, print_ack
  - print_invoice handler → printTicket pipeline
  - print_fiscal handler → formatFiscalHtml → renderHtmlToPng → printImage
  - printTest() — real test print via pipeline
  - broadcastLog() — live log to main window + console
affects: [print-agent]
tech-stack:
  added: [socket.io-client wire-up, escpos-usb optional require, net.Socket subnet scan]
  patterns: [graceful USB skip when libusb absent, fire-and-forget print_ack on failure, reconnection with backoff]
key-files:
  created:
    - print-agent/src/printer-discovery.js
    - print-agent/src/fiscal-formatter.js
  modified:
    - print-agent/main.js
decisions:
  - escpos-usb required inside try/catch — agents on machines without libusb still scan network
  - Subnet scan limited to /24 with 300ms timeout per host (~1s total via Promise.all)
  - print_fiscal banner derived from afip.tipo (replaces "DOCUMENTO NO VÁLIDO COMO FACTURA")
  - print_ack always sent on error (fire-and-forget so sales tx unaffected)
  - register_api_key emitted alongside agent_online for backend compatibility
  - Adapted plan variable names (mainWin/wsClient) → existing main.js naming (mainWindow/wsConnection)
metrics:
  duration: 15min
  completed: 2026-04-06
---

# Phase 11 Plan 03: fiscal-formatter + printer-discovery + WebSocket loop Summary

Wave 3은 Wave 2의 stub들 (`initWebSocket`, `printTest`, `discoverPrinters`)을 실제 동작으로 교체하고, AFIP 영수증 HTML 포맷터와 USB+네트워크 프린터 자동 탐색기를 추가한다.

## What Was Built

### 1. `src/printer-discovery.js`
- `discoverPrinters()` — USB + 네트워크 결과 통합
- USB: `escpos-usb`를 optional require (libusb 미설치 환경에서도 graceful skip — try/catch 두 단계)
- Network: `os.networkInterfaces()`로 IPv4 서브넷(/24) 추출 후 1~254 호스트에 9100 포트 TCP 연결 시도
- `Promise.all` + 300ms timeout/host → 전체 ~1초 내 완료
- APIPA(169.x) 제외

### 2. `src/fiscal-formatter.js`
- `formatFiscalHtml(data)` — `formatInvoiceHtml()` 결과의 `</body>` 직전에 AFIP 블록 + CSS 삽입
- AFIP 필드: `tipo`, `puntoVenta`, `numero`, `cae`, `vtoCae`, `qrUrl`
- 최상단 배너 텍스트 `DOCUMENTO NO VÁLIDO COMO FACTURA` → `tipo` 대문자로 교체
- `vtoCae`는 `Date` 파싱 가능하면 es-AR 형식, 실패 시 원문 그대로
- `qrUrl`은 옵셔널 — 없으면 QR 행 제외
- 결정적 출력 검증: 직접 스모크 테스트로 9.4KB HTML 생성 확인 (CAE 문자열 포함)

### 3. `main.js` WebSocket loop
- `initWebSocket()`:
  - `apiUrl`/`apiKey` 누락 시 setup 미완료 안내 후 return
  - 기존 `wsConnection` 정리
  - `socket.io-client`로 `${apiUrl}/realtime` 연결, auth.token = apiKey, 자동 재연결 (3s → max 15s)
  - `connect`: `setConnectionStatus('connected')` + `agent_online` + `register_api_key` emit
  - `disconnect`/`connect_error`: 상태 업데이트 + 로그
- `print_invoice` 핸들러:
  - `printControl=false`면 무시
  - `printTicket(payload, printerCfg)` 호출
  - 성공/실패 둘 다 `print_ack` 전송 (fire-and-forget)
- `print_fiscal` 핸들러:
  - `printFiscal=false`면 무시
  - `formatFiscalHtml` → `renderHtmlToPng(html, 576)` → `printImage(png, cfg)`
  - 성공/실패 둘 다 `print_ack` 전송
- `broadcastLog(msg)`: 메인창 webContents `print-log` 이벤트 + 콘솔 로그 (es-AR 시간 prefix)
- `printTest()` stub 제거 → 실제 sample payload로 `printTicket()` 호출
- `discoverPrinters()` stub 제거 → `printer-discovery` 모듈로 위임
- `setup:complete` 핸들러: 마법사 닫은 후 메인 창 자동 오픈 (Wave 2 known stub 해소)

## Plan vs Implementation 차이점

1. **변수명 적응** — 플랜의 `mainWin` / `wsClient` / `tray.setToolTip()` 직접 호출은 기존 main.js의 `mainWindow` / `wsConnection` / `setConnectionStatus()` 흐름과 충돌. 기존 명명을 유지하고 트레이 상태는 기존 `setConnectionStatus()` 경로로 업데이트 (이 함수는 트레이 메뉴 + 메인창 둘 다 갱신).
2. **`/realtime` 네임스페이스** — Wave 2의 `ws:test` IPC가 이미 `${url}/realtime`을 사용 중. 일관성 유지.
3. **`register_api_key` emit 추가** — Wave 2 마법사가 사용한 인증 패턴 호환을 위해 `auth.token` 외에 `register_api_key`도 함께 전송 (Rule 2 — backend 호환).
4. **`printControl`/`printFiscal` 토글 존중** — 플랜에는 명시 없으나 electron-store에 이미 존재하는 토글이므로 핸들러에서 체크 (Rule 2 — UX correctness).
5. **`setup:complete`에서 메인창 오픈** — Wave 2가 known stub으로 남긴 부분 해소.

## Deviations from Plan

**[Rule 2 — Missing critical functionality]** Wave 2 known stubs 중 `setup:complete` 후 메인창 자동 오픈 부분이 wire되어 있지 않았음. `openMainWindow()` 호출 추가.

**[Rule 2 — Backend compatibility]** `register_api_key` emit을 `connect` 이벤트에서 추가 — Wave 2 마법사 테스트 경로와 동일한 인증 패턴 유지.

**[Rule 2 — UX]** `printControl=false` / `printFiscal=false` 토글 시 출력 이벤트 무시. electron-store 기본 schema에 이미 존재하는 토글이지만 플랜에는 언급 없었음.

## 완료 기준 검증

- [x] `discoverPrinters()` USB 탐지 (libusb 없으면 빈 배열) — try/catch 두 단계
- [x] `discoverPrinters()` 로컬 서브넷 9100 스캔 결과 반환
- [x] `formatFiscalHtml()` CAE/Vto.CAE/QR URL 블록 포함 — 스모크 테스트 통과
- [x] `initWebSocket()` 연결 성공 시 `agent_online` emit
- [x] `print_invoice` → `printTicket()` → `print_ack ok`
- [x] `print_fiscal` → `formatFiscalHtml` → PNG → `printImage` → `print_ack ok`
- [x] 출력 실패 시 `print_ack error` 전송 (판매 트랜잭션 영향 없음)
- [x] 트레이 툴팁/메뉴가 `setConnectionStatus()` 통해 실시간 갱신
- [x] 메인창 로그에 출력 이벤트 결과 실시간 표시 (`broadcastLog`)

## Known Stubs

None. 모든 Wave 2 known stub이 해소됨:
- ~~`initWebSocket()`~~ → 실제 구현
- ~~`printTest()`~~ → 실제 sample 출력
- ~~`discoverPrinters()`~~ → printer-discovery 위임
- ~~`setup:complete` 후 메인창 오픈~~ → wired

남은 Wave 4 작업: 백엔드 PrintService, DB 마이그레이션, 프론트 설정 UI, electron-builder 패키징.

## Commits (nested print-agent repo)

| Hash    | Message |
|---------|---------|
| 36ff670 | feat(11-03): add USB+network printer discovery |
| a29f96f | feat(11-03): add AFIP fiscal HTML formatter |
| d1c02d5 | feat(11-03): wire WebSocket loop with print_invoice/print_fiscal handlers |

## Self-Check: PASSED

- print-agent/src/printer-discovery.js — FOUND
- print-agent/src/fiscal-formatter.js — FOUND
- print-agent/main.js (modified) — FOUND
- commit 36ff670 — FOUND in print-agent repo
- commit a29f96f — FOUND in print-agent repo
- commit d1c02d5 — FOUND in print-agent repo
