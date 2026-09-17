# Phase 91 ① — 회수한 돈이 카하에 착지한다 (2026-09-17)

사용자 지시: 「① 카하 줄부터 바로」. `dp` 단축키보다 먼저, **오늘 새고 있는 돈 구멍**을 닫는다.

---

## 계기 (운영 실측 2026-09-17 14:55)

```
credit_payments  1건  267,600  결제수단 3(Banco)  영수증 'test 0917_01'  지점 6
credit_ledger    2건  payment_in 51,600 + 216,000
box_operations   0건   ← 받은 돈이 카하 어디에도 없다
```

외상 잔액은 정확히 줄었는데 267,600 이 들어온 흔적이 없었다.
`grep -rn "boxOperation|cashRegister" src/app/credit/` → **0건**.

---

## ★★ 착수하면서 핸드오프의 전제 하나가 뒤집혔다

DECISIONS·ROADMAP 은 `online-orders.service.ts:2432-2465`(`registerCobro`)를
**참조 구현**으로 지목했다. 실측 결과 **그대로 베끼면 안 되는 코드**였다.

**① 운영에서 한 번도 실행된 적이 없다.**
```sql
SELECT count(*) FROM box_operations WHERE description ILIKE 'Cobro env%';  → 0
```

**② POS 판매와 규칙이 다르다.**

| 경로 | box_operations 를 쓰는 조건 | 운영 실행 |
|---|---|---|
| POS 판매 `sales-create.service.ts:2260` | **`slug === 'efectivo'` 일 때만** | 매일 |
| `registerCobro` (지목된 참조 구현) | **결제수단 무관 전부** | 0건 |

Tesorería 의 `saldo` 는 `initial_amount + Σ box_operations`(`cashRegister.service.ts`)로
**물리적 서랍 잔액**이고, 야간 자동마감이 그 금액을 실제로 금고로 이체한다.
비현금을 넣으면 **서랍에 없는 현금이 금고로 간다** — 2026-08-13 사고와 같은 형태
(카하 125: 실입금 20,000 인데 잔액 1,380,000, 전액 금고 이체).

**③ 사용자가 겪은 그 건은 Banco 였다.** efectivo 만 넣으면 서랍은 정확해지지만
사용자의 「안 보인다」는 안 풀린다. 그리고 이 시스템에 은행 원장은 없다 —
`movements` 는 0행이고 box 종속, Mercadopago 만 `mp_movements` 라는 자기 레인이 있다.

⤷ **사용자 결정(2026-09-17): efectivo 는 카하, 비현금은 볼 자리를 함께 만든다.** → D-8

---

## 무엇을 지었나

### ①-a 카하 착지 — `CreditCashLandingService` (신규)

`api-ventago/src/app/credit/services/credit-cash-landing.service.ts`

- **efectivo 줄만** 서랍에 `ingreso` 로 기록한다. 판정은 **slug 로** — `payment_methods` 는
  매장마다 행이 따로 있어(efectivo 가 store 3·6·8·9·10·11 각각 + 전역 1번) id 를 상수로
  박으면 그 매장 외에는 전부 비현금이 된다.
- 현금이 섞여 있는데 **열린 서랍이 없으면 거부한다.** 비현금뿐이면 서랍을 **아예 보지 않는다**
  (송금을 받는 데 카하가 열려 있어야 할 이유가 없다).
- `apply_favor` 는 줄을 만들지 않는다 — 이미 받아 둔 favor 를 채무에 붙이는 회계 조작이라
  **새로 들어온 돈이 아니다.** 넣으면 같은 현금을 두 번 센다.
- 서랍은 **지점 기준**으로 찾는다(CLAUDE.md 「카하(Box) 규칙」). 연 사람이 누구든 그 세션이 답이다.

호출자 **셋**이 같은 구현을 쓴다:
1. `CreditPaymentService.registerPayment` — `/cuentas-corrientes` 회수·선납
2. `OnlineOrdersService.registerCobro` — 줄을 `cashLines` 로 넘기고 **자기 손으로는 안 쓴다**(이중 기록 금지)
3. `SalesSeniaService.createSaleWithSenia` — 같은 구멍이었다(운영 `sale_senias` 0행이라 피해는 없었다)

