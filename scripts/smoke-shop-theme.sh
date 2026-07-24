#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# smoke-shop-theme.sh — Phase 61 테마 확장 스모크
#
# tienda-app 에 테스트 프레임워크가 없으므로(jest/vitest 0건), 자동 테스트가
# 없는 경로(업로드 검증 / 공개 테마 HTML) 를 curl 로 재현 가능하게 검증한다.
# 이후 모든 Wave(A2/B/C) 가 이 스크립트를 확장해 재사용한다.
#
# 사용법:
#   API_HOST=http://localhost:5002/api SHOP_HOST=http://localhost:3060 \
#   STORE_ID=9 EDIT_TOKEN=xxx ./scripts/smoke-shop-theme.sh
#
# EDIT_TOKEN 미설정 시 업로드/인가 체크(3~7)는 SKIP 하고 조회 체크(1~2)만 수행한다.
# SHOP_HOST 미설정 시 체크 8(공개 HTML)은 SKIP 한다.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

API_HOST="${API_HOST:-http://localhost:5002/api}"
SHOP_HOST="${SHOP_HOST:-}"
STORE_ID="${STORE_ID:-9}"
EDIT_TOKEN="${EDIT_TOKEN:-}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# 1x1 투명 png (base64 리터럴, ~68바이트) — 유효 이미지 업로드 성공 케이스용
PNG_1X1_B64="iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="

