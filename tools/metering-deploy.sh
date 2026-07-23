#!/bin/bash
# Clientes metering (admin-console.service 확장) — tsc 통과분 커밋+push
set -e
cd "$(dirname "$0")/../api-ventago"
FOOTER="Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
npx tsc --noEmit -p tsconfig.build.json
echo "TSC_OK"
git add src/app/admin-console/admin-console.service.ts
git commit -m "feat(admin-console): tenants 사용량 계측 확장 — 오늘/이달 VTO·WhatsApp·Fac.E, días activos(히트맵), 활성 모듈 6종

Clientes 탭(사장 전용) '오늘/이번 달 사용 상태' 대시보드용. read-only 집계(pool 안전).

$FOOTER"
git push origin main
echo "METERING_PUSH_OK"
git log --oneline -1
