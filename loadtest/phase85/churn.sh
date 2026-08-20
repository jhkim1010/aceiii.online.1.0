#!/bin/bash
# 무효화 vs 진행 중 loader — 부하 중 쓰기를 반복해 경쟁 창을 노린다.
#
# 결함(수정 전)이면: 쓰기가 들어온 순간 이미 돌던 loader 가 **옛 값을 캐시에 새로 넣어**
# 커밋된 변경이 TTL 동안 안 보인다. PUT 이 200 을 받은 뒤의 읽기는 전부 최신이어야 한다.
set -u
API=http://127.0.0.1:5012/api
ITER=${ITER:-25}; READERS=${READERS:-30}
TOK=$(curl -s --max-time 15 -X POST $API/auth/login -H 'Content-Type: application/json' \
  -d '{"emailOrUsername":"lt_s6_1@loadtest.local","password":"loadtest123"}' \
  | sed -E 's/.*"accessToken":"([^"]+)".*/\1/')
AUTH="Authorization: Bearer $TOK"
CAT=$(curl -s --max-time 20 -H "$AUTH" $API/categories/by-store)
ID=$(echo "$CAT" | python3 -c 'import sys,json;d=json.load(sys.stdin);d=d if isinstance(d,list) else d.get("data",d);print(d[0]["id"])')
ORIG=$(echo "$CAT" | python3 -c 'import sys,json;d=json.load(sys.stdin);d=d if isinstance(d,list) else d.get("data",d);print(d[0]["name"])')
echo "대상 id=$ID 원본='$ORIG' · $ITER 회 × 읽기 $READERS"

BAD=0
# 배경 읽기 부하를 계속 돌려 loader 가 자주 진행 중이 되게 한다
( END=$((SECONDS+120)); while [ $SECONDS -lt $END ]; do
    seq 1 8 | xargs -P 8 -I{} curl -s -o /dev/null --max-time 10 -H "$AUTH" $API/categories/by-store
  done ) & BG=$!

for i in $(seq 1 $ITER); do
  NEW="CHURN-$i-$RANDOM"
  C=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 -X PUT "$API/categories/$ID" \
      -H "$AUTH" -H 'Content-Type: application/json' -d "{\"name\":\"$NEW\"}")
  [ "$C" != "200" ] && { echo "  iter$i PUT $C"; continue; }
  # PUT 이 ack 된 뒤의 읽기는 전부 최신이어야 한다
  MISS=$(seq 1 $READERS | xargs -P $READERS -I{} sh -c \
    "curl -s --max-time 10 -H '$AUTH' $API/categories/by-store | grep -q '$NEW' || echo X" | grep -c X)
  if [ "$MISS" != "0" ]; then BAD=$((BAD+MISS)); echo "  iter$i: 낡은 응답 $MISS/$READERS"; fi
done
kill $BG 2>/dev/null; wait $BG 2>/dev/null
curl -s -o /dev/null --max-time 20 -X PUT "$API/categories/$ID" -H "$AUTH" \
  -H 'Content-Type: application/json' -d "{\"name\":\"$ORIG\"}"
TOTAL=$((ITER*READERS))
echo "-- 총 $TOTAL 회 읽기 중 낡음 $BAD"
[ "$BAD" -eq 0 ] && echo "== 합격: ack 후 낡은 응답 0 ==" || echo "== 불합격 =="
