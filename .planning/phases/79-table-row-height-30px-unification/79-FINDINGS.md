# Phase 79 — 실측 (2026-08-17)

계획을 세우기 전에 코드에서 직접 확인한 값들. **추측 없음** — 전부 grep/파일 확인 결과다.

## F1. 표는 세 계열이다 — 지렛대가 계열마다 다르다

| 계열 | 규모 | 현재 높이 | 바꾸는 지점 |
|---|---|---|---|
| `FullTable` (AG Grid 래퍼) | **76개 파일** | 기본값 `rowHeight = 42` | **파일 1개** (`FullTable.tsx:110`) |
| `AgGridReact` 직접 사용 | **3개 파일** | 아래 F3 | 파일별 |
| MUI `<Table>` | **96개 파일** | 테마 패딩 ≈ **49px** | **테마 override 파일 1개** |
| MUI `<DataGrid>` | 0 | — | (전부 FullTable 로 이관 완료) |

★ 76 + 96 = 172개 파일이 **파일 2개**로 움직인다. 파일을 하나씩 고치는 방식은
다음에 같은 요청이 오면 그대로 반복되므로 쓰지 않는다.

## F2. `FullTable` 에 `rowHeight` 를 직접 준 곳 — 8곳 (그중 3곳은 이미 30)

| 파일 | 값 | 비고 |
|---|---|---|
| `views/sales/list/SalesListView.tsx:734` | **34** | ★ 주석: *"42 → 34 (−20%). Nº 셀을 한 줄로 만든 뒤에야 가능하다 — 두 줄이던 시절엔 42px 에서도 잘렸다"* |
| `views/config/productos/price-types/list/PriceTypesList.tsx:162` | **48** | 이유 미기재 — 셀 내용 확인 필요 |
| `views/products/list/components/ProductParentList.tsx:411` | **28** | 30 보다 **작다** → 통일하면 오히려 **커진다**. `fillHeight` 와 함께 사용 |
| `views/homes/components/ClientList/ClientList.tsx:75` | 30 | 이미 목표값 |
| `views/homes/components/DraftAndDebtors/DraftAndDebtorsList.tsx:407` | 30 | 이미 목표값 |
| `views/caja-fuerte/components/CajaFuerteOperationsTable.tsx:98` | 30 | 2026-08-17 이번 요청으로 적용 |
| `views/configuracion/categorias-gastos/CategoriasGastosTreeView.tsx:137` | 36 | ★ **FullTable 이 아니다** — react-arborist `Tree` (`openByDefault`/`width`/`height={600}`) |
| `views/homes/.../ProductList/components/ProductListTable.tsx:316` | `ROW_HEIGHT` | ★ **상수값이 이미 30** (`:23`). AgGridReact 직접 사용 |

## F3. `AgGridReact` 직접 사용 3곳

- `views/carpetas-compartidas/FileTable.tsx:116` — `rowHeight` **미지정** → AG Grid 기본값(42)
- `views/carpetas-compartidas/admin/AccessLogsView.tsx:214` — `rowHeight` **미지정** → 42
- `views/homes/.../ProductList/components/ProductListTable.tsx:316` — `ROW_HEIGHT = 30` (POS)

★ **POS 는 이미 30px 이다.** 계획 단계에서 "POS 는 터치라 예외로 둘까"를 물었으나,
실제 코드는 이미 30 이었다 — 즉 30px 터치 조작은 **이미 운영에서 쓰이고 있는 값**이고
이번 통일로 POS 가 새로 좁아지는 것은 없다.

## F4. MUI `<Table>` 의 실제 높이 계산

`src/@core/theme/overrides/table.ts` 의 `MuiTableBody`:

```ts
'&:not(.MuiTableCell-sizeSmall):not(.MuiTableCell-paddingCheckbox):not(.MuiTableCell-paddingNone)': {
  paddingTop: theme.spacing(3.5),
  paddingBottom: theme.spacing(3.5)
}
```

`src/@core/theme/spacing/index.ts` → `spacing: (factor) => ${0.25 * factor}rem` = **4px × factor**

→ 현재: 14px + 14px + 본문 20px(body2 0.875rem × 1.43) + 경계선 1px ≈ **49px**
→ 목표 30px: 패딩 **5px** 씩 = `theme.spacing(1.25)` → 5 + 5 + 20 + 1 = **31px**,
  `spacing(1)`(4px) → **29px**. 실측으로 둘 중 택일한다(폰트 렌더링에 따라 ±1px).

★ `sizeSmall`/`paddingCheckbox`/`paddingNone` 셀은 이 규칙에서 **제외**돼 있다 —
이미 dense 로 쓰는 표가 있다는 뜻이므로 그쪽이 더 작아지지 않는지 확인해야 한다.

## F5. 행 높이는 표 전체 높이도 정한다

`FullTable.tsx:271~276`:
```ts
const computedHeight = ... Math.max(visibleRows * rowHeight + headerHeight + 2, 150)
```
→ `rowHeight` 를 줄이면 컨테이너 높이가 함께 줄어 **표 아래 빈 공간이 생기지 않는다.**
단 하한 `150px` 이 있어 행이 2~4개인 표는 여백이 남는다(기존 동작, 이번 범위 밖).

## F6. 위험 — 30px 에서 잘릴 수 있는 것

- `MuiChip-sizeSmall` = 24px → 30px 안에 들어간다 (Caja Fuerte 에서 실물 확인됨)
- `IconButton` 기본 패딩 = 40px 안팎 → **액션 열이 있는 표에서 넘칠 수 있다.**
  `size="small"`(34px)도 30px 보다 크다 → 액션 열은 별도 확인 대상
- **2줄 렌더러** — SalesListView 의 Nº 셀 주석(F2)이 남긴 전례. 다른 화면에도 2줄 셀이 있으면 같은 문제
- `FullTable` 은 셀에 `display:flex; alignItems:center` 를 이미 넣어둔다(`:59~68`) →
  세로 중앙정렬은 해결돼 있다. **넘침(overflow)만 남은 위험**이다
