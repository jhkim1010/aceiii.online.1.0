#!/bin/bash
# Phase 59 — api-ventago main 병합+push + 루트 .gsd/tools 커밋+push (agent-runner 용, 멱등)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BR="feature/phase59-afip-soap"
MSG="merge: Phase 59 ARCA SOAP 직접 발행 Wave A+B (WSAA+WSFEv1, soap-direct provider, homo E2E 검증)"

echo "== [0] stale git lock 스윕 =="
for R in "$ROOT" "$ROOT/api-ventago"; do
  find "$R/.git" -maxdepth 3 -name "*.lock" -delete 2>/dev/null || true
done

echo "== [1] api-ventago: WIP 보존 → main 병합 → push =="
cd "$ROOT/api-ventago"
# 미커밋 WIP(afip-issuer.service.ts — Phase 57 D-07 잔여)는 stash 로 보존
STASHED=0
if ! git diff --quiet src/app/afip/afip-issuer.service.ts 2>/dev/null; then
  git stash push -m phase59-wip-issuer src/app/afip/afip-issuer.service.ts
  STASHED=1
fi
git checkout main 2>&1 | tail -1
if git merge-base --is-ancestor "$BR" main 2>/dev/null; then
  echo "  이미 병합됨 — skip"
else
  git merge --no-ff "$BR" -m "$MSG"
fi
git push origin main
if [ "$STASHED" = "1" ]; then
  git stash pop || echo "  (stash pop 충돌 — stash 에 보존됨: git stash list 확인)"
fi

echo "== [2] root: .gsd/tools 커밋 + gitlink + push =="
cd "$ROOT"
git checkout main 2>&1 | tail -1
git add .gsd/spec-phase59-afip-soap-direct.md .gsd/manual-phase59-arca-soap-reference.md \
  .gsd/gateway-condiva-patch.md tools/agent-runner-jobs.js tools/phase59-branch-commit.sh \
  tools/integrate-phase59.sh api-ventago 2>/dev/null || true
git diff --cached --quiet || git commit -m "chore(phase59): SPEC·ARCA 매뉴얼·게이트웨이 패치 가이드 + runner 잡 + api gitlink"
git push origin main

echo "== RESULT =="
echo "api:  $(git -C "$ROOT/api-ventago" log --oneline -1)"
echo "root: $(git log --oneline -1)"
echo "== 완료 =="
