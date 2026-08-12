#!/usr/bin/env bash
# ============================================================
# 05 — 앱 배포 (api-ventago + ventago-app + Redis)
# ============================================================
# · repo clone / pull
# · .env 생성 (★ 스테이지 전용 시크릿. 운영 값 재사용 금지)
# · docker compose build && up
#
# 커넥션 예산은 00-config.env 의 값이 그대로 컨테이너 env 로 들어간다.
# ecosystem.config.js 가 API_WORKERS / PGBOUNCER_POOL_SIZE / API_REPLICA_COUNT 를 읽어
# 부팅 로그에 예산을 찍으므로, 배포 후 그 줄을 반드시 확인한다 (07-verify.sh 가 확인함).
# ============================================================
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_config
verify_connection_budget

# MinIO 접속 지점은 여기(로컬)에서 결정해 .env 로 내려보낸다.
# 아래 heredoc 은 원격에서 실행되지만 변수는 로컬 쉘이 먼저 치환하므로,
# .env 파일 안에 조건식을 남기면 리터럴 문자열이 되어버린다.
if [[ -n "${DOMAIN_MINIO}" ]]; then
  MINIO_HOST_RESOLVED="${DOMAIN_MINIO}"   # nginx(TLS) 경유
  MINIO_PORT_RESOLVED=443
else
  MINIO_HOST_RESOLVED="minio_stage"       # 도커 네트워크 내부 직결 (기본)
  MINIO_PORT_RESOLVED=9000
fi
log "MinIO 접속 지점: ${MINIO_HOST_RESOLVED}:${MINIO_PORT_RESOLVED}"

log "앱 배포: ${STAGE_HOST}"

stage_ssh "bash -s" <<REMOTE
set -Eeuo pipefail

DEPLOY_DIR="${DEPLOY_DIR}"

echo "── 저장소 준비 ──"
if [ ! -d "\$DEPLOY_DIR/.git" ]; then
  install -d -o ${STAGE_DEPLOY_USER} -g ${STAGE_DEPLOY_USER} "\$(dirname \$DEPLOY_DIR)"
  git clone --branch ${REPO_BRANCH} ${REPO_URL} "\$DEPLOY_DIR"
else
  cd "\$DEPLOY_DIR"
  git fetch origin ${REPO_BRANCH}
  git reset --hard origin/${REPO_BRANCH}
fi
cd "\$DEPLOY_DIR"
git log -1 --oneline

echo "── api-ventago/.env 생성 ──"
cat > "\$DEPLOY_DIR/api-ventago/.env" <<ENVFILE
NODE_ENV=production
PORT=${API_PORT}

# ── DB: 앱은 pgbouncer(${STAGE_PGB_PORT}) 를 경유한다. PG(${STAGE_PG_PORT}) 직결 금지 ──
# 컨테이너에서 호스트 로컬 서비스로 나가는 경로. daemon.json 의 주소풀과 무관하게
# host-gateway 로 고정한다.
DATABASE_HOST=host.docker.internal
DATABASE_PORT=${STAGE_PGB_PORT}
DATABASE_NAME=${STAGE_DB_NAME}
DATABASE_USER=${STAGE_DB_OWNER}
DATABASE_PASSWORD=${STAGE_DB_OWNER_PASSWORD}
DATABASE_TZ=-03:00

# ── 공개몰 읽기 전용 커넥션 ──
# ventago 만 테스트하므로 공개몰 트래픽은 없다. 최소값으로 둔다.
SHOP_DB_USER=shop_readonly
SHOP_DB_PASSWORD=${STAGE_SHOP_RO_PASSWORD}
SHOP_DB_POOL_MAX=${SHOP_DB_POOL_MAX}
# 같은 PG 인스턴스이므로 false. true 로 선언하면 앱이 설정 오류를 감지해
# 경고를 찍고 폴백한다 (shop-readonly-db.service.ts 의 contradiction 판정).
SHOP_DB_ISOLATED=false

# ── 커넥션 예산 (부팅 로그에 그대로 찍힌다) ──
API_WORKERS=${API_WORKERS}
API_REPLICA_COUNT=${API_REPLICA_COUNT}
PGBOUNCER_POOL_SIZE=${PGBOUNCER_POOL_SIZE}

# ── 시크릿 (스테이지 전용) ──
JWT_SECRET_KEY=${JWT_SECRET_KEY}

# ── MinIO ──
# 전용 도메인을 두지 않는다. 프론트가 이미지 URL 을 {API_HOST}/minio/{fileName} 로
# 만들어 API 를 경유하므로, API 컨테이너가 도커 네트워크 안에서 직접 붙으면 된다.
MINIO_HOST=${MINIO_HOST_RESOLVED}
MINIO_PORT=${MINIO_PORT_RESOLVED}
MINIO_BUCKET=${MINIO_BUCKET}
MINIO_ACCESS_KEY=${MINIO_ROOT_USER}
MINIO_SECRET_KEY=${MINIO_ROOT_PASSWORD}

