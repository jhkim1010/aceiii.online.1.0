#!/bin/bash
# ============================================================
# Ventago 배포 전 실행 스크립트
# 날짜: 2026-04-13
# 실행: cd ~/Trabajos_Programming/ACE_online_1.0 && bash pre-deploy.sh
#
# 구조:
#   - PostgreSQL: Docker 외부 (호스트에 직접 설치)
#   - api-ventago: Docker 컨테이너 (api_ventago)
#   - ventago-app: Docker 컨테이너
#   - Docker 네트워크: coolsistema_network
#     → 컨테이너 내부에서 DB 호스트는 'dbpostgres'
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Ventago 배포 전 스크립트 (2026-04-13)${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════${NC}"
echo ""

# ── 프로젝트 루트 확인 ──
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -d "api-ventago" ] || [ ! -d "ventago-app" ]; then
  echo -e "${RED}❌ 프로젝트 루트에서 실행해주세요 (api-ventago/, ventago-app/ 폴더 필요)${NC}"
  exit 1
fi

# ═══════════════════════════════════════════════════
# 1단계: DB 마이그레이션 (기존 컨테이너 이용)
# ═══════════════════════════════════════════════════
echo -e "${YELLOW}[1/5] DB 마이그레이션 — 성능 인덱스 추가${NC}"

# 기존 api_ventago 컨테이너가 살아있는지 확인
if docker ps --format '{{.Names}}' | grep -q '^api_ventago$'; then
  echo "      api_ventago 컨테이너 실행 중 → docker exec로 마이그레이션 실행"
  echo ""

  # [Phase 65 W7] 비밀번호를 이 파일에 두지 않는다 — 커밋되면 git 이력에 영구히 남는다.
  # 이 코드는 api_ventago 컨테이너 **안에서** 돌므로 앱이 이미 쓰는 DATABASE_PASSWORD 를
  # 그대로 읽는다. 값이 없으면 조용히 실패하지 않고 즉시 중단한다.
  docker exec api_ventago node -e "
const { Client } = require('pg');
if (!process.env.DATABASE_PASSWORD) {
  console.error('DATABASE_PASSWORD 가 컨테이너 환경에 없습니다. 마이그레이션을 중단합니다.');
  process.exit(1);
}
const c = new Client({
  host: 'dbpostgres',
  user: 'coolsistema',
  password: process.env.DATABASE_PASSWORD,
  database: 'ventago'
});

async function run() {
  await c.connect();
  console.log('DB 연결 성공');

  const existing = await c.query(
    \"SELECT indexname FROM pg_indexes WHERE tablename IN ('sales', 'Sellers') AND schemaname = 'public'\"
  );
  const existingNames = existing.rows.map(r => r.indexname);
  console.log('기존 인덱스:', existingNames.join(', ') || '(없음)');

  const indexes = [
    { name: 'idx_sales_store_id',          sql: 'CREATE INDEX IF NOT EXISTS idx_sales_store_id ON sales (store_id)' },
    { name: 'idx_sales_seller_id',         sql: 'CREATE INDEX IF NOT EXISTS idx_sales_seller_id ON sales (seller_id) WHERE seller_id IS NOT NULL' },
    { name: 'idx_sellers_linked_user_id',  sql: 'CREATE INDEX IF NOT EXISTS idx_sellers_linked_user_id ON \\\"Sellers\\\" (linked_user_id) WHERE linked_user_id IS NOT NULL' },
    { name: 'idx_sellers_store_id',        sql: 'CREATE INDEX IF NOT EXISTS idx_sellers_store_id ON \\\"Sellers\\\" (store_id)' },
  ];

  for (const idx of indexes) {
    if (existingNames.includes(idx.name)) {
      console.log('  skip ' + idx.name + ' (이미 존재)');
    } else {
      await c.query(idx.sql);
      console.log('  +    ' + idx.name + ' 생성 완료');
    }
  }

  const after = await c.query(
    \"SELECT indexname, tablename FROM pg_indexes WHERE tablename IN ('sales', 'Sellers') AND schemaname = 'public'\"
  );
  console.log('');
  console.log('현재 인덱스:');
  after.rows.forEach(r => console.log('  - ' + r.tablename + '.' + r.indexname));
  await c.end();
  console.log('');
  console.log('DB 마이그레이션 완료');
}
run().catch(err => { console.error('DB 마이그레이션 실패:', err.message); c.end(); process.exit(1); });
"
  echo -e "${GREEN}  ✅ DB 마이그레이션 완료${NC}"

else
  echo -e "${YELLOW}  ⚠️  api_ventago 컨테이너가 실행 중이 아닙니다.${NC}"
  echo "      마이그레이션을 건너뛰고, 배포 후 수동 실행해주세요:"
  echo ""
  echo "      docker exec api_ventago node -e \"\$(cat <<'MIGRATION'"
  echo "const { Client } = require('pg');"
  echo "const c = new Client({host:'dbpostgres',user:'coolsistema',password:process.env.DATABASE_PASSWORD,database:'ventago'});"
  echo "c.connect().then(async()=>{"
  echo "  await c.query('CREATE INDEX IF NOT EXISTS idx_sales_store_id ON sales (store_id)');"
  echo "  await c.query('CREATE INDEX IF NOT EXISTS idx_sales_seller_id ON sales (seller_id) WHERE seller_id IS NOT NULL');"
  echo "  await c.query('CREATE INDEX IF NOT EXISTS idx_sellers_linked_user_id ON \\\"Sellers\\\" (linked_user_id) WHERE linked_user_id IS NOT NULL');"
  echo "  await c.query('CREATE INDEX IF NOT EXISTS idx_sellers_store_id ON \\\"Sellers\\\" (store_id)');"
  echo "  console.log('완료'); c.end();"
  echo "}).catch(e=>{console.error(e);c.end();});"
  echo "MIGRATION"
  echo ")\""
  echo ""
