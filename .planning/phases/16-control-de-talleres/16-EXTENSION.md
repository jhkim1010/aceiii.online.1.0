# Phase 16 Extension — CMT Professional MVP (Wave 5-8)

**Gathered:** 2026-04-20
**Status:** Ready for planning (new waves)
**Source:** `docs/taller-control-roadmap.md` (Zedonk / AIMS 360 / Apparel Magic 벤치마크)
**Mode:** Extension — 기존 Phase 16 (4 Wave, 2026-04-13 완료) 위에 CMT 전문 기능 4 Wave 추가

---

## 1. 현황 분석 — 이미 완성된 기능 vs 보강 필요

### 1.1 ✅ 이미 완성된 기능 (Phase 16 Wave 1-4 + Phase 17)

| 영역 | 산출물 | 완료 Phase |
|------|--------|-----------|
| DB 모델 | `talleres_vendors`, `_etapas`, `_vendor_etapas`, `_lotes`, `_envios`, `_recepciones`, `_envio_materiales`, `_orders`, `_payments`, `_settlements`, `_defects`, `_deliveries`, `_material_issues` (13 테이블) | 16 Wave 1-3 |
| Dashboard 통합 API | `GET /api/talleres/dashboard` (KPI + 최근 활동) | 16 Wave 1 |
| 탭 Shell | `TalleresMainView` 단일 진입점 + 7 탭 | 16 Wave 1 |
| Pipeline Kanban | etapa별 컬럼 + EtapaFlow 원형 노드 (**읽기 전용**) | 16 Wave 2 |
| Talleres 탭 확장 행 | Vendor 목록 + inline 편집 | 16 Wave 3 |
| Lotes 탭 + 420px 드로어 | Lote 상세 + 자식 envíos | 16 Wave 3 |
| Envios 탭 | Envío 목록 CRUD | 16 Wave 3 |
| Liquidaciones 탭 | Settlement KPI + 테이블 | 16 Wave 4 |
| Etapas 탭 | 단가 매트릭스 (vendor × etapa) | 16 Wave 4 |
| PIN hash migration | `pin_hash`, `pin_updated_at` 컬럼 (운영 적용 확인 ✅) | Phase 17 |
| Vendor Portal (Flutter) | 독립 모바일 앱 — 로그인, envíos, recepciones, notificaciones, settlements | Phase 17 |

### 1.2 ⚠️ 부분 완성 — 보강 필요

| 영역 | 현재 상태 | 필요 확장 |
|------|----------|----------|
| Kanban | 읽기 전용 시각화만 (D-04) | **healthStatus 3-level 세마포로** (ON_TRACK/AT_RISK/LATE) + 드래그 우선순위 |
| Recepción | 단순 `receivedQuantity` + `rejectedQuantity` 숫자만 | **구조화 QC** — 결함 코드/심각도/조치/사진 |
| Settlement | 수동 생성 (사용자가 직접 테이블 입력) | **자동 생성** `generateForPeriod(vendorId, from, to)` |
| VendorEtapa | 단일 `unitPrice` (덮어쓰기) | **historización** `effectiveFrom/effectiveTo` |
| 알림 | ad-hoc notifications (Phase 17에서 시작) | **cron 08:00 지연 envío 자동 알림** |

### 1.3 ❌ 완전히 누락 — 신규 구현 필요

| 영역 | 비고 |
|------|------|
| `talleres_qc_items` 테이블 | QC 라인 (recepcion_id, defect_code, severity, action, photo) |
| `talleres_defect_codes` 테이블 | 결함 코드 카탈로그 (store별 관리) |
| Auto-rework envío 생성 | QC action=REWORK → child envío 자동 생성 |
| Vendor Scorecard | `defectRate`, `onTimeRate`, `reworkRate` 90일 집계 |
| Envío `priority` 필드 | 드래그 순서 영구 저장 |
| Envío `healthStatus` 계산 | 가상 컬럼 또는 서비스 레이어 집계 |
| Settlement state machine | DRAFT → CONFIRMED (불변 처리) |
| Settlement PDF 출력 | 기존 DOCX 템플릿 또는 jsPDF |
| Talleres Dashboard (차트) | donut (ON_TRACK/AT_RISK/LATE), bar (top vendors), line (defect rate), stacked (backlog) |
| Excel 내보내기 | xlsx skill 활용 |
| 성능 인덱스 | `(vendor_id, status, due_date)`, `(envio_id, recepcion_date)`, `(vendor_id, period_start, period_end)` |
| 사용자 매뉴얼 | `docs/manuales/talleres.md` (스페인어) |

