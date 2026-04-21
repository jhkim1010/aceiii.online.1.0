# Phase 16 Extension — CMT Professional MVP (Wave 5-10)

**Gathered:** 2026-04-20
**Last updated:** 2026-04-20 (Zedonk mockup canonical 반영)
**Status:** Ready for planning (new waves)
**Source:**
- `docs/taller-control-roadmap.md` — Zedonk / AIMS 360 / Apparel Magic 기능 벤치마크
- **`docs/zedonk-style-taller-mockup.html` — ★★★ CANONICAL UI REFERENCE** (5 탭: Overview / Cut Ticket / WIP / Cost Sheet / Kanban)
**Mode:** Extension — 기존 Phase 16 (4 Wave, 2026-04-13 완료) 위에 CMT 전문 기능 6 Wave 추가 (Wave 5-10)

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

## 2.5. Zedonk Mockup Canonical (UI 규약)

**Canonical 파일:** `docs/zedonk-style-taller-mockup.html` — 모든 Wave 5-10 UI 구현의 기준.

### 2.5.1 색상 토큰 (모든 Wave 공통)

`ventago-app/src/views/talleres/theme/zedonkTheme.ts` 신규 파일에 중앙화:

```ts
export const TALLERES_THEME = {
  primary:    '#1a1a2e',  // 네이비 - header / tab.active / button primary
  secondary:  '#f5a623',  // 골드 - accent / tab text / h2 앞 수직바
  gradient:   'linear-gradient(135deg, #1a1a2e 0%, #2d2d5f 100%)',
  bg:         '#f4f5f7',
  bgSoft:     '#fafbfd',
  text:       '#1a1a2e',
  textMuted:  '#6b6b8c',
  textLight:  '#8b8ba7',
  border:     '#d5d7e0',
  borderSoft: '#eceef3',
  status: {
    ontrack: { bg: '#e8f5e9', text: '#2e7d32', dot: '#4caf50' },
    atrisk:  { bg: '#fff8e1', text: '#f57c00', dot: '#ff9800' },
    late:    { bg: '#ffebee', text: '#c62828', dot: '#f44336' },
    done:    { bg: '#e3f2fd', text: '#1565c0', dot: '#2196f3' },
  },
  card: { radius: 10, shadow: '0 1px 3px rgba(0,0,0,0.05)' },
  hint: { bg: '#fff8e7', border: '#f5a623', text: '#6b4a00' },
}
```

### 2.5.2 컴포넌트 규약

- **Card h2**: 앞에 `gold 4px × 18px` 수직바 (`::before`)
- **Status Badge**: dot + 3px halo shadow `rgba(color, 0.2)`, uppercase 11px, letter-spacing 0.3px
- **Kanban Card**: `border-left: 3px solid {status.dot}`, hover 시 `translateY(-1px)` + 그림자 강화
- **Table th**: uppercase, letter-spacing 0.5px, 11px, `textMuted` 색
- **숫자 셀**: `font-family: 'Menlo', monospace`
- **Hint box**: 노란 배경 + 골드 3px left border, 💡 아이콘
- **Filter chip**: `active=primary+secondary`, 14px radius
- **Summary card**: 상단 3px 색상바 (status별 border-top), 28px monospace 수치

### 2.5.3 탭 구성 (TalleresMainView 재구성)

기존 7탭 → **신규 5탭 + 기존 운영 탭 2** 로 재구성:

| # | 탭 | 기반 Wave | 상태 |
|---|---|---|------|
| 1 | 📊 **Overview** | Wave 8 리디자인 | 기존 Dashboard 확장 |
| 2 | ✂️ **Cut Ticket** | **Wave 9 신규** | 신규 구축 |
| 3 | 🔄 **공정 WIP** | Wave 2 + Wave 5 확장 | Pipeline 대체 |
| 4 | 💰 **Cost Sheet** | **Wave 10 신규** | 신규 구축 |
| 5 | 📋 **Kanban** | Wave 5 | 신규 구축 |
| 6 | Talleres (Vendors) | 기존 Wave 3 | 스타일 업데이트만 |
| 7 | Liquidaciones | 기존 Wave 4 + Wave 7 | 자동 생성 추가 |

