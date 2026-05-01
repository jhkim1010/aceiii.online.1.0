#!/usr/bin/env bash
# =============================================================================
# 빠른 배포 상태 점검 (1회 SSH)
# =============================================================================
# 운영 구조:
#   - 운영서버에는 ventago-app git repo 가 없음
#   - Jenkins 가 자체 워크스페이스에서 빌드 → 도커 이미지로 배포
#   - 따라서 운영서버에서는 "도커 이미지 메타데이터" 와 "컨테이너 시작 시각" 으로 추적
#
# 출력:
#   - 컨테이너 시작 시각 (= 마지막 배포 시각)
#   - 컨테이너 이미지 ID + Created 시각 (= 마지막 빌드 성공 시각)
#   - GitHub origin/main HEAD (사용자 컴퓨터에서 조회)
# =============================================================================

set -e

SSH_HOST="jhkim-server"
APP_NAME="ventagoapp"
API_NAME="api_ventago"

GITHUB_HEAD=$(git -C ~/Trabajos_Programming/ACE_online_1.0/ventago-app ls-remote origin main 2>/dev/null | awk '{print $1}' | head -c 12)

ssh "$SSH_HOST" bash <<EOF
set -e
echo "🖥️  운영서버 : \$(hostname)   🕐 \$(date '+%Y-%m-%d %H:%M:%S')"
echo

echo "🐳 ventago 관련 컨테이너 상태"
sudo docker ps --filter "name=$APP_NAME" --filter "name=$API_NAME" \
  --format '   {{.Names}}\t {{.Status}}\t (image: {{.Image}})'
echo

echo "📅 프론트 컨테이너 시작 시각 (= 마지막 배포 시각)"
sudo docker inspect $APP_NAME --format '   StartedAt : {{.State.StartedAt}}
   Image     : {{.Image}}'
echo

echo "📦 프론트 이미지 빌드 시각 (= Jenkins 빌드 성공 시각)"
IMAGE_ID=\$(sudo docker inspect $APP_NAME --format '{{.Image}}')
sudo docker inspect "\$IMAGE_ID" --format '   Created   : {{.Created}}
   Image ID  : {{.Id}}' 2>/dev/null | head -2
echo

echo "🆔 .next 디렉토리 검색 (BUILD_ID)"
sudo docker exec $APP_NAME sh -c '
  for D in /app /usr/src/app /opt/app /workspace; do
    if [ -f "\$D/.next/BUILD_ID" ]; then
      echo "   ✅ \$D/.next/BUILD_ID = \$(cat \$D/.next/BUILD_ID)"
      stat -c "      built : %y" "\$D/.next/BUILD_ID"
    fi
  done
  if [ -d /app/.next/standalone ]; then
    echo "   ℹ standalone 모드 — /app/.next/standalone 존재"
  fi
' 2>/dev/null || echo "   ⚠ exec 실패"
echo

echo "📜 프론트 컨테이너 마지막 5줄 (구동 확인)"
sudo docker logs --tail 5 $APP_NAME 2>&1 | sed 's/^/   /'
EOF

echo
echo "🔁 GitHub origin/main HEAD : ${GITHUB_HEAD:0:12}"
echo
echo "👉 운영 컨테이너의 'StartedAt' 가 GitHub HEAD push 시각보다 늦으면 배포 OK"
echo "   '이미지 Created' 가 어제 날짜면 Jenkins 가 새 빌드를 만들지 못한 상태"
