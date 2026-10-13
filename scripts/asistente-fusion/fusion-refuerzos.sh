#!/bin/bash
# Fusion nocturna de refuerzos del asistente (Phase 102 D-10/D-10b/D-12/D-17).
# Uso: fusion-refuerzos.sh [--dry-run] [--desde-json <archivo>] [--con-eval] [--probar-aviso <texto>]
#
# Sin errexit a proposito: cada paso comprueba su exit y llama a avisar_y_salir, asi un
# fallo no mata el script antes de que diga por que (memoria set-e-kills-the-guard).
# macOS: BSD sed/grep no conocen \s; nada de group+alternation en sed -E.
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
API="$RAIZ/api-ventago"
ESTADO="$HOME/.cache/ventago-asistente-fusion"
ENV_TG="$HOME/.config/ventago/asistente-fusion.env"
LOG="$HOME/Library/Logs/ventago-asistente-fusion.log"
mkdir -p "$ESTADO" "$(dirname "$LOG")" 2>/dev/null

DRY=0; DESDE_JSON=""; CON_EVAL=0; PROBAR_AVISO=0; TEXTO_AVISO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --desde-json) shift; DESDE_JSON="${1:-}" ;;
    --con-eval) CON_EVAL=1 ;;
    --probar-aviso) PROBAR_AVISO=1; shift; TEXTO_AVISO="${1:-prueba de aviso}" ;;
    *) echo "argumento desconocido: $1" >&2; exit 2 ;;
  esac
  shift
done

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG" >&2; }

escapar() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

enviar_telegram() {
  local texto="$1"
  if [ "$DRY" = 1 ]; then log "[dry-run] aviso Telegram NO enviado: $texto"; return 0; fi
  if [ ! -f "$ENV_TG" ]; then log "falta $ENV_TG; aviso solo al log: $texto"; return 1; fi
  # shellcheck disable=SC1090
  . "$ENV_TG"
  if [ -z "${TELEGRAM_PEDIDOS_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_PEDIDOS_CHAT_ID:-}" ]; then
    log "env Telegram incompleto; aviso solo al log: $texto"; return 1
  fi
  curl -fsS -m 20 "https://api.telegram.org/bot${TELEGRAM_PEDIDOS_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_PEDIDOS_CHAT_ID}" \
    --data-urlencode "parse_mode=HTML" \
    --data-urlencode "text=${texto}" >/dev/null
  local rc=$?
  [ $rc -ne 0 ] && log "curl Telegram fallo rc=$rc"
  return $rc
}

LOCKDIR="$ESTADO/lock"
ARCHIVOS=()
LIMPIAR=()
limpiar() {
  rmdir "$LOCKDIR" 2>/dev/null
  [ -n "${TUNEL_PID:-}" ] && kill "$TUNEL_PID" 2>/dev/null
  local f; for f in "${LIMPIAR[@]:-}"; do [ -n "$f" ] && rm -f "$f"; done
}
trap limpiar EXIT

revertir() {
  # Solo los archivos EXACTOS que reporto el CLI.
  local f
  for f in "${ARCHIVOS[@]:-}"; do
    [ -n "$f" ] && git -C "$API" checkout -- "$f"
  done
}

marcar_hoy() { [ "$DRY" = 1 ] || : > "$ESTADO/ran-$(TZ=America/Argentina/Buenos_Aires date +%Y%m%d)"; }

avisar_y_salir() {
  # $1 = motivo ; $2 = (opcional) "marcar" si la corrida proceso refuerzos
  local motivo="$1"
  log "ABORTA: $motivo"
  [ "${2:-}" = "marcar" ] && marcar_hoy
  enviar_telegram "<b>Fusion de refuerzos: ERROR</b>
$(escapar "$motivo")"
  exit 1
}

# --- --probar-aviso: solo manda un aviso de prueba (lo usa el plan 13)
if [ "$PROBAR_AVISO" = 1 ]; then
  enviar_telegram "<b>Fusion de refuerzos: prueba</b>
$(escapar "$TEXTO_AVISO")"
  exit $?
fi

# --- 0. lock + marca diaria
if ! mkdir "$LOCKDIR" 2>/dev/null; then log "otra corrida en curso (lock); sale"; trap - EXIT; exit 0; fi
HOY="$(TZ=America/Argentina/Buenos_Aires date +%Y%m%d)"
if [ "$DRY" = 0 ] && [ -f "$ESTADO/ran-$HOY" ]; then log "ya corrio hoy ($HOY); sale"; exit 0; fi

# --- 1. hora ART (FORZAR_HORA solo cuenta junto con --dry-run)
if [ "$DRY" = 1 ] && [ -n "${FORZAR_HORA:-}" ]; then
  HORA="$FORZAR_HORA"
else
  HORA="$(TZ=America/Argentina/Buenos_Aires date +%H)"
