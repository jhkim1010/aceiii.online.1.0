#!/usr/bin/env bash
# scripts/measure-cockpit-pool.sh
# Phase 12 Wave 08: PostgreSQL pool 사용량 측정 스크립트
#
# 목적: 50개 동시 cockpit 호출 시뮬레이션 중 DB 연결 수(peak/avg/min)를 측정
# 실행: bash scripts/measure-cockpit-pool.sh [BASE_URL] [BEARER_TOKEN]
#
# 의존 도구:
#   - curl (필수)
#   - docker (운영서버 pg_stat_activity 조회 시 필요)
#   - hey (부하 테스트, 없으면 curl 루프로 대체)
#
# 사용 예:
#   bash scripts/measure-cockpit-pool.sh https://newapi.coolsistema.com/api "Bearer eyJ..."

set -euo pipefail

BASE_URL="${1:-http://localhost:5002/api}"
AUTH_TOKEN="${2:-}"
SAMPLE_COUNT=30
SAMPLE_INTERVAL=1
CONCURRENCY=50
REQUESTS=200

# 색상 출력
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ──────────────────────────────────────────────────────────────────────────────
# 1. 사전 확인
# ──────────────────────────────────────────────────────────────────────────────
log_info "Cockpit pool 측정 시작"
log_info "BASE_URL   = ${BASE_URL}"
log_info "동시 요청  = ${CONCURRENCY}개 / 총 요청 = ${REQUESTS}개"
log_info "샘플링     = ${SAMPLE_COUNT}회 (${SAMPLE_INTERVAL}초 간격)"

if [ -z "${AUTH_TOKEN}" ]; then
  log_warn "AUTH_TOKEN 미제공 — 인증 없이 요청 (401 예상). 실제 측정 시 토큰 전달 필요."
fi

# ──────────────────────────────────────────────────────────────────────────────
# 2. 기준선: 부하 전 연결 수 측정
# ──────────────────────────────────────────────────────────────────────────────
log_info "기준선 연결 수 측정 중 (Docker pg_stat_activity)..."

