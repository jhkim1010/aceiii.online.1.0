# 자문 요청 — 재고 매트릭스 인라인 일괄 수정(Editar → Confirmar)

당신은 이 저장소(Ventago POS/ERP — NestJS + Sequelize + PostgreSQL 18 + Next.js 13 + MUI 5)의
시니어 리뷰어입니다. **비판적으로** 검토해 주세요. 구현 전 설계 단계이며, 이후 GSD phase 로
계획을 만들 예정입니다.

## 사용자 요구 (2026-08-17 원문 요약)

> 제품 하나를 고르면 오른쪽에 "Variantes & Stock" 매트릭스가 보인다. 거기 **HVenta 오른편에
> `Editar` 체크박스**를 두고, 체크하는 순간 매트릭스가 **편집 가능**해지면 좋겠다.
> - 각 입력칸에는 **기존 스톡 값이 채워져** 있고 새 값을 입력받는다
> - 그 아래에 **얼마의 보정치가 들어가는지** 살짝 보여준다
> - `Editar` 를 누르면 매트릭스 아래 오른편에 **`Confirmar` 버튼**이 나타나고, 누르면
>   **각 variation 에 대해 수정값을 DB 에 기록**한다
>
> 이유: 지금은 variation 이 여러 개면 **셀 하나 선택 → 수정 → 확인**을 반복해야 해서 불편하다.
> 이 기능이 생기면 **아래쪽 `Ajuste manual`(Panel D) 이 필요 없어질 것 같다.**

## 현재 구조 (코드에서 확인)

- 화면: Stocks 코크핏 4패널. **Panel C** = 색상×talle 매트릭스, **Panel D** = 단일 셀 수동 조정
- 매트릭스 셀 타입:
  ```ts
  export interface SelectedCell {
    color: string; talle: string; stock: number;
    productBranchId: number;   // 기여 PB 가 유일할 때만 실제 id, 아니면 0
    branchCount: number;
    variantSku: string;
  }
  ```
- 서버 `getMatrix()` 주석: *"productBranchId 는 합산할 수 없다 … 기여 지점이 2곳 이상이면
  `productBranchId=0`(조정 불가 표식)으로 내보내고, 지점 수는 branchCount, 내역은 byBranch 로
  따로 알린다"*. 판정 기준은 `byBranch.length === 1`.
- 매트릭스 상단에 지표 체크박스가 이미 있다: `Ingreso · Venta · Stock · HIngreso · HVenta`
  (`METRIC_DEFS`, localStorage 저장). 사용자가 말한 "HVenta 오른편"이 이 줄이다.
- 조정 API: `POST /reports/stocks-cockpit/adjust` — **셀 하나**만 처리.
  오늘(2026-08-17) 다음을 방금 적용했다:
  - 권한 `@Auth(admin, gerente, superadmin)` (종전엔 `reporte-stocks:read` 만 있으면 됐다)
  - body 에 `branchId` 를 받아 `pb.branch_id` 와 대조(합산 화면·구버전 호출 차단)
  - 대상 PB 없으면 `NotFound`, 값 검증(양의 정수 등)
  - **트랜잭션 + `pg_advisory_xact_lock(80, pbId)`** 로 경합 제거
  - 이론값을 `stock_balances.available` 로 읽음(★ `on_hand` 은 예약분을 포함해 원장 합과
    다르다 — 운영 439 PB 중 44건이 정확히 reservado 만큼 차이)
  - 부모(código madre) PB 는 `trg_stocks_leaf_only` 로 금지 → 400 안내
- `stocks` 는 **append-only 원장**(`trg_stocks_immutable`). 보정은 반대 부호 행 INSERT.
  잔액은 `trg_stock_balances_apply` 가 같은 트랜잭션에서 반영.
- CLAUDE.md 규약: 하나의 업무 동작이 만드는 모든 행은 **하나의 트랜잭션**,
  여러 상품 행을 잠글 때는 **`productId` 오름차순 고정**, 트랜잭션 안에서 외부 I/O 금지.

## 내 초안

1. **`Editar` 토글**을 지표 체크박스 줄 오른쪽에 둔다. 켜면 각 셀이 숫자 입력칸이 되고
   현재 값이 채워진다. 입력칸 아래(또는 셀 안 작은 글씨)에 `Δ +3 / −2` 를 보여준다.
