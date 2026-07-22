#!/bin/bash
# ============================================================================
# Phase 60 Wave C1 — DB 포트 외부 차단 (2026-07-22)
#   5432(pgbouncer)·5433(postgres): 호스트 프로세스 → iptables INPUT 로 도커대역+localhost 만 허용
#   54322(dbpostgres 컨테이너): docker → compose 로 127.0.0.1 바인딩
#   앱(vw-agent·syncace host.docker.internal=172.17.0.1)·DBeaver(SSH터널→127.0.0.1) 무영향
#   ★자기잠금 위험 없음: 규칙은 5432/5433 만 대상, SSH22·80·443·앱포트 무관.
#   ★여는 스크립트: tools/phase60-wave-c1-db-open.sh
# 실행: ssh jhkim@62.72.7.245 'bash -s' < tools/phase60-wave-c1-db-close.sh
# ============================================================================
set -uo pipefail

echo "== [1] iptables 규칙 스크립트 설치(멱등·순서보장) =="
sudo tee /usr/local/sbin/phase60-db-firewall.sh >/dev/null <<'EOS'
#!/bin/bash
# DB 5432/5433 을 docker(172.16/12)+localhost 만 허용, 외부 DROP. 매 실행 재정렬.
del() { while iptables -C "$@" 2>/dev/null; do iptables -D "$@"; done; }
del INPUT -s 172.16.0.0/12 -p tcp -m multiport --dports 5432,5433 -j ACCEPT
del INPUT -s 127.0.0.0/8   -p tcp -m multiport --dports 5432,5433 -j ACCEPT
del INPUT -p tcp -m multiport --dports 5432,5433 -j DROP
# 순서: ACCEPT(허용) 먼저, DROP 마지막
iptables -A INPUT -s 172.16.0.0/12 -p tcp -m multiport --dports 5432,5433 -j ACCEPT
iptables -A INPUT -s 127.0.0.0/8   -p tcp -m multiport --dports 5432,5433 -j ACCEPT
iptables -A INPUT -p tcp -m multiport --dports 5432,5433 -j DROP
EOS
sudo chmod +x /usr/local/sbin/phase60-db-firewall.sh
sudo /usr/local/sbin/phase60-db-firewall.sh
echo "  적용된 규칙:"; sudo iptables -S INPUT | grep -E "5432|5433" | sed 's/^/    /'

echo "== [2] 부팅 지속(systemd, docker 이후 자동 적용) =="
sudo tee /etc/systemd/system/phase60-db-firewall.service >/dev/null <<'EOS'
[Unit]
Description=Phase60 DB port firewall (restrict 5432/5433 to docker+localhost)
After=docker.service network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/phase60-db-firewall.sh
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOS
sudo systemctl daemon-reload
sudo systemctl enable phase60-db-firewall.service >/dev/null 2>&1 && echo "  systemd 등록 완료(재부팅 후에도 유지)"

echo "== [3] 54322(dbpostgres) 127.0.0.1 바인딩 =="
CF=/home/coolsistema/infra/postgresql/docker-compose.yml
if sudo grep -qF -- "127.0.0.1:54322" "$CF"; then echo "  이미 바인딩됨 — skip"
elif sudo grep -qF -- "'54322:5432'" "$CF"; then
  sudo cp "$CF" "$CF.bak.$(date +%s)"
  sudo python3 - "$CF" <<'PYEOF'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("'54322:5432'","'127.0.0.1:54322:5432'")
open(p,'w').write(s)
print("  치환: '54322:5432' → '127.0.0.1:54322:5432'")
PYEOF
  sudo docker compose -f "$CF" up -d 2>&1 | tail -2
else echo "  !! '54322:5432' 미발견 — 수동확인"; fi

echo "== [4] 검증(앱 경로 살아있어야 정상) =="
timeout 5 bash -c "</dev/tcp/172.17.0.1/5433" 2>/dev/null && echo "  ✓ docker게이트웨이→5433 OK (vw-agent/syncace 경로 정상)" || echo "  ⚠ docker게이트웨이→5433 실패 — 즉시 open 스크립트로 원복 권장"
timeout 5 bash -c "</dev/tcp/127.0.0.1/5432" 2>/dev/null && echo "  ✓ localhost→5432 OK (SSH터널/백업 경로 정상)" || echo "  ⚠ localhost→5432 실패"
timeout 5 bash -c "</dev/tcp/127.0.0.1/54322" 2>/dev/null && echo "  ✓ localhost→54322 OK" || echo "  (54322 재기동 중일 수 있음)"
echo "  외부 리스너:"; sudo ss -ltn | awk 'NR>1{print $4}' | grep -E "0.0.0.0" | sort -u | sed 's/^/    /'
echo ""
echo "== 완료 =="
echo "  5432/5433: 리스너는 0.0.0.0 이지만 방화벽이 외부 DROP(도커+localhost만 허용)"
echo "  54322: 127.0.0.1 바인딩"
echo "  ★Mac 터미널에서 'nc -zv 62.72.7.245 5432' 가 timeout/실패면 외부차단 성공"
echo "  ★DBeaver(SSH터널)·앱은 그대로 동작. 문제 시 tools/phase60-wave-c1-db-open.sh"
