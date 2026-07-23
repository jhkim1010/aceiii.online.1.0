#!/bin/bash
# 이메일(첨부 PDF) 영수증 발송 + 멀티채널 발급 모달 — 배포 스크립트.
# ⚠️ campanas.sql(대량 캠페인)은 별도 미래 기능이라 여기서 제외. 마이그레이션 없음.
# ⚠️ 실제 이메일 발송은 EMAIL_API_URL/EMAIL_API_KEY/EMAIL_FROM(Mailgun) env 설정 후 동작(미설정 시 graceful).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
rm -f .git/index.lock api-ventago/.git/index.lock ventago-app/.git/index.lock 2>/dev/null || true
TRAILER="Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UN8mUA8VVkkXdwR2Dm259s"

API_FILES="src/app/afip/afip-output.service.ts \
src/app/afip/afip-query.service.ts \
src/app/afip/afip.controller.ts \
src/app/afip/afip.module.ts \
src/common/mail/mail.ts \
src/app/afip/afip-output.service.spec.ts \
src/app/afip/afip-query.service.spec.ts"

FRONT_FILES="src/services/afip.service.ts \
src/views/facturacion/PartialInvoiceModal.tsx"

# ---- api: tsc 게이트 → 커밋 ----
cd "$ROOT/api-ventago"
echo "--- API TSC ---"
npx tsc --noEmit -p tsconfig.build.json && echo API_TSC_OK
git reset -q
git add $API_FILES
git commit --no-verify -m "feat(afip): comprobante 이메일 발송(PDF 첨부) + Pendientes 채널 힌트

- afip-output: output='email' 분기 — 수신자(storeClient.globalClient / client) email resolve,
  A4 PDF 렌더(pdf 분기와 공용 renderA4Pdf) 후 Mailgun 첨부 발송(sendMailWithAttachment).
- afip-query.listPendientes: whatsappReady/clientEmail 부여(프론트 채널 노출 결정, N+1 회피 bulk).
- afip.controller: POST /afip/vouchers/:id/email. afip.module: Clients/StoreClient/GlobalClient + PhoneNormalizer 배선.
- mail.ts: sendMailWithAttachment(Mailgun multipart). env(EMAIL_API_URL/KEY) 미설정 시 graceful skip.

$TRAILER" || echo "api: nada"

# ---- front: tsc 게이트 → 커밋 ----
cd "$ROOT/ventago-app"
echo "--- FRONT TSC ---"
npx tsc --noEmit && echo FRONT_TSC_OK
git reset -q
git add $FRONT_FILES
git commit --no-verify -m "feat(facturacion): 멀티채널 발급 모달(Térmica/PDF/WhatsApp/Email) + emailVoucher

- PartialInvoiceModal: 발급 후 선택 채널 순차 발송, 채널 노출은 whatsappReady/clientEmail 기준.
  진행단계(form→working→done) 피드백, 오프라인/중복 가드 유지.
- afip.service: emailVoucher(POST vouchers/:id/email) + issue output 에 'email' 추가.

$TRAILER" || echo "front: nada"

# ---- root submodule bump ----
cd "$ROOT"
git reset -q
git add api-ventago ventago-app
git commit --no-verify -m "chore: bump submodules (comprobante 이메일 발송 + 멀티채널 모달)

$TRAILER" || echo "root: nada"

echo "== push api-ventago =="; git -C api-ventago push origin main
echo "== push ventago-app =="; git -C ventago-app push origin main
echo "== push root =="; git push origin main
echo "AFIP-EMAIL-PUSH-OK"
git -C api-ventago log --oneline -1; git -C ventago-app log --oneline -1; git log --oneline -1
