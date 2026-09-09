#!/bin/bash
# verify-before-commit.sh — PreToolUse(Bash) 훅: **커밋 전에 로컬 검증을 강제한다.**
#
# 왜 있나 (2026-09-09): 이 저장소에는 코드를 검사하는 자동 장치가 **없었다.**
#   · git hook / husky      → 없음
#   · gsd-validate-commit   → 커밋 **메시지 형식**만 본다
#   · Jenkins api           → `npm run build`(컴파일)만. 테스트 없음
#   · GitHub Actions jest   → 최근 20건 중 19건이 30분 타임아웃으로 `cancelled` —
#                             **19회 연속 무판정**이었다. 통보조차 못 했다
#   즉 실제 게이트는 사람이 손으로 돌리는 것 하나뿐이었고, 빠뜨리면 아무도 안 잡는다.
#
# ★ 커밋 지점을 고른 이유: 「기능을 고친 뒤」의 자연스러운 경계다. 파일 저장마다 돌리면
#   한 기능을 여러 파일로 고치는 동안의 **중간 상태**가 계속 오류를 낸다.
#
# ★ 무엇을 게이트로 삼는가 — **막을 수 있는 것만** 막는다:
#   · tsc            : 두 앱 모두 0 이어야 한다 (api 4.0s · app 2.1s 실측)
#   · app eslint     : 프론트는 warning 도 빌드를 막으므로 staged 파일이 0 이어야 한다
#   · api eslint     : **게이트로 쓰지 않는다.** 기존 오류가 파일당 수십~수백 개다
#                      (cashRegister.service.ts 만 122개). 0 을 요구하면 아무것도 커밋 못 한다.
#                      대신 **HEAD 대비 증가**했을 때만 막는다 — 내가 새로 만든 것만 책임진다.
#   · print-agent    : smoke 전부 통과 (1초 미만)
#   · jest           : staged 파일과 관련된 suite 만 (`--findRelatedTests`)
#
# ★ jest 는 반드시 `--maxWorkers=1`. 2 워커면 랜덤 suite 가 죽고, 옵션 없이 돌리면
#   이 기계에서 메모리가 20GB 를 넘는다(실측). 시간 상한도 둔다.
#
# 건너뛰기: 커밋 명령 앞에 `SKIP_VERIFY=1` 을 붙인다. 그러면 이 훅이 **왜 건너뛰는지**
#   를 찍고 통과시킨다 — 조용히 꺼지지 않는다.
#
# 설치: .claude/settings.json 의 PreToolUse(matcher: Bash)

INPUT=$(cat)

CMD=$(printf '%s' "$INPUT" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{try{process.stdout.write(JSON.parse(d).tool_input?.command||'')}catch{}})" 2>/dev/null)

# ★★ **heredoc 본문을 먼저 잘라낸다.**
#
#   훅에 오는 것은 명령 문자열 전체다. 내 작업에는 `python3 - <<'PY' ... PY` 처럼
#   **본문에 셸/깃 명령을 담은** 호출이 흔하다. 종전에는 그 본문까지 훑어서
#   "커밋 명령" 으로 오인하고 차단했다 — 실전 첫 커밋에서 바로 걸렸고,
#   그 뒤 훅을 고치는 명령까지 막혔다(자기 발을 묶는 형태다).
#
#   본문은 **명령이 아니라 데이터**다. 검사 대상에서 제외한다.
CMD=$(printf '%s' "$CMD" | node -e '
  let d = "";
  process.stdin.on("data", c => (d += c));
  process.stdin.on("end", () => {
    const lineas = d.split("\n");
    const salida = [];
    let tag = null;
    for (const l of lineas) {
      if (tag !== null) {
        // heredoc 종료: 태그만 있는 줄(<<- 는 앞 탭 허용)
        if (l.trim() === tag) tag = null;
        continue;
      }
      // 같은 줄에 여러 개가 올 수 있으나, 첫 번째만으로 충분하다(그 뒤는 본문이다).
      const m = l.match(/<<-?\s*(["\x27]?)([A-Za-z_][A-Za-z0-9_]*)\1/);
      if (m) {
        tag = m[2];
        salida.push(l.slice(0, m.index));   // 리다이렉트 앞부분만 명령으로 본다
        continue;
      }
      salida.push(l);
    }
    process.stdout.write(salida.join("\n"));
  });
' 2>/dev/null)

# ── 이 명령이 커밋인가 ──
#
# ★ [codex 지적] `*"git commit"*` 만 보면 **`git -C <path> commit`** 을 놓친다 —
#   그 형태에는 "git commit" 이라는 연속 문자열이 없다. 정상적인 git 사용법 하나로
#   게이트가 통째로 우회됐다. 토큰 단위로 본다.
if ! printf '%s' "$CMD" | grep -qE '(^|[;&|[:space:]])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]]+)?)*[[:space:]]+commit([[:space:]]|$)'; then
  exit 0
fi

# --amend / --no-verify 는 손대지 않는다(의도적 조작).
case "$CMD" in
  *--amend*|*--no-verify*) exit 0 ;;
esac

# ★★ [codex 지적 · P1] **`git commit -a` 는 이 게이트를 통째로 우회한다.**
#   훅은 실행 **전**의 index(staged)를 본다. `-a` 가 워킹트리를 stage 하는 것은
#   훅이 끝난 **뒤** git 이 하는 일이라, 그 변경은 tsc·eslint·jest 를 하나도 거치지
#   않고 커밋된다. 「commit 전 차단」이라는 선언이 흔한 명령 하나로 무너진다.
#   같은 이유로 `git commit -- <경로>`(pathspec) 도 index 밖의 것을 커밋한다.
#   → 검사할 수 없으므로 **거절한다.** 명시적으로 `git add` 한 뒤 커밋하게 한다.
if printf '%s' "$CMD" | grep -qE '(^|[[:space:]])(-a|--all|-am|-[a-zA-Z]*a[a-zA-Z]*)([[:space:]]|$)'; then
  # `-a` 를 포함하는 짧은 묶음 플래그(-am 등)까지 본다. `--author` 같은 긴 옵션은 제외.
  if ! printf '%s' "$CMD" | grep -qE '(^|[[:space:]])--a(uthor|ll-match)'; then
    node -e 'process.stdout.write(JSON.stringify({
      decision: "block",
      reason: "`git commit -a` 계열은 검증을 우회한다 — 훅은 실행 전의 index 만 볼 수 있고, -a 가 stage 하는 것은 훅 이후에 일어난다. 변경 파일을 `git add` 로 명시한 뒤 커밋하세요(다른 세션의 WIP 오염도 그래야 막힌다)."
    }))'
    exit 2
  fi
