# 외주업체(Taller) 컨트롤 시스템 로드맵 (CMT 외주관리)
## Ventago POS/ERP — MVP 4~6주

**작성일:** 2026-04-20
**작성자:** Marcos (Claude 보조)
**대상 범위:** `api-ventago/src/app/subcon/*` 및 `ventago-app/src/views/talleres/*`
**목표:** 외주업체(CMT 서브콘) 관리 수준을 단순 "거래 기록"에서 "실무 운영 가능" 수준으로 끌어올린다. Zedonk, AIMS 360, Apparel Magic을 벤치마크로 삼되, 시스템을 무겁게 만들지 않는다.

---

## 1. 현재 상황

### 1.1 기존 데이터 모델

`subcon/` 모듈은 CMT(Cut-Make-Trim) 흐름의 기초를 이미 갖추고 있습니다.

| 테이블 | 역할 | 비고 |
|---|---|---|
| `talleres_vendors` | 외주업체 마스터 | `pinHash`(포털용), rating 0-5, `settlementTerms`(자유 텍스트) |
| `talleres_etapas` | 공정 단계 (재단, 봉제, 다림질…) | 매장별 정의 가능 |
| `talleres_vendor_etapas` | 업체↔공정 M:N + `unitPrice` | 업체/공정별 단가표 |
| `talleres_lotes` | `productId` 기준 생산 로트 | 발송 시 `availableQuantity` 감소 |
| `talleres_envios` | 특정 업체·공정으로 물리적 발송 | `pendingQuantity`, `sourceRecepcionId`(연쇄 가능) |
| `talleres_recepciones` | 발송 건의 수령/반환 | `receivedQuantity` + `rejectedQuantity` |
| `talleres_envio_materiales` | 발송 시 함께 지급한 자재 | 창고 소비량 |
| `talleres_orders` | 전체 주문 (레거시) | REQUESTED→IN_PROGRESS→DELIVERED→SETTLED |
| `talleres_deliveries` / `talleres_defects` | 납품·불량 (레거시) | — |
| `talleres_settlements` / `talleres_payments` | 정산·지급 | `SubconSettlement`/`SubconPayment` |

### 1.2 기존 프론트엔드

`ventago-app/src/views/talleres/` 하위:
- `TalleresMainView` (탭 허브)
- `vendors`, `etapas`, `lotes`, `envios`, `pedidos`, `deliveries`, `defects`, `liquidaciones`
- `control/talleres_ControlPanel.tsx` (통합 패널)
- SWR 훅: `useTalleresEtapas`, `useTalleresVendors`, `useTalleresEnvios`

### 1.3 `2026-04-20` 로그에서 발견된 문제

```
column "pin_hash" does not exist
  → GET /api/talleres/vendors/all (500)
  → POST /api/talleres/vendors (500)
```

벤더 포털용 `pin_hash` 필드의 **마이그레이션이 현재 환경에 적용되지 않은 상태**입니다. 모델에는 선언되어 있지만 테이블에는 없습니다. **새 작업 시작 전에 반드시 해결되어야 합니다.**

로그의 다른 에러(`product_branches`, `use_variants`, `s.store_id` ungrouped 등)는 `talleres/` 도메인은 아니지만 같은 안정화 작업 차수에 포함하는 것이 좋습니다.

---

## 2. 벤치마크 — 실제 참조 시스템

의류/패션 제조업 선도 업체들의 외주(CMT) 관리 방식을 정리하되, **MVP에 적용 가능한 부분만** 선별합니다.

### 2.1 Zedonk (영국 부티크, 디자이너 브랜드)
- **Cut Tickets**: 로트별 재단 지시서 — 사이즈/컬러 매트릭스, 자재 소비량, 배정 업체, 납기일.
- **공정별 WIP**: 각 유닛마다 공정별 상태(재단→봉제→마감→QC→입고) 추적.
- **스타일별 Cost Sheet**: CMT + 자재 + 간접비 분해, 마진 자동 계산.
- **납기 알람 3단계**: 정상 / 위험(≤48시간) / 지연.

### 2.2 AIMS 360 (미국 중형 의류 제조)
- **Contractor Portal**: 각 업체가 PIN으로 접속, 자기 주문만 조회, 유닛별 "시작/진행/완료" 체크.
- **Bundle Tracking**: 발송 단위를 `BUNDLE-YYYY-NNN` 코드로 묶고 출고/입고 시 스캔.
- **Penalty Rules**: 업체별 설정 — 지연 일수당 %할인, 불량 벌크당 %공제.

