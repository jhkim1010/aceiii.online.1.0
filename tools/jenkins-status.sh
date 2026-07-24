#!/bin/bash
# Jenkins 빌드 결과 폴링 — $1=잡이름. building=false + result 확정 시 종료(SUCCESS=0/FAILURE=1).
JOB="$1"
if [ -z "$JENKINS_USER" ] || [ -z "$JENKINS_TOKEN" ]; then echo NO_JENKINS_CREDS; exit 2; fi
B="https://deploy.coolsistema.com"
for i in $(seq 1 30); do
  R=$(curl -s -u "$JENKINS_USER:$JENKINS_TOKEN" "$B/job/$JOB/lastBuild/api/json?tree=number,result,building,timestamp")
  echo "[$i] ${R:0:220}"
  building=$(printf '%s' "$R" | python3 -c "import sys,json;print(json.load(sys.stdin).get('building'))" 2>/dev/null || echo "?")
  result=$(printf '%s' "$R" | python3 -c "import sys,json;print(json.load(sys.stdin).get('result'))" 2>/dev/null || echo "?")
  if [ "$building" = "False" ] && [ -n "$result" ] && [ "$result" != "None" ]; then
    echo "JENKINS_RESULT=$result (build #$(printf '%s' "$R" | python3 -c "import sys,json;print(json.load(sys.stdin).get('number'))" 2>/dev/null))"
    [ "$result" = "SUCCESS" ] && exit 0 || exit 1
  fi
  sleep 12
done
echo JENKINS_STATUS_TIMEOUT; exit 3
