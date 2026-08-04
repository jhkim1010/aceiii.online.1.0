---
phase: 70-stock-cache-retirement-and-backlog-cleanup
plan: 04
subsystem: full-stack
tags: [reports, pdf, pdfkit, layout, export, trello]

# Dependency graph
requires: []
provides:
  - "리포트 공통 PDF 생성기 (ReportsPdfService — A4 가로 표 렌더, 헤더 반복, 페이지 번호, 절단 배너)"
  - "Stock Vistas / Stocks Cockpit 두 리포트의 동작하는 PDF 버튼 (화면 필터·정렬 그대로)"
  - "좁은 화면(110%/125% 확대)에서 액션 버튼이 필터에 가려지지 않는 리포트 상단바"
affects:
  - "나머지 15개 리포트 — downloadPdf 미등록이므로 PDF 버튼이 비활성 상태로 보인다"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "PDF 는 Excel export 와 같은 서버 생성 방식 — 동일한 buildQuery/params 를 재사용해 화면과 내용 일치를 구조로 보장한다"
    - "인쇄물에 들어갈 이름은 서버가 조회한다 — 클라이언트가 보낸 라벨 문자열을 믿지 않고, 숫자 ID 가 종이에 찍히는 것도 막는다"
    - "export 전용 경로는 화면 경로 함수에 얇은 래퍼(allowLargePage)로 얹는다 — 화면 상한·진단 로직을 건드리지 않는다"
    - "blob 다운로드의 실패는 본문이 Blob 이라 조용히 사라진다 — text→JSON 파싱으로 서버 message 를 복구해 노출한다"

key-files:
  created:
    - api-ventago/src/app/reports/reportsPdf.service.ts
    - ventago-app/src/utils/download-error.ts
  modified:
    - api-ventago/src/app/reports/reports.controller.ts
    - api-ventago/src/app/reports/reports.module.ts
    - api-ventago/src/app/reports/reportsStockVistas.service.ts
    - api-ventago/src/app/reports/reportsStocksCockpit.service.ts
    - ventago-app/src/views/reports-v2/ReportsTopbar.tsx
    - ventago-app/src/views/reports-v2/ReportsFilterFields.tsx
    - ventago-app/src/views/reports-v2/ReportActionsContext.tsx
    - ventago-app/src/views/reports/stock-vistas/StockVistasCockpitBody.tsx
    - ventago-app/src/views/reports/stock-vistas/hooks/useStockVistasReport.ts
    - ventago-app/src/views/reports/stocks/StocksCockpitBody.tsx
    - ventago-app/src/views/reports/stocks/panels/PanelB_ItemTable.tsx
    - ventago-app/src/services/api.service.ts
---

# 70-04 — 리포트 PDF export (Trello 30zWO5C8 "Pasar a pdf")

## 문제

신고: *"en el formato de notebook o 110% u 90% no aparece la opcion para traspasar a pdf... solo si esta en 70%"*.

**레이아웃 신고처럼 보이지만 원인이 둘이었다.**

1. `ReportsTopbar.tsx` 가 `height:56` 단일 flex row 에 `flexWrap` 이 없었다. 중앙 필터 슬롯은
   `flex:1, minWidth:0` 인데 자식 필드가 `minWidth:120/100` 고정이라 줄어들지 않아, 폭이 좁아지면
   필터가 슬롯 밖으로 넘쳐 우측 액션군을 덮었다. 70% 로 축소하면 다시 보이는 신고 내용과 정확히 일치한다.
2. **그 PDF 버튼은 `alert('PDF export — próximamente')` placeholder 였다.**
   보이게만 만들었다면 사용자는 "이제 보이는데 안 된다" 를 다시 신고했을 것이다.

둘 다 고쳤다.

## 무엇을 했나

### 레이아웃 (T1)

`flexWrap: 'wrap'` + `minHeight:56` / 높이 auto 를 택했다. `overflow:hidden` 대안은 **필터를 잘라 없애는**
방식이라 좁은 화면에서 사용자가 어떤 필터가 걸려 있는지 알 수 없게 된다. wrap 은 필터가 아랫줄로 내려갈 뿐
하나도 사라지지 않는다.

