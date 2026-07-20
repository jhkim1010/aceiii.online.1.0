#!/bin/bash
# Phase 58 — feature/phase58-offline-sync 3-repo main 통합 + push (agent-runner 용, v3 멱등)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BR="feature/phase58-offline-sync"
MSG="merge: Phase 58 오프라인-퍼스트 POS Wave A/B/B2/C1 (offline-sync, edge-agent, print failover)"

echo "== [0] stale git lock 스윕 =="
for R in "$ROOT" "$ROOT/api-ventago" "$ROOT/ventago-app"; do
  find "$R/.git" -maxdepth 3 -name "*.lock" -delete 2>/dev/null || true
done

# 멱등 가드 — 이미 병합된 repo 는 건드리지 않음 (재실행 시 코드 삭제 사고 방지)
already_merged() {
  git merge-base --is-ancestor "$BR" main 2>/dev/null
}

echo "== [1] api-ventago =="
cd "$ROOT/api-ventago"
git checkout main 2>&1 | tail -1
if already_merged; then
  echo "  이미 병합됨 — skip"
else
  git checkout -- src/app.module.ts 2>/dev/null || true
  rm -rf src/app/offline-sync
  rm -f migrations/phase58-offline-sync-ops.sql
  git merge --no-ff "$BR" -m "$MSG"
fi

echo "== [2] ventago-app =="
cd "$ROOT/ventago-app"
git checkout main 2>&1 | tail -1
if already_merged; then
  echo "  이미 병합됨 — skip"
else
  git checkout -- src/services/api.service.ts src/pages/_app.tsx 2>/dev/null || true
  rm -f src/services/offline-mode.service.ts src/components/OfflineBanner.tsx
  git merge --no-ff "$BR" -m "$MSG"
fi

echo "== [3] root =="
cd "$ROOT"
git checkout main 2>&1 | tail -1
if already_merged; then
  echo "  이미 병합됨 — skip"
else
  # dirty 상태 선커밋: gitlink(서브 main 병합 포인터) + runner 잡 정의 + 훅 스냅샷.
  # 이후 merge 는 -X ours 로 gitlink 충돌 시 최신(main) 포인터 유지.
  git add api-ventago ventago-app mobile-sales-app tools/agent-runner-jobs.js tools/integrate-phase58.sh .claude/hooks/.gsd-snapshot.json 2>/dev/null || true
  git diff --cached --quiet || git commit -m "chore(phase58): pre-merge sync (gitlinks main + runner job)"
  git merge --no-ff -X ours "$BR" -m "$MSG"

  # 병합 후 gitlink 최종 확인 커밋 (변화 있을 때만)
  git add api-ventago ventago-app 2>/dev/null || true
  git diff --cached --quiet || git commit -m "chore(phase58): gitlink sync post-merge"
fi

echo "== [4] push (sub -> root) =="
git -C "$ROOT/ventago-app" push origin main
git -C "$ROOT/api-ventago" push origin main
git -C "$ROOT" push origin main

echo "== RESULT =="
echo "api:   $(git -C "$ROOT/api-ventago" log --oneline -1)"
echo "front: $(git -C "$ROOT/ventago-app" log --oneline -1)"
echo "root:  $(git -C "$ROOT" log --oneline -1)"
echo "== 완료 =="
