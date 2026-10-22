#!/usr/bin/env bash
# [2026-10-22] Mac → STAGE (운용3). Prueba un commit ANTES de subirlo a producción.
#   uso: scripts/stage/deploy.sh [api|app|ambos] [commit-api] [commit-app]   (por defecto: ambos, HEAD)
#   No pasa por GitHub: manda el árbol del commit (git archive) y construye allá.
# ★ La app se construye con la API de stage: se reemplaza newapi.coolsistema.com → stageapi en la
#   copia (código de producción intacto).
set -euo pipefail
cd "$(dirname "$0")/../.."
QUE=${1:-ambos}; CA=${2:-HEAD}; CP=${3:-HEAD}
H=ventago-standby
enviar(){ # repo commit
  local repo=$1 c=$2 sha; sha=$(git -C "$repo" rev-parse --short "$c")
  echo "→ $repo @ $sha"
  git -C "$repo" archive --format=tar "$c" | ssh "$H" "sudo rm -rf /opt/stage/src/$repo && sudo mkdir -p /opt/stage/src/$repo && sudo tar -x -C /opt/stage/src/$repo && echo $sha | sudo tee /opt/stage/src/$repo/.stage-commit >/dev/null"
}
if [ "$QUE" != app ]; then
  enviar api-ventago "$CA"
  # 운용3 tiene 8 GB: el heap por defecto de node no alcanza para `nest build` (exit 134). Sólo en la
  #   copia de stage se agrega NODE_OPTIONS a la etapa builder; el Dockerfile de producción no cambia.
  ssh "$H" "sudo sed -i '0,/^FROM .* AS builder/s//&\nENV NODE_OPTIONS=--max-old-space-size=4096/' /opt/stage/src/api-ventago/Dockerfile /opt/stage/src/ventago-app/Dockerfile 2>/dev/null; true"
  # ecosystem.config.js fija PORT 5002 (= el puerto del api de standby, red host): en stage → 5102
  ssh "$H" "sudo sed -i 's/PORT: 5002,/PORT: 5102,/' /opt/stage/src/api-ventago/ecosystem.config.js && sudo grep -q 'PORT: 5102,' /opt/stage/src/api-ventago/ecosystem.config.js"
  ssh "$H" "sudo docker build -q -t stage-api:latest /opt/stage/src/api-ventago >/dev/null && echo '  imagen api ok'"
fi
if [ "$QUE" != api ]; then
  enviar ventago-app "$CP"
  ssh "$H" "sudo sh -c 'cd /opt/stage/src/ventago-app && grep -rlaE newapi.coolsistema.com src next.config.js | xargs sed -i s#newapi.coolsistema.com#stageapi.coolsistema.com#g' && sudo sed -i '0,/^FROM .* AS builder/s//&\nENV NODE_OPTIONS=--max-old-space-size=4096/' /opt/stage/src/ventago-app/Dockerfile && sudo docker build -q -t stage-app:latest /opt/stage/src/ventago-app >/dev/null && echo '  imagen app ok'"
fi
ssh "$H" "sudo docker compose -f /opt/stage/docker-compose.yml up -d --remove-orphans 2>&1 | tail -3"
ssh "$H" "for i in \$(seq 1 60); do curl -sf -o /dev/null http://127.0.0.1:5102/api/health && { echo '  api health 200'; exit 0; }; sleep 2; done; echo '  ★ api no respondió'; sudo docker logs --tail 30 stage_api 2>&1; exit 1"
echo "STAGE listo: https://stage.coolsistema.com (api $(ssh "$H" sudo cat /opt/stage/src/api-ventago/.stage-commit 2>/dev/null) · app $(ssh "$H" sudo cat /opt/stage/src/ventago-app/.stage-commit 2>/dev/null))"
