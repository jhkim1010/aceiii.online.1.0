#!/bin/bash
# 2026-07-14 마지막 정리 — 루트 잔여(러너 잡 파일·통합 스크립트) 커밋+push
set -e
cd "$(dirname "$0")/.."
rm -f .git/*.lock 2>/dev/null || true
git add -A
git -c user.name=Marcos.J.Kim -c user.email=junghokim10@gmail.com commit -m "chore: 러너 잡(판매원앱 빌드/mobile-test) + 2026-07-14 통합 스크립트 정리

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JX4xRJVBifRiMweJxdsiQM" || echo "(변경 없음)"
git push origin main
echo "== DONE =="; git log --oneline -1
