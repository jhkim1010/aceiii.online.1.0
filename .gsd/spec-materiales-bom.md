# SPEC: Materia Prima (Materiales + BOM) — Wave 12

생성일: 2026-04-24

## 목표

Cost Sheet가 완전히 작동하려면 필요한 두 가지를 추가:

1. **Materiales 탭** — 자재 마스터(`mes_materials`) CRUD 화면
2. **Cost Sheet 탭 내 BOM 편집** — 제품별 BOM을 인라인으로 편집하는 섹션
3. **기본 카테고리 시드** — 매장 로그인 시 기본 5개 카테고리 자동 삽입 (존재 안할 때만)
4. **BOM 버전 관리** — "새 버전 만들기" 버튼 + 과거 버전 read-only 조회

## 배경 확정 사실 (2026-04-24 운영 DB 조사)

- `mes_*` 테이블 8개 전부 운영 DB에 존재 (스키마 확인 완료)
- coolsistema(store_id=6) 데이터 카운트: materials 0, categories 0, bom 0, bom_items 0, movements 0
- 백엔드 CRUD 엔드포인트 전부 준비됨 (CrudController 상속)

### 관련 백엔드 엔드포인트

**`mes/materials`** (CrudController 상속)
- `GET /api/mes/materials` — store 기준 전체 목록
- `GET /api/mes/materials/:id` — 단건 조회
- `POST /api/mes/materials` — 생성 (storeId 자동 주입)
- `PUT /api/mes/materials/:id` — 수정
- `DELETE /api/mes/materials/:id` — 삭제

**`materia-prima/categories`** (주의: 다른 prefix!)
- 상동 + `GET /api/materia-prima/categories/store` — 현재 store 카테고리만

**`mes/bom`** (CrudController 상속)
- 상동

**누락 가능성**: BOM 에 items가 함께 편집되도록 하는 "BOM + items 묶음 PUT" 또는 별도 `mes/bom-items` 엔드포인트가 필요할 수 있음. 검증 태스크에서 확인.

### 참고 스키마 (핵심 필드만)

```
mes_materials:
  id, code*, name*, unit, standard_price, description,
  is_active, category_id, supplier_id,
  current_stock, min_stock, last_entry_date,
  color, origin, quality, image_url,
  store_id*

mes_bom:
  id, product_id*, version, is_active, store_id*

mes_bom_items:
  id, bom_id*, material_id | sub_product_id, quantity*, unit, notes

mes_material_categories:
  id, name*, slug*, icon, color, description,
  is_default, is_active, sort_order, store_id*

  UNIQUE(slug, store_id)
```

## 기술 스택

- 프론트: Next.js 13 + MUI 5 + SWR + react-hot-toast + apiConnector
- 백엔드: 기존 Nest CrudController 재사용, 필요 시 BOM items 저장 전용 엔드포인트 추가
- DB 변경 없음 (스키마 이미 완비)

## 태스크 목록

- [x] TASK-47: SPEC 작성
- [ ] TASK-48: 백엔드 엔드포인트 검증
  - `GET /mes/materials` 실제 응답 형태 확인 (storeId 필터 자동?)
  - `GET /materia-prima/categories/store` 동작 확인
  - `GET /mes/bom?productId=X` 필터 지원 여부 (없으면 findByProduct 메서드 추가)
  - `mes_bom_items` CRUD 엔드포인트 존재 여부
  - 누락 있으면 컨트롤러 보강
- [ ] TASK-49: SWR 훅 3개 신규
  - `useMaterials()` — 전체 자재 목록 (기본)
  - `useMaterialCategories()` — 카테고리 목록 + 자동 시드 훅 (빈 경우)
  - `useBom(productId)` — 특정 제품의 BOM + items include 반환
- [ ] TASK-50: `MaterialesTab.tsx` 신규
  - EtapasTab 패턴 복제
  - 컬럼: 코드, 이름, 카테고리, 단위, 단가, 공급업체, 재고, 상태
  - Dialog 폼: code*, name*, categoryId, unit, standardPrice, supplierId, currentStock, minStock, color, origin, quality, description, isActive
  - 필터: 카테고리, 상태, 검색
  - 재고 상태 dot: current < min → 빨강, current < min*2 → 주황, else 녹색
  - 비활성화 아이콘 (EtapasTab과 동일)
