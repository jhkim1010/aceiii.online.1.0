# 외상 un-ship 개방 — 설계 · CODEX 자문 · 반영 결과

작업일: 2026-08-10 / 대상: `api-ventago/src/app/online-orders/online-orders.service.ts`
커밋: api `a780487` · front `5653dc0`

---

## 배경

`revertOrder` 의 un-ship 경로(`en_transito → listo`, 즉시배송은 `entregado → listo`)는
`metadata.shipSaldo > 0` 이면 차단하고 있었다. 이유는 "외상 원장을 역기입할 수단이 없어서".
2026-08-10 취소 경로용으로 `sale_credit_void` 와 `voidSaleCredits()` 가 생기면서 그 제약이 사라졌다.

## 최종 설계 (구현됨)

1. `applyUnship` 이 재고·미러를 되돌리기 **전에** 이 주문의 미상환 채무를 void 한다.
   순서는 반드시 `detachOnlineOrder` 앞 — detach 가 `sales.online_order_id` 를 떼고 나면
   `mirrorSaleId` 가 비었을 때 어느 sale 의 채무인지 되짚을 길이 사라진다.
2. **수금이 끼면 되돌리지 않는다 (fail-closed).** 두 방향으로 본다:
   - 원장: 이 주문 credit 에 `payment_in` 이 붙었는가 (`settled > 0.005`)
   - 주문: 발송 후 `metadata.received` 가 올라갔는가 (`receivedNow > total − shipSaldo`)
3. `shipSaldo` / `shipSaldoStoreClientId` / `shipSaldoUserId` 를 함께 제거.
4. `voidSaleCredits` 를 resolve / plan / assert / execute 네 조각으로 분리.
   취소와 un-ship 의 정책이 다르므로 **공용 헬퍼에 정책을 넣지 않는다.**
5. `toCard` 에 `deliveredImmediately` 추가 → 화면이 `entregado` 칸의 두 되돌리기를 구분.
6. (함께 고침) `registerCobro` 의 lost update — 잠근 최신 행에 병합.

### 왜 (2)의 두 번째 검사가 따로 필요한가

`registerCobro` 의 수금은 이 주문이 아니라 **고객 전체 미결제 외상에 FIFO 로 배분**된다.
그 돈이 다른 주문 채무를 갚았으면 이 주문 credit 에는 offset 이 없어 원장 검사에 안 잡힌다.
그런데 재발송 시 `shipOrder` 는 saldo 를 `total − metadata.received` 로 재계산하므로
채무가 **과소 기록**된다. 주문 단위 장부와 고객 단위 원장이 서로 다른 것을 센다.

---

## CODEX 자문 — 지적과 처리

| # | 지적 | 처리 |
|---|---|---|
| Q1 | `open < amount`(부분 상환)만 막는 건 부족. **완납 포함** 수금이 확인되면 막아라 | **수용.** `settled > 0.005` 로 변경 — 부분·완납 모두 차단 |
| Q2 | "nullify 후 void 하면 무효 sale 을 가리켜 잘못된다"는 **내 전제가 틀렸다**(취소도 그렇게 한다). 다만 `detachOnlineOrder` 뒤로 가면 `sales.online_order_id` 복구 경로가 사라진다 | **수용.** 전제는 정정하고, 순서 제약은 detach 기준으로 다시 세움 |
| Q3 | `shipSaldo` 를 지우면 빨강 배지가 사라진다는 **내 전제가 틀렸다** — `toCard` 가 `total − received` 로 fallback 한다 | **수용(전제 정정).** 배지는 남는다. 발송 전 단계에서 미수액을 보여주는 건 업무적으로 맞다고 판단해 그대로 둠. 세 필드를 함께 지우는 지적은 반영 |
| Q4 | `registerCobro` 가 트랜잭션 밖 스냅샷에 되쓰기 → 지운 `shipSaldo*` 를 되살릴 수 있다 | **수용.** 잠근 최신 행 재조회 후 병합으로 변경 |
| Q5 | 공용 헬퍼에 un-ship 정책을 넣으면 부분 수금 주문을 더는 취소하지 못하는 회귀 | **수용.** 헬퍼는 정책 없이 조각으로만 분리, 정책은 호출부 |

미수용/보류 1건: `runStatusTx` 에 SERIALIZABLE 재시도가 없다는 지적은 사실이나
ship/deliver/cancel 등 기존 경로 전체에 해당하는 별건이라 이번 범위에서 제외.

---

## 검증

- api 유닛 41/41 통과 (신규 8건)
- **뮤테이션 5종 사멸 확인**: 역기입 호출 제거 / payment_in 가드 무력화 /
  received 가드 무력화 / void 를 detach 뒤로 이동 / stale 되쓰기 복원
- ⚠ 처음엔 두 가드 테스트가 **잘못된 이유로 통과**했다 — `storeClientModel` 기본 mock 이
  `balance` 를 안 줘서 잔액 부족 가드가 대신 던지고 있었다. mock 잔액을 올리고
  에러 메시지를 단언하도록 고쳐 실제로 그 가드만 검증하게 만들었다.
- api tsc 0 / eslint 44 → **37** (타입 부여로 기존 `any` 접근도 해소)
- front tsc 0 / eslint 0 / 프로덕션 빌드 통과

## 남은 것

- **운영 실측 미수행** — 외상 발송 → 되돌리기 → 재발송 왕복을 실제 주문으로 확인해야 한다.
  (이전 세션의 취소 테스트처럼 더미 주문으로 가능)
- `runStatusTx` SERIALIZABLE 재시도 부재(전 경로 공통, 별건)
