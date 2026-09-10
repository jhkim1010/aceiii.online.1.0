#!/bin/bash
# codex-review-after-commit.sh — PostToolUse(Bash) 훅: **커밋되면 CODEX 검토를 자동으로 띄운다.**
#
# 사용자 상시 지시(2026-09-09): "codex 조언 받고 / 항상 / 자동으로"
#
# ★★ 왜 커밋 **후 백그라운드**인가 — CODEX 는 게이트가 될 수 없다.
#   실측(2026-09-09): diff 를 넘긴 검토가 **약 25분**. 코드 없이 설계 질문만 준
#   1차 자문은 **50분간 0바이트**로 멈춰 있다가 죽었다.
#   커밋을 25분 막으면 아무도 안 쓴다. 그래서:
#     · commit  → 빠른 로컬 게이트(verify-before-commit.sh, ~20초)가 **막는다**
#     · commit 직후 → 이 훅이 CODEX 를 백그라운드로 띄운다(막지 않는다)
#     · push    → 사용자 승인 지점. 그때 CODEX 보고서를 읽고 함께 보고한다
#   push 가 이미 승인 대기이므로, 검토 결과가 도착할 시간이 자연히 확보된다.
#
# ★ 서브모듈이 있으므로 `codex review --working` 을 쓰지 않는다 — 그 방식은
#   서브모듈 수정 파일을 **건너뛴다**(실측). diff 를 직접 만들어 argv 로 넘긴다.
#
# ★ `--model` 을 주지 않는다. `gpt-5-codex` 를 지정하면 조용히 죽는다(실측).
#
# ★ 단일 실행(single-flight): 이미 돌고 있으면 새로 띄우지 않는다. 커밋을 연달아 하면
#   프로세스가 쌓여 기계가 마비된다.
#
# 보고서: .team/reviews/auto-<repo>-<sha>.md   (읽는 사람이 없으면 감시는 없는 것이므로
#         push 전에 **반드시** 읽는다 — CLAUDE.md 「push 는 사용자 승인 후」 참조)
#
# 끄기: 커밋 명령에 `SKIP_CODEX=1` 을 붙인다.

INPUT=$(cat)

CMD=$(printf '%s' "$INPUT" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{try{process.stdout.write(JSON.parse(d).tool_input?.command||'')}catch{}})" 2>/dev/null)

# ★ [codex 지적] `*"git commit"*` 만 보면 `git -C <path> commit` 을 놓친다.
# ★ [codex 지적 · P1] 검토가 도는 동안 만들어진 커밋은 single-flight 로 건너뛴다.
#   그 뒤로 커밋이 없으면 그 커밋은 **영원히 검토되지 않는다.** 그래서 검토가 끝나면
#   자기 자신을 다시 부른다 — 그때는 커밋 명령이 아니므로 이 관문을 통과해야 한다.
if [ "${CODEX_RELANZAR:-0}" != "1" ]; then
  if ! printf '%s' "$CMD" | grep -qE '(^|[;&|[:space:]])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]]+)?)*[[:space:]]+commit([[:space:]]|$)'; then
    exit 0
  fi
fi
case "$CMD" in
  *SKIP_CODEX=1*) echo "[codex-auto] SKIP_CODEX=1 — 검토를 띄우지 않는다." >&2; exit 0 ;;
esac

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$ROOT" 2>/dev/null || exit 0

# codex 실재 확인 — `command -v` 만으로는 부족하다. cmux 가 PATH 에 shim 을 깔아 두므로
# 실제 바이너리가 없어도 경로는 잡히고 shim 은 "not found" 를 찍으며 exit 0 을 준다.
VER="$(codex --version 2>&1 || true)"
if ! command -v codex >/dev/null 2>&1 || printf '%s' "$VER" | grep -qi 'not found'; then
  echo "[codex-auto] codex 바이너리 없음 — 검토를 건너뛴다 (npm i -g @openai/codex)" >&2
  exit 0
fi

