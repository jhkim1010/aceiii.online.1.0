#!/usr/bin/env bash
#
# 운용3 전환(failover) — 운영(srv803182)이 죽었을 때 운용3 를 원본으로 만든다.
#
# ★★ 되돌릴 수 없다. 승격된 대기 DB 는 다시 운영을 따라가지 못한다(복귀 = failback.sh, 다시 복제부터).
# ★★ 운영이 살아 있는데 돌리면 **두 원본**이 된다(split-brain) — 판매·AFIP 번호가 두 곳에서 갈라진다.
#     그래서 기본은 「운영이 확실히 죽었는지」를 여기서 직접 확인하고, 아니면 거부한다.
#
# 사용 (운용3 에서, root):
#   ventago-failover --simular                 점검과 계획만 보여 준다(아무것도 안 바꾼다)
#   ventago-failover                           점검 → 확인 문구 입력 → 전환
#   ventago-failover --forzar-prod-vivo        운영 서버는 살아 있지만 Ventago 가 죽은 경우(리허설 포함).
#                                              ★ 먼저 운영의 api_ventago 를 **멈춰야** 한다 — 스크립트가 확인한다.
#
# 하는 일: ① 운영 사망 확인 ② 복제 지연 표시 ③ 터널·사본 타이머 정지 ④ PG 승격 ⑤ /etc/hosts
#          ⑥ 컨테이너 기동(restart unless-stopped) ⑦ 헬스체크 ⑧ 감시를 「원본 모드」로 ⑨ 텔레그램 · DNS 안내
#
# ★ set -e 를 쓰지 않는다 — 단계마다 결과를 보고 멈출지 정한다.

PROD_IP=${PROD_IP:-62.72.7.245}
STBY_IP=${STBY_IP:-149.28.107.232}
PG_PORT=5434
COMPOSE="docker compose -f /opt/ventago/docker-compose.yml --project-directory /tmp"
STATE=/opt/ventago/state
LOG=/var/log/ventago-failover.log
WATCH_ENV=/etc/ventago-health-watch.env
HOSTS_MARK="# ventago-failover"

SIMULAR=""; FORZAR=""
for a in "$@"; do
  case "$a" in
    --simular) SIMULAR=1 ;;
    --forzar-prod-vivo) FORZAR=1 ;;
    *) echo "argumento desconocido: $a"; exit 64 ;;
  esac
done

[ "$(id -u)" -eq 0 ] || { echo "correr como root (sudo)"; exit 1; }
log() { echo "[$(date '+%F %T %Z')] $*" | tee -a "$LOG"; }
paso() { log "── $*"; }
abortar() { log "✖ ABORTADO: $*"; exit 1; }
# 운영 사망 판정의 거부는 --simular 에서는 멈추지 않고 「거부했을 것」만 적는다 — 나머지 점검도 보이게.
bloquear() { if [ -n "$SIMULAR" ]; then log "✖ (simulación) BLOQUEARÍA: $*"; bloqueado=1; else abortar "$*"; fi; }
bloqueado=""

enviar_telegram() {
  local token chat
  token=$(grep -E '^TELEGRAM_BOT_TOKEN=' "$WATCH_ENV" | cut -d= -f2-)
  chat=$(grep -E '^TELEGRAM_CHAT_ID=' "$WATCH_ENV" | cut -d= -f2-)
  [ -n "$token" ] && [ -n "$chat" ] || return 1
  curl -sS --max-time 15 -o /dev/null "https://api.telegram.org/bot${token}/sendMessage" \
    --data-urlencode "chat_id=${chat}" --data-urlencode "text=$1"
}

[ -f "$STATE/PROMOVIDO" ] && abortar "ya se hizo failover ($(cat "$STATE/PROMOVIDO")). Para volver: failback."

