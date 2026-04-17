#!/bin/bash

# VentaGO 개발 서버 실행 스크립트
# 순서: 1) 백엔드 + 프론트 동시 시작 → 2) 백엔드 5002 포트 listen 대기 → 3) Print Agent 실행
# 사용법: ./dev.sh 또는 bash dev.sh

set -e

# 색상 정의
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "🚀 VentaGO 개발 서버 시작 중..."

# ─── Step 0: 이전 세션의 좀비 프로세스/포트 정리 ─────────────────────────────
# concurrently의 trap이 손자 프로세스(next dev / jest-worker / nest start)까지
# 항상 정리하진 못해서 반복 실행 시 포트 충돌로 프론트 컴파일이 조용히 실패함.
echo -e "${YELLOW}🧹 이전 세션 좀비 프로세스 정리 중...${NC}"

# 포트 점유 프로세스 강제 종료 (5002=API, 3050=프론트, 5001=도커 프론트)
for PORT in 3050 5002 5001; do
    PIDS_ON_PORT=$(lsof -ti :${PORT} -sTCP:LISTEN 2>/dev/null || true)
    if [ -n "$PIDS_ON_PORT" ]; then
        echo -e "${YELLOW}  → 포트 ${PORT} 점유 프로세스 종료: ${PIDS_ON_PORT}${NC}"
        kill -9 $PIDS_ON_PORT 2>/dev/null || true
    fi
done

# stale Next.js / Nest / concurrently 프로세스 정리 (현재 쉘 제외)
pkill -9 -f "next dev" 2>/dev/null || true
pkill -9 -f "next/dist/compiled/jest-worker" 2>/dev/null || true
pkill -9 -f "nest start" 2>/dev/null || true
pkill -9 -f "concurrently.*dev:api.*dev:app" 2>/dev/null || true

sleep 1
echo -e "${GREEN}✅ 좀비 정리 완료${NC}"
echo ""

# 루트 의존성 확인 (concurrently 포함)
if [ ! -d "node_modules" ]; then
    echo -e "${YELLOW}⚠️  의존성이 설치되지 않았습니다. 설치 중...${NC}"
    npm install
fi

echo -e "${GREEN}✅ 의존성 확인 완료${NC}"
echo ""
echo -e "${BLUE}📡 백엔드 API: http://localhost:5002/api${NC}"
echo -e "${BLUE}🌐 프론트엔드: http://localhost:3050${NC}"
echo -e "${BLUE}🖨️  프린트 에이전트: 백엔드 부팅 완료 후 자동 실행${NC}"
echo -e "${BLUE}🏷️  Zebra 에이전트: 백엔드 부팅 완료 후 자동 실행${NC}"
echo ""

# 종료 시 자식 프로세스 모두 정리
PIDS=()
cleanup() {
    echo ""
    echo -e "${YELLOW}🛑 종료 중... 모든 dev 프로세스 정리${NC}"
    for pid in "${PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            # 프로세스 그룹 전체 종료 (자식의 자식까지)
            kill -TERM "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
        fi
    done
    wait 2>/dev/null || true
    exit 0
}
trap cleanup INT TERM EXIT

# ─── Step 1: 백엔드 + 프론트엔드 동시 시작 ──────────────────────────────────
echo -e "${BLUE}[1/3] 백엔드 + 프론트엔드 시작...${NC}"
# concurrently로 api와 app만 먼저 띄움 — print는 제외
npm run dev &
DEV_PID=$!
PIDS+=("$DEV_PID")