---

## 2. 설계 원칙 — roadmap 문서 채택

다음 5가지 원칙을 Wave 5-8 전반에 적용:

1. **한 유닛은 한 번에 한 etapa에만** — 상태 원자성
2. **Envío(bundle)가 작업 단위** — 개별 prenda 단위 추적 미채택 (Fase 2+ deferred)
3. **Vendor 지불 감액은 반드시 문서 + 사유 기록** — 감사 추적
4. **Vendor는 본인 데이터만** — 최소 권한 원칙 (Phase 17 이미 적용, 웹 포털도 동일)
5. **조기 경보 > 사후 보고** — 세마포 UI, cron 알림, 수동 리포트 최소화

---

## 3. Wave 5-8 계획 (Phase 16 확장)

### Wave 5 — Kanban Semáforo + Priority (5~7일)

**Goal:** 한눈에 어떤 lote가 어느 taller/etapa에 있고 지연 여부를 파악. 사용자가 우선순위를 드래그로 조정.

**Backend:**
- `talleres_envios.priority INTEGER DEFAULT 0` 컬럼 추가 (migration)
- Service 레이어에 `computeHealthStatus(envio)` 함수 — `dueDate` 기준 3단계
  - `ON_TRACK`: dueDate ≥ 오늘 + 2일
  - `AT_RISK`: dueDate ∈ [오늘, 오늘+2일)
  - `LATE`: dueDate < 오늘 AND pendingQuantity > 0
- 신규 엔드포인트 `GET /api/talleres/control/kanban?branchId=X`
  - 응답: `{ etapas: [...], enviosByEtapa: { [etapaId]: [envios...] } }`
  - **MemoryCache 30s** (`MemoryCacheService`)
  - 각 envío에 `healthStatus`, `priority`, `vendor`, `lote`, `pendingQuantity` 포함
- `PATCH /api/talleres/envios/:id/priority` — priority 값만 업데이트

**Frontend:**
- `TalleresControlPanel` → 신규 "Kanban" 서브뷰 (Pipeline 탭 내부 서브토글 or 별도 탭)
- 컬럼 = etapas (order 정렬), 카드 = 활성 envíos
- 카드에 semáforo 배지 (녹색/노랑/빨강)
- @dnd-kit 또는 react-beautiful-dnd 기반 컬럼 내 드래그 (같은 etapa 안에서만 순서 조정)
- 필터: vendor, producto, "sólo LATE"
- React.memo 적용 (고트래픽 리스트)

**Criteria:**
1. Kanban 렌더링 P95 ≤ 500ms (메모리 캐시 작동)
2. 드래그 순서 변경 즉시 반영 + DB 저장
3. 지연 envío에 빨간 배지 확실히 표시
4. 필터 변경 시 리렌더링 ≤ 200ms

---

### Wave 6 — QC 구조화 + Rework 자동화 (7~10일)

**Goal:** 수령 시 결함을 구조화해 기록. 재작업 필요 시 envío 자동 생성. 벤더 성과 지표 산출.

**DB Migration:**
- `talleres_defect_codes` (카탈로그)
  ```sql
  id SERIAL PK, code VARCHAR(40), label VARCHAR(200),
  severity_default VARCHAR(20), store_id INT NOT NULL, is_active BOOLEAN
  ```
  - Seed: `COSTURA_ABIERTA`, `MANCHA`, `TALLA_INCORRECTA`, `FALTA_ACCESORIO`, `COLOR_DIFERENTE`, `DEFECTO_TELA`, `DIMENSIONES_FUERA_ESPEC`, `ACABADO_POBRE`
- `talleres_qc_items` (recepción 라인)
  ```sql
  id SERIAL PK, recepcion_id FK, defect_code_id FK (nullable for "otro"),
  defect_custom_text VARCHAR(255), quantity INT,
  severity VARCHAR(20) CHECK (MINOR/MAJOR/CRITICAL),
  action VARCHAR(20) CHECK (ACCEPT/REWORK/SCRAP/CLAIM),
  photo_url VARCHAR(500), notes TEXT, created_at TIMESTAMPTZ
  ```

**Backend:**
- `POST /api/talleres/recepciones` 확장 — `qcItems[]` 배열 수용
- 비즈니스 규칙:
  - `action=REWORK` → `SubconEnvioService`가 자동으로 child envío 생성 (`sourceRecepcionId` 체인)
  - `action=SCRAP` → `talleres_lotes.available_quantity` 차감 + 로스 기록
  - `action=CLAIM` → `SubconDefect` 생성 (`deductionAmount` = quantity × unitPrice)
