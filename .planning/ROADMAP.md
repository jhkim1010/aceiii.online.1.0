# Roadmap: Ventago POS/ERP

## Overview

Ventago v1.0 핵심 기능(POS, 재고, 재무, 생산, 외주, 세션 보안)은 이미 운영 중.
v1.1에서는 UI 토글 인프라 구축, 마켓플레이스/재판매자 포털 강화, AI 채팅 고도화, 새 UI/UX 디자인을 목표로 한다.

## Milestones

- ✅ **v1.0 MVP** — 핵심 POS/ERP 기능 (운영 중)
- 🚧 **v1.1 개선** — Phases 1-7 (진행 중)

## Phases

### 🚧 v1.1 개선 (In Progress)

**Milestone Goal:** UI 토글 인프라 + 기능 확장 + 새 UI/UX 디자인

#### Phase 1: UI 토글 메커니즘
**Goal**: 사이드바 하단에 "UI/UX nuevo" 체크박스를 추가하여 admin/superadmin이 새 UI와 기존 UI를 전환할 수 있는 인프라 구축
**Depends on**: Nothing (v1.0 완료 상태에서 시작)
**Requirements**: TOGGLE-01
**Success Criteria** (what must be TRUE):
  1. users 테이블에 ui_mode 컬럼이 추가되고, 토글 상태가 DB에 저장됨
  2. admin/superadmin에게만 사이드바 하단에 체크박스가 표시됨
  3. 토글 ON/OFF에 따라 페이지별 조건부 렌더링 인프라가 동작함
  4. 새 UI가 미준비된 페이지는 토글 상태와 무관하게 기존 UI 유지
**Plans**: 2 plans

Plans:
- [x] 01-01-PLAN.md — DB ui_mode 컬럼 + 백엔드 API (PUT /users/ui-mode, /me 응답 포함)
- [x] 01-02-PLAN.md — 프론트엔드 UiModeContext + SidebarFooter 체크박스 + 조건부 렌더링 인프라

#### Phase 2: 마켓플레이스 & 재판매자
**Goal**: 마켓플레이스 기능 강화 및 재판매자 포털 완성
**Depends on**: Phase 1
**Requirements**: FEAT-01, FEAT-02
**Success Criteria** (what must be TRUE):
  1. 마켓플레이스에서 상품 검색/주문 가능
  2. 재판매자가 자체 포털에서 주문/재고 확인 가능
**Plans**: TBD

Plans:
- [ ] 02-01: 마켓플레이스 상품 목록/검색/주문 완성
- [ ] 02-02: 재판매자 포털 대시보드 및 주문 관리

#### Phase 3: AI 채팅 고도화
**Goal**: Knowledge base 기반 AI 채팅으로 업무 지원 자동화
**Depends on**: Phase 1
**Requirements**: FEAT-03
**Success Criteria** (what must be TRUE):
  1. 매장 데이터 기반 질의응답 가능
  2. 매출/재고 관련 인사이트 자동 제공
**Plans**: TBD

Plans:
- [ ] 03-01: Knowledge base 데이터 연동 및 임베딩
- [ ] 03-02: 채팅 UI 개선 및 컨텍스트 관리

#### Phase 4: 새 UI/UX 디자인
**Goal**: 토글 활성화 시 보이는 현대적 UI/UX 디자인 구현 (로그인, 대시보드, 전반적 UI)
**Depends on**: Phase 1
**Requirements**: UX-01, UX-02, UX-03
**Success Criteria** (what must be TRUE):
  1. 토글 ON 시 로그인 화면이 현대적 디자인으로 표시
  2. 토글 ON 시 대시보드에 주요 매출/재고 지표가 시각적으로 표시
  3. 토글 ON 시 전체 UI가 일관된 새 스타일 가이드 적용
  4. 토글 OFF 시 기존 UI가 그대로 유지됨
**Plans**: TBD

Plans:
- [ ] 04-01: 로그인/회원가입 새 디자인 (토글 ON 버전)
- [ ] 04-02: 대시보드 새 디자인 및 차트 추가 (토글 ON 버전)
- [ ] 04-03: 공통 컴포넌트 새 스타일 가이드 (토글 ON 버전)

#### Phase 5: 레거시 데이터 임포트
**Goal**: 기존 POS 시스템(todocodigos/codigos)의 상품 데이터를 JSON으로 추출하여 Ventago에 임포트하는 기능 완성
**Depends on**: Phase 1 (storeId 격리 인프라)
**Requirements**: FEAT-04
**Success Criteria** (what must be TRUE):
  1. 기존 DB에서 SQL로 JSON 추출 가능
  2. POST /import/migrate 엔드포인트로 매장별 격리된 임포트 성공
  3. 관리자 페이지에서 JSON 파일 업로드 + 지점 선택 + 미리보기 + 실행 가능
  4. 임포트 결과 리포트 (생성/건너뜀/에러 건수) 표시
**Plans**: 3 plans

Plans:
- [x] 05-01-PLAN.md — Product storeId 추가 + 임포트 백엔드 API (완료)
- [ ] 05-02-PLAN.md — 추출 스크립트 테스트 + API 통합 테스트
- [ ] 05-03-PLAN.md — 프론트엔드 임포트 UI (파일 업로드 + 미리보기 + 실행)

#### Phase 6: Reportajes (15개 보고서 시스템)
**Goal**: 기존 POS 시스템의 15개 보고서를 Ventago에 완전 구현. 기존 3개(Ventas, Items, StockRpt) 활용 + 12개 신규 구현
**Depends on**: Nothing (기존 reportes 페이지/API 존재, 기능 확장)
**Requirements**: FEAT-05
**Success Criteria** (what must be TRUE):
  1. 15개 보고서 모두 Reportajes 메뉴에서 접근 가능
  2. 모든 보고서에 기간별/지점별 필터링 동작
  3. 모든 보고서에서 Excel 내보내기 가능
  4. 기존 3개 보고서(Ventas, Items, StockRpt)가 새 구조에 통합됨
**Plans**: 7 plans

