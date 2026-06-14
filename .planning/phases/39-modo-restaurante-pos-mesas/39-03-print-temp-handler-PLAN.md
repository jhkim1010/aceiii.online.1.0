---
phase: 39-modo-restaurante-pos-mesas
plan: 03
type: execute
wave: 2
depends_on: []
files_modified:
  - print-agent/src/index.js
autonomous: false
requirements: [REQ-6, REQ-9]
user_setup:
  - service: print-agent (Electron 운영 인스턴스)
    why: "comanda/resumen 인쇄에 print_temp 핸들러 추가 후 사용자가 신규 빌드 재설치 필요"
    dashboard_config:
      - task: "push-both.sh 실행으로 print-agent 태그 bump → GitHub Actions build-print-agent.yml 트리거 → 빌드 산출물 재설치"
        location: "운영 PC 의 print-agent 앱 재설치"
must_haves:
  truths:
    - "print-agent 가 print_temp socket 이벤트를 수신하면 comanda/resumen HTML 을 PNG 로 렌더해 감열 출력한다"
    - "backend emitPrintTemp 가 보낸 데이터가 실제 인쇄로 이어진다 (현재는 핸들러 부재로 무동작)"
  artifacts:
    - path: "print-agent/src/index.js"
      provides: "print_temp socket 핸들러"
      contains: "socket.on('print_temp'"
  key_links:
    - from: "print-agent/src/index.js print_temp handler"
      to: "formatTempTicketHtml → renderHtmlToPng → printImage"
      via: "Phase 38 print_qr 파이프라인 재사용"
      pattern: "formatTempTicketHtml"
---

<objective>
★BLOCKING landmine 해소: print-agent/src/index.js 에 `socket.on('print_temp')` 핸들러를 추가한다. 현재 index.js 는 `print_invoice` 만 listen 하며, backend `emitPrintTemp` 가 emit 하는 `print_temp` 를 받는 쪽이 없어 comanda(req6)·resumen/cuenta(req9) 출력이 통째로 무동작한다. `formatTempTicketHtml`(formatter.js:666, export됨)는 호출처가 없는 상태.

Purpose: 이 핸들러 없이는 39-07 프론트의 "주방 전달"/"resumen 출력" 버튼이 backend emit 까지만 가고 프린터는 무반응. 39-07 이 이 플랜에 depends_on.
Output: print_temp 핸들러 + Electron CI 재빌드 트리거(사용자 체크포인트).
</objective>

<execution_context>
@/Users/marcoskim/Trabajos_Programming/ACE_online_1.0/.claude/get-shit-done/workflows/execute-plan.md
@/Users/marcoskim/Trabajos_Programming/ACE_online_1.0/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/phases/39-modo-restaurante-pos-mesas/39-RESEARCH.md
@CLAUDE.md

<interfaces>
<!-- print-agent 기존 모듈 컨트랙트 (코드베이스에서 추출) — 이걸 직접 사용 -->
print-agent/src/formatter.js:
```javascript
module.exports = { formatInvoiceHtml, formatInvoice, formatTempTicketHtml };
// formatTempTicketHtml(data) → HTML string (line 666, items/variants/totals 렌더 — 호출처 없음)
```
print-agent/src/renderer-engine.js:
```javascript
module.exports = { renderHtmlToPng, destroyRenderer };
// renderHtmlToPng(html, 576, timeout=10000) → Promise<pngBuffer>
```
print-agent/src/printer.js:
```javascript
module.exports = { printReceipt, printImage, testConnection };
// printImage(pngBuffer, printerConfig) → Promise  (dev 시 ~/Desktop/print-debug-*.png 저장)
```
기존 index.js 패턴 (참고):
```javascript
const { formatInvoice } = require('./formatter');
socket.on('print_invoice', async (invoiceData) => {
  const formatted = formatInvoice(invoiceData, config.printer.width);
  // ... print
});
```
Phase 38 가 print_qr 에서 동일 HTML→PNG→printImage 파이프라인 사용 (qr-formatter.js 주석 참조).
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: index.js 에 print_temp 핸들러 추가 (formatTempTicketHtml → renderHtmlToPng → printImage)</name>
  <read_first>
    - print-agent/src/index.js (기존 socket.on('print_invoice') 핸들러 — 에러 핸들링/config.printer 접근 패턴 모방, require 블록)
    - print-agent/src/formatter.js (formatTempTicketHtml signature line 666 — data 형태: 테이블명/웨이터/items/totals)
    - print-agent/src/renderer-engine.js (renderHtmlToPng(html, 576) signature)
    - print-agent/src/printer.js (printImage(pngBuffer, printerConfig) signature)
    - print-agent/src/print-pipeline.js (printTicket 래퍼 — 동일 HTML→PNG→printImage 흐름 참고)
    - 39-RESEARCH.md Pitfall 1 (print_temp 부재 = 최우선 landmine)
  </read_first>
  <action>
print-agent/src/index.js 상단 require 에 추가:
```javascript
const { formatTempTicketHtml } = require('./formatter');
const { renderHtmlToPng } = require('./renderer-engine');
const { printImage } = require('./printer');
```
(이미 require 된 것은 중복 추가 금지 — 미사용/중복 var 주의.)

