---
phase: 16-control-de-talleres
plan: "09"
subsystem: talleres-cut-ticket
tags: [talleres, cut-ticket, zedonk, matrix, bom, pdf, wave9, pdfkit, sequelize-for-update]

dependency_graph:
  requires: ["16-02", "16-03", "16-05", "16-07"]
  provides: ["cut-ticket-backend", "cut-ticket-frontend", "bom-snapshot-structure"]
  affects: ["talleres-lotes", "talleres-main-view", "pedidos-page"]

tech_stack:
  added:
    - "talleres_cut_ticket_counters table (composite PK store_id+year, SELECT FOR UPDATE 기반)"
    - "Lote 모델 7 신규 컬럼 (cutTicketNumber/styleCode/season/cutDate/sizeColorMatrix/bomSnapshot/routingPath)"
    - "CutTicketCounter Sequelize 모델"
    - "CutTicketPdfService — pdfkit A4 landscape"
    - "useCutTicket / useLotesWithCutTicket SWR 훅 (1분 dedup)"
    - "SizeColorMatrixEditor — React.memo + useMemo + debounce 300ms"
    - "RoutingFlow — EtapaFlowVisual 래퍼"
  patterns:
    - "SELECT FOR UPDATE 락으로 원자적 시퀀스 카운터 증가 (T-16-09-01)"
    - "멱등 generateCutTicket (이미 발급 시 카운터 증가 없이 기존 반환)"
    - "INV-C/D 불변 조건 — cut_date 설정 후 매트릭스 편집/재설정 차단"
    - "BOM 확장 포인트 — buildBomSnapshot 빈 배열 반환 (Wave 10 교체 예정)"
    - "next/dynamic 코드 스플릿 (CutTicketTab)"

key_files:
  created:
    - api-ventago/migrations/20260423-cut-ticket-system-step1-schema.sql
    - api-ventago/migrations/20260423-cut-ticket-system-step2-verify.sql
    - api-ventago/src/app/subcon/lotes/cut-ticket.types.ts
    - api-ventago/src/app/subcon/lotes/cut-ticket-counter.model.ts
    - api-ventago/src/app/subcon/lotes/cut-ticket-pdf.service.ts
    - ventago-app/src/hooks/api/useCutTicket.ts
    - ventago-app/src/views/talleres/cut-ticket/types.ts
    - ventago-app/src/views/talleres/cut-ticket/CutTicketTab.tsx
    - ventago-app/src/views/talleres/cut-ticket/components/CutTicketHeader.tsx
    - ventago-app/src/views/talleres/cut-ticket/components/SizeColorMatrixEditor.tsx
    - ventago-app/src/views/talleres/cut-ticket/components/BomTable.tsx
    - ventago-app/src/views/talleres/cut-ticket/components/RoutingFlow.tsx
    - ventago-app/src/views/talleres/cut-ticket/components/CutTicketEmptyState.tsx
  modified:
    - api-ventago/src/app/subcon/lotes/lote.model.ts
    - api-ventago/src/app/subcon/lotes/lote.service.ts
    - api-ventago/src/app/subcon/lotes/lote.controller.ts
    - api-ventago/src/app/subcon/subcon.module.ts
    - api-ventago/src/app/functions/seed/functions-seed-talleres.ts
    - ventago-app/src/views/talleres/TalleresMainView.tsx
    - ventago-app/src/views/talleres/components/constants.ts
    - ventago-app/src/pages/talleres/pedidos/index.tsx

decisions:
  - "QR code: qrcode 패키지 미설치 — 텍스트 placeholder로 대체 (Wave 10 또는 enhancement에서 npm i qrcode + doc.image()로 교체)"
  - "BOM buildBomSnapshot: production/materials 모듈 미가용 → 빈 배열 반환 (Wave 10 Cost Sheet에서 실제 자재 데이터로 교체)"
  - "CutTicketPdfService.generate() store 파라미터 타입: cuit를 string|number로 허용 (Store 모델의 cuit가 BIGINT number임)"
  - "pedidos 페이지 경로: /pedidos 아닌 /talleres/pedidos (라우터 구조 확인 후 정확한 경로에 배너 추가)"

metrics:
  duration: "약 120분"
  completed_date: "2026-04-21"
  tasks_completed: 3
  files_created: 13
  files_modified: 8
---

# Phase 16 Plan 09: Wave 9 — Cut Ticket System Summary

**한 줄 요약:** Zedonk Cut Ticket 시스템 — 매장+연도 FOR UPDATE 시퀀스 카운터 + 멱등 generateCutTicket + A4 landscape PDF + SizeColorMatrix 편집(INV-C/D 불변 조건) + TalleresMainView 8번째 탭

---

## Tasks Completed

