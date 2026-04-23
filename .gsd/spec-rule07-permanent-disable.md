# SPEC: RULE-07 (프린터 에이전트 offline 감시) 영구 비활성화
생성일: 2026-04-22

## 목표
RULE-07 (zebra / thermal 프린터 에이전트 offline 감시) 을 `.env` 플래그로 영구 비활성화하고, DB 의 유령 에이전트 레코드 id=5 (PB comandera) 를 삭제한다.

## 배경 및 컨텍스트
- 프린터 에이전트 관리는 운영자(사용자) 책임 밖의 영역으로 결론 — 알림 가치가 없음.
- 현재 운영 중 RULE-07 이 15분 dedup 에도 불구하고 매번 6+ 건의 "agent offline" 을 SQLite 에 기록 중.
- 2026-04-22 16:24 최초 배포. 유령 에이전트 6건 (id 6/8/9/10/11/12) 은 이미 DELETE 완료. id=5 만 남음 (last_seen_at 이 NULL 이 아닌 40시간 전이라 앞선 WHERE 조건에서 제외됨).
- 설계 방향 재검토 결과 "영구 비활성" + "나중에 시나리오 C (is_monitored 플래그) 로 부활 가능성 열어둠" → 코드 삭제가 아니라 ENV 플래그 off 스위치 채택.

## 기술 스택
- 언어/프레임워크: NestJS 11 + TypeScript
- DB: PostgreSQL 10 (운영 호스트, read-only watcher 계정, pool max=3)
- ESLint 설정: `vw-agent/.eslintrc.js` (strict — warning 도 build 실패 처리)

## 변경 대상 파일
| # | 파일 | 변경 |
|---|---|---|
| 1 | `vw-agent/src/config/env.schema.ts` | `RULE_07_ENABLED: z.coerce.boolean().default(true)` 추가 |
| 2 | `vw-agent/src/reasoners/agent-rules.service.ts` | flag false 시 onModuleInit 에서 bus.on 스킵 + 비활성 로그 |
| 3 | `vw-agent/src/observers/agent-poller.service.ts` | flag false 시 onModuleInit 에서 timer 시작 스킵 + 비활성 로그 |
| 4 | `vw-agent/.env.example` | `RULE_07_ENABLED=true` 주석 추가 |
| 5 | `vw-agent/README.md` | 규칙 표에서 RULE-07 에 "비활성 (영구)" 표시 |

## 태스크 목록
- [ ] TASK-1: `env.schema.ts` 에 `RULE_07_ENABLED` 추가
- [ ] TASK-2: `agent-rules.service.ts` 비활성 분기 추가
- [ ] TASK-3: `agent-poller.service.ts` 비활성 분기 추가
- [ ] TASK-4: `.env.example` 업데이트 (주석 + 기본값)
- [ ] TASK-5: `README.md` 규칙 표 업데이트
- [ ] TASK-6: 로컬 lint + test + build 통과 확인 (사용자가 Mac 에서 실행)
- [ ] TASK-7: 서버로 rsync + 서버 `.env` 에 `RULE_07_ENABLED=false` 추가
- [ ] TASK-8: `docker compose up -d --build` 재기동 + 비활성 로그 확인
- [ ] TASK-9: **DB DDL — id=5 유령 에이전트 삭제 (사용자 승인 필요)**
- [ ] TASK-10: /health 로 RULE-07 fire 중단 확인 (15분 후 재검증)

## 완료 기준
- ESLint 오류 0개
- lint / test / build 전부 통과
- 서버 기동 로그에 `Agent Rules 비활성 (RULE_07_ENABLED=false)` + `Agent Poller 비활성 (RULE_07_ENABLED=false)` 표시
- /health 의 `rules` 에 RULE-07 이 더 이상 추가 fire 하지 않음 (기존 count_24h 는 유지되나 증가 멈춤)
- Telegram 에 추가 RULE-07 알림 없음
- `branch_agents` 테이블에 `last_seen_at IS NULL` 인 row 0건, id=5 삭제됨

## PostgreSQL Pool 안전 점검
- AgentPoller 비활성화로 **60초 주기 SELECT 1건 제거** — pool 사용 감소 (절약 방향, 낭비 없음)
- 다른 쿼리 패턴 변경 없음
- id=5 DELETE 는 단일 row 삭제로 pool 영향 무시 가능

## 금지사항 / 주의사항
- AgentPoller / AgentRules 의 **코드 자체는 삭제하지 않음** — flag off 만.
- `BranchAgentRow`, `AgentSnapshot` 등의 type 도 유지 — 재활성 가능성 보존.
- id=5 삭제 전 FK 참조 재확인 (이미 terminals 참조 0건 검증됨).
- 프론트엔드 `sucursales/[id]/impresora` 페이지는 건드리지 않음 — UI 상으로는 여전히 에이전트 관리 가능.
