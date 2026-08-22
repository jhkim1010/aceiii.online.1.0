# 핸드오프 — 2026-08-22 (d) · Phase 85 W6-C3 ② 계획 코어

`HANDOFF-2026-08-22-c-phase85-w6c3-감사.md` 에서 이어짐.
사용자 지시: **"phase 85만 해라"** · **"미확인 참조 4개 확정하고 엔진 진행"** · **"codex 자문 구하고"**

---

## ★ 이 세션의 한 줄

**복원 계획 코어를 지었고, 그 과정에서 만든 전수 검사가
codex 지적 1건을 확인하면서 **내가 같은 날 만든 결함 2건을 더** 잡아냈다.**

---

## 배포 (전부 SUCCESS)

```
api-ventago  2c07a9d  미확인 참조 4개 확정 + 계획 코어      #793
             78e13e3  codex HIGH 3건 + NOT NULL 전수 검사   #794
             bf1d851  범위 질문 셋 반영                     #795
운영 DB 변경 없음
```

---

## 완료: 미확인 참조 4개 — **넷 다 참조가 아니었다**

| 컬럼 | 확정 | 근거 |
|---|---|---|
| `expense_cheque_events.operation_id` | 한 요청이 만든 행을 묶는 UUID | 모델 주석 + 값 대조 0/2 |
| `store_notices.campaign_id` | admin-console 의 fan-out `randomUUID()` | `campaigns.id` 는 **integer** |
| `sale_items.promo_group_id` | 프로모션 묶음 UUID | 실제 FK 는 `promotion_id` 가 따로 |
| `stock_adjust_batches.request_id` | **`Idempotency-Key`** → `CLEAR` | 복원하면 정상 신규 조정이 "재요청" 으로 오인 |

★ 값을 데이터로 대조했을 때 **안 맞았던 것이 단서**였다.
  `_id` 로 끝나고 uuid 여도 다른 테이블을 가리킨다는 뜻은 아니다.

---

## 만든 것 — `store-restore-plan.ts`

선언이 **네 파일**로 나뉘어 있다(근거가 각각 다르다 — codex E4 를 따른 것).
그런데 실행기는 **컬럼 하나에 답 하나**가 필요하다.
→ `resolveColumn()` 하나로 합치고, spec 이 **1,826개 전 컬럼**을 돌려
"정확히 하나의 답" 을 전수 검사한다.

`ColumnAction`: `COPY` / `GENERATED_ID` / `REMAP` / `DESTINATION_STORE` /
`KEEP_GLOBAL{scope}` / `CLEAR` / `RESET{value}` / `REGENERATE{secret}` /
`SERVER_IDENTITY` / `DEFERRED` / `REJECT`

---

## ★★ codex 검토 — HIGH 3건, 전부 근거 대조 후 수용

전문: `.team/reviews/w6c3-plan-resolution.md`

| # | 지적 | 조치 |
|---|---|---|
| ① | `id`/timestamps 가 `COPY` — **행동과 계약이 어긋난 이중 구조**. 실행기가 source 문자열을 안 읽으면 **원본 PK 를 그대로 INSERT** | `GENERATED_ID` 분리. 시각은 "역사 보존" 근거로 **일부러** COPY |
| ② | `audit_logs` 는 CLONE 대상이 아니다 | `CLONE_EXCLUDED_TABLES` 신설 |
| ③ | UNIQUE 를 컬럼 행동으로 평탄화하면 FK/테넌트 변환을 덮어쓴다 | `constraintPolicies` 로 **축 분리** |

### ★★★ 그리고 그 지적으로 만든 검사가 **내 결함 두 건을 더** 잡았다

| 컬럼 | 지시 | 누가 |
|---|---|---|
| `audit_logs.entity_id` | `CLEAR` | codex |
| `campaign_recipients.next_retry_at` | `RESET null` | **내 감사③ 선언** |
| `mp_accounts.mp_user_id` | `CLEAR` | **내 감사① 선언** |

셋 다 `NOT NULL` 이라 **INSERT 를 그 자리에서 죽인다.**
★ 지적 하나를 "그 한 건" 으로 고치고 넘어갔으면 두 건이 남았다.
**같은 형태를 전수로 세는 것**이 지적을 받는 것보다 중요하다.

### ②의 근거가 특히 중요하다

`audit_logs.entity_id` 는 선택지가 둘뿐이었고 **둘 다 틀렸다** —
복사하면 원본 매장 엔티티를 가리키고(의미가 거짓), 비우면 NOT NULL 위반.
**그 막다른 골목 자체가 "복제 대상이 아니다" 의 근거**다.

---

## 범위 질문 셋 — codex 판단대로 반영

