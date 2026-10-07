#!/usr/bin/env bash
# [2026-10-06] Actualización dentro de la app — publica un APK para que las apps lo ofrezcan.
#
# Uso (lo llaman mobile-sales-app/build-apk.sh y tienda-admin-app/build-apk.sh):
#   scripts/publicar-apk.sh <apk> <tag-release> <nombre-asset.apk> <cert-sha256-esperado> ["notas"]
#
# Sube a GitHub Releases (jhkim1010/ventago-downloads, público):
#   <tag>/<nombre-asset>-<versionCode>.apk   y después   <tag>/version.json
# El orden importa: version.json nunca apunta a un APK que todavía no está. Y el APK lleva el
# versionCode en el nombre (inmutable): si la subida del json falla, el feed viejo sigue
# apuntando a SU APK con SU hash — nunca a un archivo reemplazado (codex 014).
#
# ★ Se niega a publicar si:
#   · el APK no está firmado con el certificado esperado — Android rechaza instalar una
#     actualización con otra clave, así que publicarlo sólo produce «App no instalada»
#     en cada teléfono.
#   · el versionCode no es mayor que el publicado — la app no lo ofrecería.
set -euo pipefail

APK="$1"
TAG="$2"
ASSET="$3"
CERT_ESPERADO="$4"
NOTAS="${5:-}"
REPO="jhkim1010/ventago-downloads"

BT="${ANDROID_BUILD_TOOLS:-/opt/homebrew/share/android-commandlinetools/build-tools/36.0.0}"
export JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"

[[ -f "$APK" ]] || { echo "ERROR: no existe el APK: $APK" >&2; exit 1; }

# ★ head/grep -m1 cortan la tubería: con pipefail, aapt2/apksigner mueren por SIGPIPE (141)
badging="$("$BT/aapt2" dump badging "$APK" | sed -n 1p)"
code="$(sed -E "s/.*versionCode='([0-9]+)'.*/\1/" <<<"$badging")"
name="$(sed -E "s/.*versionName='([^']*)'.*/\1/" <<<"$badging")"
[[ "$code" =~ ^[0-9]+$ ]] || { echo "ERROR: no pude leer versionCode del APK" >&2; exit 1; }

cert="$("$BT/apksigner" verify --print-certs "$APK" | awk '/certificate SHA-256 digest/ && !f {print $NF; f=1}')"
if [[ "$cert" != "$CERT_ESPERADO"* ]]; then
  echo "ERROR: el APK está firmado con ${cert:0:16}…, se esperaba ${CERT_ESPERADO:0:16}…" >&2
  echo "       Los teléfonos no podrían instalar esta actualización. No se publica." >&2
  exit 1
fi

feed="https://github.com/$REPO/releases/download/$TAG/version.json"
# [2026-10-07] ★ con «?t=» : sin eso la CDN de GitHub devuelve el version.json anterior durante
#   minutos — la comprobación final fallaba («dice versionCode=2, no 3») aunque estuviera publicado
feed_actual="$(curl -fsSL "$feed?t=$(date +%s)" 2>/dev/null || true)"
publicado="$(sed -nE 's/.*"versionCode": *([0-9]+).*/\1/p' <<<"$feed_actual")"
# el mismo APK ya publicado (p.ej. se re-ejecuta build-apk.sh --skip-build para las copias) → nada que hacer
if [[ -n "$publicado" && "$code" == "$publicado" ]] \
   && grep -q "\"sha256\": *\"$(shasum -a 256 "$APK" | awk '{print $1}')\"" <<<"$feed_actual"; then
  echo "✔ v$name (versionCode $code) ya estaba publicado — sin cambios"
  exit 0
fi
if [[ -n "$publicado" && "$code" -le "$publicado" ]]; then
  echo "ERROR: versionCode $code no es mayor que el publicado ($publicado). Subí la versión en pubspec.yaml." >&2
  exit 1
fi

sha="$(shasum -a 256 "$APK" | awk '{print $1}')"
ASSET="${ASSET%.apk}-$code.apk"
url="https://github.com/$REPO/releases/download/$TAG/$ASSET"

tmp="$(mktemp -d)"
cp "$APK" "$tmp/$ASSET"
python3 - "$tmp/version.json" "$code" "$name" "$url" "$sha" "$NOTAS" <<'EOF'
import json, sys
p, code, name, url, sha, notas = sys.argv[1:]
json.dump({"versionCode": int(code), "versionName": name, "apk": url, "sha256": sha, "notas": notas},
          open(p, "w"), ensure_ascii=False, indent=2)
EOF

gh release view "$TAG" -R "$REPO" >/dev/null 2>&1 \
  || gh release create "$TAG" -R "$REPO" --title "$TAG" --notes "Actualización dentro de la app (version.json + APK)"
gh release upload "$TAG" "$tmp/$ASSET" -R "$REPO" --clobber
gh release upload "$TAG" "$tmp/version.json" -R "$REPO" --clobber

# comprobar lo que realmente quedó publicado
# (recién subido GitHub puede tardar unos segundos en servirlo: 404 → reintentar)
vuelta=""
for _ in 1 2 3 4 5 6; do
  vuelta="$(curl -fsSL "$feed?t=$(date +%s)" 2>/dev/null | sed -nE 's/.*"versionCode": *([0-9]+).*/\1/p' || true)"
  [[ "$vuelta" == "$code" ]] && break
  sleep 5
done
[[ "$vuelta" == "$code" ]] || { echo "ERROR: el feed publicado dice versionCode=$vuelta, no $code" >&2; exit 1; }
echo "✔ Publicado v$name (versionCode $code) → $feed"
