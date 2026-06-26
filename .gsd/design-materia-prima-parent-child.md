# 설계: Materia Prima 부모-자식(codigoMadre/codigoHijito) 색상별 재고 관리

작성일: 2026-06-25
상태: 설계안 + 프로토타입 (구현은 다음 단계)

## 결정 사항 (확정)

- **DB 구조**: 제품(Product)과 **동일한 진짜 부모-자식 모델** 채택.
  `mes_materials` 에 `parent_id`, `is_parent`, `color_id` 추가.
  (가상 부모 baseCode 그룹핑 대안은 기각 — 제품과의 일관성·공통 메타 부모 관리 우선)
- **이번 범위**: 설계 문서 + 인터랙티브 HTML 프로토타입(더미 데이터)까지.
  마이그레이션/모델/API/실 컴포넌트 구현은 다음 GSD 세션.

## 목표

원단(tela) 등 원자재를 제품처럼 부모-자식 변형 구조로 관리한다.
부모 원단 하나(codigoMadre, 예: `TEL-001` "Tela Denim 12oz")를 선택하면
그 아래 색상별 자식(codigoHijito, 예: `TEL-001-ROJO`)의 현재 재고를
색상별로 한눈에 보여준다.

---

## 1. 데이터 모델 (제품과 동일 패턴)

### 1.1 mes_materials 컬럼 추가

```
parent_id   integer  NULL  FK → mes_materials(id)   -- 부모면 NULL
is_parent   boolean  default false                  -- true = 색상 변형을 가진 부모
color_id    integer  NULL  FK → colors(id)          -- 부모는 NULL, 자식만 값
```

기존 `color varchar` 는 **마이그레이션 기간 동안 유지**하다가 `color_id` 로 점진 이전.
(즉시 DROP 하지 않음 — 운영 안전. 자세히는 §6)

### 1.2 관계 구조

```
Material (부모 codigoMadre)
  ├─ is_parent = true, parent_id = NULL, color_id = NULL
  ├─ code = 'TEL-001', name = '[Tela] Denim 12oz'
  ├─ 공통 메타: unit, origin, quality, supplier_id, category_id  ← 부모에서 1회 관리
  └─ variants (HasMany self-ref)
       ├─ Material (자식 codigoHijito)
       │   ├─ parent_id = 부모.id, color_id = 123 (Rojo)
       │   ├─ code = 'TEL-001-ROJO'
       │   ├─ current_stock = 50, min_stock = 10
       │   └─ name = '[Tela] Denim 12oz (Rojo)'
       └─ Material (자식)
           ├─ parent_id = 부모.id, color_id = 124 (Azul)
           ├─ code = 'TEL-001-AZUL', current_stock = 30
```

### 1.3 재고/이동

- 자식 Material 단위로 `current_stock` 보유 + `mes_material_movements`(ENTRADA/SALIDA/AJUSTE) 기록.
- 부모의 "총 재고"는 자식 합으로 **런타임 집계**(부모 행에 별도 stock 저장 안 함 → 불일치 방지).
- BOM(`bom_items`)은 **자식 Material**(특정 색상)을 직접 참조. 부모 참조 금지.

### 1.4 Sequelize 모델 (구현 시 참고 — 제품 모델과 동형)

```typescript
@ForeignKey(() => Material)
@Column({ type: DataType.INTEGER, allowNull: true })
parentId: number;

@BelongsTo(() => Material, { foreignKey: 'parentId', as: 'parent' })
parent: Material;

@HasMany(() => Material, 'parentId')
variants: Material[];

@Column({ type: DataType.BOOLEAN, defaultValue: false })
isParent: boolean;

@ForeignKey(() => Color)
@Column({ type: DataType.INTEGER, allowNull: true })
colorId: number;

@BelongsTo(() => Color)
color: Color;
```

---

## 2. 정보 구조(IA) · 화면 흐름

### 권장 레이아웃: 마스터-디테일 2단

```
┌───────────────────────────────────────────────────────────────┐
│ Inventario de Materia Prima          [+ Nueva tela madre]      │
├──────────────────────┬────────────────────────────────────────┤
│ TELAS MADRE (좌)     │  TEL-001 · Tela Denim 12oz (우)         │
│ ┌──────────────────┐ │  Unidad: m · Origen: Japón              │
│ │🔍 buscar...      │ │  [Reponer stock]  [+ Color]  [Editar]   │
│ ├──────────────────┤ │ ┌────────────────────────────────────┐ │
│ │▸ TEL-001 Denim ● │◀│ │ ● Rojo   TEL-001-ROJO   50 m  [OK]  │ │
│ │  TEL-002 Lino    │ │ │ ● Azul   TEL-001-AZUL   30 m  [OK]  │ │
│ │  TEL-003 Gabard. │ │ │ ● Negro  TEL-001-NEGRO   0 m [Agot] │ │
│ │  ALG-001 Algodón │ │ │ ● Verde  TEL-001-VERDE  -3 m  [Neg] │ │
│ └──────────────────┘ │ └────────────────────────────────────┘ │
└──────────────────────┴────────────────────────────────────────┘
```

