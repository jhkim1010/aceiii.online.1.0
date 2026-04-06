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
**Plans**: 4 plans

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
**Plans**: 4 plans

Plans:
- [x] 08-01-PLAN.md — Wave 1: Hook controlled-mode refactor (15 useXxxReport + xxxDefaultParams exports)
- [x] 08-02-PLAN.md — Wave 2: Body extraction pattern (15 XxxReportBody.tsx + thin wrappers, zero regression)
- [ ] 08-03-PLAN.md — Wave 3: Shell MVP (registry 16, reportsV2Slice, ReportsShell/Sidebar/Topbar/Params/Preview, [[...slug]].tsx, 3 reports embedded)
- [ ] 08-04-PLAN.md — Wave 4: Full embed (13 remaining reports + favorites/recents + Topbar wire)

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
**Plans**: 4 plans

Plans:
- [ ] 09-01-PLAN.md — DB 마이그레이션 + 기존 데이터 백필 (lifecycle_state 외 5개 컬럼)
- [ ] 09-02-PLAN.md — 백엔드 상태 머신 + Lifecycle API + Cron 재작성 (배치 쿼리)
- [ ] 09-03-PLAN.md — 프론트엔드 Tiendas 통합 뷰 + KPI + 탭 + 상세 페이지 이관 + Registros 제거
- [ ] 09-04-PLAN.md — Session Guard 강화 + Trial 만료 알림 이메일 + 감사 로그

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. UI 토글 메커니즘 | v1.1 | 1/2 | In Progress|  |
| 2. 마켓플레이스 & 재판매자 | v1.1 | 0/2 | Not started | - |
| 3. AI 채팅 고도화 | v1.1 | 0/2 | Not started | - |
| 4. 새 UI/UX 디자인 | v1.1 | 0/3 | Not started | - |
| 5. 레거시 데이터 임포트 | v1.1 | 1/3 | In Progress | - |
| 6. Reportajes | v1.1 | 0/4 | In Progress (VS Code) | - |
| 7. Fábrica | v1.1 | 0/4 | Not started | - |
| 8. Reportajes UX Redesign | v1.1 | 0/3 | Not started | - |
| 9. Store Lifecycle & Admin IA | v1.1 | 0/4 | Not started | - |
