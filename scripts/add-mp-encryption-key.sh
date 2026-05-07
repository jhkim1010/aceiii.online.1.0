#!/bin/bash
# ============================================================
# Phase 29 — 운영서버 api-ventago/.env 에 MP_TOKEN_ENCRYPTION_KEY 추가
#
# 배경: Phase 29 (mercadopago) 코드가 부팅 시 MpTokenCryptoService 가
#       process.env.MP_TOKEN_ENCRYPTION_KEY (32 bytes hex) 를 요구.
#       값이 없으면 throw → PM2 재기동 무한 루프 → API 다운.
#
# 동작:
#   1. SSH 로 운영서버(jhkim-server) 접속
#   2. .env 백업 (.env.bak.YYYYMMDD-HHMMSS)
#   3. MP_TOKEN_ENCRYPTION_KEY 존재 여부 확인 (멱등)
#   4. 없으면 append, 있으면 변경 거부 (이미 토큰 암호화에 사용 중일 수 있음 — 절대 변경 금지)
#   5. docker compose restart api_ventago
#   6. 부팅 로그 확인 (Nest application successfully started)
#
# 사용법 (로컬 PC 에서 SSH 통해 실행):
#   ./scripts/add-mp-encryption-key.sh                    # 신규 키 생성 + 적용
#   MP_KEY=4402ea7aff... ./scripts/add-mp-encryption-key.sh   # 사전 생성 키 사용
#   ./scripts/add-mp-encryption-key.sh --dry-run          # 변경 없이 흐름 확인
#   ./scripts/add-mp-encryption-key.sh --no-restart       # .env 만 갱신
#
# 사용법 (운영서버 srv803182 에서 직접 실행):
#   # 1. 스크립트 서버로 복사
#   scp scripts/add-mp-encryption-key.sh jhkim-server:~/
#   # 2. 서버 SSH 후 RUN_LOCAL=1 로 실행 (SSH 래핑 없이 직접 명령 수행)
#   ssh jhkim-server
#   RUN_LOCAL=1 ./add-mp-encryption-key.sh --dry-run
#   RUN_LOCAL=1 ./add-mp-encryption-key.sh
#
#   # 또는 한 줄로 (sudo 비밀번호 입력 필요할 수 있음):
#   ssh jhkim-server 'bash -s' < scripts/add-mp-encryption-key.sh   # ← 권장 X (RUN_LOCAL 미지정)
# ============================================================
set -euo pipefail

# ── 설정 ─────────────────────────────────────────────────
SSH_HOST="jhkim-server"
ENV_PATH="/var/lib/jenkins/workspace/api-new-coolsistema/.env"
COMPOSE_DIR="/var/lib/jenkins/workspace/api-new-coolsistema"
CONTAINER_NAME="api_ventago"

DRY_RUN=0
RESTART=1
RUN_LOCAL="${RUN_LOCAL:-0}"   # 1 = 운영서버 위에서 직접 실행 (SSH 래핑 안 함)

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --no-restart) RESTART=0 ;;
    -h|--help)
      sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "✗ 알 수 없는 옵션: $arg"; exit 1 ;;
  esac
done

# ── 명령 wrapper ─────────────────────────────────────────
# RUN_LOCAL=1 → 직접 실행 (서버 위), 0 → ssh "$SSH_HOST" 경유 (로컬 PC)
run_remote() {
  if [ "$RUN_LOCAL" -eq 1 ]; then
    bash -c "$1"
  else
    ssh "$SSH_HOST" "$1"
  fi
}

# stdin → tee 같은 입력 전달용 (heredoc 등)
run_remote_stdin() {
  if [ "$RUN_LOCAL" -eq 1 ]; then
    bash -c "$1"
  else
    ssh "$SSH_HOST" "$1"
  fi
}

if [ "$RUN_LOCAL" -eq 1 ]; then
  echo "(모드: RUN_LOCAL — 서버 직접 실행, sudo 호출됨)"
else
  echo "(모드: SSH — 로컬 → $SSH_HOST 원격 실행)"
fi
echo ""

# ── 1. 키 준비 ────────────────────────────────────────────
if [ -z "${MP_KEY:-}" ]; then
  echo "→ MP_TOKEN_ENCRYPTION_KEY 자동 생성 (openssl rand -hex 32)"
  MP_KEY=$(openssl rand -hex 32)
fi

