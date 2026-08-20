#!/bin/bash
# kanban 캐시: **키를 만드는 곳(dashboard.service)과 지우는 곳(envio.service)이 맞는가.**
#
# Phase 85 에서 키가 `talleres:kanban:{store}:{branch}` → `talleres~1kanban:s{store}:{branch}`
# 로 바뀌었다(storeKey 가 prefix 안의 `:` 를 이스케이프한다). 한쪽만 고치면 무효화가
# **아무것도 못 지우고 조용히 성공**하고, 발송 우선순위를 바꿔도 30초간 칸반이 안 바뀐다.
# 단위 테스트로는 이 파일 간 배선을 못 본다.
set -u
API=http://127.0.0.1:5012/api
TOK=$(curl -s --max-time 15 -X POST $API/auth/login -H 'Content-Type: application/json' \
  -d '{"emailOrUsername":"lt_s6_1@loadtest.local","password":"loadtest123"}' \
  | sed -E 's/.*"accessToken":"([^"]+)".*/\1/')
AUTH="Authorization: Bearer $TOK"

C=$(curl -s -o /tmp/k.out -w '%{http_code}' --max-time 20 -H "$AUTH" "$API/talleres/dashboard/kanban")
echo "kanban GET → $C"; [ "$C" != "200" ] && { head -c 250 /tmp/k.out; echo; exit 1; }

ENVIO=${ENVIO:-1}
# 1) 전 워커 캐시 워밍
for _ in $(seq 1 40); do curl -s -o /dev/null --max-time 20 -H "$AUTH" "$API/talleres/dashboard/kanban"; done
BEFORE=$(curl -s --max-time 20 -H "$AUTH" "$API/talleres/dashboard/kanban" \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print([e['priority'] for k,v in d['enviosByEtapa'].items() for e in v if e['id']==$ENVIO])" 2>/dev/null)
echo "수정 전 envio $ENVIO priority(칸반 응답 기준) = $BEFORE"

NEW=$(( RANDOM % 90 + 5 ))
C=$(curl -s -o /tmp/p.out -w '%{http_code}' --max-time 20 -X PATCH "$API/talleres/envios/$ENVIO/priority" \
   -H "$AUTH" -H 'Content-Type: application/json' -d "{\"priority\":$NEW}")
echo "PATCH priority=$NEW → $C"; [ "$C" != "200" ] && { head -c 250 /tmp/p.out; echo; exit 1; }

# 2) ack 직후 60회 읽기 — 전부 새 우선순위여야 한다
STALE=0
for _ in $(seq 1 60); do
  V=$(curl -s --max-time 10 -H "$AUTH" "$API/talleres/dashboard/kanban" \
      | python3 -c "import sys,json;d=json.load(sys.stdin);print(([e['priority'] for k,v in d['enviosByEtapa'].items() for e in v if e['id']==$ENVIO] or [None])[0])" 2>/dev/null)
  [ "$V" != "$NEW" ] && STALE=$((STALE+1))
done
echo "-- 수정 후 60회 중 낡음: $STALE"
[ "$STALE" -eq 0 ] && echo "== 합격: 만드는 키와 지우는 prefix 가 일치한다 ==" \
                   || echo "== 불합격: 무효화가 빗나갔다 (30초 TTL 까지 낡은 칸반) =="
