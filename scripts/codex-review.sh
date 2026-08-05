#!/usr/bin/env bash
# codex-review.sh — codex 에 보안 검토를 시키고 보고서를 .team/reviews/ 에 남긴다.
#
# 규약: .team/REVIEW-PROTOCOL.md  /  역할 정의: AGENTS.md (codex 가 자동으로 읽는다)
# codex 는 보고서만 낸다. 코드 수정·커밋은 Claude Code 가 한다.
#
# 사용:
#   scripts/codex-review.sh --working            # 미커밋 변경 (staged+unstaged+untracked)
#   scripts/codex-review.sh --task 002           # main 대비 현재 브랜치
#   scripts/codex-review.sh --commit <sha>       # 특정 커밋
#   scripts/codex-review.sh --task 002 --dry-run # 실행할 명령만 출력
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TASK=""
MODE=""
SHA=""
BASE="${CODEX_REVIEW_BASE:-main}"
DRY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task)    TASK="$2"; MODE="task"; shift 2 ;;
    --working) MODE="working"; shift ;;
    --commit)  SHA="$2"; MODE="commit"; shift 2 ;;
    --base)    BASE="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    *) echo "알 수 없는 인자: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$MODE" ]] || { echo "모드를 지정하세요: --working | --task <N> | --commit <sha>" >&2; exit 2; }

# codex 존재 확인 — `command -v` 만으로는 부족하다. cmux 가 PATH 에 shim 을 깔아두기 때문에
# 실제 바이너리가 없어도 경로는 잡히고, shim 은 "not found" 를 찍으면서 exit 0 을 준다.
# 그래서 --version 출력 내용으로 판정한다.
CODEX_VER="$(codex --version 2>&1 || true)"
if ! command -v codex >/dev/null 2>&1 || printf '%s' "$CODEX_VER" | grep -qi 'not found'; then
  cat >&2 <<'MSG'
codex 를 찾을 수 없습니다. (cmux shim 만 있고 실제 바이너리가 없는 상태일 수 있습니다)

  npm i -g @openai/codex
  codex login

설치 후 다시 실행하세요. (cmux codex-teams 도 같은 바이너리를 씁니다)
MSG
  exit 127
fi

# 검토 지시 — AGENTS.md 가 역할·보고형식·심각도를 이미 정의하므로 여기서는
# 이 저장소에서 실제로 사고가 났던 지점만 우선순위로 얹는다.
read -r -d '' PROMPT <<'EOF' || true
AGENTS.md 에 정의된 보안 검토자 역할과 보고 형식을 그대로 따르라.

이 저장소에서 실제로 사고가 났던 지점을 우선 확인하라 (.team/REVIEW-PROTOCOL.md):
1. 쓰기 경로에서 transaction 인자 누락 → 부분 저장
2. stocks 는 append-only 원장 (UPDATE/DELETE 금지, product_branch_id 기준, product_id 컬럼 없음)
3. 사용자가 준 branchId/variantId/storeId 를 소유권 확인 없이 사용
4. 권한·역할 판정 실패 시 오히려 더 주는 fail-open 분기
5. 트랜잭션 안에서의 HTTP·프린터·소켓 호출

근거 없는 추측은 내지 마라. 확실하지 않으면 "확인 필요"로 표시하고 이유를 써라.
이상이 없으면 "이상 없음"이라고 명확히 써라. 파일을 수정하지 마라.
EOF

case "$MODE" in
  working)
    ARGS=(--uncommitted)
    LABEL="워킹트리 (uncommitted)"
    OUT=".team/reviews/working-codex.md"
    ;;
  task)
    [[ -n "$TASK" ]] || { echo "--task 에 번호가 필요합니다 (예: --task 002)" >&2; exit 2; }
    ARGS=(--base "$BASE")
    LABEL="task ${TASK} (base=${BASE})"
    OUT=".team/reviews/${TASK}-codex.md"
    ;;
  commit)
    ARGS=(--commit "$SHA")
    LABEL="commit ${SHA}"
    OUT=".team/reviews/commit-${SHA}-codex.md"
    ;;
esac

# 저장소에 평문 자격증명이 남아 있으면 경고 — 검토 대상 diff 에 섞여 들어갈 수 있다.
# (비밀번호를 *제거하는* 커밋의 diff 는 삭제된 줄에 값을 그대로 싣는다.)
# 근본 해결은 태스크 004(평문 제거) + 005(회전)다. 여기서는 알리고 진행한다.
# 따옴표 있는 형태(`password:'v'`)와 없는 형태(YAML `password: v`, `PGPASSWORD=v`) 둘 다 잡는다.
# 따옴표만 가정하면 설정파일 형식을 통째로 놓친다 (codex 검토 지적, 2026-08-05).
SECRET_RE="(password|passwd|pwd)[[:space:]]*[:=][[:space:]]*['\"]?[^'\"[:space:]<][^'\"[:space:]]{5,}"
if git grep -qiE "$SECRET_RE" -- . ':(exclude)scripts/codex-review.sh' 2>/dev/null; then
  echo "경고: 저장소에 평문 자격증명 형태가 남아 있습니다 (태스크 004/005 대상)." >&2
  echo "      검토 대상에 포함되면 codex 세션에 값이 남습니다." >&2
fi

mkdir -p .team/reviews

if [[ "$DRY" == "1" ]]; then
  echo "dry-run — 실행하지 않고 명령만 출력"
  echo "codex review ${ARGS[*]} --title '<프롬프트>'  →  $OUT"
  exit 0
fi

echo "codex 검토 실행 — ${LABEL}"
# codex 0.146 기준 `--commit` 은 PROMPT 인자와 동시 사용이 막혀 있다(clap 충돌).
# 프롬프트 없이도 codex 는 AGENTS.md 를 읽으므로, 충돌하면 프롬프트를 빼고 재시도한다.
if ! codex review "${ARGS[@]}" "$PROMPT" > "$OUT" 2>"$OUT.err"; then
  if grep -q 'cannot be used with' "$OUT.err"; then
    echo "(이 모드는 추가 프롬프트를 받지 않음 — AGENTS.md 만으로 재시도)"
    codex review "${ARGS[@]}" > "$OUT" 2>"$OUT.err" || { cat "$OUT.err" >&2; rm -f "$OUT.err"; exit 1; }
  else
    cat "$OUT.err" >&2; rm -f "$OUT.err"; exit 1
  fi
fi
rm -f "$OUT.err"
cat "$OUT"

echo
echo "보고서: $OUT"
echo "다음 단계 — 지적별 수용/반박을 ${OUT%-codex.md}-resolution.md 에 기록하고,"
echo "CRITICAL/HIGH 가 남아 있으면 push 하지 않는다 (.team/REVIEW-PROTOCOL.md)"
