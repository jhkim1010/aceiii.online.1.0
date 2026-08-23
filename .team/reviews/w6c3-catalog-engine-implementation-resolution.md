# 수용본 — W6-C3 ③④ 구현 검토 2차 (2026-08-23)

원문: `w6c3-catalog-engine-implementation-codex.md` (HIGH 2 · MEDIUM 2)

**4건 전부 수용했다.** 그중 하나는 codex 가 준 처방이 **PG 에 존재하지 않아** 실측으로
다른 방법을 찾아야 했다.

## [HIGH] 시퀀스 보정이 동시 `nextval()` 과 원자적이지 않다 — 수용, 처방은 교체

codex 처방: *"복원 트랜잭션에서 각 대상 시퀀스를 `ACCESS EXCLUSIVE` 로 잠가라."*

**실측(로컬 PG18):**

```
LOCK TABLE products_id_seq IN ACCESS EXCLUSIVE MODE;
→ ERROR: cannot lock relation "products_id_seq"
  DETAIL: This operation is not supported for sequences.
```

**PG 는 시퀀스에 `LOCK TABLE` 을 허용하지 않는다.** 그래서 대안을 재 봤다:

```
BEGIN; ALTER SEQUENCE products_id_seq INCREMENT BY 1; SELECT pg_sleep(3); COMMIT;
  (동시) SELECT nextval('products_id_seq');  →  2,308ms 대기
```

내용상 no-op 인 `ALTER SEQUENCE` 가 `AccessExclusiveLock` 을 잡고 **실제로 `nextval`
을 막는다.** 이것을 쓴다.

적용:
1. 잠그기 **전에** `last_value`/`MAX(id)` 를 읽어 **올릴 필요가 있는지만** 본다.
   올릴 필요가 없으면 **잠그지 않는다** — 되살리는 id 는 원래 그 시퀀스가 발급했던
   번호라 보통 이미 아래다. 이 읽기가 경합에 져도 안전하다(남이 더 올렸다면 여전히 큼).
2. 올려야 할 때만 no-op `ALTER SEQUENCE` 로 잠그고, **잠근 뒤 다시 읽어** `setval`.
3. 집행의 **맨 끝**에 한다 — 커밋 직전이라 POS 상품 생성이 막히는 창이 가장 짧고,
   `lock_timeout=5s` 가 걸려 있어 못 잡으면 기다리는 대신 실패한다.

검증: `.itest` 2건 — 시퀀스 위로 올리기(다음 `nextval` 이 되살린 id 를 넘는지까지) ·
뒤로 안 당기기.

## [HIGH] 복구 커밋 뒤의 기록 실패가 `FAILED` 로 적힌다 — 수용

`catch` 를 복구 트랜잭션에만 걸고, 기록은 **그 밖의 별도 오류 경계**로 뺐다.
`SUCCEEDED` UPDATE + 요약 감사를 **한 짧은 트랜잭션**으로 묶었다.

기록에 실패하면 계획을 `EXECUTING` 에 **남긴다**(codex 가 준 두 선택지 중 이쪽).
`FAILED` 로 바꾸면 사람이 "안 들어갔구나" 로 읽는다. `EXECUTING` 은 재집행도 막고
(조건부 UPDATE 가 `PLANNED` 만 가져간다) 사람이 봐야 한다는 신호도 된다.
응답에 **`recorded: false`** 를 실어 화면이 말하게 하고, 로그에 요약 전문을 남긴다.
새 상태(`COMMITTED_PENDING_RECORD`)는 만들지 않았다 — DB CHECK 와 상태 기계를 함께
바꿔야 하는데, `EXECUTING` 이 이미 같은 뜻(진행 중, 사람 확인 필요)을 낸다.

## [MEDIUM] 백업 파일 **안**의 PK/UNIQUE 중복 — 수용

`findDuplicatesWithinBackup()` 신설. 목적지 조회 **전에** 돌고, 겹치면
`DUPLICATE_IN_BACKUP` 으로 거부한다. 부분 인덱스·NULL-distinct 는 `uniqueKeyApplies()`
를 그대로 재사용했다 — 두 곳이 다른 규칙을 쓰면 한쪽만 잡는 구멍이 생긴다.

검증: 단위 5건(겹침 없음 · 같은 PK · 다른 PK 같은 SKU · NULL · 부분 인덱스) + `.itest` 1건.

## [MEDIUM] 스키마 fingerprint 가 판정 근거를 다 담지 않는다 — 수용

컬럼 `type`/`notNull` 만 해시하던 것을 다음으로 넓혔다:
`isPrimaryKey`/`serverGenerated`/`isGenerated` · 파싱된 UNIQUE 정의(부분 조건 포함) ·
삽입 순서 · `CATALOG_IN_PLACE_OUTBOUND` 규칙 · `CATALOG_TABLE_RULES` ·
그리고 **`CATALOG_ENGINE_VERSION`** — 스키마가 그대로여도 판정 규칙을 바꾸면
그 전 계획은 사람이 검토한 것과 다른 일을 한다.

## codex 가 확인해 준 것 (재론 불필요)

- **요청 입력을 통한 SQL 주입 경로 없음.** 직접 삽입되는 식별자는 서버 카탈로그
  (`pg_get_serial_sequence` 결과) 또는 서버 상수뿐이고 `q()` 검증도 거친다.
- NULL-distinct · 부분 인덱스 · 자기 점유 제외는 올바르다.
- 계획과 집행이 실제로 같은 `runCatalogRestore()` 를 탄다 (`dryRun` 만 다름).
- BLOCKED 후 throw 로 선행 INSERT 도 롤백된다.