*Etapas 탭(단가 매트릭스, Wave 4)은 설정 메뉴로 이동. Lotes 탭은 Cut Ticket에 흡수.*

---

## 3. Wave 5-10 계획 (Phase 16 확장)

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

### Wave 9 — Cut Ticket System (8~12일)

**Goal:** Zedonk 재단 지시서 개념 도입. 각 Lote = 하나의 Cut Ticket = 하나의 PDF. 재단실 벽에 붙일 수 있는 단일 진실 원천.

**DB Migration:**
- `talleres_lotes` 확장 (PG10 호환):
  ```sql
  ALTER TABLE talleres_lotes
    ADD COLUMN IF NOT EXISTS cut_ticket_number VARCHAR(40),
    ADD COLUMN IF NOT EXISTS style_code VARCHAR(60),
    ADD COLUMN IF NOT EXISTS season VARCHAR(40),
    ADD COLUMN IF NOT EXISTS cut_date DATE,
    ADD COLUMN IF NOT EXISTS size_color_matrix JSONB,
    ADD COLUMN IF NOT EXISTS bom_snapshot JSONB,
    ADD COLUMN IF NOT EXISTS routing_path JSONB,
    ADD CONSTRAINT uq_cut_ticket_store UNIQUE (store_id, cut_ticket_number);

  -- 매장별 연도별 시퀀스용 테이블 (PG10 호환, sequence 대신)
  CREATE TABLE IF NOT EXISTS talleres_cut_ticket_counters (
    store_id INT NOT NULL,
    year SMALLINT NOT NULL,
    last_seq INT NOT NULL DEFAULT 0,
    PRIMARY KEY (store_id, year)
  );

  CREATE INDEX IF NOT EXISTS idx_lotes_cut_ticket
    ON talleres_lotes(store_id, cut_ticket_number);
  ```

**JSONB 스키마:**
- `size_color_matrix`:
  ```json
  {
    "colors": [{"id": 19, "name": "Negro", "hex": "#000000"}],
    "sizes": [{"id": 14, "name": "M"}],
    "qty": {"19": {"14": 30}}
  }
  ```
- `bom_snapshot`:
  ```json
  [{"materialId": 7, "name": "Seda Principal",
    "unitConsumption": 2.1, "unit": "m",
    "totalConsumption": 325.5,
    "unitPrice": 8.00, "subtotal": 2604.00,
    "stockStatus": "SUFFICIENT|LOW|OUT"}]
  ```
- `routing_path`:
  ```json
  [{"order": 1, "etapaId": 3, "etapaName": "Corte", "vendorId": null, "vendorName": "In-house"},
   {"order": 2, "etapaId": 4, "etapaName": "Confección", "vendorId": 12, "vendorName": "Taller Sofía"}]
  ```

**Backend:**
- `SubconLoteService.generateCutTicket(loteId, storeId)`:
  - 트랜잭션 내 `cut_ticket_counters` UPDATE ... RETURNING (FOR UPDATE 락)
  - 포맷: `CT-${year}-${String(seq).padStart(3, '0')}` → 예: `CT-2026-025`
  - 현재 자재가 + routing 스냅샷 생성
- `GET /api/talleres/lotes/:id/cut-ticket` — JSON 반환 (매트릭스 + BOM + routing + meta)
- `GET /api/talleres/lotes/:id/cut-ticket/pdf` — PDF 출력
  - puppeteer 또는 기존 DOCX 템플릿 스킬
  - 재단실 벽 부착용 A4 가로 레이아웃 (헤더 + 매트릭스 + BOM + routing + QR코드)
- `PATCH /api/talleres/lotes/:id/size-color-matrix` — 편집 (단, `cut_date != NULL` 이면 400)

