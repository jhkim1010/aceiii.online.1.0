#!/usr/bin/env bash
# =============================================================================
# 로컬 dev 환경 종합 점검 — Phase 26 Wave 5 외상 시스템 포함
# =============================================================================
# 점검 항목:
#   1. Node.js 버전 (18 또는 20)
#   2. 포트 (5002, 3050) 점유 여부
#   3. 로컬 PG18 (5432) 접속 + Phase 26 시드 상태
#   4. MANUALES_DIR 환경변수 + manuales 폴더
#   5. workspaces node_modules
#   6. .env 파일들
# =============================================================================

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()    { echo -e "${GREEN}✅ $1${NC}"; }
fail()  { echo -e "${RED}❌ $1${NC}"; }
warn()  { echo -e "${YELLOW}⚠️  $1${NC}"; }
info()  { echo -e "${BLUE}ℹ  $1${NC}"; }
section() { echo; echo -e "${BLUE}━━━━━━━━━━ $1 ━━━━━━━━━━${NC}"; }

# ─── 1. Node 버전 ────────────────────────────────────────────────────────────
section "1. Node.js 버전"
NODE_VER=$(node -v 2>/dev/null | sed 's/^v//' | cut -d. -f1 || echo "0")
if [ "$NODE_VER" = "18" ] || [ "$NODE_VER" = "20" ]; then
    ok "Node.js $(node -v)"
else
    fail "Node.js v${NODE_VER} (Next.js 13 은 18 또는 20 필요)"
fi

# ─── 2. 포트 점유 ────────────────────────────────────────────────────────────
section "2. 포트 점유 (이전 dev 잔여 프로세스 확인)"
for PORT in 5002 3050 5001; do
    PIDS=$(lsof -ti :${PORT} -sTCP:LISTEN 2>/dev/null || true)
    if [ -n "$PIDS" ]; then
        warn "포트 $PORT 점유 중 (PID: $PIDS) — dev.sh 실행 시 자동 정리됨"
    else
        ok "포트 $PORT 비어있음"
    fi
done

# ─── 3. 로컬 PG18 ─────────────────────────────────────────────────────────────
section "3. 로컬 PostgreSQL (5432) Phase 26 상태"
if ! psql -h localhost -p 5432 -U postgres -d ventago -c "SELECT 1" >/dev/null 2>&1; then
    fail "로컬 ventago DB 접속 실패 (psql -h localhost -p 5432 -U postgres -d ventago)"
    info "  Postgres 가 실행 중인지 확인: brew services list | grep postgres"
