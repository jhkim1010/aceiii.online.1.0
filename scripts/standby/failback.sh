#!/usr/bin/env bash
#
# 운용3 복귀(failback) — failover 뒤 원본이 된 운용3 의 DB 를 운영(srv803182)으로 되돌리고,
# 운용3 를 다시 운영의 대기(standby)로 만든다.
#
# ★ Mac 에서 돈다(standby-sync.sh 와 같은 이유: 양쪽에 다 SSH 할 수 있는 곳이 여기뿐이다).
# ★★ 정지 시간이 있다(실측 전 추정 10–15분: 2.4GB 를 Mac 경유로 옮기는 시간). **밤에** 한다.
# ★★ 운영의 현재 DB 는 **버리지 않고 옆으로 치운다** (`ventago18.antes-failback-<시각>`). 지우지 않는다.
#
# 방식 — 「깨끗이 멈춘 원본의 통째 사본」:
#   운용3 쓰기를 멈춘다 → 운용3 PG 를 정상 종료 → 데이터 폴더를 그대로 운영에 복사 → 운영을 **원본으로** 기동.
#   두 폴더가 같은 종료 체크포인트·같은 타임라인이므로, 운용3 는 standby.signal 만 놓으면 운영을 따라간다
#   (다시 2.4GB 기본 백업을 뜰 필요가 없다). 운영의 postgresql.auto.conf(메모리 설정)는 운영 것을 되살린다.
#
# 사용 (Mac):
#   scripts/standby/failback.sh --simular     점검과 계획만(아무것도 안 바꾼다)
#   scripts/standby/failback.sh               점검 → 확인 문구 → 복귀
#   ... --descartar-escrituras-prod           운영이 failover 뒤에도 판매를 받았을 때(두 원본). 그 판매는 옆으로
#                                             치운 폴더에만 남는다 — 손으로 옮겨야 한다.
#
# ★ set -e 를 쓰지 않는다 — 단계마다 결과를 보고 멈출지 정한다.

PROD=${PROD:-jhkim-server}
STBY=${STBY:-ventago-standby}
PROD_IP=${PROD_IP:-62.72.7.245}
DATA=/var/lib/postgresql/18/ventago18
UNIT=postgresql@18-ventago18
STATE=/opt/ventago/state
COMPOSE="sudo docker compose -f /opt/ventago/docker-compose.yml --project-directory /tmp"
LOG=${LOG:-$HOME/Library/Logs/ventago-failback.log}
TS=$(date +%Y%m%d%H%M)
APARTE="$DATA.antes-failback-$TS"

SIMULAR=""; DESCARTAR=""
for a in "$@"; do
  case "$a" in
    --simular) SIMULAR=1 ;;
    --descartar-escrituras-prod) DESCARTAR=1 ;;
    *) echo "argumento desconocido: $a"; exit 64 ;;
  esac
done

log() { echo "[$(date '+%F %T %Z')] $*" | tee -a "$LOG"; }
paso() { log "── $*"; }
abortar() { log "✖ ABORTADO: $*"; exit 1; }
bloquear() { if [ -n "$SIMULAR" ]; then log "✖ (simulación) BLOQUEARÍA: $*"; bloqueado=1; else abortar "$*"; fi; }
bloqueado=""
sql_prod() { ssh "$PROD" "sudo -u postgres psql -p 5434 -AtX -d ${2:-ventago}" <<<"$1" 2>/dev/null; }
sql_stby() { ssh "$STBY" "sudo -u postgres psql -p 5434 -AtX -d ${2:-ventago}" <<<"$1" 2>/dev/null; }
# A partir del paso ⑤ el original ya no está arriba en ningún lado: si algo falla, esto dice cómo volver.
SI_FALLA="운용3 sigue teniendo los datos intactos. Para volver a operar en 운용3:
  ssh $STBY 'sudo systemctl start $UNIT && sudo docker update --restart unless-stopped api_ventago ventagoapp ventago_redis && $COMPOSE start redis api app'
  (y en prod: dejar api_ventago PARADO)"
fallo_critico() { log "✖ FALLÓ: $*"; log "$SI_FALLA"; exit 1; }

ssh -o BatchMode=yes -o ConnectTimeout=10 "$PROD" true 2>/dev/null || abortar "no llego a $PROD por ssh"
ssh -o BatchMode=yes -o ConnectTimeout=10 "$STBY" true 2>/dev/null || abortar "no llego a $STBY por ssh"

