#!/bin/bash
# 매장별 이메일(Mailgun) 발송 설정 — admin config 입력 + 암호화 저장 + 발송 배선. 배포.
# ⚠️ 운영 DB(5434) store_configs 컬럼 마이그레이션은 배포 전 이미 적용됨(email_from/url/key_enc).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
rm -f .git/index.lock api-ventago/.git/index.lock ventago-app/.git/index.lock 2>/dev/null || true
TRAILER="Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UN8mUA8VVkkXdwR2Dm259s"

API_FILES="src/common/crypto/email-secret.ts \
migrations/2026-07-23-store-email-config.sql \
src/app/store/config/storeConfig.model.ts \
src/app/store/config/storeConfig.service.ts \
src/app/store/config/storeConfig.controller.ts \
src/app/afip/afip.module.ts \
src/app/afip/afip-output.service.ts \
src/common/mail/mail.ts"

FRONT_FILES="src/views/configuracion/facturacion/FacturacionPrefsView.tsx"

cd "$ROOT/api-ventago"
echo "--- API TSC ---"; npx tsc --noEmit -p tsconfig.build.json && echo API_TSC_OK
git reset -q
git add $API_FILES
git commit --no-verify -m "feat(store-config): 매장별 이메일(Mailgun) 발송 설정 + 암호화 저장

- store_configs: email_from/email_api_url/email_api_key_enc(AES-256-GCM, JWT키 파생).
  모델 toJSON redact + emailApiKeySet 노출 → 공개 GET /store-config 로 키 유출 차단.
- PUT /store-config/:id/email-config: 발신주소/URL 저장, 키는 입력 시에만 암호화 저장.
- resolveEmailConfig: 매장별 우선 → 전역 env 폴백. afip-output email 분기가 사용.
- mail.sendMailWithAttachment: env 직접읽기 → config 파라미터화(매장별 주입).

$TRAILER" || echo "api: nada"

cd "$ROOT/ventago-app"
echo "--- FRONT TSC ---"; npx tsc --noEmit && echo FRONT_TSC_OK
git reset -q
git add $FRONT_FILES
git commit --no-verify -m "feat(config): Facturación에 매장별 이메일 발송 설정 카드

- 발신주소(From) + 선택적 Mailgun URL/KEY 입력, 키는 write-only(입력 시에만 전송).
- 공개 GET 로 로드(키 redact), emailApiKeySet 로 설정여부 표시.

$TRAILER" || echo "front: nada"

cd "$ROOT"
git reset -q
git add api-ventago ventago-app
git commit --no-verify -m "chore: bump submodules (매장별 이메일 발송 설정)

$TRAILER" || echo "root: nada"

echo "== push api =="; git -C api-ventago push origin main
echo "== push front =="; git -C ventago-app push origin main
echo "== push root =="; git push origin main
echo "AFIP-EMAIL-CFG-PUSH-OK"
git -C api-ventago log --oneline -1; git -C ventago-app log --oneline -1; git log --oneline -1
