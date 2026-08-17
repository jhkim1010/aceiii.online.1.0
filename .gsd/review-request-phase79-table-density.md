# 자문 요청 — Phase 79: 표 행 높이 30px 통일, `size='small'` 표를 어떻게 할 것인가

당신은 이 저장소(Ventago POS/ERP — NestJS + Sequelize + PostgreSQL 18 + Next.js 13 Pages Router
+ MUI 5 + AG Grid Community)의 시니어 프론트엔드 리뷰어입니다. **비판적으로** 검토해 주세요.

## 배경 — 사용자 요구

> "시스템의 모든 표 행 높이를 30px 로 조정하고 싶다."

## 이미 배포한 것 (Phase 79 W1, app `c693102`)

1. `src/components/table/table-density.ts` 신설 — `TABLE_ROW_HEIGHT = 30`, `TABLE_HEADER_HEIGHT = 48`
2. `src/components/table/FullTable.tsx` (AG Grid 래퍼) 기본값 `rowHeight` **42 → 30** — 이 래퍼를 쓰는 **76개 파일**이 자동 반영
3. 개별 지정 6곳 제거(34·48·28·30×3), AG Grid 직접 사용 3곳(`FileTable`·`AccessLogsView`·POS `ProductListTable`)과
   react-arborist 트리 1곳(36→30)을 상수로 통일 → `rowHeight={숫자}` 리터럴 **0건**
4. 30px 행에서 액션 열의 **기본 `IconButton`(40px)이 넘치는** 문제를 FullTable 한 곳에서 압축:
   `'& .ag-cell .MuiIconButton-root': { padding: '2px' }`
5. `src/@core/theme/overrides/table.ts` 의 `MuiTableBody` 셀 세로 패딩 `spacing(3.5)`(14px) → `spacing(1.25)`(5px).
   해당 규칙의 셀렉터는 **원래부터** 이렇게 돼 있었다:
   ```
   '&:not(.MuiTableCell-sizeSmall):not(.MuiTableCell-paddingCheckbox):not(.MuiTableCell-paddingNone)'
   ```
   (`spacing = (factor) => ${0.25*factor}rem` → 4px × factor)

## 배포 후에 드러난 사실 — 5번이 사실상 no-op 이었다

앱 전체 `<Table>` 선언 **113개** 중

- **104개가 `<Table size='small'>`** → 셀에 `.MuiTableCell-sizeSmall` 이 붙어 위 셀렉터에서 **제외**됨
- 기본 크기(medium)는 **9개뿐** (`sales/details/ProductsTable`, `admin/revendedores`, `admin/tenants`,
  `admin/sesiones`, `admin/mensajes`, `dashboards/admin/CardLastAudit`, `reports/asistencia` 3개)

즉 "MUI `<Table>` 96개 파일이 일괄로 30px 가 된다"는 판단은 틀렸고, 실제로는 **9개만** 바뀌었다.

`size='small'` 104개의 분포: reports 33 · talleres 17 · ventas-online 9 · configuracion 9 · admin 6 ·
materia-prima 4 · homes(POS) 4 · codigo-vista 4 · legacy-import 3 · facturacion 3 · 기타 12

사용자가 특히 지목한 곳: **materia prima 4개 전량**, **talleres 컨트롤/탭 16개 전량**이 `size='small'` 이라
이번 변경에서 통째로 빠져 있었다.

## 결정해야 할 것

`MuiTableCell.sizeSmall` 에 세로 패딩을 명시해 104개를 한 번에 맞출 것인가, 맞춘다면 어떤 방식인가.

### 관측된 제약

- 이 표들은 화면마다 `sx={{ fontSize: 11 }}` ~ `13` 을 **직접** 주고 있어, 같은 패딩이어도 행 높이가 갈린다
  (MUI `sizeSmall` 기본 세로 패딩은 6px)
- **편집용 표**가 섞여 있다 — `talleres/cut-ticket/BomTable`, `SizeColorMatrixEditor`,
  `talleres/cost-sheet/CostSheetTable`, `materia-prima/InventarioView`(셀 안 TextField 34곳),
  `MovimientosView`(25곳) 등. `TextField size="small"` 은 40px 이다
