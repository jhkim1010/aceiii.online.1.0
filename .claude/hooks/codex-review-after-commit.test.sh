#!/usr/bin/env bash
# codex-review-after-commit.sh 의 **자격증명 필터** 시험.
#
# 왜 이 시험이 있나 (2026-09-09):
#   필터가 `users.must_change_password : <타입>` 이라는
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

# ★★ 시험 자료는 **조각으로 조립한다.** 통째로 적으면 자격증명 필터가 (옳게)
#   반응해서 **이 파일을 건드린 커밋의 검토가 통째로 막힌다** — 검토를 지키는
#   파일이 자기 검토를 막는 셈이다(2026-09-09 실측: commit 04b7df2 에서 그렇게 됐다).
#   조립하면 파일에는 그 형태가 없고, 시험은 실행 시점에 진짜 형태를 만든다.
#   ⤷ 필터를 약하게 만들어 피하지 않는다. **시험 자료 쪽을 바꾼다.**
EQ='='
CL=':'

echo "── 정탐: 진짜 자격증명은 막는다"
espera bloquear "env 형식 password="            "+DB_PASSWORD${EQ}hunter2secreto"
espera bloquear "JSON 형식 apiKey"              "+  \"apiKey\"${CL} \"abcdef123456\""
espera bloquear "yaml 형식 secret:"             "+  client_secret${CL} abc123def456"
espera bloquear "token="                        "+ACCESS_TOKEN${EQ}eyJhbGciOiJIUzI1NiJ9"
espera bloquear "private_key="                  "+private_key${EQ}MIIEvQIBADANBg"

echo "── 오탐 금지: 스키마 카탈로그 줄은 자격증명이 아니다"
espera pasar "실제로 검토를 죽인 줄"            "+users.must_change_password ${CL} boolean NOT NULL SERVERGEN"
espera pasar "api_key 컬럼 선언"                "+branch_agents.api_key ${CL} character varying(64)"
espera pasar "token 컬럼 선언"                  "+online_orders.confirm_token ${CL} text"
espera pasar "secret 컬럼 선언"                 "+legacy_import_secrets.secret_value ${CL} bytea"
espera pasar "타임스탬프 타입"                  "-users.password_changed_at ${CL} timestamptz"

echo "── 우회 금지: 스키마 모양으로 위장한 자격증명은 막는다"
# ★ [codex 지적 P1] 예외가 줄 앞부분만 보던 때 실제로 통과했던 형태들이다.
#   예외를 다시 느슨하게 만들면 **여기서 죽는다.**
espera bloquear "타입 뒤에 값을 붙인 위장" "+users.api_key ${CL} character varying(64) DEFAULT hunter2secretvalue"
espera bloquear "긴 타입 뒤 위장"          "+users.api_key ${CL} timestamp without time zone hunter2secretvalue"
espera bloquear "DEFAULT 로 위장"          "+config.password ${CL} integer DEFAULT supersecret123"

echo "── ★ 이 두 파일 자신이 필터에 걸리면 안 된다"
# 두 번 당했다(2026-09-09): 시험 자료와 **우회를 설명하는 주석**이 각각 자기 필터에
# 걸려, 이 파일을 건드린 커밋의 검토가 통째로 취소됐다.
# 필터를 약하게 만드는 것이 아니라 **여기 쓰는 예시의 형태**를 피하는 것이 답이다.
# 자기 자신을 검사해 두면 다음에 예시를 쓸 때 바로 안다.
propio=$(grep -inE "$SECRET_RE" "$HOOK" "$0" 2>/dev/null | grep -ivE "^[^:]+:[0-9]+:[+-]?[[:space:]]*$ESQUEMA_RE" || true)
if [ -z "$propio" ]; then
  echo "  ✓ 훅·시험 파일이 자기 필터에 걸리지 않는다"
else
  echo "  ✗ 자기 필터에 걸린다 — 예시를 <자리표시자> 로 바꾸거나 조각으로 조립할 것:"
  printf '%s\n' "$propio" | cut -c1-100 | sed 's/^/      /'
  fallos=$((fallos+1))
fi

echo "── ★ 락은 원자적이다 — 둘이 동시에 잡을 수 없다"
# [codex 지적 P1] 종전에는 부모가 락 **존재만 확인**하고 자식이 만들었다. 그 틈에
# 두 훅이 다 통과해 공용 diff·pending 을 덮어썼고, 쓰다 만 diff 를 검토하고도
# «성공» 이 되어 **미검토 변경까지 기준선이 삼킬** 수 있었다.
# 여기서는 훅이 쓰는 것과 **같은 방식**(mkdir)이 실제로 배타적인지 본다.
tmpd=$(mktemp -d)
ganadores=0
for i in 1 2 3 4 5; do
  ( mkdir "$tmpd/lock.d" 2>/dev/null && echo x >> "$tmpd/ganó" ) &
done
wait
ganadores=$(grep -c . "$tmpd/ganó" 2>/dev/null || echo 0)
rm -rf "$tmpd"
if [ "$ganadores" = "1" ]; then
  echo "  ✓ 5개가 동시에 시도해 1개만 잡았다"
else
  echo "  ✗ ${ganadores}개가 잡았다 — mkdir 이 배타적이지 않다"; fallos=$((fallos+1))
fi
# 훅이 실제로 그 방식을 쓰는가 (구현이 바뀌면 위 시험은 무의미해진다)
if grep -qE '^if ! mkdir "\$RUNDIR" 2>/dev/null; then' "$HOOK"; then
  echo "  ✓ 훅이 mkdir 로 락을 잡는다"
else
  echo "  ✗ 훅이 mkdir 로 락을 잡지 않는다 — 위 시험이 훅과 무관해졌다"; fallos=$((fallos+1))
fi
# 공용 경로로 되돌아가면 경합이 되살아난다
if grep -qE '(DIFF|PROMPT_FILE|SNAP_PEND)="\$RUNDIR/' "$HOOK"; then
  echo "  ✓ diff·prompt·pending 이 실행별 디렉터리 안에 있다"
else
  echo "  ✗ 공용 경로로 되돌아갔다 — 두 실행이 같은 파일을 쓴다"; fallos=$((fallos+1))
fi

echo "── 기준선은 검토 성공 전에 전진하지 않는다"
if grep -qE "^printf '%s' \"\\\$NUEVO\" > \"\\\$SNAP\"$" "$HOOK"; then
  echo "  ✗ 기준선을 검토 전에 전진시키는 줄이 남아 있다"; fallos=$((fallos+1))
else
  echo "  ✓ 검토 전 전진 없음"
fi
grep -q 'mv -f .\$SNAP_PEND. .\$SNAP.' "$HOOK" && echo "  ✓ 성공 시에만 전진" || { echo "  ✗ 성공 시 전진이 없다"; fallos=$((fallos+1)); }

echo
[ "$fallos" -eq 0 ] && { echo "전부 통과"; exit 0; } || { echo "실패 ${fallos}건"; exit 1; }
