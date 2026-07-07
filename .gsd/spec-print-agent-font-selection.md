# SPEC: print-agent 티켓 폰트/크기 선택 기능
생성일: 2026-07-07

## 목표
티켓 출력 폰트를 Courier New 고정에서 사용자가 선택 가능한 11종 폰트 + 5단계 크기로 변경. 기본값은 Arial(가독성).

## 배경 및 컨텍스트
- 출력 경로: formatter.js(HTML 생성) → renderer-engine.js(`renderHtmlToPng`, offscreen Chromium) → PNG → ESC/POS 래스터
- HTML 렌더링이므로 OS 시스템 폰트 자유 사용 가능
- 모든 출력(invoice/fiscal/temp/qr/test)이 `renderHtmlToPng` 단일 경로 통과 → 여기서 중앙 적용
- 설정 저장: electron-store (`store:get`/`store:set` IPC 이미 존재)
- 폰트 크기: CSS에 px 값 60+개 산재 → 배율(scale) 방식으로 `font-size: Npx` 전체 regex 스케일링

## 기술 스택
- Electron 28 / Node.js (CommonJS)
- ESLint 설정 없음 (print-agent는 electron-builder 빌드, lint 미적용) → node --check 구문 검증으로 대체
- PostgreSQL 미사용

## 태스크 목록
- [ ] TASK-1: `src/font-settings.js` 신규 — 폰트 목록/배율 정의, configure(), applyFontSettings(html)
- [ ] TASK-2: `src/renderer-engine.js` — renderHtmlToPng 진입점에서 applyFontSettings 적용
- [ ] TASK-3: `main.js` — store defaults(ticketFont='arial', ticketFontScale=1), 부팅 시 configure, store:set 시 재구성
- [ ] TASK-4: `renderer/index.html` — "Fuente del ticket" 카드 (폰트 select + 크기 select + 실시간 미리보기), setConfig 연동
- [ ] TASK-5: node --check 구문 검증 + 리뷰

## 폰트 목록 (Windows 기본 탑재 위주, fallback 포함)
Arial(기본), Verdana, Tahoma, Segoe UI, Calibri, Trebuchet MS, Georgia, Times New Roman, Courier New, Consolas, Lucida Console

## 크기 배율
85% / 100%(기본) / 115% / 130% / 145%

## 완료 기준
- 모든 출력 타입에 폰트/크기 반영, 설정은 재시작 후에도 유지
- 기존 설치본 업그레이드 시 기본값 Arial 적용 (사용자 요구: 가독성)
- node --check 오류 0개

## 금지사항 / 주의사항
- QR 코드 이미지 자체는 영향 없음 (텍스트만 스케일)
- 76mm 폭(576px)은 불변 — zoom 사용 금지 (레이아웃 폭 깨짐)
- api-ventago / 서버 변경 없음 (agent 단독 기능)
