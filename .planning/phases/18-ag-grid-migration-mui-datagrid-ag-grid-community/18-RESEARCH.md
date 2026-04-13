# Phase 18: AG Grid Migration — Research

**Researched:** 2026-04-13
**Domain:** Frontend table library migration — MUI DataGrid Free → AG Grid Community
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** 컬럼 리사이즈 — 모든 테이블에서 컬럼 드래그 리사이즈 활성화
- **D-02:** 컬럼 고정(Pin) — 좌/우 컬럼 고정 지원 (defaultColDef에 pinnable 설정)
- **D-03:** 필터 UI — 컬럼 헤더 필터 아이콘 활성화 (기본 텍스트/숫자/날짜 필터)
- **D-04:** 행 드래그 정렬 미포함 — Phase 범위 외
- **D-05:** FullTable 래퍼 인터페이스 유지 — 기존 props 시그니처 최대한 보존하여 61개 화면 자동 전환
- **D-06:** columns.tsx 공유 헬퍼 23+개 → AG Grid cellRenderer 패턴으로 전환
- **D-07:** GridColDef → ColDef 타입 전환 (51개 DataConfig 파일)
- **D-08:** renderCell → cellRenderer, renderHeader → headerComponent 매핑
- **D-09:** 서버사이드 페이지네이션 유지 + AG Grid 클라이언트 정렬
- **D-10:** 스페인어 로컬라이제이션 유지 (AG Grid localeText)
- **D-11:** 체크박스 선택, 행 클릭, 로딩 상태 기존대로 동작

### Claude's Discretion
- FullTable 내부 AG Grid API 활용 방식 (gridRef, columnApi 등)
- defaultColDef 세부 설정 (sortable, resizable, filter 기본값)
- 테마/스타일 매핑 (MUI DataGrid 클래스 → AG Grid 테마)
- 회귀 테스트 범위 및 방법

### Deferred Ideas (OUT OF SCOPE)
- 행 드래그 정렬 (상품 순서 변경 등)
- Excel 내보내기 (AG Grid Enterprise 기능)
- 그룹핑/피벗 (Enterprise)
- 서버사이드 정렬 전환
</user_constraints>

---

## Summary

**CRITICAL FINDING: 마이그레이션이 이미 상당 부분 완료되어 있다.** FullTable.tsx는 이미 AG Grid Community 35.2.1 기반으로 전환되었고, 패키지도 설치되어 있다. 남은 작업은 두 가지뿐이다: (1) `grid-types.ts` 호환성 심(shim)을 AG Grid 네이티브 타입으로 교체하고, (2) `@mui/x-data-grid` 패키지를 제거하는 것이다.

**현재 상태 상세:**
- `ventago-app/src/components/table/FullTable.tsx` — AG Grid Community로 완전 전환 완료. `adaptColumns()` 어댑터가 MUI `renderCell`/`params.row` 패턴을 AG Grid `cellRenderer`/`params.data`로 자동 변환. 서버사이드 페이지네이션, 체크박스, 행 클릭, 로딩 상태 모두 구현됨. localStorage 기반 컬럼 너비 저장도 포함.
- `ag-grid-community@35.2.1` + `ag-grid-react@35.2.1` — 설치 완료 (root node_modules 호이스팅).
- `@mui/x-data-grid@6.0.3` — 아직 `package.json`에 존재, 설치됨. `grid-types.ts` 심이 이것에 의존.
- `grid-types.ts` — `@mui/x-data-grid`에서 `GridColDef`, `GridRenderCellParams`를 re-export하는 심으로 유지 중. 58개 파일이 이 경로를 통해 타입을 가져옴.
- `columns.tsx` — 여전히 `GridRenderCellParams` 타입 사용 (grid-types 심 경유). 실제 런타임 동작은 FullTable의 `adaptColumns` 어댑터 덕분에 정상.

**Primary recommendation:** `grid-types.ts`를 AG Grid 네이티브 타입(`ColDef`, `ICellRendererParams`)으로 교체하고, `@mui/x-data-grid`를 `package.json`에서 제거한 후 `npm install`로 정리한다. 53개 DataConfig 파일의 import 경로는 그대로 유지하되 타입 정의가 바뀌므로 `params.row` 의존 코드를 검토해야 한다.

---

## Current Migration State (실제 코드베이스 조사 결과)

### 이미 완료된 작업

