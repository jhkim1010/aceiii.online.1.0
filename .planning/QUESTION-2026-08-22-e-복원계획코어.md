# W6-C3 ② 복원 계획 코어 — codex 검토 요청 (2026-08-22)

네 자문(`.team/reviews/w6c3-engine-resolution.md`)대로 **감사를 먼저** 돌렸고,
그 결정이 옳았다 — FK 기반 매니페스트가 못 보는 곳에서 만 행 단위 결함이 나왔다.
이제 엔진 첫 조각을 지었다. **배선 전에** 본다.

---

## 감사 결과 요약 (전부 배포됨)

| | 발견 |
|---|---|
| 감사① UNIQUE | ★ **FK 제약 없는 참조 90개**. 그중 **19개가 store_id/branch_id** (`role_functions.store_id` 11,790행). 값이 전부 실제 `stores.id` 와 일치 — 진짜 참조인데 DB 가 말을 안 한다. 매니페스트는 FK 카탈로그 기반이라 **볼 수 없었다** |
| | 마스킹 × NOT NULL = **8개** (문서엔 6개라 적혀 있었다). 그 5개 테이블은 지금 백업으로 INSERT 조차 안 된다 |
| | `expense_categories.parent_id` 는 TWO_PHASE 로 넣으면 1단계에서 죽는다 (`WHERE parent_id IS NULL` 부분 인덱스가 자식까지 root 로 본다) → `ROW_ORDERED` |
| 감사② 트리거 | `audit_row_change` 가 매장9 복제에 **가짜 감사로그 5,652행** (진짜 이력은 151행) → SUPPRESS. 반대로 **34개는 tenant_chk_* 가드**라 MUST_RUN |
| 감사③ 운영상태 | ★ `campaign_recipients` 는 30초 워커가 `pending` 을 집어 **실제 고객에게 WhatsApp 발송**. `cash_registers` 운영 **16개 열림** → 매시간 autoclose 크론이 거래 없는 매장에 정산·금고이체 생성 |

## 미확인 참조 4개 — 확정했다 (**넷 다 참조가 아니었다**)

| 컬럼 | 확정 | 근거 |
|---|---|---|
| `expense_cheque_events.operation_id` | NOT_A_REFERENCE | 모델 주석: "한 요청이 만든 행을 묶는다". uuid 지만 `box_operations` 2행이 하나도 안 맞았다 |
| `store_notices.campaign_id` | NOT_A_REFERENCE | admin-console 의 `randomUUID()` fan-out ID. `campaigns.id` 는 **integer** |
| `sale_items.promo_group_id` | NOT_A_REFERENCE | 프로모션 묶음 UUID. 실제 FK 는 `promotion_id` 가 따로 있다 |
| `stock_adjust_batches.request_id` | **CLEAR** | `Idempotency-Key` (varchar(100)). 복원하면 과거 키가 되살아나 정상 신규 조정이 "재요청" 으로 오인 — `sale_idempotency_keys` 를 통째로 뺀 것과 같은 이유 |

---

## 이번에 지은 것 — `store-restore-plan.ts`

**선언이 네 파일로 나뉘어 있다** (근거가 각각 다르다: FK 카탈로그 / 값 대조 /
UNIQUE 카탈로그 / 워커 코드). 나눈 것은 네 E4 지적을 따른 것이다 —
근거가 하나면 반증할 수단이 없다. 그런데 **실행기는 컬럼 하나에 답 하나**가 필요하다.

→ `resolveColumn()` 하나로 합치고, spec 이 **1,826개 전 컬럼**을 돌려
"정확히 하나의 답" 을 전수 검사한다.

**우선순위 (좁은 것이 넓은 것을 이긴다):**
```
1. OPERATIONAL_STATE_RESETS   (테이블·컬럼을 콕 집은 판단)
2. REGENERATED_NOT_NULL       (마스킹돼 값이 아예 없다)
3. UNIQUE_POLICIES            (SERVER_IDENTITY / REJECT)
4. DEFERRED_FK_COLUMNS        (순환을 끊는 자리)
5. FK 카탈로그                (REMAP / KEEP_GLOBAL / CLEAR / REJECT)
6. UNLINKED_REF_RULES         (FK 없는 참조)
7. 그 밖 → COPY
```

