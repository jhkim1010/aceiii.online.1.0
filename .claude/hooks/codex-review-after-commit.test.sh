#!/usr/bin/env bash
# codex-review-after-commit.sh 의 **자격증명 필터** 시험.
#
# 왜 이 시험이 있나 (2026-09-09):
#   필터가 `users.must_change_password : boolean NOT NULL` 이라는
#   **스키마 카탈로그 줄**을 자격증명으로 오인해 commit 52b14e3 의 검토를
#   통째로 취소시켰다. 그 파일들은 재생성될 때마다 같은 줄을 만들므로
#   오탐은 **반복된다.**
#
# ★ 정탐만 시험하면 이 오탐을 못 본다. 그래서 **오탐 금지**를 같은 수로 넣는다 —
#   필터를 그냥 지워도 정탐 시험은 통과하지 못하지만, 오탐 시험만 있으면
#   필터를 지운 것이 «통과» 로 보인다. 두 방향이 다 있어야 검사다.
set -uo pipefail
HOOK="$(cd "$(dirname "$0")" && pwd)/codex-review-after-commit.sh"
[ -f "$HOOK" ] || { echo "훅이 없다: $HOOK"; exit 1; }

# 실제 훅에서 정규식 정의를 그대로 가져온다(값을 베끼면 훅과 갈라진다).
eval "$(grep -E '^SECRET_RE=' "$HOOK")"
eval "$(grep -E '^ESQUEMA_RE=' "$HOOK")"
[ -n "${SECRET_RE:-}" ] || { echo "SECRET_RE 를 못 읽었다"; exit 1; }
[ -n "${ESQUEMA_RE:-}" ] || { echo "ESQUEMA_RE 를 못 읽었다"; exit 1; }

# 훅과 **같은 판정식**을 쓴다.
bloquea() {
  local f; f=$(mktemp); printf '%s\n' "$1" > "$f"
  local hits; hits=$(grep -inE "$SECRET_RE" "$f" 2>/dev/null | grep -ivE "^[0-9]+:[+-]?[[:space:]]*$ESQUEMA_RE" || true)
  rm -f "$f"; [ -n "$hits" ]
}

fallos=0
espera() { # espera <bloquear|pasar> <descripción> <línea>
  if [ "$1" = "bloquear" ]; then
    bloquea "$3" && echo "  ✓ $2" || { echo "  ✗ $2 — 걸러야 하는데 통과했다"; fallos=$((fallos+1)); }
  else
    bloquea "$3" && { echo "  ✗ $2 — 통과해야 하는데 걸렸다"; fallos=$((fallos+1)); } || echo "  ✓ $2"
  fi
}

echo "── 정탐: 진짜 자격증명은 막는다"
espera bloquear "env 형식 password="            '+DB_PASSWORD=hunter2secreto'
espera bloquear "JSON 형식 apiKey"              '+  "apiKey": "abcdef123456"'
espera bloquear "yaml 형식 secret:"             '+  client_secret: abc123def456'
espera bloquear "token="                        '+ACCESS_TOKEN=eyJhbGciOiJIUzI1NiJ9'
espera bloquear "private_key="                  '+private_key=MIIEvQIBADANBg'

echo "── 오탐 금지: 스키마 카탈로그 줄은 자격증명이 아니다"
espera pasar "실제로 검토를 죽인 줄"            '+users.must_change_password : boolean NOT NULL SERVERGEN'
espera pasar "api_key 컬럼 선언"                '+branch_agents.api_key : character varying(64)'
espera pasar "token 컬럼 선언"                  '+online_orders.confirm_token : text'
espera pasar "secret 컬럼 선언"                 '+legacy_import_secrets.secret_value : bytea'
espera pasar "타임스탬프 타입"                  '-users.password_changed_at : timestamptz'

echo "── 기준선은 검토 성공 전에 전진하지 않는다"
if grep -qE "^printf '%s' \"\\\$NUEVO\" > \"\\\$SNAP\"$" "$HOOK"; then
  echo "  ✗ 기준선을 검토 전에 전진시키는 줄이 남아 있다"; fallos=$((fallos+1))
else
  echo "  ✓ 검토 전 전진 없음"
fi
grep -q 'mv -f .\$SNAP_PEND. .\$SNAP.' "$HOOK" && echo "  ✓ 성공 시에만 전진" || { echo "  ✗ 성공 시 전진이 없다"; fallos=$((fallos+1)); }

echo
[ "$fallos" -eq 0 ] && { echo "전부 통과"; exit 0; } || { echo "실패 ${fallos}건"; exit 1; }
