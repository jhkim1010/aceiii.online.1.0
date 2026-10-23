#!/usr/bin/env bash
# Copia los instaladores de un release de agente (GitHub ventago-downloads) a la carpeta de
# descargas de Dropbox — pedido del usuario 2026-10-23: «항상 올리도록».
#
# Uso: scripts/agentes-a-dropbox.sh print-agent-v1.2.24 [zebra-agent-v1.0.44 ...]
# Nombre en Dropbox: <archivo>-v<versión>.<ext> (como los .apk de al lado, cada versión queda).
set -euo pipefail

DESTINO="${DROPBOX_DESCARGAS:-$HOME/Dropbox/ACE_3_uversion/app herramientas download}"
REPO="jhkim1010/ventago-downloads"

[ $# -ge 1 ] || { echo "uso: $0 <tag> [tag...]" >&2; exit 2; }
[ -d "$DESTINO" ] || { echo "no existe: $DESTINO" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

for TAG in "$@"; do
  VERSION="${TAG##*-v}"
  mkdir -p "$TMP/$TAG"
  gh release download "$TAG" -R "$REPO" -D "$TMP/$TAG" --clobber
  for F in "$TMP/$TAG"/*; do
    BASE=$(basename "$F")
    NOMBRE="${BASE%.*}-v${VERSION}.${BASE##*.}"
    cp "$F" "$DESTINO/$NOMBRE"
    echo "✓ $NOMBRE ($(du -h "$F" | cut -f1))"
  done
done
