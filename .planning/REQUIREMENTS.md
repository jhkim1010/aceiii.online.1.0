# Requirements: Ventago POS/ERP

**Defined:** 2026-04-01
**Core Value:** 매장 운영자가 POS 판매부터 재고/재무/외주까지 하나의 플랫폼에서 관리

## v1 Requirements (Validated)

### POS / 판매

- [x] **POS-01**: POS 화면에서 상품 검색/추가/결제 처리
- [x] **POS-02**: 판매 내역 조회 및 상세 보기
- [x] **POS-03**: 다양한 결제수단 지원
- [x] **POS-04**: 할인 적용

### 상품 / 재고

- [x] **PROD-01**: 상품 CRUD (카테고리, 가격, 이미지)
- [x] **PROD-02**: 재고 관리 및 추적
- [x] **PROD-03**: 가격 관리 (precios)

### 인증 / 보안

- [x] **AUTH-01**: JWT 기반 로그인/로그아웃
- [x] **AUTH-02**: CASL 기반 역할/권한 관리
- [x] **AUTH-03**: 세션 보안 (유저당 1세션, 중복로그인 차단)
- [x] **AUTH-04**: 디바이스 fingerprint + IP 기반 터미널/지점 자동 등록
- [x] **AUTH-05**: 비밀번호 재설정

### 매장 / 조직

- [x] **STORE-01**: 매장 관리 (로고 업로드 포함)
- [x] **STORE-02**: 지점(Branch) 관리 — 기본 Box/Terminal 자동 생성
- [x] **STORE-03**: 금전함(Box) 운영
- [x] **STORE-04**: 금고(Caja Fuerte) 관리
- [x] **STORE-05**: 사용자 관리 (역할: superadmin, admin, gerente, vendedor)

### 재무

- [x] **FIN-01**: 비용(Gastos) 등록 및 관리
- [x] **FIN-02**: 금전함 통제 (control-de-caja)
- [x] **FIN-03**: 보고서 (매출/재고/아이템)

### 생산 / 외주

- [x] **MFG-01**: 생산 관리 (BOM, 작업지시)
- [x] **SUB-01**: 외주 납품업체 관리
- [x] **SUB-02**: 외주 발주/검수/정산

### 인프라

- [x] **INFRA-01**: MinIO 파일 업로드 통합
- [x] **INFRA-02**: Socket.io 실시간 통신
- [x] **INFRA-03**: Jenkins CI/CD + Docker 배포

## v1.1 Requirements (Active)

### UI 토글 인프라

- [x] **TOGGLE-01**: UI/UX 토글 메커니즘 (사이드바 체크박스 + DB 저장 + 조건부 렌더링 인프라)

### UI/UX 개선 (토글 ON 시 적용)

- [ ] **UX-01**: 로그인 화면 세련화
- [ ] **UX-02**: 대시보드 개선 및 주요 지표 시각화
- [ ] **UX-03**: 전반적 UI 일관성 및 반응형 개선

### 기능 확장

- [ ] **FEAT-01**: 마켓플레이스 기능 강화
- [ ] **FEAT-02**: 재판매자(Revendedor) 포털 완성
- [ ] **FEAT-03**: AI 채팅 (Knowledge base) 고도화

## Out of Scope

| Feature | Reason |
|---------|--------|
| 모바일 네이티브 앱 | 웹 PWA 우선, 네이티브는 차후 검토 |
| 다국어(i18n) 지원 | 현재 스페인어 단일 운영 |
| App Router 마이그레이션 | 안정성 우선, 대규모 변경 리스크 |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| TOGGLE-01 | Phase 1 | In Progress |
| FEAT-01 | Phase 2 | Pending |
| FEAT-02 | Phase 2 | Pending |
| FEAT-03 | Phase 3 | Pending |
| UX-01 | Phase 4 | Pending |
| UX-02 | Phase 4 | Pending |
| UX-03 | Phase 4 | Pending |

**Coverage:**
- v1 requirements: 22 total (all validated)
- v1.1 requirements: 7 total (TOGGLE-01 추가)
- Mapped to phases: 7
- Unmapped: 0

---
*Requirements defined: 2026-04-01*
*Last updated: 2026-04-05 — Phase 1 재구성 (UI 토글), Phase 4 추가 (새 UI/UX)*
