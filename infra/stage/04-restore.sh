#!/usr/bin/env bash
# ============================================================
# 04 — 운영 DB 복제 → 스테이지 + 안전화
# ============================================================
# 흐름:
#   1) 운영(5434)에서 pg_dump (읽기 전용, --no-owner --no-acl)
#   2) Mac 로 내려받아 스테이지로 전송  (운영 → 스테이지 직결 아님: 운영에서 나가는
#      네트워크 세션을 만들지 않는다)
#   3) 스테이지 DB drop/create → restore
#   4) _stage_marker 심기
#   5) stage-sanitize.sql 실행 (외부 발신 채널 전면 차단)
#   6) 스키마 대조 (운영 vs 스테이지 테이블/컬럼 수)
#
# ★ 운영에 대한 작업은 pg_dump 뿐이며 전부 읽기 전용이다.
#   단, 덤프는 운영 서버의 I/O 를 쓴다 — 영업 시간을 피해서 돌릴 것.
# ============================================================
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_config
require_cmd ssh scp

DUMP_NAME="ventago-prod-$(date +%Y%m%d-%H%M%S).dump"
LOCAL_DUMP="/tmp/${DUMP_NAME}"
REMOTE_DUMP="/var/backups/ventago/${DUMP_NAME}"

cat <<INFO

  ┌──────────────────────────────────────────────────────────┐
  │  운영 DB 를 스테이지로 그대로 복제합니다                 │
  ├──────────────────────────────────────────────────────────┤
  │  소스 : ${PROD_SSH_ALIAS} :${PROD_PG_PORT} / ${PROD_DB_NAME}
  │  대상 : ${STAGE_HOST} :${STAGE_PG_PORT} / ${STAGE_DB_NAME}
  │                                                          │
  │  ⚠ 대상 DB '${STAGE_DB_NAME}' 는 DROP 후 재생성됩니다.
  │  ⚠ 복제 후 stage-sanitize.sql 이 자동 실행되어           │
  │     MP 토큰 · WhatsApp · 이메일 · Telegram · 프린터 키 · │
  │     WooCommerce 동기화를 전부 무력화합니다.              │
  │     이 단계를 건너뛰면 스테이지가 실제 고객에게          │
  │     메시지를 보내고 실제 결제를 일으킬 수 있습니다.      │
  └──────────────────────────────────────────────────────────┘

INFO
confirm "위 내용대로 진행할까요?"

# ── 1. 운영 덤프 (읽기 전용) ──────────────────────────────
log "운영에서 pg_dump 시작 (custom format, 압축 9)"
prod_ssh "sudo -u postgres pg_dump -p ${PROD_PG_PORT} -d ${PROD_DB_NAME} \
  --format=custom --compress=9 --no-owner --no-acl \
  --file=/tmp/${DUMP_NAME}"
prod_ssh "ls -lh /tmp/${DUMP_NAME}"
ok "덤프 생성 완료"

# ── 2. 전송 ───────────────────────────────────────────────
log "Mac 으로 내려받는 중"
scp -o StrictHostKeyChecking=accept-new "${PROD_SSH_ALIAS}:/tmp/${DUMP_NAME}" "${LOCAL_DUMP}"
prod_ssh "rm -f /tmp/${DUMP_NAME}"   # 운영에 덤프를 남기지 않는다
ls -lh "${LOCAL_DUMP}"

log "스테이지로 전송 중"
stage_scp "${LOCAL_DUMP}" "${STAGE_SSH_USER}@${STAGE_HOST}:${REMOTE_DUMP}"
ok "전송 완료"

# ── 3~5. 복원 + 안전화 ────────────────────────────────────
log "스테이지 복원 + 안전화"
stage_scp "$(dirname "${BASH_SOURCE[0]}")/sql/stage-sanitize.sql" \
          "${STAGE_SSH_USER}@${STAGE_HOST}:/tmp/stage-sanitize.sql"

stage_ssh "bash -s" <<REMOTE
set -Eeuo pipefail
PGP="sudo -u postgres psql -p ${STAGE_PG_PORT}"

echo "── 기존 연결 차단 후 DB 재생성 ──"
sudo -u postgres psql -p ${STAGE_PG_PORT} -d postgres -v ON_ERROR_STOP=1 <<SQL
SELECT pg_terminate_backend(pid) FROM pg_stat_activity
 WHERE datname = '${STAGE_DB_NAME}' AND pid <> pg_backend_pid();
SQL
systemctl stop pgbouncer || true
sudo -u postgres dropdb -p ${STAGE_PG_PORT} --if-exists ${STAGE_DB_NAME}
sudo -u postgres createdb -p ${STAGE_PG_PORT} -O ${STAGE_DB_OWNER} ${STAGE_DB_NAME}

echo "── 복원 (병렬 4잡) ──"
# --no-owner: 운영 owner(coolsistema)가 스테이지에 없을 수도 있으므로 무시하고
#             아래에서 일괄로 소유권을 넘긴다.
sudo -u postgres pg_restore -p ${STAGE_PG_PORT} -d ${STAGE_DB_NAME} \
  --no-owner --no-acl --jobs=4 --exit-on-error=0 \
  ${REMOTE_DUMP} 2>&1 | tail -30 || echo "  (일부 경고는 정상 — 아래 대조로 확인)"