# ── Redis (socket.io 어댑터 + rate-limit 공유 저장소) ──
# ★ 스테이지 전용 인스턴스. 운영 ventago_redis 를 재사용하면 socket.io 채널이 겹쳐
#   스테이지 판매의 print 이벤트가 운영 print-agent 로 나간다.
REDIS_HOST=ventago_redis_stage
REDIS_PORT=6379
REDIS_PASSWORD=${REDIS_PASSWORD}

# ══════════════════════════════════════════════════════════
#  안전 스위치 — 운영 데이터를 복제했으므로 절대 켜지 말 것
# ══════════════════════════════════════════════════════════
# 캠페인 발송 / sync_outbox 워커 / 예약 작업 전면 정지.
# 켜면 실제 고객에게 WhatsApp·이메일이 나가고 운영 쇼핑몰로 재고가 밀린다.
CRON_ENABLED=${CRON_ENABLED}

# OTP 채널 미설정 — 스킵 허용(스테이지 가입 테스트용).
# 운영에서는 절대 true 로 두지 않는다.
EMAIL_API_URL=
EMAIL_API_KEY=
EMAIL_FROM=
WHATSAPP_TOKEN=
WHATSAPP_PHONE_ID=
ONBOARDING_ALLOW_OTP_SKIP=true

# Telegram 알림 비활성
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=

# Mercadopago — sandbox 자격증명만 넣는다. 운영 client id/secret 금지.
MP_PRODUCTION_CLIENT_ID=
MP_PRODUCTION_CLIENT_SECRET=
MP_SANDBOX_CLIENT_ID=
MP_SANDBOX_CLIENT_SECRET=
MP_TOKEN_ENCRYPTION_KEY=${MP_TOKEN_ENCRYPTION_KEY}
MP_OAUTH_STATE_SECRET=${MP_OAUTH_STATE_SECRET}
MP_WEBHOOK_SECRET=${MP_WEBHOOK_SECRET}
# 웹훅 복귀 URL 을 스테이지로 고정 — 운영 URL 이 남아 있으면 스테이지 결제 콜백이
# 운영 서버로 들어간다.
MP_NOTIFICATION_BASE_URL=https://${DOMAIN_API}/api

# 공개몰
SHOP_FRONTEND_URL=https://${DOMAIN_APP}
SHOP_CURRENCY_ID=ARS

# 테넌트 격리 — 운영과 동일하게 enforce 로 둔다 (스테이지에서 회귀를 잡기 위함)
TENANT_GUARD_MODE=enforce
TENANT_DERIVED_MODE=enforce
ENVFILE
chmod 600 "\$DEPLOY_DIR/api-ventago/.env"

echo "── ventago-app/.env 생성 ──"
cat > "\$DEPLOY_DIR/ventago-app/.env" <<ENVFILE
NODE_ENV=production
NEXT_PUBLIC_API_HOST=https://${DOMAIN_API}/api
NEXT_PUBLIC_APP_ENV=stage
ENVFILE
chmod 600 "\$DEPLOY_DIR/ventago-app/.env"

echo "── compose override (스테이지 전용) ──"
# 운영 compose 를 수정하지 않고 override 로 얹는다.
#  · Redis 컨테이너명 분리 (운영 채널과 격리)
#  · 포트를 localhost 로만 바인딩 (nginx 뒤)
#  · host.docker.internal 로 호스트 pgbouncer 도달
cat > "\$DEPLOY_DIR/api-ventago/docker-compose.override.yml" <<'OVERRIDE'
services:
  apiventago:
    container_name: api_ventago_stage
    ports: !override
      - "127.0.0.1:5002:5002"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    depends_on:
      redis:
        condition: service_healthy

  redis:
    container_name: ventago_redis_stage
OVERRIDE

cat > "\$DEPLOY_DIR/ventago-app/docker-compose.override.yml" <<'OVERRIDE'
services:
  ventagoapp:
    container_name: ventagoapp_stage
    ports: !override
      - "127.0.0.1:5001:3000"
OVERRIDE

echo "── 필수 마운트 경로 ──"
install -d "\$DEPLOY_DIR/certificados"
install -d /var/lib/ventago-logs/api /var/lib/ventago-logs/app

echo "── 백엔드 빌드 & 기동 ──"
cd "\$DEPLOY_DIR/api-ventago"
docker compose build
docker compose up -d
sleep 20

echo "── 프론트 빌드 & 기동 ──"
cd "\$DEPLOY_DIR/ventago-app"
docker compose build
docker compose up -d
sleep 10

echo "── 컨테이너 상태 ──"
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

echo
echo "── 백엔드 부팅 로그 (커넥션 예산 확인) ──"
docker logs api_ventago_stage 2>&1 | grep -iE "budget|예산|pool|listening|connected" | tail -20 || true
REMOTE

ok "05-deploy 완료"
