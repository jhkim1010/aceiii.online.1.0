# 봇 PR 워크플로우 세팅 (①)

Mac 이 꺼져 있어도 폰 명령으로 코드 수정 → 검토 → 배포가 되게 하려면,
클라우드 세션이 GitHub 에 **push + PR 생성**할 수 있어야 한다.
원칙: **봇은 main 에 직접 push 하지 않는다. 항상 PR 로 올리고, 사람이 머지한다.**

## 인증 — 두 가지 선택지

### (권장) GitHub 커넥터 연결 — OAuth, 토큰 노출 없음
- Claude 앱에서 GitHub 커넥터를 연결하면 클라우드 세션이 OAuth 로 push/PR 한다.
- 원시 토큰(PAT)을 프롬프트나 파일에 남기지 않아 가장 안전하다.
- 주의: 대화형(폰으로 직접 명령)일 때 동작한다. 완전 무인 예약 실행에서는
  커넥터가 없을 수 있으니, 그 경로는 아래 PAT 또는 서버측 러너로 보완한다.

### (대안) fine-grained PAT
github.com → Settings → Developer settings → Fine-grained tokens → Generate:
- Repository access: ACE 관련 repo 만 (전체 계정 아님)
- Permissions: **Contents = Read/Write**, **Pull requests = Read/Write**
- Expiration: 90일 등으로 짧게 두고 주기적으로 교체
- 이 토큰은 **메모리·repo·커밋에 절대 저장 금지.** 실행 시 `GH_TOKEN` 환경변수로만 주입.

## 헬퍼

`tools/bot-pr.sh <branch> "<제목>" "<본문>"`
- eslint 게이트(있으면) → 브랜치 생성 → 커밋 → push → `gh pr create`.
- 봇이 이 스크립트로 PR 을 올리면, 당신은 GitHub 에서 검토 후 **원클릭 머지**.
- 머지되면 Jenkins 배포 파이프라인이 이어받는다(배포 자동화는 별도 항목 ②/③).

## 브랜치 규칙
- 이름: `bot/<주제>-<식별자>` (예: `bot/trello-6a4e6bae`)
- 커밋은 작게, 자주. 하나의 PR = 하나의 논리적 수정.
- 육안 QA 가 필요한 UI/UX 변경은 PR 을 열어두고 사람이 화면에서 확인 후 머지.

## 남은 결정 (사용자)
1. 커넥터 방식 vs PAT 방식 택1 (권장: 커넥터).
2. 완전 무인 예약 루프까지 push 가 필요하면, 무인용 인증 경로(짧은 PAT 또는
   서버측 러너)를 별도로 정한다.
