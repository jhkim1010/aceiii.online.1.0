# Phase 85 W2 잔여 2건 — codex 검토 지적별 판단

검토 입력: 워킹트리 (`scripts/codex-review.sh --working`, 2026-08-20)
보고서 원본: `.team/reviews/working-codex.md`
대상 변경: PrinterConfigTab 폴링 제거 + 소켓 집계(SocketCensusService) 도입

| # | 심각도 | 지적 | 판단 |
|---|---|---|---|
| 1 | P1 | Redis 장애 시 `await client.connect()` 가 부팅을 무기한 막는다 | **수용 — 수정함** |
| 2 | P2 | `GET /diagnostics/sockets` 가 키마다 직렬 왕복(N+1) | **수용 — 수정함** |

## 1) [P1] Redis 가 내려간 채 부팅하면 앱이 뜨지 않는다 — 수용

**지적이 맞다.** node-redis 는 `reconnectStrategy` 가 숫자를 돌려주는 한 **초기 접속도**
무한 재시도한다. `onModuleInit` 에서 `await connect()` 를 하면 Redis 가 죽어 있을 때
그 Promise 가 영영 resolve 되지 않아 **Nest 부팅 자체가 멈춘다.** 이 서비스는 설계상
Redis 없이도 동작해야 하므로(관측 정확도만 떨어진다) 부팅을 볼모로 잡을 이유가 없다.

수정: `connect()` 를 `void ... .catch(...)` 로 배경에 맡기고, 활성 여부는 원래 있던
`ready` 이벤트로만 판정한다. 성공 로그도 `ready` 핸들러로 옮겼다.

★ **같은 형태가 저장소에 이미 두 곳 더 있다** — `RedisThrottlerStorage.onModuleInit`
(`await this.client.connect()`) 와 `main.ts` 의 `RedisIoAdapter.connect()`. 이번 변경의
결함은 아니지만 **같은 조건에서 같은 방식으로 부팅이 막힌다.** 이번 커밋 범위 밖이라
고치지 않고 여기 기록만 남긴다 → Phase 85 이월 항목.

## 2) [P2] 진단 스캔의 Redis N+1 — 수용

**지적이 맞다.** SCAN 으로 얻은 키마다 `aliveCount()` 를 순차 `await` 하면 최대
SCAN_KEY_CAP(20,000) 회의 직렬 왕복이 된다. superadmin 온디맨드 엔드포인트라 상시
부하는 아니지만, 300매장에서 진단 한 번이 수십 초 걸리면 **그 진단은 안 쓰이게 된다** —
관측 장치가 안 쓰이면 없는 것과 같다.

수정: `aliveCountBatch()` 를 추가해 SCAN 한 페이지(≈500키)를 `multi` 하나로 읽고,
죽은 항목 삭제도 한 번의 `multi` 로 묶었다. 왕복이 페이지당 최대 2회가 된다.
죽은 항목 정리 자체는 그대로 한다 — 그것이 이 구조의 자가 치유다.

회귀 테스트를 함께 넣었다(`socket-census.service.spec.ts`):
"distribution: 죽은 항목은 세지 않고 실제로 지운다 (배치 경로도 정리한다)".
정리 로직을 지우면 이 테스트가 죽는다.
