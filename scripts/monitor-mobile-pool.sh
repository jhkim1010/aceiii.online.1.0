#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# monitor-mobile-pool.sh — Phase 37 모바일 트래픽 PG pool 영향 감시 (READ-ONLY)
#
# 모바일(/mobile/*) 트래픽이 데스크탑 POS 의 PG pool(min=10/max=80, CLAUDE.md)을
# 잠식하는지 pg_stat_activity 로 감시한다. SELECT/SHOW 만 실행 — 운영 상태 변경 없음.
#
# 모드:
#   (기본) pool 샘플링 — 30s 간격으로 active/idle/waiting + using% + 모바일 추정 비중 표시
#   --once      1회만 샘플 후 종료
#   --latency   /mobile/catalog + /mobile/stock/:id 응답시간 N회 측정 → p50/p95/max
#               (MOBILE-D-01 part b — P95 ≤ 300ms 목표를 측정 가능하게. 권위 sign-off 는
#                37-04 Task 3 D-02 UAT 가 이 모드로 수행)
#
# 플래그:
#   --quiet          텔레그램 미전송(콘솔만)
#   --force          이상 없어도 텔레그램 전송
#   --local          로컬 PG18 로 조회 (기본은 운영 PG10 SSH)
#   --interval=N     샘플 간격 초 (기본 30)
#   --latency        지연 측정 모드
#   --base=URL       API base (기본: 로컬 http://localhost:5002/api)
#   --bearer=TOKEN   JWT accessToken (Authorization: Bearer)
#   --session=TOKEN  mobileSessionToken (x-mobile-session-token)
#   --product=ID     /mobile/stock/:id 로 측정할 parent product id
#   --n=N            지연 측정 반복 횟수 (기본 20)
#
# 사용 예:
#   ./scripts/monitor-mobile-pool.sh --once --local
#   ./scripts/monitor-mobile-pool.sh --latency --base=http://localhost:5002/api \
#       --bearer=eyJ... --session=uuid... --product=123 --n=30
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

SSH_HOST="jhkim-server"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/api-ventago/.env"

QUIET=0; FORCE=0; LOCAL=0; ONCE=0; LATENCY=0
INTERVAL=30
POOL_MAX=80          # CLAUDE.md — PG pool max (인스턴스당). using% 기준.
WARN_PCT=80          # 80% 이상이면 경고 (CLAUDE.md 80% warning)
MOBILE_PCT=30        # 모바일 추정 비중이 이보다 크면 경고
LAT_BASE="http://localhost:5002/api"
LAT_BEARER=""
LAT_SESSION=""
LAT_PRODUCT=""
LAT_N=20

for a in "$@"; do
  case "$a" in
    --quiet) QUIET=1;;
    --force) FORCE=1;;
    --local) LOCAL=1;;
    --once) ONCE=1;;
    --latency) LATENCY=1;;
    --interval=*) INTERVAL="${a#*=}";;
    --base=*) LAT_BASE="${a#*=}";;
    --bearer=*) LAT_BEARER="${a#*=}";;
    --session=*) LAT_SESSION="${a#*=}";;
    --product=*) LAT_PRODUCT="${a#*=}";;
    --n=*) LAT_N="${a#*=}";;
  esac
done

# 텔레그램 자격 (api-ventago/.env 재사용)
TG_TOKEN=$(grep -iE "^TELEGRAM_BOT_TOKEN=" "$ENV_FILE" 2>/dev/null | cut -d= -f2-)
TG_CHAT=$(grep -iE "^TELEGRAM_CHAT_ID=" "$ENV_FILE" 2>/dev/null | cut -d= -f2-)

send_telegram(){
  local text="$1"
  if [ "$QUIET" -eq 1 ]; then echo "[monitor] --quiet: 텔레그램 미전송"; return; fi
  if [ -z "$TG_TOKEN" ] || [ -z "$TG_CHAT" ]; then
    echo "[monitor] 텔레그램 자격 없음 — 전송 skip"; return
  fi
  local http
  http=$(curl -s -o /dev/null -w '%{http_code}' \
    "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TG_CHAT}" \
    --data-urlencode "parse_mode=HTML" \
    --data-urlencode "disable_web_page_preview=true" \
    --data-urlencode "text=${text}")
  echo "[monitor] 텔레그램 전송 http=$http"
}

# ── pool 샘플 SQL (SELECT only — pg_stat_activity 집계) ──
# PG10 호환: FILTER 절 + wait_event_type 사용 (구 waiting 컬럼 미사용).
read -r -d '' POOL_SQL <<'EOSQL'
SELECT
  count(*) FILTER (WHERE state = 'active')                       AS active,
  count(*) FILTER (WHERE state = 'idle')                         AS idle,
  count(*) FILTER (WHERE state = 'idle in transaction')          AS idle_tx,
  count(*) FILTER (WHERE wait_event_type = 'Lock')               AS waiting,
  count(*)                                                       AS total,
  count(*) FILTER (WHERE query ILIKE '%mobile%')                 AS mobile_hint
FROM pg_stat_activity
WHERE datname = 'ventago'
  AND pid <> pg_backend_pid();
EOSQL
POOL_SQL_ONE=$(echo "$POOL_SQL" | tr '\n' ' ')

