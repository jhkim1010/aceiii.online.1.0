#!/bin/bash
# ============================================================================
# Phase 60 Wave C1 — DB 포트 다시 열기 (롤백, 2026-07-22)
#   phase60-wave-c1-db-close.sh 를 완전히 되돌린다:
#   - 5432/5433 iptables 차단 규칙 제거 + systemd 서비스 해제
#   - 54322 compose 를 원본(.bak)으로 복원 후 재생성 → 0.0.0.0 재노출
#   ※ DB 를 다시 인터넷에 여는 것이므로 필요할 때만 사용.
# 실행: ssh jhkim@62.72.7.245 'bash -s' < tools/phase60-wave-c1-db-open.sh
# ============================================================================
set -uo pipefail

echo "== [1] 5432/5433 iptables 차단 규칙 제거 =="
del() { while sudo iptables -C "$@" 2>/dev/null; do sudo iptables -D "$@"; done; }
del INPUT -s 172.16.0.0/12 -p tcp -m multiport --dports 5432,5433 -j ACCEPT
del INPUT -s 127.0.0.0/8   -p tcp -m multiport --dports 5432,5433 -j ACCEPT
del INPUT -p tcp -m multiport --dports 5432,5433 -j DROP
echo "  남은 관련 규칙(없어야 함):"; sudo iptables -S INPUT | grep -E "5432|5433" | sed 's/^/    /' || echo "    (없음)"

echo "== [2] systemd 부팅 지속 해제 =="
sudo systemctl disable --now phase60-db-firewall.service >/dev/null 2>&1 || true
sudo rm -f /etc/systemd/system/phase60-db-firewall.service /usr/local/sbin/phase60-db-firewall.sh
sudo systemctl daemon-reload
echo "  서비스·스크립트 제거 완료"

echo "== [3] 54322 compose 원본 복원 + 재생성(0.0.0.0 재노출) =="
CF=/home/coolsistema/infra/postgresql/docker-compose.yml
BAK=$(sudo find "$(dirname "$CF")" -maxdepth 1 -name "$(basename "$CF").bak.*" -size +50c -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
if [ -n "$BAK" ]; then
  sudo cp "$BAK" "$CF"; echo "  복원 <- $(basename "$BAK")"
else
  # 백업 없으면 문자열 역치환
  sudo sed -i "s#'127.0.0.1:54322:5432'#'54322:5432'#" "$CF"; echo "  역치환 적용"
fi
sudo docker compose -f "$CF" up -d 2>&1 | tail -2

echo "== [4] 검증: DB 포트 다시 외부 리스너로 =="
sudo ss -ltn | awk 'NR>1{print $4}' | grep -E "0.0.0.0:(5432|5433|54322)" | sort -u | sed 's/^/    /' || echo "    (아직 반영 전이면 잠시 후 재확인)"
echo "== 완료: DB 포트가 다시 열렸습니다(외부 접속 가능) =="