# ── ① 전제 ────────────────────────────────────────────────────────────────────
paso "① condiciones"
promovido=$(ssh "$STBY" "sudo cat $STATE/PROMOVIDO 2>/dev/null")
[ -n "$promovido" ] || bloquear "운용3 no está promovido (no hay $STATE/PROMOVIDO): no hay nada que devolver."
log "   운용3 promovido: ${promovido:-NO}"
en_rec_s=$(sql_stby "SELECT pg_is_in_recovery()" postgres)
log "   운용3 PG en recovery = ${en_rec_s:-?} (tiene que ser f)"
[ "$en_rec_s" = "f" ] || bloquear "el PG de 운용3 no es original (recovery=${en_rec_s:-sin respuesta})"
ver_p=$(ssh "$PROD" "/usr/lib/postgresql/18/bin/postgres --version" 2>/dev/null)
ver_s=$(ssh "$STBY" "/usr/lib/postgresql/18/bin/postgres --version" 2>/dev/null)
log "   versión prod: ${ver_p:-?} · 운용3: ${ver_s:-?}"
case "$ver_p" in *" 18."*) ;; *) bloquear "prod no tiene PostgreSQL 18 (${ver_p:-?})" ;; esac

# 운영 DB 가 failover 뒤에 판매를 받았는가 (서버가 살아나면 api 가 restart=always 로 스스로 뜬다)
estado_api_p=$(ssh "$PROD" "docker inspect api_ventago --format '{{.State.Status}}'" 2>/dev/null)
log "   prod api_ventago: ${estado_api_p:-?}"
max_s=$(sql_stby "SELECT max(id) FROM sales")
pg_p_vivo=$(ssh "$PROD" "systemctl is-active $UNIT" 2>/dev/null)
log "   prod PG: ${pg_p_vivo:-?} · 운용3 sales max(id) = ${max_s:-?}"
if [ "$pg_p_vivo" = "active" ] && [ -n "$promovido" ]; then
  # PROMOVIDO = date '+%F %T %Z' de 운용3 (p. ej. «2026-10-16 22:10:00 UTC») — PG lo lee tal cual.
  nuevas_p=$(sql_prod "SELECT count(*) FROM sales WHERE created_at > timestamptz '$promovido'")
  log "   ventas en prod creadas después de la promoción: ${nuevas_p:-?}"
  if [ "${nuevas_p:-0}" != "0" ] && [ -z "$DESCARTAR" ]; then
    bloquear "prod recibió ${nuevas_p:-?} ventas después del failover (dos originales). Al volver se pierden de prod (quedan en $APARTE). Si se acepta: --descartar-escrituras-prod"
  fi
fi
libre_p=$(ssh "$PROD" "df -BG --output=avail /var/lib/postgresql | tail -1 | tr -dc 0-9")
log "   espacio libre en prod: ${libre_p:-?} GB (hace falta ~3 GB: se guarda la copia vieja al lado)"
[ "${libre_p:-0}" -ge 10 ] || bloquear "poco espacio en prod (${libre_p:-?} GB)"
grep_conn=$(ssh "$STBY" "sudo grep -cE '^primary_(conninfo|slot_name)' $DATA/postgresql.auto.conf")
[ "$grep_conn" = "2" ] || bloquear "a la auto.conf de 운용3 le falta primary_conninfo/primary_slot_name (no podrá seguir a prod)"

# ── 계획 ───────────────────────────────────────────────────────────────────────
paso "plan"
log "   ② MinIO 운용3 → prod (sin corte)          ③ CORTE: parar api/app en 운용3 · MinIO otra vez"
log "   ④ prod: parar api_ventago y PG · mover $DATA → $APARTE"
log "   ⑤ 운용3: apagar PG limpio · copiar la carpeta entera a prod (zstd, vía Mac)"
log "   ⑥ prod: auto.conf de prod · arrancar PG como ORIGINAL · comprobar sales max(id) · slot ventago_standby"
log "   ⑦ prod: arrancar api_ventago · health      ⑧ 운용3 → standby otra vez (standby.signal · túneles · hosts · vigilancia)"
log "   ⑨ Telegram + DNS de vuelta a $PROD_IP"
if [ -n "$SIMULAR" ]; then log "SIMULACIÓN: no se cambió nada.${bloqueado:+ (en este estado el failback real se habría negado)}"; exit 0; fi

