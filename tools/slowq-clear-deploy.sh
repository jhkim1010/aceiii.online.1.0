#!/bin/bash
# 진단 slow-queries 수동 clear 엔드포인트 — tsc 검증 후에만 커밋+push (실패 시 배포 중단)
set -e
cd "$(dirname "$0")/../api-ventago"
FOOTER="Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
echo "--- eslint(비게이팅) ---"
(npx eslint src/app/diagnostics/*.ts --fix 2>&1 | tail -8) || true
echo "--- tsc (게이트) ---"
npx tsc --noEmit -p tsconfig.build.json
echo "TSC_OK"
git add src/app/diagnostics/slow-query-buffer.ts src/app/diagnostics/diagnostics.service.ts src/app/diagnostics/diagnostics.controller.ts
git commit -m "feat(diagnostics): slow-queries 수동 clear 엔드포인트(DELETE) + 인메모리 버퍼 비우기

superadmin 이 진단 화면에서 느린쿼리 로그를 완전히 비우고 이후 새로 쌓이는 것만 보도록.

$FOOTER"
git push origin main
echo "DEPLOY2_OK"
git log --oneline -1
