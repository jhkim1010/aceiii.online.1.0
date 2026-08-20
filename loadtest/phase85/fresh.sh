#!/bin/bash
# 워커 간 무효화 전파 시험 — 단일 워커로는 절대 잡히지 않는다.
#
# 1) 전 워커(4)의 categories 캐시를 채운다
# 2) 한 워커에서 카테고리를 수정한다 → 그 워커만 로컬 무효화 + Redis publish
# 3) 즉시 전 워커에서 읽어 **몇 ms 만에 새 값이 보이는가**를 잰다
#    전파가 안 되면 나머지 3워커는 TTL(60초)까지 옛 이름을 준다.
set -u
API=http://127.0.0.1:5012/api
ADMIN_EMAIL=${ADMIN_EMAIL:?}
ADMIN_PW=${ADMIN_PW:-loadtest123}

TOK=$(curl -s --max-time 15 -X POST $API/auth/login -H 'Content-Type: application/json' \
  -d "{\"emailOrUsername\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PW\"}" \
  | sed -E 's/.*"accessToken":"([^"]+)".*/\1/')
[ ${#TOK} -lt 50 ] && { echo "로그인 실패"; exit 1; }
AUTH="Authorization: Bearer $TOK"

# 1) 워밍 — 40회면 4워커 전부 채워진다
for _ in $(seq 1 40); do curl -s -o /dev/null --max-time 20 -H "$AUTH" $API/categories/by-store; done

CAT=$(curl -s --max-time 20 -H "$AUTH" $API/categories/by-store)
ID=$(echo "$CAT" | python3 -c 'import sys,json;d=json.load(sys.stdin);d=d if isinstance(d,list) else d.get("data",d);print(d[0]["id"])')
OLD=$(echo "$CAT" | python3 -c 'import sys,json;d=json.load(sys.stdin);d=d if isinstance(d,list) else d.get("data",d);print(d[0]["name"])')
NEW="FRESHTEST-$(date +%s)"
echo "대상 카테고리 id=$ID  '$OLD' → '$NEW'"

# 2) 수정
CODE=$(curl -s -o /tmp/upd.out -w '%{http_code}' --max-time 20 -X PUT "$API/categories/$ID" \
  -H "$AUTH" -H 'Content-Type: application/json' -d "{\"name\":\"$NEW\"}")
echo "PUT → HTTP $CODE"
if [ "$CODE" != "200" ]; then head -c 300 /tmp/upd.out; echo; exit 1; fi

# 3) 즉시 60회 읽어 새 이름이 몇 번째부터 보이는지
STALE=0; FRESH=0; FIRST_FRESH=""
S=$(date +%s%N)
for i in $(seq 1 60); do
  R=$(curl -s --max-time 10 -H "$AUTH" $API/categories/by-store)
  if echo "$R" | grep -q "$NEW"; then
    FRESH=$((FRESH+1))
    [ -z "$FIRST_FRESH" ] && FIRST_FRESH=$(( ($(date +%s%N)-S)/1000000 ))
  else
    STALE=$((STALE+1))
  fi
done
echo "-- 수정 후 60회 읽기:  최신 $FRESH · 낡음 $STALE"
echo "-- 첫 최신 응답까지: ${FIRST_FRESH:-N/A} ms"
if [ "$STALE" -eq 0 ]; then echo "== 합격: 전 워커 즉시 반영 =="; else echo "== 불합격: $STALE 회가 낡은 값 (워커 간 전파 실패 의심) =="; fi

# 원복
curl -s -o /dev/null --max-time 20 -X PUT "$API/categories/$ID" -H "$AUTH" \
  -H 'Content-Type: application/json' -d "{\"name\":\"$OLD\"}"
echo "-- 원복: '$OLD'"