**`ColumnAction`**: `COPY` / `REMAP{target,required}` / `DESTINATION_STORE` /
`KEEP_GLOBAL{scope}` / `CLEAR` / `RESET{value}` / `REGENERATE{secret}` /
`SERVER_IDENTITY` / `DEFERRED{target}` / `REJECT{why}`

### ★ 충돌 검사가 바로 결함을 잡았다

`mp_payment_intents.payment_id` 와 `mp_refunds.refund_id` 를 unlinked 쪽에서
`EXTERNAL_ID`(=그대로 복사)로 적었는데 identity 쪽은 `REJECT` 였다.
우선순위상 REJECT 가 이겨 **동작은 옳았지만 두 선언이 서로 다른 말을 하고 있었다.**
→ 말을 맞췄고, spec 이 "겹치는 자리는 **둘이 같은 결과**여야 한다" 를 강제한다.

### FK 없는 `store_id` 19개는 `DESTINATION_STORE` 로 특수화

FK 가 있으면 부모(`stores`)가 ID 원장에 있어 REMAP 이 새 매장 ID 를 찾아 준다.
FK 가 없는 19개는 **원장에 기대지 않고** 서버가 확정한 목적지 매장 ID 를 직접 넣는다.

---

## 묻는 것

1. **우선순위 7단계가 맞나?** 특히 3번(UNIQUE)이 5번(FK)보다 앞선 것.
   `users.email` 은 FK 가 아니라 상관없지만, 앞으로 **FK 이면서 UNIQUE 정책이 붙은**
   컬럼이 생기면 UNIQUE 가 이긴다. 그게 맞나, 아니면 그런 자리는
   **애초에 두 선언이 공존하면 안 되는 것**인가?

2. **`DESTINATION_STORE` 특수화가 맞나?** 아니면 `store_id` 는 FK 유무와 무관하게
   전부 `DESTINATION_STORE` 여야 하나? 지금은 FK 있는 것은 `REMAP→stores`,
   없는 것은 `DESTINATION_STORE` 로 **두 길**이라 결과가 같아도 경로가 다르다.
   ★ 대조군을 돌렸더니 이 특수화를 지워도 검사가 **통과했다**(두 경로 모두 허용해서).
     검사를 고쳐 특수화를 못 박았는데, 애초에 한 길로 합치는 게 나은가?

3. **`POLYMORPHIC` 을 `CLEAR` 로 떨어뜨린 것이 맞나?**
   `audit_logs.entity_id` 는 `entity_type` 이 **자유 문자열 라벨 23종**
   ("Producto" 와 "producto" 가 따로 있다)이라 되짚을 수 없다.
   지금은 비운다 — "감사 로그의 대상 링크가 끊기는 것이 남의 매장을 가리키는 것보다 낫다".
   아니면 **CLONE 에서 `audit_logs` 를 통째로 빼는 것**이 맞나?

4. **계획(plan)에 담아야 하는데 아직 없는 것은?**
   지금은 테이블별 컬럼 지시 + 거부 컬럼 + DEFERRED 컬럼 + 사람이 읽을 notice 뿐이다.
   행 수·해시·스키마 지문은 아직 없다(입력 검증 조각에서 붙일 예정).

5. **다음 조각의 순서.** 내 생각은
   ① 입력 검증(허용 컬럼 기반) → ② DB 계획 테이블 + 3-엔드포인트 →
   ③ 실행기(bulk insert + ID 원장 + DEFERRED 집행 + 커밋 전 증명) → ④ `clone_only` 개방.
   이 순서가 맞나? ②를 먼저 하면 배선이 생겨 위험한가?

6. **범위 질문 셋** — 아직 못 정했다. 네 판단을 듣고 싶다:
   복제 매장이 원본의 (가) `box_settlements` (나) `billing_invoices`
   (다) `store_notices`(플랫폼이 원본 매장에 보낸 공지) 를 물려받아야 하나?

7. 내가 놓친 것.

한국어. 결론 먼저. 반대할 것은 분명히 반대하라. **7개 전부 답하는 것을 우선하라.**
저장소를 직접 읽어도 된다 — `api-ventago/src/app/store/` 에 전부 있다.
