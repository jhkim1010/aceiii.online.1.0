#!/bin/bash

# 루트 모노레포 + 두 서브 저장소(api-ventago, ventago-app)에 동시에 push하는 스크립트
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
echo "루트 + 두 서브 저장소에 push 시작..."
echo "브랜치: $BRANCH"
echo "=========================================="

# ventago-app ESLint 사전 검증 (빌드 실패 방지)
echo ""
echo "--- ventago-app ESLint 검증 ---"
cd "$ROOT_DIR/ventago-app"
if npx next lint 2>&1 | grep -q "Error:"; then
    echo "✗ ESLint Error 발견! push를 중단합니다."
    echo "  수정 후 다시 시도하세요: cd ventago-app && npx next lint"
    npx next lint 2>&1 | grep "Error:"
    exit 1
else
    echo "✓ ESLint 통과"
fi

# 자동 커밋 + push 함수
auto_commit_push() {
    local DIR="$1"
    local NAME="$2"
    cd "$DIR"

    echo ""
    echo "--- $NAME ---"

    CURRENT_BRANCH=$(git branch --show-current)

    # 변경사항 감지 (staged + unstaged + untracked)
    if [ -n "$(git status --porcelain)" ]; then
        echo "변경사항 감지 → 자동 커밋"
        git add -A
        git commit -m "chore: auto-commit $NAME $(date '+%Y-%m-%d %H:%M')"
        echo "✓ $NAME 커밋 완료"
    else
        echo "변경사항 없음"
    fi

    # push
    if git push -u origin "$CURRENT_BRANCH"; then
        echo "✓ $NAME push 완료"
    else
        echo "✗ $NAME push 실패"
        exit 1
    fi
}

# 서브레포 자동 커밋 + push
auto_commit_push "$ROOT_DIR/api-ventago" "api-ventago"
auto_commit_push "$ROOT_DIR/ventago-app" "ventago-app"

# root: 서브모듈 포인터 업데이트 + 기타 변경 커밋 + push
echo ""
echo "--- root (ACE_online_1.0) ---"
cd "$ROOT_DIR"
git add api-ventago ventago-app
if [ -n "$(git status --porcelain)" ]; then
    git add -A
    git commit -m "chore: bump submodules + auto-commit $(date '+%Y-%m-%d %H:%M')"
    echo "✓ root 커밋 완료"
fi

CURRENT_BRANCH=$(git branch --show-current)
if git push -u origin "$CURRENT_BRANCH"; then
    echo "✓ root push 완료"
else
    echo "✗ root push 실패"
    exit 1
fi

# print-agent 변경사항 감지 → 커밋 + 태그 + 릴리즈 빌드 트리거
echo ""
echo "--- print-agent 변경 감지 ---"
cd "$ROOT_DIR"
PRINT_CHANGES=$(git diff --name-only -- print-agent/ 2>/dev/null)
PRINT_UNTRACKED=$(git ls-files --others --exclude-standard -- print-agent/ 2>/dev/null)

if [ -n "$PRINT_CHANGES" ] || [ -n "$PRINT_UNTRACKED" ]; then
    echo "print-agent 변경 감지됨:"
    echo "$PRINT_CHANGES"
    echo "$PRINT_UNTRACKED"

    git add print-agent/
    git commit -m "feat(print-agent): update print agent"

    # 최신 태그에서 patch 버전 자동 증가
    LATEST_TAG=$(git tag --list 'print-agent-v*' --sort=-version:refname | head -1)
    if [ -z "$LATEST_TAG" ]; then
        NEW_TAG="print-agent-v1.0.0"
    else
        # v1.0.0 → 1.0.0 → patch+1
        VERSION="${LATEST_TAG#print-agent-v}"
        MAJOR=$(echo "$VERSION" | cut -d. -f1)
        MINOR=$(echo "$VERSION" | cut -d. -f2)
        PATCH=$(echo "$VERSION" | cut -d. -f3)
        PATCH=$((PATCH + 1))
        NEW_TAG="print-agent-v${MAJOR}.${MINOR}.${PATCH}"
    fi

    echo "새 태그: $NEW_TAG"
    git tag "$NEW_TAG"

    if git push origin main --tags; then
        echo "✓ print-agent push + 릴리즈 빌드 트리거 완료 ($NEW_TAG)"
    else
        echo "✗ print-agent push 실패"
        exit 1
    fi
else
    echo "✓ print-agent 변경 없음 — 스킵"
fi

echo ""
echo "=========================================="
echo "모든 push 완료! (api-ventago + ventago-app + root + print-agent)"
echo "=========================================="
