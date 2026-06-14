---
phase: 39-modo-restaurante-pos-mesas
plan: 03
subsystem: infra
tags: [print-agent, socket.io, electron, escpos, thermal-printing, comanda]

# Dependency graph
requires:
  - phase: 38-codigomadre-qr-thermal
    provides: "renderHtmlToPng → printImage HTML→PNG 감열 파이프라인 (renderer-engine.js / printer.js / print-pipeline.js)"
provides:
  - "print-agent print_temp socket 핸들러 — backend emitPrintTemp 의 comanda/resumen 페이로드를 감열 출력으로 변환"
  - "39-07 프론트 '주방 전달'/'resumen 출력' 버튼의 실제 인쇄 토대 (★blocking landmine 해소)"
affects: [39-07-salonview-order-payment, 39-05-restaurant-sale-lifecycle]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "fire-and-forget socket 핸들러: try/catch 로 렌더/인쇄 실패가 socket 연결·다른 출력을 막지 않음 (T-39-06)"

key-files:
  created: []
  modified:
    - "print-agent/src/index.js — print_temp 핸들러 + formatTempTicketHtml/printImage/renderHtmlToPng require 추가"

key-decisions:
  - "index.js 가 기존엔 텍스트 경로(formatInvoice+printReceipt)만 require 했으므로, HTML→PNG 모듈 3개 require 는 신규 추가(중복 아님). 핸들러는 print-pipeline.js(printTicket) 와 동일 흐름을 인라인."
  - "print_invoice 핸들러처럼 print_confirmation emit 하지 않음 — backend emitPrintTemp 는 응답을 기다리지 않는 fire-and-forget 이므로 console 로그만."

patterns-established:
  - "식당 임시전표(comanda/resumen) 출력: formatTempTicketHtml(data) → renderHtmlToPng(html, 576) → printImage(png, config.printer)"

requirements-completed: [REQ-6, REQ-9]

# Metrics
duration: ~5min
completed: 2026-06-14
---

# Phase 39 Plan 03: print-temp Handler Summary

**print-agent index.js 에 `socket.on('print_temp')` 핸들러 추가 — backend emitPrintTemp 의 comanda/resumen 페이로드를 formatTempTicketHtml → renderHtmlToPng(576px) → printImage 파이프라인으로 감열 출력. Phase 39 최대 ★blocking landmine(핸들러 부재로 식당 출력 통째 무동작) 해소.**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-06-14T22:15:35Z
- **Completed:** 2026-06-14T22:21:00Z
- **Tasks:** 1/2 complete (Task 2 = blocking human-action checkpoint, 사용자 대기)
- **Files modified:** 1

## Accomplishments

- `print_temp` socket 핸들러를 `print_invoice` 핸들러 바로 아래에 추가 (기존 핸들러 무수정)
- `formatTempTicketHtml`(formatter.js:666, 이전엔 호출처 없음) 를 실제 호출처와 연결
- HTML→PNG→printImage 파이프라인(Phase 38 / print-pipeline.js 동일) 재사용 — 신규 인프라 0
- `node -c` 구문 검사 통과, 핸들러/require 중복 0 검증

## Task Commits

1. **Task 1: index.js 에 print_temp 핸들러 추가** - `9f1339d` (feat)

**Task 2: print-agent CI 재빌드 + 재설치** — `checkpoint:human-action` (blocking). 사용자가 `push-both.sh` 실행으로 태그 bump → GitHub Actions `build-print-agent.yml` 트리거 → 운영 PC 재설치 필요. **실행자가 push-both.sh / CI 를 트리거하지 않음 (deploy gated).**

## Files Created/Modified

- `print-agent/src/index.js` — 상단 require 에 `formatTempTicketHtml`(formatter), `printImage`(printer), `renderHtmlToPng`(renderer-engine) 추가; `print_invoice` 핸들러 아래 `print_temp` 핸들러 신규.

## Decisions Made

