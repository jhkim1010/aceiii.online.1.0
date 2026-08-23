# codex 검토 — W6-C3 ③ 카탈로그 복원 실행기 설계 (2026-08-23)

설계안: `CATALOG_IN_PLACE` 15개 테이블 · 같은 매장 · 충돌 정책 "추가만"(사용자 결정).
판정: **조건부 승인.** 가장 먼저 고칠 것 두 가지 —
"자연키가 다른 id 에 있으면 SKIP" → BLOCKED, 그리고 `prices` 의 가짜 자연키 제거.

## [HIGH] 자연키가 다른 id 에 있으면 SKIP 하는 분기

원본 PK 를 되살리는 **핵심 이유가 범위 밖 참조를 다시 잇는 것**인데, 자연키가 다른
id 에 있다고 원본 id 복원을 생략하면 `sale_items.product_id` 는 계속 없는 id 를
가리킨다. 범위 내 자식도 원본 id 를 참조하므로 FK 오류나 연쇄 SKIP 이 난다.
→ 판정 4갈래를 `INSERT` / `SKIP_ALREADY_PRESENT` / `BLOCKED_PK` /
  `BLOCKED_NATURAL_KEY` 로. "다른 id 로 이미 존재" 를 인정하려면 범위 내외 참조를
  전부 그 id 로 재매핑해야 하고, 그건 이번 범위 밖이다.

## [HIGH] `prices` 의 `(product_id, price_type_id)` 를 자연키로 선언하면 데이터 유실

DB 가 그 조합의 유일성을 보장하지 않는다(`prices_pkey` 뿐). 유일하지 않은 조합으로
"같은 행" 을 판정하면 여러 백업 가격 중 하나를 근거 없이 버린다.
→ 이번 복구에서 `prices` 는 **PK 기준으로만** 판정한다. UNIQUE 를 먼저 추가해서도
  안 된다(중복이 허용되는 현재 상태에서 제약을 걸면 기존 데이터가 걸린다).

## [HIGH] 계획과 집행 사이의 경합 — 계획 결과가 낡는다

계획 이후 일반 상품 생성이 같은 PK·SKU·slug·채번 자리를 차지할 수 있다.
`store_restore_plans` 의 조건부 UPDATE 는 **같은 계획의 이중 클릭만** 막는다.
→ execute 트랜잭션 **안에서 모든 충돌·소유권 검사를 다시** 한다. 매장 단위
  advisory transaction lock 을 먼저 잡는다. 일반 쓰기 경로가 같은 잠금을 공유하지
  않으므로, DB UNIQUE/FK 위반은 안전한 CONFLICT 로 변환하고 "계획은 예보지 보장이
  아니다" 를 화면에 표시한다.

## [MEDIUM] `products.slug` UNIQUE 충돌 판정 누락

`products_store_slug_uniq (store_id, slug) WHERE slug IS NOT NULL` 이 따로 있다.
SKU 와 PK 가 비어도 slug 로 INSERT 가 실패한다.
→ matchKey 하나가 아니라 **범위 내 모든 UNIQUE 인덱스**를 충돌 검사 대상으로.

## [MEDIUM] 감사 트리거 억제 방법이 안전하게 정의돼 있지 않다

`session_replication_role` / `DISABLE TRIGGER` 는 `tenant_chk_*` 와 family guard 까지
끄므로 쓸 수 없다. → `audit_row_change()` 에 트랜잭션 로컬 플래그 분기를 새
마이그레이션으로 추가하고, 복구 자체는 요약 감사 1건으로 남기는 방식을 제안.

## [MEDIUM] 시퀀스 보정은 `setval(max(id))` 로 부족

현재 `last_value` 가 더 크면 그 호출이 **뒤로 당긴다.** 시퀀스는 롤백되지 않는다.
→ `pg_get_serial_sequence()` 로 실제 시퀀스를 찾고 `GREATEST(last_value, max(id))`.
  `GENERATED ALWAYS` identity 면 `OVERRIDING SYSTEM VALUE` 필요 여부도 확인.

## [MEDIUM] `sku_serials` GREATEST 가 백업 값만 보면 부족

`GREATEST(현재 last_serial, 백업 last_serial, 그 scope 의 products.serial MAX)`.
같은 scope 행을 `FOR UPDATE` 로 잠가 신규 발급과 경합하지 않게.

## [MEDIUM] 계획 상태 전이와 "단일 트랜잭션" 의 경계

`PLANNED → EXECUTING` 을 카탈로그 INSERT 와 같은 트랜잭션에서 하면 실패 시 선점도
롤백돼 재집행이 가능해진다. → ① 짧은 트랜잭션으로 선점 ② 별도 단일 트랜잭션으로
복구 ③ 짧은 트랜잭션으로 결과 기록. `EXECUTING` 에 남은 건 운영자 확인 기반 복구,
자동 재실행 금지.

## 질문별 결론

1. 원본 PK 복원은 옳다. PK 점유·자연키 점유 **둘 다** 우회 없이 BLOCKED 가 맞다.
2. `price_types(store_id, store_entity_id)` 는 도메인 불변식 확인 후 DB UNIQUE 로
   승격하는 편이 낫다(현재 nullable). `prices` 는 지금 matchKey 로 쓰면 안 된다.
3. `sku_serials` GREATEST 는 정당한 안전 예외지만 문구상 "기존을 건드리지 않는다" 와
   충돌하므로 정책 이름에 명시하고(`INSERT_ONLY_EXCEPT_MONOTONIC_COUNTER_ADVANCE`)
   계획 화면에 before/after 를 따로 보여라.
4. family guard 는 부모 우선이면 정상. `tenant_chk_*` 는 후검사의 대체가 아니라
   이중 방어이므로 유지. 단일 트랜잭션에 `lock_timeout`/`statement_timeout`.
