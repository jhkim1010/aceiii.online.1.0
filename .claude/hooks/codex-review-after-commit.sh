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
#   프로세스가 쌓여 기계가 마비된다. 판정은 **락 파일이 아니라 실행 중인 프로세스**로
#   한다 — 파일은 낡지만 프로세스는 낡지 않는다(2026-09-10, 아래 락 제거 주석 참조).
#
# 보고서: .team/reviews/auto-<repo>-<sha>.md   (읽는 사람이 없으면 감시는 없는 것이므로
#         push 전에 **반드시** 읽는다 — CLAUDE.md 「push 는 사용자 승인 후」 참조)
#
# 끄기: 커밋 명령에 `SKIP_CODEX=1` 을 붙인다.

INPUT=$(cat)

# ★★★ [2026-09-13] **node 가 도는지 먼저 확인한다.** 이 파싱이 node 로 되어 있고
#   실패를 삼키므로, node 가 죽으면 `CMD` 가 비어 커밋 매칭이 실패하고 이 훅이
#   **아무 말 없이 통과**한다. 2026-09-10~13 에 실제로 그랬고, 흔적은
#   `.auto-codex.heads` 가 멈춰 있는 것뿐이었다. 이유는 `node-sano.sh` 에 있다.
. "$(dirname "${BASH_SOURCE[0]}")/node-sano.sh"

# ★★ 실패 두 가지를 같은 것으로 다룬다 (CODEX P2, 2026-09-13):
#   ① node 가 안 돈다  ② node 는 도는데 훅 입력 JSON 을 못 읽는다.
#   ② 를 `CMD=""` 로 떨어뜨리면 아래 커밋 매칭이 실패해 **다시 조용한 누락**이 된다.
PARSEO_OK=0
CMD=""
if node_sano; then
  if CMD=$(cmd_de_entrada "$INPUT"); then
    PARSEO_OK=1
  else
    CMD=""
  fi
fi

if [ "$PARSEO_OK" != "1" ]; then
  # ★ 이 훅은 게이트가 아니므로 막지 않는다. 대신 **소리를 낸다** —
  #   조용한 통과가 이 결함의 전부였다.
  echo "[codex-auto] ★★ 훅 입력을 해석할 수 없다 — 이 커밋의 검토를 띄우지 못한다." >&2
  echo "[codex-auto]   기준선(.auto-codex.heads)은 전진시키지 않으므로 다음 커밋이 범위로 함께 가져간다." >&2
  exit 0
fi

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

