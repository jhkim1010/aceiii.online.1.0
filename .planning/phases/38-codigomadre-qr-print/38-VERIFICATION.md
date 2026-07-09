---
phase: 38-codigomadre-qr-print
verified: 2026-07-09T04:12:26Z
status: human_needed
score: 8/8 code-level success criteria verified
overrides_applied: 0
human_verification:
  - test: "운영 PG10 (ventago DB) 에 phase38-qr-print-log.sql 수동 적용"
    expected: "qr_print_log 테이블 + UNIQUE(branch_id,product_id,price_type_id) + (branch_id,price_type_id) 인덱스 생성, 2회차 재실행 0 변경/0 에러 (멱등)"
    why_human: "마이그레이션 규약 — 운영 DDL 은 코드 배포와 별개로 사용자 확인 후 수동 적용 (현재 로컬 PG18 만 적용됨)"
  - test: "dev electron 실행 → TAB3 'QR' 열림 → price-type 선택 → 'Buscar cambios' → 델타 NUEVO/CAMBIO 실제 렌더 시각 확인"
    expected: "2패널 다크네이비+골드 테마, 우 패널에 NUEVO(골드)/CAMBIO(주황) 뱃지 + 체크박스 + 구→신 가격 렌더"
    why_human: "UI 시각 렌더링·테마·레이아웃은 정적 grep 으로 확정 불가 (실 electron 렌더 필요)"
  - test: "좌 패널 수치 5개(폭/높이/QR모듈/1:3비율/폰트) 변경 시 라이브 프리뷰 즉시 갱신 육안 확인"
    expected: "input 변경마다 좌 QR 사각형/우 이름·가격 근사 프리뷰가 즉시 반영, Guardar 로 저장"
    why_human: "라이브 프리뷰 시각 반영은 육안 확인 필요"
  - test: "실 Zebra 프린터 연결 → 'Imprimir seleccionados' 물리 출력 → 재 Buscar 시 성공분 제외 확인"
    expected: "선택 항목 1:3 QR 라벨 물리 출력, 성공분은 mark_qr_printed 스냅샷 후 다음 델타에서 제외; QR 스캔 시 Phase 37 앱이 /product/:p 상세로 이동"
    why_human: "실 프린터 하드웨어 + 물리 라벨 스캔 + E2E 델타 사이클은 코드로 검증 불가"
  - test: "프린터 오프라인 상태에서 출력 → 실패행 빨강 + 인라인 배너(#qr-status) + prominent 토스트 노출 확인"
    expected: "실패 productId 행 .qr-failed(빨강) 유지 + 에러 배너 + addLocalLog 토스트, 실패분 스냅샷 미기록(다음 델타 재등장)"
    why_human: "부분 실패 UX 실시간 동작은 실 프린터/네트워크 상태 필요"
  - test: "zebra-agent CI 빌드(build-zebra-agent.yml) — push 시 태그 자동 증가 후 Windows/macOS 빌드 통과 (SC8 CI 파트)"
    expected: "push-both.sh push → build-zebra-agent.yml 태그 증가 → CI 빌드 green"
    why_human: "SC8 의 'zebra-agent CI 빌드 통과' 는 push 이후에만 검증 가능 (이 플랜은 push 안 함)"
  - test: "회귀 — 기존 TAB1(Imprimir)/TAB2(Etiqueta) 정상 동작 확인"
    expected: "탭 전환·바코드 출력·etiqueta preset 무회귀 (TAB3 추가가 기존 흐름을 깨지 않음)"
    why_human: "기존 탭 실동작 회귀는 electron 실행 필요 (정적으로는 탭 전환 JS 에 qr 훅 1줄만 추가 확인됨)"
---

# Phase 38: CodigoMadre QR 배치·델타 출력 (Zebra) Verification Report

**Phase Goal:** zebra-agent 에 QR 배치 출력 탭(TAB3) 추가 — 운영자가 price-type 선택 후 "Buscar cambios" → 신규/변경 codigomadre parent 델타 리스트 → 선택 항목만 Zebra 접착 라벨(좌 QR / 우 제품명+가격, 1:3, 1개/2개) 로 일괄 출력, QR 은 딥링크 `/m/stock?s=&p=` 인코딩(Phase 37 파서 계약), 출력 성공분만 지점별 `qr_print_log` 스냅샷 upsert.
**Verified:** 2026-07-09T04:12:26Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

