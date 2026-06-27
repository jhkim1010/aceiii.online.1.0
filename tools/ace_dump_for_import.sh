#!/usr/bin/env bash
# =============================================================================
# ace_dump_for_import.sh — ACE 레거시 DB에서 import에 필요한 테이블만 백업
# =============================================================================
#
# VentaGO 의 "Importar Legacy" 화면(/configuracion/importar-legacy)은 ACE
# pg_dump SQL 파일을 받아 상품·가격·고객·판매원을 import 합니다. 전체 DB 를
# 덤프하면 25MB 업로드 상한을 초과하는 경우가 많아, import 가 실제로 읽는
# 9개 테이블만 plain 포맷(-Fp)으로 덤프합니다.
#
# 덤프 대상 (import 가 읽는 유일한 테이블):
#   tipos / color / temporadas / origenes / empresas  (참조 테이블)
#   todocodigos (códigos madres) / codigos (códigos hijitos)
#   vendedores / clientes
#
# 사용법 / Uso:
#   ./ace_dump_for_import.sh                         # 기본값으로 실행
#   ACE_DB=ace_db ACE_USER=postgres ./ace_dump_for_import.sh
#   ./ace_dump_for_import.sh -d ace_db -U postgres -h localhost -o salida.sql
#
# 결과 파일을 "Importar Legacy" 화면에 업로드하면 됩니다.
# =============================================================================

set -euo pipefail

# ── 기본 접속 정보 (환경변수로 덮어쓰기 가능) ──────────────────────────────
DB_NAME="${ACE_DB:-ace_db}"
DB_USER="${ACE_USER:-postgres}"
DB_HOST="${ACE_HOST:-localhost}"
DB_PORT="${ACE_PORT:-5432}"
SCHEMA="${ACE_SCHEMA:-public}"
OUTPUT="ace_import_$(date +%Y%m%d_%H%M%S).sql"

# ── 인자 파싱 ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--db)     DB_NAME="$2"; shift 2 ;;
    -U|--user)   DB_USER="$2"; shift 2 ;;
    -h|--host)   DB_HOST="$2"; shift 2 ;;
    -p|--port)   DB_PORT="$2"; shift 2 ;;
    -s|--schema) SCHEMA="$2";  shift 2 ;;
    -o|--output) OUTPUT="$2";  shift 2 ;;
    --help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *)
      echo "인자 오류: 알 수 없는 옵션 '$1' (--help 로 사용법 확인)" >&2
      exit 1 ;;
  esac
done

# ── import 가 읽는 테이블 (이 목록만 덤프) ──────────────────────────────────
TABLES=(
  tipos
  color
  temporadas
  origenes
  empresas
  todocodigos
  codigos
  vendedores
  clientes
)

# ── -t 옵션 조립 (schema.table) ────────────────────────────────────────────
TABLE_ARGS=()
for t in "${TABLES[@]}"; do
  TABLE_ARGS+=( -t "${SCHEMA}.${t}" )
done

echo "ACE → import 백업 시작"
echo "  DB:     ${DB_NAME} @ ${DB_HOST}:${DB_PORT} (user=${DB_USER})"
echo "  스키마: ${SCHEMA}"
echo "  테이블: ${TABLES[*]}"
echo "  출력:   ${OUTPUT}"
echo ""

# ── 덤프 실행 ──────────────────────────────────────────────────────────────
# -Fp : plain SQL (import 화면이 받는 유일한 포맷)
# --no-owner / --no-privileges : 대상 PG 권한 차이로 인한 노이즈 제거
# 존재하지 않는 테이블이 있으면 pg_dump 가 에러로 중단됨 → set -e 로 즉시 종료
if ! pg_dump \
    -h "${DB_HOST}" \
    -p "${DB_PORT}" \
    -U "${DB_USER}" \
    -d "${DB_NAME}" \
    -Fp \
    --no-owner \
    --no-privileges \
    "${TABLE_ARGS[@]}" \
    -f "${OUTPUT}"; then
  echo "백업 실패: pg_dump 가 오류를 반환했습니다." >&2
  echo "  - 비밀번호 입력 프롬프트가 필요하면 PGPASSWORD 환경변수를 설정하세요." >&2
  echo "  - 테이블명이 다르면 ACE_SCHEMA / 테이블 목록을 확인하세요." >&2
  exit 1
fi

# ── 결과 요약 ──────────────────────────────────────────────────────────────
SIZE_BYTES=$(wc -c < "${OUTPUT}" | tr -d ' ')
SIZE_MB=$(awk "BEGIN { printf \"%.2f\", ${SIZE_BYTES}/1024/1024 }")

echo ""
echo "백업 완료: ${OUTPUT} (${SIZE_MB} MB)"

# 25MB 업로드 상한 경고
LIMIT_BYTES=$((25 * 1024 * 1024))
if [[ "${SIZE_BYTES}" -gt "${LIMIT_BYTES}" ]]; then
  echo ""
  echo "⚠ 경고: 파일이 25MB 업로드 상한(${LIMIT_BYTES} B)을 초과했습니다."
  echo "  clientes 가 매우 큰 경우, 불필요한 행 제외 후 다시 시도하세요."
else
  echo "업로드 상한(25MB) 이내 — Importar Legacy 화면에 그대로 업로드하세요."
fi