# ★★ [2026-09-10] 락을 고치지 않고 **없앴다.**
#   종전: 고정 경로 `.auto-codex.run.d` 를 만들어 그것이 곧 락이자 작업 공간이었다.
#
#   고정 경로를 쓰는 순간 그 파일은 **낡을 수 있고**, 그래서 낡음을 판정해야 하고,
#   판정했으면 회수해야 한다. CODEX 가 라운드마다 낸 지적 4건 —
#     · pid 를 쓰기 전에 죽으면 빈 디렉터리가 남아 **이후 모든 커밋이 영구 침묵**
#     · 두 훅이 각자 `rm -rf`+`mkdir` 해서 **살아 있는 실행의 작업 공간을 지운다**
#     · `kill -0` 은 번호만 보므로 **PID 재사용**을 「실행 중」으로 오판
#     · 시험이 소스 grep 으로 연결을 판정해 **결함 있는 구현을 정답으로 삼는다**
#   — 은 전부 **그 선택 하나에서 파생**된 것이었다. 고칠 문제가 아니라 없앨 문제다.
#
#   → 작업 공간은 `mktemp -d`. **공유 상태가 0이므로 두 실행이 만날 자리가 없다.**
#   → 겹침 방지는 파일이 아니라 **실행 중인 codex 프로세스**를 본다. 프로세스는 낡지
#     않는다 — 죽으면 그 순간 판정도 사라지므로 **영구 침묵이 구조적으로 불가능하다.**
#   최악의 경우는 검토 둘이 동시에 도는 것이고, 그건 부하이지 정확성이 아니다.
#   (기준선은 실행별 pending 에서 성공 시에만 옮겨지므로, 겹쳐도 미검토를 삼키지 않는다 —
#    늦게 끝난 쪽이 옛 기준선을 써도 **다시 검토하는** 방향으로 어긋난다.)
# ★ [CODEX P2 · 2026-09-10] `pgrep -f 'codex exec'` 는 **시스템 전체**를 본다 —
#   다른 저장소의 검토나 사용자가 직접 돌린 codex 까지 「이 저장소가 돌고 있다」로
#   오인해 이 커밋의 검토를 미룬다. 러너의 argv 에 **저장소 절대경로 표식**을 심어
#   그것만 본다(표식은 러너 스크립트 끝에 붙인다 — 아래 참조).
# ★★ [CODEX P2 · 2026-09-10] `pgrep -f` 의 패턴은 **정규식**이다. `$ROOT` 를 그대로
#   넣으면 경로의 `.` 이 「아무 글자」가 된다 — 이 저장소 경로가 바로 그렇다
#   (`aceiii.online.1.0` 은 `aceiii<any>online<any>1<any>0` 과도 맞는다).
#   그러면 이름이 비슷한 **다른** 저장소의 검토가 이 저장소를 막아, 이번 수정이
#   없애려던 「남의 검토 때문에 침묵」이 그대로 되살아난다.
#   → 고정 문자열로 만든다. (같은 이스케이프를 아래 기준선 조회도 쓴다.)
MARCA="codex-auto-run: $(printf '%s' "$ROOT" | sed 's/[][\.^$*+?(){}|]/\\&/g')"
if pgrep -f "$MARCA" >/dev/null 2>&1; then
  echo "[codex-auto] 이 저장소의 검토가 이미 돌고 있다 — 새로 띄우지 않는다. 다음 커밋 때 범위로 함께 검토된다." >&2
  exit 0
fi

# 죽은 실행이 남긴 작업 공간은 **그냥 쓰레기다** — 아무도 그것을 보고 판정하지 않는다.
# (종전에는 이 잔여물이 곧 락이어서 하나만 남아도 검토가 멈췄다.) 하루 지난 것만 치운다.
find "$ROOT/.team/reviews" -maxdepth 1 -type d -name '.auto-codex.run.*' -mtime +1 -exec rm -rf {} + 2>/dev/null || :

