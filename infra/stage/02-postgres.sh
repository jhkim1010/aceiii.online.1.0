#!/usr/bin/env bash
# ============================================================
# 02 — PostgreSQL 18 + pgbouncer
# ============================================================
# 운영과 동일한 포트 구조를 그대로 재현한다:
#   앱 → pgbouncer(5432, transaction mode) → PG18 클러스터 ventago18(5434)
# 구조가 같아야 운영 설정/스크립트/진단 절차가 그대로 통한다.
#
# 커넥션 예산은 00-config.env 에서 산정하고 verify_connection_budget 이 검증한다.
# ============================================================
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_config
verify_connection_budget

log "PostgreSQL ${STAGE_PG_VERSION} + pgbouncer 설치: ${STAGE_HOST}"

stage_ssh "bash -s" <<REMOTE
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "── PGDG 저장소 ──"
install -d /usr/share/postgresql-common/pgdg
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
  -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc
. /etc/os-release
echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] \
https://apt.postgresql.org/pub/repos/apt \${VERSION_CODENAME}-pgdg main" \
  > /etc/apt/sources.list.d/pgdg.list
apt-get update -qq

echo "── PostgreSQL ${STAGE_PG_VERSION} + pgbouncer 설치 ──"
apt-get install -y -qq \
  postgresql-${STAGE_PG_VERSION} postgresql-client-${STAGE_PG_VERSION} \
  postgresql-contrib-${STAGE_PG_VERSION} pgbouncer

echo "── 클러스터 ventago${STAGE_PG_VERSION} (포트 ${STAGE_PG_PORT}) ──"
if ! pg_lsclusters | awk '{print \$1"/"\$2}' | grep -qx "${STAGE_PG_VERSION}/ventago${STAGE_PG_VERSION}"; then
  # 기본 클러스터(main)는 쓰지 않는다 — 운영과 이름/포트를 맞춘다.
  pg_createcluster ${STAGE_PG_VERSION} ventago${STAGE_PG_VERSION} \
    --port=${STAGE_PG_PORT} --locale=en_US.UTF-8 --start
  echo "  생성 완료"
else
  echo "  이미 존재 — 스킵"
fi
# 기본 main 클러스터는 커넥션·메모리 낭비이므로 정지한다.
if pg_lsclusters | awk '{print \$1"/"\$2}' | grep -qx "${STAGE_PG_VERSION}/main"; then
  pg_ctlcluster ${STAGE_PG_VERSION} main stop || true
  pg_dropcluster ${STAGE_PG_VERSION} main || true
  echo "  기본 main 클러스터 제거 (리소스 낭비 방지)"
fi

PGCONF=/etc/postgresql/${STAGE_PG_VERSION}/ventago${STAGE_PG_VERSION}

echo "── postgresql.conf 튜닝 ──"
TOTAL_MB=\$(free -m | awk '/^Mem:/{print \$2}')

# ★ 이 서버는 DB 전용이 아니다. 같은 8GB 안에서 아래가 함께 돈다:
#     PG + pgbouncer + api(PM2 ${API_WORKERS}워커) + Next.js + Redis + MinIO + Docker + OS
#   교과서값(shared_buffers = RAM/4)을 쓰면 Next.js 빌드 때 OOM 이 난다.
#   운영 서버에서 겪은 그 사고(build #620, swap 0 상태의 SIGABRT)를 여기서 반복하지 않는다.
#   → DB 몫을 RAM 의 약 45% 로 한정하고 그 안에서 배분한다.
DB_BUDGET_MB=\$(( TOTAL_MB * 45 / 100 ))

SHARED_BUFFERS_MB=\$(( DB_BUDGET_MB * 45 / 100 ))    # 8GB → 약 1.6GB
# effective_cache_size 는 실제 할당이 아니라 플래너 힌트다. OS 페이지 캐시로
# 기대할 수 있는 양만 잡는다 (앱이 쓰는 몫을 뺀 나머지).
EFFECTIVE_CACHE_MB=\$(( TOTAL_MB * 40 / 100 ))       # 8GB → 약 3.2GB

# ── work_mem: 여기가 가장 틀리기 쉬운 값 ──
# work_mem 은 커넥션당이 아니라 **쿼리 안의 정렬/해시 노드마다** 따로 잡힌다.
# 즉 최악 사용량은  max_connections × 노드수 × work_mem  이다.
# 노드수를 보수적으로 3 으로 잡고, shared_buffers 를 뺀 나머지 DB 예산 안에
# 들어오도록 역산한다. 상한 16MB — 이 규모에서 그 이상은 OOM 을 사는 것이다.
SORT_NODES=3
WORK_MEM_MB=\$(( (DB_BUDGET_MB - SHARED_BUFFERS_MB) / ${PG_MAX_CONNECTIONS} / SORT_NODES ))
[ "\$WORK_MEM_MB" -gt 16 ] && WORK_MEM_MB=16
[ "\$WORK_MEM_MB" -lt 4  ] && WORK_MEM_MB=4

