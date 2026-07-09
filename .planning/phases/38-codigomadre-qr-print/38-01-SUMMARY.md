---
phase: 38-codigomadre-qr-print
plan: 01
subsystem: api
tags: [websocket, socket.io, sequelize, postgres, qr, zebra-agent, delta, idor]

# Dependency graph
requires:
  - phase: 37-mobile-sales-shell
    provides: "/m/stock?s=&p= 딥링크 QR 파서 계약 (qr_scanner_sheet.dart)"
provides:
  - "qr_print_log 테이블 (지점별 QR 델타 스냅샷, PG10/PG15 멱등)"
  - "QrPrintLog sequelize-typescript 모델"
  - "PrintService.getPendingQrDelta (NUEVO/CAMBIO/동일 판정, N+1 없음)"
  - "PrintService.markQrPrinted (단일 bulk upsert 스냅샷)"
  - "buildQrPayload base-price 폴백 (products.price)"
  - "PrintGateway get_qr_pending / mark_qr_printed WebSocket ack 핸들러"
affects: [zebra-agent QR TAB3, Phase 38 Wave 2+ (라벨 출력 UI)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "gateway emitWithAck ack 핸들러로 에이전트 데이터 요청 (REST 아님) — branchId=client.data (IDOR 안전)"
    - "델타 판정: 벌크 findAll(≈5 SELECT) + in-memory 조인 (N+1 없음, pool 보호)"
    - "UNIQUE(branch,product,pt) + bulkCreate updateOnDuplicate 단일 upsert"

key-files:
  created:
    - api-ventago/migrations/phase38-qr-print-log.sql
    - api-ventago/src/app/print/qr-print-log.model.ts
    - api-ventago/src/app/print/print.service.qr.spec.ts
  modified:
    - api-ventago/src/app/print/print.service.ts
    - api-ventago/src/app/print/print.gateway.ts
    - api-ventago/src/app/print/print.module.ts
    - api-ventago/src/app/print/print.service.spec.ts

key-decisions:
  - "전송 계층 = /print-agent 소켓 ack (get_qr_pending/mark_qr_printed), REST 아님 (D-6b)"
  - "branchId/storeId 는 client.data(API key)에서만 도출, payload 무시 (D-6 IDOR 안전)"
  - "base/PRECIO 1 = products.price 폴백 — buildQrPayload null-price 버그 수정 + 델타에 동일 반영"

patterns-established:
  - "델타 스냅샷 판정을 벌크 쿼리 + Map in-memory 조인으로 (상품 수와 무관 상수 쿼리)"
  - "gateway ack 핸들러는 NOT_AUTHENTICATED / PRICE_TYPE_REQUIRED 가드를 get_price_types 와 동일 구조로"

requirements-completed: [QR-01, QR-02, QR-03, QR-04, QR-07, QR-10]

# Metrics
duration: 35min
completed: 2026-07-09
---

# Phase 38 Plan 01: QR 델타 백엔드 계층 Summary

**지점별 qr_print_log 스냅샷 테이블 + PrintService 델타 2메서드(NUEVO/CAMBIO 판정, N+1 없음) + /print-agent 소켓 ack 핸들러(get_qr_pending/mark_qr_printed)로 zebra-agent 배치 QR 델타를 API key 도출 branch 기준 IDOR-safe 하게 제공**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-07-09
- **Completed:** 2026-07-09
- **Tasks:** 3 (Task 2 는 TDD RED→GREEN)
- **Files modified:** 7 (3 created, 4 modified)

## Accomplishments
- `qr_print_log` 테이블 — PG10/PG15 멱등 마이그레이션, UNIQUE(branch_id, product_id, price_type_id) + (branch_id, price_type_id) 인덱스. 로컬 PG18 적용 + 2회차 재실행 0 변경/0 에러 확인.
- `PrintService.getPendingQrDelta` — Branch→storeId 도출, parent 상품/가격/스냅샷을 벌크 findAll(≈5 SELECT)로 로딩 후 in-memory 조인해 NUEVO/CAMBIO/동일 판정. 상품 수와 무관한 상수 쿼리(N+1 없음).
- `PrintService.markQrPrinted` — items 성공분을 UNIQUE 기반 단일 bulkCreate updateOnDuplicate 로 upsert (1 쿼리, pool 안전). 빈 배열은 무쿼리 { updated: 0 }.
- `buildQrPayload` base-price 폴백 — prices 행 없으면 products.price 사용 (기존 null-price 버그 수정).
- `PrintGateway` get_qr_pending / mark_qr_printed ack 핸들러 — branchId 는 client.data 에서만 도출, payload 의 branch/store 는 절대 신뢰하지 않음 (D-6 IDOR 안전).

## Task Commits

api-ventago 서브모듈 내부 커밋 (base HEAD 5ca0a54):

1. **Task 1: qr_print_log 마이그레이션 + 모델 + 모듈 등록** — `d23a27d` (feat)
2. **Task 2 RED: QR 델타 실패 스펙** — `6e74896` (test)
3. **Task 2 GREEN: getPendingQrDelta + markQrPrinted + base 폴백** — `56bd15f` (feat)
4. **Task 3: get_qr_pending / mark_qr_printed gateway ack** — `91dac87` (feat)

_TDD: Task 2 는 RED(6e74896) → GREEN(56bd15f) 2커밋._

## Files Created/Modified
- `api-ventago/migrations/phase38-qr-print-log.sql` — qr_print_log 멱등 마이그레이션 (운영 PG10 수동 적용 RUNBOOK)
- `api-ventago/src/app/print/qr-print-log.model.ts` — QrPrintLog 모델 (tableName qr_print_log)
- `api-ventago/src/app/print/print.service.qr.spec.ts` — 델타 10 케이스 Jest 스펙
- `api-ventago/src/app/print/print.service.ts` — getPendingQrDelta/markQrPrinted 추가 + buildQrPayload base 폴백 + QrPrintLog 주입
- `api-ventago/src/app/print/print.gateway.ts` — get_qr_pending/mark_qr_printed ack 핸들러
- `api-ventago/src/app/print/print.module.ts` — forFeature 에 QrPrintLog 등록
- `api-ventago/src/app/print/print.service.spec.ts` — base 폴백 계약 반영해 기존 null-price 테스트 갱신

## Build / Test Results (REAL)
- **Jest (print scope):** `npx jest print` → 3 suites / 27 tests PASS (print.service.qr.spec 10 tests, print.service.spec 4 QR tests 포함).
- **tsc (print/qr scope):** `npx tsc --noEmit | grep -iE "print|qr"` → 0 print/qr 에러.
- **ESLint:** 신규 `qr-print-log.model.ts` 단독 lint exit 0. `src/app/print` 전체는 236개 사전존재(pre-existing) `no-unsafe-*` 에러 보유 — 내 신규 코드는 파일 기존 `any` 패턴(getStockTodayForAgent 등)과 동일 스타일, net-new 회피가능 에러 없음.
- **Pool 안전:** `src/app/print` 내 `new Pool(` grep → 0. 델타는 벌크 findAll 상수 쿼리.
- **마이그레이션 멱등:** 로컬 PG18 2회 적용 — 2회차 전부 NOTICE skipping, 0 에러. `\d qr_print_log` 9컬럼 + UNIQUE(branch,product,pt) + (branch,pt) 인덱스 확인.
- **DB 무변경(운영):** 운영 PG10 미적용 (user_setup RUNBOOK 대기).

## Decisions Made
- **전송 계층 소켓 ack (D-6b):** REST `GET /print/qr/*` 대신 `/print-agent` 소켓 ack 로 구현. zebra-agent 의 유일 인증 채널이 소켓이고 print.controller 는 웹 JWT 전용이라 API key 를 못 받기 때문. 기존 get_price_types/get_stock_today ack 패턴과 동일 구조.
- **IDOR 안전:** 두 핸들러 모두 branchId 를 `client.data?.branchId`(handleConnection 이 API key 로 세팅)에서만 도출. payload 의 branch/store 는 읽지 않음 (grep 확인: 신규 핸들러 payload.branchId 미사용).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] buildQrPayload null-price 계약과 충돌하던 기존 테스트 갱신**
- **Found during:** Task 2 (base fallback 구현)
- **Issue:** print.service.spec.ts 의 "가격 행 없으면 price=null" 테스트가 D-6b 가 명시한 버그(base 가격 누락)를 검증하고 있었음. 폴백 수정 시 이 테스트가 실패.
- **Fix:** 해당 테스트를 base(products.price) 폴백 계약으로 갱신 (product.price 990 → payload.price 990).
- **Files modified:** api-ventago/src/app/print/print.service.spec.ts
- **Verification:** 갱신 후 27 print 테스트 전부 green.
- **Committed in:** 56bd15f (Task 2 GREEN)