RUNDIR=$(mktemp -d "$ROOT/.team/reviews/.auto-codex.run.XXXXXX") || exit 0

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
                              #   ($RUNDIR 은 mktemp 라 실행마다 다르다 — 공유될 수가 없다)
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
#   ⤷ 2026-10-23 부터는 diff 전체가 아니라 **걸린 줄만** 가리고 보낸다 — 아래 ★★★★ 참조.
# ★ [2026-09-09] 키 뒤의 **닫는 따옴표**를 허용한다. 종전 식은 `"apiKey": <값>` 형태의
#   같은 JSON 형태를 통과시켰다 — 자격증명을 막는 필터에 난 진짜 구멍이었고,
#   시험을 붙이자마자 드러났다.
# ★★★ [2026-09-17 실측] 위 식은 **코드 식별자를 자격증명으로 오인**했다.
#   `const isDpToken = isDeudaPagoToken(skuText);` 의 「Token = isDeudaPago…」 가 걸려
#   ventago-app 커밋 **4건의 검토가 통째로 건너뛰어졌다**(그 줄은 기준선 이후 모든
#   diff 에 들어 있어서 한 번 걸리자 계속 걸렸다). 스키마 카탈로그 오탐(위 ★★)과
#   **같은 뿌리**다: 키만 보고 **값이 무엇인지 안 봤다.**
#   → 값이 **문자열 리터럴**(따옴표로 시작)이거나, 따옴표 없이 **줄 끝까지 이어지는
#     불투명 토큰**일 때만 자격증명으로 본다. 함수 호출·타입 표기는 `(` 나 뒤따르는
#     코드 때문에 줄 끝 고정에 걸려 빠진다.
#   ★ 필터를 **약하게 만들지 않았다** — 대조군은 이 파일이 아니라
#     `codex-review-after-commit.test.sh` 가 들고 있다(리터럴을 여기 적으면 이 파일
#     자신이 필터에 걸린다. 그 시험의 「자기 필터」 검사가 그걸 강제한다).
#     거기서 확인하는 것: env/JSON/yaml 형식 · 스키마 모양으로 **위장한** 값 →
#     여전히 막는다. 코드 식별자(`… = 함수이름(인자)`)와 순수 스키마 카탈로그 줄 →
#     이제 통과한다.
# ★★★★ [2026-09-17, 자동 검토 P1·P2] 위 1차 수정도 부족했다. **분기를 셋으로 나눈다.**
#   한 덩어리 정규식으로 「코드」와 「설정」을 가르려다 두 번 틀렸다 —
#   ① 따옴표 안에 **선행 공백**이 있으면 못 잡았다(종전 식도 같았다: 원래 있던 구멍).
#   ② `= 객체.속성.속성;` 형태를 **여전히** 자격증명으로 오인했다. 함수 호출만 고쳤을 뿐이고,
#      속성 접근은 코드에 훨씬 흔하다 — 그대로 두면 같은 사고가 또 난다.
#   ⤷ 자격증명이 **실제로 나타나는 세 모양**만 각각 적는다. 값의 의미가 아니라
#     그 세 모양에 맞는지를 본다.
#     A) 구분자 **바로 뒤**의 문자열 리터럴 — `key: "<값>"` (따옴표 안 선행공백 2칸까지 허용)
#     B) env/설정 파일 모양 — 줄 처음부터 `NAME=<값>` (= 앞뒤 공백 없음, 줄 끝까지)
#     C) `:` 구분자 뒤 어딘가의 불투명 토큰 — 스키마 타입 뒤에 값을 숨긴 위장을 잡는다
#   ★ 코드의 `const x = a.b.c;` 는 A(리터럴 아님)·B(줄 처음이 아니고 = 앞에 공백)·
#     C(구분자가 `=`) 어디에도 안 맞는다.
SECRET_KEY_RE="(password|passwd|pwd|secret|token|api[_-]?key|private[_-]?key)"
SECRET_RE="${SECRET_KEY_RE}['\"]?[[:space:]]*[:=][[:space:]]*['\"][[:space:]]{0,2}[^'\"[:space:]]{5,}|^[+-]?[[:space:]]*[A-Za-z0-9_]*${SECRET_KEY_RE}[A-Za-z0-9_]*=[^'\"[:space:]]{8,}[[:space:]]*\$|${SECRET_KEY_RE}['\"]?[[:space:]]*:.*[^'\"[:space:]()]{8,}[[:space:],;]*\$"
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