- index.js 는 기존에 **텍스트 경로**(`formatInvoice` + `printReceipt`)만 사용 중이었고 HTML→PNG 모듈을 require 하지 않았다. 따라서 plan 의 "require 중복 추가 금지" 주의는 충족 — 추가한 3개 require 는 전부 신규이며 중복 0.
- `print_temp` 핸들러는 `print_invoice` 와 달리 `print_confirmation` 을 emit 하지 않는다 (backend emitPrintTemp = fire-and-forget). 에러는 console 로만 남겨 무반응 디버깅 로그 확보.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking/Interface mismatch] 핸들러를 실제 코드 흐름에 맞춰 작성**
- **Found during:** Task 1
- **Issue:** Plan `<interfaces>` 는 index.js 가 이미 HTML→PNG 파이프라인(`config.printer` 접근)을 쓰는 것처럼 기술했으나, 실제 index.js 는 **텍스트 경로**(`formatInvoice`→`printReceipt`)만 require/사용 중이었고 `renderHtmlToPng`/`printImage` 는 require 조차 안 돼 있었다. 또한 Phase 38 의 `formatQrHtml` 도 index.js 에 socket 핸들러가 없는 상태(별개 gap, 본 plan 범위 외).
- **Fix:** deviation 프로토콜대로 "기존 파이프라인 재사용"을 충실히 따라, `print-pipeline.js`(printTicket) 와 동일한 `formatTempTicketHtml → renderHtmlToPng(html,576) → printImage(png, config.printer)` 흐름을 인라인으로 구현하고, 누락된 require 3개를 추가. 새 print 파이프라인을 발명하지 않고 검증된 모듈만 호출.
- **Files modified:** print-agent/src/index.js
- **Verification:** `node -c` 통과, `socket.on('print_temp'`=1, `print_invoice`=1(무수정), require 각 1회.
- **Committed in:** `9f1339d` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking/interface mismatch)
**Impact on plan:** plan 의 핵심 의도(print_temp 핸들러 = formatTempTicketHtml→renderHtmlToPng→printImage)는 그대로 충족. 인터페이스 가정만 실제 코드에 맞춰 조정. scope creep 없음.

## Issues Encountered

- Plan interfaces 가 index.js 의 실제 상태(텍스트 경로)와 불일치 → 위 Deviation 1 로 해소.

## User Setup Required

**print-agent (Electron 운영 인스턴스) 재빌드/재설치 필요 (Task 2 = blocking checkpoint).**

운영 print-agent 들은 현재 `print_temp` 핸들러가 없는 빌드를 실행 중이므로, 코드 변경(9f1339d)을 받으려면 Electron 앱 재빌드+재설치가 필요하다:

1. `./push-both.sh` 실행 → print-agent 변경 감지 → 태그 자동 증가 → GitHub Actions `build-print-agent.yml`(Windows/macOS) 트리거
2. GitHub Actions Actions 탭에서 빌드 성공 확인 (실패 시 로그 `#NNN.txt` 공유)
3. 운영 PC 에서 신규 print-agent 빌드 재설치
4. (dev 검증 대안) `npm run dev:print` 실행 후 39-07 "주방 전달" 시 `~/Desktop/print-debug-*.png` 에 comanda PNG 생성 확인

**실행자는 push-both.sh / CI 를 트리거하지 않는다 (사용자 게이트 deploy 액션).**

## Next Phase Readiness

- 코드 측면: `print_temp` 핸들러 준비 완료 — 39-07 프론트 comanda/resumen 출력이 backend emit → 실제 인쇄로 이어질 토대 완성.
- 블로커: Task 2 (CI 재빌드 + 운영 재설치) 사용자 액션 미완 시, 운영 print-agent 는 여전히 print_temp 무수신. dev 환경(`npm run dev:print`)은 최신 코드 즉시 반영되므로 39-07 dev 검증은 가능.

## TDD Gate Compliance

N/A — 본 plan 은 `type: execute` (tdd 아님). print-agent 는 Electron 런타임 모듈로 단위 테스트 인프라 없음; 검증은 `node -c` 구문 + dev print-debug PNG (Task 2) 로 수행.

## Self-Check: PASSED

- FOUND: print-agent/src/index.js
- FOUND: .planning/phases/39-modo-restaurante-pos-mesas/39-03-SUMMARY.md
- FOUND commit: 9f1339d

---
*Phase: 39-modo-restaurante-pos-mesas*
*Completed: 2026-06-14 (Task 1) — Task 2 human-action checkpoint pending*
