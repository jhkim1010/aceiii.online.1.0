#!/usr/bin/env bash
# ============================================================
# 07 — 검증
# ============================================================
# 스테이지가 "떠 있다"가 아니라 "안전하게 떠 있다"를 확인한다.
# 실패 항목이 하나라도 있으면 종료 코드 1.
# ============================================================
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_config

FAILED=0
check() {
  local name="$1" result="$2"
  if [[ "$result" == "PASS" ]]; then ok "$name"; else warn "$name — FAIL"; FAILED=$((FAILED+1)); fi
}

log "═══ 스테이지 검증 시작 ═══"

# ── 1. HTTPS / 인증서 ─────────────────────────────────────
log "1. HTTPS"
for d in "${DOMAIN_APP}" "${DOMAIN_API}"; do
  code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "https://${d}/" || echo 000)
  # app 은 basic auth 라 401 이 정상, api 는 200/404
  if [[ "$code" =~ ^(200|301|302|401|404)$ ]]; then check "  https://${d} (HTTP ${code})" PASS
  else check "  https://${d} (HTTP ${code})" FAIL; fi

  exp=$(echo | openssl s_client -servername "$d" -connect "$d:443" 2>/dev/null \
        | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || echo "")
  [[ -n "$exp" ]] && log "     인증서 만료: $exp"
done

# ── 2. API health ─────────────────────────────────────────
log "2. API health (DB 도달성 포함)"
health=$(curl -sS --max-time 15 "https://${DOMAIN_API}/api/health" || echo "")
if echo "$health" | grep -qiE '"?(ok|up|healthy)"?'; then
  check "  /api/health" PASS
  echo "     $health" | head -c 300; echo
else
  check "  /api/health (응답: ${health:0:120})" FAIL
fi

# ── 3~7. 서버 내부 ────────────────────────────────────────
stage_ssh "bash -s" <<REMOTE
set -uo pipefail

echo
echo "3. 컨테이너"
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'stage|minio' || echo "  !! 컨테이너 없음"
UNHEALTHY=\$(docker ps --filter health=unhealthy --format '{{.Names}}')
[ -n "\$UNHEALTHY" ] && echo "  !! unhealthy: \$UNHEALTHY" || echo "  unhealthy 없음"

echo
echo "4. PostgreSQL 커넥션 예산 실측"
sudo -u postgres psql -p ${STAGE_PG_PORT} -d ${STAGE_DB_NAME} -x -c "
  SELECT
    current_setting('max_connections')            AS max_connections,
    (SELECT count(*) FROM pg_stat_activity)       AS total_backends,
    (SELECT count(*) FROM pg_stat_activity
      WHERE datname='${STAGE_DB_NAME}')           AS ventago_backends,
    (SELECT count(*) FROM pg_stat_activity
      WHERE datname='${STAGE_DB_NAME}' AND state='idle') AS idle,
    (SELECT count(*) FROM pg_stat_activity
      WHERE datname='${STAGE_DB_NAME}' AND state='idle in transaction') AS idle_in_tx;
"
# idle in transaction 이 쌓이면 pool 이 반납되지 않고 있다는 뜻 — 즉시 조사 대상.

echo "5. pgbouncer pool"
PGPASSWORD='${STAGE_DB_OWNER_PASSWORD}' psql -h 127.0.0.1 -p ${STAGE_PGB_PORT} \
  -U ${STAGE_DB_OWNER} -d pgbouncer -c 'SHOW POOLS;' 2>/dev/null \
  || echo "  (pgbouncer admin 조회 실패 — stats_users 확인)"

echo
echo "6. ★ 안전 스위치 (운영 데이터 복제 상태이므로 가장 중요) ★"
sudo -u postgres psql -p ${STAGE_PG_PORT} -d ${STAGE_DB_NAME} -t -A -F' | ' -c "
SELECT 'MP live token',        count(*) FROM mp_accounts WHERE access_token <> 'STAGE_DISABLED'
UNION ALL SELECT 'WooCommerce active',  count(*) FROM commerce_channels WHERE is_active
UNION ALL SELECT 'WP active',           count(*) FROM wp_channels WHERE is_active
UNION ALL SELECT 'outbox pending',      count(*) FROM sync_outbox WHERE status IN ('pending','processing')
UNION ALL SELECT 'WhatsApp active',     count(*) FROM store_whatsapp_config WHERE is_active
UNION ALL SELECT 'Telegram chat 남음',  count(*) FROM stores WHERE telegram_chat_id IS NOT NULL
UNION ALL SELECT 'email api key 남음',  count(*) FROM store_configs WHERE email_api_key_enc IS NOT NULL
UNION ALL SELECT 'campaign 예약중',     count(*) FROM campaigns WHERE scheduled_at IS NOT NULL
UNION ALL SELECT 'stripe key 남음',     count(*) FROM subscription_config WHERE stripe_secret_key IS NOT NULL;
"
echo "  ↑ 전부 0 이어야 합니다. 0 이 아니면 sql/stage-sanitize.sql 을 다시 실행하세요."

echo
echo "  스테이지 표식:"
sudo -u postgres psql -p ${STAGE_PG_PORT} -d ${STAGE_DB_NAME} -c 'SELECT * FROM _stage_marker;'

echo
echo "  앱 .env 안전 스위치:"
grep -E '^(CRON_ENABLED|MP_NOTIFICATION_BASE_URL|REDIS_HOST|TELEGRAM_BOT_TOKEN|EMAIL_API_KEY|WHATSAPP_TOKEN)=' \
  ${DEPLOY_DIR}/api-ventago/.env

echo
echo "7. 방화벽 (앱/DB 포트가 외부에 열려 있으면 안 된다)"
ufw status numbered | grep -E '5001|5002|5432|5434|9000|9001' \
  && echo "  !! 위험: 앱/DB 포트가 열려 있습니다" \
  || echo "  앱/DB 포트 외부 노출 없음"
ss -tlnp | grep -E ':(5001|5002|5432|5434|9000)\b' | grep -v '127.0.0.1' \
  && echo "  !! 위험: 0.0.0.0 바인딩 발견" \
  || echo "  전부 localhost 바인딩"

echo
echo "8. 디스크 / 메모리"
df -h / | tail -1
free -h | head -2
REMOTE

echo
if (( FAILED > 0 )); then
  die "검증 실패 ${FAILED}건 — 위 FAIL 항목을 확인하세요."
fi
ok "═══ 검증 통과 ═══"
cat <<SUMMARY

  스테이지 접속 정보
  ─────────────────────────────────────────────
  프론트  https://${DOMAIN_APP}
          basic auth → user: stage
          비밀번호   → ssh ${STAGE_SSH_USER}@${STAGE_HOST} 'cat /root/.stage-basic-auth-password'
  API     https://${DOMAIN_API}/api
  DB      ssh ${STAGE_SSH_USER}@${STAGE_HOST} "sudo -u postgres psql -p ${STAGE_PG_PORT} -d ${STAGE_DB_NAME}"

  로그인 계정은 운영과 동일합니다 (데이터 복제).
  새 IP·새 디바이스로 접속하면 지점/터미널 등록 모달이 뜨는 것이 정상입니다.

SUMMARY
