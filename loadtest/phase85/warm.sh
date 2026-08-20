#!/bin/bash
# 워밍 후 측정 — "캐시가 붙어 있는가" 를 stampede 와 분리해서 본다.
# 워밍을 워커 수보다 넉넉히 (WARM) 보내 전 워커의 캐시를 채운 뒤 측정한다.
set -u
N=${N:-100}; EP=${EP:-/api/auth/me}; WARM=${WARM:-40}; LABEL=${LABEL:-run}
PSQL="sudo -u postgres psql -p 5434 -d ventago_staging -tAc"
sudo docker restart api_staging >/dev/null
for _ in $(seq 1 40); do curl -s --max-time 3 http://127.0.0.1:5012/api/health >/dev/null 2>&1 && break; sleep 1; done
sleep 3
TOK=$(curl -s --max-time 15 -X POST http://127.0.0.1:5012/api/auth/login -H 'Content-Type: application/json' \
  -d '{"emailOrUsername":"lt_vu_8@loadtest.local","password":"loadtest123"}' | sed -E 's/.*"accessToken":"([^"]+)".*/\1/')
[ ${#TOK} -lt 50 ] && { echo "로그인 실패"; exit 1; }

echo "### [$LABEL] $EP  워밍 ${WARM} → 측정 ${N}"
# 워밍: 순차로 보내 각 워커가 자기 캐시를 채우게 한다
for _ in $(seq 1 "$WARM"); do curl -s -o /dev/null --max-time 20 -H "Authorization: Bearer $TOK" "http://127.0.0.1:5012$EP"; done

$PSQL "SELECT pg_stat_statements_reset();" >/dev/null
OUT=$(mktemp -d)
seq 1 "$N" | xargs -P "$N" -I{} curl -s -o /dev/null -w '%{http_code} %{time_total}\n' --max-time 60 \
  -H "Authorization: Bearer $TOK" "http://127.0.0.1:5012$EP" >> "$OUT/res.txt"
echo -n "-- HTTP: "; awk '{print $1}' "$OUT/res.txt" | sort | uniq -c | tr '\n' ' '; echo
echo -n "-- p50/p95: "; awk '{print $2}' "$OUT/res.txt" | sort -n | awk '{a[NR]=$1} END{printf "%.3f / %.3f s\n", a[int(NR*0.5)], a[int(NR*0.95)]}'
echo -n "-- 워밍 후 100요청의 DB calls: "
$PSQL "SELECT COALESCE(SUM(calls),0) FROM pg_stat_statements s JOIN pg_database d ON d.oid=s.dbid WHERE d.datname='ventago_staging';"
echo "-- 상위:"
$PSQL "SELECT '   '||lpad(calls::text,4)||' x '||left(regexp_replace(query,'\s+',' ','g'),90) FROM pg_stat_statements s JOIN pg_database d ON d.oid=s.dbid WHERE d.datname='ventago_staging' ORDER BY calls DESC LIMIT 6;"
rm -rf "$OUT"