| 항목 | 상태 | 파일 |
|------|------|------|
| FullTable.tsx AG Grid 전환 | **완료** | `src/components/table/FullTable.tsx` |
| ag-grid-community 35.2.1 설치 | **완료** | `package.json` + `node_modules/` |
| ag-grid-react 35.2.1 설치 | **완료** | `package.json` + `node_modules/` |
| AG Grid Quartz 테마 적용 | **완료** | FullTable.tsx 내 CSS import |
| 스페인어 로케일 파일 생성 | **완료** | `src/components/table/ag-grid-locale-es.ts` |
| adaptColumns() 어댑터 | **완료** | FullTable.tsx 내 구현 |
| localStorage 컬럼 너비 저장 | **완료** | FullTable.tsx 내 구현 (추가 기능) |
| ProductListTable (별도 컴포넌트) | **완료** | `src/views/homes/components/ProductList/components/ProductListTable.tsx` |
| 18-01-PLAN.md 존재 | **완료** | Planning 파일 |

### 남은 작업

| 항목 | 상태 | 영향 범위 |
|------|------|----------|
| `grid-types.ts` AG Grid 타입으로 교체 | **미완** | 1개 파일 |
| `@mui/x-data-grid` package.json에서 제거 | **미완** | package.json |
| `columns.tsx` 타입 어노테이션 업데이트 | **미완** | 1개 파일 |
| 53개 DataConfig 타입 어노테이션 | **선택적** | 런타임은 이미 동작 중 |

---

## Standard Stack

### Core (이미 설치됨)
| Library | Version | Purpose | Status |
|---------|---------|---------|--------|
| ag-grid-community | 35.2.1 | AG Grid 핵심 로직 + 타입 | **설치 완료** [VERIFIED: npm registry] |
| ag-grid-react | 35.2.1 | React AgGridReact 컴포넌트 | **설치 완료** [VERIFIED: npm registry] |
| @mui/x-data-grid | 6.0.3 | 제거 대상 | **아직 존재** [VERIFIED: package.json] |

### 제거 대상
```bash
# package.json에서 @mui/x-data-grid 제거 후
npm install
```

### AG Grid v35 특이사항 [VERIFIED: 코드베이스 grep]
- `AllCommunityModule` + `ModuleRegistry.registerModules()` 방식 사용 (v32+ 방식)
- CSS: `ag-grid-community/styles/ag-grid.css` + `ag-grid-community/styles/ag-theme-quartz.css`
- 테마 prop: `theme="legacy"` — 새 Theming API가 아닌 CSS 클래스 기반 방식 사용
- `rowSelection` 타입: `'multiple'` | `'single'` | `undefined` (v32+에서 객체 방식도 지원하지만 문자열도 호환)

---

## Architecture Patterns

### 현재 FullTable.tsx 구조 (완료)

```
FullTable props (그대로 유지)
├── data: { data: T[], count: number } | T[]
├── columns: MUI-style GridColDef[]  (adaptColumns로 자동 변환)
├── paginationModel: { page, pageSize }
├── setPagination: (model) => void
├── setRowSelected: (ids) => void
├── checkboxSelection: boolean (default: true)
├── onRowClick: (params: { row: any }) => void
├── hideFooter: boolean
├── loading: boolean
├── fillHeight: boolean
└── storageKey?: string  (localStorage 키 접두어)
```

```
adaptColumns() 어댑터 (FullTable.tsx 내부)
├── field, headerName, sortable, resizable 매핑
├── flex, minWidth, width 매핑
├── align/headerAlign → cellStyle/headerClass 매핑
├── valueGetter: params.row → params.data 브리지
└── renderCell: params.row → params.data 브리지 (핵심)
```

### grid-types.ts 교체 패턴

**현재 (교체 필요):**
```typescript
// grid-types.ts — @mui/x-data-grid에 의존
export type { GridColDef, GridRenderCellParams } from '@mui/x-data-grid'
```

**교체 후 (AG Grid 네이티브 타입):**
```typescript
// grid-types.ts — AG Grid 네이티브 타입
import type { ColDef } from 'ag-grid-community'

// GridColDef = AG Grid ColDef (하위 호환)
export type GridColDef = ColDef

// GridRenderCellParams: adaptColumns가 { row, value, data } 주입
// params.row는 AG Grid가 아닌 adaptColumns 어댑터가 제공
export interface GridRenderCellParams {
  row: any
  value: any
  data?: any
  [key: string]: any
}
```

