---
status: testing
phase: 33-permissions-v2
source:
  - .gsd/spec-permissions-v2.md
  - .gsd/runbook-permissions-v2-prod.md
  - .gsd/review-permissions-v2-day1-2.md
  - .gsd/review-permissions-v2-day3.md
  - .gsd/review-permissions-v2-day4.md
  - .gsd/review-permissions-v2-day6-7.md
  - .gsd/review-permissions-v2-day8.md
  - .gsd/review-permissions-v2-sprint1-final.md
  - .gsd/review-permissions-v2-final-phase29.md
started: 2026-05-18T13:30:00.000Z
updated: 2026-05-19T15:35:00.000Z
backup: /home/jhkim/ventago_backup_20260518_2244.dump (843K, 1443 TOC entries, PG10.23, dumped 2026-05-18 13:44:03 UTC)
env: production-pg10
pre_flight_checks:
  active_users_24h: 0
  prerequisite_tables_present: true
  new_tables_absent: true (idempotent OK)
  audit_logs_enum_baseline: 5 values (create/edit/remove/open/close)
  user_functions_columns_baseline: 7 columns (5 new to add)
notes: |
  Phase 33 (Permissions v2) retroactively registered 2026-05-17.
  Code implementation 완료 + push 완료 (commits da6bf01, 9c51fd9, f768d78).
  운영 PG10 마이그레이션 미실행 — UAT 는 운영 적용 후 수행.
---

## Current Test

number: 11
name: 첫 매장 사용자 로그인 + 권한 매트릭스 화면
expected: |
  - super_admin 로 ventago.coolsistema.com 로그인
  - /configuracion/permisos 접속
  - 4 탭 표시 (권한 매트릭스 / 사용자 상세 / 감사 로그 / 승인 임계값)
  - 매트릭스 그리드 정상 렌더 (sticky header + first column)
  - mockup.html 의 다크 네이비 + 골드 테마 확인
awaiting: user response

## Tests

### 0. Pre-flight — 운영 DB 백업
expected: pg_dump 백업 파일 생성 (ventago_backup_YYYYMMDD_HHMM.dump), 크기 > 0
result: pass
artifacts:
  - /home/jhkim/ventago_backup_20260518_2244.dump
  - size: 843K, TOC entries: 1443, PG10.23
  - dumped_at: 2026-05-18T13:44:03Z (UTC)
critical: true

### 1. 운영 PG10 메인 마이그레이션 적용
expected: |
  api-ventago/migrations/phase29-permissions-v2.sql 실행 후:
  - BEGIN / COMMIT 정상 완료
  - 4 신규 테이블 생성
  - audit_logs.action ENUM 8값 추가
  - user_functions 5 컬럼 추가
  - role_functions.branch_id 컬럼 추가
  - CREATE INDEX 7-8개
result: pass
artifacts:
  - 8 ALTER TYPE + 4 CREATE TABLE + 6 ALTER TABLE + 10 CREATE INDEX
  - applied_at: 2026-05-18T14:00:00Z
critical: true

### 2. fixup 마이그레이션 (PG10 호환성 검증)
expected: |
  phase29-permissions-v2-fixup.sql 실행 (또는 skip 판단):
  - user_functions 5 컬럼이 메인 SQL 에서 정상 들어갔으면 skip 가능
result: skipped
reason: 메인 SQL 에서 5 컬럼 완벽 적용되어 fixup 불필요

### 3. functions.permission_slug 매핑
expected: |
  phase29-functions-permission-slug.sql 실행 후:
  - 17 UPDATE + CREATE INDEX
  - functions 테이블의 permission_slug 컬럼이 18+개 함수에 매핑됨
result: pass
artifacts:
  - ALTER TABLE + 17 UPDATE (29 rows affected) + CREATE INDEX
  - 28 mapped rows / 131 unmapped / 159 total
critical: true

### 4. 검증 쿼리 — 4 신규 테이블 존재
expected: 4 tables
result: pass
actual: 4

### 5. 검증 쿼리 — audit_logs ENUM 13값
expected: 13 (기존 5 + 신규 8)
result: pass
actual: 13

### 6. 검증 쿼리 — user_functions 5 신규 컬럼
expected: 5
result: pass
actual: 5

### 7. 검증 쿼리 — functions.permission_slug ≥ 18
expected: ≥ 18
result: pass
actual: 18 distinct permission_slugs

### 8. Backend 배포 (Jenkins) — api_ventago 컨테이너 부팅
expected: |
  Jenkins api-coolsistema job 빌드 트리거 + 배포 후:
  - docker logs api_ventago 에 [SequelizeModels] 로그 정상
  - 4 신규 모델 등록 확인 (UserBranch, ApprovalThreshold, ApprovalRequest, UserPermissionCache)
  - PermissionsModule 정상 로드
  - 부팅 에러 0
result: pass
artifacts:
  - container_uptime: 16h (booted 2026-05-18 14:23:12 UTC, verified 2026-05-19)
  - PermissionsModule dependencies initialized — confirmed
  - 4 신규 모델 모두 로드: ApprovalRequest, ApprovalThreshold, UserBranch, UserPermissionCache
  - 부팅 ERROR 0건 (MpTokenRefreshCron failed=0 만 — 정상 cron 결과)
  - 검증 명령: ssh jhkim-server "docker logs api_ventago 2>&1 | grep PermissionsModule"
critical: true

### 9. Frontend 배포 — permissions.gen.ts regenerate + Jenkins
expected: |
  - cd ventago-app && API_URL=https://newapi.coolsistema.com/api npm run gen:permissions
  - src/configs/permissions.gen.ts 생성됨
  - git add/commit/push
  - Jenkins front-coolsistema 빌드 성공
  - https://ventago.coolsistema.com 정상 접속
