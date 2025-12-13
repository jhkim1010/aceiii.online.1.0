#!/bin/bash

# VentaGO 개발 서버 실행 스크립트
# 사용법: ./dev.sh 또는 bash dev.sh

echo "🚀 VentaGO 개발 서버 시작 중..."

# 색상 정의
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 백엔드 의존성 확인
if [ ! -d "api-ventago/node_modules" ]; then
    echo -e "${YELLOW}⚠️  백엔드 의존성이 설치되지 않았습니다. 설치 중...${NC}"
    cd api-ventago && npm install && cd ..
fi

# 프론트엔드 의존성 확인
if [ ! -d "ventago-app/node_modules" ]; then
    echo -e "${YELLOW}⚠️  프론트엔드 의존성이 설치되지 않았습니다. 설치 중...${NC}"
    cd ventago-app && npm install && cd ..
fi

echo -e "${GREEN}✅ 의존성 확인 완료${NC}"
echo ""
echo -e "${BLUE}📡 백엔드 API: http://localhost:5002/api${NC}"
echo -e "${BLUE}🌐 프론트엔드: http://localhost:3000${NC}"
echo ""
echo "두 서버를 동시에 실행합니다..."
echo ""

# 동시 실행
npm run dev