**핵심 이유:** `params.row`는 AG Grid 네이티브 타입에 없음. `adaptColumns`가 `{ ...params, row: params.data }` 형태로 주입하므로, 런타임은 이미 동작하지만 TypeScript 타입을 위해 커스텀 인터페이스가 필요하다.

### DataConfig 파일 패턴 (53개 — 타입 어노테이션만 변경)

**현재 패턴 (변경 전):**
```typescript
// 모든 DataConfig 파일의 공통 패턴
import { GridColDef, GridRenderCellParams } from 'src/components/table/grid-types'

export const columns = (actions: any): GridColDef[] => {
  return [
    {
      field: 'name',
      renderCell: (params: GridRenderCellParams) => titleColumn(params.row.name)
    }
  ]
}
```

**grid-types.ts 교체 후 동작:**
- import 경로는 그대로 (`src/components/table/grid-types`)
- `GridColDef` = `ColDef` (AG Grid) — 타입 호환
- `GridRenderCellParams` = 커스텀 인터페이스 (`{ row: any, value: any }`) — `params.row` 유지
- **런타임에서 이미 동작 중이므로 53개 DataConfig 파일 내용 수정 불필요**

### columns.tsx 패턴 (renderCell 헬퍼)

```typescript
// 현재: GridRenderCellParams 타입 사용 (grid-types 심 경유)
// 교체 후: grid-types.ts의 커스텀 GridRenderCellParams 인터페이스 사용
// import 경로 변경 불필요

// 헬퍼 함수들은 params.row를 직접 사용 (4개 함수):
export const dateTimeColumn = (params: GridRenderCellParams, field = 'createdAt') => {
  const date = DateTime.fromISO(params.row[field])...  // params.row 사용
}
export const dateColumn = (params: GridRenderCellParams, field = 'createdAt') => {
  const date = DateTime.fromISO(params.row[field])...  // params.row 사용
}
export const emailAndPhoneColumn = (params: GridRenderCellParams) => {
  // params.row.email, params.row.phone 사용
}
export const actionsColumn = (actions: any) => ({
  renderCell: (params: GridRenderCellParams) => actions(params.row)  // params.row 사용
})
```

**actionsColumn 특이사항:** `renderCell`을 포함한 객체를 반환하는 팩토리 함수. `adaptColumns`가 이 `renderCell`을 `cellRenderer`로 감싸므로 런타임 정상 동작.

### 4개 "직접 사용" 파일 — 실제로는 모두 FullTable 사용

CONTEXT.md에서 "직접 DataGrid 사용"으로 분류된 4개 파일을 검증한 결과:

| 파일 | 실제 사용 | DataGrid 렌더링 여부 |
|------|---------|-------------------|
| `GlobalClientesView.tsx` | `FullTable` | 없음 |
| `CargaMasivaClientesView.tsx` | `FullTable` | 없음 |
| `CajaFuerteOperationsTable.tsx` | `FullTable` | 없음 |
| `ClienteVistaView.tsx` | `FullTable` | 없음 |

**결론:** `<DataGrid>` JSX를 직접 렌더링하는 파일은 코드베이스에 존재하지 않는다. 이 4개 파일은 `GridColDef` 타입을 grid-types 심에서 가져오고, 인라인 `renderCell` 정의를 포함하며, `FullTable`에 props로 전달한다. `adaptColumns` 어댑터가 이미 처리한다.

**단, 이 파일들의 인라인 renderCell에서 `params.row` 사용 패턴 확인:**
- `GlobalClientesView.tsx`: `params.row.isActive`, `params.row.fullname`, `params.row.nameFantasy`, `params.row` (callback)
- `CajaFuerteOperationsTable.tsx`: `params.row.type` (2곳)

grid-types.ts 교체 시 `GridRenderCellParams` 인터페이스에 `row: any`가 유지되면 이 파일들도 타입 에러 없음.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| params.row 브리지 | 직접 cellRenderer 구현 | adaptColumns() 어댑터 (이미 존재) | 53개 DataConfig 파일 수정 불필요 |
| 스페인어 로케일 | 직접 번역 | ag-grid-locale-es.ts (이미 존재) | 이미 완성됨 |
| 컬럼 너비 저장 | localStorage 직접 조작 | FullTable.tsx 내장 (이미 존재) | 경로 기반 자동 키 생성 포함 |
| 서버사이드 페이지네이션 | AG Grid 내장 SSRM | MUI Pagination 컴포넌트 (이미 구현) | AG Grid SSRM은 Enterprise, MUI Pagination이 더 유연 |

