# 자문 요청 — VentaVista 목록의 판매 번호를 "지점별 일련번호" 로 바꿀 것인가

## 사용자 요구 (2026-08-11)

1. 첫 칼럼 `Tipo` 제거 (의미 없다고 판단)
2. `VCode` 에 **그 지점에서 이루어진 판매의 순서 번호**만 표시. 매장 전체 누적 번호는 불필요
3. `Hora` 앞에 `Fecha` 칼럼 추가
4. (사용자 인식) "지금은 터미널마다 판매 번호를 시리얼로 붙이는 것 같다. 하루 번호는
   **지점별로 초기화**되고, 한 지점에 여러 터미널이 있으면 마지막 번호를 서로 차지하는 식이라
   한 지점에 몇 개의 판매가 있었는지 보기 어렵다"
5. 행 높이 20% 축소

## 내가 실측한 사실 (사용자 인식과 다른 부분 포함)

### 채번은 **터미널별이 아니라 매장별**이다
`sales-create.service.ts:784 reserveDailyNumber(storeId, tz, t, targetDate?)`
- `pg_advisory_xact_lock(storeId, saleDayLocal)` 로 **매장+영업일** 단위 직렬화
- UNIQUE: `uq_sales_store_daylocal_dn (store_id, sale_day_local, daily_number)
  WHERE activity_type='sale' AND daily_number > 0`
- `activity_type='sale'` 만 번호를 갖는다 (movido/fallado 는 잠식 안 함)

운영 실측 (store 6, 2026-08-11):
```
 id  | daily_number | terminal_id | branch_id |  sucursal
 143 |            1 |           6 |         6 | coolsistema
 144 |            2 |           6 |         6 | coolsistema
 146 |            3 |           6 |         6 | coolsistema
 150 |            4 |          36 |         6 | coolsistema
 151 |            5 |          36 |         6 | coolsistema
 153 |            6 |          36 |         6 | coolsistema
 154 |            7 |          36 |         6 | coolsistema
 155 |            8 |          36 |         6 | coolsistema
```
**터미널 6 과 36 이 하나의 연속 수열을 공유한다 (1..8 결번 없음).**
즉 "터미널마다 시리얼이라 서로 차지한다" 는 현상은 **일어나고 있지 않다.**

실제 남는 문제는 **지점이 2개 이상일 때 번호가 뒤섞인다**는 것이다
(store 6 = coolsistema + HELGUERA. 오늘은 HELGUERA 판매 0이라 깨끗해 보였을 뿐).

### `sales` 에 `branch_id` 가 **없다**
`origin_branch_id` / `target_branch_id` 는 Phase 35 의 movido/fallado 전용이다.
일반 판매의 지점은 `terminal_id → boxes.box_id → branches.branch_id` 로 유도한다.
(CLAUDE.md 에도 "sales 테이블은 branch_id 없음" 으로 명시)

### `daily_number` 는 **영수증에 인쇄된다**
`sales-create.service.ts:1861`:
```ts
number: `Ticket-${(sale.dailyNumber || sale.id).toString().padStart(6, '0')}`
```
`SaleDetailPanel.tsx:74` 도 `Detalle de Venta #{dailyNumber}` 로 노출.

### Tipo 칼럼은 색 tint 와 중복이지만 완전 중복은 아니다
`getActivityRowSx` 가 internet(cyan) / movido(blue) / fallado(red) 행에 배경+좌측 보더를 준다.
그러나 **Internet 행의 VCode 는 `o.orderNumber`** 로 판매 번호와 **다른 수열**이다
(`SalesListView.tsx:330`). 라벨을 지우면 같은 칼럼에 두 체계의 번호가 섞인다.

## 내가 생각하는 선택지

- **A. 신규 컬럼 `branch_daily_number`** — (branch, 영업일) 단위로 채번. 과거는 renumber
  하지 않고 오늘 이후부터. 영수증도 이 번호를 찍는다.
- **B. 표시 전용** — 목록 쿼리에서 `ROW_NUMBER() OVER (PARTITION BY branch, day ORDER BY ...)`.
  스키마 무변경. 다만 **화면 번호 ≠ 영수증 번호** 가 된다.
- **C. 기존 `daily_number` 의 채번 범위를 지점별로 변경 + 과거 renumber** — 이미 인쇄된
  영수증과 어긋난다.

## 묻고 싶은 것

1. **A/B/C 중 무엇인가, 아니면 다른 답이 있는가?** 특히 "화면 번호와 영수증 번호가
   달라지는 것" 의 실무 비용을 어떻게 보는가. 사용자는 번호로 판매를 찾는다.
2. **A 를 택하면 채번 경로를 어떻게 바꾸는가?** 지금은 매장+영업일 advisory lock 1개다.
   지점별 lock 으로 바꾸면 동시성은 좋아지지만, 판매 생성은 **핫 경로**이고 Phase 64 에서
   단일 트랜잭션·락 순서를 정리한 곳이다. 두 개의 번호(store 단위 + branch 단위)를
   같은 트랜잭션에서 채번하면 락을 2개 잡게 되는데 교착 위험은 없는가?
   아니면 store 단위 채번을 **없애고** branch 단위 하나만 남겨야 하는가?
   (store 단위를 없애면 UNIQUE 인덱스와 기존 조회·리포트가 영향받는다 — 어디를 봐야 하는가?)
