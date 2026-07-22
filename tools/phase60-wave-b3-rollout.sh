#!/bin/bash
# ============================================================================
# Phase 60 Wave B3-ROLLOUT (2026-07-21) — 인증서 전체 world 권한 제거
#   카나리(3ktextil) 검증 완료: coolinvoice(uid1000 group) + api_ventago(root) 읽기 OK.
#   전체 certificados 트리에 동일 적용: chgrp 1000 + o-rwx + g+rwX (소유자 유지).
#   검증: world-readable key/cert 0개, 여러 매장 두 컨테이너 읽기 OK.
# 실행: ssh jhkim@62.72.7.245 'bash -s' < tools/phase60-wave-b3-rollout.sh
# 롤백: sudo chmod -R o+rX /var/lib/jenkins/workspace/certificados
# ============================================================================
set -uo pipefail
BASE=/var/lib/jenkins/workspace/certificados

echo "== [before] world-readable 파일 수 =="
sudo find "$BASE" -type f -perm -o+r | wc -l

echo "== [적용] 전체 트리: chgrp 1000 + world 제거 + 그룹 rwX =="
sudo chgrp -R 1000 "$BASE"
sudo chmod -R o-rwx "$BASE"
sudo chmod -R g+rwX "$BASE"
echo "  완료"

echo "== [검증1] world 권한 남은 파일 수 (0 이어야 성공) =="
LEFT=$(sudo find "$BASE" -type f -perm -o+rwx | wc -l)
LEFTR=$(sudo find "$BASE" -type f -perm -o+r | wc -l)
echo "  world-any(rwx): $LEFT   world-read: $LEFTR   (둘 다 0 기대)"

echo "== [검증2] 여러 매장 두 컨테이너 읽기 (샘플 5개 디렉터리) =="
FAIL=0
for D in $(sudo find "$BASE" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort | head -5); do
  F=$(sudo find "$BASE/$D" -maxdepth 1 -type f ! -name '.*' 2>/dev/null | head -1)
  [ -z "$F" ] && continue
  REL=${F#$BASE/}
  R1=$(sudo docker exec coolinvoice sh -c "cat '/home/node/app/certificates/$REL' >/dev/null 2>&1 && echo OK || echo FAIL")
  R2=$(sudo docker exec api_ventago  sh -c "cat '/app/certificates/$REL' >/dev/null 2>&1 && echo OK || echo FAIL")
  echo "  $D/$(basename "$F") → coolinvoice:$R1 api_ventago:$R2"
  [ "$R1" = OK ] && [ "$R2" = OK ] || FAIL=1
done

echo ""
if [ "$LEFTR" -eq 0 ] && [ "$FAIL" -eq 0 ]; then
  echo "✅ 롤아웃 성공 — 개인키 world 노출 제거, 두 앱 읽기 정상."
  echo "   ★마지막: 실제 인보이스 1건(B/A) 발급으로 최종 확인 권장."
else
  echo "⚠ 확인 필요 — world-read 남음($LEFTR) 또는 읽기 실패. 롤백: sudo chmod -R o+rX $BASE"
fi
