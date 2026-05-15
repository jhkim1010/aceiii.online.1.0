# Runbook — Phase 29 권한 시스템 v2 운영 PG10 적용

작성일: 2026-05-15
대상 환경: srv803182 (62.72.7.245), PostgreSQL 10 호스트, ventago DB
관련 SPEC: `.gsd/spec-permissions-v2.md`

## 사전 조건

- [ ] 운영 사용자 0명 확인 (zero-cost window 가정)
- [ ] dev PG18 에서 마이그레이션 + 시드 + E2E 테스트 모두 통과
- [ ] Mac 에서 `npm run build` (api-ventago + ventago-app) 성공
- [ ] Jenkins 배포 파이프라인 정상 (최근 빌드 grün)
- [ ] 운영 DB 백업 완료 (pg_dump)

## 적용 순서

### 단계 1 — 사전 백업 (필수)

```bash
ssh jhkim-server "sudo -u postgres pg_dump -Fc ventago > ~/ventago_backup_$(date +%Y%m%d_%H%M).dump"
ssh jhkim-server "ls -lh ~/ventago_backup_*.dump | tail -3"
```

### 단계 2 — phase29 메인 마이그레이션 (DDL)

```bash
# 사용자 확인 필수 — DDL 임 (CLAUDE.md 규칙)
ssh jhkim-server "sudo -u postgres psql -d ventago -v ON_ERROR_STOP=1" \
  < api-ventago/migrations/phase29-permissions-v2.sql
```

기대 출력:
```
BEGIN
NOTICE:  [Phase29] audit_logs.action ENUM 8개 값 추가 완료
DO
CREATE TABLE  (×4)
COMMENT      (×다수)
ALTER TABLE  (×1: role_functions branch_id)
ALTER TABLE  (×5: user_functions 5 컬럼)
COMMENT      (×다수)
COMMIT
CREATE INDEX (×7-8)
```

### 단계 3 — fixup 적용 (PG10 호환성 검증)

phase29 본 SQL 안의 `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` 가 PG10 에서 정상 동작하면 fixup 은 skip 가능. 만약 user_functions 5 컬럼이 안 들어가면:

```bash
ssh jhkim-server "sudo -u postgres psql -d ventago -v ON_ERROR_STOP=1" \
  < api-ventago/migrations/phase29-permissions-v2-fixup.sql
```

### 단계 4 — functions.permission_slug 매핑

```bash
ssh jhkim-server "sudo -u postgres psql -d ventago -v ON_ERROR_STOP=1" \
  < api-ventago/migrations/phase29-functions-permission-slug.sql
```

기대: 17 UPDATE + CREATE INDEX

### 단계 5 — 검증 쿼리 (운영 PG10)

```sql
-- 신규 테이블 4개
SELECT count(*) FROM information_schema.tables
WHERE table_schema='public'
  AND table_name IN ('user_branches','approval_thresholds','approval_requests','user_permission_cache');
-- 기대: 4

-- audit_logs ENUM 13값
SELECT count(*) FROM pg_enum e JOIN pg_type t ON e.enumtypid=t.oid
WHERE t.typname='enum_audit_logs_action';
-- 기대: 13

-- user_functions 5 신규 컬럼
SELECT count(*) FROM information_schema.columns
WHERE table_schema='public' AND table_name='user_functions'
  AND column_name IN ('branch_id','valid_from','valid_until','reason','granted_by');
-- 기대: 5

-- functions.permission_slug 매핑
SELECT count(DISTINCT permission_slug) FROM functions WHERE permission_slug IS NOT NULL;
-- 기대: ≥ 18
```

### 단계 6 — Backend 배포 (Jenkins)

Phase 29 코드를 `main` 브랜치에 merge 후:

```bash
# Jenkins UI 에서 api-coolsistema job 빌드 트리거
# 또는 자동 webhook 으로 push 시 빌드
```

배포 후 확인:
```bash
ssh jhkim-server "docker logs api_ventago --tail 100 | grep -E 'SequelizeModels|Pool|PermissionsModule'"
```

기대: `[SequelizeModels]` 로그에 4 신규 모델 (UserBranch, ApprovalThreshold, ApprovalRequest, UserPermissionCache) 포함.

### 단계 7 — Frontend 배포 (Jenkins)

```bash
# ventago-app 의 generator 한 번 실행 (BE 가 떠있는 상태)
cd ventago-app && API_URL=https://newapi.coolsistema.com/api npm run gen:permissions
git add src/configs/permissions.gen.ts
git commit -m "chore(phase29): regenerate permissions.gen.ts from prod BE"
git push

# Jenkins front-coolsistema 빌드 트리거
```

### 단계 8 — 첫 매장 셋업 (ACE 또는 신규)

