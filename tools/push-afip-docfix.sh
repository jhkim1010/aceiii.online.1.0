#!/bin/bash
# AFIP 10015 수정 — 문서 없음/무효(예 "00000000") → 단순 Consumidor Final(DocTipo=99,DocNro=0).
# api-ventago 4파일 선별 커밋+push. Mac 네이티브.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
rm -f .git/index.lock api-ventago/.git/index.lock 2>/dev/null || true

TRAILER="Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UN8mUA8VVkkXdwR2Dm259s"

git -C api-ventago reset -q
git -C api-ventago add \
  src/app/afip/code-maps.ts \
  src/app/afip/providers/soap-direct.provider.ts \
  src/app/afip/providers/rest-gateway.provider.ts \
  src/app/afip/build-factura.ts
git -C api-ventago commit --no-verify -m "fix(afip): AFIP 10015 — 문서 없음/무효는 단순 Consumidor Final(99)

Consumidor Final 의 document='00000000' 처럼 '길이는 있으나 숫자값 0' 인 문서에서
decideDocumentType 이 DNI(96) 반환 -> provider 가 DocNro=0 으로 만들어 DocTipo96+DocNro0
불일치 -> AFIP 거부 10015. 수정:
- decideDocumentType: 숫자만 추출, 값이 0/무효면 FINAL_CONSUMER(99).
- soap-direct / rest-gateway: 불변식 DocNro=0 <=> DocTipo=99 강제.
- build-factura: CF 표시/QR docNro 정규화(placeholder 숨김, QR 스캔값 정합).

$TRAILER" || echo "api-ventago: nada que commitear"

git add api-ventago
git commit --no-verify -m "chore: bump api-ventago (AFIP 10015 docType/docNro 수정)

$TRAILER" || echo "root: nada que commitear"

echo "== push api-ventago =="; git -C api-ventago push origin main
echo "== push root =="; git push origin main
echo "AFIP-DOCFIX-PUSH-OK"
git -C api-ventago log --oneline -1
git log --oneline -1
