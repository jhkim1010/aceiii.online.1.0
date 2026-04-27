# SPEC: Phase 25 순차 진행 (25-02 → 25-03 → 25-04)
생성일: 2026-04-26

## 목표
Phase 25 Wave 1을 완성하기 위해 Plan 25-02, 25-03, 25-04를 순차 실행한다.
clientes masivo importación 기능 백엔드 인프라(스키마 + 모델)를 운영 적용 가능 상태로 만든다.

## 배경 및 컨텍스트

**운영 DB 사전 확인 (2026-04-26 검증 완료):**
- `sales.store_client_id` 컬럼: 없음
- `client_imports / client_merges / client_access_audits` 테이블: 없음
- `global_clients`: 0 rows
- `store_clients`: 0 rows
- `clients`: 4 rows (스토어당 1개)
- `sales`: 8 rows (모두 client_id populated, store_client_id NULL)

**이미 완료된 항목:**
- `api-ventago/migrations/20260424-phase25-step3-sales-store-client.sql` (로컬 존재)
- `api-ventago/src/app/sales/sales.model.ts`의 `storeClientId` 필드 (이미 코드에 적용)

**관련 파일:**
- `.planning/phases/25-clientes-globales-compartidos-entre-tiendas-historial-aislad/25-02-PLAN.md`
- `.planning/phases/25-clientes-globales-compartidos-entre-tiendas-historial-aislad/25-03-PLAN.md`
- `.planning/phases/25-clientes-globales-compartidos-entre-tiendas-historial-aislad/25-04-PLAN.md`

## 기술 스택
- 언어/프레임워크: NestJS 11 + TypeScript + Sequelize-typescript
- DB: 운영 PostgreSQL 10 (호스트), dev PostgreSQL 15 (Docker `dbpostgres`)
- ESLint 설정 파일: `api-ventago/.eslintrc.js`
- Pool: api-ventago Sequelize singleton (max=50, 변경 금지)

## 태스크 목록

### Plan 25-02 (Task 3만 — 나머지는 이미 완료)
- [ ] TASK-1: 운영 DB에 step3 SQL 적용 (`sales.store_client_id` 컬럼 + FK + 인덱스)
- [ ] TASK-2: api_ventago 컨테이너 재시작 + boot 검증 (sync 로그 확인)
- [ ] TASK-3: 25-02-SUMMARY.md 작성

### Plan 25-03 (신규 SQL 2개 + 적용)
- [ ] TASK-4: `step5-data-migration.sql` 생성 (legacy clients → global+store_clients + sales 재매핑)
- [ ] TASK-5: `step6-verify.sql` 생성 (8개 read-only assertion 섹션)
- [ ] TASK-6: dev PG15에서 step5 더블런 (멱등성 검증)
- [ ] TASK-7: dev PG15에서 step6 실행 (모든 assertion 통과 확인)
- [ ] TASK-8: 운영 사전 상태 조회 (clients 4개 document 형식 확인)
- [ ] TASK-9: 운영 DB에 step5 적용 + step6 검증 + 더블런
- [ ] TASK-10: 25-03-SUMMARY.md 작성

### Plan 25-04 (audit 테이블 SQL + 모델 3개)
- [ ] TASK-11: `step4-audit-tables.sql` 생성 (3개 테이블 + FK + GRANT)
- [ ] TASK-12: dev PG15에서 step4 더블런 (멱등성 검증)
- [ ] TASK-13: `client-import.model.ts` 생성
- [ ] TASK-14: `client-merge.model.ts` 생성
- [ ] TASK-15: `client-access-audit.model.ts` 생성
- [ ] TASK-16: `npm run build` 통과 확인 (TS 에러 0)
- [ ] TASK-17: ESLint 검증 (`npx eslint <new files>` 0 에러)
- [ ] TASK-18: 운영 DB에 step4 적용 + 검증
- [ ] TASK-19: api_ventago 재시작 + boot 검증
- [ ] TASK-20: 25-04-SUMMARY.md 작성

### 최종
- [ ] TASK-21: STATE.md 업데이트 (completed_plans 1→4, percent 갱신)

## 완료 기준
- 운영 DB에 `sales.store_client_id` 컬럼 + 3개 audit 테이블 + global/store_clients 데이터 존재
- `npm run build` TS 에러 0개
- 새로 작성한 모델 파일에 ESLint 에러 0개
- api_ventago 컨테이너 정상 boot (sync ALTER 로그 0건)
- step6 verify 모든 assertion 통과 (orphan 0, 스코프 위반 0)
- 운영 DB pool 사용량: SSH 통한 SQL 실행만 (SELECT 위주, 변경은 트랜잭션 1회씩)

## 금지사항 / 주의사항

**PostgreSQL Pool 안전:**
- 운영 DB는 PG10 호스트 직접 접속 (`sudo -u postgres psql`) — pgbouncer 5432 프록시 거치지 않음
- 각 마이그레이션은 BEGIN/COMMIT 트랜잭션 1회로 wrap (커넥션 1개만 사용)
- Sequelize 모델만 추가 — 새 Pool 인스턴스 생성 금지
- `sync: false` 유지 (boot 시 ALTER 로그 발생하면 즉시 중단)

**파괴적 작업 금지:**
- 레거시 `clients` 테이블 UPDATE/DELETE 금지 (D2-03)
- `sales.client_id` 컬럼 변경 금지 (D2-01 backward compat)
- 기존 인덱스 DROP 금지 (Phase 25-01에서 제거할 것은 이미 제거됨)

**ESLint:**
- 새 파일은 `lines-around-comment`, `newline-before-return` 규칙 준수
- 주석은 한국어, 변수/함수명은 영어
- 모든 async 메서드 try/catch 포함

**사용자 확인 게이트 (반드시 정지):**
1. Plan 25-02 운영 적용 전 (step3 SQL)
2. Plan 25-03 운영 적용 전 (step5 SQL — 데이터 변경 있음)
3. Plan 25-04 운영 적용 전 (step4 SQL)

## 운영 적용 컨테이너 주의
- 운영서버: srv803182 / 62.72.7.245 (SSH alias: jhkim-server)
- DB: ventago (PG10 호스트, owner: coolsistema)
- API: docker compose restart api_ventago (DB는 호스트라 Docker 아님)
