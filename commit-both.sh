#!/bin/bash

# 두 서브모듈에 동일한 커밋 메시지로 커밋하는 스크립트
# 사용법: ./commit-both.sh "커밋 메시지"

if [ -z "$1" ]; then
    echo "사용법: ./commit-both.sh \"커밋 메시지\""
    exit 1
fi

COMMIT_MSG="$1"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "두 서브모듈에 커밋 시작..."
echo "커밋 메시지: $COMMIT_MSG"
echo "=========================================="

# api-ventago 커밋
echo ""
echo "--- api-ventago 커밋 중 ---"
cd "$ROOT_DIR/api-ventago"

# 변경사항이 있는지 확인
if [ -n "$(git status --porcelain)" ]; then
    git add .
    git commit -m "$COMMIT_MSG"
    echo "✓ api-ventago 커밋 완료"
else
    echo "⚠ api-ventago: 커밋할 변경사항이 없습니다"
fi

# ventago-app 커밋
echo ""
echo "--- ventago-app 커밋 중 ---"
cd "$ROOT_DIR/ventago-app"

# 변경사항이 있는지 확인
if [ -n "$(git status --porcelain)" ]; then
    git add .
    git commit -m "$COMMIT_MSG"
    echo "✓ ventago-app 커밋 완료"
else
    echo "⚠ ventago-app: 커밋할 변경사항이 없습니다"
fi

echo ""
echo "=========================================="
echo "커밋 완료!"
echo "=========================================="
echo ""
echo "다음 명령어로 push할 수 있습니다:"
echo "  cd api-ventago && git push"
echo "  cd ventago-app && git push"
echo ""
echo "또는 push-both.sh 스크립트를 사용하세요:"
echo "  ./push-both.sh"
