# 핸드오프 — 2026-08-22 (e) · Phase 85 W6-C3 ② 입력 검증기 + 계획 테이블

`HANDOFF-2026-08-22-d-phase85-w6c3-계획코어.md` 에서 이어짐.
사용자 지시: **"phase 85만 해라"** · **"다음 작업 진행"**

---

## ★ 이 세션의 한 줄

**codex 권장 순서 1번(입력 검증기)과 3번(계획 테이블)을 지었고,
입력 검증기는 짓는 도중에 "진짜 백업 파일을 통째로 거부하는" 결함을 스스로 드러냈다.**

---

## 배포 (전부 SUCCESS)

```
api-ventago  8e5c67f  입력 검증기 (허용 목록 기반)        #796
             18004e1  계획 테이블 + 상태 기계             #797
운영 DB      2026-08-22-w6c3-store-restore-plans.sql 적용 (새 테이블 1개, 기존 행 0건 변경)
로컬 DB(5432) 0테이블 — 미적용
```

---

## ① 입력 검증기 — `store-restore-input.ts` · `store-backup-keys.ts`

지금 복원은 `backupData: any` 를 받아 `...fields` 로 펼쳐 넣는다. 파일에 있는 것이면
무엇이든 INSERT 로 간다. → **허용 목록 기준**으로 해석하고 모르는 것은 **거부**한다.

### ★★ 짓는 도중에 드러난 결함

ORM `toJSON()` 은 `DataType.VIRTUAL` 컬럼도 함께 낸다. **진짜 백업 파일**의
`users` 행에는 `roles` 가, `store` 행에는 `statusDetails`·`integrations`·
`typeOfPayers` 가 들어 있는데 **테이블에 그런 컬럼이 없다.**
선언 없이 지었으면 검증기가 **실제 백업 파일을 통째로 거부**했을 것이다.

→ `DERIVED_ROW_KEYS` 선언 + **모델 소스를 훑어** 새 VIRTUAL 이 생기면 빌드를 깨뜨린다.

★ "모르는 컬럼은 거부" 와 모순이 아니다 —
  **선언 없이** 버리면 조용한 유실, **이유와 함께** 버리면 기록된 판단이다.

### 컬럼 이름이 두 벌이다

raw SQL 은 `api_key`, ORM 은 `apiKey` — **같은 파일 안에 섞여 있다**
(`users`/`branches`/`sales` 는 ORM, `products`/`stocks`/`prices` 는 raw SQL).
한쪽만 보면 아무것도 안 보면서 봤다고 믿는다 — 마스킹에서 똑같이 당했다.
→ 양쪽을 카탈로그 이름으로 정규화하고, **한 행에 둘 다 있으면 거부한다**
  (어느 쪽이 진짜인지 우리가 정하면 안 된다).
★ 모델의 `@Column({field:})` **158쌍이 전부** 단순 camelCase 규칙을 따르는 것을
  확인했고, 벗어나면 빌드가 깨진다.

### ★ 대조군이 또 통과했다 — 이번엔 백업 키

백업 키가 세 벌(최상위 camelCase / 옛 키 / `tables[]`)이라 "테이블마다 정확히 한 자리" 를
강제했는데, **선언을 지워도 `tables[]` 폴백 때문에 자리 수가 그대로**라 통과했다.
→ `getStoreBackupData()` 의 **반환 리터럴을 직접 읽어** 쓰는 쪽과 읽는 쪽을 묶었다.
★ 그 추출도 처음엔 `key:` 만 잡아 shorthand(`products,`) **24개를 놓쳤다** —
  절반만 보면서 통과할 뻔했다.

---

## ② 계획 테이블 — `store_restore_plans` + `store-restore-plan-state.ts`

계획과 집행은 **다른 요청**이다. 운영은 PM2 4워커라 메모리에 두면 다른 워커로 가거나
재시작에 사라진다. 그리고 **중복 실행을 막을 자리**가 필요하다 —
`CLONE` 의 목적지 매장 ID 는 집행 전에 존재하지 않아 advisory lock 을 걸 대상이 없다.

```sql
UPDATE store_restore_plans SET status='EXECUTING'
 WHERE id=$1 AND status='PLANNED'      -- 0행이면 다른 요청이 이미 가져갔다
```

**운영에서 롤백 트랜잭션으로 검증했다:**

| 확인 | 결과 |
|---|---|
| owner | `coolsistema` ✓ |
| 전이1 (PLANNED→EXECUTING) | **1행** |
| 전이2 (재실행) | **0행** ← 배타성 |
| `chk_srp_destination` | destination 없는 SUCCEEDED 를 막음 ✓ |

검증 후 ROLLBACK. 테이블 0행.

