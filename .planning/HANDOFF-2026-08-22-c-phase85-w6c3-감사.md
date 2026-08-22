# 핸드오프 — 2026-08-22 (c) · Phase 85 W6-C3 감사 3종 + 운영 정리

`HANDOFF-2026-08-22-b-phase85-w6c3-매니페스트.md` 에서 이어짐.
사용자 지시: **"phase 85만 해라"** · **"codex 조언 듣고"** · **"오염 4행 정리하고, 중복 FK 는 없애도록"**

---

## ★ 이 세션의 한 줄

**엔진을 짓기 전에 감사를 먼저 돌렸고, 그 결정이 옳았다 —
FK 기반 매니페스트가 못 보는 곳에서 만 행 단위의 교차 매장 참조와
"복제하면 진짜 고객에게 메시지가 다시 가는" 경로가 나왔다.**

---

## 배포 (전부 SUCCESS + blue/green 전환 + smoke 5종)

```
api-ventago  fb0fa5b  오염 4행 정리 + 중복 FK 제거        #789
             70892b1  감사① UNIQUE + FK 없는 참조 90개    #790
             7e43a2b  감사② 트리거 58개 분류              #791
             9722c67  감사③ 운영 상태 4분류               #792
운영 DB      2026-08-22-w6-limpiar-filas-cruzadas.sql  적용 (4행 삭제)
             2026-08-22-w6-drop-duplicate-fks.sql      적용 (제약 3개, 영향 0행)
로컬 DB(5432) 0테이블 — 미적용. 복원 시 순서대로 돌릴 것 (둘 다 사실상 no-op)
```

---

## 완료: 이월 두 건 (사용자 승인)

### 오염 4행 정리 → **감사기가 종료코드 0 이 됐다**
`venta_suspendida_items` 2 + `ventas_suspendidas` 1 + `qr_print_log` 1 삭제.
모호 0건. 고아 109건은 전역 데이터라 실패시키지 않는다.
구멍(쓰기 경로 3곳)은 **이 정리 이전에** 막았다 — 순서가 근거다.

### 중복 FK 제약 3개 제거
★ 출처를 추적했다: `2026-07-28-phase64-missing-constraints.sql` 이 스키마를 맞출 때
**제약의 "이름" 만 대조하고 "의미" 는 안 봤다.** 이미 같은 (컬럼→부모컬럼)을 덮는
제약이 다른 이름으로 있는지 확인하지 않아 중복이 만들어졌다.
★ `mes_material_movements` 쪽은 정의가 달라서, 남는 짝의 `ON UPDATE CASCADE` 가
지운 쪽 때문에 **무력화돼 있었다.**
검증을 두 방향으로 했다 — 중복 0건 **+ 남은 제약 3개 존재**
("중복 0" 만 보면 둘 다 지워진 경우도 통과한다).

---

## ★★ 감사 3종 — 엔진을 짓기 전에 미지수를 없앤다

codex 자문(`.team/reviews/w6c3-engine-resolution.md`)이 HIGH 4건을 짚었고,
그중 3건이 "먼저 알아야 할 미지수" 였다. 순서를 뒤집으면 지은 걸 다시 짓는다.

### 감사① — **매니페스트의 완결성 주장이 불완전했다** ← 이번 세션 최대 발견

W6-C3 ① 은 "FK 컬럼 351개 전부에 처리를 정했다" 고 말한다. **참이지만 안전하다는
뜻이 아니었다** — 매니페스트는 FK 카탈로그에서 처리를 유도하므로
**FK 제약이 없는 참조는 애초에 보이지 않는다.**

| | |
|---|---:|
| FK 없는 참조 컬럼 | **90개** |
| 그중 `store_id`/`branch_id` | **19개** |
| `role_functions.store_id` 만 | **11,790행** |

실측으로 이 값들은 **전부 실제 `stores.id`·`branches.id` 와 일치**했다 —
진짜 참조인데 DB 가 말을 안 할 뿐이다. 그대로 복사하면 **복제 매장의
권한·재고·정산이 원본 매장을 가리킨다.** Phase 85 W6 이 막으려던 결함 그 자체다.

