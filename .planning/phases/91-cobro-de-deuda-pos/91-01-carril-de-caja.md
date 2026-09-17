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
