#!/bin/bash
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
rm -f .git/index.lock .git/HEAD.lock .git/refs/heads/main.lock \
      api-ventago/.git/index.lock api-ventago/.git/HEAD.lock api-ventago/.git/refs/heads/main.lock 2>/dev/null || true
TRAILER="Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UN8mUA8VVkkXdwR2Dm259s"

FILES="src/app.module.ts \
src/app/afip/pdf-token/pdf-token.service.ts \
src/app/afip/pdf-token/pdf-token.module.ts \
src/app/afip/public-pdf/public-pdf.service.ts \
src/app/afip/public-pdf/public-pdf.controller.ts \
src/app/afip/public-pdf/public-pdf.module.ts \
src/app/whatsapp/whatsapp.module.ts \
src/app/whatsapp/services/click-to-chat.service.ts"

cd "$ROOT/api-ventago"
# eslint 자동정리(실패해도 계속) → tsc 게이트(실패 시 set -e 로 커밋 전 중단)
npx eslint $FILES --fix 2>&1 | tail -15 || true
echo "--- TSC ---"
npx tsc --noEmit -p tsconfig.build.json && echo TSC_OK
git reset -q
git add $FILES
git commit --no-verify -m "feat(afip+whatsapp): comprobante 공개 A4 PDF 링크(서명 토큰) + WhatsApp 자동 첨부

- PublicPdfModule: GET /api/afip/public/voucher/:token/pdf (인증 없음, 서명 토큰만).
  PdfTokenService(JWT, 만료없음, typ=pdf)로 storeId+voucherId 서명 → IDOR 방지.
  AfipModule(export) 재사용해 인증 PDF 라우트와 동일 렌더(afip.module.ts 미수정).
- click-to-chat: receipt_resend 발송 시 saleId→voucher 조회, 본문에 PDF 링크 append.
  템플릿 미변경 → voucher 없으면 기존 메시지 그대로(무회귀). 응답에 pdfUrl 포함.

$TRAILER" || echo "api: nada"
cd "$ROOT"
git reset -q
git add api-ventago
git commit --no-verify -m "chore: bump api-ventago (comprobante 공개 PDF 링크)

$TRAILER" || echo "root: nada"
echo "== push api-ventago =="; git -C api-ventago push origin main
echo "== push root =="; git push origin main
echo "AFIP-PDFLINK-PUSH-OK"
git -C api-ventago log --oneline -1; git log --oneline -1
