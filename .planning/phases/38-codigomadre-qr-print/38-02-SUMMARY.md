---
phase: 38-codigomadre-qr-print
plan: 02
subsystem: zebra-agent
tags: [zebra-agent, zpl, qr, electron, ipc, websocket, delta, formatter]

# Dependency graph
requires:
  - phase: 38-codigomadre-qr-print
    plan: 01
    provides: "get_qr_pending / mark_qr_printed WebSocket ack 핸들러 (백엔드 델타 계층)"
  - phase: 37-mobile-sales-shell
    provides: "/m/stock?s=&p= 딥링크 QR 파서 계약 (qr_scanner_sheet.dart)"
provides:
  - "formatQrLabel 순수 함수 (1:3 QR/이름 분할, doble 복제, layout 수치, QR=qrUrl byte-identical)"
  - "qr:fetchPending IPC (get_qr_pending ack → 델타 리스트)"
  - "qr:print IPC (항목별 sendZpl + 성공분 mark_qr_printed 스냅샷, 부분 실패 안전)"
  - "preload qrFetchPending / qrPrint contextBridge 노출"
affects: [Phase 38 Wave 3 (TAB3 renderer UI 배선)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "formatQrLabel = 순수 함수 (offsetX 블록 렌더 재사용, doble = 같은 상품 2블록)"
    - "qr:print 항목별 sendZpl → succeeded/failed 분리 → 성공분만 mark ack (D-11 부분 실패 안전)"
    - "IPC 에이전트 데이터 요청 = wsConnection.timeout(ms).emitWithAck (get_price_types 와 동일 구조)"

key-files:
  created:
    - zebra-agent/test/qr-label.test.js
  modified:
    - zebra-agent/src/zpl-formatter.js
    - zebra-agent/main.js
    - zebra-agent/preload.js

key-decisions:
  - "QR 인코딩 = qrUrl 그대로 (sanitize 는 ^,~ 만 제거하며 딥링크엔 없음) — Phase 37 파서 byte-identical 계약 보존"
  - "doble = region(단일 폭) 오프셋으로 같은 상품 2블록, 미디어 ^PW 2배 (D-9)"
  - "성공분만 mark_qr_printed; mark ack 실패 시 로그만(다음 델타 재등장이 안전한 방향) (D-11)"

patterns-established:
  - "wrapQrText: estTextWidth 기반 단어→문자 줄바꿈으로 우 패널 폭 초과 이름 다줄 분할"

requirements-completed: [QR-05, QR-06, QR-07, QR-09, QR-10]

# Metrics
duration: ~20min
completed: 2026-07-09
---

# Phase 38 Plan 02: zebra-agent QR 라벨 생성기 + 통신 계층 Summary

**zebra-agent 에 순수 함수 `formatQrLabel`(1:3 좌 QR / 우 이름+가격, doble=같은 상품 2장, layout 수치 반영, QR=qrUrl byte-identical) + `qr:fetchPending`/`qr:print` IPC(get_qr_pending ack → 델타, 항목별 sendZpl → 성공분만 mark_qr_printed 스냅샷) + preload 브릿지를 추가해 38-01 백엔드 델타 계층과 배선**

## Performance
- **Duration:** ~20 min
- **Tasks:** 2 (Task 1 은 TDD RED→GREEN)
- **Files:** 4 (1 created, 3 modified) — 전부 zebra-agent/ (부모 레포)

## Accomplishments
- `formatQrLabel({ qrUrl, name, price, priceLabel, layout })` 순수 함수 — 좌 1/4 `^BQN,2,{qrModule}^FDQA,{qrUrl}` QR + 우 3/4 제품명(`^A0N`, 줄바꿈) + `{priceLabel}: {price}`. layout 기본값 `{ widthMm:50, heightMm:25, qrModule:4, splitRatio:0.25, fontSize:22, mode:'simple' }`.
- **QR 페이로드 계약 보존** — sanitize 는 `^`,`~` 만 제거하고 `/m/stock?s=&p=` 딥링크엔 그 문자가 없어 byte-identical. 단위 테스트로 `^FDQA,{qrUrl}^FS` 정확 포함 검증(simple 1회 / doble 2회).
- **doble 복제** — `mode:'doble'` 이면 region(단일 라벨 폭 dot) 오프셋으로 같은 상품 블록을 2번 렌더, 미디어 `^PW` 2배 (리스트 N → 2N장, D-9).
- **layout 수치 반영** — widthMm=50→`^PW400`, heightMm=25→`^LL200`; qrModule/fontSize/splitRatio 변경이 `^BQN` 배율·이름 폰트·우 패널 x 오프셋에 반영.
- **줄바꿈** — `wrapQrText` 가 estTextWidth 기준으로 우 패널 폭 초과 이름을 단어(초과 단어는 문자) 단위로 다줄 분할.
- `qr:fetchPending(priceTypeId)` IPC — `wsConnection.timeout(10000).emitWithAck('get_qr_pending', { priceTypeId })` (branch/store 미전송, 서버 API key 도출).
- `qr:print({ items, layout, mode, priceTypeId })` IPC — 항목별 `formatQrLabel`+`sendZpl`, `succeeded`/`failed` 분리(부분 실패 시 배치 미중단), 성공분만 `emitWithAck('mark_qr_printed', { priceTypeId, items: succeeded })`. mark ack 실패 시 로그만(다음 델타 재등장, D-11). 반환 `{ ok, printed, failed }`.
- preload `electronAPI` 에 `qrFetchPending` / `qrPrint` 노출.

## Task Commits
부모 레포 커밋 (base HEAD aa4398d):

1. **Task 1 RED: formatQrLabel 실패 스펙** — `fdc3f0a` (test)
2. **Task 1 GREEN: formatQrLabel 구현** — `6f8bab7` (feat)
3. **Task 2: qr:fetchPending/qr:print IPC + preload** — `6920c50` (feat)

_TDD: Task 1 은 RED(fdc3f0a) → GREEN(6f8bab7)._

## Files Created/Modified
- `zebra-agent/test/qr-label.test.js` (created) — formatQrLabel node assert 단위 테스트 26 checks
- `zebra-agent/src/zpl-formatter.js` — formatQrLabel + renderQrBlock + wrapQrText 추가, module.exports 에 formatQrLabel
- `zebra-agent/main.js` — require 에 formatQrLabel, qr:fetchPending/qr:print IPC 핸들러
- `zebra-agent/preload.js` — qrFetchPending/qrPrint contextBridge 노출

## Build / Test Results (REAL)
- **qr-label.test.js:** `node test/qr-label.test.js` → **26 checks passed ✅** (QR=qrUrl byte-identical, 1:3 좌표, layout 수치, doble 2장, sanitize, 줄바꿈, 빈 필드 방어).
- **회귀 (print-flow.test.js):** `node test/print-flow.test.js` → **28 checks passed ✅** (기존 4모드/auto-fit/sanitize 무회귀).
- **모듈 로드:** `node -e "require('./src/zpl-formatter.js')"` → `module OK` (문법 무결).
- **main/preload 문법:** `node --check main.js && node --check preload.js` → 통과.
- **계약 grep:** `emitWithAck('get_qr_pending'`, `emitWithAck('mark_qr_printed'`, preload `qrFetchPending`/`qrPrint` 전부 존재.

## Decisions Made
- **QR byte-identical:** sanitize(qrUrl) 를 통과시켜도 딥링크(`/m/stock?s=&p=`)엔 `^`,`~` 가 없어 훼손 0. 테스트가 `^FDQA,{qrUrl}^FS` 정확 매칭으로 계약 고정.
- **doble 오프셋:** 기존 modo-duplicado 의 halfWidth/offsetX 발상을 재사용 — region 을 단일 라벨 폭으로 두고 오른쪽 복제본 offsetX=region.
- **mark 실패 로그-only:** 출력은 이미 물리적으로 완료됐으므로 스냅샷 ack 실패는 되돌릴 수 없음. 미기록 → 다음 델타에 재등장(중복 출력)이 누락(D-11 위반)보다 안전.

## Threat Model Compliance
- **T-38-06 (Tampering, ZPL injection):** mitigate — formatQrLabel 이 name/qrUrl/priceLabel 을 sanitize() 후 `^FD` 삽입. ✅
- **T-38-07 (Repudiation, 실패분 재출력 누락):** mitigate — 항목별 sendZpl 결과로 succeeded 만 mark; failed 는 스냅샷 미기록. ✅
- **T-38-08 (DoS, 대량 emit):** mitigate — mark 는 성공분 1회 ack, fetch/print timeout 10s. ✅
- **T-38-09 (Spoofing, 타 매장 priceTypeId):** mitigate — 에이전트는 branch/store 미전송, 서버가 client.data(API key)로 제한(38-01). ✅

## Deviations from Plan
None — 계획대로 실행. formatQrLabel 시그니처/좌표/doble/layout/IPC 계약 모두 플랜 action 대로 구현.

## Requirements Status
- QR-05 (라벨 레이아웃 1:3 좌 QR / 우 이름+가격, D-8) ✅ formatQrLabel
- QR-06 (simple/doble 출력 단위, D-9) ✅ mode='doble' 같은 상품 2장
- QR-07 (QR 페이로드 = /m/stock?s=&p= 훼손 없음, D-6) ✅ byte-identical 테스트
- QR-09 (출력 성공분만 스냅샷, D-11) ✅ qr:print succeeded 만 mark
- QR-10 (store 격리 / IDOR 안전) ✅ branch/store 미전송, 서버 도출

## Confirmation: api-ventago sellers/* Untouched
`git diff --name-only fdc3f0a~1 6920c50` → zebra-agent/{main.js,preload.js,src/zpl-formatter.js,test/qr-label.test.js} 4개뿐. api-ventago 서브모듈/sellers 파일 0건. 작업 시작 시 존재하던 ` M api-ventago`(sellers/vendedor-device 미커밋)는 손대지 않음.

## Next Phase Readiness
- 배선 완료 — Wave 3 TAB3 renderer(라이브 프리뷰 + 델타 리스트 + simple/doble 토글 + 수치 조정)가 `window.electronAPI.qrFetchPending`/`qrPrint` 로 붙을 준비 완료 (D-10 UI).
- 잔여(선행 플랜): 운영 PG10 `phase38-qr-print-log.sql` 수동 적용(38-01 user_setup).
- zebra-agent 변경 → push 시 `build-zebra-agent.yml` 태그 자동 증가(push-both.sh). 이 플랜은 push 안 함(사용자 요청 시).

## Self-Check: PASSED
- Created file exists: zebra-agent/test/qr-label.test.js ✅
- Commits exist: fdc3f0a, 6f8bab7, 6920c50 ✅
- api-ventago/sellers: 0 files in any Phase 38-02 commit ✅

---
*Phase: 38-codigomadre-qr-print*
*Completed: 2026-07-09*
