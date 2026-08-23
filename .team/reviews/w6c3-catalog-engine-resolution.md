# 수용본 — W6-C3 ③ 카탈로그 복원 실행기 (2026-08-23)

원문: `w6c3-catalog-engine-codex.md`

## 실측으로 확인한 것 (codex 가 맞았다)

운영(5434) 조회:

```
prices_dup (product_id, price_type_id)      = 0 쌍   ← 오늘은 안 겹친다
price_types_dup (store_id, store_entity_id) = 4 쌍   ← 겹친다
price_types_null store_entity_id            = 18 / 18 (전부 NULL)
products_null_sku  = 0      products_null_slug = 367 / 367 (전부 NULL)
id 컬럼 14개 전부 plain serial (IDENTITY 아님)
```

★ **내 설계의 `price_types` matchKey `(store_id, store_entity_id)` 는 틀렸다.**
  운영 18행 전부 NULL 이고 4쌍이 겹친다. 그리고 내가 `store-restore-scopes.ts` 에
  적어 둔 근거("`store_entity_id` 1~5 가 code-import 의 가격 슬롯에 매핑된다")도
  **데이터로는 성립하지 않는다** — `code-import.service.ts:154-158` 이 실제로
  `storeEntityId ASC` 로 5개를 고르지만 값이 전부 NULL 이라 정렬이 아무것도 정하지
  않는다. 그 자체가 별건 결함이고, 여기서는 **그 컬럼을 판정 근거로 쓰지 않는다.**

★ `prices` 는 오늘 안 겹치지만 **DB 가 막지 않는다.** "오늘 데이터로는 안 터진다" 를
  근거로 삼지 않는다 — 이 저장소가 `expense_categories` 부분 인덱스에서 이미
  같은 판단을 내렸다(엔진은 오늘 데이터가 아니라 스키마가 허용하는 것에 맞춘다).

## 수용

| codex | 조치 |
|---|---|
| [HIGH] 자연키 다른 id → SKIP | **BLOCKED_UNIQUE** 로 변경. 우회 없음 |
| [HIGH] `prices` 가짜 자연키 | 강제되는 UNIQUE 만 충돌 판정에 쓴다. `prices`·`price_types` 는 **강제 UNIQUE 0개** → PK 판정만 |
| [HIGH] 계획/집행 경합 | 집행 트랜잭션 안에서 **전 판정 재수행** + `pg_advisory_xact_lock(store_id)` + UNIQUE/FK 위반을 CONFLICT 로 변환 |
| [MED] slug UNIQUE 누락 | matchKey 하나가 아니라 **카탈로그의 UNIQUE 전부**를 검사. 부분 인덱스(`WHERE slug IS NOT NULL`)와 NULL-distinct 를 함께 다룬다 |
| [MED] setval 뒤로 당김 | `pg_get_serial_sequence` + `GREATEST(last_value, max(id))`. IDENTITY 아님을 확인했으므로 `OVERRIDING SYSTEM VALUE` 불필요 |
| [MED] sku_serials GREATEST 부족 | `GREATEST(현재, 백업, 그 scope products.serial MAX)` + `FOR UPDATE` |
| [MED] 상태 전이 경계 | 트랜잭션 3개로 분리 — 선점 / 복구 / 결과기록 |
| [MED] 정책 이름 | `INSERT_ONLY_EXCEPT_MONOTONIC_COUNTER_ADVANCE` |

## 수용하지 않은 것 하나 — 감사 트리거 억제

codex 는 `audit_row_change()` 에 트랜잭션 로컬 플래그 분기를 넣자고 했다. **하지 않는다.**

- 범위 축소로 규모가 사라졌다. 전체 복제는 가짜 감사 5,652행이지만 카탈로그만이면
  **약 100행**이다. 100행은 소음이 아니라 **증거**다.
- 감사 행은 이미 올바르게 귀속된다 — `audit_row_change()` 가
  `current_setting('ventago.actor_user_id')` 를 읽고, 집행 트랜잭션이 `SET LOCAL` 로
  그 값을 건다. 즉 "누가 무엇을 되살렸는가" 가 행 단위로 남는다.
- 그리고 억제 플래그는 **영구적인 구멍**이 된다. 이 저장소는 이미
  "판정의 근거는 저장의 근거와 같아야" 로 값을 치렀다 — 감사를 끄는 스위치가
  DB 함수 안에 생기면 다음 사람은 그것을 다른 경로에서 켠다.

대신 **요약 감사 1건**을 따로 남긴다(계획 id · 백업 해시 · actor · INSERT/SKIP/ADVANCE 건수).

## 부분 수용 하나 — 일반 쓰기 경로의 잠금 공유

codex 는 일반 카탈로그 쓰기 경로도 같은 advisory lock 을 쓰게 하자고 했다.
**이번에는 하지 않는다** — 그러면 상품 생성 경로 전부를 건드려야 하고, 그 자체가
판매 경로에 잠금을 새로 도입하는 변경이다. 대신 codex 가 준 대안을 그대로 쓴다:
집행 안에서 재판정 + DB 위반을 CONFLICT 로 변환 + **"계획은 예보지 보장이 아니다"**
를 응답에 담는다.
