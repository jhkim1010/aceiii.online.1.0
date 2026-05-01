#!/usr/bin/env bash
# =============================================================================
# 운영서버 배포 상태 상세 점검
# =============================================================================
# 운영 구조: Jenkins → docker image → docker compose up
# 운영서버에는 ventago-app git repo 가 없으므로,
# 도커 이미지 빌드 시각 + 컨테이너 시작 시각으로 배포 상태 추적.
# =============================================================================

set -e

SSH_HOST="jhkim-server"
APP_NAME="ventagoapp"
API_NAME="api_ventago"
COMPOSE_DIR="/home/coolsistema/projects/api-ventago"

echo "==============================================================="
echo "[1/5] SSH 연결 + 호스트 정보"
echo "==============================================================="
ssh -o ConnectTimeout=5 "$SSH_HOST" "echo '✅ SSH OK on:' && hostname && uptime"
echo

echo "==============================================================="
echo "[2/5] 실행 중 ventago/api 컨테이너"
echo "==============================================================="
ssh "$SSH_HOST" "sudo docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.RunningFor}}' | grep -E '$APP_NAME|$API_NAME|NAMES'"
echo

echo "==============================================================="
echo "[3/5] 컨테이너 시작 시각 (= 마지막 docker compose up 시각)"
echo "==============================================================="
ssh "$SSH_HOST" "sudo docker inspect $APP_NAME --format '  $APP_NAME StartedAt : {{.State.StartedAt}}'
sudo docker inspect $API_NAME --format '  $API_NAME StartedAt : {{.State.StartedAt}}'"
echo

echo "==============================================================="
echo "[4/5] 이미지 Created 시각 (= Jenkins 빌드 성공 시각)"
echo "==============================================================="
ssh "$SSH_HOST" bash <<EOF
APP_IMG=\$(sudo docker inspect $APP_NAME --format '{{.Image}}')
API_IMG=\$(sudo docker inspect $API_NAME --format '{{.Image}}')
echo "  $APP_NAME 이미지 :"
sudo docker inspect "\$APP_IMG" --format '    Created : {{.Created}}
    ID      : {{.Id}}'
echo
echo "  $API_NAME 이미지 :"
sudo docker inspect "\$API_IMG" --format '    Created : {{.Created}}
    ID      : {{.Id}}'
EOF
echo

echo "==============================================================="
echo "[5/5] 컨테이너 안 .next/BUILD_ID + 마지막 로그"
echo "==============================================================="
ssh "$SSH_HOST" bash <<EOF
echo "▶ $APP_NAME .next/BUILD_ID 검색"
sudo docker exec $APP_NAME sh -c '
  for D in /app /usr/src/app /opt/app /workspace; do
    if [ -f "\$D/.next/BUILD_ID" ]; then
      echo "    ✅ \$D/.next/BUILD_ID = \$(cat \$D/.next/BUILD_ID)"
      stat -c "       built : %y" "\$D/.next/BUILD_ID"
    fi
  done
  if [ -d /app/.next/standalone ]; then
    echo "    ℹ standalone 모드 (.next/standalone 존재)"
  fi
' 2>/dev/null

echo
echo "▶ $APP_NAME 마지막 로그 20줄"
sudo docker logs --tail 20 $APP_NAME 2>&1 | sed 's/^/    /'

echo
echo "▶ $API_NAME 마지막 로그 10줄"
sudo docker logs --tail 10 $API_NAME 2>&1 | sed 's/^/    /'
EOF
echo

GITHUB_HEAD=$(git -C ~/Trabajos_Programming/ACE_online_1.0/ventago-app ls-remote origin main 2>/dev/null | awk '{print $1}' | head -c 12)
GITHUB_PUSH_TIME=$(git -C ~/Trabajos_Programming/ACE_online_1.0/ventago-app log -1 --pretty=format:'%ci' origin/main 2>/dev/null)
echo "==============================================================="
echo "📊 요약"
echo "==============================================================="
echo "  GitHub origin/main HEAD : ${GITHUB_HEAD:0:12}"
echo "  GitHub commit 시각      : $GITHUB_PUSH_TIME"
echo
echo "  → 위 'StartedAt' 가 GitHub commit 시각보다 늦으면 배포 OK."
echo "  → '이미지 Created' 가 GitHub commit 시각보다 빠르면 Jenkins 가 아직 새 빌드 못 만든 상태."
echo "==============================================================="