**2. [Rule 3 - Scope guard] eslint --fix 가 재포맷한 무관 파일 되돌림**
- **Found during:** Task 3 (`npx eslint src/app/print --fix`)
- **Issue:** 블랭킷 --fix 가 Phase 38 무관 파일 `print.controller.ts` 를 formatting-only 로 재포맷 (files_modified 미포함).
- **Fix:** `git checkout -- src/app/print/print.controller.ts` 로 되돌려 스코프 유지.
- **Files modified:** 없음 (되돌림)
- **Verification:** 최종 커밋 파일 목록에 print.controller.ts 없음.
- **Committed in:** N/A (revert)

---

**Total deviations:** 2 (1 Rule 1 버그-테스트 갱신, 1 Rule 3 스코프 가드)
**Impact on plan:** 계획대로 실행. 버그-테스트 갱신은 D-6b 가 요구한 폴백 수정의 필연적 귀결. 스코프 크립 없음.

## Issues Encountered
- **사전존재 tsc 에러 2건 (out-of-scope):** `src/app/mercadopago/webhook/mp-webhook.service.spec.ts` — MpWebhookService 생성자 인자 불일치(9 expected, 7 given). Phase 38 과 무관(내 커밋이 건드리지 않음), PrintService 미참조 확인. 미수정, 사후 추적 대상.
- **사전존재 ESLint no-unsafe-* 236건 (out-of-scope):** print 모듈 전반의 `any` 패턴. 신규 코드는 기존 스타일 준수, 별도 수정 안 함.

