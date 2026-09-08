#!/usr/bin/env bash
#
# 미마감 카하 일괄 정리 — countedCash=0 (구간만 닫고 돈은 안 움직인다)
# 사용자 결정 2026-09-05 / 범위 재확인 2026-09-06.
#
# ★ 정식 경로만 쓴다. SQL 로 closing_time 을 채우지 않는다 —
#   그러면 장부(box_settlements) 없이 잔액이 사라진다.
#   이 엔드포인트는 정산행을 만들고, 차액을 variance 로 남기고,
#   감사 로그에 "contado / esperado / diferencia + 사유" 를 기록한다.
#
# ★ countedCash=0 이면 box_operations 도 caja_fuerte_operations 도 만들지 않는다
#   (cashRegister.service.ts 의 `if (counted > 0)`). 돈은 어디로도 안 간다.
#
# ★★ superadmin 토큰 하나로 전 매장을 돈다 — 요청마다 `X-Store-Id` 를 붙인다.
#   2026-09-05 에 이게 안 먹었던 이유는 nginx 가 아니라 **가드가 두 번 도는 것**이었다
#   (api-ventago 26e2416 에서 수정, 운영 반영 확인).
#
# ★★★ regularize 는 「열린 세션」이 아니라 **그 서랍의 미정산 섬 전체**를 닫는다.
#   아래 SESIONES 열은 실제로 닫히는 세션 수다(열린 세션 수가 아니다).
#
# 쓰는 법
#   ./regularizar-cajas.sh --dry-run      # 무엇을 할지 보기만
#   ./regularizar-cajas.sh --diag         # 대행 헤더가 먹는지만 확인 (카하 안 건드림)
#   TOKEN=... ./regularizar-cajas.sh      # 실제 실행
#   ./regularizar-cajas.sh 15             # 특정 서랍만
set -uo pipefail

API="${API:-https://newapi.coolsistema.com/api}"
NOTES="${NOTES:-미마감 구간 정리 — 현금 이체 없음 (2026-09-05 결정)}"

# box | store | through | 매장 | 세션(실제로 닫히는 수) | esperado (2026-09-06 운영 실측)
#
# ★ ACE(store 9) 의 box 18·19 는 2026-09-06 에 **한 번 뺐다가 다시 넣었다.**
#   뺀 이유: 19 = Caja de SALA 의 esperado 가 -2,731,000 이라 0 으로 닫으면
#   「현금이 273만 남아돌았다」는 기록이 남는다 — 원인을 먼저 봤다.
#   다시 넣은 이유: 원인 규명이 끝났다(핸드오프 2026-09-06 ③).
#     · -2,720,000 은 gasto 부호 결함(커밋 924736f, 2026-08-13 에 이미 수정)이
#       2026-06-04 자동마감에 남긴 흔적이다. 그 커밋이 과거 이체를 재계산하지
#       않기로 했으므로 장부에 유령이 남아 있었다.
#     · -680,000 은 중복 지출(box_operations #69)로, 2026-09-06 에 삭제했다
#       → esperado -2,731,000 → -2,051,000.
#     · 나머지 -11,000 과 box 18 의 -26,000 은 부패가 아니라 구조다 —
#       매일의 개시금 선언이 원장에 입금으로 안 잡히는데 자동마감은 그 현금을
#       금고로 옮긴다.
#   각 사유는 아래 배열의 NOTES 칸에 스페인어로 그대로 들어가 감사 로그에 남는다.
CAJAS=(
  "15|6|2026-08-10|coolsistema|JuanaCaja · 51세션 · esperado 677,400|"
  "6|6|2026-08-10|coolsistema|Caja 1 · 60세션 · esperado 139,500|"
  "20|6|2026-08-10|coolsistema|Caja de HELGUERA · 5세션 · esperado 0|"
  "3|3|2026-04-28|CART|Caja 1 · 17세션 · esperado -1,100|"
  "13|3|2026-04-10|CART|Caja de TEST · 1세션 · esperado 14,500|"
  "9|8|2026-04-20|genius|Caja 1 · 6세션 · esperado 464|"
  "21|10|2026-06-16|mana|Caja 1 · 2세션 · esperado 0|"
  "22|11|2026-06-23|Asado|Caja 1 · 4세션 · esperado 0|"
  "23|13|2026-07-24|Lenceria naty|Caja 1 · 3세션 · esperado 0|"
  "24|14|2026-07-21|naty|Caja 1 · 1세션 · esperado 0|"
  "18|9|2026-07-28|ACE|Caja Jefe · 32세션 · esperado -26,000|Regularización caja 18 (Caja Jefe). La diferencia de -26.000 está explicada: las aperturas declaradas por día (30.000 / 20.000 / 12.000) nunca entraron al libro como ingreso, y el cierre automático retiró ese efectivo hacia la caja fuerte. El código actual detecta este caso comparando declaredOpening contra openingFromSafe y lo marca review_required. Sin movimiento de efectivo."
  "19|9|2026-07-31|ACE|Caja de SALA · 20세션 · esperado -2,051,000|Regularización caja 19 (Caja de SALA). Diferencia explicada: (1) el 2026-06-04 un defecto de signo (commit 924736f) guardaba los gastos en negativo, el cierre automático calculó el saldo en +1.380.000 y transfirió ese fantasma a la caja fuerte (caja_fuerte_operations #44); el ingreso real fue 20.000. La caja fuerte quedó saldada en 0 por retiro del propietario el 2026-08-13. (2) Se eliminó un gasto duplicado de 680.000 el 2026-09-06 (box_operations #69, ver audit). (3) El resto (-11.000) son aperturas declaradas que no figuran como ingreso en el libro. Sin movimiento de efectivo."
)

