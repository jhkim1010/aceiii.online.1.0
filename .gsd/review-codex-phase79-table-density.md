# CODEX 검토 결과 — Phase 79 표 밀도 (2026-08-17)

요청서: `.gsd/review-request-phase79-table-density.md`

## 총평

①을 채택하되, `size='small'` 전체를 무조건 "정확히 30px"로 만드는 방식이 아니라 **텍스트 중심의 compact 표는
30px 근처, 편집·다줄 콘텐츠는 자동 확장**하는 정책으로 정의하는 것이 맞습니다. ②의 `min-height`는 table
row/cell에서 일관되게 작동하지 않고, 콘텐츠가 큰 행의 높이도 통일하지 못하므로 실익이 없습니다.

다만 현재 구조를 그대로 확장하면 안 됩니다. `TABLE_ROW_HEIGHT`는 AG Grid의 강제 높이일 뿐 MUI Table의
높이를 제어하지 않으며, `MuiTableCell.sizeSmall` 전역 변경은 편집 행까지 영향을 줍니다. 또한 FullTable의 모든
`IconButton`을 시각적으로만 축소한 조치는 클릭·터치 타깃을 지나치게 줄입니다.

## 반드시 고쳐야 할 것 (Blocker)

### B1. `IconButton` 전역 압축을 액션 셀 전용 정책으로 축소
`[근거: ventago-app/src/components/table/FullTable.tsx:290]`

셀 안의 **모든** `IconButton`에 `padding: 2px`를 적용한다. 24px 아이콘이면 실제 버튼이 약 28px에 불과하며,
아이콘을 클릭해야 하는 모든 FullTable 화면의 포인터·터치 타깃이 함께 작아진다. 이 규칙은 버튼의 **시각 크기만**
줄일 뿐 접근 가능한 hit area를 확보하지 않는다.

대안:
- `field === 'action'`인 열에 전용 `cellClass`를 부여하고 **그 클래스 안에서만** 압축
- 액션이 하나면 행 전체 클릭 또는 30px 셀 전체를 hit area로
- 액션이 여러 개면 작은 버튼 여러 개 대신 **overflow 메뉴 1개**로 합치기
- 터치가 핵심인 표는 `TABLE_ROW_HEIGHT_TOUCH` 같은 명시적 예외를 두고 최소 40~44px 유지
- `title`만으로 접근 이름을 대신하지 말고 `aria-label`도 요구

★ POS의 직접 사용 AG Grid가 이미 30px라는 사실은 FullTable의 모든 버튼을 28px로 만들어도 안전하다는
근거가 아니다. **POS 표가 이 FullTable 전역 셀렉터를 사용한다는 근거도 없다.**

> **검증됨 (2026-08-17)**: `ProductListTable` 은 `FullTable` 을 쓰지 않는다(grep 0건) → 압축 규칙이 POS
> 상품 그리드에는 닿지 않는다. 반대로 **터치로 쓰는 POS 보조 목록은 FullTable 기반**이다 —
> `DraftAndDebtors` 의 삭제 버튼은 `size="small"`(30px)이었는데 이번 규칙으로 **약 24px 로 줄었다.**
> 즉 지적은 구체적 사례로 확인된다.

### B2. "MUI Table도 동일한 30px를 보장한다"는 단일 출처 규약 수정
`[근거: table-density.ts:7, @core/theme/overrides/table.ts:33, CLAUDE.md:298]`

AG Grid의 `rowHeight={30}`은 콘텐츠와 무관한 **강제 높이**지만, MUI Table은 글꼴 line-height, 셀 padding,
Chip·버튼·입력기·다줄 콘텐츠 중 **가장 큰 요소가** 행 높이를 결정한다. 현재 주석과 규약은 서로 다른 메커니즘을
같은 결과로 표현하고 있어, 이후 변경자가 "상수 하나만 바꾸면 모두 정확히 맞는다"고 **다시 오판**할 수 있다.

