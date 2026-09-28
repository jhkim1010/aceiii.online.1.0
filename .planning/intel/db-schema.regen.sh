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
# [CODEX P2, 2026-09-28] La consulta anterior unía key_column_usage (columnas
# de origen) con constraint_column_usage (columnas de destino) SÓLO por
# nombre de constraint, sin emparejar la posición ordinal. Para una FK de una
# sola columna eso da 1 fila correcta por casualidad; para una FK COMPUESTA
# (2+ columnas a cada lado) produce el producto cartesiano de columnas de
# origen × columnas de destino — filas que describen relaciones que la DB
# jamás declaró (p. ej. `nota_attachments.nota_id -> notas.store_id`, que no
# existe: la FK real es el PAR `(nota_id, store_id) -> (id, store_id)`).
#
# Primer intento del fix: unir `information_schema.referential_constraints`
# con DOS lecturas de `key_column_usage` emparejando por
# `position_in_unique_constraint`. Es correcto (probado a mano), pero
# `key_column_usage` internamente llama a `_pg_expandarray()` por cada fila
# de cada constraint de la base — con ~130 tablas tardó **varios minutos** y
# hubo que cancelarlo (`pg_cancel_backend`). `information_schema` está pensado
# para portabilidad entre motores, no para velocidad.
#
# Se usa en cambio `pg_constraint` (catálogo nativo) directo: `conkey` y
# `confkey` son DOS ARRAYS PARALELOS — el catálogo ya garantiza que la
# posición N de uno corresponde a la posición N del otro, así que
# `unnest(conkey, confkey) WITH ORDINALITY` los empareja sin ningún join
# adicional. Mismo resultado que la versión con information_schema (24
# columnas de FK compuestas de Notas verificadas fila por fila, idénticas),
# pero ~0.03s en vez de minutos.
psql -U "$PSQL_USER" -d "$PSQL_DB" -t -A -F '|' -c "
SELECT
  src.relname AS src_table,
  string_agg(sa.attname, ', ' ORDER BY k.ord) AS src_columns,
  tgt.relname AS fk_table,
  string_agg(ta.attname, ', ' ORDER BY k.ord) AS fk_columns
FROM pg_constraint c
JOIN pg_class src ON src.oid = c.conrelid
JOIN pg_class tgt ON tgt.oid = c.confrelid
JOIN pg_namespace n ON n.oid = src.relnamespace AND n.nspname = 'public'
CROSS JOIN LATERAL unnest(c.conkey, c.confkey) WITH ORDINALITY AS k(srcattnum, tgtattnum, ord)
JOIN pg_attribute sa ON sa.attrelid = src.oid AND sa.attnum = k.srcattnum
JOIN pg_attribute ta ON ta.attrelid = tgt.oid AND ta.attnum = k.tgtattnum
WHERE c.contype = 'f'
GROUP BY src.relname, tgt.relname, c.conname
ORDER BY src.relname, min(k.ord);
" | awk -F'|' '
BEGIN {
  print "# Ventago Foreign Keys"
  print ""
  print "> Columnas separadas por `, ` en una misma fila = FK COMPUESTA (varias"
  print "> columnas juntas referencian la fila, no relaciones independientes)."
  print ""
  print "| Source Table | Source Column(s) | → | Target Table | Target Column(s) |"
  print "|---|---|---|---|---|"
}
{ print "| `" $1 "` | `" $2 "` | → | `" $3 "` | `" $4 "` |" }
' > "$OUT_FKS"

echo "Wrote:"
echo "  $OUT_TABLES ($(wc -l < "$OUT_TABLES") lines)"
echo "  $OUT_FKS ($(wc -l < "$OUT_FKS") lines)"
