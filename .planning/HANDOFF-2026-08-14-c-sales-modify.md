# 핸드오프 — 2026-08-14 (3차) 판매 수정 백엔드

`HANDOFF-2026-08-14-b-caja-fuerte-ventas.md` 의 **§D 를 이어받아 끝낸** 기록이다.
그 문서가 "여기서부터 이어가면 된다" 고 지목한 지점에서 시작했다.

한 줄 요약: **§D 백엔드는 배포됐다. codex 지적 6건 + 추가로 나온 10건을 전부 반영했고,
프론트는 아직 없다.**

---

## 배포

| 커밋 | 내용 | 빌드 |
|---|---|---|
| api `6b5b28f` | 판매 수정 — 서버 판정 + 취소·재등록 단일 트랜잭션 | **#708 SUCCESS** |
| root `f366798` | 서브모듈 포인터 (api 4건 + app 3건 이월분 포함) | — |

운영 확인: `POST /api/sales/:id/modify` 가 4개 워커 전부에 매핑, 인증 없이 401.

마이그레이션 `2026-08-14-sales-single-reversal.sql` — **로컬 5432 · 운영 5434 양쪽 적용·검증 완료.**
한 판매에 역분개는 하나뿐임을 부분 유니크 인덱스가 막는다(적용 전 운영 중복 0건 확인).

테스트: sales 관련 12스위트 228건 + 연관 모듈 포함 307건 통과. 신규 파일 lint 0 오류.

---

# §A. 무엇을 만들었나

`POST /sales/:id/modify` — 두 갈래이고 **어느 쪽인지는 서버가 정한다.**

| 판정 | 조건 | 처리 |
|---|---|---|
| **a 덮어쓰기** | 품목(종류·수량·단가)·금액·결제 원장 구성이 그대로 | 같은 번호에 제자리 수정 |
| **b 대체** | 그 밖 | 오늘 날짜로 ① 원본 `Anulado` ② 역분개 ③ 새 판매(`replacesSaleId`→①) |

권한 `modificar-venta`. `Idempotency-Key` 헤더 선택. 소급 한도 일반 어제 / admin 1개월.
CAE 발행 건은 거부(`ERR-MOD-003`).

## ★ 사용자 결정 — crédito/seña/MP 는 막지 않고 **b 로 보낸다**

원래 사양은 "결제수단이 무엇으로 바뀌든 a" 였다. 그런데 제자리 수정은 원장을 건드리지
않아 crédito 로 바꿔도 **채무가 안 생긴다**(§C-2 의 거울상).

codex 는 "결제수단 변경은 전부 replace 여야 한다" 고 했지만 그건 사양을 줄이는 것이다.
사용자에게 물었고 **"b 로 보낸다"** 를 골랐다 — 기능은 그대로 되고, b 경로가 이미
채무 역기입·MP 환불·재고 복원을 올바르게 한다. 막는 게 아니라 되는 경로로 보내는 것.

→ `LEDGER_BOUND_SLUGS = {credito, senia, favor, mercadopago, cheque}`.
   이 구성이 달라지면 b. `efectivo↔tarjeta` 는 a 그대로(서랍 차액만 보정).

---

# §B. 트랜잭션 분해 (Critical ①)

`create`(610줄)·`nullifySale`(412줄)을 **순수 추출**로 셋으로 쪼갰다:

```
prepareX(...)          // 트랜잭션 밖 사전 조회 — 힌트일 뿐
XInTransaction(..., t) // DB 부분. t 는 필수 인자
afterXCommit(...)      // 외부 I/O. 절대 throw 하지 않는다
```

공개 `create()`/`nullifySale()` 은 얇은 조립으로 남겼고 **기존 spec 183건이 무변경 통과**했다.
그게 동작 보존의 증거다(§C-2 의 online-orders 41건과 같은 방식).

`modifySale` 이 바깥에서 트랜잭션 하나를 열어 두 DB 부분을 담는다 → "취소만 남고 새 판매가
없는" 상태가 구조적으로 불가능해진다.

★ 본문은 **한 글자도 안 고쳤다.** 경계만 옮기고 `const {…} = prep` 로 이름을 풀었다.

---

# §C. codex 가 5라운드에 걸쳐 잡은 것

**매 라운드가 실제 결함을 냈다.** 고친 것 자체가 새 결함을 만들었기 때문이다.
메모리에 남김: `always-consult-codex` 10항.