**Frontend (탭 ✂️ Cut Ticket):**
- `CutTicketTab.tsx` — 탭 컨테이너
- `CutTicketHeader.tsx` — 8 필드 그리드 (번호/스타일/시즌/발행일/납기일/재단/봉제/총수량)
  - border-left 4px gold, bgSoft background
- `SizeColorMatrixEditor.tsx` — 편집 가능한 매트릭스
  - 행: product의 color variants
  - 열: product의 size variants
  - 셀: `<input type="number">` (50px 너비, 중앙 정렬)
  - 자동 행/열/전체 합계 재계산 (React state + useMemo)
  - `cut_date != NULL` 이면 read-only
- `BomTable.tsx` — 자재 명세 테이블 (재고 상태 배지: SUFFICIENT/LOW/OUT)
- `RoutingFlow.tsx` — 5단계 공정 카드 (기존 EtapaFlow 재사용)
- `📄 PDF 출력 (재단실용)` 버튼 (primary 네이비+골드)

**Criteria:**
1. 새 Lote 생성 시 `cut_ticket_number` 자동 발급, 매장+연도 범위 내 중복 없음
2. 매트릭스 편집 시 행/열 합계 실시간 재계산 (60fps)
3. PDF 출력 클릭 시 A4 PDF 다운로드 < 3초
4. 재단 시작(`cut_date` 세팅) 후 매트릭스 편집 API 400 반환

---

### Wave 10 — Cost Sheet (6~8일)

**Goal:** Zedonk Cost Sheet — 스타일 제작 전 마진 시뮬레이션. 목표 마진 미달 시 즉시 경고.

**DB Migration:**
```sql
CREATE TABLE IF NOT EXISTS style_cost_sheets (
  id SERIAL PRIMARY KEY,
  product_id INT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  store_id INT NOT NULL,
  currency CHAR(3) NOT NULL DEFAULT 'USD',
  retail_price NUMERIC(12,2),
  target_margin_pct NUMERIC(5,2) NOT NULL DEFAULT 50,
  overhead_pct NUMERIC(5,2) NOT NULL DEFAULT 11.3,
  shipping_cost_per_lote NUMERIC(12,2) NOT NULL DEFAULT 200,
  lote_size_default INT NOT NULL DEFAULT 155,
  material_cost NUMERIC(12,2),
  cmt_cost NUMERIC(12,2),
  overhead_cost NUMERIC(12,2),
  total_cost NUMERIC(12,2),
  margin_amount NUMERIC(12,2),
  margin_pct NUMERIC(5,2),
  calc_snapshot JSONB,
  last_calculated_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_cost_product_store UNIQUE (product_id, store_id)
);
CREATE INDEX idx_cost_sheets_store ON style_cost_sheets(store_id);
```

**Backend:**
- `StyleCostSheetService.compute(productId, storeId, opts?)`:
  1. **자재비** = Σ (BOM.unitConsumption × material.currentPrice) per unit
     - product의 BOM은 `production/materials/` 모듈에서 조회
  2. **CMT** = Σ (routing.etapas의 `talleres_vendor_etapas.unitPrice` 현재 활성)
  3. **간접비** = (material + cmt) × overheadPct + (shippingPerLote / loteSize)
  4. **총원가** = material + cmt + overhead
  5. **마진** = retailPrice - totalCost
  6. **마진율** = margin / retailPrice × 100
  7. 결과 → `style_cost_sheets` UPSERT + `calc_snapshot` 에 계산 상세 JSON 보관
- `POST /api/talleres/cost-sheets/:productId/calculate` — 재계산 트리거
- `GET /api/talleres/cost-sheets/:productId` — 최신 cost sheet + snapshot
- `PATCH /api/talleres/cost-sheets/:productId` — retail_price / target_margin_pct / overhead_pct 편집

