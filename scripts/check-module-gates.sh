#!/usr/bin/env bash
# ============================================================================
# Phase 65 TASK-E1 — 모듈 게이트 활성화 전 회귀 검증
#
# 배경: withAccess.tsx 의 arguments[0] 버그를 고치면 82개 파일의 allowedModules
# 게이트가 "처음으로" 켜진다. 프론트가 참조하는 module slug 가 DB modules 에
# 없으면 그 페이지는 아무도 못 들어간다 → 배포 즉시 화면 증발.
#
# 이 스크립트는 두 가지를 대조한다.
#   1) 프론트가 쓰는 module slug 중 DB에 없는 것  → 게이트 켜면 전원 차단
#   2) 역할별로 접근 가능한 module slug 집합       → 누가 무엇을 잃는지 사전 확인
#
# 사용법:
#   ./scripts/check-module-gates.sh              # 로컬 5432
#   ./scripts/check-module-gates.sh prod         # 운영 5434 (SSH 경유)
#
# pool 안전: 조회 전용 SELECT 만 수행.
# ============================================================================
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/ventago-app"
TARGET="${1:-local}"

run_sql() {
  if [ "$TARGET" = "prod" ]; then
    ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -P pager=off -A -F'|' -t -c \"$1\""
  else
    psql -p 5432 -d ventago -P pager=off -A -F'|' -t -c "$1"
  fi
}

echo "== 대상: $TARGET =="
echo

# ---------------------------------------------------------------------------
# 1) 프론트가 참조하는 module slug 수집
# ---------------------------------------------------------------------------
TMP_FRONT="$(mktemp)"
grep -rhoE 'allowedModules=\{\[[^]]*\]' "$APP_DIR/src" --include=*.tsx 2>/dev/null \
  | sed 's/allowedModules={\[//; s/\]//' \
  | tr -d "\"' " | tr ',' '\n' | grep -v '^$' | sort -u > "$TMP_FRONT"

echo "프론트 참조 module slug: $(wc -l < "$TMP_FRONT")개"

# ---------------------------------------------------------------------------
# 2) DB 의 module slug 수집
# ---------------------------------------------------------------------------
TMP_DB="$(mktemp)"
run_sql "SELECT slug FROM modules ORDER BY slug;" | tr -d '\r' | grep -v '^$' | sort -u > "$TMP_DB"
echo "DB module slug: $(wc -l < "$TMP_DB")개"
echo

# ---------------------------------------------------------------------------
# 3) 위험 1 — DB 에 없는 slug (게이트 켜면 해당 페이지 전원 차단)
# ---------------------------------------------------------------------------
echo "--- [위험] 프론트가 쓰지만 DB modules 에 없는 slug ---"
MISSING="$(comm -23 "$TMP_FRONT" "$TMP_DB" || true)"
if [ -z "$MISSING" ]; then
  echo "없음 — 게이트를 켜도 안전합니다."
else
  echo "$MISSING" | sed 's/^/  ✗ /'
  echo
  echo "  → 이 slug 를 참조하는 페이지는 게이트 활성화 시 접근 불가가 됩니다."
  echo "     modules 시드를 추가하거나 프론트 slug 를 실제 값으로 고치세요."
fi
echo

# ---------------------------------------------------------------------------
# 4) 역할별 접근 가능 module 수 — 게이트 활성화 후 실제로 보게 될 범위
#    (structure 계산과 동일 규칙: 허용 function 이 1개 이상인 모듈만)
# ---------------------------------------------------------------------------
echo "--- 역할별 접근 가능 module 수 (게이트 활성화 후 예상) ---"
run_sql "
SELECT s.name || ' | ' || r.slug || ' | ' || count(DISTINCT m.id) || ' módulos'
FROM roles r
JOIN stores s ON s.id = r.store_id
LEFT JOIN role_functions rf ON rf.role_id = r.id
LEFT JOIN functions f ON f.id = rf.function_id
LEFT JOIN modules m ON m.id = f.module_id
WHERE r.store_id IS NOT NULL
GROUP BY s.name, r.slug
ORDER BY 1;" | sed 's/^/  /'
echo

# ---------------------------------------------------------------------------
# 5) 위험 2 — 어떤 역할도 접근할 수 없는 module (고아 모듈)
# ---------------------------------------------------------------------------
echo "--- [점검] 어떤 매장 역할도 권한이 없는 module ---"
ORPHAN="$(run_sql "
SELECT m.slug
FROM modules m
WHERE NOT EXISTS (
  SELECT 1 FROM functions f
  JOIN role_functions rf ON rf.function_id = f.id
  JOIN roles r ON r.id = rf.role_id AND r.store_id IS NOT NULL
  WHERE f.module_id = m.id
)
ORDER BY m.slug;")"
if [ -z "$ORPHAN" ]; then
  echo "  없음"
else
  echo "$ORPHAN" | sed 's/^/  ! /'
fi
echo

# ---------------------------------------------------------------------------
# 6) 참고 — functions.slug 중복 (권한 누수 원인)
# ---------------------------------------------------------------------------
echo "--- [점검] functions.slug 중복 ---"
DUP="$(run_sql "
SELECT slug || ' (' || count(*) || ')'
FROM functions GROUP BY slug HAVING count(*) > 1 ORDER BY 1;")"
if [ -z "$DUP" ]; then
  echo "  없음 — 유일성 확보됨"
else
  echo "$DUP" | sed 's/^/  ✗ /'
fi

rm -f "$TMP_FRONT" "$TMP_DB"
echo
echo "== 완료 =="
