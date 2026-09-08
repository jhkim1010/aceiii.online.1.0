#!/usr/bin/env bash
#
# ventago-health-watch 설치 — systemd 타이머 60초.
#
# ★ cron 이 아니라 systemd 타이머인 이유: `systemctl list-timers` 로 **살아 있는지
#   확인할 수 있다.** cron 은 조용히 안 돌아도 티가 안 난다. 이번 사고의 교훈이
#   「기록은 있는데 읽는 사람이 없었다」이므로 감시 자체의 가시성이 중요하다.
#
# 사용: sudo bash install-health-watch.sh
set -u

SRC_DIR=$(cd "$(dirname "$0")" && pwd)
DEST=/usr/local/bin/ventago-health-watch.sh

install -m 0755 "$SRC_DIR/ventago-health-watch.sh" "$DEST" || exit 1
echo "설치: $DEST"

cat > /etc/systemd/system/ventago-health-watch.service <<'UNIT'
[Unit]
Description=Ventago 가용성 감시 (텔레그램 경보)
# ★ 앱 컨테이너에 의존하지 않는다 — 앱이 죽었을 때 돌아야 하는 장치다.
After=docker.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ventago-health-watch.sh
# 스크립트가 스스로 죽어도 타이머는 계속 돈다.
TimeoutStartSec=60
UNIT

cat > /etc/systemd/system/ventago-health-watch.timer <<'UNIT'
[Unit]
Description=Ventago 가용성 감시 타이머 (60초)

[Timer]
# 부팅 2분 뒤 첫 실행 — 컨테이너들이 올라올 시간을 준다(재부팅 직후 오경보 방지).
OnBootSec=2min
OnUnitActiveSec=60s
AccuracySec=10s
Unit=ventago-health-watch.service

[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload || exit 1
systemctl enable --now ventago-health-watch.timer || exit 1
echo "타이머 활성화 완료"
systemctl list-timers ventago-health-watch.timer --no-pager
