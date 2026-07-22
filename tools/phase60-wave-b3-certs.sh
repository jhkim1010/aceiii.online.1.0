#!/bin/bash
# ============================================================================
# Phase 60 Wave B3 (2026-07-21) — 인증서 777 world 권한 제거 (카나리 우선, 신중)
#   문제: /var/lib/jenkins/workspace/certificados 전체 777, 개인키(.key)도 -rwxrwxrwx
#         → world-readable 개인키(최고위험) + world-writable
#   제약: coolinvoice(컨테이너 uid 1000)가 "world-read" 로 읽는 중 → 단순 o-rwx 하면
#         발급 파손. 해결: 그룹=gid 1000 부여 + g+rwX 로 앱 접근 보존하며 world 만 제거.
#         api_ventago(root) 는 무조건 접근. writer=jenkins(owner 유지).
#   방식: ★매장 1개 카나리 → 두 컨테이너 읽기/쓰기 검증 → (수동) 전체 롤아웃
# 실행: ssh jhkim@62.72.7.245 'bash -s' < tools/phase60-wave-b3-certs.sh [매장명]
# ============================================================================
set -uo pipefail
BASE=/var/lib/jenkins/workspace/certificados
STORE="${1:-}"

if [ -z "$STORE" ]; then
  STORE=$(sudo find "$BASE" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort | head -1)
  echo "== 카나리 매장 미지정 → 자동선택: '$STORE' (원하면 인자로 매장명 전달) =="
fi
DIR="$BASE/$STORE"
if ! sudo test -d "$DIR"; then echo "!! '$DIR' 없음 — 매장명 확인"; exit 1; fi

echo "== [0] 현재 권한 (before) =="
sudo ls -la "$DIR" | head -8

echo "== [1] 카나리 권한 적용: chgrp 1000 + world 제거 + 그룹 접근 보존 =="
# 개인키 world-read 제거가 핵심. 소유자(jenkins/root/coolsistema)는 유지.
sudo chgrp -R 1000 "$DIR"
sudo chmod -R o-rwx "$DIR"      # ★world(others) 전면 차단 = 취약점 제거
sudo chmod -R g+rwX "$DIR"      # 앱 그룹(uid1000=coolinvoice) 읽기/쓰기/탐색 보존
echo "== after =="
sudo ls -la "$DIR" | head -8

echo "== [2] 컨테이너 실접근 검증 (읽기) =="
KEY=$(sudo find "$DIR" -maxdepth 2 -type f \( -name '*.key' -o -name '*.crt' -o -name '*.pem' \) | head -1)
KREL=${KEY#$BASE/}
echo "  검증 파일: $KREL"
R1=$(sudo docker exec coolinvoice sh -c "cat '/home/node/app/certificates/$KREL' >/dev/null 2>&1 && echo OK || echo FAIL")
R2=$(sudo docker exec api_ventago sh -c "cat '/app/certificates/$KREL' >/dev/null 2>&1 && echo OK || echo FAIL")
echo "  coolinvoice(uid1000) 읽기: $R1   |   api_ventago(root) 읽기: $R2"

echo "== [3] 컨테이너 쓰기 검증 (앱이 런타임에 인증서 생성하는 경우 대비) =="
W1=$(sudo docker exec coolinvoice sh -c "touch '/home/node/app/certificates/$STORE/.__wtest' 2>/dev/null && rm -f '/home/node/app/certificates/$STORE/.__wtest' && echo OK || echo NO-WRITE")
echo "  coolinvoice 쓰기: $W1  (NO-WRITE 여도 앱이 이 폴더에 쓰지 않으면 정상)"

echo ""
if [ "$R1" = "OK" ] && [ "$R2" = "OK" ]; then
  echo "✅ 카나리 성공 — 두 앱 모두 읽기 OK, world 권한 제거됨."
  echo "   ★다음: 실제 발급 스모크(B/A 인보이스 1건) 확인 후, 아래로 전체 롤아웃:"
  echo "   ---------------------------------------------------------------"
  echo "   sudo chgrp -R 1000 $BASE && sudo chmod -R o-rwx $BASE && sudo chmod -R g+rwX $BASE"
  echo "   # 확인: sudo find $BASE -name '*.key' -perm /o+r  (출력 0줄이어야 함)"
  echo "   ---------------------------------------------------------------"
else
  echo "❌ 카나리 실패 — 롤백 후 중단."
  echo "   원복: sudo chmod -R o+rX '$DIR'   (world 읽기 복원)"
  echo "   coolinvoice 실패 시: 컨테이너 uid/gid 재확인(docker exec coolinvoice id)."
fi