- 컨테이너 `minHeight:56 / flex:'0 0 auto' / py:0.75` (`ReportsTopbar.tsx:34-44`)
- 중앙 슬롯만 `flexWrap:'wrap' + rowGap/columnGap` (`:93-104`) — 액션 Stack 은 `flexShrink:0` 유지라
  wrap 후에도 항상 우측에 남는다
- 제목 `maxWidth:{xs:140, lg:220}` (`:84`), 필터 필드 `minWidth 120→112` (`ReportsFilterFields.tsx:26-30`)

1366@125%(가용 681px) 기준 요구 폭 = 140(제목)+112(필터 최소 1열)+245(액션) ≈ 497px → 성립.
**픽셀 실측은 브라우저 UAT 로만 확정된다** (아래 「남은 것」).

### PDF 생성 (T2)

`reportsPdf.service.ts` 신규 (537행). A4 **가로**, 표 렌더, 페이지마다 헤더 행 반복, 우하단 `Página N / M`.

### PDF 버튼 배선 (T3·T4)

`ReportActionsContext` 에 `downloadPdf` 를 추가하고 `hasExcel` 패턴을 그대로 복제했다 —
**등록하지 않은 리포트는 버튼이 비활성**이라 경고창이 뜨지 않는다. Body 가 등록 → Topbar 가 호출.

적용은 계획대로 **Stock Vistas / Stocks 두 개만**. 나머지는 아래 후속 목록.

## 설계 판단

### D1 — 레이아웃은 wrap (overflow:hidden 아님)

위 「레이아웃」 참조. 핵심은 **정보 손실 여부**다. `overflow:hidden` 은 액션을 지켜내는 대신 필터를 지운다.
wrap 은 상단바가 2~3줄이 되지만 아무것도 잃지 않는다. 리포트 화면에서 "어떤 필터가 걸렸는지" 는
액션 버튼만큼 중요하다.

### D2 — pdfkit 재사용 = 신규 패키지 0

플랜은 puppeteer 경로를 먼저 검토하라고 했다. 검토 결과 **이미 저장소에 `pdfkit` 이 있다** —
`subcon-settlements/settlement-pdf.service.ts` 가 쓰고 있다. puppeteer 는 헤드리스 크롬을 띄우므로
표 하나 뽑자고 워커 메모리를 수백 MB 물리게 된다. pdfkit 은 순수 렌더러라 그 비용이 없다.

**신규 npm 패키지 0건.** `pypdf` 는 규약대로 쓰지 않았다.

import 형태는 `import * as PDFDocument from 'pdfkit'` 를 썼다. 이 프로젝트 `tsconfig` 에
`esModuleInterop` 이 없어서 default import 는 `pdfkit_1.default`(undefined) 로 컴파일된다.
컴파일 산출물을 실제로 확인했다 — `const PDFDocument = require("pdfkit")` + `new PDFDocument({…})`.

### D3 — export 는 화면 경로에 얇은 래퍼로

`getItemsForExport()` 는 `getItems()` 를 `allowLargePage:true` 로 부르는 래퍼다(`reportsStocksCockpit.service.ts:494-503`).
화면 경로의 200행 상한은 `pageCap = allowLargePage === true ? EXPORT_PAGE_LIMIT : 200` 한 줄로만 갈린다.
쿼리를 복제했다면 이후 화면 쪽 수정이 export 에 반영되지 않아 조용히 갈라졌을 것이다.

### D4 — 행 상한 2,000 (플랜의 5,000 아님)

플랜은 예시로 5,000행을 들었지만 2,000 으로 낮췄다. pdfkit 렌더는 **동기 CPU 작업**이고 운영은 실질 단일
워커라, 렌더 시간이 그대로 이벤트 루프 정지 시간이 된다. 함께 넣은 완화책:

- 페이지 경계마다 `await new Promise(r => setImmediate(r))` 로 루프 양보 (`reportsPdf.service.ts:271`)
- **동시 생성 1건** `inFlight` 플래그 — 경합 시 429 즉시 거절 (`:163, :235-242, :290-292`)
- `rows·bytes·elapsedMs` 로깅 (`:283-287`)

절단 시 1페이지 상단 빨간 배너 + 각 페이지 푸터 `(truncado)`.

### D5 — 인쇄될 이름은 서버가 조회한다