### 2.3 Apparel Magic
- **Cuts & Bundles 워크플로우**: 재단→번들 묶음→번들별 티켓→봉제→QC→창고. 번들마다 바코드 티켓 출력.
- **Pay Rate Grid**: 공정 단위 단가(칼라 봉제, 소매 부착, 단추구멍) → 합산 = 의류 단위 원가.
- **Claims / Chargebacks**: 업체 공제 기록 — 사유 + 증빙 파일 첨부.

### 2.4 **복사하지 않을** 것 (MVP엔 과함)
- 번들당 바코드 티켓 인쇄 → 별도 zebra-agent 연동 + 스캔 필요 (Fase 2+ 검토).
- 공정 원자 단위 Pay Rate Grid(칼라·소매·단추별) → 현재 `vendor_etapa.unitPrice` 수준이면 충분.
- EDI / 통관 연동.
- 내부 작업자 급여 모듈.

### 2.5 우리가 **채택할** 원칙
1. **한 유닛은 동시에 한 공정에만 존재한다** (원자적 상태).
2. **작업 단위는 발송(번들)**, 개별 의류가 아니다.
3. **벤더 지급 감액은 반드시 문서와 사유를 가진다** (감사 대응).
4. **업체는 자기 것만 본다** (포털 최소권한 원칙).
5. **조기 경보 > 사후 보고** — 수동 리스트가 아니라 날짜 신호등.

---

## 3. MVP 로드맵 — 4~6주

공격적 타임라인: **1주 = 1 웨이브** + 선행 Fase 0 필수.

### Fase 0 — 안정화 (3~5일, **블로킹**)

이게 끝나지 않으면 다음 단계로 넘어가지 않습니다. 2026-04-20 로그에서 바로 도출.

- [ ] `talleres_vendors` 테이블에 **`pin_hash` 마이그레이션**
  ```sql
  ALTER TABLE talleres_vendors
    ADD COLUMN IF NOT EXISTS pin_hash VARCHAR(255),
    ADD COLUMN IF NOT EXISTS pin_updated_at TIMESTAMP;
  ```
  로컬 + 운영(`srv803182`, `dbpostgres` 컨테이너)에 적용.
- [ ] 모듈 내 나머지 미적용 마이그레이션 확인 — `ventago` DB에 `list_migrations` 실행.
- [ ] 스모크 테스트: `GET /api/talleres/vendors/all`, `POST /api/talleres/vendors` → 200.
- [ ] `SubconModule`이 pool에 **추가 커넥션을 만들지 않는지** 검증 (기본 `sequelize` 사용, pool max=50 유지, 병렬 인스턴스 금지).

**산출물:** 24시간 동안 `talleres/*` 에러 로그 없음.

---

### Fase 1 — 상태 신호등 & 칸반 보드 (1주차)

**목표:** 한눈에 어떤 로트가 어느 업체·어느 공정에 있고, 납기가 위험한지 파악 가능.

#### 1.1 백엔드
- [ ] `envio.healthStatus` 계산 필드 (virtual 또는 집계 엔드포인트):
  - `ON_TRACK` — `dueDate` ≥ 오늘 + 2일
  - `AT_RISK` — `dueDate`가 오늘 ~ 오늘+2일 사이
  - `LATE` — `dueDate` < 오늘 이고 `pendingQuantity` > 0
- [ ] 엔드포인트 `GET /api/talleres/control/kanban?branchId=X`
  - 응답: `{ etapas: [...], envios: [...etapaId로 groupBy] }`
  - **30초 메모리 캐시** (`MemoryCacheService`) — 신규 pool 인덱스/커넥션 생성 금지.

#### 1.2 프론트엔드
- [ ] `talleres_ControlPanel.tsx` → **공정별 칸반**
  - 컬럼 = `etapas` (`order` 순)
  - 카드 = 활성 발송 + `vendor.name`, `lote.loteNumber`, `pendingQuantity`, 신호등 배지
  - **시각적** 드래그앤드롭(DB 이동 X) — 우선순위만 `envio.priority` (신규 `INTEGER DEFAULT 0`) 저장.
- [ ] 빠른 필터: `vendor`, `제품`, `지연 건만`.

**예상 공수:** 3~4일.
**선행 조건:** Fase 0만 완료되면 됨.

---

### Fase 2 — 품질관리 & Rework (2주차)

**목표:** 수령 시 단순 수량만 입력하지 말고 **구조화된 QC**를 기록한다.

