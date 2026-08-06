#!/bin/bash
# ============================================================
# [Phase 75 W1-9 / Phase 74 R4-3] 백업·리포트 부재 감지 워치독
#
# 배경: 서버 안의 감시는 서버가 죽으면 함께 죽는다. uptime-watchdog.sh 가
#       "API 가 살아 있는가"를 밖에서 보는 것처럼, 이 스크립트는
#       "백업과 일일 점검이 실제로 돌고 있는가"를 밖에서 본다.
#
#       실패 알림만으로는 부족하다 — 크론 자체가 안 돌면 실패 알림도 안 온다.
#       그래서 "결과물이 낡았는가"를 본다(dead man's switch).
#
# 동작: ssh 로 두 파일의 나이를 확인한다.
#         1) 최신 백업 덤프  (임계 26h)
#         2) 일일 점검 JSONL (임계 26h)
#       임계 초과 시 Telegram 1회 알림, 복구 시 1회 알림 (플랩 방지).
#       ssh 자체가 실패하면 uptime-watchdog 이 이미 알리므로 여기서는 조용히 넘어간다.
#
# 설치: launchd (com.ventago.backup-freshness.plist, StartInterval 3600)
# 자격증명: tools/.uptime.env (uptime-watchdog.sh 와 공유 — gitignore)
# ============================================================

set -u

SSH_HOST="${VENTAGO_SSH_HOST:-jhkim-server}"
BACKUP_DIR="/var/lib/postgresql/pg_backups"
METRICS_DIR="/var/lib/postgresql/ops-metrics"

# 임계(시간). 테스트 시 `STALE_HOURS=0 ./backup-freshness-watchdog.sh` 로 알림 경로를 실증한다.
STALE_HOURS="${STALE_HOURS:-26}"

STATE_FILE="/tmp/ventago-backup-freshness.state"
ENV_FILE="$(cd "$(dirname "$0")" && pwd)/.uptime.env"

TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

send_telegram() {
  local text="$1"
  if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
    echo "$(date '+%F %T') [freshness] TELEGRAM 미설정 — 알림 생략: $text"
    return
  fi
  curl -s -m 10 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" \
    --data-urlencode text="$text" \
    -d parse_mode=HTML >/dev/null 2>&1 || true
}

# 원격 파일의 나이(시간). 파일이 없으면 99999, ssh 실패면 빈 문자열.
# ★ `ssh -n` 필수 — ssh 는 기본적으로 stdin 을 소비한다. 이 스크립트가 파이프로 실행되거나
#   (`... | bash`) 호출자가 stdin 을 넘기면 ssh 가 나머지 스크립트를 통째로 삼켜 조용히 중단된다.
#   2026-08-06 테스트에서 실제로 이 증상을 겪었다.
remote_age_hours() {
  local pattern="$1"
  ssh -n -o BatchMode=yes -o ConnectTimeout=10 "$SSH_HOST" \
    "sudo -u postgres bash -c '
       f=\$(ls -t ${pattern} 2>/dev/null | head -1)
       if [ -z \"\$f\" ]; then echo 99999; exit 0; fi
       now=\$(date +%s); m=\$(stat -c %Y \"\$f\")
       echo \$(( (now - m) / 3600 ))
     '" 2>/dev/null
}

DUMP_AGE=$(remote_age_hours "${BACKUP_DIR}/ventago_*.dump")
JSONL_AGE=$(remote_age_hours "${METRICS_DIR}/daily.jsonl")

# ── launchd 에이전트 생존 확인 ──────────────────────────────────────────────
# 2026-08-06: 저장소 경로 이동으로 plist 4개가 옛 경로를 가리킨 채 **등록 해제**돼 있었다.
# 서버가 죽어도 아무도 모르는 상태였고, 아무도 그것을 몰랐다.
# 감시기 자체를 감시하지 않으면 같은 일이 반복된다.
EXPECTED_AGENTS="uptime-watchdog trello-sync agent-runner git-fetch-notify backup-freshness"
MISSING_AGENTS=""
for a in $EXPECTED_AGENTS; do
  launchctl list "com.ventago.$a" >/dev/null 2>&1 || MISSING_AGENTS="${MISSING_AGENTS} ${a}"
done

# ssh 실패 — uptime-watchdog 이 이미 다룬다. 중복 알림하지 않는다.
if [ -z "${DUMP_AGE}" ]; then
  echo "$(date '+%F %T') [freshness] ssh 실패 — 판정 보류 (uptime-watchdog 담당)"
  exit 0
fi

PROBLEMS=""
[ "${DUMP_AGE}" -gt "$STALE_HOURS" ] 2>/dev/null && \
  PROBLEMS="${PROBLEMS}🚨 백업 덤프가 <b>${DUMP_AGE}시간</b>째 갱신되지 않았습니다 (임계 ${STALE_HOURS}h)\n"

# 2026-08-06 서버 배포 완료 — 이제 파일 부재(99999)도 문제다. 부재를 조용히 넘기면
# 수집기가 지워지거나 크론이 빠진 것을 아무도 모른다. 서버측 heartbeat 판정과 대칭.
if [ "${JSONL_AGE}" = "99999" ]; then
  PROBLEMS="${PROBLEMS}🚨 일일 점검 리포트(daily.jsonl)가 없습니다 — 수집기가 미설치이거나 삭제됐습니다\n"
elif [ -n "${JSONL_AGE}" ] && [ "${JSONL_AGE}" -gt "$STALE_HOURS" ] 2>/dev/null; then
  PROBLEMS="${PROBLEMS}⚠️ 일일 점검 리포트가 <b>${JSONL_AGE}시간</b>째 갱신되지 않았습니다\n"
fi

[ -n "$MISSING_AGENTS" ] && \
  PROBLEMS="${PROBLEMS}🚨 launchd 에이전트 미등록:<code>${MISSING_AGENTS}</code> — 감시가 꺼져 있습니다\n"

# 서버에 heartbeat 를 남긴다 — 이 Mac 워치독이 죽으면 서버측 일일 점검이 알아챈다(상호 감시).
ssh -n -o BatchMode=yes -o ConnectTimeout=10 "$SSH_HOST" \
  "sudo -u postgres touch ${METRICS_DIR}/mac-watchdog.heartbeat 2>/dev/null" >/dev/null 2>&1 || true

ALERTED=0
[ -f "$STATE_FILE" ] && read -r ALERTED < "$STATE_FILE" 2>/dev/null

if [ -n "$PROBLEMS" ]; then
  if [ "${ALERTED:-0}" = "0" ]; then
    send_telegram "$(printf "🚨 <b>VentaGo 백업 부재 감지</b>\n\n${PROBLEMS}\n서버 크론(postgres 유저) 확인이 필요합니다.")"
    echo "1" > "$STATE_FILE"
  fi
  echo "$(date '+%F %T') [freshness] STALE dump=${DUMP_AGE}h jsonl=${JSONL_AGE}h"
else
  if [ "${ALERTED:-0}" = "1" ]; then
    send_telegram "✅ <b>VentaGo 백업 정상 복구</b> — 덤프 ${DUMP_AGE}시간 전 ($(date '+%F %T'))"
  fi
  echo "0" > "$STATE_FILE"
  echo "$(date '+%F %T') [freshness] OK dump=${DUMP_AGE}h jsonl=${JSONL_AGE}h"
fi
