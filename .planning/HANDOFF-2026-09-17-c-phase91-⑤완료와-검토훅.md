# 핸드오프 2026-09-17 (3) — Phase 91 ⑤ 배포 완료 · 검토 훅 복구 · deudores 필터 대기

## ▶ 다음 세션이 먼저 할 일

### 1) **push 대기 중인 커밋 1건** — api `f30b2ff5`

```
api-ventago f30b2ff5  fix(clients): DEUDORES / RESERVADORES 체크박스가 실제로 거른다
```
**api 단독 변경**이다(프론트 수정 불필요 — 프론트는 이미 `isDebtor` 를 보내고 있었다).
push 하면 Jenkins `api-new-coolsistema` 가 돌고 운영에 배포된다. 사용자 승인을 받을 것.
★ push 전에 `.team/reviews/` 의 이 커밋 자동 보고서를 읽을 것(아래 「검토 훅」 참조).

### 2) Phase 91 남은 것

| | 내용 | 비고 |
|---|---|---|
| ⑥ | 통계 현금 기준 전환 (D-5) | ★ **반만 하면 이중계상** — 지금 외상 판매가 이미 기간 매출에 들어 있다 |
| ⑦ | 미수금 표시 (D-7) | |
| — | 회수 판매 **취소 역분개** | 지금은 명시적 거부(`ERR-DP-ANUL`). FIFO 배분을 되돌리는 설계 필요 |
| — | **5차 P1 — 조회가 둘이다** | `registerCashOperation`(잠금 없음·사용자 폴백) vs `assertCanLand`(지점 전용·FOR UPDATE). 내 fail-closed 추론은 **아직 검증 안 함** |
| — | Seña 환불 방향 (A/B/C) | 운영 사용 0건이라 급하지 않다 |
| — | `registerCobro` 재시도 멱등 | 운영 실행 0건 |
| — | CODEX 유보 1건 | 서버가 회수 시점 미수금 한도를 **잠금 아래 재검증**해야 한다는 지적. 맞지만 초과분 → `favor_in` 은 `/credit/payments`(선납)와 **공유하는 의도된 동작**이라 ⑥ 과 함께 판단 |

---

## ⑤ `dp` 단축키 — **완료 · 운영 배포됨**

Jenkins **api #908 · front #743 둘 다 SUCCESS**. 커밋: api `597bdd21` ·
app `5b3f867` → `f2579d3` → `0ba91d2` · root `c76c158`.

상세 설계·근거·검증은 **`.planning/phases/91-cobro-de-deuda-pos/91-01-carril-de-caja.md`**
의 「⑤ 완료」 절에 있다. 여기에는 그 뒤에 일어난 것만 적는다.

### 화면 실측 (스테이징, 끝까지 눌러서 확인)

`dp` + Enter → 다이얼로그(Deuda actual · 금액 프리필 · `INT-0917-JWNDVF`) → 50,000 회수 →
카트 `dpago` 줄 → Efectivo → 확정. DB 결과:

```
sales 213        credit_payment_id=1
sale_items       1행 — 제네릭 "Cobro de deuda — recibo INT-0917-JWNDVF" (서버가 만들었다)
credit_payments  1 — 50000 · receipt INT-0917-JWNDVF · branch 16
credit_ledger    payment_in 50000 · parent_ledger_id 3 · "Pago FIFO sobre venta #137"
box_operations   venta 50000 — 1건만 (ingreso 중복 없음)
고객 7472 외상   237,000 → 187,000
중복 판매        없음 (F2 와 버튼을 둘 다 눌렀는데도 1건)
```

거절 경로도 화면에서 하나씩 확인: 고객 미선택 · 잔액 0(버튼 비활성) · 빚 초과 ·
`credito` 로 확정 · 카트 잠김 · 결제 모달에서 credito·favor·senia **목록에서 사라짐**.

### ★★ 실측이 아니면 못 잡았을 결함 — 응답 확인 (`9f4f4a4`)