#### 2.1 백엔드 — `recepciones` 확장
- [ ] 신규 테이블 `talleres_qc_items`
  ```
  id, recepcion_id, defect_code (FK), quantity,
  severity (MINOR|MAJOR|CRITICAL),
  action (ACCEPT|REWORK|SCRAP|CLAIM),
  photo_url (MinIO), notes
  ```
- [ ] 신규 테이블 `talleres_defect_codes` (매장별 카탈로그)
  - 시드 예시: `COSTURA_ABIERTA`(박음질 터짐), `MANCHA`(얼룩), `TALLA_INCORRECTA`(사이즈 오류), `FALTA_ACCESORIO`(부자재 누락), `COLOR_DIFERENTE`(색상 불일치).
- [ ] 엔드포인트 `POST /api/talleres/recepciones` — 동일 페이로드에 `qcItems[]` 포함.
- [ ] 비즈니스 규칙:
  - `action=REWORK` → 동일 업체·공정으로 `sourceRecepcionId`를 가진 자식 `Envio` 자동 생성.
  - `action=SCRAP` → `lote.availableQuantity`에서 차감 + 손실 기록.
  - `action=CLAIM` → 정산용 `SubconDefect`에 `deductionAmount`로 생성.

#### 2.2 프론트엔드
- [ ] 수령 모달에 QC 편집 가능 테이블(코드, 수량, 심각도, 사진) 추가.
- [ ] 사진 업로드는 MinIO (`MinioService.uploadFile`), 경로 `talleres/qc/{storeId}/{recepcionId}/`.
- [ ] `talleres_DefectsListView` → "사진" 컬럼 + `defect_code` 필터.
- [ ] `VendorDetailPanel`에 **업체별 스코어카드**:
  - `defectRate = Σ불량수량 / Σ수령수량` 최근 90일
  - `onTimeRate = 납기내 수령 / 전체`
  - `reworkRate`

**예상 공수:** 4~5일.

---

### Fase 3 — 단가/자동 정산 (3주차)

**목표:** 수령 기록에서 정산서가 자동 생성되고, 불량 공제가 즉시 반영된다.

#### 3.1 백엔드
- [ ] `VendorEtapa` 보강:
  - `effectiveFrom`, `effectiveTo` 추가 (단가 이력화).
  - 검증: 특정 시점 `(vendor, etapa)` 조합의 활성 단가는 1개만 존재.
- [ ] 서비스 `SubconSettlementService.generateForPeriod(vendorId, from, to)`
  - 기간 내 모든 `Recepcion.receivedQuantity - rejectedQuantity` 집계.
  - 수령일 기준 유효 `VendorEtapa.unitPrice` 곱셈.
  - 같은 기간 `SubconDefect.deductionAmount` 차감.
  - `SubconSettlement` 초안 + 라인 상세 반환.
- [ ] 엔드포인트 `POST /api/talleres/settlements/draft` — `(vendorId, periodStart, periodEnd)` 기준 idempotent.
- [ ] 엔드포인트 `POST /api/talleres/settlements/:id/confirm` — 편집 잠금, 상태 `CONFIRMED`.

#### 3.2 프론트엔드
- [ ] `talleres_LiquidacionesListView` → "초안 생성" 버튼 (업체 + 기간 선택).
- [ ] 정산 상세 화면: 라인별 드릴다운(발송 → 수령 → 공정 → 수량 × 단가).
- [ ] PDF 출력 (기존 DOCX→PDF 템플릿 재사용 또는 경량 jsPDF).

**예상 공수:** 4~5일.
**Pool 주의:** 초안 생성은 **단일 트랜잭션**에서 읽기 쿼리를 `Promise.all`로 병렬, 쓰기는 단일 `bulkCreate`로 라인 일괄 입력.

---

### Fase 4 — 벤더 포털 (4주차)

**목표:** 외주업체가 PIN으로 접속해 자기 발송을 조회/갱신 — WhatsApp 전화 없이 운영.

`vendor-portal` 모듈이 일부 존재 (`VendorPortalModule`, `pinHash`). 흐름 완성.

#### 4.1 백엔드
- [ ] `POST /api/vendor-portal/login` (vendorId + PIN) → 단기(4h) JWT, scope `vendor:{id}`.
- [ ] Guard `VendorScopeGuard` — 토큰의 `vendorId`로 모든 쿼리 필터.
- [ ] 최소 엔드포인트:
  - `GET /vendor-portal/envios` (자기 것, status ≠ COMPLETED)
  - `POST /vendor-portal/envios/:id/start` → `startedAt` 기록
  - `POST /vendor-portal/envios/:id/progress` → % 진행률 갱신
