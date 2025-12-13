#!/bin/bash

# VentaGO 모노레포 Git 푸시 스크립트
# 사용법: ./scripts/git-push.sh [all|root|api|app]

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

ROOT_REPO="https://github.com/jhkim1010/aceiii.online.1.0.git"
API_REPO="https://github.com/WillAular/api-ventago.git"
APP_REPO="https://github.com/WillAular/ventago-app.git"

push_root() {
    echo -e "${BLUE}📦 루트 저장소 푸시 중...${NC}"
    git add .
    if git diff --staged --quiet; then
        echo -e "${YELLOW}⚠️  루트에 변경사항이 없습니다.${NC}"
    else
        git commit -m "chore: 모노레포 통합 업데이트" || true
        git push origin main
        echo -e "${GREEN}✅ 루트 저장소 푸시 완료${NC}"
    fi
}

push_api() {
    echo -e "${BLUE}📦 백엔드 저장소 푸시 중...${NC}"
    cd api-ventago
    git add .
    if git diff --staged --quiet; then
        echo -e "${YELLOW}⚠️  백엔드에 변경사항이 없습니다.${NC}"
    else
        git commit -m "chore: 모노레포에서 업데이트" || true
        git push origin main || git push origin master
        echo -e "${GREEN}✅ 백엔드 저장소 푸시 완료${NC}"
    fi
    cd ..
}

push_app() {
    echo -e "${BLUE}📦 프론트엔드 저장소 푸시 중...${NC}"
    cd ventago-app
    git add .
    if git diff --staged --quiet; then
        echo -e "${YELLOW}⚠️  프론트엔드에 변경사항이 없습니다.${NC}"
    else
        git commit -m "chore: 모노레포에서 업데이트" || true
        git push origin main || git push origin master
        echo -e "${GREEN}✅ 프론트엔드 저장소 푸시 완료${NC}"
    fi
    cd ..
}

case "${1:-all}" in
    "all")
        echo -e "${GREEN}🚀 모든 저장소 푸시 시작...${NC}"
        push_root
        push_api
        push_app
        echo -e "${GREEN}✨ 모든 저장소 푸시 완료!${NC}"
        ;;
    "root")
        push_root
        ;;
    "api")
        push_api
        ;;
    "app")
        push_app
        ;;
    *)
        echo "사용법: $0 [all|root|api|app]"
        echo "  all  - 모든 저장소 푸시 (기본값)"
        echo "  root - 루트 저장소만 푸시"
        echo "  api  - 백엔드 저장소만 푸시"
        echo "  app  - 프론트엔드 저장소만 푸시"
        exit 1
        ;;
esac

