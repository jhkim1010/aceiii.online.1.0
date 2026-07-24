#!/bin/bash
# 이메일 개편 — 캠페인:Resend(주석/스키마), 영수증:SMTP(nodemailer), Mailgun 제거(UI카드·매뉴얼).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TRAILER="Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UN8mUA8VVkkXdwR2Dm259s"

# ---------- API ----------
cd "$ROOT/api-ventago"
rm -f .git/index.lock 2>/dev/null || true
echo "--- npm install nodemailer ---"; npm install nodemailer@^6.9.14 @types/nodemailer@^6.4.14 --save 2>&1 | tail -6
echo "--- API TSC ---"; npx tsc --noEmit -p tsconfig.build.json && echo API_TSC_OK
git reset -q
git add src/common/mail/mail.ts src/app/afip/afip-output.service.ts package.json package-lock.json
git commit --no-verify -m "feat(email): 캠페인=Resend / 영수증 PDF=SMTP(nodemailer), Mailgun 발송경로 제거

- common/mail: sendMail=Resend(EMAIL_API_URL/KEY/FROM). Mailgun 첨부 함수 제거 →
  sendMailWithAttachmentSmtp(nodemailer, SMTP_HOST/PORT/USER/PASS/FROM, 트랜스포터 1회 캐시).
- afip-output: 영수증 PDF를 중앙 SMTP로 발송(매장별 Mailgun resolve 제거).

$TRAILER" || echo "api: nada"
echo "== push api =="; git push origin main

# ---------- FRONT ----------
cd "$ROOT/ventago-app"
rm -f .git/index.lock 2>/dev/null || true
F1="src/views/configuracion/facturacion/FacturacionPrefsView.tsx"
echo "--- eslint --fix ---"; npx eslint "$F1" --fix 2>&1 | tail -6 || true
echo "--- eslint recheck (exit gate) ---"; npx eslint "$F1" && echo NO_ESLINT_ERRORS
echo "--- FRONT TSC ---"; npx tsc --noEmit >/dev/null 2>&1 && echo FRONT_TSC_OK || { echo FRONT_TSC_FAIL; exit 1; }
git reset -q
# Mailgun 매뉴얼 삭제
git rm -q public/manuales/manual-mailgun-ES.pdf public/manuales/manual-mailgun-KO.pdf 2>/dev/null || echo "mailgun pdf: already gone"
git add "$F1" public/manuales/manifest.json public/manuales/manual-resend-es.html public/manuales/manual-resend-ko.html
git commit --no-verify -m "feat(facturacion): Mailgun 이메일 설정 카드 제거 + Resend 매뉴얼 추가

- FacturacionPrefsView: 매장별 Mailgun(From/API URL/KEY) 카드 삭제(이메일은 중앙 관리로 이전).
- manuales: mailgun PDF 2종 삭제, Resend 설정 매뉴얼(HTML, ES/KO) 추가 + manifest 갱신.

$TRAILER" || echo "front: nada"
echo "== push front =="; git push origin main

# ---------- ROOT ----------
cd "$ROOT"; git reset -q
git add api-ventago ventago-app
git commit --no-verify -m "chore: bump api/front (이메일 Resend/SMTP 개편 + Mailgun 제거)

$TRAILER" || echo "root: nada"
echo "== push root =="; git push origin main
echo "EMAIL-RESEND-SMTP-PUSH-OK"
git -C api-ventago log --oneline -1; git -C ventago-app log --oneline -1; git log --oneline -1
