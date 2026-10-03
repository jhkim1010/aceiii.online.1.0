#!/bin/bash
# VentaGO Pedidos — instala la app en ESTA Mac sin electron-builder.
#
# ★ No usar electron-builder localmente: en este monorepo poda node_modules de la raíz
#   (147 paquetes desaparecieron el 2026-09-29). Acá sólo se copia el Electron ya instalado
#   y se le pone la app adentro (Contents/Resources/app) — no toca node_modules.
# ★ Los instaladores para distribuir (Windows/mac) salen de GitHub Actions
#   (tag pedidos-app-v*, .github/workflows/build-pedidos-app.yml).
set -euo pipefail

AQUI="$(cd "$(dirname "$0")/.." && pwd)"
RAIZ="$(cd "$AQUI/.." && pwd)"
ELECTRON_APP="$RAIZ/node_modules/electron/dist/Electron.app"
DESTINO="${1:-/Applications}/VentaGO Pedidos.app"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[ -x "$ELECTRON_APP/Contents/MacOS/Electron" ] || { echo "No encuentro Electron en $ELECTRON_APP" >&2; exit 1; }

VERSION="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$AQUI/package.json" | head -1)"
APP="$TMP/VentaGO Pedidos.app"
ditto "$ELECTRON_APP" "$APP"

# la app
rm -f "$APP/Contents/Resources/default_app.asar"
mkdir -p "$APP/Contents/Resources/app"
for f in package.json main.js preload.js; do cp "$AQUI/$f" "$APP/Contents/Resources/app/"; done
ditto "$AQUI/renderer" "$APP/Contents/Resources/app/renderer"
ditto "$AQUI/src" "$APP/Contents/Resources/app/src"
ditto "$AQUI/assets" "$APP/Contents/Resources/app/assets"

# ícono
ICONSET="$TMP/icon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 64 128 256 512; do
  sips -z $s $s "$AQUI/assets/icon-512.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2)); [ $d -le 512 ] && sips -z $d $d "$AQUI/assets/icon-512.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/electron.icns"

# nombre / id
PL="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName VentaGO Pedidos" "$PL"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName VentaGO Pedidos" "$PL" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string VentaGO Pedidos" "$PL"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.coolsistema.ventago-pedidos" "$PL"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PL"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$PL"

# firma ad-hoc (cambió el bundle: sin esto macOS lo rechaza)
codesign --force --deep --sign - "$APP" >/dev/null 2>&1

# reemplazar la instalada (cerrándola si está abierta)
pkill -f "VentaGO Pedidos.app/Contents/MacOS" 2>/dev/null || true
sleep 1
rm -rf "$DESTINO"
ditto "$APP" "$DESTINO"
xattr -dr com.apple.quarantine "$DESTINO" 2>/dev/null || true
echo "Instalada: $DESTINO (v$VERSION)"
