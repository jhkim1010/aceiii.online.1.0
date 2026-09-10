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

echo "── ★ 훅을 실제로 돌린다 (가짜 codex · 임시 저장소)"
# ★★ [CODEX P2 · 2026-09-09] 종전 시험은 임시 디렉터리에서 **순수 `mkdir` 배타성**만
#   보고, 훅과의 연결은 **소스 문자열 grep** 으로 판정했다. 그러면 결함 있는 현재
#   구현이 그대로 정답이 된다 — 락 로직을 무엇으로 바꿔도 시험은 통과했다.
#   → 여기서는 **훅 파일을 그대로 실행한다.** PATH 에 가짜 `codex` 를 깔아 25분이
#     아니라 즉시 끝나게 할 뿐, 훅의 분기는 전부 진짜 것이 돈다.

# ★ 진짜 검토가 돌고 있으면 훅은 (옳게) 비켜 준다 — 그러면 아래 시험이 전부 무의미하다.
#   조용히 통과시키지 않는다. 「부재」에서 침묵하지 않는 것이 이 저장소의 규칙이다.
omitidos=0
if pgrep -f 'codex exec' >/dev/null 2>&1; then
  echo "  ⚠ 진짜 CODEX 검토가 돌고 있다 — 훅 실행 시험을 건너뛴다(통과가 아니다)"
  omitidos=1
fi

preparar() {  # → 임시 프로젝트 경로
  local d; d=$(mktemp -d)
  mkdir -p "$d/.team/reviews" "$d/bin"
  git init -q "$d" >/dev/null 2>&1
  git -C "$d" config user.email t@t >/dev/null 2>&1
  git -C "$d" config user.name t >/dev/null 2>&1
  git -C "$d" config commit.gpgsign false >/dev/null 2>&1
  printf 'linea %s\n' 1 2 3 4 5 6 7 8 > "$d/archivo.ts"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" commit -qm "primer commit" >/dev/null 2>&1
  cat > "$d/bin/codex" <<'FALSO'
#!/usr/bin/env bash
[ "${1:-}" = "--version" ] && { echo "codex-falso 0.0.0"; exit 0; }
[ "${CODEX_FALSO_FALLA:-0}" = "1" ] && { echo "fallo simulado"; exit 1; }
sleep "${CODEX_FALSO_DEMORA:-0}"
printf 'codex\n지적할 P1/P2/P3 결함 없음.\n'
FALSO
  chmod +x "$d/bin/codex"
  echo "$d"
}

correr() {  # <proyecto> → 훅 실행, stderr 를 echo
  printf '{"tool_input":{"command":"git commit -m x"}}' \
    | PATH="$1/bin:$PATH" CLAUDE_PROJECT_DIR="$1" bash "$HOOK" 2>&1
}

hay_informe() {  # <proyecto> — 보고서가 생길 때까지 최대 ~10초
  local i=0
  while [ "$i" -lt 100 ]; do
    ls "$1"/.team/reviews/auto-*.md >/dev/null 2>&1 && return 0
    sleep 0.1; i=$((i + 1))
  done
  return 1
}

