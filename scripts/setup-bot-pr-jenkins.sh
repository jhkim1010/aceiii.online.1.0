#!/bin/bash
# ③ 봇 PR 게이트웨이 + 배포 웹훅 서버 세팅 (운영서버 srv803182 에서 jhkim 으로 실행)
# 사용법:
#   scp scripts/setup-bot-pr-jenkins.sh jhkim@62.72.7.245:~/
#   ssh jhkim@62.72.7.245 'bash ~/setup-bot-pr-jenkins.sh'
# 롤백: config.xml.bak.* 복원 + jobs/bot-pr 삭제 + plugins/build-token-root.hpi 삭제 + jenkins 재시작
set -euo pipefail
TS=$(date +%Y%m%d_%H%M%S)
JH=/var/lib/jenkins

echo "== 0. 사전 확인 =="
systemctl is-active jenkins >/dev/null || { echo "jenkins 비활성 — 중단"; exit 1; }

echo "== 1. build-token-root 플러그인 설치 (토큰으로 지정 잡만 트리거 가능) =="
if sudo test -f $JH/plugins/build-token-root.jpi || sudo test -f $JH/plugins/build-token-root.hpi; then
  echo "  이미 설치됨 - 스킵"
else
  sudo curl -sSL -o $JH/plugins/build-token-root.hpi https://updates.jenkins.io/latest/build-token-root.hpi
  sudo chown jenkins:jenkins $JH/plugins/build-token-root.hpi
  echo "  다운로드 완료: $(sudo stat -c%s $JH/plugins/build-token-root.hpi) bytes"
fi

echo "== 2. ACE-Sync 잡에 GitHubPushTrigger 추가 (front/api 와 동일 형식) =="
sudo cp $JH/jobs/ACE-Sync/config.xml $JH/jobs/ACE-Sync/config.xml.bak.$TS
sudo python3 - <<'PYEOF'
p = '/var/lib/jenkins/jobs/ACE-Sync/config.xml'
s = open(p).read()
if 'GitHubPushTrigger' in s:
    print('  이미 있음 - 스킵')
else:
    trig = '''  <triggers>
    <com.cloudbees.jenkins.GitHubPushTrigger plugin="github@1.43.0">
      <spec></spec>
    </com.cloudbees.jenkins.GitHubPushTrigger>
  </triggers>'''
    s2 = s.replace('  <triggers/>', trig, 1)
    assert s2 != s, 'triggers/ 블록을 못 찾음'
    open(p, 'w').write(s2)
    print('  ACE-Sync 트리거 추가 완료')
PYEOF

echo "== 3. capability 토큰 생성/재사용 =="
if sudo test -s $JH/.bot_trigger_token; then
  TOK=$(sudo cat $JH/.bot_trigger_token); echo "  기존 토큰 재사용"
else
  TOK=$(openssl rand -hex 20)
  echo -n "$TOK" | sudo tee $JH/.bot_trigger_token >/dev/null
  sudo chown jenkins:jenkins $JH/.bot_trigger_token
  sudo chmod 600 $JH/.bot_trigger_token
  echo "  신규 토큰 생성"
fi

echo "== 4. bot-pr 빌드 스크립트 배치 =="
sudo tee $JH/bot-pr.sh >/dev/null <<'BOTEOF'
#!/bin/bash
# bot-pr 잡 빌드 스크립트 — 패치(base64 diff)를 받아 bot/* 브랜치로 push 하고 PR 을 연다.
# 안전장치: 허용 repo 3개, 브랜치는 bot/* 만, main 직접 push 불가(항상 PR 경유).
set -euo pipefail

case "$REPO" in
  ventago-app|api-ventago|node_js_svr_ace3) ;;
  *) echo "[bot-pr] 허용되지 않은 repo: $REPO"; exit 1 ;;