run_pool_query(){
  if [ "$LOCAL" -eq 1 ]; then
    local pw
    pw=$(grep -iE "^DATABASE_password=" "$ENV_FILE" 2>/dev/null | cut -d= -f2-)
    PGPASSWORD="$pw" psql -h localhost -p 5432 -U postgres -d ventago -tAF'|' -c "$POOL_SQL_ONE" 2>&1
  else
    ssh "$SSH_HOST" "sudo -u postgres psql -d ventago -tAF'|' -c \"$POOL_SQL_ONE\"" 2>&1
  fi
}

sample_pool(){
  local row active idle idle_tx waiting total mobile_hint pct mob_pct verdict
  row=$(run_pool_query)
  if [ $? -ne 0 ] || [ -z "$row" ]; then
    echo "[monitor] pool 조회 실패: $row"; return 1
  fi
  IFS='|' read -r active idle idle_tx waiting total mobile_hint <<< "$row"

  pct=$(awk -v t="$total" -v m="$POOL_MAX" 'BEGIN{ if(m>0) printf "%.0f", (t/m)*100; else print 0 }')
  mob_pct=$(awk -v mh="$mobile_hint" -v t="$total" 'BEGIN{ if(t>0) printf "%.0f", (mh/t)*100; else print 0 }')

  verdict="OK"
  if [ "${waiting:-0}" -gt 0 ]; then verdict="ALERT:waiting>0"; fi
  if [ "$pct" -ge "$WARN_PCT" ]; then verdict="ALERT:using%>=${WARN_PCT}"; fi
  if [ "$mob_pct" -ge "$MOBILE_PCT" ]; then verdict="WARN:mobile>=${MOBILE_PCT}%"; fi

  printf '[%s] active=%s idle=%s idle_tx=%s waiting=%s total=%s/%s (%s%%) mobile~%s (%s%%) → %s\n' \
    "$(date '+%H:%M:%S')" "$active" "$idle" "$idle_tx" "$waiting" \
    "$total" "$POOL_MAX" "$pct" "$mobile_hint" "$mob_pct" "$verdict"

  if [ "$verdict" != "OK" ] || [ "$FORCE" -eq 1 ]; then
    send_telegram "🩺 <b>mobile-pool</b> $(date '+%m-%d %H:%M')
active=${active} idle=${idle} waiting=${waiting}
total=${total}/${POOL_MAX} (${pct}%) mobile~${mobile_hint} (${mob_pct}%)
verdict: <b>${verdict}</b>"
  fi

  case "$verdict" in
    ALERT*) return 3;;
    *) return 0;;
  esac
}

# ── 지연 측정 모드 (MOBILE-D-01 part b) ──
measure_latency(){
  if [ -z "$LAT_BEARER" ] || [ -z "$LAT_SESSION" ]; then
    echo "[monitor] --latency 는 --bearer 와 --session 토큰이 필요합니다."; exit 2
  fi

  local endpoints=("$LAT_BASE/mobile/catalog")
  if [ -n "$LAT_PRODUCT" ]; then
    endpoints+=("$LAT_BASE/mobile/stock/$LAT_PRODUCT")
  fi

  echo "[monitor] 지연 측정 — N=$LAT_N, 목표 P95 ≤ 300ms (CLAUDE.md)"
  local ep
  for ep in "${endpoints[@]}"; do
    local times=()
    local i t
    for ((i=0; i<LAT_N; i++)); do
      # time_total(초) → ms. SELECT-only GET, 서버 상태 변경 없음.
      t=$(curl -s -o /dev/null -w '%{time_total}' \
        -H "Authorization: Bearer ${LAT_BEARER}" \
        -H "x-mobile-session-token: ${LAT_SESSION}" \
        "$ep")
      t=$(awk -v s="$t" 'BEGIN{ printf "%.0f", s*1000 }')
      times+=("$t")
    done

    # 정렬 후 p50/p95/max
    local sorted p50 p95 mx n idx95
    sorted=$(printf '%s\n' "${times[@]}" | sort -n)
    n=${#times[@]}
    p50=$(echo "$sorted" | awk -v n="$n" 'NR==int((n+1)/2){print; exit}')
    idx95=$(awk -v n="$n" 'BEGIN{ i=int(0.95*n); if(i<1)i=1; print i }')
    p95=$(echo "$sorted" | awk -v k="$idx95" 'NR==k{print; exit}')
    mx=$(echo "$sorted" | tail -1)

    local flag="OK"
    if [ "${p95:-0}" -gt 300 ]; then flag="ALERT:P95>300ms"; fi
    printf '  %-45s p50=%sms p95=%sms max=%sms → %s\n' "$ep" "$p50" "$p95" "$mx" "$flag"
  done
}

# ── main ──
if [ "$LATENCY" -eq 1 ]; then
  measure_latency
  exit 0
fi

if [ "$LOCAL" -eq 1 ]; then
  echo "[monitor] 로컬(PG18) mobile pool 감시 시작 — $(date '+%Y-%m-%d %H:%M:%S')"
else
  echo "[monitor] 운영(PG10) mobile pool 감시 시작 — $(date '+%Y-%m-%d %H:%M:%S')"
fi

RC=0
if [ "$ONCE" -eq 1 ]; then
  sample_pool || RC=$?
else
  echo "[monitor] ${INTERVAL}s 간격 샘플링 (Ctrl-C 종료)"
  while true; do
    sample_pool || RC=$?
    sleep "$INTERVAL"
  done
fi

exit "$RC"
