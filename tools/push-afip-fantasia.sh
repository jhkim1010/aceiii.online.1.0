#!/bin/bash
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
rm -f .git/index.lock .git/HEAD.lock .git/refs/heads/main.lock \
      api-ventago/.git/index.lock api-ventago/.git/HEAD.lock api-ventago/.git/refs/heads/main.lock \
      ventago-app/.git/index.lock ventago-app/.git/HEAD.lock ventago-app/.git/refs/heads/main.lock 2>/dev/null || true
TRAILER="Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UN8mUA8VVkkXdwR2Dm259s"
git -C api-ventago reset -q
git -C api-ventago add src/app/afip/build-factura.ts src/app/afip/pdf/a4-generator.ts
git -C api-ventago commit --no-verify -m "feat(afip): Nombre de fantasía(razonSocialL2) + 로고 없을 때 큰 글씨 렌더

build-factura emisor 에 nombreFantasia(issuer.razonSocialL2). a4-generator 는 로고 미등록 시
Nombre de fantasía(없으면 razón social)를 로고 자리에 21pt 렌더. EMISOR 블록은 법적 razón social 유지.

$TRAILER" || echo "api: nada"
git -C ventago-app reset -q
git -C ventago-app add src/views/facturacion/IssuerConfig.tsx
git -C ventago-app commit --no-verify -m "feat(facturacion): Configuración 에 Nombre de fantasía 필드

$TRAILER" || echo "front: nada"
git reset -q
git add api-ventago ventago-app print-agent/src/fiscal-formatter.js
git commit --no-verify -m "chore(afip): bump submodules + 감열 emisor Nombre de fantasía

$TRAILER" || echo "root: nada"
echo "== push ventago-app =="; git -C ventago-app push origin main
echo "== push api-ventago =="; git -C api-ventago push origin main
echo "== push root =="; git push origin main
echo "AFIP-FANTASIA-PUSH-OK"
git -C api-ventago log --oneline -1; git -C ventago-app log --oneline -1; git log --oneline -1
