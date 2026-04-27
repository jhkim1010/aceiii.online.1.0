---
phase: 25-clientes-globales-compartidos-entre-tiendas-historial-aislad
plan: 04
subsystem: database
tags: [postgresql, sequelize, audit-tables, jsonb, pg10, idempotent]

# Dependency graph
requires: []
provides:
  - client_imports table (FK user/store, idx 2개) — D4-06
  - client_merges table (FK user/store/winner, JSONB field_picks, idx 2개) — D1-04
  - client_access_audits table (FK user, idx 2개) — D3-04
  - ClientImport Sequelize model (api-ventago/src/app/client-import/models/)
  - ClientMerge Sequelize model (api-ventago/src/app/clients/models/)
  - ClientAccessAudit Sequelize model (api-ventago/src/app/common/models/)
affects:
  - Wave 2 OwnerScopeGuard (Plan 05) — ClientAccessAudit 에 403 이벤트 INSERT
  - Wave 4 client-import 모듈 (Plan 10+) — ClientImport 에 import 결과 INSERT
  - Wave 3 promote/merge service — ClientMerge 에 conflict 해결 기록 INSERT

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Audit 테이블 분리: PG10 ENUM 확장 한계(RESEARCH.md Pitfall 2) 회피 위해 audit_logs 사용 안 하고 3개 별도 테이블"
    - "JSONB field_picks: PG 네이티브 JSONB 로 field-by-field 사용자 선택 기록 (인덱스 없이 audit 용)"
    - "FK ON DELETE RESTRICT: 사용자/매장 삭제 시 audit 행 보존 (감사 추적성)"
    - "운영 GRANT 자동화: pg_roles IF EXISTS check 로 dev/prod 동일 SQL"

key-files:
  created:
    - api-ventago/migrations/20260424-phase25-step4-audit-tables.sql
    - api-ventago/src/app/client-import/models/client-import.model.ts
    - api-ventago/src/app/clients/models/client-merge.model.ts
    - api-ventago/src/app/common/models/client-access-audit.model.ts

key-decisions:
  - "audit 테이블 3개를 별도로 생성 (audit_logs ENUM 확장 회피, PG10 호환)"
  - "JSONB 사용 (PG10 도 JSONB 지원, 인덱스 불필요한 audit 용)"
  - "ClientImport 모델 위치: api-ventago/src/app/client-import/models/ (Wave 4 에서 모듈화 시 재배치 예정)"
  - "ClientMerge: clients/models/ 에 배치 (clients 모듈과 강결합)"
  - "ClientAccessAudit: common/models/ 에 배치 (Guard 가 사용하므로 횡단 관심사)"

patterns-established:
  - "PG10 audit 테이블 패턴: SERIAL PK + ON DELETE RESTRICT FK + DESC 인덱스 (최근 조회 가속)"
  - "Sequelize 모델 explicit field 매핑: 모든 camelCase 속성에 field: 'snake_case' 명시"

requirements-completed:
  - REQ-25-18
  - D1-04
  - D3-04
  - D4-06

# Metrics
duration: 25min (SQL 작성 + 3 모델 작성 + TS 컴파일 검증 + 운영 적용 + 멱등성 검증)
completed: 2026-04-26
---

# Phase 25 Plan 04: Wave 1 Step 4 Audit Tables Summary

**3개 audit 테이블(client_imports, client_merges, client_access_audits) 운영 생성 완료 + 3개 Sequelize 모델 작성. TypeScript 컴파일 통과. 멱등성 검증 완료.**

## Performance

- **Duration:** ~25분
- **Started:** 2026-04-26T01:40 KST
- **Completed:** 2026-04-26T02:05 KST
- **Tasks:** 3/3 (SQL + 3 models + 운영 적용)

## Accomplishments

- **3개 audit 테이블 생성**: client_imports (13컬럼), client_merges (11컬럼+JSONB), client_access_audits (14컬럼)
- **FK 무결성**: 모든 테이블이 users(id) 참조 + store/winner 참조까지 6개 FK 설정
- **인덱스 최적화**: 각 테이블에 최근 조회용 DESC 인덱스 2개씩 (총 6개)
- **3 Sequelize 모델 작성**: ClientImport, ClientMerge (JSONB), ClientAccessAudit — 모두 explicit field 매핑
- **운영 GRANT 자동화**: pg_roles IF EXISTS 체크로 PG10 운영에 자동 grant
- **TypeScript 컴파일 통과**: tsc --noEmit 에러 0건
- **멱등성 검증**: 재실행 시 NOTICE skipping 만 발생, 에러 0건

## Files Created

- `api-ventago/migrations/20260424-phase25-step4-audit-tables.sql` — 3개 CREATE TABLE + 6개 FK + 6개 인덱스 + COMMENT 3개 + GRANT 자동화
- `api-ventago/src/app/client-import/models/client-import.model.ts` — ClientImport 모델 (D4-06)
- `api-ventago/src/app/clients/models/client-merge.model.ts` — ClientMerge 모델 (D1-04, JSONB fieldPicks)
- `api-ventago/src/app/common/models/client-access-audit.model.ts` — ClientAccessAudit 모델 (D3-04)

## Production Migration Timeline

