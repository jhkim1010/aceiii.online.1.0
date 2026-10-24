#!/usr/bin/env bash
# [2026-10-24] Publica una versión de Guardia (edge-agent) para la actualización desde la web.
#
# Uso (desde la raíz del monorepo o desde edge-agent/):
#   edge-agent/publicar-guardia.sh ["notas del release"]
#
# Sube a GitHub Releases (jhkim1010/ventago-downloads, público), tag `guardia-latest`:
#   guardia-<version>.tgz   y DESPUÉS   version.json {version, url, sha256, notas}
# El orden importa (igual que scripts/publicar-apk.sh): version.json nunca apunta a un paquete
# que todavía no está, y el nombre lleva la versión (inmutable) — si falla la subida del json,
# el feed viejo sigue apuntando a SU paquete con SU hash.
#
# El paquete es `git archive` del commit (HEAD:edge-agent) con prefijo package/ — sólo lo
# commiteado: nunca node_modules, config.json (contraseña de PG + agentKey) ni logs/.
#
# ★ Se niega a publicar si:
#   · hay cambios sin commitear en edge-agent/ (el paquete no sería lo que se probó)
#   · la versión de package.json no es mayor que la publicada (Guardia no la tomaría)
set -euo pipefail

NOTAS="${1:-}"
REPO="jhkim1010/ventago-downloads"
TAG="guardia-latest"

raiz="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$raiz"

if ! git diff --quiet HEAD -- edge-agent || [[ -n "$(git ls-files --others --exclude-standard edge-agent)" ]]; then
  echo "ERROR: hay cambios sin commitear en edge-agent/ — commiteá primero." >&2
  exit 1
fi

version="$(git show HEAD:edge-agent/package.json | python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])')"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "ERROR: versión inválida en package.json: $version" >&2; exit 1; }

feed="https://github.com/$REPO/releases/download/$TAG/version.json"
# ★ «?t=»: sin eso la CDN de GitHub devuelve el version.json anterior durante minutos
publicado="$(curl -fsSL "$feed?t=$(date +%s)" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("version",""))' 2>/dev/null || true)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
ASSET="guardia-$version.tgz"
git archive --format=tar --prefix=package/ HEAD:edge-agent | gzip -n -9 > "$tmp/$ASSET"
sha="$(shasum -a 256 "$tmp/$ASSET" | awk '{print $1}')"

if [[ -n "$publicado" ]]; then
  mayor="$(python3 - "$version" "$publicado" <<'PY'
import sys
a, b = (tuple(int(x) for x in v.split('-')[0].split('.')) for v in sys.argv[1:])
print('si' if a > b else ('igual' if a == b else 'no'))
PY
)"
  if [[ "$mayor" == "igual" ]]; then
    echo "✔ v$version ya estaba publicada — sin cambios (si cambiaste código, subí la versión)"
    exit 0
  fi
  [[ "$mayor" == "si" ]] || { echo "ERROR: v$version no es mayor que la publicada ($publicado)." >&2; exit 1; }
fi

url="https://github.com/$REPO/releases/download/$TAG/$ASSET"
python3 - "$tmp/version.json" "$version" "$url" "$sha" "$NOTAS" <<'PY'
import json, sys
p, version, url, sha, notas = sys.argv[1:]
json.dump({"version": version, "url": url, "sha256": sha, "notas": notas},
          open(p, "w"), ensure_ascii=False, indent=2)
PY

gh release view "$TAG" -R "$REPO" >/dev/null 2>&1 \
  || gh release create "$TAG" -R "$REPO" --title "$TAG" --notes "Guardia — actualización desde la web (version.json + paquete)"
gh release upload "$TAG" "$tmp/$ASSET" -R "$REPO"            # sin --clobber: el paquete es inmutable
gh release upload "$TAG" "$tmp/version.json" -R "$REPO" --clobber

# comprobar lo que realmente quedó publicado (recién subido puede tardar: reintentar)
vuelta=""
for _ in 1 2 3 4 5 6; do
  vuelta="$(curl -fsSL "$feed?t=$(date +%s)" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("sha256",""))' 2>/dev/null || true)"
  [[ "$vuelta" == "$sha" ]] && break
  sleep 5
done
[[ "$vuelta" == "$sha" ]] || { echo "ERROR: el feed publicado no tiene el sha256 esperado" >&2; exit 1; }
echo "✔ Publicada Guardia v$version → $feed"