# ── ① 운영 사망 확인 ────────────────────────────────────────────────────────────
paso "① ¿prod está caído? (3 rondas, 20 s entre cada una)"
api_vivo=0; ssh_vivo=0
for r in 1 2 3; do
  c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 --resolve "newapi.coolsistema.com:443:${PROD_IP}" https://newapi.coolsistema.com/api/health)
  s=$(timeout 8 bash -c "exec 3<>/dev/tcp/${PROD_IP}/22" 2>/dev/null && echo abierto || echo cerrado)
  log "   ronda $r: API prod HTTP ${c:-000} · ssh(22) ${s}"
  [ "$c" = "200" ] && api_vivo=1
  [ "$s" = "abierto" ] && ssh_vivo=1
  [ "$r" -lt 3 ] && sleep 20
done
if [ "$api_vivo" -eq 1 ]; then
  bloquear "la API de prod RESPONDE 200. Con prod vivo esto crea dos originales. Si es un ensayo: parar api_ventago en prod primero."
fi
if [ "$ssh_vivo" -eq 1 ]; then
  if [ -z "$FORZAR" ]; then
    bloquear "el servidor de prod está vivo (ssh abierto) aunque la API no responde. Primero intentar arreglar allá. Si de verdad hay que cambiar: --forzar-prod-vivo (y la API de prod tiene que quedar parada)."
  fi
  [ -n "$FORZAR" ] && log "   ⚠ --forzar-prod-vivo: servidor de prod vivo, API caída. Se sigue bajo responsabilidad del operador."
fi

