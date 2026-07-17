#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# push-fixes-2026-07-17.sh
# 클라우드 세션이 통합한 버그 픽스를 origin/main 으로 push (Mac 에서 실행).
#
# 배경: 클라우드 샌드박스에서는 (1) origin 원격에 push 불가, (2) 마운트 .git 의
# index.lock 생성 차단으로 일반 commit/cherry-pick 불가 → 이 스크립트로 Mac 에서 마무리.
#
# ★ 확인된 사실 (2026-07-17):
#   - 대다수 pending 픽스는 이미 origin/main 에 있음 → 제외:
#       6a54ff4f(dailyNumber), 6a50ec34(zebra 검색: api+root), 6a55061f(Recibir)
#   - 진짜 미반영 픽스는 아래 3건뿐.
#
# push 는 Jenkins CI/CD(api-coolsistema / front-coolsistema) 를 트리거 → 운영 배포됨.
# 실행 전 각 repo 상태를 확인하세요.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
ROOT="/Users/marcoskim/Trabajos_Programming/ACE_online_1.0"

echo "══════════════════════════════════════════════════════════════"
echo " 1) api-ventago — zebra 라벨 PRECIO 1(base) 누락 인쇄 픽스 (Trello 6a591931)"
echo "══════════════════════════════════════════════════════════════"
cd "$ROOT/api-ventago"
git fetch origin
# 로컬 main 은 클라우드 세션이 이미 602173e(픽스)로 fast-forward 해 둠 (origin/main +1).
# 혹시 로컬 main 이 준비 안 됐으면 아래 주석 해제:
#   git branch -f main origin/main && git cherry-pick 602173e
echo "-- 로컬 main 상태 (602173e 픽스 포함, origin/main +1 이어야 함) --"
git log --oneline origin/main..main
echo "-- lint / type / test (실패 시 중단됨) --"
npm run lint -- src/app/print/print.service.ts
npx tsc --noEmit
# npm run test -- print.service   # 필요 시
read -rp "api-ventago main 을 push 할까요? (Jenkins 배포 트리거) [y/N] " a
[ "$a" = "y" ] && git push origin main || echo "  건너뜀."

echo "══════════════════════════════════════════════════════════════"
echo " 2) ventago-app — 티켓 고객명(fullname) + 재인쇄 Venta 렌더 (Trello 6a5675a3, 6a566b67)"
echo "══════════════════════════════════════════════════════════════"
cd "$ROOT/ventago-app"
git fetch origin
# 이 두 픽스는 이미 워킹트리에 미커밋 상태로 정확히 존재 (아래 3파일, +14/-2).
#   ProductList.tsx      : client → selectedClient.fullname 폴백
#   SaleReviewPanel.tsx  : ticketType 'invoiced'
#   services/print.service.ts : ticketType/number 스키마
echo "-- 커밋 대상 3파일 diff 확인 --"
git --no-pager diff --stat origin/main -- \
  src/views/homes/components/ProductList/ProductList.tsx \
  src/views/homes/components/SaleReview/SaleReviewPanel.tsx \
  src/services/print.service.ts
echo "-- 현재 브랜치가 main 인지 확인 (아니면: git stash → git checkout main → 아래 파일만 반영) --"
git rev-parse --abbrev-ref HEAD
npm run lint -- \
  src/views/homes/components/ProductList/ProductList.tsx \
  src/views/homes/components/SaleReview/SaleReviewPanel.tsx \
  src/services/print.service.ts
read -rp "위 3파일만 커밋할까요? [y/N] " b
if [ "$b" = "y" ]; then
  git add src/views/homes/components/ProductList/ProductList.tsx \
          src/views/homes/components/SaleReview/SaleReviewPanel.tsx \
          src/services/print.service.ts
  git commit -m "fix(pos): 티켓 고객명(fullname) 인쇄 + 재인쇄 Venta 렌더(ticketType invoiced)

- ProductList: invoice.client 를 selectedClient.fullname 우선(레거시 .name 폴백)
- SaleReviewPanel/print.service: 재인쇄 시 ticketType='invoiced' + invoice.number 로
  'PRESUPUESTO TEMPORAL' 배너 없이 'Venta # NNNN' 렌더
Trello: 6a5675a3, 6a566b67"
  read -rp "ventago-app main 을 push 할까요? (Jenkins 배포 트리거) [y/N] " c
  [ "$c" = "y" ] && git push origin main || echo "  push 건너뜀 (커밋만 됨)."
else
  echo "  건너뜀."
fi

echo "══════════════════════════════════════════════════════════════"
echo " 3) (선택) 루트 서브모듈 gitlink 갱신"
echo "══════════════════════════════════════════════════════════════"
echo "  Jenkins 는 각 repo main 에서 빌드하므로 보통 불필요."
echo "  루트 참조를 맞추려면:"
echo "    cd $ROOT && git add api-ventago ventago-app && \\"
echo "    git commit -m 'chore: bump submodules — pos/zebra 티켓 픽스' && git push origin main"

echo ""
echo "✅ 완료. 실기 검증:"
echo "  · zebra: store 6/12 상품 검색 → PRECIO 1 nivel 선택 → 라벨에 base 가격 인쇄 확인"
echo "  · POS: 고객 선택 판매 티켓에 고객명(Consumidor Final 아님) 확인 / ctrl+R 재인쇄가 'Venta #' 로 인쇄 확인"
