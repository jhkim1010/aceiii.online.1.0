# 교환(cambio) 판매의 취소·수정 — 부호 있는 역분개 (설계, 2026-09-26)

> 현재: `assertNoEsCambio` 가 ERR-DEV-012 로 막는다 (`api-ventago/src/app/sales/cambio.ts`).
> 전제 커밋: api `71ea26d8` (13:03 배포 예약분). **이 작업은 그 배포가 끝난 뒤 시작한다** —
> 예약 작업이 api `main` 을 통째로 push 하므로 그 전에 커밋이 섞이면 검증 안 된 코드가 나간다.

## 0. 원칙

1. **일반 판매의 취소 경로는 한 글자도 결과가 바뀌지 않는다.** 모든 부호 변경은
   `esVentaConDevolucion(original)` 일 때만 탄다. 이유: 레거시 판매에 음수 결제행·음수 할인이
   있을 수 있고, 거기서 `-Math.abs(x)` → `-x` 로 바꾸면 조용히 반대 부호가 된다.
   ⤷ 헬퍼 하나: `invertir(x, signed) = signed ? -(x) : -Math.abs(x)`.
2. 역분개 R 은 원본 S 의 **정확한 부호 반전**이다. S+R 을 합치면 판매·재고·서랍·손님 잔액·
   현금주의 매출이 전부 0 이 되어야 한다 — 이것이 시험의 단언이다.

## 1. 교환 판매 S 가 남긴 것 → 취소 R 이 할 일

| 항목 | S 가 쓴 것 (예: +A 1개, −B 1개) | R 이 할 일 | 현재 코드 (틀림) |
|---|---|---|---|
| 헤더 금액 | subtotal/total 음수일 수 있음 | `-(x)` | `-abs(x)` → 합계<0 교환이면 R 도 음수 |
| 품목 | qty +1 / −1 | qty −1 / **+1** | 둘 다 −1 |
| 재고 | A −1, B +1 | A +1, **B −1** | 둘 다 +1 (B 를 두 번 더함) |
| 결제행 | 음수 가능 | `-(amount)` | `-abs` |
| 서랍 (합계<0 현금) | `retiro` X | **`ingreso` X** (손님이 현금을 돌려준다) | `retiro` 없음/반대 |
| 서랍 (합계>0 현금) | `venta` | `retiro` (종전 그대로) | 정상 |
| 손님 계정 (합계<0 favor) | 후크가 `payment_in` Y(남의 빚 FIFO) + `favor_in` W | §2 | **아무것도 안 함** (favor 가 손님에게 남는다) |
| 손님 계정 (합계>0 crédito/favor) | 종전 판매와 같음 | 종전 `reverseForSale`/`favorToRestore` | 정상 |
| 할인·추가요금 | 부호 그대로 | `-(x)` | `-abs` |
| AFIP | 합계>0 일 때만 자동 발급 | 변경 없음 — NC 는 별도 화면에서 **팩투라 금액**으로 발급 | 영향 없음 |
| MP 환불 | 합계>0 MP 결제만 가능 | 종전 그대로 | 정상 |

## 2. 손님 계정 되돌리기 (합계<0 · favor 로 받은 교환)

S 의 원장 행은 `sale_id = S` 로 찾는다 (`applyReturnCredit` 이 그렇게 쓴다).

- `payment_in` Y (남의 외상을 갚은 몫) → **`sale_credit` Y, sale_id = R** (빚이 다시 생긴다)
- `favor_in` W → **`favor_apply` min(W, 현재 favor), sale_id = R**
  - 손님이 그 favor 를 이미 썼으면 모자란 몫 → **`sale_credit`, sale_id = R**
    (「favor 는 crédito 의 음수」— 한 숫자가 정확히 X 만큼 올라간다)

**왜 새 movement 타입(`payment_in_void`)이 아닌가:** CHECK 제약 마이그레이션 + open 잔액 공식
4곳(메모리 `credit-open-balance-formula`) + 현금주의 `CREDITO_CASH_MOVEMENTS` 를 같이 고쳐야 한다.
`sale_credit` 은 셋 다 이미 맞게 다룬다.
- 현금주의 매출 검산: S(−X, payment_in +Y) + R(+X, sale_credit −Y) = **0** ✓
  favor 를 이미 쓴 경우도 그 사용분(+) 과 부족분 sale_credit(−) 이 상쇄 ✓
