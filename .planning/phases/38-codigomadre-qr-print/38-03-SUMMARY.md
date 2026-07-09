---
phase: 38-codigomadre-qr-print
plan: 03
subsystem: zebra-agent
tags: [zebra-agent, renderer, qr, ui, tab3, delta, electron, ipc, preview]

# Dependency graph
requires:
  - phase: 38-codigomadre-qr-print
    plan: 02
    provides: "preload qrFetchPending(priceTypeId) / qrPrint({items,layout,mode,priceTypeId}) + fetchPriceTypes IPC"
provides:
  - "renderer TAB3 'QR' 2패널 UI (좌 라이브 프리뷰+수치 조정 / 우 price-type+델타 리스트+체크박스)"
  - "Buscar cambios → qrFetchPending 델타 렌더(NUEVO/CAMBIO 배지, 구→신 가격) + Imprimir seleccionados → qrPrint 배선"
  - "라이브 HTML 프리뷰(1:3 QR/이름·가격) + getConfig('qrLayout') 저장(etiqueta preset 불변)"
  - "에러 가시성(인라인 배너 #qr-status + 토스트 로그) + 실패행 표시 + 성공분 자동 제거"
affects: [Phase 38 수동 UAT (dev electron), Phase 37 스캔 딥링크 소비]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "TAB3 는 기존 tab-btn/data-tab/tab-content 규칙에 자동 편입 (탭 전환 JS 에 qr 훅 1줄 추가)"
    - "라이브 프리뷰 = 순수 HTML/CSS 근사(canvas 아님) — .qp-qr flex-basis=splitRatio, 의사 QR 그리드"
    - "QR layout 저장 = setConfig('qrLayout') 로 격리 (etiqueta setLabelLayout 프리셋과 분리해 회귀 방지)"
    - "델타 출력 후 실패=행 빨강 유지 / 성공=행+currentDelta 제거 (다음 Buscar 재등장 방지 UX)"

key-files:
  created: []
  modified:
    - zebra-agent/renderer/index.html

key-decisions:
  - "QR layout 은 setConfig('qrLayout') 에 저장 — setLabelLayout(바코드 etiqueta preset)을 건드리지 않아 TAB2 회귀 0"
  - "프리뷰는 canvas(ZPL dot 좌표계) 대신 HTML/CSS 1:3 근사 — 실제 ZPL 렌더 불가 명시(preview-hint), 수치 변경 즉시 반영에 집중"
  - "NUEVO=골드(#f5a623)/CAMBIO=주황(#ff9800) 배지 — 둘 다 기존 파일에 이미 쓰이던 테마 색, 신규 색 도입 0"

requirements-completed: [QR-08, QR-09]

# Metrics
duration: ~4min
completed: 2026-07-09
---

# Phase 38 Plan 03: zebra-agent TAB3 "QR" 2패널 렌더러 UI Summary

**zebra-agent renderer 에 TAB3 "QR" 추가 — 좌 라이브 프리뷰(1:3 QR/이름·가격 HTML 근사) + 5개 수치 조정(ancho/alto/módulo/proporción/fuente, getConfig('qrLayout') 저장), 우 price-type 드롭다운 + 1/2개 토글 + "Buscar cambios"(qrFetchPending → NUEVO/CAMBIO 배지·체크박스·구→신 가격) + "Imprimir seleccionados (N)"(qrPrint 선택분, 실패행 빨강+인라인 배너+토스트, 성공분 자동 제거). 38-02 IPC 에 전량 배선, 기존 다크네이비+골드 테마 재사용**

## Performance
- **Duration:** ~4 min
- **Tasks:** 2 (모두 auto)
- **Files:** 1 modified (zebra-agent/renderer/index.html, 부모 레포)

