# Phase 91 ⑥ — 통계를 현금 기준으로 (D-5) · 2026-09-18

> 「외상 판매는 매출이 **아니다**(돈을 안 받았으므로). **회수한 순간** 매출이다.」

착수 전 핸드오프의 경고: **「반만 하면 이중계상」.** 실제로 반만 한 상태가
**이미 운영에 있었다** — ⑤(`dp` 단축키)가 회수를 정식 판매로 만들면서, 그 매출이
원래 외상 판매와 **두 번** 세어지고 있었다.

---

## 착수하면서 설계 문서의 전제 둘이 뒤집혔다 (운영 실측 2026-09-18)

### ① 「외상 판매」의 출처가 둘이고, 10건 중 **8건이 어긋난다**

| 판매 | total | `sale_payment_methods` | `credit_ledger.sale_credit` |
|---|---|---|---|
| 19·21·22 | 424,860 | `credito` 있음 | **없음** (고객도 없음 — 신용 모듈 이전) |
| 61 | 1,050,000 | `credito` | 있음 |
| 74·137·138·139·140 | 639,600 | `internet_pedido = 0.00` | **있음** (온라인 주문 경로) |
| 141 | 1,000 | 결제행 **없음** | 500 + void 500 (취소) |

**기준은 `credit_ledger` 다.** 근거는 「어느 쪽이 더 많이 잡나」가 아니라 **장부가
닫히는가**이다 — 원장에 있는 외상만 나중에 `payment_in` 으로 돌아온다.
원장에 없는 19·21·22 는 회수될 채권 자체가 없으므로 빼면 **영영 안 돌아온다.**

### ② 회수 경로가 **셋**인데 `sales` 를 만드는 것은 하나뿐

| 경로 | 카하 | `sales` 행 |
|---|---|---|
| POS `dp` (⑤) | ○ | **○** |
| `/credit/payments` (`/cuentas-corrientes`) | ○ (①에서 고침) | **✗** ← 사용자가 실제로 쓴 경로 |
| `/online-orders/:id/cobro` | ○ | **✗** |

D-6 의 근거였던 「`sales` 에 넣으면 기간 통계에 **저절로** 잡힌다」는 **세 경로 중
하나에서만** 참이다. 나머지 둘로 받은 돈은 판매 시점에 빼기만 하고 다시 더해지지
않아 **통계에서 사라진다.** 운영에 이미 그 형태가 있다 — `payment_in` 267,600
(2026-09-17), 대응 판매 없음.

**사용자 결정(2026-09-18): 통계가 `payment_in` 을 직접 더한다.**
⤷ 경로가 몇 개든, 새 경로가 생기든 **원장 하나만 보므로 안 샌다.**

---

## 확정된 공식

```
기간 매출(현금주의)
  = Σ sales.total_amount           (기존 status 규칙, 단 credit_payment_id IS NULL)
  + Σ credit_ledger                (bucket='credito', 각 행의 created_at 기준)
        sale_credit      → −amount
        sale_credit_void → +amount
        payment_in       → +amount
```

단일 출처: `api-ventago/src/app/reports/sale-status.constants.ts` 의 「Phase 91 ⑥」 절.

### 왜 원장 행을 **자기 날짜**에 세는가
같은 파일 위쪽의 취소 규약과 같은 이유 — **이미 마감한 달을 건드리지 않는다.**
판매 141 로 검산: 판매 141 `Anulado` +1,000 · 142 `Anulación` −1,000 ·
원장 7 `sale_credit` −500 · 원장 8 `sale_credit_void` +500 → 그날 합 0.
원장을 판매 날짜로 끌어오면 **늦은 취소가 지난 달 매출을 바꾼다.**

### 왜 초과 회수도 `payment_in` 만 세야 하는가
빚보다 많이 받으면 남는 돈은 `favor_in`(선수금)이 된다. 회수 **판매 총액**을 세면
그 선수금까지 매출이 되고, 나중에 그 favor 로 물건을 살 때 **또** 매출이 된다.

### 범위 밖 (의도)
- `senia`(예약금)·`favor`(선수금) — 받을 때가 아니라 **판매에 적용될 때** 매출이다.
  지금 코드가 이미 그렇게 한다. 여기서 더하면 이중계상.
- `writeoff`·`adjustment` — 모델에 정의만 있고 **쓰는 코드가 없다**(grep 0건).
  둘 다 현금이 아니므로 생겨도 매출을 움직이면 안 된다.