Plans:
- [x] 06-01-PLAN.md — Wave 1: 기존 데이터 활용 간단 보고서 (Vendedor, Gasto, Fallados, Corregido) + 보고서 허브 페이지
- [x] 06-02-PLAN.md — Wave 2: 매출 확장 보고서 (Breve Venta, Facturacion, Clientes Credito)
- [x] 06-03-PLAN.md — Wave 3: 재고/보류 보고서 (Ingreso Deposito, Movidos, Reservado)
- [x] 06-04-PLAN.md — Wave 4: 신규 기능 보고서 (Alertas, Cheque Estado)

#### Phase 7: Fábrica (생산 관리)
**Goal**: Fábrica 메뉴 하위의 생산 관리 전체 워크플로우 완성 (BOM, 작업지시, 자재 관리, 생산실적)
**Depends on**: Nothing (기존 production 모듈/API 존재, 기능 확장)
**Requirements**: FEAT-06
**Success Criteria** (what must be TRUE):
  1. BOM(자재명세서) CRUD 및 원가 계산이 동작함
  2. 작업지시 생성/진행/완료 워크플로우가 동작함
  3. 자재 입출고 및 재고 추적이 가능함
  4. 생산실적 조회 및 대시보드 표시
**Plans**: TBD

Plans:
- [ ] 07-01: BOM 관리 (자재명세서 CRUD + 원가 계산)
- [ ] 07-02: 작업지시 워크플로우 (생성/진행/완료)
- [ ] 07-03: 자재 관리 (입출고 + 재고 추적)
- [ ] 07-04: 생산실적 대시보드

#### Phase 8: Reportajes UX Redesign (Sidebar + Preview Shell)
**Goal**: Phase 6의 백엔드/데이터 위에 얹는 신규 UX 셸 — Pattern 2 (좌측 사이드바 + 우측 파라미터/미리보기) 구조로 16개 보고서에 통합 진입점 제공. UI 토글 ON 시에만 활성화되며, 기존 `/reportes` 경로와 병렬 운영.
**Depends on**: Phase 1 (UI 토글), Phase 6 Wave 1~3 (백엔드 API)
**Requirements**: UX-04
**Success Criteria** (what must be TRUE):
  1. `/reportes-v2` 진입 시 16개 보고서가 4개 카테고리(Ventas/Finanzas/Inventario/Clientes&Control)로 좌측 사이드바에 표시
  2. 사이드바 클릭 시 shallow routing으로 우측만 갱신 (full reload 없음)
  3. 검색창으로 보고서 필터링 가능
  4. Phase 6 기존 view 컴포넌트가 preview body에 embed되어 재사용됨
  5. UI 토글 OFF 시 기존 `/reportes` 경로가 영향받지 않음
  6. 사이드바 리렌더링 최적화 (React.memo/useMemo)
  7. Pool 낭비 없음 — registry는 정적 상수, 즐겨찾기/최근실행은 localStorage 우선
**Plans**: 7 plans

Plans:
- [x] 08-01-PLAN.md — Wave 1: Hook controlled-mode refactor (15 useXxxReport + xxxDefaultParams exports)
- [x] 08-02-PLAN.md — Wave 2: Body extraction pattern (15 XxxReportBody.tsx + thin wrappers, zero regression)
- [x] 08-03-PLAN.md — Wave 3: Shell MVP (registry 16, reportsV2Slice, ReportsShell/Sidebar/Topbar/Params/Preview, [[...slug]].tsx, 3 reports embedded)
- [x] 08-04-PLAN.md — Wave 4: Full embed (13 remaining reports + favorites/recents + Topbar wire)

#### Phase 11: Thermal Printing — VentaGO Print Agent (Electron 데스크탑 앱)
**Goal**: 판매 확정 시 내부 컨트롤 티켓 자동 출력, AFIP CAE 취득 성공 시 공식 영수증 출력. **HTML→PNG→ESC/POS 그래픽 파이프라인**으로 색상·볼드·2줄 줄바꿈이 표현되는 현대적 80mm 티켓 출력. 비개발자도 더블클릭으로 설치·설정 가능한 Electron 데스크탑 앱 (Windows 우선, macOS 지원).
**Depends on**: Phase 10 (AFIP 영수증은 Phase 10 CAE 취득 후), Phase 9 (branchId 기반 설정)
**Requirements**: PRINT-01
**Success Criteria** (what must be TRUE):
  1. 판매 확정 시 지점의 print-agent로 `print_invoice` 이벤트 자동 전송 (fire-and-forget)
  2. 그래픽 모드 컨트롤 티켓 — Subtotal(굵게)/+Recargo(파란색)/−Descuento(빨간색)/TOTAL(검정블록) 정상 인쇄
  3. 상품명 2줄 자동 줄바꿈 (긴 이름 clamp), 상품별 discount는 소계 구역에만 표시
  4. CAE 취득 성공 시 `print_fiscal` 이벤트 자동 전송 (CAE/Vto.CAE/QR URL 포함)
  5. 프린터 미연결 지점에서 출력 이벤트 전송 시 판매/발행 트랜잭션에 영향 없음
  6. 비개발자도 3단계 마법사로 5분 내 초기 설정 완료
  7. Windows NSIS `.exe` + macOS `.dmg` 빌드 성공
  8. 지점별 API Key 관리자 화면에서 확인/복사/재발급 가능
  9. 관리자 화면에서 print-agent 온라인/오프라인 상태 실시간 표시 (30초 폴링)
  10. 설치 가이드 UI (서버 URL + API Key 자동 채워진 코드블록) 제공
**Plans**: 4 plans (4 Waves)

Plans:
- [x] 11-01-PLAN.md — Wave 1: 그래픽 파이프라인 코어 (formatter.js + renderer-engine.js + print-pipeline.js + printer.js)
- [x] 11-02-PLAN.md — Wave 2: Electron 앱 스켈레톤 (main.js + preload.js + 설정 GUI + 3단계 셋업 마법사 + electron-store)
- [x] 11-03-PLAN.md — Wave 3: fiscal-formatter + printer-discovery (USB+네트워크) + WebSocket 루프 실구현
- [x] 11-04-PLAN.md — Wave 4: 백엔드 PrintService + DB(branch_printer_configs) + 프론트 설정 UI + electron-builder 패키징
- [x] 11-05-PLAN.md — Wave 5: GitHub Actions 크로스 빌드 (Mac→Win .exe / Mac→Mac .dmg) + 자동 릴리즈 + 프론트 다운로드 UI