## 1라운드 (설계)
- **교착** — replace 는 복원{원본} → 차감{신규} 순이라 전역 오름차순이 깨진다
  (원본{5,9} 뒤 신규{3,7} vs 동시 판매{3}→{5}). → `lockStockScopeAscending` 으로
  합집합을 **미리** 잠근다.
  ★ 정렬 키가 PK(`product_branch_id`)가 아니라 **`product_id`** 인 것이 핵심 —
  초과판매 가드와 원장 트리거가 그 순서를 쓴다. PK 순으로 잠그면 오히려 새 교착이 난다.
  ★ create 의 `채번 advisory → 재고` 순서는 **건드리지 않았다**. 한쪽만 뒤집으면 새 교착 경로.
- **멱등** — 결과를 커밋 후 best-effort 로 남기면 그 사이 죽었을 때 재시도가 결과를 못 찾는다.
  → `sale_idempotency_keys.response_body` 에 **업무 트랜잭션 안에서** 확정(마이그레이션 불필요).
- **후처리 유실** — `afterNullifyCommit` 실패가 `afterCreateCommit` 을 막으면 새 판매의
  프린터·AFIP·ledger 가 조용히 사라진다. → 독립 try/catch.

## 2라운드 (구현 후) — 배포를 막았다
- ★ **역분개가 락 이전 스냅샷을 되돌렸다.** 판정·재고 선점은 최신인데 역분개와 현금 출금만
  과거 값. → `SalesService.findOne(id, transaction?)` 추가, `prepareNullify` 를 **락 뒤로** 이동.
- ★ **판정이 클라이언트 slug 를 믿었다.** `paymentMethodId` 는 crédito 인데 slug 를 생략하면
  a 로 빠져 **채무 없이 결제행만 바뀐다.** → 트랜잭션 안에서 DB JOIN 으로 해석
  (`resolveRequestedPayments`), 타 매장 결제수단은 `ERR-MOD-010`.
  메모리: `decision-source-must-match-write-source`.
- **선택 필드 유실** — replace 가 `sellerId`/`branchId`/`taxes` 등을 원본에서 안 이어받았다.
  ★ 특히 지점이 비면 다지점 매장에서 `prepareCreate` 가 지점을 못 정해 **재고가 아예 안 빠진다**.

## 3라운드
- `prepareNullify` 안의 `Store.findByPk`/`resolveSaleBranchId` 가 트랜잭션을 안 타
  **커넥션을 쥔 채 풀에서 하나 더 요구**했다. → 전부 transaction 전달.
- `provinceId: null` 이 `??` 때문에 무시됐다.

## 4라운드
- ★ **`@IsOptional()` 이 null 을 통과시켜** 3라운드 수정이 무효였다. 게다가 a 는
  `!== undefined`(null=비우기), b 는 `??`(null=안보냄) 이라 **경로마다 결과가 달랐다.**
  → `provided()` 헬퍼로 통일. 메모리: `is-optional-lets-null-through`.
  → `provinceId` 의 "비우기" 는 create 가 고객 province 를 자동 추론해 b 로는 표현 불가 →
    **DTO 에서 `| null` 을 뺐다.** 되는 척하지 않는다.

## 5라운드 — "배포 차단 사유는 없습니다"

## 반영하지 않은 것 (근거를 대조해 판단)
`resolveSaleBranchId` 의 폴백들이 지점의 store 소속을 검증하지 않는다 — **바꾸지 않았다.**
- 운영 확인: terminal→box→branch 가 타 매장인 판매 **0건**, users.branch_id 타 매장 **0건**
- 내 새 경로는 이 값을 `createDto.branchId` 로 넘기고 `prepareCreate` 가 `Branch.findOne({id, storeId})`
  로 검증해 **큰 소리로** 실패한다(조용한 누수 아님)
- 이 함수는 배포된 `nullifySale` 이 쓴다. null 을 돌려주게 바꾸면
  `assertBranchResolvableOnNullify` 가 **지금 정상 동작하는 취소를 거부**한다
codex 도 "제시한 근거와 이번 변경 범위에서는 타당" 이라고 동의.

---

# §D. 디버깅 로그 (사용자 요청)

- `sale_modify_decision` — **왜 그렇게 판정했는지**. before/after 지문·금액·지점을 다 담는다.
  b 는 번호가 바뀌므로 "왜 번호가 달라졌냐" 에 답할 수 있어야 한다.
- 단계별 `[VentasDebug][modify] step=` — entrada / prepare_ok / locked / replace_scope
  (**lockOrder 포함** — 교착 의심 시 증거) / stock_locked / nullified / created / committed
- `overwrite_cash` — efectivoBefore/After/delta. 서랍 안 맞는다는 신고의 첫 확인 대상.
- `sale_modify_rolled_back` — 롤백되면 **DB 에 흔적이 없다.** 로그가 유일한 증거.

