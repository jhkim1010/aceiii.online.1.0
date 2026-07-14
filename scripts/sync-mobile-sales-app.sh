#!/usr/bin/env bash
# =====================================================================
# 판매원 앱 동기화 — 직원이 머지한 최신 main을 모노레포로 끌어오기
# ---------------------------------------------------------------------
# 하는 일:
#   1) mobile-sales-app/ (중첩 repo) 에서 origin/main fast-forward pull
#   2) 루트 repo의 gitlink(커밋 포인터) 갱신 커밋
#
# 실행 위치: 모노레포 루트. 릴리스 빌드 전마다 실행하면 됨.
# 안전장치: 로컬 수정이 있으면 중단(ff-only), 변화 없으면 커밋 안 함
# =====================================================================
set -euo pipefail

FOLDER="mobile-sales-app"

if [ ! -e "$FOLDER/.git" ]; then
  echo "❌ ${FOLDER} 가 아직 중첩 repo가 아닙니다. 먼저 scripts/split-mobile-sales-app.sh 실행."
  exit 1
fi

# ── 1) 앱 repo 최신화 (fast-forward만 허용 → 로컬 수정 보호) ────────
BEFORE=$(git -C "$FOLDER" rev-parse HEAD)
git -C "$FOLDER" fetch origin
git -C "$FOLDER" merge --ff-only origin/main || {
  echo "❌ fast-forward 불가 — ${FOLDER} 에 로컬 커밋/수정이 있습니다."
  echo "   확인: git -C ${FOLDER} status && git -C ${FOLDER} log origin/main..HEAD"
  exit 1
}
AFTER=$(git -C "$FOLDER" rev-parse HEAD)

if [ "$BEFORE" = "$AFTER" ]; then
  echo "✅ 이미 최신입니다 (${AFTER:0:8}) — 할 일 없음"
  exit 0
fi

echo "✅ 업데이트: ${BEFORE:0:8} → ${AFTER:0:8}"
git -C "$FOLDER" log --oneline "${BEFORE}..${AFTER}" | sed 's/^/   /'

# ── 2) 루트 repo gitlink 갱신 ────────────────────────────────────────
git add "$FOLDER"
if git diff --cached --quiet; then
  echo "ℹ️  루트 gitlink 변화 없음"
else
  git commit -m "chore: mobile-sales-app ${AFTER:0:8} 동기화"
  echo "✅ 루트 gitlink 커밋 완료 — 필요 시 git push origin main"
fi