#### Phase 10: Facturación Electrónica (AFIP)
**Goal**: AFIP 전자세금계산서 발행 기능을 Ventago NestJS 모듈로 통합. 기존 Java afip-connector의 IVA 판단/InvoiceType 결정 로직을 TypeScript로 포팅하고, 외부 릴레이 서비스(`invoice.coolsistema.com`)를 재사용. POS 판매 화면에서 원클릭 발행, PDF+QR 출력, 발행 이력 관리.
**Depends on**: Phase 9 (Store lifecycle_state로 발행 게이트 제어, Tiendas 상세에 Fiscal Config 탭 추가)
**Requirements**: TAX-01
**Success Criteria** (what must be TRUE):
  1. 매장별 `store_fiscal_configs`에 CUIT, punto de venta, relay_client_id 저장
  2. POS 판매 확정 시 "Emitir Factura" 버튼으로 AFIP CAE 발행 가능
  3. InvoiceType A/B/C/E/M 자동 결정 (resiva 기반 Java 로직 포팅)
  4. IVA 계산 (일반/면세/해외거래처) 정확 동작
  5. CAE 취득 후 `invoices` + `invoice_items` 테이블에 기록
  6. AFIP 규격 PDF + QR 생성 및 출력 에이전트 전달
  7. SUSPENDED/ARCHIVED 매장은 발행 차단 (Phase 9 lifecycle guard 활용)
  8. 릴레이 장애 시 graceful error (재시도 1회 + user-facing 에러 메시지)
  9. 발행 이력 화면 (캘린더 필터 + CAE/tipo/monto 컬럼)
  10. `AFIP_RELAY_BASE_URL`, `AFIP_RELAY_CLIENT_ID`, `AFIP_RELAY_CUIT`, `AFIP_RELAY_PROD` 환경변수로 외부화
**Plans**: 7 plans

Plans:
- [ ] 10-01-PLAN.md — DB 스키마 (store_fiscal_configs + invoices + invoice_items 3개 테이블)
- [ ] 10-02-PLAN.md — AFIP Relay 클라이언트 + AfipRelayService + FacturacionService (Java 로직 포팅)
- [ ] 10-03-PLAN.md — PDF/QR 생성 (Puppeteer + HTML 템플릿 + AFIP QR v1 JSON→base64url)
- [ ] 10-04-PLAN.md — POS 프론트 통합 (Emitir Factura 버튼 + 발행 이력 뷰 + Fiscal Config UI)

#### Phase 9: Store Lifecycle & Admin IA 통합
**Goal**: Admin 사이드바의 Tiendas/Registros 이중화 해소 + Store 레벨 상태 머신(TRIAL/ACTIVE/SUSPENDED/ARCHIVED/DELETED) 도입. 매장 생성 시 자동 30일 trial 부여, 만료 시 cron 자동 정지, superadmin 수동 승인/연장 지원.
**Depends on**: Nothing (기존 store 모듈 확장)
**Requirements**: ADMIN-01, BILLING-01
**Success Criteria** (what must be TRUE):
  1. 사이드바에서 "Registros" 메뉴가 제거되고 Tiendas 단일 진입점으로 통합됨
  2. Tiendas 화면에 KPI 4카드 + 상태 탭(Trial/Activas/Suspendidas/Archivadas/Papelera) 표시
  3. 매장 생성 시 자동으로 lifecycle_state='TRIAL', trial_ends_at=+30일 설정
  4. Trial 만료 + grace period 경과 시 cron이 배치 UPDATE로 SUSPENDED 전이 (pool 1 connection)
  5. superadmin이 수동으로 Activar/Suspender/Archivar/Restaurar/ExtendTrial 가능
  6. SUSPENDED/ARCHIVED 매장의 사용자가 로그인/API 호출 차단 (401 STORE_SUSPENDED)
  7. 상세 페이지 진입 시 사이드바 active 상태가 "Tiendas"에 유지됨 (점프 없음)
  8. 기존 `/admin/registros` 북마크가 `/admin/tiendas?tab=trial`로 리디렉트
  9. Trial 만료 7/3/1일 전 admin 이메일 자동 발송 (중복 방지)
  10. 모든 lifecycle 전이가 감사 로그에 기록됨 (lifecycle_reason 필드)
**Plans**: 7 plans

Plans:
- [ ] 09-01-PLAN.md — DB 마이그레이션 + 기존 데이터 백필 (lifecycle_state 외 5개 컬럼)
- [ ] 09-02-PLAN.md — 백엔드 상태 머신 + Lifecycle API + Cron 재작성 (배치 쿼리)
- [ ] 09-03-PLAN.md — 프론트엔드 Tiendas 통합 뷰 + KPI + 탭 + 상세 페이지 이관 + Registros 제거
- [ ] 09-04-PLAN.md — Session Guard 강화 + Trial 만료 알림 이메일 + 감사 로그

#### Phase 12: Reportajes Cockpit (통일 UI/UX + 보고서별 특화 시각화)
**Goal**: Phase 8의 보고서 셸 위에 단일 56px Topbar + KPI Strip + Cockpit Layout(카드 그리드/시계열/드로워) 패턴을 적용해 16개 보고서 전체를 통일하고, 사장이 한눈에 의사결정할 수 있는 시각화로 발전시킨다. Vendedor 보고서를 표준 사례로 먼저 구현하고 나머지가 같은 패턴을 복제한다.
**Depends on**: Phase 8 (셸/사이드바/registry/controlled hooks), Phase 6 (백엔드 데이터)
**Requirements**: UX-12-01 ~ UX-12-08, PERF-12
**Success Criteria** (what must be TRUE):
  1. 16개 보고서 모두 단일 56px Topbar에 제목·Sucursal·검색·날짜2개·액션이 한 줄로 표시 (별도 FilterBar 없음)
  2. 16개 보고서 모두 `<CockpitLayout>` 컴포넌트를 사용 (KPI Strip + Primary Area + Detail Area + Drawer)
  3. Vendedor 보고서가 `vendor-cockpit-mockup.html` 디자인과 픽셀 단위 일치 (카드 그리드 + 메달 + 게이지 + sparkline + 배지)
  4. registry entry에 `filterSchema`·`cockpitLayout` 필드 추가, 셸이 schema-driven으로 자동 렌더
  5. 보고서별 단일 통합 API 엔드포인트 (`/reports/{slug}-cockpit`) — KPI/랭킹/차트를 1회 호출로 응답
  6. PostgreSQL pool 사용량이 Phase 8 대비 동일하거나 낮음 (50명 동시 시뮬레이션 측정)
  7. raw SQL CTE + GROUP BY 사용으로 N+1 쿼리 0개
  8. 비교 모드(⚖) 토글로 카드 다중 선택 + 비교 차트
  9. Meta(목표) 입력 UI: 사장이 판매원/카테고리별 목표를 설정 가능 (`users.monthly_sales_target` 컬럼)
  10. 배지 시스템 (🔥 연속 1등 / ⚠ 할인 과다 / 💎 객단가 챔피언) 자동 적용
  11. 우측 드로워(380px)로 venta/transaction 단일 상세, 배경을 가리지 않음
  12. 마지막 Jenkins 빌드 로그 그린, 운영 배포 안전 절차 통과
