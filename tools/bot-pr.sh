#!/usr/bin/env bash
# 봇(클라우드 세션)이 수정본을 브랜치로 올리고 PR 을 연다.
# 원칙: main 직접 push 금지 — 항상 PR 경유로 사람이 검토·머지한다.
# 사전조건: gh 인증(GitHub 커넥터 또는 fine-grained PAT) + 파일 수정은 이미 끝난 상태.
# 사용법: bot-pr.sh <branch> "<PR 제목>" "<PR 본문>"
set -euo pipefail

BRANCH="${1:?branch 이름 필요 (예: bot/trello-card-1234)}"
TITLE="${2:?PR 제목 필요}"
BODY="${3:-자동 생성 PR — 봇 유지보수 루프}"

# eslint 게이트 (있으면). 실패하면 PR 안 만들고 중단.
if [ -f package.json ] && grep -q '"lint"' package.json; then
  echo "[bot-pr] eslint 실행..."
  npm run lint
fi

BASE="$(git symbolic-ref --short HEAD 2>/dev/null || echo main)"
git fetch origin --quiet || true
git switch -c "$BRANCH"
git add -A
git commit -m "$TITLE"
git push -u origin "$BRANCH"

# gh CLI 로 PR 생성 (커넥터/PAT 인증 전제)
gh pr create --base "$BASE" --head "$BRANCH" --title "$TITLE" --body "$BODY"
echo "[bot-pr] PR 생성 완료 (base=$BASE, head=$BRANCH)"