# ─── Step 2: 백엔드 5002 포트 listen 대기 ───────────────────────────────────
echo -e "${BLUE}[2/3] 백엔드(5002 포트) 부팅 대기 중...${NC}"
MAX_WAIT=120  # 최대 2분 대기
WAITED=0
while ! lsof -nP -iTCP:5002 -sTCP:LISTEN >/dev/null 2>&1; do
    if ! kill -0 "$DEV_PID" 2>/dev/null; then
        echo -e "${RED}❌ npm run dev 프로세스가 종료되었습니다. 로그를 확인하세요.${NC}"
        exit 1
    fi
    if [ "$WAITED" -ge "$MAX_WAIT" ]; then
        echo -e "${RED}❌ 백엔드가 ${MAX_WAIT}초 안에 부팅되지 않았습니다.${NC}"
        exit 1
    fi
    sleep 1
    WAITED=$((WAITED + 1))
    # 5초마다 진행 상황 표시
    if [ $((WAITED % 5)) -eq 0 ]; then
        echo -e "${YELLOW}  ⏳ 대기 중... (${WAITED}s)${NC}"
    fi
done

# 추가 안전장치 — HTTP 응답까지 확인 (NestJS가 listen 후 라우트 등록까지 마쳤는지)
echo -e "${YELLOW}  🔍 HTTP 응답 대기 중...${NC}"
HTTP_WAIT=0
while [ "$HTTP_WAIT" -lt 30 ]; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 http://127.0.0.1:5002/api 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" != "000" ]; then
        echo -e "${GREEN}  ✅ 백엔드 응답 확인: HTTP ${HTTP_CODE}${NC}"
        break
    fi
    sleep 1
    HTTP_WAIT=$((HTTP_WAIT + 1))
done

echo -e "${GREEN}✅ 백엔드 부팅 완료${NC}"

# ─── Step 2.5: 프론트엔드(3050) listen 대기 — Next.js 초기 컴파일 완료 확인 ──
echo -e "${BLUE}[2.5/3] 프론트엔드(3050 포트) 컴파일 대기 중...${NC}"
MAX_WAIT_FE=180  # Next.js 초기 컴파일은 오래 걸릴 수 있음 — 최대 3분
WAITED_FE=0
while ! lsof -nP -iTCP:3050 -sTCP:LISTEN >/dev/null 2>&1; do
    if ! kill -0 "$DEV_PID" 2>/dev/null; then
        echo -e "${RED}❌ dev 프로세스가 종료됐습니다. 위 로그에서 'Failed to compile' 또는 에러를 확인하세요.${NC}"
        exit 1
    fi
    if [ "$WAITED_FE" -ge "$MAX_WAIT_FE" ]; then
        echo -e "${RED}❌ 프론트엔드가 ${MAX_WAIT_FE}초 안에 부팅되지 않았습니다.${NC}"
        echo -e "${YELLOW}   수동 확인: cd ventago-app && rm -rf .next && npm run dev${NC}"
        exit 1
    fi
    sleep 1
    WAITED_FE=$((WAITED_FE + 1))
    if [ $((WAITED_FE % 10)) -eq 0 ]; then
        echo -e "${YELLOW}  ⏳ 컴파일 대기 중... (${WAITED_FE}s)${NC}"
    fi
done
echo -e "${GREEN}✅ 프론트엔드 부팅 완료: http://localhost:3050${NC}"

# ─── Step 3: Print Agent + Zebra Agent 실행 ─────────────────────────────────
echo -e "${BLUE}[3/3] Print Agent + Zebra Agent 시작...${NC}"
sleep 2  # 프론트 컴파일 안정화 여유
npm run dev:print &
PRINT_PID=$!
PIDS+=("$PRINT_PID")

npm run dev:zebra &
ZEBRA_PID=$!
PIDS+=("$ZEBRA_PID")

echo ""
echo -e "${GREEN}🎉 모든 dev 프로세스 실행 중${NC}"
echo -e "${BLUE}   백엔드/프론트엔드 PID: ${DEV_PID}${NC}"
echo -e "${BLUE}   Print Agent PID:      ${PRINT_PID}${NC}"
echo -e "${BLUE}   Zebra Agent PID:      ${ZEBRA_PID}${NC}"
echo -e "${YELLOW}   종료: Ctrl+C${NC}"
echo ""

# 어느 한 프로세스가 종료되면 전체 종료
wait -n "$DEV_PID" "$PRINT_PID" "$ZEBRA_PID" 2>/dev/null || wait