### 같은 트랜잭션 · 잠금 순서

카하 착지를 `registerPayment` 의 SERIALIZABLE 트랜잭션 **안**으로, 그리고 `store_clients`
잠금보다 **먼저** 넣었다.

- 종전 `registerCobro` 는 원장 커밋 **뒤에** 카하를 썼다 — 그 사이 실패하면 돈이 원장에만 남는다.
- 판매 취소 경로가 `cash_registers → store_clients` 순서로 잠근다. 반대로 잡으면 **교착**이다.
- `getOpenCashRegister` 에 `{ transaction, lock }` 을 추가했다. 잠그지 않으면 자동마감 cron 이
  세션을 닫고 정산하는 사이에 끼어들어, 그 `ingreso` 가 **영원히 금고에 반영되지 않는다.**

### 서버가 정하는 것

`POST /credit/payments` 컨트롤러가 `branchId` 를 **body 에서 안 받는다.** 그 값이 곧
"어느 서랍에 현금을 넣을 것인가" 다. `storeId`·`userId` 는 이미 같은 이유로 덮어쓰고
있었는데 `branchId` 만 빠져 있었다. `cashLines`·`cashDescription` 도 서버 내부 호출자 전용이다.

### ①-b 비현금 회수를 볼 자리

- `GET /api/credit/cobros-no-efectivo` (`CreditReportService.listCobrosNoEfectivo`)
  — `pm.slug NOT IN ('efectivo','favor')`. 지점 스코프는 **서버가 JWT 로 계산**한다.
  합계는 페이지가 아니라 **전체**다(대사용).
- Tesorería › Estado de Caja 에 카드 `CobrosNoEfectivoCard`.
  부제에 **「서랍 잔액에 더하지 않는다」**를 적었다 — 합칠 수 있는 것처럼 보이면 대사가 틀린다.

---

## 검증 (전부 실행해서 확인)

**로컬 DB 통합 시험** `src/app/credit/credit-cobro-caja.itest.ts` — **9/9**
(`npm run test:itest -- credit-cobro-caja`). mock 이 아니라 실제 PG 에 붙는다.

| 검사 | 무엇을 막는가 |
|---|---|
| efectivo 선납 → 서랍에 ingreso | `FOR UPDATE` + include 조합이 **실제로 도는가**(문법은 mock 이 못 잡는다) |
| 대조군: banco 는 서랍에 안 들어간다 | 「전 결제수단 기록」 구현 |
| 서랍 없으면 거부 + 원장도 안 남는다 | 조용한 건너뛰기 |
| **원장 실패 시 이미 쓴 서랍 기록도 사라진다** | **트랜잭션 갈라짐** |
| 대조군: 서랍 없어도 banco 는 통과 | 「항상 거부」 |
| 다른 사람이 연 서랍에도 착지 | userId 기준 조회로의 회귀 |
| 비현금이 cobros-no-efectivo 에 나온다 | 표시 경로 |
| 대조군: efectivo 는 안 나온다 | 같은 돈 이중 계상 |
| 지점 권한 0 → 빈 결과 (+ 지점 주면 보인다) | fail-closed 가 "쿼리가 죽어서" 가 아님 |

**단위 시험** `credit-cash-landing.service.spec.ts` 10/10 · `online-orders.service.spec.ts` 52/52.

**돌연변이로 대조군이 무는지 확인** — 통과만으로는 지켜지는지 알 수 없다:

| 돌연변이 | 결과 |
|---|---|
| efectivo 판정 제거(전부 통과) | 3건 실패 ✅ |
| 서랍 없을 때 조용히 건너뛰기 | 1건 실패 ✅ |
| 카하 착지를 트랜잭션 **밖**으로 | 「원장 실패 시…」 **1건만** 실패 ✅ (정확히 그 검사가 원자성을 잡고 있다) |

**그 밖**: api tsc 0 · api jest 17 suite / 181건 · 추가한 줄의 eslint 0 ·
`nest build` + `dist/main` 실제 부팅(DI 해소 확인, `/api/credit/cobros-no-efectivo` 라우트 매핑 확인) ·
app tsc 0 · app eslint 0 · 프론트 계약 spec 3 suite / 19건.

