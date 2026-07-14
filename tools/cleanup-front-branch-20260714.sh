#!/bin/bash
# fix/trello-6a54ff4f 정리(-D, 이미 main 병합됨) + 원격 삭제 + root gitlink
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/ventago-app"
rm -f .git/*.lock 2>/dev/null || true
git branch -D fix/trello-6a54ff4f 2>/dev/null || echo "(로컬 브랜치 없음)"
git push origin --delete fix/trello-6a54ff4f 2>/dev/null || echo "(원격 브랜치 없음/이미 삭제)"
cd "$ROOT"
rm -f .git/*.lock 2>/dev/null || true
git add ventago-app
git -c user.name=Marcos.J.Kim -c user.email=junghokim10@gmail.com commit -m "chore: ventago-app gitlink → main(ee28a97) 반영" || echo "(변경 없음)"
git push origin main
echo "== DONE =="
