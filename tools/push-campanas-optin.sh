#!/bin/bash
# Campañas opt-in 동의 수집 — api(엔드포인트) + front(관리 화면) 배포.
# tsc/eslint 게이트 후 특정 파일만 커밋·푸시. 서브모듈 bump 포함.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TRAILER="Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UN8mUA8VVkkXdwR2Dm259s"

# ---------- API ----------
cd "$ROOT/api-ventago"
rm -f .git/index.lock 2>/dev/null || true
echo "--- API TSC ---"; npx tsc --noEmit -p tsconfig.build.json && echo API_TSC_OK
git reset -q
git add src/app/campaigns/services/contact-prefs.service.ts \
        src/app/campaigns/client-contact-prefs.controller.ts \
        src/app/campaigns/dto/set-consent.dto.ts \
        src/app/campaigns/campaigns.module.ts
git commit --no-verify -m "feat(campanas): 손님별 WhatsApp 수신 동의(opt-in) 수집 API

- ClientContactPrefsController: GET(단건/일괄) · PUT(동의/거부). storeId 소유권 검증.
- ContactPrefsService: getConsent/getConsentMap/setWhatsappConsent 추가.
  일괄 조회는 client_id IN (...) 단일 쿼리(pool 안전). setOptIn/setOptOut 재사용.

$TRAILER" || echo "api: nada"
echo "== push api =="; git push origin main

# ---------- FRONT ----------
cd "$ROOT/ventago-app"
rm -f .git/index.lock 2>/dev/null || true
F1="src/views/configuracion/campanas/WhatsappConsentSection.tsx"
F2="src/views/configuracion/campanas/CampanasView.tsx"
echo "--- eslint --fix ---"; npx eslint "$F1" "$F2" --fix 2>&1 | tail -6 || true
echo "--- eslint recheck (exit code gate) ---"; npx eslint "$F1" "$F2" && echo NO_ESLINT_ERRORS
echo "--- FRONT TSC ---"; npx tsc --noEmit >/dev/null 2>&1 && echo FRONT_TSC_OK || { echo FRONT_TSC_FAIL; exit 1; }
git reset -q
git add "$F1" "$F2"
git commit --no-verify -m "feat(campanas): WhatsApp 수신 동의 관리 화면(opt-in)

- WhatsappConsentSection: 손님 검색→목록→스위치로 동의/거부 저장(낙관적 갱신).
  일괄 상태 조회(client-contact-prefs?clientIds=)로 pool 낭비 없음. 매뉴얼 링크.
- CampanasView 하단에 합침.

$TRAILER" || echo "front: nada"
echo "== push front =="; git push origin main

# ---------- ROOT (submodule bump) ----------
cd "$ROOT"; git reset -q
git add api-ventago ventago-app
git commit --no-verify -m "chore: bump api/front (Campañas opt-in 동의 수집)

$TRAILER" || echo "root: nada"
echo "== push root =="; git push origin main
echo "CAMPANAS-OPTIN-PUSH-OK"
git -C api-ventago log --oneline -1; git -C ventago-app log --oneline -1; git log --oneline -1