---

## Common Pitfalls

### Pitfall 1: grid-types.ts에서 직접 ColDef 타입 export
**What goes wrong:** `export type { ColDef as GridColDef } from 'ag-grid-community'`로 하면 AG Grid `ColDef`에는 `renderCell` 속성이 없어서 타입 에러 발생.
**Why it happens:** `renderCell`은 MUI 고유 속성, AG Grid는 `cellRenderer` 사용.
**How to avoid:** `GridColDef`를 `ColDef & { renderCell?: any }` 형태의 확장 인터페이스로 정의. 또는 `any`를 사용하거나, adaptColumns에서 알아서 처리하므로 `GridColDef = ColDef | any`도 방법.

**권장 접근법:**
```typescript
// grid-types.ts
import type { ColDef } from 'ag-grid-community'

// MUI 호환 확장 — renderCell을 허용하되 AG Grid 속성도 전부 포함
export type GridColDef = ColDef & {
  renderCell?: (params: GridRenderCellParams) => any
  renderHeader?: (params: any) => any
  align?: 'left' | 'center' | 'right'
  headerAlign?: 'left' | 'center' | 'right'
}

export interface GridRenderCellParams {
  row: any
  value: any
  data?: any
  field?: string
  [key: string]: any
}
```

### Pitfall 2: @mui/x-data-grid 제거 전 grid-types.ts 업데이트 순서
**What goes wrong:** grid-types.ts 업데이트 전에 @mui/x-data-grid를 package.json에서 삭제하면 TypeScript 컴파일 에러 발생.
**How to avoid:** 순서 엄수: (1) grid-types.ts 교체 → (2) package.json 수정 → (3) npm install

### Pitfall 3: columns.tsx의 actionsColumn renderCell
**What goes wrong:** `actionsColumn`은 `{ renderCell: ... }` 객체를 반환. 타입이 `GridColDef`의 `renderCell`을 허용하는지 확인 필요.
**How to avoid:** 위 `GridColDef` 확장 타입이 `renderCell?: any`를 포함하면 자동 해결.

### Pitfall 4: ESLint no-unused-vars
**What goes wrong:** grid-types.ts를 수정하면서 미사용 import가 생기면 `@typescript-eslint/no-unused-vars` 에러로 빌드 실패.
**How to avoid:** grid-types.ts 교체 후 columns.tsx와 DataConfig 샘플 파일 ESLint 검증 필수.

### Pitfall 5: ag-grid-community CSS import가 Next.js에서 동작하지 않는 경우
**What goes wrong:** Next.js Pages Router에서 CSS를 컴포넌트에서 직접 import 시 "Global CSS cannot be imported from files other than your Custom <App>" 에러.
**Current status:** FullTable.tsx에서 이미 import하고 있고 동작 중이므로 문제없음. [VERIFIED: 현재 코드베이스]

### Pitfall 6: lines-around-comment ESLint 규칙
**What goes wrong:** grid-types.ts에 주석을 추가할 때 주석 바로 위에 빈 줄 없으면 ESLint 에러.
**How to avoid:** 모든 `//` 주석 위에 빈 줄 추가.

---

## Code Examples

### grid-types.ts 교체 예시

```typescript
// Source: codebase analysis + ag-grid-community v35 types
import type { ColDef } from 'ag-grid-community'

// MUI DataGrid 호환 래퍼 타입 — renderCell 허용
export type GridColDef = ColDef & {
  renderCell?: (params: GridRenderCellParams) => any
  renderHeader?: (params: any) => any
  align?: 'left' | 'center' | 'right'
  headerAlign?: 'left' | 'center' | 'right'
}

// adaptColumns가 { row: params.data, value: params.value } 주입
export interface GridRenderCellParams {
  row: any
  value: any
  data?: any
  field?: string
  [key: string]: any
}
```

### package.json @mui/x-data-grid 제거

```json
// 제거할 줄:
"@mui/x-data-grid": "^6.0.3",

// 유지 (이미 있음):
"ag-grid-community": "^35.2.1",
"ag-grid-react": "^35.2.1",
```

