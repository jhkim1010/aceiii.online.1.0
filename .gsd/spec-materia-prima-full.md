# SPEC: Materia Prima 통합 + Talleres Liquidaciones
생성일: 2026-04-24

## 목표

1. Materia Prima 사이드바의 5개 서브메뉴(Dashboard/Inventario/Movimientos/Proveedores/Pagos)를 **모두 작동하는 완전한 UI**로 구현.
2. Talleres 탭에 있던 중복 Materiales 탭을 제거하고 사이드바로 **단일 진실 공급원(Single Source of Truth)** 확립.
3. Cut Ticket 발급 시 BOM 기준 **원자재 자동 차감** 훅 추가 (재고 실시간 감소).
4. Talleres 메뉴에 **Liquidaciones (외주업자 정산) 탭** 신규 추가.

## 배경 및 컨텍스트

### 현재 상태 (2026-04-24 기준)
- Wave 12에서 Talleres 탭에 `MaterialesTab`을 만들어 작동 상태였음. 그러나 사이드바의 `views/materia-prima/*`가 **broken** (Spanish 필드명 `nombre/codigo/categoria` vs 백엔드 English `name/code/categoryId` 스키마 불일치)이라 **UI 중복 + 사이드바 먹통** 문제 발생.
- 외주업자 Pago(`subcon-settlements`) 시스템은 **백엔드 완비 (PDF까지)**, 프론트 UI 없음.
- 원자재 공급자 Pago(`material-supplier-payments`) 시스템도 **백엔드 완비**, 프론트 UI는 `PagosView.tsx`가 broken.

### 업무 흐름 (사용자 확인 완료)
```
Materia Prima 관점             Talleres 관점
  ↓                             ↓
공급자(Proveedor)               외주업자(Vendor/Taller)
  ↓ 자재 입고                    ↓ Envio/Recepcion
MaterialMovement (ENTRADA)     Subcon Settlement
  ↓ 미지급 → 채무                 ↓ 정산 → 미지급 → 채무
MaterialSupplierPayment        SubconSettlement(PAID)
(원단집 La Estrella 지불)        (Sra. María 봉제비 지불)
```

두 Pago 시스템은 **물리적으로 완전히 분리된 독립 서브시스템**. 테이블·연결 FK·UI 위치 모두 분리.

## 기술 스택
- 프론트: Next.js 13 Pages Router + MUI 5 + SWR + Axios (`apiConnector`)
- 백엔드: NestJS 11 + Sequelize-typescript (`underscored: true`)
- DB: PostgreSQL (운영 PG10 호스트 / 로컬 PG15 Docker)
- ESLint 설정: `ventago-app/.eslintrc`, `api-ventago/.eslintrc`

## 백엔드 가용 엔드포인트 (조사 완료)

| 기능 | 엔드포인트 | 상태 |
|---|---|---|
| Materials CRUD | `/mes/materials` | ✅ |
| Material Categories | `/materia-prima/categories/*` (seed-defaults 포함) | ✅ |
| Movement Entry/Exit | `POST /materia-prima/movements/{entry,exit}` | ✅ |
| Movement 목록 | `GET /materia-prima/movements` (필터+페이지네이션) | ✅ |
| Dashboard 통계 | `GET /materia-prima/movements/dashboard` (4지표 SQL) | ✅ |
| Supplier Payment CRUD | `/materia-prima/payments/*` + `/debt-summary` | ✅ |
| Suppliers | `/suppliers/by-store` | ✅ |
| Talleres Settlements | `/talleres/settlements/*` (draft/confirm/cancel/paid/pdf/lines) | ✅ |
| **Cut Ticket BOM 자동차감** | `lote.service.ts` | ⚠️ **추가 필요** |

---

## 태스크 목록

### Phase 1 — 당장 필요한 핵심 (매일 쓰는 기능)

- [ ] **TASK-55**: InventarioView 교체 — 기존 broken → MaterialesTab 로직 이식 (스키마 맞춤)
  - 파일: `ventago-app/src/views/materia-prima/InventarioView.tsx`
  - 필드: `name/code/categoryId/unit/standardPrice/currentStock/minStock/color/origin/quality/supplierId/description/isActive`
  - Categorías 버튼 → CategoriesManagerDialog
  - Auto-seed 카테고리 (매장에 0개면)

- [ ] **TASK-56**: CategoriesManagerDialog 이전
  - From: `ventago-app/src/views/talleres/materiales/CategoriesManagerDialog.tsx`
  - To: `ventago-app/src/views/materia-prima/CategoriesManagerDialog.tsx`
  - import 경로 수정