fi
if printf '%s' "$CMD" | grep -qE 'commit[^|;&]*[[:space:]]--[[:space:]]'; then
  node -e 'process.stdout.write(JSON.stringify({
    decision: "block",
    reason: "`git commit -- <경로>` 는 index 밖의 내용을 커밋하므로 검증 대상과 실제 커밋 내용이 갈라진다. `git add <경로>` 후 커밋하세요."
  }))'
  exit 2
fi

if printf '%s' "$CMD" | grep -q 'SKIP_VERIFY=1'; then
  echo "[verify-before-commit] SKIP_VERIFY=1 — 검증을 건너뛴다. 직접 돌린 결과로 책임진다." >&2
  exit 0
fi

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$ROOT" 2>/dev/null || exit 0

# ★ `set -e` 를 쓰지 않는다. 검증 훅에서 그건 **진단하기 전에 죽는** 장치다 —
#   실패를 감지하려고 부른 명령이 0 이 아닌 코드를 내면 훅이 조용히 끝난다.
#   실패는 값으로 모으고 마지막에 한 번 판정한다.
fallos=""
anotar() { fallos="${fallos}${fallos:+ / }$1"; }

# staged 파일 목록 (그 저장소 기준 상대경로)
staged() { git -C "$1" diff --cached --name-only 2>/dev/null; }