### FullTable.tsx — 현재 구현 요약 (변경 불필요)

```typescript
// 현재 FullTable.tsx 핵심 동작 패턴 (이미 완성됨)
// Source: ventago-app/src/components/table/FullTable.tsx

// 1. AllCommunityModule 등록
ModuleRegistry.registerModules([AllCommunityModule])

// 2. adaptColumns: MUI GridColDef[] → AG Grid ColDef[]
const adaptColumns = (muiColumns: any[]): ColDef[] => {
  return muiColumns.map((col) => {
    const agCol: ColDef = { ... }
    // renderCell → cellRenderer 래핑 (params.row 주입 포함)
    if (col.renderCell) {
      agCol.cellRenderer = (params: any) =>
        col.renderCell({ ...params, row: params.data, value: params.value })
    }
    return agCol
  })
}

// 3. AgGridReact 렌더링
<AgGridReact
  theme="legacy"
  columnDefs={columnDefs}
  rowSelection={checkboxSelection ? 'multiple' : undefined}
  localeText={AG_GRID_LOCALE_ES}
  suppressCellFocus
  rowHeight={42}
/>

// 4. 커스텀 MUI Pagination (서버사이드)
<Pagination count={totalPages} page={page + 1} onChange={handlePageChange} />
```

### columns.tsx — 업데이트 불필요한 이유

```typescript
// columns.tsx에서 params.row는 adaptColumns 어댑터로 이미 주입됨
// grid-types.ts GridRenderCellParams 인터페이스에 row: any가 있으면 타입 OK

export const dateTimeColumn = (params: GridRenderCellParams, field = 'createdAt') => {
  // params.row[field] — adaptColumns가 row = params.data를 주입하므로 동작
  const date = DateTime.fromISO(params.row[field]).toFormat('MM-dd-yyyy');
  ...
}
```

---

## State of the Art

| Old Approach | Current Approach | Status |
|--------------|------------------|--------|
| `<DataGrid>` MUI 직접 사용 | `<AgGridReact>` (FullTable 래퍼 경유) | 이미 전환됨 |
| `GridColDef` MUI 타입 | `ColDef` AG Grid 타입 (grid-types.ts 경유) | 미완 |
| `GridRenderCellParams` | 커스텀 인터페이스 (`{ row, value }`) | 미완 |
| `@mui/x-data-grid` 설치 | 제거 | 미완 |

**AG Grid v35 주목할 변경사항:**
- `rowSelection`: 문자열 방식(`'multiple'`) 유지 가능 (현재 코드와 호환)
- `theme="legacy"`: CSS 클래스 기반 Quartz 테마 (현재 사용 중)
- `AllCommunityModule`: v32+에서 도입된 모듈 방식 (현재 사용 중)

---

## Runtime State Inventory

> 해당 없음 — 이 Phase는 라이브러리 교체 + 타입 변경이며 런타임 저장 상태 변경 없음.

| Category | Items Found | Action Required |
|----------|-------------|-----------------|
| Stored data | None | 없음 |
| Live service config | None | 없음 |
| OS-registered state | None | 없음 |
| Secrets/env vars | None | 없음 |
| Build artifacts | node_modules/@mui/x-data-grid | npm install로 자동 정리 |

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| ag-grid-community | FullTable.tsx | ✓ | 35.2.1 | — |
| ag-grid-react | FullTable.tsx | ✓ | 35.2.1 | — |
| @mui/x-data-grid | grid-types.ts (제거 대상) | ✓ | 6.0.3 | 제거 후 커스텀 타입 |
| Node.js + npm | npm install | ✓ | darwin | — |

---

## Validation Architecture

> workflow.nyquist_validation 설정 없음 — 기본 활성화

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Next.js 빌드 검증 (`next build`) + 브라우저 수동 확인 |
| Config file | next.config.js |
| Quick run command | `cd ventago-app && npx next build 2>&1 \| tail -30` |
| Full suite command | `cd ventago-app && npm run lint && npx next build` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | Notes |
|--------|----------|-----------|-------------------|-------|
| GRID-01 | TypeScript 컴파일 성공 | build | `npx next build` | types 교체 후 필수 |
| GRID-01 | ESLint 통과 | lint | `npm run lint` | no-unused-vars 위험 |
| GRID-01 | FullTable 렌더링 | manual | 브라우저 확인 | 이미 동작 중 |
| GRID-01 | @mui/x-data-grid 제거 | build | `npm ls @mui/x-data-grid` | 제거 후 확인 |

