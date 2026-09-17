# 외상 회수(deuda pago) — 사용자 결정 + 실측 (2026-09-17)

구형 시스템의 `dp` 단축키를 Ventago 에 얹되, **오늘 돈이 새는 구멍**을 함께 막는다.
Mock-up: https://claude.ai/code/artifact/9bd307cd-7637-46c7-bfa3-98585ed7021a

---

## 발단 — 사용자가 겪은 것

「외상을 받았다고 기록했는데 Tesorería 에 그 내용이 없다」

**원인은 표시 문제가 아니다. 돈이 회계상 어디에도 착지하지 않는다.**

운영 실측 2026-09-17 14:55 (같은 시간대 전 테이블):
```
credit_payments  1건   ← id=1, 총 267,600, 결제수단 3(Banco), 영수증 'test 0917_01', 지점 6
credit_ledger    2건   ← payment_in 51,600 + 216,000, sale_id 는 둘 다 NULL
sales            0건
box_operations   0건   ← 카하
movements        0건
mp_movements     0건
```
외상 잔액은 정확히 줄었는데 **267,600 이 들어온 흔적이 카하에 없다.**

★ **회수 경로가 둘이고 동작이 다르다:**

| 경로 | 화면 | credit_ledger | box_operations |
|---|---|---|---|
| ① `POST /credit/payments` | `/cuentas-corrientes` | 기록함 | **안 함** ← 사용자가 쓴 경로 |
| ② `POST /online-orders/:id/cobro` | `/ventas-online › Cuentas por cobrar` | 기록함 | **함** (`type='ingreso'`) |

Tesorería 의 모든 금액은 **오직 `box_operations`** 에서 나온다
(`cashRegister.service.ts:1645-1652`). credit 모듈은 카하를 아예 모른다 —
`grep -rn "boxOperation\|cashRegister" api-ventago/src/app/credit/` → **0건**.

★★ **②가 참조 구현이다** — `online-orders.service.ts:2432-2465`:
`registerPayment` 호출 → `addOperation({type:'ingreso'})` → 열린 카하 없으면 **차단**(`:2405-2410`).

---

## 사용자 결정

| # | 결정 | 내용 |
|---|---|---|
| **D-1** | 새 화면 없음 | 기존 `nueva-venta` POS 의 SKU 칸이 `dp` 를 하나 더 알아듣게 한다. 새 라우트·메뉴 없음 |
| **D-2** | **회수는 단독 작업** | `deuda pago` 는 **오직 그것 하나만.** 물건이 담겼으면 `dp` 거절, `dpago` 가 담겼으면 물건 거절. **양방향** |
| **D-3** | 회수는 카하에 들어간다 | 오늘의 구멍. 열린 카하 없으면 차단 |
| **D-4** | **정식 영수증·AFIP 은 손대지 않는다** | 사용자 명시. ⤷ **dpago 판매는 전표를 발행하면 안 된다** |
| **D-5** | **통계는 현금 기준** | 외상 판매는 매출이 **아니다**(돈을 안 받았으므로). **회수한 순간** 매출. 재고는 지금처럼 판매 시점에 빠진다 |
| **D-6** | **A안 채택** — 회수를 정식 판매로 | D-5 하에서 회수가 곧 매출이므로, `sales` 에 넣으면 기간 통계에 **저절로** 잡힌다 |
| **D-7** | 미수금을 화면에 함께 | D-5 의 부작용(원가와 매출이 다른 달에 떨어짐)을 읽을 수 있게 만든다 |

### D-6 의 근거 — 내가 처음에 B안을 권했다가 뒤집혔다

내 반대 근거는 「매출 이중계상」이었는데 그것은 **발생주의 전제**였다.
D-5(현금주의)로 가면 그 근거가 사라진다. 반대로 B안(회수=판매 아님)이면
**회수가 기간 통계에 안 들어와서** 모든 기간 쿼리가 두 출처를 합쳐야 하고,
「판매」의 정의가 둘이 된다 — 스스로 어긋나는 구조다.

★ **B안에서 살아남는 것**: 카하 줄 + 「열린 카하 없으면 차단」. A안에서도 똑같이 필요하고,
  **`dp` 단축키를 안 만들어도 오늘의 구멍은 그것만으로 닫힌다.**

---

## ★ D-5 가 요구하는 것 — 이걸 빠뜨리면 A안이 이중계상이 된다

**지금 코드는 발생주의다.** 기간 매출 총액(`reportsBreveVentaCockpit.service.ts:62`)은
```sql
SELECT SUM(s.total_amount) FROM sales s
 WHERE s.status IN (...) AND store/branch/date 조건만      ← 결제수단 필터 없음
```
외상 판매도 그 순간 `sales` 에 들어가 **이미 기간 매출에 포함돼 있다.**
일일 요약(`daily-summary.util.ts`)도 `credito` 를 버킷으로 집계할 뿐 빼지 않는다.

