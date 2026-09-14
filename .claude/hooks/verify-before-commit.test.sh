#!/bin/bash
# verify-before-commit.sh 전수 시험 — `bash .claude/hooks/verify-before-commit.test.sh`
#
# 훅 전수 시험 — 정탐(막아야 함)과 오탐(통과해야 함)을 함께 본다.
# 대조군이 없으면 "무조건 막는 훅" 도 정탐 시험만으로는 통과해 보인다.
cd /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0 || exit 1
H=.claude/hooks/verify-before-commit.sh

t() {
  esperado="$1"; shift
  cmd="$1"
  r=$(printf '{"tool_input":{"command":%s}}' "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$cmd")" \
      | CLAUDE_PROJECT_DIR="$PWD" bash "$H" 2>&1)
  c=$?
  if [ "$esperado" = "block" ] && [ "$c" = "2" ]; then v="OK  "
  elif [ "$esperado" = "pass" ] && [ "$c" = "0" ]; then v="OK  "
  else v="FALLO"; fi
  printf '  %s (esperado=%s exit=%s)  %s\n' "$v" "$esperado" "$c" "$(printf '%s' "$cmd" | head -c 62 | tr '\n' ' ')"
}

echo "── 막아야 함 ──"
t block "git commit -a -m 'fix: x'"
t block "git commit -am 'fix: x'"
t block "git commit -m 'fix: x' -- src/a.ts"

echo "── ★ git add 와 git commit 이 한 명령에 있으면 막는다 (2026-09-14 실측 구멍) ──"
# PreToolUse 라 add 의 결과를 볼 수 없다 → 검사가 하나도 안 돌고 통과했다.
t block "git add src/a.ts && git commit -m 'fix: x'"
t block "git add -A; git commit -m 'fix: x'"
t block "git -C api-ventago add src/a.ts && git -C api-ventago commit -F -"
t block "git stage src/a.ts && git commit -m 'fix: x'"

echo "── 통과해야 함 (오탐 금지) ──"
t pass  "ls -la"
t pass  "git commit -q -F -"
t pass  "git commit --author='A <a@b>' -m 'fix: x'"
t pass  "git -C api-ventago commit -q -F -"
t pass  "cd api-ventago && git commit -q -F -"
t pass  "git status --short"
t pass  "git add src/a.ts"                      # add 만 있으면 커밋이 아니다 → 통과

# ★ 핵심 오탐: heredoc 본문에 git 명령이 들어 있는 경우
printf -v _ '' 2>/dev/null
CMD_HEREDOC="$(cat <<'OUTER'
python3 - <<'PY'
print("git commit -a -m 'x'")
print("git commit -- src/a.ts")
PY
OUTER
)"
t pass "$CMD_HEREDOC"

CMD_MSG="$(cat <<'OUTER'
git commit -q -F - <<'MSG'
fix: 설명에 git commit -a 와 -- 경로를 인용한다
MSG
OUTER
)"
t pass "$CMD_MSG"

# ── ★★★ node 가 죽어 있을 때 (2026-09-13 실제 사고) ────────────────────────────
#
# NODE_OPTIONS 의 `--require` preload 파일이 사라지면 모든 node 실행이 즉사한다.
# 이 훅은 훅 입력 JSON 을 node 로 파싱하고 그 실패를 삼키므로, 종전에는 `CMD` 가
# 비어 커밋 매칭이 실패하고 **모든 커밋이 조용히 통과**했다. 며칠간 그랬다.
#
# ★ 대조군을 함께 둔다 — 오염된 상태에서도 무해한 명령은 통과해야 한다.
#   그것이 없으면 「무조건 막는 훅」도 이 시험을 통과한다.
tenv() { # tenv <esperado> <cmd> [VAR=val ...]
  esperado="$1"; cmd="$2"; shift 2
  r=$(printf '{"tool_input":{"command":%s}}' "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$cmd")" \
      | env "$@" CLAUDE_PROJECT_DIR="$PWD" bash "$H" 2>&1)
  c=$?
  if [ "$esperado" = "block" ] && [ "$c" = "2" ]; then v="OK  "
  elif [ "$esperado" = "pass" ] && [ "$c" = "0" ]; then v="OK  "
  else v="FALLO"; fi
  printf '  %s (esperado=%s exit=%s)  %s\n' "$v" "$esperado" "$c" "$(printf '%s' "$cmd" | head -c 52 | tr '\n' ' ')"
}

