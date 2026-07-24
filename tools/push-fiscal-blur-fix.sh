#!/bin/bash
# print-agent 재정영수증(fiscal) 흐림 수정 — 격리 배포(root repo) + 릴리스 태그.
# origin/main 기준 worktree 에 fiscal-formatter.js 변경 1개만 얹어 FF push + print-agent-v1.0.18 태그 push.
# 로컬 root main 의 Phase 61 선행 커밋(72개)은 절대 건드리지 않는다. GitHub Actions 가 태그로 print-agent 빌드.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAG="print-agent-v1.0.18"
FILE="print-agent/src/fiscal-formatter.js"
TRAILER="Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01XPyB2SXid5ZjS7kndibuzS"

cd "$ROOT"
rm -f .git/index.lock 2>/dev/null || true
rm -rf /tmp/iso-fiscal.* 2>/dev/null || true
git worktree prune 2>/dev/null || true
echo "== fetch origin =="; git fetch origin

WT="$(mktemp -d /tmp/iso-fiscal.XXXXXX)"
git worktree add -f --detach "$WT" origin/main
mkdir -p "$WT/$(dirname "$FILE")"
cp "$ROOT/$FILE" "$WT/$FILE"

cd "$WT"
echo "== JS 문법 검사 =="
node --check "$FILE" && echo JS_SYNTAX_OK

git add "$FILE"
git commit --no-verify -m "fix(print-agent): 재정영수증(fiscal) 감열 흐림 수정 — 본문 굵게 + Courier New + 순수 흑백

- fiscal-formatter.js body: font-family 'Courier New' + font-weight:bold 추가.
  이진화(renderer-engine threshold 128) 후 얇은 monospace 획이 끊겨 흐리던 문제 해소
  — 2026-07-11 formatter.js(컨트롤 티켓) 흐림수정과 동일 처리를 fiscal 경로에 적용.
- .line .k 회색(#333)→#000, 최소 글자 크기 소폭 상향(thead/line/table). 나머지 렌더/발행 무변경.

$TRAILER"

NEWSHA="$(git rev-parse HEAD)"

echo "== push origin main (FF, fiscal 커밋만) — 최대 3회 =="
ok=0
for n in 1 2 3; do
  if git push origin HEAD:main; then ok=1; break; fi
  echo "push 재시도 $n"; sleep 10; git fetch origin 2>/dev/null || true
done
[ "$ok" = "1" ] || { echo "PUSH_FAILED"; cd "$ROOT"; git worktree remove --force "$WT" 2>/dev/null||true; exit 1; }

echo "== 릴리스 태그 $TAG @ $NEWSHA =="
git tag -f -a "$TAG" -m "print-agent $TAG — fiscal 영수증 흐림 수정(굵게+Courier)" "$NEWSHA"
okt=0
for n in 1 2 3; do
  if git push -f origin "$TAG"; then okt=1; break; fi
  echo "tag push 재시도 $n"; sleep 10
done

echo "== 정리 =="
cd "$ROOT"
git worktree remove --force "$WT" 2>/dev/null || true
git worktree prune 2>/dev/null || true

[ "$okt" = "1" ] || { echo "TAG_PUSH_FAILED"; exit 1; }
echo "FISCAL-BLUR-FIX-PUSH-OK tag=$TAG sha=$NEWSHA"
