# Phase 25: Clientes globales compartidos — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-23
**Phase:** 25-clientes-globales-compartidos-entre-tiendas-historial-aislad
**Areas discussed:** DNI/CUIT 필수성 정책, 기존 Clients 테이블 마이그레이션, Owner 그룹 경계, Import UX (CargaMasiva)

---

## DNI/CUIT 필수성 정책

| Option | Description | Selected |
|--------|-------------|----------|
| Local Clients 테이블에만 | 기존 `clients` 테이블을 로컬전용으로 남겨 storeId 스코프로만 저장. GlobalClient 는 DNI/CUIT 반드시 있어야 생성 가능 | ✓ |
| GlobalClient 에 두되 플래그로 구분 | GlobalClient 테이블 하나에 `isGlobal` boolean 추가 | |
| 거부 — 저장 불가 | POS 에서 DNI/CUIT 없이 고객 등록 시도하면 차단 | |

**User's choice:** Local Clients 테이블에만 (Recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| 둘 중 하나만 있으면 OK + 체크섬 검증 | DNI (7~8 digits) 또는 CUIT (11 digits mod 11) 중 하나만 있으면 global 에 진입 | ✓ |
| CUIT 만 인정 (법인 중심) | B2B 위주 사업이라면 CUIT 만 필수 | |
| 둘 다 있어야 상승격 | DNI+CUIT 모두 있어야 global 로 보존 | |

**User's choice:** 둘 중 하나만 있으면 OK + 체크섬 검증 (Recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| 자동 글로벌로 승격 + merge 제안 UI | 로컬 레코드에 document 추가 시 Global 로 자동 promote + merge 모달 | ✓ |
| 라디오 버튼으로 수동 승격 | 자동 promote 안함, 사용자 수동 클릭 | |
| 승격 없이 복사 | 로컬/글로벌 두 레코드 공존 | |

**User's choice:** 자동 글로벌로 승격 + merge 제안 UI (Recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| 필드별 선택 UI | 양쪽 값 연출 + 사용자가 필드마다 체크박스로 선택 | ✓ |
| Global 우선 (신뢰) | 기존 Global 레코드 값 유지 | |
| 최신 updatedAt 우선 | 두 레코드 중 updatedAt 이 최신인 값 선택 | |

**User's choice:** 필드별 선택 UI (Recommended)

---

## 기존 Clients 테이블 마이그레이션

| Option | Description | Selected |
|--------|-------------|----------|
| sales.storeClientId 로 전환 | sales 가 항상 StoreClient 참조 — 로컬/글로벌 통일 접근 | ✓ |
| Dual FK: localClientId XOR globalStoreClientId | sales 에 두 개 nullable FK | |
| legacy clients 테이블 완전 통합 | `clients` → `local_clients` rename + polymorphic FK | |

**User's choice:** sales.storeClientId 로 전환 (Recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| document 있는 레코드 자동 GlobalClient 상승격 + StoreClient 연결 | 기존 clients 중 document NOT NULL 자동 이관 | ✓ (사용자가 "오직 DNI, CUIT이 분명한 것만 globalclient 로 옮겨줘" 명시) |
| 기존 데이터 마이그레이션 안함 — 신규만 | 신구 분리 | |
| 매장별 dry-run 리포트 후 수동 상승격 | admin UI 에서 검토 후 승인 | |

**User's choice:** document 있는 레코드 자동 GlobalClient 상승격 (사용자 명시: "오직 DNI, CUIT이 분명한 것만")

---

| Option | Description | Selected |
|--------|-------------|----------|
| 유지하되 @deprecated 마크 + 난열 rename | `Clients` → `LocalClients` 클래스명 변경 + @deprecated | |
| 모델 제거 + 모든 호출부 전환 | Phase 25 에서 `Clients` 전수 제거 | |
| 그대로 유지 + 신규 sales 에서만 StoreClient 사용 | legacy 와 신규 공존 | ✓ |

**User's choice:** 그대로 유지 + 신규 sales 에서만 StoreClient 사용

---

| Option | Description | Selected |
|--------|-------------|----------|
| Phase 25 Wave 1 초기 | 스키마 변경 + 데이터 이관 먼저, 이후 모든 Wave 는 신규 구조 | ✓ |
| Import 기능 완성 후 성화 | import UI/API 먼저, 마지막 Wave 에서 migration | |

