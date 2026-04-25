# SPEC: Materia Prima 전용 Supplier 시스템 분리
생성일: 2026-04-24

## 목표

Materia Prima(원자재) 도메인의 공급자(Proveedor)를 ventas의 `suppliers` 테이블과 **완전히 분리된 독립 테이블** 로 신설하고, 자재 등록 폼 UX를 개선하며, 재고 부족 시 공급자에게 즉시 연락(전화/WhatsApp/이메일) 할 수 있는 UI를 추가한다.

## 사용자 결정 사항

| 질문 | 결정 |
|---|---|
| Supplier 필드 구성 | **프로 세트** — name, cuit, phone, whatsapp, email, address, contact_person, payment_terms, notes, is_active |
| 마이그레이션 방식 | **완전히 독립 시작** — 기존 `mes_materials.supplier_id` NULL 리셋, 자재 데이터가 0 이므로 안전 |
| 연락 UI 위치 | **Inventario 행 + Dashboard 알림 둘 다** |
| 자재 등록 시 신규 공급자 입력 | **Inline 신규 다이얼로그** — 자재 폼 안에서 즉시 등록 |

## 배경 및 컨텍스트

### 현재 구조 (문제점)
- `mes_materials.supplier_id` → ventas의 `suppliers` 테이블 FK
- ventas의 `Supplier` 모델은 `name`, `isActive` 두 필드만 — 정보 빈약
- ventas suppliers는 판매·세금·고객 회계 도메인이라 자재 공급자와 의미가 다름
- 두 도메인이 같은 테이블을 쓰면 운영자 혼선 + 향후 `suppliers` 스키마 확장 시 양 도메인 충돌

### 신규 구조
```
ventas.suppliers              ← 판매 도메인 (그대로 유지)
   ↑
   ╳ FK 제거 (Material 에서 더 이상 참조 안 함)

mes_material_suppliers        ← Materia Prima 전용 (신설)
  ├─ name (required)
  ├─ cuit (Argentina tax ID)
  ├─ phone
  ├─ whatsapp
  ├─ email
  ├─ address
  ├─ contact_person
  ├─ payment_terms (예: "30/60/90 días")
  ├─ notes
  ├─ is_active
  ├─ store_id (멀티테넌트)
  └─ UNIQUE(cuit, store_id), UNIQUE(name, store_id)
   ↑
   ↑ 새 FK
mes_materials.supplier_id     ← 신규 테이블 가리키게 변경
mes_material_movements.supplier_id  ← 신규 테이블 가리키게 변경
mes_material_supplier_payments.supplier_id  ← 신규 테이블 가리키게 변경
```

### 데이터 안전성
- coolsistema의 `mes_materials` = 0 rows → 기존 supplier_id 참조 데이터 없음
- `mes_material_movements` = 0 rows
- `mes_material_supplier_payments` = (확인 필요) 운영에 데이터 없을 가능성 높음
- → **운영 데이터 손실 위험 0** 으로 안전한 마이그레이션 가능

## 기술 스택
- 백엔드: NestJS 11 + Sequelize-typescript (`underscored: true`)
- 프론트: Next.js 13 + MUI 5 + SWR + Axios
- DB: PostgreSQL 15 (로컬 Docker), PG10 (운영)

## 태스크 목록

### Phase A: 백엔드 (DB + 모델)

- [ ] **TASK-2**: DB 마이그레이션 SQL — `api-ventago/migrations/2026-04-25-create-material-suppliers.sql`
  - `CREATE TABLE mes_material_suppliers` (모든 필드 + 인덱스 + 유니크)
  - `ALTER TABLE mes_materials` — supplier_id 의 FK 를 새 테이블로 (또는 새 컬럼 추가 + 기존 NULL)
  - `ALTER TABLE mes_material_movements` — 동일
  - `ALTER TABLE mes_material_supplier_payments` — 동일
  - 운영 DB 데이터 0건이므로 단순 `DROP CONSTRAINT + ADD CONSTRAINT` 방식

- [ ] **TASK-3**: MaterialSupplier 모델/서비스/컨트롤러
  - `api-ventago/src/app/production/material-suppliers/material-supplier.model.ts`
  - `material-supplier.service.ts` — CrudService 상속 + `findAllByStore`
  - `material-supplier.controller.ts` — `@Controller('materia-prima/suppliers')` + `@Auth(...)`
  - `production.module.ts` 에 등록

- [ ] **TASK-4**: 기존 Material 관련 모델 supplier 참조 변경
  - `materials.model.ts` — `@ForeignKey(() => Supplier)` → `@ForeignKey(() => MaterialSupplier)`
  - `material-movement.model.ts` — 동일
  - `material-supplier-payment.model.ts` — 동일
  - `material-movement.service.ts` 의 `include: [{ model: Supplier }]` → `MaterialSupplier`
  - `material-supplier-payment.service.ts` 의 debt-summary SQL — `LEFT JOIN suppliers s` → `LEFT JOIN mes_material_suppliers s`
  - 모듈 imports 정리

### Phase B: 프론트 (훅 + 화면)

- [ ] **TASK-5**: SWR 훅 `useMaterialSuppliers`
  - `ventago-app/src/hooks/api/useMaterialSuppliers.ts`
  - `useApi<any[]>('/materia-prima/suppliers')`

- [ ] **TASK-6**: ProveedoresView 재작성
  - 엔드포인트: `/suppliers/by-store` → `/materia-prima/suppliers`
  - 다이얼로그 폼: name, cuit, phone, whatsapp, email, address, contact_person, payment_terms, notes, is_active
  - WhatsApp/전화 빠른 액션 버튼 (각 카드)
  - 기존 채무 배지·정렬 유지 (debt-summary join 결과)