DRY=0
DIAG=0
SOLO=""
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --diag)    DIAG=1 ;;
    *[!0-9]*)  echo "알 수 없는 인자: $a" >&2; exit 2 ;;
    # ★ 서랍을 **여러 개** 받는다. 하나만 받게 해 두었더니 남은 두 개를 돌리려고
    #   전체를 다시 실행했고, 이미 끝난 10건이 throttle 슬롯을 다 써서
    #   마지막 두 건이 429 가 났다(SENSITIVE_THROTTLE = 60초에 10건).
    *)         SOLO="$SOLO $a" ;;
  esac
done
SOLO="${SOLO# }"

# 이 실행에서 실제로 보낼 요청 수 — throttle 상한(10/분)을 넘으면 미리 알린다.
N_ENVIOS=0
for row in "${CAJAS[@]}"; do
  IFS='|' read -r _b _rest <<<"$row"
  if [ -z "$SOLO" ]; then
    N_ENVIOS=$((N_ENVIOS+1))
  else
    for x in $SOLO; do [ "$x" = "$_b" ] && N_ENVIOS=$((N_ENVIOS+1)); done
  fi
done
if [ "$DRY" -eq 0 ] && [ "$DIAG" -eq 0 ] && [ "$N_ENVIOS" -gt 10 ]; then
  echo "※ 이 실행은 요청 $N_ENVIOS 건입니다. 서버 상한은 60초에 10건이라"
  echo "  뒤쪽 건이 429 로 거부될 수 있습니다 — 서랍 번호를 인자로 나눠 주세요."
  echo "  예) $0 18 19"
  echo
fi

# ── 토큰 ────────────────────────────────────────────────────────────────
# TOKEN 이 없으면 물어본다. 비번이 화면·히스토리에 안 남는다.
# ★ JSON 은 python 이 만든다 — 비번에 " 나 \ 가 있어도 안 깨진다.
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

  echo "✓ 토큰 확보 (길이 ${#TOKEN})" >&2

  return 0
}