⤷ **미회수 외상 판매를 기간 매출에서 빼는 작업이 반드시 같이 가야 한다.**

**바뀌는 폭 (store 6, 2026-09-17 실측):**
```
전체 판매      159건 / 26,423,936
그중 외상 판매   7건 /  1,690,600   (6.4%)
이미 회수됨           267,600
아직 못 받은 외상   1,422,000
```
7건이 판매 시점 통계에서 빠지고, 회수분은 **회수한 날짜**로 옮겨 간다.
총합은 같지만 **금액이 달을 건너간다** — 7·8월이 내려가고 받는 달이 올라간다.

★ 사용자에게 「과거 수치가 바뀐다」를 고지했고 승인받았다(2026-09-17).

---

## 세무 — 지금은 충돌 없다, 그러나 전제가 아니다

AFIP 자동발급 판정(`afip/auto-issue.ts:10`)은 `useFacturaElectronica && afipAutoIssue`
**두 플래그만** 본다 — **결제수단을 안 본다.** 즉 플래그가 켜진 매장이면 외상 판매에도 전표가 나간다.

운영 실측: store 6 의 외상 판매 **7건 전부 전표 0건**(이 매장은 자동발급을 안 쓴다).
⤷ 지금은 충돌이 없지만 **어느 매장이 플래그를 켜면 세무상 매출 시점은 판매 시점으로 고정**되고,
  그 매장에서는 「회수=매출」이 세무와 갈라진다. 설계가 그 전제에 기대면 안 된다.

**D-4 의 구체적 요구**: dpago 판매는 AFIP 경로를 타지 않아야 한다.
결제수단을 안 보는 그 판정 자리에서 **명시적으로 끊고**,
**누가 그 차단을 빼면 실패하는 시험**을 둔다(대조군 필수).

---

## 작업 순서 (권고)

1. **카하 줄** — `POST /credit/payments` 가 `box_operations` 를 쓰고, 열린 카하 없으면 차단.
   참조 구현 `online-orders.service.ts:2432-2465` 를 그대로 따른다.
   ★ **가장 먼저.** 작고, 참조가 있고, `dp` 와 무관하게 **돈 구멍을 닫는다.**
2. **dpago 판매 생성** — `sales` + `sale_items`(재고 이동 없음) + `sale_payment_methods`
   + `credit_ledger.payment_in`(이번엔 `sale_id` 채움) + `box_operations`.
3. **AFIP 차단 + 대조군 시험** (D-4).
4. **D-2 강제** — 화면에서 양방향 차단 + **서버가 섞인 요청을 거절**.
   ★ 프론트 플래그는 보안 경계가 아니다. 버튼을 감춰도 API 는 열려 있다.
5. **`dp` 단축키** — `ProductsInputs.tsx:349` (`handleSkuInputChange`). 특수 토큰 처리 자리.
   비상품 줄 패턴은 이미 있다(`tmpMode`, Tab → `tmp001`, `:300-330`).
6. **통계 전환** (D-5) — 미회수 외상 판매를 기간 매출에서 제외.
   `reportsBreveVentaCockpit` · `daily-summary.util.ts` · `dashboard-admin.service.ts`.
7. **미수금 표시** (D-7).

---

## 조사에서 나온 부수 사실

- **open 잔액 공식이 5곳에 복붙**돼 있다(공식은 서로 같고 단일 출처 함수는 없다).
  `credit-payment.service.ts:264-277` · `sale-credit-reversal.service.ts:93-103` ·
  `credit-report.service.ts:100-116` · `:199-208` · `dashboard-admin.service.ts:424-429`.
  전부 `favor_apply` 를 명시적으로 제외한다(이중 차감 방지). 경계값 처리만 다르다
  (`> 0.005` / `> 0` / `redondearMonto()`).
- **프론트 버그(기존)**: `ClientLedgerView.tsx:43-53` 의 `MOVEMENT_LABELS` 키가 **대문자**인데
  백엔드는 **소문자**(`payment_in`)를 내려준다. 폴백 때문에 원장 표에 **raw `payment_in`** 이
  그대로 보인다. `:289` 의 `=== 'SENIA_RESERVE'` 조건도 영원히 false.
- `sale_items.product_id` 는 **nullable** 이지만 현 코드는 항상 제네릭 상품 id + `custom_name`
  으로 채운다(`ProductsInputs.tsx:312-322`).
- `dpago` 문자열은 저장소 전체에 **0건** — 구형 단축키는 이식된 적이 없다.
- 「Debtors」라는 이름에 속지 말 것: `DraftAndDebtorsList.tsx` 는 **보류 판매** 목록이고
  외상과 무관하다.
- `/cuentas-corrientes` 모듈·권한 시드가 **운영 DB 에 적용됐는지 확인 못 함**
  (`registrar-pago-credito`, `ver-cuentas-corrientes`). 착수 전 확인할 것.
