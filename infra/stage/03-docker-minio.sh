#!/usr/bin/env bash
# ============================================================
# 03 — Docker Engine / Compose + MinIO
# ============================================================
# · Docker CE + compose plugin
# · coolsistema_network (운영과 동일한 external 네트워크명 — compose 파일이 이 이름을 요구)
# · 컨테이너 로그 로테이션 (없으면 json 로그가 디스크를 채운다)
# · MinIO (S3 호환 파일 저장) — localhost 바인딩, nginx 뒤에서만 노출
# ============================================================
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_config

log "Docker + MinIO 설치: ${STAGE_HOST}"

stage_ssh "bash -s" <<REMOTE
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "── Docker 저장소 ──"
install -m 0755 -d /etc/apt/keyrings
. /etc/os-release
curl -fsSL https://download.docker.com/linux/\${ID}/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/\${ID} \${VERSION_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -qq

echo "── Docker CE ──"
apt-get install -y -qq \
  docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

echo "── 데몬 설정 (로그 로테이션 필수) ──"
# 기본 json-file 드라이버는 무제한으로 자란다. 스테이지에서 디스크 풀 나면
# 원인 파악에 쓸 로그부터 사라지므로 반드시 제한을 건다.
cat > /etc/docker/daemon.json <<'DJSON'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "50m", "max-file": "5" },
  "live-restore": true,
  "default-address-pools": [{ "base": "172.30.0.0/16", "size": 24 }]
}
DJSON
systemctl enable docker
systemctl restart docker

usermod -aG docker "${STAGE_DEPLOY_USER}" || true

echo "── 외부 네트워크 coolsistema_network ──"
docker network inspect coolsistema_network >/dev/null 2>&1 \
  || docker network create coolsistema_network
docker network ls | grep coolsistema

echo "── MinIO ──"
install -d -m 755 /var/lib/minio-stage/data
cat > /etc/minio-stage.env <<MENV
MINIO_ROOT_USER=${MINIO_ROOT_USER}
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}
MENV
chmod 600 /etc/minio-stage.env

cat > /root/minio-compose.yml <<'MCOMPOSE'
services:
  minio:
    image: minio/minio:latest
    container_name: minio_stage
    restart: always
    command: server /data --console-address ":9001"
    env_file:
      - /etc/minio-stage.env
    ports:
      # ★ localhost 바인딩. 외부 접근은 nginx(TLS) 를 통해서만.
      - "127.0.0.1:9000:9000"
      - "127.0.0.1:9001:9001"
    volumes:
      - /var/lib/minio-stage/data:/data
    healthcheck:
      test: ["CMD", "mc", "ready", "local"]
      interval: 30s
      timeout: 5s
      retries: 3
    networks:
      - coolsistema_network

networks:
  coolsistema_network:
    external: true
MCOMPOSE

docker compose -f /root/minio-compose.yml up -d
sleep 8

echo "── 버킷 생성: ${MINIO_BUCKET} ──"
docker run --rm --network coolsistema_network --entrypoint sh minio/mc:latest -c "
  mc alias set stage http://minio_stage:9000 '${MINIO_ROOT_USER}' '${MINIO_ROOT_PASSWORD}' &&
  mc mb --ignore-existing stage/${MINIO_BUCKET} &&
  mc anonymous set download stage/${MINIO_BUCKET} &&
  mc ls stage
"

echo
echo "✓ Docker + MinIO 완료"
docker --version
docker compose version
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
REMOTE

ok "03-docker-minio 완료"
