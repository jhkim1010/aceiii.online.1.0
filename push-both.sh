#!/bin/bash

# 세 서브모듈에 동시에 push하는 스크립트
# 사용법: ./push-both.sh [브랜치명] (기본값: 현재 브랜치)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 브랜치명 확인 (기본값: 현재 브랜치)
if [ -z "$1" ]; then
    cd "$ROOT_DIR/api-ventago"
    BRANCH=$(git branch --show-current)
else
    BRANCH="$1"
fi

echo "=========================================="
echo "두 서브모듈에 push 시작..."
echo "브랜치: $BRANCH"
echo "=========================================="

# api-ventago push
echo ""
echo "--- api-ventago push 중 ---"
cd "$ROOT_DIR/api-ventago"
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "$BRANCH" ]; then
    echo "⚠ 현재 브랜치($CURRENT_BRANCH)와 지정한 브랜치($BRANCH)가 다릅니다."
    read -p "계속하시겠습니까? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

if git push -u origin "$CURRENT_BRANCH"; then
    echo "✓ api-ventago push 완료"
else
    echo "✗ api-ventago push 실패"
    exit 1
fi

# ventago-app push
echo ""
echo "--- ventago-app push 중 ---"
cd "$ROOT_DIR/ventago-app"
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "$BRANCH" ]; then
    echo "⚠ 현재 브랜치($CURRENT_BRANCH)와 지정한 브랜치($BRANCH)가 다릅니다."
    read -p "계속하시겠습니까? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

if git push -u origin "$CURRENT_BRANCH"; then
    echo "✓ ventago-app push 완료"
else
    echo "✗ ventago-app push 실패"
    exit 1
fi

echo ""
echo "=========================================="
echo "모든 push 완료!"
echo "=========================================="
