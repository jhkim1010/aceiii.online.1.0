# Phase 25: Clientes globales compartidos entre tiendas (historial aislado) + Importación masiva — Context

**Gathered:** 2026-04-23
**Status:** Ready for planning

<domain>
## Phase Boundary

같은 owner 그룹에 속한 여러 tienda 가 고객 **기본정보**(nombre, document, email, teléfono, dirección, provincia, localidad, note)를 공유하되, **구입 이력**(sales, sale_items, pagos, discounts, saldos_credito, preferencias)은 storeId 기준으로 절대 교차 조회 불가.

**공유 대상 제약:** DNI 또는 CUIT 가 있는 고객만 global pool 진입. document 없는 고객은 local (legacy `clients` 테이블) scope.

**기능 범위:** ClienteView 상단에 "Importación masiva" 버튼 추가 → 기존 `/clientes-globales/carga-masiva` 페이지로 라우팅 → CSV/Excel 업로드 → 컬럼 매핑 → DNI/CUIT 검증 + 체크섬 → preview (행별 Global/Local/Skip 버킷 chip) → 트랜잭션 커밋 → 실패행 리포트.

**범위 제외:** 새로운 capabilities 추가 금지. 기존 `GlobalClient`/`StoreClient` 모델 및 `CargaMasivaClientesView.tsx` 재사용.

</domain>

<decisions>
## Implementation Decisions

### Area 1 — DNI/CUIT 필수성 정책

- **D1-01:** DNI/CUIT 없는 고객은 **legacy `clients` 테이블 (local)** 에만 저장. GlobalClient 생성 불가. 기존 `GlobalClient` 의 `fullname+phone` partial unique 인덱스는 제거 또는 의미 변경 (global pool 진입 차단 정책과 상충)
- **D1-02:** DNI 또는 CUIT **둘 중 하나만 있어도 OK** + 형식 검증:
  - DNI: AR 7~8 자리 숫자
  - CUIT: AR 11 자리 숫자 + mod 11 체크섬 검증
- **D1-03:** 로컬 고객에 나중에 DNI/CUIT 추가 시 **자동 Global 승격** + 동일 document 가 그룹 내 다른 tienda 에 존재하면 **merge 제안 모달** 표시
- **D1-04:** Merge 충돌 (이름/주소 등 필드 다름) 해결: **필드별 선택 UI** — 양쪽 값 연출 + 사용자가 필드마다 체크박스로 최종값 선택
- **D1-05:** `GlobalClient.document` UNIQUE 제약은 `(ownerGroupId, document)` 로 강화 — 다른 owner 그룹 간 동일 document 허용 (완전 격리된 pool)

### Area 2 — 기존 Clients 테이블 마이그레이션

- **D2-01:** sales FK 는 **`sales.storeClientId`** 신규 컬럼으로 전환. 신규 sales 는 항상 StoreClient 를 참조. 기존 `sales.clientId` (legacy) 는 호환성 위해 유지하나 신규 쓰기 경로에서 사용 중단
- **D2-02:** 기존 legacy `clients` 데이터 중 **`document NOT NULL` 이고 DNI/CUIT 형식 검증 통과** 한 레코드만 GlobalClient 로 일회성 bulk 마이그레이션 + StoreClient 생성 + 해당 store 의 과거 sales.storeClientId 재매핑
- **D2-03:** `document IS NULL` 또는 형식 오류 레코드는 legacy `clients` 테이블에 그대로 유지 — `local_clients` 로 간주. 기존 `Clients` Sequelize 모델 코드는 **그대로 유지** (rename 없음). 신규 sales 생성 경로만 StoreClient 우선, 폴백으로 local clients
- **D2-04:** 마이그레이션 실행 시점 = **Phase 25 Wave 1 초기** (schema 변경 + 데이터 이관이 가장 먼저). 이후 모든 Wave 는 신규 구조 위에서 작성

### Area 3 — Owner 그룹 경계

- **D3-01:** `stores.ownerGroupId INTEGER NOT NULL` 컬럼 추가. `GlobalClient.ownerGroupId` 도 추가. UNIQUE = `(ownerGroupId, document)`
- **D3-02:** 기존 운영 매장 (CART=3, coolsistema=6, genius=8, ACE=9) 은 초기 마이그레이션에서 **모두 동일 ownerGroupId = 1** 로 설정 — 실제 소유 분리는 superadmin 이 추후 UI 에서 조정
- **D3-03:** 신규 매장 생성 시 기본 동작 = **매번 새 ownerGroupId 자동 생성** (1매장 = 1그룹). 추후 superadmin 이 병합 가능
- **D3-04:** Owner 경계 위반 시도 (다른 ownerGroup 의 GlobalClient 접근) = **HTTP 403 Forbidden** + `audit_logs` 에 시도 기록 (userId, IP, endpoint, targetClientId)

### Area 4 — Import UX (CargaMasiva) 개선

