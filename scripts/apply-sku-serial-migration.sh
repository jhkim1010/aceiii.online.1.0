#!/usr/bin/env bash
# =============================================================================
# SKU serial 컬럼화 마이그레이션 적용 스크립트
# =============================================================================
# 대상 2개 SQL (순서 중요 — 스키마 먼저, backfill 나중):
#   1) api-ventago/migrations/2026-07-16-sku-serials.sql       (sku_serials 테이블 + products.serial + products.str_prefix)
#   2) api-ventago/migrations/2026-07-16-sku-serial-backfill.sql (str_prefix=앞2자리(25/26) + serial 추출 + 카운터 시딩)
#
# 사용법:
#   ./scripts/apply-sku-serial-migration.sh local dry-run   # 로컬 5432, 검증만(ROLLBACK)
#   ./scripts/apply-sku-serial-migration.sh local apply     # 로컬 5432, 실제 적용
#   ./scripts/apply-sku-serial-migration.sh prod  dry-run   # 운영 5434(SSH), 검증만(ROLLBACK)
#   ./scripts/apply-sku-serial-migration.sh prod  apply     # 운영 5434(SSH), 실제 적용
#
# 권장 순서: local dry-run → local apply → prod dry-run → prod apply
#
# 안전장치:
#   - ON_ERROR_STOP=1: 첫 에러에서 중단
#   - dry-run: 전체를 BEGIN..ROLLBACK 으로 감싸 아무 영구 변경 없이 fill rate 만 확인
#   - apply: --single-transaction, 실패 시 전체 롤백
#   - apply 전 y/N 확인 프롬프트
#   - 신규 테이블 owner→coolsistema 는 SQL 내 DO 블록이 처리(role 없으면 skip)
# =============================================================================
set -euo pipefail

# repo 루트로 이동 (스크립트 위치 기준)
cd "$(dirname "${BASH_SOURCE[0]}")/.."

MIG_DIR="api-ventago/migrations"
SCHEMA="$MIG_DIR/2026-07-16-sku-serials.sql"
BACKFILL="$MIG_DIR/2026-07-16-sku-serial-backfill.sql"

TARGET="${1:-}"
MODE="${2:-}"

DB="ventago"
SSH_HOST="jhkim-server"   # ~/.ssh/config alias (운영 srv803182)

# ── 인자 검증 ────────────────────────────────────────────────────────────
if [[ "$TARGET" != "local" && "$TARGET" != "prod" ]] || [[ "$MODE" != "dry-run" && "$MODE" != "apply" ]]; then
  echo "사용법: $0 <local|prod> <dry-run|apply>" >&2
  echo "예:    $0 local dry-run" >&2
  exit 1
fi

# ── SQL 파일 존재 확인 (feat/sku-serial 브랜치여야 존재) ──────────────────
for f in "$SCHEMA" "$BACKFILL"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: SQL 파일 없음: $f" >&2
    echo "       api-ventago 서브모듈이 feat/sku-serial 브랜치인지 확인하세요:" >&2
    echo "       (cd api-ventago && git checkout feat/sku-serial)" >&2
    exit 1
  fi
done

# ── 검증 쿼리 (적용 후 fill rate 확인) ────────────────────────────────────
VERIFY_SQL="
SELECT count(*) FILTER (WHERE str_prefix IS NOT NULL) AS prefix_filled,
       count(*) FILTER (WHERE serial IS NOT NULL)     AS serial_filled,
       count(*) AS total_parents,
       round(100.0 * count(*) FILTER (WHERE str_prefix IS NOT NULL) / nullif(count(*),0), 1) AS prefix_pct,
       round(100.0 * count(*) FILTER (WHERE serial IS NOT NULL) / nullif(count(*),0), 1) AS serial_pct
  FROM products WHERE is_parent = true;
SELECT count(*) AS counter_groups FROM sku_serials;
"

# ── SQL 본문 조립 ─────────────────────────────────────────────────────────
# dry-run: BEGIN + 스키마 + backfill + 검증 + ROLLBACK (영구 변경 0)
# apply : psql --single-transaction 이 전체를 한 트랜잭션으로 감쌈
# 파일은 psql 의 \i 대신 로컬에서 cat 해 stdin 으로 넘긴다 — SSH 원격 psql 은
# \i 의 상대경로를 운영서버에서 찾아 실패하기 때문(파일은 로컬에만 존재).
build_payload() {
  if [[ "$MODE" == "dry-run" ]]; then
    echo "BEGIN;"
    cat "$SCHEMA"
    cat "$BACKFILL"
    echo "$VERIFY_SQL"
    echo "ROLLBACK;"
  else
    cat "$SCHEMA"
    cat "$BACKFILL"
  fi
}

# ── 확인 프롬프트 (apply 만) ──────────────────────────────────────────────
if [[ "$MODE" == "apply" ]]; then
  echo "⚠  실제 적용: $TARGET ($([ "$TARGET" == local ] && echo '5432' || echo '5434'))"
  echo "   1) $SCHEMA"
  echo "   2) $BACKFILL"
  read -r -p "계속하시겠습니까? (y/N) " ans
  if [[ "$ans" != "y" && "$ans" != "Y" ]]; then
    echo "취소됨."
    exit 0
  fi
fi

echo "▶ $TARGET / $MODE 실행 중..."

# ── 실행 ──────────────────────────────────────────────────────────────────
if [[ "$TARGET" == "local" ]]; then
  # 로컬 Mac PG18 5432
  if [[ "$MODE" == "dry-run" ]]; then
    build_payload | psql -p 5432 -d "$DB" -v ON_ERROR_STOP=1
  else
    build_payload | psql -p 5432 -d "$DB" -v ON_ERROR_STOP=1 --single-transaction
    echo "── 검증 ──"
    psql -p 5432 -d "$DB" -v ON_ERROR_STOP=1 -c "$VERIFY_SQL"
  fi
else
  # 운영 srv803182 PG18 5434 (SSH → sudo -u postgres)
  if [[ "$MODE" == "dry-run" ]]; then
    build_payload | ssh "$SSH_HOST" "sudo -u postgres psql -p 5434 -d $DB -v ON_ERROR_STOP=1"
  else
    build_payload | ssh "$SSH_HOST" "sudo -u postgres psql -p 5434 -d $DB -v ON_ERROR_STOP=1 --single-transaction"
    echo "── 검증 ──"
    ssh "$SSH_HOST" "sudo -u postgres psql -p 5434 -d $DB -v ON_ERROR_STOP=1 -c \"$VERIFY_SQL\""
  fi
fi

echo "✔ $TARGET / $MODE 완료"
if [[ "$MODE" == "dry-run" ]]; then
  echo "  (ROLLBACK 됨 — 영구 변경 없음. filled/total_parents 비율 확인 후 apply)"
fi
