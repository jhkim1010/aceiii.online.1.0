# W6-C3 ② 복원 계획 코어 — codex 검토 수용 (2026-08-22)

원본: `.team/reviews/w6c3-plan-codex.md` · 질문: `.planning/QUESTION-2026-08-22-e-복원계획코어.md`

codex 결론: **"코어의 분리 방향은 승인, 다음 조각 진행 전 HIGH 3건 수정 필요."**
**세 건 모두 근거를 대조해 확인했고 전부 수용했다.**

---

## ★★ 그리고 그 검토가 만든 검사가 **내 결함 두 건을 더** 잡았다

codex 는 `audit_logs.entity_id` 하나를 짚었다. 같은 형태를 전수로 세어 보니 셋이었다:

| 컬럼 | 지시 | 누가 만들었나 |
|---|---|---|
| `audit_logs.entity_id` | `CLEAR` | codex 가 지적 |
| `campaign_recipients.next_retry_at` | `RESET null` | **내 감사③ 선언** |
| `mp_accounts.mp_user_id` | `CLEAR` | **내 감사① 선언** |

**셋 다 `NOT NULL` 이라 INSERT 를 그 자리에서 죽인다.**

★ 선언 네 벌이 각자 옳아 보여도 **컬럼의 NOT NULL 과 부딪히는지는 카탈로그와
대조해야만 보인다.** 지적 하나를 "그 한 건" 으로 고치고 넘어갔으면 두 건이 남았다.
→ 영구 검사로 박았다(`CLEAR / DEFERRED / RESET(null)` 이 NOT NULL 에 붙으면 빌드 실패).

---

## HIGH ① — 행동과 계약이 어긋난 이중 구조

```ts
if (NEVER_FROM_BACKUP.has(entry.column)) {
  return at({ kind: 'COPY' }, 'NEVER_FROM_BACKUP(생략 대상)');   // ← 틀렸다
}
```

`ColumnAction.COPY` 의 계약은 "백업 값을 그대로 넣는다" 다. `source` 문자열에만
"생략 대상" 이라고 적어 두면, 실행기가 그 **문자열을 해석하지 않는 한 원본 PK 를
그대로 INSERT** 한다. 시퀀스와 충돌하거나 원본 매장의 ID 공간을 침범한다.

→ `GENERATED_ID` 액션을 분리했다. 시각 컬럼은 `COPY` 로 두되 **"역사 보존"** 이라는
근거를 붙였다 — 복원 시각으로 뭉개면 판매·원장 통계와 정산이 통째로 틀린다.

★ 대조군을 돌렸더니 `id`→`COPY` 로 되돌려도 **처음엔 통과했다.** 검사가 없었다.
  지금은 "모든 PK 가 GENERATED_ID" 를 전수로 확인한다.

## HIGH ② — `audit_logs` 는 CLONE 대상이 아니다

선택지가 둘뿐이었고 **둘 다 틀렸다**:
- 그대로 복사 → 새 매장의 행이 **원본 매장 엔티티**를 가리킨다 (의미가 거짓)
- 비운다 → **`NOT NULL` 위반**

그 막다른 골목 자체가 "복제 대상이 아니다" 의 근거다. `entity_type` 이 자유 문자열
라벨 **23종**이고("Producto" 와 "producto" 가 따로 있다) `old_values`/`new_values` 에
원본 ID 와 개인정보가 들어 있다.

→ `CLONE_EXCLUDED_TABLES` 를 신설했다. **`EXCLUDED_TABLES`(백업 제외)와 다르다** —
아카이브로 보존하는 것과 새 매장의 운영 데이터가 되는 것은 다른 일이다.

## HIGH ③ — UNIQUE 는 컬럼 행동과 **다른 축**이다

내 구현은 인덱스 정의를 정규식으로 훑어 참여 컬럼 전부에 같은 행동을 붙였다. 둘이 틀린다:
- `(store_id, external_code)` 에 `REJECT` 가 붙으면 **`store_id` 의 목적지 변환까지 덮어쓴다**
- 한 컬럼이 여러 인덱스에 참여하면 `Map.set()` 의 **마지막 정책이 조용히 이긴다**