| Task | Name | Commit | Sub-repo | Key Files |
|------|------|--------|----------|-----------|
| 1 | Backend DB 마이그레이션 + Lote 확장 + 서비스 + PDF | `03b9eee` | api-ventago | migrations×2, cut-ticket.types.ts, cut-ticket-counter.model.ts, lote.model.ts, lote.service.ts, lote.controller.ts, cut-ticket-pdf.service.ts, subcon.module.ts, functions-seed-talleres.ts |
| 2 | Frontend CutTicketTab + 5 서브컴포넌트 + SWR 훅 | `a003711` | ventago-app | useCutTicket.ts, cut-ticket/types.ts, CutTicketTab.tsx, CutTicketHeader.tsx, SizeColorMatrixEditor.tsx, BomTable.tsx, RoutingFlow.tsx, CutTicketEmptyState.tsx |
| 3 | TalleresMainView 탭 + /pedidos deprecation | `0034b94` | ventago-app | TalleresMainView.tsx, constants.ts, pages/talleres/pedidos/index.tsx |

---

## Artifacts Delivered

### Must-Have Truths 검증

- [x] talleres_lotes에 cut_ticket_number VARCHAR(40) + uq_cut_ticket_store UNIQUE(store_id, cut_ticket_number) — DB 레벨 중복 차단
- [x] generateCutTicket — 단일 Sequelize transaction + SELECT FOR UPDATE counter + CT-${year}-${seq.padStart(3,'0')} 포맷 발급
- [x] 멱등 (INV-B) — 이미 cut_ticket_number 있으면 카운터 증가 없이 기존 반환
- [x] size_color_matrix JSONB — {colors, sizes, qty[colorId][sizeId]} 구조 + totalQuantity = Σ cells
- [x] bom_snapshot JSONB — 빈 배열 기본값 (buildBomSnapshot 확장 포인트, Wave 10 교체)
- [x] routing_path JSONB — talleres_etapas order ASC + vendorAssignments 매핑
- [x] PATCH /size-color-matrix — INV-matrix-frozen: cut_date IS NOT NULL → 400 CutTicketImmutableException
- [x] PATCH /cut-date — INV-D: NULL→날짜 한 번만 전이, 재설정 400
- [x] GET /:id/cut-ticket — cut_ticket_number null → 404 CutTicketNotGeneratedException
- [x] GET /:id/cut-ticket/pdf — pdfkit A4 landscape + header/matrix/BOM/routing/QR placeholder
- [x] GET /lotes?hasCutTicket=true — cut_ticket_number IS NOT NULL 필터 지원
- [x] TalleresMainView 8탭 (pipeline 다음 cut-ticket, URL ?tab=cut-ticket)
- [x] CutTicketTab — lote selector + empty state CTA + Header/Matrix/BOM/Routing + PDF 버튼
- [x] SizeColorMatrixEditor — cut_date != null → read-only, debounce 300ms + useMemo 합계 + React.memo
- [x] RoutingFlow — EtapaFlowVisual 재사용 (synthetic etapas + envios)
- [x] PDF 다운로드 — apiConnector.get(path, {responseType:'blob'}) + filename=cut-ticket-${number}.pdf
- [x] CASL slug talleres_cut_ticket_edit 시드
- [x] /talleres/pedidos 상단 Warning Alert 배너 (기존 기능 보존)

---

## Smoke Test Results

### Migration Step2 검증 출력

```
 column_name    |     data_type     | is_nullable
----------------+-------------------+-------------
 bom_snapshot   | jsonb             | YES
 cut_date       | date              | YES
 cut_ticket_number | character varying | YES
 routing_path   | jsonb             | YES
 season         | character varying | YES
 size_color_matrix | jsonb          | YES
 style_code     | character varying | YES
(7 rows)

        conname       |         pg_get_constraintdef
---------------------+--------------------------------------
 uq_cut_ticket_store | UNIQUE (store_id, cut_ticket_number)
(1 row)

      indexname       | indexdef (WHERE cut_ticket_number IS NOT NULL)
(1 row)

 store_id | integer  NO / year | smallint NO / last_seq | integer NO default 0 / ...
(5 rows)

contype: c(year>=2026), c(last_seq>=0), f(FK stores), p(PK store_id+year)
```

### TSC / Lint / Build

| 체크 | 결과 |
|------|------|
| `api-ventago npx tsc --noEmit` | 0 errors |
| `api-ventago npm run build` | exit 0 |
| `ventago-app npx tsc --noEmit` (Wave 9 파일) | 0 errors |
| `ventago-app npx next lint --dir src/views/talleres/cut-ticket --dir src/hooks/api` | 0 warnings |
| `ventago-app npx next lint --dir src/views/talleres --dir src/pages/talleres/pedidos` | 0 warnings |

