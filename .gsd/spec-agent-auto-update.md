# SPEC: print-agent / zebra-agent 자동 업데이트 (electron-updater)
생성일: 2026-07-07

## 목표
매장 PC에 설치된 에이전트가 스스로 새 버전을 감지·다운로드·설치하도록 하여,
릴리즈 후 수동 재설치 없이 전 매장에 업데이트가 전파되게 한다.

## 배경 및 컨텍스트
- 릴리즈 흐름: `push-both.sh` → `print-agent-vX.Y.Z` 태그 → GitHub Actions →
  public repo `jhkim1010/ventago-downloads` 릴리즈에 설치파일 업로드
- 문제 1: ventago-downloads 를 print/zebra 두 앱이 공유 → GitHub provider 의
  "최신 릴리즈" 조회가 서로 충돌 → **generic provider + 앱별 고정 롤링 태그** 사용
  - print: `print-agent-latest`, zebra: `zebra-agent-latest`
  - URL: `https://github.com/jhkim1010/ventago-downloads/releases/download/<태그>/`
- 문제 2: package.json version 이 태그와 무관 (1.0.9 고정) → CI 에서 태그 버전을
  package.json 에 stamp 해야 updater 버전 비교가 정확해짐
- 문제 3: macOS 는 코드서명 없음 → 자동 업데이트 Windows 전용 (매장 PC = Windows)
- 트레이 'Salir' 는 `app.exit(0)` 사용 — electron-updater 의 autoInstallOnAppQuit 은
  'quit' 이벤트에 훅되므로 app.exit 에서도 동작. 추가로 트레이에 수동 설치 메뉴 제공.

## 기술 스택
- Electron 28 + electron-builder 24 + electron-updater 6 (신규 의존성)
- ESLint: 에이전트 워크스페이스에는 설정 없음 → `node --check` 로 문법 검증
- PostgreSQL: 해당 없음

## 태스크 목록
- [ ] TASK-1: print-agent/package.json — electron-updater 의존성 + publish(generic) 설정
- [ ] TASK-2: print-agent/src/updater.js 신규 — 체크(부팅 10초 후 + 4시간마다),
      백그라운드 다운로드, 종료 시 설치, 로그 브로드캐스트
- [ ] TASK-3: print-agent/main.js — initAutoUpdater 연동 + 트레이 "Reiniciar y actualizar" 메뉴
- [ ] TASK-4: .github/workflows/build-print-agent.yml — 버전 stamp(npm version) +
      latest.yml/exe/blockmap 을 print-agent-latest 롤링 릴리즈에 업로드
- [ ] TASK-5: zebra-agent 동일 적용 (package.json / src/updater.js / main.js / workflow)
- [ ] TASK-6: 루트 package-lock.json 갱신 (npm install --package-lock-only)
- [ ] TASK-7: node --check 문법 검증

## 완료 기준
- 두 에이전트 모두 packaged+win32 에서만 업데이트 체크 (dev/mac 스킵)
- CI 가 버전 stamp → latest.yml 생성 → 롤링 릴리즈 덮어쓰기 업로드
- 기존 버전별 릴리즈(히스토리)는 그대로 유지
- 문법 오류 0개

## 금지사항 / 주의사항
- 기존 print 파이프라인/WebSocket 로직 변경 금지
- 'Salir' 의 app.exit(0) 유지 (mainWindow close preventDefault 때문에 app.quit 불가)
- 첫 배포는 여전히 수동 재설치 필요 (기존 설치본에는 updater 없음)
- RELEASE_REPO_TOKEN 시크릿 재사용 (이미 존재)
