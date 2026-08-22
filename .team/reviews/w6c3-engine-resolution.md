# W6-C3 ② 엔진 본체 설계 — codex 자문 결과 (2026-08-22)

원본: `.team/reviews/w6c3-engine-codex.md` · 질문: `.planning/QUESTION-2026-08-22-d-복원엔진-본체-설계.md`

codex 결론: **"`CLONE` 전용 엔진은 지금 열어도 되는 방향. 다만 세 가지는 설계를 바꿔야 한다."**

| 안 | codex | 결정 |
|---|---|---|
| F1 plan → execute 2단계 | 찬성, **단 execute 가 파일을 다시 받으면 안 된다** | 수정 수용 |
| F2 입력 검증 | 찬성, **컬럼 이름만으로 부족** — 타입·제약·트리거까지 | 확대 수용 |
| F3 잠금 + 카탈로그 대조 | 찬성, 중복 실행은 **DB 상태 전이**가 따로 막아야 | 수용 |
| F4 단일 트랜잭션 | 찬성, **단 ORM create 1만 번은 반대** — bulk insert | 수용 |
| F5 DEFERRED 원장 | 찬성, **전체 ID remap 원장으로 확대** | 수용 |
| F6 역방향 소유 증명 | 찬성, **ID 범위 금지** — 임시 원장 기반 | 수용 |
| F7 자격증명 행 보존 | **조건부** — 소비자 게이트를 같은 배포에서 고치기 전엔 반대 | 수용 (아래 ★) |
| F8/F9 CLONE 만 개방 | 찬성 | 수용 |
| 운영 상태 정규화 1개 | **확정하지 말 것** — 4분류 감사 필요 | 수용 |

---

## ★ 근거를 직접 대조한 것 (둘 다 사실이었다)

### ① `mp_accounts` 는 행을 남겨도 결제 경로에 안 걸린다

```ts
// mp-account-resolver.service.ts — 두 갈래 모두 disconnectedAt: null 필터
where: { storeId, branchId, disconnectedAt: null }
where: { storeId, branchId: null, disconnectedAt: null }
```

→ `disconnected_at` 을 채워 두면 결제 resolver 가 그 계정을 **고르지 않는다.**
행을 남겨 `mp_wallets`·`mp_payment_intents` FK 와 과거 감사 관계를 지킬 수 있다.
다만 `findByPk()` 로 계정을 **직접** 읽는 결제·웹훅 경로가 같은 검사를 하는지
**전수 확인이 따로 필요하다**(codex 지적).

### ② `commerce_channels`/`wp_channels` 는 행만 남겨도 "연결됨" 으로 보인다

```tsx
// IntegracionesHubView.tsx:106
setWpStatus(wpChannels.length > 0 ? 'connected' : 'disconnected')
```

→ **`isActive` 를 안 본다. 행 개수만 본다.** 비활성 행을 남기면 복제 매장의
설정 화면이 "연결됨" 이라고 말한다. 자격증명은 없는데.

★ 이것이 codex 가 F7 을 조건부로 돌린 이유다. 내 질문은
  "존재하지만 못 쓰는 것 vs 없는 것 중 어느 쪽이 덜 위험한가" 였는데,
  **답은 테이블마다 다르고, 소비자가 그 상태를 어떻게 읽는지가 정한다.**
  `mp_accounts` 는 소비자가 이미 제대로 걸러서 보존이 낫고,
  `wp_channels` 는 소비자가 안 걸러서 보존이 거짓말이 된다.

---

## codex 가 바꾸라고 한 것 세 가지

### 1. `execute` 는 `planId` 만 받는다

```
POST /store/restore/uploads   multipart file        → uploadId
POST /store/restore/plan      { uploadId, mode, registrationId? } → { planId, summary, expiresAt }
POST /store/restore/execute   { planId }            → 결과
```

`mode` 까지 plan 에 고정한다. execute 에서 바꿀 수 있으면 **검토한 작업과 실제 작업이 달라진다.**

상태 저장: 업로드 원본은 MinIO 임시 객체, 계획 메타는 **DB**.
**메모리는 반대** — PM2 4워커라 plan 과 execute 가 다른 워커에 갈 수 있다.
`PLANNED → EXECUTING` 을 원자적 전이로 한 번만 허용해 이중 클릭·재실행을 막는다.

