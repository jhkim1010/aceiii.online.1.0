# 핸드오프 — 2026-08-27 · 가격 계산기 통합 + WooCommerce webhook 재설계 ★

`HANDOFF-2026-08-25-phase86-매퍼3종.md` 이후. 두 갈래 작업이 하루에 겹쳤다.

---

## ★★ 이 세션의 한 줄

**«통과한다» 가 «지켜진다» 가 아니라는 것을 두 번 다르게 배웠다.**
가격은 **계산기가 여섯 벌**로 갈라져 사람이 켜 둔 반올림이 한 번도 안 걸리고
있었고, webhook 은 **테스트 11개가 아무것도 안 지키고** 있었다(돌연변이 시험).

---

## 배포 (전부 SUCCESS · 운영 반영 확인)

```
api-ventago                                                        Jenkins
  9e5267b  사람이 켜 둔 반올림이 한 번도 안 걸리고 있었다             #831
  5ec7dbc  마지막 한 벌 — precision 을 스페인어 단어로 읽던 계산기   #832
  bd3a7b5  «Secret 은 맞는데 401» — 원인은 PHP 의 JSON 표기          #833
  3113a8e  webhook 다섯 구멍 + 네이티브 WooCommerce webhook          #834
  295362b  참조 문서를 네이티브 기준으로                              #835
  dd0bcfa  스니펫 경로를 통째로 삭제                                  #836
  69e5dd3  돌연변이 시험 — 25/25 죽는다                               #837

ventago-app
  22c9c14  계산기가 여섯 벌이었다 — 하나로 모으고 구간을 저장         #686
  7ceec6d  스니펫의 JSON 인코딩                                       #687
  4d91522  연동 안내 재작성 — PHP 가 더는 필요없다                    #688
  6db10a6  안내에서 PHP 스니펫 제거                                   #689

DB (로컬 5432 + 운영 5434 **양쪽** 적용 확인)
  2026-08-27-price-type-ranges.sql
  2026-08-27-wp-webhook-hardening.sql   ← CONCURRENTLY 라 두 번에 나눠 실행
```

---

# 1부 — 가격

## ★★★ 계산기가 여섯 벌이었다

같은 `price_types` 규칙을 읽는 경로가 여섯 개였고 전부 조금씩 달랐다.
그리고 **전부 `roundingType` 을 소문자로 비교**했다 — DB 값은 대문자다
(`uppercaseStringFields()` 가 저장할 때 대문자로 바꾸는데 제외 목록에 없다).

**결과: `rounding_enabled = true` 인 가격유형에서 반올림이 한 번도 안 걸렸다.**

거기에 두 가지가 더 있었다:
- 통합 계산기가 `increase_type='amount'` 를 몰랐다 → `4000` 이 `+4000` 이 아니라
  **`×40`**. 호출부가 삼항으로 우회하고 있어 안 보였다(운영에 amount 3행 실재).
- `productsPrice` 의 자체 `roundPrice` 는 `precision` 을 `'milésima'` 같은
  **스페인어 단어**로 읽었다. 실제 값은 `'1000'` 이라 **무동작**이었다.

→ 여섯 벌을 `price-calculator.ts` 하나로 모았다(백엔드·프런트 각 1개, 같은 식).

## ★★ 정답표를 파일로 뺐다

`shared/price-calculator.golden.json` — **프런트와 백엔드 테스트가 같은 파일을
읽는다.** 예전 spec 은 프런트 구현을 복사해 와서 비교했는데, 그러면 프런트
버그까지 «정답» 으로 굳는다. 실제로 대문자 `UP` 버그가 양쪽에 있는 채로
테스트가 통과하고 있었다.

## 사용자 결정 (되묻지 말 것)

- `increase_value` 는 **프런트 방식** — `121` = 기준가의 121% (`base × v/100`)
- 구간은 **항상 기준가(Precio 1)로 고른다**. 계산된 값이 아니다
- 구간 값은 기준가에 **더한다**. 최종가가 아니다 (ACE `valor_aumento` 와 같은 뜻)

## ⚠ 아직 안 한 것 · 남은 위험

- **반올림이 이제 실제로 걸린다.** 다음 일괄 가격 갱신에서 값이 바뀐다.
  실측 영향: **ACE 의 «DESC.5» 19개**. 나머지 매장 0. 제가 미리 다시 쓰지 않았다 —
  사용자가 갱신을 누를 때 적용된다. **사용자에게 이 사실이 전달돼 있다.**