result: pass
artifacts:
  - Jenkins front-coolsistema #352 빌드 성공 (2026-05-19)
  - commit chain: f7c1680 (next/font/google→@fontsource) → f9f18ca (lockfile fix) →
    f021a16 (npm install→ci) → 33650fb (force-install fontsource) →
    8b38809 (woff2 commit + @font-face) → 1c69b50 (_app.tsx 직접 import)
  - 5회 빌드 실패 후 6번째 성공 (#346/#347/#349/#350/#351 fail → #352 pass)
  - 근본 원인: Alpine + Node 20 npm 10.x 의 @fontsource phantom-install 버그
  - 근본 해결: @fontsource 의존성 제거 + public/fonts/public-sans/*.woff2 직접 commit
critical: true

### 10. 첫 매장 (ACE store_id=9) 7 role 시드
expected: |
  ACE 매장에 7 신규 role 추가 (store_owner, store_admin, branch_manager,
  cashier, inventory_clerk, accountant, viewer). INSERT 후 SELECT 로 8개 role
  존재 확인 (super_admin store_id=NULL 1개 + ACE store_id=9 의 7개).
result: pass
artifacts:
  - 실제 ACE store_id=9 role 10개 (Spanish 이름 매핑 + legacy 호환):
    - Dueño (32) → store_owner
    - Admin Tienda (33) → store_admin
    - Gerente Sucursal (34) → branch_manager
    - Cajero (35) → cashier
    - Stock (36) → inventory_clerk
    - Contador (37) → accountant
    - Solo Lectura (38) → viewer
    - Admin (29) / Vendedor (30) / Gerente (31) — legacy (호환 유지)
  - store_id IS NULL system roles 4개 (1 vendedor / 2 admin / 3 superadmin / 4 gerente)
  - 7 spec role 모두 present (스페인어 localization 의도된 결과)
critical: true

### 11. 첫 매장 사용자 로그인 + 권한 매트릭스 화면
expected: |
  - super_admin 로 ventago.coolsistema.com 로그인
  - /configuracion/permisos 접속
  - 4 탭 표시 (권한 매트릭스 / 사용자 상세 / 감사 로그 / 승인 임계값)
  - 매트릭스 그리드 정상 렌더 (sticky header + first column)
  - mockup.html 의 다크 네이비 + 골드 테마 확인
result: [pending]

### 12. PermissionGuard cache 동작
expected: |
  - 신규 사용자 생성 + user_branches grant
  - 첫 권한 체크: cache MISS → SQL JOIN 후 user_permission_cache INSERT
  - 2회차 같은 사용자 권한 체크: cache HIT → JSONB lookup
  - docker logs 에서 [PermissionGuard] cache MISS / HIT 로그 비율 확인
result: [pending]

### 13. BranchScopeGuard 동작
expected: |
  - @BranchScope({ paramName: 'branchId' }) 가 적용된 컨트롤러 호출 시:
  - 요청 path/body 의 branchId 가 user 의 user_branches 에 매칭 → 200
  - 매칭 안 됨 → 403 Forbidden
result: [pending]

### 14. Approval 임계값 플로우
expected: |
  - cashier role 사용자가 환불 시도 (max_amount 초과)
  - approval_requests 테이블에 status='pending' INSERT
  - socket.io 로 승인자 (branch_manager) 에게 알림
  - branch_manager 가 /api/approval/requests/:id/approve 호출
  - approval_requests.status='approved' 변경
  - 원래 환불 작업 자동 진행
result: [pending]

### 15. Audit log 권한 변경 기록
expected: |
  - 권한 grant/revoke/threshold_change 등 모든 변경 시
  - audit_logs 에 entity_type='permission' 으로 row INSERT
  - oldValues + newValues + reason 정상 기록
  - 같은 transaction 안에서 권한 변경 + audit 함께 commit (rollback 시 둘 다 rollback)
result: [pending]

### 16. Pool 사용률 모니터링 (배포 직후 1시간)
expected: |
  docker logs api_ventago --since 1h | grep '[Pool]'
  - 사용률 P95 ≤ 50%
  - 80% 초과 경고 0건
  - 대기 발생 0건
  - cache hit ratio ≥ 95%
result: [pending]

### 17. 권한 체크 latency
expected: |
  GET /api/permissions/matrix?storeId=9 응답 P95 ≤ 30ms
  (현재 role_functions 단일 쿼리 104ms 였음 → cache + 단일 JOIN 으로 개선)
result: [pending]

### 18. Cold start smoke test
expected: |
  - docker compose down + docker compose up -d
  - api_ventago 부팅 시 마이그레이션 idempotent 확인 (재실행 에러 없음)
  - 8 role 시드 idempotent 확인 (중복 INSERT 에러 없음)
  - /api/auth/me 응답 정상 (PermissionsModule 로드 완료 표시)
result: [pending]

## Summary

total: 19
passed: 10
issues: 0
pending: 8
skipped: 1
blocked: 0

## Gaps

[none yet — testing not started]

## Pre-UAT Checklist

운영 PG10 적용 전 사용자 확인 필요 항목:

- [ ] 운영 사용자 0명 확인 (zero-cost window)
- [ ] dev PG18 에서 마이그레이션 + 시드 + E2E 테스트 통과 확인
- [ ] api-ventago + ventago-app Mac 빌드 성공
- [ ] Jenkins 최근 빌드 grün
- [ ] 운영 DB 백업 (Test 0)
- [ ] CLAUDE.md DDL 규칙 준수 — 각 마이그레이션 단계별 사용자 확인
