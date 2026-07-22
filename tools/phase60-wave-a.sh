#!/bin/bash
# Phase 60 Wave A — 무중단 보안 강화 (운영 서버에서 실행)
# 안전장치: sshd 문법 검사 실패 시 자동 원복. reload 라서 기존 SSH 세션은 끊기지 않음.
# 실행 전: Mac 에서 ssh 세션 하나를 열어 유지할 것 (비상구).
set -e

echo "== [0] before: 로그인 실패 기록 수 =="
sudo lastb 2>/dev/null | wc -l || true

echo "== [1] sshd 강화 (드롭인 00-hardening.conf) =="
# 00- 접두사: sshd 는 first-match — Include 가 최상단이라 00 파일 값이 최우선으로 먹힘
printf 'PermitRootLogin no\nPasswordAuthentication no\nKbdInteractiveAuthentication no\nMaxAuthTries 4\n' \
  | sudo tee /etc/ssh/sshd_config.d/00-hardening.conf >/dev/null
if sudo sshd -t; then
  sudo systemctl reload ssh
  echo "  적용 완료 (기존 세션 유지됨)"
else
  sudo rm -f /etc/ssh/sshd_config.d/00-hardening.conf
  echo "  !! sshd 문법 오류 — 자동 원복했습니다. 적용 안 됨"
  exit 1
fi
echo "  유효값 확인:"
sudo sshd -T 2>/dev/null | grep -E "^(permitrootlogin|passwordauthentication|kbdinteractiveauthentication|maxauthtries)"

echo "== [2] fail2ban 설치·활성 (sshd jail, journald 백엔드) =="
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q fail2ban >/dev/null 2>&1 || sudo apt-get install -y fail2ban
printf '[sshd]\nenabled = true\nbackend = systemd\nmaxretry = 4\nbantime = 1h\n' \
  | sudo tee /etc/fail2ban/jail.d/sshd.local >/dev/null
sudo systemctl enable --now fail2ban
sudo systemctl restart fail2ban
sleep 2
sudo fail2ban-client status sshd || echo "  (기동 직후엔 지연될 수 있음 — 잠시 후 'sudo fail2ban-client status sshd' 재확인)"

echo "== [3] 인증서 파일 권한 현황 (보고만 — 변경은 Wave B 에서 컨테이너 uid 확인 후) =="
ls -l /var/lib/jenkins/workspace/certificados/key 2>/dev/null || true
ls -ld /var/lib/jenkins/workspace/certificados 2>/dev/null || true
stat -c '%U:%G %a %n' /var/lib/jenkins/workspace/certificados/coolsistema/key 2>/dev/null || true

echo ""
echo "== 완료. 지금 '새 터미널 창'에서 ssh jhkim@62.72.7.245 접속이 되는지 꼭 확인하세요 =="
echo "== 문제 시 원복(열어둔 세션에서): sudo rm /etc/ssh/sshd_config.d/00-hardening.conf && sudo systemctl reload ssh =="
