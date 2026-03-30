#!/bin/bash

# VentaGO 모노레포 Git 푸시 스크립트
# 사용법:
#   ./scripts/git-push.sh                          → 전체 푸시 (기본 메시지)
#   ./scripts/git-push.sh "커밋 메시지"              → 전체 푸시 (커스텀 메시지)
#   ./scripts/git-push.sh api "커밋 메시지"          → 백엔드만 푸시
#   ./scripts/git-push.sh app "커밋 메시지"          → 프론트엔드만 푸시
#   ./scripts/git-push.sh root "커밋 메시지"         → 루트만 푸시

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE_DIR"

# 인자 파싱: 첫 인자가 타겟인지 메시지인지 판단
TARGET="all"
MSG=""

if [[ "$1" == "all" || "$1" == "root" || "$1" == "api" || "$1" == "app" ]]; then
    TARGET="$1"
    MSG="$2"
else
    MSG="$1"
fi

# 기본 메시지
if [ -z "$MSG" ]; then
    MSG="chore: update $(date '+%Y-%m-%d %H:%M')"
fi

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN} VentaGO Git Push${NC}"
echo -e "${GREEN} 타겟: ${YELLOW}${TARGET}${GREEN}  메시지: ${YELLOW}${MSG}${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

push_repo() {
    local name="$1"
    local dir="$2"

    echo -e "${BLUE}📦 [${name}] 확인 중...${NC}"

    if [ -n "$dir" ]; then
        cd "$BASE_DIR/$dir"
    fi

    # 변경사항 확인
    local changes=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    if [ "$changes" -eq 0 ]; then
        echo -e "${YELLOW}  ⚠️  변경사항 없음 — 건너뜀${NC}"
        echo ""
        cd "$BASE_DIR"
        return 0
    fi

    # 변경 파일 목록 표시
    echo -e "  변경된 파일 ${YELLOW}${changes}${NC}개:"
    git status --porcelain | head -10 | while read line; do
        echo -e "    ${line}"
    done
    if [ "$changes" -gt 10 ]; then
        echo -e "    ... 외 $((changes - 10))개"
    fi

    # 커밋 & 푸시
    git add .
    git commit -m "$MSG" || true
    git push origin main 2>/dev/null || git push origin master 2>/dev/null || {
        echo -e "${RED}  ❌ 푸시 실패 — 브랜치를 확인하세요${NC}"
        cd "$BASE_DIR"
        return 1
    }

    echo -e "${GREEN}  ✅ 푸시 완료${NC}"
    echo ""
    cd "$BASE_DIR"
}

# 실행
case "$TARGET" in
    "all")
        push_repo "백엔드 (api-ventago)" "api-ventago"
        push_repo "프론트엔드 (ventago-app)" "ventago-app"
        push_repo "루트" ""
        ;;
    "api")
        push_repo "백엔드 (api-ventago)" "api-ventago"
        ;;
    "app")
        push_repo "프론트엔드 (ventago-app)" "ventago-app"
        ;;
    "root")
        push_repo "루트" ""
        ;;
esac

echo -e "${GREEN}✨ 완료!${NC}"
