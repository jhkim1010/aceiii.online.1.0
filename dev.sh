#!/bin/bash

# VentaGO 개발 서버 실행 스크립트
# 사용법: ./dev.sh 또는 bash dev.sh

echo "🚀 VentaGO 개발 서버 시작 중..."

# 색상 정의
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 루트 의존성 확인 (concurrently 포함)
if [ ! -d "node_modules" ]; then
    echo -e "${YELLOW}⚠️  의존성이 설치되지 않았습니다. 설치 중...${NC}"
    npm install
fi

echo -e "${GREEN}✅ 의존성 확인 완료${NC}"
echo ""
echo -e "${BLUE}📡 백엔드 API: http://localhost:5002/api${NC}"
echo -e "${BLUE}🌐 프론트엔드: http://localhost:3050${NC}"
echo -e "${BLUE}🖨️  프린트 에이전트: print-agent${NC}"
echo ""
echo "세 모듈을 동시에 실행합니다..."
echo ""

# 동시 실행 (API + App + Print Agent)
npm run dev:all

