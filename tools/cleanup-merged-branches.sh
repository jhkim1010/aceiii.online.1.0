#!/bin/bash
# 병합 완료 로컬 브랜치 정리 (backup 제외, 15개)
# 각 삭제 시 복구용 SHA 를 출력하므로 되돌리기 안전. 원격(origin)은 건드리지 않음.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

del() {
  local sub="$1"; shift
  local d; [ "$sub" = "." ] && d="$ROOT" || d="$ROOT/$sub"
  echo "════ ${sub} ════"
  local cur; cur="$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  for b in "$@"; do
    if [ "$b" = "$cur" ]; then echo "  건너뜀(현재 브랜치) $b"; continue; fi
    if git -C "$d" show-ref --verify --quiet "refs/heads/$b"; then
      local sha; sha="$(git -C "$d" rev-parse --short "$b")"
      if git -C "$d" branch -D "$b" >/dev/null 2>&1; then
        echo "  ✓ 삭제 $b   (복구: git -C $sub branch $b $sha)"
      else
        echo "  ✗ 실패 $b"
      fi
    else
      echo "  · 없음 $b"
    fi
  done
}

del api-ventago feat/revendedor-onboarding feat/revendedor-zona feat/sku-serial feature/phase58-offline-sync feature/phase59-afip-soap fix/trello-6a591931 main1 fix/trello-6a54ff4f
del ventago-app feat/revendedor-onboarding feat/sku-serial feature/phase58-offline-sync fix/trello-6a54ff4f main1
del mobile-sales-app feat/revendedor-onboarding
del . feature/phase58-offline-sync

echo "BRANCH_CLEANUP_DONE (backup/phase57-df122c7 는 보관됨)"
