#!/usr/bin/env bash
# [2026-10-22] Stage (운용3): producción → stage. Fuente = réplica local ventago18:5434 (sólo lectura).
#   Destino = cluster PG18 «stage» :5435. Corre como root (timer diario o a mano).
# ★ Nunca escribe en 5434. El dump se hace del standby; si la recuperación cancela la consulta
#   (conflicto con WAL) se reintenta.
set -euo pipefail
D=/var/lib/stage
mkdir -p "$D"; chown postgres "$D"
log(){ echo "$(date '+%F %T') stage-refresh: $*"; }

for intento in 1 2 3; do
  if sudo -u postgres pg_dump -p 5434 -d ventago -Fc -f "$D/ventago.dump.tmp"; then break; fi
  log "pg_dump falló (intento $intento)"; [ "$intento" = 3 ] && exit 1; sleep 30
done
mv "$D/ventago.dump.tmp" "$D/ventago.dump"
log "dump $(du -h "$D/ventago.dump" | cut -f1)"

# los contenedores de stage sueltan la base mientras se reemplaza
docker stop stage_api >/dev/null 2>&1 || true
sudo -u postgres psql -p 5435 -v ON_ERROR_STOP=1 -q \
  -c "DROP DATABASE IF EXISTS ventago WITH (FORCE)" \
  -c "CREATE DATABASE ventago OWNER coolsistema"
# --no-owner: todo queda de coolsistema (el rol de la app de stage)
sudo -u postgres pg_restore -p 5435 -d ventago --no-owner --no-privileges --role=coolsistema -j 4 "$D/ventago.dump" \
  2> "$D/restore.err" || log "pg_restore terminó con avisos ($(grep -c ERROR "$D/restore.err" || true) ERROR) — ver $D/restore.err"
sudo -u postgres psql -p 5435 -d ventago -v ON_ERROR_STOP=1 -q -f /opt/stage/sanitize.sql
log "tablas $(sudo -u postgres psql -p 5435 -d ventago -Atc "select count(*) from pg_tables where schemaname in ('public','reseller')") · ventas $(sudo -u postgres psql -p 5435 -d ventago -Atc 'select count(*) from sales')"
docker start stage_api >/dev/null 2>&1 || true
log "listo"
