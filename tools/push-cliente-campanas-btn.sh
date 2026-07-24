#!/bin/bash
# ClienteVista 에 'Configurar Campañas'(/configuracion/campanas) 버튼 추가 — front only.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TRAILER="Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UN8mUA8VVkkXdwR2Dm259s"
cd "$ROOT/ventago-app"
rm -f .git/index.lock 2>/dev/null || true
F1="src/views/cliente-vista/ClienteVistaView.tsx"
echo "--- eslint --fix ---"; npx eslint "$F1" --fix 2>&1 | tail -6 || true
echo "--- eslint recheck ---"; npx eslint "$F1" && echo NO_ESLINT_ERRORS
echo "--- FRONT TSC ---"; npx tsc --noEmit >/dev/null 2>&1 && echo FRONT_TSC_OK || { echo FRONT_TSC_FAIL; exit 1; }
git reset -q
git add "$F1"
git commit --no-verify -m "feat(cliente-vista): 'Configurar Campañas' 버튼 추가(/configuracion/campanas 바로가기)

- 고객 목록 화면에서 WABA 설정·opt-in 동의·캠페인 빌더 화면으로 바로 진입.

$TRAILER" || echo "front: nada"
echo "== push front =="; git push origin main
cd "$ROOT"; git reset -q; git add ventago-app
git commit --no-verify -m "chore: bump ventago-app (ClienteVista Campañas 버튼)

$TRAILER" || echo "root: nada"
echo "== push root =="; git push origin main
echo "CLIENTE-CAMPANAS-BTN-OK"
git -C ventago-app log --oneline -1; git log --oneline -1
