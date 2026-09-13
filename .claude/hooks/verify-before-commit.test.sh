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

echo "── 통과해야 함 (오탐 금지) ──"
t pass  "ls -la"
t pass  "git commit -q -F -"
t pass  "git commit --author='A <a@b>' -m 'fix: x'"
t pass  "git -C api-ventago commit -q -F -"
t pass  "cd api-ventago && git commit -q -F -"
t pass  "git status --short"

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
FAKE=$(mktemp -d)
printf '#!/bin/sh\nexit 1\n' > "$FAKE/node"; chmod +x "$FAKE/node"
tenv block "git commit -m 'fix: x'" "PATH=$FAKE:/usr/bin:/bin"
tenv pass  "ls -la"                 "PATH=$FAKE:/usr/bin:/bin"
rm -rf "$FAKE"
