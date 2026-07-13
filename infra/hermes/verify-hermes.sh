#!/usr/bin/env bash
# =============================================================================
# verify-hermes.sh — 설치 전/후 운영 영향 대조 (읽기 전용, 상태변경 없음)
# 사용: bash verify-hermes.sh > /tmp/hermes-before.txt  (설치 전)
#       bash verify-hermes.sh > /tmp/hermes-after.txt   (설치 후)
#       diff /tmp/hermes-before.txt /tmp/hermes-after.txt
# =============================================================================
set -uo pipefail

echo "=== [mem] ==="
free -h

echo "=== [load] ==="
uptime

echo "=== [docker 컨테이너 상태/메모리] ==="
docker stats --no-stream --format '{{.Name}}\t{{.Status}}\t{{.MemUsage}}' 2>/dev/null | sort

echo "=== [PG 리스너 (변화 없어야 정상)] ==="
ss -tlnp 2>/dev/null | grep -E ':(5432|5433|5434|54322)' | awk '{print $4}' | sort

echo "=== [hermes 서비스 상태] ==="
systemctl is-active hermes-gateway 2>/dev/null || echo "미등록/미실행"
systemctl show hermes-gateway -p MemoryMax -p MemoryCurrent -p CPUQuotaPerSecUSec 2>/dev/null || true

echo "=== [hermes 유저 그룹 (docker/sudo 없어야 정상)] ==="
id hermes 2>/dev/null || echo "hermes 유저 없음"