→ `store-restore-unlinked-refs.{ts,txt}` 로 90개 전부 선언.
근거 등급(`MEASURED`/`CODE`/`UNVERIFIED`)을 값마다 붙였다 —
**추측과 확인을 섞지 않는다.** 미확인 4개는 세어 보이게 남겼다.

**그 밖:**
- **마스킹 × NOT NULL = 8개** (`branch_agents.api_key` · `commerce_channels.secret` ·
  `mp_accounts.access_token` …). 그 5개 테이블은 **지금 백업으로는 INSERT 조차 안 된다.**
  설계 문서엔 6개라 적혀 있었고 W6-C2 에서 둘이 늘었는데 아무도 다시 안 셌다
  → **숫자를 문서가 아니라 카탈로그가 세게** 했다.
- ★ **감사 도구 자체가 두 번 조용히 틀렸다.** `unnest(indkey)` 로 컬럼을 모으면
  `whatsapp_templates (COALESCE(store_id,0), …)` 가 "전역" 으로 오분류되고
  `stores (lower(alias_name))` 은 목록에서 **통째로 사라진다.**
  둘 다 "덜 위험해 보이게" 틀린다 — 감사 도구에서 가장 나쁜 방향이다.
- `expense_categories.parent_id` 는 TWO_PHASE 로 넣으면 **1단계에서 죽는다**
  (`WHERE parent_id IS NULL` 부분 인덱스가 자식까지 root 로 본다).
  오늘 데이터로는 안 터지지만 스키마가 허용한다 → `ROW_ORDERED` 선언.

### 감사② — 트리거 58개

★★ `audit_row_change` 가 7개 테이블에 AFTER INSERT. 매장 9 복제 기준
**가짜 감사 로그 5,652행**을 만드는데 그 매장의 **진짜 감사 이력은 151행**이다.
97%가 소음이 되고 전부 복원 실행자가 방금 만든 것처럼 기록된다.
게다가 `audit_logs` 는 백업에서 복원하는 테이블이라 **이중 기록**. → `SUPPRESS`.

★ 반대로 **34개가 `tenant_chk_*` 테넌트 격리 가드**였다. 복원이 재매핑을 틀리면
**DB 가 행 단위로 막아 준다** — 우리가 만들려는 커밋 전 불변식을 DB 가 이미 절반
갖고 있다. codex 말대로 무조건 비활성화는 답이 아니다.

★ **spec 이 내 거짓 선언 3건을 잡았다.** "복원은 INSERT 만 하니 안 돈다" 로
`NOT_REACHED` 를 적었는데 **DEFERRED 2단계가 UPDATE 를 친다** — 전제부터 틀렸다.

### 감사③ — 운영 상태 4분류

codex 판별질문: **"새 매장이 생긴 직후 cron·worker·POS·외부 webhook 이
이 행을 '지금 처리해야 할 일' 로 인식하는가?"**

| 테이블 | 무엇이 집어가나 | 결과 |
|---|---|---|
| **`campaign_recipients`** | `CampaignSenderService` **30초** 워커 | **실제 고객에게 WhatsApp 재발송** |
| `campaigns` | 같은 워커가 `queued → sending` | 짝이라 함께 되돌린다 |
| **`cash_registers`** | `autoclose` 크론 **매시간** | 운영 **16개 열림** → 거래 없는 매장에 정산·금고이체 생성 |
| `branch_agents` | `reaper` 크론 **매분** | 없는 프린터로 출력 |
| `restaurant_tables` | POS `placeOrder()` | (이전 세션에 처리) |

★ **되돌리지 않는다** 고 판정한 것도 근거와 함께 적었다 —
`online_orders`(만료는 사실 정리) · `talleres_envios`(알림만, 채권은 실재) ·
`sales`(status 는 회계 사실) · `box_settlements` · `billing_invoices`.
"봤고 되돌릴 필요 없다" 를 안 적으면 다음 사람이 처음부터 다시 판단한다.

---

## codex 자문 — 근거를 직접 대조한 것

