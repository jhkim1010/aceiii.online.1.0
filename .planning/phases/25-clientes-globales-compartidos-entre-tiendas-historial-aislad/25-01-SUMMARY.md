---
phase: 25-clientes-globales-compartidos-entre-tiendas-historial-aislad
plan: 01
subsystem: database
tags: [postgresql, sequelize, migration, owner-group, multi-tenant, pg10, partial-unique-index]

# Dependency graph
requires: []
provides:
  - stores.owner_group_id (NOT NULL, backfilled to 1 for all 4 production stores)
  - global_clients.owner_group_id (NOT NULL)
  - uq_global_clients_owner_doc_partial (UNIQUE on owner_group_id+document WHERE document NOT NULL)
  - idx_global_clients_owner_group (조회 가속)
  - idx_stores_owner_group (조회 가속)
  - owner_groups_seq sequence (START 2, Wave 2 신규매장 자동그룹 부여용)
  - Sequelize Store.ownerGroupId / GlobalClient.ownerGroupId 모델 매핑
  - 레거시 인덱스/제약 제거: idx_global_clients_name_phone (D1-01), global_clients_document_key, global_clients_document
affects:
  - 25-02 OwnerScopeGuard (store_id → owner_group_id 매핑 의존)
  - 25-03 promote/merge service (owner_group_id 단위 격리 의존)
  - 25-04 client-import (owner_group_id+document 단위 중복 검증 의존)
  - 모든 Wave 2~5 plans (스키마 기반)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "PG10 호환 partial UNIQUE: ADD CONSTRAINT ... WHERE 미지원 → CREATE UNIQUE INDEX ... WHERE 사용"
    - "Idempotent migration: ADD COLUMN IF NOT EXISTS + UPDATE backfill + SET NOT NULL + DO 블록 EXCEPTION"
    - "Sequelize 모델 explicit field 매핑: field: 'owner_group_id' (underscored:true 의존하지 않고 명시)"
    - "신규 owner group 자동 부여: CREATE SEQUENCE owner_groups_seq START 2 (D3-03)"

key-files:
  created:
    - api-ventago/migrations/20260424-phase25-step1-owner-group.sql
    - api-ventago/migrations/20260424-phase25-step2-global-owner.sql
  modified:
    - api-ventago/src/app/store/store.model.ts
    - api-ventago/src/app/shared/global-clients/global-clients.model.ts

key-decisions:
  - "PG10 partial UNIQUE 호환을 위해 ADD CONSTRAINT 대신 CREATE UNIQUE INDEX ... WHERE 사용 (PG10/PG15 양쪽 호환)"
  - "Sequelize 모델에 unique:true 컬럼 선언 제거 — 부분 UNIQUE는 인덱스 레벨에서만 관리 (D1-01 정합성)"
  - "owner_groups_seq START 2 — 기존 4개 매장이 group=1 이므로 신규는 2부터 (D3-02/D3-03)"
  - "global_clients_document_key / global_clients_document 등 다중 누적 UNIQUE 제약을 DO 블록 LOOP 로 일괄 제거 (Sequelize sync 누적 정리)"

patterns-established:
  - "Phase 25 owner_group_id 멀티테넌트 그룹 경계 — 같은 그룹의 매장끼리 global_clients 공유, 다른 그룹 간 완전 격리"
  - "PG10 호환 마이그레이션 작성 규칙: BEGIN/COMMIT 래핑, ON_ERROR_STOP=1, IF NOT EXISTS, DO 블록 EXCEPTION"

requirements-completed:
  - REQ-25-01
  - REQ-25-02
  - REQ-25-22
  - D1-01
  - D1-05
  - D3-01
  - D3-02
  - D3-03

# Metrics
duration: 30min
completed: 2026-04-25
---

# Phase 25 Plan 01: Wave 1 Data-Layer Foundation (owner_group_id schema) Summary

**`stores.owner_group_id` 와 `global_clients.owner_group_id` 컬럼 추가 + ownerGroup 단위 partial UNIQUE 인덱스 (PG10 호환) — 운영 4개 매장 group=1 backfill 완료, 레거시 fullname+phone 인덱스 제거**

## Performance

