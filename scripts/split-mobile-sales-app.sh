#!/usr/bin/env bash
# =====================================================================
# 판매원 앱(mobile-sales-app) 별도 저장소 분리 — 1회 실행 스크립트
# ---------------------------------------------------------------------
# 하는 일:
#   1) GitHub에 private repo 생성 (jhkim1010/mobile-sales-app)
#   2) 모노레포 이력에서 mobile-sales-app 폴더만 분리(subtree split)
#   3) 새 저장소로 push (main)
#   4) 모노레포 폴더를 api-ventago 패턴(중첩 repo + gitlink)으로 전환
#
# 실행 위치: 모노레포 루트 (~/Trabajos_Programming/ACE_online_1.0)
# 필요: gh CLI 로그인 상태 (gh auth status)
# 안전장치: 각 단계 검증 실패 시 즉시 중단(set -e), 원본은 .bak 보존
# =====================================================================
set -euo pipefail

REPO_OWNER="jhkim1010"
REPO_NAME="mobile-sales-app"
REPO_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}.git"
FOLDER="mobile-sales-app"
SPLIT_BRANCH="split/${REPO_NAME}"

# ── 0) 사전 검증 ─────────────────────────────────────────────────────
if [ ! -d "$FOLDER" ] || [ ! -f "package.json" ]; then
  echo "❌ 모노레포 루트에서 실행하세요 (mobile-sales-app 폴더가 보이는 위치)"
  exit 1
fi
if [ -e "$FOLDER/.git" ]; then
  echo "✅ 이미 중첩 repo로 전환되어 있습니다. 할 일 없음."
  exit 0
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "❌ gh CLI 로그인이 필요합니다: gh auth login"
  exit 1
fi
if ! git diff --quiet -- "$FOLDER"; then
  echo "❌ ${FOLDER}에 커밋 안 된 변경이 있습니다. 먼저 커밋/스태시 하세요."
  exit 1
fi

# ── 1) GitHub repo 생성 (이미 있으면 통과) ──────────────────────────
if gh repo view "${REPO_OWNER}/${REPO_NAME}" >/dev/null 2>&1; then
  echo "ℹ️  ${REPO_OWNER}/${REPO_NAME} 이미 존재 — 생성 건너뜀"
else
  gh repo create "${REPO_OWNER}/${REPO_NAME}" --private \
    --description "Ventago 판매원 모바일 앱 (Flutter)"
  echo "✅ repo 생성: ${REPO_URL}"
fi

# ── 2) 이력 보존 분리 ────────────────────────────────────────────────
git branch -D "$SPLIT_BRANCH" 2>/dev/null || true
git subtree split --prefix="$FOLDER" -b "$SPLIT_BRANCH"
echo "✅ subtree split 완료 → 브랜치 ${SPLIT_BRANCH}"

# ── 3) 새 저장소로 push ──────────────────────────────────────────────
git push "$REPO_URL" "${SPLIT_BRANCH}:main"
echo "✅ push 완료 → ${REPO_URL} (main)"

# ── 4) 폴더를 중첩 repo로 전환 (api-ventago 패턴) ───────────────────
mv "$FOLDER" "${FOLDER}.bak"
git clone "$REPO_URL" "$FOLDER"

# clone 결과와 원본 작업본 내용 대조 (빌드 산출물/.git 제외)
if diff -rq "$FOLDER" "${FOLDER}.bak" \
     -x .git -x build -x .dart_tool -x .idea >/dev/null 2>&1; then
  echo "✅ 내용 일치 확인"
else
  echo "⚠️  clone 결과와 원본에 차이가 있습니다 — 아래 diff 확인 후 수동 정리:"
  diff -rq "$FOLDER" "${FOLDER}.bak" -x .git -x build -x .dart_tool -x .idea || true
fi

# 루트 repo: 일반 파일 추적 해제 → gitlink 등록
git rm -r --cached "$FOLDER" >/dev/null
git add "$FOLDER"
git commit -m "chore: mobile-sales-app 별도 저장소 분리 (gitlink 전환)

- 새 저장소: ${REPO_URL}
- api-ventago/ventago-app 과 동일한 중첩 repo 패턴
- 직원 협업자 초대는 repo Settings > Access 에서"
echo "✅ 루트 repo gitlink 전환 커밋 완료"

echo ""
echo "=================================================================="
echo "다음 단계:"
echo "  1) 직원 초대: https://github.com/${REPO_OWNER}/${REPO_NAME}/settings/access"
echo "     (Add people → 직원 GitHub 계정 → Role: Write)"
echo "  2) 직원에게 줄 링크: ${REPO_URL%.git}"
echo "  3) 문제 없으면 백업 삭제: rm -rf ${FOLDER}.bak"
echo "  4) 루트 push: git push origin main"
echo "=================================================================="