대안 — 토큰을 값 하나가 아니라 **정책 객체**로:
```ts
export const TABLE_DENSITY = {
  compactRowHeight: 30,
  compactCellPaddingY: 4,
  headerHeight: 48,
  touchRowHeight: 44,
} as const
```
문서는 넷을 구분해야 한다: AG Grid compact(강제 30px) / MUI compact text row(30px 목표의 padding) /
편집·다줄 MUI row(자동 확장) / 터치 조작 행(별도 최소 타깃).
공용 토큰은 `components/table` 아래보다 **테마와 컴포넌트 양쪽에서 의존 가능한 중립 경로**가 안전하다.

## 고치는 게 좋은 것 (Should)

- **S1. ① 적용하되 `sizeSmall` 과 제품 compact 정책을 장기적으로 분리**
  이번 범위에선 `MuiTableCell.sizeSmall` body padding 축소가 104개 표를 복구하는 가장 현실적 방법.
  `spacing(1)` 또는 실측값을 적용하되 **"정확한 30px"를 선언하지 말 것.**
  장기적으로 `<Table size='small'>` 이 MUI 크기 옵션인지 Ventago 의 30px 계약인지 모호하므로
  `CompactTable` 래퍼나 `className='table-density-compact'` 도입이 낫다. `MuiTable` 루트의 모든
  `.MuiTableCell-root` 에 거는 방식은 `paddingNone`·체크박스·자체 밀도 표까지 덮으므로 **더 위험**하다.
- **S2. ②의 `min-height` 안은 폐기** — `tr`/`table-cell` 의 `min-height` 는 신뢰할 수 없다.
- **S3. 편집 표를 "자동 확장되니 안전"으로 간주하지 말고 명시적 density variant 로 분류**
  compact padding 이 더해지면 40px 입력기 + 상하 padding 으로 **48~50px 가 되어 오히려 커질 수** 있다.
  helper text·multiline·Select·adornment·validation 이 붙으면 더 커진다.
  읽기 중심(`BomTable`)은 compact, 셀 편집기가 본문에 있는 화면(`CostSheetTable`·`InventarioView`·
  `MovimientosView`)은 `density='editable'` 전용 클래스로.
  `SizeColorMatrixEditor` 는 이미 실질적 예외로 동작 — 그 사실을 주석·테스트로 명시할 것.
- **S4. 본문과 헤더 밀도 정책 분리 문서화** — `MuiTableBody` 만 바꾸면 `sizeSmall` 헤더는 MUI 기본 padding 을
  유지해 **헤더가 본문보다 높아질** 수 있다. "모든 표 행"에 헤더가 포함되는지 명시할 것.
- **S5. 정확한 30px 대신 허용 범위(예: 29~32px)로 검증** — font 11~13px 이 섞인 상태에서 정확값은 보장 불가.
  정확한 30px 가 계약이라면 `fontSize`·`lineHeight`까지 토큰화해야 한다.
- **S6. 테마 우선순위에 의존한 예외를 회귀 테스트로 고정** — `sx > theme styleOverrides` 라는 구현 우선순위에
  기대고 있어 selector specificity 가 올라가거나 `!important` 가 들어오면 조용히 깨진다.
  대표 fixture: 텍스트 sizeSmall / Chip·IconButton 행 / TextField 편집 행 / 2줄 텍스트 행 /
  체크박스·paddingNone 행 / SizeColorMatrixEditor / FullTable 액션 행.

## 선택 (Nice)

- **N1. compact 계약 위반 탐지 보조 검사** — `rowHeight={숫자}` grep 만으로는 `sx`·`height`·`py`·큰 자식·
  다줄 렌더러를 못 잡는다. ESLint/CI 스크립트로 경고.
- **N2. 시각 회귀 기준을 콘텐츠 유형별로 보관** — 스크린샷 비교 + `getBoundingClientRect().height` assertion.
- **N3. 빈 상태·합계 행·의도적 다줄 행은 compact 측정 대상에서 제외 표시** — 빈 상태 `py: 4`, 합계 강조,
  BOM 보조 텍스트 2줄을 회귀로 오판하지 않도록 데이터 행/편집 행/합계 행을 구분.
