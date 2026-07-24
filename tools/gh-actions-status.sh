#!/bin/bash
# GitHub Actions 빌드 결과 폴링 — $1=워크플로파일, $2=headBranch(태그명). completed 될 때까지(최대 ~8분).
REPO="jhkim1010/aceiii.online.1.0"
WF="${1:-build-print-agent.yml}"
REF="${2:-print-agent-v1.0.18}"
if ! command -v gh >/dev/null 2>&1; then echo NO_GH_CLI; exit 2; fi
gh auth status >/dev/null 2>&1 || { echo GH_NOT_AUTHED; exit 2; }
for i in $(seq 1 34); do
  J=$(gh run list --repo "$REPO" --workflow "$WF" --limit 15 --json databaseId,headBranch,status,conclusion,event,createdAt,url 2>&1)
  ROW=$(printf '%s' "$J" | python3 -c "import sys,json
try: rs=json.load(sys.stdin)
except: rs=[]
m=[r for r in rs if r.get('headBranch')=='$REF']
print(json.dumps(m[0]) if m else '')" 2>/dev/null)
  if [ -z "$ROW" ]; then echo "[$i] run 미등록(대기)"; sleep 15; continue; fi
  status=$(printf '%s' "$ROW" | python3 -c "import sys,json;print(json.load(sys.stdin).get('status'))")
  concl=$(printf '%s' "$ROW" | python3 -c "import sys,json;print(json.load(sys.stdin).get('conclusion'))")
  url=$(printf '%s' "$ROW" | python3 -c "import sys,json;print(json.load(sys.stdin).get('url'))")
  echo "[$i] status=$status conclusion=$concl"
  if [ "$status" = "completed" ]; then
    echo "GH_ACTIONS_RESULT=$concl url=$url"
    [ "$concl" = "success" ] && exit 0 || exit 1
  fi
  sleep 15
done
echo GH_ACTIONS_TIMEOUT; exit 3