좌측 `List` + `ListItemButton(selected)` — 자식 중 저재고/품절이 있으면 항목에 빨강 점(`Badge`).
우측은 선택된 부모의 공통 메타 + 색상별 자식 재고 리스트 + 액션.

**트레이드오프 요약**

| 패턴 | 채택 |
|---|---|
| 마스터-디테일 2단 | ✅ 권장 — 입고 등 넓은 액션을 디테일에 펼침, POS 동선 일치 |
| 아코디언/확장행 | 부모 적을 때 임시방편. 입고 폼 넣으면 행 높이 폭발 |
| 별도 상세 페이지 | 왕복 클릭·컨텍스트 단절. 비권장 |

좁은 폭: `useMediaQuery` → 좌측 `Drawer` 로 접고 디테일 풀스크린.

---

## 3. 색상별 재고 리스트 컴포넌트 (1D)

제품은 색상×사이즈 2D 격자(`VariantsStock`)지만, 원자재는 **색상 축 1개뿐** → 세로 1D 리스트.

각 색상 행 (좌→우):

1. **색상 스와치** — `colors.hex` 채운 원형 `Box` (14~16px)
2. **색상명** — `Typography` 13px
3. **codigoHijito** — `TEL-001-ROJO`, monospace 회색
4. **현재고 + 단위** — `50 m`, monospace 굵게 (단위는 항상 숫자에 붙여 표기 — 미터/콘 혼동 방지)
5. **상태 배지** — `Chip`: OK(초록) / Bajo(주황) / Agotado(빨강) / Negativo(빨강)
6. **빠른 입고** — `IconButton(tabler:plus)` → 인라인 수량 입력 → blur 시 ENTRADA 기록

### 상태 색 규약 (기존 stockStatus/stockColor 재사용)