# ★★★ [2026-09-18 실측] 세 번째 오탐. 이번에 막힌 것은 **코드가 아니라 문서**였다 —
#   핸드오프에 적어 둔 조회 방법 한 줄이 기준선 이후 diff 에 들어가, 그 뒤 커밋
#   **3건의 검토가 연쇄로 건너뛰어졌다**(2026-09-18 08:43·08:44·12:12).
#   형태: 환경변수(이름에 PASSWORD 가 든)에 **명령 치환의 결과를 대입**하는 줄이다.
#   ★ 그 형태를 여기 그대로 적지 않는다 — 이 파일 자신이 필터에 걸린다(시험이 강제).
#     실제 예시는 `codex-review-after-commit.test.sh` 가 조각으로 조립해 들고 있다.
#   분기 A 는 「따옴표 바로 뒤의 불투명 토큰」을 보는데 치환의 여는 부분이 거기 맞았다.
#   ⤷ 값이 `$(...)` 나 `${...}` **하나로 끝나면** 자격증명이 아니다. 거기 적힌 것은
#     「어디서 읽어 오는가」이지 값이 아니다.
#   ★ 예외는 **줄 끝까지 고정한다.** 스키마 예외에서 배운 것과 같다 — 앞부분만 보면
#     `password="$(x)" real=<값>` 같은 꼬리가 통째로 면제된다.
#   ★ 앞의 `^[0-9]+:[+-]?[[:space:]]*` 는 **쓰는 쪽**이 붙인다(ESQUEMA_RE 와 같은 규약).
#     여기서 또 `^` 를 붙이면 이어 붙일 때 정규식이 깨진다.
SUSTITUCION_RE='(export[[:space:]]+)?[A-Za-z0-9_]*'"${SECRET_KEY_RE}"'[A-Za-z0-9_]*[[:space:]]*=[[:space:]]*["'"'"']?\$[({].*[)}]["'"'"']?[[:space:]]*$'
# 원본 줄번호를 지키려고 `grep -n` 결과에서 거른다(`N:내용` 이므로 앵커를 맞춘다).
# 한 파일에서 자격증명 형태의 줄(개인키는 블록 전체)을 표식 줄로 바꾸고, 가린 줄 수를 출력한다.
# ★ 크기 상한 경로는 **가린 뒤에** 크기를 잰다 — 표식이 원래 줄보다 길 수 있어서, 자른 뒤에
#   가리면 상한을 넘긴다(시험 ⑨ 가 상한 3777 에서 2바이트 넘침으로 잡았다).
ocultar_en() {
  local f="$1" hits keys lista
  hits=$(grep -inE "$SECRET_RE" "$f" 2>/dev/null | grep -ivE "^[0-9]+:[+-]?[[:space:]]*$ESQUEMA_RE" | grep -ivE "^[0-9]+:[+-]?[[:space:]]*$SUSTITUCION_RE" | cut -d: -f1 || true)
  keys=$(awk '/BEGIN [A-Z ]*PRIVATE KEY/{k=1} k{print NR} /END [A-Z ]*PRIVATE KEY/{k=0}' "$f" 2>/dev/null)
  lista=$( { printf '%s\n' "$hits"; printf '%s\n' "$keys"; } | grep -E '^[0-9]+$' | sort -n -u)
  if [ -z "$lista" ]; then echo 0; return 0; fi
  printf '%s\n' "$lista" > "$f.ocultar"
  awk 'NR==FNR{o[$1]=1; next} (FNR in o){c=substr($0,1,1); if(c!="+" && c!="-") c=" "; print c "[codex-auto: 줄 생략 — 자격증명 형태]"; next} {print}' \
    "$f.ocultar" "$f" > "$f.tmp" && mv -f "$f.tmp" "$f"
  rm -f "$f.ocultar"
  printf '%s\n' "$lista" | grep -c .
}

