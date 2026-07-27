#!/bin/bash
# ============================================================================
# Phase 63 Wave E 준비 — 스테이징에 더미 매장 N개 시드 + 매장 목록 파일 생성
#
# 목적: "300매장 × 10터미널" 분산 용량을 측정하려면 실제로 판매 가능한 매장이
#   300개 있어야 한다. A-2b(단일 매장) 에서 드러난 재고 행 락 경합이 분산
#   환경에서 사라지는지 확인하는 것이 이 시나리오의 핵심이다.
#
# 안전: ventago_staging 전용. 시드 SQL 자체가 DB 이름을 검사하고 다르면 중단한다.
#   운영 DB(ventago)에는 어떤 경우에도 실행되지 않는다.
#
# 사용:
#   ./prepare-300-stores.sh              # 300매장 × 유저10 × 상품20
#   N_STORES=50 ./prepare-300-stores.sh  # 소규모 리허설
#
# 결과물:
#   stores.txt  — burst-multistore.js 의 STORES_FILE 로 넘길 매장 id 목록
# ============================================================================
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
DB="${DB:-ventago_staging}"
PGPORT="${PGPORT:-5434}"
N_STORES="${N_STORES:-300}"
N_USERS="${N_USERS:-10}"
N_PRODUCTS="${N_PRODUCTS:-20}"
OUT="${OUT:-$DIR/stores.txt}"

PSQL=(sudo -u postgres psql -p "$PGPORT" -d "$DB" -v ON_ERROR_STOP=1)

if [ "$DB" = "ventago" ]; then
  echo "★ 중단: 운영 DB(ventago) 에는 실행하지 않는다." >&2
  exit 1
fi

# 시드는 DUMMY-01.. 이름을 새로 만들 뿐 기존 것을 재사용하지 않는다.
# 이미 더미가 있는 상태에서 그냥 돌리면 이름이 겹치는 매장이 쌓인다 →
# 기본적으로 기존 더미를 먼저 지우고 원하는 개수로 다시 만든다(RESET=false 로 생략 가능).
if [ "${RESET:-true}" = "true" ]; then
  EXISTING=$("${PSQL[@]}" -tAc "SELECT count(*) FROM stores WHERE name LIKE 'DUMMY-%'")
  if [ "$EXISTING" -gt 0 ]; then
    echo "[0/3] 기존 더미 매장 ${EXISTING}개 정리 (판매 데이터 포함)"
    "${PSQL[@]}" -f "$DIR/cleanup-dummy-stores.sql" | tail -3
  fi
fi

echo "[1/3] 더미 매장 시드 — n_stores=$N_STORES users=$N_USERS products=$N_PRODUCTS"
echo "      (매장 수에 비례해 수 분 걸릴 수 있다)"
time "${PSQL[@]}" \
  -v n_stores="$N_STORES" \
  -v n_users="$N_USERS" \
  -v n_products="$N_PRODUCTS" \
  -f "$DIR/seed-dummy-stores.sql" | tail -20

echo
echo "[2/3] 판매 가능한 매장 목록 추출 → $OUT"
# 조건: 삭제되지 않고 활성 + 상품/고객/테스트유저가 모두 있는 매장만.
# 하나라도 없으면 그 매장 VU 는 부팅 실패로 조용히 빠지므로 여기서 걸러낸다.
"${PSQL[@]}" -tAc "
  SELECT string_agg(id::text, ',' ORDER BY id)
  FROM stores s
  WHERE s.deleted_at IS NULL
    AND COALESCE(s.is_active, FALSE)
    AND EXISTS (SELECT 1 FROM products  p WHERE p.store_id = s.id)
    AND EXISTS (SELECT 1 FROM clients   c WHERE c.store_id = s.id)
    AND EXISTS (SELECT 1 FROM users     u WHERE u.store_id = s.id
                                          AND u.username LIKE 'lt\\_s%')
" | tr -d '[:space:]' > "$OUT"

COUNT=$(tr ',' '\n' < "$OUT" | grep -c . || true)
echo "      판매 가능 매장: ${COUNT}개"

echo
echo "[3/3] 사전 점검"
"${PSQL[@]}" -c "
  SELECT count(*) FILTER (WHERE name LIKE 'DUMMY-%') AS dummy_stores,
         (SELECT count(*) FROM users WHERE username LIKE 'lt\\_s%')            AS lt_users,
         (SELECT count(*) FROM terminal_devices)                              AS devices,
         (SELECT count(*) FROM branch_ip_registries)                          AS ip_regs
  FROM stores;"

cat <<EOF

준비 완료. 실행 예 (목표: 3,000터미널 × 1건/40초 ≈ 75 판매/s):

  cd $DIR
  k6 run -e BASE_URL=http://127.0.0.1:5012/api \\
         -e STORES_FILE=$OUT \\
         -e RATE=75 -e DUR=10m -e PER_STORE=10 \\
         burst-multistore.js

  # 심야 전체 리허설(Wave E 합격선 검증)은 RATE 를 단계적으로: 25 → 50 → 75 → 100
  # watchdog 동반 필수:  WD_MAX_LOAD=13 ./watchdog.sh &

사후 정합성 검증:
  sudo -u postgres psql -p $PGPORT -d $DB -f verify-burst.sql
EOF