- `bulk-update-explicit` 은 프런트가 계산한 금액을 **그대로 저장**한다.
  지금은 양쪽 식이 같아 값이 같지만, 구조적으로 서버가 최종 권위가 아니다.
- `CodigoVistaView` 는 `levels`/`pct`/`roundUnit` 이라는 **다른 모델**을 쓴다
  (`price_types` 를 안 읽는다). 합칠지는 별도 판단이라 손대지 않았다.
- ACE 에서 보존한 규칙(`legacy_price_rules`)을 `price_types`/`price_type_ranges`
  로 **옮기는 단계는 여전히 미착수**다(사람의 판단이 필요한 «켜기» 단계).
- themarket 751행의 소수 손실 — `prices.amount` 가 INTEGER 라 생기는 것.
  임포트 감사(`legacy_price_decimals`)와 섞지 말 것.

---

# 2부 — WooCommerce webhook

## ★★★ «Secret 은 맞는데 401» 의 진짜 원인

`WpGuard` 가 raw body 를 안 보존해 **받은 body 를 다시 직렬화**해 HMAC 을
만들었다. WordPress 의 `wp_json_encode($payload)` 기본값은 비ASCII 를 `\uXXXX`,
`/` 를 `\/` 로 escape 한다. **같은 데이터인데 다른 바이트**다 → 401.

  「Ana Perez」 주문은 통과하고 「José Muñoz」 만 실패 → **간헐적 장애로 보인다.**
  아르헨티나에서는 이름·주소에 악센트가 거의 항상 있다.

→ webhook 경로에만 raw body 를 보존하고(2MB 상한) **원문 바이트로 검증**한다.
  PHP 8.2/7.4 컨테이너로 실제 바이트를 뽑아 확인했다.

## ★★★ 구조를 바꿨다 — 이제 PHP 를 안 쓴다

WooCommerce **기본 Webhook** 을 서버가 이해한다. WordPress 에 코드를 안 심는다.

```
배달 URL : …/api/integrations/wp/wc?channel=wpch_…
Secret   : Ventago 채널의 Secret
Topic    : Pedido creado + Pedido actualizado  (둘 다 필요 — 취소가 «actualizado» 로 온다)
API      : WP REST API Integration v3          (v1/v2 는 형식이 달라 SKU 를 못 찾는다)
```

★ **경로가 하나뿐인 것이 설계다.** 여럿이면 한 경로의 서명을 다른 경로에
  재사용할 수 있다. 생성·취소는 주문의 `status` 로 가른다.
★ 채널을 URL 로 받는 이유: 기본 Webhook 은 임의 헤더를 못 넣는다.
  채널 키는 **권한이 아니라 식별자**이고 실제 권한은 서명이다.

## ★★ 스니펫 경로를 통째로 지웠다 (2026-08-27)

근거 — 운영 실측: `wp_channels.last_received_at` = **NULL**, `source='wp'` 보류판매
**0건**. **웹훅이 한 번도 도착한 적이 없어** 지킬 설치본이 0이었다.

지운 것: `/orders`·`/orders/cancel` 라우트, `legacy` 재직렬화 서명(**더 약한**
검증이었다), `sentAt` 시각 창(네이티브에는 서명된 시각이 없어 **한 번도 발동한 적
없는 검사**), 인코딩 진단 문구(원문 서명이 그 문제를 없앴으므로 **더 이상 참이
아닌 조언**).

되살릴 일이 생기면 git 에 있다(`dd0bcfa` 직전).

## 막은 다섯 구멍

| | 방법 |
|---|---|
| 재전송 | `wp_webhook_events` 대장 + 유일 인덱스. 판단을 **INSERT 가** 한다 |
| 엔드포인트 바인딩 | 경로를 하나로 없앴다(필드가 아니라 **구조**로) |
| DB 멱등성 | `uq_ventas_susp_wp_pedido` (branch_id, num_pedido) WHERE source='wp' |
| 순서 역전 | `wp_order_states` tombstone. 비교는 **출처 시각**으로 |
| Secret 교체 | `secret_prev` + 7일 기한 |

## ⚠ 아직 안 한 것 (codex 권고 중 남은 것)

- **주문 단위 create/cancel 직렬화.** tombstone 확인과 실제 생성 사이가 경합한다.
  per-order advisory lock 으로 «상태 조회 → 갱신 → 판매 반영» 을 한 트랜잭션에
  묶어야 한다. **이번에 안 했다.**