# ★★ [codex 지적 · P1 · 2026-09-09] 종전에는 부모가 **락 파일의 존재만 확인**하고,
#   실제 파일은 백그라운드 자식이 만들었다. 그 사이에 다른 커밋 훅이 들어오면
#   **둘 다 통과**해서 공용 diff·prompt·pending 을 동시에 덮어썼다.
#   codex 는 여기에 더 나쁜 결과를 덧붙였다 — 쓰다 만 diff 를 읽고도 종료코드 0 과
#   비어 있지 않은 출력이면 «성공» 이 되어, **검토되지 않은 변경까지 기준선이 삼킨다.**
#
#   → `mkdir` 로 잡는다. POSIX 에서 원자적이라 둘이 동시에 성공할 수 없다.
#     그리고 **잡은 디렉터리를 그 실행의 작업 공간으로 쓴다** — diff·prompt·pending 이
#     실행 안에 있으므로 공유될 수가 없다(경합을 막는 게 아니라 없앤다).
RUNDIR="$ROOT/.team/reviews/.auto-codex.run.d"
mkdir -p "$ROOT/.team/reviews" 2>/dev/null

if ! mkdir "$RUNDIR" 2>/dev/null; then
  pid=$(cat "$RUNDIR/pid" 2>/dev/null)
  if [ -z "$pid" ]; then
    # 방금 잡혔고 아직 pid 를 못 쓴 상태다. 살아 있다고 보고 비켜 준다 —
    # 기준선은 전진하지 않으므로 다음 커밋이 범위로 함께 가져간다.
    echo "[codex-auto] 검토가 막 시작됐다 — 비켜 준다. 다음 커밋 때 범위로 함께 검토된다." >&2
    exit 0
  fi
  if kill -0 "$pid" 2>/dev/null; then
    echo "[codex-auto] 이미 검토가 돌고 있다(pid $pid) — 새로 띄우지 않는다. 다음 커밋 때 범위로 함께 검토된다." >&2
    exit 0
  fi
  # 죽은 실행이 남긴 것 — 치우고 다시 잡는다.
  rm -rf "$RUNDIR"
  mkdir "$RUNDIR" 2>/dev/null || exit 0
fi
LOCK="$RUNDIR/pid"

# 방금 커밋이 어느 저장소인지 — 명령 문자열이 아니라 **실제 HEAD 변화**로 찾는다.
# (`cd api-ventago && git commit` 처럼 경로가 명령에 섞여 있어 파싱은 못 믿는다.)
SNAP="$ROOT/.team/reviews/.auto-codex.heads"
PRIMERA_VEZ=0
[ -f "$SNAP" ] || PRIMERA_VEZ=1
declare -a REPOS=("." "api-ventago" "ventago-app")
CAMBIADOS=""
NUEVO=""
for r in "${REPOS[@]}"; do
  sha=$(git -C "$r" rev-parse --short HEAD 2>/dev/null) || continue
  NUEVO="${NUEVO}${r}=${sha}"$'\n'
  # ★ [codex 지적] `grep -E "^${r}="` 에서 r="." 이면 `.` 은 **정규식의 「아무 글자」**다 —
  #   `a=...` 같은 다른 줄을 읽어 엉뚱한 기준선과 비교한다. 고정 문자열로 본다.
  prev=$(grep -F -- "${r}=" "$SNAP" 2>/dev/null | grep -E "^$(printf '%s' "$r" | sed 's/[][\.^$*+?(){}|]/\\&/g')=" | head -1 | cut -d= -f2)
  if [ -n "$prev" ] && [ "$prev" != "$sha" ]; then
    CAMBIADOS="${CAMBIADOS}${CAMBIADOS:+ }${r}:${sha}"
  fi
done
SNAP_PREV="$ROOT/.team/reviews/.auto-codex.heads.prev"
cp "$SNAP" "$SNAP_PREV" 2>/dev/null || : > "$SNAP_PREV"
# ★★ [2026-09-09 실측 · P1] 종전에는 **여기서** 기준선을 전진시켰다. 그래서 아래
#   어느 단계가 중단되든(자격증명 오탐 · codex 부재 · 실행 실패) 그 커밋은
#   **영구 미검토**가 됐다 — commit 52b14e3 에서 실제로 그렇게 됐다.
#   → 기준선은 **검토가 실제로 끝난 뒤에만** 전진한다. 그때까지는 대기 파일에 둔다.
#     검토를 못 띄우면 기준선이 그대로이므로 다음 커밋이 **범위로 함께** 가져간다.
SNAP_PEND="$RUNDIR/pending"   # ★ 실행 안에 둔다 — 공유되면 남의 커밋을 기준선에 얹는다
printf '%s' "$NUEVO" > "$SNAP_PEND"

