# SPEC: print-agent 연결 신뢰성 UI/UX (test print + fallback 명시화 + POS 상태 pill)
생성일: 2026-07-02

## 목표
터미널↔프린터 에이전트 연결 상태를 관리자·계산원이 즉시 확인/검증할 수 있게 한다.
① 관리 페이지 원격 테스트 인쇄(ack 확인) ② fallback broadcast 명시화 ③ POS 실시간 상태 pill.

## 배경 및 컨텍스트 (2026-07-02 조사 완료)

### 로그 상태
- `api-ventago/logs/error-2026-07-02.log` — 0건. print 관련 에러 없음.
- SlowQuery: sync_outbox 705ms~2.7s (별건, 이번 스코프 아님).

### 현재 구조 (파일별)
- `api-ventago/src/app/print/print.gateway.ts` — `/print-agent` ns. `print_ack` 핸들러는 **로그만 남김** (L196-201). agent_info 에 terminals 목록 전달.
- `api-ventago/src/app/print/print.service.ts` — `emitPrintTemp(branchId, data, targetSocketId?)` (L62), `setOnline` (L302), `setOfflineBySocketId` (L314), `getTerminalThermalAgent` (L270), `hasOnlineThermalAgent` (L291). 모두 단일 쿼리 (pool 안전).
- `api-ventago/src/app/print/print.controller.ts` — `/print/temp` (L190): terminalId 매핑 시 targeted emit, 아니면 **조용히 broadcast fallback** (L239-247). 성공 응답은 `{ok:true, branchId}` 뿐 — targeted/fallback 구분 없음.
- `api-ventago/src/common/socket/websocket.gateway.ts` — 프론트향 `/realtime` ns. `register_terminal` → terminal:{id} room 이미 존재. **branch room 없음**.
- `ventago-app/src/views/branches/components/printer/PrinterConfigTab.tsx` — 에이전트 카드 (online chip, API key, 재발급). **테스트 인쇄 버튼 없음**.
- `ventago-app/src/views/homes/components/ProductList/ProductList.tsx` — autoImpTiq 체크박스 (L1600-1611), thermal 에이전트 30초 폴링 (L273-280), autoImpTiq 자동 동기화 (L287).
- `ventago-app/src/views/homes/components/ProductList/components/PaymentSummary.tsx` — 수동 Imprimir (L152).
- `print-agent/main.js` — `print_temp` 수신 (L969), `print_ack` emit 다수 (invoice 경로). 로컬 테스트 인쇄 기능 이미 존재.
- `zebra-agent/main.js` — 동일 구조, ZPL.

## 기술 스택
- 백엔드: NestJS 11 + Sequelize (`underscored: true`), socket.io
- 프론트: Next.js 13 + MUI 5, socket.io-client (기존 사용례: `useSuspendedSaleSocket.ts`)
- DB: PostgreSQL — **신규 테이블/컬럼 없음. 마이그레이션 불필요.**
- ESLint: ventago-app strict (newline-before-return, lines-around-comment, no-unused-vars)

## 태스크 목록

### 기능 ① 원격 테스트 인쇄 + print_ack 확인
- [x] TASK-1: PrintService — pending-ack 인메모리 Map<testId, resolver> + `requestTestPrint(agentId)`: findByPk 1회 → offline 이면 `{ok:false, reason:'agent_offline'}` → online 이면 socketId 로 `print_test {testId}` emit 후 ack 5초 대기 (timeout 시 `{ok:true, acked:false}`) — 파일: `print.service.ts`
- [x] TASK-2: PrintGateway — `print_ack` 핸들러에 testId 매칭 시 pending resolver 호출 추가 (기존 로그 유지) — 파일: `print.gateway.ts`
- [x] TASK-3: PrintController — `POST /print/agents/:id/test` 추가 — 파일: `print.controller.ts`
- [x] TASK-4: print-agent — `print_test` 수신 → 기존 테스트 인쇄 파이프라인 재사용 → `print_ack {testId, status, error?, elapsedMs}` — 파일: `print-agent/main.js`
- [x] TASK-5: zebra-agent — 동일 (ZPL 테스트 라벨) — 파일: `zebra-agent/main.js`
- [x] TASK-6: PrinterConfigTab — 카드에 "🖨 Imprimir prueba" 버튼 (isOnline 시만 활성) → 결과 표시: ✅ confirmada (Xms) / ⚠️ sin respuesta (versión antigua?) / 🔴 error — 파일: `PrinterConfigTab.tsx`