if [ -t 0 ]; then
  printf '\nEscribí exactamente  VOLVER A PROD  para seguir: '
  read -r confirma
  [ "$confirma" = "VOLVER A PROD" ] || abortar "confirmación incorrecta"
else
  abortar "sin terminal: el failback pide confirmación escrita"
fi
t0=$(date +%s)

# ── ② MinIO (정지 전, 대부분 여기서) ──────────────────────────────────────────────
minio_copia() {
  ssh "$STBY" "sudo systemctl start minio-tunnel && sleep 3 && sudo rclone --config /etc/rclone-ventago.conf copy local:coolsistema prod:coolsistema --transfers 4 --log-level NOTICE" 2>&1 | tee -a "$LOG"
  return "${PIPESTATUS[0]}"
}
paso "② MinIO 운용3 → prod"
minio_copia || abortar "la copia de MinIO falló — nada cambió todavía"

# ── ③ 정지 ─────────────────────────────────────────────────────────────────────
paso "③ CORTE: parar escrituras en 운용3"
ssh "$STBY" "sudo docker update --restart no api_ventago ventagoapp ventago_redis >/dev/null && $COMPOSE stop api app" 2>&1 | tee -a "$LOG"
[ "$(ssh "$STBY" "sudo docker inspect api_ventago --format '{{.State.Running}}'")" = "false" ] || abortar "api_ventago de 운용3 sigue corriendo"
max_s=$(sql_stby "SELECT max(id) FROM sales")
log "   운용3 congelado · sales max(id) = $max_s"
minio_copia || abortar "MinIO (segunda pasada) falló — 운용3 está parado: volver a arrancarlo con: ssh $STBY '$COMPOSE start api app'"

# ── ④ 운영 정리 ────────────────────────────────────────────────────────────────
paso "④ prod: parar api y PG, apartar la carpeta"
ssh "$PROD" "docker stop api_ventago" 2>&1 | tee -a "$LOG"
ssh "$PROD" "sudo systemctl stop $UNIT && sudo mv $DATA $APARTE && sudo install -d -o postgres -g postgres -m 700 $DATA" \
  || fallo_critico "no pude parar/apartar el PG de prod. Revisar: ssh $PROD 'systemctl status $UNIT; ls -d $DATA*'"
log "   copia vieja de prod: $APARTE (NO arrancarla: es otra línea de tiempo)"

# ── ⑤ 복사 ─────────────────────────────────────────────────────────────────────
paso "⑤ 운용3: apagar PG y copiar"
ssh "$STBY" "sudo systemctl stop $UNIT" || fallo_critico "no pude apagar el PG de 운용3"
cl=$(ssh "$STBY" "sudo /usr/lib/postgresql/18/bin/pg_controldata $DATA | grep -E 'cluster state'")
log "   운용3 $cl"
case "$cl" in *"shut down"*) ;; *) fallo_critico "el PG de 운용3 no quedó apagado limpio ($cl)" ;; esac
ssh "$STBY" "sudo tar -C $DATA --exclude=./postmaster.pid --exclude=./standby.signal --exclude=./backup_label.old --exclude=./postgresql.auto.conf -cf - . | zstd -3 -T2 -q" \
  | ssh "$PROD" "zstd -d -q | sudo tar -C $DATA -xf - && sudo cp -p $APARTE/postgresql.auto.conf $DATA/ && sudo chown -R postgres:postgres $DATA && sudo chmod 700 $DATA" \
  || fallo_critico "la copia a prod falló"
log "   copiado en $(( $(date +%s) - t0 ))s desde el inicio"

# ── ⑥ 운영 기동 ────────────────────────────────────────────────────────────────
paso "⑥ prod: arrancar PG como original"
ssh "$PROD" "sudo systemctl start $UNIT" || fallo_critico "el PG de prod no arrancó — ssh $PROD 'sudo tail -50 /var/log/postgresql/postgresql-18-ventago18.log'"
[ "$(sql_prod "SELECT pg_is_in_recovery()" postgres)" = "f" ] || fallo_critico "el PG de prod quedó en recovery"
max_p=$(sql_prod "SELECT max(id) FROM sales")
log "   prod sales max(id) = $max_p · 운용3 al congelar = $max_s"
[ -n "$max_p" ] && [ "$max_p" = "$max_s" ] || fallo_critico "los datos no coinciden"
sql_prod "SELECT pg_create_physical_replication_slot('ventago_standby', true)" postgres >/dev/null \
  || log "   ⚠ no pude crear el slot ventago_standby (¿ya existe?)"