# ★★★ [2026-10-23 실측] **크기 상한.** 기준선이 10-19 에 멈춘 채 범위가 쌓여 diff 가
#   2.1MB 가 됐다. 그 크기는 ① 모델 문맥에 안 들어가고 ② 종전처럼 argv 로 넘기면
#   macOS ARG_MAX(1MB)에 걸려 exec 자체가 실패한다 → 기준선이 또 안 전진 → 영구 침묵.
#   → 넘치면 저장소별 **마지막 커밋만** 검토하고, 빠진 범위를 파일로 남긴다.
#     검토가 끝나면 기준선은 전진한다(밀린 범위를 끝없이 들고 다니지 않는다).
MAX_BYTES="${CODEX_AUTO_MAX_BYTES:-400000}"
TAMANO=$(wc -c < "$DIFF" | tr -d ' ')
if [ "$TAMANO" -gt "$MAX_BYTES" ]; then
  MARCA_TRUNC="$ROOT/.team/reviews/.auto-codex.TRUNCATED.$(date '+%Y%m%d-%H%M%S').txt"
  {
    printf 'truncated_at=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    printf 'bytes=%s max=%s\n' "$TAMANO" "$MAX_BYTES"
    printf 'range_not_reviewed=%s\n' "$(tr '\n' ' ' < "$SNAP_PREV" 2>/dev/null) -> $(printf '%s' "$NUEVO" | tr '\n' ' ')"
    printf 'note=범위가 너무 커서 저장소별 마지막 커밋만 검토했다. 필요하면 scripts/codex-review.sh 로 나눠 돌릴 것.\n'
  } > "$MARCA_TRUNC" 2>/dev/null || true
  echo "[codex-auto] diff 가 ${TAMANO}바이트(상한 ${MAX_BYTES}) — 저장소별 마지막 커밋만 검토한다." >&2
  # ★ [codex P1·P1·P2, 5889ec55] 자르기는 **저장소마다 따로**, **줄 경계에서만** 한다.
  #   합친 뒤 앞에서 자르면 뒤 저장소가 통째로 빠지는데 기준선은 전진한다(영구 미검토).
  #   줄 중간에서 자르면 자격증명 값의 앞부분만 남아 검사에 안 걸린 채 나가고,
  #   한글 중간에서 자르면 UTF-8 이 깨져 같은 자리에서 매번 실패한다.
  # ★ [codex P2, 991bd6c8] 몫은 **남은 예산 / 남은 저장소 수**로 그때그때 정한다 — 작은
  #   저장소가 안 쓴 몫이 다음 저장소로 넘어간다. 머리말·절단 표식도 예산에서 뺀다.
  # ★ [codex P1, 991bd6c8 — 수용하지 않음] 「잘렸으면 기준선을 멈춰라」는 따르지 않는다.
  #   몫보다 큰 커밋은 다음에도 똑같이 잘리므로, 멈추면 **영구 침묵이 그대로 돌아온다.**
  #   대신 잘린 저장소를 TRUNCATED 마커에 적는다 — 빠진 것이 보이게 한다.
  # 저장소별 diff 를 먼저 만들고 **작은 것부터** 몫을 준다 — 작은 저장소가 남긴 몫이 큰 쪽으로 간다.
  N_REPOS=0
  : > "$RUNDIR/partes"
  for entry in $CAMBIADOS; do
    r="${entry%%:*}"; sha="${entry##*:}"
    N_REPOS=$((N_REPOS + 1)); PARTE="$RUNDIR/parte.$N_REPOS"
    {
      echo "===== ${r} @ ${sha} (마지막 커밋만 — 범위가 상한을 넘었다) ====="
      git -C "$r" log -1 --pretty='커밋: %s' "$sha" 2>/dev/null
      git -C "$r" show --no-color --submodule=short "$sha" 2>/dev/null
    } > "$PARTE"
    N_OCULTAS_CAP=$(( ${N_OCULTAS_CAP:-0} + $(ocultar_en "$PARTE") ))
    printf '%s %s %s\n' "$(wc -c < "$PARTE" | tr -d ' ')" "$PARTE" "${r}@${sha}" >> "$RUNDIR/partes"
  done
  RESTANTE="$MAX_BYTES"
  CORTADOS=""
  : > "$DIFF"
  while read -r tam PARTE etiq; do
    CUOTA=$(( RESTANTE / (N_REPOS > 0 ? N_REPOS : 1) ))
    if [ "$tam" -gt "$CUOTA" ]; then
      MARCA_CORTE="===== (${etiq%@*}: 상한에서 줄 단위로 잘림) ====="
      CUERPO=$(( CUOTA - $(printf '%s\n' "$MARCA_CORTE" | wc -c | tr -d ' ') ))
      # LC_ALL=C — length 를 바이트로 센다. 줄은 통째로 넣거나 통째로 뺀다.
      LC_ALL=C awk -v max="$CUERPO" '{ n += length($0) + 1; if (n > max) exit; print }' "$PARTE" > "$PARTE.cut"
      printf '%s\n' "$MARCA_CORTE" >> "$PARTE.cut"
      USADO=$(wc -c < "$PARTE.cut" | tr -d ' ')
      cat "$PARTE.cut" >> "$DIFF"
      CORTADOS="${CORTADOS}${CORTADOS:+ }${etiq}"
    else
      cat "$PARTE" >> "$DIFF"
      USADO="$tam"
    fi
    RESTANTE=$(( RESTANTE - USADO )); N_REPOS=$(( N_REPOS - 1 ))
  done < <(sort -n "$RUNDIR/partes")
  rm -f "$RUNDIR"/parte.* "$RUNDIR/partes"
  if [ "${N_OCULTAS_CAP:-0}" -gt 0 ]; then
    echo "[codex-auto] 자격증명 형태 ${N_OCULTAS_CAP}줄을 가리고 보낸다(상한 경로)." >&2
    printf 'redacted_at=%s\ncount=%s\nheads=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$N_OCULTAS_CAP" "$(printf '%s' "$NUEVO" | tr '\n' ' ')" \
      > "$ROOT/.team/reviews/.auto-codex.REDACTED.$(date '+%Y%m%d-%H%M%S').txt" 2>/dev/null || true
  fi
  if [ -n "$CORTADOS" ]; then
    printf 'last_commit_cut=%s\n' "$CORTADOS" >> "$MARCA_TRUNC" 2>/dev/null || true
  fi