> 컬럼 행동은 "이 값이 **무엇으로 변환되는가**",
> 제약 정책은 "**변환된 결과**가 제약을 충족하는가".

→ `constraintPolicies` 로 축을 분리했다. `SERVER_IDENTITY` 는 정규식 유도를 버리고
`SERVER_IDENTITY_COLUMNS` 로 **컬럼 단위 직접 선언**한다
(`lower((alias_name)::text)` 같은 표현식·cast 에서 정규식이 오판한다).

★ 그래서 **FK 이면서 UNIQUE 인 컬럼은 합법적 공존**이다. 우선순위로 다투게 두면 안 된다.

---

## 그 밖 수용

| 지적 | 조치 |
|---|---|
| `DEFERRED` 에 FK 간선이 없으면 자기 테이블로 fallback | **던진다.** 대상을 추측하면 엉뚱한 부모를 가리키는 원장이 조용히 만들어진다 |
| 충돌 검사가 `!== undefined` | `in` 으로. 되돌릴 값이 `null` 인 선언(`current_sale_id: null`)을 **놓치고 있었다** |
| `RESET_UNRESOLVED` 가 있으면 plan 거부 | 적용. 미결인 채 집행하면 그 행이 원본 상태 그대로 복제된다 |
| nullable FK 의 `required` 가 모호 | 미해결 — 다음 조각(실행기)에서 "입력 non-null 인데 매핑 없음" 은 실패로 정한다 |
| `notices` 가 문자열뿐 | 미해결 — 구조화된 영향 요약이 필요하다 |

### `seller_attendance` 미결을 **행 필터**로 해소했다

퇴근 시각을 지어내는 것은 **거짓 사실을 만드는 일**이라 컬럼을 되돌릴 수 없었다.
그리고 열린 근무는 과거가 아니라 **현재 상태**다 — 복제 매장이 남의 근무를 이어받아
퇴근 처리하면 그 사람의 근태 기록이 된다.
→ `CLONE_ROW_FILTERS`: `check_out_at IS NOT NULL` 인 행만 복제한다.

---

## 범위 질문 셋 — codex 판단

| | 판단 | 근거 |
|---|---|---|
| `box_settlements` | **포함** | 크론이 `settled_through` 를 기준선으로 삼는다. 빼면 복제된 과거 `cash_registers` 가 **전부 미정산으로 인식**돼 새 정산·금고 이체가 만들어진다 |
| `billing_invoices` | **제외** | 매장 영업 이력이 아니라 **플랫폼과 원본 법적 주체 사이의 채권·세무 문서**다. `billing_payments`·`billing_payment_submissions` 까지 **종속 그래프 전체** |
| `store_notices` | **제외** | 원본에게 보낸 공지다. `read_at IS NULL` 이면 새 매장 접속 즉시 과거 공지가 **현재 공지로** 뜬다. fan-out 통계도 왜곡된다 |

★ 셋 다 아직 **반영하지 않았다** — `CLONE_EXCLUDED_TABLES` 에 billing 3종과
`store_notices` 를 넣는 것이 다음 조각의 첫 작업이다.

## 다음 조각 순서 (codex 권장 — 내 안에서 ②를 뒤로 미룸)

```
1. 입력 파서와 검증기
2. 완전한 순수 plan 생성기      ← 지금 여기(부분)
3. DB 계획 테이블 + 원자적 상태 전이
4. 실행기 + 커밋 전 증명
5. 업로드/plan/execute 엔드포인트 배선   ← 내 안에서는 3번이었다
6. 실패 주입·재실행·동시 실행 통합 테스트
7. clone_only 개방
```

> 실행기 없이 upload/plan 만 열어도 **임시 객체 누적, 저장공간 DoS, 만료 청소,
> 권한 경계** 같은 운영 표면이 생긴다.

`RESTORE_ENGINE_STATUS='blocked'` 는 **마지막 통합 검증까지** 유지한다.
