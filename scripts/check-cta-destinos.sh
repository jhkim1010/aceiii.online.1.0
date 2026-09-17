#!/usr/bin/env bash
# [Phase 89] **막다른 CTA 를 막는다.**
#
# ★ 이 저장소에는 «없는 메뉴·없는 페이지로 보낸» 전례가 기록돼 있다. 버튼이 있는데
#   눌러도 아무 일이 없으면 기능은 없는 것과 같다. 그래서 «프론트가 부르는 경로» 와
#   «서버가 실제로 여는 경로» 를 **서로 다른 파일에서 읽어 대조한다.**
#   한쪽만 보면 둘이 같이 틀려도 통과한다.
#
# ★ 대조군: 존재하지 않는 경로를 같은 방식으로 검사했을 때 **반드시 실패해야** 한다.
#   그 판이 통과하면 이 스크립트는 아무것도 검사하지 않고 있는 것이다 → 종료코드 2.
#
# ★ grep 에 -a 를 붙인다 — 이 저장소의 일부 소스가 바이너리로 판정돼 조용히 0건이
#   나온 전례가 있다(memory: grep-needs-dash-a-in-this-repo). -F(고정 문자열)를 쓴다 —
#   경로 리터럴의 `.` 이 정규식 와일드카드가 되는 것을 막는다.
#
# ★ 5번째 짝(관리자 승인 화면)은 CTA 폼이 직접 링크하지 않는다 — CTA① 신청 뒤에
#   사람이 따로 여는 «다음 화면» 이다. 그래서 프론트 쪽 문자열은 그 화면이 실제로
#   불러오는 백엔드 엔드포인트 리터럴(`useResellersPending.ts` 의 `reseller/admin/pending`)
#   로 짝짓는다 — 존재하지 않는 문자열을 억지로 셀 수는 없다. 화면 파일 자체의 존재는
#   아래 (c) 에서 별도로 확인한다.
#
# 사용:
#   scripts/check-cta-destinos.sh                                    # 정적 대조만
#   API=http://localhost:5002/api scripts/check-cta-destinos.sh      # + 실제 HTTP 확인
#   APP=http://localhost:3050 API=... scripts/check-cta-destinos.sh  # + 프론트 라우트 HTTP 확인
# 종료코드: 도착지 없음 1 · 대조군이 통과 2 · 정상 0
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2

FAIL=0

# $1=file $2=pattern — 고정 문자열 카운트(바이너리 판정 무시). 못 찾아도 죽지 않는다.
count_in() {
  grep -aFc -- "$2" "$1" 2>/dev/null || true
}

file_exists() {
  [ -f "$1" ] && echo 1 || echo 0
}

echo "── (a) 정적 대조 — 프론트 ↔ 서버 ──"

# [1] CTA① reseller 신청
F1=$(count_in "ventago-app/src/views/m-stock/ResellerApplyForm.tsx" "reseller/auth/register")
B1A=$(count_in "api-ventago/src/app/reseller/auth/reseller-auth.controller.ts" "@Controller('reseller/auth')")
B1B=$(count_in "api-ventago/src/app/reseller/auth/reseller-auth.controller.ts" "@Post('register')")
echo "[1] CTA① reseller 신청 — 프론트 ${F1}건 / 도착지(@Controller ${B1A}건 · @Post('register') ${B1B}건)"
if [ "${F1:-0}" -lt 1 ] || [ "${B1A:-0}" -lt 1 ] || [ "${B1B:-0}" -lt 1 ]; then
  echo "  ✗ 짝이 없다"
  FAIL=1
fi

# [2] CTA③ 이탈 받이 리드
F2=$(count_in "ventago-app/src/views/m-stock/VentagoLeadForm.tsx" "public/ventago-leads")
B2A=$(count_in "api-ventago/src/app/leads/leads-public.controller.ts" "@Controller('public/ventago-leads')")
B2B=$(count_in "api-ventago/src/app/leads/leads-public.controller.ts" "@Post()")
echo "[2] 이탈 받이 리드 — 프론트 ${F2}건 / 도착지(@Controller ${B2A}건 · @Post() ${B2B}건)"
if [ "${F2:-0}" -lt 1 ] || [ "${B2A:-0}" -lt 1 ] || [ "${B2B:-0}" -lt 1 ]; then
  echo "  ✗ 짝이 없다"
  FAIL=1
fi

# [3] QR 공개 조회 (89-04 산출물 — 이 plan 이 만들진 않았지만 CTA 페이지 자체의 전제다)
F3=$(count_in "ventago-app/src/pages/m/stock/index.tsx" "public/qr-stock")
B3=$(count_in "api-ventago/src/app/print/qr-public.controller.ts" "@Controller('public/qr-stock')")
echo "[3] QR 공개 조회 — 프론트 ${F3}건 / 도착지 ${B3}건"
if [ "${F3:-0}" -lt 1 ] || [ "${B3:-0}" -lt 1 ]; then
  echo "  ✗ 짝이 없다"
  FAIL=1
fi

# [4] CTA② 주 도착지 — 가입 화면(+ 프리필 코드 존재, 89-12 산출물)
F4=$(count_in "ventago-app/src/views/m-stock/QrProductView.tsx" "/register?ref=")
D4=$(file_exists "ventago-app/src/pages/register/index.tsx")
P4=$(count_in "ventago-app/src/views/register/components/RegisterForm.tsx" "router.query.ref")
echo "[4] 가입 화면(/register?ref=) — 프론트 ${F4}건 / 파일존재 ${D4} / 프리필(router.query.ref) ${P4}건"
if [ "${F4:-0}" -lt 1 ] || [ "${D4}" -ne 1 ] || [ "${P4:-0}" -lt 1 ]; then
  echo "  ✗ 짝이 없다 — 링크는 있는데 프리필이 없으면 조용한 절반 실패다"
  FAIL=1
