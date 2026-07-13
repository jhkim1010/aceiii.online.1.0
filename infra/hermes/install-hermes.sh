#!/usr/bin/env bash
# =============================================================================
# Hermes Agent 격리 설치 스크립트 — 운영 서버 srv803182 (Ubuntu 24.04)
#
# 목적: 12개 운영 컨테이너/PG18/pgbouncer 에 영향 0으로 Hermes 를 상시 설치
# 실행: sudo bash install-hermes.sh
#   - root 로 실행하되, 앱 설치 단계는 hermes 유저로 강등하여 수행
#
# 멱등(idempotent): 재실행해도 안전 (이미 있는 항목은 skip)
# =============================================================================
set -euo pipefail

HERMES_USER="hermes"
HERMES_HOME="/home/${HERMES_USER}"
NODE_MAJOR="20"          # Node LTS
PYTHON_VER="3.11"        # Hermes 권장 버전 (uv 로 격리 설치)

log()  { printf '\033[1;36m[hermes-install]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "root 로 실행해야 합니다 (sudo bash install-hermes.sh)"

# --- TASK-1: 전용 non-root 유저 생성 (docker/sudo 그룹 절대 미포함) ----------
if ! id "$HERMES_USER" &>/dev/null; then
  useradd --create-home --shell /bin/bash "$HERMES_USER"
  log "유저 ${HERMES_USER} 생성 완료 (docker/sudo 미포함 → 운영 격리)"
else
  log "유저 ${HERMES_USER} 이미 존재 — skip"
fi
# 안전장치: 혹시라도 docker/sudo 그룹에 있으면 즉시 중단
if id -nG "$HERMES_USER" | tr ' ' '\n' | grep -qE '^(docker|sudo|root)$'; then
  fail "${HERMES_USER} 가 docker/sudo/root 그룹에 속해 있습니다 — 격리 위반, 중단"
fi

# --- TASK-2: 시스템 의존성 (ripgrep, ffmpeg) — 서비스 아님, 무해 -------------
log "시스템 패키지 설치: ripgrep, ffmpeg, git, curl"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y ripgrep ffmpeg git curl ca-certificates

# --- TASK-3 & 4: hermes 유저 하에서 Node(nvm) + uv + Python3.11 + Hermes ------
log "hermes 유저 컨텍스트에서 런타임 + Hermes 설치 시작"
sudo -iu "$HERMES_USER" env NODE_MAJOR="$NODE_MAJOR" PYTHON_VER="$PYTHON_VER" bash <<'EOSU'
set -euo pipefail
cyan() { printf '\033[1;36m[hermes-user]\033[0m %s\n' "$*"; }

# nvm (Node 버전 격리) — 시스템 node 오염 없음
if [ ! -s "$HOME/.nvm/nvm.sh" ]; then
  cyan "nvm 설치"
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
fi
export NVM_DIR="$HOME/.nvm"
# shellcheck disable=SC1091
. "$NVM_DIR/nvm.sh"
nvm install "$NODE_MAJOR"
nvm alias default "$NODE_MAJOR"
cyan "node $(node -v) / npm $(npm -v)"

# uv (Python 패키지/버전 매니저) — ~/.local 격리
if ! command -v uv &>/dev/null && [ ! -x "$HOME/.local/bin/uv" ]; then
  cyan "uv 설치"
  curl -fsSL https://astral.sh/uv/install.sh | sh
fi
export PATH="$HOME/.local/bin:$PATH"

# Hermes 권장 Python 3.11 을 uv 로 격리 설치 (시스템 3.12 유지)
cyan "Python ${PYTHON_VER} (uv 격리) 설치"
uv python install "${PYTHON_VER}" || cyan "python ${PYTHON_VER} 설치 스킵/기존"

# Hermes Agent 공식 설치
cyan "Hermes Agent 설치 (공식 install.sh)"
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash

# 설치된 hermes 바이너리 경로 확인
HERMES_BIN="$(command -v hermes || echo "$HOME/.local/bin/hermes")"
cyan "hermes 바이너리: ${HERMES_BIN}"
EOSU

log "런타임 + Hermes 설치 완료"
log "다음 단계: (1) ${HERMES_HOME}/.hermes/gateway.env 에 LLM 자격증명 설정(600)"
log "           (2) hermes-gateway.service 등록 → systemctl enable --now hermes-gateway"
log "설치 스크립트 종료. 상태변경은 여기까지, 서비스 기동은 별도 확인 후 진행."