**Plans**: 8 plans

Plans:
- [x] 12-01-PLAN.md — 셸 인프라 통일: 56px Topbar + filterSchema + CockpitLayout + Redux currentParams
- [x] 12-02-PLAN.md — Vendedor Cockpit (표준 사례): 카드 그리드 + KPI + 탭 + 드로워 + 통합 API
- [x] 12-03-PLAN.md — Ventas + Items: 시계열 + 상품 믹스 cockpit
- [x] 12-04-PLAN.md — Finanzas: Facturación + Gastos + Cheque Estado
- [x] 12-05-PLAN.md — Inventario: Stocks + Corregido + Movidos + Fallados + Ingreso (5개)
- [x] 12-06-PLAN.md — Clientes & Control: Clientes-Crédito + Breve Venta + Reservado + Alertas (4개)
- [x] 12-07-PLAN.md — Comparison Mode + Meta(목표) 입력 + 배지 룰 엔진
- [x] 12-08-PLAN.md — 백엔드 통합 API 검증 + 프론트 캐시 + Pool 사용량 측정 + 운영 배포

#### Phase 13: Nuevo Producto + Zebra Barcode Agent
**Goal**: Products → Nuevo Producto 흐름을 "category → codigo madre → 색상·사이즈 매트릭스 → codigos hijitos" 로 재설계하고, 각 자식 SKU(id_codigo)마다 Zebra 프린터로 Code128 바코드 라벨을 출력할 수 있는 독립 Zebra Agent (Electron 데스크탑 앱) 를 구축한다. Phase 11 Print Agent 아키텍처를 복제한다.
**Depends on**: Phase 1 (UI 토글), Phase 11 (Print Agent 아키텍처 재사용)
**Requirements**: PRODUCT-13, BARCODE-13
**Success Criteria** (what must be TRUE):
  1. Nuevo Producto 에서 category 선택 → `codigo madre` 자동 생성 미리보기
  2. 색상·사이즈 매트릭스 N×M 조합 한 번 클릭으로 자식 SKU 일괄 생성 (각자 고유 `sku` + `id_codigo`)
  3. `temporada`, `origen` 이 태그로 저장되어 필터·통계 집계 가능
  4. Zebra Agent 가 Windows `.exe` + macOS `.dmg` 로 빌드되어 비개발자 설치·셋업 가능
  5. 생성 직후 "Imprimir Etiquetas" 클릭 시 자식 수만큼 Zebra 라벨 출력 (Code128 + 상품명 + 색상·사이즈 + 가격)
  6. Print Agent 와 Zebra Agent 가 동일 매장에서 네임스페이스 충돌 없이 동시 동작
  7. Zebra Agent 오프라인 시에도 상품 생성 / 판매 / 재고 플로우 영향 없음 (fire-and-forget)
  8. 관리자 화면에서 Zebra Agent 온라인 상태 실시간 표시 + API Key 재발급 가능
  9. 바코드 스캐너로 라벨 스캔 시 `id_codigo` 가 `nueva-venta` 에서 해당 자식 SKU 로 매칭되어 카트 추가
**Plans**: 5 plans

Plans:
- [ ] 13-01-PLAN.md — DB 마이그레이션 (temporada/origen/id_codigo) + Product 모델 확장 + BranchPrinterConfig Zebra 지원
- [ ] 13-02-PLAN.md — 백엔드: codigo madre 자동 생성 + 매트릭스 벌크 variants API + POST /print/barcode
- [ ] 13-03-PLAN.md — 프론트: Nuevo Producto 매트릭스 UI + 태그 입력 + Generar variantes 흐름
- [ ] 13-04-PLAN.md — Zebra Agent 스켈레톤 (Electron + WebSocket + 셋업 마법사 + ZPL formatter + Zebra driver)
- [ ] 13-05-PLAN.md — 프론트 Imprimir Etiqueta + 관리자 Zebra 상태 UI + GitHub Actions 크로스 빌드 + E2E smoke

#### Phase 15: Materia Prima Control — 원자재 관리 시스템
**Goal:** 의류 소형 생산업자를 위한 원자재(Materia Prima) 입고·사용·잔고 관리 + 공급자 대금 관리 시스템. 카드형 대시보드 + 카테고리 필터(tela/boton/cierre/hilo/accesorio + 커스텀) + 간단 장부형 대금 관리. 사이드바에 독립 앱 메뉴로 추가, 허가된 사용자만 접근 가능.
**Depends on:** Phase 14 (Permisos Control), 기존 production 모듈 (mes_materials)
**Requirements**: MPRIMA-01 ~ MPRIMA-07
**Success Criteria** (what must be TRUE):
  1. 사이드바에 "Materia Prima" 앱 그룹 표시 (권한 있는 사용자만)
  2. Dashboard에서 KPI(총 원자재, 재고부족, 재고총액, 미지급잔액) 한눈에 파악
  3. 원자재 등록 시 카테고리(기본 5종 + 커스텀) 선택 가능
  4. 원단(tela)은 색상·원산지·품질 추가 속성 관리
  5. 입고 시 공급자 연결 + 대금 처리(외상/즉시결제/부분결제) 선택
  6. 출고 시 작업지시(WorkOrder) 또는 참조번호 연결
  7. 공급자별 미지급 잔액 + 결제 이력 조회
  8. 최소재고 이하 시 알림 배지 표시
  9. BOM과 연동하여 제품별 원자재 소요량 기반 원가 계산
  10. 허가된 사용자만 접근 가능 (Phase 14 권한 시스템 활용)