- [ ] **금지**: 벤더가 `unitPrice` 편집, 다른 업체 조회.

#### 4.2 프론트엔드
- [ ] 공개 페이지 `/vendor-portal/login` (Ventago 메인 레이아웃 외부).
- [ ] 경량 뷰: 발송 리스트, "시작 표시" 버튼, "% 진행률" 필드, 메모.
- [ ] **모바일 우선** — 업체들은 주로 휴대폰으로 접속.
- [ ] 신규 발송 시 Socket.io(namespace `/vendor-portal`) 실시간 알림.

**예상 공수:** 5일.

---

### Fase 5 — 알림/리포트/대시보드 (5주차, MVP 선택적)

**목표:** 칸반을 실행 가능한 정보로 전환.

- [ ] 일일 크론 08:00 (`@nestjs/schedule`) — 지연 발송 점검, 해당 `branchId` 오너에게 알림.
- [ ] 대시보드 `talleres/dashboard`:
  - 상태별 발송(ON_TRACK/AT_RISK/LATE) — 도넛.
  - 월간 Top 5 업체 (물량 기준) — 바.
  - 최근 12주 defect rate 추이 — 라인.
  - 공정별 백로그 — 스택 바.
- [ ] Excel 출력 (`xlsx` 스킬 사용) — 현재 필터의 발송 목록.

**예상 공수:** 3~4일.

---

### Fase 6 — 버퍼 & 마감 (6주차)

- [ ] 운영 반영 (`srv803182`), `list_migrations` 검증.
- [ ] 1~2개 업체 파일럿 실데이터 투입.
- [ ] 인덱스 점검:
  - `talleres_envios (vendor_id, status, due_date)`
  - `talleres_recepciones (envio_id, recepcion_date)`
  - `talleres_settlements (vendor_id, period_start, period_end)`
- [ ] N+1 쿼리 점검 (특히 칸반 — 일반적 병목 지점).
- [ ] 최종 사용자 문서 `docs/manuales/talleres.md` (스페인어).
- [ ] 사용자 교육 2회 (세션당 1시간).

---

## 4. 아키텍처 요약 (MVP 이후)

```
┌─────────────────────────────────────────────────────────────┐
│                    FRONTEND (ventago-app)                   │
│  ┌────────────┐  ┌────────────┐  ┌────────────────────┐     │
│  │  Kanban    │  │ 정산(초안) │  │ 벤더 포털          │     │
│  │  컨트롤    │  │            │  │ (모바일, PIN)      │     │
│  └─────┬──────┘  └─────┬──────┘  └─────────┬──────────┘     │
└────────┼────────────────┼───────────────────┼───────────────┘
         │ SWR 30초       │                   │ JWT 4h scope
         ▼                ▼                   ▼
┌─────────────────────────────────────────────────────────────┐
│                    BACKEND (api-ventago)                    │
│  /api/talleres/*          /api/vendor-portal/*              │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ EnvioService  RecepcionService  SettlementService     │  │
│  │ QcService     DefectCodeService VendorPortalService   │  │
│  └───────────────────┬───────────────────────────────────┘  │
│           MemoryCache (칸반 30초 / 참조데이터 60초)         │
└───────────────────────┬─────────────────────────────────────┘
                        │ pool max=50, 중복 금지
                        ▼
┌─────────────────────────────────────────────────────────────┐
│                   PostgreSQL 15 (ventago)                   │
│  talleres_vendors       talleres_etapas                     │
│  talleres_vendor_etapas talleres_lotes                      │
│  talleres_envios        talleres_recepciones                │
│  talleres_qc_items (신규)   talleres_defect_codes (신규)    │
│  talleres_settlements   talleres_payments                   │
└─────────────────────────────────────────────────────────────┘
```

---

## 5. 공통 규약 (모든 Fase 적용)

### 5.1 PostgreSQL — Pool
- **새 `Sequelize` 인스턴스 생성 금지**. `DatabaseModule`의 싱글톤 사용.
- 풀 **`max=50` 고정**, 변경 금지. 쿼리 포화 시 SQL 최적화 또는 캐시로 해결. **풀 증가 금지**.
- 트랜잭션: 반드시 `finally`에서 종료 (commit 또는 rollback). Fase 0에서 전수 감사.
- 칸반/대시보드의 모든 쿼리는 `MemoryCacheService` 경유 (TTL 30초).

### 5.2 Sequelize / 네이밍
- `underscored: true` 전역 설정. 모델 `camelCase` → DB `snake_case` (예: `dueDate` → `due_date`).
- 원시 SQL 마이그레이션은 `api-ventago/migrations/*.sql` — srv803182 Docker 컨테이너에서 실행.

