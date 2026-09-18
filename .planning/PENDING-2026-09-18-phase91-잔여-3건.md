# Phase 91 잔여 3건 — Pending (2026-09-18, 사용자 지시)

⑦ 미수금 표시(D-7)만 먼저 마무리하고 나머지는 보류한다.

---

## ① 5차 P1 — 「조회가 둘이다」 · **추론 검증 완료 (결론: dpago 는 fail-closed)**

문서가 「다음 세션이 실제로 재 볼 것」이라 한 항목. **쟀고, 추론이 맞았다.**

### 두 조회의 실제 차이

| | 기록: `resolveOpenCashRegister` | 판정: `getOpenCashRegister` |
|---|---|---|
| 파일 | `sales/sales-create.service.ts:2609` | `cashRegister/cashRegister.service.ts:2057` |
| 지점 있음 | 서랍 기준 조회 → **없으면 사용자 폴백** | 서랍 기준 조회 → **폴백 없음** |
| 지점 없음 | 사용자 기준 | 사용자 기준 |
| 잠금 | 인자로 받음 — **`registerCashOperation` 은 안 넘긴다(무잠금)** | `assertCanLand` 가 `lock:true` 로 넘김 |

### 호출 순서 (같은 트랜잭션 안)
```
createInTransaction
  :1035  processPaymentMethods → registerCashOperation   ← 기록 (무잠금)
  :1054  registerDeudaPagoEnVenta → assertCanLand        ← 판정 (FOR UPDATE)
```
**기록이 판정보다 먼저다.**

### 그래서 왜 fail-closed 인가 (경우를 전부 셈)
1. **지점에 열린 서랍이 있다** → 두 조회가 같은 쿼리·같은 `ORDER BY id DESC` 라
   **같은 세션**을 고른다. 어긋날 여지가 없다.
2. **지점에 열린 서랍이 없다** → 기록은 사용자 폴백으로 **다른 지점 서랍**에 꽂힐 수
   있지만, 그 직후 판정이 **지점 전용**이라 못 찾고 throw → **트랜잭션 전체 롤백**.
   꽂힌 `box_operations` 도 같이 사라진다.
3. **기록과 판정 사이에 자동마감이 끼어든다** → 판정의 잠긴 조회가 `closing_time`
   재평가로 아무것도 못 찾아 throw → 역시 롤백.

⤷ **회수 판매 경로에서는 돈이 남지 않는다.** CODEX 가 말한 「이미 정산된 서랍에
  현금이 남는다」는 **판정이 없는 일반 efectivo 판매**의 이야기이고, 그건 Phase 91
  이전부터 있던 상태다.

### 그래도 남는 것 (보류 사유)
조회가 둘인 것 자체는 결함이다 — 같은 질문에 두 구현이 답하면 언젠가 갈라진다.
합치려면 `registerCashOperation` 도 **잠그고 지점 전용**으로 옮겨야 하는데,
그 함수는 **모든 efectivo 판매**가 쓴다. 영향 범위가 POS 전체이고,
지점 폴백을 없애면 지점을 못 정하는 레거시 경로의 판매가 거부된다.
⤷ **별도 작업으로 다룰 것.** 지금의 위험도는 「일반 efectivo 판매가 무잠금으로
  읽는다」이고, 그것은 이번 phase 가 만든 것이 아니다.

---

## ② 회수 판매 취소 역분개 — 설계 필요

지금은 명시적으로 거부한다(`ERR-DP-ANUL`, `sales-create.service.ts:1665`).

풀어야 하는 것: 회수는 FIFO 로 여러 채권에 배분된다(`payment_in` + `parent_ledger_id`).
되돌리려면 **어느 채권에서 얼마씩 떼어낼지**를 정해야 하고, 그 사이 다른 입금이
끼어들었을 수 있다. 초과분이 `favor_in` 으로 갔으면 그것도 같이 되돌려야 한다.

★ 지금 상태가 위험하지는 않다 — **거부는 조용한 오염보다 낫다.** 사용자는
  Cuentas Corrientes 에서 수동 조정으로 처리할 수 있다.

---

## ③ Seña 환불 방향 — **사용자 결정 대기**

`cancelSaleWithSenia(action:'refund')` 가 `senia_refund` 원장만 쓰고 서랍의
`retiro` 를 안 쓴다. 손님에게 현금이 나가는데 서랍이 모른다(①이 고친 입금 쪽의 반대).

**운영 사용 0건**(`sale_senias` 0행, `senia_*` 원장 0건) — 지금 새는 돈은 없다.

| 안 | 내용 |
|---|---|
| A | 언제나 현금으로 본다 — 서랍에 `retiro`, 열린 카하 없으면 거부 |
| B | 원래 받은 수단을 보고 efectivo 였을 때만 서랍에서 뺀다 |
| C | 취소 화면에서 반환 수단을 고르게 한다(DTO·UI 변경) |

취소 경로는 결제수단을 안 받고 UI 가 "en efectivo" 로 고정돼 있다
(`SeniaCancelDialog.tsx`). 원래 수단은 `sale_payment_methods` 에 남아 있어 되짚을 수 있다.