★ 그리고 새 매장의 **정체성을 파일에서 가져오면 안 된다**(HIGH).
  `store.name`·owner group·대표자·구독 상태는 **가입 신청 레코드와 현재 권한**에서 확정한다.

### 2. 역방향 소유 증명은 임시 원장으로 (ID 범위 금지)

시퀀스에는 동시 INSERT·롤백 구멍·트리거 생성 행이 섞이므로
`id BETWEEN a AND b` 는 **남의 행을 포함하거나 복원 행을 누락한다.**

→ REMAP 에 어차피 필요한 ID 매핑을 **트랜잭션 임시 테이블**로 승격한다
(`restore_rows(table_name, old_pk, new_pk, kind)`), 그 `new_pk` 만 증명한다.
전 테이블 스캔이 아니라 1만 PK 인덱스 조인이 된다.

★ "원장이 틀리면 감사도 헛돈다" 는 내 우려에 대한 답:
  원장을 **감사 보조자료가 아니라 INSERT 성공과 FK remap 의 유일한 근거**로 만든다.
  `입력 수 = RETURNING 수 = 원장 수` **삼중 일치**가 아니면 롤백한다.

### 3. F7 은 소비자 게이트와 **같은 배포**로

`wp_channels`/`commerce_channels` 는 위 ② 때문에 UI·서버 소비자를 먼저 고쳐야 한다.
그 전에 열면 "연결됨" 이라 표시되는 껍데기가 생긴다.

---

## codex 가 추가로 짚은 것

| 급 | 무엇 |
|---|---|
| HIGH | 새 매장 정체성을 파일이 아니라 가입 신청에서 확정 |
| HIGH | 런타임 대조가 FK 만이면 부족 — 타입·nullable·default·identity·PK·UNIQUE·CHECK·트리거까지 fingerprint |
| HIGH | **전역 UNIQUE 충돌 정책** — users email/username 말고도 slug·code·webhook key 등이 있다. plan 단계에서 전 UNIQUE 를 4분류(재발급/유지/거부/매장범위) |
| HIGH | **트리거 부작용** — 복원 INSERT 가 감사·알림·큐·파생원장을 돌린다. 무조건 비활성화는 반대(제약 보호까지 잃는다). 트리거마다 분류 필요 |
| MEDIUM | advisory lock 만으로 중복 실행이 안 막힌다 — 새 store ID 는 생성 전엔 없다 |
| MEDIUM | 결과 감사 기록 (누가·원본 해시·생성 store ID·테이블별 행 수·실패 단계). **백업 원문·자격증명은 로그 금지** |

## 운영 상태 4분류 — `restaurant_tables` 하나로 확정하지 말 것

codex 의 분류:

1. `PRESERVE_HISTORY` — 판매·결제·원장·감사 **사실**
2. `RESET_RUNTIME_STATE` — 설정 행은 필요하지만 **현재 실행 상태**는 초기화
3. `REAUTH_REQUIRED` — 관계·설정 보존, 외부 권한 제거
4. `EXCLUDE_EPHEMERAL` — 세션·토큰·기기·큐. 아예 복제 안 함 (이미 EXCLUDED 로 되어 있다)

찾는 신호 (내가 쓴 "status + FK" 만으로 부족):
`current_*_id` · `active_*_id` · `open_*_id` · `locked_by` · `assigned_*` ·
`status` + `opened_at/closed_at/completed_at/disconnected_at` 조합 ·
서비스가 **두 컬럼을 한 UPDATE 로** 바꾸는 코드 ·
cron/worker 가 `pending/running/retry` 를 조회하는 테이블 · 외부 식별자·webhook secret·OAuth token

**가장 강한 감사 질문:**
> 새 매장이 생성된 직후 cron·worker·POS·외부 webhook 이 이 행을 **"지금 처리해야 할 일"** 로 인식하는가?

우선 후보: `campaign_recipients`(pending/retry) · `client_imports`/`code_imports`(running) ·
`cash_registers`(열린 세션) · `rider_settlements`(open) · `commerce_channels`/`wp_channels`/`mp_accounts` ·
프린터·에이전트 연결 상태.

반대로 `sales.status`·`online_orders.status`·`billing_*`·`box_settlements` 는
**과거 사실이거나 정산 권위**일 수 있어 이름만 보고 초기화하면 안 된다.
각 상태를 소비하는 서비스의 **"다음 행동"** 을 확인해야 한다.