모든 8개 Success Criteria 가 **코드 계층에서 검증**되었다. 코드 갭 0. 남은 항목은 전부 실 하드웨어/운영 DB/시각 UAT (코드로 검증 불가) 이므로 human_needed.

### Observable Truths (ROADMAP Success Criteria)

| # | Truth (SC) | Status | Evidence |
|---|-----------|--------|----------|
| 1 | qr_print_log(branch,product,pt...) UNIQUE upsert, PG10/15 호환 | ✓ VERIFIED | `phase38-qr-print-log.sql`: `CREATE TABLE IF NOT EXISTS qr_print_log` + `uq_qr_print_log_branch_prod_pt` UNIQUE(branch_id,product_id,price_type_id) + SERIAL(gen_random_uuid 미사용). 로컬 PG18 실존 확인 (to_regclass + 3 인덱스). 멱등. |
| 2 | get_qr_pending → NUEVO/CAMBIO 델타, store 격리, N+1 없음, qrUrl 조립 | ✓ VERIFIED | `getPendingQrDelta` (print.service.ts:178): Branch→storeId 도출, products/prices/qrLog 각 findAll 1회(≈5 SELECT 상수), in-memory 조인, base(products.price) 폴백, qrUrl `/m/stock?s=${storeId}&p=${p.id}`. `new Pool` grep=0. D-6b: socket ack `get_qr_pending` (gateway:297, ROADMAP 재계약). |
| 3 | mark_qr_printed 성공분 upsert(insert/update) | ✓ VERIFIED | `markQrPrinted` (print.service.ts:290): bulkCreate `updateOnDuplicate:['printedPrice','printedName','printedAt','updatedAt']` 단일 upsert, 빈 배열 → `{updated:0}` 무쿼리. gateway ack `mark_qr_printed` (gateway:332). |
| 4 | formatQrLabel 1:3 좌 QR/우 이름+가격, doble=2장, layout 수치 | ✓ VERIFIED | `formatQrLabel` (zpl-formatter.js:495) + `renderQrBlock`(splitX=region*splitRatio) + `wrapQrText`. `^PW`/`^LL`/`^BQN,2,{qrModule}`, mode='doble'→region 오프셋 2블록(^PW 2배). qr-label.test.js **26 checks PASS**. |
| 5 | QR 페이로드 = /m/stock?s=&p= (Phase 37 파서 계약 일치) | ✓ VERIFIED | 발행: `${webBase}/m/stock?s=${storeId}&p=${id}` (service:159,252 / formatter `^FDQA,${sanitize(qrUrl)}`). 파서 `qr_scanner_sheet.dart:20` `uri.path.contains('/m/stock')` + `:23` `queryParameters['p']`. **계약 일치, 훼손 없음** (sanitize 는 ^,~ 만 제거; 딥링크에 없음). |
| 6 | TAB3 2패널: price-type 드롭다운 + 1/2 토글 + 프리뷰/수치 + 델타(뱃지/체크박스/구→신 가격) + Imprimir | ✓ VERIFIED (code) | renderer/index.html: `data-tab="qr"`, `#tab-qr`, `#qr-price-type`, `#qr-mode-simple/doble`, `#qr-preview` + 5 수치 입력, `#qr-delta-table`, NUEVO/CAMBIO 뱃지, `#qr-print-btn`, `#qr-status`. JS: `initQrTab/renderPreview/renderQrDelta/qrFetchPending/qrPrint` 배선. **시각 렌더는 UAT.** |
| 7 | 성공분만 mark→다음 Buscar 제외; 실패 행 표시 + 스냅샷 미기록 + 에러 가시성 | ✓ VERIFIED (code) | main.js qr:print: 항목별 sendZpl → `succeeded`/`failed` 분리, `mark_qr_printed` 에 succeeded 만 전달(:514). renderer: `res.failed` productId 행 `.qr-failed`(빨강) + `qrBanner('error')` + `addLocalLog('❌ QR:')`, 성공분 currentDelta 제거. **물리 사이클은 UAT.** |
| 8 | 백엔드 Jest + zpl-formatter 단위 통과, zebra-agent CI 빌드 통과 | ✓ VERIFIED (tests) / ? CI human | api-ventago `npx jest print` → **3 suites / 27 tests PASS**. zebra-agent qr-label **26 PASS** + print-flow(회귀) **28 PASS**. CI 빌드(build-zebra-agent.yml)는 push 후에만 검증 → human. |