**운영 SQL 실측** — 새 조회를 운영 DB 에 직접 돌려 사용자의 그 건이 나오는지 확인:
```
 id | paid_at             | total_amount | method | receipt_no   | branch      | cliente
  1 | 2026-09-17 14:55:46 |       267600 | Banco  | test 0917_01 | coolsistema | GONZALEZ EDUARDO EMILIO
```

---

## CODEX 검토 (자동 훅이 안 돌아 수동으로 띄웠다 — 아래 「곁가지」 참조)

보고서: `.team/reviews/auto-root-d914335_api-ventago-2a0fe93f_ventago-app-f9a295b.md`
지적 **5건**. 근거를 하나씩 코드·운영 DB 와 대조했고 **4건을 고쳤다.**

| # | 지적 | 판정 | 조치 |
|---|---|---|---|
| P2 | `filterEfectivo` 가 **해석 안 된 결제수단 id 를 조용히 비현금**으로 넘긴다. 매장 경계도 없다 | **맞다 — 가장 중요** | 자기 매장 + 전역(`store_id IS NULL`)으로 제한. 하나라도 해석 안 되면 **거부** |
| P1 | `user.branchId`(홈 지점)만 보면 **지점을 옮겨 일하는 사람**의 현금이 엉뚱한 서랍으로 간다. `branchId` 가 null 이면 **사용자 기준 폴백** | **맞다** | `resolveActiveBranchId` 신설(`x-branch-id` 를 허용 목록으로 검증). 지점 미확정 + 현금이면 **거부** |
| P2 | Seña 는 `branchId` 를 **여전히 body 가 소유**한다 | **맞다** | 같은 판정을 쓴다 — 두 경로가 갈라지면 한쪽이 우회로가 된다 |
| P1 | 혼합 결제를 **헤더 결제수단 하나로 판정**해 비현금 합계가 틀린다 | **맞다** | 한 영수증에 현금+비현금을 섞으면 **거부**. 근본 해법(영수증별 분할 행 저장)은 ② 의 몫 |
| P1 | `registerCobro` 가 원장 커밋 **뒤에** 주문을 갱신해, 재시도로 수금이 복제된다 | **맞다, 그러나 이번 변경이 만든 것이 아니다** | **보류** — 아래 |

### 근거 대조에서 확인한 것

- `x-branch-id` 는 **실제로 프론트가 매 요청에 싣는다**(`api.service.ts:108`, BranchContext 의 `selectedBranchId`).
- 운영 활성 사용자 17명 중 **1명이 `branch_id IS NULL`** — 그 사람의 현금 회수가 사용자 기준 폴백을 탔을 것이다.
- 검증에 `BranchScopeGuard` 를 **쓰지 않았다**: 그 가드는 `user_branches` 매핑만 보는데
  운영에 그 표가 4행뿐이라 정상 사용자 대부분이 403 이 된다. 판정은 `resolveAllowedBranchIds`
  하나로 모았다.

### 보류한 1건 — `registerCobro` 재시도 복제 (P1)

`registerPayment` 커밋 → 별도 트랜잭션으로 주문 `metadata.received` 갱신 → 소켓 emit.
뒤 단계가 실패하면 클라이언트는 오류를 받는데 원장·서랍은 남는다. 자동 생성 영수증 번호가
`Date.now()` 기반이라 재시도가 유니크 제약도 피한다.

**이번 변경이 만든 구조가 아니다** — 종전에도 같은 순서였다. 다만 이번에 `box_operations`
가 그 첫 트랜잭션에 들어갔으므로 **복제의 피해가 커졌다**(서랍 기록까지 중복된다).
안 고친 이유: 제대로 된 해법은 `credit_payments` 에 idempotency key 를 저장하는 것이고
그건 스키마 변경 + ②(dpago 판매)의 멱등 설계와 같이 가야 한다. 그리고 **이 경로는 운영
실행 0건**이다. ② 착수 시 함께 처리할 것.

