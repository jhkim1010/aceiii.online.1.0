#!/bin/bash
# Phase 85 W1 — TTL 경계 stampede 정량 측정
#
# 프로토콜: 컨테이너 재시작(전 워커 캐시 cold) → 토큰 확보 → 재시작(로그인 캐시 제거)
#           → pg_stat_statements 리셋 → 같은 키에 동시 N 요청 → calls 증분.
#
# 종전(3단)이면 동시 N 요청이 전부 DB 를 친다. getOrLoad 면 **워커당 1회** 로 수렴한다
# — 캐시가 워커별 프로세스 로컬 Map 이라 이론 하한은 1 이 아니라 워커 수(4)다.
set -u
N=${N:-100}
EP=${EP:-/api/auth/me}
LABEL=${LABEL:-run}
PSQL="sudo -u postgres psql -p 5434 -d ventago_staging -tAc"

restart_cold() {
  sudo docker restart api_staging >/dev/null
  for _ in $(seq 1 40); do
    curl -s --max-time 3 http://127.0.0.1:5012/api/health >/dev/null 2>&1 && break
    sleep 1
  done
  sleep 3
}

echo "### [$LABEL] $EP · 동시 $N"
restart_cold

TOK=$(curl -s --max-time 15 -X POST http://127.0.0.1:5012/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"emailOrUsername":"lt_vu_8@loadtest.local","password":"loadtest123"}' \
  | sed -E 's/.*"accessToken":"([^"]+)".*/\1/')
if [ ${#TOK} -lt 50 ]; then echo "로그인 실패"; exit 1; fi

restart_cold                      # 로그인이 남긴 캐시까지 제거. 토큰은 그대로 유효
$PSQL "SELECT pg_stat_statements_reset();" >/dev/null

OUT=$(mktemp -d)
S=$(date +%s%N)
seq 1 "$N" | xargs -P "$N" -I{} curl -s -o /dev/null \
  -w '%{http_code} %{time_total}\n' --max-time 60 \
  -H "Authorization: Bearer $TOK" "http://127.0.0.1:5012$EP" >> "$OUT/res.txt"
E=$(date +%s%N)

echo "-- 벽시계: $(( (E-S)/1000000 )) ms"
echo -n "-- HTTP: "; awk '{print $1}' "$OUT/res.txt" | sort | uniq -c | tr '\n' ' '; echo
echo -n "-- 응답 p50/p95/max: "; awk '{print $2}' "$OUT/res.txt" | sort -n \
  | awk '{a[NR]=$1} END{printf "%.3f / %.3f / %.3f s\n", a[int(NR*0.5)], a[int(NR*0.95)], a[NR]}'
echo -n "-- DB calls 증분 총합: "
$PSQL "SELECT COALESCE(SUM(calls),0) FROM pg_stat_statements s JOIN pg_database d ON d.oid=s.dbid WHERE d.datname='ventago_staging';"
echo "-- 상위 쿼리:"
$PSQL "SELECT '   '||lpad(calls::text,4)||' x '||left(regexp_replace(query,'\s+',' ','g'),95) FROM pg_stat_statements s JOIN pg_database d ON d.oid=s.dbid WHERE d.datname='ventago_staging' ORDER BY calls DESC LIMIT 6;"
rm -rf "$OUT"
