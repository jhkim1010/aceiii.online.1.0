---
phase: 25-clientes-globales-compartidos-entre-tiendas-historial-aislad
plan: 02
subsystem: database
tags: [postgresql, sequelize, migration, dual-fk, sales, store-clients, pg10]

# Dependency graph
requires:
  - 25-01 (stores.owner_group_id, global_clients.owner_group_id)
provides:
  - sales.store_client_id (nullable INTEGER FK → store_clients.id, ON DELETE SET NULL)
  - fk_sales_store_client constraint
  - idx_sales_store_client_id (partial, WHERE NOT NULL)
  - idx_sales_store_id_store_client_id (partial composite)
  - Sale.storeClientId Sequelize property + @BelongsTo(StoreClient) association
affects:
  - 25-03 sales remap (UPDATE sales SET store_client_id 의존)
  - Wave 3 sales.service (storeClientId → clientId 폴백 읽기 우선순위)
  - 모든 신규 sales 쓰기 경로 (양쪽 FK 모두 채워야 함)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Dual-FK 전략 (D2-01): 신규 sales 는 store_client_id 사용, 레거시 client_id 유지"
    - "PG10 호환 FK 추가: ALTER TABLE ... ADD CONSTRAINT IF NOT EXISTS 미지원 → DO 블록 + EXCEPTION duplicate_object"
    - "Partial INDEX WHERE NOT NULL: 인덱스 크기 최소화 (8/8 sales NULL 이므로 빈 인덱스로 시작)"
    - "운영 GRANT 누락 방지: pg_roles 존재 시에만 EXECUTE GRANT (dev 로컬엔 coolsistema role 없음)"

key-files:
  created:
    - api-ventago/migrations/20260424-phase25-step3-sales-store-client.sql (Plan 25-01 사전 작업으로 생성됨)
  modified:
    - api-ventago/src/app/sales/sales.model.ts (Plan 25-01 사전 작업으로 수정됨)

key-decisions:
  - "sales 모델에 storeClientId + @BelongsTo(StoreClient) 추가, clientId 는 그대로 유지 (D2-01 dual-FK)"
  - "FK ON DELETE SET NULL: store_client 삭제되어도 sales 행은 보존, FK 만 NULL 처리 (역사적 매출 데이터 보호)"
  - "Partial UNIQUE 인덱스 패턴 재사용: store_client_id IS NOT NULL 만 인덱싱"
  - "운영 GRANT 자동 부여: DO 블록 IF EXISTS check 로 dev/prod 동일 SQL 사용 가능"

patterns-established:
  - "Phase 25 dual-FK 마이그레이션: 신규 컬럼 nullable + 기존 컬럼 그대로 유지 → 점진 cut-over"
  - "운영 GRANT 자동화 패턴 (Wave 6/7/9 교훈 반영): DO 블록 + IF EXISTS pg_roles"

requirements-completed:
  - REQ-25-07
  - D2-01

# Metrics
duration: 5min (운영 적용 only — SQL 파일 + 모델은 Plan 25-01 사전 작업으로 완료)
completed: 2026-04-26
---

# Phase 25 Plan 02: Wave 1 sales.store_client_id Dual-FK Summary

**`sales.store_client_id` nullable FK 컬럼 + Sale Sequelize 모델 dual-FK 운영 적용 완료. 8개 레거시 sales 행 변경 없음 (Plan 03 에서 backfill 예정).**

## Performance

- **Duration:** ~5분 (운영 적용만 수행 — SQL/모델은 Plan 25-01 사전 작업으로 이미 작성됨)
- **Started:** 2026-04-26T01:00 KST (사용자 SSH 세션)
- **Completed:** 2026-04-26T01:05 KST
- **Tasks:** 1/3 (Task 3 운영 적용만 수행, Task 1+2 는 사전 완료)

## Accomplishments

- **운영 step3 적용**: `ALTER TABLE sales ADD COLUMN store_client_id INTEGER NULL` + FK + 인덱스 2개 + COMMENT + GRANT
- **컨테이너 영향 없음**: `sync: false` 설정 덕분에 새 nullable 컬럼은 컨테이너 재시작 불필요 (기존 INSERT/SELECT 영향 없음)
- **레거시 데이터 보존**: 8 sales 행 모두 `store_client_id = NULL` 유지 (Plan 03 에서 store_clients 생성 후 backfill 예정)