- **Duration:** ~30분 (Tasks 1+2 사전 작업 포함, Task 3 운영 적용 ~10분)
- **Started:** 2026-04-25T12:49:35Z (Phase 25 execution start)
- **Completed:** 2026-04-25T13:05:00Z
- **Tasks:** 3/3
- **Files modified:** 4 (2 created SQL + 2 modified model)

## Accomplishments

- **Schema migration 적용**: stores + global_clients 양쪽에 `owner_group_id INTEGER NOT NULL` 컬럼 추가, 운영 4개 매장(CART, coolsistema, genius, ACE) 모두 group=1 로 backfill
- **Partial UNIQUE 격리**: `uq_global_clients_owner_doc_partial UNIQUE (owner_group_id, document) WHERE document IS NOT NULL` — 같은 그룹 내에서만 document UNIQUE, 다른 그룹은 같은 DNI 가능 (D1-05)
- **레거시 인덱스 정리**: `idx_global_clients_name_phone` (fullname+phone partial unique) 제거 → D1-01 정책 (document 없는 고객은 global pool 진입 불가)
- **Sequelize 모델 동기화**: Store.ownerGroupId / GlobalClient.ownerGroupId 추가, document 컬럼의 inline `unique: true` 제거 (인덱스 레벨로 이관)
- **운영 컨테이너 무중단 재시작**: api_ventago restart 후 `Nest application successfully started` 확인, Sequelize sync 동작 없음 (sync: false 정상)

## Task Commits

1. **Task 1: SQL migration files (step1 + step2)** — `3408f67` (feat)
2. **Task 2: Sequelize models update (Store + GlobalClient)** — `1ae4740` (feat)
3. **Task 3: Production migration apply + container restart** — `0032788` (chore, empty commit with verification log)

## Files Created/Modified

- `api-ventago/migrations/20260424-phase25-step1-owner-group.sql` — stores.owner_group_id 추가 + 4 row backfill + NOT NULL + owner_groups_seq + idx_stores_owner_group
- `api-ventago/migrations/20260424-phase25-step2-global-owner.sql` — global_clients.owner_group_id + DO 블록 LOOP 로 누적 UNIQUE 정리 + uq_global_clients_owner_doc_partial 생성 + idx_global_clients_name_phone 제거
- `api-ventago/src/app/store/store.model.ts` — ownerGroupId @Column 추가 (한국어 주석)
- `api-ventago/src/app/shared/global-clients/global-clients.model.ts` — ownerGroupId 추가 + document inline unique 제거

## Production Migration Timeline

| 시각 (UTC) | 작업 | 결과 |
|----|----|----|
| 13:01 | Pre-migration 사전 검증 (stores, global_clients, 인덱스 목록) | stores 4 rows, global_clients 0 rows, 레거시 인덱스 3개 확인 |
| 13:02 | step1 적용 (`ssh jhkim-server psql ... < step1.sql`) | BEGIN / ALTER / UPDATE 4 / ALTER / CREATE SEQUENCE / CREATE INDEX / COMMIT |
| 13:02 | step2 적용 | BEGIN / ALTER / UPDATE 0 / ALTER / DO LOOP / CREATE UNIQUE INDEX / DROP INDEX / CREATE INDEX / COMMIT |
| 13:03 | Post-migration 검증 (`\d stores`, `\d global_clients`, sequence) | 모든 확인 통과 |
| 13:03 | `docker restart api_ventago` | restart OK |
| 13:03 | Boot 로그 확인 (Nest app start, 에러/sync 검색) | `successfully started`, 에러 0건, ALTER TABLE 로그 0건 |

## Row Counts Pre/Post Migration

| 테이블 | 적용 전 | 적용 후 | 변경 |
|----|----|----|----|
| stores | 4 rows | 4 rows | owner_group_id 컬럼 추가, 모두 1 로 backfill |
| global_clients | 0 rows | 0 rows | 컬럼만 추가, 데이터 변경 없음 |

## Index State Before/After (global_clients)

**Before (4 indexes):**
- `global_clients_pkey`
- `global_clients_document` (단순 인덱스, document)
- `global_clients_document_key` (UNIQUE constraint, document 전역)
- `idx_global_clients_name_phone` (partial UNIQUE, fullname+phone WHERE document IS NULL)

