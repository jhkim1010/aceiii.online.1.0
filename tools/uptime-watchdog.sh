#!/bin/bash
# ============================================================
# [Phase 65 W8] 외부 uptime 워치독 — Mac(launchd)에서 60초마다 운영 API 를 밖에서 확인
#
# 배경: 서버 내부 알람(Telegram 500)은 프로세스가 죽으면 함께 죽는다.
#       이 스크립트는 서버 "외부"(사용자 Mac)에서 /api/health 를 확인해 그 고리를 끊는다.
#       2026-07-25 재부팅 후 2시간 무감지 다운의 재발 방지 장치.
#
# 동작: 연속 2회 실패 시 Telegram 1회 알림, 복구 시 1회 알림 (플랩 방지).
#       상태는 /tmp/ventago-uptime.state 에 유지.
# 설치: launchd (com.ventago.uptime-watchdog.plist, StartInterval 60)
# 자격증명: tools/.uptime.env (TELEGRAM_BOT_TOKEN/TELEGRAM_CHAT_ID — gitignore, 서버 .env 에서 복사)
# ============================================================

set -u
HEALTH_URL="https://newapi.coolsistema.com/api/health"
STATE_FILE="/tmp/ventago-uptime.state"
ENV_FILE="$(cd "$(dirname "$0")" && pwd)/.uptime.env"

# 자격증명 로드 (없으면 로그만 — 감시 자체는 계속)
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

send_telegram() {
  local text="$1"
  if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
    echo "$(date '+%F %T') [watchdog] TELEGRAM 미설정 — 알림 생략: $text"
    return
  fi
  curl -s -m 10 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" \
    --data-urlencode text="$text" \
    -d parse_mode=HTML >/dev/null 2>&1 || true
}

# 헬스 확인 (10초 타임아웃, HTTP 200 + "ok":true 요구)
BODY=$(curl -s -m 10 -w '\n%{http_code}' "$HEALTH_URL" 2>/dev/null)
CODE=$(echo "$BODY" | tail -1)
OK=false
if [ "$CODE" = "200" ] && echo "$BODY" | head -1 | grep -q '"ok":true'; then
  OK=true
fi

# 상태 파일: "<연속실패수> <알림발송여부(0/1)>"
FAILS=0
ALERTED=0
if [ -f "$STATE_FILE" ]; then
  read -r FAILS ALERTED < "$STATE_FILE" 2>/dev/null || true
fi

if [ "$OK" = "true" ]; then
  if [ "${ALERTED:-0}" = "1" ]; then
    send_telegram "✅ <b>VentaGo API 복구</b> — /api/health OK ($(date '+%F %T'))"
  fi
  echo "0 0" > "$STATE_FILE"
  echo "$(date '+%F %T') [watchdog] OK"
else
  FAILS=$((${FAILS:-0} + 1))
  if [ "$FAILS" -ge 2 ] && [ "${ALERTED:-0}" = "0" ]; then
    send_telegram "🚨 <b>VentaGo API 다운 감지</b> — /api/health 연속 ${FAILS}회 실패 (HTTP ${CODE:-없음}, $(date '+%F %T')). 서버/DB 확인 필요."
    ALERTED=1
  fi
  echo "$FAILS ${ALERTED:-0}" > "$STATE_FILE"
  echo "$(date '+%F %T') [watchdog] FAIL #$FAILS (HTTP ${CODE:-none})"
fi
