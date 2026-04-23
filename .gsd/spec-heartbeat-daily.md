# SPEC: Heartbeat 주기 변경 (30분 → 매일 KST 09:00 1회) + 24h 요약
생성일: 2026-04-23

## 목표
vw-agent 의 RULE-08 heartbeat 송신 주기를 30분마다 → **매일 한국시간 09:00 정각 1회**로 변경. 메시지 본문은 지난 24시간 이벤트 요약 (critical/warn 건수 + 규칙별 breakdown) 을 포함하여 "간밤/어제 무슨 일 있었는지" 를 한 번에 파악 가능하게 한다.

## 배경 및 컨텍스트
- 현재: `setInterval(30분)` 로 무조건 송신. 문제 없을 때는 하루 48건의 noise.
- 사용자 요청: 아무 문제 없으면 하루 1회. 결정: 매일 09:00 KST 고정 + 24h 요약 포함 (A-x).
- NestJS `@nestjs/schedule` 이 이미 AppModule 에 등록되어 있어 `@Cron` 사용 가능.
- 기동 직후 "살아있음" 증명은 이미 `formatStartup()` 이 보내는 🟢 기동 완료 메시지로 달성됨 → 기동 2분 뒤 첫 heartbeat 도 필요 없음.

## 기술 스택
- NestJS 11 + TypeScript + `@nestjs/schedule` (cron 데코레이터)
- Telegram MarkdownV2 메시지
- ESLint strict (warning 도 build error)

## 변경 대상 파일
| # | 파일 | 변경 |
|---|---|---|
| 1 | `vw-agent/src/reasoners/heartbeat.service.ts` | setInterval 제거 → `@Cron('0 0 9 * * *', { timeZone: 'Asia/Seoul' })` 적용 + 24h 이벤트 집계 로직 추가 |
| 2 | `vw-agent/src/notifiers/message.templates.ts` | `formatHeartbeat` → `formatDailyReport` 으로 시그니처 개편 (uptime + 요약 객체) |
| 3 | `vw-agent/src/notifiers/telegram.service.ts` | `sendHeartbeat` → `sendDailyReport` 이름/파라미터 변경 |
| 4 | `vw-agent/.env.example` + README.md | `HEARTBEAT_INTERVAL_MIN` 제거 안내 (또는 deprecated 주석) + 스케줄 명시 |
| 5 | `vw-agent/src/config/env.schema.ts` | `HEARTBEAT_INTERVAL_MIN` 은 코드에서 더 이상 안 쓰지만 schema 유지 (추후 재활용) |

## 메시지 예시 (변경 후)
```
💚 vw-agent 일일 리포트
🕒 2026-04-24 09:00:00 (KST)
⏱ uptime: 1d 2h 15m

📊 지난 24시간 이벤트
  • critical: 0건
  • warn: 3건
  • info: 0건

📋 규칙별 발생
  • RULE-04: 2건 (warn)
  • RULE-06: 1건 (warn)

🔌 PG pool: total 1/3, idle 1, waiting 0
🧠 memory: 102 MB
```

## 태스크 목록
- [ ] TASK-1: `message.templates.ts` 에 `formatDailyReport()` 추가 (기존 `formatHeartbeat` 는 삭제 또는 유지 결정)
- [ ] TASK-2: `telegram.service.ts` 에 `sendDailyReport()` 추가
- [ ] TASK-3: `heartbeat.service.ts` 전면 개편
  - setInterval 제거
  - `@Cron('0 0 9 * * *', { name: 'daily-heartbeat', timeZone: 'Asia/Seoul' })` 메서드 추가
  - 24h 이벤트 집계 (SQLite `recentEvents` 200건 → 24h 필터 → severity/rule 별 집계)
  - 첫 송신 delay 로직 제거
- [ ] TASK-4: `.env.example` + `README.md` — HEARTBEAT_INTERVAL_MIN 안내 갱신 ("cron 으로 대체됨, 값은 무시")
- [ ] TASK-5: 로컬 lint/test/build 통과 확인
- [ ] TASK-6: rsync + `docker compose up -d --build`
- [ ] TASK-7: 기동 로그 확인 — `Heartbeat 시작 (daily cron 09:00 Asia/Seoul)` 출력
- [ ] TASK-8: (선택) 테스트 송신 — `@Cron` 을 발동시키는 수동 trigger 로 한 번 송신해서 포맷 확인

## 완료 기준
- ESLint 0 error, 테스트 0 failed, build 성공
- 서버 기동 로그에 "daily cron 09:00 Asia/Seoul" 또는 유사 표시
- 2026-04-24 09:00 KST 에 실제 1건 수신 + 24h 요약 포함
- 그 외 시각엔 heartbeat 송신 없음 (SQLite heartbeats 테이블 관찰)

## PostgreSQL Pool 안전 점검
- 이 작업은 PG 와 무관 (Heartbeat 은 SQLite 만 읽음). pool 영향 없음.
- 송신 1회가 하루 1번으로 감소 → Telegram API 호출 감소 (부차 효과).

## 금지사항 / 주의사항
- `@Cron` 은 NestJS 프로세스 1개 기준 동작 — vw-agent 는 단일 컨테이너라 double-fire 걱정 없음.
- `timeZone: 'Asia/Seoul'` 는 Node.js Intl / ICU 빌드 의존 — `node:20-bookworm-slim` 베이스에서 동작 확인 필요.
- 기존 `HEARTBEAT_INTERVAL_MIN` 환경변수는 schema 에서 제거하지 말 것 (운영 `.env` 가 갖고 있어서 제거하면 fail-fast). 사용만 안 함.
- `formatHeartbeat` 를 지우기 전에 다른 곳에서 참조 없는지 grep 확인.
- `@Cron` cron 표현: 6자리 (second 포함). "0 0 9 * * *" = 매일 09:00:00.