**User's choice:** Phase 25 Wave 1 초기 (Recommended)

---

## Owner 그룹 경계

| Option | Description | Selected |
|--------|-------------|----------|
| `stores.ownerGroupId` 추가 | stores + global_clients 에 ownerGroupId. UNIQUE (ownerGroupId, document) | ✓ |
| `owner_groups` 테이블 + FK | 별도 테이블로 구조화 | |
| stores.ownerUserId — 사용자 직접 묶음 | 같은 ownerUserId 가진 매장끼리 공유 | |

**User's choice:** `stores.ownerGroupId` 추가 (Recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| 모든 기존 매장 = 동일 owner | CART, coolsistema, genius, ACE 를 동일 ownerGroupId=1 | ✓ |
| 각 매장 = 독립 owner | 4개 매장 각각 다른 ownerGroup | |
| 직접 매핑을 지정 | 사용자가 명시적 매핑 제공 | |

**User's choice:** 모든 기존 매장 = 동일 owner (Recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| 생성 파라메터에 ownerGroupId 필수 입력 | 신규 매장 추가 폼에 드롭다운 | |
| 기본값 "신규 그룹" 생성 | 신규 매장 = 새 ownerGroup 자동 (1매장=1그룹) | ✓ |

**User's choice:** 기본값 "신규 그룹" 생성

---

| Option | Description | Selected |
|--------|-------------|----------|
| 403 Forbidden + audit 기록 | 타 ownerGroup 접근 시도 시 명시적 차단 + 감사 | ✓ |
| 404 Not Found (leak 방지) | 존재 자체를 숨김 | |

**User's choice:** 403 Forbidden + audit 기록 (Recommended)

---

## Import UX (CargaMasiva)

| Option | Description | Selected |
|--------|-------------|----------|
| ClienteView 상단 버튼 + 기존 /carga-masiva 재사용 | POS 내 ClienteView 툴바에 버튼 → 기존 페이지 라우트 | ✓ |
| ClienteView 내 모달로 직접 표시 | Dialog 로 오픈 | |
| 메뉴 바에 별도 항목 추가 | Clientes 아래 서브메뉴 | |

**User's choice:** ClienteView 의 상단 버튼 + 현재 /clientes-globales/carga-masiva 재사용 (Recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| 색상 chip + 대상 버킷 표시 | 행 끝 [Global]/[Local]/[Skip] chip | ✓ |
| 탭으로 분류 표시 | 3탭 분리 | |
| 미시각적 상태 컬럼 | 텍스트만 | |

**User's choice:** 색상 칩 + 대상 버킷 표시 (Recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| 사용자 선택 (기본 = Local 저장) | 라디오 버튼 업로드 전 선택, 기본 Local | ✓ |
| 무조건 skip | DNI/CUIT 없는 행 자동 스킵 | |
| 무조건 Local 저장 | DNI/CUIT 없는 행도 자동 Local | |

**User's choice:** 사용자 선택 (기본 = Local 저장) (Recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| link to current tienda only | Global 레코드 유지 + StoreClient 연결만 추가 | ✓ |
| update basic info | CSV 값으로 Global 레코드 덮어쓰기 | |
| skip | 이미 있으면 건너뜀 | |

**User's choice:** link to current tienda only (Recommended)

---

## Claude's Discretion

- MUI Stepper 단계 수, chip 색상 hex (기존 CargaMasivaClientesView 컨벤션)
- DNI/CUIT 정규식 세부 (AR 공식 규칙)
- 403 vs 404 법적 요건 검토는 researcher 확인
- audit_logs 테이블 스키마 확장 세부
- CSV/Excel 최대 크기 (10MB 기준 제시)
- Promotion 자동 트리거 지점 (POS 편집 저장 vs 별도 버튼)

## Deferred Ideas

- Global 고객 통합 검색 (여러 tienda aggregate)
- Promotion/Merge 자동화 워크플로우 고도화
- Delete/Deactivate 정책
- Cross-phase client analytics (정책상 불가)
- 비어있는 Global 레코드 청소 cron
- M&A 시 매장 소유권 이전