- [ ] **TASK-57**: MateriaPrimaDashboardView 재작성 (KPI + 알림 + 분포)
  - 파일: `ventago-app/src/views/materia-prima/MateriaPrimaDashboardView.tsx`
  - 상단: KpiCard 4개 (총자재수, 품절, 부족, 재고금액) — `GET /materia-prima/movements/dashboard`
  - 중단: Bajo Stock 자재 리스트 (minStock 이하) — `useMaterials` 필터
  - 하단: 카테고리별 자재 분포 (CategoryDistributionChart) + 공급자 채무 상위 (DebtSummaryChart)

- [ ] **TASK-58**: MovimientosView 재작성 (백엔드 스키마 맞춤)
  - 파일: `ventago-app/src/views/materia-prima/MovimientosView.tsx`
  - 필드 교체: `nombre/cantidad/fecha/proveedor` → `materialId/quantity/movementDate/supplierId/unitPrice/totalAmount/paymentStatus/type`
  - 탭: Entrada / Salida / Ajuste
  - 필터: 기간(dateFrom/dateTo), 자재, 공급자, 유형
  - 등록 다이얼로그: Entrada (입고) + Salida (수동 출고)

- [ ] **TASK-59**: 백엔드 — Cut Ticket 발급 시 BOM 자동 차감 훅 (PG pool 안전)
  - 파일: `api-ventago/src/app/subcon/lotes/lote.service.ts` (generateCutTicket 경로)
  - 로직:
    1. BOM.findByProduct(productId)로 활성 BOM 조회
    2. BomItem 순회하며 각 자재별 소비량 = bomItem.quantity × totalQuantity
    3. MaterialMovement(type=SALIDA) 생성 + material.currentStock 감소 (트랜잭션 내부)
    4. 재고 부족 자재는 **에러 아니라 경고 리스트**로 수집 후 `calc_snapshot.warnings`에 append (하드 블록 X)
  - **PostgreSQL pool 규칙 준수**: 기존 `sequelize.transaction()` 패턴 유지 (try/finally release 자동)
  - 주의: `existing material-movement.service.ts`의 `createExit` 재사용 (중복 구현 금지)

- [ ] **TASK-60**: Talleres 탭에서 Materiales 제거
  - `ventago-app/src/views/talleres/components/constants.ts` — `materiales` 항목 삭제
  - `ventago-app/src/views/talleres/TalleresMainView.tsx` — MaterialesTab dynamic import + 라우팅 삭제
  - `ventago-app/src/views/talleres/tabs/MaterialesTab.tsx` — 삭제
  - `ventago-app/src/views/talleres/materiales/` 폴더 — 삭제 (Dialog는 TASK-56에서 이미 이동 완료)

### Phase 2 — 공급망·채무 관리

- [ ] **TASK-61**: ProveedoresView 재작성
  - 파일: `ventago-app/src/views/materia-prima/ProveedoresView.tsx`
  - 테이블: 공급자 목록 + 각 공급자 옆에 `채무 금액 배지` (DebtSummary 매핑)
  - CRUD 다이얼로그: name/phone/cuit/email/address/paymentTerms
  - 행 클릭 시 → 해당 공급자 Pagos 필터링된 Movimientos로 점프 (선택)

- [ ] **TASK-62**: PagosView 재작성
  - 파일: `ventago-app/src/views/materia-prima/PagosView.tsx`
  - 상단 요약: 공급자별 채무 (DebtSummary 카드)
  - 하단 테이블: Pago 이력 (`/materia-prima/payments/store`)
  - 등록 다이얼로그: supplierId (Autocomplete), amount, method (EFECTIVO/TRANSFERENCIA/CHEQUE/TARJETA/OTRO), paymentDate, reference, note, movementId (optional)

### Phase 3 — Talleres Liquidaciones

- [ ] **TASK-63**: LiquidacionesTab 신규 (Talleres 메뉴)
  - 파일: `ventago-app/src/views/talleres/tabs/LiquidacionesTab.tsx` (신규)
  - `views/talleres/components/constants.ts` 에 `{ value: 'liquidaciones', label: 'Liquidaciones', icon: 'tabler:file-invoice' }` 추가
  - `TalleresMainView.tsx` 에 dynamic import + 라우팅
  - 구조:
    - 상단: `Nueva liquidación` 버튼 → Dialog (vendor + periodStart/periodEnd) → `POST /talleres/settlements/draft`
    - 중단: 목록 테이블 (`GET /talleres/settlements/all`) — id/vendor/period/status/totalAmount 컬럼
    - 우측 Drawer: 선택 시 lines 상세 (`GET /talleres/settlements/:id/lines`) + 상태별 버튼(Confirm/Cancel/MarkPaid) + PDF 다운로드

### 공통