**Frontend (탭 💰 Cost Sheet):**
- `CostSheetTab.tsx` — 탭 컨테이너
- `CostSheetTable.tsx` — 섹션별 테이블 (2fr : 1fr grid)
  - Section headers (네이비 배경 + 골드 텍스트): Materiales / CMT / Overhead
  - Subtotal rows (bgSoft)
  - Grand total (gold 배경)
  - Margin row (초록 배경 `#e8f5e9` + text `#2e7d32`)
- `MarginCard.tsx` — 네이비 gradient 배경, 골드 큰 숫자 (%)
  - 마진율 달성 → 초록 체크 `✓ 목표 마진 달성`
  - 마진율 미달 → 빨간 경고 `⚠️ 목표 마진 미달`
  - 로트 총 마진 = retailPrice × loteSize - totalCost × loteSize
- 편집 폼: retail_price, target_margin_pct, overhead_pct 수정 시 자동 재계산 (debounce 500ms)

**Criteria:**
1. 계산 API P95 ≤ 400ms (BOM 5항목 + CMT 5단계 기준)
2. 마진 미달 시 MarginCard가 빨간 경고 스타일로 변경
3. retail_price 편집 후 500ms 내 자동 재계산
4. `calc_snapshot` JSONB 에 계산 시점 모든 단가 보관 (단가 변경 시 이전 값 추적 가능)

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

## 5. 예상 일정 — 총 38~54일 (7~8주)

| Wave | 내용 | 기간 | 완료일 목표 |
|------|------|------|------------|
| Wave 5 | Kanban Semáforo + Priority (Zedonk 테마) | 5~7일 | 2026-04-27 |
| Wave 6 | QC 구조화 + Rework 자동화 | 7~10일 | 2026-05-07 |
| Wave 7 | Tarifa Historización + Auto-liquidación | 7~10일 | 2026-05-17 |
| Wave 8 | Alertas + Overview Dashboard (Zedonk 테마) + Polish | 5~7일 | 2026-05-24 |
| **Wave 9** | **Cut Ticket System (신규, Zedonk 핵심)** | **8~12일** | **2026-06-05** |
| **Wave 10** | **Cost Sheet (신규, Zedonk 핵심)** | **6~8일** | **2026-06-13** |

**Wave 의존성:**
- Wave 5 → 6 → 7: 순차
- Wave 8: 5/6/7 이후 (Dashboard 집계 지표가 이들에 의존)
- Wave 9: Wave 5 (테마 토큰) + 기존 Wave 3 Lotes 모델 확장
- Wave 10: Wave 9 (BOM 스냅샷 구조 재사용) + Wave 7 (단가 historización)

---

## 6. 의존성

- **Phase 14** (CASL permissions) — `talleres_qc_admin`, `talleres_settlement_confirm`, `talleres_cut_ticket_edit`, `talleres_cost_sheet_edit` 신규 function slug
- **Phase 17** (Vendor Portal Flutter) — FCM 인프라 재활용 (Wave 8 cron 알림)
- **Phase 19** (Performance 300ms) — 인덱스 설계 기준 참조
- **운영 DB (PG10)** — 모든 신규 마이그레이션 PG10 문법 호환 필수 (sequence 대신 counter 테이블 패턴)
- **MinIO** — Wave 6 사진 업로드 + Wave 9 PDF 캐시 저장소
- **Puppeteer 또는 DOCX 템플릿 스킬** — Wave 9 Cut Ticket PDF 출력
- **production/materials 모듈** — Wave 10 Cost Sheet 의 BOM 데이터 소스

---

## 7. 다음 액션 제안

1. 이 확장안 승인 후 `/gsd-plan-phase 16 --from-wave 5` 로 Wave 5 PLAN.md 생성
2. 또는 Wave별로 독립 실행: `/gsd-plan-phase 16 --wave 5`, `--wave 6`, ...
3. 대안: 새 Phase 25로 분리 ("Control de Talleres — CMT Professional") — Phase 16 완료 상태 유지

---

*Source doc: docs/taller-control-roadmap.md — Marcos + Claude, 2026-04-20*
