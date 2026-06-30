# SPEC: socket.io PM2 cluster 안정화 (print-agent 연결 + 워커간 emit)

생성일: 2026-06-30
상태: 계획 (즉시 stopgap 적용됨 — instances:1)

## 목표
PM2 cluster(instances ≥ 2)를 복원하면서 print-agent/zebra-agent 연결을 안정화하고,
워커 간 emit 누락(판매 워커 ≠ agent 접속 워커)을 제거한다.

## 근본 원인 (확정)
- `ecosystem.config.js`: `instances: 2, exec_mode: 'cluster'`.
- socket.io HTTP long-polling 은 한 세션(sid)의 모든 HTTP 요청이 같은 워커로 가야 함.
- PM2 cluster 가 매 HTTP 요청을 라운드로빈 → sid 만든 워커와 다른 워커 도달 시
  engine.io `{"code":1,"message":"Session ID unknown"}` (HTTP 400).
- 재현 증거(2026-06-30): handshake→POST(200 ok, 같은 워커)→GET(400, 다른 워커).
  websocket 업그레이드 probe 도 라운드로빈으로 실패.
- 2차(잠재) 버그: 공유 어댑터 부재 → `server.to('branch:X').emit()` 이 같은 워커 소켓만
  도달. 연결이 성공해도 다른 워커에서 처리된 판매의 print_invoice/print_temp 누락.

## 즉시 stopgap (적용됨)
- `instances: 2 → 1`. 단일 워커라 sid 분산·워커간 emit 문제 모두 소멸. 서버 재시작 필요.
- 한계: 멀티코어 미사용(처리량↓). 500 동시접속 목표 위해 정식 수정 후 복귀 필요.

## 중요 제약 (PM2 + adapter caveat)
`@socket.io/cluster-adapter` 는 `setupPrimary()` 를 cluster primary 에서 호출해야 하는데,
PM2 cluster 모드에서 primary 는 pm2-runtime 이 소유 → 앱 코드가 primary 에서 안 돎.
따라서 표준 cluster-adapter 단독은 PM2 에서 동작하지 않음. 두 경로 중 택1 필요.

## 정식 수정 — 경로 후보 (택1, 사용자 결정 필요)

### 경로 A: ws-only + Redis adapter  (Redis 필요)
- 게이트웨이 `transports: ['websocket']` → 단일 Upgrade 로 워커 고정 → sticky 불필요.
- `@socket.io/redis-adapter`(+ ioredis) → 워커간 emit. Redis 는 워커가 직접 접속하므로
  PM2 primary 설정 불필요(동작 보장).
- 장점: 표준적, 수평 확장(다중 서버)까지 대비. 단점: Redis 인프라 추가.

### 경로 B: @socket.io/pm2 + cluster-adapter  (Redis 불필요)
- `pm2-runtime` → `@socket.io/pm2` 로 교체(Dockerfile). sticky session + 워커간 라우팅
  자동 처리. polling/websocket 모두 동작.
- 장점: Redis 없이 PM2 공식 해법. 단점: 런타임 교체 + 회귀 테스트.

## 태스크 목록 (경로 확정 후)
- [ ] TASK-1: (경로 결정) Redis 가용성 확인 → A 또는 B 선택
- [ ] TASK-2: 서버 어댑터 적용 (custom IoAdapter 에 adapter 주입)
- [ ] TASK-3: 게이트웨이 transports 설정 (경로 A: websocket 고정)
- [ ] TASK-4: print-agent / zebra-agent 클라이언트 `transports: ['websocket']`
- [ ] TASK-5: nginx `/socket.io/` Upgrade/Connection 헤더 + proxy_read_timeout ≥ 60s 점검
- [ ] TASK-6: 스테이징/단일 검증 후 `instances: 1 → 2(이상)` 복귀
- [ ] TASK-7: 2워커에서 print_invoice 워커-크로스 emit 도달 검증

## 완료 기준
- instances ≥ 2 에서 print-agent 가 끊김 없이 connected 유지.
- 임의 워커에서 발생한 판매의 출력 이벤트가 agent 에 100% 도달.
- ESLint 0, slow query 무영향.

## 금지/주의
- 표준 `@socket.io/cluster-adapter` 단독 사용 금지(PM2 primary 제약).
- pool: 워커 수 × max(80) 가 PG max_connections=300 이하인지 확인 (2워커=160 OK).