# ★★ [codex 지적 · P1] 종전에는 기준선이 없으면(=훅 설치 후 첫 커밋) 기준선만 저장하고
#   끝냈다. 그래서 **배선 후 첫 커밋이 조용히 무검토로 통과**했고, 보고서가 없는 것과
#   「검토했는데 지적 0」이 구별되지 않았다.
#   → 기준선이 없으면 **방금 만든 커밋(HEAD)** 을 검토 대상으로 삼는다.
if [ -z "$CAMBIADOS" ] && [ "$PRIMERA_VEZ" = "1" ]; then
  for r in "${REPOS[@]}"; do
    sha=$(git -C "$r" rev-parse --short HEAD 2>/dev/null) || continue
    # 이 커밋이 방금(60초 이내) 만들어진 것만 — 오래된 HEAD 를 뒤늦게 검토하지 않는다.
    edad=$(git -C "$r" log -1 --format=%ct 2>/dev/null)
    ahora_ts=$(date +%s)
    if [ -n "$edad" ] && [ $((ahora_ts - edad)) -le 60 ]; then
      CAMBIADOS="${CAMBIADOS}${CAMBIADOS:+ }${r}:${sha}"
    fi
  done
  [ -n "$CAMBIADOS" ] && echo "[codex-auto] 기준선이 없었다 — 방금 만든 커밋을 검토한다." >&2
fi

[ -z "$CAMBIADOS" ] && { rm -rf "$RUNDIR"; exit 0; }

DIFF="$RUNDIR/diff"
: > "$DIFF"
ETIQUETAS=""
for entry in $CAMBIADOS; do
  r="${entry%%:*}"; sha="${entry##*:}"
  # ★ [codex 지적] 최신 한 건이 아니라 **기준선부터의 범위**를 모은다. 검토가 도는 동안
  #   커밋이 두 건 이상 쌓이면 중간 것이 영구히 빠졌다.
  base=$(grep -F -- "${r}=" "$SNAP_PREV" 2>/dev/null | grep -E "^$(printf '%s' "$r" | sed 's/[][\.^$*+?(){}|]/\\&/g')=" | head -1 | cut -d= -f2)
  if [ -n "$base" ] && git -C "$r" cat-file -e "${base}^{commit}" 2>/dev/null; then
    echo "===== ${r} @ ${base}..${sha} =====" >> "$DIFF"
    git -C "$r" log --oneline "${base}..${sha}" >> "$DIFF" 2>/dev/null
    git -C "$r" diff --no-color --submodule=short "${base}" "${sha}" >> "$DIFF" 2>/dev/null
  else
    echo "===== ${r} @ ${sha} =====" >> "$DIFF"
    git -C "$r" log -1 --pretty='커밋: %s' >> "$DIFF"
    git -C "$r" show --no-color --submodule=short "$sha" >> "$DIFF" 2>/dev/null
  fi
  # 루트는 `basename "."` = "." 이라 파일명이 `auto-.-sha.md` 로 지저분해진다.
  etiq="$r"; [ "$etiq" = "." ] && etiq="root"
  ETIQUETAS="${ETIQUETAS}${ETIQUETAS:+_}$(basename "$etiq")-${sha}"
done

