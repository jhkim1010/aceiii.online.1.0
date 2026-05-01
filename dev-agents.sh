#!/bin/bash

# VentaGO Print Agent + Zebra Agent 실행 스크립트
# - 두 개의 Electron 앱(print-agent, zebra-agent)을 같이 띄움
# - 백엔드(5002)가 이미 떠 있어야 정상 연결 (먼저 ./dev.sh 실행)
# - 사용법: ./dev-agents.sh

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# ─── Node 버전 강제 (dev.sh 와 동일) ─────────────────────────────────────────
if [ -d "/usr/local/opt/node@20/bin" ]; then
    export PATH="/usr/local/opt/node@20/bin:$PATH"
elif [ -d "/usr/local/opt/node@18/bin" ]; then
    export PATH="/usr/local/opt/node@18/bin:$PATH"
fi

NODE_VER=$(node -v 2>/dev/null | sed 's/^v//' | cut -d. -f1)
if [ "$NODE_VER" != "18" ] && [ "$NODE_VER" != "20" ]; then
    echo -e "${RED}❌ Node.js 버전이 맞지 않습니다: v$(node -v)${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Node.js $(node -v) 사용${NC}"

# ─── 백엔드(5002) 가 떠있는지 확인 — 떠있지 않으면 안내만 하고 그래도 진행 ──
if lsof -nP -iTCP:5002 -sTCP:LISTEN >/dev/null 2>&1; then
    echo -e "${GREEN}✅ 백엔드(5002) 가 실행 중입니다.${NC}"
else
    echo -e "${YELLOW}⚠️  백엔드(5002) 가 실행 중이 아닙니다.${NC}"
    echo -e "${YELLOW}   다른 터미널에서 ./dev.sh 를 먼저 실행하는 것을 권장합니다.${NC}"
    echo -e "${YELLOW}   계속 진행하려면 5초 후 자동 시작 (Ctrl+C 로 취소)...${NC}"
    sleep 5
fi

echo ""
echo -e "${BLUE}🖨️  Print Agent + 🏷️  Zebra Agent 시작...${NC}"
echo -e "${YELLOW}   종료: Ctrl+C (양쪽 다 같이 종료됨)${NC}"
echo ""

# ─── 종료 시 자식 프로세스 정리 ──────────────────────────────────────────────
PIDS=()
cleanup() {
    echo ""
    echo -e "${YELLOW}🛑 종료 중... print/zebra agent 정리${NC}"
    for pid in "${PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill -TERM "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
        fi
    done

    # 추가 안전장치 — Electron 자식 프로세스 까지
    pkill -9 -f "print-agent.*electron" 2>/dev/null || true
    pkill -9 -f "zebra-agent.*electron" 2>/dev/null || true
    wait 2>/dev/null || true
    exit 0
}
trap cleanup INT TERM EXIT

# ─── Print Agent 시작 ────────────────────────────────────────────────────────
npm run dev:print &
PRINT_PID=$!
PIDS+=("$PRINT_PID")
echo -e "${GREEN}✅ Print Agent 시작 (PID: ${PRINT_PID})${NC}"

# ─── Zebra Agent 시작 ───────────────────────────────────────────────────────
npm run dev:zebra &
ZEBRA_PID=$!
PIDS+=("$ZEBRA_PID")
echo -e "${GREEN}✅ Zebra Agent 시작 (PID: ${ZEBRA_PID})${NC}"

echo ""
echo -e "${GREEN}🎉 두 에이전트 실행 중${NC}"
echo -e "${BLUE}   Print Agent PID: ${PRINT_PID}${NC}"
echo -e "${BLUE}   Zebra Agent PID: ${ZEBRA_PID}${NC}"
echo ""

# 어느 한 에이전트가 종료되면 전체 종료
wait -n "$PRINT_PID" "$ZEBRA_PID" 2>/dev/null || wait
