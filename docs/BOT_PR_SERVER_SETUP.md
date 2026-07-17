# ③ 서버 세팅 — 봇 PR 게이트웨이 + 배포 웹훅 (2026-07-17)

## 배경
- 목표: 폰 명령 → (Mac off) → 클라우드가 코드 수정 → PR → 사용자 승인 머지 → 자동 배포.
- 정찰 결과: `deploy.coolsistema.com`(nginx 443) → Jenkins 8080 프록시 이미 존재.
  front(`ventago-app`)·api(`api-ventago`) 잡에 GitHubPushTrigger 이미 켜져 있음.
  **빠진 것은 GitHub 쪽 웹훅 등록뿐** (그래서 지금까지 수동 트리거였음).
- 무인 인증 설계: GitHub 자격증명은 **서버에만**. 클라우드는 bot-pr 잡 하나만
  트리거할 수 있는 **capability 토큰 1개**만 소지 (유출돼도 PR 열기만 가능).
- 에이전트가 서버에 직접 설치하는 것은 정책상 차단 → 이 스크립트를 사용자가 실행.

## 1. 실행 (Mac 터미널에서)
```bash
scp /Users/marcoskim/Trabajos_Programming/ACE_online_1.0/scripts/setup-bot-pr-jenkins.sh jhkim@62.72.7.245:~/
ssh jhkim@62.72.7.245 'bash ~/setup-bot-pr-jenkins.sh'
```
스크립트가 하는 일:
1. `build-token-root` 플러그인 설치 (토큰으로 **지정 잡만** 트리거 — Jenkins 전체 권한 아님)
2. ACE-Sync 잡에 GitHubPushTrigger 추가 (백업: config.xml.bak.타임스탬프)
3. capability 토큰 생성 → `/var/lib/jenkins/.bot_trigger_token` (600)
4. `bot-pr` 빌드 스크립트 + 잡 생성 (허용 repo 3개, 브랜치 `bot/*` 강제, main push 불가)
5. Jenkins 재시작 (도커 앱 컨테이너는 무관 — CI 만 재시작)
6. 셀프 테스트 (webhook 엔드포인트 + 토큰 트리거)

마지막에 출력되는 **capability 토큰을 Claude 에게 전달**하면 클라우드 세션이 사용.

## 2. GitHub 웹훅 (자동 배포의 마지막 조각)
3개 repo 각각: `jhkim1010/ventago-app`, `jhkim1010/api-ventago`, `jhkim1010/node_js_svr_ace3`
- Settings → Webhooks → Add webhook
- Payload URL: `https://deploy.coolsistema.com/github-webhook/`
- Content type: `application/json`, 이벤트: **Just the push event**
- 등록 후 Recent Deliveries 에 초록 체크 = 정상
→ 이제 main 에 머지되면 Jenkins 가 즉시 빌드·배포 (수동 트리거 불필요)

## 3. fine-grained PAT (봇 push + PR 생성용, 서버에만 저장)
github.com → Settings → Developer settings → Fine-grained tokens → Generate:
- Repository access: 위 3개 repo 만
- Permissions: **Contents = Read and write**, **Pull requests = Read and write**
- 만료 90일 (만료 시 재발급해서 같은 파일에 덮어쓰기)
저장 (토큰을 채팅에 붙이지 말 것):
```bash
ssh jhkim@62.72.7.245
sudo bash -c 'umask 077; cat > /var/lib/jenkins/.github_pr_token'   # 토큰 붙여넣고 엔터, Ctrl-D
sudo chown jenkins:jenkins /var/lib/jenkins/.github_pr_token
```

## 4. 동작 확인
- DRY_RUN 테스트 (푸시 안 함): Claude 가 클라우드에서 실행하거나 직접:
```bash
curl -s "https://deploy.coolsistema.com/buildByToken/buildWithParameters?job=bot-pr&token=<토큰>&DRY_RUN=true"
```
- Jenkins UI → bot-pr → 빌드 로그에서 "연결 테스트 OK" 확인.

## 5. 롤백 (전부 가역)
```bash
# 웹훅: GitHub Settings > Webhooks 에서 삭제 → 이전 수동 방식 그대로
sudo cp /var/lib/jenkins/jobs/ACE-Sync/config.xml.bak.<TS> /var/lib/jenkins/jobs/ACE-Sync/config.xml
sudo rm -rf /var/lib/jenkins/jobs/bot-pr /var/lib/jenkins/plugins/build-token-root.hpi
sudo rm -f /var/lib/jenkins/.bot_trigger_token /var/lib/jenkins/.github_pr_token /var/lib/jenkins/bot-pr.sh
sudo systemctl restart jenkins
# PAT: GitHub 에서 revoke
```

## 보안 요약
| 비밀 | 위치 | 유출 시 최대 피해 |
|---|---|---|
| capability 토큰 | 서버 600 + 클라우드 세션 | bot-pr 잡 트리거 = PR 열기만 |
| GitHub PAT | 서버 600 (jenkins 만 읽음) | 3개 repo push/PR — 단 배포는 사람 머지 게이트 |
| Jenkins SSH 키 | 기존 그대로 | 변경 없음 |
배포는 항상 **사람이 PR 머지해야** 발생 → 봇 단독으로 prod 도달 불가.