3. **지점을 어떻게 확정하는가?** `sales` 에 branch 컬럼이 없다. 채번 시점에
   `dtoBranchId` 또는 `resolvedTerminalId → box → branch` 를 쓸 수 있는데,
   **terminal 이 null 인 판매**(caja 미개설 등)가 존재한다면 그 행의 지점은 무엇인가?
   컬럼을 새로 두는 게 맞는가(`branch_id` denormalize), 아니면 유도만으로 충분한가?
4. **Tipo 칼럼 제거가 안전한가?** 색 tint 가 대체하지만 Internet 행은 번호 체계가 달라
   같은 칼럼에서 구분이 사라진다. 어떻게 하는 게 맞는가?
5. **행 높이 20% 축소(42→34px)** — 현재 VCode 셀이 2줄(번호 + `#id`)이라 42px 에서도
   이미 잘려 보인다(스크린샷). 축소하려면 무엇을 먼저 정리해야 하는가?
6. 내가 놓친 것이 있는가? 특히 **일련번호를 바꾸면 깨지는 다른 곳**
   (리포트·AFIP 전자청구·영수증 재인쇄·오프라인 edge agent 채번 등).

## 배경 제약

- 판매 생성은 단일 트랜잭션 원칙 + 락 순서 고정(productId 오름차순) — Phase 64 규약
- 트랜잭션 안에서 외부 I/O 금지, 커밋 후 실패는 응답을 바꾸지 않는다
- 오프라인 edge agent 가 별도로 판매를 만들 수 있다(offline-sync) — 채번 충돌 가능성 검토 필요

---

# CODEX 회신 + 내 실측 검증 (2026-08-11)

## 결론: 내 A안은 기각. CODEX 의 **D안**이 맞다.

> `sales.branch_id` 를 판매 시점의 불변 스냅샷으로 추가하고, **기존 `daily_number`
> 컬럼의 의미를 배포 시점부터 `(branch_id, sale_day_local)` 일련번호로 전환**한다.
> 과거 행은 번호를 다시 매기지 않는다.

즉 **새 번호 컬럼을 만들지 않는다.** 사용자에게 번호를 두 개 노출하지 않고,
이미 인쇄된 영수증도 보존된다.

### 내 A안(`branch_daily_number` 신규 컬럼)이 기각된 이유
번호가 둘이 되면 "어느 화면이 어느 번호를 뜻하는가"를 영원히 설명해야 한다.
`dailyNumber` 를 실제로 쓰는 곳(전부 확인함):
- 판매 번호 검색 — `SaleReviewPanel.tsx:146`
- 취소 확인 — `SaleReviewPanel.tsx:219`
- POS 영수증 — `ProductList.tsx:1309`
- 수표 연결 — `ChequesView.tsx:269`
- 서버 재인쇄 — `sales-create.service.ts:1861` (`Ticket-000007`)
- 상세 제목 — `SaleDetailPanel.tsx:74`
- 리포트 raw SQL — `reportsItemsCockpit.service.ts:530`

### B(표시 전용 ROW_NUMBER) 기각
사용자가 번호로 판매를 찾는다는 요구와 정면 충돌. 정렬·필터·페이지네이션이 바뀌면
번호가 달라지고, 특히 **Internet 행은 프론트에서 merge** 되므로(`SalesListView.tsx:319`)
화면 계산 번호를 업무 식별자로 쓰면 안 된다. 잘못된 취소·잘못된 재인쇄로 이어진다.

### C(과거 renumber) 기각
이미 인쇄된 영수증과 어긋난다. (AFIP 법정 번호는 `afip_vouchers.afip_number` 로
별도 체계라 직접 깨지지는 않는다 — 확인함.)

## ★ 배포가 진짜 난관이다 (CODEX 지적, 내가 놓쳤던 것)

구 UNIQUE 인덱스 `(store_id, sale_day_local, daily_number)` 가 살아 있는 동안에는
**같은 매장의 두 지점이 같은 번호를 만들 수 없다.** 따라서
"신규 인덱스 생성 → 코드 배포 → 구 인덱스 제거" 라는 통상적 무중단 순서가
**성립하지 않는다.** 다음 중 하나가 필요하다:
- 짧은 쓰기 중단을 둔 원자적 cutover
- 임시 컬럼을 이용한 단계적 배포
- 모든 워커 동시 교체가 보장되는 배포 절차

## 락 — store 락을 **없애고** branch 락 하나만

두 번호를 병행하지 않으므로 락도 하나다. 병행하면 모든 경로(정상 판매/취소 역분개/
오프라인 동기화/향후 배치)가 같은 락 순서를 지켜야 하는데, 취소도 별도로
`reserveDailyNumber()` 를 부르므로(`sales-create.service.ts:911`) 한 곳만 빠뜨려도 교착이다.

