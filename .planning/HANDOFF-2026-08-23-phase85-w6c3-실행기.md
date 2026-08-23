# 핸드오프 — 2026-08-23 · Phase 85 W6-C3 ③④ 카탈로그 복원 실행기 ★

`HANDOFF-2026-08-22-f-phase85-w6c3-범위재조정.md` 에서 이어짐.
사용자 지시: **"handoff 읽고 phase 85에 해당된 작업만 하고, 더 없으면 phase 86을 시작하자"**

---

## ★★ 이 세션의 한 줄

**전 세션이 남긴 유일한 미결(충돌 정책)을 사용자가 정했고, 실행기를 지어 잠금을 풀었다.
그리고 처음으로 이 경로의 SQL 을 **실제 DB 에서 돌려 봤다** — 거기서만 나오는 결함 둘을 잡았다.**

---

## Phase 85 현황

| 웨이브 | 상태 |
|---|---|
| W1 캐시 봉인 · W2 소켓 · W3 pageSize · W4 규약 · W5 무중단 배포 | ✅ 완결 |
| **W6 논리 복구 (카탈로그/SKU)** | ✅ **이번 세션 완결 — 잠금 해제** |
| W4 파티셔닝 · W7 rollup · W8 p95 게이트 | ⏸ 착수 조건 미달 (근거 문서화됨) |

→ **Phase 85 는 착수 가능한 범위가 끝났다.** 다음은 Phase 86.

---

## 배포

```
api-ventago  cbce1cb  카탈로그(SKU) 복원 실행기 — 같은 매장 · 추가만    #800
superproj    5bd5e3f  + codex 검토 문서 4개
운영 DB      2026-08-23-w6c3-restore-plan-catalog-mode.sql  (5432 + 5434 양쪽 적용 ✓)
테스트       단위 321 (기존 272 → +49) · **실제 DB 통합 11 (신설)**
```

---

## ① 사용자 결정 — 충돌 정책은 **추가만**

이미 있는 상품은 판매가 참조하고 있을 수 있고, POS 검색에 서버 폴백이 없어
반쪽 복원이 판매를 막는다. 그래서 없는 것만 넣고 기존 행은 건드리지 않는다.

**예외 하나**: `sku_serials.last_serial` 은 단조 카운터라 **전진**시킨다.
기존 50 · 백업 80 인데 기존이 이기면 다음 발급 51 이 되살린 SKU 와 충돌한다.
정책 이름에 박아 뒀다 — `INSERT_ONLY_EXCEPT_MONOTONIC_COUNTER_ADVANCE`.

## ② ★ 원본 PK 를 그대로 되살린다 (CLONE 과 정반대)

CLONE 은 `id` 를 REGENERATE 했다. 여기서는 반대다:

1. `sale_items.product_id` 등 **범위 밖 참조**가 다시 이어져야 "되돌린" 것이다
2. `sku_serials.{supplier,category,subcategory}_id` 는 **FK 없는 참조** —
   id 를 바꾸면 조용히 남을 가리킨다. FK 카탈로그가 못 보는 자리라 검사도 안 걸린다
3. id 원장·2단계 UPDATE·DEFERRED 집행이 통째로 필요 없어진다

→ **id 를 못 되살리면 그 행은 막는다(BLOCKED).** 우회하면 위 근거가 무너진다.

## ③ codex 2라운드 — 6건 수용, 1건 미수용

### 1R (설계) — `w6c3-catalog-engine-{codex,resolution}.md`

| 지적 | 조치 |
|---|---|
| 자연키가 **다른 id** 에 있으면 SKIP | → **BLOCKED**. SKIP 이면 없는 id 를 가리킨 채 "성공" 반환 |
| `prices (product_id, price_type_id)` 자연키 | DB 가 강제 안 함 → **PK 판정만** |
| 계획/집행 경합 | 집행 트랜잭션 **안에서 전 판정 재수행** + advisory lock |
| `products.slug` UNIQUE 누락 | 카탈로그의 **UNIQUE 전부** 검사(부분 인덱스 포함) |

★ **내 선언이 실측으로 틀렸다**: `price_types (store_id, store_entity_id)` 를
  자연키로 뒀는데 운영 18행 **전부 NULL** 이고 4쌍이 겹친다.
  `store-restore-scopes.ts` 에 적어 둔 근거("1~5 가 code-import 가격 슬롯")도
  데이터로는 성립하지 않는다 — `code-import.service.ts:154` 가 그 컬럼으로
  정렬하지만 전부 NULL 이라 아무것도 정하지 않는다. **별건 결함(미해결)**.

### 2R (구현) — `w6c3-catalog-engine-implementation-{codex,resolution}.md`

