#!/usr/bin/env bash
# [2026-10-22] STAGE: cuando los 3 A records apuntan a 운용3 → certificado + nginx 443 + bucket.
set -euo pipefail
IP=149.28.107.232
for h in stage stageapi stageminio; do
  r=$(dig +short "$h.coolsistema.com" @1.1.1.1 | tail -1)
  [ "$r" = "$IP" ] || { echo "✖ $h.coolsistema.com → ${r:-nada} (falta el A record a $IP)"; exit 1; }
done
ssh ventago-standby 'sudo certbot certonly --webroot -w /var/www/acme -n --agree-tos --register-unsafely-without-email \
  -d stage.coolsistema.com -d stageapi.coolsistema.com -d stageminio.coolsistema.com --deploy-hook "systemctl reload nginx"'
scp -q "$(dirname "$0")/nginx-stage.conf" ventago-standby:/tmp/stage.conf
ssh ventago-standby 'sudo install -m 644 /tmp/stage.conf /etc/nginx/conf.d/stage.conf && rm /tmp/stage.conf && sudo nginx -t && sudo systemctl reload nginx'
# bucket del minio de stage (el api lo espera con el mismo nombre que producción)
ssh ventago-standby 'sudo sh -c ". /opt/stage/minio.env; docker exec stage_minio sh -c \"mc alias set s http://127.0.0.1:9000 \$MINIO_ROOT_USER \$MINIO_ROOT_PASSWORD >/dev/null && mc mb -p s/coolsistema\""'
for u in https://stage.coolsistema.com/login/ https://stageapi.coolsistema.com/api/health; do echo "$u → $(curl -s -o /dev/null -w '%{http_code}' "$u")"; done
