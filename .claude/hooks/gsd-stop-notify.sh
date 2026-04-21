#!/usr/bin/env bash
# ------------------------------------------------------------
# GSD Stop-event Telegram 알림 hook
#
# 동작:
#   - Stop hook 으로 실행됨 (Claude 가 사용자에게 턴을 넘기는 순간)
#   - .claude/hooks/.gsd-snapshot.json 의 최신 진행 상황을 읽음
#   - transcript 마지막 assistant 메시지 첫 줄(최대 300자) 추출
#   - 세션 소요 시간 계산 → 최소 시간(TELEGRAM_MIN_DURATION_SEC) 필터 적용
#   - Telegram 전송 (비차단 백그라운드, 3초 타임아웃)
#
# 주의:
#   - stop_hook_active=true 이면 즉시 종료 (루프 방지)
#   - env/snapshot 누락 시 조용히 exit 0 (Claude 진행 방해 금지)
# ------------------------------------------------------------
set -u
# set -e 사용 금지: 알림 실패가 Claude 세션을 막으면 안 됨

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${HOOK_DIR}/telegram.env"
SNAPSHOT="${HOOK_DIR}/.gsd-snapshot.json"

# env 없으면 조용히 종료
[[ -f "${ENV_FILE}" ]] || exit 0
# shellcheck disable=SC1090
source "${ENV_FILE}"
[[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]] || exit 0

MIN_DURATION="${TELEGRAM_MIN_DURATION_SEC:-30}"

# ------------------------------------------------------------
# Claude 가 넘겨준 stdin JSON 파싱
# 예: { "session_id": "...", "transcript_path": "...", "cwd": "...", "stop_hook_active": false }
# ------------------------------------------------------------
HOOK_INPUT="$(cat 2>/dev/null || true)"

extract_field() {
  local key="$1"
  if command -v jq >/dev/null 2>&1; then
    echo "${HOOK_INPUT}" | jq -r ".${key} // empty" 2>/dev/null
  else
    echo "${HOOK_INPUT}" \
      | grep -o "\"${key}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
      | head -1 \
      | sed -E "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"/\1/"
  fi
}

SESSION_ID="$(extract_field session_id)"
TRANSCRIPT_PATH="$(extract_field transcript_path)"
CWD="$(extract_field cwd)"
STOP_HOOK_ACTIVE="$(extract_field stop_hook_active)"

# 이미 다른 Stop hook 이 돌고 있으면 루프 방지
if [[ "${STOP_HOOK_ACTIVE}" == "true" ]]; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${CWD:-$PWD}}"
PROJECT_NAME="$(basename "${PROJECT_DIR}")"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

# ------------------------------------------------------------
# transcript 마지막 assistant 메시지 첫 줄 + 세션 소요 시간 추출
# ------------------------------------------------------------
LAST_SUMMARY=""
DURATION_SEC=0
if [[ -n "${TRANSCRIPT_PATH}" && -f "${TRANSCRIPT_PATH}" ]] && command -v jq >/dev/null 2>&1; then
  LAST_SUMMARY="$(tac "${TRANSCRIPT_PATH}" 2>/dev/null \
    | jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' 2>/dev/null \
    | head -1 \
    | head -c 300)"

  FIRST_TS="$(jq -r 'select(.timestamp) | .timestamp' "${TRANSCRIPT_PATH}" 2>/dev/null | head -1)"
  if [[ -n "${FIRST_TS}" ]]; then
    FIRST_EPOCH="$(date -j -f "%Y-%m-%dT%H:%M:%S" "${FIRST_TS%.*}" +%s 2>/dev/null \
      || date -d "${FIRST_TS}" +%s 2>/dev/null \
      || echo 0)"
    NOW_EPOCH="$(date +%s)"
    if [[ "${FIRST_EPOCH}" != "0" ]]; then
      DURATION_SEC=$(( NOW_EPOCH - FIRST_EPOCH ))
    fi
  fi
fi

# 최소 소요시간 필터 (짧은 Q&A 턴은 알림 생략)
if [[ "${DURATION_SEC}" -gt 0 && "${DURATION_SEC}" -lt "${MIN_DURATION}" ]]; then
  exit 0
fi

format_duration() {
  local s=$1
  if [[ $s -lt 60 ]]; then
    echo "${s}초"
  elif [[ $s -lt 3600 ]]; then
    echo "$((s/60))분 $((s%60))초"
  else
    echo "$((s/3600))시간 $(((s%3600)/60))분"
  fi
}
DURATION_HUMAN="$(format_duration "${DURATION_SEC}")"

# ------------------------------------------------------------
# 진행 상황 한 줄 요약 (.gsd-snapshot.json 있으면 읽어서)
# ------------------------------------------------------------
PROGRESS_LINE=""
if [[ -f "${SNAPSHOT}" ]] && command -v jq >/dev/null 2>&1; then
  PROGRESS_LINE="$(jq -r '
    if (.completedPlans != null and .totalPlans != null) then
      "📋 Plans \(.completedPlans)/\(.totalPlans) · Phases \(.completedPhases)/\(.totalPhases) (\(.percent)%)"
    else
      ""
    end
  ' "${SNAPSHOT}" 2>/dev/null)"
fi

# ------------------------------------------------------------
# 메시지 구성 (Markdown 특수문자 이스케이프)
# ------------------------------------------------------------
sanitize() {
  echo -n "$1" | sed -e 's/`/\\`/g' -e 's/_/\\_/g' -e 's/\*/\\*/g'
}

SAFE_PROJECT="$(sanitize "${PROJECT_NAME}")"
SAFE_SUMMARY="$(sanitize "${LAST_SUMMARY:-(요약 없음)}")"

MESSAGE="🛑 *Claude 세션 정지 — 사용자 입력 대기*
📁 ${SAFE_PROJECT}
⏱️ 소요: ${DURATION_HUMAN}
🕒 ${TIMESTAMP}"

if [[ -n "${PROGRESS_LINE}" ]]; then
  MESSAGE="${MESSAGE}
${PROGRESS_LINE}"
fi

MESSAGE="${MESSAGE}

${SAFE_SUMMARY}"

# ------------------------------------------------------------
# Telegram 전송 (비차단, 3초 타임아웃, 백그라운드)
# ------------------------------------------------------------
curl -s --max-time 3 \
  -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d "chat_id=${TELEGRAM_CHAT_ID}" \
  --data-urlencode "text=${MESSAGE}" \
  -d "parse_mode=Markdown" \
  -d "disable_web_page_preview=true" \
  >/dev/null 2>&1 &

exit 0