- [ ] **TASK-7**: InventarioView 폼 재배치 + Inline 신규 Supplier 다이얼로그
  - 폼 1행: **Categoría 만 (전체 너비)** — 첫 선택 시 코드+이름 prefix 자동 채움
  - 폼 2행: Código + Nombre (자동 채워진 상태)
  - 폼 3행: Unidad + Precio + (재고/최소재고)
  - 폼 4행: **Proveedor Autocomplete** + Inline `⊕ Nuevo Proveedor` 옵션
    - 클릭 시 InlineSupplierDialog 열림 → 저장 → `useMaterialSuppliers` mutate → 신규 ID 자동 선택
  - 폼 5행: 색상/원산지/품질/설명
  - 자재 행 우측에 **연락 아이콘** 추가 (재고 부족 OR 0 일 때만 강조)

- [ ] **TASK-8**: ContactSupplierPopover 신규 재사용 컴포넌트
  - `ventago-app/src/views/materia-prima/components/ContactSupplierPopover.tsx`
  - props: `supplierId`, `materialName`, `anchorEl`, `onClose`
  - 내부에서 `useMaterialSuppliers` 사용해 supplier 정보 lookup
  - 표시: phone (`tel:`), whatsapp (`https://wa.me/`), email (`mailto:`) 각 줄 클릭 가능
  - WhatsApp 메시지 prefill: `Hola ${supplier.contactPerson || supplier.name}, necesito reponer ${materialName}`

- [ ] **TASK-9**: MateriaPrimaDashboardView 'stock crítico' 행에 연락 버튼
  - lowStockItems 테이블 마지막 컬럼: `supplierId` 있으면 ContactSupplierPopover 트리거 아이콘

- [ ] **TASK-10**: PagosView, MovimientosView 의 Supplier Autocomplete 도 새 훅으로 교체
  - `useSuppliersByStore` → `useMaterialSuppliers` 로 변경 (Materia Prima 화면 한정)
  - ventas의 다른 화면에서는 `useSuppliersByStore` 그대로 유지 (영향 X)

### Phase C: 검증

- [ ] **TASK-11**: ESLint 통과 + 마이그레이션 안내 + 동작 검증
  - 프론트: `npx eslint <변경 파일들>` → 0 errors
  - 백엔드: Jenkins 빌드 위임
  - 운영DB: 사용자에게 마이그레이션 SQL 실행 안내 (사용자 동의 후)
  - 시나리오 테스트:
    1. ProveedoresView → "Nuevo Proveedor" → name + cuit + phone + whatsapp + email 입력 → 저장
    2. InventarioView → "Nuevo material" → 카테고리 선택 → 자동 코드/이름 → Proveedor 드롭다운에 방금 등록 공급자 보이는지 확인
    3. Proveedor Autocomplete → "⊕ Nuevo Proveedor" 클릭 → Inline 다이얼로그 → 저장 → 자동 선택 확인
    4. 자재 stock 일부러 0 으로 만들기 → Inventario 행 우측 연락 아이콘 → popover 에서 WhatsApp 클릭 → wa.me 링크 정상
    5. Dashboard → stock crítico 행에서도 동일 popover 작동 확인

## 완료 기준

- [ ] DB 마이그레이션 운영 적용 완료 (사용자 승인 후)
- [ ] `mes_material_suppliers` 테이블 생성 + 모든 unique/index 적용
- [ ] 기존 `suppliers` 테이블은 ventas 도메인에서 그대로 사용 (영향 X)
- [ ] 프론트 ESLint 0 errors / 0 warnings
- [ ] Materia Prima 5개 사이드바 메뉴 모두 정상 (회귀 0건)
- [ ] 새 supplier inline 등록 흐름 완성
- [ ] Inventario + Dashboard 양쪽 연락 popover 작동

## PostgreSQL Pool 안전 체크리스트

- [ ] 마이그레이션은 단일 트랜잭션 (BEGIN; ... COMMIT;) — 부분 실패 방지
- [ ] 새 모델의 모든 raw SQL은 replacements 사용 (SQL injection 방지)
- [ ] 기존 service 의 transaction 패턴 그대로 유지 (release 누락 없음)

## 금지사항 / 주의사항

- ❌ ventas의 `suppliers` 테이블 **수정 금지** — ventas 도메인 영향 없도록
- ❌ ventas suppliers의 데이터를 신규 테이블로 자동 복사 금지 (사용자 결정: 완전 독립 시작)
- ❌ 자재가 이미 등록된 매장(다른 store_id 가 운영 중일 가능성)에서 supplier_id 가 NULL 이 되어 보이지 않을 수 있음 → 마이그레이션 SQL 실행 전 모든 매장의 자재·결제 데이터 카운트 확인
- ⚠️ ESLint: `newline-before-return`, `lines-around-comment` 엄격
- ⚠️ 주석 한국어, 함수·변수명 영어
- ⚠️ Inline 신규 다이얼로그는 `react-hook-form` 안 쓰고 단순 useState (다른 다이얼로그와 일관성)

## 배포 전략

1. **마이그레이션 SQL** 운영 적용 — 사용자에게 SQL 보여주고 동의 후 SSH 실행
2. 코드 push → Jenkins 자동 빌드
3. 프론트/백엔드 컨테이너 재시작 자동
4. 사용자 브라우저에서 Cmd+Shift+R 후 시나리오 테스트

## 후속 작업 (이번 범위 밖)

- ventas suppliers와 mes_material_suppliers를 **연결**하고 싶을 때 → 별도 join 테이블 또는 양방향 ID 매핑 필드
- supplier별 자재 통계 페이지 (지난 12개월 매입액·발주 빈도 등)
- WhatsApp Business API 연동 (현재는 wa.me 링크 수동 발송)
- 공급자별 PDF 발주서 자동 생성