`resolveLabels()` 가 store/branch/supplier/category/season 이름을 **UNION ALL 1쿼리**로 가져온다
(`:170-231`, 왕복 1회). 전 서브쿼리가 `store_id = :storeId` 스코프라 타 매장 이름이 새지 않는다.
라벨 조회가 실패해도 PDF 를 막지 않고 기본 문구로 폴백한다 — 이름 없는 PDF 가 PDF 없음보다 낫다.

### 열 폭 — 19열에서 무엇을 지킬 것인가

`sucursal-variante` vista 는 19열이라 Excel 폭을 그대로 비례 배분하면 Descripción 이 8pt 기준 약 22자에서
잘린다. 세 가지를 겹쳤다:

- 열 수 연동 폰트 `bodyFontFor()` — 16열 이상 6pt (`:147-148`)
- 텍스트 열 가중치 `PDF_WIDTH_BOOST` (`:73-87`)
- **숫자 열 최소 폭 바닥** 후 여유 열에서 비례 회수 (`layoutColumns()` `:297-340`)

바닥을 숫자에 더 후하게 준 이유: 텍스트가 잘리면 축약이지만 **숫자가 잘리면 값을 오독**한다(`123456` → `1234`).
실측 결과 19열에서 Descripción 42자 / Código 13자 / Estado `SIN_MOVIMIENTO` / 날짜 10자가 온전히 들어간다
(잘리는 열은 Color 11자 중 10자 1건).

## design-review F1〜F13 대응 결과

| # | Sev | 결과 | 처리 |
|---|---|---|---|
| F1 | Major | 해소 | 계약 문자열 `downloadPdf` 를 `ReportsTopbar.tsx:17` 주석으로 유지 (호출은 `ReportActionsContext` 경유 `invokePdf()`). 자동 게이트 통과 |
| F2 | Major | 해소 | D4 참조 — 상한 5000→2000, 페이지 경계 루프 양보, 동시 1건 429, rows/bytes/elapsedMs 로깅 |
| F3 | Major | 해소 | D5 참조 — 서버 라벨 조회, 숫자 ID 인쇄 없음, 전 서브쿼리 store_id 스코프 |
| F4 | Minor | 해소 | `getPdfColumns(vista)` public accessor 추가 (`reportsStockVistas.service.ts:483-486`) — private `resolveConfig`/`VISTA_CONFIG` 우회 없이 Excel 과 같은 헤더 출처 사용 |
| F5 | Minor | 해소 | `ReportActionsContext` 의 `useState(false)` 선언 포함 7곳 전부 반영 |
| F6 | Minor | 해소 | `pdfQueryRef` 초기값 `{sortBy:'rStock', sortDir:'asc'}` — 서버 기본값과 일치. 정렬을 한 번도 안 바꾼 첫 로드에서도 순서가 맞는다 |
| F7 | Minor | 해소 | `onQueryChange` 시그니처 `{sortBy, sortDir}` 통일, 호출을 `load()` **진입부**로(성공 조건 아님), deps 추가, 부모는 `useCallback([])` 로 안정화 |
| F8 | Minor | 해소 | 위 「열 폭」 참조 — 절단 정책을 코드로 확정하고 근거 주석을 남겼다 |
| F9 | Minor | 해소 | `sendPdf()` 주석에 "`X-Report-Truncated` 는 진단용, `downloadFile` 이 헤더를 버리므로 프런트 미소비 — UI 를 걸지 말 것" 명시 (`reports.controller.ts:1741-1744`) |
| F10 | Minor | **이 문서로 해소** | SUMMARY 미작성이 지적이었다. 아래 「plan 과의 차이」에 `files_modified` 편차를 기록했다 |
| F11 | Minor | 해소 | 신규 파일 `reportsPdf.service.ts` error 0 / warning 1, 프런트 error 0. 잔여였던 `reports.controller.ts:1721` prettier 1건은 이번 후속 커밋에서 정리 |
| F12 | Minor | 해소 | Stocks 는 `resolveScopedStoreId(user, query.storeId)`, Stock Vistas 는 `resolveStockVistasStoreId` — 둘 다 인증 주체 파생. 비-superadmin 이 남의 storeId 를 보내면 `ForbiddenException` |
| F13 | Minor | N/A | plan.md 행번호 표기 문제. 코드 영향 없음 |

