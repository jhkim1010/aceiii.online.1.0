# SPEC: RULE-04 노이즈 제거 (Docker 감시 allowlist 필터)
생성일: 2026-04-22

## 목표
운영 서버에서 Ventago 와 무관한 제3자 컨테이너(portainer_agent, minio-client 등) 가 RULE-04 를 대량 fire 시키는 노이즈를 제거한다. `DOCKER_MONITOR_PREFIXES` 를 Ventago 관련 prefix 로 한정 설정.

## 배경 및 컨텍스트
- 재배포 후 43분간 RULE-04 가 82건 fire (최근 2분마다 새 fire) — 과도한 노이즈.
- 이전 확인에서 `portainer_agent` (created/exitCode=128), `minio-client` (exited 2개월 전) 이 반복 감지됨.
- `DockerPoller` 는 모든 컨테이너를 수집 → `DockerRulesService.isMonitored()` 가 prefix allowlist 로 필터.
- 현재 `DOCKER_MONITOR_PREFIXES` 빈값 → 전체 감시 (= 필터 없음).
- 코드 변경 불필요. `.env` 값만 설정하면 됨.

## 기술 스택
- 언어/프레임워크: NestJS 11 + TypeScript
- DB: PostgreSQL (변경 없음)
- ESLint 설정: vw-agent/.eslintrc.js

## 변경 대상
- `vw-agent/.env` (운영 서버) — `DOCKER_MONITOR_PREFIXES` 값 설정
- 코드 변경 없음

## 태스크 목록
- [ ] TASK-1: 운영 서버 컨테이너 전체 목록 조사 (docker ps -a)
- [ ] TASK-2: RULE-04 이벤트 집계로 실제 감지된 컨테이너 확인
- [ ] TASK-3: Ventago 관련 prefix 확정 (사용자 승인)
- [ ] TASK-4: `.env` 의 DOCKER_MONITOR_PREFIXES 갱신 (+ 백업)
- [ ] TASK-5: `docker compose restart vw-agent` (빌드 불필요)
- [ ] TASK-6: 기동 로그에 prefix 값 반영 확인 — "Docker Rules 활성 (prefixes=...)"
- [ ] TASK-7: 15분 관찰 — RULE-04 count_24h 증가 멈춤 확인

## 완료 기준
- Ventago 관련 컨테이너 (api_ventago / dbpostgres / ventago_* 등) 는 여전히 감시 중
- portainer_agent / minio-client 등 제3자 컨테이너는 더 이상 fire 안 함
- RULE-04 의 신규 fire 빈도가 현저히 감소

## PostgreSQL Pool 안전 점검
- 이 작업은 PG 와 무관 — pool 영향 없음
- Docker socket 접근 패턴도 동일 (전체 list 는 여전히 수집, 판단에서만 필터)

## 금지사항 / 주의사항
- 코드 변경 없이 `.env` 만 수정. 빌드 불필요, restart 만으로 반영.
- allowlist 에 누락이 생기면 실제 장애 시 알림이 안 올 수 있으므로 prefix 선택 신중.
- 빌드를 다시 하지 않으므로 `docker compose restart vw-agent` 가 정답 (`up -d --build` 아님).