MAINT_MEM_MB=\$(( DB_BUDGET_MB / 12 ))
[ "\$MAINT_MEM_MB" -gt 512 ] && MAINT_MEM_MB=512

SHARED_BUFFERS=\${SHARED_BUFFERS_MB}MB
EFFECTIVE_CACHE=\${EFFECTIVE_CACHE_MB}MB
WORK_MEM=\${WORK_MEM_MB}MB
MAINT_MEM=\${MAINT_MEM_MB}MB

WORST_CASE=\$(( SHARED_BUFFERS_MB + WORK_MEM_MB * ${PG_MAX_CONNECTIONS} * SORT_NODES + MAINT_MEM_MB ))
echo "  RAM 총량        : \${TOTAL_MB}MB"
echo "  DB 예산(45%)    : \${DB_BUDGET_MB}MB"
echo "  shared_buffers  : \$SHARED_BUFFERS"
echo "  work_mem        : \$WORK_MEM (× ${PG_MAX_CONNECTIONS} conn × \${SORT_NODES} node)"
echo "  maintenance     : \$MAINT_MEM"
echo "  최악 사용량 추정: \${WORST_CASE}MB / 총 \${TOTAL_MB}MB"
if [ "\$WORST_CASE" -gt "\$(( TOTAL_MB * 80 / 100 ))" ]; then
  echo "  !! 최악 사용량이 RAM 의 80% 를 넘습니다 — PG_MAX_CONNECTIONS 를 낮추세요"
  exit 1
fi

cat > \$PGCONF/conf.d/10-ventago-stage.conf <<PGC
# ── 스테이지 전용 튜닝 (infra/stage/02-postgres.sh 가 생성) ──
listen_addresses = 'localhost'          # ★ 외부 노출 금지. 앱은 pgbouncer 경유.
port = ${STAGE_PG_PORT}
max_connections = ${PG_MAX_CONNECTIONS}

shared_buffers = \$SHARED_BUFFERS
effective_cache_size = \$EFFECTIVE_CACHE
work_mem = \$WORK_MEM
maintenance_work_mem = \$MAINT_MEM

# SSD 가정
random_page_cost = 1.1
effective_io_concurrency = 200

# 체크포인트 스파이크 완화
checkpoint_completion_target = 0.9
wal_buffers = 16MB
max_wal_size = 2GB
min_wal_size = 512MB

# ── 병렬 처리: 4 vCore 기준 ──
# 앱(PM2 ${API_WORKERS}워커) + Next.js 가 같은 CPU 를 쓴다. PG 가 코어를 독식하면
# API 응답이 밀린다. 총 워커를 2 로 묶고 쿼리당 2개까지만 허용한다.
max_worker_processes = 4
max_parallel_workers = 2
max_parallel_workers_per_gather = 2
max_parallel_maintenance_workers = 2

# autovacuum: 스테이지는 대량 복원 직후 죽은 튜플이 많다. 조금 공격적으로.
autovacuum_max_workers = 2
autovacuum_naptime = 30s
autovacuum_vacuum_scale_factor = 0.05
autovacuum_analyze_scale_factor = 0.02

# 세션 TZ — 앱(DATABASE_TZ=-03:00)과 맞춘다. UTC 로 두면 21시 이후 판매가
# 보고서 날짜 필터에서 누락된다 (운영에서 겪은 결함).
timezone = '${STAGE_TZ}'

# ── 로깅: 스테이지는 운영보다 촘촘하게 본다 ──
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d.log'
log_rotation_age = 1d
log_rotation_size = 100MB
log_min_duration_statement = 100        # 100ms 이상 쿼리 기록 (규약과 동일 기준)
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on
log_temp_files = 0
log_autovacuum_min_duration = 0
log_line_prefix = '%m [%p] %q%u@%d/%a '

# 통계 확장 — 느린 쿼리 추적
shared_preload_libraries = 'pg_stat_statements'
pg_stat_statements.max = 10000
pg_stat_statements.track = all
PGC

echo "── pg_hba.conf (localhost 만) ──"
cat > \$PGCONF/pg_hba.conf <<'HBA'
# TYPE  DATABASE  USER      ADDRESS         METHOD
local   all       postgres                  peer
local   all       all                       scram-sha-256
host    all       all       127.0.0.1/32    scram-sha-256
host    all       all       ::1/128         scram-sha-256
HBA

pg_ctlcluster ${STAGE_PG_VERSION} ventago${STAGE_PG_VERSION} restart
sleep 3
pg_lsclusters

echo "── 역할 / 데이터베이스 ──"
sudo -u postgres psql -p ${STAGE_PG_PORT} -v ON_ERROR_STOP=1 <<SQL
DO \\\$\\\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${STAGE_DB_OWNER}') THEN
    CREATE ROLE ${STAGE_DB_OWNER} LOGIN PASSWORD '${STAGE_DB_OWNER_PASSWORD}';
  ELSE
    ALTER ROLE ${STAGE_DB_OWNER} PASSWORD '${STAGE_DB_OWNER_PASSWORD}';
  END IF;

  -- 공개몰 읽기 전용 격리 계정 (migrations/shop-mvp-readonly-role.sql 과 동일 이름)
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'shop_readonly') THEN
    CREATE ROLE shop_readonly LOGIN PASSWORD '${STAGE_SHOP_RO_PASSWORD}';
  ELSE
    ALTER ROLE shop_readonly PASSWORD '${STAGE_SHOP_RO_PASSWORD}';
  END IF;