| 지적 | 조치 |
|---|---|
| 시퀀스 보정이 동시 `nextval` 과 원자적이지 않다 | 아래 ★ |
| 복구 커밋 **뒤**의 기록 실패가 FAILED 로 적힌다 | 오류 경계 분리 · `recorded:false` |
| 백업 파일 **안**의 PK/UNIQUE 중복 미검사 | `findDuplicatesWithinBackup()` 신설 |
| fingerprint 가 판정 근거를 다 안 담는다 | UNIQUE·FK·판정규칙·엔진버전 포함 |

★★ **codex 처방이 PG 에 없었다.** "시퀀스를 ACCESS EXCLUSIVE 로 잠가라" →

```
LOCK TABLE products_id_seq IN ACCESS EXCLUSIVE MODE;
→ ERROR: cannot lock relation — This operation is not supported for sequences.
```

실측으로 대안을 찾았다:

```
BEGIN; ALTER SEQUENCE products_id_seq INCREMENT BY 1; SELECT pg_sleep(3); COMMIT;
  (동시) nextval  →  2,308ms 대기
```

내용상 no-op 인 `ALTER SEQUENCE` 가 `AccessExclusiveLock` 을 잡고 **실제로 막는다.**
올릴 필요가 있을 때만 잠그고, 집행의 **맨 끝**에 한다(창을 최소화).

### 미수용 — 감사 트리거 억제

범위 축소로 5,652행 → **약 100행**. 100행은 소음이 아니라 **증거**이고
`SET LOCAL ventago.actor_user_id` 로 이미 올바르게 귀속된다.
억제 플래그를 DB 함수에 넣으면 **영구적인 구멍**이 된다.

## ④ ★ 실제 DB 통합 테스트를 처음 만들었다 (`.itest.ts`)

`npm run test:itest` · `test/itest/jest-itest.json` · 로컬 PG(5432) 필요.
`testRegex` 가 `.spec.ts` 라 **일반 jest·CI 에서는 빠진다.**

**단위 spec 과 tsc 를 둘 다 통과한 뒤 여기서 두 결함이 나왔다:**

1. `pg_get_serial_sequence('public.ProductBranch','id')` → **relation does not exist**
   (인용 안 하면 소문자로 접힌다). 대소문자 섞인 테이블 하나가 조용히 죽었다
2. 위 시퀀스 잠금 방법 — 문서만 읽었으면 없는 API 를 썼을 것이다

## ⑤ 잠금은 엔진마다 하나씩

`RESTORE_ENGINE_STATUS`(전체 복제)는 **여전히 `blocked`**.
카탈로그만 `CATALOG_RESTORE_STATUS = 'enabled'`.
하나로 합치면 한쪽을 열려다 **고쳐진 적 없는 다른 쪽이 같이 열린다** —
`store-restore-contract.spec.ts` 가 그 시도를 막는다.

## ⑥ 엔드포인트

```
POST /store/restore/catalog/plan      { destinationStoreId, backup }  → 계획 + planId
POST /store/restore/catalog/execute   { planId }                      → 집행
```
둘 다 superadmin 전용. 계획을 만든 사람만 집행한다.

---

## ★ 남은 것 (다음 세션)

### 이 기능에 대해
- **프론트 화면이 없다.** 지금은 API 만 있다. superadmin 콘솔에 계획 미리보기
  (INSERT/SKIP/BLOCKED 건수 + BLOCKED 목록 + `recorded:false` 경고)가 필요하다
- `.itest` 는 **로컬에서만** 돈다. 손 절차로 남으면 안 돈다 — W8 부하 리그에
  얹거나 CI 에 PG 서비스를 붙이는 것이 정석
- `store_restore_plans` 만료 청소(EXPIRED + MinIO 객체) 크론이 없다

### 로컬 DB 를 복원했다 ★
`~/Dropbox/ventago_pg_backups/ventago_20260820_031701.dump` 로 복원(235 테이블).
★ 그냥 `pg_restore --role=coolsistema` 하면 **permission denied** 로 죽는다 —
  DB owner 가 `postgres` 였기 때문. `DROP DATABASE` → `CREATE DATABASE ventago
  OWNER coolsistema` 후 복원해야 한다.
복원 후 08-20~08-23 마이그레이션 8개를 순서대로 적용했다.

### 종전 이월 (그대로)
- `price_types.store_entity_id` 전부 NULL → code-import 가격 슬롯 정렬이 무의미 (신규)
- `mp_accounts` 를 `findByPk()` 로 직접 읽는 결제·웹훅 경로 전수검사
- `commerce_channels`/`wp_channels` 소비자 게이트
- sudoers mode 0440 · 프론트 blue/green 없음 · POS 카탈로그 P95 376ms ·
  소켓 한도 0 · `/me` 11쿼리 미캐시
