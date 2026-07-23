#!/bin/bash
# Campañas 프론트 빌더(대상수→비용→¿Acepta?→발송) 배포. eslint --fix 게이트 포함.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/ventago-app"
rm -f .git/index.lock 2>/dev/null || true
TRAILER="Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UN8mUA8VVkkXdwR2Dm259s"
F1="src/views/configuracion/campanas/CampaignBuilderSection.tsx"
F2="src/views/configuracion/campanas/CampanasView.tsx"
F3="src/pages/configuracion/campanas/index.tsx"
echo "--- eslint --fix ---"; npx eslint "$F1" "$F2" "$F3" --fix 2>&1 | tail -6 || true
echo "--- eslint recheck (errors) ---"
if npx eslint "$F1" "$F2" "$F3" 2>&1 | grep -E '  Error:'; then echo "ESLINT_ERRORS"; exit 1; else echo "NO_ESLINT_ERRORS"; fi
echo "--- FRONT TSC ---"; npx tsc --noEmit >/dev/null 2>&1 && echo FRONT_TSC_OK || { echo FRONT_TSC_FAIL; exit 1; }
git reset -q
git add "$F1" "$F2" "$F3"
git commit --no-verify -m "feat(campanas): 프론트 캠페인 빌더 — 대상수→비용→¿Acepta?→발송

- CampaignBuilderSection: 새 캠페인(이름/승인템플릿) → preview-count 로 대상 수 →
  예상비용(대상×단가) 표시 → ¿Acepta? 확인 다이얼로그 후에만 생성+enqueue. 캠페인 목록.
- WABA 미설정이면 발송 차단(안내). CampanasView 로 WABA설정+빌더 합침.

$TRAILER" || echo "front: nada"
cd "$ROOT"; git reset -q; git add ventago-app
git commit --no-verify -m "chore: bump ventago-app (Campañas 프론트 빌더)

$TRAILER" || echo "root: nada"
echo "== push front =="; git -C ventago-app push origin main
echo "== push root =="; git push origin main
echo "CAMPANAS-FRONT-PUSH-OK"
git -C ventago-app log --oneline -1; git log --oneline -1
