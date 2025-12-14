#!/bin/bash

# PostgreSQL 데이터베이스 시작 스크립트

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🐳 Docker 상태 확인 중...${NC}"

# Docker가 실행 중인지 확인
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}❌ Docker가 실행되지 않고 있습니다.${NC}"
    echo -e "${YELLOW}💡 Docker Desktop을 시작해주세요:${NC}"
    echo "   1. Docker Desktop 앱을 실행하세요"
    echo "   2. 또는 터미널에서: open -a Docker"
    echo ""
    echo -e "${YELLOW}또는 로컬 PostgreSQL을 사용하려면:${NC}"
    echo "   brew services start postgresql@15"
    exit 1
fi

echo -e "${GREEN}✅ Docker가 실행 중입니다${NC}"
echo ""

echo -e "${BLUE}📦 PostgreSQL 컨테이너 시작 중...${NC}"
cd "$(dirname "$0")/../api-ventago/docker"

docker-compose -f docker-compose-postgresql.yml up -d

echo ""
echo -e "${GREEN}✅ PostgreSQL이 시작되었습니다!${NC}"
echo ""
echo -e "${BLUE}📊 컨테이너 상태:${NC}"
docker ps --filter "name=postgres_db"

echo ""
echo -e "${BLUE}🔗 연결 정보:${NC}"
echo "   Host: localhost"
echo "   Port: 54321"
echo "   Database: ventago"
echo "   User: postgres"
echo "   Password: postgres"
echo ""
echo -e "${YELLOW}💡 마이그레이션 실행:${NC}"
echo "   cd api-ventago && npm run migrate"