# ★★ [codex 지적 · P1] **자격증명이 외부로 나가는 것을 막는다.**
#   이 diff 는 외부 서비스(CODEX)로 **전송**된다. 한번 나가면 그 세션에 값이 남고
#   되돌릴 수 없다. 저장소의 `scripts/codex-review.sh` 는 이미 같은 이유로 경고를
#   내는데, 이 훅은 **필터 없이 보내고 있었다.**
#   → 같은 정규식으로 검사하고, 걸리면 **보내지 않는다**(경고가 아니라 거절이다 —
#     자동으로 도는 장치에서 경고는 아무도 안 읽는다).
# ★ [2026-09-09] 키 뒤의 **닫는 따옴표**를 허용한다. 종전 식은 `"apiKey": <값>` 형태의
#   같은 JSON 형태를 통과시켰다 — 자격증명을 막는 필터에 난 진짜 구멍이었고,
#   시험을 붙이자마자 드러났다.
SECRET_RE="(password|passwd|pwd|secret|token|api[_-]?key|private[_-]?key)['\"]?[[:space:]]*[:=][[:space:]]*['\"]?[^'\"[:space:]<][^'\"[:space:]]{5,}"
# ★★ [2026-09-09 실측] 위 정규식은 **스키마 카탈로그 줄을 자격증명으로 오인**했다.
#   `store-restore-columns.txt` 의 `users.must_change_password : <타입>`
#   이 걸려서 commit 52b14e3 의 검토가 통째로 취소됐다(그리고 아래 ② 때문에
#   기준선은 이미 전진해 **영구 미검토**가 됐다).
#   이 파일들은 재생성될 때마다 같은 줄을 만든다 — `api_key` · `secret` · `token` 을
#   컬럼명으로 가진 표가 있는 한 이 오탐은 **반복된다.**
#   → 값이 SQL 타입인 `<표>.<컬럼> : <타입>` 형태는 자격증명이 아니다. 그것만 뺀다.
#     (필터를 약하게 만들지 않는다. `password=<값>` 형태는 그대로 걸린다.)
# ★★ [codex 지적 · P1 · 2026-09-09] 이 예외는 처음에 **줄 앞부분만** 봤다. 그래서
#   `users.api_key : <긴 타입> DEFAULT <값>` 처럼 앞이 스키마 모양이면
#   **뒤에 무엇이 붙든 통째로 면제**됐다 — 자격증명 필터에 낸 구멍이었다.
#   (codex 가 든 예 `... : text DEFAULT ...` 자체는 `text` 가 짧아 애초에 필터에
#    안 걸렸지만, 타입이 긴 형태로 바꾸면 실제로 통과했다. 취지가 맞았다.)
#   → **`$` 로 줄 끝까지 고정**하고, 타입 뒤에는 카탈로그가 실제로 만드는
#     `NOT NULL` · `PK` · `SERVERGEN` · `GENERATED` 만 허용한다.
#   대조: store-restore-columns.txt 의 2,006줄 전부를 이 패턴이 인식한다.
ESQUEMA_RE='[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:[[:space:]]*(boolean|smallint|integer|bigint|text|character( varying)?|varchar|timestamp( with(out)? time zone)?|timestamptz|date|time( with(out)? time zone)?|numeric|double precision|real|jsonb|json|uuid|bytea|inet|interval|ARRAY|USER-DEFINED|enum_[a-z0-9_]+)(\([0-9]+(,[0-9]+)?\))?(\[\])?([[:space:]]+(NOT NULL|PK|SERVERGEN|GENERATED))*[[:space:]]*$'
# 원본 줄번호를 지키려고 `grep -n` 결과에서 거른다(`N:내용` 이므로 앵커를 맞춘다).
SECRET_HITS=$(grep -inE "$SECRET_RE" "$DIFF" 2>/dev/null | grep -ivE "^[0-9]+:[+-]?[[:space:]]*$ESQUEMA_RE" || true)
if [ -n "$SECRET_HITS" ]; then
  echo "[codex-auto] ★ diff 에 자격증명 형태가 있다 — **외부로 보내지 않는다.**" >&2
  # ★★ [codex 지적] **값을 되뿜지 않는다.** 종전에는 걸린 줄을 그대로 찍었다 —
  #   외부 전송은 막으면서 같은 비밀을 **세션 로그에 남기는** 짓이었다.
  #   위치(줄 번호)와 개수만 알린다. 실제 값은 사람이 diff 를 직접 봐야 한다.
  echo "[codex-auto]   위치: $(printf '%s\n' "$SECRET_HITS" | cut -d: -f1 | head -5 | tr '\n' ',' )번째 줄 (총 $(printf '%s\n' "$SECRET_HITS" | grep -c . )건)" >&2
  echo "[codex-auto]   확인 후 필요하면 사람이 직접 검토를 돌릴 것(scripts/codex-review.sh)." >&2
  rm -rf "$RUNDIR"
  exit 0
fi
if grep -qE 'BEGIN [A-Z ]*PRIVATE KEY' "$DIFF" 2>/dev/null; then
  echo "[codex-auto] ★ diff 에 개인키가 있다 — 외부로 보내지 않는다." >&2
  rm -rf "$RUNDIR"
  exit 0
fi

# 내용이 사실상 없으면(문서만·포인터만) 검토를 띄우지 않는다 — 25분을 낭비하지 않는다.
LINEAS=$(grep -cE '^[+-]' "$DIFF" 2>/dev/null || echo 0)
if [ "$LINEAS" -lt 6 ]; then
  echo "[codex-auto] 변경이 실질적이지 않다(${LINEAS}줄) — 검토를 띄우지 않는다." >&2
  # 검토할 것이 없어서 건너뛰는 것은 정당하다 → 기준선을 전진시킨다.
  mv -f "$SNAP_PEND" "$SNAP" 2>/dev/null || :
  rm -rf "$RUNDIR"
  exit 0
fi

OUT="$ROOT/.team/reviews/auto-${ETIQUETAS}.md"