기존 `socket.on('print_invoice', ...)` 블록 바로 아래에 신규 핸들러 추가:
```javascript
// Phase 39: 식당 comanda(주방 전표) + resumen(cuenta/영수증) 출력
// backend print.service.emitPrintTemp(branchId, data) 가 보내는 print_temp 수신
socket.on('print_temp', async (tempData) => {
  try {
    console.log('[print_temp] 수신:', tempData?.kind || 'comanda', 'table=', tempData?.tableName);

    // formatTempTicketHtml 이 comanda/resumen HTML 생성 (data.kind 로 분기 가능)
    const html = formatTempTicketHtml(tempData);

    // Phase 38 print_qr 와 동일 파이프라인: HTML → PNG(576px) → 감열 출력
    const pngBuffer = await renderHtmlToPng(html, 576);

    await printImage(pngBuffer, config.printer);

    console.log('[print_temp] 출력 완료');
  } catch (err) {
    console.error('[print_temp] 출력 실패:', err);
  }
});
```
주의:
- config 객체/printer 설정 접근은 기존 print_invoice 핸들러와 동일 변수(config.printer) 사용 — 실제 변수명 확인 후 일치.
- renderHtmlToPng 폭은 576 (Phase 38 print_qr 와 동일, 감열 58mm).
- fire-and-forget — 에러는 console 로만(프린터 무반응 디버깅용 로그 남김, backend 는 응답 기다리지 않음).
- formatTempTicketHtml 이 data.kind('comanda'|'cuenta'|'receipt') 로 분기하는지 확인 — 분기 미지원이면 39-07 backend 가 보내는 data shape 에 맞춰 formatter 호출만 정확히.

주석 한국어. 기존 print_invoice 핸들러 무수정.
  </action>
  <verify>
    <automated>cd /Users/marcoskim/Trabajos_Programming/ACE_online_1.0 && node -c print-agent/src/index.js && grep -c "socket.on('print_temp'" print-agent/src/index.js</automated>
  </verify>
  <acceptance_criteria>
    - grep "socket.on('print_temp'" print-agent/src/index.js 결과 1건
    - print_temp 핸들러 본문에 formatTempTicketHtml + renderHtmlToPng + printImage 호출 3개 전부 존재
    - `node -c print-agent/src/index.js` 문법 에러 0 (syntax check 통과)
    - 기존 `socket.on('print_invoice'` 핸들러 여전히 존재 (무수정)
    - require 중복 0 (formatTempTicketHtml/renderHtmlToPng/printImage 각 1회만 require)
  </acceptance_criteria>
  <done>print_temp 핸들러가 index.js 에 추가되어 formatTempTicketHtml→renderHtmlToPng→printImage 파이프라인을 수행. node -c 통과.</done>
</task>

<task type="checkpoint:human-action" gate="blocking">
  <name>Task 2: print-agent CI 재빌드 + 재설치 (사용자 액션)</name>
  <action>push-both.sh 로 print-agent 태그 bump → CI 빌드 → 운영 PC 재설치. dev 는 npm run dev:print 로 print_temp 수신 검증.</action>
  <what-built>print-agent/src/index.js 에 print_temp socket 핸들러 추가 완료. 이제 운영 print-agent 인스턴스가 이 코드를 받으려면 Electron 앱 재빌드 + 재설치 필요.</what-built>
  <how-to-verify>
    1. `./push-both.sh` 실행 → print-agent 변경 감지 → 태그 자동 증가 → GitHub Actions `build-print-agent.yml` 트리거 (Windows/macOS 빌드)
    2. GitHub Actions 빌드 성공 확인 (Actions 탭)
    3. 운영 PC 에서 신규 print-agent 빌드 재설치
    4. (dev 검증) `npm run dev:print` 로 print-agent 실행 → 39-07 주문 "주방 전달" 시 ~/Desktop/print-debug-*.png 에 comanda PNG 생성 확인
  </how-to-verify>
  <resume-signal>print-agent 재빌드/재설치 완료 또는 dev print-debug PNG 확인 후 "approved" 입력. 빌드 실패 시 로그(#NNN.txt) 공유.</resume-signal>
</task>

</tasks>

<threat_model>
## Trust Boundaries
| Boundary | Description |
|----------|-------------|
| backend socket → print-agent | emit 페이로드를 print-agent 가 렌더/인쇄 (신뢰된 내부 채널, branch:{id} room 인증) |

## STRIDE Threat Register
| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-39-06 | Denial | print_temp 핸들러 에러 | mitigate | try/catch fire-and-forget — 렌더/인쇄 실패가 socket 연결/다른 출력 막지 않음 |
| T-39-07 | Spoofing | branch:{id} room | accept | 기존 print-agent API Key 인증 + room 격리 재사용 (신규 인증 없음) |
</threat_model>

<verification>
- node -c print-agent/src/index.js 통과
- dev: npm run dev:print 후 print_temp 수신 시 print-debug PNG 생성
- CI: build-print-agent.yml 빌드 성공
</verification>

<success_criteria>
- print_temp 핸들러 존재, formatTempTicketHtml 파이프라인 동작
- 39-07 프론트 comanda/resumen 출력이 실제 인쇄로 이어질 토대 완성
</success_criteria>

<output>
완료 후 `.planning/phases/39-modo-restaurante-pos-mesas/39-03-SUMMARY.md` 작성.
</output>