첫 시도에서 화면은 **「Venta creada exitosamente」** 를 띄웠는데 DB 는:
```
sales 212  total 100000  credit_payment_id=NULL  sale_items 0행
credit_payments 0행 · payment_in 없음     ← 빚 그대로
box_operations  venta 100000              ← 돈은 서랍에
```
**돈은 받고 빚은 안 깎인 판매.** 원인은 그때 돌던 로컬 API 가 낡아 `deudaPago` 를 몰랐고
전역 ValidationPipe 가 그 필드를 **조용히 버린** 것이다. 환경 문제지만 **화면이 성공이라
말한 것**이 진짜 문제라, 응답의 `creditPaymentId` 가 비면 닫히지 않는 경고를 띄우게 했다.
throw 하지 않는다 — 커밋 후 오류는 판매를 복제한다. **짝 배포의 안전망**도 된다.

---

## 검토 훅 — 「호출되지 않는다」는 **오진이었다** (root `b21204d`·`840bc21`·`68a0f48`, push 완료)

★ **종전 핸드오프와 메모리의 「PostToolUse 훅이 호출되지 않는다」는 틀렸다.** 정정했다.

훅은 계속 호출되고 있었고 **시크릿 탐지 오탐에 걸려 흔적 없이 멈추고** 있었다.
근거: api 커밋 18:59:57 → 훅이 만든 run 디렉터리와 보고서가 **19:00**(판정까지 완료).

걸린 줄은 이 하나다: `const isDpToken = isDeudaPagoToken(skuText);`
「Token = isDeudaPago…」 가 `SECRET_RE` 에 물렸고, 그 줄이 기준선 이후 **모든** app diff 에
들어 있어 그 뒤 커밋 4건이 연쇄로 막혔다. 훅은 걸리면 run 디렉터리까지 지우고 exit 0 해서
**「검토 없음」과 「호출 안 됨」이 구분되지 않았다** — 그게 오진의 원인이다.

**고친 것**
- 시크릿 판정을 **분기 셋**으로: 인접 문자열 리터럴 / `^NAME=값$`(env) / `:` 뒤 불투명
  토큰(스키마 위장). 코드의 `const x = a.b.c;` 는 어디에도 안 맞는다.
- 건너뛰면 **`.auto-codex.SKIPPED.<시각>.txt`** 를 남긴다(건너뛴 HEAD SHA·줄번호·개수만).
- 시험에 대조군 9건 추가. `bash .claude/hooks/codex-review-after-commit.test.sh` → 전부 통과.

**다음 세션이 알아야 할 조작법**
1. 자동 검토가 안 돈 것 같으면 **① `.auto-codex.heads` 전진 여부 ② `.SKIPPED.*.txt` 존재**
   를 본다. SKIPPED 가 있으면 훅은 돌았고 오탐이다.
2. 손으로 `codex exec` 를 띄울 때는 **`< /dev/null`** 을 붙일 것. 안 붙이면 stdin 대기로
   영원히 멈춘다(이 세션에서 25분 낭비했다. 0바이트 출력이 「돌고 있는 중」처럼 보인다).

★ 이 훅을 고치는 동안 **내 수정이 두 라운드 연속 새 결함을 만들었고, 두 번 다 이미 있던
  시험과 그 훅 자신이 잡았다.** 1차는 이전 라운드가 막아 둔 우회 3개를 다시 열었고,
  2차는 자동 검토가 P1 1 · P2 2 를 짚었다(그중 둘은 원래 있던 구멍).

---

## ★★ 환경 — 이것을 모르면 엉뚱한 DB 를 본다

**로컬 앱은 로컬 PG(5432)를 쓰지 않는다.** `api-ventago/.env` 가
`127.0.0.1:15432` (SSH 터널) → 서버의 **`ventago_staging`** 을 가리킨다.
이 세션에서 나는 처음에 로컬 5432 를 보고 「로컬 DB 에 그 고객이 있다」고 말했는데
**앱이 쓰지 않는 DB** 였다. 조회는 이렇게 한다:

```bash
cd api-ventago
export PGPASSWORD="$(grep -E '^DATABASE_PASSWORD=' .env | cut -d= -f2-)"
psql -h 127.0.0.1 -p 15432 -U coolsistema -d ventago_staging -c '...'
```
itest(`npm run test:itest`)는 반대로 **로컬 5432** 를 쓴다 — 둘을 섞지 말 것.