- **D4-01:** "Importación masiva" 진입점 = **ClienteView 상단 버튼**. 클릭 시 기존 `/clientes-globales/carga-masiva` 페이지로 라우팅. 메뉴 바에 별도 항목 추가 안 함 (중복 진입점 회피)
- **D4-02:** Preview 행 시각화 = **색상 chip + 버킷 표시**. 각 행 끝에 `[Global]` (파랑) / `[Local]` (회색) / `[Skip]` (빨강) chip. 오류 행은 배경 옅은 빨강. 칩 클릭으로 필터 가능
- **D4-03:** DNI/CUIT 없는 행 기본 처리 = **사용자 선택 라디오 버튼** (업로드 시작 전): `[Local 저장]` (기본) / `[Skip]`. 행별 오버라이드 가능
- **D4-04:** 기존 Global 고객 중복 발견 시 기본 동작 = **"link to current tienda only"** — Global 레코드 그대로 + 현재 tienda 의 StoreClient 연결만 추가. 행별 오버라이드: `skip` / `update basic info`
- **D4-05:** Import 는 **트랜잭션 단위** — 전체 성공 또는 부분 커밋 (행별 상태 리포트). 실패행 다운로드 = CSV 에 `row_index`, `error_code`, `error_message` 컬럼 포함
- **D4-06:** Audit log (`client_imports` 테이블) — userId, storeId, fileName, totalRows, createdCount, updatedCount, skippedCount, errorCount, executedAt

### Claude's Discretion

- 구체적인 UI 라이브러리 패턴 (MUI Stepper 단계 수, chip 색상 정확한 hex) — 기존 CargaMasivaClientesView 컨벤션 따름
- DNI/CUIT 정규식 세부 (선행 0 허용 여부 등) — AR 공식 규칙 따라 결정
- 403 vs 404 선택 — 현재 403 채택했으나 leak 방지 필요하면 researcher 가 AR 법적 요건 확인 후 조정 가능
- audit_logs 테이블 스키마 확장 — 기존 audit_logs 구조에 맞게 합체
- CSV/Excel 파일 최대 크기 (10MB 제시했으나 성능 관점 재검토 가능)
- Promotion 자동 트리거 지점 — POS 고객 편집 화면 저장 시점 vs 별도 "Promote" 버튼 — UX 연구 후 결정

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing architecture (must read to avoid duplicate work)

- `api-ventago/src/app/shared/global-clients/global-clients.model.ts` — 기존 GlobalClient 모델 (document unique, fullname+phone partial unique 제거 필요)
- `api-ventago/src/app/shared/store-clients/store-clients.model.ts` — StoreClient 모델 (storeId 스코프 비공개 데이터 — balance, creditLimit, note, internalCode)
- `api-ventago/src/app/shared/shared.module.ts` — 공유 모듈 조합
- `api-ventago/src/app/global-clients/` — 레거시 HTTP endpoint (shared/ 로 마이그레이션 예정 여부 확인)
- `api-ventago/src/app/global-clients/GLOBAL_CLIENTS_README.md` — 설계 문서 (document unique 정책 등 기존 결정)
- `api-ventago/src/app/clients/clients.model.ts` — legacy Clients (storeId scoped) — 유지 대상
- `api-ventago/src/app/sales/sales.model.ts` — sales.clientId → Clients FK (storeClientId 신규 컬럼 추가 대상)
- `api-ventago/src/app/marketplace/public-purchase/public-purchase.service.ts` — 이미 GlobalClient 사용 패턴 (findOrCreateGlobalClient) — 참조 구현

### Frontend (재사용 대상)

- `ventago-app/src/views/clientes-globales/GlobalClientesView.tsx` — 조회/편집 뷰 (570 lines)
- `ventago-app/src/views/clientes-globales/CargaMasivaClientesView.tsx` — 대량 업로드 Stepper (570 lines) — 신규 정책 적용 대상
- `ventago-app/src/pages/clientes-globales/index.tsx` — 페이지 래퍼
- `ventago-app/src/pages/clientes-globales/carga-masiva/index.tsx` — import 페이지 라우트
- ClienteView 파일 경로 (POS 내 고객 계정 관리) — researcher 가 찾아야 함 (`ventago-app/src/views/clientes/` 또는 `ventago-app/src/views/clients/` 후보)

### Security / auth

- `api-ventago/src/app/session/` — SessionGuard 기존 패턴 (owner scope guard 추가 방식 참조)
- `api-ventago/src/common/` — 공통 guards/decorators 디렉토리 (scope guard 신규 추가 위치)
- `ventago-app/src/configs/casl.ts` — CASL 정의 (신규 `manage-clientes-import` 권한 추가 대상)

### Library / parser

- `ventago-app/src/views/clientes-globales/CargaMasivaClientesView.tsx` 내 papaparse + xlsx 사용 패턴 — 재사용

### Project instructions

