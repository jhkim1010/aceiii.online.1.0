#!/bin/bash
# WIRING GAP #1 — print-agent fiscal 출력 배선(thermal factura D-02). api-ventago 2파일만 선별 커밋+push.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
rm -f .git/index.lock api-ventago/.git/index.lock 2>/dev/null || true

TRAILER="Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UN8mUA8VVkkXdwR2Dm259s"

git -C api-ventago reset -q
git -C api-ventago add src/app/afip/afip-output.service.ts src/app/afip/afip-query.service.ts
git -C api-ventago commit --no-verify -m "fix(afip): print-agent fiscal 출력 배선(WIRING GAP #1) — thermal factura(D-02)

dispatch thermal 에서 buildFactura(voucher,sale,issuer)로 D-02 factura 생성해
emitPrintInvoice payload.factura 로 전달 -> print-agent print_invoice 가 fiscal path
(CAE/QR comprobante)로 렌더. AfipQueryService.getSaleForFactura eager-load 추가.

$TRAILER" || echo "api-ventago: nada que commitear"

git add api-ventago
git commit --no-verify -m "chore: bump api-ventago (fiscal 출력 배선 WIRING GAP #1)

$TRAILER" || echo "root: nada que commitear"

echo "== push api-ventago =="; git -C api-ventago push origin main
echo "== push root =="; git push origin main
echo "FISCAL-WIRING-PUSH-OK"
git -C api-ventago log --oneline -1
git log --oneline -1