**로컬 API 는 `node dist/main` 이라 watch 가 없다.** 코드를 고쳤으면
`npx nest build` → 프로세스 재시작을 해야 반영된다(이게 위 `sales 212` 사고의 원인이다).

★★ **dev 서버가 떠 있는 동안 `next build` 를 돌리지 말 것.** `.next` 를 공유해서
  프론트가 **500** 이 된다(내가 그렇게 사용자의 앱을 한 번 죽였다). 복구는
  `kill <next dev>` → `rm -rf ventago-app/.next` → `npx next dev -p 3050`.
  tsc·eslint·jest 는 `.next` 를 안 건드리므로 언제든 안전하다.

---

## 스테이징에 남긴 것 (지우지 않았다)

| | 내용 | 영향 |
|---|---|---|
| `sales 212` | 품목 0개 · 현금 100,000 · **회수 미적용** | 낡은 API + 새 프론트가 무엇을 만드는지 보여 주는 증거. store 6 기간 매출이 100,000 부풀어 있고 고객 7472 빚은 그만큼 덜 깎였다 |
| `sales 213` | 정상 회수 판매(위 실측) | — |
| 고객 7472 | 외상 237,000 → **187,000** | 위 회수 반영 |
| itest 더미 매장 | `ZZ-CLIENTES-DEUDORES` 는 afterAll 에서 정리됨 | — |

---

## deudores 필터 (push 대기 · `f30b2ff5`)

**사용자 보고**: 판매 화면 DEUDORES 를 켜도 외상 없는 사람까지 나왔다.

**원인**: 컨트롤러는 `...filters` 로 넘기는데 `findAllQuerys` 의 인자 타입이
`{search?, storeId?}` 뿐이라 `isDebtor`·`isReservator` 가 **조용히 버려졌다.**
DTO 에 필드가 있어 400 도 안 났다 — **두 체크박스는 처음부터 아무것도 안 걸렀다.**

**정의를 새로 만들지 않았다**: `store_clients.balance > 0` (= `getTopDebtors` 와 같은 기준).
RESERVADORES 는 `senia_balance > 0`. open 잔액 공식이 다섯 군데 복붙돼 있어 여섯 번째
변형을 만들면 화면마다 답이 달라진다. 실측으로 `sc.balance` 는 원장 합계와 일치했다.

**조인**: `clients` ↔ `store_clients` 는 **정규화된 document 문자열**로 이어진다.
`EXISTS` 를 쓴다 — 같은 document(Consumidor Final `00000000`)에 여러 행이 걸려
JOIN 하면 행이 불어나 페이지네이션이 깨진다.
`storeId` 가 없으면 **빈 결과**다(전체로 폴백 금지).

**검증**: 스테이징 응답 ON 4명 / OFF 28명 / RESERVADORES 0명 / `search+isDebtor` 교집합 1명.
화면에서도 확인. 신규 `clients-deudores-filter.itest.ts` **9/9**(대조군·타 매장 격리 포함),
돌연변이 3종 전부 잡힘.

---

## 이 세션의 교훈 (다음 세션이 반복하지 않도록)

1. **「실측」이 어느 DB 인지 확인할 것.** 앱이 보는 DB 와 내가 psql 로 보는 DB 가 달랐다.
2. **낡은 서버 프로세스가 새 필드를 조용히 버린다.** ValidationPipe 가 미지의 필드를
   떨어뜨리면 「성공」 응답과 함께 반쪽 기록이 남는다 → **응답으로 확인**해야 한다.
3. **필터가 함수 인자 타입에서 사라지는 것**은 타입·컴파일·단위시험이 못 본다.
   좁히는 필터는 **실제 쿼리를 돌려** 「무엇이 빠지는가」와 「대조군이 남는가」를 같이 재라.
4. **돌연변이가 안 물면 시험이 없는 것이다.** 이 세션에서 두 번 그랬다
   (`mismoMonto` 의 NaN 분기, 마커의 HEAD 기록). 둘 다 「상대가 0/부재일 때」를
   추가해서야 물었다.
5. **수정 라운드마다 CODEX 에 다시 넘길 것.** 이번에도 내 수정이 새 결함을 만들었다
   (dp 금액 비교 fail-open, 훅 정규식 우회 3개).
