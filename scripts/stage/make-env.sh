#!/usr/bin/env bash
# [2026-10-22] Arma /opt/stage/api.env desde el de standby, SACANDO lo que habla con el mundo y
#   apuntando a la base/redis/minio de stage. Correr en 운용3 como root. Idempotente.
set -euo pipefail
SRC=/opt/ventago/api.env; DST=/opt/stage/api.env
. /opt/stage/db.env
[ -f /opt/stage/minio.env ] || { echo "MINIO_ROOT_USER=stage"; echo "MINIO_ROOT_PASSWORD=$(openssl rand -hex 20)"; } > /opt/stage/minio.env
. /opt/stage/minio.env
REDIS_PW=$(grep -E '^REDIS_PASSWORD=' "$DST" 2>/dev/null | cut -d= -f2- || true); REDIS_PW=${REDIS_PW:-$(openssl rand -hex 16)}
# fuera: telegram, email, try-on pago, base «shop», certificados, y todo lo que reescribimos abajo
grep -vE '^(TELEGRAM_|EMAIL_|AFIP_CERT_ALERT_EMAIL|FASHN_|TRYON_|SHOP_DB_|AFIP_CERTS_DIR|DATABASE_|DB_|REDIS_|MINIO_|PORT=|OLLAMA_|LLM_)' "$SRC" > "$DST.tmp"
cat >> "$DST.tmp" <<EOV
# ---- stage ----
PORT=5102
DATABASE_HOST=127.0.0.1
DATABASE_PORT=5435
DATABASE_NAME=ventago
DATABASE_USER=coolsistema
DATABASE_PASSWORD=$STAGE_DB_PASSWORD
DB_HOST=127.0.0.1
DB_PORT=5435
DB_NAME=ventago
DB_USER=coolsistema
DB_PASSWORD=$STAGE_DB_PASSWORD
REDIS_HOST=127.0.0.1
REDIS_PORT=6380
REDIS_PASSWORD=$REDIS_PW
MINIO_HOST=stageminio.coolsistema.com
MINIO_PORT=443
MINIO_BUCKET=coolsistema
MINIO_ACCESS_KEY=$MINIO_ROOT_USER
MINIO_SECRET_KEY=$MINIO_ROOT_PASSWORD
AFIP_CERTS_DIR=/app/certificates-stage-vacio
AFIP_CERTS_DIR_VENTAGO=/app/certificates-stage-vacio
LLM_PROVIDER=none
# stage: 2 workers (producción 4) — 운용3 tiene 8 GB
API_WORKERS=2
EOV
install -m 600 "$DST.tmp" "$DST"; rm -f "$DST.tmp"
cp /opt/ventago/app.env /opt/stage/app.env; chmod 600 /opt/stage/app.env /opt/stage/minio.env
mkdir -p /opt/stage/logs/api /opt/stage/minio
echo "api.env: $(grep -c . "$DST") líneas · fuera: $(grep -cE '^(TELEGRAM_|EMAIL_|FASHN_)' "$DST" || true) variables de salida"