2. **`Confirmar`** 는 변경된 셀만 모아 **새 배치 엔드포인트** 하나로 보낸다:
   `POST /reports/stocks-cockpit/adjust-batch`
   - body: `{ branchId, items: [{ productBranchId, realStock }], note? }`
   - 서버: **하나의 트랜잭션**에서 `productBranchId` 오름차순으로 advisory lock →
     각 셀의 `available` 재조회 → diff 계산 → 원장 INSERT.
   - 부분 실패는 전체 롤백(원자성) — 일부만 반영되면 사용자가 무엇이 남았는지 알 수 없다.
3. **편집 불가 셀**: `productBranchId <= 0`(기여 PB 복수), 지점 미선택(합산 화면),
   부모 PB → 입력칸을 주지 않고 이유를 표시.
4. **Panel D 는 남긴다** — 단일 셀 조정과 히스토리 표시에 여전히 쓰이고, 없애면 되돌릴 수
   없는 UI 변경이 된다. `Editar` 가 켜져 있는 동안에는 Panel D 를 숨기거나 비활성.

## 질문

1. **낙관적 동시성**: `Confirmar` 는 화면에 로드된 시점의 값 위에서 만들어진다. 그 사이 다른
   사용자가 판매·입고로 재고를 바꿨다면, 절대값(`realStock`)을 그대로 보내면 **남의 변경을
   조용히 덮는다**. 이 저장소에는 같은 유형의 사고 이력이 있다(판매 수정 확인 단계는 "판정만이
   아니라 본 원본 상태도 되돌려 보내" 야 한다는 결론). 배치에도 **기대 기준값(expected
   baseline)** 을 실어 보내고 서버가 대조해야 하는가? 어긋난 셀만 실패시켜야 하는가,
   전체를 막아야 하는가?
2. **원자성 vs 부분 성공**: 20개 셀 중 3개가 기준값 불일치면 어떻게 해야 하는가?
   전체 롤백이 맞는가, 아니면 성공분을 커밋하고 실패 목록을 돌려주는 게 맞는가?
3. **잠금 순서·규모**: 셀이 수십 개면 advisory lock 을 수십 개 잡는다. CLAUDE.md 의
   "productId 오름차순" 규약과 어떻게 맞추는가? 락 수가 많을 때의 위험은?
   한 제품의 PB 들만 잠그므로 상한이 있는가?
4. **Panel D 제거 여부**: 사용자는 "필요 없어질 것 같다" 고 했다. 제거하면 잃는 것이 있는가?
   (예: 셀 하나만 고칠 때의 note 입력, 조정 결과 표시, 부모 PB 안내)
5. **감사(audit)**: 배치 조정은 원장에 N 행을 남긴다. `note` 를 배치 전체에 하나로 붙이는 것과
   셀마다 받는 것 중 무엇이 맞는가? 나중에 "이 보정들이 한 번의 실사에서 나왔다" 를 알 수
   있어야 하는가(배치 id)?
6. **UX 안전장치**: 실수로 큰 값을 넣는 것을 어떻게 막는가? (예: 총 보정량이 임계 초과 시 확인)
   `Editar` 를 끄면 입력을 버리는가 유지하는가?
7. **성능**: `Confirmar` 후 Panel B/C 재조회가 필요하다. 지금 구조에서 어떤 순서로 갱신해야
   깜빡임·응답 역전이 없는가(오늘 Panel C 에 요청 시퀀스 방어를 넣었다)?
8. 그 밖에 놓친 위험 — 특히 **조용히 잘못된 재고가 되는** 경로.

## 읽어야 할 파일

- `ventago-app/src/views/reports/stocks/panels/PanelC_ColorMatrix.tsx`
- `ventago-app/src/views/reports/stocks/panels/PanelD_StockAdjust.tsx`
- `ventago-app/src/views/reports/stocks/StocksCockpitBody.tsx`
- `api-ventago/src/app/reports/reportsStocksCockpit.service.ts` (`getMatrix`, `adjustStock`)
- `api-ventago/src/app/reports/reports.controller.ts` (`stocks-cockpit/adjust`)
- `api-ventago/src/app/reports/reportsStocksCockpit.adjust.spec.ts`
- `CLAUDE.md` 「쓰기 경로 규약 (Phase 64)」

## 출력 형식

**총평** → **반드시 고쳐야 할 것(Blocker)** → **고치는 게 좋은 것(Should)** → **선택(Nice)**.
각 항목에 `[근거: 파일:줄]` 과 **구체적 대안**을 붙일 것.
