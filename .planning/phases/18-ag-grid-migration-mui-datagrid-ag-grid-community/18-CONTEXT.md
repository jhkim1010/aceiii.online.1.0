# Phase 18: AG Grid Migration — Context

**Gathered:** 2026-04-13
**Status:** Ready for planning
**Mode:** 기술 마이그레이션 — MUI DataGrid Free → AG Grid Community

<domain>
## Phase Boundary

MUI DataGrid Free (v6.0.3)를 AG Grid Community로 완전 교체. FullTable 래퍼 중심 마이그레이션으로 61개 화면 자동 전환, 4개 직접 사용 파일 개별 마이그레이션, 51개 DataConfig 타입 전환. @mui/x-data-grid 패키지 완전 제거.

</domain>

<decisions>
## Implementation Decisions

### 활성화할 AG Grid 기능
- **D-01:** 컬럼 리사이즈 — 모든 테이블에서 컬럼 드래그 리사이즈 활성화
- **D-02:** 컬럼 고정(Pin) — 좌/우 컬럼 고정 지원 (defaultColDef에 pinnable 설정)
- **D-03:** 필터 UI — 컬럼 헤더 필터 아이콘 활성화 (기본 텍스트/숫자/날짜 필터)
- **D-04:** 행 드래그 정렬 미포함 — Phase 범위 외

### 마이그레이션 전략
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

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### FullTable 래퍼
- `ventago-app/src/components/table/FullTable.tsx` — 현재 MUI DataGrid 래퍼 (마이그레이션 핵심 대상)

### columns.tsx 공유 헬퍼
- `ventago-app/src/components/table/columns.tsx` — 23+개 renderCell 헬퍼 (AG Grid cellRenderer로 전환)

### DataConfig 파일 (51개)
- `ventago-app/src/views/**/components/*DataConfig.tsx` — GridColDef → ColDef 타입 전환 대상

### 직접 DataGrid 사용 파일 (4개)
- `ventago-app/src/views/admin/clientes/GlobalClientes*.tsx`
- `ventago-app/src/views/productos/components/CargaMasiva*.tsx`
- `ventago-app/src/views/caja-fuerte/CajaFuerte*.tsx`
- `ventago-app/src/views/talleres/vendors/components/talleres_VendorDetailPanel.tsx` (또는 ClienteVista)

### 프로젝트 컨벤션
- `.planning/codebase/CONVENTIONS.md` — ESLint 규칙
- `CLAUDE.md` — 프로젝트 전체 규칙

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `FullTable` 래퍼가 모든 테이블의 단일 진입점 — 이 파일만 바꾸면 61개 화면 자동 전환
- `columns.tsx` 공유 헬퍼 — MUI renderCell → AG Grid cellRenderer 매핑 필요
- `CardFilter` 컴포넌트 — 테이블 외부 필터 (AG Grid 필터와 별개)

### Established Patterns
- DataConfig 파일: GridColDef[] 배열을 export하는 패턴
- FullTable props: columns, rows, pageSize, onPageChange, onRowClick, checkboxSelection 등
- 서버사이드 페이지네이션: page/pageSize → API 호출 → rows + totalCount

### Integration Points
- package.json: @mui/x-data-grid 제거, ag-grid-community + ag-grid-react 추가
- FullTable.tsx: 내부 구현만 교체, props 인터페이스 유지
- 테마: MUI DataGrid 커스텀 스타일 → AG Grid 테마 매핑

</code_context>

<specifics>
## Specific Ideas

- AG Grid Community Edition 사용 (라이선스 무료)
- defaultColDef에 resizable:true, sortable:true, filter:true 기본 설정
- pinnedLeftColumns/pinnedRightColumns 지원
- AG Grid Alpine 또는 Quartz 테마 사용
- 기존 MUI DataGrid 커스텀 스타일을 AG Grid CSS 변수로 매핑

</specifics>

<deferred>
## Deferred Ideas

- 행 드래그 정렬 (상품 순서 변경 등)
- Excel 내보내기 (AG Grid Enterprise 기능)
- 그룹핑/피벗 (Enterprise)
- 서버사이드 정렬 전환

</deferred>

---

*Phase: 18-ag-grid-migration*
*Context gathered: 2026-04-13*