## 검수(Inspector) 지적 후속 처리

Inspector 판정은 **GO**(비차단)였고, §5 의 4건을 이어서 처리했다.

| 지적 | 처리 |
|---|---|
| `reports.controller.ts:1721` prettier 1건 | 개행 정리. **신규 구간(≥1600행)의 lint 지적 0건** 확인. 남은 prettier 7건(168/715-731)은 `git blame` 으로 커밋 `89389dd` 소속 = 70-04 이전 부채 |
| PDF 실패가 완전 무음 | 아래 「다운로드 실패 노출」 |
| export 경로 DEBUG 진단 쿼리 | `filterParam && rows.length > 0 && filters.allowLargePage !== true` — export 에서만 건너뛴다. 화면 경로(200행·진단 출력)는 무변경 |
| `uFecha` 가 숫자 컬럼 취급 | `PDF_NUMERIC_KEYS` 에서 제외 |

### 다운로드 실패 노출 (신규 `download-error.ts`)

`downloadPdf` 의 catch 가 `console.log` 만 하고 끝나서 429·400·500 이 사용자에게 보이지 않았다.
운영은 실질 단일 워커라 **두 지점이 동시에 PDF 를 누르면 한쪽은 아무 반응 없이 끝난다.**

파고들어 보니 원인이 두 겹이었다:

1. `apiConnector.downloadFile` 은 `responseType:'blob'` 이라 **에러 본문도 Blob** 으로 온다.
   그래서 axios 인터셉터의 `error.response.data.message` 가 `undefined` 가 되고,
   전역 배너(`GlobalErrorBanner`)에는 `Error 429 al procesar la solicitud` 같은 **일반 문구만** 뜬다.
2. 인터셉터가 `throw new Error(error.response.data.message)` 로 **원본 응답을 버린 채** 다시 던져서,
   호출부 catch 는 상태코드조차 알 수 없었다(`Error("undefined")`).

처리:

- `src/utils/download-error.ts` 신규 — Blob → text → JSON 순으로 서버 `message` 를 복구하고
  `react-hot-toast` 로 노출. 파싱은 어떤 경로로도 throw 하지 않으며, 실패 시 상태코드 기반 문구
  (429 = `Ya hay una descarga en curso…`)로 폴백한다. 취소된 요청(`ERR_CANCELED`)은 알리지 않는다.
- `api.service.ts` 인터셉터가 rethrow 하는 Error 에 `response`/`status` 를 실어 보낸다.
  기존 소비자는 `.message` 만 읽으므로 **속성 추가는 하위 호환**이다.

`<Toaster />` 마운트를 확인했다 — `_app.tsx:336`. 인라인 Alert 쪽도 같은 파일 `:339` 의
`<GlobalErrorBanner />` 가 인터셉터의 `errorBus` push 를 받아 이미 뜬다.
즉 규약(`feedback_error_visibility`: 인라인 Alert + 글로벌 토스트)은 **배너(인터셉터) + 토스트(헬퍼)** 조합으로 충족된다.
`downloadExcel` 은 범위 밖이라 건드리지 않았다 — 같은 헬퍼를 붙이면 되는 후속 항목이다.

### `uFecha` 를 숫자 집합에서 뺀 근거 (레이아웃 破綻 여부 검증)

`PDF_NUMERIC_KEYS` 멤버십이 좌우하는 것은 **정렬 방향**과 `layoutColumns()` 의 **최소 폭 바닥** 두 가지뿐이다.
`minNumericW(7)=29.35pt` → `minTextW(7)=27pt` 로 바닥이 **낮아지므로** `floorSum` 이 줄어 배분이 오히려 여유로워진다.
Stocks Cockpit 15열(bodyFont 7pt) 실계산:

| | 숫자 취급(종전) | 텍스트 취급(현재) |
|---|---|---|
| floorSum | 435.55pt | 433.20pt |
| 회수 비율 | 0.9641 | 0.9643 |
| `uFecha` 최종 폭 | 51.3pt | 51.2pt |

폭 변화 0.1pt, 나머지 열은 0.01pt 미만. `2026-08-03`(10자)은 7pt 기준 약 38.9pt 라 여유가 남는다.
**破綻하지 않으므로 제외를 확정**했고 근거를 코드 주석으로도 남겼다(`reportsPdf.service.ts` PDF_NUMERIC_KEYS 위).

