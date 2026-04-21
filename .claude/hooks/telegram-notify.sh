#!/usr/bin/env bash
# ------------------------------------------------------------
# Claude Code Stop-event Telegram 알림 hook
#
# - .claude/hooks/telegram.env 에서 토큰/chat_id 읽음
# - transcript 마지막 줄(assistant text) 을 추출하여 메시지에 포함
# - 프로젝트 경로 · 타임스탬프 · 세션 소요시간 함께 전송
# - Telegram API 호출은 2초 타임아웃, 실패해도 Claude 실행 차단하지 않음
# ------------------------------------------------------------
set -u
# set -e 쓰지 않음: 알림 실패가 Claude 작업을 멈추게 하면 안 됨

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${HOOK_DIR}/telegram.env"

# env 파일 없으면 조용히 종료
if [[ ! -f "${ENV_FILE}" ]]; then
  exit 0
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

# 필수 변수 검증
if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
  exit 0
fi

MIN_DURATION="${TELEGRAM_MIN_DURATION_SEC:-0}"

# ------------------------------------------------------------
# Claude Code 가 hook 에게 JSON 을 stdin 으로 넘겨줌
# 예: { "session_id": "...", "transcript_path": "...", "cwd": "...", "stop_hook_active": false }
# jq 있으면 사용, 없으면 grep 폴백
# ------------------------------------------------------------
HOOK_INPUT="$(cat || true)"

extract_field() {
  local key="$1"
  if command -v jq >/dev/null 2>&1; then
    echo "${HOOK_INPUT}" | jq -r ".${key} // empty" 2>/dev/null
  else
    echo "${HOOK_INPUT}" | grep -o "\"${key}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed -E "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"/\1/"
  fi
}

SESSION_ID="$(extract_field session_id)"
TRANSCRIPT_PATH="$(extract_field transcript_path)"
CWD="$(extract_field cwd)"
STOP_HOOK_ACTIVE="$(extract_field stop_hook_active)"

# 이미 다른 Stop hook 이 처리 중이면 건너뜀 (루프 방지)
if [[ "${STOP_HOOK_ACTIVE}" == "true" ]]; then
  exit 0
fi

PROJECT_NAME="$(basename "${CWD:-$PWD}")"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

# ------------------------------------------------------------
# transcript 마지막 assistant 메시지 첫 줄 추출 (요약용)
# transcript 는 JSONL: {"type":"assistant","message":{"content":[{"type":"text","text":"..."}]}}
# ------------------------------------------------------------
LAST_SUMMARY=""
DURATION_SEC=0
if [[ -n "${TRANSCRIPT_PATH}" && -f "${TRANSCRIPT_PATH}" ]]; then
  if command -v jq >/dev/null 2>&1; then
    LAST_SUMMARY="$(tac "${TRANSCRIPT_PATH}" 2>/dev/null \
      | jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' 2>/dev/null \
      | head -1 \
      | head -c 300)"

    # 첫 user 메시지 timestamp 와 현재 시각 비교하여 대략적 duration 계산
    FIRST_TS="$(jq -r 'select(.timestamp) | .timestamp' "${TRANSCRIPT_PATH}" 2>/dev/null | head -1)"
    if [[ -n "${FIRST_TS}" ]]; then
      FIRST_EPOCH="$(date -j -f "%Y-%m-%dT%H:%M:%S" "${FIRST_TS%.*}" +%s 2>/dev/null || date -d "${FIRST_TS}" +%s 2>/dev/null || echo 0)"
      NOW_EPOCH="$(date +%s)"
      if [[ "${FIRST_EPOCH}" != "0" ]]; then
        DURATION_SEC=$(( NOW_EPOCH - FIRST_EPOCH ))
      fi
    fi
  fi
fi

# 최소 소요시간 필터
if [[ "${DURATION_SEC}" -gt 0 && "${DURATION_SEC}" -lt "${MIN_DURATION}" ]]; then
  exit 0
fi

# duration 사람이 읽기 좋게 포맷
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
# 메시지 구성 (Markdown) — 특수문자는 최소한만 이스케이프
# ------------------------------------------------------------
# Markdown 파싱 에러 방지: 백틱과 언더스코어 이스케이프
sanitize() {
  echo -n "$1" | sed -e 's/`/\\`/g' -e 's/_/\\_/g' -e 's/\*/\\*/g'
}

SAFE_PROJECT="$(sanitize "${PROJECT_NAME}")"
SAFE_SUMMARY="$(sanitize "${LAST_SUMMARY:-(요약 없음)}")"

MESSAGE="✅ *Claude 작업 완료*
📁 프로젝트: ${SAFE_PROJECT}
⏱️ 소요: ${DURATION_HUMAN}
🕒 ${TIMESTAMP}

${SAFE_SUMMARY}"

# ------------------------------------------------------------
# Telegram API 호출 (비차단: 2초 타임아웃, 백그라운드)
# ------------------------------------------------------------
curl -s --max-time 3 \
  -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d "chat_id=${TELEGRAM_CHAT_ID}" \
  --data-urlencode "text=${MESSAGE}" \
  -d "parse_mode=Markdown" \
  -d "disable_web_page_preview=true" \
  >/dev/null 2>&1 &

# hook 은 즉시 종료 (Claude 차단하지 않음)
exit 0
