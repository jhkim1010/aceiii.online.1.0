# SPEC: print-agent 셋업 마법사 서버 URL 입력 제거

생성일: 2026-06-30

## 목표
print-agent 첫 실행 셋업 마법사(Step 1)에서 "URL del servidor" 입력 칸을 제거하고, 고정 서버(`SERVER_URL`)를 자동 사용한다. 사용자는 API Key만 입력한다.

## 배경 및 컨텍스트
- 실제 WebSocket 연결 함수 `initWebSocket()`(main.js)는 이미 `const url = SERVER_URL;` 로 코드 고정 URL만 사용 — 마법사 입력 URL은 연결에 사용되지 않는 잔재.
- `SERVER_URL` = 개발 `http://localhost:5002/api`, 운영 `https://newapi.coolsistema.com/api` (main.js:28-30).
- 메인 화면(`index.html`)의 프로파일 편집기는 이미 정리됨: `formUrl`이 `type="hidden"`(line 86), 저장 시 `apiUrl: ''` 고정(line 536). → 추가 작업 불필요.
- 유일하게 사용자에게 보이는 URL 칸은 `setup-wizard.html` Step 1.

## 기술 스택
- 언어/프레임워크: Electron 28 (Node.js main + renderer)
- DB: 없음 (PostgreSQL 미관련 → pool 규칙 N/A)
- ESLint: print-agent 별도 설정 확인 후 적용

## 태스크 목록
- [ ] TASK-1: main.js — `agent:serverUrl` IPC 핸들러 추가 (SERVER_URL 반환)
- [ ] TASK-2: preload.js — `getServerUrl` 브릿지 추가
- [ ] TASK-3: setup-wizard.html — `#apiUrl` 입력 제거, readonly 서버 표시(`#serverDisplay`)로 대체, 안내 문구 수정
- [ ] TASK-4: setup-wizard.js — SERVER_URL 자동 로드/사용, API Key만 검증·저장
- [ ] TASK-5: 검증 (문법/ESLint, IPC 연결 확인)

## 완료 기준
- 마법사 Step 1에 URL 입력 칸이 없음. 사용자는 API Key만 입력.
- "Probar conexión"이 고정 SERVER_URL로 테스트.
- 연결 성공 시 `apiUrl=SERVER_URL`, `apiKey` 저장 → 기존 마이그레이션/연결 로직과 호환.
- 문법/ESLint 오류 0개.

## 금지사항 / 주의사항
- `initWebSocket()` 연결 로직은 건드리지 않음 (이미 SERVER_URL 사용).
- index.html 프로파일 편집기는 이미 정리됨 — 범위 밖, 변경 금지.
- IPC 시그니처(`ws:test`)는 유지해 다른 화면 영향 없게 함.
