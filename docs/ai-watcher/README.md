# AI Watcher (vw-agent) 프로젝트 문서

Ventago 운영 서버(srv803182) 를 감시·예측·수정하는 AI 비서 시스템의 설계 및 구현 문서 모음.

## 문서 목록

| 파일 | 역할 | 상태 |
|---|---|---|
| [roadmap.md](./roadmap.md) | 전체 로드맵 (M1~M6), 아키텍처, 서버 리소스 배분, 설계 원칙 | Active |
| [spec-M1.md](./spec-M1.md) | **Milestone 1 (MVP)** 상세 SPEC — 감시 규칙 8종 + Telegram 알림 | Active (승인 대기) |
| [spec-pool-leak-diagnosis-DEFERRED.md](./spec-pool-leak-diagnosis-DEFERRED.md) | PG connection 누수 진단 SPEC | Deferred (34 conn 정상으로 판정) |

## Milestone 구분

| Milestone | 기능 요약 | 예상 기간 |
|---|---|---|
| **M1** | 감시 + Telegram 알림 (MVP) | 3~5 일 |
| M2 | LLM (Claude API) 판단 추가 | +3~5 일 |
| M3 | 승인 기반 자동 수정 | +5~7 일 |
| M4 | 예측 기반 알림 (Preventive) | +7~10 일 |
| M5 | 세션/보안 이상 감지 | +3~5 일 |
| M6 | 웹 대시보드 (옵션) | +7~10 일 |

## 핵심 원칙 (변경 금지)

1. **PostgreSQL pool 낭비 금지** — vw-agent 는 전용 `ventago_watcher` read-only 계정 + 독립 pool (max=3)
2. **Destructive 작업은 승인 필수** — M3 부터 Telegram 승인 버튼. M1~M2 는 알림만
3. **최근 로그부터 확인** — 감지 루프의 첫 동작은 `api-ventago/logs/error-YYYY-MM-DD.log` 최신 파일 tail
4. **자기 자신을 감시** — dead-man heartbeat (Telegram silent 메시지 + /health 엔드포인트)
5. **오탐 우선 튜닝** — M1 은 "알림만" 받으면서 1주일 튜닝 기간 후 M2 진행

## 현재 상태

- [x] 로드맵 수립
- [x] M1 SPEC 상세화
- [x] Connection 누수 진단 (deferred)
- [ ] **M1 사용자 최종 승인 (현재 단계)**
- [ ] M1 Execute
- [ ] M1 Review
- [ ] M2 시작

## 관련 경로

- 구현 위치 (예정): `ACE_online_1.0/vw-agent/` (npm workspace 신규 추가)
- 참고 코드: `api-ventago/src/database/database.module.ts` (Sequelize pool 설정)
- 참고 코드: `api-ventago/src/common/logger/logger.config.ts` (Winston 로그 설정)
- 모니터링 대상 로그: `api-ventago/logs/error-*.log`, `api-ventago/logs/combined-*.log`