- `SizeColorMatrixEditor` 는 이미 `'& .MuiTableCell-root': { padding: 0 }` + 셀별 `py: 0.3~0.4` 로
  **자기 패딩을 직접 관리**한다(`sx` 가 테마 styleOverrides 보다 우선)
- MUI `<tr>` 높이는 **내용이 정한다**(AG Grid 처럼 강제되지 않는다). 패딩 축소는 *최소* 높이만 낮춘다

### 내가 사용자에게 제안한 두 안

- **①** `sizeSmall` 세로 패딩만 줄인다. 텍스트 행 → 30px 근처, 입력이 든 편집 행 → 자기 높이 유지(안 잘림)
- **②** 텍스트 행에 `min-height: 30px` 까지 명시해 더 균일하게, 편집 행은 자동 확장 허용

나는 ①로 시작해 실측 후 필요하면 ②로 올리자고 제안했다.

## 질문

1. ① vs ② 중 무엇이 맞는가. 아니면 **셋째 길**(예: `Table size` 를 손대지 않고 밀도 전용 CSS 클래스/컴포넌트를
   도입, 또는 `MuiTableCell.sizeSmall` 대신 `MuiTable` 루트에서 `& .MuiTableCell-root` 로 거는 방식)이 나은가?
2. 화면별 `fontSize: 11~13` 이 제각각인 상태에서 "정확히 30px"를 목표로 삼는 것이 타당한가,
   아니면 **패딩만 일치**시키고 높이는 폰트에 맡기는 것이 맞는가?
3. 편집용 표(BomTable·CostSheetTable·InventarioView·MovimientosView)를 예외로 **명시적으로 빼야** 하는가,
   아니면 MUI 의 content-driven 높이에 맡기면 실제로 안전한가? 내가 놓친 깨짐 경로가 있는가?
4. AG Grid 쪽에서 `'& .ag-cell .MuiIconButton-root': { padding: '2px' }` 로 **모든 셀 버튼을 전역 압축**한 것이
   과한가? 터치 타깃(POS `/nueva-venta` 는 터치 입력)이나 접근성 관점에서 문제가 되는가?
   AG Grid 셀은 `overflow: hidden` 이라 넘치면 조용히 잘린다는 점을 고려해 달라.
5. `TABLE_ROW_HEIGHT`(AG Grid, px 강제)와 테마 패딩(MUI, 최소 높이)이 **같은 30 이라는 목표를 공유하지만
   서로 다른 메커니즘**이다. 이 둘이 나중에 조용히 갈라지지 않게 하려면 어떤 구조가 맞는가?
6. 그 밖에 이 접근에서 놓친 위험 — 특히 **회귀가 조용히 일어나는** 경로.

## 읽어야 할 파일

- `ventago-app/src/components/table/table-density.ts`
- `ventago-app/src/components/table/FullTable.tsx`
- `ventago-app/src/@core/theme/overrides/table.ts`
- `ventago-app/src/@core/theme/spacing/index.ts`
- `ventago-app/src/views/talleres/cut-ticket/components/BomTable.tsx`
- `ventago-app/src/views/talleres/cut-ticket/components/SizeColorMatrixEditor.tsx`
- `ventago-app/src/views/materia-prima/InventarioView.tsx`
- `ventago-app/src/views/talleres/control/talleres_ControlPanel.tsx`
- `.planning/phases/79-table-row-height-30px-unification/79-FINDINGS.md`
- `CLAUDE.md` (「성능 최적화 규약 › 프론트엔드 규약」에 이번에 추가한 표 밀도 규약)

## 출력 형식

`.gsd/review-codex-phase77.md` 와 같은 형식으로:
**총평** → **반드시 고쳐야 할 것(Blocker)** → **고치는 게 좋은 것(Should)** → **선택(Nice)**.
각 항목은 `[근거: 파일:줄]` 을 달고, **구체적 대안**을 제시할 것.