- `./CLAUDE.md` — 프로젝트 특이사항 (PG10 vs PG15 호환성, `underscored: true` Sequelize snake_case 매핑, `apiConnector.remove()` 등)
- `.planning/STATE.md` — Phase 14 CASL 권한, Phase 21 Store Baseline 의존성

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **GlobalClient + StoreClient 모델** — 데이터 모델 이미 존재. Phase 25 는 정책/제약 강화 + ownerGroupId 컬럼 추가 + 레거시 이관
- **CargaMasivaClientesView** (570 lines, Stepper 기반) — 파일 업로드, 컬럼 매핑, preview 로직 이미 존재. 신규 정책 적용 + merge UI + 체크섬 검증 추가
- **GlobalClientesView** — 조회/편집 UI 이미 존재 — ownerGroup 필터 및 promotion 트리거 연동만 필요
- **public-purchase.service.ts** `findOrCreateGlobalClient` — marketplace 에서 이미 GlobalClient upsert 패턴 구현 — 참조 가능
- **papaparse + xlsx** — CSV/Excel 파싱 라이브러리 이미 로드되어 있음
- **SessionGuard** 패턴 — 공용 guard 로 ownerGroup 경계 체크 확장

### Established Patterns

- Sequelize `underscored: true` 전역 설정 — 모델 camelCase → DB snake_case 자동 매핑. `ownerGroupId` → `owner_group_id`
- API 엔드포인트는 `kebab-case` (`/global-clients`, `/clientes-globales/carga-masiva`)
- Migration SQL 은 `api-ventago/migrations/` 폴더 + 운영서버 Docker 에서 직접 실행
- PG10 (운영) 과 PG15 (dev Docker) 문법 호환성 주의 — `GENERATED AS IDENTITY` 등 신규 기능 제한
- CASL 권한은 `ventago-app/src/configs/casl.ts` + 백엔드 `@UseGuards` + `@Permissions()` 데코레이터 조합
- Audit log 는 기존 `audit_logs` 테이블 사용 (Phase 14 와 연결)
- SWR 훅 (`src/hooks/api/use*`) 로 참조 데이터 캐싱 — GlobalClient 조회도 SWR 전환 여지

### Integration Points

- **ClienteView 상단 툴바** — "Importación masiva" 버튼 삽입 지점 (정확 파일 경로는 researcher 가 확인)
- **POS 판매 화면 고객 선택** — 드롭다운/검색은 ownerGroup 내 GlobalClient + 현재 tienda 의 local Clients 합집합 조회
- **Store 생성 폼** — ownerGroupId 필드 추가 (superadmin 용) + 자동 할당 로직 연동
- **Migration 실행 순서** — Wave 1: `stores.ownerGroupId` 추가 → 기존 4매장 ownerGroupId=1 설정 → `global_clients.ownerGroupId` 추가 → UNIQUE 재구성 → legacy clients 데이터 이관
- **DB indexes** — `global_clients(owner_group_id, document) UNIQUE` WHERE document IS NOT NULL

</code_context>

<specifics>
## Specific Ideas

- **"내 모든 고객들" 해석** — 사용자는 "내가 가진 모든 매장들 사이의 고객" 의미. ownerGroup 단위 = 사용자 본인 매장 묶음
- **구입목록 공유 절대 불가** — 이는 법적/영업적으로 중요한 요구. 모든 sales/reports/analytics 엔드포인트에 client_id 스코프 체크 추가 (현재 tienda 의 StoreClient 또는 local Client 만 조회 가능)
- **DNI/CUIT 없는 막 생성된 고객 공유 불필요** — 사용자 명시 ("Consumidor Final" 류). 이들은 legacy `clients` 테이블에 그대로 유지
- **기존 CargaMasivaClientesView 570 lines 재활용** — scratch 에서 재작성하지 않고 정책/검증/UI 개선만 덧붙이기

</specifics>

<deferred>
## Deferred Ideas

- **Global 고객 통합 검색 (여러 tienda 에서 동일 DNI 고객 활동 요약)** — 구입목록 공유 금지 요구와 충돌 가능. 별도 phase 에서 "anonymous aggregate" 방식 검토
- **Promotion/Merge 자동화 워크플로우 고도화** — 대량 로컬→글로벌 승격 배치, 주기적 merge 제안 등. Phase 25 는 수동 + 단건 merge 만 다룸
- **Delete/Deactivate 정책** — 글로벌 레코드 삭제 시 타 tienda 영향. 현재는 isActive 플래그로 soft delete 만, 완전 삭제는 별도 phase
- **Cross-phase client analytics** — 다른 owner group 고객과 비교/벤치마크 — 정책적으로 불가, 검토 금지
- **비어있는 글로벌 레코드 청소 cron** — StoreClient 연결 0개인 GlobalClient 자동 정리 — 별도 유지보수 phase
- **다른 owner 그룹 고객 이관 (M&A 시 매장 소유권 이전)** — 별도 phase (데이터 프라이버시 법 검토 필요)

### Reviewed Todos (not folded)

None — no pending todos matched Phase 25 scope.

</deferred>

---

*Phase: 25-clientes-globales-compartidos-entre-tiendas-historial-aislad*
*Context gathered: 2026-04-23*
