#!/usr/bin/env bash
# ============================================================
# 00 — 사전 점검 (읽기 전용 · 아무것도 바꾸지 않는다)
# ============================================================
# 대상 VPS 는 2023-09-04 생성된 기존 서버다. 새 서버가 아니므로
# 01~07 을 돌리기 전에 "지금 뭐가 돌고 있는지" 를 반드시 먼저 본다.
#
# 01-base.sh 는 다음을 파괴적으로 수행한다 — 아래 점검 없이 돌리면 안 된다:
#   · ufw --force reset          → 기존 방화벽 규칙 전멸
#   · sshd 비밀번호 로그인 차단   → 키가 없으면 락아웃
#   · sysctl overcommit 변경      → 기존 서비스 메모리 거동 변화
# 02-postgres.sh 는 기본 main 클러스터를 drop 한다 → 기존 DB 가 있으면 데이터 소실.
#
# 사용법 (열어두신 SSH 세션에 통째로 붙여넣기):
#   아래 REMOTE 블록 내용만 복사해서 붙여넣으셔도 됩니다.
# 또는 로컬에서:  ./00-inspect.sh
# ============================================================
set -Eeuo pipefail

if [[ -f "$(dirname "${BASH_SOURCE[0]}")/00-config.env" ]]; then
  source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
  load_config
  RUNNER="stage_ssh bash -s"
else
  echo "00-config.env 가 없습니다 — 아래 블록을 SSH 세션에 직접 붙여넣으세요."
  RUNNER="cat"
fi

$RUNNER <<'INSPECT'
set +e
echo "════════════════════════════════════════════════════════"
echo "  스테이지 후보 서버 사전 점검 (읽기 전용)"
echo "  $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "════════════════════════════════════════════════════════"

echo
echo "── 1. 시스템 ──"
hostnamectl 2>/dev/null | sed 's/^/  /'
echo "  uptime:$(uptime -p 2>/dev/null)"
echo "  부팅:  $(uptime -s 2>/dev/null)"

echo
echo "── 2. 자원 ──"
echo "  CPU: $(nproc) core"
free -h | sed 's/^/  /'
echo "  swap:"; swapon --show 2>/dev/null | sed 's/^/    /' || echo "    (없음)"
df -hT / /var 2>/dev/null | sed 's/^/  /'

echo
echo "── 3. ★ 이미 돌고 있는 서비스 (여기가 핵심) ──"
echo "  [열린 포트]"
ss -tlnp 2>/dev/null | sed 's/^/    /'
echo
echo "  [실행 중 유닛 — 주요 데몬만]"
systemctl list-units --type=service --state=running --no-pager --no-legend 2>/dev/null \
  | grep -iE 'nginx|apache|postgres|mysql|maria|mongo|redis|docker|pgbouncer|php|node|pm2|caddy|haproxy|jenkins|minio' \
  | sed 's/^/    /' || echo "    (해당 없음)"

echo
echo "  [Docker]"
if command -v docker >/dev/null 2>&1; then
  docker --version | sed 's/^/    /'
  echo "    컨테이너:"; docker ps -a --format '      {{.Names}}\t{{.Image}}\t{{.Status}}' 2>/dev/null
  echo "    볼륨:";     docker volume ls -q 2>/dev/null | sed 's/^/      /'
  echo "    네트워크:"; docker network ls --format '      {{.Name}}' 2>/dev/null
else
  echo "    Docker 미설치"
fi

echo
echo "  [PostgreSQL]"
if command -v pg_lsclusters >/dev/null 2>&1; then
  pg_lsclusters 2>/dev/null | sed 's/^/    /'
  echo "    ※ main 클러스터에 데이터가 있으면 02-postgres.sh 의 pg_dropcluster 를 반드시 제거할 것"
else
  echo "    PostgreSQL 미설치 (깨끗함)"
fi

echo
echo "  [웹서버 설정]"
ls -1 /etc/nginx/sites-enabled/ 2>/dev/null | sed 's/^/    nginx: /' || echo "    nginx 설정 없음"
ls -1 /etc/apache2/sites-enabled/ 2>/dev/null | sed 's/^/    apache: /' || true

echo
echo "── 4. ★ 방화벽 (01-base.sh 가 reset 하므로 먼저 기록) ──"
if command -v ufw >/dev/null 2>&1; then
  ufw status verbose 2>/dev/null | sed 's/^/  /'
else
  echo "  ufw 미설치"
fi
echo "  [iptables 규칙 수] $(iptables -S 2>/dev/null | wc -l)"

echo
echo "── 5. ★ SSH 접근 (락아웃 방지 — 가장 중요) ──"
echo "  authorized_keys (root): $(wc -l < /root/.ssh/authorized_keys 2>/dev/null || echo 0) 개"
grep -HE '^(PasswordAuthentication|PermitRootLogin|Port)' \
  /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | sed 's/^/  /'
echo "  현재 접속 방식: ${SSH_CONNECTION:-(로컬)}"
echo "  ※ authorized_keys 가 0 이면 01-base.sh 의 sshd 하드닝을 건너뛸 것 (락아웃)"

echo
echo "── 6. 사용자 / cron ──"
awk -F: '$3>=1000 && $3<65534 {print "  "$1" (uid "$3", home "$6")"}' /etc/passwd
echo "  [root cron]"; crontab -l 2>/dev/null | grep -v '^#' | sed 's/^/    /' || echo "    없음"
echo "  [/etc/cron.d]"; ls -1 /etc/cron.d 2>/dev/null | sed 's/^/    /'

echo
echo "── 7. 네트워크 / DNS ──"
ip -4 addr show scope global 2>/dev/null | grep inet | sed 's/^/  /'
echo "  외부에서 본 IP: $(curl -s --max-time 8 https://ifconfig.me 2>/dev/null || echo '조회 실패')"
echo "  [DNS 확인 — 06-nginx-ssl.sh 전에 반드시 통과해야 함]"
for d in stage.coolsistema.com stageapi.coolsistema.com stagefiles.coolsistema.com; do
  r=$(getent hosts "$d" 2>/dev/null | awk '{print $1}' | head -1)
  echo "    $d → ${r:-미설정}"
done

echo
echo "── 8. ★ IONOS 클라우드 방화벽 확인 (외부에서만 가능) ──"
echo "  이 VPS 는 IONOS Cloud Firewall('My firewall policy') 뒤에 있습니다."
echo "  ufw 를 열어도 IONOS 콘솔에서 막혀 있으면 certbot HTTP-01 이 실패합니다."
echo "  콘솔에서 아래 인바운드가 허용돼 있는지 확인하세요:"
echo "     TCP 22 (SSH) / TCP 80 (certbot) / TCP 443 (HTTPS)"

echo
echo "── 9. 운영 서버 도달성 (04-restore.sh 가 pg_dump 를 가져올 경로) ──"
timeout 5 bash -c 'cat < /dev/null > /dev/tcp/62.72.7.245/22' 2>/dev/null \
  && echo "  62.72.7.245:22 도달 가능" \
  || echo "  62.72.7.245:22 도달 불가 (덤프는 Mac 경유로 전송되므로 필수는 아님)"

echo
echo "════════════════════════════════════════════════════════"
echo "  점검 완료 — 위 출력을 그대로 복사해서 전달해 주세요"
echo "════════════════════════════════════════════════════════"
INSPECT