---

## 적용 규칙 — ①은 어디나 필수, ②는 귀속 가능한 곳만

| | 무엇 | 왜 |
|---|---|---|
| ① | 회수 판매(dpago)를 판매 합계에서 뺀다 | **안 하면 이중계상.** ⑤ 이전 동작으로 되돌리는 것이라 회귀가 없다 |
| ② | 외상 원장 조정을 더한다 | 현금주의 전환. **귀속 가능한 축에만** 붙는다 |

②가 못 붙는 축과 이유:

- **상품·카테고리·색·사이즈** — 회수에는 **상품이 없다.**
  (그래서 ①이 더 중요하다: 회수 판매는 `products.isGeneric` 한 줄을 달고 있어서
  빼지 않으면 그 상품이 회수액만큼 「팔린 것」이 된다 — 실측: staging 판매 213 → 제품 19.)
- **판매원** — 회수에는 **판 사람이 없다.** 원장의 `user_id` 는 「돈 받은 사람」이다.
  그걸로 귀속하면 **판 적 없는 사람에게 실적이 붙는다.**
  ⤷ 판매원 카드는 「그 판매원의 외상」만 조정한다. 그래서
  **판매원 합계의 총합 < 매장 합계**이고, 그 차이가 곧 회수액이다.
  실측(store 6, 2026-07-01~09-30): 21,710,231 vs 21,977,831 → 차이 **267,600 = 회수액**.
- **VentaVista · 일일요약의 지점 분해** — 판매의 지점 귀속이
  `terminal→box→branch` 인데 원장은 자기 `branch_id` 를 쓴다. 두 기준을 섞으면
  조정액이 **엉뚱한 지점**에 붙는다.

---

## 바뀐 파일

| 파일 | ① | ② |
|---|---|---|
| `reports/sale-status.constants.ts` | — | **단일 출처**(조각 7개 신설) |
| `reports/reportsBreveVentaCockpit.service.ts` | ○ | ○ (요약·트렌드·피크·목록) |
| `reports/reportsSalesCockpit.service.ts` | ○ | ○ (요약·트렌드·지점·기간집계·판매원) |
| `reports/reportsVendedorCockpit.service.ts` | ○ | ○ (KPI·카드·스파크·추이) |
| `reports/reportsStocksCockpit.service.ts` | ○ | ○ (당일 매출, 매장 타임존) |
| `reports/reportsProductsCockpit.service.ts` | ○ | — (상품 축) |
| `reports/reportsItemsCockpit.service.ts` | ○ | — (상품 축) |
| `reports/salesDimensions.service.ts` | ○ | — (차원 축) |
| `sales/sales.service.ts` | ○ | ○ (일일요약 **총액만**) / ○ — (VentaVista) |
| `dashboard-admin/dashboard-admin.service.ts` | ○ | — (요일 패턴 지표) |
| `admin-console/admin-console.service.ts` | ○ | — (테넌트 활동량) |

### 손대지 않은 것과 이유
- `reportsFalladosCockpit`(`status='nullified'`) · `reportsCorregidoCockpit`
  (`status='nullification'`) — 매출이 아니다. (덤: 두 상태 문자열은 운영에
  **0건**이다. `'Paid'` 오타와 같은 형태 — 별건으로 남긴다.)
- `reportsReservadoCockpit` — `ventas_suspendidas` 테이블, `sales` 아님.
- `credit-report.service` · `online-orders` 의 `cp.total_amount` — 외상 보고서 자신.
- `campaigns/segment-refresh.cron` — 고객 **누적 구매액**(세그먼트), 기간 매출 아님.
- `production/*` 의 `mm.total_amount` — 자재 이동, 무관.

### ★ 일일요약(`DailySalesStats`)은 **총액만** 바꿨다
이 화면은 **서랍 대사**가 목적이다 — `Caja = 초기금 + buckets.efectivo − 지출`.
회수 판매의 현금은 **실제로 서랍에 들어갔으므로** 결제수단 버킷에서 빼면
화면이 서랍보다 적어져 대사가 깨진다. 그래서:
- 버킷·원장·결제수단별: **그대로**(현금 흐름).
- 「Venta Total」: ① + ②. ⑤ 배포 이후 이 숫자가 회수액만큼 부풀어 있었다.
- 응답에 `creditCashAdjustment` 를 함께 실어 화면이 「왜 바뀌었나」에 답할 수 있게 했다.
  지점을 고른 조회에서는 **`null`**(0 이 아니다 — 「조정 없음」이 아니라 「셀 수 없음」).