## Accomplishments
- **탭 편입:** `.tabs` 에 `<button data-tab="qr">QR</button>` + `#tab-qr` 콘텐츠 블록. 기존 탭 전환 JS 에 `if (btn.dataset.tab === 'qr') initQrTab();` 1줄만 추가 → 기존 규칙에 자동 편입(TAB1/TAB2 회귀 0).
- **좌 패널(프리뷰+수치):** `#qr-preview-box`(flex 1:3 — `.qp-qr` splitRatio 폭 / `.qp-info` 이름+가격), 의사 QR 그리드(module 클수록 셀 감소 + 모서리 3 finder). 수치 5개 `#qr-width-mm`(50)/`#qr-height-mm`(25)/`#qr-module`(4)/`#qr-split-ratio`(0.25)/`#qr-font-size`(22) → `input` 이벤트마다 `renderPreview()` 즉시 갱신. `#qr-save-layout` → `setConfig('qrLayout', ...)`.
- **우 패널(델타):** `#qr-price-type`(fetchPriceTypes 재사용) + simple/doble 세그먼트 토글(`#qr-mode-simple`/`#qr-mode-doble`) + `#qr-buscar` + `#qr-delta-table`(전체선택 th + Estado 배지 + Código + Nombre + Precio) + summary-bar(`#qr-selected-count` + `#qr-print-btn`) + `#qr-status` 인라인 배너.
- **Buscar cambios:** `qrFetchPending(priceTypeId)` → `currentDelta` 보관 → 행별 체크박스(기본 checked, `data-product-id`) + NUEVO/CAMBIO 배지 + CAMBIO 는 `oldPrice → price`(취소선→굵게, oldName 다르면 title 툴팁). 0건 = "Sin cambios" 안내, priceTypeId 미선택 = 에러 배너.
- **선택 카운트:** 전체선택 토글 + 개별 토글 → `#qr-selected-count` + 버튼 라벨 "Imprimir seleccionados (N)" 실시간 갱신, N=0 이면 버튼 비활성.
- **Imprimir seleccionados:** 선택 productId 로 `currentDelta` 필터 → `qrPrint({ items, layout, mode, priceTypeId })`. `res.failed` productId 행은 `.qr-failed`(빨강) 유지, 성공분은 행+`currentDelta` 제거(다음 Buscar 재등장 방지). 부분 성공 = "N impresa(s), M con error" 에러 배너.
- **에러 가시성(규약):** fetch/print 예외·`ok=false`·부분 실패 전부 `#qr-status` 인라인 배너 + `addLocalLog('❌ QR: ...')` 토스트 로그 동시 노출.
- **테마:** 신규 색 도입 0 — NUEVO=`#f5a623`, CAMBIO=`#ff9800`(둘 다 기존 파일 사용색), 패널 `#0f3460`, 라인 `#2a2a4a`, 배경 `#1a1a2e`.

## Task Commits
부모 레포 커밋 (base HEAD 6c38508):

1. **Task 1: TAB3 마크업(탭 버튼 + 2패널 + CSS)** — `e660454` (feat)
2. **Task 2: TAB3 JS 배선(price-type/Buscar/프리뷰/Imprimir/에러)** — `7fdf93e` (feat)

## Files Created/Modified
- `zebra-agent/renderer/index.html` — TAB3 탭 버튼 + `#tab-qr` 2패널 마크업 + QR 전용 CSS(배지/배너/프리뷰/세그먼트) + 인라인 JS 블록(~250줄): `initQrTab`/`renderPreview`/`qrLoadLayout`/`qrReadLayout`/`qrLoadPriceTypes`/`qrBanner`/`qrFmtPrice`/`renderQrDelta`/`qrUpdateSelection` + Buscar/Imprimir/전체선택/저장 핸들러.

## Build / Test Results (REAL)
renderer 는 순수 HTML/JS(빌드 스텝 없음). 아래는 **실제 실행한** 구조/문법 검증:

- **인라인 JS 문법 파싱:** `<script>` 블록 추출 후 `new Function(js)` — **OK inline JS parses (1259 lines)** (SyntaxError 0, 중괄호 균형 확인).
- **구조 grep (Task 1):** `data-tab="qr"`, `id="tab-qr"`, `id="qr-delta-table"`, `id="qr-price-type"`, `id="qr-preview-grid"`, `id="qr-print-btn"`, `id="qr-width-mm"`, `id="qr-save-layout"` → **OK markup** (전부 존재).
- **배선 grep (Task 2):** `qrFetchPending(`, `qrPrint(`, `fetchPriceTypes(`, `renderPreview|qr-preview`, `NUEVO`, `CAMBIO`, `initQrTab` → **OK wiring grep**.
- **변경 범위:** `git diff --name-only e660454~1 7fdf93e` → `zebra-agent/renderer/index.html` **1개뿐**. api-ventago/ventago-app 서브모듈 0건.
- **회귀(정적):** 탭 전환 JS 는 기존 `if label` 블록에 `if qr` 1줄만 추가 — TAB1/TAB2 마크업·핸들러 무변경.