### Wave 0 Gaps
- 없음 — 기존 빌드 인프라 활용 가능

---

## Open Questions

1. **grid-types.ts의 GridColDef 타입 정의 방법**
   - What we know: `ColDef`에는 `renderCell` 속성이 없음. 53개 DataConfig 파일이 `renderCell`을 정의함.
   - Recommendation: `type GridColDef = ColDef & { renderCell?: any; align?: ...; headerAlign?: ... }`로 확장

2. **@mui/x-data-grid 제거 후 peer dependency 경고**
   - What we know: `@mui/x-data-grid`의 `@mui/system` 5.12.1을 직접 참조하는 package.json 항목 존재 (`"@mui/x-data-grid/@mui/system": "5.12.1"`)
   - What's unclear: 이것이 npm workspaces 오버라이드인지, 수동 추가인지
   - Recommendation: `@mui/x-data-grid` 제거 시 해당 줄도 함께 제거

3. **53개 DataConfig 파일 타입 어노테이션 — 필수인가?**
   - What we know: 런타임은 이미 동작 중. TypeScript 타입만 문제.
   - grid-types.ts를 올바르게 교체하면 53개 파일 내용 수정 없이 빌드 통과 가능.
   - Recommendation: grid-types.ts 교체 후 빌드 테스트로 확인. 에러 시 개별 파일 수정.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | 53개 DataConfig 파일은 grid-types.ts 교체만으로 타입 에러 없이 빌드 통과 | Architecture Patterns | 빌드 실패 시 개별 파일 수정 필요 |
| A2 | `@mui/x-data-grid` 제거 후 다른 MUI 컴포넌트에 영향 없음 | Standard Stack | MUI 컴포넌트들은 @mui/material에 의존하며 x-data-grid에 의존하지 않음 |

---

## Sources

### Primary (HIGH confidence)
- [VERIFIED: 코드베이스 직접 검사] `ventago-app/src/components/table/FullTable.tsx` — AG Grid 35.2.1 완전 구현 확인
- [VERIFIED: npm registry + node_modules] ag-grid-community@35.2.1, ag-grid-react@35.2.1 설치 확인
- [VERIFIED: package.json] @mui/x-data-grid@6.0.3 여전히 존재 확인
- [VERIFIED: 코드베이스 grep] grid-types.ts가 @mui/x-data-grid에서 re-export 확인
- [VERIFIED: grep 58개 파일] grid-types.ts 심에 의존하는 파일 목록 확인
- [VERIFIED: grep 결과] `<DataGrid>` JSX 직접 렌더링 파일 0개 확인

### Secondary (MEDIUM confidence)
- [ASSUMED] AG Grid v35 `ColDef` + 커스텀 확장 타입이 `renderCell` 패턴을 허용

---

## Metadata

**Confidence breakdown:**
- Current state analysis: HIGH — 코드베이스 직접 검증
- Remaining work scope: HIGH — 파일 수 및 변경 범위 확인
- Type replacement approach: MEDIUM — 빌드 테스트로 최종 확인 필요
- AG Grid v35 API: HIGH — 이미 동작하는 FullTable.tsx 코드 기반

**Research date:** 2026-04-13
**Valid until:** 2026-05-13 (ag-grid-community 35.x 안정 버전 기준)

---

## Planning Guidance (플래너에게)

**이 Phase의 실제 남은 작업은 매우 작다:**

1. **Wave 2 (grid-types.ts 교체)** — 1개 파일 수정
   - `grid-types.ts`: `@mui/x-data-grid` re-export → `ag-grid-community` `ColDef` + 커스텀 인터페이스
   - `columns.tsx`: import 경로는 그대로, 타입만 변경됨 (자동 호환)
   - 빌드 테스트로 53개 DataConfig 파일 타입 에러 확인

2. **Wave 3 (패키지 제거)** — package.json 수정 + npm install
   - `package.json`에서 `@mui/x-data-grid` 제거
   - `"@mui/x-data-grid/@mui/system": "5.12.1"` 줄도 함께 제거
   - `npm install` 실행
   - 최종 빌드 검증

**총 예상 파일 수정:** 2개 (grid-types.ts, package.json) + 빌드 에러 시 DataConfig 파일 개별 수정
