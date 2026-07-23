#!/bin/bash
# 매장별 comprobante 로고 — PDF 렌더(store.logoUrl MinIO) + Configuración 업로드 카드. 선별 커밋+push.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
rm -f .git/index.lock .git/HEAD.lock .git/refs/heads/main.lock \
      api-ventago/.git/index.lock api-ventago/.git/HEAD.lock api-ventago/.git/refs/heads/main.lock \
      ventago-app/.git/index.lock ventago-app/.git/HEAD.lock ventago-app/.git/refs/heads/main.lock 2>/dev/null || true

TRAILER="Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UN8mUA8VVkkXdwR2Dm259s"

git -C api-ventago reset -q
git -C api-ventago add \
  src/app/afip/afip.module.ts \
  src/app/afip/afip-output.service.ts \
  src/app/afip/pdf/a4-generator.ts
git -C api-ventago commit --no-verify -m "feat(afip): A4 PDF 매장별 로고 렌더 — store.logoUrl(MinIO) 다운로드

pdf dispatch 에서 store.logoUrl 을 MinIO 로 다운로드해 로고 buffer 를 generateA4Pdf 에 전달
(좌상단 렌더, 없으면 발행자명 텍스트 폴백, 다운로드 실패해도 graceful). a4-generator 는 로고를
Buffer 로도 수용. afip.module 에 Store forFeature + MinioModule 추가.

$TRAILER" || echo "api-ventago: nada"

git -C ventago-app reset -q
git -C ventago-app add src/views/facturacion/IssuerConfig.tsx
git -C ventago-app commit --no-verify -m "feat(facturacion): Configuración 에 매장 로고 업로드 카드

Logo del comprobante 카드 — 현재 로고 미리보기 + 파일 선택 -> PUT /store/:id(FormData logoFile)
업로드. 매장별 로고(store.logoUrl)로 A4 PDF 좌상단에 반영.

$TRAILER" || echo "ventago-app: nada"

git reset -q
git add api-ventago ventago-app
git commit --no-verify -m "chore(afip): bump api-ventago + ventago-app (매장별 comprobante 로고)

$TRAILER" || echo "root: nada"

echo "== push ventago-app =="; git -C ventago-app push origin main
echo "== push api-ventago =="; git -C api-ventago push origin main
echo "== push root =="; git push origin main
echo "AFIP-LOGO-PUSH-OK"
git -C api-ventago log --oneline -1; git -C ventago-app log --oneline -1; git log --oneline -1