**Score:** 8/8 success criteria 코드 계층 검증 (SC8 CI 파트만 push 대기)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `api-ventago/migrations/phase38-qr-print-log.sql` | PG10/15 멱등, UNIQUE(branch,product,pt) | ✓ VERIFIED | BEGIN/COMMIT, IF NOT EXISTS, SERIAL, gen_random_uuid 미사용. 로컬 PG18 실존. |
| `api-ventago/.../qr-print-log.model.ts` | QrPrintLog tableName qr_print_log | ✓ VERIFIED | `@Table({tableName:'qr_print_log'})`, module.ts forFeature 등록(:27). |
| `api-ventago/.../print.service.ts` | getPendingQrDelta + markQrPrinted + base 폴백 | ✓ VERIFIED | 두 메서드 + buildQrPayload null-price 폴백 수정(:164). |
| `api-ventago/.../print.gateway.ts` | get_qr_pending / mark_qr_printed ack | ✓ VERIFIED | 두 핸들러, branchId=client.data 전용, payload.branchId 미사용. |
| `api-ventago/.../print.service.qr.spec.ts` | 델타 Jest 스펙 | ✓ VERIFIED | 27 print 테스트 중 포함, 전부 green. |
| `zebra-agent/src/zpl-formatter.js` | formatQrLabel 순수 함수 | ✓ VERIFIED | formatQrLabel/renderQrBlock/wrapQrText + module.exports. |
| `zebra-agent/test/qr-label.test.js` | node assert 단위 | ✓ VERIFIED | 26 checks PASS. |
| `zebra-agent/main.js` | qr:fetchPending/qr:print IPC | ✓ VERIFIED | emitWithAck get_qr_pending/mark_qr_printed, 항목별 sendZpl, 성공분 mark, 프린터 가드. |
| `zebra-agent/preload.js` | qrFetchPending/qrPrint 노출 | ✓ VERIFIED | contextBridge 노출(:39-40). |
| `zebra-agent/renderer/index.html` | TAB3 2패널 + 배선 | ✓ VERIFIED (code) | 마크업 + JS ~250줄 배선. 시각 UAT 잔여. |

### Key Link Verification

| From | To | Via | Status |
|------|----|----|--------|
| PrintGateway get/mark | client.data.branchId | API key 도출 (payload 미신뢰) | ✓ WIRED — payload.branchId/storeId 미사용 확인 |
| getPendingQrDelta | qr_print_log | branch_id+price_type_id 벌크 조회 | ✓ WIRED — qrLogRepo.findAll Map 조인 |
| service/formatter | /m/stock 딥링크 | qrUrl 서버 조립 | ✓ WIRED — `/m/stock?s=&p=` |
| main.js qr:fetchPending | 백엔드 get_qr_pending | emitWithAck('get_qr_pending') | ✓ WIRED (main.js:462) |
| main.js qr:print | 백엔드 mark_qr_printed | 성공분 emitWithAck('mark_qr_printed') | ✓ WIRED (main.js:512) |
| formatQrLabel | ^BQN QR | ^FDQA,{qrUrl} | ✓ WIRED (formatter:463) |
| TAB3 Buscar/Imprimir | preload qrFetchPending/qrPrint | window.electronAPI 호출 | ✓ WIRED (renderer:1640,1760) |
| TAB3 수치 컨트롤 | 라이브 프리뷰 + config | input→renderPreview, setConfig('qrLayout') | ✓ WIRED (renderer:1617,1623) |

### Locked Decisions Check (D-1..D-11 + D-6b)

| Decision | Honored | Evidence |
|----------|---------|----------|
| D-1 TAB3 위치, 웹 트리거 없음 | ✓ | renderer data-tab="qr", 웹 트리거 코드 없음 |
| D-2 Zebra ZPL 전용 | ✓ | formatQrLabel ZPL, thermal per-row 미구현 |
| D-3 델타 정의(NUEVO/CAMBIO/동일) | ✓ | getPendingQrDelta nameChanged\|\|priceChanged 판정 |
| D-4 지점별 추적 | ✓ | qr_print_log.branch_id, branchId=client.data |
| D-5 price-type 단일 선택 | ✓ | priceTypeId 단일 인자, 배치 전체 기준 |
| D-6 QR 페이로드 + API key 도출 IDOR 안전 | ✓ | storeId 서버 도출, payload 미신뢰 |
| **D-6b 소켓 ack (REST 아님)** | ✓ | get_qr_pending/mark_qr_printed emitWithAck, print.controller REST 미추가 |
| D-7 parent(isParent)만 | ✓ | where isParent:true |
| D-8 1:3 좌우 분할 | ✓ | renderQrBlock splitRatio |
| D-9 simple/doble | ✓ | mode='doble' 2블록 |
| D-10 2패널 UI | ✓ | .two-panel 좌 프리뷰/우 델타 |
| D-11 성공분만 스냅샷 | ✓ | succeeded 만 mark_qr_printed |