fi

SECRET_HITS=$(grep -inE "$SECRET_RE" "$DIFF" 2>/dev/null | grep -ivE "^[0-9]+:[+-]?[[:space:]]*$ESQUEMA_RE" | grep -ivE "^[0-9]+:[+-]?[[:space:]]*$SUSTITUCION_RE" || true)
# ★★★★ [2026-10-23 실측] **diff 전체를 거절하지 않고, 걸린 줄만 가린다.**
#   종전에는 한 줄이라도 걸리면 diff 를 통째로 버리고 기준선을 그대로 뒀다. 그런데
#   그 줄은 기준선 이후 **모든 누적 diff 에 다시 들어간다** — 그래서 한 번 걸리면
#   이후 커밋이 전부 같은 이유로 건너뛰어진다. 10-19 부터 10-23 까지 SKIPPED 마커가
#   1,800개 쌓였고 검토는 0건이었다(걸린 22줄 중 14줄은 `process.env` 참조 같은 오탐).
#   9-10 에 없앤 「영구 침묵」이 다른 길로 돌아온 것이다.
#   → 걸린 줄은 그 자리에서 **내용을 지운 표식 줄**로 바꾸고 나머지를 보낸다.
#     밖으로 나가지 않는다는 원래 목적은 그대로다(가린 줄은 전송되지 않는다).
#     개인키는 BEGIN…END 블록 전체를 가린다.
KEY_LINES=$(awk '/BEGIN [A-Z ]*PRIVATE KEY/{k=1} k{print NR} /END [A-Z ]*PRIVATE KEY/{k=0}' "$DIFF" 2>/dev/null)
OCULTAR=$( { printf '%s\n' "$SECRET_HITS" | cut -d: -f1; printf '%s\n' "$KEY_LINES"; } | grep -E '^[0-9]+$' | sort -n -u)
N_OCULTAS=0
if [ -n "$OCULTAR" ]; then
  N_OCULTAS=$(printf '%s\n' "$OCULTAR" | grep -c .)
  printf '%s\n' "$OCULTAR" > "$RUNDIR/ocultar"
  awk 'NR==FNR{o[$1]=1; next} (FNR in o){c=substr($0,1,1); if(c!="+" && c!="-") c=" "; print c "[codex-auto: 줄 생략 — 자격증명 형태]"; next} {print}' \
    "$RUNDIR/ocultar" "$DIFF" > "$DIFF.ocultado" && mv -f "$DIFF.ocultado" "$DIFF"
  # ★ 가린 뒤 다시 검사한다. 남아 있으면(가리기 실패) 종전처럼 보내지 않는다 — 안전 쪽.
  RESTO=$(grep -inE "$SECRET_RE" "$DIFF" 2>/dev/null | grep -ivE "^[0-9]+:[+-]?[[:space:]]*$ESQUEMA_RE" | grep -ivE "^[0-9]+:[+-]?[[:space:]]*$SUSTITUCION_RE" || true)
  if [ -n "$RESTO" ] || grep -qE 'BEGIN [A-Z ]*PRIVATE KEY' "$DIFF" 2>/dev/null; then
    echo "[codex-auto] ★ 자격증명 형태를 가리지 못했다 — **외부로 보내지 않는다.**" >&2
    {
      printf 'skipped_at=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
      printf 'reason=redaction_failed\n'
      printf 'heads_skipped=%s\n' "$(printf '%s' "$NUEVO" | tr '\n' ' ')"
    } > "$ROOT/.team/reviews/.auto-codex.SKIPPED.$(date '+%Y%m%d-%H%M%S').txt" 2>/dev/null || true
    rm -rf "$RUNDIR"
    exit 0
  fi
  # ★ 값은 남기지 않는다 — 줄 번호와 개수만. 사람이 원본 diff 에서 직접 본다.
  echo "[codex-auto] 자격증명 형태 ${N_OCULTAS}줄을 가리고 보낸다 (위치: $(printf '%s\n' "$OCULTAR" | head -5 | tr '\n' ',')…)." >&2
  {
    printf 'redacted_at=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    printf 'count=%s\n' "$N_OCULTAS"
    printf 'lines=%s\n' "$(printf '%s\n' "$OCULTAR" | head -10 | tr '\n' ',')"
    printf 'heads=%s\n' "$(printf '%s' "$NUEVO" | tr '\n' ' ')"
  } > "$ROOT/.team/reviews/.auto-codex.REDACTED.$(date '+%Y%m%d-%H%M%S').txt" 2>/dev/null || true
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
# ★ 저장소 표식을 **맨 앞에** 둔다. `bash -c "$(cat ...)"` 의 argv 에 스크립트 전문이
#   실리는데, `ps`/`pgrep` 이 보는 길이는 잘릴 수 있다 — 뒤에 두면 못 볼 수 있다.
printf '# codex-auto-run: %s\n' "$ROOT" > "$RUNNER"
cat >> "$RUNNER" <<'RUNNER_EOF'
#!/usr/bin/env bash
# 자동 생성됨 — codex-review-after-commit.sh 가 매번 덮어쓴다. 직접 고치지 말 것.
set -u
ok=0
# ★ [2026-10-23] argv 가 아니라 **stdin** 으로 넘긴다(`-`). argv 는 macOS ARG_MAX(1MB)에서
#   exec 가 실패한다 — 큰 diff 가 「실패 → 기준선 정지 → 다음엔 더 큰 diff」로 굳는다.
if cat "$PROMPT_FILE" "$DIFF" | codex exec --sandbox read-only - > "$OUT" 2>&1 && [ -s "$OUT" ]; then
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
export PROMPT_FILE DIFF OUT SNAP SNAP_PEND ROOT SELF
# ★ 파일 경로로 실행하지 않는다. 러너는 `$RUNDIR` 안에 있고 러너가 끝나면서
#   그 디렉터리를 지우는데, **실행 중인 스크립트 파일이 사라지면 bash 가 남은 줄을
#   못 읽는다.** 내용을 읽어 넘기면 파일 의존이 없다(따옴표는 한 겹뿐이다).
nohup bash -c "$(cat "$RUNNER")" >/dev/null 2>&1 &

echo "[codex-auto] CODEX 검토를 백그라운드로 띄웠다 (${CAMBIADOS}). 결과: ${OUT#$ROOT/}" >&2
echo "[codex-auto] ★ push 승인을 구하기 전에 이 보고서를 읽어야 한다." >&2

exit 0
