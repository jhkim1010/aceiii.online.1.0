#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
APT="apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"
echo "== 1 apt"; apt-get update -q >/dev/null; $APT upgrade -q >/dev/null
$APT install -q ufw fail2ban unattended-upgrades chrony curl ca-certificates jq >/dev/null
echo "== 2 sshd"
cat > /etc/ssh/sshd_config.d/00-hardening.conf <<'C'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
C
sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config.d/50-cloud-init.conf
sshd -t && systemctl reload ssh
echo "== 3 ufw"
ufw --force reset >/dev/null
ufw default deny incoming >/dev/null; ufw default allow outgoing >/dev/null
for p in 22 80 443; do ufw allow $p/tcp >/dev/null; done
ufw --force enable >/dev/null
echo "== 4 unattended"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'C'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
C
cat > /etc/apt/apt.conf.d/52ventago-noreboot <<'C'
Unattended-Upgrade::Automatic-Reboot "false";
C
systemctl enable --now unattended-upgrades >/dev/null 2>&1
echo "== 5 swap"
echo 'vm.swappiness=10' > /etc/sysctl.d/99-ventago-swap.conf; sysctl -q -p /etc/sysctl.d/99-ventago-swap.conf
grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
echo "== 6 tz"; timedatectl set-timezone UTC; systemctl enable --now chrony >/dev/null 2>&1
echo "== 7 fail2ban"
cat > /etc/fail2ban/jail.d/sshd.local <<'C'
[sshd]
enabled = true
backend = systemd
C
systemctl enable fail2ban >/dev/null 2>&1; systemctl restart fail2ban
echo "== 8 jhkim"
id jhkim >/dev/null 2>&1 || adduser --disabled-password --gecos "" jhkim >/dev/null
usermod -aG sudo jhkim
install -d -m 700 -o jhkim -g jhkim /home/jhkim/.ssh
install -m 600 -o jhkim -g jhkim /root/.ssh/authorized_keys /home/jhkim/.ssh/authorized_keys
echo 'jhkim ALL=(ALL) NOPASSWD:ALL' > /tmp/90-jhkim
visudo -cf /tmp/90-jhkim >/dev/null && install -m 440 /tmp/90-jhkim /etc/sudoers.d/90-jhkim
visudo -c >/dev/null
echo "== 9 docker"
install -m 0755 -d /etc/apt/keyrings
[ -f /etc/apt/keyrings/docker.asc ] || curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
apt-get update -q >/dev/null
$APT install -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null
systemctl enable --now docker >/dev/null 2>&1
usermod -aG docker jhkim
echo DONE