### Nest 부팅 + Wave 9 라우트 매핑

```
Mapped {/api/talleres/lotes/:id/cut-ticket, POST} route
Mapped {/api/talleres/lotes/:id/cut-ticket, GET} route
Mapped {/api/talleres/lotes/:id/cut-ticket/pdf, GET} route
Mapped {/api/talleres/lotes/:id/size-color-matrix, PATCH} route
Mapped {/api/talleres/lotes/:id/cut-date, PATCH} route
Nest application successfully started
```

### HTTP 401 프로브 (인증 없이)

| 엔드포인트 | 응답 |
|------------|------|
| POST /api/talleres/lotes/1/cut-ticket | 401 |
| GET /api/talleres/lotes/1/cut-ticket | 401 |
| GET /api/talleres/lotes/1/cut-ticket/pdf | 401 |
| PATCH /api/talleres/lotes/1/size-color-matrix | 401 |
| PATCH /api/talleres/lotes/1/cut-date | 401 |

### DB 제약 스모크

| 테스트 | 결과 |
|--------|------|
| uq_cut_ticket_store UNIQUE 존재 확인 | PASS |
| year=2025 INSERT → CHECK 위반 | PASS (violates check constraint "talleres_cut_ticket_counters_year_check") |
| last_seq=-1 INSERT → CHECK 위반 | PASS (violates check constraint "talleres_cut_ticket_counters_last_seq_check") |

---

## Deviations from Plan

### 계획대로 실행 (주요)

- 2-file 마이그레이션 (step1 트랜잭션 DDL + step2 검증)
- BOM 빈 배열 기본값 (buildBomSnapshot 확장 포인트)
- QR 텍스트 placeholder (qrcode 패키지 미설치 — Wave 10 교체 예정)
- TalleresMainView 최소 변경 (+1 탭, Wave 8에서 전면 재구성)

### 자동 수정 사항

**[Rule 1 - Bug] Store.cuit 타입 불일치 수정**
- 발견: CutTicketPdfService의 generate() 파라미터에 store.cuit가 string으로 선언되었으나 Store 모델은 BIGINT (number)
- 수정: `cuit?: string | number`로 변경
- 파일: api-ventago/src/app/subcon/lotes/cut-ticket-pdf.service.ts

**[Rule 2 - 누락] CutTicketEmptyState.tsx 미사용 import 제거**
- ESLint no-unused-vars: Box import 제거
- 파일: ventago-app/src/views/talleres/cut-ticket/components/CutTicketEmptyState.tsx

### 발견 사항

- /pedidos 경로: 루트 /pedidos 아닌 /talleres/pedidos/index.tsx에 위치 (계획서는 ventago-app/src/pages/pedidos/index.tsx 명시했으나 실제는 talleres 하위) — 정확한 경로에 배너 추가함

---

## Known Stubs

| Stub | 파일 | 이유 |
|------|------|------|
| buildBomSnapshot 빈 배열 | api-ventago/src/app/subcon/lotes/lote.service.ts | production/materials 모듈 미가용 — Wave 10 Cost Sheet에서 실제 BOM 데이터로 교체 예정 |
| drawQrPlaceholder 텍스트 | api-ventago/src/app/subcon/lotes/cut-ticket-pdf.service.ts | qrcode npm 미설치 — Wave 10 또는 enhancement에서 doc.image(qrBuffer)로 교체 예정 |
| meta.dueDate null | lote.service.ts findCutTicketDetail | Wave 9 스코프 — Wave 10+에서 envio.dueDate 최소값으로 확장 예정 |

---

## 다음 단계

- **Wave 10 (Cost Sheet)**: buildBomSnapshot의 bom_snapshot 구조를 원천으로 사용하여 실제 자재 원가 계산
- **Wave 8 (Dashboard + Polish)**: TalleresMainView 전면 재구성 (5+2 탭 구성)
- **운영 배포**: `sudo -u postgres psql -d ventago -v ON_ERROR_STOP=1 -1 -f 20260423-cut-ticket-system-step1-schema.sql` (PG10 호환)

---

## Self-Check: PASSED

- [x] 마이그레이션 2파일 존재 + 로컬 적용 완료
- [x] api-ventago 커밋 03b9eee 존재
- [x] ventago-app 커밋 a003711 존재
- [x] ventago-app 커밋 0034b94 존재
- [x] TSC 0 errors (api + app Wave 9 파일)
- [x] Lint 0 warnings
- [x] build exit 0
- [x] Nest 5 Wave 9 라우트 매핑 확인
- [x] HTTP 401 × 5 프로브 통과
- [x] DB CHECK/UNIQUE 제약 스모크 통과
