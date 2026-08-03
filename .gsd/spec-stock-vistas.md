# SPEC: Reportes › Stock Vistas — 재고 4관점 리포트
생성일: 2026-08-02

## 목표

`Reportes` 화면에 신규 리포트 **Stock Vistas** 를 추가한다. 지점별/통합 × 변형/코디고 마드레 **4관점**을 탭으로 전환해 보고, Excel 로 내보낸다. 데이터는 새로 만드는 재고 스냅샷(`stock_balances`) 기반 인터페이스 뷰 4종에서만 읽는다.

## 배경 및 컨텍스트

- 근거 문서: `.planning/stock-views-proposal-2026-08-02.md` (W1~W4 구간을 이번에 구현)
- 목업 승인 완료 — 탭 4개, estado 칩, % 막대, `DEPÓSITO` 배지, `Sucurs. c/stock` 컬럼
- 계기: Trello LNBmJ2ZI — 재고 정의가 코드 여러 곳에 흩어져 있어 재고가 음수로 내려간 사고
- 실측 벤치마크(운영 동급 서버, 원장 1,000만 행): legacy 방식 253ms vs 스냅샷 0.61ms (**415배**)
- 현재 규모는 손익분기점(매장당 원장 1,800행) 미만 — 지금 이득이 아니라 **분기점 이후를 위한 구조**임을 인지하고 진행

### 현재 구조 (조사 완료)

| 항목 | 위치 |
|---|---|
| 리포트 등록 | `ventago-app/src/views/reports-v2/registry.ts` — `REPORTS_REGISTRY` 배열에 `ReportEntry` 1개 추가하면 사이드바·토픽바·본문 자동 연결 |
| 카테고리 | `inventario` (기존 6개: ingreso/stocks/corregido/movidos/fallados/season-turnover) |
| 메뉴 | `menuRegistry.ts` 수정 **불필요** — `reportes` 는 `directPath:'/reportes-v2'` 통합 셸 |
| 백엔드 | `api-ventago/src/app/reports/reports.controller.ts` + 리포트별 `Reports<Name>Service` (raw SQL) |
| 권한 | `@FunctionGuard('reporte-<slug>','read')` + `functions.seed.ts` 의 `individualReportFunctions` |
| 테이블 | AG Grid 아님 — **커스텀 MUI Table** (`PanelB_ItemTable.tsx` 패턴) |
| 필터 | `filterSchema` 문자열 배열 → `ReportsFilterFields.tsx` 자동 렌더. 공용 `SucursalField`(`__all__` 마커), `DateRangeField` |
| Excel | 서버 생성 방식 — Body 가 `useReportActionsRegistration({ downloadExcel })` 등록 → Topbar 버튼이 호출 → `apiConnector.downloadFile('/reports/<slug>-export', fileName, params)` |

### 로그 확인 (2026-08-02 23:20)

- `api_ventago` 최근 2시간 에러 없음 (RouterExplorer 매핑 로그만)
- Jenkins `api-new-coolsistema #596`, `front-coolsistema #526` 모두 SUCCESS
- 운영 DB 활성 커넥션 3개 — 정상

## 기술 스택

- 백엔드: NestJS 11 + Sequelize (`sequelize.query()` — **풀 관리형**, 수동 `connect()/release()` 없음)
- 프론트: Next.js 13 Pages Router + MUI 5 + Redux Toolkit
- DB: PostgreSQL 18 — 로컬 5432 / 운영 5434 (pgbouncer 5432 경유)
- ESLint: `ventago-app/.eslintrc` — **warning 도 빌드를 막음** (프론트만 해당)

## 태스크 목록

### A. DB 마이그레이션 (로컬 5432 + 운영 5434 **양쪽** 적용)

- [ ] **TASK-1**: `stocks` 에 `store_id` / `branch_id` 추가 + 백필 + 인덱스 + BEFORE INSERT 자동 채움 트리거
  파일: `api-ventago/migrations/2026-08-02-stocks-tenant-columns.sql`
  → 조인 3개 제거 + Phase 67 격리 사각지대 해소. 앱 코드 변경 불필요(트리거가 채움)
- [ ] **TASK-2**: `stock_balances` 테이블 + `AFTER INSERT` 증분 트리거 + 전량 백필 + owner 이전
  파일: `api-ventago/migrations/2026-08-02-stock-balances.sql`
- [ ] **TASK-3**: 감시 뷰 `v_stock_balance_drift`, `v_stock_tenant_leak`
  파일: `api-ventago/migrations/2026-08-02-stock-drift-watch.sql`
- [ ] **TASK-4**: `v_stock_dia` + 인터페이스 뷰 4종
  파일: `api-ventago/migrations/2026-08-02-stock-interface-views.sql`
  뷰: `v_stock_sucursal_variante` / `v_stock_total_variante` / `v_stock_sucursal_madre` / `v_stock_total_madre`

