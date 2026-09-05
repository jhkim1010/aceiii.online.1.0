#!/usr/bin/env bash
#
# 미마감 카하 일괄 정리 — countedCash=0 (구간만 닫고 돈은 안 움직인다)
# 사용자 결정 2026-09-05.
#
# ★ 정식 경로만 쓴다. SQL 로 closing_time 을 채우지 않는다 —
#   그러면 장부(box_settlements) 없이 잔액이 사라진다.
#   이 엔드포인트는 정산행을 만들고, 차액을 variance 로 남기고(review_required),
#   감사 로그에 "contado / esperado / diferencia + 사유" 를 기록한다.
#
# ★★ superadmin 토큰 하나로 전 매장을 돈다 — 요청마다 `X-Store-Id` 를 붙인다.
#   백엔드(JwtGlobalGuard)가 그 요청 동안 그 매장 사용자로 취급한다.
#
# 쓰는 법
#   1) 토큰 얻기 (아이디/비번은 화면에 안 남는다)
#        export TOKEN=$(curl -s -X POST https://newapi.coolsistema.com/api/auth/login \
#          -H 'Content-Type: application/json' \
#          -d '{"email":"<superadmin>","password":"<비번>"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
#   2) 먼저 무엇을 할지 **보기만** 한다
#        ./regularizar-cajas.sh --dry-run
#   3) 실제 실행
#        ./regularizar-cajas.sh
#        ./regularizar-cajas.sh 15        # 특정 서랍만
set -uo pipefail

API="${API:-https://newapi.coolsistema.com/api}"
NOTES="${NOTES:-미마감 구간 정리 — 현금 이체 없음 (2026-09-05 결정)}"

# box_id | store_id | through | 매장 | 설명(2026-09-05 실측)
CAJAS=(
  "15|6|2026-08-10|coolsistema|JuanaCaja · 6세션 · 장부 805,900"
  "3|3|2026-04-28|CART|Caja 1 · 1세션 · 16,500"
  "13|3|2026-04-10|CART|Caja de TEST · 1세션 · 14,500"
  "22|11|2026-06-23|Asado|Caja 1 · 2세션 · 9,000"
  "23|13|2026-07-24|Lenceria naty|Caja 1 · 2세션 · 100"
  "24|14|2026-07-21|naty|Caja 1 · 1세션 · 0"
  "21|10|2026-06-16|mana|Caja 1 · 2세션 · 0"
  "9|8|2026-04-20|genius|Caja 1 · 1세션 · 0"
)

DRY=0
DIAG=0
SOLO=""
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --diag)    DIAG=1 ;;
    *[!0-9]*)  echo "알 수 없는 인자: $a" >&2; exit 2 ;;
    *)         SOLO="$a" ;;
  esac
done