# 검증: 64 hex chars
if [ ${#MP_KEY} -ne 64 ] || ! [[ "$MP_KEY" =~ ^[0-9a-fA-F]{64}$ ]]; then
  echo "✗ MP_KEY 가 64 hex chars 가 아님 (length=${#MP_KEY})"
  exit 1
fi

echo "✓ 키 검증 통과: ${MP_KEY:0:8}...${MP_KEY: -8} (실제 키는 password vault 에 백업하세요)"
echo ""

# ── 2. 운영서버 .env 상태 확인 ────────────────────────────
echo "→ 운영서버 .env 상태 확인 ($ENV_PATH)"

EXISTING=$(run_remote "sudo grep -E '^MP_TOKEN_ENCRYPTION_KEY=' '$ENV_PATH' || true")

if [ -n "$EXISTING" ]; then
  echo "⚠️  MP_TOKEN_ENCRYPTION_KEY 가 이미 설정되어 있습니다:"
  echo "    $EXISTING"
  echo ""
  echo "✗ 안전상 변경 거부 — 이미 운영 토큰 암호화에 사용 중일 수 있습니다."
  echo "  변경 시 mp_accounts 테이블의 저장된 토큰을 복호화 불가."
  echo ""
  echo "현재 키가 정상이면 이 스크립트 실행은 불필요합니다."
  echo "키 분실/회전이 필요하면 별도 마이그레이션 절차 (mp_accounts 재인증) 필요."
  exit 1
fi

echo "✓ MP_TOKEN_ENCRYPTION_KEY 미설정 — 신규 추가 가능"
echo ""

if [ "$DRY_RUN" -eq 1 ]; then
  echo "── DRY RUN ─────────────────────────────────────────"
  echo "  추가 예정:"
  echo "    $ENV_PATH 끝에 한 줄 추가"
  echo "    MP_TOKEN_ENCRYPTION_KEY=${MP_KEY:0:8}...${MP_KEY: -8}"
  echo "    (백업: $ENV_PATH.bak.YYYYMMDD-HHMMSS)"
  echo ""
  if [ "$RESTART" -eq 1 ]; then
    echo "  실행 예정: cd $COMPOSE_DIR && sudo docker compose up -d (env_file 재로드 — 컨테이너 재생성)"
  fi
  echo ""
  echo "실제 적용하려면 --dry-run 빼고 다시 실행"
  exit 0
fi

# ── 3. 백업 + .env 갱신 ───────────────────────────────────
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
BACKUP_PATH="${ENV_PATH}.bak.${TIMESTAMP}"

echo "→ .env 백업: $BACKUP_PATH"
run_remote "sudo cp '$ENV_PATH' '$BACKUP_PATH'"
echo "✓ 백업 완료"

echo "→ MP_TOKEN_ENCRYPTION_KEY append"
# heredoc 으로 안전하게 전달 (특수문자 escape 불필요)
APPEND_CONTENT=$(cat <<EOF

# Phase 29 — Mercadopago 토큰 암호화 마스터 키 ($(date '+%Y-%m-%d') 추가)
# CRITICAL: 이 키는 mp_accounts 의 access_token/refresh_token 복호화에 사용됨.
# 절대 변경/삭제 금지 — 변경 시 모든 매장 MP 재인증 필요.
# 백업: password vault (운영자 책임)
MP_TOKEN_ENCRYPTION_KEY=$MP_KEY
EOF
)
if [ "$RUN_LOCAL" -eq 1 ]; then
  printf '%s\n' "$APPEND_CONTENT" | sudo tee -a "$ENV_PATH" > /dev/null
else
  printf '%s\n' "$APPEND_CONTENT" | ssh "$SSH_HOST" "sudo tee -a '$ENV_PATH' > /dev/null"
fi

# 검증
ADDED=$(run_remote "sudo grep -c '^MP_TOKEN_ENCRYPTION_KEY=' '$ENV_PATH'")
if [ "$ADDED" -ne 1 ]; then
  echo "✗ append 검증 실패 (count=$ADDED) — 백업 복원 필요시: sudo cp $BACKUP_PATH $ENV_PATH"
  exit 1
fi
echo "✓ .env 갱신 완료"
echo ""

# ── 4. 컨테이너 재시작 ────────────────────────────────────
if [ "$RESTART" -eq 0 ]; then
  echo "── 재시작 생략 (--no-restart) ──"
  echo "  다음 Jenkins deploy 또는 수동 restart 시 반영됩니다."
  echo "  수동 재시작: ssh $SSH_HOST 'cd $COMPOSE_DIR && sudo docker compose up -d'"
  exit 0
fi

# 주의: docker compose restart 는 env_file 을 다시 안 읽음 — 반드시 up -d (재생성) 사용.
echo "→ docker compose up -d (env_file 재로드 — 컨테이너 재생성)"
run_remote "cd '$COMPOSE_DIR' && sudo docker compose up -d" 2>&1 | tail -5
echo ""

# ── 5. 부팅 로그 확인 ─────────────────────────────────────
echo "→ 부팅 로그 확인 (최대 30초 대기)"
SUCCESS_PATTERN="Nest application successfully started"
FAIL_PATTERN="Error:"

for i in $(seq 1 15); do
  LOG=$(run_remote "sudo docker logs --tail 100 $CONTAINER_NAME 2>&1" | tail -50)
  if echo "$LOG" | grep -q "$SUCCESS_PATTERN"; then
    echo ""
    echo "✓ 서버 정상 부팅 완료"
    echo "$LOG" | grep -E "$SUCCESS_PATTERN|listen|Bootstrap" | tail -5
    exit 0
  fi
  if echo "$LOG" | grep -qE "Error: MP_|MODULE_NOT_FOUND|UnhandledPromiseRejection"; then
    echo ""
    echo "✗ 부팅 중 에러 감지 — 마지막 로그:"
    echo "$LOG" | tail -20
    echo ""
    if [ "$RUN_LOCAL" -eq 1 ]; then
      echo "백업 복원: sudo cp $BACKUP_PATH $ENV_PATH && cd $COMPOSE_DIR && sudo docker compose up -d"
    else
      echo "백업 복원: ssh $SSH_HOST 'sudo cp $BACKUP_PATH $ENV_PATH && cd $COMPOSE_DIR && sudo docker compose up -d'"
    fi
    exit 1
  fi
  sleep 2
done

echo ""
echo "⚠️  30초 안에 부팅 완료 신호 없음 — 수동 확인 필요"
if [ "$RUN_LOCAL" -eq 1 ]; then
  echo "  sudo docker logs --tail 50 $CONTAINER_NAME"
else
  echo "  ssh $SSH_HOST 'sudo docker logs --tail 50 $CONTAINER_NAME'"
fi
exit 1