fi
echo ""

# ═══════════════════════════════════════════════════
# 2단계: Git 최신 코드 확인
# ═══════════════════════════════════════════════════
echo -e "${YELLOW}[2/5] Git 상태 확인${NC}"
if git diff --quiet HEAD 2>/dev/null; then
  echo -e "${GREEN}  ✅ 변경사항 없음 (커밋 완료 상태)${NC}"
else
  echo -e "${YELLOW}  ⚠️  커밋되지 않은 변경사항 있음:${NC}"
  git status --short
  echo ""
  read -p "  계속 진행하시겠습니까? (y/N) " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}  ❌ 중단됨. 먼저 git commit 후 다시 실행해주세요.${NC}"
    exit 1
  fi
fi
echo ""

# ═══════════════════════════════════════════════════
# 3단계: 백엔드 빌드 + 재시작
# ═══════════════════════════════════════════════════
echo -e "${YELLOW}[3/5] 백엔드 빌드 & 재시작 (api-ventago)${NC}"
cd api-ventago
docker compose build
docker compose up -d
echo -e "${GREEN}  ✅ api-ventago 빌드 + 재시작 완료${NC}"
cd ..
echo ""

# ═══════════════════════════════════════════════════
# 4단계: 프론트엔드 빌드 + 재시작
# ═══════════════════════════════════════════════════
echo -e "${YELLOW}[4/5] 프론트엔드 빌드 & 재시작 (ventago-app)${NC}"
cd ventago-app
docker compose build
docker compose up -d
echo -e "${GREEN}  ✅ ventago-app 빌드 + 재시작 완료${NC}"
cd ..
echo ""

# ═══════════════════════════════════════════════════
# 5단계: 헬스체크
# ═══════════════════════════════════════════════════
echo -e "${YELLOW}[5/5] 헬스체크${NC}"
echo "      API 시작 대기 (5초)..."
sleep 5

# API 헬스체크
API_STATUS=$(curl -sf -o /dev/null -w "%{http_code}" http://localhost:5002/api/auth/me 2>/dev/null || echo "000")
if [ "$API_STATUS" = "401" ] || [ "$API_STATUS" = "200" ]; then
  echo -e "${GREEN}  ✅ API 서버 응답 정상 (HTTP $API_STATUS, 포트 5002)${NC}"
else
  echo -e "${RED}  ⚠️  API 서버 응답 이상 (HTTP $API_STATUS)${NC}"
  echo "      로그 확인: docker logs api_ventago --tail 50"
fi

# 프론트 헬스체크
FRONT_STATUS=$(curl -sf -o /dev/null -w "%{http_code}" http://localhost:5001 2>/dev/null || echo "000")
if [ "$FRONT_STATUS" = "200" ] || [ "$FRONT_STATUS" = "302" ]; then
  echo -e "${GREEN}  ✅ 프론트엔드 응답 정상 (HTTP $FRONT_STATUS, 포트 5001)${NC}"
else
  echo -e "${RED}  ⚠️  프론트엔드 응답 이상 (HTTP $FRONT_STATUS)${NC}"
  echo "      로그 확인: docker logs ventago_app --tail 50"
fi

# DB Pool 설정 확인
echo ""
POOL_LOG=$(docker logs api_ventago --tail 200 2>&1 | grep -i "Pool" | head -3 || true)
if [ -n "$POOL_LOG" ]; then
  echo -e "${GREEN}  ✅ DB Pool 로그:${NC}"
  echo "$POOL_LOG" | while read -r line; do echo "      $line"; done
else
  echo -e "${YELLOW}  ⚠️  Pool 로그 미확인 — 잠시 후 확인:${NC}"
  echo "      docker logs api_ventago 2>&1 | grep Pool"
fi

# 느린 쿼리 확인
SLOW=$(docker logs api_ventago --tail 200 2>&1 | grep -i "SlowQuery" | head -3 || true)
if [ -n "$SLOW" ]; then
  echo ""
  echo -e "${YELLOW}  ⚠️  느린 쿼리 감지됨:${NC}"
  echo "$SLOW" | while read -r line; do echo "      $line"; done
fi

echo ""
echo -e "${BLUE}══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  배포 완료${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════${NC}"
echo ""
echo "  변경 사항:"
echo "    1. DB Pool: min=5, max=20, idle=10s, acquire=30s"
echo "    2. 느린 쿼리(100ms+) 자동 경고 로그"
echo "    3. Pool 상태 주기적 모니터링 (30초/60초 간격)"
echo "    4. N+1 쿼리 수정 (products 조회/생성)"
echo "    5. seller_id FK 위반 방어 코드"
echo "    6. HTTP 이벤트 리스너 메모리 누수 수정"
echo "    7. DB 인덱스 4개 추가"
echo ""
echo "  모니터링:"
echo "    docker logs api_ventago -f --tail 50         # 실시간 로그"
echo "    docker logs api_ventago 2>&1 | grep SlowQuery  # 느린 쿼리"
echo "    docker logs api_ventago 2>&1 | grep Pool       # Pool 상태"
echo ""