### 기능 ② fallback broadcast 명시화
- [x] TASK-7: `/print/temp` 성공 응답 확장: targeted 시 `{ok:true, targeted:true, agentLabel}`, fallback 시 `{ok:true, fallback:true, reason:'no_mapping'|'no_terminal'}` — 파일: `print.controller.ts`
- [x] TASK-8: 프론트 fallback warning toast (세션당 1회, module-level flag): "Este terminal no tiene comandera asignada — se imprimió en todas las comanderas de la sucursal" — 파일: `ProductList.tsx` (autoImpTiq L1150 + 수동 L1573), `PaymentSummary.tsx` (L152)

### 기능 ③ POS 실시간 상태 pill (socket push)
- [x] TASK-9: WebsocketGateway(`/realtime`) — `register_branch` 메시지 → `branch:{branchId}` room join — 파일: `websocket.gateway.ts` (+`websocket.service.ts`)
- [x] TASK-10: PrintService — setOnline / setOfflineBySocketId 후 `/realtime` `branch:{branchId}` room 에 `agent_status_changed {agentId, branchId, agentType, label, isOnline}` emit. setOfflineBySocketId 는 `returning: true` 로 branchId 확보. WebsocketGateway 주입 시 순환 의존 확인 (forwardRef 필요 여부) — 파일: `print.service.ts`
- [x] TASK-11: 프론트 훅 `useThermalAgentStatus(branchId)` — mount 시 GET /print/agents/:branchId 1회 + `/realtime` socket 구독으로 갱신. **기존 30초 폴링 제거** — 파일: `ventago-app/src/views/homes/hook/useThermalAgentStatus.ts` (신규)
- [x] TASK-12: ProductList — autoImpTiq 옆 상태 pill: 🟢 `{agentLabel}` (터미널 매핑 online) / 🟡 `Sin asignar` (매핑 없음, tooltip 안내) / 🔴 `Comandera desconectada`. 매핑 판별: cashRegister.terminal 의 thermalAgentId (없으면 응답 보강 필요 — 아래 열린 이슈) — 파일: `ProductList.tsx`

### 검증
- [x] TASK-13: ESLint 검증 (`npx eslint` — api-ventago + ventago-app 변경 파일)
- [x] TASK-14: PostgreSQL pool 안전 점검 (신규 쿼리: findByPk 1회/test, returning update 1회/disconnect — 폴링 제거로 순감소)
- [x] TASK-15: 로그 재확인 + GSD 리뷰 리포트

## 완료 기준
- ESLint 오류 0개
- 관리 페이지에서 테스트 인쇄 → 실물 출력 + ack 결과 UI 표시
- 매핑 없는 터미널 인쇄 시 warning toast 1회 노출
- POS pill 이 에이전트 연결/해제 시 폴링 없이 수초 내 갱신
- DB 쿼리 순증 없음 (30초 폴링 제거로 오히려 감소)

## 금지사항 / 주의사항
- pool 설정 (min=10, max=80) 변경 금지
- `/print/temp` 기존 필드(`ok`, `reason:'agent_offline'`) 하위 호환 유지 — 구버전 프론트/EnvioTimeline 이 그대로 동작해야 함
- 에이전트는 배포된 앱 — 구버전 에이전트는 `print_test` 미지원 → timeout 을 에러가 아닌 "sin respuesta" 로 처리. 신규 태그 릴리즈는 push-both.sh 로 별도 진행
- agent_status_changed payload 에 apiKey 절대 포함 금지
- pending-ack Map 은 timeout 시 반드시 delete (메모리 누수 방지)

