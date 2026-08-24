# 수용본 — 환불 재시도의 판매 귀속 결함 (2026-08-24)

## 무엇이 뚫려 있었나

```
POST /mercadopago/refunds/:saleId/retry   @Auth(admin, superadmin, gerente)
  saleId  ← @Param, **검증 없음**
  → intentModel.findOne({paymentId})     ← 전역 훅이 좁힌다(=자기 매장 결제만)
  → attemptModel.create({ saleId, ... })  ← saleId 를 **그대로** INSERT
  → refundModel.create({ saleId, ... })   ← 같음
```

`mp_refunds`·`mp_refund_attempts` 에는 **`store_id` 가 없다.** 전역 격리 훅은 이 둘에
**파생 규칙(→ sale)** 만 걸고, `installDerivedForModel` 은 **읽기 훅만** 설치한다.
쓰기 쪽 검사(`assertDerivedParentsInScope`)는 `crud.service.ts` 에서만 불리는데
MP 모듈은 그것을 안 쓴다 → **쓰기가 무방비.**

→ 자기 매장 결제로 **남의 매장 판매에 환불 원장을 찍을 수 있었다.**
   같은 매장 안에서도 결제 X 를 판매 Y 에 기록할 수 있었다(정합성 결함).

## 불변식

`pendingVentaId` 가 곧 `sale.id` 다 — `refundForSale()` 이 그 컬럼으로 intent 를 찾아
`retryAttempt(sale.id, ...)` 를 부른다. 정상 경로에서는 **항상 성립**하고,
어긋나는 것은 요청이 지어낸 조합뿐이다.

## 고친 방식 — 네 축

| 축 | 무엇을 보나 | 훅 독립? |
|---|---|---|
| ① 판매 가시성 | `Sale.findByPk` — 전역 훅이 매장으로 좁힌다 | ✗ |
| ② **관계** | `intent.pendingVentaId === saleId` | ✓ |
| ③ **정합성** | `intent.storeId === sale.storeId` | ✓ |
| ④ **요청자 인가** | `TenantContext` 의 허용 매장에 `sale.storeId` 가 있는가 | ✓ |

★ 거부는 `attemptModel.create` 와 MP 호출 **전에** 일어난다 — attempt 를 먼저 만들면
  남의 판매에 `attemptNo` 자리가 생기고, MP 를 먼저 부르면 **돈이 실제로 움직인 뒤**
  거부하는 것이 된다.

## ★ codex 가 잡은 내 과장 (MEDIUM, 수용)

나는 ③을 "훅이 꺼져도 남는 축" 이라고 적었다. **정합성 축에서만 맞고 인가 축에서는
틀렸다.** ②③ 은 두 행의 관계만 보지 "요청자가 그 매장 사람인가" 는 **아무도 묻지
않는다.** 그래서 `TENANT_GUARD_MODE=warn` 이면 남의 매장 `mpPaymentId` 와 **그 결제의
진짜 `saleId`** 를 함께 아는 공격자가 ①②③ 을 전부 통과한다.

→ ④를 신설했다. 훅과 같은 규칙(`TenantContext`)을 쓰되 **모드 스위치를 안 탄다** —
  환경변수로 꺼지는 것은 방어가 아니라 기본값이다.
  superadmin·system·미해석 컨텍스트는 훅과 똑같이 통과시킨다(크론이 `refundForSale`
  을 타므로 막으면 취소 환불이 죽는다). 거부는 **404** 로 답한다 — 남의 판매가
  **있다는 사실**도 알려 주지 않는다.

## codex 가 확인해 준 것

- `TENANT_GUARD_MODE=enforce` 에서 우회 경로 없음
- `refundForSale` 회귀 없음 — 원본 판매는 삭제되지 않고 `Anulado` 로 남으며
  커밋 후 `findByPk` 로 조회된다. `pendingVentaId === original.id` 불변식도 일치
- 거부 시점 적절 (attempt·MP 호출보다 앞)
- minor: "MP 호출도 없다" 를 실제로 단언하라 → `jest.spyOn(mpApi,'post')` 추가

## ★ 대조군에서 내가 찾은 것 — 통과하는 대조군

`superadmin 은 통과한다` 테스트가 **superadmin 우회를 지워도 안 죽었다.**
`storeId: null` 로 세워서 `allowed === null` 분기로 빠져 통과하고 있었던 것이다 —
그 형태는 **검사가 없는 것과 같다.**
→ `storeId` 를 **가진** superadmin 으로 바꿔 실제로 그 분기를 타게 했고,
  system 컨텍스트(크론) 테스트도 따로 세웠다. 이제 대조군이 문다.

## 검증

- 단위 832건 (mercadopago + sales + store + common) · 환불 18건
- `tsc` 0 · API 빌드 0 · eslint **신규 0건**(기존 2건 유지)
- **대조군 6종** — 각각 tsc 오류 0 을 함께 확인해 컴파일 실패로 인한 가짜 실패가
  아님을 확인:
  ① 관계 검사 제거 ② 매장 정합성 제거 ③ 판매 가시성 제거 ④ 검사 미호출
  ⑤ 요청자 인가 제거 ⑥ superadmin·system 통과 제거(과잉 차단)
- DB 변경 **없음** — 코드만 고쳤다

## 남은 것

`mp_refunds`/`mp_refund_attempts` 에 `store_id` 가 없는 것 자체는 그대로다.
파생 규칙이 **읽기만** 덮는 구조도 그대로다 — 즉 이 두 표에 **새 쓰기 경로가 생기면
같은 결함이 다시 난다.** 지금 쓰기 경로는 이 파일 두 곳뿐임을 전수로 확인했다.
구조적 해결은 `assertDerivedParentsInScope` 를 CRUD 밖에서도 강제하거나
두 표에 `store_id` 를 더하는 것이고, 그건 별도 작업이다.
