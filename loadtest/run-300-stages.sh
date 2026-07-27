#!/bin/bash
# ============================================================================
# Phase 63 Wave E — 300매장 분산 용량 측정 (단계 실행)
#
# A-2b(단일 매장)는 950 판매/분(≈16/s)에서 재고 행 락으로 무너졌다.
# 여기서는 같은 총량을 300매장에 분산시켜 그 벽이 사라지는지 잰다.
#
# 단계: RATE 25 → 50 → 75 → 100 (초당 판매 건수)
#   75/s ≈ 3,000터미널 × 1건/40초 = 목표 부하
#   100/s = 목표 대비 133% 여유 확인
#
# 각 단계마다: k6 결과 + DB 저장 건수 + 참여 매장 수 + 락 대기를 기록한다.
# watchdog 동반 — 운영 지표 임계 초과 시 k6 자동 중단.
# ============================================================================
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS="$DIR/results"
STORES_FILE="${STORES_FILE:-$DIR/stores.txt}"
BASE_URL="${BASE_URL:-http://127.0.0.1:5012/api}"
PGPORT="${PGPORT:-5434}"
DB="${DB:-ventago_staging}"
STAGES="${STAGES:-25:5m 50:5m 75:10m 100:5m}"

mkdir -p "$RESULTS"
SUMMARY="$RESULTS/wave-e-summary.txt"
: > "$SUMMARY"

psql_q() { sudo -u postgres psql -p "$PGPORT" -d "$DB" -tAc "$1" 2>/dev/null; }

echo "[wave-e] 매장 목록: $(tr ',' '\n' < "$STORES_FILE" | grep -c .)개" | tee -a "$SUMMARY"

# 지표 샘플러 + watchdog 기동
WD_MAX_LOAD="${WD_MAX_LOAD:-13}" nohup "$DIR/watchdog.sh" > "$RESULTS/watchdog-wave-e.log" 2>&1 &
WD_PID=$!
nohup "$DIR/sample-metrics.sh" "$RESULTS/wave-e-metrics.log" > /dev/null 2>&1 &
SM_PID=$!
trap 'kill $WD_PID $SM_PID 2>/dev/null' EXIT

for stage in $STAGES; do
  RATE="${stage%%:*}"
  DUR="${stage##*:}"
  OUT="$RESULTS/wave-e-rate${RATE}.txt"

  echo "" | tee -a "$SUMMARY"
  echo "=== RATE=${RATE}/s  DUR=${DUR}  ($(date -u +%H:%M:%S) UTC) ===" | tee -a "$SUMMARY"

  T0=$(psql_q "select now()")

  k6 run -e BASE_URL="$BASE_URL" -e STORES_FILE="$STORES_FILE" \
         -e RATE="$RATE" -e DUR="$DUR" -e PER_STORE=10 \
         "$DIR/burst-multistore.js" > "$OUT" 2>&1
  K6_RC=$?

  # k6 지표
  grep -E "sale_ok|sale_err|http_req_failed|sale_ms\.|checks\." "$OUT" \
    | sed 's/^ *//' | tee -a "$SUMMARY"

  # DB 대조 — 요청 성공 수와 저장 수가 같아야 한다
  DBROW=$(psql_q "select count(*)||' ventas / '||count(distinct u.store_id)||' matriz stores'
                    from sales s join users u on u.id = s.user_id
                   where s.created_at > '$T0'")
  echo "DB: $DBROW" | tee -a "$SUMMARY"

  # 채번 중복 (F-1 회귀 감시)
  DUP=$(psql_q "select coalesce(sum(c-1),0) from (
                  select count(*) c from sales s join users u on u.id=s.user_id
                   where s.created_at > '$T0' and s.daily_number is not null
                   group by u.store_id, s.sale_date::date, s.daily_number
                  having count(*) > 1) t")
  echo "daily_number 중복: ${DUP:-?}" | tee -a "$SUMMARY"

  # 락 대기 잔재
  LOCK=$(psql_q "select count(*) from pg_stat_activity
                  where datname='$DB' and wait_event_type='Lock'")
  echo "잔여 락 대기: ${LOCK:-?} | k6 exit=$K6_RC" | tee -a "$SUMMARY"

  # 다음 단계 전 큐 배수 대기
  sleep 45
done

echo "" | tee -a "$SUMMARY"
echo "=== 전체 완료 $(date -u +%H:%M:%S) UTC ===" | tee -a "$SUMMARY"
echo "정합성 검증: sudo -u postgres psql -p $PGPORT -d $DB -f $DIR/verify-burst.sql" | tee -a "$SUMMARY"
