#!/bin/bash
# 2026-07-11 main 통합 (멱등 — 재실행 안전)
#  - ventago-app: main push (ahead 1: repaso Ticket→Print Agent) + 병합완료된 fix/trello-6a4e6bae 삭제
#  - root: print-agent 흐림/디더 픽스 + 서브모듈 포인터 + trello-inbox 커밋 → push
#  - api-ventago: 클린/main 단일 — 작업 없음
set -e
cd "$(dirname "$0")/.."

FOOTER="Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014hCqSWJpm9VTJsyqLJ31je"

echo "════ ventago-app ════"
git -C ventago-app checkout main
git -C ventago-app push origin main
# fix/trello-6a4e6bae — main 에 완전 병합 확인됨(577fbdf 동일 커밋). 로컬 전용 브랜치.
git -C ventago-app branch -d fix/trello-6a4e6bae 2>/dev/null && echo "브랜치 삭제: fix/trello-6a4e6bae" || echo "브랜치 이미 없음"

echo "════ root ════"
git add -A
git diff --cached --quiet || git commit -m "fix(print-agent): 영수증 흐림/디더 수정 — 순수 흑백 이진화 + 회색 전면 제거 + 본문 굵게

- renderer-engine: capturePage 결과를 threshold 128 순수 흑/백 이진화 → 하프톤 디더 원천 차단
- formatter: #1a1a1a 등 중간 회색 전부 #000 + body bold (invoice/temp 공통)
- win-printer: 인쇄 img image-rendering:pixelated — 리샘플 회색 재생성 방지
- ventago-app 서브모듈 포인터 갱신 (repaso Ticket → Print Agent 라우팅)
- trello-inbox 동기화 결과 + 문서/러너 잡 추가

$FOOTER"
git push origin main

echo "════ 완료 ════"
git log --oneline -2
git -C ventago-app log --oneline -1
echo "-- ventago-app branches --"
git -C ventago-app branch
