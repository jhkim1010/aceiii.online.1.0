#!/bin/bash
# ============================================================================
# Phase 60 Wave B2 (교정판2 2026-07-21) — 관리 콘솔 외부포트 127.0.0.1 바인딩
#   교정: grep 에 '--' 추가(하이픈 시작 문자열), cd 대신 docker compose -f(권한),
#         Jenkins 이미 적용시 skip.
#   대상: pgAdmin 8090 / Portainer 9000·9443 / MinIO 9001·9005 / Mongo 27021 / Jenkins 8080
#   ★B1(basic auth) 완료 후 실행. 하나씩 재기동·검증.
# 실행: ssh jhkim@62.72.7.245 'bash -s' < tools/phase60-wave-b2.sh
# ============================================================================
set -uo pipefail

rebind() {  # CF OLD NEW NAME
  local CF="$1" OLD="$2" NEW="$3" NAME="$4"
  if ! sudo test -f "$CF"; then echo "  !! $NAME: $CF 없음 — skip"; return 1; fi
  if sudo grep -qF -- "$NEW" "$CF"; then echo "  $NAME: 이미 바인딩됨 — skip"; return 0; fi
  if ! sudo grep -qF -- "$OLD" "$CF"; then echo "  !! $NAME: 기대 문자열 미발견('$OLD') — 수동확인"; return 1; fi
  sudo cp "$CF" "$CF.bak.$(date +%s)"
  sudo python3 - "$CF" "$OLD" "$NEW" <<'PYEOF'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
open(p, 'w').write(open(p).read().replace(old, new))
print('  치환:', old.strip(), '→', new.strip())
PYEOF
}
up() { sudo docker compose -f "$1" up -d 2>&1 | tail -2; }   # cd 없이 실행(권한)
check() { sleep 3; curl -sk -o /dev/null -w "  $1 → HTTP %{http_code} ($2)\n" --max-time 8 "$3"; }
ext() { sudo ss -ltn | awk '{print $4}' | grep -qE "(^|\*|0\.0\.0\.0):$1\$" && echo "  포트 $1 여전히 외부노출 ⚠" || echo "  포트 $1 외부노출 제거 ✓"; }

echo "########## 1/5: pgAdmin (8090) ##########"
CF=/home/coolsistema/infra/pgadmin/docker-compose.yml
rebind "$CF" '- "8090:80"' '- "127.0.0.1:8090:80"' pgadmin && up "$CF"
check "cooldb.coolsistema.com" "401 기대" "https://cooldb.coolsistema.com/"; ext 8090

echo "########## 2/5: Portainer (9000·9443) ##########"
CF=/home/coolsistema/infra/portainer/docker-compose.yml
rebind "$CF" '- "9000:9000"' '- "127.0.0.1:9000:9000"' portainer-9000
rebind "$CF" '- "9443:9443"' '- "127.0.0.1:9443:9443"' portainer-9443
up "$CF"
check "portainer.coolsistema.com" "401 기대" "https://portainer.coolsistema.com/"; ext 9000; ext 9443

echo "########## 3/5: MinIO (콘솔 9001 · S3 9005) ##########"
CF=/home/coolsistema/infra/minio/docker-compose.yml
rebind "$CF" '- "9005:9000"' '- "127.0.0.1:9005:9000"' minio-9005
rebind "$CF" '- "9001:9001"' '- "127.0.0.1:9001:9001"' minio-9001
up "$CF"
check "minio(콘솔)" "401 기대" "https://minio.coolsistema.com/"
check "apiminio(S3 health)" "200 기대=앱경로 유지" "https://apiminio.coolsistema.com/minio/health/live"
ext 9001; ext 9005
echo "  ★앱 업로드 스모크: POS/프론트에서 이미지 업로드 1건 실제 확인 권장"

echo "########## 4/5: MongoDB (27021, 변수표기) ##########"
CF=/home/coolsistema/mongodb/docker-compose.yml
rebind "$CF" '- ${EXPOSE_PORT}:27017' '- 127.0.0.1:${EXPOSE_PORT}:27017' mongo && up "$CF"
check "manager.coolsistema.com" "200/404=매니저 정상(apicoolsistema→mongo 도커망)" "https://manager.coolsistema.com/"
ext 27021

echo "########## 5/5: Jenkins (8080, systemd) ##########"
if sudo test -f /etc/systemd/system/jenkins.service.d/override.conf && ! (sudo ss -ltn | awk '{print $4}' | grep -qE "(^|\*|0\.0\.0\.0):8080\$"); then
  echo "  이미 127.0.0.1 바인딩됨 — skip"
else
  echo "  Jenkins 재시작(약 30~60s). 진행중 빌드 없을 때 실행."
  sudo mkdir -p /etc/systemd/system/jenkins.service.d
  printf '[Service]\nEnvironment="JENKINS_LISTEN_ADDRESS=127.0.0.1"\n' | sudo tee /etc/systemd/system/jenkins.service.d/override.conf >/dev/null
  sudo systemctl daemon-reload; sudo systemctl restart jenkins
  echo "  재시작 대기..."; sleep 30
  curl -s -o /dev/null -w "  내부 127.0.0.1:8080 → HTTP %{http_code} (403/200=정상)\n" --max-time 8 http://127.0.0.1:8080/ || echo "  (아직 기동중)"
fi
check "deploy.coolsistema.com" "401 기대" "https://deploy.coolsistema.com/"; ext 8080

echo ""
echo "== 최종: 외부(0.0.0.0) 노출 포트 목록 =="
sudo ss -ltn | awk 'NR>1{print $4}' | grep -E "0.0.0.0|\*:" | sort -u
echo "== 위 목록에 8090/9000/9443/9001/9005/27021/8080 가 없어야 성공 =="
echo "== 유지 정상: 22 / 80 / 443 / 5002(agent) / 5001·5010·5011 / 3030 / 8085 =="
echo "== 원복: 각 compose 의 .bak.* 복원 후 sudo docker compose -f <파일> up -d =="