get_connection_count() {
  docker exec api_ventago node -e "
    const { Client } = require('pg');
    // [Phase 65 W7] 비밀번호는 컨테이너 환경에서 읽는다 — 이 파일은 커밋된다
    const c = new Client({host:'dbpostgres',user:'coolsistema',password:process.env.DATABASE_PASSWORD,database:'ventago'});
    c.connect()
      .then(() => c.query(\"SELECT count(*)::int AS cnt FROM pg_stat_activity WHERE datname='ventago' AND state IS NOT NULL\"))
      .then(r => { console.log(r.rows[0].cnt); c.end(); })
      .catch(e => { console.log(0); c.end(); });
  " 2>/dev/null || echo 0
}

BASELINE=$(get_connection_count)
log_info "기준선 연결 수: ${BASELINE}"

# ──────────────────────────────────────────────────────────────────────────────
# 3. 부하 테스트 (hey 또는 curl 루프)
# ──────────────────────────────────────────────────────────────────────────────
COCKPIT_URL="${BASE_URL}/reports/vendedor-cockpit?startDate=$(date -v-30d '+%Y-%m-%d' 2>/dev/null || date -d '30 days ago' '+%Y-%m-%d')&endDate=$(date '+%Y-%m-%d')"

log_info "부하 테스트 URL: ${COCKPIT_URL}"

# 샘플 배열 초기화
declare -a SAMPLES=()

# 백그라운드에서 연결 수를 SAMPLE_COUNT 회 샘플링
sample_connections() {
  local results=()

  for i in $(seq 1 "${SAMPLE_COUNT}"); do
    local cnt
    cnt=$(get_connection_count)
    results+=("${cnt}")
    log_info "  샘플 ${i}/${SAMPLE_COUNT}: 연결 수 = ${cnt}"
    sleep "${SAMPLE_INTERVAL}"
  done

  echo "${results[@]}"
}

if command -v hey &>/dev/null; then
  log_info "hey 감지 — 부하 테스트 실행"
  HEADER_ARG=""

  if [ -n "${AUTH_TOKEN}" ]; then
    HEADER_ARG="-H \"Authorization: ${AUTH_TOKEN}\""
  fi

  # 부하 테스트를 백그라운드에서 실행하면서 연결 수 샘플링
  hey -n "${REQUESTS}" -c "${CONCURRENCY}" ${HEADER_ARG} "${COCKPIT_URL}" &>/tmp/hey_output.txt &
  HEY_PID=$!

  log_info "부하 테스트 PID: ${HEY_PID} — 샘플링 시작"
  SAMPLE_OUTPUT=$(sample_connections)
  wait "${HEY_PID}" 2>/dev/null || true

  log_info "hey 결과:"
  cat /tmp/hey_output.txt 2>/dev/null || true
else
  log_warn "hey 미설치 — curl 루프로 대체 (정밀도 낮음)"
  log_warn "설치: go install github.com/rakyll/hey@latest"

  # curl 50개 병렬 실행 (백그라운드)
  for i in $(seq 1 "${CONCURRENCY}"); do
    (
      for j in $(seq 1 4); do
        curl -s -o /dev/null -w "%{http_code}" \
          ${AUTH_TOKEN:+-H "Authorization: ${AUTH_TOKEN}"} \
          "${COCKPIT_URL}" &>/dev/null || true
      done
    ) &
  done

  log_info "curl 루프 실행 중 — 샘플링 시작"
  SAMPLE_OUTPUT=$(sample_connections)
  wait 2>/dev/null || true
fi

# ──────────────────────────────────────────────────────────────────────────────
# 4. 통계 계산
# ──────────────────────────────────────────────────────────────────────────────
log_info "측정 완료 — 통계 계산 중"

read -ra SAMPLES <<< "${SAMPLE_OUTPUT}"

PEAK=0
TOTAL=0
MIN=999999
COUNT=${#SAMPLES[@]}

for val in "${SAMPLES[@]}"; do
  TOTAL=$((TOTAL + val))

  if [ "${val}" -gt "${PEAK}" ]; then
    PEAK="${val}"
  fi

  if [ "${val}" -lt "${MIN}" ]; then
    MIN="${val}"
  fi
done

if [ "${COUNT}" -gt 0 ]; then
  AVG=$((TOTAL / COUNT))
else
  AVG=0
  MIN=0
fi

AFTER=$(get_connection_count)

echo ""
echo "════════════════════════════════════════════"
echo "  Cockpit Pool 사용량 측정 결과"
echo "════════════════════════════════════════════"
echo "  기준선 (부하 전): ${BASELINE} connections"
echo "  Peak             : ${PEAK} connections"
echo "  Avg              : ${AVG} connections"
echo "  Min              : ${MIN} connections"
echo "  부하 후          : ${AFTER} connections"
echo "  샘플 수          : ${COUNT}"
echo "════════════════════════════════════════════"

# ──────────────────────────────────────────────────────────────────────────────
# 5. 기준 비교 (Phase 8 기준: pool_max=10 기본값)
# ──────────────────────────────────────────────────────────────────────────────
PHASE8_BASELINE="${PHASE8_PEAK:-10}"

if [ "${PEAK}" -le "${PHASE8_BASELINE}" ]; then
  echo -e "${GREEN}[PASS]${NC} Peak ${PEAK} ≤ Phase8 기준 ${PHASE8_BASELINE} — pool 회귀 없음"
else
  echo -e "${RED}[FAIL]${NC} Peak ${PEAK} > Phase8 기준 ${PHASE8_BASELINE} — EXPLAIN ANALYZE 검토 필요"
  echo ""
  echo "  권고 조치:"
  echo "  1. 느린 쿼리 확인: SELECT query, mean_exec_time FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 10;"
  echo "  2. 인덱스 검토: EXPLAIN ANALYZE [느린 쿼리]"
  echo "  3. Sequelize pool 설정 확인: database/index.ts — pool.max 값"
fi

echo ""
log_info "측정 완료. 결과를 SUMMARY.md 또는 스프레드시트에 기록하세요."
