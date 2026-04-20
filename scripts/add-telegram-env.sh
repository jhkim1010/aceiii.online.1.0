#!/bin/bash
# ============================================================
# Telegram 알림용 환경변수를 운영서버 api-ventago/.env에 추가
# - 멱등: 이미 있으면 스킵
# - 실행 후 docker compose 재시작 (선택)
#
# 사용법:
#   ./scripts/add-telegram-env.sh                # 기본 토큰/chat_id 사용
#   TOKEN=... CHAT_ID=... ./scripts/add-telegram-env.sh
#   ./scripts/add-telegram-env.sh --no-restart   # 재시작 생략
# ============================================================
set -euo pipefail

# ── 기본값 (필요시 환경변수로 덮어쓰기) ─────────────────────
DEFAULT_TOKEN="8696415712:AAHBfwdpXheTnBRlBvF2Ua7E0Etwk3ER0OA"
DEFAULT_CHAT_ID="8340106887"

TOKEN="${TOKEN:-$DEFAULT_TOKEN}"
CHAT_ID="${CHAT_ID:-$DEFAULT_CHAT_ID}"
RESTART=1

for arg in "$@"; do
  case "$arg" in
    --no-restart) RESTART=0 ;;
    -h|--help)
      sed -n '2,12p' "$0"; exit 0 ;;
  esac
done

# ── api-ventago 경로 자동 탐지 ─────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$ROOT_DIR/api-ventago/.env"
COMPOSE_DIR="$ROOT_DIR/api-ventago"

if [ ! -f "$ENV_FILE" ]; then
  echo "✗ .env 파일을 찾을 수 없음: $ENV_FILE"
  echo "  운영서버의 api-ventago 디렉토리 구조를 확인하세요."
  exit 1
fi

echo "=========================================="
echo "Telegram 환경변수 추가"
echo "대상: $ENV_FILE"
echo "=========================================="

# ── 기존 값 교체 또는 추가 (멱등) ──────────────────────────
upsert_env() {
  local KEY="$1"
  local VALUE="$2"

  if grep -qE "^${KEY}=" "$ENV_FILE"; then
    # 이미 존재 → 동일 값이면 스킵, 다르면 교체
    local CURRENT
    CURRENT=$(grep -E "^${KEY}=" "$ENV_FILE" | head -1 | cut -d= -f2-)
    if [ "$CURRENT" = "$VALUE" ]; then
      echo "  = $KEY 이미 동일 값으로 설정됨 (skip)"
    else
      # BSD/GNU sed 호환 (백업 파일 생성)
      sed -i.bak -E "s|^${KEY}=.*|${KEY}=${VALUE}|" "$ENV_FILE"
      rm -f "${ENV_FILE}.bak"
      echo "  ~ $KEY 값 갱신됨"
    fi
  else
    # 없음 → 파일 끝에 추가
    # 파일 끝에 개행 없으면 먼저 추가
    [ -n "$(tail -c 1 "$ENV_FILE")" ] && echo "" >> "$ENV_FILE"
    echo "${KEY}=${VALUE}" >> "$ENV_FILE"
    echo "  + $KEY 추가됨"
  fi
}

# Telegram 섹션 주석이 없으면 추가
if ! grep -q "^# Telegram" "$ENV_FILE"; then
  [ -n "$(tail -c 1 "$ENV_FILE")" ] && echo "" >> "$ENV_FILE"
  echo "" >> "$ENV_FILE"
  echo "# Telegram 알림 (coolsistema_bot)" >> "$ENV_FILE"
fi

upsert_env "TELEGRAM_BOT_TOKEN" "$TOKEN"
upsert_env "TELEGRAM_CHAT_ID"   "$CHAT_ID"

echo ""
echo "✓ .env 업데이트 완료"

# ── 연결 테스트 (선택) ─────────────────────────────────────
echo ""
echo "--- Telegram 연결 테스트 ---"
if command -v curl >/dev/null 2>&1; then
  RES=$(curl -s --max-time 10 \
    "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    -H "Content-Type: application/json" \
    -d "{\"chat_id\":\"${CHAT_ID}\",\"text\":\"🔧 Ventago API server — env actualizado $(date '+%Y-%m-%d %H:%M:%S')\"}" \
    | head -c 200 || true)
  if echo "$RES" | grep -q '"ok":true'; then
    echo "✓ 테스트 메시지 전송 성공"
  else
    echo "⚠ 테스트 메시지 전송 실패: $RES"
  fi
else
  echo "⚠ curl 없음 — 연결 테스트 스킵"
fi

# ── Docker 컨테이너 재시작 ──────────────────────────────────
if [ "$RESTART" -eq 1 ]; then
  echo ""
  echo "--- api_ventago 컨테이너 재시작 ---"
  cd "$COMPOSE_DIR"
  if command -v docker >/dev/null 2>&1; then
    # docker compose v2 우선, 없으면 docker-compose v1
    if docker compose version >/dev/null 2>&1; then
      docker compose up -d
    elif command -v docker-compose >/dev/null 2>&1; then
      docker-compose up -d
    else
      echo "✗ docker compose 명령을 찾을 수 없음"
      exit 1
    fi
    echo "✓ 재시작 완료"
    echo ""
    echo "로그 확인: docker logs -f api_ventago"
  else
    echo "✗ docker 명령을 찾을 수 없음"
    exit 1
  fi
else
  echo ""
  echo "ℹ 재시작 생략됨 (--no-restart). 수동 재시작:"
  echo "  cd api-ventago && docker compose up -d"
fi

echo ""
echo "=========================================="
echo "완료"
echo "=========================================="
