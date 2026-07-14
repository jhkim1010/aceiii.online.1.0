#!/bin/bash
# 2026-07-14 api-ventago 커밋 2건 + push — 브리지 lock 이슈로 Mac 러너에서 실행
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/api-ventago"

# 샌드박스가 남긴 stale lock 정리
rm -f .git/index.lock .git/HEAD.lock .git/next-index-*.lock .git/index.lock.stale-20260714 .git/objects/*/tmp_obj_* 2>/dev/null || true

GC="git -c user.name=Marcos.J.Kim -c user.email=junghokim10@gmail.com"

# 커밋 2: 모바일 암호 로그인 전환
git add src/app/mobile
$GC commit -m "feat(mobile): 로그인 PIN → 일반 암호(users.password) 단일 인증 전환

- mobile-login.dto: pin → password
- mobile-auth.service: users.password bcrypt 대조, setMobilePin 제거
- set-pin 엔드포인트 제거 (DTO 는 사용중지 스텁)
- spec: mobile 30/30 PASS

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JX4xRJVBifRiMweJxdsiQM"

# 커밋 3: 완제품 입고 백엔드 + 마이그레이션
git add src/app/subcon src/app/products src/app/branch migrations/2026-07-14-branch-is-warehouse.sql migrations/2026-07-14-lote-stocked-quantity.sql
$GC commit -m "feat(talleres): 완제품 입고 — 로트 매트릭스를 창고/매장 재고로 (ingreso-stock)

- POST /talleres/lotes/:id/ingreso-stock (지점 선택, 멱등 stocked_quantity)
- ProductStockService.ingresarStockPorMatrix (변형→ProductBranch→Stocks bulkCreate, 단일 tx)
- branches.is_warehouse + talleres_lotes.stocked_quantity (마이그레이션, 운영 5434 적용됨)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JX4xRJVBifRiMweJxdsiQM"

echo "== push =="
git push origin main
git log --oneline -4
echo "== DONE =="