# ── api-ventago ──
API_TS=$(staged api-ventago | grep -E '^src/.*\.ts$' | grep -v '\.d\.ts$')
if [ -n "$API_TS" ]; then
  if ! (cd api-ventago && npx tsc --noEmit -p tsconfig.json >/tmp/vbc-api-tsc.log 2>&1); then
    anotar "api tsc 실패 (자세히: /tmp/vbc-api-tsc.log)"
  fi

  # eslint — **내가 추가한 줄에 오류가 있을 때만** 막는다.
  #
  # ★ api 는 기존 오류가 파일당 수십~수백 개다(cashRegister.service.ts 만 122개).
  #   0 을 요구하면 이 저장소에서는 아무것도 커밋할 수 없다. 그래서 diff 가 **추가한
  #   줄**에 걸린 오류만 본다 — 내가 만든 것만 책임진다.
  # ★ 종전 안(HEAD 사본을 만들어 개수를 비교)은 폐기했다. 임시 `.ts` 를 **소스 트리에**
  #   써야 했고, 훅이 중간에 죽으면 그 파일이 남아 tsc·빌드를 깨뜨린다.
  nuevas=$(
    (cd api-ventago && node -e '
      const { execSync } = require("child_process");
      const files = process.argv.slice(1);
      if (!files.length) process.exit(0);

      // 1) staged diff 에서 **추가된 줄 번호**를 모은다.
      const added = new Map();
      for (const f of files) {
        let d = "";
        try { d = execSync(`git diff --cached -U0 -- "${f}"`, { encoding: "utf8" }); } catch { continue; }
        const set = new Set();
        for (const line of d.split("\n")) {
          const m = line.match(/^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/);
          if (!m) continue;
          const start = Number(m[1]);
          const count = m[2] === undefined ? 1 : Number(m[2]);
          for (let i = 0; i < count; i++) set.add(start + i);
        }
        if (set.size) added.set(f, set);
      }
      if (!added.size) process.exit(0);

      // 2) eslint 를 JSON 으로 받아 그 줄에 걸린 error 만 센다.
      let out = "";
      try {
        out = execSync(
          `npx eslint --no-fix -f json ${[...added.keys()].map(f => JSON.stringify(f)).join(" ")}`,
          { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 },
        );
      } catch (e) {
        out = e.stdout || "";   // eslint 는 위반이 있으면 0 이 아닌 코드를 낸다
      }
      // ★ [codex 지적] 해석 실패를 **성공으로 처리하지 않는다.** 종전에는 여기서
      //   조용히 exit 0 이라, eslint 가 깨지면 lint 검사가 통째로 사라지는데
      //   통과처럼 보였다 — 「부재에서 침묵」이다.
      let report = [];
      try { report = JSON.parse(out); }
      catch { process.stdout.write("__ESLINT_ILEGIBLE__"); process.exit(0); }

      const malos = [];
      for (const r of report) {
        const rel = r.filePath.replace(process.cwd() + "/", "");
        const set = added.get(rel);
        if (!set) continue;
        const hits = (r.messages || []).filter(m => m.severity === 2 && set.has(m.line));
        if (hits.length) malos.push(`${rel}:${hits[0].line} ${hits[0].ruleId || ""} (+${hits.length - 1})`);
      }
      if (malos.length) process.stdout.write(malos.join("; "));
    ' $API_TS)
  )
  if [ "$nuevas" = "__ESLINT_ILEGIBLE__" ]; then
    anotar "api eslint 출력을 해석할 수 없다 — 검사가 사라진 것이므로 통과시키지 않는다"
  elif [ -n "$nuevas" ]; then
    anotar "api eslint — 내가 추가한 줄에 오류가 있다: $nuevas"
  fi

  # ── jest ── **변경된 모듈 디렉터리**만 돌린다.
  #
  # ★ `--findRelatedTests` 를 쓰지 않는다. 실측(2026-09-09, print.service.ts):
  #     --findRelatedTests → 17 suites / **91초**
  #     디렉터리 지정      →  7 suites / **6초**
  #   널리 import 되는 파일 하나가 저장소 절반을 끌어온다. 15배 차이는 커밋마다 낸다.
  #   (그래서 이 훅은 「관련 전부」가 아니라 「그 모듈」을 본다 — 범위가 좁다는 것을
  #    알고 쓴다. 전수는 GitHub Actions 와 사람이 돌린다.)
  # ★ `sed -E` 의 그룹+대안(`(a|b)`)은 **BSD sed 에서 깨진다** — 이 기계에서 실측했고
  #   그 결과 DIRS 가 빈 문자열이 되어 **jest 가 아예 안 돌았다.** 통과처럼 보였다.
  #   awk 로 바꾼다(GNU/BSD 동일 동작).
  # ★ 최상위 `src/*.ts`(main.ts 등)는 스코프가 `src` 전체 = 전수 suite(11분+)이므로
  #   대상에서 뺀다. 대신 **뺐다는 사실을 찍는다** — 조용한 공백을 만들지 않는다.
  DIRS=$(printf '%s\n' $API_TS | awk -F/ '
    $1=="src" && ($2=="app" || $2=="common") && NF>=4 { print $1"/"$2"/"$3; next }
    NF>=3 { d=$1; for(i=2;i<NF;i++) d=d"/"$i; print d; next }
  ' | sort -u)
  SIN_SCOPE=$(printf '%s\n' $API_TS | awk -F/ 'NF<3 { print }' | tr '\n' ' ')
  if [ -n "$SIN_SCOPE" ]; then
    echo "[verify-before-commit] jest 범위 밖(전수 suite 가 필요): $SIN_SCOPE — 필요하면 직접 돌릴 것" >&2
  fi
  if [ -n "$DIRS" ]; then
    # ★★ 옵션은 **실측으로 정했다. 베끼지 마라.**
    #   `NODE_OPTIONS=--max-old-space-size=2048` 을 GitHub Actions 워크플로에서 그대로
    #   가져왔더니 **그 상한이 OOM 을 만들었다** — `print.service.spec.ts` 가 2GB 힙에서
    #   죽고 워커가 SIGTERM 으로 연쇄 사망해, **무해한 커밋이 차단됐다**(대조군이 잡았다).
    #   러너의 값과 이 기계의 값은 다르다.
    #   `--workerIdleMemoryLimit=800MB` 도 뺐다 — 워커를 계속 재시작시켜 7초 → 35초.
    #   남은 것은 `--maxWorkers=1` 하나다(2 워커면 랜덤 suite 가 죽는다 — 필수).
    #   실측: src/app/print 7 suites / 7초.
    # ★ [codex 지적] `--passWithNoTests` 를 그냥 두면 **한 건도 안 돌아도 통과**한다 —
    #   DIRS 가 spec 없는 디렉터리로 잡히면 검사가 사라지는데 초록불이다.
    #   플래그는 유지한다(spec 없는 모듈이 실제로 있다). 대신 **몇 건 돌았는지 확인**하고,
    #   0 이면 「검사 없음」을 로그로 드러낸다.
    (
      cd api-ventago && npx jest --passWithNoTests --maxWorkers=1 --silent $DIRS
    ) >/tmp/vbc-api-jest.log 2>&1 &
    jest_pid=$!
    esperado=0
    vencido=0
    while kill -0 "$jest_pid" 2>/dev/null; do
      sleep 2
      esperado=$((esperado + 2))
      if [ "$esperado" -ge 180 ]; then
        kill -9 "$jest_pid" 2>/dev/null
        vencido=1
        break
      fi
    done
    wait "$jest_pid" 2>/dev/null
    rc=$?
    if [ "$vencido" -eq 1 ]; then
      anotar "api jest 가 180초 안에 안 끝났다 — 직접 돌린 뒤 SKIP_VERIFY=1 로 커밋"
    elif [ "$rc" -ne 0 ]; then
      anotar "api jest 실패 (대상: $(printf '%s' "$DIRS" | tr '\n' ' ')· 자세히: /tmp/vbc-api-jest.log)"
    else
      # 통과했는데 **한 건도 안 돌았다면** 이 커밋에는 테스트 근거가 없다. 막지는 않되
      # (spec 없는 모듈은 실재한다) 조용히 넘기지 않는다.
      if ! grep -qE '^Tests: +[1-9]' /tmp/vbc-api-jest.log 2>/dev/null; then
        echo "[verify-before-commit] ★ api jest 가 **0건** 실행됐다 (대상: $(printf '%s' "$DIRS" | tr '\n' ' ')) — 이 커밋은 테스트로 검증되지 않았다." >&2
      fi
    fi
  fi
fi

# ── ventago-app ── 프론트는 warning 도 빌드를 막는다 → staged 파일 0 을 요구한다
APP_FILES=$(staged ventago-app | grep -E '^src/.*\.(ts|tsx)$')
if [ -n "$APP_FILES" ]; then
  if ! (cd ventago-app && npx tsc --noEmit -p tsconfig.json >/tmp/vbc-app-tsc.log 2>&1); then
    anotar "app tsc 실패 (자세히: /tmp/vbc-app-tsc.log)"
  fi
  existentes=""
  for f in $APP_FILES; do [ -f "ventago-app/$f" ] && existentes="$existentes $f"; done
  if [ -n "$existentes" ]; then
    if ! (cd ventago-app && npx eslint --no-fix $existentes >/tmp/vbc-app-lint.log 2>&1); then
      anotar "app eslint 실패 — 프론트는 이것이 곧 Jenkins 빌드 실패다 (자세히: /tmp/vbc-app-lint.log)"
    fi
  fi
fi

# ── print-agent ── smoke 는 1초 미만이라 항상 돌린다
if staged . | grep -qE '^print-agent/'; then
  for t in print-agent/test/*.smoke.js; do
    [ -f "$t" ] || continue
    if ! node "$t" >/tmp/vbc-pa.log 2>&1; then
      anotar "print-agent smoke 실패: $(basename "$t") (자세히: /tmp/vbc-pa.log)"
    fi
  done
fi

# ── 감시 스크립트 문법 ──
if staged . | grep -qE '^scripts/.*\.sh$'; then
  for sh in $(staged . | grep -E '^scripts/.*\.sh$'); do
    [ -f "$sh" ] || continue
    bash -n "$sh" 2>/tmp/vbc-sh.log || anotar "$sh 문법 오류 (자세히: /tmp/vbc-sh.log)"
  done
fi

if [ -n "$fallos" ]; then
  node -e '
    const r = process.argv[1];
    process.stdout.write(JSON.stringify({
      decision: "block",
      reason: "커밋 전 로컬 검증 실패 — " + r +
        "\n\n고친 뒤 다시 커밋하세요. 검증을 건너뛰어야 하면 명령 앞에 SKIP_VERIFY=1 을 붙입니다(이유가 로그에 남습니다)."
    }));
  ' "$fallos"
  exit 2
fi

exit 0