★ **info 레벨로 넣었다.** 운영 로그레벨이 `info` 라 `logger.debug` 는 안 보이는데,
사고 뒤에 소급해서 debug 를 켤 수 없다. 판매 생성의 `[VentasDebug]` 가 debug 인 것은
**판매마다** 찍혀 용량이 문제되기 때문이고, 수정은 하루 수십 건이라 그 걱정이 없다.
빈도가 다르면 레벨도 달라야 한다.

---

# §E. 다음 — 프론트 (미착수)

1. **Historial(`/ventas` → `SalesListView`) 수정 버튼.** 현재 행 액션은 보기·재출력 둘뿐이고
   `Anular` 조차 POS 의 `Repaso de ventas`(Ctrl+R)에만 있다. 권한 `modificar-venta` 는 이미 있다.
2. **nueva-venta 편집 모드.** ★ 새로 만들지 말고 **보류 판매 복원(suspender→recall) 경로를
   재사용**할 것 — `SaleProductsContext` 에 `suspendedSaleId`/`restoredQuantities` 가 이미 있다.
   두 벌이면 "같은 판정이 두 곳에서 갈라진다" 가 재현된다.
3. **확정 직전 확인 단계** — 서버 판정 결과("#1234 유지" vs "#1234 취소하고 새 판매")를
   보여준다. 사용자가 b 인 줄 모르고 누르면 안 된다.
   ★ 판정만 미리 알려주는 dry-run 엔드포인트가 아직 없다 — 필요하면 만들어야 한다.
4. Historial 에서 ①②③ 을 **한 묶음으로** 보여주기 (`replaces_sale_id` 로 이제 이어진다).

## 백엔드에 남은 것
- **결제 합계 검증 없음** — 합계≠총액은 `Pendiente por pagar` 라는 정상 상태다(운영 101건 중
  1건 실재). 그래서 막지 않았다. 프론트가 붙은 뒤 실제 오입력 양상을 보고 정하는 게 맞다.
- `provinceId` 비우기 미지원 (위 §C 4라운드)
- MP 환불에 HTTP 멱등키 없음 (codex 1라운드 지적, 기존 취소 경로와 동일 — 이번 범위 밖)

---

## 이월 (앞 핸드오프에서 그대로)

- **판매 158 유령 현금 52,000** — 이미 금고 이체됨. C-1 수정은 앞으로만 적용. 실사 큐로 처리 가능
- **seña/favor 역기입 의미 결정** — 정해지면 `ERR-NUL-002` 를 풀 수 있다. 운영 0건이라 안 급함
- **실사 큐 13개 서랍** — 서랍 15(+660,900)부터. 19(−2,731,000)·18 은 옛 이체 대조가 먼저
- ★ **`approveReturn` 은 C-1 과 같은 구멍** — 환불액 역분개를 만들면서 카하를 전혀 조정하지
  않는다. DTO 에 환불 수단 구분이 없어 무조건 retiro 를 넣으면 안 된다. **아직 안 고쳤다**
- `/suspended-sales` 403 (구 번들 의심) / 수표 `Anular`(마감된 카하) / 감사 로그 조회 화면
  / `payment_source='mixto'` 보고서 / 카하 125 유령 이체 / 로트 10 실물 / §5-5 미검토 쓰기 경로

---

## 작업 방식 — 이번에 걸린 것

- ★ **codex 는 한 번 받고 끝내면 안 된다.** 5라운드 전부가 실제 결함을 냈고, 3·4라운드는
  **내가 방금 고친 것이 만든** 결함이었다. 라운드마다 "이번에 고친 것만 보라" 로 범위를
  좁히면 답이 짧고 정확해진다.
- ★ **범위를 줄이는 결정은 물어본다.** codex 가 "결제수단 변경은 전부 replace" 라고 했을 때
  그대로 따랐으면 사양이 조용히 줄었다. 물어봤고 사용자가 더 나은 답(b 로 보내기)을 골랐다.
  앞 세션에서도 같은 실수를 두 번 했다(메모리 `propose-dont-declare`).
- ★ **"고쳤다" 와 "실제로 그렇게 동작한다" 는 다르다.** `provinceId` 를 `!== undefined` 로
  고쳤는데 `@IsOptional()` 이 null 을 통과시켜 **아무것도 안 바뀌었다.** 라이브러리의 실제
  동작을 확인하지 않고 의도만 코드에 적었다.
- ★ **외부 지적도 근거를 대조한다.** `resolveSaleBranchId` 건은 운영 데이터를 직접 조회해
  0건임을 확인하고, 고치면 오히려 정상 취소가 깨진다는 것까지 확인한 뒤 **안 고치기로**
  했다. codex 도 근거를 보고 동의했다.
- **순수 추출 리팩터는 기존 spec 이 증명해 준다.** 본문을 한 글자도 안 고치고 경계만 옮기면
  183건 무변경 통과가 곧 동작 보존의 증거가 된다.
