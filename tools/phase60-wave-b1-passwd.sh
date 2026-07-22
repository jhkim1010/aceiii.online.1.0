#!/bin/bash
# ============================================================================
# Phase 60 Wave B1-PASSWD (2026-07-21) — 관리 basic auth 비밀번호 재설정+검증
#   사용법:
#     자동생성(권장): ssh jhkim@62.72.7.245 'bash -s' < tools/phase60-wave-b1-passwd.sh
#     직접지정:       ssh jhkim@62.72.7.245 'bash -s -- 원하는비번' < tools/phase60-wave-b1-passwd.sh
#   헷갈리는 문자(I l 1 O 0) 제외. htpasswd 갱신 후 4종 접속 자동 검증.
# ============================================================================
set -uo pipefail
HT=/etc/nginx/.htpasswd-admin
USER=admin
PW="${1:-}"

if [ -z "$PW" ]; then
  # 모호한 글자 제외한 문자셋으로 12자 생성
  PW=$(LC_ALL=C tr -dc 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789' </dev/urandom | head -c12)
fi

sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q apache2-utils >/dev/null 2>&1 || true
sudo htpasswd -bc "$HT" "$USER" "$PW" >/dev/null 2>&1
sudo chmod 644 "$HT"; sudo chown root:root "$HT"
echo "== htpasswd 갱신 완료 =="

echo "== 검증: 새 비번으로 접속(200/302/401=Jenkins자체 다 정상=nginx통과), 틀린비번=401 =="
for N in portainer minio cooldb deploy; do
  OK=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 8 -u "$USER:$PW" "https://$N.coolsistema.com/")
  NG=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 8 -u "$USER:__wrong__" "https://$N.coolsistema.com/")
  echo "  $N → 정확한비번:$OK / 틀린비번:$NG (틀린비번이 401 이면 게이트 정상)"
done

echo ""
echo "=================================================="
echo "  관리 도구 basic auth"
echo "    아이디  : $USER"
echo "    비밀번호: $PW"
echo "  (한 글자씩: $(echo "$PW" | sed 's/./& /g'))"
echo "  ※ Jenkins(deploy)는 이 게이트 통과 후 Jenkins 자체 로그인 별도"
echo "=================================================="