## Files Created/Modified (Plan 25-01 사전 작업으로 완료)

- `api-ventago/migrations/20260424-phase25-step3-sales-store-client.sql` — step3 마이그레이션
- `api-ventago/src/app/sales/sales.model.ts` — storeClientId 필드 + @BelongsTo(StoreClient) 추가

## Production Migration Timeline

| 시각 (KST) | 작업 | 결과 |
|----|----|----|
| 01:00 | Pre-migration: sales 8 rows / store_client_id 컬럼 0건 확인 | 적용 안전 |
| 01:02 | step3 적용 (ssh jhkim-server psql ... < step3.sql) | BEGIN / ALTER / DO / CREATE INDEX x2 / COMMENT / DO / COMMIT |
| 01:03 | Post-migration: \d sales | store_client_id 컬럼 + fk_sales_store_client + idx 2개 모두 확인 |
| 01:03 | sales 행 수 검증 | COUNT=8, COUNT(store_client_id)=0 (정상) |
| 01:04 | docker logs api_ventago | "successfully started" 확인 (sync 로그 0건) |

## Row Counts Pre/Post Migration

| 테이블 | 적용 전 | 적용 후 | 변경 |
|----|----|----|----|
| sales | 8 rows | 8 rows | store_client_id 컬럼 추가, 모두 NULL |

## Index State After Plan 25-02 (sales)

- `sales_pkey` (유지)
- `idx_sales_store_client_id` (UNIQUE 아님, partial, WHERE store_client_id NOT NULL) — 신규
- `idx_sales_store_id_store_client_id` (partial composite) — 신규

## Decisions Made

- **운영 적용만 수행**: SQL 파일과 모델 변경은 이미 Plan 25-01 시점에 사전 작업으로 완료된 상태였음 → 운영 DB 적용만 별도로 수행
- **컨테이너 재시작 생략**: 새 nullable 컬럼이고 sync:false 설정이라 재시작 불필요. 기존 컨테이너의 Sequelize 모델은 storeClientId 를 모르는 상태이지만 INSERT/SELECT 에 영향 없음 (코드 신규 배포 시점에서 인식)

## Deviations from Plan

- 25-02-PLAN.md 의 Task 1+2 (SQL/모델 작성)는 Plan 25-01 실행 시 사전에 완료되어 있었음 → Task 3 (운영 적용)만 수행
- 컨테이너 강제 재시작은 생략 (안전성 판단)

## Issues Encountered

- Step D의 `cd /root/api-ventago: Permission denied` 에러: docker compose 명령은 실행 안 됨. 단, sync 로그가 없으므로 컨테이너 상태에 영향 없음 (기존 컨테이너 정상 동작 중)
- 그 외 이슈 없음

## User Setup Required

None — 모든 작업 SSH 통한 자동 적용으로 완료

## Next Phase Readiness

- **Ready for 25-03 (Wave 1 Step 5+6 데이터 마이그레이션)**: sales.store_client_id 컬럼이 존재하므로 backfill UPDATE 가능
- **Blockers**: 없음

## Self-Check: PASSED

검증 항목:
- [x] api-ventago/migrations/20260424-phase25-step3-sales-store-client.sql 존재
- [x] api-ventago/src/app/sales/sales.model.ts 의 storeClientId 필드 + @BelongsTo(StoreClient)
- [x] 운영 DB 검증: sales.store_client_id 컬럼 존재, integer, nullable
- [x] 운영 DB 검증: fk_sales_store_client FK 존재 (ON DELETE SET NULL)
- [x] 운영 DB 검증: idx_sales_store_client_id + idx_sales_store_id_store_client_id 인덱스 존재
- [x] 운영 DB 검증: sales 행 수 변경 없음 (8 → 8)
- [x] api_ventago 컨테이너 정상 동작 (Nest app successfully started)

---
*Phase: 25-clientes-globales-compartidos-entre-tiendas-historial-aislad*
*Completed: 2026-04-26*