### ★ 전이 표에 `FAILED → PLANNED` 를 넣지 않았다

실패한 집행이 **어디까지 갔는지** 모르는 채 같은 계획을 다시 돌리면
**절반 만들어진 매장 위에 또 만든다.** 재시도는 **새 계획**으로 한다.
`EXECUTING` 으로 가는 길도 `PLANNED` 하나뿐이다 — 그것이 조건부 UPDATE 가
배타성을 만드는 근거다.

### 판정과 선점을 나눴다

`checkClaimable()` 은 **사람에게 이유를 말하기 위한 것**이고, 실제 배타성은
`WHERE status='PLANNED'` 가 만든다. 판정만 있으면 경합에 뚫리고,
조건부 UPDATE 만 있으면 실패했을 때 **왜인지 말할 수 없다.**
만료를 상태보다 **먼저** 본다 — 만료된 `PLANNED` 를 집행하면 업로드 객체가 이미 청소된 뒤다.

### ★ 커버리지 가드가 새 테이블을 즉시 잡았다 (감시 두 겹 모두)

`store_restore_plans` 는 **EXCLUDED** — 매장 데이터가 아니라 복원 작업 자체의 기록이고,
복원하면 끝났어야 할 계획이 `PLANNED` 로 되살아난다.
`destination_store_id` FK 로 매장에 닿지만 그건 **"무엇을 만들었나"** 이지
**"누구 것인가"** 가 아니다.

★ 순서 제약도 드러났다: 테이블이 **운영에 생긴 뒤에만** 인벤토리를 재생성할 수 있어,
  승인 전에는 테스트를 초록으로 만들 수 없었다. 모델에 컬럼을 더할 때와 같은 형태다.

---

## ★ 다음 — codex 권장 순서 4번: **실행기 + 커밋 전 증명**

```
1. 입력 파서와 검증기            ✅ #796
2. 순수 plan 생성기              ✅ (부분 — 아래 "계획에 아직 없는 것")
3. DB 계획 테이블 + 상태 전이     ✅ #797
4. 실행기 + 커밋 전 증명          ← 다음
5. 업로드/plan/execute 엔드포인트 배선
6. 실패 주입·재실행·동시 실행 통합 테스트
7. clone_only 개방
```

### 실행기가 해야 하는 것

- 위상 정렬 순서로 **bulk insert** + `RETURNING` (ORM `create()` 1만 번은 codex 반대)
- `restore_rows(table, old_pk, new_pk)` **트랜잭션 임시 테이블** — **ID 범위 금지**
  (시퀀스에는 동시 INSERT·롤백 구멍·트리거 생성 행이 섞인다)
- **입력 수 = RETURNING 수 = 원장 수 삼중 일치** 아니면 롤백
- DEFERRED 원장 집행 + `unresolvedDeferred()` 0건
- advisory lock(목적지 매장) → 런타임 카탈로그 대조(정규화 의미) → **첫 쓰기**
- 커밋 전 역방향 소유 증명 — **원장의 `new_pk` 만** 대상
- `audit_row_change` 억제는 **트랜잭션 로컬**로 (pool 재사용 후 상태가 남으면 안 된다)
- MinIO 객체 복사는 **트랜잭션 시작 전에** 끝낸다

### 계획에 아직 없는 것 (codex 목록)

`planId`·버전·만료 / 업로드 객체 ID + SHA-256 / 목적지 storeId·가입신청 ID·owner group /
테이블별 예상 행 수 / **트리거 집행 계획**(실행기가 트리거 파일을 다시 읽으면
"검토한 계획만 실행한다" 가 깨진다) / `KEEP_GLOBAL` scope 증명 결과 / 실패 코드 /
결과 감사 레코드 / 구조화된 영향 요약(`notices` 가 문자열뿐이다)

### 미해결

- nullable FK 의 `required` 의미 — **입력이 non-null 인데 매핑이 없으면 실패**해야 한다
- `mp_accounts` 를 `findByPk()` 로 직접 읽는 결제·웹훅 경로 전수검사
- `commerce_channels`/`wp_channels` 소비자 게이트(프론트가 **행 개수**로 "연결됨" 판정)

---

## 이월

- 로컬 DB(5432) 0테이블 — 복원 시 오늘 마이그레이션 3개 + `w6-talleres-missing-fks.sql`
- W6-C4 DB 복합 FK — 감사①이 더 급한 것을 찾았다(FK 없는 테넌트 컬럼 19개)
- `products.image_url` UTF-8 모지바케 — 별건
- 종전 이월 유지: sudoers mode 0440 · 프론트 blue/green 없음 ·
  POS 카탈로그 P95 376ms · 소켓 한도 0 · `/me` 11쿼리 미캐시