if [ "$omitidos" = "0" ]; then
  # ① 정탐 — 검토가 실제로 돌고, 성공했으니 기준선이 전진한다.
  p=$(preparar); correr "$p" >/dev/null 2>&1
  if hay_informe "$p" && grep -qF '.=' "$p/.team/reviews/.auto-codex.heads" 2>/dev/null; then
    echo "  ✓ 검토가 돌고 기준선이 전진한다"
  else
    echo "  ✗ 검토가 안 돌거나 기준선이 안 전진했다"; fallos=$((fallos+1))
  fi
  rm -rf "$p"

  # ② 반대 방향 — 검토가 **실패**하면 기준선은 전진하지 않는다.
  #   (①만 있으면 「항상 전진」으로 만들어도 통과한다. 두 방향이 다 있어야 검사다.)
  p=$(preparar); CODEX_FALSO_FALLA=1 correr "$p" >/dev/null 2>&1
  if hay_informe "$p" && [ ! -f "$p/.team/reviews/.auto-codex.heads" ]; then
    echo "  ✓ 검토 실패 시 기준선이 전진하지 않는다"
  else
    echo "  ✗ 검토가 실패했는데 기준선이 전진했다(그 커밋은 영구 미검토가 된다)"; fallos=$((fallos+1))
  fi
  rm -rf "$p"

  # ③ 겹침 방지 — codex 가 돌고 있으면 새로 띄우지 않는다.
  p=$(preparar)
  CODEX_FALSO_DEMORA=10 "$p/bin/codex" exec --sandbox read-only x >/dev/null 2>&1 &
  bg=$!; sleep 0.4
  salida=$(correr "$p")
  kill "$bg" 2>/dev/null; wait "$bg" 2>/dev/null
  if printf '%s' "$salida" | grep -q '이미 검토가 돌고 있다' && ! ls "$p"/.team/reviews/auto-*.md >/dev/null 2>&1; then
    echo "  ✓ 검토가 돌고 있으면 새로 띄우지 않는다"
  else
    echo "  ✗ 겹쳐서 띄웠다"; fallos=$((fallos+1))
  fi
  rm -rf "$p"

  # ④ ★ 회귀 — **죽은 실행이 남긴 잔여물이 다음 검토를 막지 않는다.**
  #   옛 구현에서는 이 빈 디렉터리 하나가 곧 락이라, 이후 **모든 커밋이 영구 침묵**했다
  #   (CODEX P1). 지금은 작업 공간이 mktemp 라 잔여물이 판정에 쓰이지 않는다.
  p=$(preparar)
  mkdir -p "$p/.team/reviews/.auto-codex.run.d"   # ← 옛 고정 경로, pid 없음
  correr "$p" >/dev/null 2>&1
  if hay_informe "$p"; then
    echo "  ✓ 죽은 잔여물이 있어도 검토가 돈다"
  else
    echo "  ✗ 잔여물 때문에 검토가 멈췄다 — 영구 침묵이 되살아났다"; fallos=$((fallos+1))
  fi

  # ★★ 대조군 — 같은 잔여물에 **옛 로직**을 적용하면 비켜 준다(=영구 침묵).
  #   대조군까지 통과하면 ④ 는 아무것도 구별하지 않는 것이다.
  control() {  # 옛 구현 그대로: 고정 경로 mkdir 실패 + pid 없음 → 비켜 준다
    local rd="$1" pid
    mkdir "$rd" 2>/dev/null && { echo toma; return; }
    pid=$(cat "$rd/pid" 2>/dev/null)
    [ -z "$pid" ] && { echo cede; return; }
    kill -0 "$pid" 2>/dev/null && echo cede || echo toma
  }
  if [ "$(control "$p/.team/reviews/.auto-codex.run.d")" = "cede" ]; then
    echo "  ✓ 대조군(옛 로직)은 같은 잔여물에서 멈춘다 — ④ 가 실제로 구별한다"
  else
    echo "  ✗ 대조군도 통과한다 — ④ 는 아무것도 검사하지 않는다"; fallos=$((fallos+1))
  fi
  rm -rf "$p"

  # ⑤ ★★ 자격증명 필터가 **훅에서 실제로 집행되는가.**
  #   위쪽 필터 시험 14개는 훅의 정규식을 `eval` 해 와서 **자기 판정식**으로 검사한다.
  #   그래서 훅의 `if [ -n "$SECRET_HITS" ]` 를 통째로 지워도 14개가 전부 통과했다
  #   (2026-09-10 돌연변이로 실측). 정규식이 맞는 것과 그것이 전송을 막는 것은 다르다.
  #   → 자격증명이 든 커밋을 만들어 **보고서가 안 생기는지**로 본다.
  p=$(preparar)
  { printf 'linea %s\n' 9 10 11 12 13 14; printf 'DB_PASSWORD%shunter2secreto\n' "$EQ"; } > "$p/config.env"
  git -C "$p" add -A >/dev/null 2>&1
  git -C "$p" commit -qm "con credencial" >/dev/null 2>&1
  salida=$(correr "$p")
  sleep 0.5
  if printf '%s' "$salida" | grep -q '외부로 보내지 않는다' \
     && ! ls "$p"/.team/reviews/auto-*.md >/dev/null 2>&1 \
     && [ ! -f "$p/.team/reviews/.auto-codex.heads" ]; then
    echo "  ✓ 자격증명이 든 diff 는 전송되지 않는다(그리고 기준선도 안 전진한다)"
  else
    echo "  ✗ 자격증명이 든 diff 가 외부로 나갔다"; fallos=$((fallos+1))
  fi
  # ★ 값을 로그에 되뿜지 않는다 — 막으면서 같은 비밀을 세션 로그에 남기면 소용없다.
  if printf '%s' "$salida" | grep -q 'hunter2secreto'; then
    echo "  ✗ 걸린 값을 stderr 에 되뿜었다"; fallos=$((fallos+1))
  else
    echo "  ✓ 걸린 값을 되뿜지 않는다(위치·개수만)"
  fi
  rm -rf "$p"
fi


echo
[ "$fallos" -eq 0 ] && { echo "전부 통과"; exit 0; } || { echo "실패 ${fallos}건"; exit 1; }