pass() { echo "PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
skip() { echo "SKIP: $1"; SKIP_COUNT=$((SKIP_COUNT + 1)); }

# ── 체크 1~2: 공개 테마 조회 ────────────────────────────────────────────────
# curl 연결 실패(서버 미기동)가 set -e 로 스크립트를 죽이지 않도록 || true 로 방어
theme_body="$(curl -s -w '\n%{http_code}' "${API_HOST}/public/shop/${STORE_ID}/theme" 2>/dev/null || echo -e "\n000")"
theme_status="$(echo "$theme_body" | tail -n1)"
theme_json="$(echo "$theme_body" | sed '$d')"

if [ "$theme_status" = "200" ] \
  && echo "$theme_json" | grep -q '"cssVars"' \
  && echo "$theme_json" | grep -q -- '--on-navy'; then
  pass "1. GET /public/shop/:storeId/theme → 200 + cssVars + --on-navy"
else
  fail "1. GET /public/shop/:storeId/theme (status=${theme_status})"
fi

if echo "$theme_json" | grep -q '"content"'; then
  pass "2. theme 응답에 content 키 포함"
else
  fail "2. theme 응답에 content 키 없음"
fi

# ── 체크 3~7: 업로드 검증 + 인가 (EDIT_TOKEN 필요) ──────────────────────────
if [ -z "$EDIT_TOKEN" ]; then
  skip "3. 업로드 거부(확장자) — EDIT_TOKEN 미설정"
  skip "4. 업로드 거부(크기) — EDIT_TOKEN 미설정"
  skip "5. 업로드 거부(영상 확장자) — EDIT_TOKEN 미설정"
  skip "6. 업로드 성공(logo png) — EDIT_TOKEN 미설정"
  skip "7. 인가 실패(토큰 없음) — EDIT_TOKEN 미설정"
  echo ""
  echo "결과: PASS=${PASS_COUNT} FAIL=${FAIL_COUNT} SKIP=${SKIP_COUNT} (EDIT_TOKEN 미설정 — 조회만 수행, exit 0)"
  exit 0
else
  # 신규 엔드포인트: POST /shop/:storeId/theme/asset?kind=... (StoreThemeEditGuard)
  asset_url="${API_HOST}/shop/${STORE_ID}/theme/asset"

  # 3. theme/asset 확장자 거부 (.exe)
  exe_file="${TMP_DIR}/evil.exe"
  printf 'MZ-fake-binary' > "$exe_file"
  status="$(curl -s -o /dev/null -w '%{http_code}' \
    -X POST "${asset_url}?kind=logo" \
    -H "Authorization: Bearer ${EDIT_TOKEN}" \
    -F "file=@${exe_file};type=application/octet-stream")"
  [ "$status" = "400" ] && pass "3. theme/asset .exe 업로드 → 400" || fail "3. theme/asset .exe 업로드 (status=${status})"

  # 4. theme/asset 크기 거부 (3MB 더미 png)
  big_file="${TMP_DIR}/big.png"
  dd if=/dev/zero of="$big_file" bs=1024 count=3072 >/dev/null 2>&1
  status="$(curl -s -o /dev/null -w '%{http_code}' \
    -X POST "${asset_url}?kind=logo" \
    -H "Authorization: Bearer ${EDIT_TOKEN}" \
    -F "file=@${big_file};type=image/png")"
  [ "$status" = "400" ] && pass "4. theme/asset 3MB png 업로드 → 400" || fail "4. theme/asset 3MB png 업로드 (status=${status})"

  # 5. theme/asset 영상 확장자 거부 (.mov)
  mov_file="${TMP_DIR}/clip.mov"
  dd if=/dev/zero of="$mov_file" bs=1024 count=1 >/dev/null 2>&1
  status="$(curl -s -o /dev/null -w '%{http_code}' \
    -X POST "${asset_url}?kind=reelVideo" \
    -H "Authorization: Bearer ${EDIT_TOKEN}" \
    -F "file=@${mov_file};type=video/quicktime")"
  [ "$status" = "400" ] && pass "5. theme/asset .mov 업로드(reelVideo) → 400" || fail "5. theme/asset .mov 업로드 (status=${status})"

  # 6. theme/asset 유효 png 업로드 성공
  logo_file="${TMP_DIR}/logo.png"
  echo "$PNG_1X1_B64" | base64 -d > "$logo_file" 2>/dev/null \
    || echo "$PNG_1X1_B64" | base64 --decode > "$logo_file"
  upload_body="$(curl -s -w '\n%{http_code}' \
    -X POST "${asset_url}?kind=logo" \
    -H "Authorization: Bearer ${EDIT_TOKEN}" \
    -F "file=@${logo_file};type=image/png")"
  upload_status="$(echo "$upload_body" | tail -n1)"
  upload_json="$(echo "$upload_body" | sed '$d')"
  if { [ "$upload_status" = "200" ] || [ "$upload_status" = "201" ]; } \
    && echo "$upload_json" | grep -q '"fileName"' \
    && echo "$upload_json" | grep -q 'theme_logo_'; then
    pass "6. theme/asset 유효 png(logo) 업로드 → fileName=theme_logo_*"
  else
    fail "6. theme/asset 유효 png(logo) 업로드 (status=${upload_status}, body=${upload_json})"
  fi

  # 7. theme/asset 인가 실패 — 토큰 없이 동일 업로드
  status="$(curl -s -o /dev/null -w '%{http_code}' \
    -X POST "${asset_url}?kind=logo" \
    -F "file=@${logo_file};type=image/png")"
  [ "$status" = "401" ] && pass "7. theme/asset 토큰 없이 업로드 → 401" || fail "7. theme/asset 토큰 없이 업로드 (status=${status})"
fi

# ── 체크 8: 공개 스토어프런트 HTML (선택) ────────────────────────────────────
if [ -n "$SHOP_HOST" ]; then
  html="$(curl -s "${SHOP_HOST}/${STORE_ID}" 2>/dev/null || echo '')"
  if echo "$html" | grep -q 'data-macro='; then
    pass "8. 공개 HTML data-macro= 존재"
  else
    fail "8. 공개 HTML data-macro= 없음"
  fi
else
  skip "8. 공개 HTML 확인 — SHOP_HOST 미설정"
fi

# ── 결과 요약 ────────────────────────────────────────────────────────────────
echo ""
echo "결과: PASS=${PASS_COUNT} FAIL=${FAIL_COUNT} SKIP=${SKIP_COUNT}"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi

exit 0