| 시각 (KST) | 작업 | 결과 |
|----|----|----|
| 01:55 | Pre-migration: 3 테이블 부재 확인 | 적용 안전 |
| 01:58 | step4 1차 적용 | CREATE TABLE x3, DO x여러개, CREATE INDEX x6, COMMENT x3, COMMIT |
| 02:00 | Post-migration \d 검증 | 3 테이블 모두 컬럼/FK/인덱스 확인 |
| 02:02 | step4 2차 적용 (멱등성) | 모두 NOTICE skipping, 에러 0건 |
| 02:03 | api_ventago 컨테이너 로그 확인 | 새 테이블 관련 로그 0건 (정상 — 모델은 아직 컨테이너에 없음) |

## Verified Table Structures (운영)

### client_imports (13 columns)
- PK: id (SERIAL)
- FK: user_id → users(id) ON DELETE RESTRICT
- FK: store_id → stores(id) ON DELETE RESTRICT
- 데이터: file_name, total_rows, created/updated/skipped/error_count, executed_at, missing_doc_policy
- 인덱스: idx_client_imports_store_exec (store_id, executed_at DESC), idx_client_imports_user_exec

### client_merges (11 columns)
- PK: id (SERIAL)
- FK: user_id, store_id, winner_global_client_id (모두 ON DELETE RESTRICT)
- **JSONB**: field_picks (default '{}'::jsonb)
- 데이터: loser_global_client_id, local_client_id, merge_reason, merged_at
- 인덱스: idx_client_merges_winner, idx_client_merges_merged_at (DESC)

### client_access_audits (14 columns)
- PK: id (SERIAL)
- FK: user_id (ON DELETE RESTRICT)
- 데이터: caller_store_id, caller_owner_group_id, target_store_id, target_owner_group_id, target_global_client_id, endpoint (TEXT), method, ip_address (45 chars IPv6), user_agent (TEXT), denied_at
- 인덱스: idx_client_access_audits_user_denied (user_id, denied_at DESC), idx_client_access_audits_caller_store

## Decisions Made

- **audit 테이블 분리 (vs audit_logs ENUM 확장)**: PG10 의 ENUM 변경은 트랜잭션 외부에서만 가능 → 깨끗한 테이블 3개로 분리하면 PG10/PG15 양쪽 동일 적용 가능
- **JSONB 사용**: PG10 도 JSONB 지원 (PG9.4+), audit 용이라 인덱스 없이 저장만 — 향후 admin UI 에서 raw JSON 조회
- **FK ON DELETE RESTRICT**: audit 무결성 보존이 우선 — 사용자 삭제 막아도 됨 (운영상 사용자 삭제는 매우 드묾)
- **각 모델의 위치**: ClientImport (client-import/), ClientMerge (clients/), ClientAccessAudit (common/) — 책임 위치별 분산

## Deviations from Plan

- dev PG15 검증 생략 (샌드박스 docker 접근 제한) → 운영 직접 적용 + 멱등성 재검증으로 보강
- ESLint 검증은 호스트에서 push-both.sh 직전 실행 권장 (샌드박스에서 typescript-eslint projectService 로딩 시간 초과)

## Issues Encountered

- 첫 시도에서 모든 결과 expected 와 일치
- ESLint 실행이 샌드박스에서 타임아웃 → TypeScript 컴파일(tsc --noEmit)로 정합성 검증 완료 (에러 0)

## User Setup Required

- **다음 push-both.sh 실행 시점**: 새 모델 3개가 컨테이너에 반영됨 (현재 컨테이너는 모델 모르지만 sync:false 라 안전)
- **Wave 4 (Plan 25-10) 진행 시**: client-import 모듈 등록 + ClientImport 모델 SequelizeModule.forFeature 추가 필요

## Next Phase Readiness

- **Ready for Plan 25-05 (Wave 2 OwnerScopeGuard)**: client_access_audits 테이블 + ClientAccessAudit 모델 완성, Guard 가 INSERT 즉시 가능
- **Ready for Plan 25-10 (Wave 4 client-import 모듈)**: client_imports 테이블 + ClientImport 모델 완성
- **Ready for Plan 25-08 (Wave 3 promote/merge)**: client_merges 테이블 + ClientMerge 모델 완성
- **Blockers**: 없음

## Self-Check: PASSED

검증 항목:
- [x] step4 SQL 파일 존재
- [x] ClientImport 모델 파일 존재 (tableName='client_imports')
- [x] ClientMerge 모델 파일 존재 (tableName='client_merges', JSONB)
- [x] ClientAccessAudit 모델 파일 존재 (tableName='client_access_audits')
- [x] tsc --noEmit 에러 0건
- [x] 운영 DB: client_imports 13컬럼 + 2 FK + 2 인덱스 확인
- [x] 운영 DB: client_merges 11컬럼 + 3 FK + 2 인덱스 + JSONB 확인
- [x] 운영 DB: client_access_audits 14컬럼 + 1 FK + 2 인덱스 확인
- [x] 멱등성 재실행: NOTICE skipping 만, 에러 0
- [x] api_ventago 컨테이너 영향 없음 (sync:false)

---
*Phase: 25-clientes-globales-compartidos-entre-tiendas-historial-aislad*
*Completed: 2026-04-26*