fi

# [5] 관리자 승인 화면(다음 화면) — 프론트는 그 화면이 실제로 부르는 엔드포인트 리터럴로 짝짓는다
F5=$(count_in "ventago-app/src/hooks/api/useResellersPending.ts" "reseller/admin/pending")
B5A=$(count_in "api-ventago/src/app/reseller/admin/reseller-admin.controller.ts" "@Controller('reseller/admin')")
B5B=$(count_in "api-ventago/src/app/reseller/admin/reseller-admin.controller.ts" "@Get('pending')")
echo "[5] 관리자 승인 화면(다음 화면) — 프론트 ${F5}건 / 도착지(@Controller ${B5A}건 · @Get('pending') ${B5B}건)"
if [ "${F5:-0}" -lt 1 ] || [ "${B5A:-0}" -lt 1 ] || [ "${B5B:-0}" -lt 1 ]; then
  echo "  ✗ 짝이 없다"
  FAIL=1
fi

echo
echo "── (b) 대조군 — 존재하지 않는 경로 ──"
CTRL_FRONT=$(count_in "ventago-app/src/views/m-stock/ResellerApplyForm.tsx" "public/no-existe-jamas")
CTRL_FRONT2=$(count_in "ventago-app/src/views/m-stock/VentagoLeadForm.tsx" "public/no-existe-jamas")
CTRL_BACK=$(count_in "api-ventago/src/app/leads/leads-public.controller.ts" "public/no-existe-jamas")
CTRL_TOTAL=$(( ${CTRL_FRONT:-0} + ${CTRL_FRONT2:-0} + ${CTRL_BACK:-0} ))
echo "대조군(public/no-existe-jamas) — 총 ${CTRL_TOTAL}건 (0 이어야 한다)"
if [ "$CTRL_TOTAL" -gt 0 ]; then
  echo "✗ 대조군이 통과했다(존재하지 않는 문자열이 잡혔다) — 이 스크립트는 아무것도 검사하지 않고 있다"
  exit 2
fi

echo
echo "── (c) 프론트 라우트 존재 (Pages Router = 파일이 곧 라우트) ──"
R1=$(file_exists "ventago-app/src/pages/m/stock/index.tsx")
R2=$(file_exists "ventago-app/src/pages/admin/revendedores.tsx")
echo "m/stock/index.tsx 존재: ${R1} · admin/revendedores.tsx 존재: ${R2}"
if [ "$R1" -ne 1 ] || [ "$R2" -ne 1 ]; then
  echo "  ✗ 프론트 라우트 파일이 없다"
  FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then
  echo
  echo "✗ 정적 대조 실패 — 도착지 부재"
  exit 1
fi

echo
echo "✓ 정적 대조 통과."

if [ -n "${API:-}" ]; then
  echo
  echo "── (d) 실제 HTTP 확인 (API=$API) ──"

  http_code() {
    curl -s -o /dev/null -w '%{http_code}' "$@"
  }

  c1=$(http_code -X POST "$API/public/ventago-leads" -H 'Content-Type: application/json' -d '{}')
  echo "POST /public/ventago-leads (빈 body) → ${c1} (400/429 기대, 404 면 실패)"
  [ "$c1" = "404" ] && { echo "  ✗ 404 — 도착지 없음"; FAIL=1; }

  c2=$(http_code -X POST "$API/reseller/auth/register")
  echo "POST /reseller/auth/register (빈 body) → ${c2} (400 기대, 404 면 실패)"
  [ "$c2" = "404" ] && { echo "  ✗ 404 — 도착지 없음"; FAIL=1; }

  c3=$(http_code "$API/public/qr-stock/999999/999999")
  echo "GET /public/qr-stock/999999/999999 → ${c3} (없는 상품이라 404 가 정상 — 연결 자체만 확인)"

  c4=$(http_code "$API/onboarding/referral/check?apodo=cool")
  echo "GET /onboarding/referral/check?apodo=cool → ${c4} (200 기대, @Public — 89-12 프리필의 검증 경로)"
  [ "$c4" = "404" ] && { echo "  ✗ 404 — 도착지 없음"; FAIL=1; }

  echo "  Throttle(429) 확인 — /reseller/auth/register 연속 호출 중..."
  GOT_429=0
  for _ in 1 2 3 4 5 6 7 8; do
    c=$(http_code -X POST "$API/reseller/auth/register")
    if [ "$c" = "429" ]; then
      GOT_429=1
      break
    fi
  done
  if [ "$GOT_429" -eq 1 ]; then
    echo "  ✓ 429 를 받았다 — Throttle 이 실제로 걸려 있다"
  else
    echo "  ✗ 429 를 못 받았다 — Throttle 확인 실패"
    FAIL=1
  fi

  if [ "$FAIL" -ne 0 ]; then
    echo
    echo "✗ 실제 HTTP 확인 실패"
    exit 1
  fi
fi

if [ -n "${APP:-}" ]; then
  echo
  echo "── 프론트 라우트 HTTP 확인 (APP=$APP) ──"
  app_code() {
    curl -sL -o /dev/null -w '%{http_code}' "$@"
  }
  c5=$(app_code "$APP/register?ref=cool")
  echo "GET /register?ref=cool → ${c5} (200 기대, 404 면 실패)"
  if [ "$c5" = "404" ]; then
    echo "✗ 404 — 프론트 라우트 없음"
    exit 1
  fi
fi

echo
echo "✓ 전체 통과."
exit 0
