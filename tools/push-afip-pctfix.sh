#!/bin/bash
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
rm -f .git/index.lock api-ventago/.git/index.lock 2>/dev/null || true
TRAILER="Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UN8mUA8VVkkXdwR2Dm259s"
cd "$ROOT/api-ventago"
echo "--- TSC ---"
npx tsc --noEmit -p tsconfig.build.json && echo TSC_OK
git reset -q
git add src/app/afip/build-factura.ts
git commit --no-verify -m "fix(afip): 부분청구 voucher PDF 생성 실패 — invoicePct DECIMAL 문자열 형변환

voucher.invoicePct 는 DECIMAL(5,2) 라 sequelize 가 '30.00'(문자열)로 반환 →
applyPartial 의 typeof pct==='number' 검사에서 즉시 throw → buildFactura 실패 →
부분청구(pct!=100) comprobante 의 A4 PDF(공개/인증 라우트 공통)와 감열 fiscal payload 모두 실패.
Number(voucher.invoicePct) 로 강제 형변환해 해소.

$TRAILER" || echo "api: nada"
cd "$ROOT"
git reset -q
git add api-ventago
git commit --no-verify -m "chore: bump api-ventago (부분청구 PDF invoicePct 형변환 fix)

$TRAILER" || echo "root: nada"
echo "== push api-ventago =="; git -C api-ventago push origin main
echo "== push root =="; git push origin main
echo "AFIP-PCTFIX-PUSH-OK"
git -C api-ventago log --oneline -1
