#!/bin/bash

# PostgreSQL 데이터베이스 중지 스크립트

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${BLUE}🛑 PostgreSQL 컨테이너 중지 중...${NC}"
cd "$(dirname "$0")/../api-ventago/docker"

docker-compose -f docker-compose-postgresql.yml down

echo -e "${GREEN}✅ PostgreSQL이 중지되었습니다${NC}"