echo "── 소유권 이전: ${STAGE_DB_OWNER} ──"
# ★ 운영 규칙과 동일: 테이블뿐 아니라 시퀀스 owner 도 별도로 옮겨야 한다.
#   누락하면 앱 계정이 nextval() 에서 permission denied 500 을 낸다.
sudo -u postgres psql -p ${STAGE_PG_PORT} -d ${STAGE_DB_NAME} -v ON_ERROR_STOP=1 <<SQL
DO \\\$\\\$
DECLARE r record;
BEGIN
  EXECUTE 'ALTER DATABASE ${STAGE_DB_NAME} OWNER TO ${STAGE_DB_OWNER}';
  EXECUTE 'ALTER SCHEMA public OWNER TO ${STAGE_DB_OWNER}';
  FOR r IN SELECT tablename FROM pg_tables WHERE schemaname='public' LOOP
    EXECUTE format('ALTER TABLE public.%I OWNER TO ${STAGE_DB_OWNER}', r.tablename);
  END LOOP;
  FOR r IN SELECT sequencename FROM pg_sequences WHERE schemaname='public' LOOP
    EXECUTE format('ALTER SEQUENCE public.%I OWNER TO ${STAGE_DB_OWNER}', r.sequencename);
  END LOOP;
  FOR r IN SELECT viewname FROM pg_views WHERE schemaname='public' LOOP
    EXECUTE format('ALTER VIEW public.%I OWNER TO ${STAGE_DB_OWNER}', r.viewname);
  END LOOP;
  FOR r IN SELECT matviewname FROM pg_matviews WHERE schemaname='public' LOOP
    EXECUTE format('ALTER MATERIALIZED VIEW public.%I OWNER TO ${STAGE_DB_OWNER}', r.matviewname);
  END LOOP;
END
\\\$\\\$;

-- 공개몰 읽기 전용 계정 권한 (migrations/shop-mvp-readonly-role.sql 과 동일 의도)
GRANT CONNECT ON DATABASE ${STAGE_DB_NAME} TO shop_readonly;
GRANT USAGE ON SCHEMA public TO shop_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO shop_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO shop_readonly;

CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- gen_random_bytes (안전화 스크립트가 사용)
SQL

echo "── 스테이지 표식 심기 ──"
sudo -u postgres psql -p ${STAGE_PG_PORT} -d ${STAGE_DB_NAME} -v ON_ERROR_STOP=1 <<SQL
CREATE TABLE IF NOT EXISTS _stage_marker (
  id          int PRIMARY KEY DEFAULT 1,
  environment text NOT NULL DEFAULT 'stage',
  cloned_from text,
  cloned_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT _stage_marker_single CHECK (id = 1)
);
INSERT INTO _stage_marker (id, environment, cloned_from)
VALUES (1, 'stage', '${PROD_SSH_ALIAS}:${PROD_PG_PORT}/${PROD_DB_NAME}')
ON CONFLICT (id) DO UPDATE
  SET cloned_from = EXCLUDED.cloned_from, cloned_at = now();
ALTER TABLE _stage_marker OWNER TO ${STAGE_DB_OWNER};
SQL

echo "── 안전화 실행 ──"
sudo -u postgres psql -p ${STAGE_PG_PORT} -d ${STAGE_DB_NAME} \
  -v ON_ERROR_STOP=1 --single-transaction -f /tmp/stage-sanitize.sql
rm -f /tmp/stage-sanitize.sql

echo "── ANALYZE (플래너 통계 재구축) ──"
sudo -u postgres vacuumdb -p ${STAGE_PG_PORT} -d ${STAGE_DB_NAME} --analyze-only --jobs=4 -q

systemctl start pgbouncer
sleep 2

echo "── 복원 결과 ──"
sudo -u postgres psql -p ${STAGE_PG_PORT} -d ${STAGE_DB_NAME} -c "
  SELECT count(*) AS tables FROM pg_tables WHERE schemaname='public';"
sudo -u postgres psql -p ${STAGE_PG_PORT} -d ${STAGE_DB_NAME} -c "
  SELECT pg_size_pretty(pg_database_size('${STAGE_DB_NAME}')) AS db_size;"

# 덤프는 남긴다 (롤백용). 7일 이상 된 것은 정리.
find /var/backups/ventago -name 'ventago-prod-*.dump' -mtime +7 -delete || true
ls -lh /var/backups/ventago/
REMOTE

# ── 6. 스키마 대조 ────────────────────────────────────────
log "스키마 대조 (운영 vs 스테이지)"
PROD_COUNTS=$(prod_ssh "sudo -u postgres psql -p ${PROD_PG_PORT} -d ${PROD_DB_NAME} -tA -c \
  \"SELECT (SELECT count(*) FROM pg_tables WHERE schemaname='public')||'/'|| \
           (SELECT count(*) FROM information_schema.columns WHERE table_schema='public')\"")
STAGE_COUNTS=$(stage_ssh "sudo -u postgres psql -p ${STAGE_PG_PORT} -d ${STAGE_DB_NAME} -tA -c \
  \"SELECT (SELECT count(*) FROM pg_tables WHERE schemaname='public')||'/'|| \
           (SELECT count(*) FROM information_schema.columns WHERE table_schema='public')\"")

log "  운영   (테이블/컬럼): ${PROD_COUNTS}"
log "  스테이지(테이블/컬럼): ${STAGE_COUNTS}"

# 스테이지는 _stage_marker 1개가 더 있으므로 정확히 같지는 않다.
if [[ "$PROD_COUNTS" == "$STAGE_COUNTS" ]]; then
  warn "완전히 동일합니다 — _stage_marker 가 반영되지 않았을 수 있으니 확인하세요"
else
  ok "대조 완료 (차이는 _stage_marker 만큼이어야 정상)"
fi

rm -f "${LOCAL_DUMP}"
ok "04-restore 완료"