PROMPT="이 커밋의 diff 를 검토해라. Ventago(NestJS+Sequelize+PG18 · pm2 4워커 cluster / Next.js 13 / Electron print-agent).
한국어로, P1/P2/P3 로 분류해서 **결함만** 짚어라. 칭찬·요약은 필요 없다.

특히 이 저장소에서 반복된 실패 형태를 의심해라:
- 트랜잭션 안에서 인쇄·소켓·HTTP (롤백돼도 종이가 나간다)
- 커밋 후 단계에서 throw (클라이언트가 재시도해 같은 판매/주문을 복제한다)
- 좁히는 필터가 해석 실패 시 **전체로 폴백**하는 것 (사용자는 좁혔다고 믿는다)
- 감시·판정이 「부재」에서 침묵하는 것 (0건이 위반 0건이 아니다)
- 같은 상태를 두 곳이 소유해 갈라지는 것
- 멀티테넌트 store_id / 지점 경계 누락
- 검사가 구현에서 정답을 가져와 헛통과하는 것

diff:
"

# ★ 프롬프트 파일을 **먼저** 쓴다. 종전에는 백그라운드를 띄운 뒤에 썼는데,
#   그 사이 자식이 파일을 읽으면 프롬프트 없이(=diff 만) 검토가 돈다 — 경합이다.
PROMPT_FILE="$RUNDIR/prompt"
printf '%s' "$PROMPT" > "$PROMPT_FILE"

# ★ 백그라운드 본문을 **파일로** 쓴다. 종전에는 `bash -c "..."` 안에 전부 넣었는데,
#   따옴표가 세 겹이라 한 글자만 어긋나도 조용히 다른 명령이 됐다.
RUNNER="$RUNDIR/run.sh"
cat > "$RUNNER" <<'RUNNER_EOF'
#!/usr/bin/env bash
# 자동 생성됨 — codex-review-after-commit.sh 가 매번 덮어쓴다. 직접 고치지 말 것.
set -u
echo $$ > "$LOCK"
ok=0
if codex exec --sandbox read-only "$(cat "$PROMPT_FILE")$(cat "$DIFF")" > "$OUT" 2>&1 && [ -s "$OUT" ]; then
  ok=1
  # ★ 검토가 실제로 끝났을 때만 기준선을 전진시킨다.
  mv -f "$SNAP_PEND" "$SNAP"
else
  echo '[codex-auto] ★ 검토가 실패했다 — 기준선을 전진시키지 않는다. 다음 커밋이 범위로 함께 가져간다.' >> "$OUT"
fi
# ★ 검토가 도는 동안 새 커밋이 있었나 — 있으면 **이어서** 검토한다.
#   이게 없으면 「검토 중에 만든 마지막 커밋」이 영원히 검토되지 않는다.
pendiente=0
if [ "$ok" = "1" ]; then
  for r in . api-ventago ventago-app; do
    cur=$(git -C "$r" rev-parse --short HEAD 2>/dev/null) || continue
    prev=$(grep -F -- "$r=" "$SNAP" 2>/dev/null | head -1 | cut -d= -f2)
    [ -n "$prev" ] && [ "$prev" != "$cur" ] && pendiente=1
  done
fi

# 락 해제 = 작업 공간 제거. 여기서부터는 $RUNDIR 안의 어떤 파일도 읽지 않는다.
rm -rf "$RUNDIR"

if [ "$pendiente" = "1" ]; then
  echo '[codex-auto] 검토 중 새 커밋이 있었다 — 이어서 검토한다.' >> "$OUT"
  CODEX_RELANZAR=1 CLAUDE_PROJECT_DIR="$ROOT" bash "$SELF" < /dev/null >/dev/null 2>&1 &
fi
RUNNER_EOF
chmod +x "$RUNNER"

SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
export LOCK PROMPT_FILE DIFF OUT SNAP SNAP_PEND ROOT SELF
# ★ 파일 경로로 실행하지 않는다. 러너는 `$RUNDIR` 안에 있고 러너가 끝나면서
#   그 디렉터리를 지우는데, **실행 중인 스크립트 파일이 사라지면 bash 가 남은 줄을
#   못 읽는다.** 내용을 읽어 넘기면 파일 의존이 없다(따옴표는 한 겹뿐이다).
nohup bash -c "$(cat "$RUNNER")" >/dev/null 2>&1 &

echo "[codex-auto] CODEX 검토를 백그라운드로 띄웠다 (${CAMBIADOS}). 결과: ${OUT#$ROOT/}" >&2
echo "[codex-auto] ★ push 승인을 구하기 전에 이 보고서를 읽어야 한다." >&2

exit 0
