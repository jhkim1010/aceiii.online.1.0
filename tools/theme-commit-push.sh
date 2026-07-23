#!/bin/bash
# 매장 홈페이지 테마 Phase1 — 3 repo 커밋 + push
# 원칙: (1) 특정 파일만 커밋(무관 WIP 제외) (2) 서브모듈 먼저, 루트 마지막 (3) native 실행(마운트 git lock 회피)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CO="Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"

echo "== stale index.lock 정리 (device 샌드박스가 남긴 것) =="
rm -f .git/index.lock api-ventago/.git/index.lock ventago-app/.git/index.lock 2>/dev/null || true

API_FILES=(
  src/app/shop-public/store-theme.constants.ts
  src/app/shop-public/store-theme.service.ts
  src/app/shop-public/store-theme.controller.ts
  src/app/shop-public/store-theme-token.util.ts
  src/app/shop-public/store-theme-edit.guard.ts
  src/app/shop-public/store-theme-admin.service.ts
  src/app/shop-public/store-theme-admin.controller.ts
  src/app/shop-public/shop-public.module.ts
  migrations/2026-07-22-store-themes.sql
  scripts/_theme-di-probe.ts
)
echo "== api-ventago 커밋 =="
git -C api-ventago add "${API_FILES[@]}"
git -C api-ventago commit \
  -m "feat(shop-public): 매장별 홈페이지 테마 Phase1 — 공개조회(readonly pool+캐시)+저장/발행(매직링크 인증)+store_themes 마이그" \
  -m "$CO" -- "${API_FILES[@]}"

echo "== ventago-app 커밋 =="
git -C ventago-app add src/services/store-theme.service.ts src/components/ThemeEditButton.tsx
git -C ventago-app commit \
  -m "feat(theme): 매장 홈페이지 디자인 편집 진입(매직링크) 서비스+버튼" \
  -m "$CO" -- src/services/store-theme.service.ts src/components/ThemeEditButton.tsx

ROOT_FILES=(
  tienda-app/src/types/shop.ts
  tienda-app/src/services/shop-api.ts
  tienda-app/src/styles/globals.css
  tienda-app/src/components/ProductCard.tsx
  tienda-app/src/components/Header.tsx
  "tienda-app/src/pages/[storeId]/index.tsx"
  "tienda-app/src/pages/[storeId]/panel/diseno.tsx"
  tienda-app/src/lib/theme-preset.ts
  .gsd/spec-store-homepage-themes.md
  tools/agent-runner-jobs.js
  api-ventago
  ventago-app
)
echo "== root 커밋 (tienda-app + spec + 러너잡 + 서브모듈 포인터) =="
git add "${ROOT_FILES[@]}"
git commit \
  -m "feat(tienda+theme): 매장 홈페이지 테마 SSR 렌더+편집 페이지 / 서브모듈 포인터(api-ventago,ventago-app) / 러너 잡" \
  -m "$CO" -- "${ROOT_FILES[@]}"

echo "== push (서브모듈 먼저, 루트 마지막) =="
git -C ventago-app push origin main
git -C api-ventago push origin main
git push origin main

echo "THEME_COMMITPUSH_DONE"
echo "api:  $(git -C api-ventago log --oneline -1)"
echo "vapp: $(git -C ventago-app log --oneline -1)"
echo "root: $(git log --oneline -1)"