| | 결정 | 근거 |
|---|---|---|
| `box_settlements` | **포함** | 크론이 `settled_through` 를 기준선으로 삼는다. 빼면 복제된 과거 카하가 **전부 미정산**으로 인식돼 거래 없는 매장에 정산·금고이체가 생긴다 |
| `billing_*` 3종 | **제외** | 매장 영업 이력이 아니라 플랫폼과 **원본 법적 주체** 사이의 채권·세무 문서. 자식 `invoice_id` 가 NOT NULL 이라 **종속 그래프 단위**로 |
| `store_notices` | **제외** | `read_at IS NULL` 공지가 복제 매장에 **현재 공지로** 뜬다 |
| `store_billing_discounts` | **제외** | ★ codex 가 말하지 않았고 **내가 같은 근거로 확장**했다. 되돌릴 근거가 있으면 한 줄 지우면 된다 |

★ "제외는 종속 그래프 단위" 를 **구조적으로 강제**하는 검사를 넣었다 —
제외한 부모를 NOT NULL REMAP 으로 가리키는 자식이 남으면 빌드가 깨진다.

## 그 밖 해소

- `seller_attendance` 미결 → **행 필터**(`check_out_at IS NOT NULL`).
  퇴근 시각을 지어내는 것은 거짓 사실을 만드는 일이라 컬럼을 되돌릴 수 없었다.
- `RESET_UNRESOLVED` 가 하나라도 있으면 **계획 생성 자체를 거부**한다.
- `DEFERRED` 에 FK 간선이 없으면 자기 테이블 fallback → **던진다.**
- 충돌 검사 `!== undefined` → `in` (되돌릴 값이 `null` 인 선언을 놓치고 있었다).

---

## 대조군 — 이번에 **두 번** 통과해 버렸다

| 대조군 | 첫 결과 |
|---|---|
| `store_id` DESTINATION_STORE 분기 제거 | ★ **통과** — 검사가 두 경로를 다 허용해 구분 못 함 |
| `id` → `COPY` 되돌리기 | ★ **통과** — 검사가 아예 없었음 |
| 부모만 빼고 NOT NULL 자식 남기기 | 목록 변화로만 잡힘 — 진짜 위험을 안 세고 있었음 |

셋 다 검사를 고쳐 지금은 잡힌다.
**대조군을 안 돌렸으면 "초록" 이 아무것도 안 막고 있었다.**

---

## ★ 다음 — codex 권장 순서 (내 안에서 엔드포인트를 뒤로 미룸)

```
1. 입력 파서와 검증기 (허용 컬럼 목록 기반, 미지 컬럼 거부)
2. 완전한 순수 plan 생성기          ← 지금 여기(부분)
3. DB 계획 테이블 + 원자적 상태 전이 (PLANNED→EXECUTING)
4. 실행기 + 커밋 전 증명
5. 업로드/plan/execute 엔드포인트 배선   ← 내 안에서는 3번이었다
6. 실패 주입·재실행·동시 실행 통합 테스트
7. clone_only 개방
```

> 실행기 없이 upload/plan 만 열어도 **임시 객체 누적·저장공간 DoS·만료 청소·
> 권한 경계** 같은 운영 표면이 생긴다. (codex)

`RESTORE_ENGINE_STATUS='blocked'` 는 **마지막 통합 검증까지** 유지한다.

### 계획에 아직 없는 것 (codex 목록)

`planId`·버전·만료 / 업로드 객체 ID + SHA-256 / 목적지 storeId·가입신청 ID·owner group /
테이블별 예상 행 수 / **트리거 집행 계획**(지금 `RestorePlan` 에 없다 —
실행기가 트리거 파일을 다시 읽으면 "검토한 계획만 실행한다" 가 깨진다) /
`KEEP_GLOBAL` scope 증명 결과 / 크기·행수 상한 / 실패 코드 / 결과 감사 레코드

### 아직 미해결

- nullable FK 의 `required` 가 모호 — "입력이 NULL 일 수 있음" vs "매핑 실패 허용".
  **입력이 non-null 인데 매핑이 없으면 nullable 이라도 실패**해야 한다
- `notices` 가 문자열뿐 — 구조화된 영향 요약 필요
- `mp_accounts` 를 `findByPk()` 로 직접 읽는 결제·웹훅 경로 전수검사
- `commerce_channels`/`wp_channels` 소비자 게이트 (프론트가 행 개수로 "연결됨" 판정)

---

## 이월

- 로컬 DB(5432) 0테이블 — 복원 시 오늘 마이그레이션 2개 + `w6-talleres-missing-fks.sql`
- W6-C4 DB 복합 FK — ★ 감사①이 더 급한 것을 찾았다(FK 없는 테넌트 컬럼 19개)
- `products.image_url` UTF-8 모지바케 — 별건
- 종전 이월 유지: sudoers mode 0440 · 프론트 blue/green 없음 ·
  POS 카탈로그 P95 376ms · 소켓 한도 0 · `/me` 11쿼리 미캐시
