#!/bin/bash
# ============================================================================
# Phase 60 — deploy(Jenkins) basic auth 제거 (2026-07-22)
#   핸드폰 앱이 Jenkins 에 붙도록 deploy.coolsistema.com 의 nginx basic auth 해제.
#   8080 은 계속 127.0.0.1 바인딩(외부차단) 유지. Jenkins 자체 로그인/API토큰이 인증.
#   나머지 관리도구(portainer/minio/cooldb)의 basic auth 는 그대로.
# 실행: ssh jhkim@62.72.7.245 'bash -s' < tools/phase60-deploy-remove-auth.sh
# 되돌리기: tools/phase60-wave-b1-fix2.sh 로 재적용 가능
# ============================================================================
set -uo pipefail
F=/etc/nginx/sites-enabled/deploy.coolsistema.com.conf
TS=$(date +%s)
echo "== deploy basic auth 제거 =="
sudo cp "$F" "$F.authbak.$TS"
sudo sed -i '/auth_basic /d; /auth_basic_user_file/d' "$F"
# X-Forwarded-Proto 보강(443 프록시, 멱등)
if ! sudo grep -q "X-Forwarded-Proto" "$F"; then
  sudo sed -i 's#\(proxy_pass  http://127.0.0.1:8080;\)#\1\n    proxy_set_header X-Forwarded-Proto https;#' "$F"
fi
echo "== nginx 검증·reload (실패 시 자동 원복) =="
if sudo nginx -t 2>/dev/null; then sudo systemctl reload nginx; echo "  reload 완료"; else
  echo "  !! 문법오류 — 원복"; sudo cp "$F.authbak.$TS" "$F"; sudo systemctl reload nginx; exit 1; fi
echo "== 검증: deploy 응답(401=아직 auth / 403·200=Jenkins 자체인증=정상) =="
echo -n "  https://deploy.coolsistema.com/ → "; curl -sk -o /dev/null -w '%{http_code}\n' --max-time 8 https://deploy.coolsistema.com/
echo -n "  Jenkins API(login) → "; curl -sk -o /dev/null -w '%{http_code}\n' --max-time 8 https://deploy.coolsistema.com/login
echo "== 8080 외부차단 유지 확인 =="; sudo ss -ltn | grep ':8080' | awk '{print "  "$4}'
echo "== 완료. 앱 서버주소를 https://deploy.coolsistema.com 로 변경 후 Jenkins 계정/API토큰으로 로그인 =="