esac
case "$BRANCH" in
  bot/*) ;;
  *) echo "[bot-pr] 브랜치는 bot/* 만 허용: $BRANCH"; exit 1 ;;
esac

# 패치가 비어 있으면 연결 테스트로 간주 (셀프 테스트용)
if [ -z "${PATCH_B64:-}" ]; then
  echo "[bot-pr] 패치 없음 — 연결 테스트 OK"; exit 0
fi

TOKEN_FILE=/var/lib/jenkins/.github_pr_token
if [ ! -s "$TOKEN_FILE" ] && [ "$DRY_RUN" != "true" ]; then
  echo "[bot-pr] GitHub PAT 없음($TOKEN_FILE) — DRY_RUN 만 가능"; exit 1
fi

WORK=repo
rm -rf "$WORK" patch.diff
if [ -s "$TOKEN_FILE" ]; then
  PAT=$(cat "$TOKEN_FILE")
  git clone --depth 50 "https://x-access-token:${PAT}@github.com/jhkim1010/${REPO}.git" "$WORK"
else
  git clone --depth 50 "git@github.com:jhkim1010/${REPO}.git" "$WORK"
fi
cd "$WORK"
BASE=$(git symbolic-ref --short HEAD)
export BASE
git switch -c "$BRANCH"

echo "$PATCH_B64" | base64 -d > ../patch.diff
echo "== 패치 미리보기 =="
git apply --stat ../patch.diff
git apply --check ../patch.diff
git apply ../patch.diff
git add -A
git -c user.name="ventago-bot" -c user.email="bot@coolsistema.com" commit -m "$TITLE"

if [ "$DRY_RUN" = "true" ]; then
  echo "== DRY_RUN: push/PR 생략 =="; git show --stat HEAD; exit 0
fi

git push -u origin "$BRANCH"
# 토큰이 남지 않도록 remote URL 세척
git remote set-url origin "https://github.com/jhkim1010/${REPO}.git"

PAT=$(cat "$TOKEN_FILE")
curl -sf -X POST \
  -H "Authorization: Bearer $PAT" -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/jhkim1010/${REPO}/pulls" \
  -d "$(python3 -c 'import json,os; print(json.dumps({"title": os.environ["TITLE"], "body": os.environ.get("BODY",""), "head": os.environ["BRANCH"], "base": os.environ["BASE"]}))")" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print("PR:", d.get("html_url"))'
echo "[bot-pr] 완료"
BOTEOF
sudo chown jenkins:jenkins $JH/bot-pr.sh
sudo chmod 700 $JH/bot-pr.sh
echo "  배치 완료"

echo "== 5. bot-pr 잡 생성 =="
sudo mkdir -p $JH/jobs/bot-pr
sudo tee $JH/jobs/bot-pr/config.xml >/dev/null <<'XMLEOF'
<?xml version='1.1' encoding='UTF-8'?>
<project>
  <description>봇 PR 게이트웨이 — 패치를 받아 bot/* 브랜치로 push 하고 PR 을 연다. main 직접 push 불가. (setup-bot-pr-jenkins.sh 가 생성)</description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <hudson.model.ParametersDefinitionProperty>
      <parameterDefinitions>
        <hudson.model.ChoiceParameterDefinition>
          <name>REPO</name>
          <description>대상 repo</description>
          <choices class="java.util.Arrays$ArrayList">
            <a class="string-array">
              <string>ventago-app</string>
              <string>api-ventago</string>
              <string>node_js_svr_ace3</string>
            </a>
          </choices>
        </hudson.model.ChoiceParameterDefinition>
        <hudson.model.StringParameterDefinition>
          <name>BRANCH</name>
          <description>bot/* 형식만 허용</description>
          <defaultValue>bot/change</defaultValue>
        </hudson.model.StringParameterDefinition>
        <hudson.model.StringParameterDefinition>
          <name>TITLE</name>
          <defaultValue>bot: automated change</defaultValue>
        </hudson.model.StringParameterDefinition>
        <hudson.model.TextParameterDefinition>
          <name>BODY</name>
          <defaultValue></defaultValue>
        </hudson.model.TextParameterDefinition>
        <hudson.model.TextParameterDefinition>
          <name>PATCH_B64</name>
          <description>base64 인코딩된 git diff</description>
          <defaultValue></defaultValue>
        </hudson.model.TextParameterDefinition>
        <hudson.model.BooleanParameterDefinition>
          <name>DRY_RUN</name>
          <defaultValue>true</defaultValue>
        </hudson.model.BooleanParameterDefinition>
      </parameterDefinitions>
    </hudson.model.ParametersDefinitionProperty>
  </properties>
  <scm class="hudson.scm.NullSCM"/>
  <canRoam>true</canRoam>
  <disabled>false</disabled>
  <blockBuildWhenDownstreamBuilding>false</blockBuildWhenDownstreamBuilding>
  <blockBuildWhenUpstreamBuilding>false</blockBuildWhenUpstreamBuilding>
  <authToken>__TOK__</authToken>
  <triggers/>
  <concurrentBuild>false</concurrentBuild>
  <builders>
    <hudson.tasks.Shell>
      <command>bash /var/lib/jenkins/bot-pr.sh</command>
      <configuredLocalRules/>
    </hudson.tasks.Shell>
  </builders>
  <publishers/>
  <buildWrappers/>
</project>
XMLEOF
sudo sed -i "s|__TOK__|$TOK|" $JH/jobs/bot-pr/config.xml
sudo chown -R jenkins:jenkins $JH/jobs/bot-pr
echo "  잡 생성 완료"

echo "== 6. Jenkins 재시작 (앱 컨테이너는 영향 없음) =="
sudo systemctl restart jenkins
for i in $(seq 1 90); do
  curl -sf -o /dev/null http://localhost:8080/login && break
  sleep 2
done
curl -sf -o /dev/null http://localhost:8080/login && echo "  Jenkins UP" || { echo "  Jenkins 기동 실패 — sudo journalctl -u jenkins 확인"; exit 1; }

echo "== 7. 셀프 테스트 =="
curl -s -o /dev/null -w "  github-webhook endpoint: HTTP %{http_code} (200/302/405 면 정상)\n" -X POST http://localhost:8080/github-webhook/
sleep 3
curl -s -o /dev/null -w "  buildByToken(연결 테스트 빌드): HTTP %{http_code} (201 이면 정상)\n" \
  "http://localhost:8080/buildByToken/buildWithParameters?job=bot-pr&token=$TOK&DRY_RUN=true"

echo
echo "================================================================"
echo "완료! capability 토큰 (클라우드 세션에 전달할 것):"
echo "  $TOK"
echo "외부 트리거 URL:"
echo "  https://deploy.coolsistema.com/buildByToken/buildWithParameters?job=bot-pr&token=<토큰>"
echo
echo "다음 수동 단계 2개:"
echo "  1) GitHub 3개 repo 웹훅 추가 (Settings > Webhooks):"
echo "     https://deploy.coolsistema.com/github-webhook/  (push 이벤트만)"
echo "  2) fine-grained PAT 을 서버에 저장:"
echo "     ssh jhkim@62.72.7.245"
echo "     sudo bash -c 'umask 077; cat > /var/lib/jenkins/.github_pr_token'  (토큰 붙여넣고 Ctrl-D)"
echo "     sudo chown jenkins:jenkins /var/lib/jenkins/.github_pr_token"
echo "================================================================"
