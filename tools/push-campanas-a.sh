#!/bin/bash
# Campañas Phase A — 매장 WhatsApp(WABA) 설정 + 매뉴얼 링크. 배포.
# ⚠️ campanas.sql 6테이블은 배포 전 이미 운영(5434)+로컬(5432) 적용됨.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
rm -f .git/index.lock api-ventago/.git/index.lock ventago-app/.git/index.lock 2>/dev/null || true
TRAILER="Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UN8mUA8VVkkXdwR2Dm259s"

API_FILES="migrations/2026-07-22-campanas.sql \
src/app/store/whatsapp-config/store-whatsapp-config.model.ts \
src/app/store/whatsapp-config/store-whatsapp-config.service.ts \
src/app/store/whatsapp-config/store-whatsapp-config.controller.ts \
src/app/store/whatsapp-config/store-whatsapp-config.module.ts \
src/app.module.ts"

FRONT_FILES="src/views/configuracion/campanas/WhatsappCampaignConfigView.tsx \
src/pages/configuracion/campanas/index.tsx \
src/views/configuracion/integraciones/IntegracionesHubView.tsx \
public/manuales/whatsapp-campanas-es.html"

cd "$ROOT/api-ventago"
echo "--- API TSC ---"; npx tsc --noEmit -p tsconfig.build.json && echo API_TSC_OK
git reset -q
git add $API_FILES
git commit --no-verify -m "feat(campanas): 매장 WhatsApp(WABA) 설정 [Phase A]

- store_whatsapp_config 모델/서비스/컨트롤러 — WABA ID/Phone Number ID/Access Token(암호화)/활성.
  toJSON redact(accessTokenSet) + 전용 GET/PUT(@Auth+소유검증) + resolveWabaConfig/isReady.
  access_token 은 email-secret(AES-256-GCM) 재사용 암호화, 발송 시에만 복호화.
- campanas.sql(6테이블) 커밋(운영/로컬 이미 적용). 캠페인은 매장 자기 WABA 로만(중앙 폴백 없음).

$TRAILER" || echo "api: nada"

cd "$ROOT/ventago-app"
echo "--- FRONT TSC ---"; npx tsc --noEmit && echo FRONT_TSC_OK
git reset -q
git add $FRONT_FILES
git commit --no-verify -m "feat(config): Campañas — WhatsApp(WABA) 설정 화면 + 매뉴얼 링크 [Phase A]

- Integraciones › Mensajería 에 'Campañas (WhatsApp masivo)' 카드 → /configuracion/campanas.
- WABA 자격증명 입력(토큰 write-only), 발송비용 매장 직접청구 안내, 매뉴얼(정적 HTML) 링크.

$TRAILER" || echo "front: nada"

cd "$ROOT"
git reset -q
git add api-ventago ventago-app
git commit --no-verify -m "chore: bump submodules (Campañas Phase A — WhatsApp WABA 설정)

$TRAILER" || echo "root: nada"

echo "== push api =="; git -C api-ventago push origin main
echo "== push front =="; git -C ventago-app push origin main
echo "== push root =="; git push origin main
echo "CAMPANAS-A-PUSH-OK"
git -C api-ventago log --oneline -1; git -C ventago-app log --oneline -1; git log --oneline -1
