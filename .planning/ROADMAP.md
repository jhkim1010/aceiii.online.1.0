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
| 16. Control de Talleres (Wave 1-4) | v1.1 | 10/10 | Complete   | 2026-04-23 |
| 16. Control de Talleres (Wave 5-10 Zedonk CMT) | v1.1 | 1/6 | In Progress | -          |
| 17. Portal de Talleres | v1.1 | 5/5 | Complete    | 2026-04-13 |
| 18. AG Grid Migration | v1.1 | 1/1 | Complete    | 2026-04-13 |
| 23. Multi-TZ Report Correctness | v1.1 | 0/5 | Not started | - |
| 37. Mobile Sales Shell (Vendedor + Revendedor Flutter) | v1.1 | 0/5 | Not started | - |
| 39. Modo Restaurante — POS por mesas | v1.1 | 7/7 | Complete   | 2026-06-14 |

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
**Plans:** 10/10 plans complete

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
- [x] 16-08-PLAN.md — Wave 8: Alertas + Overview Dashboard (Zedonk 테마) + Polish (cron 08:00 LATE 알림 + 즉시 조치 테이블 + 4 차트 + Excel + 인덱스 + 매뉴얼 es) — 5~7일
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

### Phase 25: Clientes globales compartidos entre tiendas (historial aislado) + Importación masiva CSV/Excel en ClienteView

**Goal:** 같은 그룹/소유자(owner) 하에 등록된 여러 tienda 가 고객 **기본정보**(nombre, DNI/CUIT, email, teléfono, dirección, provincia, localidad, fecha_nacimiento, notas)를 공유. **단, 공유 대상은 DNI 또는 CUIT 가 있는 클라이언트만** — DNI/CUIT 없이 POS 에서 즉석 생성된 익명/일회성 고객("Consumidor Final" 유형)은 로컬 storeId 스코프로만 존재. **구입 이력**(sales, sale_items, pagos, discounts, preferencias)은 DNI/CUIT 유무와 관계없이 언제나 storeId 기준으로 절대 교차 조회 불가. ClienteView 에 "Importación masiva" 메뉴 추가하여 CSV/Excel 업로드 → 컬럼 매핑 → DNI/email 중복 검증 → 미리보기 → 트랜잭션 커밋 → 실패행 리포트 플로우 제공.

**Requirements:**
1. 클라이언트 이원화 구조:
   - **Global clients (공유 풀)**: DNI 또는 CUIT 가 있는 레코드만. owner 그룹 내 tienda 전체에서 조회 가능
   - **Local clients (매장 전용)**: DNI/CUIT 미입력 레코드. 해당 storeId 스코프 외 노출 금지
   - 구현: `global_clients` 테이블 + `client_store_links(globalClientId, storeId, localAlias?)` 또는 `clients.isGlobal` 플래그 + `ownerGroupId` 컬럼
2. `storeOwnerId` (또는 `ownerGroupId`) 기반 공유 범위 정의 — 같은 owner 의 tiendas 끼리만 공유
3. 공유되는 필드(global scope): nombre, DNI/CUIT, email, teléfono, dirección, provincia, localidad, fecha_nacimiento, notas 등 **기본정보만**
4. **절대 공유 금지** 필드/관계: sales, sale_items, pagos, discounts, saldos_credito, preferencias_compra, ltv, categorias_compradas — 항상 storeId 스코프
5. **Promotion 규칙**: 로컬 클라이언트에 나중에 DNI/CUIT 가 추가되면 자동으로 글로벌 풀로 승격. 승격 시 동일 DNI/CUIT 로 다른 tienda 에 기존 글로벌 레코드가 있으면 **merge 제안 UI** — 사용자 확인 후 병합 (local 레코드 id → global id 재매핑, sales FK 갱신, merge audit 기록)
6. **Demotion 금지**: 글로벌 레코드에서 DNI/CUIT 를 제거할 수 없음 (validation block). 필요 시 별도 로컬 레코드로 신규 생성 후 이관
7. 기존 sales/sale_items 의 clientId FK 는 (global 또는 local) clients.id 를 참조 — 단 조회 시 언제나 `WHERE sales.storeId = :callerStoreId` 강제
8. 백엔드 모든 클라이언트 관련 엔드포인트(`/clients/*`, `/sales/*`, `/reports/*`)에 client-scope guard 적용 — 다른 매장 historial 접근 시도 시 403. `/clients/search` 는 글로벌 풀 조회 가능하되 해당 cliente 의 historial 은 항상 빈 값 또는 호출 tienda 분만 반환
9. DNI/CUIT 또는 email 로 기존 글로벌 클라이언트 조회 API — 중복 등록 방지, 기존 레코드에 "현재 tienda 연결" 만 추가 (새 global row 생성 X)
10. ClienteView 에 "Importación masiva" 버튼 + 모달: CSV/Excel 업로드(xlsx/csv, 최대 10MB)
11. **Import 시 DNI/CUIT 필수 행만 글로벌 풀에 업서트** — DNI/CUIT 가 빈 행은 로컬 클라이언트로 저장하거나 사용자 설정에 따라 skip (import 옵션 토글)
12. 컬럼 매핑 UI — 업로드 파일의 컬럼명을 DB 필드에 매핑 (자동 감지 + 수동 재지정)
13. Preview 테이블 — 첫 N행 파싱 결과 + 중복/오류 하이라이트 (DNI 중복/CUIT 체크섬 오류/이메일 형식 오류/provincia 미매칭/DNI 없음 등), 각 행마다 **"→ 글로벌 / 로컬 / skip"** 대상 분류 표시
14. 검증 규칙: DNI 형식(AR 7~8자리 숫자), CUIT 체크섬(AR 11자리 mod 11), email regex, teléfono 숫자만, provincia 는 existing provinces 테이블에서 lookup
15. 기존 글로벌 클라이언트 발견 시 동작 옵션: **skip** / **update basic info** / **link to current tienda only** 사용자 선택 (전역 기본 + 행별 오버라이드)
16. 트랜잭션 단위 커밋 — 전체 성공 또는 부분 실패(행별 상태 리포트)
17. 실패행 리포트 다운로드 — CSV 로 실패 이유 포함 재내보내기 가능
18. Audit log — 누가, 언제, 어떤 파일로, 몇 건 import / update / skip / promote / merge 했는지 기록 (`client_imports`, `client_merges` 테이블)
19. 권한 — superadmin + tienda admin 만 import 가능 (CASL `manage-clientes-import`), vendedor 는 불가
20. 다국어 — 에러 메시지/UI 라벨 es/ko 모두 번역
21. 성능 — 10,000 행 import 시 < 30초 (bulk insert + 중복 조회는 DNI/CUIT UNIQUE INDEX 활용, `global_clients(ownerGroupId, dni)` / `(ownerGroupId, cuit)` partial index)
22. **Data integrity**: `global_clients.dni` 또는 `global_clients.cuit` 중 최소 하나는 NOT NULL 강제. UNIQUE 제약은 `ownerGroupId + dni`, `ownerGroupId + cuit` 기준 — 다른 owner 그룹 간 동일 DNI 허용(완전 격리된 고객 풀)

**Depends on:** Phase 14 (Permisos Control — CASL 권한), Phase 21 (Store Baseline Invariant System — storeOwnerId 구조)

**Plans:** 18/18 plans executed