### 5.3 프론트엔드 / 성능
- 참조 데이터에 `useEffect + apiConnector.get` **절대 금지**. `src/hooks/api/`에 SWR 훅 사용/신규 생성.
- `pageSize` 최대 50.
- 신규 talleres 뷰는 `next/dynamic({ ssr: false })`로 코드 스플릿.
- 칸반 카드 컴포넌트는 `React.memo` (렌더 트래픽 높음).

### 5.4 ESLint (빌드 차단)
- `return` 앞 빈 줄.
- `//` 주석 앞 빈 줄.
- 미사용 import 금지.

### 5.5 벤더 포털 보안
- PIN은 bcrypt (`saltRounds=10`).
- 벤더용 JWT ≠ 내부 사용자 JWT (다른 `secret` / `audience`).
- 로그인 감사 테이블 `vendor_portal_audit` (vendorId, ip, result, timestamp).

---

## 6. 리스크와 완화책

| 리스크 | 영향 | 완화책 |
|---|---|---|
| `pin_hash` 마이그레이션 운영 누락 (이미 발생) | 高 — 모듈 중단 | Fase 0 필수 + `IF NOT EXISTS` + `list_migrations` 검증 |
| 칸반 N+1 쿼리 | 中 — 눈에 띄는 지연 | 30초 캐시 + 명시적 eager `include` + `(vendor_id,status,due_date)` 인덱스 |
| 정산 초안 계산 오류 | 高 — 법적 분쟁 소지 | 상태 `DRAFT`→`CONFIRMED`, CONFIRMED 불변, `generateForPeriod` 단위 테스트 필수 |
| 벤더 포털 PIN 취약 | 中 — 사칭 위험 | PIN 최소 6자리, 15분당 5회 rate limit, 초과 시 락 |
| 벤더 포털 Socket.io로 인한 pool 증가 | 高 | 별도 namespace, `connect`에서 DB 쿼리 금지 (JWT 캐시 기반 인증만) |
| QC 사진으로 MinIO 포화 | 低~中 | 클라이언트에서 1280px로 리사이즈 후 업로드, 2년 보관 정책 |

---

## 7. 최종 산출물 (30~42일차)

1. 마이그레이션 SQL 적용 (`talleres_qc_items`, `talleres_defect_codes`, `vendors`/`envios` 신규 필드).
2. `api/talleres/*` 및 `api/vendor-portal/*` 신규 8~10개 엔드포인트.
3. 신규/개선 뷰 4종 (Kanban, QC 모달, 정산 상세, 벤더 포털).
4. SWR 훅 3종 (`useTalleresKanban`, `useTalleresQcCodes`, `useVendorScorecard`).
5. 사용자 매뉴얼 `docs/manuales/talleres.md`.
6. 마지막 주에 1개 파일럿 업체 실운영.

---

## 8. 대상 외 (제품 Fase 2+)

의식적으로 **뒤로 미룬 항목**들. 나중에 "왜 안 했지?"가 되지 않도록 명시.

- 번들별 바코드 (zebra-agent와 envios 통합 필요).
- 원자 공정 단위 단가 (칼라 봉제 vs 소매 부착 등).
- WhatsApp 통합 채팅 (현재는 포털 + 알림으로 대체).
- 정산 전자서명.
- `gastos/` 모듈과 회계 자동 연동.
- 업체별 생산능력(Capacity) 예측 (하루 몇 장 소화?).
- 벤더용 네이티브 모바일 앱 (포털 모바일 웹으로 MVP 충족).

---

## 9. 즉시 할 것 (이번 주)

1. **오늘** — 로컬에 `pin_hash` 마이그레이션 적용, `GET /api/talleres/vendors/all`가 200 응답하는지 확인.
2. **+1일** — srv803182에서 미적용 마이그레이션 인벤토리 (`list_migrations`).
3. **+2일** — Fase 1 킥오프: 칸반 UI 디자인 (Figma 목업 또는 바로 더미 컴포넌트).
4. **+3일** — `feature/talleres-kanban` 브랜치 생성 + 첫 엔드포인트 `/api/talleres/control/kanban`.

---

**로드맵 리뷰 규칙:** 각 Fase 완료 시점에 최신 로그(`api-ventago/logs/combined-YYYY-MM-DD.log`)를 확인해 `talleres/*` 도메인 신규 에러가 있는지 점검하고 우선순위를 조정합니다.
