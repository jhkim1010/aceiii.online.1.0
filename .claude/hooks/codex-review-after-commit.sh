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
if ! printf '%s' "$CMD" | grep -qE '(^|[;&|[:space:]])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]]+)?)*[[:space:]]+commit([[:space:]]|$)'; then
  exit 0
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

LOCK="$ROOT/.team/reviews/.auto-codex.lock"
mkdir -p "$ROOT/.team/reviews" 2>/dev/null

if [ -f "$LOCK" ]; then
  pid=$(cat "$LOCK" 2>/dev/null)
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    # ★ [codex 지적] 여기서 그냥 끝내면 **snapshot 이 갱신되지 않은 채** 남고, 다음 커밋
    #   때는 `git show <최신 sha>` 하나만 모으므로 **중간 커밋이 어떤 보고서에도 안 들어간다.**
    #   snapshot 을 건드리지 않는 것 자체는 맞다(기준선이 유지돼야 다음에 범위로 잡힌다).
    #   대신 **범위로 모으도록** 아래 diff 수집을 `prev..sha` 로 바꿨다.
    echo "[codex-auto] 이미 검토가 돌고 있다(pid $pid) — 새로 띄우지 않는다. 다음 커밋 때 범위로 함께 검토된다." >&2
    exit 0
  fi
  rm -f "$LOCK"
fi

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
SNAP_PEND="$ROOT/.team/reviews/.auto-codex.heads.pending"
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

[ -z "$CAMBIADOS" ] && exit 0

DIFF="$ROOT/.team/reviews/.auto-codex.diff"
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
# ★ [2026-09-09] 키 뒤의 **닫는 따옴표**를 허용한다. 종전 식은 `"apiKey": "abc123"`
#   같은 JSON 형태를 통과시켰다 — 자격증명을 막는 필터에 난 진짜 구멍이었고,
#   시험을 붙이자마자 드러났다.
SECRET_RE="(password|passwd|pwd|secret|token|api[_-]?key|private[_-]?key)['\"]?[[:space:]]*[:=][[:space:]]*['\"]?[^'\"[:space:]<][^'\"[:space:]]{5,}"
# ★★ [2026-09-09 실측] 위 정규식은 **스키마 카탈로그 줄을 자격증명으로 오인**했다.
#   `store-restore-columns.txt` 의 `users.must_change_password : boolean NOT NULL`
#   이 걸려서 commit 52b14e3 의 검토가 통째로 취소됐다(그리고 아래 ② 때문에
#   기준선은 이미 전진해 **영구 미검토**가 됐다).
#   이 파일들은 재생성될 때마다 같은 줄을 만든다 — `api_key` · `secret` · `token` 을
#   컬럼명으로 가진 표가 있는 한 이 오탐은 **반복된다.**
#   → 값이 SQL 타입인 `<표>.<컬럼> : <타입>` 형태는 자격증명이 아니다. 그것만 뺀다.
#     (필터를 약하게 만들지 않는다. `password=hunter2` 는 그대로 걸린다.)
ESQUEMA_RE='[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:[[:space:]]*(boolean|integer|bigint|smallint|text|character|varchar|timestamp|timestamptz|date|numeric|double|real|jsonb|json|uuid|bytea|inet|interval|time|ARRAY|USER-DEFINED)'
# 원본 줄번호를 지키려고 `grep -n` 결과에서 거른다(`N:내용` 이므로 앵커를 맞춘다).
SECRET_HITS=$(grep -inE "$SECRET_RE" "$DIFF" 2>/dev/null | grep -ivE "^[0-9]+:[+-]?[[:space:]]*$ESQUEMA_RE" || true)
if [ -n "$SECRET_HITS" ]; then
  echo "[codex-auto] ★ diff 에 자격증명 형태가 있다 — **외부로 보내지 않는다.**" >&2
  # ★★ [codex 지적] **값을 되뿜지 않는다.** 종전에는 걸린 줄을 그대로 찍었다 —
  #   외부 전송은 막으면서 같은 비밀을 **세션 로그에 남기는** 짓이었다.
  #   위치(줄 번호)와 개수만 알린다. 실제 값은 사람이 diff 를 직접 봐야 한다.
  echo "[codex-auto]   위치: $(printf '%s\n' "$SECRET_HITS" | cut -d: -f1 | head -5 | tr '\n' ',' )번째 줄 (총 $(printf '%s\n' "$SECRET_HITS" | grep -c . )건)" >&2
  echo "[codex-auto]   확인 후 필요하면 사람이 직접 검토를 돌릴 것(scripts/codex-review.sh)." >&2
  rm -f "$DIFF"
  exit 0
fi
if grep -qE 'BEGIN [A-Z ]*PRIVATE KEY' "$DIFF" 2>/dev/null; then
  echo "[codex-auto] ★ diff 에 개인키가 있다 — 외부로 보내지 않는다." >&2
  rm -f "$DIFF"
  exit 0
fi

# 내용이 사실상 없으면(문서만·포인터만) 검토를 띄우지 않는다 — 25분을 낭비하지 않는다.
LINEAS=$(grep -cE '^[+-]' "$DIFF" 2>/dev/null || echo 0)
if [ "$LINEAS" -lt 6 ]; then
  echo "[codex-auto] 변경이 실질적이지 않다(${LINEAS}줄) — 검토를 띄우지 않는다." >&2
  # 검토할 것이 없어서 건너뛰는 것은 정당하다 → 기준선을 전진시킨다.
  mv -f "$SNAP_PEND" "$SNAP" 2>/dev/null || :
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
PROMPT_FILE="$ROOT/.team/reviews/.auto-codex.prompt"
printf '%s' "$PROMPT" > "$PROMPT_FILE"

nohup bash -c "
  echo \$\$ > '$LOCK'
  if codex exec --sandbox read-only \"\$(cat '$PROMPT_FILE')\$(cat '$DIFF')\" > '$OUT' 2>&1 && [ -s '$OUT' ]; then
    # ★ 검토가 실제로 끝나고 보고서가 비어 있지 않을 때만 기준선을 전진시킨다.
    mv -f '$SNAP_PEND' '$SNAP'
  else
    echo '[codex-auto] ★ 검토가 실패했다 — 기준선을 전진시키지 않는다. 다음 커밋이 범위로 함께 가져간다.' >> '$OUT'
  fi
  rm -f '$LOCK'
" >/dev/null 2>&1 &

echo "[codex-auto] CODEX 검토를 백그라운드로 띄웠다 (${CAMBIADOS}). 결과: ${OUT#$ROOT/}" >&2
echo "[codex-auto] ★ push 승인을 구하기 전에 이 보고서를 읽어야 한다." >&2

exit 0
