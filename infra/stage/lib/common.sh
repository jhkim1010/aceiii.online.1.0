#!/usr/bin/env bash
# 공통 헬퍼 — 모든 스크립트가 source 한다.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/00-config.env}"

# ── 로깅 ──────────────────────────────────────────────────
_ts() { date '+%Y-%m-%d %H:%M:%S'; }
log()  { printf '\033[0;36m[%s] %s\033[0m\n' "$(_ts)" "$*"; }
ok()   { printf '\033[0;32m[%s] ✓ %s\033[0m\n' "$(_ts)" "$*"; }
warn() { printf '\033[0;33m[%s] ! %s\033[0m\n' "$(_ts)" "$*" >&2; }
die()  { printf '\033[0;31m[%s] ✗ %s\033[0m\n' "$(_ts)" "$*" >&2; exit 1; }

# 실패 지점을 정확히 남긴다 — 로그만 보고 원인을 좁힐 수 있어야 한다.
trap 'die "실패: ${BASH_SOURCE[0]}:${LINENO} → ${BASH_COMMAND}"' ERR

# ── 설정 로드 + 검증 ──────────────────────────────────────
load_config() {
  [[ -f "$CONFIG_FILE" ]] || die "설정 파일이 없습니다: $CONFIG_FILE (00-config.env.example 복사 후 작성)"
  # shellcheck disable=SC1090
  set -a; source "$CONFIG_FILE"; set +a

  local unset_vars=()
  while IFS= read -r line; do
    unset_vars+=("$line")
  done < <(grep -E '=CHANGE_ME' "$CONFIG_FILE" | cut -d= -f1 || true)

  if ((${#unset_vars[@]} > 0)); then
    die "아직 채우지 않은 설정이 있습니다: ${unset_vars[*]}"
  fi
  ok "설정 로드 완료 ($CONFIG_FILE)"
}

# ── 커넥션 예산 검증 (pool 낭비/고갈 방지) ────────────────
# 앱→pgbouncer 클라이언트 상한과 pgbouncer→PG 백엔드 상한의 정합성을 부팅 전에 확인한다.
# 이 검사를 통과하지 못하면 배포 자체를 막는다. 운영에서 pool 고갈로 겪은 사고를
# 스테이지에서 반복하지 않기 위함이다.
# 산식은 앱의 단일 출처(src/common/config/connection-budget.ts)와 **동일해야 한다**:
#   totalClients = replicas × workers × (mainMax + shopMax)
# 여기서만 다르게 계산하면 배포 전 검사와 부팅 로그가 다른 숫자를 말하게 되고,
# 두 값이 갈라지는 순간 둘 다 못 믿게 된다.
verify_connection_budget() {
  local shop_effective clients backend pg_ceiling

  # 공개몰 pool: SHOP_DB_ISOLATED=false 이면 앱이 min(요청값, 5) 로 깎는다
  # (shop-readonly-db.service.ts 의 FALLBACK_POOL_MAX=5).
  shop_effective=$SHOP_DB_POOL_MAX
  (( shop_effective > 5 )) && shop_effective=5

  clients=$(( API_REPLICA_COUNT * API_WORKERS * (SEQUELIZE_POOL_MAX + shop_effective) ))
  backend=$(( PGBOUNCER_POOL_SIZE + PGBOUNCER_SHOP_POOL_SIZE ))

  log "커넥션 예산 검증"
  log "  앱 클라이언트 상한 : ${API_REPLICA_COUNT} node × ${API_WORKERS} worker × (${SEQUELIZE_POOL_MAX} main + ${shop_effective} shop) = ${clients}"
  log "  pgbouncer 백엔드   : ${PGBOUNCER_POOL_SIZE}(app) + ${PGBOUNCER_SHOP_POOL_SIZE}(shop) = ${backend}"
  log "  pgbouncer 클라이언트 상한(max_client_conn) : 200"
  log "  PG max_connections : ${PG_MAX_CONNECTIONS}"

  # ★ 층위 주의: clients 는 앱→pgbouncer, backend 는 pgbouncer→PG 다.
  #   두 값을 같은 자로 재면 정상 구성을 결함으로 오판한다(Phase 75 W0-10).
  #   서버측 포화의 진짜 판정 근거는 SHOW POOLS 의 cl_waiting 이다 — 07-verify.sh 가 본다.
  (( clients <= 200 )) \
    || die "앱 클라이언트 상한(${clients})이 pgbouncer max_client_conn(200)을 넘습니다."

  # 백엔드 총합은 PG 상한의 70% 를 넘지 않아야 한다 (슈퍼유저/유지보수/모니터링 여유).
  pg_ceiling=$(( PG_MAX_CONNECTIONS * 70 / 100 ))
  (( backend <= pg_ceiling )) \
    || die "pgbouncer 백엔드 합(${backend})이 PG max_connections 의 70%(${pg_ceiling})를 초과합니다. PGBOUNCER_POOL_SIZE 를 낮추세요."

  # 클라이언트가 백엔드보다 지나치게 크면 대기가 상시화된다.
  # transaction pooling 이라 어느 정도의 초과는 정상(그게 pgbouncer 의 존재 이유)이지만,
  # 6배를 넘으면 sequelize acquire(15초) 안에 못 받는 요청이 나오기 시작한다.
  if (( clients > backend * 6 )); then
    warn "앱 클라이언트(${clients}) / 백엔드(${backend}) 비율이 6:1 을 넘습니다 — acquire 타임아웃 위험."
    warn "  PGBOUNCER_POOL_SIZE 를 올리거나 API_WORKERS 를 줄이세요."
  fi

  # 반대로 클라이언트가 백엔드보다 작으면 pgbouncer 서버 슬롯이 영원히 놀게 된다.
  # PG 백엔드 프로세스 하나당 메모리를 쓰므로 이건 그냥 낭비다.
  if (( clients < backend )); then
    warn "앱 클라이언트(${clients})가 백엔드 슬롯(${backend})보다 적습니다 — 슬롯 낭비."
    warn "  PGBOUNCER_POOL_SIZE 를 ${clients} 이하로 낮추세요."
  fi

  ok "커넥션 예산 정합"
}

# ── 원격 실행 헬퍼 ────────────────────────────────────────
stage_ssh() {
  ssh -o StrictHostKeyChecking=accept-new -p "${STAGE_SSH_PORT}" \
      "${STAGE_SSH_USER}@${STAGE_HOST}" "$@"
}

stage_scp() {
  scp -o StrictHostKeyChecking=accept-new -P "${STAGE_SSH_PORT}" "$@"
}

prod_ssh() {
  ssh -o StrictHostKeyChecking=accept-new "${PROD_SSH_ALIAS}" "$@"
}

# 원격에 bash 스크립트를 통째로 흘려보낸다 (파일을 남기지 않음).
stage_run_script() {
  local script_path="$1"
  [[ -f "$script_path" ]] || die "스크립트 없음: $script_path"
  stage_ssh "bash -s" < "$script_path"
}

require_cmd() {
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "필요한 명령이 없습니다: $c"
  done
}

confirm() {
  local msg="$1"
  read -r -p "$(printf '\033[0;33m%s [yes/no]: \033[0m' "$msg")" reply
  [[ "$reply" == "yes" ]] || die "사용자가 취소했습니다."
}