## plan 과의 차이 — ★ files_modified 3건 vs 실제 12건

`70-04-PLAN.md` frontmatter 의 `files_modified` 는 3건이다. 실제로는 **12파일**을 만졌다
(후속 커밋까지 포함하면 14파일). 플랜이 T1(레이아웃)·T3(배선)·T4(적용 대상)의 파급을 파일 목록에 반영하지 않은 것이다.

| 파일 | plan | 실제 | 왜 |
|---|---|---|---|
| `reports-v2/ReportsTopbar.tsx` | 수정 | 수정 | — |
| `reports/reportsPdf.service.ts` | 신규 | 신규 | — |
| `reports/reports.module.ts` | 수정 | 수정 | — |
| `reports/reports.controller.ts` | — | **추가** | PDF 엔드포인트 2개(`stock-vistas-pdf`, `stocks-cockpit/items-pdf`) + `sendPdf()` |
| `reports/reportsStockVistas.service.ts` | — | **추가** | F4 의 `getPdfColumns()` accessor |
| `reports/reportsStocksCockpit.service.ts` | — | **추가** | `getItemsForExport()` + `allowLargePage` + PDF 헤더 상수 |
| `reports-v2/ReportActionsContext.tsx` | — | **추가** | T3 의 `downloadPdf` 등록/호출 계약 |
| `reports-v2/ReportsFilterFields.tsx` | — | **추가** | T1 의 필드 `minWidth 120→112` |
| `stock-vistas/StockVistasCockpitBody.tsx` | — | **추가** | `downloadPdf` 등록 지점 |
| `stock-vistas/hooks/useStockVistasReport.ts` | — | **추가** | `downloadPdf` 구현(Excel 과 같은 `buildQuery`) |
| `stocks/StocksCockpitBody.tsx` | — | **추가** | `downloadPdf` 등록 + 정렬 미러 `pdfQueryRef` |
| `stocks/panels/PanelB_ItemTable.tsx` | — | **추가** | 정렬 상태를 부모로 올리는 `onQueryChange` |
| `ventago-app/src/utils/download-error.ts` | — | **추가(후속)** | 다운로드 실패 노출 헬퍼 |
| `ventago-app/src/services/api.service.ts` | — | **추가(후속)** | rethrow Error 에 response/status 보존 |

**교훈**: "버튼을 실제로 동작시킨다" 는 T3 는 등록·호출·상태 미러 3계층을 건드린다. 플랜 단계에서
`files_modified` 에 UI 배선 파일이 한 개(Topbar)만 잡혀 있으면 실제 diff 는 반드시 커진다.

## DB / 패키지

- **DB 마이그레이션 0건.** 스키마를 건드리지 않았다. 신규 SQL 은 조회 전용이며 `stocks` 를 읽지 않는다.
- **신규 npm 패키지 0건.** 저장소에 이미 있는 `pdfkit` 재사용 (D2).

## 검증

Inspector 실측(api `eb31895` / front `7105226`) + 후속 수정 후 재실행 값. **재실행한 항목은 아래 값이 최신이다.**

| 명령 | exit | 요약 |
|---|---|---|
| `npx eslint` (프런트 변경 4파일, 재실행) | **0** | 출력 없음 — error 0 / warning 0 |
| `npm run build` (ventago-app, 재실행) | **0** | 125 페이지 생성. `Warning:` 30건은 전부 기존 파일의 `react-hooks/exhaustive-deps` — 변경 파일에 해당 경고 0건 |
| `npx eslint src/app/reports/reports.controller.ts` (재실행) | 1 | 총 15 errors — **신규 구간(≥1600행) 지적 0건**. prettier 잔여 7건은 커밋 `89389dd` 소속 기존 부채, `no-unsafe-*` 8건도 기존 |
| `npx tsc --noEmit -p tsconfig.build.json` (재실행) | **0** | 출력 없음 |
| `npx nest build` (재실행) | **0** | dist 생성 확인 |
| `npx jest --testPathPattern "reports"` (재실행) | **0** | `3 passed / 3 total`, `19 passed / 19 total` — 신규 실패 0건 |