if [ "$DRY" -eq 0 ]; then
  if [ -z "${TOKEN:-}" ]; then
    echo "※ 로그인하면 **기존 세션이 끊깁니다** — 앱/웹에서 다시 로그인해야 합니다."
    obtener_token || exit 1
  fi

  # 권한 확인 — superadmin 전용 경로. 8번 호출한 뒤 403 을 보는 것보다 낫다.
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
  #
  # ★ `/auth/me` 로 재면 **안 된다.** 그 라우트는 request.user 를 안 보고
  #   Authorization 헤더에서 사용자를 다시 유도한다(auth.controller.ts getMe →
  #   authService.me(req.headers.authorization)). 대행이 정상이어도 storeId 가
  #   절대 안 바뀌므로 「헤더가 안 먹는다」는 **틀린 결론**이 나온다.
  #   `/auth/verify` 는 `@GetUser()` 로 request.user 를 그대로 돌려준다 — 이게 맞는 잣대다.
  if [ "$DIAG" -eq 1 ]; then
    echo "── 진단: X-Store-Id 대행 (GET /auth/verify — request.user 를 그대로 보여준다)"
    ver() { printf '%s' "$1" | python3 -c 'import sys,json
try: d=json.load(sys.stdin)
except Exception: print("(JSON 아님)"); raise SystemExit
u = d.get("user") or {}
print("storeId=", u.get("storeId"), " actingAsStoreId=", u.get("actingAsStoreId"),
      " roles=", u.get("roles"))' 2>/dev/null; }
    sin=$(curl -s --max-time 30 -H "Authorization: Bearer $TOKEN" "$API/auth/verify")
    con=$(curl -s --max-time 30 -H "Authorization: Bearer $TOKEN" -H 'X-Store-Id: 6' "$API/auth/verify")
    echo "  헤더 없이 : $(ver "$sin")"
    echo "  헤더 있이 : $(ver "$con")"
    echo
    echo "  ※ 헤더 있이 storeId=6 · actingAsStoreId=6 이면 정상입니다."
    exit 0
  fi
fi

printf '%-5s %-8s %-14s %-12s %s\n' BOX STORE MATCH THROUGH 설명
printf '%s\n' "------------------------------------------------------------------------"

ok=0; fail=0; yadone=0
for row in "${CAJAS[@]}"; do
  IFS='|' read -r box store through tienda desc motivo <<<"$row"
  [ -z "$motivo" ] && motivo="$NOTES"
  if [ -n "$SOLO" ]; then
    match=0
    for x in $SOLO; do [ "$x" = "$box" ] && match=1; done
    [ "$match" -eq 0 ] && continue
  fi

  printf '%-5s %-8s %-14s %-12s %s\n' "$box" "$store" "$tienda" "$through" "$desc"

  if [ "$DRY" -eq 1 ]; then
    continue
  fi

  # ★ el motivo lleva paréntesis, puntos y comas: lo serializa python, no la shell.
  body=$(python3 -c 'import json,sys;print(json.dumps({"through":sys.argv[1],"countedCash":0,"notes":sys.argv[2]}))' "$through" "$motivo")
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
    429)     fail=$((fail+1)); echo "      ✗ 429 요청 상한(60초에 10건) — 60초 뒤 이 서랍만 다시: $0 $box" ;;
    400)
      # ★ ERR-REG-004 는 실패가 아니라 **이미 정리됨**이다 — 이 경로는 멱등이다.
      #   2026-09-06 에 성공한 실행을 다시 돌려 10건이 전부 이 응답을 받았고,
      #   스크립트가 「실패 10」이라고 보고해 되돌려진 줄 알았다. 실제로는 정상이었다.
      if grep -q 'ERR-REG-004' "$out"; then
        yadone=$((yadone+1)); echo "      = 이미 정리됨 (ERR-REG-004 — 이 구간에 남은 세션 없음)"
      else
        fail=$((fail+1)); echo "      ✗ $code $(head -c 300 "$out")"
      fi
      ;;
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
  echo "성공 $ok · 이미 정리됨 $yadone · 실패 $fail"
  echo "확인: /caja → 정산 이력, 또는 감사 로그(Caja/edit)"
fi