fi
HORA=$((10#$HORA))
if [ "$HORA" -lt 16 ]; then log "hora ART $HORA < 16: nada que hacer (espera a las 22h)"; exit 0; fi

# --- 2. refuerzos activos
JSON="$(mktemp "$ESTADO/refuerzos.XXXXXX")"
LIMPIAR+=("$JSON")
if [ -n "$DESDE_JSON" ]; then
  cp "$DESDE_JSON" "$JSON" || avisar_y_salir "no se pudo leer $DESDE_JSON"
else
  ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -Atc \"SELECT coalesce(json_agg(r),'[]') FROM (SELECT id, titulo, contenido_es, archivo_destino, slug FROM knowledge_refuerzos WHERE estado='activo' ORDER BY id) r\"" > "$JSON"
  rc=$?
  [ $rc -ne 0 ] && avisar_y_salir "consulta de refuerzos fallo (ssh rc=$rc)"
fi
NFILAS="$(node -e 'const a=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));console.log(a.length)' "$JSON" 2>/dev/null)"
if [ -z "$NFILAS" ]; then avisar_y_salir "JSON de refuerzos ilegible"; fi
if [ "$NFILAS" = 0 ]; then log "0 refuerzos activos; sale en silencio"; exit 0; fi

# --- 3. repo en main y manuales/ limpio
RAMA="$(git -C "$API" rev-parse --abbrev-ref HEAD)"
[ "$RAMA" = "main" ] || avisar_y_salir "rama actual $RAMA, no main" marcar
if [ -n "$(git -C "$API" status --porcelain -- manuales/)" ]; then
  avisar_y_salir "manuales/ tiene cambios sin commitear; no se mezcla con WIP" marcar
fi
if [ "$DRY" = 0 ]; then
  git -C "$API" pull --ff-only || avisar_y_salir "git pull --ff-only fallo" marcar
fi

# --- 4. fusion
SALIDA="$(cd "$API" && npx ts-node src/app/chat/knowledge/fusion-refuerzos.cli.ts "$JSON" --manuales-dir=manuales)"
rc=$?
[ $rc -ne 0 ] && avisar_y_salir "CLI de fusion fallo rc=$rc" marcar
ARCHIVOS_TXT="$(printf '%s' "$SALIDA" | node -e 'const o=JSON.parse(require("fs").readFileSync(0,"utf8"));console.log(o.archivos.join("\n"))')"
IDS="$(printf '%s' "$SALIDA" | node -e 'const o=JSON.parse(require("fs").readFileSync(0,"utf8"));console.log(o.agregados.join(","))')"
MOTIVOS="$(printf '%s' "$SALIDA" | node -e 'const o=JSON.parse(require("fs").readFileSync(0,"utf8"));console.log(o.omitidos.map(x=>x.id+":"+x.motivo).join(" "))')"
while IFS= read -r l; do [ -n "$l" ] && ARCHIVOS+=("$l"); done <<EOT
$ARCHIVOS_TXT
EOT
if [ -z "$IDS" ]; then avisar_y_salir "nada para fusionar ($MOTIVOS)" marcar; fi
log "fusionados ids=$IDS archivos=${ARCHIVOS[*]} omitidos=$MOTIVOS"

# --- 5. jest
(cd "$API" && npx jest src/app/chat/eval src/app/chat/knowledge --maxWorkers=1 --workerIdleMemoryLimit=800MB)
rc=$?
if [ $rc -ne 0 ]; then revertir; avisar_y_salir "jest fallo (rc=$rc); fusion revertida, ids=$IDS" marcar; fi

# --- 6. D-12 (siempre fuera de --dry-run; en --dry-run solo con --con-eval)
if [ "$DRY" = 0 ] || [ "$CON_EVAL" = 1 ]; then
  MODELO="$(ssh jhkim-server "docker inspect api_ventago --format '{{range .Config.Env}}{{println .}}{{end}}'" 2>/dev/null | grep '^OLLAMA_MODEL=' | head -1 | cut -d= -f2-)"
  [ -n "$MODELO" ] || { revertir; avisar_y_salir "D-12: no se pudo leer OLLAMA_MODEL de produccion" marcar; }
  ssh -N -L 11434:127.0.0.1:11434 root@74.208.60.137 &
  TUNEL_PID=$!
  sleep 3
  (cd "$API" && OLLAMA_URL=http://localhost:11434 OLLAMA_MODEL="$MODELO" npx ts-node src/app/chat/eval/evaluar-asistente.ts --solo=rechazo)
  rc=$?
  kill "$TUNEL_PID" 2>/dev/null; TUNEL_PID=""
  if [ $rc -ne 0 ]; then
    revertir
    avisar_y_salir "D-12: inventó en preguntas que no debe contestar (eval rc=$rc); ids=$IDS" marcar
  fi
fi

# --- 7. dry-run: mostrar diff y salir
if [ "$DRY" = 1 ]; then
  git -C "$API" diff -- "${ARCHIVOS[@]}"
  log "[dry-run] fin; sin commit, sin push, sin Telegram"
  exit 0
fi

# --- 8. commit
RAMA="$(git -C "$API" rev-parse --abbrev-ref HEAD)"
[ "$RAMA" = "main" ] || { revertir; avisar_y_salir "rama cambio a $RAMA antes del commit" marcar; }
git -C "$API" add -- "${ARCHIVOS[@]}" || { revertir; avisar_y_salir "git add fallo" marcar; }
STAGED="$(git -C "$API" diff --cached --name-only | sort)"
ESPERADO="$(printf '%s\n' "${ARCHIVOS[@]}" | sort)"
if [ "$STAGED" != "$ESPERADO" ]; then
  avisar_y_salir "el index tiene archivos ajenos a la fusion; no se commitea" marcar
fi
git -C "$API" commit -m "docs(manuales): fusionar refuerzos $IDS

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
rc=$?
[ $rc -ne 0 ] && avisar_y_salir "commit bloqueado (hook de verificacion rc=$rc); sin push" marcar
SHA="$(git -C "$API" rev-parse HEAD)"
marcar_hoy

# --- 9. push (>=16h ART, o <=5 usuarios activos) y solo el commit de fusion
HORA="$(TZ=America/Argentina/Buenos_Aires date +%H)"; HORA=$((10#$HORA))
if [ "$HORA" -lt 16 ]; then
  ACTIVOS="$(ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -Atc \"select count(distinct user_id) from active_sessions where last_activity_at > now() - interval '15 minutes'\"" 2>/dev/null)"
  if ! [ "${ACTIVOS:-99}" -le 5 ] 2>/dev/null; then
    avisar_y_salir "antes de las 16h con ${ACTIVOS:-?} usuarios activos: commit ${SHA:0:8} queda local" 
  fi
fi
git -C "$API" fetch origin main || avisar_y_salir "fetch origin main fallo; commit ${SHA:0:8} queda local"
RANGO="$(git -C "$API" log --format=%H origin/main..HEAD)"
if [ "$RANGO" != "$SHA" ]; then
  avisar_y_salir "push abortado: origin/main..HEAD contiene commits ajenos a la fusión (commit ${SHA:0:8} queda local para revisión)"
fi
git -C "$API" push origin main || avisar_y_salir "push fallo; commit ${SHA:0:8} queda local"

# --- 10. build por SHA y retiro por el sync (plan 10)
BUILD=""; RESULT=""
for _ in $(seq 1 30); do
  BUILD="$(ssh jhkim-server "grep -l '$SHA' /var/lib/jenkins/jobs/api-new-coolsistema/builds/*/log 2>/dev/null | sed -e 's|.*/builds/||' -e 's|/log||' | sort -n | tail -1")"
  if [ -n "$BUILD" ]; then
    RESULT="$(ssh jhkim-server "sed -n 's|.*<result>\\(.*\\)</result>.*|\\1|p' /var/lib/jenkins/jobs/api-new-coolsistema/builds/$BUILD/build.xml 2>/dev/null")"
    [ -n "$RESULT" ] && break
  fi
  sleep 60
done
[ "$RESULT" = "SUCCESS" ] || avisar_y_salir "build ${BUILD:-?} resultado '${RESULT:-sin resultado}' para ${SHA:0:8}; ids=$IDS"

NIDS="$(printf '%s' "$IDS" | awk -F, '{print NF}')"
RETIRADOS=0
for _ in $(seq 1 15); do
  RETIRADOS="$(ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -Atc \"SELECT count(*) FROM knowledge_refuerzos WHERE id IN ($IDS) AND estado='fusionado'\"" 2>/dev/null)"
  [ "${RETIRADOS:-0}" = "$NIDS" ] && break
  sleep 60
done

# --- 11. aviso final
TITULOS="$(node -e 'const a=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));const ids=process.argv[2].split(",").map(Number);console.log(a.filter(r=>ids.includes(r.id)).map(r=>"- "+r.titulo).join("\n"))' "$JSON" "$IDS")"
ESTADO_TXT="OK"; [ "${RETIRADOS:-0}" = "$NIDS" ] || ESTADO_TXT="OK con retiro incompleto"
enviar_telegram "<b>Fusion de refuerzos: $ESTADO_TXT</b>
IDs: $(escapar "$IDS") ($NIDS)
$(escapar "$TITULOS")
Archivos: $(escapar "${ARCHIVOS[*]}")
SHA: ${SHA:0:8} · build $(escapar "$BUILD")
Retirados ${RETIRADOS:-0}/$NIDS"
exit 0