echo "── NODE_OPTIONS 오염 (없는 preload) — 훅이 스스로 복구해야 함 ──"
ROTO="--require=/no/existe/$$-preload.cjs"
tenv block "git commit -a -m 'fix: x'" "NODE_OPTIONS=$ROTO"
tenv pass  "ls -la"                    "NODE_OPTIONS=$ROTO"

echo "── node 자체가 안 돌 때 — 커밋만 fail-closed, 나머지는 통과 ──"
# ★ [CODEX P1] 종전 판은 원문을 정규식으로 「git 커밋」인지 맞히려 했고,
#   아래 형태들을 **전부 놓쳐 fail-open** 이었다. 우회형을 하나씩 더하는 대신
#   판정을 포기하고 보수적으로 군다(`podria_ser_commit`). 그 증거로 전부 막힌다.
FAKE=$(mktemp -d)
printf '#!/bin/sh\nexit 1\n' > "$FAKE/node"; chmod +x "$FAKE/node"
tenv block "git commit -m 'fix: x'"              "PATH=$FAKE:/usr/bin:/bin"
tenv block "/usr/bin/git commit -m 'fix: x'"     "PATH=$FAKE:/usr/bin:/bin"
tenv block "\"git\" commit -m 'fix: x'"          "PATH=$FAKE:/usr/bin:/bin"
tenv block "git -C api-ventago commit -m 'x'"    "PATH=$FAKE:/usr/bin:/bin"
tenv block "cd api-ventago && git commit -F -"   "PATH=$FAKE:/usr/bin:/bin"
tenv pass  "ls -la"                              "PATH=$FAKE:/usr/bin:/bin"
tenv pass  "npm test"                            "PATH=$FAKE:/usr/bin:/bin"
rm -rf "$FAKE"

echo "── ★ node 는 도는데 입력 JSON 을 못 읽을 때 (CODEX P1) ──"
# 종전 판은 이 경우 `CMD=""` 로 떨어져 **조용히 전체 통과**했다 —
# 고치려던 결함이 다른 가지에 그대로 남아 있었다.
craudo() { # craudo <esperado> <입력 원문 그대로>
  r=$(printf '%s' "$2" | CLAUDE_PROJECT_DIR="$PWD" bash "$H" 2>&1); c=$?
  if [ "$1" = "block" ] && [ "$c" = "2" ]; then v="OK  "
  elif [ "$1" = "pass" ] && [ "$c" = "0" ]; then v="OK  "
  else v="FALLO"; fi
  printf '  %s (esperado=%s exit=%s)  %s\n' "$v" "$1" "$c" "$(printf '%s' "$2" | head -c 48)"
}
craudo block 'no-es-json-en-absoluto: git commit -m x'
# ★ 커밋을 언급하지 않는 해석 불가 입력은 **막지 않는다** — 모든 Bash 를 세울 수는 없다.
#   다만 판정하지 못했다는 사실은 **반드시 말해야** 한다(그 침묵이 이 결함의 전부였다).
craudo pass  '{"tool_input":{"command":'
craudo pass  'no-es-json-y-tampoco-menciona-nada'

sal=$(printf '%s' '{"tool_input":{"command":' | CLAUDE_PROJECT_DIR="$PWD" bash "$H" 2>&1)
if printf '%s' "$sal" | grep -q '해석할 수 없다'; then
  echo "  OK   해석 불가를 말한다(조용히 통과하지 않는다)"
else
  echo "  FALLO 해석에 실패했는데 아무 말이 없다 — 이것이 바로 그 결함이다"
fi
