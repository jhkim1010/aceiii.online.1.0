# Print Agent 문제 분석 리포트 (2026-07-06)

분석 범위: `api-ventago/src/app/print/*`, `print-agent/*`, 로컬 최신 로그(2026-07-03), 로컬 DB.
참고: SSH MCP 미연결로 운영 서버 로그/DB는 이번 세션에서 직접 확인 못 함 — 운영 확인 필요 항목 표시.

---

## 심각도 높음

### 1. print_invoice / reprint / print_fiscal 에 터미널 라우팅 없음 → 중복 출력
- `/print/temp` 만 terminalId → thermal_agent_id 라우팅이 구현됨 (2026-07-02 작업).
- 판매 확정 티켓(`sales-create.service.ts:983`), 재인쇄(`:1007`), fiscal 영수증은 여전히 `branch:{id}` broadcast.
- **테스트 A 재현**: 지점 룸에 에이전트 2개 접속 → broadcast 1회에 양쪽 모두 수신(각 1회) → comandera 2대 지점에서 판매마다 티켓 2장 출력.
- 수정: `sendToprinters`/`reprintSale` 에 sale.terminalId 기반 `getTerminalThermalAgent` 라우팅 적용 (+ fallback 유지).

### 2. 터미널→에이전트 매핑이 실제로 전혀 설정되지 않음
- 로컬 DB: `terminals.thermal_agent_id / zebra_agent_id` 전 행 NULL. branch 1 에는 thermal 에이전트 2대 등록.
- 매핑이 없으므로 라우팅 코드가 있어도 **항상 fallback broadcast 경로**로 동작 → 문제 1이 항상 발현.
- **운영 DB 확인 필요**: `SELECT id, name, thermal_agent_id FROM terminals WHERE is_deleted=false;`
- 수정: 매핑 UI 안내/온보딩 또는 에이전트 1대뿐인 지점은 자동 매핑.

### 3. 운영 빌드에 DevTools 자동 오픈 (디버그 잔재)
- `print-agent/main.js:241` — `mainWindow.webContents.openDevTools({ mode: 'detach' })` 가 조건 없이 실행.
- 배포된 에이전트에서 매장 PC에 DevTools 창이 뜸.
- 수정: `if (IS_DEV)` 가드.

---

## 심각도 중간

### 4. 테스트 인쇄 ack 5초 고정 타임아웃 → 위양성 실패 보고
- `PrintService.TEST_ACK_TIMEOUT_MS = 5000`. 에이전트의 print_test 는 HTML→PNG 렌더 + 프린터 전송 전체 파이프라인 실행 후 ack.
- **테스트 B 재현**: ack 가 타임아웃보다 늦으면 `acked:false` 반환, 늦게 도착한 ack 는 no-op → 실제로 출력됐는데 UI 에는 "응답 없음".
- escpos-network `device.open` 에 자체 connect 타임아웃 없음 → 프린터 다운 시 OS TCP 타임아웃(수십 초)까지 hang.
- 수정: 타임아웃 10–15초로 상향 + 에이전트 printer 연결에 2–3초 connect 타임아웃 도입.

### 5. print_temp 마다 PNG 디스크 덤프 + full payload 콘솔 출력 (디버그 잔재)
- `main.js:1044–1055` — 매 출력마다 `os.tmpdir()/ventago-print/temp-*.png` 저장, 정리 없음 → 디스크 누적.
- `main.js:1012` — `JSON.stringify(payload, null, 2)` 전체 판매내역 콘솔 출력 (성능 + 정보 노출).
- 수정: IS_DEV 가드 또는 제거.

### 6. emitPrintBarcode / emitPrintQr — 오프라인 에이전트에 조용히 드랍
- `agentId` 지정 시 `findByPk().then()` 에 `.catch` 없음 (unhandled rejection 가능).
- 에이전트 offline(`socketId` null)이면 emit 안 하고 API 는 `ok:true` 반환 → 라벨이 안 나와도 프론트는 성공 표시.
- 수정: async 로 전환, offline 시 `{ ok:false, reason:'agent_offline' }` 반환.

### 7. print_temp / print_invoice ack 미활용
- print_temp 는 에이전트가 ack 자체를 안 보냄. print_invoice ack 는 게이트웨이가 로그만 남김 (저장·재시도·POS 통지 없음).
- broadcast fallback 에선 출력 실패를 서버·POS 어느 쪽도 알 수 없음.
- 수정(후속): invoiceId ack 를 sale.print 상태로 기록하거나 realtime push 로 POS pill 에 실패 반영.

---

## 심각도 낮음 / 주의

### 8. 30초 주기 프린터 TCP probe 와 인쇄 충돌 가능
- renderer 가 30초마다 프린터 9100 포트에 TCP connect (`index.html:654`). 단일 연결만 허용하는 저가 열전사 프린터에서 probe 와 인쇄가 겹치면 간헐 "프린터 연결 실패" 발생 가능.
- 수정: 인쇄 중 probe 스킵(뮤텍스) 또는 주기 상향.

### 9. 소켓 연결 rate-limit 의 프록시 IP 수렴
- `SOCKET_CONNECT_LIMIT=60/60s` per IP. 운영이 nginx 프록시 뒤에서 `handshake.address` 가 프록시 IP 로 수렴하면, 백엔드 재시작 시 전체 에이전트 동시 재접속이 한도를 공유. 현재 에이전트 수(≤10)로는 여유 있으나 확장 시 주의.

### 10. 다중 인스턴스 확장 시 socket.io adapter 부재
- Redis adapter 없음 → API 2인스턴스 운영 시 `server.to(socketId/room)` 이 다른 인스턴스 소켓에 도달 못 함 + polling 은 sticky session 필요. 현재 1인스턴스라 문제 없음. 확장 전 필수 선행.

### 11. formatter null payload 크래시 (경미)
- `formatTempTicketHtml(null)` / `formatInvoiceHtml(null)` throw. 서버가 항상 객체를 보내므로 실질 위험 낮음. 빈 객체·필드 누락·긴 문자열·특수문자는 모두 통과 (테스트 완료).

---

## 실행한 테스트

| 테스트 | 방법 | 결과 |
|---|---|---|
| A. 지점 broadcast 중복 수신 | socket.io 서버+클라 2대 시뮬 | 에이전트 2대 모두 수신 → 중복 출력 재현 |
| B. ack 타임아웃 위양성 | pending Map 로직 재현 (축소 타임아웃) | 느린 ack → `acked:false` + 늦은 ack no-op 재현 |
| C. formatter 강건성 | 실제 모듈 직접 호출 (엣지 payload 8종) | null 만 실패, 나머지 통과 |
| D. DB 매핑 상태 | 로컬 PG18 조회 | 매핑 전부 NULL, branch 1 thermal 2대 |
| (jest 스펙) | print.service.spec.ts | 샌드박스 메모리 한계로 실행 불가 — Mac 에서 `npx jest print` 권장 |

## 권장 수정 순서
1. #3, #5 (에이전트 디버그 잔재 제거 — 다음 릴리즈에 필수)
2. #1 (invoice/fiscal 터미널 라우팅 — api 선배포)
3. #2 (매핑 데이터 정비, 운영 DB 확인)
4. #4, #6 (타임아웃/오프라인 피드백)
5. #7, #8 (후속 신뢰성 개선)