Plans:
- [x] 25-01-PLAN.md — Wave 1: stores.ownerGroupId + global_clients.ownerGroupId schema + partial UNIQUE + drop legacy idx_name_phone (D1-01, D1-05, D3-01, D3-02)
- [x] 25-02-PLAN.md — Wave 1: sales.storeClientId dual-FK (D2-01)
- [x] 25-03-PLAN.md — Wave 1: Legacy clients → global_clients + store_clients migration + sales remap (D2-02, D2-03)
- [x] 25-04-PLAN.md — Wave 1: Audit tables (client_imports, client_merges, client_access_audits) + Sequelize models (D3-04, D4-06)
- [x] 25-05-PLAN.md — Wave 2: OwnerScopeGuard + @OwnerScope decorator + OwnerScopeService + /me ownerGroupId + StoreService auto-allocate (D3-03, D3-04)
- [x] 25-06-PLAN.md — Wave 2: Seed manage-clientes-import + @OwnerScope on /global-clients/* + service-level ownerGroupId filter + demotion block (D1-06, REQ-25-19)
- [x] 25-07-PLAN.md — Wave 3: POST /clients/:id/promote + conflict detection (D1-03)
- [x] 25-08-PLAN.md — Wave 3: POST /clients/merge + optimistic lock + field whitelist + audit (D1-04)
- [x] 25-09-PLAN.md — Wave 4 (TDD): cuit.validator.ts + dni.validator.ts backend (D1-02, REQ-25-14)
- [x] 25-10-PLAN.md — Wave 4: POST /clients/import — ClientImportService chunked transaction + CASL gate + audit (REQ-25-10..18, REQ-25-21)
- [x] 25-11-PLAN.md — Wave 5: CargaMasiva step 0 radio + step 1 bucket classifier + chips + per-row override + i18n (D4-03, D4-02)
- [x] 25-12-PLAN.md — Wave 5: CargaMasiva step 2 result panel + failure CSV download + /clients/import wire + 10k-row perf QA (REQ-25-17, REQ-25-21)
- [x] 25-13-PLAN.md — Wave 6: ClienteView top-bar "Importación masiva" button (D4-01)
- [x] 25-14-PLAN.md — Wave 6: PromoteMergeDialog + ClienteView save-handler wire (D1-03, D1-04)
- [x] 25-15-PLAN.md — Wave 7: sales/reports scope audit + dual-FK read precedence + cross-store regression (REQ-25-04, REQ-25-07, Pitfall 6) [DEFERRED — 4개 매장 모두 group=1 이라 운영 영향 없음]
- [x] 25-16-PLAN.md — Wave 8 (Hot Fix A): ClientsSyncService 추출 + 4개 client INSERT path (POS / import / legacy CRUD / storeTemplate) 통합 + import dedupe normalize (REQ-25-09, REQ-25-15, REQ-25-22, D1-02, D1-03)
- [x] 25-17-PLAN.md — Wave 9 (Backfill B): 운영 50개 legacy clients → global_clients/store_clients 일괄 이관 + sales.client_id → store_client_id remap + dry-run/postcheck SQL (REQ-25-09, REQ-25-22, D2-02, D2-03)
- [x] 25-18-PLAN.md — Wave 10 (Safety Net C): Sequelize @AfterCreate / @AfterBulkCreate hook 으로 모델 자가 보장 invariant — 향후 신규 path 자동 sync (REQ-25-09, REQ-25-22, D1-02)

### Phase 26: Gastos N차 카테고리 트리 — 무한 깊이(최대 5단계) 카테고리 계층 구조

**Goal:** 기존 2단계 평면 구조(`expenses_categories` + `expenses_subcategories`)를 단일 자기참조 트리 테이블(`expense_categories`)로 통합. 사용자가 매장별로 N차 카테고리(루트 → 자식 → 손자 ... 최대 5단계)를 자유롭게 만들고, 다른 부모로 subtree 째 이동하고, 어느 깊이의 노드든 gasto 등록 시 선택 가능하게 한다. Reports 는 recursive CTE 로 부모 노드에 자손 합계를 자동 롤업하고, 사용자는 "어느 깊이까지 펼칠지" 옵션으로 보고서 가독성 조절. Adjacency list + materialized path(`path` 컬럼) 하이브리드로 CRUD 단순성과 breadcrumb 표시 속도를 동시 확보.

**Requirements:**
1. 새 테이블 `expense_categories`: id, store_id, parent_id(self FK, NULL=root), name, path(materialized 'A > B > C'), depth(0..5), sort_order, color, icon, status, timestamps
2. 깊이 제한 5단계 — `CHECK (depth <= 5)` + 자기 참조 사이클 방지 `CHECK (parent_id IS NULL OR parent_id != id)`
3. 같은 부모 밑 동명 형제 금지 — `UNIQUE (store_id, parent_id, name)`
4. `path` / `depth` 자동 갱신 트리거 (BEFORE INSERT/UPDATE) — INSERT 시 부모 path 조회해 prefix, parent 변경 시 본인 + 모든 자손 path/depth 재계산
5. 기존 `expenses_categories` + `expenses_subcategories` → 새 `expense_categories` 마이그레이션: 카테고리는 루트(parent_id=NULL)로, 서브카테고리는 자식(parent_id=root.id)으로 변환. expenses.category_id 는 그대로 유지하되 의미만 "선택된 노드 ID"로 변경(루트일 수도, 자식일 수도, 손자일 수도). expenses.subcategory_id 는 기존 값이 있으면 category_id 로 옮긴 후 컬럼 drop
6. 기존 `expenses_categories` / `expenses_subcategories` 테이블은 일정 기간(2주) deprecated 상태 유지 후 drop — 롤백 안전
7. 백엔드 신규 모델 `ExpenseCategory` (Sequelize self-FK + HasMany children/parent) + 기존 `ExpensesCategories` / `ExpensesSubcategories` 모델 삭제
8. CRUD endpoints: GET /expense-categories/tree (전체 트리 한 번에 — store-scoped), POST /expense-categories (루트 또는 자식), PUT /expense-categories/:id (rename), PUT /expense-categories/:id/move (parent 변경 — subtree 째 이동, 깊이 5 검증), PUT /expense-categories/:id/sort (sort_order 변경), DELETE /expense-categories/:id (자식 처리 옵션 포함)
9. 삭제 정책: 자식 있는 노드 삭제 시 다이얼로그로 사용자 선택 — (a) 자식들을 부모로 승격(grandparent 의 자식으로 이동) (b) 자식들을 다른 노드 밑으로 이동 (c) 전체 subtree 삭제. 정책 파라미터를 DELETE body 로 전달
10. 다른 부모로 이동(`PUT /:id/move`): subtree 전체 이동. 이동 후 본인 + 모든 자손의 depth 합계가 5 초과면 400 반환. 사이클(자기 자신 또는 자손을 부모로 지정) 방지 검증
11. 프론트엔드 카테고리 관리 페이지(`/configuracion/categorias-gastos` 또는 기존 gastos 설정 안에): 트리 뷰 컴포넌트 (react-arborist 또는 MUI TreeView) — expand/collapse, 인라인 편집, [+] 자식 추가, [✎] 이름 변경, [🗑] 삭제 다이얼로그, 드래그앤드롭으로 같은 부모 내 정렬 + 다른 부모로 이동, 검색(이름 매칭)
12. Gasto 등록/편집 폼의 카테고리 선택: cascading + 검색 가능한 트리 드롭다운. 선택된 노드의 path 전체 표시 (`Servicios > Internet > Móvil`). 어느 깊이의 노드든 선택 가능. "현재 입력값으로 새 카테고리 생성" 단축 옵션
13. Gasto 리스트 화면: 카테고리 컬럼에 path 한 줄 표시 (`expense_categories.path` 직접 SELECT — recursive CTE 불필요)
14. Reports (`reportsGasto.service.ts`, `reportsGastoCockpit.service.ts`) 트리 롤업: recursive CTE 또는 `WITH RECURSIVE` 로 부모 노드 합계 = 자손 전체 합계 자동 계산. 사용자가 UI에서 "depth 1까지 / 2까지 / 전체" 선택 가능 — 선택한 깊이까지만 행 노출하고 그 아래는 부모 합계에 포함
15. 권한 — 기존 expenses CRUD 권한과 동일(admin 가능, vendedor 불가). 트리 구조 변경(이동/삭제)은 명시적으로 admin 만
16. 다국어 — 에러 메시지/UI 라벨 es/ko 모두 번역. 트리 컴포넌트의 "Add child", "Move to..." 등 UI 문자열 i18n
17. Audit — 카테고리 이동/삭제 시 audit_log 에 기록 (어떤 노드가 어디로, 자식 처리 정책 등)
18. 글로벌 에러 배너 호환 — 모든 endpoint 의 에러는 GlobalErrorBanner 로 자동 노출 (이번 마일스톤에서 도입한 영구 Alert 시스템 활용)

**Depends on:** 없음 (독립). 단 expenses 관련 reports 코드 영향 있으니 운영 배포 시 회귀 테스트 필수

**UI hint:** yes (관리 페이지 트리 뷰 + Gasto 폼 트리 드롭다운 + Reports depth 선택 UI)

**Success Criteria** (what must be TRUE):
  1. `expense_categories` 테이블 + 트리거 + 마이그레이션 적용. 기존 매장 데이터가 트리 구조로 정상 변환됨 (모든 카테고리는 루트, 모든 서브카테고리는 그 자식)
  2. expenses 모든 row 의 category_id 가 새 테이블 ID 로 재배선됨 (subcategory_id 가 있던 row 는 자식 노드 ID 로 매핑)
  3. 깊이 5 초과 시도 시 400 반환 (CHECK + app-level)
  4. 사이클 시도(자기 자신/자손을 부모로) 시 400 반환
  5. 사용자가 카테고리 관리 페이지에서 N차 카테고리를 자유롭게 만들고, 인라인 편집/삭제/드래그 이동 가능
  6. Gasto 등록 폼에서 어느 깊이의 노드든 선택 가능 + path 표시 + 검색 동작
  7. Reports 가 사용자 선택 depth 까지 펼치고 부모 합계가 자손 롤업으로 정확히 일치
  8. 삭제 시 자식 처리 옵션 3종 (승격/다른 노드로 이동/전체 삭제) 모두 동작
  9. Subtree 이동 시 본인+자손 depth 합계가 5 초과되면 차단됨
  10. 회귀 테스트: 기존 gasto 등록/리스트/reports 화면 모두 새 모델로 정상 동작 (subcategory_id drop 후에도)
  11. 운영 배포 후 기존 카테고리/서브카테고리 데이터 손실 0건 — backup snapshot 검증

**Plans**: TBD

Plans:
- [x] 26-01-PLAN.md — Wave 1: DB schema + materialized path triggers + Sequelize model + migration scripts (완료 2026-04-27)
- [x] 26-02-PLAN.md — Wave 2: Backend API (8 endpoints) + 21 unit tests + 6-category seed for new stores (완료 2026-04-28)
- [x] 26-03-PLAN.md — Wave 3: Admin tree management UI (react-arborist) + Create/Move/Delete dialogs at /configuracion/categorias-gastos (완료 2026-04-28, tasks 1-4 — checkpoint 5 awaiting human verify)
- [/] 26-04-PLAN.md — Wave 4: CategoryTreeSelector (search/MRU/inline create) + ExpenseModal/list migration + recursive CTE rollup endpoint + DepthSelector reports widget (tasks 1-4 완료 2026-04-28 — checkpoint 5 awaiting human verify)
- [ ] 26-05-PLAN.md — Wave 5: Migration & Cleanup — drop expenses_subcategory_id + deprecated tables + regression QA

### Phase 27: Ventas Online — 온라인 판매 관리 (Mercado Libre / Webshop / Instagram / WhatsApp 통합)

**Goal:** 오프라인 POS 와 별도로, 온라인 채널에서 들어오는 주문을 단일 페이지에서 관리. 주문 라이프사이클(pending → confirmed → preparing → shipped → delivered, cancelled, returned) 추적, 채널별 KPI 제공. 기존 `sales` 도메인과 격리 (`online_orders` 신규 테이블 트리오).

**Requirements:**
1. 신규 테이블 `online_orders` (id, store_id, order_number, channel, client_id/snapshot, status, subtotal/shipping/discount/total, payment_method/status/reference, shipping_carrier/tracking/label_url, external_order_id, notes, metadata JSONB, created_at + lifecycle 타임스탬프) — UNIQUE (store_id, order_number)
2. 신규 테이블 `online_order_items` — 상품 snapshot (product_name/sku/size/color) 포함 (상품 삭제돼도 주문 보존)
3. 신규 테이블 `online_returns` — 반품 사유 enum + 환불액 + status
4. 채널 enum: mercadolibre, webshop, instagram, whatsapp, other
5. 상태 enum: pending, confirmed, preparing, shipped, delivered, cancelled, returned
6. 재고 차감은 `confirmed` 시점 (SERIALIZABLE 트랜잭션) — race condition 방지
7. 취소 시 재고 복구 (SERIALIZABLE)
8. NestJS 모듈 `online-orders` — REST 11개 엔드포인트 (list/detail/create/confirm/prepare/ship/deliver/cancel/return/dashboard/return-status)
9. 권한: 읽기 vendedor 까지, 쓰기 gerente 이상, 반품 승인 admin
10. 프론트엔드 `/ventas-online` 페이지 — KPI 4종 + 필터 + 주문 테이블 + 탭 (Pedidos/Envíos/Devoluciones)
11. 프론트엔드 `/ventas-online/[orderId]` 상세 — 2컬럼 (고객+상품 / 타임라인+결제+액션)
12. SWR 훅 4종 (useOnlineOrders, useOnlineOrder, useOnlineDashboard, useOnlineReturns)
13. 사이드바 `venta` 앱 children 에 "Ventas Online" 추가 (하드코딩, 매장 가시성 무관)
14. 디자인: Primary `#05a7cf`, MUI DataGrid pageSize 50, 코드 스플리팅 (dynamic import ssr:false)

**Depends on:** 없음 (독립 도메인). store_clients (Phase 25) 활용.

**UI hint:** yes (KPI 카드 + 주문 테이블 + 상세 + 탭)

**Success Criteria** (what must be TRUE):
  1. PG10/PG15 호환 마이그레이션 실행 시 3개 테이블 + index + CHECK 제약 모두 적용
  2. POST /online-orders 시 매장별 order_number 자동 +1, UNIQUE 충돌 시 retry 로직
  3. PATCH /online-orders/:id/confirm 시 재고 차감 (SERIALIZABLE), 잘못된 상태 전환은 BadRequest
  4. PATCH /online-orders/:id/cancel 시 재고 복구 (SERIALIZABLE)
  5. /ventas-online 페이지 진입 시 KPI 4종 + 주문 테이블 정상 렌더
  6. 사이드바에 "Ventas Online" 메뉴 노출 + 클릭 시 라우팅 정상
  7. ESLint warning 0건, `npm run build` 통과

**Plans**: 4 plans

Plans:
- [ ] 27-01-PLAN.md — Wave 1: DB 마이그레이션 + Sequelize 모델 + 모듈 등록
- [ ] 27-02-PLAN.md — Wave 2: NestJS 서비스 + 컨트롤러 + DTO + REST API
- [ ] 27-03-PLAN.md — Wave 3: 프론트엔드 페이지 + 뷰 컴포넌트
- [ ] 27-04-PLAN.md — Wave 4: SWR 훅 + 사이드바 통합 + ESLint 검증

### Phase 29: POS Mercadopago — QR Dinámico

**Goal:** 매장 내 결제수단으로 Mercadopago QR Dinámico 도입. store_id 단위로 MP OAuth 계정을 1회 연결, nueva-venta 결제 화면에서 "Mercadopago" 선택 시 백엔드가 QR Code Dinámico 생성(`external_reference = pendingVentaId`). 고객이 MP 앱으로 스캔/결제 → MP webhook → 백엔드 검증 → Socket.io 로 해당 terminal 에 push → 프론트가 자동으로 "Generar Venta" 트리거. 3분 timeout + 수동 취소 + webhook 지연 대비 5초 polling fallback. 환불(devolución) 시 MP REST 자동 환불 호출 포함.

**Requirements**: MP-POS-01, MP-POS-02, MP-POS-03, MP-POS-04, MP-POS-05, MP-POS-06, MP-POS-07
**Depends on:** Phase 21 (store baseline — payment_methods 자동생성), Phase 22 (suspender restore — 결제 실패 시 venta 정합성)
**Plans:** 11/11 plans complete

**Success Criteria** (spec phase 에서 정제):
  1. `store_mercadopago_accounts` 테이블 + OAuth 연결 화면(configuracion 모듈)에서 매장 owner 가 MP 계정 connect/disconnect 가능
  2. nueva-venta 결제수단 선택 시 "Mercadopago QR" 옵션 노출 (계정 미연결 시 disabled + 안내)
  3. QR 생성 시 external_reference = pendingVentaId, 만료 3분 표시 + 수동 취소 버튼
  4. MP webhook 수신 시 서명 검증 + payment status 확인 → Socket.io `payment:approved` 이벤트로 해당 terminal 에 push
  5. 프론트가 이벤트 수신 시 자동 Generar Venta 처리 + 영수증 인쇄
  6. webhook 지연 대비 클라이언트 5초 polling fallback (`GET /v1/payments?external_reference=...`)
  7. 환불 처리 시 MP REST `POST /v1/payments/{id}/refunds` 자동 호출 + 실패 fallback UX

Plans:
- [x] 29-01-PLAN.md — Wave 0: Pre-flight (qrcode.react install + MP_* env vars + test fixtures + ops MP App setup doc)
- [x] 29-02-PLAN.md — Wave 1a: DB migrations (7 mp_* tables PG10/15) + 29-RUN.md execution guide
- [x] 29-02b-PLAN.md — Wave 1b: AES-256-GCM crypto service + 7 Sequelize models + MercadopagoModule bootstrap (split from 29-02 per checker BLOCKER 4)
- [x] 29-03-PLAN.md — Wave 2: OAuth (MP API client + HMAC state + token exchange + Store/POS registration + account resolver + 3 endpoints)
- [x] 29-04-PLAN.md — Wave 3: QR generation (POST /qr + DELETE /qr/:id + GET /payment-intents/:id polling)
- [x] 29-05-PLAN.md — Wave 4: Webhook (re-fetch + idempotent processor) + Socket.io extension (terminal room) + wallet credit
- [x] 29-06-PLAN.md — Wave 5: Frontend OAuth UI (configuracion/mercadopago page + 3 components + sidebar nav + GET /accounts endpoint)
- [x] 29-07-PLAN.md — Wave 6: Frontend POS UI (PaymentSummaryModal extension + QR side-panel + sandbox banner + auto-trigger handleSubmit + processedIntentRef guard)
- [x] 29-08-PLAN.md — Wave 6: Backend Caja MP (MpTransferService + 3 endpoints) + 2 cron jobs (reconcile w/ stale-intent sweep + token refresh)
- [x] 29-08b-PLAN.md — Wave 6: Frontend Caja MP UX (2 SWR hooks + 3 components + CashControlList integration) — split from 29-08 per checker WARNING 6
- [x] 29-09-PLAN.md — Wave 7: Refunds (auto-call on nullifySale + retry endpoint + SalesDetailView failure UX + attempt history)

### Phase 30: POS Mercadopago — Point 단말기

**Goal:** Mercadopago Point Smart 물리 단말기 연동으로 카드(NFC/칩/스와이프) 결제 추가. Phase 29 의 OAuth/store_mercadopago_accounts/webhook/Socket.io 인프라 재사용. nueva-venta 결제 화면에서 "Mercadopago Point" 선택 시 단말기로 결제 명령 전송, 단말기 결제 완료 → webhook → 자동 Generar Venta. 단말기 등록/할당 UI 추가 (terminal ↔ point_device 매핑).

**Requirements**: MP-POINT-01..NN (TBD — Phase 29 완료 후 spec)
**Depends on:** Phase 29 (OAuth + webhook + Socket.io 인프라)
**Plans:** 0 plans (예상 4–5 plans, Phase 29 완료 후 본격 가동)

Plans:
- [x] TBD (Phase 29 완료 후 /gsd-spec-phase 30) (completed 2026-05-05)

### Phase 31: Online Mercadopago — Phase 27 통합 (Checkout Pro/Bricks)

**Goal:** Phase 27 (Ventas Online) 의 결제 레이어로 Mercadopago Checkout Pro / Bricks 추가. 온라인 주문(`online_orders`) 생성 시 MP preference 발급 → 고객에게 결제 링크/Bricks 위젯 제공 → 결제 완료 webhook → `online_orders.payment_status` 자동 갱신 + Socket.io 알림. Phase 29 OAuth 토큰/webhook 인프라 재사용.

**Requirements**: MP-ONLINE-01..NN (TBD — Phase 27 + 29 완료 후 spec)
**Depends on:** Phase 27 (Ventas Online 데이터 모델), Phase 29 (OAuth + webhook 인프라)
**Plans:** 0 plans (예상 4–5 plans)

Plans:
- [ ] TBD (Phase 27 + 29 완료 후 /gsd-spec-phase 31)

### Phase 32: stocks-historial-drawer — Stocks 보고서 row 클릭 → 우측 380px drawer 슬라이드로 productBranch 의 movido/ingreso/fallado/corregido 전체 ledger 를 chronologically 표시. 옛 시스템의 producto별 stock historial 멘탈 모델을 Phase 12 cockpit drawer 패턴으로 재현.

**Goal:** Stocks 보고서에서 productBranch 단위 stock ledger 변동 이력(movido/ingreso/fallado/corregido)을 우측 380px drawer 로 lazy fetch + chronologically 표시. PanelB row 와 PanelC cell 양쪽에서 historial 아이콘으로 진입, ESC/backdrop/re-click 닫기, 30일 윈도우 + "더 로드" 페이지네이션, audit_logs JOIN 으로 사용자명 표시(Sistema fallback), note 패턴 파싱으로 movido 상대 sucursal 표시.
**Requirements**: TBD (enhancement phase, no formal REQ-IDs)
**Depends on:** Phase 12 (cockpit drawer 패턴, useCockpitCache, shared formatters)
**Plans:** 2/2 plans complete

Plans:
- [x] 32-01-PLAN.md — Backend: getHistorial 메소드 + GET /reports/stocks-cockpit/historial 엔드포인트 (CTE + branches/audit_logs LEFT JOIN + note 분류)
- [x] 32-02-PLAN.md — Frontend: useStocksHistorial 훅 + StocksHistorialDrawer 컴포넌트 + StocksCockpitBody/PanelB/PanelC wiring

### Phase 33: Permissions v2 — RBAC + Branch Scope + Approval Threshold + Audit

**Goal:** 운영 사용자 0명인 zero-cost window 를 활용하여 권한 모델을 한 번에 v2 로 갈아엎음. 8 표준 role + `user_branches` 다지점 매핑(1 user × N branch × 1 role) + `approval_thresholds`/`approval_requests` 승인 임계치 워크플로 + `user_permission_cache` 5분 TTL + audit 통합. 기존 `users.branch_id` deprecate, `function-permission.guard.ts` (104ms slow query) 를 캐시 기반으로 교체. **점진 마이그레이션·기능 플래그·병렬 가드 운영 모두 생략** (사용자 0명 가정).
**Requirements**: PERM-V2-01..NN (TBD — 정식 REQ-ID 미부여, spec 본문 참조)
**Depends on:** Phase 14 (Permisos Control UI 기반), Phase 25 (audit_logs 패턴), Phase 29 (storeTemplate seed 패턴)
**Plans:** 3/3 plans implementation 완료 / verifying (uncommitted 30 파일, 운영 PG10 runbook 미실행, 정식 UAT 미수행)
**Status:** ⚠ verifying — `git status` 미커밋 + runbook 미실행 + UAT 필요. retroactively 등록된 phase (작업은 .gsd/ 와 .planning/permissions-redesign/ 에서 진행됨).

Plans:
- [x] 33-01 — Sprint 1 (Day 1-7): backend 4 마이그레이션 + 22 Sequelize 모델/서비스/가드/컨트롤러 (`user_branches`, `approval_thresholds`, `approval_requests`, `user_permission_cache`, PermissionGuard 캐시 기반 교체) — see [.gsd/spec-permissions-v2.md](../.gsd/spec-permissions-v2.md), [.gsd/review-permissions-v2-day1-2.md](../.gsd/review-permissions-v2-day1-2.md), [.gsd/review-permissions-v2-day3.md](../.gsd/review-permissions-v2-day3.md), [.gsd/review-permissions-v2-day4.md](../.gsd/review-permissions-v2-day4.md), [.gsd/review-permissions-v2-sprint1-final.md](../.gsd/review-permissions-v2-sprint1-final.md)
- [x] 33-02 — Sprint 2 (Day 6-8): frontend 13 페이지/뷰/훅/스크립트 + 9 문서 (CASL ↔ function_slug 어휘 통일, UserBranch 관리 UI, ApprovalRequest 대기열) — see [.gsd/review-permissions-v2-day6-7.md](../.gsd/review-permissions-v2-day6-7.md), [.gsd/review-permissions-v2-day8.md](../.gsd/review-permissions-v2-day8.md), [.gsd/guide-permissions-v2-frontend-migration.md](../.gsd/guide-permissions-v2-frontend-migration.md), [.gsd/review-permissions-v2-final-phase29.md](../.gsd/review-permissions-v2-final-phase29.md)
- [x] 33-03 — Post-sprint hardening: `storeTemplate.createDefaultRoleFunctions` idempotent 가드 (`findOrCreate`) — see [.gsd/review-phase30-01-idempotent.md](../.gsd/review-phase30-01-idempotent.md)
- [ ] 33-UAT — 운영 PG10 적용 ([.gsd/runbook-permissions-v2-prod.md](../.gsd/runbook-permissions-v2-prod.md)) + 8 role 시드 검증 + 다지점 사용자 시나리오 검증 + approval threshold 워크플로 E2E

### Phase 33.1: Permissions v2 D1/D2 Hotfix — ensureRoleFunctions auto-fill 제거 + cache invalidation 추가 (INSERTED)

**Goal:** 2026-05-24 자동 권한 점검에서 발견한 P0 결함 2건 hotfix.
- **D1**: `user-structure.service.ts::ensureRoleFunctions` (line 113-160) + `user-registration.service.ts::ensureRoleFunctions` (line 139-160) 가 `/me` 호출 시점에 role 의 모든 function 에 대해 `RoleFunction.create(...)` 를 자동 실행하여 사용자의 명시적 권한 토글과 DB 상태를 분리시킴 — tight repro 에서 bulk-actions `{fn:7, ['read']}` 직후 role_functions 1 row → /me 직후 11 row 누적 확인. 권한 매트릭스 UI 신뢰성 붕괴.
- **D2**: `role-function.service.ts::bulkUpdateRoleFunctionActions` (line 71-105) 끝에 `cacheService.invalidateUser` 호출 누락 → `user_permission_cache` 0 rows = Phase 33 spec "5분 TTL 캐시" 미작동 = function-permission.guard 의 104ms slow query 캐시 교체 목표 미달성. `/me` 매 호출마다 권한 재계산 (PG pool 부담).

**Requirements:** D1-FIX-01, D1-FIX-02, D1-FIX-03, D1-FIX-04, D2-FIX-01, D2-FIX-02, REG-FIX-01, REG-FIX-02, REG-FIX-03 (총 9 IDs — 33.1-CONTEXT.md `<specifics>` 매핑)
**Depends on:** Phase 33 (Permissions v2 — D1/D2 결함이 Phase 33 구현 내부에 존재)
**Plans:** 3 plans (planning 완료 2026-05-24, execute 완료 2026-05-25) — Wave 1 sequential [33.1-01 D1 fix + 33.1-02 D2 fix] → Wave 2 [33.1-03 회귀 검증]
**Status:** ✅ VERIFIED 2026-05-26 — 3 commits (95c2484 + 0181056 + e09376c) in api-ventago. Jest 11 tests PASS. Dev repro `phase33.1-d1-d2-repro.sh` EXIT=0 (D1 PASS: `/me` 가 role_functions mutate 안 함 / D2 invalidate OK / cache WRITE soft-fail = Phase 33 PermissionResolverService 책임, 33.1 out of scope). 운영 PG10 적용 push 대기.

근거: [.planning/phases/33-permissions-v2/audit/2026-05-24-automated-verification.md](phases/33-permissions-v2/audit/2026-05-24-automated-verification.md) — 자동 시나리오 A/B/F 점검 결과 + [.planning/phases/33.1-permissions-v2-hotfix-d1-d2/33.1-CONTEXT.md](phases/33.1-permissions-v2-hotfix-d1-d2/33.1-CONTEXT.md) — locked decisions

Plans:
- [x] 33.1-01-PLAN.md — D1 fix: user-structure.service.ts::ensureRoleFunctions read-only 화 + backfillRoleFunctions 삭제 + user-registration.service.ts::ensureRoleFunctions 삭제 (D1-FIX-01..04, Wave 1) — commit 95c2484
- [x] 33.1-02-PLAN.md — D2 fix: PermissionCacheService.invalidateRole 신규 메서드 + RoleFunctionService DI 주입 + bulkUpdateRoleFunctionActions 끝에 invalidateRole 호출 + RoleFunctionModule imports 에 PermissionsModule 추가 (D2-FIX-01..02, Wave 1) — commit 0181056
- [x] 33.1-03-PLAN.md — 회귀 검증: D1 Jest spec 신규 + D2 Jest spec 확장 + tight repro 쉘 스크립트 + Task 4 사용자 checkpoint (REG-FIX-01..03, Wave 2) — commit e09376c, Jest 11 tests PASS, dev repro VERIFIED 2026-05-26 (EXIT=0)

### Phase 34: Customer WhatsApp + CRM Routing — Phase 29 Wave C

**Goal:** `clients` 와 `global_clients` 에 전용 `whatsapp` 컬럼 추가하여 Phase 29 Wave B Click-to-Chat 이 `client.phone` 이 아닌 `client.whatsapp` 으로 라우팅. **Strict mode (fallback 없음)**: WhatsApp 미등록 고객은 422 `WHATSAPP_NOT_REGISTERED`, 정규화 실패는 422 `INVALID_WHATSAPP_NUMBER`. 폼에 "Igual que teléfono" 미러 체크박스 + ClienteVistaView/GlobalClientesView 컬럼 노출 + WhatsAppSendDialog 게이팅. 기존 고객은 마이그레이션 시점에 `phone` 에서 1회 백필.
**Requirements**: WA-CRM-01..NN (TBD — spec 본문 참조)
**Depends on:** Phase 29 Wave B (Click-to-Chat 서비스 + WhatsAppSendDialog 인프라), Phase 25 (global_clients/clients_sync 패턴)
**Plans:** 1/1 plan (12 tasks) implementation 완료 + 모든 commit pushed / verifying (정식 UAT 미수행, 운영 적용 보류)
**Status:** ⚠ verifying — api-ventago 9 commits + ventago-app 3 commits 모두 origin 에 push 되었으나 운영 매장에서 실제 사용 검증 미수행. retroactively 등록된 phase (작업은 docs/superpowers/ 에서 진행됨).

Plans:
- [x] 34-01 — 12-task TDD 구현: DB 마이그레이션(phone 백필) + Sequelize 모델 + DTOs + ClientsSyncService 전파 + ClickToChatService TDD swap + WhatsAppSendDialog 게이트 + ClienteVistaView/GlobalClientesView 컬럼·폼·미러 체크박스 + Jest 스펙 + ESLint sweep — see [docs/superpowers/specs/2026-05-14-client-whatsapp-crm-design.md](../docs/superpowers/specs/2026-05-14-client-whatsapp-crm-design.md), [docs/superpowers/plans/2026-05-14-client-whatsapp-crm.md](../docs/superpowers/plans/2026-05-14-client-whatsapp-crm.md)
- [ ] 34-UAT — manual UAT scenarios (whatsapp-only customer, "Igual que teléfono" 체크박스 동작, 422 에러 표시, 기존 고객 백필 결과 확인) + 운영 적용

### Phase 35: Activity Ledger — Movidos/Fallados Trace in ventaVista

**Goal:** `nueva-venta` 스페셜 모드(`movidos`, `fallados`)로 등록되는 비-판매 활동을 `sales.activity_type` 1급 컬럼으로 승격해 `ventaVista` 에 통합 거래 원장(unified transaction ledger)으로 노출. 기존 sales 쿼리는 명시적 `activity_type='sale'` 필터로 보호하여 매출 통계 무오염 유지 (D-04 default scope risk 회피). KPI strip 을 per-sucursal Resumen 테이블(`VENTAS · PRENDAS · DESC · MOV+ · MOV− · FAL · NETO`)로 교체, 행/셀 클릭으로 리스트 필터 chip + URL query 드릴다운. Stock Cockpit 의 미스터리 OFFSET 도 MOV+/MOV−/FAL 로 분리해 명확화 (Phase B). 신규 CASL `stock.movement` 권한 + branch 제약으로 무단 재고 이동 차단.
**Requirements**: AL-01..AL-36 (35-SPEC.md 의 D-01..D-11 + API + UI/UX + UAT criteria 매핑)
**Depends on:** Phase 33 (Permissions v2 — CASL `stock.movement` 권한 통합), Phase 32 (stocks-historial-drawer — 동일 데이터 source 의 보완 뷰)
**Plans:** 9 plans (5 waves) — Wave 1 schema → Wave 2 backend (parallel) → Wave 3 frontend (parallel) → Wave 4 backfill → Wave 5 UAT
**Status:** ⏳ pending — planning 완료 (2026-05-22), execute 대기

Plans:
- [x] 35-01 — DB 스키마: sales.activity_type/origin_branch_id/target_branch_id + CHECK + 2 FK + 3 INDEX (Wave 1) — 2026-05-23
- [x] 35-02 — StockService.createStockMovement 단일 트랜잭션 (sales+sale_items+stocks) + @Permission('stock.movement','create') + branch 제약 + permission_slug 마이그레이션 (Wave 2) — 2026-05-23
- [x] 35-03 — 13개 sales 쿼리 서비스에 activity_type='sale' 명시 필터 + GET /sales/all 4 신규 query + GET /sales/daily-stats 신규 엔드포인트 (Wave 2) — 2026-05-23
- [x] 35-04 — useDailySalesStats SWR 훅 + SalesResumenTable 컴포넌트 (8 컬럼, TOTAL 행 조건부, movBalance 알람) (Wave 3) — 2026-05-23
- [x] 35-05 — DataConfig Tipo chip + Cliente dual-purpose + 의미없는 컬럼 '—' + SalesListView Resumen 교체 + URL ↔ filter sync + chip strip (Wave 3) — 2026-05-23
- [x] 35-06 — ProductList.handleSubmitSpecial 응답 saleId 추출 + toast "Ver detalle" 액션 링크 (Wave 3) — 2026-05-23
- [x] 35-07 — Stock Cockpit Phase B: reportsStocksCockpit items SQL 에 MOV+/MOV−/FAL sub-query + PanelB_ItemTable 3 컬럼 + OFFSET 색상 분기 (Wave 3) — 2026-05-23
- [x] 35-08 — backfill SQL (movido out/in + fallado, idempotent + backfill_failures + backfill_processed_sale_id) + dry-run 쉘 (dev/prod 환경) (Wave 4) — 2026-05-23 (dry-run only; production deferred to UAT)
- [~] 35-09 — UAT: 35-UAT.md 22 항목 (U1..U22) + phase35-uat.sh 자동 검증 쉘 (Wave 5) — 2026-05-23 scaffold complete · automated 21/22 PASS (1 cURL SKIP) · 17 manual items awaiting user validation

### Phase 36.1: Sale branch 필터 + dailyNumber 비-0 회귀 hotfix

**Goal:** Phase 35 UAT 종료 후 spec-phase 36 진행 중 사용자 추가 검증 시 발견된 회귀 2건 hotfix. (1) **REG-1 정상 sale 의 branch 필터 누락**: sales.service.ts:364-369 의 branch 필터가 origin_branch_id/target_branch_id 만 매칭하여 admin user (branch_id=NULL) 가 등록한 sale 행이 ventaVista 의 branch chip 필터에서 모두 제외됨. (2) **REG-2 movido/fallado dailyNumber 비-0 부여**: U12b 1차 검증 시 모두 0 이었으나 후속 인터랙션 후 비-0 값 (2/3/5/6/8) 부여됨. sale daily_number 와 충돌 (sale 101 dn=2 / movido 99 dn=2). 근본 원인 미파악 — Phase 36.1 plan 단계에서 추적.

**Requirements:** REG-1-FIX-01..NN + REG-2-FIX-01..NN (TBD — spec 본문 또는 plan 직행)
**Depends on:** Phase 35 (hotfix 5건 적용 완료)
**Plans:** 0 plans (예상 2-3 plans: REG-1 fix + REG-2 root cause 추적 + 회귀 검증)
**Status:** ⏳ pending — /gsd-spec-phase 36.1 또는 /gsd-plan-phase 36.1 으로 본격 가동

Plans:
- [ ] TBD (/gsd-plan-phase 36.1)

### Phase 36: 권한매핑보강+UAT감업 — stock.movement role_function_actions 누락 + 운영 RUNBOOK

**Goal:** Phase 35 manual UAT (2026-05-23) 에서 발견된 운영 적용 차단 사항 해결. (1) `role_functions` INSERT 했으나 `role_function_actions` 매핑이 누락되어 admin UI 권한 매트릭스에 모든 role 이 "권한 없음"으로 표시되고 PermissionGuard 가 403 반환하던 회귀 수정 — 모든 store 의 `stock.movement` × {create/read/update/delete} 매핑 일괄 부여 마이그레이션 SQL + admin UI 일괄 부여 UX 검증. (2) 운영 PG10 적용 절차 RUNBOOK (`35-RUNBOOK-PROD.md`) 작성 — 마이그레이션 순서, backfill dry-run/실행, U9 권한 SQL, hotfix 코드 배포 순서, 롤백 절차 포함. (3) Phase 35 UAT 의 deferred 항목 (U14 movBalance 알람 staging 재검증, U18 MOV+ tooltip 후속 plan 검토) 결정.
**Requirements:** PERM-MAP-FIX-01..NN + RUNBOOK-PROD-01..NN (TBD — spec 본문 참조)
**Depends on:** Phase 35 (Activity Ledger — hotfix 5건 dev 적용 완료), Phase 33 (Permissions v2 — role_function_actions 스키마)
**Plans:** 3 plans (planning 완료 2026-05-23) — 36-01 SQL + 36-02 RUNBOOK + 36-03 U14+UAT+plant-seed
**Status:** ⏳ ready-to-execute — /gsd-execute-phase 36 또는 plan-by-plan 수동 실행

Plans:
- [ ] 36-01 — role_function_actions 보강 마이그레이션 SQL (phase36-stock-movement-actions-backfill.sql) + dev 검증 + idempotent
- [ ] 36-02 — 35-RUNBOOK-PROD.md 작성 (5 sections: 사전 점검 / 마이그레이션 / Backfill / Hotfix 배포 / 회귀 검증 / 롤백)
- [ ] 36-03 — U14 interactive psql + browser 재검증 + 35-UAT.md 결과 갱신 (U9/U9b/U10/U14 PASS) + STATE 전환 + U18 plant-seed

### Phase 37: Mobile Sales Shell — Vendedor + Revendedor 통합 Flutter 앱 (role 기반 scope 자동 결정)

**Goal:** 하나의 Flutter 앱이 로그인 응답의 `role` 에 따라 데이터 가시 범위(scope)를 자동으로 결정한다. `role=vendedor` 이면 자기 1지점(branch)의 stock 만 보고 거기서만 판매(BranchScope 모드), `role=revendedor` 이면 owner 그룹 내 허용된 N개 매장의 통합 카탈로그를 보고 견적/주문(MultiStoreScope 모드, Phase 24 `reseller.catalog_unified` 사용). 백엔드는 동일한 `/mobile/*` 엔드포인트에서 JWT claim 의 role/scope 를 강제하여 URL 파라미터 조작으로 다른 지점/매장 데이터 접근 불가. Phase 17 Portal de Talleres 의 Flutter 인프라(Dio + Riverpod + secure storage + FCM + JWT)를 100% 재사용하되 별도 앱이 아닌 monorepo workspace 로 흡수. 데스크탑 POS 의 `active_sessions` 와 분리된 `mobile_sessions` 테이블로 한 유저가 데스크탑+모바일 동시 접속 가능.

**Requirements**: MOBILE-01..NN (TBD — /gsd-spec-phase 37 에서 정제)
**Depends on:** Phase 33 (Permissions v2 — `user_branches` 다지점 매핑 + PermissionGuard 캐시), Phase 17 (Portal de Talleres — Flutter 인프라 코드 재사용), Phase 24 Wave 1-2 (Reseller Marketplace — `reseller.catalog_unified` MV. **revendedor 모드 활성화 전제**. vendedor 모드는 Phase 24 와 무관하게 먼저 출시 가능)

**운영 진단 결과 (2026-05-31):** vendedor user 2명, 모두 active, 모두 coolsistema(store_id=6) 소속. C_NEEDS_BACKFILL=0, MISMATCH=0. → **베타 매장 coolsistema 확정 (D-09)**, **Plan 37-01 backfill = idempotent 2-row INSERT 만 (D-08)**, **multi-branch UI 후순위 — 1차 출시는 1지점 lock UI (D-10)**, vendedor 폭증 가정 없음 (D-11). ACE 의 Phase 33 신규 8 role 미사용 발견 → 별도 phase 후보 (D-12, 37 범위 외).

**UI hint:** yes (Flutter 모바일 앱 — vendedor / revendedor 듀얼 모드)

**Success Criteria** (what must be TRUE):
  1. `mobile_sessions` 테이블(user_id, device_fingerprint, fcm_token, scope_mode, scope_branch_id, active_session_token, last_seen_at) 생성. 데스크탑 `active_sessions` 와 분리되어 한 유저가 데스크탑+모바일 동시 접속 가능
  2. `MobileScopeGuard` 가 모든 `/mobile/*` 엔드포인트에 적용되어 JWT claim 의 role 을 보고 자동 scope 좁힘 — vendedor 는 `user_branches.branch_id IN (?)` 강제, revendedor 는 `reseller_tienda_link.store_id IN (?)` 강제
  3. vendedor 의 `users.branch_id` 또는 `user_branches` 매핑이 NULL/0건이면 모바일 로그인 401 `VENDEDOR_SCOPE_NOT_DEFINED`
  4. 모바일이 보내는 `?storeId=` / `?branchId=` 쿼리는 신뢰하지 않음 — 토큰 scope 와 충돌 시 403 `SCOPE_VIOLATION`
  5. `GET /mobile/catalog` 단일 엔드포인트로 통일 — vendedor 응답에는 자기 branch 의 product_branch stock 수치 포함, revendedor 응답에는 매장별 stock 합계 + min markup price 포함. 응답 shape 의 공통 키는 동일하여 Flutter 가 같은 위젯으로 렌더
  5b. 🆕 **D-14 (2026-06-11) — 재고 조회 진입점 차이 (UI/UX)**: vendedor 는 상품에 붙은 **QR(Phase 38 CodigoMadre 라벨, 딥링크 `/m/stock?s=&p=`) 을 스캔**해 자기 매장 **전 지점별 재고**를 비교 조회(STOCK-READ scope = 매장 전 지점 read, SELL scope=자기 1지점 과 구분). revendedor 는 **QR 불필요**, 카탈로그 검색으로 팔고자 하는 제품의 매장별 재고 확인. 상세: 37-CONTEXT.md D-14
  5c. 🆕 **D-15 (2026-06-11) — 상품 상세 = 변형 재고 매트릭스 (UI)**: 수량 선택 화면은 +/- 스테퍼가 아니라 웹 `VariantsStockVenta.tsx` 의 **색×사이즈 매트릭스 모바일 이식** — 각 셀에 수량 **직접 입력** + 셀마다 현 지점·타 지점 재고 동시 표시. `variantQuantities` (`colorId-sizeId`) 로 카트 적재. 상세: 37-CONTEXT.md D-15 / SPEC MOBILE-C-08
  6. 🔄 **D-13 으로 정정 (2026-06-11)** — 모바일 판매 (`POST /mobile/sales`) 는 **확정 판매가 아니라 보류(suspendido) 를 생성**한다. 기존 `suspended-sales` 모듈 재사용 → **Caja·당일 매상 무영향**, 재고만 `type:'suspend'` 로 임시 예약. 확정·Caja 반영은 데스크탑 POS 운영자가 보류 목록에서 복원·결제할 때 발생. vendedor + revendedor 공통(revendedor 는 Phase 24 quote/order pending 이 동등 역할) + Phase 25 store_clients scope 강제. _(폐기된 원안: sales-create 재사용 + activity_type='sale' 확정.)_ 상세: 37-CONTEXT.md D-13
  7. **Pool 보호**: `MemoryCacheService` 로 카탈로그 60초 / stock 10초 캐시. 100명 동시 모바일 접속 시 PG pool 사용량 +20 connection 이하 (process-local 캐시 1차 방어선, MV 2차, DB 마지막)
  8. **Scope 는 set 으로 설계**: vendedor 의 `user_branches` row 가 1개면 strict 1지점, N개면 multi-branch (UI 만 selector 표시). enum boolean 으로 박지 않음 — 6개월 뒤 "옆 지점 stock 보기" 요구 즉시 대응
  9. 매장 lifecycle (Phase 9) SUSPENDED/ARCHIVED 전이 시 모바일 로그인도 동일하게 차단 (401 STORE_SUSPENDED)
  10. Flutter Riverpod `ScopeProvider` 가 `/me` 응답 보고 BranchScope / MultiStoreScope 자동 결정 — 화면(검색/카트/결제)은 공통 컴포넌트, scope 별 차이는 selector 잠금 + 가격 표시 규칙뿐
  11. 오프라인 모드: 카탈로그 lastFetch 캐시로 stock 조회 가능, 판매 확정은 온라인 필수 (확정 순간만 SERIALIZABLE 트랜잭션)
  12. `mobile_sessions.active_session_token` UNIQUE — 동일 device fingerprint 재로그인 시 기존 모바일 세션 즉시 401 `MOBILE_SESSION_EXPIRED` (데스크탑 active_sessions 와 동일 정책)

**Plans**: 5 plans (5 Waves) — vendedor MVP 우선, revendedor 는 Phase 24 완료 후 Wave 5 활성화

Plans:
- [ ] 37-01-PLAN.md — Wave 1: Backend MobileScopeGuard + JWT scope claim 확장 + `mobile_sessions` 마이그레이션 + `/mobile/auth/login` + `/mobile/me` (vendedor branch_id NULL 거부)
- [ ] 37-02-PLAN.md — Wave 2: Backend `/mobile/catalog` + `/mobile/stock` + `/mobile/sales` (scope 강제 + MemoryCacheService 캐시 + activity_type='sale' + store_clients scope)
- [ ] 37-03-PLAN.md — Wave 3: Flutter 셸 (Phase 17 재사용) + Riverpod ScopeProvider + 로그인/홈 + secure storage + 세션 만료 처리 + FCM 등록
- [ ] 37-04-PLAN.md — Wave 4: Flutter Vendedor 화면 (1지점 lock + 바코드 스캐너 + 카트 + 결제 + 영수증 출력 hook) — **MVP 1차 출시**
- [ ] 37-05-PLAN.md — Wave 5: Flutter Revendedor 화면 (매장 selector + 매장별 최소가/마진 + 견적 생성 + Phase 24 quote API 연동) — **Phase 24 Wave 1-2 완료 후 활성화**

### Phase 38: CodigoMadre QR 감열 출력 — CodigoVista QR 버튼 + print-agent QR 라벨

**Goal:** CodigoVista(precios) 의 CodigoMadre View 에서 각 parent 행에 QR 출력 버튼을 추가한다. 버튼 클릭 → price-type 선택 Popover → `POST /print/qr` → print-agent(감열/ESC-POS)가 **QR + CodigoMadre 코드 + 제품명 + 선택 가격** 라벨을 출력. QR 은 딥링크 URL(`https://ventago.coolsistema.com/m/stock?s={storeId}&p={parentProductId}`)을 인코딩하여, 나중에 판매원 앱(Phase 37)이 스캔하면 그 제품의 지점별 재고를 변형 테이블로 보여줄 수 있게 한다. 본 Phase 범위 = **데스크탑 QR 출력(Half A)** 만. 모바일 스캔/`/m/stock` 해석/크로스 지점 변형 재고 뷰(Half B)는 **Phase 37 mobile 범위로 편입**.

**Requirements**: QR-01..NN (TBD — /gsd-spec-phase 38 에서 정제)
**Depends on:** Phase 13 (print-agent 인프라 — socket `/print-agent`, HTML→PNG→printImage 파이프라인), Phase 33 (precios 권한). Half B 는 Phase 37 (mobile-sales-app) 의존이나 본 Phase 범위 외.

**설계 문서:** [docs/superpowers/specs/2026-06-11-codigomadre-qr-thermal-print-design.md](../../docs/superpowers/specs/2026-06-11-codigomadre-qr-thermal-print-design.md)

**UI hint:** yes (CodigoVista parent 행 QR 버튼 + price-type Popover)

**확정 결정 (brainstorming 2026-06-11):**
- D-1 범위: 데스크탑 QR 출력만 (Half A). 모바일 스캔은 Phase 37.
- D-2 QR 페이로드: 딥링크 URL (storeId + parentProductId). `/m/stock` 해석은 Phase 37.
- D-3 라벨: QR + 코드 + 제품명 + 가격.
- D-4 가격: 출력 시 사용자가 price-type 선택 (Popover).
- D-5 파이프라인: print-agent 가 HTML 에서 QR 생성 → 기존 renderHtmlToPng(576) → printImage (fiscal 패턴 재사용).

**Success Criteria** (what must be TRUE):
  1. CodigoVista CodigoMadre View 의 parent 행에만 QR 출력 IconButton 노출 (변형 행 제외, 행 클릭 편집과 분리)
  2. 버튼 클릭 → price-type 선택 Popover (usePriceTypes SWR 재사용) → 선택 가격으로 출력
  3. `POST /print/qr { branchId, parentProductId, priceTypeId, agentId? }` → 백엔드가 딥링크 URL 조립 + Product/가격 조회 → `emitPrintQr` 가 `branch:{branchId}` 룸에 `print_qr` emit (기존 barcode 패턴)
  4. print-agent `print_qr` 핸들러가 QR(qrcode) + 코드 + 제품명 + 가격 HTML → renderHtmlToPng(576) → printImage 로 감열 출력
  5. QR 페이로드 = `https://ventago.coolsistema.com/m/stock?s={storeId}&p={parentProductId}` (운영) / dev 호스트 치환
  6. 에이전트 오프라인/실패 시 프론트 인라인 Alert + 글로벌 토스트 (에러 가시성 규약)
  7. 출력은 현재 지점(selectedBranchId) thermal 에이전트 대상 (다중 시 룸 또는 agentId)
  8. ESLint 0 (프론트), 백엔드 tsc 0, print-agent CI 빌드 통과

**Plans**: TBD (/gsd-plan-phase 38)

Plans:
- [ ] TBD (/gsd-plan-phase 38)

### Phase 39: Modo Restaurante — POS por mesas (salón + comanda + timing + resumen de pago)

**Goal:** 식당(restaurante) 업종을 위한 테이블 단위 POS 모드. admin·configuración 에서 매장별 "modo restaurante" 토글을 켜면 nueva-venta 화면이 **테이블 배치도(salón) 뷰**로 전환된다. 사용자가 직접 배치한 테이블(원형/긴 원/정사각/직사각, 위치 지정)을 클릭 → **웨이터(seller) 선택 → categoría · 음식 메뉴 · 수량 입력 → "주방으로 전달"(comanda)**. 주문→음식나옴(조리 시간), 음식나옴→소비완료(체류 시간)가 테이블별로 기록된다. 테이블 선택 시 감열 프린터로 **resumen de pago** 출력, **현금/카드/MercadoPago** 수금 기록. **외상 개념 없음, 메뉴 단순.**

**핵심 설계 방향 (brainstorming 2026-06-13):** 별도 프로젝트 재구축이 아니라 **기존 시스템 확장**. sales / sale_items / sale_payment_methods / sellers / print-agent(comandera) / socket.io / mercadopago / 멀티테넌트(store→branch→box→terminal) / 권한(CASL) / 배포를 **그대로 재사용**한다. 신규 항목은 (1) `restaurant_tables`(배치도: 형태·위치·좌석수·상태), (2) `sales` 의 식당 전용 컬럼(table_id + 주문 타이밍, 모두 nullable → 소매 모드 무영향), (3) "modo restaurante" 플래그(store_configs), (4) 전용 venta 프론트 화면. venta 화면은 플래그로 분기 — 소매(기존 VcontrolHome) / 식당(신규 SalonView). 한 계정으로 소매·식당 매장 혼용 가능, 매상·gasto·웨이터 통계는 기존 모듈 자동 통합.

**범위 결정 (MVP 우선):** Slice 1 (이 Phase 핵심) = 식당모드 토글 + 테이블 배치도 편집/뷰 + 주문→주방(comanda 출력) + resumen 결제 + 기본 타이밍 기록. **후속 슬라이스(별도 Phase 후보)** = KDS(주방 디스플레이 화면) 고도화, 상세 타이밍 분석 리포트. 관리/리포트(웨이터·gasto·매상)는 기존 모듈 재사용이므로 본 Phase 신규 구현 최소화.

**미해결 (→ /gsd-spec-phase 39 / /gsd-discuss-phase 39 에서 정제):**
- 주방 전달 방식: comandera(감열) 출력 vs 주방 화면(KDS) vs 둘 다 — 기존 print-agent 인프라 우선 검토
- 두 타이밍 이벤트의 트리거 방식 (누가/어디서 "음식 나옴", "소비 완료" 마킹하는가)
- 메뉴 = 기존 products/categories 재사용 여부 (식당 단순 메뉴 매핑)
- 테이블 배치도 충실도: 자유 드래그 평면 편집기 vs 단순 그리드
- 미결제 테이블의 "열린 주문(open ticket)" 상태 모델 — 기존 sales DRAFT 활용 여부

**Depends on:** Phase 11/13 (print-agent — `/print-agent` socket, HTML→PNG→printImage), Phase 29 (MercadoPago POS), Phase 33 (권한/CASL). 기존 sales/sellers/payment-methods 모듈.

**UI hint:** yes (configuración 식당모드 토글 + Salón 배치도 편집기 + 테이블 주문 패널 + resumen de pago)

**설계 문서(brainstorm 진행 중):** docs/superpowers/specs/ (TBD — /gsd-spec-phase 39 에서 확정)

**Success Criteria** (what must be TRUE): SPEC.md 15개 acceptance criteria (use_restaurant_mode 토글 / SalonView 분기 / restaurant_tables CRUD / sales nullable 회귀0 / 배치도 드래그 / comanda emit / 타이밍 / DRAFT 누적→PAID / cuenta+영수증 / 현금·카드·MP / split+merge / 메뉴 products+카테고리 필터).

**Requirements:** REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, REQ-7, REQ-8, REQ-9, REQ-10, REQ-11 (SPEC.md 11 locked)

**Plans:** 7/7 plans complete

**Status:** 🟢 deployed (2026-06-16) — 7개 plan + 6/16 후속작업(restaurant_elements 구조물, 테이블 회전/크기, category 일원화, mozo admin 제외, 설정 재배치) 그룹 커밋 push, 운영 PG10 마이그레이션 8개 적용, print-agent v1.0.8 CI 빌드 성공. ⚠ 소매 회귀 1건(sellers admin 제외가 공유 /sellers 오염 → ACE 드롭다운 0개) 발견·수정(excludeAdmins opt-in 격리) 재배포. 잔여: Jenkins 자동배포 완료 검증 + 운영 PC print-agent 재설치 + 브라우저 UAT(식당+소매 판매원 귀속).

Plans:
- [x] 39-01-db-foundation-PLAN.md — restaurant_tables 마이그레이션 + sales nullable 컬럼 + store_configs 플래그 + 모델 (REQ-1,2,3)
- [x] 39-02-tables-crud-PLAN.md — RestaurantTablesModule CRUD + 스코프 + 상태 동기화 헬퍼 (REQ-2,5)
- [x] 39-03-print-temp-handler-PLAN.md — print-agent print_temp 핸들러 (★blocking, comanda/resumen 인쇄) + CI 재빌드 (REQ-6,9)
- [x] 39-04-storeconfig-flag-PLAN.md — update-flag 화이트리스트 + 식당 카테고리 저장 (REQ-1)
- [x] 39-05-restaurant-sale-lifecycle-PLAN.md — DRAFT 누적 + comanda emit + 타이밍 + cuenta/영수증 + split/merge 결제 (REQ-6,7,8,9,10,11)
- [x] 39-06-config-toggle-editor-PLAN.md — StoreConfigContext 플래그 + configuración 토글 + SalonEditor 배치도 편집기 (REQ-1,4,5)
- [x] 39-07-salonview-order-payment-PLAN.md — nueva-venta 분기 + SalonView + OrderModal + 타이밍 + RestaurantPaymentModal (REQ-4,6,7,8,9,10,11)

### Phase 40: Restaurante Delivery — 인터넷 주문 접수 · 배차 · 수금 통제

**Goal:** 식당모드(`use_restaurant_mode`) 매장의 인터넷 배달 주문 라이프사이클 통제. 직원이 WhatsApp·전화·배달앱(PedidosYa/Rappi) 주문을 내부 콘솔로 접수 → 주방(comanda) → 라이더 배차 → 배달 → **수금 → 정산 마감**까지. 핵심 원칙: *배달 완료 ≠ 주문 종료* — 음식이 나가도 돈이 정산(conciliado)되기 전까지 열린 주문으로 통제. 현금 contra entrega 는 라이더가 현장 수금 후 카하 정산까지 미수금 추적.

**핵심 설계 방향 (brainstorming 2026-06-16):** C안 — 신규 delivery 레이어 + 기존 `Sale` 백본 재사용. 소매용 `online-orders`(택배·운송장) 는 도메인이 달라 재사용하지 않음. 금전·품목·재고·comanda·MercadoPago QR·caja(box)·clients(CRM) 인프라는 전부 재사용. 신규 엔티티 3개: `Repartidor`(라이더), `RestaurantDelivery`(주문상태·주소·tipo·canal·라이더 FK, Sale 1:1), `RiderSettlement`(현금 정산 마감). 식당모드 살롱 옆 "Delivery" 탭으로 추가, mesa ↔ delivery 가 같은 Sale 위에서 동작.

**범위 (합의):** 화면 4개 = (1) 설정>Repartidores 카드(식당모드 on일 때만), (2) 주문 접수 모달(Delivery/Para llevar), (3) 배차 보드 칸반(Nuevo→En cocina→Listo→En camino→Por cobrar + Conciliación), (4) 라이더 정산(현금 마감→카하 입금). 수금: MP QR = webhook 자동 확인(기존 재사용), 현금 = 라이더 교대 정산, 배달앱 = **L1 정산 CSV 대조**(주문 수동 입력 + payout CSV 업로드 자동 매칭 + 불일치 표시).

**범위 밖 (별도 Phase 후보):** 고객용 공개 추적 링크, 배달앱 L2 완전 API 양방향 연동, 라이더 모바일 전용 화면, GPS 위치추적, 외상(fiado) 배달.

**Depends on:** Phase 39 (식당모드 salón/mesa/comanda/결제), Phase 29 (MercadoPago QR + webhook), Phase 34 (Client WhatsApp+CRM), 기존 box(caja)/print-agent/sales 모듈.

**UI hint:** yes (Repartidores 설정 카드 + 주문 접수 모달 + 배차 보드 칸반 + 라이더 정산 화면 — 목업 brainstorming 2026-06-16 완료)

**설계 문서:** docs/superpowers/specs/2026-06-16-restaurant-delivery-design.md

**Success Criteria** (what must be TRUE): 라이더 등록/비활성(이력 보존) · Delivery/Takeaway 단일TX 접수(Sale source=delivery + RestaurantDelivery 1:1) + comanda · 칸반 보드(Nuevo·En cocina·Listo·En camino·Por cobrar + Conciliación) 실시간 Socket.io · 라이더 미배정 시 En camino 차단 · 현금 Entregado→Por cobrar 잔류 → 라이더 정산 "Registrar rendición"→caja movement+Liquidado · QR=webhook 자동 종료(Por cobrar 미경유) · 배달앱 payout CSV externalRef 정확매칭 자동 Conciliado+불일치 빨강 · delivery sale 매출 보고서 자동 반영 · 소매 무회귀. (40-SPEC.md AC lock 완료)

**Requirements:** REQ-1 (Repartidor 엔티티), REQ-2 (RestaurantDelivery Sale 1:1), REQ-3 (RiderSettlement), REQ-4 (SaleSource 'delivery'), REQ-5 (주문 접수 콘솔), REQ-6 (배차 보드 칸반), REQ-7 (Por cobrar 통제 + 라이더 정산→caja), REQ-8 (MP QR 자동 수금), REQ-9 (배달앱 L1 CSV 대조). (40-SPEC.md lock 완료)

**Plans:** 5/8 plans executed
- [x] 40-01-PLAN.md — DB foundation: 4 idempotent migrations (repartidores/restaurant_deliveries/rider_settlements + sales.source CHECK 'delivery')
- [x] 40-02-PLAN.md — Repartidor backend module (store-scoped CRUD + soft-deactivate)
- [x] 40-03-PLAN.md — RestaurantDelivery model + /restaurant Socket.io gateway (JWT auth, branch room)
- [x] 40-04-PLAN.md — RestaurantDelivery service (intake TX, transitions, Entregado→PAID, cancel) + controller + module
- [x] 40-05-PLAN.md — RiderSettlement module (build + rendición→caja box movement, caja-required guard)
- [ ] 40-06-PLAN.md — Payout CSV reconcile (MinIO + externalRef exact match) + MP QR webhook auto-close
- [ ] 40-07-PLAN.md — Frontend: SWR hooks + Repartidores config card (mode-gated) + Nuevo pedido modal
- [ ] 40-08-PLAN.md — Frontend: dispatch board kanban (Socket.io) + rider settlement view + CSV upload + Delivery tab wiring + UAT
