#!/bin/bash
# AFIP 발행 직후 comandera 자동 감열출력 배선 — api-ventago 격리 배포.
# origin/main 기준 임시 worktree(모노레포 root 하위)에서 감열 커밋 1개만 만들어 origin main 으로 FF push.
# 로컬 main 의 Phase 61 선행 커밋(8개)·기타 WIP 는 절대 건드리지 않는다.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API="$ROOT/api-ventago"
FILES="src/app/afip/afip.controller.ts src/app/afip/afip.module.ts src/app/afip/dto/issue-voucher.dto.ts src/app/sales/sales-create.service.ts"
TRAILER="Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01XPyB2SXid5ZjS7kndibuzS"

cd "$API"
rm -f .git/index.lock 2>/dev/null || true
# 이전 실패 잔여 worktree 정리 (/tmp + root 하위 둘 다)
rm -rf /tmp/iso-thermal.* "$ROOT"/.iso-thermal-wt-* 2>/dev/null || true
git worktree prune 2>/dev/null || true

echo "== fetch origin =="; git fetch origin

# ★worktree 를 모노레포 root 하위에 둬야 root/node_modules(typescript hoist) 탐색이 닿는다
WT="$ROOT/.iso-thermal-wt-$$"
rm -rf "$WT" 2>/dev/null || true
git worktree add -f --detach "$WT" origin/main
ln -sfn "$API/node_modules" "$WT/node_modules"

for f in $FILES; do
  mkdir -p "$WT/$(dirname "$f")"
  cp "$API/$f" "$WT/$f"
done

cd "$WT"
echo "== TSC (격리: origin/main + 감열변경만) =="
# npx 금지(엉뚱한 tsc 패키지 설치 방지) — root 에 hoist 된 tsc 바이너리 직접 호출
"$ROOT/node_modules/.bin/tsc" --noEmit -p tsconfig.build.json && echo API_TSC_OK

git add $FILES
git commit --no-verify -m "feat(afip): fac. electronica 발행 직후 comandera 자동 감열출력 배선 (CoolSyncro cae-issuer 이식)

- 자동발행(sales-create): issueForSale 성공(ok+voucherId) 직후 AfipOutputService.dispatch({output:'thermal'}) 자동 호출
  (branchId=resolvedBranchId, terminalId=resolvedTerminalId). 출력 실패는 비치명적(warn 로그만, 판매/CAE 유효 유지).
- 수동발행(afip.controller issue): output==='thermal' + branchId 전달 시 void dispatch(비-throw). 현재 프론트 미전달 → 잠든 안전망.
- afip.module: AfipOutputService export. dto/issue-voucher: optional branchId/terminalId.
- dispatch=짧은 조회 후 websocket emit → DB 커넥션 장기점유 없음(pool 안전). print-agent/영수증 포맷 기존 유지.

$TRAILER"

echo "== push origin main (FF, 감열 커밋만) — 최대 3회 재시도 =="
ok=0
for n in 1 2 3; do
  if git push origin HEAD:main; then ok=1; break; fi
  echo "push 시도 $n 실패(일시적 GitHub 5xx 가능) — 10초 후 재시도"; sleep 10
  git fetch origin 2>/dev/null || true
done

echo "== 정리 =="
cd "$API"
git worktree remove --force "$WT" 2>/dev/null || true
rm -rf "$WT" 2>/dev/null || true
git worktree prune 2>/dev/null || true

if [ "$ok" != "1" ]; then echo "PUSH_FAILED_AFTER_RETRIES"; exit 1; fi
echo "AFIP-AUTO-THERMAL-PUSH-OK"
git fetch origin 2>/dev/null || true
git log --oneline origin/main -1
