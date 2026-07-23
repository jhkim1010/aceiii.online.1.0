#!/bin/bash
# AFIP A4 PDF 재설계(CoolSyncro 모던 이식) + 감열 formatter 제목. 선별 커밋+push. Mac 네이티브.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
rm -f .git/index.lock .git/HEAD.lock .git/refs/heads/main.lock api-ventago/.git/index.lock api-ventago/.git/HEAD.lock api-ventago/.git/refs/heads/main.lock 2>/dev/null || true

TRAILER="Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UN8mUA8VVkkXdwR2Dm259s"

# api-ventago: A4 PDF 3파일
git -C api-ventago reset -q
git -C api-ventago add \
  src/app/afip/pdf/a4-generator.ts \
  src/app/afip/pdf/a4-generator.spec.ts \
  src/app/afip/afip-output.service.ts
git -C api-ventago commit --no-verify -m "feat(afip): A4 PDF comprobante 재설계 — CoolSyncro 모던 레이아웃 이식 (RG1415+RG4892)

기존 PDF 는 품목도 없이(lines=[]) 밋밋 -> AFIP 규격과 상이. 재설계:
- a4-generator: Factura(D-02) 소비. 로고/Letra칩/COD, EMISOR·CLIENTE 2단,
  지브라 품목표(A/M IVA 분리: P.Unit=neto/IVA%/Subtotal c/IVA · B: IVA포함가),
  Neto/IVA/Otros/TOTAL 다크바, QR(RG4892)+CAE+Vto 푸터, 다중페이지 Pag n/N.
- pdf dispatch: buildFactura 로 sale+voucher+issuer -> D-02 재구성(thermal 과 동일 소스).
- 미사용 letra() 제거, spec 갱신.

$TRAILER" || echo "api-ventago: nada que commitear"

# root: api-ventago pointer + print-agent 감열 formatter(제목 추가)
git reset -q
git add api-ventago print-agent/src/fiscal-formatter.js
git commit --no-verify -m "chore(afip): bump api-ventago(A4 PDF 재설계) + print-agent 감열 comprobante 제목

print-agent fiscal-formatter: comprobante 제목(FACTURA A/B/M) 추가(CoolSyncro 감열 참조).
※감열 반영은 print-agent 재빌드+재설치 필요.

$TRAILER" || echo "root: nada que commitear"

echo "== push api-ventago =="; git -C api-ventago push origin main
echo "== push root =="; git push origin main
echo "AFIP-PDF-PUSH-OK"
git -C api-ventago log --oneline -1
git log --oneline -1