### Pending — Manual UAT (human, dev electron + 실 프린터)
아래는 **정적 검증 불가, 수동 UAT 필요**(플랜 verification 명시):
- TAB3 열림 → price-type 선택 → "Buscar cambios" → 델타 NUEVO/CAMBIO 실제 렌더 확인
- 수치 5개 변경 시 좌 프리뷰 라이브 반영(비율/QR 폭/폰트) 육안 확인
- 실 Zebra 연결 → "Imprimir seleccionados" 물리 출력 → 재 Buscar 시 성공분 제외 확인
- 프린터 오프라인 상태 출력 → 실패행 빨강 + 인라인 배너 + 토스트 노출 확인
- TAB1/TAB2 정상 동작(회귀) 확인

## Decisions Made
- **QR layout 격리 저장:** `setConfig('qrLayout')` 사용 — `setLabelLayout()` 는 TAB2 바코드 etiqueta preset 의 layout 을 덮어써 회귀 위험이 있어 배제. TAB3 는 자체 키에 독립 저장.
- **HTML 근사 프리뷰:** 실제 ZPL 렌더는 프린터 전용이라 canvas dot 좌표 재현 대신 1:3 flex + 의사 QR 그리드로 "수치 변경 즉시 감각적 반영"에 집중, `preview-hint` 로 근사임을 명시.
- **배지 색 재사용:** NUEVO=골드/CAMBIO=주황(#ff9800) — #ff9800 은 기존 코드(niveles 경고 등)에서 이미 쓰던 색이라 신규 팔레트 도입 없이 상태 구분.

## Deviations from Plan
None — 계획대로 실행. Task 1 마크업 id/구조, Task 2 배선(fetchPriceTypes/qrFetchPending/qrPrint/renderPreview/에러 가시성) 모두 플랜 action·acceptance_criteria 대로 구현.

> 참고: 플랜 예시의 layout 저장은 `setLabelLayout({...}) 또는 setConfig('qrLayout', {...})` 를 허용했고, 회귀 안전을 위해 후자(setConfig)를 선택. 이는 플랜이 명시한 선택지 내 결정이므로 deviation 아님.

## Threat Model Compliance
- **T-38-10 (Tampering, 임의 priceTypeId/items):** mitigate — items 는 `currentDelta`(서버 반환)에서만 필터 구성, priceTypeId 는 서버가 API key 로 branch/store 도출(38-01). renderer 는 임의 상품 주입 경로 없음. ✅
- **T-38-11 (Info Disclosure, 타 매장 노출):** accept — 델타는 서버 store 격리 후 반환, 단일 사용자 데스크탑. ✅
- **T-38-12 (EoP, node 직접 접근):** mitigate — contextIsolation=true + nodeIntegration=false(기존 유지), `window.electronAPI` 화이트리스트 IPC 만 사용. ✅

## Requirements Status
- **QR-08** (TAB3 2패널 UI: 좌 프리뷰+수치 / 우 델타 리스트+체크박스, price-type+1/2 토글, D-10) ✅ 마크업+배선 완료 (수동 UAT 로 시각 확정)
- **QR-09** (출력 성공분만 스냅샷/자동 제외, D-11) ✅ UI 층 — 성공분 행+currentDelta 제거로 다음 Buscar 재등장 방지(백엔드 mark_qr_printed 스냅샷은 38-01/02, 성공분만 전달)

## Confirmation: api-ventago sellers/* Untouched
`git diff --name-only e660454~1 7fdf93e` → `zebra-agent/renderer/index.html` 1개뿐. api-ventago 서브모듈/sellers 파일 0건. 작업 시작 시 존재하던 ` M api-ventago`(미커밋 sellers/vendedor 작업) 및 `m ventago-app` 은 손대지 않음. STATE.md/ROADMAP.md 미변경.

## Next Phase Readiness
- Wave 3 UI 완료 — Phase 38 코드 계층(38-01 백엔드 델타 + 38-02 formatter/IPC + 38-03 TAB3 UI) 전량 배선 완료.
- 잔여: 운영 PG10 `phase38-qr-print-log.sql` 수동 적용(38-01 user_setup) + dev electron 수동 UAT(위 Pending 목록) + zebra-agent push 시 `build-zebra-agent.yml` 태그 자동 증가(push-both.sh, 사용자 요청 시).

## Self-Check: PASSED
- Modified file exists: zebra-agent/renderer/index.html ✅
- Commits exist: e660454, 7fdf93e ✅
- Only renderer/index.html in commits (api-ventago/sellers 0 files) ✅
- Inline JS parses (no SyntaxError) ✅

---
*Phase: 38-codigomadre-qr-print*
*Completed: 2026-07-09*