## 열린 이슈
- ~~cashRegister.terminal 응답에 `thermalAgentId` 포함 여부 미확인~~ → **해결**: `getOpenCashRegister` 가 Terminal 모델 전체를 include (attributes 필터 없음) → `terminal.thermalAgentId` 이미 응답에 포함됨. 백엔드 수정 불필요.

---

## GSD 리뷰 리포트 (2026-07-02 완료)

### 변경 파일 요약
| 파일 | 변경 |
|---|---|
| `api-ventago/src/app/print/print.service.ts` | requestTestPrint + pending-ack Map, resolveTestAck, emitAgentStatusChanged, setOnline/setOfflineBySocketId returning:true |
| `api-ventago/src/app/print/print.gateway.ts` | print_ack 핸들러 testId resolver 매칭 |
| `api-ventago/src/app/print/print.controller.ts` | POST /print/agents/:id/test, /print/temp 응답 targeted/fallback 명시 |
| `api-ventago/src/app/print/print.module.ts` | WebsocketModule import |
| `api-ventago/src/common/socket/websocket.service.ts` | registerBranch / emitToBranch (room 기반, Map 불필요) |
| `api-ventago/src/common/socket/websocket.gateway.ts` | register_branch 메시지 핸들러 |
| `print-agent/main.js` | print_test 수신 → printTest() 재사용 → print_ack{testId} |
| `zebra-agent/main.js` | 동일 (ZPL 테스트 라벨) |
| `ventago-app/.../printer/PrinterConfigTab.tsx` | Imprimir prueba 버튼 + ✅/⚠️/🔴 결과 chip |
| `ventago-app/.../hook/useThermalAgentStatus.ts` | 신규 — REST 1회 + /realtime push 구독, refetch 반환 |
| `ventago-app/.../ProductList/ProductList.tsx` | 30초 폴링 제거 → 훅 전환, 상태 pill(🟢/🟡/🔴), fallback toast ×2 |
| `ventago-app/.../components/PaymentSummary.tsx` | fallback toast |
| `ventago-app/src/services/print.service.ts` | warnPrintFallbackOnce (세션당 1회) |

### 품질 검증
- [x] ESLint: api-ventago 6개 파일 + ventago-app 5개 파일 → 오류 0개
- [x] TypeScript: api-ventago tsc 통과 (기존 mp-webhook.service.spec.ts 2건은 무관한 기존 오류)
- [x] node --check: print-agent/main.js, zebra-agent/main.js 구문 OK
- [x] PostgreSQL pool: 신규 쿼리 = 테스트당 findByPk 1회. returning:true 는 별도 SELECT 없음. 30초 폴링 제거로 쿼리 순감소. pool.connect/release 직접 사용 없음 (Sequelize 관리)
- [x] 에러 핸들링: 모든 async try/catch, pending Map timeout 시 delete
- [x] 하위 호환: /print/temp 기존 필드 유지, 구버전 에이전트 timeout → "sin respuesta" 처리

### 후속 작업 / 주의사항
- **에이전트 릴리즈 필요**: print_test 는 신규 에이전트 빌드에만 포함 — `./push-both.sh` 로 태그 증가 → CI 빌드 → 매장 에이전트 업데이트 후 ack 확인 가능. 그 전까지는 "⚠️ Sin respuesta" 로 표시됨 (정상)
- 백엔드 배포 전까지 프론트 pill 은 초기 fetch 값만 표시 (push 이벤트 미수신) — api 먼저 배포 권장
- sync_outbox slow query (705ms~2.7s) 는 별건 — 다음 세션 점검 후보