옵션 A — 기존 매장 (ACE, store_id=9) 에 8 role 시드 추가:
```sql
-- 기존 4 role 폐기 X (legacy 호환)
-- 7 매장별 신규 role 추가
INSERT INTO roles (name, slug, store_id, created_at, updated_at) VALUES
  ('Dueño', 'store_owner', 9, NOW(), NOW()),
  ('Admin', 'store_admin', 9, NOW(), NOW()),
  ('Gerente Sucursal', 'branch_manager', 9, NOW(), NOW()),
  ('Cajero', 'cashier', 9, NOW(), NOW()),
  ('Stock', 'inventory_clerk', 9, NOW(), NOW()),
  ('Contador', 'accountant', 9, NOW(), NOW()),
  ('Solo Lectura', 'viewer', 9, NOW(), NOW())
ON CONFLICT DO NOTHING;
```

옵션 B — 신규 매장 (UI 마법사):
- https://ventago.coolsistema.com/admin/store/setup-wizard 접속 (super_admin 로그인)
- 4단계 마법사 진행

## 모니터링 (배포 직후 1주)

### 관찰 지표
```sql
-- audit_logs 의 권한 변경 분포
SELECT action, count(*)
FROM audit_logs
WHERE entity_type IN ('user_branch','user_function','approval_threshold','role')
  AND created_at > NOW() - INTERVAL '7 days'
GROUP BY action;

-- user_permission_cache 의 hit ratio (간접 측정 — row 갯수 vs 만료 갯수)
SELECT count(*) AS total_rows,
       count(*) FILTER (WHERE computed_at > NOW() - INTERVAL '5 minutes') AS fresh,
       count(*) FILTER (WHERE computed_at <= NOW() - INTERVAL '5 minutes') AS expired
FROM user_permission_cache;

-- approval_requests 의 처리 분포
SELECT status, count(*)
FROM approval_requests
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY status;
```

### 로그 모니터링
```bash
ssh jhkim-server "docker logs api_ventago --since 1h | grep -E 'Pool|PermissionGuard|ApprovalService'"
```

기대:
- `[Pool] 사용률 X%` 가 80% 미만 유지
- `[PermissionGuard]` 의 cache MISS 비율이 5% 이하
- `[ApprovalService]` 가 큐잉 처리 정상

### 알람 (자동)
- `[Pool] 사용률 80% 초과` 경고 → 즉시 점검
- `[Pool] 커넥션 대기 발생` 경고 → cache invalidation 패턴 검토
- `[SlowQuery]` 의 role_functions 관련 100ms+ → resolver SQL 점검

## 롤백 시나리오

### 시나리오 A — Backend 부팅 실패
```bash
# Jenkins 에서 이전 빌드로 롤백 (or git revert HEAD push)
ssh jhkim-server "docker logs api_ventago --tail 50"
```

### 시나리오 B — 마이그레이션 자체 실패
```bash
# DB 복구
ssh jhkim-server "sudo -u postgres pg_restore -d ventago -c ~/ventago_backup_YYYYMMDD_HHMM.dump"
# Backend 재배포 (이전 버전)
```

### 시나리오 C — 권한 체크 실패로 사용자 401/403 폭주
```sql
-- 임시: 모든 user_branches 의 valid_until 을 미래로 (무력화)
UPDATE user_branches SET valid_until = '2099-01-01' WHERE valid_until IS NULL;
-- 또는 PermissionGuard 임시 비활성화 (env 변수 또는 코드 hotfix)
```

또는 application 레벨에서 `PERMISSIONS_V2_ENABLED=false` 환경변수로 신규 가드 무력화 (별도 구현 필요).

## 운영 사용자 0명 가정의 한계

본 runbook 은 사용자 0명 가정 하에 작성됨. 만약 사용자가 늘어나면:

1. 마이그레이션 시 `users.branch_id` → `user_branches` backfill 필요:
```sql
INSERT INTO user_branches (user_id, branch_id, role_id, is_default, granted_by, reason)
SELECT u.id, u.branch_id, ur.role_id, true, u.id, 'auto-backfill from users.branch_id'
FROM users u
JOIN user_roles ur ON ur.user_id = u.id
WHERE u.branch_id IS NOT NULL
ON CONFLICT (user_id, branch_id) DO NOTHING;
```

2. 신규 가드를 log-only 모드로 7일 dry-run (별도 SPEC).

## 후속 작업

- [ ] 운영 적용 후 1주 모니터링 결과 → review-permissions-v2-prod-1week.md
- [ ] Phase 30 후보:
  - 기존 @FunctionGuard → @Permission 점진 마이그레이션
  - functions.permission_slug 커버리지 18% → 80%+ 확장
  - storeTemplate 의 idempotent 가드 추가 (중복 INSERT 방지)
  - approval_thresholds UI 편집 기능
  - Frontend ACL 어휘 일괄 통일