- [ ] **TASK-64**: SWR 훅 추가
  - `ventago-app/src/hooks/api/useMaterialMovements.ts` — `useSWR('/materia-prima/movements?...')`
  - `ventago-app/src/hooks/api/useMaterialPayments.ts`
  - `ventago-app/src/hooks/api/useSupplierDebt.ts`
  - `ventago-app/src/hooks/api/useSettlements.ts`
  - `ventago-app/src/hooks/api/useMaterialDashboard.ts` (dashboard 통계)
  - `useSuppliers` 존재 여부 확인, 없으면 신규

### 검증

- [ ] **TASK-65**: ESLint + 로그 확인 + 리뷰 리포트
  - `cd ventago-app && npx eslint . --fix`
  - `cd api-ventago && npx eslint . --fix`
  - 최신 로그 파일(`logs/error-YYYY-MM-DD.log`) 확인 — 새로운 에러 없는지
  - PostgreSQL pool 규칙: 새로 추가된 `createExit` 호출 체인이 `sequelize.transaction()` 내부에 있는지 재확인 (pool 누수 없음)
  - 변경 파일 요약 + 후속 작업 리스트

---

## 완료 기준

- [ ] ESLint 오류 0개 (ventago-app, api-ventago 둘 다)
- [ ] 사이드바 Materia Prima 5개 서브메뉴 모두 오류 없이 열림
- [ ] Talleres 메뉴에서 Materiales 탭 사라지고 Liquidaciones 탭 추가
- [ ] 자재 입고(Entrada) → currentStock 증가 확인
- [ ] Cut Ticket 발급 → BOM 기준 자재 SALIDA 자동 기록 + currentStock 감소 확인
- [ ] 공급자 Pago 등록 → 채무 요약에서 해당 금액 차감 확인
- [ ] Liquidación Draft 생성 → Confirm → MarkPaid 흐름 동작 + PDF 다운로드 가능
- [ ] 로그 파일 깨끗 (신규 에러 0건)

## PostgreSQL Pool 안전 체크리스트

- [ ] `lote.service.ts`의 BOM 자동차감은 **단일 `sequelize.transaction()` 블록 내부**에서 수행 (이중 트랜잭션 금지)
- [ ] `createExit`는 이미 내부에서 transaction 시작·commit·rollback 처리 → **재사용 시 외부 트랜잭션과 중첩 주의** → 트랜잭션 공유용 변형 메서드 필요 시 `createExitInTransaction(tx)` 분리
- [ ] 모든 `sequelize.query` 호출은 `QueryTypes.SELECT` 명시 + replacements 바인딩 사용 (SQL injection 방지)
- [ ] 새로 쓰는 raw SQL 없음 — 기존 service 메서드 재사용 우선

## 금지사항 / 주의사항

- ❌ `pool.connect()` 수동 사용 금지 (Sequelize가 관리 중, 중복 pool 생성 위험)
- ❌ 트랜잭션 중첩 금지 (`createExit` 내부에 이미 tx) — Cut Ticket 훅에서는 `createExitInTransaction(tx)` 분리 변형 필요
- ❌ 스페인어 필드명(nombre/categoria/stockMinimo 등) 절대 사용 금지 — 백엔드 스키마는 영문 (name/categoryId/minStock)
- ❌ `apiConnector.delete()` 사용 금지 → `apiConnector.remove()` 사용
- ❌ 기존 BomEditorSection은 Cost Sheet 탭에 **그대로 유지** — 건드리지 않음
- ⚠️ ESLint `newline-before-return`, `lines-around-comment` 규칙 엄격 — 모든 `return` 위·주석 위 빈 줄 필수
- ⚠️ 사용자 전역 preference: 주석은 한국어, 함수·변수명은 영어
- ⚠️ 페이지네이션 기본 pageSize 10, 최대 50 (500 금지)

## 배포 전략

1. 모든 태스크 완료 후 단일 커밋 묶음으로 push
2. Jenkins CI: `front-coolsistema`, `api-coolsistema` job 자동 트리거
3. 빌드 실패 시 Jenkins 로그 확인 (`#NNN.txt`) → fix → 재push
4. 배포 후 운영 DB에서 스모크 테스트:
   - `SELECT COUNT(*) FROM mes_materials WHERE store_id = 6`
   - 로그인 → 사이드바 5개 메뉴 확인 → Cut Ticket 발급 후 `mes_material_movements` 레코드 생성 확인

## 후속 작업 (이번 범위 밖)

- Cut Ticket 자동차감 시 **재고 부족 경고 UI** 개선 (toast로만 끝내지 말고 sheet 영역에 표시)
- Liquidaciones 탭에 **잘못된 정산 감사 로그**
- 공급자 외상 요약에 **기간별 증감 추세 차트** 추가
- Materia Prima > Pagos에 **일괄 Pago (여러 Movimiento 한번에 결제)** 기능
