#!/bin/bash
# 공개주소(slug) 정규화 충돌 방지 — api-ventago 커밋+푸시
# 스코프 한정: 아래 3파일만 커밋 (다른 WIP 는 건드리지 않음)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/api-ventago"
CO="Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"

echo "== stale index.lock 정리 =="
rm -f .git/index.lock 2>/dev/null || true

FILES=(
  src/app/shop-public/store-slug.util.ts
  src/app/shop-public/store-slug.service.ts
  migrations/2026-07-23-stores-slug-canonical.sql
)
echo "== add (지정 파일만) =="
git add "${FILES[@]}"

echo "== commit =="
git commit \
  -m "feat(shop-public): 공개주소 slug 정규화 충돌 방지 - 구분기호/대소문자 무시 유니크(canonical) [Phase61]" \
  -m "$CO" -- "${FILES[@]}"

echo "== push origin main =="
git push origin main

echo "API_SLUG_CANONICAL_DONE"
git log --oneline -1