**Plans**: 7 plans

Plans:
- [x] 15-01-PLAN.md — DB 스키마 + 백엔드 모델 + 시더 (App/Module/Function + 카테고리 seed)
- [x] 15-02-PLAN.md — 백엔드 서비스 + API 엔드포인트 (CRUD, 입출고, 대금, 대시보드 통계, 알림)
- [x] 15-03-PLAN.md — 프론트엔드 Dashboard + Inventario 화면
- [x] 15-04-PLAN.md — 프론트엔드 Proveedores + Movimientos + Pagos 화면
- [x] 15-05-PLAN.md — UI 리팩토링: 공유 컴포넌트 추출 (KpiCard, StockBar, MaterialCard, CategoryChips) + Inventario 리디자인
- [x] 15-06-PLAN.md — UI 리팩토링: Dashboard 2칸 그리드 + CSS 바 차트 (카테고리 분포, 채무 요약)
- [x] 15-07-PLAN.md — UI 리팩토링: Proveedores + Movimientos + Pagos 목업 스타일 적용 + 입출고 모달 개선

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. UI 토글 메커니즘 | v1.1 | 2/2 | Complete | 2026-03-31 |
| 2. 마켓플레이스 & 재판매자 | v1.1 | 0/2 | Not started | - |
| 3. AI 채팅 고도화 | v1.1 | 0/2 | Not started | - |
| 4. 새 UI/UX 디자인 | v1.1 | 0/3 | Not started | - |
| 5. 레거시 데이터 임포트 | v1.1 | 1/3 | In Progress | - |
| 6. Reportajes | v1.1 | 4/4 | Complete | 2026-04-03 |
| 7. Fábrica | v1.1 | 0/4 | Not started | - |
| 8. Reportajes UX Redesign | v1.1 | 4/4 | Complete | 2026-04-05 |
| 9. Store Lifecycle & Admin IA | v1.1 | 0/4 | Not started | - |
| 10. Facturación Electrónica (AFIP) | v1.1 | 0/4 | Not started | - |
| 11. Thermal Printing — Electron 앱 | v1.1 | 5/5 | Complete | 2026-04-07 |
| 12. Reportajes Cockpit | v1.1 | 6/8 | Complete    | 2026-04-13 |
| 13. Nuevo Producto + Zebra Barcode Agent | v1.1 | 0/5 | Not started | - |
| 14. Permisos Control | v1.1 | 4/4 | Complete    | 2026-04-10 |
| 15. Materia Prima Control | v1.1 | 3/3 | Complete   | 2026-04-13 |
| 16. Control de Talleres (Wave 1-4) | v1.1 | 8/8 | Complete   | 2026-04-21 |
| 16. Control de Talleres (Wave 5-10 Zedonk CMT) | v1.1 | 1/6 | In Progress | -          |
| 17. Portal de Talleres | v1.1 | 5/5 | Complete    | 2026-04-13 |
| 18. AG Grid Migration | v1.1 | 1/1 | Complete    | 2026-04-13 |
| 23. Multi-TZ Report Correctness | v1.1 | 0/5 | Not started | - |

#### Phase 14: Permisos Control — 역할별 권한 관리 UI
**Goal:** Full-stack 역할별/유저별 CRUD 권한 관리 시스템. 기존 Apps→Modules→Functions 구조에 CRUD Action(create/read/update/delete)을 추가하여 정교한 권한 관리 실현. 백엔드 FunctionGuard + 프론트엔드 CASL granular enforcement + 관리 UI 포함.
**Depends on:** Nothing (기존 auth/role/function 모듈 확장)
**Requirements**: PERM-01, PERM-02, PERM-03, PERM-04, PERM-05, PERM-06, PERM-07
**Success Criteria** (what must be TRUE):
  1. role_function_actions / user_function_actions 테이블이 존재하고 기존 데이터 backfill 완료
  2. /me 응답에 permissions 맵 (functionSlug → CRUD booleans) 포함
  3. @FunctionGuard('slug', 'action') 데코레이터로 백엔드 엔드포인트 보호
  4. CASL buildAbilityFor가 permissions 맵 기반으로 granular 권한 체크 (manage:all 아님)
  5. RolePermissionsDrawer에서 Function별 C/R/U/D 칩 편집 가능
  6. UserPermissionsDrawer에서 role 기본값 대비 override 표시 (amber 보더) + 리셋 기능
  7. 권한 없는 사이드바 메뉴 숨김 + URL 직접 접근 시 401 페이지 표시
  8. superadmin manage:all 유지, admin은 store 범위, gerente는 branch 범위 제한
**Plans**: 7 plans

Plans:
- [x] 14-01-PLAN.md — DB schema: RoleFunctionAction + UserFunctionAction 모델 + 기존 데이터 backfill
- [x] 14-02-PLAN.md — 백엔드: /me permissions 맵 + FunctionGuard + action CRUD API + scope enforcement
- [x] 14-03-PLAN.md — 프론트: CASL 리팩토링 + CrudActionRow + RolePermissionsDrawer CRUD 확장
- [x] 14-04-PLAN.md — 프론트: UserPermissionsDrawer override + 401 페이지 + 네비게이션 권한 숨김

### Phase 16: Control de Talleres — CMT 전문 기능 확장 (Zedonk 스타일)

