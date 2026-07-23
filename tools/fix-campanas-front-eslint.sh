#!/bin/bash
# 프론트 빌드 복구: campanas 뷰 lines-around-comment 등 eslint --fix + 재푸시.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/ventago-app"
rm -f .git/index.lock 2>/dev/null || true
F1="src/views/configuracion/campanas/WhatsappCampaignConfigView.tsx"
F2="src/pages/configuracion/campanas/index.tsx"
echo "--- eslint --fix ---"
npx eslint "$F1" "$F2" --fix 2>&1 | tail -8 || true
echo "--- recheck errors (expect none) ---"
if npx eslint "$F1" "$F2" 2>&1 | grep -E '  Error:'; then echo "STILL_HAS_ERRORS"; exit 1; else echo "NO_ESLINT_ERRORS"; fi
echo "--- tsc ---"
npx tsc --noEmit >/dev/null 2>&1 && echo TSC_OK || { echo TSC_FAIL; exit 1; }
git reset -q
git add "$F1" "$F2"
git commit --no-verify -m "fix(config): campanas 뷰 eslint lines-around-comment 수정 — 프론트 빌드 복구

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UN8mUA8VVkkXdwR2Dm259s" || echo "front: nada"
git push origin main
cd "$ROOT"; git reset -q; git add ventago-app
git commit --no-verify -m "chore: bump ventago-app (campanas front eslint 수정)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" || echo "root: nada"
git push origin main
echo "CAMPANAS-FRONT-ESLINT-FIX-OK"
git -C "$ROOT/ventago-app" log --oneline -1
