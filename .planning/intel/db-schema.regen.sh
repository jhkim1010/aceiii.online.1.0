#!/usr/bin/env bash
# Ventago DB schema regen — 마이그레이션 적용 후 또는 모델 변경 후 실행.
# 출력: .planning/intel/db-schema-tables.md + .planning/intel/db-schema-fks.md
#
# 사용:
#   ./.planning/intel/db-schema.regen.sh             # local PG18 (default)
#   PSQL_USER=postgres PSQL_DB=ventago ./.planning/intel/db-schema.regen.sh
#
# 운영 PG10 도 같은 스키마이므로 로컬에서 생성한 결과를 git commit 하면 됨.

set -euo pipefail

PSQL_USER="${PSQL_USER:-postgres}"
PSQL_DB="${PSQL_DB:-ventago}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

OUT_TABLES="$ROOT_DIR/.planning/intel/db-schema-tables.md"
OUT_FKS="$ROOT_DIR/.planning/intel/db-schema-fks.md"

echo "Dumping columns..."
psql -U "$PSQL_USER" -d "$PSQL_DB" -t -A -F '|' -c "
SELECT c.table_name, c.column_name, c.data_type, c.is_nullable,
       COALESCE(c.column_default, '') AS dflt,
       COALESCE(c.character_maximum_length::text, '') AS maxlen
FROM information_schema.columns c
JOIN information_schema.tables t ON t.table_name = c.table_name AND t.table_schema = c.table_schema
WHERE c.table_schema = 'public' AND t.table_type = 'BASE TABLE'
ORDER BY c.table_name, c.ordinal_position;
" | awk -F'|' -v ts="$TS" '
BEGIN {
  print "# Ventago Database Schema (PostgreSQL public)"
  print ""
  print "> Auto-generated from local PG18 `ventago` DB on " ts "."
  print "> **Regenerate**: `./.planning/intel/db-schema.regen.sh`"
  print "> **운영 PG10 == local PG18** — 같은 마이그레이션 적용 (api-ventago/migrations/)"
  print ""
  print "## Conventions"
  print ""
  print "- 모든 컬럼 `snake_case` (Sequelize `underscored: true` 전역)."
  print "- Sequelize 모델은 `camelCase` 속성 → DB `snake_case` 컬럼 자동 매핑."
  print "- SQL 직접 작성 시 **반드시 이 파일의 snake_case 이름 사용**."
  print "- 멀티테넌트: 거의 모든 테이블에 `store_id` FK."
  print ""
  current=""
}
{
  if ($1 != current) {
    if (current != "") print ""
    print "## `" $1 "`"
    print ""
    print "| Column | Type | Null | Default |"
    print "|---|---|---|---|"
    current = $1
  }
  type = $3
  if ($6 != "") type = type "(" $6 ")"
  nullable = ($4 == "NO" ? "NOT NULL" : "")
  gsub(/\|/, "\\|", $5)
  dflt = (length($5)>40 ? substr($5,1,37)"..." : $5)
  print "| `" $2 "` | " type " | " nullable " | " dflt " |"
}
' > "$OUT_TABLES"

echo "Dumping foreign keys..."
psql -U "$PSQL_USER" -d "$PSQL_DB" -t -A -F '|' -c "
SELECT
  tc.table_name AS src_table,
  kcu.column_name AS src_column,
  ccu.table_name AS fk_table,
  ccu.column_name AS fk_column
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
JOIN information_schema.constraint_column_usage ccu
  ON ccu.constraint_name = tc.constraint_name AND ccu.table_schema = tc.table_schema
WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_schema = 'public'
ORDER BY tc.table_name, kcu.column_name;
" | awk -F'|' '
BEGIN {
  print "# Ventago Foreign Keys"
  print ""
  print "| Source Table | Source Column | → | Target Table | Target Column |"
  print "|---|---|---|---|---|"
}
{ print "| `" $1 "` | `" $2 "` | → | `" $3 "` | `" $4 "` |" }
' > "$OUT_FKS"

echo "Wrote:"
echo "  $OUT_TABLES ($(wc -l < "$OUT_TABLES") lines)"
echo "  $OUT_FKS ($(wc -l < "$OUT_FKS") lines)"