### CODEX 2차 (수정분 재검토) — P1 1건, 내가 만든 것

`resolveActiveBranchId` 가 **「헤더 부재」와 「줬는데 무효」를 같은 답으로** 냈다.
후보 목록에서 순서대로 고르는 구조라 무효·타매장·무권한 헤더가 **조용히 홈 지점으로**
떨어졌다 — 화면은 B 지점에 넣었다 하고 현금은 A 지점에 남는다. 이 phase 가 없애고 있는
침묵 폴백과 같은 형태를 내가 새로 만든 것이다.

★ 더 나쁜 것은 **그 동작을 정답으로 고정한 시험을 내가 같이 써 놨다**는 것이다
(itest 「…무시하고 홈 지점으로 간다」 2건). 검사가 결함 있는 구현을 기준으로 삼으면
그 뒤로는 아무도 못 본다. 두 검사를 「거부한다」로 뒤집었다.

수정: 지정했으면 **그 값 하나만** 판정하고 실패 시 `ForbiddenException`. 없을 때만
홈 지점을 쓰되 그것도 검증한다. 돌연변이(거부 대신 홈 지점 폴백)로 거부 검사 2건만
죽고 대조군은 통과하는 것을 확인했다.

★★ **운영 영향 — push 전에 알아야 할 것.**
다지점 매장 4곳(CART·coolsistema·ACE·Sager)의 **비특권 사용자 7명**
(gerente 2 · vendedor 3 · cashier 1 · inventory_clerk 1)이 **홈 지점이 아닌 지점을
골라 둔 상태**로 회수를 등록하면 이제 **403** 을 받는다. `user_branches` 매핑은
운영에 6행뿐이다. admin 5명은 전 지점 권한이라 영향 없다.
종전에는 조용히 홈 지점 서랍으로 들어갔다 — 즉 **지금까지도 그 사람들의 기록은
틀려 있었고**, 바뀐 것은 그 사실이 보이게 된 것뿐이다.
필요하면 `user_branches` 에 매핑을 미리 넣어 두면 403 이 안 난다.

### CODEX 3·4차 — 수렴

| 라운드 | 결과 | 조치 |
|---|---|---|
| 3차 | P1/P2 **0건** · P3 1건 | `Number()` 는 10진 정수 파서가 아니다(`'0x10'`→16 · `'1e2'`→100 · `'+12'` · `'012'`). 변형된 헤더가 **다른 지점**으로 해석될 수 있다 → `^[1-9]\d*$` + `isSafeInteger` |
| 4차 | P2 1건 | 빈 `x-branch-id` 를 「미제공」으로 접었다 — 「보냈는데 못 읽는다」가 「안 보냈다」와 같은 답을 낸다. 부재는 `undefined` 하나로만 판정 |

★ 4차 P2 는 **실제 피해가 없다**: 헤더를 안 보내면 어차피 홈 지점이므로 `''` 로 얻는 것이
없고, 프론트는 값이 있을 때만 싣는다. 그래도 판정이 두 갈래로 갈라지지 않게 맞췄다.

★★ **한 번 받고 끝내면 안 된다.** 4라운드 중 **2건이 그 라운드에서 내가 새로 만든 결함**이었다
(2차 P1 침묵 폴백 + 그것을 정답으로 고정한 내 시험, 3차 P3 느슨한 파싱). 고친 것을 다시 넘길 것.

---

## 곁가지로 고친 것

**itest 하네스의 정리가 조용히 아무것도 안 지우고 있었다.**
`dropDummyStore` 의 `DELETE FROM etapas` 는 **존재하지 않는 표**다(실제 이름은
`talleres_etapas`). `run()` 이 오류를 삼켜 매장 삭제가 `talleres_etapas_store_id_fkey` 에
막혔고, 더미 매장이 계속 쌓였다(로컬에 5개 잔존 — 치웠다). credit·caja 계열
(`credit_ledger`·`credit_payments`·`sale_senias`·`box_operations`·`box_settlements`·
`cash_registers`) 정리도 없어서 함께 추가했다. `createImportHarness({ extraImports })` 로
임포트 말고 다른 모듈도 같은 배선으로 띄울 수 있게 했다.

