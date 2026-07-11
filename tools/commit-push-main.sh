#!/bin/bash
# main 직접 커밋+push (핫픽스/최적화 소규모 변경용)
set -e
cd "$(dirname "$0")/.."
FOOTER="Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"

cd api-ventago
git add -A
git diff --cached --quiet || git commit -m "perf(products): findAll hasMany include separate 분리 — JOIN 행폭발(90상품→489행)·hydration 150ms 제거

DB 실측 0.98ms vs 계측 155ms — 원인은 ORM hydration. EXPLAIN ANALYZE 검증 완료.

$FOOTER"
git push origin main
cd ..

git add -A
git diff --cached --quiet || git commit -m "chore: api-ventago 포인터 갱신 (products findAll 성능) + runner 잡 정리

$FOOTER"
git push origin main
echo "══ push 완료 ══"
git -C api-ventago log --oneline -1
