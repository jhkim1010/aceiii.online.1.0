#!/usr/bin/env bash
# =============================================================================
# 운영서버 경로 자동 탐지 — 한 번 SSH 로 모든 정보 수집
# =============================================================================
# 출력:
#   - 컨테이너 이름 + 이미지 + 상태
#   - 컨테이너 안의 작업 디렉토리 + Next.js .next/ 위치
#   - 호스트의 docker-compose.yml 경로
#   - 운영 git repo 경로 (있다면)
# =============================================================================

set -e

ssh jhkim-server bash <<'EOF'
echo "==============================================================="
echo "[A] 실행 중인 모든 컨테이너 (이름·이미지·상태)"
echo "==============================================================="
sudo docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' 2>/dev/null
echo

echo "==============================================================="
echo "[B] ventago / coolsistema 관련 컨테이너 후보"
echo "==============================================================="
CANDS=$(sudo docker ps --format '{{.Names}}' | grep -iE 'ventago|coolsistema' || true)
if [ -z "$CANDS" ]; then
  echo "⚠️  ventago/coolsistema 매칭 컨테이너 없음"
else
  for C in $CANDS; do
    echo "▶ $C"
    sudo docker inspect "$C" --format '   workdir : {{.Config.WorkingDir}}
   image   : {{.Config.Image}}
   created : {{.Created}}'
    echo "   .next/BUILD_ID 후보 위치 검색:"
    sudo docker exec "$C" sh -c '
      for D in /app /usr/src/app /opt/app /workspace; do
        if [ -f "$D/.next/BUILD_ID" ]; then
          echo "     ✅ $D/.next/BUILD_ID  ->  $(cat $D/.next/BUILD_ID 2>/dev/null)"
        fi
      done
    ' 2>/dev/null || echo "     (exec 실패)"
    echo
  done
fi

echo "==============================================================="
echo "[C] 호스트 — docker-compose.yml 검색"
echo "==============================================================="
sudo find /home /opt /var/www /srv /root -maxdepth 6 -name 'docker-compose.yml' 2>/dev/null | head -20 || true
echo

echo "==============================================================="
echo "[D] 호스트 — ventago-app .git 경로 검색 (배포 repo)"
echo "==============================================================="
sudo find /home /opt /srv /root -maxdepth 6 -type d -name '.git' 2>/dev/null | xargs -I{} sh -c 'echo "{}" | grep -qiE "ventago|coolsistema" && echo "  {}"' 2>/dev/null | head -10 || true
echo

echo "==============================================================="
echo "[E] 호스트 사용자 + sudo 권한 확인"
echo "==============================================================="
echo "  whoami: $(whoami)"
echo "  groups: $(groups)"
EOF