---

## 남은 것 (이 커밋 범위 밖)

| # | 내용 |
|---|---|
| ② | `dpago` 판매 생성 (`sales` + `sale_items` 재고이동 없음 + `sale_payment_methods`) |
| ③ | AFIP 차단 + 대조군 (D-4) — `afip/auto-issue.ts:10` 은 결제수단을 안 본다 |
| ④ | 단독 규칙(D-2) 양방향 강제 — **서버가 섞인 요청을 거절**해야 한다 |
| ⑤ | `dp` 단축키 — `ProductsInputs.tsx:349` |
| ⑥ | 통계 현금 기준 전환(D-5) — ★ 반만 하면 이중계상 |
| ⑦ | 미수금 표시(D-7) |

**새로 발견해 남겨 둔 것:**
- **`registerCobro` 재시도 수금 복제**(CODEX P1) — 위 「보류한 1건」. ② 와 함께.
- ★ **CODEX 자동 검토 훅(PostToolUse)이 2026-09-16 18:52 이후 호출되지 않는다.**
  훅 스크립트는 정상이다 — 합성 입력을 직접 먹이니 바로 돌았다. 근거:
  훅이 실행마다 만드는 `.team/reviews/.auto-codex.run.*` 이 그 시각 이후 없다가
  수동 호출 때만 새로 생겼다. 같은 파일의 **PreToolUse(Bash) 게이트는 정상 동작**한다
  (실제로 이 작업의 커밋을 두 번 차단했다). `settings.json` 은 그 이후 변경 없음.
  ⤷ **push 전에 `.auto-codex.heads` 값을 매번 직접 확인할 것.** 멈춰 있으면 검토는 없다.
- **Seña 환불(`cancelSaleWithSenia`, `action:'refund'`)은 서랍에서 돈이 나가는데 `retiro` 를 안 쓴다.**
  입금 쪽과 **같은 형태의 반대 방향** 구멍이다. 안 고친 이유: 그 경로는 결제수단을 안 받고
  주석만 「en efectivo」 라, 원래 이체로 받은 seña 를 현금으로 돌려주는지가 **사용자 결정**이다.
  운영 `sale_senias` 0행이라 지금 새는 돈은 없다.
- 프론트 기존 버그: `ClientLedgerView.tsx:43-53` 의 `MOVEMENT_LABELS` 키가 대문자인데 백엔드는
  소문자(`payment_in`)를 준다 → 원장 표에 raw `payment_in` 이 보인다. `:289` 의
  `=== 'SENIA_RESERVE'` 는 영원히 false. (이번 범위 아님)
- `CreditPaymentModal` 은 `user.branchId` 를 보낸다. 서버가 같은 값을 쓰므로 동작은 같지만,
  **다른 지점에서 근무 중인 사람**(BranchContext 의 `selectedBranchId`)은 자기 홈 지점 서랍으로
  간다. 지금까지도 그랬다 — 바뀐 것은 없지만 기록해 둔다.

---

# ② 완료 (2026-09-17) — 회수가 정식 판매가 됐다

`.planning/ROADMAP.md` Phase 91 과 DECISIONS D-6 대로 A안. 커밋 `a3529d83`·`3840f54f`.

## 설계에서 뒤집힌 것 — `activity_type` 을 쓰면 안 된다

첫 후보였지만 틀렸다. `sales.service.ts` 가 여러 곳에서 `activityType='sale'` 로 거른다
(Phase 35 D-04 「매출 통계 무오염」). 새 값을 주면 회수 판매가 **목록·통계에서 전부
걸러진다** — 기간 통계에 넣으려는 D-6 과 정반대다.

→ `activity_type` 은 `'sale'` 그대로, 표식은 **`sales.credit_payment_id`**(nullable FK).
그 한 컬럼이 셋을 한다: AFIP 차단 근거 · 미수금 되짚기 · 매출 복제 방지(부분 UNIQUE).

`credit_ledger.payment_in.sale_id` 를 채우는 안은 버렸다 — 그 컬럼은 행 종류마다 이미
다른 것을 가리킨다(`sale_credit`=외상 발생 판매, `favor_apply`=갚은 대상 판매).
세 번째 뜻을 얹으면 아무도 못 읽는다.

