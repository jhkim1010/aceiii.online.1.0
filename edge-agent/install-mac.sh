#!/usr/bin/env bash
# Ventago Guardia (servidor local de la sucursal; nombre interno edge-agent) — instalación asistida (macOS)
# Equivalente a install.ps1 (Windows). [2026-10-24]
#
# Qué hace (6 pasos, igual que en Windows):
#   1. Verifica requisitos (Node >= 18, PostgreSQL de Homebrew) y dice qué falta si falta.
#   2. Crea la base local `ventago_edge` si no existe (si existe NO se toca: espejo y outbox se conservan).
#   3. npm install --omit=dev
#   4. Escribe config.json pidiendo la agentKey (chmod 600: lleva la contraseña de PG y la agentKey).
#   5. Registra un LaunchAgent (~/Library/LaunchAgents/com.ventago.guardia.plist):
#      RunAtLoad + KeepAlive + ThrottleInterval 60 s → arranca al iniciar sesión y se levanta sola si se cae.
#   6. Arranca y verifica http://127.0.0.1:<puerto>/api/health
#
# Qué NO hace (a propósito): NO instala Node ni PostgreSQL — dice exactamente qué falta.
#
# Uso (dentro de la carpeta edge-agent):
#   ./install-mac.sh                       instalar / volver a correr (idempotente)
#   ./install-mac.sh --reconfigurar        reescribir config.json
#   ./install-mac.sh --agent-key vg_pr_…   sin preguntar
#   ./install-mac.sh --pg-user U --pg-password P --puerto 5010
#   ./install-mac.sh --solo-plist <dir>    sólo escribe el plist en <dir> (no toca nada más; para revisar)
#   ./install-mac.sh --desinstalar         quita el LaunchAgent (no borra la base ni config.json)
#
# ★ La actualización desde la web también funciona acá: Guardia cambia de versión dentro de esta
#   carpeta y su supervisor (src/index.js) la relanza; si el proceso entero sale, KeepAlive lo levanta.
set -euo pipefail

RAIZ="$(cd "$(dirname "$0")" && pwd)"
ETIQUETA="com.ventago.guardia"
PLIST="$HOME/Library/LaunchAgents/$ETIQUETA.plist"
RECONF=0
AGENT_KEY=""
PG_USER="${USER:-postgres}"
PG_PASSWORD=""
PUERTO=5010
SOLO_PLIST=""
DESINSTALAR=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --reconfigurar) RECONF=1 ;;
    --agent-key) AGENT_KEY="$2"; shift ;;
    --pg-user) PG_USER="$2"; shift ;;
    --pg-password) PG_PASSWORD="$2"; shift ;;
    --puerto) PUERTO="$2"; shift ;;
    --solo-plist) SOLO_PLIST="$2"; shift ;;
    --desinstalar) DESINSTALAR=1 ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "opción desconocida: $1" >&2; exit 2 ;;
  esac
  shift
done

titulo() { printf '\n\033[36m== %s ==\033[0m\n' "$1"; }
ok()     { printf '  \033[32m[OK]\033[0m %s\n' "$1"; }
aviso()  { printf '  \033[33m[!]\033[0m  %s\n' "$1"; }
fallo()  { printf '  \033[31m[X]\033[0m  %s\n' "$1"; }

escribir_plist() { # $1 = destino, $2 = ruta de node
  local destino="$1" node_bin="$2"
  mkdir -p "$(dirname "$destino")"
  cat > "$destino" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$ETIQUETA</string>
  <key>ProgramArguments</key>
  <array>
    <string>$node_bin</string>
    <string>src/index.js</string>
  </array>
  <key>WorkingDirectory</key><string>$RAIZ</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>$(dirname "$node_bin"):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>60</integer>
  <key>StandardOutPath</key><string>$RAIZ/logs/launchd.out.log</string>
  <key>StandardErrorPath</key><string>$RAIZ/logs/launchd.err.log</string>
</dict>
</plist>
PLIST
}

# ── modos que no instalan ──────────────────────────────────────────────────
if [[ -n "$SOLO_PLIST" ]]; then
  node_bin="$(command -v node || echo /opt/homebrew/bin/node)"
  escribir_plist "$SOLO_PLIST/$ETIQUETA.plist" "$node_bin"
  echo "$SOLO_PLIST/$ETIQUETA.plist"
  exit 0
fi

if [[ $DESINSTALAR -eq 1 ]]; then
  launchctl bootout "gui/$(id -u)/$ETIQUETA" 2>/dev/null || true
  rm -f "$PLIST"
  ok "LaunchAgent quitado (la base ventago_edge y config.json quedan como estaban)"
  exit 0
fi

# ── 1. Requisitos ──────────────────────────────────────────────────────────
titulo "1/6  Requisitos"
faltan=()
if ! command -v node >/dev/null; then
  faltan+=("Node.js 18 o superior  ->  brew install node   (o https://nodejs.org/en/download)")
else
  v="$(node --version | sed 's/^v//')"
  if (( ${v%%.*} < 18 )); then faltan+=("Node.js 18+ (tiene $v)  ->  brew upgrade node"); else ok "Node $v"; fi
fi
if ! command -v psql >/dev/null; then
  # Homebrew instala postgresql@NN «keg-only»: psql no queda en el PATH
  cand="$(ls -d /opt/homebrew/opt/postgresql@*/bin /usr/local/opt/postgresql@*/bin 2>/dev/null | sort -V | tail -1 || true)"
  if [[ -n "$cand" ]]; then export PATH="$cand:$PATH"; ok "PostgreSQL encontrado en $cand (agregado al PATH de esta sesión)"; fi
