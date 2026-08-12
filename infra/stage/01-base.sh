#!/usr/bin/env bash
# ============================================================
# 01 — OS 기본 셋업 / 보안 하드닝
# ============================================================
# 로컬(Mac)에서 실행:  ./01-base.sh
# 대상: 스테이지 서버 (root)
#
# 하는 일:
#   · apt 업데이트 + 기본 패키지
#   · timezone / locale
#   · swap 생성 (운영은 swap 0 이라 OOM killer 가 Postgres 를 고를 수 있었다 — 스테이지는 만든다)
#   · 배포 유저 생성 + docker 그룹
#   · ufw 방화벽 (SSH / HTTP / HTTPS 만)
#   · fail2ban
#   · unattended-upgrades (보안 패치만)
#   · sshd 하드닝 (비밀번호 로그인 차단 — ★ 키 로그인 확인 후에만 적용)
# ============================================================
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_config

log "스테이지 서버 base 셋업 시작: ${STAGE_HOST}"

stage_ssh "bash -s" <<REMOTE
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "── OS 확인 ──"
. /etc/os-release
echo "  \$PRETTY_NAME"
case "\$ID-\$VERSION_ID" in
  ubuntu-22.04|ubuntu-24.04|debian-12) ;;
  *) echo "!! 검증되지 않은 OS 입니다: \$PRETTY_NAME — 계속하려면 스크립트를 확인하세요"; exit 1 ;;
esac

echo "── 패키지 갱신 ──"
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
  curl wget ca-certificates gnupg lsb-release \
  git vim htop jq unzip rsync \
  ufw fail2ban unattended-upgrades \
  net-tools dnsutils \
  build-essential

echo "── timezone / locale ──"
timedatectl set-timezone "${STAGE_TZ}"
locale-gen en_US.UTF-8 >/dev/null 2>&1 || true

echo "── swap (4G) ──"
# 운영 서버는 swap 이 0 이라 메모리 스파이크 시 OOM killer 가 PostgreSQL 을 죽일 수 있다.
# 여기는 8GB 한 대에 PG + API + Next.js 빌드가 전부 올라가므로 특히 필요하다.
# Next.js 프로덕션 빌드 한 번이 2GB 넘게 쓴다 — swap 없이는 빌드 중 OOM 이 난다.
# 240GB NVMe 이므로 4G 는 부담이 없다.
if ! swapon --show | grep -q .; then
  fallocate -l 4G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo "  swap 2G 생성"
else
  echo "  swap 이미 존재 — 스킵"
fi
# DB 서버이므로 swap 은 최후 수단으로만 쓰이게 한다.
sysctl -w vm.swappiness=10 >/dev/null
grep -q '^vm.swappiness' /etc/sysctl.conf || echo 'vm.swappiness=10' >> /etc/sysctl.conf

echo "── 커널 파라미터 (PostgreSQL 권장) ──"
cat > /etc/sysctl.d/60-ventago-stage.conf <<'SYSCTL'
# ── 오버커밋 정책 ──
# PostgreSQL 문서는 vm.overcommit_memory=2 (엄격) 를 권한다. 하지만 이 서버는
# DB 전용이 아니다 — Node/V8 은 힙을 실제 사용량보다 훨씬 크게 **예약**하므로
# 엄격 모드에서 Next.js 빌드가 ENOMEM 으로 죽는다.
# 그래서 오버커밋은 기본 휴리스틱(0)으로 두고, postmaster 는 아래 systemd
# drop-in 의 OOMScoreAdjust 로 따로 보호한다. (효과는 같고 앱은 안 깨진다)
vm.overcommit_memory = 0

# 더티 페이지를 조금씩 자주 내보내 체크포인트 스파이크를 줄인다
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10

# 동시 접속 대비
net.core.somaxconn = 1024
net.ipv4.tcp_max_syn_backlog = 2048

# 파일 디스크립터 (docker + PG + node)
fs.file-max = 200000
SYSCTL
sysctl --system >/dev/null

echo "── PostgreSQL OOM 보호 ──"
# 메모리 압박 시 커널이 postmaster 를 고르면 DB 전체가 내려간다.
# postmaster 는 보호하고(-900), 자식 백엔드는 기본값으로 둬서 개별 쿼리가
# 대신 희생되게 한다 (PG 가 자식에게 0 을 다시 설정한다).
install -d /etc/systemd/system/postgresql@.service.d
cat > /etc/systemd/system/postgresql@.service.d/oom.conf <<'OOM'
[Service]
OOMScoreAdjust=-900
OOM
systemctl daemon-reload

echo "── 배포 유저: ${STAGE_DEPLOY_USER} ──"
if ! id -u "${STAGE_DEPLOY_USER}" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "${STAGE_DEPLOY_USER}"
  usermod -aG sudo "${STAGE_DEPLOY_USER}"
  echo "  생성 완료"
else
  echo "  이미 존재 — 스킵"
fi
# root 의 authorized_keys 를 배포 유저에게 복사 (같은 키로 접속 가능하게)
install -d -m 700 -o "${STAGE_DEPLOY_USER}" -g "${STAGE_DEPLOY_USER}" "/home/${STAGE_DEPLOY_USER}/.ssh"
if [ -f /root/.ssh/authorized_keys ]; then
  install -m 600 -o "${STAGE_DEPLOY_USER}" -g "${STAGE_DEPLOY_USER}" \
    /root/.ssh/authorized_keys "/home/${STAGE_DEPLOY_USER}/.ssh/authorized_keys"
fi

echo "── 방화벽 (ufw) ──"
ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing
ufw allow ${STAGE_SSH_PORT}/tcp comment 'SSH'
ufw allow 80/tcp   comment 'HTTP (certbot + redirect)'
ufw allow 443/tcp  comment 'HTTPS'
# ★ 앱/DB 포트는 열지 않는다. 전부 nginx 뒤 / localhost 바인딩이다.
#    5001·5002·5432·5434·9000 을 외부에 노출하면 스테이지가 곧 공격면이 된다.
ufw --force enable
ufw status verbose

echo "── fail2ban ──"
cat > /etc/fail2ban/jail.local <<'F2B'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = systemd

[sshd]
enabled = true
F2B
systemctl enable --now fail2ban
systemctl restart fail2ban

echo "── 자동 보안 업데이트 ──"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'AUTOUP'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
AUTOUP

echo "── sshd 하드닝 ──"
# ★ 키 로그인이 확인된 뒤에만 비밀번호 로그인을 끈다.
#   현재 세션이 키로 들어와 있으므로 안전하다.
if [ -n "\${SSH_CONNECTION:-}" ] || [ -s /root/.ssh/authorized_keys ]; then
  cat > /etc/ssh/sshd_config.d/99-ventago-stage.conf <<'SSHD'
PasswordAuthentication no
PermitRootLogin prohibit-password
ChallengeResponseAuthentication no
X11Forwarding no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
SSHD
  sshd -t && systemctl reload ssh
  echo "  비밀번호 로그인 차단 적용"
else
  echo "  !! authorized_keys 가 비어 있어 비밀번호 로그인을 유지합니다 (락아웃 방지)"
fi

echo "── 로그 디렉터리 ──"
install -d -m 755 /var/lib/ventago-logs/api
install -d -m 755 /var/lib/ventago-logs/app
install -d -m 755 /var/backups/ventago

echo
echo "✓ base 셋업 완료"
free -h
df -h /
REMOTE

ok "01-base 완료"