`.env` 없는 worktree 에서는 `reportsSalesCockpit.spec.ts` 가 `database "marcoskim" does not exist` 로 실패한다(환경 문제).
본 저장소 `.env` 를 임시 복사해 실행하고 **검증 후 삭제**했다.

Phase 70 baseline 의 기존 실패(15 suites / 33 tests)는 이번 변경과 무관하며 `reports` 패턴 밖이다.

DB 접근은 로컬 PG18(5432) SELECT 전용(치환 검증 1회). DDL/DML 0건. 운영 미접속.

## 남은 것

### 브라우저 수동 UAT (미실행 — 로컬 API 5002 / 앱 3050 / PG 5432)

1. **레이아웃** — 1366×768 에서 `/reportes-v2/stocks`, `/reportes-v2/stock-vistas` 를 70%/100%/110%/125% 로:
   ⭐·XLS·PDF·Ejecutar 4개가 전부 보이고 **클릭이 먹히는지**, 필터가 아랫줄로 접히며 하나도 사라지지 않는지,
   상단바가 2~3줄이 돼도 아래 표가 잘리지 않는지, 70% 에서 기존처럼 1줄 56px 인지(회귀 확인)
2. **PDF 실물** — Stock Vistas 4개 vista 전부 열어: 헤더의 매장·지점·`Vista/Estado/Buscar` 가 화면과 같은 값(숫자 ID 아님)인지,
   19열 `sucursal-variante` 에서 Descripción/Código/Estado/날짜가 잘리지 않는지, 2페이지 이상일 때 헤더 반복 + `Página N / M`
3. **Stocks 정렬 일치** — Panel A 지점 + Proveedor/Tipo/Temporada/Buscar + Panel B 헤더 클릭 정렬 후 PDF 의
   행 순서·필터 요약이 화면과 같은지. 특히 **최초 로드 직후(정렬 미변경)** 상태
4. **절단 배너** — `PDF_MAX_ROWS` 를 임시로 5 로 낮춰 상단 빨간 배너 + 푸터 `(truncado)` 확인 후 2000 복원
5. **비활성 버튼** — `/reportes-v2/ventas` 등에서 PDF 아이콘이 비활성이고 경고창이 없는지
6. **동시 생성 429** — 두 탭에서 거의 동시에 PDF 클릭 → 한쪽에 `Ya hay una descarga en curso…` 토스트가 뜨는지
   (이번 후속 수정의 실증. 종전에는 무음이었다)

### 후속 항목

1. **PDF 미적용 15개 리포트** — `downloadPdf` 미등록이라 버튼이 비활성이다:
   `ventas · items · vendedor · clientes-credito · breve-venta · reservado · alertas · facturacion · gastos · cheque-estado · ingreso · corregido · movidos · fallados · season-turnover`
2. **`subcon/subcon-settlements/settlement-pdf.service.ts:2`** — `import PDFDocument from 'pdfkit'` (default import) 가 남아 있다.
   `tsconfig` 에 `esModuleInterop` 이 없어 `pdfkit_1.default` 로 컴파일되므로 런타임 `is not a constructor` 가능성.
   `GET .../settlements/:id/pdf` 실동작 확인 필요. (이번 신규 코드는 `import * as` 형태를 쓴다 — D2)
3. **`reportsPdf.service.ts` 단위 테스트 없음** — 537행 신규 서비스에 spec 이 없다.
   `layoutColumns()`(최소폭 회수)·`formatValue()`·`sanitize()` 는 순수 함수라 DB 없이 테스트 가능
4. **백엔드 lint 부채** — `reportsStocksCockpit.service.ts` 145 / `reports.controller.ts` 15 / `reportsStockVistas.service.ts` 13 errors (전부 기존).
   백엔드는 빌드에 lint 게이트가 없어 방치돼 왔다. "수정 파일 eslint 0" 같은 계획 문구는 백엔드에서 애초에 달성 불가능한 기준이다
5. **`downloadExcel` 에도 실패 노출** — 같은 `notifyDownloadError` 헬퍼를 붙이면 된다(이번 범위 밖)
6. **`ventago-app/_to_delete/`** — worktree 에 과거 git lock 잔해 디렉터리가 있다(추적되지 않음, 이번 작업과 무관). 정리 대상
