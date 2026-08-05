#!/usr/bin/env bash
# codex-review.sh — 변경 diff 를 codex 에 넘겨 보안 검토 보고서를 받는다.
#
# 규약: .team/REVIEW-PROTOCOL.md  /  역할 정의: AGENTS.md
# codex 는 보고서만 낸다. 코드 수정·커밋은 Claude Code 가 한다.
#
# 사용:
#   scripts/codex-review.sh --task 001
#   scripts/codex-review.sh --working
#   scripts/codex-review.sh --task 002 --paths api-ventago/src/app/products
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TASK=""
MODE="task"
PATHS=()
BASE="${CODEX_REVIEW_BASE:-main}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task)    TASK="$2"; MODE="task"; shift 2 ;;
    --working) MODE="working"; shift ;;
    --paths)   shift; while [[ $# -gt 0 && "$1" != --* ]]; do PATHS+=("$1"); shift; done ;;
    --base)    BASE="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    *) echo "알 수 없는 인자: $1" >&2; exit 2 ;;
  esac
done
DRY="${DRY:-0}"

# codex 존재 확인 — `command -v` 만으로는 부족하다. cmux 가 PATH 에 shim 을 깔아두기 때문에
# 실제 바이너리가 없어도 경로는 잡히고, shim 은 "not found" 를 찍으면서 exit 0 을 준다.
# 그래서 --version 출력 내용으로 판정한다.
CODEX_VER="$(codex --version 2>&1 || true)"
if [[ "$DRY" != "1" ]] && { ! command -v codex >/dev/null 2>&1 || printf '%s' "$CODEX_VER" | grep -qi 'not found'; }; then
  cat >&2 <<'MSG'
codex 를 찾을 수 없습니다. (cmux shim 만 있고 실제 바이너리가 없는 상태일 수 있습니다)

  npm i -g @openai/codex
  codex login

설치 후 다시 실행하세요. (cmux codex-teams 도 같은 바이너리를 씁니다)
MSG
  exit 127
fi

# 시크릿이 담긴 파일은 diff 자체에서 제외 — codex 가 값을 보지 못하게 한다 (AGENTS.md 금지 항목)
EXCLUDES=(
  ':(exclude).env' ':(exclude).env.*' ':(exclude)**/.env' ':(exclude)**/.env.*'
  ':(exclude)**/*.pem' ':(exclude)**/*.key' ':(exclude)**/id_*'
  ':(exclude)**/package-lock.json'
)

# bash 3.2 에서 빈 배열 + set -u 조합은 unbound 로 죽는다 — 개수로 분기한다
if [[ ${#PATHS[@]} -eq 0 ]]; then
  TARGETS=(.)
else
  TARGETS=("${PATHS[@]}")
fi

# --ignore-submodules=all 필수 — 서브모듈(api-ventago/ventago-app)이 체크아웃돼 있으면
# git diff 가 그 워킹트리를 통째로 스캔하며 멈춘다. 서브모듈 코드 검토는 해당 저장소 안에서
# 이 스크립트를 돌린다(아래 「서브모듈 검토」 참조).
DIFFOPTS=(--ignore-submodules=all)

if [[ "$MODE" == "task" ]]; then
  [[ -n "$TASK" ]] || { echo "--task 에 번호가 필요합니다 (예: --task 001)" >&2; exit 2; }
  DIFF="$(git diff "${DIFFOPTS[@]}" "$BASE"...HEAD -- "${TARGETS[@]}" "${EXCLUDES[@]}")"
  LABEL="task ${TASK} (${BASE}...HEAD)"
  OUT=".team/reviews/${TASK}-codex.md"
else
  DIFF="$(git diff "${DIFFOPTS[@]}" HEAD -- "${TARGETS[@]}" "${EXCLUDES[@]}")"
  LABEL="워킹트리 (uncommitted)"
  OUT=".team/reviews/working-codex.md"
fi

# 공백 제거 비교(${DIFF//.../}) 금지 — macOS 기본 bash 3.2 에서 수십 KB 문자열에 쓰면 사실상 멈춘다.
if ! printf '%s' "$DIFF" | grep -q '[^[:space:]]'; then
  echo "검토할 변경이 없습니다 — $LABEL"
  exit 0
fi

# ── 시크릿 리댁션 ─────────────────────────────────────────────────────────────
# 파일 단위 제외(EXCLUDES)만으로는 부족하다. 비밀번호를 *제거하는* 커밋의 diff 에는
# 삭제된 줄(`-`)에 값이 그대로 실린다. 값 형태로 한 번 더 지운다.
DIFF="$(printf '%s' "$DIFF" | sed -E \
  -e 's#(postgres(ql)?://[^:/@[:space:]]+):[^@[:space:]]+@#\1:<REDACTED>@#g' \
  -e "s/(password[[:space:]]*[:=][[:space:]]*)'[^']*'/\1'<REDACTED>'/gI" \
  -e 's/(password[[:space:]]*[:=][[:space:]]*)"[^"]*"/\1"<REDACTED>"/gI' \
  -e 's/(PGPASSWORD=)[^[:space:]"'"'"']+/\1<REDACTED>/g' \
  -e 's/((DATABASE|DB|PG|JWT|API)_[A-Z_]*(PASSWORD|SECRET|KEY|TOKEN)[[:space:]]*=[[:space:]]*)[^[:space:]"'"'"']+/\1<REDACTED>/g' \
)"

# 리댁션이 실제로 먹었는지 확인 — 남아 있으면 보내지 않는다 (fail-closed)
if printf '%s' "$DIFF" | grep -qiE "password[[:space:]]*[:=][[:space:]]*['\"][^'\"<]{6,}['\"]"; then
  echo "중단: diff 에 리댁션되지 않은 자격증명 형태가 남아 있습니다." >&2
  echo "해당 줄을 확인하고 --paths 로 범위를 좁히거나 리댁션 규칙을 보강하세요." >&2
  printf '%s' "$DIFF" | grep -niE "password[[:space:]]*[:=][[:space:]]*['\"][^'\"<]{6,}['\"]" | head -5 | sed -E "s/(['\"])[^'\"]{6,}(['\"])/\1…\2/g" >&2
  exit 3
fi

mkdir -p .team/reviews

PROMPT=$(cat <<EOF
저장소 루트의 AGENTS.md 에 정의된 보안 검토자 역할로 아래 diff 를 검토하라.

대상: ${LABEL}

AGENTS.md 의 보고 형식과 심각도 체계를 그대로 따른다. 근거 없는 추측은 내지 말고,
확실하지 않으면 "확인 필요"로 표시하고 이유를 써라. 이상이 없으면 "이상 없음"이라고 명확히 써라.

이 프로젝트에서 실제로 사고가 났던 지점을 우선 확인하라 (.team/REVIEW-PROTOCOL.md 참조):
1. 쓰기 경로에서 transaction 인자 누락 → 부분 저장
2. stocks 는 append-only 원장 (UPDATE/DELETE 금지, product_branch_id 기준, product_id 컬럼 없음)
3. 사용자가 준 branchId/variantId/storeId 를 소유권 확인 없이 사용
4. 권한·역할 판정 실패 시 오히려 더 주는 fail-open 분기
5. 트랜잭션 안에서의 HTTP·프린터·소켓 호출

파일을 수정하지 마라. 보고서만 출력하라.

--- diff 시작 ---
${DIFF}
--- diff 끝 ---
EOF
)

if [[ "$DRY" == "1" ]]; then
  printf '%s\n' "$PROMPT" > "${OUT%.md}-prompt.txt"
  echo "dry-run — codex 호출 없이 프롬프트만 생성: ${OUT%.md}-prompt.txt"
  exit 0
fi

echo "codex 검토 실행 — ${LABEL}"
# NOTE: codex 비대화 실행 형식. 설치된 codex 버전에 따라 서브커맨드명이 다르면 이 줄만 고치면 된다.
codex exec "$PROMPT" > "$OUT"

echo "보고서: $OUT"
echo
echo "다음 단계 — 지적별 수용/반박을 .team/reviews/ 에 기록하고,"
echo "CRITICAL/HIGH 가 남아 있으면 push 하지 않는다 (.team/REVIEW-PROTOCOL.md)"
