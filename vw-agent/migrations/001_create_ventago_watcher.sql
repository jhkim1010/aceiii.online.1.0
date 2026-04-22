-- =============================================================================
-- vw-agent: ventago_watcher 감시 전용 read-only 계정 생성
-- -----------------------------------------------------------------------------
-- 대상: ventago 데이터베이스
-- 실행 환경:
--   - 로컬 dev  : Mac Homebrew PostgreSQL 18 (port 5432)
--   - 운영       : srv803182 호스트 PG 10
-- 목적:
--   - vw-agent 가 운영 PG 에 붙어 pg_stat_activity / pg_stat_database 등
--     모니터링 뷰를 조회하기 위한 최소 권한 계정.
--   - INSERT/UPDATE/DELETE/DDL 은 모두 차단.
-- 안전 조치:
--   - statement_timeout = 3s, idle_in_transaction_session_timeout = 5s
--   - application_name = 'vw-agent-watcher' (pg_stat_activity 에서 식별)
-- -----------------------------------------------------------------------------
-- 실행 예:
--   PG_PW=$(grep '^PG_WATCHER_PASSWORD=' vw-agent/.env | cut -d= -f2-)
--   PGPASSWORD=wkrdjqwnd psql -h 127.0.0.1 -p 5432 -U postgres -d ventago \
--     -v watcher_pw="'${PG_PW}'" \
--     -f vw-agent/migrations/001_create_ventago_watcher.sql
-- -----------------------------------------------------------------------------
-- 참고: psql 변수 `:'watcher_pw'` 는 DO $$ ... $$ 블록 내부에서는 확장되지
--       않으므로, 역할 생성/비밀번호 갱신은 블록 바깥에서 수행한다.
-- =============================================================================

-- ---------- 1단계: 역할 존재 여부를 psql 변수로 저장 (블록 내부에서 사용 가능) ----------
SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ventago_watcher')
  AS watcher_exists \gset

-- ---------- 2단계: 없으면 CREATE, 있으면 ALTER — psql \if 분기 ----------
\if :watcher_exists
  ALTER ROLE ventago_watcher WITH LOGIN PASSWORD :'watcher_pw';
\else
  CREATE ROLE ventago_watcher WITH LOGIN PASSWORD :'watcher_pw';
\endif

-- ---------- 3단계: 권한 부여 ----------
GRANT CONNECT ON DATABASE ventago TO ventago_watcher;
GRANT USAGE   ON SCHEMA   public  TO ventago_watcher;

-- branch_agents 테이블 존재 시에만 SELECT 권한 (로컬 dev 에는 없을 수 있음)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'branch_agents'
  ) THEN
    EXECUTE 'GRANT SELECT ON TABLE public.branch_agents TO ventago_watcher';
  END IF;
END
$$;

-- pg_monitor 롤 — pg_stat_activity 등 모니터링 뷰 조회 필수 (PG10+)
GRANT pg_monitor TO ventago_watcher;

-- ---------- 4단계: 세션 제약 ----------
ALTER ROLE ventago_watcher SET statement_timeout = '3s';
ALTER ROLE ventago_watcher SET idle_in_transaction_session_timeout = '5s';
ALTER ROLE ventago_watcher SET application_name = 'vw-agent-watcher';
ALTER ROLE ventago_watcher SET lock_timeout = '2s';

-- ---------- 검증 (출력) ----------
\echo '--- ventago_watcher 계정 상태 ---'
SELECT rolname, rolcanlogin, rolsuper, rolbypassrls
FROM pg_roles WHERE rolname = 'ventago_watcher';

SELECT has_database_privilege('ventago_watcher','ventago','CONNECT') AS can_connect,
       has_schema_privilege(  'ventago_watcher','public','USAGE')    AS schema_usage;

-- =============================================================================
-- 완료: ventago_watcher 가 read-only 로 ventago DB 접근 가능
-- =============================================================================
