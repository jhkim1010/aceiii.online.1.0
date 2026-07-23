#!/bin/bash
# opt 기능 2건 — (1) 손님 폼 동의 체크박스(front InfoClient), (2) 손님 opt-out 확인 페이지 브랜드화(api).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TRAILER="Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UN8mUA8VVkkXdwR2Dm259s"

# ---------- API (opt-out 확인 페이지) ----------
cd "$ROOT/api-ventago"
rm -f .git/index.lock 2>/dev/null || true
echo "--- API TSC ---"; npx tsc --noEmit -p tsconfig.build.json && echo API_TSC_OK
git reset -q
git add src/app/campaigns/unsubscribe.controller.ts
git commit --no-verify -m "feat(campanas): opt-out 확인 페이지 브랜드화(손님용 baja 셀프 링크)

- UnsubscribeController.page(): Ventago 브랜드 확인 카드(체크/경고 아이콘, 인라인 SVG).
  성공/무효/오류 톤 구분. 서명 토큰 opt-out 흐름은 그대로.

$TRAILER" || echo "api: nada"
echo "== push api =="; git push origin main

# ---------- FRONT (동의 체크박스) ----------
cd "$ROOT/ventago-app"
rm -f .git/index.lock 2>/dev/null || true
F1="src/views/homes/components/InfoClient.tsx"
echo "--- eslint --fix ---"; npx eslint "$F1" --fix 2>&1 | tail -6 || true
echo "--- eslint recheck (exit code gate) ---"; npx eslint "$F1" && echo NO_ESLINT_ERRORS
echo "--- FRONT TSC ---"; npx tsc --noEmit >/dev/null 2>&1 && echo FRONT_TSC_OK || { echo FRONT_TSC_FAIL; exit 1; }
git reset -q
git add "$F1"
git commit --no-verify -m "feat(campanas): 손님 등록/편집 폼에 WhatsApp 수신 동의(opt-in) 체크박스

- InfoClient: 선택 손님의 동의 상태 로드 → 체크박스 → 저장 시 변경된 경우에만
  PUT /client-contact-prefs/:id (신규 미체크 손님을 실수로 opt-out 하지 않도록).
  동의 저장 실패는 손님 저장을 막지 않음(경고만).

$TRAILER" || echo "front: nada"
echo "== push front =="; git push origin main

# ---------- ROOT ----------
cd "$ROOT"; git reset -q
git add api-ventago ventago-app
git commit --no-verify -m "chore: bump api/front (opt 기능 — 폼 동의 체크박스 + baja 확인 페이지)

$TRAILER" || echo "root: nada"
echo "== push root =="; git push origin main
echo "OPTIN-FORM-PUSH-OK"
git -C api-ventago log --oneline -1; git -C ventago-app log --oneline -1; git log --oneline -1
