#!/bin/bash
# ventago-app: fix/trello-6a54ff4f → main ff 병합 + push + 브랜치 정리 + root gitlink
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/ventago-app"
rm -f .git/*.lock .git/refs/heads/*.lock 2>/dev/null || true
git checkout main || true
git checkout main
git merge --ff-only fix/trello-6a54ff4f
git push origin main
git branch -d fix/trello-6a54ff4f
git push origin --delete fix/trello-6a54ff4f 2>/dev/null || echo "(원격 브랜치 없음)"
git log --oneline -3

cd "$ROOT"
rm -f .git/index.lock .git/HEAD.lock 2>/dev/null || true
git add ventago-app
git -c user.name=Marcos.J.Kim -c user.email=junghokim10@gmail.com commit -m "chore: ventago-app gitlink → main(ee28a97) 병합 반영" || echo "(변경 없음)"
git push origin main
echo "== DONE =="
