#!/usr/bin/env bash
# [Phase 106] Google Play — AAB firmados del canal Play para todas las apps Android.
#
#   ./play-store/build-aab.sh                 # todas
#   ./play-store/build-aab.sh mobile-sales-app tienda-admin-app
#
# Canal Play = `-Pplay=true` (manifiesto sin REQUEST_INSTALL_PACKAGES) + `--dart-define=CANAL_PLAY=true`
# (sin autoactualización). El APK directo de siempre no cambia.
# Cada AAB se verifica: firmado con la clave de subida y SIN el permiso de instalar paquetes.
set -uo pipefail
cd "$(dirname "$0")/.."
RAIZ=$(pwd)
# /usr/bin/keytool es un stub sin JDK en macOS — usar el JDK que usa Flutter (flutter config jdk-dir)
if [ -z "${JAVA_HOME:-}" ]; then
  JAVA_HOME=$(flutter config --list 2>/dev/null | awk '/jdk-dir:/{print $2}')
  [ -d "${JAVA_HOME:-/nonexistent}" ] || JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
  export JAVA_HOME
fi
export PATH="$JAVA_HOME/bin:$PATH"
OUT="$RAIZ/play-store/out"
mkdir -p "$OUT"

FLUTTER_APPS=(mobile-sales-app tienda-admin-app despacho-app talleres-vendor-app ventago-admin-app)
ELEGIDAS=("$@")
[ ${#ELEGIDAS[@]} -eq 0 ] && ELEGIDAS=("${FLUTTER_APPS[@]}" wear-admin-app)

KEYPROPS="${ANDROID_KEY_PROPERTIES:-$HOME/android-keys/key.properties}"
[ -f "$KEYPROPS" ] || { echo "✗ falta $KEYPROPS (clave de subida)"; exit 1; }
ALIAS=$(grep -a '^keyAlias=' "$KEYPROPS" | cut -d= -f2)
STORE=$(grep -a '^storeFile=' "$KEYPROPS" | cut -d= -f2)
# huella de la clave de subida — cada AAB tiene que estar firmado con ESTA
HUELLA=$(keytool -list -v -keystore "$STORE" -alias "$ALIAS" \
          -storepass "$(grep -a '^storePassword=' "$KEYPROPS" | cut -d= -f2)" 2>/dev/null \
          | grep -a 'SHA256:' | head -1 | awk '{print $2}')
[ -n "$HUELLA" ] || { echo "✗ no pude leer la huella de la clave de subida"; exit 1; }

verificar() { # $1 = aab
  local aab="$1" ok=0
  # firma: el certificado del AAB es la clave de subida
  local h
  h=$(keytool -printcert -jarfile "$aab" 2>/dev/null | grep -a 'SHA256:' | head -1 | awk '{print $2}')
  if [ "$h" != "$HUELLA" ]; then echo "  ✗ firma: $h ≠ clave de subida"; ok=1; else echo "  ✓ firmado con la clave de subida"; fi
  # permiso: el manifiesto (protobuf) guarda los nombres como texto plano
  if unzip -p "$aab" base/manifest/AndroidManifest.xml | grep -aq 'REQUEST_INSTALL_PACKAGES'; then
    echo "  ✗ tiene REQUEST_INSTALL_PACKAGES (Play lo rechaza)"; ok=1
  else
    echo "  ✓ sin REQUEST_INSTALL_PACKAGES"
  fi
  return $ok
}

FALLAS=0
for app in "${ELEGIDAS[@]}"; do
  echo "━━ $app"
  if [ "$app" = "wear-admin-app" ]; then
    (cd wear-admin-app && ./gradlew -q bundleRelease) || { echo "  ✗ build"; FALLAS=$((FALLAS+1)); continue; }
    src=wear-admin-app/app/build/outputs/bundle/release/app-release.aab
    ver=$(grep -aoE 'versionName = "[^"]+"' wear-admin-app/app/build.gradle.kts | cut -d'"' -f2)
  else
    (cd "$app" && flutter build appbundle --release -Pplay=true --dart-define=CANAL_PLAY=true >/tmp/aab-$app.log 2>&1) \
      || { echo "  ✗ build (ver /tmp/aab-$app.log)"; FALLAS=$((FALLAS+1)); continue; }
    src="$app/build/app/outputs/bundle/release/app-release.aab"
    ver=$(grep -aE '^version:' "$app/pubspec.yaml" | awk '{print $2}')
  fi
  dst="$OUT/$app-$ver.aab"
  cp "$src" "$dst"
  echo "  → play-store/out/$(basename "$dst") ($(du -h "$dst" | cut -f1))"
  verificar "$dst" || FALLAS=$((FALLAS+1))
done

echo
[ $FALLAS -eq 0 ] && echo "✓ todo listo para subir" || { echo "✗ $FALLAS con problemas"; exit 1; }