## User Setup Required
운영 PG10 (ventago DB) 에 마이그레이션 수동 적용 필요 (마이그레이션 규약):
```
ssh jhkim-server 'sudo -u postgres psql -d ventago' < api-ventago/migrations/phase38-qr-print-log.sql
```
(사용자 확인 후 실행 — DDL). 로컬 PG18 은 이미 적용됨.

## Requirements Status
- QR-01 (qr_print_log 테이블) ✅
- QR-02 (델타 판정 NUEVO/CAMBIO/동일) ✅
- QR-03 (mark 스냅샷 upsert) ✅
- QR-04 (지점별 추적, branch_id) ✅
- QR-07 (qrUrl /m/stock?s=&p= 조립) ✅
- QR-10 (store 격리 / IDOR 안전) ✅

## Next Phase Readiness
- 백엔드 델타 계층 완료 — zebra-agent QR TAB3(Wave 2+) 가 get_qr_pending/mark_qr_printed ack 로 붙을 준비 완료.
- 잔여: 운영 PG10 마이그레이션 수동 적용 + zebra-agent renderer/preload/main TAB3 UI (후속 wave).
- api-ventago 작업 트리에 무관한 sellers/vendedor-device 진행중 코드가 미커밋 상태로 남아있음 (본 플랜이 건드리지 않음, 확인 완료).

## Confirmation: sellers/* Untouched
`git diff --name-only 5ca0a54 HEAD` → migrations/phase38-qr-print-log.sql + src/app/print/* 만. sellers/vendedor-device 파일 0건 포함.

## Self-Check: PASSED
- Created files exist: phase38-qr-print-log.sql, qr-print-log.model.ts, print.service.qr.spec.ts ✅
- Commits exist: d23a27d, 6e74896, 56bd15f, 91dac87 ✅
- sellers/vendedor-device: 0 files in any Phase 38 commit ✅

---
*Phase: 38-codigomadre-qr-print*
*Completed: 2026-07-09*
