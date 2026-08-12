#!/usr/bin/env bash
# ============================================================
# 06 — nginx 리버스 프록시 + Let's Encrypt
# ============================================================
# 전제: DNS A 레코드가 이미 STAGE_HOST 를 가리키고 있어야 한다.
#       (certbot HTTP-01 챌린지가 실패하는 원인 1순위)
#
# 구성:
#   ${DOMAIN_APP}   → 127.0.0.1:${APP_PORT}   (Next.js)
#   ${DOMAIN_API}   → 127.0.0.1:${API_PORT}   (NestJS, WebSocket 업그레이드 포함)
#   ${DOMAIN_MINIO} → 127.0.0.1:9000          (MinIO, 선택)
#
# 스테이지이므로 robots noindex + basic auth 옵션을 넣어둔다.
# ============================================================
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_config

log "DNS 확인"
for d in "${DOMAIN_APP}" "${DOMAIN_API}" ${DOMAIN_MINIO:+"${DOMAIN_MINIO}"}; do
  resolved=$(dig +short "$d" A | tail -1)
  if [[ "$resolved" == "${STAGE_HOST}" ]]; then
    ok "  $d → $resolved"
  else
    die "$d 가 ${STAGE_HOST} 로 해석되지 않습니다 (현재: ${resolved:-없음}). DNS A 레코드를 먼저 설정하세요."
  fi
done

stage_ssh "bash -s" <<REMOTE
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "── nginx + certbot 설치 ──"
apt-get install -y -qq nginx certbot python3-certbot-nginx apache2-utils

echo "── 공통 프록시 파라미터 ──"
cat > /etc/nginx/snippets/ventago-proxy.conf <<'SNIP'
proxy_http_version 1.1;
proxy_set_header Host              \$host;
proxy_set_header X-Real-IP         \$remote_addr;
proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto \$scheme;

# WebSocket 업그레이드 (socket.io — print-agent / zebra-agent / 프론트 실시간)
proxy_set_header Upgrade    \$http_upgrade;
proxy_set_header Connection \$connection_upgrade;

proxy_connect_timeout 10s;
proxy_send_timeout    120s;
proxy_read_timeout    120s;
proxy_buffering off;
SNIP

cat > /etc/nginx/conf.d/ventago-upgrade-map.conf <<'MAP'
map \$http_upgrade \$connection_upgrade {
  default upgrade;
  ''      close;
}
MAP

echo "── 스테이지 접근 제한용 basic auth 계정 ──"
# 검색엔진/외부인 유입을 막는다. 앱 로그인과 별개의 1차 관문.
# 계정: stage / 비밀번호는 아래 출력 참조
if [ ! -f /etc/nginx/.htpasswd-stage ]; then
  STAGE_BASIC_PW=\$(openssl rand -base64 18)
  htpasswd -bc /etc/nginx/.htpasswd-stage stage "\$STAGE_BASIC_PW" >/dev/null 2>&1
  echo "\$STAGE_BASIC_PW" > /root/.stage-basic-auth-password
  chmod 600 /root/.stage-basic-auth-password
  echo "  basic auth 생성 — user: stage / pass: \$STAGE_BASIC_PW"
  echo "  (재확인: cat /root/.stage-basic-auth-password)"
else
  echo "  이미 존재 — 스킵"
fi

echo "── 사이트 설정 (우선 HTTP. certbot 이 443 을 붙인다) ──"

# 프론트
cat > /etc/nginx/sites-available/${DOMAIN_APP} <<SITE
server {
    listen 80;
    server_name ${DOMAIN_APP};

    # 스테이지는 색인되면 안 된다
    add_header X-Robots-Tag "noindex, nofollow, noarchive" always;
    location = /robots.txt { return 200 "User-agent: *\\nDisallow: /\\n"; }

    location /.well-known/acme-challenge/ { root /var/www/html; auth_basic off; }

    location / {
        auth_basic "Ventago Stage";
        auth_basic_user_file /etc/nginx/.htpasswd-stage;
        proxy_pass http://127.0.0.1:${APP_PORT};
        include /etc/nginx/snippets/ventago-proxy.conf;
    }
}
SITE

# 백엔드
cat > /etc/nginx/sites-available/${DOMAIN_API} <<SITE
server {
    listen 80;
    server_name ${DOMAIN_API};

    client_max_body_size 60m;   # 파일 업로드 (SHARED_FOLDERS_MAX_UPLOAD_MB=50 + 여유)
    add_header X-Robots-Tag "noindex, nofollow" always;

    location /.well-known/acme-challenge/ { root /var/www/html; }

    # ★ API 에는 basic auth 를 걸지 않는다.
    #   걸면 print-agent / zebra-agent 의 socket.io 연결과 MP 웹훅이 401 로 막힌다.
    location / {
        proxy_pass http://127.0.0.1:${API_PORT};
        include /etc/nginx/snippets/ventago-proxy.conf;
    }
}
SITE

ln -sf /etc/nginx/sites-available/${DOMAIN_APP} /etc/nginx/sites-enabled/
ln -sf /etc/nginx/sites-available/${DOMAIN_API} /etc/nginx/sites-enabled/

if [ -n "${DOMAIN_MINIO}" ]; then
cat > /etc/nginx/sites-available/${DOMAIN_MINIO} <<SITE
server {
    listen 80;
    server_name ${DOMAIN_MINIO};
    client_max_body_size 200m;
    add_header X-Robots-Tag "noindex, nofollow" always;
    location /.well-known/acme-challenge/ { root /var/www/html; }
    location / {
        proxy_pass http://127.0.0.1:9000;
        include /etc/nginx/snippets/ventago-proxy.conf;
    }
}
SITE
ln -sf /etc/nginx/sites-available/${DOMAIN_MINIO} /etc/nginx/sites-enabled/
fi

rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable nginx
systemctl reload nginx

echo "── Let's Encrypt 발급 ──"
# ★ set -e 하에서 `[ -n "" ] && VAR=...` 는 종료코드 1 을 반환해 스크립트를 죽인다.
#   DOMAIN_MINIO 를 비워두는 것이 기본 구성(ventago 만 테스트)이므로 if 문으로 쓴다.
DOMAIN_ARGS="-d ${DOMAIN_APP} -d ${DOMAIN_API}"
if [ -n "${DOMAIN_MINIO}" ]; then
  DOMAIN_ARGS="\$DOMAIN_ARGS -d ${DOMAIN_MINIO}"
fi

certbot --nginx \$DOMAIN_ARGS \
  --non-interactive --agree-tos \
  --email ${LETSENCRYPT_EMAIL} \
  --redirect --keep-until-expiring

echo "── 자동 갱신 확인 ──"
systemctl list-timers | grep -i certbot || true
certbot renew --dry-run

nginx -t && systemctl reload nginx

echo
echo "✓ nginx + SSL 완료"
echo "  https://${DOMAIN_APP}   (basic auth: stage / \$(cat /root/.stage-basic-auth-password 2>/dev/null))"
echo "  https://${DOMAIN_API}/api/health"
if [ -n "${DOMAIN_MINIO}" ]; then
  echo "  https://${DOMAIN_MINIO}"
fi
REMOTE

ok "06-nginx-ssl 완료"