- [ ] TASK-51: `CategoriesManagerDialog.tsx` 신규
  - Materiales 탭 헤더 "Categorías" 버튼 → 이 Dialog
  - 카테고리 목록 + 인라인 이름/아이콘/색상 수정
  - "시드 기본 카테고리 삽입" 버튼 (DEFAULT_MATERIAL_CATEGORIES 5개 일괄 등록)
  - 또는 첫 방문 시 자동 시드 (백엔드에 seed 엔드포인트 추가)
- [ ] TASK-52: `BomEditorSection.tsx` + `CostSheetTab.tsx` 통합
  - BOM header: 버전 드롭다운 + "새 버전 만들기" 버튼 + is_active 토글
  - 라인: Material Autocomplete + quantity + unit 자동 + subtotal 자동
  - + "Agregar material" 라인 추가
  - 삭제 아이콘
  - 저장 로직: debounce 500ms 자동 저장 (CostSheetEditableForm 패턴과 동일)
  - 저장 후 Cost Sheet "Recalcular" 자동 트리거
- [ ] TASK-53: ESLint + 리뷰

## 상세 구현 노트

### Materiales 탭 UI (EtapasTab 패턴)

```tsx
// 헤더
<Typography>Materiales</Typography>
<Button onClick={handleOpenCategories}>Categorías</Button>
<Button variant="contained" onClick={handleOpenCreate}>+ Nuevo material</Button>

// 필터 3개
<TextField placeholder="Buscar..." />
<Select>Todas categorías / Tela / Botón / Cierre / Hilo / Accesorio</Select>
<Switch label="Mostrar inactivos" />

// 테이블 컬럼
| 상태점 | 코드 | 이름 | 카테고리 | 단위 | 단가 | 재고 | 상태 | 액션 |
```

### BOM Editor 동작

1. 제품 선택 → `useBom(productId)` 호출
2. BOM 없으면 → "Crear BOM" 버튼 → POST `/mes/bom` with `{productId, version: '1.0', isActive: true}`
3. BOM 있으면 → items 편집 가능
4. Material Autocomplete: `useMaterials()` 필터링
5. quantity 변경 → debounce 500ms → PATCH bom-items
6. 하단에 실시간 총 자재비 표시
7. "Aplicar a Cost Sheet" 버튼 → POST `/talleres/cost-sheets/:productId/calculate`

### BOM 버전 관리 플로우

- 헤더 드롭다운: "v1.0 (activa)" / "v0.9" / ...
- "새 버전 만들기" 버튼:
  1. 확인 Dialog ("현재 BOM을 복사해 새 버전을 만듭니다")
  2. POST 로 새 `mes_bom` 생성 (version = 현재 + 0.1 또는 사용자 입력)
  3. 기존 bom_items 전부 새 BOM에 복사
  4. 기존 BOM은 is_active=false, 새 BOM은 is_active=true
- 과거 버전 드롭다운 선택 시: read-only 모드로 표시

### 카테고리 자동 시드 전략

**옵션 A (추천)**: Materiales 탭 최초 로드 시 categories가 빈 배열이면 자동으로 `POST /materia-prima/categories/seed-defaults` 호출 → 백엔드가 `seedMaterialCategoriesForStore` 실행

**옵션 B**: 사용자가 "Seed defaults" 버튼 클릭

백엔드에 seed 엔드포인트가 없으면 추가 필요 (TASK-48).

## 완료 기준

- Talleres 메뉴에 "Materiales" 탭 새로 생김
- Materiales 탭에서 자재 CRUD 작동
- 카테고리 최초 로드 시 기본 5개 자동 생성
- Cost Sheet 탭에서 제품 선택 → BOM 편집 섹션 표시
- BOM items 추가/수정/삭제 → Cost Sheet 마진 실시간 업데이트
- 버전 드롭다운 + 새 버전 만들기 동작
- ESLint 0 에러 (제 변경 영역)

## 금지사항 / 주의사항

- `mes_*` 스키마 변경 없음
- 기존 Cost Sheet 동작 깨지지 않게 (BOM 없을 때 "BOM not configured" 메시지는 그대로 유지되어야 함)
- PostgreSQL pool: 매 자재 편집 시 새 쿼리 발생 — debounce 필수 (500ms)
- 주석 한국어, 함수명 영어, 사용자 메시지 스페인어