- `GET /api/talleres/vendors/:id/scorecard?days=90`
  - `defectRate = Σ qc_quantity / Σ received_quantity`
  - `onTimeRate = envíos 제때 완료 / 전체 완료`
  - `reworkRate = REWORK action 수 / 전체 recepciones`
- MinIO 업로드: 폴더 구조 `talleres/qc/{storeId}/{recepcionId}/{filename}`

**Frontend:**
- `ReceptionModal` 확장 — QC 테이블 편집 가능 (code 드롭다운, quantity, severity, action, 사진 업로드)
- 클라이언트 사이드 이미지 리사이즈 (max 1280px) 후 업로드
- `DefectsListView` 확장 — 사진 썸네일 컬럼 + `defect_code` 필터
- `VendorDetailPanel` 신규 Scorecard 섹션 (3 KPI + 트렌드 sparkline)

**Criteria:**
1. QC 5개 항목 포함한 recepción 저장 < 3초
2. REWORK 시 child envío 자동 생성 + source 체인 유지
3. 사진 업로드 성공률 ≥ 99% (3회 재시도)
4. Scorecard 90일 데이터 조회 < 500ms

---

### Wave 7 — Tarifa Historización + Auto-liquidación (7~10일)

**Goal:** 벤더별 단가 변경 이력 추적. 특정 기간 liquidación 자동 생성. DRAFT→CONFIRMED 상태머신.

**DB Migration:**
- `talleres_vendor_etapas` 확장
  ```sql
  ADD COLUMN effective_from DATE NOT NULL DEFAULT CURRENT_DATE,
  ADD COLUMN effective_to DATE NULL,
  ADD CONSTRAINT chk_period CHECK (effective_to IS NULL OR effective_to > effective_from);
  CREATE INDEX idx_vendor_etapa_active
    ON talleres_vendor_etapas (vendor_id, etapa_id, effective_from)
    WHERE effective_to IS NULL;
  ```
  - Backfill: 기존 행은 `effective_from = created_at::date`, `effective_to = NULL`
- `talleres_settlements` 확장
  ```sql
  ADD COLUMN status VARCHAR(20) DEFAULT 'DRAFT'
    CHECK (status IN ('DRAFT','CONFIRMED','PAID','CANCELLED')),
  ADD COLUMN confirmed_at TIMESTAMPTZ NULL,
  ADD COLUMN confirmed_by INT NULL REFERENCES users(id);
  ```

**Backend:**
- `VendorEtapaService.setRate(vendorId, etapaId, unitPrice, effectiveFrom)`
  - 이전 active 행의 `effective_to = effectiveFrom - 1일` 설정
  - 신규 row INSERT
  - 트랜잭션 + FOR UPDATE 락
- `SubconSettlementService.generateForPeriod(vendorId, periodStart, periodEnd)` 신규 구현
  - 기간 내 모든 `Recepcion` 조회 (net qty = received - rejected)
  - 각 recepción의 date 기준 vigente `VendorEtapa` 단가 적용
  - `SubconDefect.deductionAmount` 동기간 차감
  - DRAFT Settlement + 상세 lines bulkCreate
  - idempotent (같은 vendor + period 재호출 시 기존 DRAFT 업데이트)
- `POST /api/talleres/settlements/draft` + `POST /:id/confirm`
- PDF 생성 — 기존 DOCX 템플릿 또는 jsPDF

**Frontend:**
- `LiquidacionesTab`에 "Generar borrador" 버튼 (vendor + 기간 선택)
- 상세 뷰: 라인별 (envío → recepción → etapa → qty × unitPrice - deductions)
- "Confirmar" 버튼 — CONFIRMED 후 편집 UI 비활성화
- PDF 다운로드

**Criteria:**
1. 3개월치 liquidación draft 생성 < 5초 (100+ recepciones)
2. 같은 vendor+period 재호출 시 중복 DRAFT 생성 없음
3. CONFIRMED 상태 → 편집 API 모두 400 반환
4. PDF에 CUIT/expedidor/vendor 정보 정확 표시

---

### Wave 8 — Alertas + Dashboard + Polish (5~7일)

**Goal:** Kanban을 정보에서 행동으로 — cron 알림, 집계 차트, Excel, 운영 배포 준비.

**Backend:**
- `@nestjs/schedule` cron `0 8 * * *` (매일 08:00 local)
  - `LATE` envíos 스캔 → 각 branch owner에게 notification 생성
  - Phase 17 vendor_notifications 테이블 + FCM 재활용