**Goal:** Wave 1-4 (UI 통합 + Dashboard API + Kanban 시각화 + 단가 매트릭스) 위에 Zedonk 의류 브랜드 워크플로우 6 Wave 추가. 5 탭 구조 (Overview / Cut Ticket / WIP / Cost Sheet / Kanban) 로 재편, navy(#1a1a2e) + gold(#f5a623) 테마 통일, CMT 전문 기능(QC/rework/auto-liquidación) + 의류 브랜드 핵심(Cut Ticket + Cost Sheet) 추가.
**Requirements**: TALLERES-01~09 (Wave 1-4), TALLERES-10~17 (Wave 5-10 — 신규 Zedonk CMT)
**Depends on:** Phase 15, Phase 17 (FCM), Phase 14 (CASL — talleres_qc_admin/settlement_confirm/cut_ticket_edit/cost_sheet_edit)
**Plans:** 9/10 plans complete (Wave 1-4 완료 2026-04-13, Wave 5 완료 2026-04-20, Wave 6 완료 2026-04-21 로컬+운영, Wave 7 완료 2026-04-21 로컬, Wave 9 완료 2026-04-21 로컬, Wave 10 완료 2026-04-22 로컬, Wave 8 계획 예정)

Extension 근거:
- `.planning/phases/16-control-de-talleres/16-EXTENSION.md` (gap 분석 + 10 Wave 설계)
- `docs/taller-control-roadmap.md` (Zedonk/AIMS360/ApparelMagic 벤치마크)
- `docs/zedonk-style-taller-mockup.html` (**canonical UI reference** — 5 탭 인터랙티브 목업)

Plans:
- [x] 16-01-PLAN.md — Wave 1: Backend Dashboard 통합 API + Tab Shell + Dashboard Tab + 공유 컴포넌트 (완료 2026-04-13)
- [x] 16-02-PLAN.md — Wave 2: Pipeline Tab (Kanban + EtapaFlow 원형 노드, 읽기 전용) (완료 2026-04-13)
- [x] 16-03-PLAN.md — Wave 3: Talleres Tab (확장 행) + Lotes Tab (420px 드로어) + Envios Tab (완료 2026-04-13)
- [x] 16-04-PLAN.md — Wave 4: Liquidaciones Tab (정산 KPI + 테이블) + Etapas Tab (단가 매트릭스) (완료 2026-04-13)
- [x] 16-05-PLAN.md — Wave 5: Kanban Semáforo + Priority (Zedonk 테마 최초 적용, healthStatus 3-level + priority 드래그 + MemoryCache 30s) — 완료 2026-04-20 (api-ventago 097c3f8 / ventago-app 0eca278,108908e)
- [x] 16-06-PLAN.md — Wave 6: QC 구조화 + Rework 자동화 (`talleres_qc_items`/`_defect_codes` + 사진 업로드 + REWORK→child envío 자동생성 + Vendor Scorecard) — 7~10일
- [x] 16-07-PLAN.md — Wave 7: Tarifa Historización + Auto-liquidación (VendorEtapa effectiveFrom/To + generateForPeriod + DRAFT→CONFIRMED 불변 + PDF) — 7~10일
- [ ] 16-08-PLAN.md — Wave 8: Alertas + Overview Dashboard (Zedonk 테마) + Polish (cron 08:00 LATE 알림 + 즉시 조치 테이블 + 4 차트 + Excel + 인덱스 + 매뉴얼 es) — 5~7일
- [x] **16-09-PLAN.md — Wave 9 (신규): Cut Ticket System** (`talleres_lotes` 확장: cut_ticket_number/size_color_matrix/bom_snapshot/routing_path + PDF 출력 + 매트릭스 에디터 + BOM 테이블 + Routing Flow) — 8~12일
- [x] **16-10-PLAN.md — Wave 10 (신규): Cost Sheet** (`style_cost_sheets` 신규 테이블 + 자재+CMT+간접비 자동 계산 + 마진 시뮬레이션 MarginCard navy gradient + 목표 마진 경고) — 완료 2026-04-22 로컬 (api-ventago cefc12f / ventago-app 48a5e72,cdf071c)

### Phase 17: Portal de Talleres - 외주업자용 보조 프로그램 (aviso/알림, 진행현황 확인, 수령 확인)

**Goal:** Flutter 독립 모바일 앱으로 외주업체(vendor)가 자기에게 발송된 물건의 진행현황 확인, 수령 완료 마킹, 알림 수신, 정산 이력 확인. 백엔드에 vendor 전용 인증 + portal API 추가.
**Requirements**: VP-01, VP-02, VP-03, VP-04, VP-05, VP-06
**Depends on:** Phase 16
**Plans:** 5/5 plans complete

Plans:
- [x] 17-01-PLAN.md — Backend: DB migration (pin_hash + vendor_notifications) + VendorPortalModule + vendor JWT auth
- [x] 17-02-PLAN.md — Backend: Envios/Recepciones/Settlements/Notifications API + DUE_SOON cron
- [x] 17-03-PLAN.md — Flutter: Project creation + core infra (Dio, Riverpod, secure storage) + auth flow + store tabs
- [x] 17-04-PLAN.md — Flutter: Envios list/detail + Recepcion creation dialog + home navigation
- [x] 17-05-PLAN.md — Flutter: Notifications (with badge) + Settlements (with date filter) + home integration

### Phase 18: AG Grid Migration - MUI DataGrid를 AG Grid Community로 교체 (컬럼 리사이즈/고정)

**Goal:** AG Grid Community 마이그레이션 완료. FullTable.tsx + columns.tsx + 로케일 + adaptColumns 어댑터는 이미 전환 완료. 남은 작업: grid-types.ts 타입 심을 AG Grid 네이티브로 교체하고 @mui/x-data-grid 패키지 완전 제거.
**Depends on:** Nothing (독립적으로 진행 가능)
**Requirements**: GRID-01
**Success Criteria** (what must be TRUE):
  1. ag-grid-community + ag-grid-react 패키지 설치, @mui/x-data-grid 제거
  2. FullTable 래퍼가 AG Grid 기반으로 동작 (기존 props 인터페이스 유지)
  3. 61개 FullTable 사용 화면이 회귀 없이 동작
  4. 4개 직접 DataGrid 사용 파일(GlobalClientes, CargaMasiva, CajaFuerte, ClienteVista)이 AG Grid로 전환
  5. 51개 DataConfig 파일의 GridColDef → AG Grid ColDef 타입 전환
  6. columns.tsx 공유 헬퍼(23+개)가 AG Grid cellRenderer 패턴으로 동작
  7. 사용자가 모든 테이블에서 컬럼 리사이즈(드래그) 가능
  8. 스페인어 로컬라이제이션 유지
  9. 서버사이드 페이지네이션 + 클라이언트사이드 정렬 유지
  10. 체크박스 선택, 행 클릭, 로딩 상태 기존대로 동작
**Plans**: 1 plan

Plans:
- [x] 18-01-PLAN.md — grid-types.ts AG Grid 네이티브 타입 교체 + @mui/x-data-grid 패키지 제거 + 빌드 검증

### Phase 19: Performance 300ms — 사이드바 메뉴 클릭 ≤ 300ms 콘텐츠 표시

**Goal:** 모든 사이드바 메뉴 클릭 후 콘텐츠가 300ms 이내에 표시되도록 프론트엔드/백엔드/인프라 전반을 최적화한다. 현재 병목 요소를 측정·분석하고, 서버 사양 권장안과 함께 체계적으로 개선한다.

**Depends on:** Phase 1 (UI 토글), Phase 12 (Cockpit 보고서)
**Requirements**: PERF-19-01, PERF-19-02, PERF-19-03, PERF-19-04, PERF-19-05, PERF-19-06

**UI hint:** no

**Success Criteria** (what must be TRUE):
  1. Lighthouse Performance 점수 ≥ 80 (모바일 기준)
  2. 모든 사이드바 메뉴 클릭 → 콘텐츠 렌더 완료까지 ≤ 300ms (개발 환경 기준, 프로덕션은 CDN/서버 사양에 따라 ± 허용)
  3. Next.js 번들 분석 완료 — 페이지별 JS 크기 ≤ 200KB (gzip)
  4. 코드 스플리팅 적용 — 사이드바 전환 시 필요한 청크만 로드
  5. API 응답 시간: 목록 API ≤ 100ms, 대시보드/통계 API ≤ 200ms (PostgreSQL 쿼리 포함)
  6. PostgreSQL 쿼리 최적화 — slow query (>100ms) 0건
  7. 프론트엔드 불필요 리렌더링 제거 — React DevTools Profiler 기준 메뉴 전환 시 리렌더 컴포넌트 ≤ 5개
  8. 서버 사양 권장안 문서화 (CPU, RAM, 디스크 I/O, PostgreSQL 튜닝 파라미터)
  9. Docker 이미지 크기 최적화 (multi-stage build, .dockerignore 정리)
  10. Jenkins 빌드 그린, 운영 배포 안전
**Plans**: 6 plans

Plans:
- [ ] 19-01-PLAN.md — 프론트엔드 번들 마무리: 나머지 72개 페이지 코드 스플리팅 + 미사용 라이브러리 제거 + AG Grid 1회 초기화
- [ ] 19-02-PLAN.md — 프론트엔드 렌더링 최적화: Context useMemo + hover prefetch + UserLayout 검증
- [ ] 19-03-PLAN.md — API 호출 최적화: Promise.all 병렬화 + SWR 훅 실적용
- [ ] 19-04-PLAN.md — 백엔드 캐시 + DB 최적화: 인메모리 캐시 서비스 + 대시보드 쿼리 통합 + PostgreSQL 튜닝
- [ ] 19-05-PLAN.md — 인프라 & Docker: 멀티스테이지 빌드 + 서버 사양 권장안
- [ ] 19-06-PLAN.md — 검증 & 문서화: 전체 재측정 + Lighthouse ≥80 + CLAUDE.md 성능 섹션

### Phase 20: Nueva Venta variation/codigo madre 디버깅 - 콘솔·서버·print-agent 로그 추가 및 suspender/restore 오류 추적

**Goal:** [To be planned]
**Requirements**: TBD
**Depends on:** Phase 19
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd-plan-phase 20 to break down)