| 상태 | 조건 | 색 |
|---|---|---|
| OK | current ≥ min, > 0 | 초록 |
| Bajo | 0 < current < min | 주황(#F5A623 골드 = 경고색) |
| Agotado | current = 0 | 빨강 |
| Negativo | current < 0 | 빨강 + 행 배경 옅은 danger |

**음수 재고**: 부호 노출(`-3 m`), 빨강 표기, **거래 차단 안 함**(프로젝트 규칙). `Tooltip` "Stock negativo — revisá conteo".
**품절**: `Chip "Agotado"` + 공급자 연락(`ContactSupplierTrigger`) 강조.

---

## 4. 부모 생성 / 색상 추가 플로우

"Nueva tela madre" → `Dialog`:

1. **상단(부모 공통)**: Categoría 선택 → `codePrefixFromCategory`+`generateNextCode` 로 baseCode 자동(`TEL-001`).
   Unidad·Origen·Calidad·Proveedor 는 부모 공통값 1회 입력.
2. **하단(색상 변형 리스트)**: 이미 구현된 `colorRows` UI 승격.
   행 = 색상 Select(스와치) + 초기재고 + 최소재고. "Agregar color" 로 N행.
3. **코드 미리보기**: 행마다 `TEL-001-<토큰>` 인라인 표시(`colorToCodeToken` 재사용).
4. **저장**: 부모 1행(is_parent=true) + 자식 N행을 단일 트랜잭션 생성.
   → 기존 `POST /mes/materials/bulk` 를 **부모 생성 포함하도록 확장**(items + parent 메타).

편집은 **단건 유지**. 기존 부모에 색상 1건 추가는 bulk(items=1, parentId 지정)로 재사용.

---

## 5. 빠른 입고(Reponer stock) 플로우

제품 `ProductParentList` 의 "오늘 입고/수정 모드"를 1D 로 단순화.

- 디테일 우상단 **"Reponer stock"** → 모달: 부모의 모든 색상이 "추가 입고량" 1열 격자로.
- **공급자·단가·결제상태는 입고 헤더 1회 입력**(배치 전체 적용 — 보통 같은 묶음).
- **날짜 백데이트**: 헤더 `DatePicker`(기본 오늘). 과거 보정 지원.
- **결제상태**: `ToggleButtonGroup`(Pagado/Pendiente). Pendiente → `material_supplier_payments` 미수 기록.
- 저장 → 색상별 ENTRADA `mes_material_movements` 일괄 + current_stock 가산.
- Tab 네비 + blur 0 정규화(VariantsStock 패턴 차용).

---

## 6. 마이그레이션 UX (흩어진 행 → 부모-자식 묶기)

진짜 부모 모델이므로, 기존 색상별 독립 Material 들을 부모-자식으로 재배선하는 1회성 마법사 필요.

**"Agrupar telas" 마법사** (`Stepper`):
1. **자동 후보 추출**: 이름 유사도 + `stripColorSuffix`/`stripCategoryPrefix` 로
   `Denim (Rojo)`,`Denim (Azul)` 같은 동일 부모 후보 그룹 제안.
2. **검토/확정**: 그룹별 부모명·baseCode 확정. 부모 행 신규 생성(is_parent=true).
3. **자식 재배선**: 그룹 내 기존 행에 `parent_id` 세팅 + `color_id` 매핑 + code 정규화(`-ROJO`).
   기존 행 보존(이동기록·BOM FK 안전). **삭제·이동 없이 컬럼만 업데이트**.
4. **미리보기 + 트랜잭션 확정**: 변경 코드/이름 `Table` 미리보기 → 일괄 적용.
5. **롤백 안전**: parent_id/color_id NULL 복원으로 원복 가능.

운영 적용: `api-ventago/migrations/` 에 컬럼 추가 SQL + 데이터 재배선은 마법사(앱 내) 또는 별도 스크립트. PG10/PG15 호환 주의.

---

## 7. 디자인 시스템

- 테마: 다크 네이비(#1a1a2e) + 골드(#f5a623). 단, 이 화면 액센트는 기존 보라(#7C4DFF) 유지.
  골드는 stockStatus "경고(Bajo)" 색으로 이미 역할이 잡혀 있어 액센트 중복 금지.
- MUI 매핑:
  - 마스터: `List`/`ListItemButton(selected)`/`Badge`
  - 디테일 헤더: `Box`/`Typography`/`Button`
  - 색상 행: `ListItem`/스와치 `Box`/`Chip`/`IconButton`
  - 모달: `Dialog`/`TextField`/`Select`/`Autocomplete`/`DatePicker`/`ToggleButtonGroup`
  - 빈·로딩: `Skeleton`, 중앙 `Box`

---

## 8. 구현 로드맵 (다음 세션)

### Phase A — 백엔드 스키마/모델
1. migration: `mes_materials` 에 parent_id/is_parent/color_id 추가 (color varchar 유지)
2. Material 모델 self-ref + Color 관계 추가
3. `GET /mes/materials/parents` (is_parent=true 목록)
4. `GET /mes/materials/:parentId/colors` (자식+재고)
5. `POST /mes/materials/bulk` 확장: 부모 생성 + 자식 N건 트랜잭션

### Phase B — 프론트
6. InventarioView → 마스터-디테일 레이아웃 전환
7. ColorStockList(1D) 컴포넌트
8. 부모 생성 모달(색상 리스트 승격) + 코드 미리보기
9. Reponer stock 모달(헤더 메타 + 색상별 수량 + 백데이트)

### Phase C — 마이그레이션
10. Agrupar telas 마법사
11. 운영 데이터 재배선 + 검증

### 완료 기준
- 부모 선택 → 색상별 재고 1D 리스트 표시
- 부모 생성 시 색상 N개 일괄 + 코드 자동
- 음수 재고 표기하되 차단 없음
- ESLint 0, pool 누수 0(Sequelize 트랜잭션)

---

## 9. 재활용 자산

| 자산 | 위치 | 역할 |
|---|---|---|
| `colorToCodeToken` | InventarioView.tsx | 자식 코드 토큰 |
| `applyColorSuffix`/`stripColorSuffix` | InventarioView.tsx | 이름 동기화·마이그레이션 후보 |
| `generateNextCode`/`codePrefixFromCategory` | InventarioView.tsx | baseCode 자동 |
| `stockStatus`/`stockColor` | InventarioView.tsx | 상태 배지/색 |
| `POST /mes/materials/bulk` | materials.service.ts | 부모+자식 일괄 생성 |
| 제품 `VariantsStock`/`ProductParentList`/`createVariantsBatch` | products/ | 패턴 참고(2D→1D 단순화) |
| `ContactSupplierTrigger` | materia-prima/ | 품절 공급자 연락 |
