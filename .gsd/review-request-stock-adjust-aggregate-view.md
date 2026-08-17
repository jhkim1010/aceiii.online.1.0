# 자문 요청 — 전 지점 합산 뷰에서 재고 수동 조정을 막는 방법

당신은 이 저장소(Ventago POS/ERP — NestJS + Sequelize + PostgreSQL 18 + Next.js 13 + MUI 5)의
시니어 리뷰어입니다. **비판적으로** 검토해 주세요. 구현 전 설계 단계입니다.

## 사용자 지적 (2026-08-17)

> "지금 모든 지점의 스톡 합계를 보는 화면인데 거기서 스톡을 수정한다는 것은 비논리적이다.
>  모든 지점 합산을 보는 화면에서는 수정 기능을 차단하고, **특정 지점을 보는 화면에서만**
>  수정 가능하게 해달라."

## 현재 구조 (내가 코드에서 확인한 것)

화면: `/reportes` → Stocks 코크핏
- **Panel A** `PanelA_BranchSummary` — 지점 요약. 행 클릭으로 지점 선택(`branchId`), 기본은 TOTAL(=null)
- **Panel B** `PanelB_ItemTable` — 제품 목록
- **Panel C** `PanelC_ColorMatrix` — 색상×talle 매트릭스. 셀 클릭 → `SelectedCell`
- **Panel D** `PanelD_StockAdjust` — 이론값 vs 실제값 입력 → 차이를 stocks 에 보정 행으로 INSERT

핵심 사실:
- 합산 보기(`branchId = null`)에서 매트릭스 셀의 **`productBranchId` 는 0 이다.**
  (`reportsStocksCockpit.matrix.spec.ts` 가 이 동작을 고정하고 있다: 여러 지점 행을 합산하고
  `productBranchId: 0`, `branchCount: 2`)
- Panel D 는 그 값을 그대로 `POST /reports/stocks-cockpit/adjust` 에 보낸다:
  ```ts
  productBranchId: selectedCell.productBranchId,
  realStock: realNum,
  ```
- 백엔드 `adjustStock()` 는 `ProductBranch` 를 조회해 소유 매장을 확인한다:
  ```sql
  SELECT pb.product_id, p.store_id FROM "ProductBranch" pb
    JOIN products p ON p.id = pb.product_id WHERE pb.id = :pbId LIMIT 1
  ```
  - 매장 사용자(`storeId != null`): pbId=0 → 행 없음 → `ownerStoreId = null` → `null !== storeId`
    → **ForbiddenException("otra tienda")** — 사유가 틀린 메시지다(다른 매장이 아니라 대상이 없다)
  - **superadmin(`storeId = null`)**: 소유 검증을 건너뛴다 → 이론값 0 조회 → stocks INSERT 시도
    → `product_branch_id = 0` 은 FK 위반으로 DB 에서 터진다(내 판단)
- Panel D 는 이미 이 사정을 알고 있다. 주석:
  *"통합 보기의 다중지점 셀은 productBranchId 가 전부 0 이라 그걸로 감시하면 셀을 옮겨도
  초기화가 안 된다"* — 즉 **0 이라는 것을 알면서도 저장 버튼은 그대로 열려 있다.**

## 내 계획 초안

1. **화면**: `branchId === null` (또는 `selectedCell.productBranchId <= 0`) 이면 Panel D 를
   입력 불가 상태로 두고, "지점을 선택하세요" 를 이유로 표시한다. 저장 버튼 비활성.
2. **서버**: `adjustStock()` 에서 `productBranchId` 가 유효 양수가 아니거나 대상 행이 없으면
   `BadRequest('productBranch 없음')` 으로 **명시적으로** 거부한다(지금은 매장 사용자에게
   "다른 매장" 이라는 틀린 사유가 간다. superadmin 은 FK 오류로 터진다).
3. Panel A 에서 지점을 고르면 정상 동작(현재와 동일).

## 질문

1. 이 접근이 맞는가? 화면만 막고 서버를 그대로 두면 안 되는 이유를 확인해 달라
   (이 저장소에는 Flutter 앱 등 다른 소비자가 있고, `/api/reports/*` 를 직접 호출한다).
2. **부분 선택 상태**가 더 있는가? 예: Panel A 에서 지점을 골랐지만 Panel C 가 여전히 합산 셀을
   들고 있는 경우(선택 잔존), 또는 `codigoMadreView`(부모 집계) 상태에서의 셀 — 이때
   `productBranchId` 는 무엇이고 조정이 의미가 있는가?
3. superadmin 이 전 매장 보기(`storeId=null`)일 때는 지점을 골라도 **매장이 섞인다**.
   이 경우 조정을 허용해야 하는가?
4. 조정 자체의 의미: 이 프로젝트의 `stocks` 는 append-only 원장이고 보정은 반대 부호 행으로
   한다(CLAUDE.md 「쓰기 경로 규약」). 합산 뷰에서의 조정을 "지점별로 안분해서 여러 행" 으로
   구현하자는 제안이 나올 수 있는데, 그 대안을 어떻게 보는가?
5. 막는 것 외에 **화면이 사용자에게 뭐라고 말해야** 하는가? (지금은 아무 설명 없이 저장이
   실패하거나, 매장 사용자에게 "다른 매장 권한 없음" 이라는 틀린 사유가 뜬다)
6. 그 밖에 놓친 위험 — 특히 **조용히 잘못된 지점에 반영될 수 있는** 경로.

## 읽어야 할 파일

- `ventago-app/src/views/reports/stocks/panels/PanelD_StockAdjust.tsx`
- `ventago-app/src/views/reports/stocks/panels/PanelC_ColorMatrix.tsx`
- `ventago-app/src/views/reports/stocks/panels/PanelA_BranchSummary.tsx`
- `ventago-app/src/views/reports/stocks/StocksCockpitBody.tsx`
- `api-ventago/src/app/reports/reportsStocksCockpit.service.ts` (`getMatrix`, `adjustStock`)
- `api-ventago/src/app/reports/reportsStocksCockpit.adjust.spec.ts`
- `api-ventago/src/app/reports/reportsStocksCockpit.matrix.spec.ts`
- `CLAUDE.md` 「쓰기 경로 규약 (Phase 64)」

## 출력 형식

**총평** → **반드시 고쳐야 할 것(Blocker)** → **고치는 게 좋은 것(Should)** → **선택(Nice)**.
각 항목에 `[근거: 파일:줄]` 과 **구체적 대안**을 붙일 것.