### Phase 21: Store Baseline Invariant System — store 단위 필수 설정(payment_methods, sellers, discounts 등)의 자동 생성·자가 치료·slug 기반 식별 시스템

**Goal:** [To be planned]
**Requirements**: TBD
**Depends on:** Phase 20
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd-plan-phase 21 to break down)

### Phase 22: Suspender Restore Fidelity & Variant Stock Integrity — suspender hold/release + restore UX 정합성, nullifySale 의 variant 재고 복원, branchId 기반 multi-branch 지원 완성

**Goal:** [To be planned]
**Requirements**: TBD
**Depends on:** Phase 21
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd-plan-phase 22 to break down)

### Phase 23: Multi-TZ Report Correctness — 모든 보고서/집계가 매장 timezone 기준으로 날짜 경계를 해석하도록 전환

**Goal:** 모든 cockpit/보고서 쿼리에서 Sequelize 세션 TZ 의존을 제거하고 매장 `stores.timezone` 기준으로 날짜 범위를 해석한다. UTC 세션 환경에서도 저녁 판매(매장 로컬 22:00 등)가 누락되지 않으며, 여러 TZ 매장이 동시에 운영되어도 각 매장 로컬 날짜로 집계된다. 로컬 임시 패치(`DATABASE_TZ='-03:00'`)를 걷어내고 `AT TIME ZONE :storeTz` 패턴으로 표준화.

**Requirements**: REPORT-TZ-01, REPORT-TZ-02, REPORT-TZ-03, REPORT-TZ-04, REPORT-TZ-05
**Depends on:** Phase 22 (또는 독립, v1.1 개선 범위)

**Success Criteria** (what must be TRUE):
  1. `DATABASE_TZ='+00:00'` 로 백엔드 실행해도 ventas/vendors/mix/gasto/facturacion 보고서가 매장 로컬 날짜 기준 올바른 결과를 반환
  2. `stores.timezone` backfill 완료, 누락 매장 0건 (필요 시 기본값 'America/Bogota')
  3. 공통 헬퍼 `tzDateBounds(storeTz)` 도입, 주요 cockpit 서비스 10+개가 이를 사용
  4. `CockpitFilters` 가 `storeTz` 파라미터를 포함하고 `resolveStoreTz(storeId)` 메모리 캐시로 storeId당 1회만 조회
  5. 멀티 TZ 매장 시뮬레이션(Argentina+Mexico) 통합 테스트 통과 — 같은 `startDate/endDate` 요청에 대해 각 매장 로컬 기준으로 다른 UTC 범위 적용
  6. `storeId=null` (전사 집계) 호출 정책 수립: 요청자 user.store.timezone 우선 fallback
  7. 회귀 테스트 5개 이상 — UTC 세션 × 매장 TZ 조합, 저녁 판매 경계 포함 여부 검증
  8. 임시 패치 `database.module.ts` 의 `timezone: '-03:00'` 제거 후에도 전 기능 정상
  9. `Branch.timezone` 컬럼 추가(migration) + fallback chain: branch → store → default
  10. 디버깅 로그(`[SalesCockpit-MIX-DEBUG]`, `[DEBUG-FE]`, `[DEBUG-MIX][CTRL]` 등) 정리