# ── ⑦ 운영 api ─────────────────────────────────────────────────────────────────
paso "⑦ prod: api"
ssh "$PROD" "docker start api_ventago; docker inspect ventagoapp --format '{{.State.Running}}' | grep -q true || docker start ventagoapp" 2>&1 | tee -a "$LOG"
ok=""
for i in $(seq 1 40); do
  sleep 3
  cuerpo=$(curl -s --max-time 5 --resolve "newapi.coolsistema.com:443:${PROD_IP}" https://newapi.coolsistema.com/api/health)
  case "$cuerpo" in *'"db":"up"'*) ok=1; break ;; esac
done
log "   prod health: ${cuerpo:-sin respuesta}"
[ -n "$ok" ] || log "   ✖ la API de prod no quedó sana en 120 s — ssh $PROD 'docker logs --tail 80 api_ventago'"
log "   corte total: $(( $(date +%s) - t0 ))s"

# ── ⑧ 운용3 → 대기 ─────────────────────────────────────────────────────────────
paso "⑧ 운용3 vuelve a ser standby"
# ★ standby.signal 이 없으면 PG 를 켜지 않는다 — 켜면 운용3 가 다시 원본이 되어 두 원본이 된다.
ssh "$STBY" "sudo sed -i '/# ventago-failover/d' /etc/hosts; $COMPOSE stop redis >/dev/null 2>&1; \
  sudo -u postgres touch $DATA/standby.signal && sudo test -f $DATA/standby.signal" \
  || { log "   ✖ no pude poner standby.signal en 운용3 — su PG queda APAGADO (prod ya es el original y está bien)"; exit 1; }
ssh "$STBY" "sudo systemctl enable --now pg-tunnel minio-tunnel standby-minio-sync.timer && sudo systemctl start $UNIT" 2>&1 | tee -a "$LOG"
rec=""
for i in $(seq 1 20); do
  sleep 3
  rec=$(sql_stby "SELECT pg_is_in_recovery()||'|'||coalesce((SELECT status FROM pg_stat_wal_receiver),'sin-receptor')" postgres)
  [ "$rec" = "t|streaming" ] && break
done
log "   운용3 recovery|receptor = ${rec:-?}"
if [ "$rec" = "t|streaming" ]; then
  ssh "$STBY" "if sudo test -f /etc/ventago-health-watch.env.bak-failover; then sudo cp -p /etc/ventago-health-watch.env.bak-failover /etc/ventago-health-watch.env; fi \
    && sudo mv $STATE/PROMOVIDO $STATE/PROMOVIDO.devuelto-$TS"
  log "   vigilancia en modo réplica · PROMOVIDO → PROMOVIDO.devuelto-$TS (standby-sync vuelve a actuar)"
else
  log "   ✖ 운용3 no sigue a prod. Prod YA es el original y está bien; 운용3 hay que rehacerlo con pg_basebackup (PLAN paso 2)."
  log "     PROMOVIDO se deja puesto para que standby-sync no toque los contenedores."
fi

# ── ⑨ 알림 ─────────────────────────────────────────────────────────────────────
paso "⑨ aviso"
msg="🟢 Ventago FAILBACK: prod (${PROD_IP}) es otra vez el original — $(date '+%F %T %Z')
API prod: ${ok:+sana}${ok:-NO sana} · sales max(id) ${max_p}
운용3: ${rec}
FALTA: si el DNS se había cambiado, volver los A de newapi · app · apiminio .coolsistema.com → ${PROD_IP}"
ssh "$STBY" "t=\$(sudo grep -E '^TELEGRAM_BOT_TOKEN=' /etc/ventago-health-watch.env | cut -d= -f2-); c=\$(sudo grep -E '^TELEGRAM_CHAT_ID=' /etc/ventago-health-watch.env | cut -d= -f2-); \
  curl -sS --max-time 15 -o /dev/null https://api.telegram.org/bot\$t/sendMessage --data-urlencode chat_id=\$c --data-urlencode text@-" <<<"$msg" \
  || log "   (no se pudo mandar Telegram)"
log "LISTO. DNS → ${PROD_IP} si se había cambiado. Copia vieja de prod en $APARTE (no se borra)."
