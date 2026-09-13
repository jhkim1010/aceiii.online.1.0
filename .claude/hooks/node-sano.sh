# node-sano.sh — 훅이 쓰는 `node` 가 **실제로 도는지** 확인하고, 안 돌면 고친다.
#
# `source` 전용이다. 실행 파일이 아니다.
#
# ★★★ 왜 있나 (2026-09-13 실측 — 훅 두 개가 며칠간 죽어 있었다).
#   이 환경의 `NODE_OPTIONS` 에는 cmux 가 만든
#   `--require=/var/folders/.../cmux-claude-node-options/restore-node-options.cjs`
#   가 들어 있다. **그 임시 파일이 사라지면 모든 node 실행이 `MODULE_NOT_FOUND`
#   로 즉사**한다. 그런데 두 훅은 첫 줄에서 node 로 훅 입력 JSON 을 파싱하고
#   그 실패를 `2>/dev/null` 로 삼킨다 → `CMD` 가 빈 문자열 → 커밋 매칭 실패 →
#   **`exit 0`**. 커밋 게이트도 CODEX 자동 검토도 **아무 말 없이 통과**했다.
#   유일한 흔적은 `.team/reviews/.auto-codex.heads` 가 2026-09-10 에 멈춘 것뿐이었고,
#   그것을 보는 사람이 없었다. [[watchdog-silence-modes-need-absence-alerts]] 그대로다.
#
# ★★ **패턴으로 `NODE_OPTIONS` 를 손보지 않는다 — 실제로 돌려 본다.**
#   「없는 `--require` 를 지운다」식으로 고치면 그 원인만 막힌다. 원인이 무엇이든
#   (preload 부재 · 잘못된 플래그 · 깨진 값) **증상은 하나** — node 가 안 돈다.
#   증상을 재는 편이 원인을 열거하는 것보다 좁고 정확하다.
#
# ★ 되돌리지 않는다: 한 번 비우면 이 훅이 끝날 때까지 비어 있다. 훅은 짧은 수명의
#   자식 프로세스라 세션에 영향이 없다.

# 성공하면 0, node 가 아예 못 돌면 1.
node_sano() {
  node -e '' >/dev/null 2>&1 && return 0

  local antes="${NODE_OPTIONS-}"
  unset NODE_OPTIONS
  if node -e '' >/dev/null 2>&1; then
    echo "[hook] ★ NODE_OPTIONS 가 node 를 죽이고 있었다 — 이 훅에서만 비웠다." >&2
    echo "[hook]   값: ${antes}" >&2
    echo "[hook]   세션 전체를 고치려면 없어진 preload 파일을 no-op 으로 다시 만들 것." >&2

    return 0
  fi

  export NODE_OPTIONS="$antes"
  echo "[hook] ★★ node 가 아예 안 돈다 — 이 훅은 **판정할 수 없다.**" >&2

  return 1
}

# 훅 입력 JSON 에서 명령 문자열을 꺼낸다. node 가 죽어 있으면 빈 문자열이 아니라
# **실패를 알린다** — 그래야 부르는 쪽이 「명령이 없었다」와 구별할 수 있다.
#   성공: 0 + stdout 에 명령
#   실패: 1 (stdout 비어 있음)
cmd_de_entrada() {
  local entrada="$1"
  local salida
  salida=$(printf '%s' "$entrada" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{try{process.stdout.write(JSON.parse(d).tool_input?.command||'')}catch{process.exit(3)}})" 2>/dev/null)
  local c=$?
  [ "$c" -ne 0 ] && return 1
  printf '%s' "$salida"

  return 0
}

# 입력이 커밋일 **가능성이 있는가** — node 없이, 원문 JSON 을 그대로 본다.
#
# ★★★ 정규식으로 「git 커밋 명령」을 맞히려 하지 않는다 (CODEX P1, 2026-09-13).
#   첫 판은 `git` 로 시작하는 형태만 잡아서 `/usr/bin/git commit` · `"git" commit` ·
#   `git -C <경로> commit` 을 **전부 놓쳤다** — 게이트가 fail-open 이 됐다.
#   빠진 형태를 하나씩 더하는 것은 지는 싸움이다. 우회형은 계속 나온다.
#
# ★★ 그래서 **판정을 포기하고 보수적으로 군다**: 원문에 `commit` 이 있으면 막는다.
#   이 함수는 **정상 경로가 아니다** — node 가 죽어 훅이 판정 자체를 못 하는
#   드문 상태에서만 불린다. 그 상태에서 과잉 차단의 대가는 「다시 시도하세요」이고,
#   과소 차단의 대가는 **검증 없는 커밋**이다. 둘은 같은 무게가 아니다.
#   (`git log` 처럼 무관한 명령까지 막힐 수 있다. 의도한 것이다 — 그때는 node 를
#    고치거나 `SKIP_VERIFY=1` 을 쓴다. 둘 다 사람이 알고 하는 선택이다.)
podria_ser_commit() {
  printf '%s' "$1" | grep -qi 'commit'
}
