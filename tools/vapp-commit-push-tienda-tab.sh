#!/bin/bash
# 공개몰(Tienda Online) 설정 탭 — ventago-app 커밋+푸시
# 스코프 한정: 아래 2파일만 커밋 (afip/PartialInvoice 등 WIP 는 건드리지 않음)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/ventago-app"
CO="Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"

echo "== stale index.lock 정리 =="
rm -f .git/index.lock 2>/dev/null || true

FILES=(
  src/views/configuracion/tienda/StorefrontDesignView.tsx
  src/pages/configuracion/index.tsx
)
echo "== add (지정 파일만) =="
git add "${FILES[@]}"

echo "== commit =="
git commit \
  -m "feat(configuracion): 공개몰(Tienda Online) 설정 탭 - StorefrontDesignCard 마운트 [Phase61]" \
  -m "$CO" -- "${FILES[@]}"

echo "== push origin main =="
git push origin main

echo "VAPP_TIENDA_TAB_DONE"
git log --oneline -1