---

## 검증

### 운영 데이터 월별 대조 (store 6, read-only)

```
  mes   |    antes    |   ajuste    |    ahora
--------+-------------+-------------+-------------
2026-04 |   778065.00 |        0.00 |   778065.00   ← 대조군
2026-05 |  2013720.00 |        0.00 |  2013720.00   ← 대조군
2026-06 |   232320.00 |        0.00 |   232320.00   ← 대조군
2026-07 |  9997600.00 | -1101600.00 |  8896000.00
2026-08 | 11749820.00 |  -588000.00 | 11161820.00
2026-09 |  1652410.97 |  +267600.00 |  1920010.97
```
합계 변화 = −1,101,600 −588,000 +267,600 = **−1,422,000**
= 설계 문서가 적어 둔 **「아직 못 받은 외상 1,422,000」과 정확히 일치.**
⤷ 돈이 사라지지도 복제되지도 않았다.

### 생성된 SQL 을 운영에 직접 실행 (문법 + 결과)
breve-venta 4개 · sales-cockpit 7개 · vendedor 5개 — **전부 오류 0**.

★ 실측이 아니면 못 잡았을 것:
- **2026-09-17 — 판매 0건인데 매출 267,600.** 조정을 판매 CTE 에 조인했다면
  그날이 통째로 사라졌다. `days` 시리즈/`FULL OUTER JOIN` 으로 붙인 근거다.
- **판매원 「Sin asignar」가 두 줄로 갈라졌다.** `seller_id IS NULL` 이 실제로
  17건 있는데 `NULL = NULL` 이 참이 아니라, 한 줄은 판매만 · 다른 줄은 조정만(음수).
  `IS NOT DISTINCT FROM` 은 PG 가 FULL JOIN 조건으로 **거부**한다
  (`FULL JOIN is only supported with merge-joinable or hash-joinable join conditions`)
  → 양쪽을 초병값 `-1` 로 접었다.
- **지점 합계 검산**: 20,198,231 + 1,629,600 + 150,000 = 21,977,831 = 매장 합계 ✓

### itest — `src/app/reports/cash-basis-revenue.itest.ts`
`npm run test:itest -- cash-basis-revenue`

- **대조군**: 외상이 없는 매장은 숫자가 한 푼도 안 바뀐다
- 외상 판매는 판매한 달의 매출에서 빠진다 (건수는 그대로)
- 회수는 받은 날의 매출 — **판매 0건인 날에도**(트렌드·피크 포함)
- **판매를 안 만드는 경로**(`payment_in` 만)도 매출로 잡힌다
- 취소는 **자기 날짜에** 상계되고 지난 달을 안 건드린다
- **항등식**: 전액 회수하면 전 기간 합계 = 발생주의 합계
- 상세 목록도 같은 기준 · 목록 기준(취소 제외)에서 `void` 가 매출을 부풀리지 않는다
- `bucket='credito'` 의 실제 movement_type 전수가 상수에 덮여 있는지 DB 에 직접 질의

---

## 남은 것 / 별건으로 기록

- **⑦ 미수금 표시(D-7)** — ⑥ 의 부작용(원가와 매출이 다른 달에 떨어짐)을 읽을 수
  있게 만드는 것. 아직 안 했다.
- **프론트** — 이번 변경은 **전부 서버 쪽**이다. 화면 라벨(「Venta Total」)이
  이제 현금주의를 뜻하는데 그 설명이 화면에 없다. `creditCashAdjustment` 를
  응답에 실어 뒀으니 ⑦ 에서 함께 쓰면 된다.
- **`sales.branch_id` vs `u.branch_id`** — breve-venta 의 요약은 `s.branch_id`,
  목록은 `u.branch_id` 를 쓴다(기존). 다지점 사용자가 있는 매장에서 두 값이
  갈린다. 이번에 **건드리지 않았다**.
- **`'nullified'` / `'nullification'`** — fallados·corregido cockpit 이 쓰는 상태
  문자열이 운영에 0건. `'Paid'` 오타와 같은 형태로 보인다.
- **초과 회수의 서버 재검증**(CODEX 유보 1건) — 여전히 미해결. ⑥ 의 공식은
  초과분이 `favor_in` 으로 가더라도 **금액은 안 틀린다**(payment_in 만 세므로).
