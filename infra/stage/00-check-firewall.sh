#!/usr/bin/env bash
# ============================================================
# 00b — IONOS Cloud Firewall 실제 통과 테스트
# ============================================================
# 왜 필요한가:
#   그냥 `nc -zv 74.208.60.137 80` 을 쏘면 **아직 아무것도 리스닝하지 않으므로**
#   방화벽이 열려 있어도 "닫힘"으로 보인다. 방화벽 문제인지 리스너 부재인지
#   구분이 안 되는 테스트는 아무것도 알려주지 않는다.
#
#   그래서 이 스크립트는 서버에 **임시 리스너를 띄운 뒤** 밖에서 두드린다.
#   이게 certbot HTTP-01 챌린지가 실제로 겪는 경로와 같다.
#
# 안전성: 임시 리스너는 5초 후 자동 종료되고, 방화벽 설정을 바꾸지 않는다.
#
# 실행: ./00-check-firewall.sh        (Mac 에서 — claude 를 터미널에서 띄운 경우)
# ============================================================
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_config

log "IONOS Cloud Firewall 통과 테스트: ${STAGE_HOST}"
echo

# ── 1. SSH (22) — 이미 붙었으므로 자명하지만 기록 ────────────
if stage_ssh "echo ok" >/dev/null 2>&1; then
  ok "TCP 22  (SSH)   — 통과"
else
  die "TCP 22 조차 막혀 있습니다. STAGE_HOST/키를 확인하세요."
fi

# ── 2. 80 / 443 ──────────────────────────────────────────
for PORT in 80 443; do
  log "TCP ${PORT} 테스트 — 서버에 임시 리스너 기동"

  # 이미 무언가 듣고 있으면 건드리지 않는다 (nginx 가 이미 떠 있는 경우 등)
  IN_USE=$(stage_ssh "ss -tln | awk '{print \$4}' | grep -qE ':${PORT}\$' && echo yes || echo no")

  if [[ "$IN_USE" == "yes" ]]; then
    log "  (포트 ${PORT} 에 이미 리스너가 있음 — 그대로 테스트)"
  else
    # ufw 가 활성이면 임시로 허용 규칙이 있는지 확인만 한다 (변경하지 않음)
    stage_ssh "command -v ufw >/dev/null && ufw status 2>/dev/null | grep -qE '^${PORT}/tcp .*ALLOW' \
                 && echo '  ufw: ${PORT} 허용됨' \
                 || echo '  ufw: ${PORT} 규칙 없음 (비활성이면 무관)'" || true

    # 5초짜리 임시 리스너. nohup + disown 으로 SSH 세션 종료와 무관하게 살려둔다.
    stage_ssh "nohup timeout 5 python3 -c \"
import http.server, socketserver
socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(('0.0.0.0', ${PORT}), http.server.SimpleHTTPRequestHandler) as s:
    s.serve_forever()
\" >/dev/null 2>&1 &" || true
    sleep 1
  fi

  # 밖(=이 Mac)에서 두드린다
  CODE=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 6 \
         "http://${STAGE_HOST}:${PORT}/" 2>/dev/null || echo 000)

  if [[ "$CODE" != "000" ]]; then
    ok "TCP ${PORT} — 통과 (HTTP ${CODE})"
  else
    warn "TCP ${PORT} — 도달 실패"
    warn "  → IONOS 콘솔에서 열어야 합니다:"
    warn "     Menu ▸ Server & Cloud ▸ Network ▸ Firewall Policies"
    warn "     → 서버(${STAGE_HOST}) 선택 → 'My firewall policy'"
    warn "     → 마지막 행에 TCP/${PORT} 추가 후 저장"
    warn "     (또는 'Insert Default Values' 로 HTTP/HTTPS 사전 정의 규칙 삽입)"
    FW_FAIL=1
  fi
  sleep 5   # 임시 리스너가 종료될 때까지 대기
done

echo
if [[ "${FW_FAIL:-0}" == "1" ]]; then
  die "80 또는 443 이 막혀 있습니다. 06-nginx-ssl.sh 의 Let's Encrypt 발급이 실패합니다."
fi
ok "80 / 443 모두 통과 — certbot HTTP-01 챌린지 가능"
