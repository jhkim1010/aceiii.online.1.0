#!/bin/bash
# 매장 홈페이지 테마 — 라운드2(공개몰 활성 토글 enabled) 3 repo 커밋 + push
# 원칙: 특정 파일만 커밋(무관 WIP 제외) / 서브모듈 먼저·루트 마지막 / native 실행(git lock 회피)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CO="Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"

echo "== stale index.lock 정리 =="
rm -f .git/index.lock api-ventago/.git/index.lock ventago-app/.git/index.lock 2>/dev/null || true

API_FILES=(
  src/app/shop-public/store-theme.constants.ts
  src/app/shop-public/store-theme.service.ts
  src/app/shop-public/store-theme-admin.service.ts
  src/app/shop-public/store-theme-admin.controller.ts
  migrations/2026-07-22-store-themes-enabled.sql
)
echo "== api-ventago 커밋 =="
git -C api-ventago add "${API_FILES[@]}"
git -C api-ventago commit \
  -m "feat(shop-public): 공개몰 활성 토글(enabled) — admin ON/OFF, 새 매장 기본 비활성(유료 opt-in)+기존 grandfather" \
  -m "$CO" -- "${API_FILES[@]}"

VAPP_FILES=(
  src/services/store-theme.service.ts
  src/components/StorefrontDesignCard.tsx
)
echo "== ventago-app 커밋 =="
git -C ventago-app add "${VAPP_FILES[@]}"
git -C ventago-app commit \
  -m "feat(theme): 공개몰 활성 토글 카드(StorefrontDesignCard) + 상태/설정 서비스" \
  -m "$CO" -- "${VAPP_FILES[@]}"

ROOT_FILES=(
  tienda-app/src/types/shop.ts
  "tienda-app/src/pages/[storeId]/index.tsx"
  .gsd/spec-store-storefront-subdomains.md
  tools/agent-runner-jobs.js
  api-ventago
  ventago-app
)
echo "== root 커밋 =="
git add "${ROOT_FILES[@]}"
git commit \
  -m "feat(tienda+theme): 공개몰 비활성 시 404 게이트 + Phase2 SPEC(서브도메인 자동화) / 서브모듈 포인터 / 러너잡" \
  -m "$CO" -- "${ROOT_FILES[@]}"

echo "== push (서브모듈 먼저, 루트 마지막) =="
git -C ventago-app push origin main
git -C api-ventago push origin main
git push origin main

echo "THEME_COMMITPUSH2_DONE"
echo "api:  $(git -C api-ventago log --oneline -1)"
echo "vapp: $(git -C ventago-app log --oneline -1)"
echo "root: $(git log --oneline -1)"