- **GitHub Actions 의 mutation gate.** Jenkins 에서는 못 돌린다(운영 서버 위, swap 0).
- **배포가 검증에 안 묶여 있다.** main push 에 Actions 와 Jenkins 가 **동시에**
  출발하므로 테스트는 알려줄 뿐 배포를 막지 못한다(codex 지적).

---

# 3부 — 돌연변이 시험 ★★★ 이 세션에서 가장 중요한 것

`bash api-ventago/scripts/mutantes-wp.sh` · 목록 `test/mutantes/wp.json` (25개)

**처음 돌렸을 때 18개 중 11개가 살아남았다.** 즉 그 버그를 넣어도 테스트가 통과했다.

## 그중 최악 — 자기참조

```ts
for (const estado of ESTADOS_CANCELADOS)   // ← 구현이 export 한 집합을 순회
  expect(mapear({...p, status: estado}).cancelado).toBe(true)
```
집합에서 `'cancelled'` 를 지워도 루프가 그 값을 안 돌아 **통과한다.**
실제 결과는 «취소된 주문이 POS 에 되살아난다» — 돈이 걸린 결함이다.
→ 기대값을 **손으로 적은 계약표**로. 구현 집합과 표가 같은지 따로 확인.

## 고친 방식 (다음에도 같은 형태를 쓸 것)

- **순수 함수로 뺀다** — `wp-order-decision.ts`, `wp-secretos.ts`.
  서비스·가드 안에 있으면 DB 없이 못 돌려서 결국 안 검사된다.
- **그리고 배선을 따로 본다** — 순수 함수 검사만으로는 «서비스가 실제로 부르는가»
  가 안 잡힌다(계산기가 여섯 벌로 갈라진 것과 같은 형태).
- **경계는 셋** — `=` 가 있으면 «같음 · 1ms 전 · 1ms 후».
- **조건이 둘이면 표본은 넷** — `esPing` 이 그래서 뚫려 있었다.

## 실제 결함도 하나 나왔다

재전송 판정이 `ignoreDuplicates` 후 **재조회해 `receivedAt` 이 2초 이내인가**로
«방금 넣었나» 를 재고 있었다. 시계 휴리스틱이라 틀린다 — DB 왕복이 2초를 넘으면
정상 주문을 버리고, 2초 안에 온 진짜 재전송은 통과한다.
→ `ON CONFLICT DO NOTHING RETURNING id`. itest 에서 **동시 10건 중 정확히 하나만**
  true 인 것을 본다.

## 스크립트 자체의 함정 (두 번 걸렸다)

- `export` 를 빠뜨려 `--itest` 가 **unit 으로 돌았다** → 「통합이 지키는 것」이
  생존으로 잘못 보고됐다. 판정은 이제 **unit ∪ itest** 다.
- 패턴을 못 찾으면 `NO_APLICA` 로 **실패시킨다** — 조용히 0건이 되면 이 시험은
  아무것도 재지 않는다.

**현재: 25/25 죽음, 생존 0.**

---

## 그 밖에 이 세션에서 드러난 것

- **`store_entity_id` 유니크 인덱스가 실제로 산다** — 테스트를 쓰다가 두 번째
  `price_types` 에서 죽었다. 운영 경로와 같은 카운터로 번호를 받게 고쳤다.
- **legacy_* 컬럼 8개가 미선언**이었다. 내 변경 때문이 아니라 기준선 파일이 낡아
  가려져 있던 것. 전부 판단을 적었다.
  ⚠ **선언과 집행이 아직 안 이어져 있다** — `buildRestorePlan`/`resolveColumn` 은
  **spec 에서만** 호출된다. 지금은 안전하다(전체 복원이 `blocked`, legacy 표는
  어느 복원 경로에도 안 닿는다 — 실측 확인). 그러나 `RESTORE_ENGINE_STATUS` 를
  열 때 **계획기를 실제 복원 경로에 연결하는 일이 함께 되어야 한다.**

---

## 다음 세션이 먼저 볼 것

1. **가격**: 일괄 갱신 시 ACE «DESC.5» 19개가 바뀐다 — 사용자와 시점을 정할 것
2. **webhook**: 주문 단위 create/cancel 직렬화(advisory lock)
3. **CI**: Actions 성공 SHA 만 Jenkins 가 배포하도록 (지금은 동시 출발)
4. ACE 가격 규칙을 `price_types` 로 옮기는 «켜기» 단계 (사람의 판단 필요)

## 참고

- 실측 명령들은 커밋 메시지에 그대로 있다(`git log --oneline`).
- codex 자문 원문: `/tmp/codex-*.out` (세션 한정 — 필요하면 다시 물을 것)