**Plans**: 5 plans

Plans:
- [ ] 23-01-PLAN.md — tz-helpers 도입 + CockpitFilters 확장 + storeTz 메모리 캐시 + DB backfill 스크립트
- [ ] 23-02-PLAN.md — reportsSalesCockpit + salesDimensions 전환 + 기존 디버그 로그 정리
- [ ] 23-03-PLAN.md — 나머지 cockpit 서비스 8개 일괄 전환 (Gasto/Facturacion/BreveVenta/ChequeEstado/Fallados/Movidos/Reservado/Ingreso)
- [ ] 23-04-PLAN.md — Branch.timezone 컬럼 migration + fallback chain + 전사 집계 정책 구현
- [ ] 23-05-PLAN.md — 통합 테스트 (UTC 세션 × 멀티 매장) + `DATABASE_TZ` 임시 패치 제거 + 문서화

### Phase 24: Revendedor Marketplace — 중개형(Commission-based) 마켓플레이스 + Flutter 앱

**Goal:** 100개+ Tienda의 상품을 Revendedor가 **주문 중개(커미션) 방식**으로 영업·판매하는 마켓플레이스 구축. Revendedor는 재고 리스크 없이 통합 카탈로그에서 상품을 검색해 **최소가 하한선 + 자유 마진** 규칙으로 견적을 만들고 고객에게 제시한다. Tienda가 주문을 확정·출고하며, 플랫폼은 수수료를 차감한 뒤 주 1회 정산한다. 도매가·권장소비자가·브랜드를 모두 공개하는 공동 브랜딩 모델. 신규 `reseller` 스키마 + Revendedor 전용 Flutter 앱 + Ventago 관리자 UI 통합.

**Depends on:** Phase 9 (Store lifecycle — ACTIVE 매장만 노출), Phase 14 (CASL permissions — revendedor_admin slug), 기존 `revendedor/` + `marketplace/` 모듈
**Requirements**: RESELLER-01, RESELLER-02, RESELLER-03, RESELLER-04, RESELLER-05, RESELLER-06, RESELLER-07

**UI hint:** yes (Flutter 앱 + 관리자 UI)

**Success Criteria** (what must be TRUE):
  1. `reseller` 스키마에 7개 테이블(`resellers`, `tienda_sharing_policy`, `reseller_tienda_link`, `quotes`, `quote_items`, `orders`, `order_status_log`) 생성되고 CHECK 제약 + 인덱스 적용
  2. 재판매자 가입(CUIT/RUT/RFC + 서류 업로드) + 관리자 승인 워크플로우 동작
  3. Tienda별 공유 정책 편집(최소 마진율/수수료율/재고 홀드 시간/카테고리/제외 상품) 가능
  4. `reseller.catalog_unified` Materialized View + 5분 주기 CONCURRENTLY refresh 동작
  5. 견적 생성 시 30분 재고 홀드, 만료 스캔 cron(1분 주기)으로 자동 expired 처리
  6. 주문 상태머신(pending_tienda → confirmed → preparing → shipped → delivered → completed) 전 구간 동작 + 상태 이력 로그 기록
  7. 최소가 하한선 검증 서버사이드 강제 — `final_price < wholesale_price * (1 + min_markup_pct/100)`면 400 반환
  8. Revendedor Flutter 앱(Android/iOS)에서 로그인/카탈로그/상품 상세/마진 계산기/견적/주문/정산 내역 확인 가능
  9. 주 1회(금요일) 정산 배치 — 수수료 계산 idempotent, `settled_at IS NULL` 조건으로 중복 지급 방지
  10. Ventago 관리자 UI(revendedor_admin)에서 Revendedor 승인, 공유 정책 편집, 주문 모니터링, 정산 대시보드 접근 가능 (Phase 14 CASL로 권한 보호)
  11. SUSPENDED/ARCHIVED 매장은 MV에서 자동 제외(Phase 9 lifecycle 연동)
  12. Pool 낭비 없음 — Sequelize 전역 pool 재사용, 모든 raw SQL 경로에서 connection release 보장
  13. `reseller.canonical_categories` 테이블 + `public.categories.canonical_category_id` FK 추가 — 100+ 매장의 로컬 카테고리를 전역 정규화 레이어에 매핑
  14. 자동 매핑 배치 (이름 exact match) + superadmin 수동 매핑 UI + 미매핑 카테고리 누적 시 제안 대시보드 동작
  15. `reseller.catalog_unified` MV 에 `canonical_category_id` 컬럼 포함 → Revendedor Flutter 앱에서 canonical_category_id 하나로 전 매장 카테고리 필터링 가능
  16. 초기 canonical seed 50개 기본 카테고리 (Indumentaria/Calzado/Accesorio 등) 생성

**Plans**: 5 plans (5 Waves)

Plans:
- [ ] 24-01-PLAN.md — Wave 1: 기반 구축 (`reseller` 스키마 + 3개 테이블 마이그레이션 + Reseller 가입/검증 API + 관리자 승인 화면)
- [ ] 24-02-PLAN.md — Wave 2: 통합 카탈로그 + Canonical Category Taxonomy (`canonical_categories` 테이블 + `categories.canonical_category_id` FK + 자동/수동 매핑 UI + Materialized View(canonical_category_id 포함) + refresh cron + 카테고리/검색 API + Flutter 브라우저/마진 계산기)
- [ ] 24-03-PLAN.md — Wave 3: 주문 플로우 (`quotes` / `orders` 테이블 + 견적 30분 홀드 + 상태머신 + Tienda POS 주문 관리 탭)
- [ ] 24-04-PLAN.md — Wave 4: 정산 (수수료 계산 배치 + 주 1회 cron + Revendedor/Tienda 정산 화면)
- [ ] 24-05-PLAN.md — Wave 5: 고도화 (분쟁 워크플로우 + FCM 알림 + 실적 리포트 + Tienda별 Revendedor 성과 대시보드)
