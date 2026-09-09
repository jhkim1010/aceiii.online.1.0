#!/bin/bash
# Phase 88 계획에 대한 CODEX 자문 — Mac 에서 실행한다(격리 VM 에는 codex 바이너리가 없다).
# 소요 약 25분. 백그라운드로 돌고 결과는 .team/reviews/phase88-codex.md 에 쌓인다.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
command -v codex >/dev/null || { echo "codex 없음 — npm i -g @openai/codex"; exit 1; }
OUT=".team/reviews/phase88-codex.md"
nohup codex exec --sandbox read-only "$(cat .team/reviews/phase88-codex-prompt.md)" > "$OUT" 2>&1 &
echo "CODEX 자문 시작(pid $!). 결과: $OUT"
echo "진행 확인:  tail -f $OUT"