END
\\\$\\\$;
SQL

if ! sudo -u postgres psql -p ${STAGE_PG_PORT} -tAc \
     "SELECT 1 FROM pg_database WHERE datname='${STAGE_DB_NAME}'" | grep -q 1; then
  sudo -u postgres createdb -p ${STAGE_PG_PORT} -O ${STAGE_DB_OWNER} ${STAGE_DB_NAME}
  echo "  DB ${STAGE_DB_NAME} 생성"
fi

sudo -u postgres psql -p ${STAGE_PG_PORT} -d ${STAGE_DB_NAME} -v ON_ERROR_STOP=1 <<'SQL'
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;
SQL

echo "── pgbouncer (transaction mode, 포트 ${STAGE_PGB_PORT}) ──"
cat > /etc/pgbouncer/pgbouncer.ini <<PGB
;; 스테이지 pgbouncer — infra/stage/02-postgres.sh 가 생성
;; 구조는 운영과 동일: 앱 → 여기(${STAGE_PGB_PORT}) → PG18(${STAGE_PG_PORT})

[databases]
;; pool_size 는 (db, user) 쌍마다 적용된다. 쌍이 늘면 백엔드 총합도 늘어난다.
${STAGE_DB_NAME} = host=127.0.0.1 port=${STAGE_PG_PORT} dbname=${STAGE_DB_NAME} pool_size=${PGBOUNCER_POOL_SIZE}
${STAGE_DB_NAME}_shop = host=127.0.0.1 port=${STAGE_PG_PORT} dbname=${STAGE_DB_NAME} pool_size=${PGBOUNCER_SHOP_POOL_SIZE}

[pgbouncer]
listen_addr = 127.0.0.1
listen_port = ${STAGE_PGB_PORT}
auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt

;; transaction mode: 트랜잭션 단위로 서버 커넥션을 반납한다.
;; ★ 이 모드에서는 세션 레벨 기능(prepared statement 캐시, advisory lock, LISTEN/NOTIFY)이
;;   깨진다. 앱이 그 전제로 짜여 있으므로 절대 session 으로 바꾸지 않는다.
pool_mode = transaction

max_client_conn = 200
default_pool_size = ${PGBOUNCER_POOL_SIZE}
min_pool_size = 2
reserve_pool_size = 5
reserve_pool_timeout = 3

;; 유휴 서버 커넥션을 오래 붙들지 않는다 (pool 낭비 방지)
server_idle_timeout = 60
server_lifetime = 3600
;; 앱의 sequelize acquire 가 15초이므로 그보다 짧게 잡아 빠르게 실패시킨다.
query_wait_timeout = 10

;; transaction mode 필수 — 클라이언트가 남긴 세션 상태를 서버 반납 전에 초기화
server_reset_query = DISCARD ALL
server_reset_query_always = 0
ignore_startup_parameters = extra_float_digits,options

log_connections = 1
log_disconnections = 1
log_pooler_errors = 1
stats_period = 60

admin_users = postgres, ${STAGE_DB_OWNER}
stats_users = postgres, ${STAGE_DB_OWNER}
PGB

echo "── pgbouncer userlist (SCRAM 해시를 PG 에서 그대로 가져온다) ──"
sudo -u postgres psql -p ${STAGE_PG_PORT} -tA -c \
  "SELECT '\"'||rolname||'\" \"'||rolpassword||'\"' FROM pg_authid
   WHERE rolcanlogin AND rolpassword IS NOT NULL;" \
  > /etc/pgbouncer/userlist.txt
chown postgres:postgres /etc/pgbouncer/userlist.txt
chmod 600 /etc/pgbouncer/userlist.txt

systemctl enable pgbouncer
systemctl restart pgbouncer
sleep 2
systemctl --no-pager status pgbouncer | head -5

echo "── 연결 확인 ──"
PGPASSWORD='${STAGE_DB_OWNER_PASSWORD}' psql \
  -h 127.0.0.1 -p ${STAGE_PGB_PORT} -U ${STAGE_DB_OWNER} -d ${STAGE_DB_NAME} \
  -c "SELECT current_database(), current_user, version();"

echo
echo "✓ PostgreSQL + pgbouncer 완료"
echo "  PG        : 127.0.0.1:${STAGE_PG_PORT} (클러스터 ventago${STAGE_PG_VERSION})"
echo "  pgbouncer : 127.0.0.1:${STAGE_PGB_PORT} (transaction mode, pool_size=${PGBOUNCER_POOL_SIZE})"
REMOTE

ok "02-postgres 완료"
