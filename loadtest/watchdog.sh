#!/bin/bash
# ============================================================================
# Phase 63 — 부하 테스트 안전 가드 (주간 테스트 필수 동반 실행)
#
# 운영 서버 자원이 임계치를 넘으면 k6 를 즉시 중단시켜 운영 서비스를 보호한다.
# 사용: 운영 서버에서 k6 실행 직전에 백그라운드로 띄운다.
#   ./watchdog.sh &   →   k6 run ... ;  kill %1
#
# 임계치 (환경변수로 조정 가능):
#   WD_MAX_LOAD   : 1분 load average 상한 (기본 6.0 — 8코어의 75%)
#   WD_MIN_FREE_MB: 최소 여유 메모리 MB (기본 2048)
#   WD_MAX_WAITING: 운영 pgbouncer cl_waiting 상한 (기본 5)
# ============================================================================
set -u

WD_MAX_LOAD="${WD_MAX_LOAD:-6.0}"
WD_MIN_FREE_MB="${WD_MIN_FREE_MB:-2048}"
WD_MAX_WAITING="${WD_MAX_WAITING:-5}"
INTERVAL=5

echo "[watchdog] 시작 — load<${WD_MAX_LOAD}, free>${WD_MIN_FREE_MB}MB, cl_waiting<${WD_MAX_WAITING}"

kill_k6() {
  echo "[watchdog] ★ 임계치 초과: $1 — k6 중단!"
  pkill -INT k6 2>/dev/null
  sleep 5
  pkill -9 k6 2>/dev/null
  exit 1
}

while true; do
  # 1) load average
  LOAD=$(awk '{print $1}' /proc/loadavg)
  if awk -v l="$LOAD" -v m="$WD_MAX_LOAD" 'BEGIN{exit !(l>m)}'; then
    kill_k6 "load=${LOAD}"
  fi

  # 2) 여유 메모리
  FREE_MB=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
  if [ "$FREE_MB" -lt "$WD_MIN_FREE_MB" ]; then
    kill_k6 "free=${FREE_MB}MB"
  fi

  # 3) 운영 pgbouncer 대기 큐 (운영 서비스 영향 감지 — 실패해도 무시)
  # -w: 비밀번호 프롬프트 금지 (인증 실패 시 조용히 건너뜀 — 감시가 멈추면 안 됨)
  WAITING=$(psql -w -h 127.0.0.1 -p 5432 -U coolsistema -d pgbouncer \
    -Atc "SHOW POOLS;" 2>/dev/null | awk -F'|' '$1=="ventago"{s+=$6} END{print s+0}')
  if [ -n "$WAITING" ] && [ "$WAITING" -gt "$WD_MAX_WAITING" ]; then
    kill_k6 "cl_waiting=${WAITING}"
  fi

  sleep "$INTERVAL"
done
