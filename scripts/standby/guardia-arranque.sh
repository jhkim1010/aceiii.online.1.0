#!/usr/bin/env bash
#
# ventago-guardia-arranque — corre en PROD antes de levantar su Postgres (ExecStartPre de
# postgresql@18-ventago18, drop-in 20-guardia-standby.conf). 2026-10-17.
#
# Por qué: después de un failover, 운용3 es el original. Si prod revive (reinicio, el proveedor
#   lo levanta), su Postgres arranca solo como original Y api_ventago (restart=always) vende contra
#   él → dos originales, ventas en dos lugares. 운용3 no tiene forma de apagar prod (el túnel sólo
#   reenvía puertos), así que prod tiene que preguntar antes de arrancar.
#
# Regla:
#   · 운용3 responde «PROMOVIDO…»  → NO arranca (exit 1) + aviso por Telegram.
#   · responde «STANDBY…»          → arranca.
#   · no responde                   → arranca igual: un reinicio normal de prod con 운용3 caído no
#                                      puede dejar a las tiendas sin sistema. (Hueco conocido: si
#                                      운용3 está promovido Y no se lo alcanza, no se puede saber.)
#   · /etc/ventago/guardia-omitir   → arranca y borra el archivo (failback.sh lo pone justo antes
#                                      de levantar prod como original de nuevo). Para forzar a mano:
#                                      sudo touch /etc/ventago/guardia-omitir && sudo systemctl start …
#
# ★ Se habla con 운용3 por IP (--resolve) y con TLS verificado: el DNS puede apuntar a cualquiera
#   de los dos en medio de un cambio, y el certificado garantiza que contesta 운용3 de verdad.
# ★ Sin `set -e`: cualquier error inesperado debe terminar en «arranca» (exit 0), nunca en bloquear.
set -u

STBY_IP=${STBY_IP:-149.28.107.232}
HOST=newapi.coolsistema.com
OMITIR=${OMITIR:-/etc/ventago/guardia-omitir}
ENV_TG=${ENV_TG:-/var/lib/jenkins/workspace/api-new-coolsistema/.env}

log() { logger -t ventago-guardia -- "$*" 2>/dev/null; echo "ventago-guardia: $*" >&2; }

avisar() {
  local tok chat
  tok=$(grep -sE '^TELEGRAM_BOT_TOKEN=' "$ENV_TG" | head -1 | cut -d= -f2- | tr -d '"'"'"'')
  chat=$(grep -sE '^TELEGRAM_CHAT_ID=' "$ENV_TG" | head -1 | cut -d= -f2- | tr -d '"'"'"'')
  [ -n "$tok" ] && [ -n "$chat" ] || return 0
  curl -s --max-time 8 "https://api.telegram.org/bot${tok}/sendMessage" \
    --data-urlencode "chat_id=${chat}" --data-urlencode "text=$1" >/dev/null 2>&1 || true
}

if [ -f "$OMITIR" ]; then
  rm -f "$OMITIR"
  log "omitida una vez ($OMITIR) — arranco"
  exit 0
fi

for intento in 1 2 3; do
  resp=$(curl -s --max-time 5 --resolve "${HOST}:443:${STBY_IP}" "https://${HOST}/__ventago/estado" 2>/dev/null | head -c 200)
  case "$resp" in
    PROMOVIDO*)
      log "운용3 dice «${resp}» — NO arranco el Postgres de prod (sería un segundo original)."
      avisar "⛔ PROD (srv803182) quiso arrancar su Postgres pero 운용3 está PROMOVIDO (${resp}). No se arrancó: las tiendas siguen en 운용3. Para volver a prod usar failback.sh. Forzar (sólo si 운용3 ya no es el original): sudo touch ${OMITIR} && sudo systemctl start postgresql@18-ventago18"
      exit 1
      ;;
    STANDBY*)
      exit 0
      ;;
  esac
  sleep 2
done

log "운용3 no respondió (${STBY_IP}) — arranco igual (no bloquear un reinicio normal)"
exit 0