fi
if ! command -v psql >/dev/null; then
  faltan+=("PostgreSQL 14+  ->  brew install postgresql@16 && brew services start postgresql@16")
else
  ok "psql $(psql --version | awk '{print $3}')"
fi
if (( ${#faltan[@]} > 0 )); then
  fallo "Faltan requisitos. Instálelos y vuelva a correr este script:"
  printf '       - %s\n' "${faltan[@]}"
  exit 1
fi

# ── 2. Base local ──────────────────────────────────────────────────────────
titulo "2/6  Base de datos local (ventago_edge)"
export PGPASSWORD="$PG_PASSWORD"
if ! existe="$(psql -U "$PG_USER" -h 127.0.0.1 -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='ventago_edge'" 2>/dev/null)"; then
  fallo "No se pudo conectar a PostgreSQL como '$PG_USER'. ¿Está corriendo? (brew services list) ¿Usuario/contraseña? (--pg-user/--pg-password)"
  exit 1
fi
if [[ "$existe" == "1" ]]; then
  ok "ventago_edge ya existe (no se toca — el espejo y la outbox se conservan)"
else
  psql -U "$PG_USER" -h 127.0.0.1 -d postgres -c "CREATE DATABASE ventago_edge" >/dev/null
  ok "ventago_edge creada"
fi

# ── 3. Dependencias ────────────────────────────────────────────────────────
titulo "3/6  Dependencias (npm install)"
(cd "$RAIZ" && npm install --omit=dev --no-audit --no-fund >/dev/null 2>&1) || { fallo "npm install falló"; exit 1; }
ok "dependencias instaladas"

# ── 4. config.json ─────────────────────────────────────────────────────────
titulo "4/6  Configuración"
CFG="$RAIZ/config.json"
if [[ -f "$CFG" && $RECONF -eq 0 ]]; then
  ok "config.json ya existe — no se toca (use --reconfigurar para reescribirlo)"
else
  if [[ -z "$AGENT_KEY" ]]; then
    echo "  La agentKey se obtiene en Ventago: Sucursales -> Impresoras -> agregar agente tipo Guardia ('edge')."
    read -r -p "  agentKey: " AGENT_KEY
  fi
  if (( ${#AGENT_KEY} < 10 )); then fallo "agentKey inválida"; exit 1; fi
  umask 077
  node - "$CFG" "$AGENT_KEY" "$PUERTO" "$PG_USER" "$PG_PASSWORD" <<'JS'
const [p, agentKey, port, user, password] = process.argv.slice(2);
const cfg = {
  cloudApiUrl: 'https://newapi.coolsistema.com/api',
  agentKey,
  port: Number(port),
  localDb: { host: '127.0.0.1', port: 5432, database: 'ventago_edge', user, password },
  pullIntervalMs: 300000,
  stockIntervalMs: 60000,
  pruneIntervalMs: 3600000,
  healthProbeIntervalMs: 15000,
  pushIntervalMs: 20000,
  logLevel: 'info',
};
require('fs').writeFileSync(p, JSON.stringify(cfg, null, 2));
JS
  # La config lleva la contraseña de PG y la agentKey — que no la lea cualquiera.
  chmod 600 "$CFG"
  ok "config.json escrito (chmod 600)"
fi

# ── 5. Arranque automático ─────────────────────────────────────────────────
titulo "5/6  Arranque automático (launchd)"
# ★ Sin esto Guardia NO vuelve sola después de reiniciar ni después de caerse.
mkdir -p "$RAIZ/logs"
escribir_plist "$PLIST" "$(command -v node)"
plutil -lint "$PLIST" >/dev/null || { fallo "plist inválido: $PLIST"; exit 1; }
launchctl bootout "gui/$(id -u)/$ETIQUETA" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
ok "LaunchAgent '$ETIQUETA' registrado (arranca al iniciar sesión, se relanza si se cae — cada 60 s como máximo)"

# ── 6. Arrancar y verificar ────────────────────────────────────────────────
titulo "6/6  Arranque y verificación"
launchctl kickstart -k "gui/$(id -u)/$ETIQUETA" >/dev/null 2>&1 || true
sleep 6
if salud="$(curl -fsS --max-time 10 "http://127.0.0.1:$PUERTO/api/health")"; then
  ok "agente respondiendo en el puerto $PUERTO"
  echo "       $salud"
  if ! grep -q '"cloudOnline":true' <<<"$salud"; then
    aviso "El agente arrancó pero NO ve la nube. Revise internet y la agentKey."
    aviso "Un 401 en el log significa agentKey incorrecta (no es problema de red)."
  fi
else
  fallo "El agente no respondió en http://127.0.0.1:$PUERTO/api/health"
  echo "       Revise el log: $RAIZ/logs/edge-agent-$(date +%F).log y $RAIZ/logs/launchd.err.log"
  exit 1
fi

echo
printf '\033[32mListo.\033[0m\n'
echo "  Estado:    http://127.0.0.1:$PUERTO/api/edge/status"
echo "  Log:       $RAIZ/logs/"
echo "  Detener:   launchctl bootout gui/\$(id -u)/$ETIQUETA"
echo "  Arrancar:  launchctl bootstrap gui/\$(id -u) $PLIST"
echo "  Reiniciar: launchctl kickstart -k gui/\$(id -u)/$ETIQUETA"
echo "  Quitar:    ./install-mac.sh --desinstalar"
