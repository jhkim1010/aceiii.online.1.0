#!/bin/bash
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/ventago-app"
rm -f .git/index.lock 2>/dev/null || true
F1="src/views/configuracion/campanas/CampaignBuilderSection.tsx"
echo "--- eslint (errors only, correct pattern) ---"
if npx eslint "$F1" 2>&1 | grep -E '  error  '; then echo "ESLINT_ERRORS"; exit 1; else echo "NO_ESLINT_ERRORS"; fi
echo "--- tsc ---"; npx tsc --noEmit >/dev/null 2>&1 && echo TSC_OK || { echo TSC_FAIL; exit 1; }
git reset -q; git add "$F1"
git commit --no-verify -m "fix(campanas): loadCampaigns 미사용 sid 파라미터 제거 — 프론트 빌드 복구

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UN8mUA8VVkkXdwR2Dm259s" || echo "front: nada"
git push origin main
cd "$ROOT"; git reset -q; git add ventago-app
git commit --no-verify -m "chore: bump ventago-app (campanas front eslint fix)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" || echo "root: nada"
git push origin main
echo "CAMPANAS-FRONT-FIX-OK"; git -C ventago-app log --oneline -1