**After (3 indexes):**
- `global_clients_pkey` (유지)
- `uq_global_clients_owner_doc_partial` (UNIQUE, owner_group_id+document WHERE document NOT NULL) — 신규
- `idx_global_clients_owner_group` (단순 인덱스, owner_group_id) — 신규

## Decisions Made

- **PG10 호환 partial UNIQUE**: PG10 은 `ADD CONSTRAINT ... WHERE` 미지원이므로 `CREATE UNIQUE INDEX ... WHERE` 사용 (RESEARCH.md Pitfall 1 기반). PG15 dev 와 PG10 prod 양쪽 동일 SQL 적용 가능.
- **Sequelize 누적 UNIQUE 자동 청소**: `Sequelize sync` 누적으로 `global_clients_document_key`, `_key1` ~ `_key7` 까지 다중 존재 가능성 발견 → DO 블록 LOOP 로 `pg_constraint` 조회 후 일괄 DROP (운영에서는 `_key` 1개만 발견됨, 스크립트는 안전).
- **owner_groups_seq START 2**: 신규 매장 등록 시 `nextval('owner_groups_seq')` 호출하면 group 2 부터 시작 — 기존 4개 매장이 모두 group 1 이므로 충돌 방지 (Wave 2 StoreService 에서 활용 예정).
- **모델의 explicit `field` 매핑**: Sequelize `underscored: true` 가 자동 변환을 하지만, 미래 변경 안전을 위해 `field: 'owner_group_id'` 명시 (PATTERNS.md 권장).

## Deviations from Plan

None — plan 그대로 실행됨.

## Issues Encountered

- 운영 DB 의 `global_clients` 에 사전 인덱스가 PLAN 추정(2개)보다 1개 많은 3개(`global_clients_document_key`, `global_clients_document`, `idx_global_clients_name_phone`) 존재 → DO 블록 LOOP 패턴 덕에 모두 안전하게 정리됨.
- 그 외 이슈 없음.

## User Setup Required

None — 모든 작업이 SSH 통한 자동 적용으로 완료됨.

## Next Phase Readiness

- **Ready for 25-02 (Wave 2 OwnerScopeGuard)**: store_id → owner_group_id 매핑 인프라 완성. `idx_stores_owner_group` 인덱스로 조회 성능 확보.
- **Ready for 25-04 (Client Import)**: `uq_global_clients_owner_doc_partial` 가 (owner_group_id, document) 단위 중복 검증을 DB 레벨에서 강제 — import 로직은 이 인덱스 violation 을 catch 하면 됨.
- **신규 매장 자동 그룹 생성 (D3-03)**: Wave 2 StoreService 에서 `nextval('owner_groups_seq')` 호출 시 group 2 부터 자동 부여 가능.
- **Blockers**: 없음.

## Self-Check: PASSED

검증 항목:
- [x] api-ventago/migrations/20260424-phase25-step1-owner-group.sql 존재 (FOUND)
- [x] api-ventago/migrations/20260424-phase25-step2-global-owner.sql 존재 (FOUND)
- [x] api-ventago/src/app/store/store.model.ts 수정됨 (commit 1ae4740)
- [x] api-ventago/src/app/shared/global-clients/global-clients.model.ts 수정됨 (commit 1ae4740)
- [x] commit 3408f67 존재 (Task 1 SQL files)
- [x] commit 1ae4740 존재 (Task 2 model update)
- [x] commit 0032788 존재 (Task 3 production apply)
- [x] 운영 DB 검증: stores.owner_group_id NOT NULL, 4 rows = 1
- [x] 운영 DB 검증: global_clients.owner_group_id NOT NULL
- [x] 운영 DB 검증: uq_global_clients_owner_doc_partial 인덱스 존재
- [x] 운영 DB 검증: idx_global_clients_name_phone 제거됨
- [x] api_ventago 컨테이너 재시작 + boot 정상 (Nest application successfully started)

---
*Phase: 25-clientes-globales-compartidos-entre-tiendas-historial-aislad*
*Completed: 2026-04-25*