# ── ② 복제 상태 ────────────────────────────────────────────────────────────────
paso "② réplica"
fila=$(runuser -u postgres -- psql -p $PG_PORT -d postgres -AtX -F'|' -c \
  "SELECT pg_is_in_recovery(), coalesce(now()-pg_last_xact_replay_timestamp(), interval '0')::text,
          coalesce((SELECT status FROM pg_stat_wal_receiver),'sin-receptor'), pg_last_wal_replay_lsn()" 2>/dev/null)
[ -n "$fila" ] || abortar "no puedo consultar el PG local ($PG_PORT)"
IFS='|' read -r en_rec ultima_tx receptor lsn <<<"$fila"
log "   en recovery=$en_rec · última transacción aplicada hace $ultima_tx · receptor=$receptor · lsn=$lsn"
[ "$en_rec" = "t" ] || abortar "el PG local ya no está en recovery (¿promovido a mano?)"
log "   ⤷ lo que prod haya escrito después de esa última transacción NO está acá."
ventas=$(runuser -u postgres -- psql -p $PG_PORT -d ventago -AtX -c "SELECT max(id) FROM sales" 2>/dev/null)
log "   sales max(id) local = ${ventas:-?}"

# ── 계획 ───────────────────────────────────────────────────────────────────────
paso "plan"
log "   ③ parar pg-tunnel · minio-tunnel · standby-minio-sync.timer"
log "   ④ pg_promote()  — IRREVERSIBLE"
log "   ⑤ /etc/hosts: 127.0.0.1 newapi/app/apiminio.coolsistema.com"
log "   ⑥ start redis · api_ventago · ventagoapp (restart unless-stopped)"
log "   ⑦ health local + vía nginx · ⑧ vigilancia en modo original · ⑨ Telegram + DNS"
if [ -n "$SIMULAR" ]; then log "SIMULACIÓN: no se cambió nada.${bloqueado:+ (con prod así, el failover real se habría negado)}"; exit 0; fi

if [ -t 0 ]; then
  printf '\nEscribí exactamente  PROMOVER ventago  para seguir: '
  read -r confirma
  [ "$confirma" = "PROMOVER ventago" ] || abortar "confirmación incorrecta"
else
  abortar "sin terminal: el failover pide confirmación escrita"
fi

# ── ③ 사본 경로 정지 ─────────────────────────────────────────────────────────────
paso "③ parar túneles y copias desde prod"
systemctl disable --now standby-minio-sync.timer pg-tunnel minio-tunnel 2>&1 | tee -a "$LOG"

# ── ④ 승격 ─────────────────────────────────────────────────────────────────────
paso "④ promover PG"
runuser -u postgres -- psql -p $PG_PORT -d postgres -AtX -c "SELECT pg_promote(true, 60)" | tee -a "$LOG"
[ "$(runuser -u postgres -- psql -p $PG_PORT -d postgres -AtX -c 'SELECT pg_is_in_recovery()')" = "f" ] \
  || abortar "pg_promote no terminó — revisar /var/log/postgresql/postgresql-18-ventago18.log"
install -d -m 755 "$STATE"; date '+%F %T %Z' > "$STATE/PROMOVIDO"
log "   PG es original. Marcado $STATE/PROMOVIDO (standby-sync.sh deja de tocar este servidor)."

# ── ⑤ hosts ────────────────────────────────────────────────────────────────────
paso "⑤ /etc/hosts"
# api usa la red del host: MINIO_HOST=apiminio.coolsistema.com tiene que resolver acá, no a prod.
cp -p /etc/hosts "/etc/hosts.bak-failover-$(date +%Y%m%d%H%M)"
grep -q "$HOSTS_MARK" /etc/hosts || echo "127.0.0.1 newapi.coolsistema.com app.coolsistema.com apiminio.coolsistema.com $HOSTS_MARK" >> /etc/hosts

# ── ⑥ 컨테이너 ─────────────────────────────────────────────────────────────────
paso "⑥ contenedores"
for c in ventago_redis api_ventago ventagoapp minio; do docker update --restart unless-stopped "$c" >/dev/null; done
$COMPOSE start redis minio api app 2>&1 | tee -a "$LOG"

# ── ⑦ 헬스체크 ─────────────────────────────────────────────────────────────────
paso "⑦ health"
ok=""
for i in $(seq 1 40); do
  sleep 3
  cuerpo=$(curl -s --max-time 5 http://127.0.0.1:5002/api/health)
  case "$cuerpo" in *'"db":"up"'*) ok=1; break ;; esac
done
log "   api local: ${cuerpo:-sin respuesta}"
[ -n "$ok" ] || log "   ✖ la API no quedó sana en 120 s — docker logs api_ventago"
for u in newapi.coolsistema.com/api/health app.coolsistema.com/login apiminio.coolsistema.com/minio/health/live; do
  h=${u%%/*}
  log "   vía nginx https://$u → $(curl -s -o /dev/null -w '%{http_code}' --max-time 10 --resolve "$h:443:127.0.0.1" "https://$u")"
done

# ── ⑧ 감시 모드 ────────────────────────────────────────────────────────────────
paso "⑧ vigilancia: de «réplica» a «original»"
cp -p "$WATCH_ENV" "$WATCH_ENV.bak-failover"
sed -i -E 's/^ETIQUETA=.*/ETIQUETA=ORIGINAL-운용3/; s/^CONTENEDORES=.*/CONTENEDORES=api_ventago ventagoapp/; s/^CHEQUEAR_ADAPTER=.*/CHEQUEAR_ADAPTER=1/; s/^CHEQUEAR_REPLICA=.*/CHEQUEAR_REPLICA=/' "$WATCH_ENV"
grep -vE 'TOKEN' "$WATCH_ENV" | tee -a "$LOG"

# ── ⑨ 알림 ─────────────────────────────────────────────────────────────────────
paso "⑨ aviso"
msg="🟠 Ventago FAILOVER a 운용3 (${STBY_IP}) — $(date '+%F %T %Z')
API local: ${ok:+sana}${ok:-NO sana}
Última transacción de prod aplicada: hace ${ultima_tx}
FALTA: cambiar en GoDaddy los A de newapi · app · apiminio .coolsistema.com → ${STBY_IP}"
enviar_telegram "$msg" || log "   (no se pudo mandar Telegram)"
log "LISTO. Siguiente: DNS (GoDaddy) newapi/app/apiminio → ${STBY_IP}. Volver a prod: failback (paso 7)."