| 주장 | 확인 |
|---|---|
| `mp_accounts` 는 행을 남겨도 결제 경로에 안 걸린다 | ✅ resolver 두 갈래 모두 `disconnectedAt: null` 필터 |
| `wp_channels` 는 행만 남겨도 "연결됨" 으로 보인다 | ✅ `IntegracionesHubView` 가 `wpChannels.length > 0` 만 본다 |

★ 내 질문("존재하지만 못 쓰는 것 vs 없는 것")의 답:
**테이블마다 다르고, 소비자가 그 상태를 어떻게 읽는지가 정한다.**

---

## 대조군 — 만든 검사가 실제로 무엇을 막는지 전부 확인

감사① 4종 · 감사② 3종 · 감사③ 3종 — **10종 전부 잡혔다.**
통과는 "검사 안 함" 과 구분되지 않는다.

현재: `src/app/store` + `src/common/migrations` **179/179 통과.**

---

## ★ 다음 — W6-C3 ② 엔진 본체

codex 설계(`.team/reviews/w6c3-engine-resolution.md`)를 그대로 지으면 된다.
**감사가 끝났으므로 이제 미지수가 없다.**

1. `POST /store/restore/uploads` → `/plan` → `/execute` (execute 는 **planId 만** 받는다)
   - 업로드 원본은 MinIO 임시 객체, 계획 메타는 **DB**(메모리 금지 — PM2 4워커)
   - `PLANNED → EXECUTING` 원자적 전이로 중복 실행 차단
   - ★ 새 매장 정체성은 **가입 신청**에서 확정 (파일의 `store.name`·slug·대표자 아님)
2. 실행기: 위상 정렬 순서로 bulk insert + `RETURNING` 으로 ID 원장
   - `restore_rows(table, old_pk, new_pk)` **임시 테이블** — ID 범위 금지
   - `입력 수 = RETURNING 수 = 원장 수` **삼중 일치** 아니면 롤백
3. DEFERRED 집행 + `unresolvedDeferred()` 0건 확인
4. advisory lock → 런타임 카탈로그 대조(정규화 의미 비교) → 첫 쓰기
5. 커밋 전 역방향 소유 증명 — **원장의 `new_pk` 만** 대상
6. `RESTORE_ENGINE_STATUS` 를 `'clone_only'` 로. `IN_PLACE_RECOVERY` 는 계속 거부

**선행 조건 (열기 전에 반드시):**
- ⬜ 미확인 참조 4개 확정 (`expense_cheque_events.operation_id` ·
  `store_notices.campaign_id` · `sale_items.promo_group_id` ·
  `stock_adjust_batches.request_id`)
- ⬜ `commerce_channels`/`wp_channels` **소비자 게이트를 같은 배포에서** 수정
  (프론트가 행 개수로 "연결됨" 을 판정한다)
- ⬜ `seller_attendance` 열린 근무를 무엇으로 되돌릴지 결정 (`RESET_UNRESOLVED`)
- ⬜ **범위 질문 둘**: 복제 매장이 원본의 `box_settlements` / `billing_invoices` 를
  물려받아야 하는가 (상태가 아니라 범위 문제다)
- ⬜ `audit_logs.entity_id` 다형 참조 — CLONE 에서 `audit_logs` 를 어떻게 할지
  (`entity_type` 이 자유 문자열 라벨 23종이라 되짚을 수 없다)
- ⬜ `mp_accounts` 를 `findByPk()` 로 직접 읽는 결제·웹훅 경로 전수검사

---

## 이월

- W6-C4 DB 복합 FK: `sale_items` 등에 `store_id` → 3회 배포.
  ★ 감사①이 **더 급한 것을 찾았다** — FK 없는 테넌트 컬럼 19개가 먼저다
- **로컬 DB(5432) 0테이블** — 복원 시 오늘 마이그레이션 2개 + `w6-talleres-missing-fks.sql`
- `products.image_url` UTF-8 모지바케 — 별건
- 종전 이월 유지: sudoers mode 0440 · 프론트 blue/green 없음 ·
  POS 카탈로그 P95 376ms · 소켓 한도 0 · `/me` 11쿼리 미캐시
