# SPEC: print-agent 문제 수정 (라우팅·디버그 잔재·타임아웃)
생성일: 2026-07-06

## 목표
분석 리포트(.planning/reports/print-agent-issues-2026-07-06.md)의 심각도 상위 3건을 수정한다:
① invoice/reprint 터미널 라우팅 ② print-agent 디버그 잔재 제거 ③ ack/connect 타임아웃 개선.

## 배경 및 컨텍스트
- `/print/temp` 만 terminalId→thermal_agent_id 라우팅 구현. `print_invoice`(판매 확정/재인쇄)는 지점 broadcast → 다중 comandera 지점 중복 출력 (테스트로 재현됨).
- `print-agent/main.js`: openDevTools 무조건 실행(241), print_temp 마다 PNG 덤프 + full payload 콘솔 출력 (디버그 잔재).
- 테스트 인쇄 ack 5초 고정 → 느린 프린터 위양성. escpos-network open 에 connect 타임아웃 없음.
- emitFiscalReceipt 는 호출처 없음 → 이번 스코프에서 제외 (변경 금지).

## 기술 스택
- 백엔드: NestJS 11 + Sequelize (pool min=10/max=80 — 변경 금지, 추가 쿼리는 단일 SELECT 만)
- 에이전트: Electron 28 + socket.io-client + escpos
- ESLint: 프로젝트 규칙 — newline-before-return, lines-around-comment, no-unused-vars

## 태스크 목록
- [x] TASK-1: `PrintService.emitPrintInvoice` 에 `targetSocketId?` 파라미터 추가 (emitPrintTemp 패턴) — 파일: api-ventago/src/app/print/print.service.ts
- [x] TASK-2: `sendToprinters` / `reprintSale` 에 sale.terminalId 기반 라우팅 적용. 매핑+online → targeted, 매핑 offline 또는 매핑 없음 → 기존 broadcast fallback (판매 티켓은 어디서든 나오는 게 우선) — 파일: api-ventago/src/app/sales/sales-create.service.ts (`resolveInvoiceTargetSocketId` 헬퍼)
- [x] TASK-3: openDevTools / PNG 덤프 / full payload 로그를 IS_DEV 가드 — 파일: print-agent/main.js
- [x] TASK-4: TEST_ACK_TIMEOUT_MS 5000→15000 (env PRINT_TEST_ACK_TIMEOUT_MS 재정의 가능) — 파일: api-ventago/src/app/print/print.service.ts
- [x] TASK-5: network 프린터 printImage 에 TCP preflight(2.5s 타임아웃) 추가 — 즉시 명확한 실패 — 파일: print-agent/src/printer.js
- [x] TASK-6: ESLint 검증 — HEAD 대비 신규 에러 0 (pre-existing 141건은 스코프 외)
- [x] TASK-7: 라우팅 로직 시뮬 테스트 — targeted/fallback/offline매핑 3케이스 PASS

## 리뷰 결과 (2026-07-06)
- ESLint: HEAD 141 에러 → 수정 후 141 (신규 0). catch any 접근 1건 발견 즉시 수정.
- 시뮬 테스트: CASE1 targeted(중복 없음)/CASE2 매핑 없음 broadcast(하위 호환)/CASE3 offline 매핑 broadcast(티켓 유실 없음) 모두 PASS.
- main.js / printer.js: node -c 구문 검사 통과. jest 는 샌드박스 메모리 한계로 미실행 → Mac 에서 `npx jest print` 권장.
- pool: 추가 쿼리는 판매당 단일 SELECT(getTerminalThermalAgent) 1회. pool 설정 무변경.

## 배포 순서 (필수)
1. api-ventago 선배포 (라우팅 + ack 타임아웃)
2. print-agent 릴리즈 (태그 push → CI 빌드) — 구버전 에이전트도 broadcast fallback 으로 정상 동작 (하위 호환)
3. 운영 DB `terminals.thermal_agent_id` 매핑 설정 — 매핑 전까지는 기존 broadcast 동작 유지

## 완료 기준
- ESLint 오류 0개 (수정 파일 기준)
- 매핑+online 터미널 판매 → 해당 comandera 로만 emit / 매핑 없음 → 기존 broadcast 유지 (하위 호환)
- print-agent 운영 모드에서 DevTools·PNG 덤프·payload 덤프 미실행

## 금지사항 / 주의사항
- DB pool 설정 변경 금지. 라우팅 추가 쿼리는 기존 `getTerminalThermalAgent` (단일 SELECT+include) 재사용.
- emitFiscalReceipt, zebra-agent, 프론트엔드 변경 금지.
- print_temp 의 "매핑 offline → 거부" 동작은 유지 (변경 금지) — invoice 만 fallback 정책.