```
reserveDailyNumber(branchId, tz, t, targetDate)
  WHERE branch_id = :branchId AND sale_day_local = :day AND activity_type='sale'
  lock key = (branchId, YYYYMMDD)
```
지점이 다르면 독립 진행 → 지금보다 경합이 **줄어든다**.

## 지점은 유도하지 말고 저장한다 (`sales.branch_id` denormalize)

유도만 유지하면: 터미널 없는 판매의 지점 확정 불가 / terminal↔box 재배치 시 과거 귀속이
바뀜 / 지점별 UNIQUE 를 표현 불가 / 조회마다 join / 취소가 원본 지점 계승 어려움.

생성 경로에는 이미 검증된 `resolvedBranchId` 가 있다(`sales-create.service.ts:399-410`,
`Branch.findOne({id, storeId})` 로 매장 소유권 검증). **단, 지금은 트랜잭션 밖에서
계산된다** — 채번의 입력이 되려면 락 이전으로 옮겨야 한다.

권고 정책: DTO 지점(소유권 검증) → 열린 caja 의 box.branch → 단일 지점 매장이면 그 지점 →
다지점인데 확정 불가면 **판매 거부**(사용자가 지점을 고르게). 취소는 원본 branch_id 계승.
과거 행은 nullable 로 두고 확정 가능한 것만 백필.

## 내가 실측으로 확인/보탠 것

### ① 사용자 전제 정정 — 터미널별 채번이 아니다
`reserveDailyNumber(storeId, ...)` = **매장+영업일** advisory lock.
운영 실측(store 6, 2026-08-11): 터미널 6·36 이 daily_number 1..8 을 **결번 없이 공유**.
"터미널이 마지막 번호를 서로 차지한다" 는 현상은 일어나고 있지 않다.

### ② "누적 번호" 는 `00007` 이 아니라 `#154`
`00007`(daily_number)은 매일 리셋된다. 누적인 것은 목록 둘째 줄의 전역 `sales.id` 였다.
→ **이건 이미 고쳤다** (`front 3f7a74f`: 둘째 줄 제거, 상세의 "ID interno" 로 이동).

### ③ 문제의 실제 발생 빈도 — 전 이력에서 **하루**
지점 2곳이 같은 날 판매한 날: `store 6 / 2026-08-10` 단 하루, 총 3건
(coolsistema #1 / HELGUERA #2·#3). 그래서 채번 전환은 **급하지 않다**.

### ④ ★ CODEX 도 못 잡은 것 — 채번 경로가 **둘**이다
`online-order-sales-mirror.service.ts:88-99` 는
- advisory lock 이 **없고**
- `saleDayLocal` 필터가 **없다** (주석은 "오늘의 마지막 sale + 1" 인데 where 에 날짜가 없다)
→ **전 이력 최대값 + 1** 을 쓴다.

실증: `sale 142` = `daily_number 21`, `sale_day_local NULL`, `terminal_id NULL`, −1000.
그날 실제 수열은 1..8인데 21이 존재한다. `sale_day_local` 이 NULL 이라 UNIQUE 인덱스도
비켜간다(PG 는 NULL 을 서로 다른 값으로 본다).

**지점별 채번을 얹기 전에 이걸 먼저 고쳐야 한다** — 안 그러면 서로 다른 구현이 셋이 된다.

### ⑤ `terminal_id` NULL 판매 19건
store 6 = 14건 / store 9 = 2건 / **store 11 = 3건(전부)**. 지점 유도 불가.
지점별 채번의 선행 결정 사항.

### ⑥ 오프라인 경로 — 위험 낮음, 다만 귀속 구멍 하나
오프라인 push 는 `SalesCreateService.create()` 를 재사용하므로 중앙에서 최종 번호를 받는다
(`offline-push.service.ts:262`). 오프라인 인쇄 번호는 별도 참조일 뿐이다.
다만 `branchId: sale.branchId ?? scope.branchId` (`:284`) 는 **payload 가 같은 매장의
다른 지점을 고를 수 있게** 한다. 인증된 `scope.branchId` 를 강제하는 편이 맞다.

## 결정 (2026-08-11, 사용자)

**1단계만 진행 — 표시 개선.** 완료: `front 3f7a74f`
- Tipo 칼럼 제거(표식은 Nº 셀로 흡수) / `#id` 제거 → 상세 "ID interno" / Fecha 추가
  (`sale_day_local` = 매장 타임존 영업일) / 행 42→34px / 필터 배너를 0건→상시로 확대

**2단계 보류 — 지점별 채번.** 두 번째 지점이 실제 운영에 들어갈 때 별도 Phase.
선행 순서:
1. 미러 채번 버그 수정 (④) ← 이것부터
2. `terminal_id` NULL 정책 (⑤)
3. `sales.branch_id` 추가 + 백필
4. cutover 설계 (구 UNIQUE 인덱스 문제)
5. 오프라인 귀속 강제 (⑥)