# ── 토큰 ────────────────────────────────────────────────────────────────
# TOKEN 이 없으면 **물어본다**. 편집할 것이 없고 비번이 화면·히스토리에 안 남는다.
#
# ★ JSON 은 python 이 만든다 — 비번에 " 나 \ 가 있어도 안 깨진다.
#   (셸에서 문자열로 이어 붙이면 그런 비번에서 조용히 틀린 요청이 나간다.)
obtener_token() {
  local u p resp
  printf '아이디(email 또는 username): ' >&2
  read -r u
  printf '비밀번호: ' >&2
  read -rs p
  printf '\n' >&2

  resp=$(curl -s --max-time 30 -X POST "$API/auth/login" \
    -H 'Content-Type: application/json' \
    --data-binary "$(python3 -c 'import json,sys;print(json.dumps({"emailOrUsername":sys.argv[1],"password":sys.argv[2]}))' "$u" "$p")")

  TOKEN=$(printf '%s' "$resp" | python3 -c 'import sys,json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
print(d.get("accessToken", ""))' 2>/dev/null)

  if [ -z "$TOKEN" ]; then
    echo "✗ 로그인 실패 — 서버 응답:" >&2
    printf '%s\n' "$resp" | head -c 500 >&2
    echo >&2
    return 1
  fi

  # 신규 IP/기기면 등록 요구가 붙는다. accessToken 은 그래도 쓸 수 있다.
  printf '%s' "$resp" | grep -q 'requireBranchRegistration' \
    && echo "※ 새 IP 라 지점 등록 요구가 붙었습니다(REST 호출에는 지장 없음)." >&2
  printf '%s' "$resp" | grep -q 'requireTerminalRegistration' \
    && echo "※ 새 기기라 터미널 등록 요구가 붙었습니다(REST 호출에는 지장 없음)." >&2

  echo "✓ 토큰 확보 (길이 ${#TOKEN})" >&2

  return 0
}

if [ "$DRY" -eq 0 ]; then
  if [ -z "${TOKEN:-}" ]; then
    echo "※ 로그인하면 **기존 세션이 끊깁니다** — 앱/웹에서 다시 로그인해야 할 수 있습니다."
    obtener_token || exit 1
  fi

  # 권한 확인 — superadmin 전용 경로로 미리 잰다. 8번 호출한 뒤 403 을 보는 것보다 낫다.
  perm=$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 \
    -H "Authorization: Bearer $TOKEN" "$API/afip/soap-status")
  case "$perm" in
    200) echo "✓ superadmin 권한 확인" ;;
    401) echo "✗ 토큰이 유효하지 않습니다 (401)"; exit 1 ;;
    403) echo "✗ superadmin 이 아닙니다 (403)"; exit 1 ;;
    *)   echo "※ 권한 확인이 애매합니다 ($perm) — 그래도 진행합니다" ;;
  esac
  echo

  # ── 진단: X-Store-Id 대행이 실제로 붙는가 ─────────────────────────────
  # 400 "Usuario no tiene tienda asignada" 는 대행이 안 붙었다는 뜻이다.
  # 헤더 유무로 /auth/me 의 storeId 가 바뀌는지 직접 잰다.
  if [ "$DIAG" -eq 1 ]; then
    echo "── 진단: X-Store-Id 대행"
    sin=$(curl -s --max-time 30 -H "Authorization: Bearer $TOKEN" "$API/auth/me")
    con=$(curl -s --max-time 30 -H "Authorization: Bearer $TOKEN" -H 'X-Store-Id: 6' "$API/auth/me")
    ver() { printf '%s' "$1" | python3 -c 'import sys,json
try: d=json.load(sys.stdin)
except Exception: print("(JSON 아님)"); raise SystemExit
print("storeId=", d.get("storeId"), " actingAsStoreId=", d.get("actingAsStoreId"),
      " roles=", d.get("roles"))' 2>/dev/null; }
    echo "  헤더 없이 : $(ver "$sin")"
    echo "  헤더 있이 : $(ver "$con")"
    echo
    echo "  ※ 둘이 같으면 헤더가 안 먹은 것입니다(nginx 가 지웠거나 역할 판정 실패)."
    echo "    다르면 대행은 되는데 다른 이유로 400 이 난 것입니다."
    exit 0
  fi
fi

printf '%-5s %-8s %-14s %-12s %s\n' BOX STORE MATCH THROUGH 설명
printf '%s\n' "------------------------------------------------------------------------"

ok=0; fail=0
for row in "${CAJAS[@]}"; do
  IFS='|' read -r box store through tienda desc <<<"$row"
  [ -n "$SOLO" ] && [ "$SOLO" != "$box" ] && continue

  printf '%-5s %-8s %-14s %-12s %s\n' "$box" "$store" "$tienda" "$through" "$desc"

  if [ "$DRY" -eq 1 ]; then
    continue
  fi

  body="{\"through\":\"$through\",\"countedCash\":0,\"notes\":\"$NOTES\"}"
  out="/tmp/reg-box-$box.json"

  # ★ SENSITIVE_THROTTLE 이 걸려 있다 — 연속 호출 사이에 간격을 둔다.
  code=$(curl -s -o "$out" -w '%{http_code}' --max-time 60 -X POST \
    "$API/cash-register/settlement-queue/$box/regularize" \
    -H "Authorization: Bearer $TOKEN" \
    -H "X-Store-Id: $store" \
    -H 'Content-Type: application/json' \
    -d "$body")

  case "$code" in
    200|201) ok=$((ok+1));   echo "      ✓ $code $(head -c 300 "$out")" ;;
    401|403) fail=$((fail+1)); echo "      ✗ $code 권한 없음 — superadmin 토큰인지 확인" ;;
    400)     fail=$((fail+1)); echo "      ✗ $code $(head -c 300 "$out")  (이미 닫혔거나 구간 겹침일 수 있음)" ;;
    *)       fail=$((fail+1)); echo "      ✗ $code $(head -c 300 "$out")" ;;
  esac
  echo
  sleep 3
done

if [ "$DRY" -eq 1 ]; then
  echo
  echo "※ --dry-run 이라 아무것도 실행하지 않았습니다."
  echo "  실제 실행: TOKEN=... $0"
else
  echo "------------------------------------------------------------------------"
  echo "성공 $ok · 실패 $fail"
  echo "확인: /caja → 정산 이력, 또는 감사 로그(Caja/edit)"
fi
