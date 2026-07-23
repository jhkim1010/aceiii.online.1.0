#!/bin/bash
# Phase 61 — 공개몰 slug + 서브도메인 라우팅 3 repo 커밋 + push
# 특정 파일만 커밋(무관 WIP 제외) / 서브모듈 먼저·루트 마지막 / native 실행
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CO="Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"

echo "== stale index.lock 정리 =="
rm -f .git/index.lock api-ventago/.git/index.lock ventago-app/.git/index.lock 2>/dev/null || true

API_FILES=(
  src/app/shop-public/store-slug.util.ts
  src/app/shop-public/store-slug.service.ts
  src/app/shop-public/store-slug-public.controller.ts
  src/app/shop-public/store-slug-admin.controller.ts
  src/app/shop-public/shop-public.module.ts
  migrations/2026-07-22-stores-slug.sql
)
echo "== api-ventago 커밋 =="
git -C api-ventago add "${API_FILES[@]}"
git -C api-ventago commit \
  -m "feat(shop-public): 매장 slug + by-slug 공개조회 + 소유자 slug 설정(예약어/형식/중복 검증) [Phase61]" \
  -m "$CO" -- "${API_FILES[@]}"

VAPP_FILES=(
  src/services/store-theme.service.ts
  src/components/StorefrontDesignCard.tsx
)
echo "== ventago-app 커밋 =="
git -C ventago-app add "${VAPP_FILES[@]}"
git -C ventago-app commit \
  -m "feat(theme): 공개몰 카드에 slug 설정 + 공개 URL(<slug>.coolsistema.com) 표시 [Phase61]" \
  -m "$CO" -- "${VAPP_FILES[@]}"

ROOT_FILES=(
  tienda-app/src/middleware.ts
  tools/agent-runner-jobs.js
  api-ventago
  ventago-app
)
echo "== root 커밋 =="
git add "${ROOT_FILES[@]}"
git commit \
  -m "feat(tienda): 공개몰 서브도메인 미들웨어(<slug>.coolsistema.com→/[storeId] rewrite) / 서브모듈 포인터 [Phase61]" \
  -m "$CO" -- "${ROOT_FILES[@]}"

echo "== push (서브모듈 먼저, 루트 마지막) =="
git -C ventago-app push origin main
git -C api-ventago push origin main
git push origin main

echo "THEME_COMMITPUSH_P61_DONE"
echo "api:  $(git -C api-ventago log --oneline -1)"
echo "vapp: $(git -C ventago-app log --oneline -1)"
echo "root: $(git log --oneline -1)"
