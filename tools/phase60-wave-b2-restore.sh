#!/bin/bash
# ============================================================================
# Phase 60 Wave B2-RESTORE (2026-07-21) — compose 복원 + 올바른 포트 바인딩
#   문제교정: 이전 python 이 파일 truncate 후 read → 빈 compose. 백업(.bak)은 온전.
#   조치: 각 compose 를 최신 정상 .bak 로 복원 → 안전 치환(read후write) → 재생성 → 검증
#   데이터: 4개 모두 host bind-mount → 재생성 무손실.
# 실행: ssh jhkim@62.72.7.245 'bash -s' < tools/phase60-wave-b2-restore.sh
# ============================================================================
set -uo pipefail

# 최신 정상(>50B) 백업 경로 (root 로 glob 확장)
newest_bak() { sudo find "$(dirname "$1")" -maxdepth 1 -name "$(basename "$1").bak.*" -size +50c -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-; }

# CF 복원 + 다중치환(안전) : restore_bind CF NAME OLD1 NEW1 [OLD2 NEW2 ...]
restore_bind() {
  local CF="$1" NAME="$2"; shift 2
  local BAK; BAK=$(newest_bak "$CF")
  if [ -z "$BAK" ]; then echo "  !! $NAME: 정상 백업 없음 — skip(수동확인)"; return 1; fi
  # 현재 파일이 이미 바인딩+정상이면 복원 생략
  if [ "$(sudo stat -c%s "$CF")" -gt 50 ] && sudo grep -qF -- "127.0.0.1" "$CF"; then
    echo "  $NAME: 이미 바인딩됨 — 치환 생략"; return 0; fi
  echo "  $NAME: 복원 <- $(basename "$BAK")"
  sudo cp "$BAK" "$CF"
  sudo python3 - "$CF" "$@" <<'PYEOF'
import sys
p = sys.argv[1]; s = open(p).read()
a = sys.argv[2:]
for i in range(0, len(a), 2):
    if a[i] not in s: print('  !! 미발견:', a[i]);
    s = s.replace(a[i], a[i+1])
open(p, 'w').write(s)      # read 완료 후 write (truncate 버그 없음)
print('  치환 완료:', p)
PYEOF
}
up()  { sudo docker compose -f "$1" up -d 2>&1 | tail -3; }
chk() { sleep 3; curl -sk -o /dev/null -w "  $1 → HTTP %{http_code} ($2)\n" --max-time 8 "$3"; }
ext() { sudo ss -ltn | awk '{print $4}' | grep -qE "(^|\*|0\.0\.0\.0):$1\$" && echo "  포트 $1 여전히 외부노출 ⚠" || echo "  포트 $1 외부노출 제거 ✓"; }

echo "########## 1/4: pgAdmin (8090) ##########"
CF=/home/coolsistema/infra/pgadmin/docker-compose.yml
restore_bind "$CF" pgadmin '- "8090:80"' '- "127.0.0.1:8090:80"' && up "$CF"
chk "cooldb" "401 기대" "https://cooldb.coolsistema.com/"; ext 8090

echo "########## 2/4: Portainer (9000·9443) ##########"
CF=/home/coolsistema/infra/portainer/docker-compose.yml
restore_bind "$CF" portainer '- "9000:9000"' '- "127.0.0.1:9000:9000"' '- "9443:9443"' '- "127.0.0.1:9443:9443"' && up "$CF"
chk "portainer" "401 기대" "https://portainer.coolsistema.com/"; ext 9000; ext 9443

echo "########## 3/4: MinIO (9001·9005) ##########"
CF=/home/coolsistema/infra/minio/docker-compose.yml
restore_bind "$CF" minio '- "9005:9000"' '- "127.0.0.1:9005:9000"' '- "9001:9001"' '- "127.0.0.1:9001:9001"' && up "$CF"
chk "minio(콘솔)" "401 기대" "https://minio.coolsistema.com/"
chk "apiminio(S3)" "200 기대=앱경로" "https://apiminio.coolsistema.com/minio/health/live"
ext 9001; ext 9005
echo "  ★앱 이미지 업로드 1건 실제 확인 권장"

echo "########## 4/4: MongoDB (27021) ##########"
CF=/home/coolsistema/mongodb/docker-compose.yml
restore_bind "$CF" mongo '- ${EXPOSE_PORT}:27017' '- 127.0.0.1:${EXPOSE_PORT}:27017' && up "$CF"
chk "manager" "200/404=정상" "https://manager.coolsistema.com/"; ext 27021

echo ""
echo "== compose 파일 무결성 재확인(크기>50) =="
for CF in /home/coolsistema/infra/pgadmin/docker-compose.yml /home/coolsistema/infra/portainer/docker-compose.yml /home/coolsistema/infra/minio/docker-compose.yml /home/coolsistema/mongodb/docker-compose.yml; do echo "  $(sudo stat -c%s "$CF")B  $CF"; done
echo ""
echo "== 최종: 외부(0.0.0.0) 노출 포트 =="
sudo ss -ltn | awk 'NR>1{print $4}' | grep -E "0.0.0.0|\*:" | sort -u
echo "== 8090/9000/9443/9001/9005/27021 사라지고 22/80/443/5002/5001/5010/5011/3030/8085 만 남으면 성공 =="