## 마이그레이션 (로컬 5432 · 운영 5434 · staging **셋 다 적용 완료**)

```
2026-09-17-phase91-sales-credit-payment-id.sql          ALTER + FK(NOT VALID→VALIDATE)
2026-09-17-b-phase91-sales-credit-payment-unique.sql    부분 UNIQUE CONCURRENTLY
```
운영 `sales` 195행/360kB · 전부 NULL 로 시작 · INVALID 인덱스 0 · FK `convalidated=t`.

## CODEX 4건 — 전부 맞았고, 그중 하나는 내가 ①의 결함을 되살린 것

| 등급 | 내용 | 조치 |
|---|---|---|
| P1 | `skipCashLanding` 로 기록을 건너뛰니 **「열린 카하 없으면 거부」 판정까지 사라졌다.** 판매 경로의 `registerCashOperation` 은 카하가 없으면 조용히 통과 → 현금 회수가 원장에만 남는다(①이 고친 그 상태) | `assertCanLand()` 분리. **기록의 주인과 판정의 주인은 다르다** |
| P1 | 영수증 번호 자동 생성(`DP-${sale.id}`)이 재시도마다 달라져 **두 UNIQUE 를 둘 다 통과** → 회수 복제 | 영수증 번호 **필수**, 폴백 제거 |
| P1 | 회수 판매를 일반 경로로 취소하면 현금은 나가고 매출도 상계되는데 **빚만 갚은 채 남는다** | 안전한 역분개 전까지 **거부** |
| P2 | 물건이 담긴 요청을 **조용히 폐기** → 플래그가 잘못 붙은 정상 판매의 상품·재고가 사라진다 | 거부로 전환 |

★★ P2 는 **내가 쓴 시험이 그 결함을 정답으로 고정**하고 있었다(「원래 상품이 사라짐」을
성공 조건으로 단언). 2차 라운드의 「홈 지점 폴백」에 이어 **같은 형태를 두 번** 만들었다.
고친 코드를 다시 CODEX 에 넘기지 않았으면 둘 다 그대로 배포됐다.

## 검증

api jest 83 suite/1238건 · 회수 관련 신규 29건(대조군 포함) · 로컬 DB 통합 25/25 ·
tsc 0 · 추가한 줄 eslint 0 · `nest build` + `dist/main` 실제 부팅.

★ itest 하네스에 `SalesModule` 을 넣어 전 흐름을 실제 DB 로 재려다 **OOM** 이 났다
(`collectModels()` + SalesModule 의존 그래프). 그래서 결정 둘(서랍 주인·AFIP 차단)을
순수 함수로 떼어 내 **그 결정만 재는 시험**으로 대신했다 — 소스 문자열 검사는 쓰지 않았다.

---

# ⑤ `dp` 단축키 — 다음 세션이 바로 착수할 수 있게 (탐색 완료, 미구현)

★ 서버는 **이미 준비돼 있다.** `POST /sales` 가 `deudaPago` 를 받는다. 남은 건 화면뿐이다.

## 서버가 요구하는 것 (② 에서 확정 — 어기면 400)

```jsonc
POST /sales
{
  "items": [],                                   // ★ 비어 있어야 한다. 물건이 있으면 거부(D-2)
  "paymentMethods": [ { "paymentMethodId": N, "amount": M } ],   // ★ 정확히 하나
  "totalAmount": M,                              // 결제 금액과 **정확히** 같아야 한다
  "discount|discountAmount|transport|taxes": 0,  // 0 아니면 거부
  "discounts": [], "recharges": [],              // 있으면 거부
  "deudaPago": { "storeClientId": S, "receiptNo": "R-..." }   // ★ receiptNo 필수
}
```
- `credito`·`favor`·`senia` 결제수단은 거부된다(빚을 빚으로 갚을 수 없다).
- 서버가 제네릭 품목 줄을 직접 만든다 — 프론트가 품목을 보낼 필요도, 보내서도 안 된다.
- **영수증 번호는 재시도에도 같아야 한다.** 그래야 `uq_credit_payments_receipt`
  (store_id, receipt_no) 가 복제를 실제로 막는다. → **카트 상태에 담아** 두어야 한다
  (제출 때마다 새로 만들면 안 된다. 새로고침 복원에서도 살아남아야 한다).