**모든 잠금 결정(12/12) 준수.**

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| 백엔드 델타/upsert/payload 스펙 | `npx jest print` | 3 suites / 27 tests PASS | ✓ PASS |
| formatQrLabel 단위 | `node test/qr-label.test.js` | 26 checks PASS | ✓ PASS |
| 기존 라벨 회귀 | `node test/print-flow.test.js` | 28 checks PASS | ✓ PASS |
| main/preload 문법 | `node --check` (summary) | OK | ✓ PASS |
| pool 안전 | `grep new Pool( src/app/print` | 0 | ✓ PASS |
| 로컬 PG18 테이블 | `to_regclass('qr_print_log')` | qr_print_log + 3 인덱스 | ✓ PASS |

### Requirements Coverage

| Req | Source Plan | Description | Status | Evidence |
|-----|-------------|-------------|--------|----------|
| QR-01 | 38-01 | qr_print_log + upsert | ✓ SATISFIED | 마이그레이션 + UNIQUE + bulkCreate updateOnDuplicate |
| QR-02 | 38-01 | 델타 pending | ✓ SATISFIED | getPendingQrDelta NUEVO/CAMBIO |
| QR-03 | 38-01 | store 격리 + N+1 없음 | ✓ SATISFIED | storeId 고정 where + 상수 findAll |
| QR-04 | 38-01 | mark-printed upsert | ✓ SATISFIED | markQrPrinted |
| QR-05 | 38-02 | formatQrLabel 1:3 | ✓ SATISFIED | renderQrBlock split |
| QR-06 | 38-02 | doble 2장 | ✓ SATISFIED | mode='doble' 2블록 |
| QR-07 | 38-01/02 | QR 페이로드 계약 | ✓ SATISFIED | /m/stock?s=&p= ↔ dart 파서 일치 |
| QR-08 | 38-03 | TAB3 2패널 | ✓ SATISFIED (code) | 마크업+배선 (시각 UAT) |
| QR-09 | 38-02/03 | 항목별 출력 + 에러 가시성 | ✓ SATISFIED (code) | succeeded/failed + 배너+토스트 |
| QR-10 | 38-01/02 | 테스트/CI | ✓ SATISFIED (tests) / CI human | Jest 27 + node 26/28 pass; CI push 대기 |

ORPHANED 요구사항 없음 (QR-01..QR-10 전부 플랜에 매핑).

### Anti-Patterns Found

없음 (blocker/warning 0). 신규 코드에 TODO/placeholder/빈 구현 없음. print 모듈 사전존재 no-unsafe-* eslint 236건은 out-of-scope(신규 코드 아님, SUMMARY 명시).

### Gaps Summary

**코드 갭 0.** 8개 Success Criteria + QR-01..QR-10 + 12개 잠금 결정 모두 실코드에서 검증. 백엔드 Jest 27 + zebra 단위 26 + 회귀 28 전부 green. QR-07 딥링크 계약이 Phase 37 파서(`/m/stock` path + `p=` 쿼리)와 일치함을 직접 확인 — 회귀 없음. D-6b 소켓 ack 전송 계층이 REST 대신 정확히 구현됨.

남은 것은 **코드로 검증 불가능한 항목**(human_verification 참조): (1) 운영 PG10 마이그레이션 수동 적용, (2) TAB3 시각 UAT, (3) 실 Zebra 물리 출력 + 델타 사이클, (4) 프린터 오프라인 실패 UX, (5) zebra-agent CI 빌드(push 후), (6) 기존 TAB1/TAB2 회귀. 이들은 코드 갭이 아니라 배포/하드웨어/시각 검증 게이트다.

---

_Verified: 2026-07-09T04:12:26Z_
_Verifier: Claude (gsd-verifier)_
