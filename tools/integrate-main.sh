#!/bin/bash
# main 통합 + 배포 push + feature 브랜치 정리 (멱등 — 재실행 안전)
set -e
cd "$(dirname "$0")/.."
BR=feat/factura-electronica
MSG_FOOTER="Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"

integrate() {
  local label="$1" cmsg="$2"
  echo "════ $label ════"
  if git show-ref --verify --quiet "refs/heads/$BR"; then
    git checkout "$BR"
    git add -A
    git diff --cached --quiet || git commit -m "$cmsg

$MSG_FOOTER"
  fi
  git checkout main
  git pull origin main --ff-only
  if git show-ref --verify --quiet "refs/heads/$BR"; then
    git merge --no-ff "$BR" -m "merge: $BR → main

$MSG_FOOTER" || { echo "MERGE_CONFLICT in $label"; exit 1; }
  fi
  git push origin main
  git push origin --delete "$BR" 2>/dev/null || true
  git branch -D "$BR" 2>/dev/null || true
}

(cd api-ventago && integrate "api-ventago" "fix: admin-console 스키마 수정 + suspended-sales 보안 + AFIP 잔여 작업")
(cd ventago-app && integrate "ventago-app" "fix: Descargas 카드 lint 정리")
integrate "root" "feat: superadmin 앱 안정화(keychain/파싱) + agent-runner 확장 + 배포 워크플로우"
echo "════ 완료 ════"
git log --oneline -3
git branch -a | head