else
    ok "ventago DB 접속 OK"

    PHASE26_REPORT=$(psql -h localhost -p 5432 -U postgres -d ventago -A -t -F '|' -c "
      SELECT
        (SELECT COUNT(*) FROM information_schema.tables WHERE table_name='credit_ledger'),
        (SELECT COUNT(*) FROM information_schema.tables WHERE table_name='credit_payments'),
        (SELECT COUNT(*) FROM information_schema.tables WHERE table_name='sale_senias'),
        (SELECT COUNT(*) FROM information_schema.columns WHERE table_name='store_clients'
           AND column_name IN ('senia_balance','favor_balance','credit_term_days','credit_status','last_payment_at')),
        (SELECT COUNT(*) FROM information_schema.columns WHERE table_name='stores' AND column_name='senia_ui_mode'),
        (SELECT COUNT(*) FROM payment_methods WHERE store_id IS NULL AND slug IN ('credito','favor','senia')),
        (SELECT COUNT(*) FROM modules WHERE slug='cuentas-corrientes'),
        (SELECT COUNT(*) FROM functions f JOIN modules m ON m.id=f.module_id WHERE m.slug='cuentas-corrientes'),
        (SELECT COUNT(*) FROM role_functions rf JOIN functions f ON f.id=rf.function_id JOIN modules m ON m.id=f.module_id WHERE m.slug='cuentas-corrientes')
    " 2>/dev/null | tr -d ' ')

    IFS='|' read -r T_LEDGER T_PAY T_SEN SC_COLS S_UI PM_GLOB M_CC F_CC RF_CC <<< "$PHASE26_REPORT"

    [ "$T_LEDGER" = "1" ] && ok "credit_ledger 테이블 존재" || fail "credit_ledger 테이블 없음"
    [ "$T_PAY" = "1" ] && ok "credit_payments 테이블 존재" || fail "credit_payments 테이블 없음"
    [ "$T_SEN" = "1" ] && ok "sale_senias 테이블 존재" || fail "sale_senias 테이블 없음"
    [ "$SC_COLS" = "5" ] && ok "store_clients 신규 5컬럼 OK" || fail "store_clients 컬럼 부족 ($SC_COLS/5)"
    [ "$S_UI" = "1" ] && ok "stores.senia_ui_mode OK" || fail "stores.senia_ui_mode 누락"
    [ "$PM_GLOB" -ge "3" ] && ok "payment_methods 글로벌 시드 OK ($PM_GLOB)" || fail "payment_methods 시드 부족 ($PM_GLOB/3)"
    [ "$M_CC" = "1" ] && ok "modules 'cuentas-corrientes' OK" || fail "modules 'cuentas-corrientes' 누락 — 실행: psql ... < api-ventago/migrations/phase26-wave5-module-seed.sql"
    [ "$F_CC" -ge "1" ] && ok "functions 'cuentas-corrientes' 매핑 OK ($F_CC)" || fail "functions 매핑 누락 — 실행: psql ... < api-ventago/migrations/phase26-wave5-functions-seed.sql"
    [ "$RF_CC" -ge "1" ] && ok "role_functions 매핑 OK ($RF_CC)" || fail "role_functions 매핑 누락 — 사이드바에 표시 안 됨"
fi

# ─── 4. MANUALES_DIR / manuales/ ─────────────────────────────────────────────
section "4. manuales/ 폴더 + MANUALES_DIR 환경변수"
if [ -d "$ROOT/manuales" ]; then
    MD_COUNT=$(find "$ROOT/manuales" -maxdepth 1 -name "*.md" | wc -l | tr -d ' ')
    ok "manuales/ 폴더 존재 (.md 파일 ${MD_COUNT}개)"
else
    fail "manuales/ 폴더 없음"
fi

if grep -q "^MANUALES_DIR=" "$ROOT/api-ventago/.env" 2>/dev/null; then
    MD_DIR=$(grep "^MANUALES_DIR=" "$ROOT/api-ventago/.env" | cut -d= -f2)
    ok "api-ventago/.env: MANUALES_DIR=$MD_DIR"
else
    warn "api-ventago/.env 에 MANUALES_DIR 미설정"
    info "  로컬 dev 에서 process.cwd()=api-ventago 라서 'api-ventago/manuales' 를 찾음 → 빈 폴더"
    info "  추가 권장: echo 'MANUALES_DIR=../manuales' >> api-ventago/.env"
fi

# ─── 5. node_modules ─────────────────────────────────────────────────────────
section "5. workspaces node_modules"
for WS in "" "api-ventago" "ventago-app" "print-agent" "zebra-agent" "vw-agent"; do
    if [ -z "$WS" ]; then
        TARGET="$ROOT/node_modules"
        LBL="root"
    else
        TARGET="$ROOT/$WS/node_modules"
        LBL="$WS"
    fi
    if [ -d "$TARGET" ]; then
        ok "$LBL/node_modules 존재"
    else
        # workspaces 호이스팅으로 일부는 비어있는 게 정상
        info "$LBL/node_modules 없음 (호이스팅된 경우 정상)"
    fi
done

# ─── 6. .env 파일들 ──────────────────────────────────────────────────────────
section "6. .env 파일"
for ENV in "api-ventago/.env" "ventago-app/.env" "ventago-app/.env.local"; do
    if [ -f "$ROOT/$ENV" ]; then
        ok "$ENV 존재"
    else
        info "$ENV 없음 (default 동작)"
    fi
done

# ─── 7. 운영 서버 동기화 상태 ────────────────────────────────────────────────
section "7. GitHub origin/main HEAD"
GH=$(cd "$ROOT/ventago-app" && git ls-remote origin main 2>/dev/null | awk '{print $1}' | head -c 12)
LOCAL=$(cd "$ROOT/ventago-app" && git rev-parse --short=12 HEAD)
if [ "$GH" = "$LOCAL" ]; then
    ok "ventago-app 로컬 HEAD == GitHub origin/main ($LOCAL)"
else
    warn "로컬 ventago-app HEAD ($LOCAL) ≠ GitHub origin/main ($GH)"
fi

GH_API=$(cd "$ROOT/api-ventago" && git ls-remote origin main 2>/dev/null | awk '{print $1}' | head -c 12)
LOCAL_API=$(cd "$ROOT/api-ventago" && git rev-parse --short=12 HEAD)
if [ "$GH_API" = "$LOCAL_API" ]; then
    ok "api-ventago 로컬 HEAD == GitHub origin/main ($LOCAL_API)"
else
    warn "로컬 api-ventago HEAD ($LOCAL_API) ≠ GitHub origin/main ($GH_API)"
fi

echo
echo -e "${GREEN}━━━━━━━━━━ 점검 완료 ━━━━━━━━━━${NC}"
echo -e "${YELLOW}부족한 항목이 있다면 위 메시지의 해결 방법을 참고하세요.${NC}"