## 붙일 자리 (실측)

| 무엇 | 어디 |
|---|---|
| `dp` 토큰 감지 | `ProductsInputs.tsx` — `handleSkuKeyDown`(Tab→tmp 모드 전례) · `handleSkuInputChange` |
| 비상품 줄 추가 전례 | 같은 파일 `handleAddTmpProduct` — `onAddProduct({ id: genericProductId, isGeneric: true, customName })` |
| 카트·제출 | `ProductList.tsx` — `handleAddProduct`(:638) · `saleObject`(:1406) · `POST /sales`(:1588) |
| 고객 식별자 | `saleObject.storeClientId = resolvedStoreClientId` — **이미 있다**(그대로 `deudaPago.storeClientId` 로) |
| 멱등 | `idempotencyKeyRef` — `Idempotency-Key` 헤더가 이미 붙는다(:1589). 영수증 번호는 그 위의 두 번째 방어다 |

## 권고 구현 (가장 덜 침습적)

1. `dp` 입력 → 부모에 `onDeudaPago()` 콜백. 부모가 **카트가 비어 있고 고객이
   선택돼 있는지** 확인하고 아니면 toast 로 거절(D-2 양방향).
2. dp 줄을 **기존 `onAddProduct` 로** 카트에 넣는다(`isDeudaPago: true` + 금액 + 영수증번호).
   그러면 합계·결제 패널·영수증 미리보기가 **손대지 않아도 그대로 돈다.**
3. dp 줄이 카트에 있으면 다른 품목 추가를 거절한다(반대 방향).
4. `saleObject` 조립에서만 갈라진다:
   `items: dpLine ? [] : itemsWithPromo`, `deudaPago: { storeClientId, receiptNo }`.

★ 프론트 차단은 **보안 경계가 아니다** — 서버가 이미 같은 규칙을 강제한다.
  화면 차단은 사용자가 400 을 만나기 전에 알려 주려는 것뿐이다.

## 확인해야 할 것

- 구형 시스템의 `dp` 가 **영수증을 인쇄했는가.** 인쇄 경로가 둘이라(`printTicket` +
  AFIP 자동출력) 손대기 전에 전수로 셀 것 — **중복 인쇄는 결단코 금지**.
  회수 판매는 AFIP 를 안 타므로 남는 것은 `printTicket` 하나다.
- 목업: https://claude.ai/code/artifact/9bd307cd-7637-46c7-bfa3-98585ed7021a

---

# 사용자 결정 대기 — Seña 환불

`cancelSaleWithSenia(action:'refund')` 는 `senia_refund` 원장만 쓰고 **서랍의 `retiro` 를
안 쓴다** — 손님에게 현금이 나가는데 서랍이 모른다(①이 고친 입금 쪽의 반대 방향).

**운영에서 한 번도 쓰인 적이 없다**(실측 2026-09-17): `sale_senias` 0행,
`credit_ledger` 에 `senia_*` 0건. 보이는 `favor_refund` 1건은 노트가
*"Limpieza QA … no es dinero real"* 인 수동 정리 행이다.

★ 결정이 필요한 이유: 취소 경로는 **결제수단을 받지 않고** UI 가 "en efectivo" 로
고정돼 있다(`SeniaCancelDialog.tsx`). 이체로 받은 seña 를 현금으로 돌려주는지가 업무 규칙이다.
원래 받은 수단은 `sale_payment_methods` 에 남아 있어 되짚을 수는 있다.

| 안 | 내용 |
|---|---|
| A | 언제나 현금으로 본다 — 서랍에 `retiro` 를 쓰고, 열린 카하가 없으면 거부 |
| B | 원래 받은 수단을 보고 efectivo 였을 때만 서랍에서 뺀다(비현금이면 원장만) |
| C | 취소 화면에 반환 수단을 고르게 한다(DTO·UI 변경) |
