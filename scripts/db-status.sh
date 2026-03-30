#!/bin/bash

# PostgreSQL 데이터베이스 상태 확인 스크립트

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}📊 PostgreSQL 상태 확인${NC}"
echo ""

# Docker 컨테이너 확인
if docker ps --filter "name=postgres_db" --format "{{.Names}}" | grep -q "postgres_db"; then
    echo -e "${GREEN}✅ PostgreSQL 컨테이너가 실행 중입니다${NC}"
    echo ""
    docker ps --filter "name=postgres_db" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""
    
    # 연결 테스트
    echo -e "${BLUE}🔗 연결 테스트 중...${NC}"
    if docker exec postgres_db pg_isready -U postgres > /dev/null 2>&1; then
        echo -e "${GREEN}✅ 데이터베이스 연결 성공${NC}"
    else
        echo -e "${RED}❌ 데이터베이스 연결 실패${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  PostgreSQL 컨테이너가 실행되지 않고 있습니다${NC}"
    echo ""
    echo -e "${YELLOW}💡 시작하려면:${NC}"
    echo "   ./scripts/db-start.sh"
    echo "   또는"
    echo "   npm run db:start"
fi