- 일일 대사(`creditLedgerDailyReconcile`)·자가 치유는 `%anul%` 을 제외하므로 R 의 sale_credit 이
  거짓 경보를 내지 않는다 ✓
- **대가:** 다시 생긴 빚은 원래 판매 C 가 아니라 R 에 매달리고, 연체 기간이 오늘부터 다시 센다.

**후크 미완료 경합:** 원장은 커밋 후 후크가 별도 트랜잭션으로 쓴다. 음수 favor 결제가 있는데
`sale_id = S` 원장 행이 **0건**이면 → **거부** (ERR-DEV-013 「cuenta del cliente todavía se está
registrando, reintentá en unos minutos」). 자가 치유(매시 40분)가 채운 뒤 다시 하면 된다.
손님 행은 원장을 읽기 **전에** `FOR UPDATE` 로 잠근다 (같은 손님의 다른 판매·반품과 직렬화).

## 3. 재고 — 반품 줄의 되돌림은 재고를 뺀다

B 를 이미 다른 손님에게 팔았으면 R 이 B 를 −1 해서 음수가 된다.
- 권장: **매장 설정을 따른다** (CLAUDE.md 「경합 방어는 설정을 존중」). `allowSaleWithoutStock=false`
  매장은 판매와 같은 `FOR UPDATE` 검사로 막고, 허용 매장은 음수 허용.
- 락 순서: 종전대로 productId 오름차순 (루프가 이미 정렬돼 있다).

## 4. 수정 (sales-modify) — 2단계로 미룬다

- **overwrite**(같은 품목, 결제·손님만 변경): `efectivoTotalOf` 와 현금 델타가 양수 전제.
  합계<0 교환의 결제를 efectivo↔favor 로 바꾸는 경로가 새로 생긴다.
- **replace**(취소 + 새 판매): `buildCreateDto` 가 음수 수량 → `isReturn: true` 로 되살려야 하고,
  **프론트 수정 화면이 반품 줄 카트를 막고 있다**(`homes/` 반품 줄 = 수정 차단).
- ⤷ 1단계(취소)만으로 「잘못 찍은 교환」은 **취소 → 다시 찍기**로 해결된다. 수정은 그 다음.

## 5. 1단계 작업 목록 (취소만, API 만)

1. `cambio.ts`: `assertNoEsCambio(…, 'anular')` 해제 — `'modificar'` 는 유지
2. `nullifyInTransaction`: `signed = esVentaConDevolucion(original)` 로 헤더·품목·재고·결제·할인·추가요금 부호 분기
3. 서랍: `efectivoNeto = Σ signed amount` → >0 `retiro`(종전), <0 `ingreso` (열린 카하 없으면 거부 — 종전 ERR-NUL-001 문구 재사용)
4. `SaleCreditReversalService.reverseReturnCreditForSale(S, R)` 신설 — §2
5. 재고 검사 — §3 (결정에 따라)
6. 시험: `sale-return.itest.ts` 에 취소 시나리오 — 합계>0 현금 · 합계<0 현금 · 합계<0 favor(빚 있음/없음/이미 씀) · 원장 미완료 거부 · **S+R 합 = 0 전수 단언**(판매·재고·서랍·잔액·현금주의)
7. 대조군: 일반 판매 취소 spec 전부 무변경 통과 · 돌연변이(부호 분기를 abs 로 되돌리면 죽는지)
8. 스테이징 검증 → 사용자 지정 시각에 운영

프론트: 취소 버튼은 이미 있고 ERR-DEV-012 를 받아 보여 주고 있다 — API 만 풀리면 동작한다
(스테이징에서 화면으로 확인할 것).

## 6. 결정 대기

| # | 질문 | 권장 |
|---|---|---|
| D1 | favor 를 이미 쓴 손님의 교환을 취소하면 모자란 몫은? | 빚(sale_credit)으로 — 한 숫자 모델과 일치. 대안: 거부 |
| D2 | 돌려받은 옷을 이미 다시 팔았으면(재고 음수)? | 매장 설정을 따른다 |
| D3 | 수정(modificar)도 이번에? | 아니오 — 취소 먼저, 수정은 2단계 |