- 인덱스 추가:
  ```sql
  CREATE INDEX idx_envios_vendor_status_due ON talleres_envios(vendor_id, status, due_date);
  CREATE INDEX idx_recepciones_envio_date ON talleres_recepciones(envio_id, recepcion_date);
  CREATE INDEX idx_settlements_vendor_period ON talleres_settlements(vendor_id, period_start, period_end);
  ```
- `GET /api/talleres/dashboard-v2` — 집계 엔드포인트
  - `enviosByStatus` (ON_TRACK/AT_RISK/LATE count)
  - `topVendors` (volume 상위 5, 최근 30일)
  - `defectRateTrend` (12주 주간)
  - `backlogByEtapa` (etapa별 pendingQuantity)
  - **MemoryCache 60s**

**Frontend:**
- `DashboardTab` 리디자인
  - Donut: envíos by status
  - Bar: top 5 vendors volume
  - Line: defect rate 12주 추이
  - Stacked bar: backlog by etapa
- Excel 내보내기 버튼 (모든 리스트 탭) — 현재 필터 유지
- 로딩 상태 + 빈 상태 UI 통일

**배포 + 문서:**
- 운영 migrations 적용 (`talleres_qc_items`, `talleres_defect_codes`, `priority`, vendor_etapa 컬럼, settlements 컬럼, 인덱스)
- `docs/manuales/talleres.md` — 스페인어 사용자 매뉴얼 (목차: Kanban, QC, Liquidación, Portal)
- 1개 taller 파일럿 (실데이터 투입)
- 소스 서버 smoke test: 500 로그 0건 유지 24h

**Criteria:**
1. Cron 08:00 실행 시 LATE envío 수만큼 notification 생성 확인
2. Dashboard 4 차트 모두 P95 ≤ 800ms
3. 3개 인덱스 운영 적용 + EXPLAIN ANALYZE 로 사용 확인
4. 매뉴얼 스페인어 검증 + 파일럿 taller 피드백 반영

---

## 4. 위험 요소 및 완화 (`docs/taller-control-roadmap.md § 6` 에서 발췌)

| 위험 | 영향 | 완화 |
|------|------|------|
| Kanban N+1 쿼리 | 중 — 느림 | 30s cache + `include` 명시 + 복합 인덱스 |
| Draft 계산 오류 | 상 — 법적 문제 | DRAFT/CONFIRMED 상태머신 + 단위 테스트 (`generateForPeriod`) |
| QC 사진 MinIO 포화 | 하 | 클라이언트 리사이즈 1280px + 2년 보존 정책 |
| Pool 낭비 (settlement 생성) | 상 | 단일 트랜잭션 + `bulkCreate` + Promise.all 읽기 |
| PG10 ↔ PG15 문법 차이 | 중 | 모든 마이그레이션 PG10 호환 작성 (GENERATED AS IDENTITY 금지) |

---

## 5. 예상 일정 — 총 24~34일 (4~5주)

| Wave | 기간 | 완료일 목표 |
|------|------|------------|
| Wave 5 | 5~7일 | 2026-04-27 |
| Wave 6 | 7~10일 | 2026-05-07 |
| Wave 7 | 7~10일 | 2026-05-17 |
| Wave 8 | 5~7일 | 2026-05-24 |

---

## 6. 의존성

- **Phase 14** (CASL permissions) — `talleres_qc_admin`, `talleres_settlement_confirm` 신규 function slug 추가 필요
- **Phase 17** (Vendor Portal Flutter) — FCM 인프라 재활용 (Wave 8 cron 알림)
- **Phase 19** (Performance 300ms) — 인덱스 설계 기준 참조 (사이드 이득)
- **운영 DB (PG10)** — 모든 신규 마이그레이션 PG10 문법 호환 필수
- **MinIO** — Wave 6 사진 업로드 저장소 (기존 인프라 재사용)

---

## 7. 다음 액션 제안

1. 이 확장안 승인 후 `/gsd-plan-phase 16 --from-wave 5` 로 Wave 5 PLAN.md 생성
2. 또는 Wave별로 독립 실행: `/gsd-plan-phase 16 --wave 5`, `--wave 6`, ...
3. 대안: 새 Phase 25로 분리 ("Control de Talleres — CMT Professional") — Phase 16 완료 상태 유지

---

*Source doc: docs/taller-control-roadmap.md — Marcos + Claude, 2026-04-20*