### B. 백엔드

- [ ] **TASK-5**: `ReportsStockVistasService` — 4관점 조회(vista 파라미터) + 필터(sucursal/estado/search) + 페이지네이션 + KPI
  파일: `api-ventago/src/app/reports/reportsStockVistas.service.ts`
- [ ] **TASK-6**: 컨트롤러 엔드포인트 2개 — `GET /reports/stock-vistas`, `GET /reports/stock-vistas-export`
  파일: `api-ventago/src/app/reports/reports.controller.ts` (+ 모듈 provider 등록)
- [ ] **TASK-7**: 권한 함수 시드 `Reporte Stock Vistas` → 슬러그 `reporte-stock-vistas`
  파일: `api-ventago/src/app/functions/seed/functions.seed.ts`

### C. 프론트

- [ ] **TASK-8**: `useStockVistasReport` 훅 — `stockVistasDefaultParams`, 조회, `downloadExcel`
  파일: `ventago-app/src/views/reports/stock-vistas/hooks/useStockVistasReport.ts`
- [ ] **TASK-9**: Body 컴포넌트 — 탭 4개 + MUI Table + estado 칩 + % 막대 + KPI
  파일: `ventago-app/src/views/reports/stock-vistas/StockVistasCockpitBody.tsx`
- [ ] **TASK-10**: `registry.ts` 엔트리 추가 (lazy import 포함)
  파일: `ventago-app/src/views/reports-v2/registry.ts`

### D. 검증

- [ ] **TASK-11**: 프론트 ESLint 0 오류 (`npx eslint <파일> `)
- [ ] **TASK-12**: 백엔드 `npx tsc --noEmit -p tsconfig.build.json`
- [ ] **TASK-13**: PostgreSQL pool 안전 점검
- [ ] **TASK-14**: 마이그레이션 양쪽 적용 확인 + `v_stock_balance_drift` **0행** 확인
- [ ] **TASK-15**: push → Jenkins 빌드 성공 + 컨테이너 재생성 확인

## 완료 기준

- ESLint 오류 0개 (프론트), tsc 오류 0개 (백엔드)
- 마이그레이션이 **로컬(5432)·운영(5434) 양쪽**에 적용됨
- `SELECT count(*) FROM v_stock_balance_drift` = **0**
- `SELECT count(*) FROM v_stock_tenant_leak` = **0**
- 4개 탭의 숫자가 서로 맞물림: 변형 합 = 마드레, 지점 합 = 통합
- Jenkins `api-new-coolsistema` / `front-coolsistema` 빌드 SUCCESS + 컨테이너 재생성

## PostgreSQL pool 안전 규칙 (이 작업 적용분)

- Sequelize `sequelize.query()` 만 사용 — 수동 `connect()/release()` 없음(누수 지점 자체가 없음)
- 트랜잭션 불필요 (전부 읽기 전용 조회)
- **트랜잭션 안 외부 I/O 금지** 원칙 유지 — Excel 생성은 조회 완료 후 메모리에서 수행
- 페이지네이션 **필수**, `pageSize` 상한 50 (프로젝트 규약)
- 뷰 조회는 반드시 `store_id` 로 먼저 좁힌다 (인덱스 사용 + 테넌트 격리)
- 신규 트리거는 `stock_balances` 1행만 잠근다 — 기존 `products` 부모 행 잠금보다 경합이 **적다**

## 금지사항 / 주의사항

- ❌ `trg_stocks_sync_product_cache` **제거 금지** — 이번 범위는 W1~W4 까지. 캐시 폐기는 W7(별도 phase)
- ❌ `products.stock` 읽는 기존 코드 변경 금지 — 이번 리포트는 새 뷰만 읽는다
- ❌ 기존 `stocks` 리포트(`slug: 'stocks'`) 파일 수정 금지 — 회귀 위험
- ❌ `stocks` 원장 행 UPDATE/DELETE 금지 (`trg_stocks_immutable` 이 막지만 시도 자체를 하지 않는다)
- ❌ `menuRegistry.ts` 수정 불필요
- ⚠️ 신규 테이블은 마이그레이션 끝에 `ALTER TABLE/SEQUENCE ... OWNER TO coolsistema` DO 블록 필수 — 누락 시 운영 permission denied 500
- ⚠️ 뷰 조인에 **매장 가드** 필수: `AND b.store_id = p.store_id`, `AND pm.store_id = p.store_id`
- ⚠️ 프론트 ESLint — `return` 위 빈 줄, `//` 주석 위 빈 줄, 미사용 import 금지
- ⚠️ 컬럼명은 `.planning/intel/db-schema-tables.md` 로 확인 후 사용 (추측 금지)
