---
gsd_state_version: 1.0
milestone: v1.1
milestone_name: 개선
status: executing
stopped_at: Phase 85 W1(캐시 봉인)·W2(소켓 공유+서버 집계) 완결·배포 · 소켓 한도는 분포 관측 후 env 로 켠다 · 다음은 W3 (2026-08-20)
last_updated: "2026-08-19T00:00:00.000Z"
last_activity: 2026-07-24
progress:
  total_phases: 61
  completed_phases: 24
  total_plans: 221
  completed_plans: 171
  percent: 77
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-01)

**Core value:** 매장 운영자가 POS 판매부터 재고/재무/외주까지 하나의 플랫폼에서 관리
**Current focus:** 2026-08-13 에 W1-12 소음 검증 + 요일별 피크 분포로 Phase 76 리허설 창 결정. 그 전까지는 W2(소켓 멀티플렉싱) 개발이 가장 큰 건

## Current Position

Phase 85 (scale-durability-structural-enforcement) — **W1·W2 완결·배포 (2026-08-20) · 다음 W3**

★ **W1 캐시 봉인 완료.** `get`/`set` 이 private 이라 3단(get→miss→DB→set) 패턴이 컴파일 에러다.
  스테이징 실측: 동시 100 요청에 DB calls **81 → 9**(워커당 정확히 1회 = 프로세스 로컬 캐시의
  이론적 하한). codex 검토가 **기존 `getOrLoad` 의 결함 2건**을 잡았다(무효화 vs 진행 중 loader /
  동기 재진입 시 조용한 undefined) — 둘 다 고치고 mutation 검증했다.
  상세: `.planning/HANDOFF-2026-08-20-b-phase85-w1-done.md`
  ★ `/me` 는 W1 이 못 줄였다(3%) — 워밍 상태에서도 **11쿼리가 미캐시**다. 별도 대상이며
    이전 핸드오프가 이것을 "W7" 이라 적은 것은 **오기**다(W7 은 야간 rollup).

★ **W2 클라이언트 절반 완료·배포**(front-coolsistema #673 SUCCESS).
  기전: socket.io 는 **같은 네임스페이스를 두 번째로 열면 일부러 새 물리 연결을 만든다**
  (`lookup()` 의 sameNamespace 분기). `/realtime` 을 5곳이 각자 열어 POS 터미널 1대가
  연결 5개를 썼다. 이제 `src/realtime` 레지스트리가 네임스페이스당 1개를 공유하고,
  `no-restricted-imports` 로 `socket.io-client` 직접 사용을 봉인했다(예외 1개).
  spec 이 "소비자 5명 → `io()` 1회" 를 직접 단언한다(mutation 검증 완료).

★ 착수 전 대조에서 계획 수치 2개가 또 틀렸다 — 대상이 4개가 아니라 **9개**였고,
  「서버측 제한 기본 2」는 그대로 켜면 **POS 가 전부 끊긴다**. 근거 문서가 낡은 것이 3번째다.

★ **W2 방 이탈 프로토콜 완료·배포** (api #761 / front #674, 둘 다 SUCCESS).
  `unregister_terminal`·`unregister_branch`(/realtime) + `leave`(보드 2개).
  `registerTerminal` 도 이제 이전 방을 떠난다(`registerBranch` 는 원래부터 떠나고 있었다 —
  "leave 가 아예 없다" 던 최초 조사는 부정확했다).
  ★ codex 가 [HIGH] 경합을 잡았다: register 는 DB 검사를 await 한 뒤 join 하는데 leave 는
    동기라 `register → 대기 → leave(무효) → join` 순서면 원치 않는 방에 **영구히** 남는다.
    "지금 원하는 방" 을 await 전에 기록하고 join 직전 재확인하는 것으로 닫았다(회귀 spec 4건).

★ **W2 완결·배포** (api #762 + fe9b63e / front #675, 전부 SUCCESS). 잔여 2건 모두 처리:
  1. `PrinterConfigTab.tsx` 30초 폴링 제거 → 공유 소켓 `register_branch` 구독으로 대체.
  2. 서버측 소켓 수 집계(`SocketCensusService`) — **Redis 공유** 카운터.
     워커 로컬로 세면 pm2 4워커에 흩어져 실제의 1/4 만 보인다(rate-limit 과 같은 함정).
     죽은 항목은 6분 만료 + HDEL 로 자가 치유 — 없으면 워커가 SIGKILL 로 죽을 때마다
     카운트가 영구히 올라가 **한도를 켠 순간 전원 차단**이다.
  ★ **한도는 기본 0 = 꺼짐이다(의도).** 켜는 순간 초과분은 실시간 두절 = POS 에서
    MP 결제 승인 알림 두절이다. `GET /api/diagnostics/sockets`(superadmin) 의 `histogram`
    으로 실사용 분포를 며칠 본 뒤 `SOCKET_MAX_PER_IDENTITY` env 로 켠다(재배포 불필요).
    계획서의 "기본 2" 는 통합 **전**(POS 한 탭 = 5소켓) 값이라 그대로 켜면 POS 가 끊긴다.
  ★ 배포 직후 운영 Redis 확인에서 **키가 `u:undefined` 하나뿐**이었다 — 브라우저 JWT 에
    `id` 가 없어(서명 payload 는 name/email/roles/storeId 뿐) 전원이 한 identity 로 뭉쳤다.
    고쳐서 재배포한 뒤 또 보니 `u!<socketId>` — id·email 이 **둘 다 없는** 공방 포털
    토큰(`vendor-auth.service.ts:81`)이 `/realtime` 에 붙어 있었다. 이 저장소의 JWT 는
    한 가지 모양이 아니다(사용자=email만 / 재판매자=type+id / 공방=type+vendorId).
    `jwtIdentity()` 가 `type` 접두어 + (id|vendorId) → email 해시 → 소켓별 고유 순으로 고른다.
    **관측 장치는 "코드가 맞다" 로 검증되지 않는다 — 운영에서 나온 값을 봐야 한다.**
  ★★ **부수 발견 — Phase 85 밖이지만 판단이 필요하다** (`.planning/FINDING-2026-08-20-jwt-has-no-user-id.md`):
    사용자 JWT 에 `id` 가 없고 `jwt.strategy` 는 **email 로 사용자를 찾는다**. 운영 26명 중
    4명이 `email IS NULL` 이라 `WHERE email IS NULL` 이 **첫 행 하나**(id 24, store 6)를 돌려준다
    → id 29 로 로그인해도 이후 요청이 **id 24 로 해석**된다(귀속·감사·권한 전부).
    ★ id 40 은 **store 17** 이다 — 로그인하는 순간 테넌트 경계를 넘는다(아직 로그인 기록 없음).
    권한 캐시도 `authUserKey(email)` 이라 4명이 항목 하나를 공유한다.
    같은 원인으로 `emitToUser`(user:{id} room)도 죽어 있다.
    **모든 인증 요청이 타는 경로 변경이라 손대지 않았다 — 영업시간 금지.**
  ★ `/support` 는 공유 금지다 — 서버가 `client.data.role` 에 customer/viewer 를 덮어써서
    (support.gateway.ts:172/249) 공유하면 고객 화면공유가 조용히 죽는다. 서버에서 역할을
    분리하기 전에는 `DEDICATED` 에서 빼지 말 것.

★ **지켜진 규약과 무너진 규약의 차이는 성실함이 아니라 강제 지점의 유무다.**
2026-07-31 리뷰 9건 재점검 결과 백엔드 5건은 전부 해결(강제 지점이 있는 형태로 고침),
프론트 3건은 19일째 미해결이며 **신규 위반이 늘었다**(문서에만 있는 규약).
B-8 은 미해결이 아니라 **복제 중** — `catalog-refresh.ts:134` 가 주석에 "기존과 같은 형태"라
쓰고 안티패턴을 그대로 옮겼다.

★ 재점검 중 **초기 판정 2건이 반증으로 뒤집혔다**(B-4 pool 예산 = 해결 / B-7 = 부분해결).
근거 문서(2026-07-31 리뷰)가 이미 낡아 있었다 — **착수 전 코드 대조는 예외가 없다.**

- 계획: `.planning/phases/85-scale-durability-structural-enforcement/` — FINDINGS + SPEC + 01-PLAN
- 자문 근거: `.planning/ADVISOR-2026-08-19-승산과-300매장.md`
- 웨이브: W1 캐시 봉인 → W2 소켓 provider+서버제한 → W3 pageSize 클램프 → W4 무중단 마이그레이션·파티셔닝
  → W5 무중단 배포 → W6 매장별 논리 복구 → W7 야간 rollup → W8 300매장 회귀 자동화 + p95 게이트
- 착수 순서: **W1 부터.** 가장 기계적·저위험이라 강제 지점 패턴을 먼저 증명하기 좋다
- ★ W4 는 **행 수 실측 전에 착수 금지**(`85-FINDINGS.md` E 절). 추측 파티셔닝은 되돌리는 비용이 더 크다
- ★ W2·W3 는 **서버측 강제를 마지막에 켠다**. 순서를 바꾸면 전 고객이 끊기거나 화면이 죽는다
- 플랜은 웨이브 착수 시점에 쓴다 — 지금 W4~W8 을 상세히 쓰면 착수 전에 낡는다(Phase 84 교훈)

---

Phase 84 (produccion-cantidad-ledger-y-flujo-unico) — **W1·W2 배포 완료 · W3 진행 중 (2026-08-18)**

★ `stocks` 에 `type='production'` 첫 3행 생성 — 이 시스템에서 생산품이 처음 재고가 됐다.
로트 8 의 사라진 100장이 `unexplained_quantity=100` 으로 처음 숫자가 됐다.
핸드오프: `.planning/HANDOFF-2026-08-18-b-produccion-stock.md`
★ W1·W2 에서 **두 번 다 계획이 틀렸다** — 착수 전 코드 대조 필수.

계기: 사용자 보고 — *"materia prima / talleres 컨트롤에서 작업이 잘 흐르지 않고 개념이 명확하지 않다."*

★ 실측: `stocks` 1,716건 중 `type='production'` **0건** — 생산품이 판매 재고가 된 적이 없다.
로트 10 은 3공정 완료(2026-07-15) 후 34일째 `stocked_quantity=0`.
로트 8 은 **발송 기록 없이 100장 증발**.

근본 원인 둘: **차원 손실**(계획=변형별 / 실행=총량 / 재고=변형별) +
**권위 있는 수량 원장 부재**(CODEX 가 더 근본이라 지적).

- 계획: `.planning/phases/84-produccion-cantidad-ledger-y-flujo-unico/` — FINDINGS + 7 plans
- 목업: https://claude.ai/code/artifact/e6008879-c411-4dc1-866c-ee4583dc192a
- 착수 순서: W1(격자·지점 필수) → W2(상태 3분할) → W3(감사 원장) → W4(복구 큐, 사람 확인)
  → W5(자재 OPENING_BALANCE) → W6(격리·순서) → W7(작업 큐 화면)

★ **W6 의 `settlements.store_id` 는 0건인 지금이 유일한 기회다.**

---

Phase 83 (customer-delivery-confirmation-link) — **W1+W2 배포 완료 (2026-08-18)**

핸드오프: `.planning/HANDOFF-2026-08-18-entrega-confirmacion.md`

★ 세션 시작 시 발견: Enviado 보고서의 `Confirmar entrega` 버튼이 운영에서 **404** 였다
(프론트만 배포되고 서버가 워킹트리에 남아 있었다). 복구 후 Phase 83 진행.

- 마이그레이션 `2026-08-18-phase83-delivery-confirmation.sql` — 로컬(5432)·운영(5434) 양쪽 적용
- 공개 확인 링크: 토큰을 **body 로** 받는다(URL 로그 유출 차단, CODEX Blocker)
- 소요일 KPI 를 `delivered_on`(도착일) 기준으로 전환 — 늦게 눌러도 지연이 안 부푼다
- 링크 발송은 **카운터 QR** (운영 주문 12건 전부 이메일·전화가 비어 있다)

- 분쟁 해소 버튼: 보드 카드에 추가(#725/#653). 미해결 분쟁을 보드 목록 맨 앞으로
  정렬 — 안 그러면 오래된 주문의 새 신고가 50건 창 밖으로 밀려 닿을 수 없었다.

**미완 (다음 세션 1순위):** **실제 발송 1건으로 토큰 발급 → QR → 고객 확인 경로가
아직 한 번도 안 돌았다**(스모크는 잘못된 토큰 404 까지만). Enviado 보고서의
Reclamos 탭에는 해소 버튼이 없다(보드에만).

---

Phase 75 (scale-readiness) — **W1 배포·관찰 중 · W0 실측 완료 · W4-4/W6-8/W6-9 배포 (2026-08-07)**

### 2026-08-10 세션 추가분

**W6-1 크론 리더 lease — 배포·가동 중.** 플랜의 "advisory lock" 은 세 경로 전부 막혀 채택 불가였다
(pgbouncer transaction pooling · 크론 21개 중 다수가 외부 I/O · PG 직결 ECONNREFUSED).
lease 테이블로 구현. **codex 검토 3회에서 P1 5건 + P2 1건**이 나왔고 전부 수용했다 —
공통 뿌리는 "리더십을 부팅 시 1회 결정으로 다뤘다"는 것이었다(리더 사망 시 인수 불가 ·
뺏겨도 @Cron 계속 실행 · split-brain · fail-open 영구화). 후보 전원 상시 참여 + 전이 시
실제 stop/start + TTL 펜싱으로 재설계. 스테이징 2노드에서 하드 킬 → 인수까지 실증.
운영 관측: 리더 1 / 비리더 3, 리더십 상실·split-brain 0건.

**0-8 route p95 확보 — 그리고 사흘을 놓칠 뻔했다.** winston 이 `.log.gz` 로 회전하는데
수집기가 `.log` 만 봐서 3일치가 `n=0` 이었다. **나도 "계측이 안 온다"고 한 번 오진했다.**
원자료는 멀쩡했고 `.gz` 를 읽도록 고쳐 복구 — 08-07 p95 342ms / 08-08 p95 664ms.
**300ms 규약 초과.** 단 표본이 하루 27~60건(SPA 라우트 전환만 발화)이라 추세 비교용이다.

**G1 은 "충족"이 아니라 "측정된 적 없음"이었다.** 하루 1회 04:10 UTC(현지 01:10) 측정은
하루 중 가장 조용한 시각이라 `sockets` 가 나흘 내내 0 이었다. W2·G1·G6 는 전부 피크를
요구하므로 판정 자체가 성립하지 않았다 → **5분 주기 표본 수집** 추가(피크/p95/중앙 집계).
원자료도 Dropbox 로 보낸다 — 위 `.gz` 사고에서 원자료가 복구를 가능하게 했기 때문이다.

**0-6/0-7 브라우저 실측** — POS 진입 API 33건, 탭당 소켓 +2(5002·443 일치).
단 5002 는 전부 nginx 업스트림(127.0.0.1)이라 탭과 1:1 이 아니다. 탭당 WS 개수 확정은
DevTools 확인이 남았다. API 응답 크기는 `Timing-Allow-Origin` 부재로 측정 불가.

### 이번 세션(2026-08-06~07) 요약

**W1 일일 점검 — 배포 완료, 게이트 6건 통과.** `/var/lib/postgresql/ops-metrics/` + 크론 `10 4 * * *` +
Dropbox 오프사이트. Telegram 은 **사용자 단말 수신까지 확인**(발송 로그가 아니라 도달).
배포 중 **감시 결함 4건**을 발견·수정했고, 전부 같은 종류였다 — **"부재"에서 침묵하는 감시**:
ssh-agent 가 비어 Mac 워치독이 매시간 `판정 보류` 만 남기던 것(백업이 멈춰도 알림 없음) ·
pgbouncer 수집 불능(TCP 전용 + `stats_users` 계정 — `cl_waiting` 은 G1 의 유일한 근거) ·
heartbeat/`daily.jsonl` **파일 부재 시 무알림**(자기 게이트를 구현이 통과 못 하는 상태) ·
디스크 임계 env 화(검증하려고 스크립트를 고치면 원복을 빠뜨린다).

**W0 계측 기준선 — 확보(`75-W0-BASELINE.md`).** 그리고 **W4 의 전제를 반증했다**:
`sync_outbox` claim 3,015ms → 5일치 `pg_stat_statements` 에서 **45,009회 실행에 max 1.1ms**.
출처는 07-29 단일 일자 앱 로그였고 **그 로그는 이미 사라졌다**(컨테이너에 로그 volume 부재).
→ 4-2/4-3/4-3b **동결**, 4-4 **최우선 승격**, W4 성격을 "고친다"에서 "재발을 관측한다"로 전환.

**0-8(route p95)은 구조적으로 축적 불가였다** — 계측은 살아 있는데 배포마다 로그가 소멸.
volume 마운트 + 일일 p50/p95 집계로 **2026-08-07 부터 축적 시작**. W7 비교 기준은 이 시점 이후다.

**배포 완료:** W4-4(워커별 flush — 관측이 4워커 중 1개만 보고 있었다. 리더 가드 해제 cron 21→20 확인) ·
W6-8(워커 수 단일 출처 — `API_WORKERS=6` 이면 둘 다 이동, G3 실험 준비) ·
W6-9(`PGBOUNCER_POOL_SIZE=50` 실측 고정 — 부팅 로그에서 `(추정)` 소멸).

**G5 문구 정정:** `pool_size=50`(pgbouncer→PG, db·user 쌍별)과 앱→pgbouncer 클라이언트 합계(100)는
**층위가 다르다**. 원문대로 판정하면 정상 구성을 결함으로 오판하고 그 처방이 시스템을 느리게 만든다.

**Phase 76 신설** — 사용자 전략(스위치로 병렬을 리허설). CONTEXT·SPEC 작성 완료.

### 다음 (2026-08-13 판정)

1. **W1-12 소음 검증** — 정상 7일 알림 0건이어야 W1 완료
2. **요일별 트래픽** — Phase 76 리허설 창 결정 근거. **"주말"로 정하지 않는다**(토요일은 최대 매출일일 수 있다)
3. **0-3/0-6/0-7** — 영업시간 POS 탭 1개 DevTools (0-7 은 W2 게이트의 유일한 비교 기준)

---

Phase 70 (stock-cache-retirement-and-backlog-cleanup) — **7/7 플랜 완료 · 운영 배포 확인 (2026-08-04)**

선행 작업 **Stock Vistas W1~W4** (api #597 / front #527, 로컬·운영 마이그레이션 양쪽 적용):
`stocks.store_id`/`branch_id` 비정규화 + `stock_balances` 증분 스냅샷 + 인터페이스 뷰 4종 + 감시 뷰 2종 + Reportes › Stock Vistas 리포트. 불변식 `v_stock_balance_drift` / `v_stock_tenant_leak` 모두 0행 확인.

Phase 70 실행 결과 (단일 프로세스 순차 S1~S5 — cmux-team 병렬 실행은 인프라 사유로 중단, `70-RESUME.md` 에 실패 기록 보존):

| Plan | 결과 |
|---|---|
| 70-01 / 70-01b 재고 **읽기** 경로 → `stock_balances`/뷰 | 완료 — 잔여 `products.stock` 읽기 0 (api `ba22ff7`, `aa93aae`) |
| 70-02 미머지 브랜치 10개 + cmux-team 잔재 정리 | 완료 (S1) |
| 70-03 / 70-03b 상품 코드 수정·삭제 UI + 삭제 하드닝·SKU 소급 갱신 | 완료 (app `e5bb72a`, api `a1c0fbd` / app `c3d4995`) |
| 70-04 리포트 PDF 내보내기 + 상단바 반응형 | 완료 (api `eb31895`·`3e7c8f7` / app `7105226`·`fd951a4`) |
| 70-05 저장 성공 후 폼 리셋 (안 B) | 완료 (app `400e9cb`) |
| 70-06 `trg_stocks_sync_product_cache` 폐기 | 완료 — 로컬(5432) + 운영(5434) 양쪽 적용, `products.stock` 강등 (api `c0bfe06`) |
| 70-07 UAT + Trello 정리 | UAT 7건 PASS(쓰기 항목 포함 전수) — `70-UAT.md` |

UAT 중 발견한 실결함 1건: `POST /products/update-status` 403 — `updateProductsStatus` 가 `attributes: ['id','status']` 로만 조회해 인스턴스 `storeId` 가 `undefined` → TenantGuard 가 **자기 매장 상품**을 차단(전 매장 상태 일괄변경 불능). `attributes` 에 `storeId` 추가로 수정(api `0625429`, Jenkins **#604**), 배포 후 403 → 201 `{"updated":2}` 재검증. 동일 패턴(attributes 제한 조회 → 인스턴스 쓰기) 전수 스캔 결과 실결함은 이 1건뿐.

곁다리 배포: Trello `bklfCOX3` 같은 날 2번째 지점 입고(api `e5e7d76` / app `c3dd121`) · `zTHHD941` Codigo Vista(front #526) · `LNBmJ2ZI` 입고 취소 멱등화 + 운영 재고 -336→0 보정(api #595/#596) · `uyBUKfBM` 지점 전환(`/auth/me` 가 `active_sessions.branch_id` 우선, api #598).

**Phase 70 잔여 2건 (종결 전 처리):**

1. **Trello 카드 5건 → Hechos Semanales 이동** — Chrome 확장 미연결 + Trello 토큰 부재로 자동 이동 불가. `trello-inbox/triage-state.json` 에 `status: verified` / `hechosPending: true` 기록됨(fXUDii66 · 30zWO5C8 · zTHHD941 · diACgk5B · bklfCOX3).
2. **야간 03:30 드리프트 크론 첫 관찰** — 사전 확인은 PASS(`stock_balances` 232행, drift 0). 확인 명령: `docker logs api_ventago | grep 'stock drift reconcile'` → `drift 0 ✓` 및 텔레그램 무알람.

---

Phase 69 (tenant-isolation-security-hardening) — **11/11 플랜 완료 (2026-08-02)**

- R1 `/realtime` 소켓 handshake 인증 + room 소유권 검증 (69-01/02)
- R2 `correct-today` branchIds/variantId 전량 소유권 검증 (69-03)
- R3 벤더 포털 토큰 단일 매장 scope + 구 토큰 차단 (69-04/05)
- R4 파생 스코프 40개 확장 → `TENANT_DERIVED_MODE` 기본값 enforce 승격 (69-06/07)
- R5 TenantContext 확정 실패 fail-closed + storeId 미배정 차단 (69-08)
- 회귀 관문 `npm run test:tenant` 20종 (구코드 17/20 실패 증거) (69-09)
- 배포 런북 + 운영 UAT — R1/R3/R4/R5 실증 PASS, 에러 0 (69-10)
- 파생 미등록 모델 6개는 defer 철회 → 69-11 에서 엔진(`allowGlobalRows`/`anyOf`) 보강해 전부 등록, 파생 대상 39 → 45 (69-11-SUMMARY.md)
- 잔여: 브라우저/실계정 체크리스트 7항목 (deferred-items.md)

## 다음 작업 후보 (Phase 70 종결 후)

- **Phase 64 (트랜잭션 안전성·동시성)** — 10 플랜 중 wave 2~6·8~10 이 `partial`. 열린 것 중 가장 큰 덩어리
- **보안 마감 phase (신규 제안)** — Phase 65 W6 잔존분 + W7 을 묶는다. 근거는 `65-W6-AUDIT.md`
  1. `approver_role_slug` 집행 (6-4 PARTIAL — 컬럼·시드는 있는데 읽는 곳이 0곳이라 승인 등급 SoD 미성립)
  2. W6 회귀 spec 을 `test:tenant` 에 편입 (6-5 OPEN — 감사로그 2라우트·사용자 수정/삭제·자가승인 케이스 0건)
  3. W7-1/2/4 저장소 평문 자격증명 제거 + 부팅 시 시크릿 미설정 실패 + 스캔 게이트
  4. W7-3 **DB 계정 비밀번호 회전** — 파괴적, 단독 배포창 + 승인 + 주체 목록 선행
- **Phase 65 (재고 원장 단일 진실)** — **plan 없이 일부가 이미 배포됨.** W6 는 `c23ab35`(2026-07-29), W3~W5 는 Stock Vistas + Phase 70 이 대체. 남은 것은 W1·W7·W8·W9. 상세는 ROADMAP Phase 65 「실제 진행 상태」
- **Phase 74 (백업 RPO 축소·복구 검증)** — CONTEXT·SPEC·PLAN 완료(2026-08-06), plan 파일 미분할. **W1(백업 내용 검증)·W2(실패 알람)는 무위험·승인 불필요라 즉시 착수 가능.** 현황 실측: 백업은 정상 동작 중(03:17 → 03:40 Dropbox, 14일 로테이션)이나 RPO 24시간 · 복구 리허설 0건 · 실패 알람 0건 · 오프사이트 평문. W3(연속 WAL, `pg_receivewal`)은 복제 슬롯 디스크 위험으로 승인 게이트. 서버 2호기는 **D-63-2 보류 유지** — 범위 밖
- **Phase 75 (확장 준비 — 요청 비용·수평확장 전제·일일 점검)** — CONTEXT·SPEC·PLAN 완료(2026-08-06), plan 파일 미분할. **장기 phase(수 개월)**. 계기는 "사용자 3000명 대비" 질문이나 실측 결과 병목은 하드웨어가 아니었다(CPU 8코어 중 4개·31GB 중 18GB 유휴인데 동시접속 500 진단이 HIGH). **W1(일일 자동 점검 — 디스크 70%/일 증분 10GB/소진 예측/Telegram)을 최우선**으로 세운다 — 장기 작업이라 계측 없이는 진척을 판정할 수 없고, Phase 74 의 슬롯 디스크 감시·백업 실패 알람도 같은 장치를 공유한다. **`D-63-2`(2호기) 보류 유지** — 다만 이유를 "아직 필요 없어서"에서 "β(노드 간 일관성 비용) 때문에 지금 붙이면 역효과라서"로 교정하고, 착수 게이트 **G1~G6** 를 정의해 `66-PLAN.md:109` 의 순환 논법을 대체
- **Phase 74 (백업 RPO 축소·복구 검증)** — 위 참조. Phase 75 W1 과 일일 점검 장치 공유
- **Phase 66 (CRM·재무 정합성)** — CONTEXT·SPEC 만 있고 **플랜 미분할**, 실행 미착수. **P2 「2호기 착수 조건」은 Phase 75 W7 의 G1~G6 로 교체 예정**
- **Phase 57 (Facturación Electrónica)** — 3 wave 전부 `partial`
- 기타 `partial`: 05 데이터 임포트 · 09 store lifecycle · 10 factura · 26 gastos 트리 · 27 ventas online

---

Phase: 61 (tienda-online-editor) — EXECUTING
Phase 33 (Permissions v2 — RBAC + Branch Scope + Approval) — **VERIFIED 2026-06-11 ✅ (휴면 인정 종결)**

- 인프라: 마이그레이션(4 테이블/ENUM 13값/컬럼/인덱스) + 백엔드/프론트 배포 + 7 표준 role 시드 — Test 0~10 PASS (5/18~19)
- 33.1 D1/D2 hotfix 운영 배포 확인 (deployed dist 검증: D1 ensureRoleFunctions read-only ✅ / D2 bulkUpdate→invalidateRole ✅)
- Test 16 (pool) PASS — 경고/대기 0건, 4/400 연결. Test 18 (cold start) PASS — 6/9 재빌드 부팅 ERROR 0
- Test 12/13/14/15/17 N/A — 신규 RBAC 기능(branch scope/approval/cache/8-role) 운영 휴면, 영향 유저 0명
- Test 11 deferred — 프론트 배포 완료(#352), UI 렌더는 optional manual check
- 휴면 데이터(빈 role_functions/user_branches=0/permission_slug 131 null)는 acceptable artifact
- 상세: [.planning/phases/33-permissions-v2/33-UAT.md](phases/33-permissions-v2/33-UAT.md)
- 미적용(deferred, 사용자 confirm 필요): cleanup SQL `33.1-cleanup-orphan-role-functions.sql` — 운영 휴면이라 비긴급

Phase 33.1 (Permissions v2 D1/D2 Hotfix) — VERIFIED 2026-05-26 ✅ → 운영 배포 확인됨 (2026-06-11)
Plans: 3/3 (33.1-01 D1 95c2484 + 33.1-02 D2 0181056 + 33.1-03 REG e09376c) — Jest 11 PASS

Phase 35 (Activity Ledger — Movidos/Fallados Trace in ventaVista) — IMPLEMENTATION 완료 / ready-for-prod-deploy
Plans: 8/9 (35-01..35-08) + 35-09 UAT scaffold. UAT verified_with_gaps (22/22, 2026-05-23).
Status: Ready to execute

  - ✅ U9 권한 매핑: phase36-stock-movement-actions-backfill.sql (8c7ba1d, dev 멱등 검증) — role_function_actions 보강
  - ✅ 운영 RUNBOOK: 35-RUNBOOK-PROD.md 작성 (Phase 36-02) — 사용자 검토 대기
  - ✅ Phase 36.1 회귀 hotfix(REG-1/REG-2) 코드 존재 (f3ade81)
  - ⏳ 남은 manual UAT (dev 실행 필요): U9/U10 cURL smoke (POST /stocks/movement 200/403) + U14 movBalance 브라우저 ⚠ 캡처

Resume: 1) RUNBOOK 사용자 검토/승인 (35-RUNBOOK-PROD.md)
        2) `./dev.sh` 후 U9/U10 cURL + U14 브라우저 manual 보충
        3) 운영 적용 (RUNBOOK Section 0~4, 각 단계 사용자 확인) → Phase 35/36 complete → Phase 37 배포 게이트 해제

Phase 34 (Client WhatsApp + CRM Routing — Phase 29 Wave C) — IMPLEMENTATION 완료 / verifying
Plan: 15 of 15
Status: ⚠ verifying — 정식 UAT 미수행, 운영 매장 실사용 검증 대기

Phase 32 (stocks-historial-drawer) — COMPLETE (2/2)
Last activity: 2026-07-24

Progress: [████████░░] 82% (Phase 33/34 verifying 미산입, 운영 적용 + UAT 후 +4 plans 재계수 필요)

## Performance Metrics

**Velocity:**

- Total plans completed: 20
- Average duration: -
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 14 | 4 | - | - |
| 16 | 4 | - | - |
| 17 | 5 | - | - |
| 18 | 1 | - | - |
| 12 | 6 | - | - |

**Recent Trend:**

- Last 5 plans: -
- Trend: -

*Updated after each plan completion*
| Phase 01-ui-ux P01 | 8 | 2 tasks | 4 files |
| Phase 06-reportajes P01 | 25min | 2 tasks | 26 files |
| Phase 06-reportajes P02 | 15min | 2 tasks | 22 files |
| Phase 06-reportajes P03 | 10min | 2 tasks | 21 files |
| Phase 06-reportajes P04 | 10min | 2 tasks | 16 files |
| Phase 08-reportajes-ux P01 | 15min | 2 tasks | 15 files |
| Phase 08-reportajes-ux P02 | 20min | 2 tasks | 30 files |
| Phase 08-reportajes-ux P03 | 45min | 3 tasks | 9 files |
| Phase 08-reportajes-ux P04 | 35min | 3 tasks | 5 files |
| Phase 11-thermal-printing P01 | reconciled | 3 tasks | 5 files |
| Phase 11-thermal-printing P02 | 25min | 2 tasks | 4 files |
| Phase 11-thermal-printing P03 | 15min | 3 tasks | 3 files |
| Phase 11-thermal-printing P04 | 20min | 5 tasks | 9 files |
| Phase 11-thermal-printing P05 | 12min | 5 tasks | 5 files |
| Phase 16-control-de-talleres P06 | 90 | 3 tasks | 23 files |
| Phase 25 P01 | 30min | 3 tasks | 4 files |
| Phase 25 P02 | 5min  | 1 task  | 1 file (운영 적용만) |
| Phase 25 P03 | 30min | 3 tasks | 2 files (step5+step6 SQL) |
| Phase 25 P04 | 25min | 3 tasks | 4 files (step4 SQL + 3 models) |
| Phase 25 P05 | 25min | 7 tasks | 7 files (CommonModule + 가드 + auth/store 수정) |
| Phase 25 P06 | 30min | 6 tasks | 4 files (slug seed + controller/service @OwnerScope) |
| Phase 25 P09 | 10min | 4 tasks | 4 files (CUIT/DNI validators + spec) |
| Phase 25 P07 | 30min | 4 tasks | 4 files (promote service + module + controller + spec) |
| Phase 25 P08 | 25min | 3 tasks | 3 files (merge service + endpoint + spec) |
| Phase 25 P10 | 25min | 5 tasks | 5 files (DTO + service skel + controller + module + app.module 등록) |
| Phase 25 P11 | 30min | 4 tasks | 1 file (importBatch 본체 + bucket 분류 + chunked transaction) |
| Phase 25 P12 | 15min | 3 tasks | 1 file (per-row error + ClientImport audit + response shape) |
| Phase 25 P13 | 5min  | 2 tasks | 0 files (빌드/lint 검증 + SUMMARY 작성) |
| Phase 25 P14 | 25min | 4 tasks | 1 file (CargaMasivaClientesView frontend wiring) |
| Phase 26 P01 | 45min | 7 tasks | 8 files |
| Phase 26 P02 | 13min | 5 tasks | 12 files |
| Phase 26-gastos-categoria-tree-n-niveles P03 | ~9min | 4 tasks | 13 files |
| Phase 26-gastos-categoria-tree-n-niveles P04 | ~28min | 4 tasks | 17 files |
| Phase 29 P01 | 8min | 3 tasks | 8 files |
| Phase 29-pos-mercadopago-qr-din-mico PP02 | 6min | 1 task tasks | 7 files files |
| Phase 29-pos-mercadopago-qr-din-mico P02b | 11min | 2 tasks | 11 files |
| Phase 29-pos-mercadopago-qr-din-mico P03 | 16min | 3 tasks | 12 files |
| Phase 29-pos-mercadopago-qr-din-mico P04 | 20min | 3 tasks tasks | 7 files files |
| Phase 29 P05 | 28min | 3 tasks | 10 files |
| Phase 29 P06 | 30min | 3 tasks | 13 files |
| Phase 29 P07 | 25 | 5 tasks | 8 files |
| Phase 29 P08 | 18min | 2 tasks | 9 files |
| Phase 29 P08b | 8min | 3 tasks | 7 files |
| Phase 29 P09 | 12min | 4 tasks | 11 files |
| Phase 25 P15 | 30min | 2 tasks | 8 files |
| Phase 25-clientes-globales-compartidos-entre-tiendas-historial-aislad P17 | 13min | 2 tasks | 4 files |
| Phase 25-clientes-globales-compartidos-entre-tiendas-historial-aislad P18 | ~25min | 3 tasks | 4 files |
| Phase 32 P01 | 25min | 2 tasks | 2 files |
| Phase 32-stocks-historial-drawer-stocks-row-380px-drawer-productbranc P02 | 7min | 3 tasks | 5 files |
| Phase 39-modo-restaurante-pos-mesas P01 | 20min | 2 tasks | 6 files |
| Phase 39 P03 | 5min | 1 tasks | 1 files |
| Phase 39 P02 | 4min | 2 tasks | 6 files |
| Phase 39 P04 | 7min | 1 tasks | 3 files |
| Phase 39 P05 | 6min | 3 tasks | 5 files |
| Phase 40 P04 | 9min | 2 tasks | 7 files |
| Phase 40 P05 | 5min | 2 tasks | 7 files |
| Phase 40 P06 | 5min | 2 tasks | 6 files |
| Phase 40 P07 | 5min | 3 tasks | 5 files |
| Phase 40 P08 | 5min | 3 tasks | 4 files |
| Phase 42 P03 | 6m | 3 tasks | 3 files |
| Phase 42 P04 | 12m | 4 tasks | 7 files |
| Phase 42 P05 | 10m | 3 tasks | 9 files |
| Phase 42 P06 | 1 session | 2 tasks | 2 files |
| Phase 42 P07 | ~14m | 4 tasks | 4 files |
| Phase 42 P08 | - | 3 tasks | 4 files |
| Phase 37 P06 | 22 min | 4 tasks | 22 files |
| Phase 37 P07 | 12min | 3 tasks | 10 files |
| Phase 37 P08 | 9 min | 3 tasks | 10 files |
| Phase 57 P01 | 20min | 2 tasks | 4 files |
| Phase 57 P02 | 8min | 2 tasks | 2 files |
| Phase 57 P03 | 15m | 2 tasks | 5 files |
| Phase 61 P01 | 30min | 3 tasks | 5 files |
| Phase 61 P02 | 10min | 3 tasks | 4 files |
| Phase 61 P03 | 20min | 3 tasks | 3 files |
| Phase 61 P04 | 51min | 3 tasks | 3 files |
| Phase 61 P05 | 25min | 3 tasks | 6 files |
| Phase 61 P06 | 20min | 3 tasks | 6 files |
| Phase 61 P07 | 20min | 3 tasks | 3 files |
| Phase 61 P08 | 30min | 3 tasks | 5 files |
| Phase 61 P09 | 35min | 3 tasks | 5 files |
| Phase 61 P10 | 10min | 3 tasks | 5 files |
| Phase 61 P11 | 15min | 3 tasks | 3 files |
| Phase 61 P12 | 35min | 3 tasks | 4 files |
| Phase 61 P14 | 40min | 3 tasks | 4 files |
| Phase 61 P13 | 30min | 3 tasks | 4 files |

## Accumulated Context

### Roadmap Evolution

- Phase 14 added: Permisos Control — 역할별 권한 관리 UI
- Phase 15 added: Materia Prima Control — 원자재 관리 시스템 (의류업 특화)
- Phase 16 added: Control de Talleres — 중간 생산 과정 담당자 관리 및 컨트롤
- Phase 17 added: Portal de Talleres — 외주업자용 보조 프로그램 (aviso/알림, 진행현황, 수령 확인)
- Phase 18 added: AG Grid Migration — MUI DataGrid를 AG Grid Community로 교체 (컬럼 리사이즈/고정)
- Phase 20 added: Nueva Venta variation/codigo madre 디버깅 — 콘솔·서버·print-agent 로그 추가 및 suspender/restore 오류 추적
- Phase 21 added: Store Baseline Invariant System — store 단위 필수 설정(payment_methods, sellers 등)의 자동 생성·자가 치료·slug 기반 식별
- Phase 22 added: Suspender Restore Fidelity & Variant Stock Integrity — Reserved stock hold/release, restore UX 정합성, nullifySale variant 재고 복원, multi-branch 지원 완성
- Phase 25 added: Clientes globales compartidos entre tiendas (historial aislado) + Importación masiva CSV/Excel en ClienteView — 같은 그룹/소유자 매장 간 고객 기본정보 공유(이름/DNI/email/전화/주소), 구입이력은 storeId 격리. ClienteView에 CSV/Excel 업로드 + 컬럼 매핑 + DNI/email 중복 검증 + preview 커밋 + 실패행 리포트
- Phase 26 added: Gastos N차 카테고리 트리 — 무한 깊이(최대 5단계) 카테고리 계층 구조. 자기참조 트리(adjacency list + materialized path)로 사용자가 N차 sub category 자유 생성/이동/삭제. Reports 는 recursive CTE 롤업, 사용자가 depth 선택 가능
- Phase 29 added: POS Mercadopago — QR Dinámico (매장 내 QR 스캔 결제, store 단위 OAuth 계정, webhook + Socket.io 자동 Generar Venta, 3분 timeout/수동 취소, 환불은 phase 마지막 plan 에 포함)
- Phase 30 added: POS Mercadopago — Point 단말기 (물리 NFC/카드 단말기 결제, MP Point Smart SDK 연동. Phase 29 의 OAuth/webhook 인프라 재사용)
- Phase 31 added: Online Mercadopago — Phase 27 통합 (Checkout Pro/Bricks 로 온라인 채널 결제. Phase 27 ventas online 의 결제 레이어로 통합. Phase 29 OAuth 토큰/webhook 재사용)
- Phase 32 added: stocks-historial-drawer — Stocks 보고서 row 클릭 → 우측 380px drawer 슬라이드로 productBranch 의 movido/ingreso/fallado/corregido 전체 ledger 를 chronologically 표시 (Phase 12 cockpit drawer 패턴 재현). 2026-05-08 완료.
- **Phase 33 added (retroactive, 2026-05-17)**: Permissions v2 — RBAC + Branch Scope + Approval Threshold + Audit. 8 표준 role + user_branches 다지점 매핑 + approval_thresholds/approval_requests + user_permission_cache (5분 TTL). 운영 사용자 0명 zero-cost window 활용해 점진 마이그레이션 없이 한 번에 교체. 2026-05-14~15 .gsd/spec-permissions-v2.md 기반 49 파일 구현 (backend 4 마이그레이션 + 22 model/service/guard/controller + frontend 13 + docs 9). **현재 verifying**: api-ventago 30 파일 uncommitted + 운영 PG10 runbook 미실행.
- **Phase 34 added (retroactive, 2026-05-17)**: Customer WhatsApp + CRM Routing (Phase 29 Wave C) — clients/global_clients 에 whatsapp 컬럼 추가, Click-to-Chat 이 client.phone 대신 client.whatsapp 으로 라우팅 (strict mode, 422 fallback). "Igual que teléfono" 미러 체크박스 + ClienteVistaView/GlobalClientesView 컬럼+폼+WhatsAppSendDialog 게이팅. 2026-05-13~14 12-task TDD 구현 완료 (api 9 commits + app 3 commits, 모두 push). **현재 verifying**: 정식 UAT 미수행.
- **Phase 36 added (2026-05-23)**: 권한매핑보강+UAT감업 — Phase 35 manual UAT 에서 발견된 운영 적용 차단 사항 해결. (1) `stock.movement` 의 `role_function_actions` 매핑 누락 (Plan 02 마이그레이션 SQL 한계) — 모든 store 의 role × action 일괄 부여 SQL + admin UI 권한 매트릭스 검증. (2) 운영 PG10 RUNBOOK (`35-RUNBOOK-PROD.md`) 작성 — 마이그레이션 순서 / backfill dry-run·실행 / 5건 hotfix 배포 / 롤백 절차. (3) Phase 35 deferred 항목 (U14 movBalance 알람 staging 재검증, U18 MOV+ tooltip) 후속 결정. **현재 pending**: /gsd-spec-phase 36 (완료, 2026-05-23 commit 884c707) → /gsd-discuss-phase 36 / /gsd-plan-phase 36.
- **Phase 36.1 added (2026-05-23)**: Sale branch 필터 + dailyNumber 비-0 회귀 hotfix — (1) REG-1: sales.service.ts:364-369 의 branch 필터가 origin/target_branch_id 만 매칭하여 admin user(branch_id=NULL) 의 sale 행이 ventaVista branch chip 필터에서 누락. fix: sale 의 terminal → box → branch 경유 OR 절 추가. (2) REG-2: movido/fallado 가 INSERT 시점에 daily_number 비-0 부여 (U12b 1차 검증 0 → 후속 2/3/5/6/8). 근본 원인 미파악, 방어적 fix 로 stocks.service.ts 의 Sale.create() 에 `dailyNumber: 0` 명시 + 기존 DB 데이터 UPDATE 복원. **현재 in-progress**: 코드 fix 완료, 사용자 재검증 대기.
- **Phase 33.1 inserted (2026-05-24, URGENT)**: Permissions v2 D1/D2 Hotfix — 2026-05-24 자동 권한 점검(Scenario A/B/F)에서 발견한 P0 결함 2건. (D1) `user-structure.service.ts::ensureRoleFunctions` + `user-registration.service.ts::ensureRoleFunctions` 가 `/me` 호출 시점에 role 의 모든 function 에 대해 `RoleFunction.create(...)` 자동 실행 → bulk-actions 직후 1 row 였던 role_functions 가 /me 직후 11 row 로 복구. 사용자의 명시적 권한 토글과 DB 상태가 분리. (D2) `role-function.service.ts::bulkUpdateRoleFunctionActions` 끝에 `cacheService.invalidateUser` 호출 누락 → `user_permission_cache` 0 rows 로 Phase 33 spec "5분 TTL 캐시" 미작동. **현재 pending**: /gsd-plan-phase 33.1. 근거: `.planning/phases/33-permissions-v2/audit/2026-05-24-automated-verification.md`.
- **Phase 39 added (2026-06-13)**: Modo Restaurante — 식당 업종용 테이블 단위 POS 모드. configuración 식당모드 토글 → nueva-venta 가 테이블 배치도(salón) 뷰로 전환. 테이블(원형/긴원/정사각/직사각, 사용자 위치 지정) 클릭 → 웨이터 선택 → categoría·음식·수량 → 주방 전달(comanda) → 주문→음식나옴/음식나옴→소비완료 타이밍 테이블별 기록 → resumen de pago 감열 출력 → 현금/카드/MercadoPago 수금. 외상 없음, 메뉴 단순. **설계 방향(brainstorm 2026-06-13): 재구축 X, 기존 시스템 확장.** sales/sale_items/sale_payment_methods/sellers/print-agent/socket.io/mercadopago/멀티테넌트/CASL/배포 그대로 재사용. 신규 = restaurant_tables + sales 식당 컬럼(table_id+타이밍, nullable) + store_configs 플래그 + 전용 SalonView 프론트. MVP 우선(Slice 1 = 토글+배치도+주문/comanda+resumen 결제+기본 타이밍; KDS 화면·상세 타이밍 리포트는 후속 Phase 후보). **현재 not-planned**: /gsd-spec-phase 39 (미해결: 주방전달 방식 comandera vs KDS, 타이밍 트리거, 메뉴=products 재사용 여부, 배치도 충실도, open-ticket 상태모델) → /gsd-discuss-phase 39 → /gsd-plan-phase 39.
- **Phase 38 added (2026-06-11)**: CodigoMadre QR 감열 출력 — CodigoVista CodigoMadre View parent 행에 QR 출력 버튼 + price-type 선택 Popover → `POST /print/qr` → print-agent(감열) 가 QR(딥링크 URL: storeId+parentProductId) + 코드 + 제품명 + 가격 라벨 출력 (HTML→PNG→printImage, qrcode). 범위 = 데스크탑 QR 출력(Half A) 만. 모바일 스캔→`/m/stock`→크로스 지점 변형 재고 뷰(Half B)는 Phase 37 mobile 편입. 설계: docs/superpowers/specs/2026-06-11-codigomadre-qr-thermal-print-design.md. **현재 not-planned**: /gsd-spec-phase 38 또는 /gsd-plan-phase 38.
- **Phase 40 added (2026-06-16)**: Restaurante Delivery — 식당모드 매장 인터넷 배달 주문 접수·배차·수금 통제. 직원이 WhatsApp·전화·배달앱(PedidosYa/Rappi) 주문을 내부 콘솔로 접수 → 주방(comanda) → 라이더 배차 → 배달 → 수금 → 정산 마감. 핵심: *배달 완료 ≠ 주문 종료*, 현금 contra entrega 는 카하 정산까지 미수금 추적. **설계(brainstorm 2026-06-16): C안 — 신규 delivery 레이어 + 기존 Sale 백본 재사용.** 소매 online-orders 는 도메인 달라 재사용 X. 신규 엔티티 3개(Repartidor, RestaurantDelivery[Sale 1:1], RiderSettlement), 금전·재고·comanda·MP QR·caja·clients 재사용. 화면 4개(설정 Repartidores 카드, 주문 접수 모달, 배차 보드 칸반, 라이더 정산). 수금: MP QR=webhook 자동, 현금=라이더 교대 정산, 배달앱=L1 정산 CSV 대조. 범위밖: 고객 추적링크/배달앱 L2 API/라이더 모바일앱/GPS/외상. 설계: docs/superpowers/specs/2026-06-16-restaurant-delivery-design.md. **현재 not-planned**: /gsd-spec-phase 40 → /gsd-plan-phase 40.
- **Phase 41 added (2026-06-18)**: Soporte Remoto Embebido — 내장 원격 지원(보기 전용 MVP). 고객(매장 운영자)이 Ventago 웹에서 "지원 요청" → 서버가 세션 UUID 발급 → 고객이 UUID 를 지원팀 전달 → 지원팀이 인증 뷰어에서 그 UUID 로 고객 웹 화면(DOM)을 실시간·보기전용 재생. **rrweb DOM 미러링**(영상 코덱 없음, 대역폭 작고 저지연), 지원팀→고객 제어 채널 없음(의도된 보안 제약). **repo 스택 정식화(사용자 초안 조정)**: standalone `ws` 서버/별도 `pg` Pool → **기존 Socket.io 게이트웨이(`/support` 네임스페이스) + Sequelize 싱글턴 pool 재사용**(pool 낭비 0, `pool.connect()` 미사용). 신규 = support_sessions 테이블 + `/support` gateway + 고객 rrweb record 통합 + 지원팀 replay 뷰어(`pages/soporte/visor.tsx`). 보안(R-1..R-6): JWT+permission 게이트 뒤 뷰어 / 15분 만료 / 고객 진행배너+종료버튼 / maskAllInputs+결제·키화면 block / 동시뷰어 1 / store-scope. 범위밖: Flutter POS 화면, getDisplayMedia 픽셀영상, 역방향 입력. SPEC: .planning/phases/41-remote-support-viewonly/41-SPEC.md (Open Q: 뷰어 permission_slug 매핑 / rrweb 이벤트 DB 영속화 여부 / 운영 `/support` CORS). **현재 not-planned, 사용자 보안결정 승인 대기**: 승인 → /gsd-discuss-phase 41 또는 /gsd-plan-phase 41. **2026-06-19 ROADMAP `### Phase 41` 엔트리 소급 백필 완료** (그동안 STATE 진화로그에만 있던 갭 해소). 코드는 2026-06-19 main 통합(기능 플래그 OFF).
- **Phase 42 added (2026-06-19)**: Retail Delivery — Despacho / Cuentas por cobrar / Historial (의류 배송 통제). 식당 delivery 통제 UX(Phase 40)를 의류(비식당) 모드로 이식. **설계 방향(brainstorming 2026-06-19): A안 — 기존 online-orders(OnlineOrder) 백본 재사용 + 식당식 통제 UX 입히기.** 식당이 신규 RestaurantDelivery 를 만든 것과 달리, 의류 배송은 online-orders 가 만들어진 도메인(채널·운송장·택배사·결제상태)이라 데이터 재사용. 부족한 "직관적 통제 경험"만 신규. 신규 = Transporte 모델(CRUD, Correo Argentino/OCA/Andreani/Propia) + OnlineOrder 보강(transporteId·preparedAt/dispatchedAt/deliveredAt) + 외상은 기존 CreditLedger(sale_credit/payment_in/favor) 재사용. 화면 = Ventas Online 페이지 3탭 격상(Despacho 칸반 컬럼별누적+마스터디테일 보드75%/타임라인25% · Cuentas por cobrar 외상통제 · Historial) + 설정 Transporte 카드. 정산축 재해석: 라이더 현금 → 고객 외상(cuenta corriente). 완납후발송 게이트(잔액>0 외상발송 경고), 언제든 부분/split cobro(현금·이체·cheque·tarjeta·QR), 타임라인 Ticket/Recibo/Nota, 취소시 환불/favor. store_config `use_envios`(기본 OFF) 게이트. 범위밖: 반품(nueva-venta). 설계: docs/superpowers/specs/2026-06-19-retail-delivery-despacho-design.md. **2026-06-19 PLANNED — Ready to execute**: /gsd-plan-phase 42 완료 → CONTEXT(설계스펙 기반)+RESEARCH(HIGH conf, 5 pitfalls, Open Q 전부 RESOLVED)+PATTERNS(24파일/22 analog) 생성, **8 plans in 8 waves**(42-01 Transporte CRUD+use_envios 마이그레이션 · 42-02 OnlineOrder 보강+ship 완납게이트(shipSaldo)+cobro(FIFO+caja)+cancel favor · 42-03 [BLOCKING] 마이그레이션 로컬적용+deliver 결제귀속 재정렬(Pitfall1)+RD-12 회귀 · 42-04 /envios 게이트웨이+cuentas-por-cobrar/nota/auth-scoped GET:id(I-1 해소) · 42-05 프론트 foundation · 42-06 3탭+Despacho 칸반+실시간 · 42-07 타임라인+CobroModal+취소favor+NuevoEnvio · 42-08 Cuentas/Historial+검증). plan-checker VERIFICATION PASSED(revision 1회: 결제귀속 시점 정렬+백엔드 라우트 소유권+useEnviosHistory sibling). 다음: /gsd-execute-phase 42.
- Phase 69 added: 테넌트 격리 잔여 구멍 봉쇄 — 실시간 소켓 무인증 room 가입 / correct-today 타 매장 원장 쓰기 / 벤더 PIN 1개로 타 매장 권한 / 파생 스코프 observe 기본 / TenantContext fail-open. 외부 보안 리뷰 2026-07-31, 결함 5건 코드 대조 검증 완료 (URGENT)
- **Phase 77·78 ROADMAP 스텁 백필 (2026-08-17)**: 두 phase 는 계획서가 `.gsd/` 에만 있고 ROADMAP 에 항목이 없어 **번호가 비어 보였다** — `gsd-tools phase add` 가 실제로 77 을 새 phase 에 배정했다(즉시 79 로 정정). 재발 방지로 ROADMAP 에 포인터 스텁을 남겼다. 77 = Solicitudes Internas(보류, Wave 0 D1/D4/D6 미확정) · 78 = Module Integrity Suite(Wave 2 미착수).
- **Phase 79 added (2026-08-17)**: 표 행 높이 30px 통일 — 사용자 요청. 실측: `FullTable`(AG Grid 래퍼) 기본값 `rowHeight=42` 가 **76개 파일**을 한 번에 좌우하는 지렛대이고, 개별 지정 **8곳**(28·30·30·30·34·36·48·`ROW_HEIGHT`)과 `AgGridReact` 직접 사용 **3곳**(FileTable·AccessLogsView·POS ProductListTable), MUI `<Table>` **96개 파일**(theme override 로 일괄 처리해야 함)이 남는다. MUI `<DataGrid>` 직접 사용은 0(전부 이관 완료). 선행 샘플 1건 적용 완료(`CajaFuerteOperationsTable`, app `199130d`). **2026-08-17 PLANNED — 3 plans / 2 waves**: `79-FINDINGS.md`(실측) + `79-01`(AG Grid 계열: 단일 출처 상수 `table-density.ts` + FullTable 기본값 → 76곳 자동 반영, 개별 지정 34/48/28 제거, 직접 사용 3곳) + `79-02`(MUI `<Table>` 테마 override — `spacing(3.5)`=14px → `spacing(1.25)`=5px, 96곳 일괄) + `79-03`(시각 회귀 확인 · 예외 근거 · CLAUDE.md 밀도 규약, `autonomous: false`). ★ 사용자 결정(2026-08-17): **POS 도 예외 없이 30px** — 그런데 실측해 보니 **POS 는 이미 30px**(`ROW_HEIGHT = 30`)이라 실질 변화가 없다. **2026-08-17 W1 실행·배포 완료** (app `c693102`, 빌드 #635): `table-density.ts` 신설 · FullTable 기본값 42→30(76곳 자동) · MUI 테마 `spacing(3.5)`→`(1.25)`(96곳 일괄) · 개별 지정 6곳 제거 · AG Grid 직접 3곳 + react-arborist 트리(36→30) 통일 · `rowHeight={숫자}` 리터럴 **0건**. ★ 실행 중 드러난 것: 30px 행에서 **기본 `IconButton`(40px)이 넘친다** — 50여 화면을 개별 수정하는 대신 FullTable 한 곳에서 압축(`.ag-cell .MuiIconButton-root padding 2px`). `PriceTypesList` 48px 의 원인이 이것이었다. CLAUDE.md 밀도 규약 반영 완료. **남은 것: W2(`79-03`) 시각 확인 — 사람이 화면으로 판정.**

- **Phase 80 added (2026-08-17)**: 생산 중(WIP) 수량·완성 예상시점을 Stocks 리포트에. 사용자 요청. ★ 사용자 결정이 내 제안과 다르다 — 생산 중 물건에는 **지점이 없는데**(지점은 수령 시 `talleres_recepciones.target_branch_id` 로 처음 정해진다) 사용자가 **지점 수 균등 분배**를 선택했다. 받아들이되 추정치임을 필드명·화면에 못박는다(`estimatedBranchWipQty`·값마다 `≈`). CODEX 검토에서 **Blocker 6건**: ①`열린 envío pending 합`은 공정 사이 대기 수량을 놓쳐 WIP 총량이 아니다 ②로트당 "현재 공정" 하나는 분할 발송·rework 에서 성립 안 함 → cohort 단위 ③`max(due_date)`는 완성예정일이 아니다(최종 공정만) ④엔드포인트 단일 `@FunctionGuard` 로는 필드가 응답에 그대로 실린다 → **필드 단위 차단** ⑤균등 분배의 대상 지점·잔여 규칙 미고정 시 합계 불일치 ⑥madre/leaf 모집단(`groupLeafIds`)을 안 맞추면 누락·중복. 전문 `.gsd/review-codex-phase80-talleres-wip.md`. **4 plans / 3 waves — 실행 대기**: `/gsd-execute-phase 80`.

- **Phase 81 added (2026-08-17)**: 재고 매트릭스 인라인 일괄 수정(Editar → Confirmar). 사용자 요청 — 셀 하나씩 선택·수정·확인을 반복하는 불편 해소. ★ 핵심 위험은 "여러 개를 쓴다" 가 아니라 **화면을 연 뒤의 판매·입고를 절대값 조정이 조용히 덮는 것**(화면 10 → 8 입력 → 그 사이 판매 −2 → 서버가 +1 을 기록해 판매를 되돌림) → 항목마다 `expectedStock` 을 싣고 락 후 대조, 하나라도 어긋나면 **원장에 0행 + 409**. CODEX 검토 Blocker 4건(기준값 대조 필수 · 부분 성공 금지 · `product_id ASC, pb_id ASC` 고정 락 순서 + 중복 거부 · 배치 상한 50과 집합 검증) · Should 8건(집합 쿼리 · `batchId` 감사 · Idempotency · 셀별 편집가능 사유 응답 · 미저장 입력 폐기 확인 · 큰 보정은 차단이 아니라 확인 · 저장 후 remount 금지 · **Panel D 제거하지 말 것**). ★ 사용자는 Panel D 가 필요 없어질 것이라 했으나 이번엔 **숨기기까지만** — 단일 셀 note·이론값·결과가 거기에만 있고 지우는 것은 되돌리기 어렵다. 전문 `.gsd/review-codex-matrix-inline-bulk-edit.md`. **4 plans / 3 waves — 실행 대기**: `/gsd-execute-phase 81`.

- **Phase 82 added (2026-08-17)**: Enviado — 온라인 판매 배송 관제 보고서 + Reservado 숨김. 사용자 요청(Despacho 보드는 잘 돼 있으니 보고서는 다른 질문에 답해야 한다). 외부 조사(Shopify `pending fulfillment` · ShipStation aging · MercadoLibre `Despachos demorados` · Shipium/DCL/Shipink OTD 95%)에서 가져온 것: 경과 시간 정렬 · "떠났는데 안 닿은 것" 별도 탭 · **운송사별 비교**(전체 평균이 부진을 감춘다) · KPI 옆 기준치 표기. ★ 조사 권장 KPI 중 **반품률은 뺐다** — 데이터가 없어 항상 0 인 칸이 된다. 대신 **En tránsito(건수+묶인 금액)**. ★ 사용자 결정: "정시" 는 **내부 기준 5일**(약속일 컬럼 안 만듦) → 화면이 기준을 표기해야 한다. ★ 함정: `online_orders` 에 `shipped_at` 과 `dispatched_at` 이 **둘 다** 있다(운영 9건 모두 둘 다 채워져 구분 안 됨) → `shipped_at` 정본 고정. Mockup: https://claude.ai/code/artifact/eec55483-c567-4fb3-889d-75a26059a103 . **2 plans / 2 waves — 실행 대기**: `/gsd-execute-phase 82`.

- **Phase 83 added (2026-08-17)**: 고객 배달 확인 링크. ★ 계기는 사용자 질문 — *"운송사 API 연동이 안 될 텐데 배달 완료를 어떻게 확인하지?"* 코드 확인 결과 **연동이 없고** `delivered_at` 은 직원이 누른 시각이다 → Phase 82 의 OTD 는 운송사 성과가 아니라 **클릭 습관**을 재고 있었다. Phase 82 를 교정(주 KPI = `Sin confirmar`, OTD 는 "확인 시각 기준" 각주, 확인율 KPI, 직원 확인 시 **도착일 입력**)하고, 고객 확인은 이 phase 로 분리. ★ 사용자 원안의 *"직원 확인 → 고객이 OK"* 마지막 단계는 뺐다 — 고객이 첫 번째를 안 눌렀으면 두 번째도 안 눌러 **주문이 계속 열린 채 남는다**. 대신 직원 확인은 즉시 종결 + 고객에게 통지만(침묵=동의), "안 받았다" 는 `En disputa`. ★ 자동 확인 금지 — 레거시 폴백(`mirrorSaleId == null`)이 매출·외상을 만들어 **아무도 안 누른 회계 기록**이 생긴다. 운송사/애그리게이터 연동(ShipNow·Zipnova)은 월 수백 건 규모에서 재검토. **2 plans / 2 waves — 실행 대기**.

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Phase 1]: 로그인 화면에 primary→secondary 그라데이션 적용
- [Phase 01-ui-ux]: PUT /users/ui-mode 엔드포인트를 @Get(':id') 라우트보다 위에 배치하여 NestJS 라우트 우선순위 문제 방지
- [Phase 01-ui-ux]: uiMode 유효성 검증을 컨트롤러에서 수행 (BadRequestException)
- [Phase 01-ui-ux]: UiModeProvider placed inside AuthProvider because it calls useAuth() hook
- [Phase 06-reportajes]: QuerysDto startDate/endDate를 optional로 변경 (잔액 보고서 호환)
- [Phase 06-reportajes]: MUI Chip은 'tonal' variant 미지원 — 'filled' 사용 + color로 시각 구분
- [Phase 06-reportajes]: Alertas: SReal<=0 Sin Stock / SReal<=5 Bajo Stock 임계값
- [Phase 06-reportajes]: Cheque Estado: PaymentMethod.slug=cheque 1차 필터, 없으면 전체 fallback
- [Phase 08-reportajes-ux]: Variant A helper props optional — shell 은 자체 Topbar 로 대체
- [Phase 11-thermal-printing]: electron-store defaults 사용 (schema 검증 보류) — 기존 config.json과 호환
- [Phase 16-control-de-talleres]: Wave 6: forwardRef() for QcItemService-EnvioService circular dep; crypto.randomUUID() over uuid package; uiId void pattern for ESLint; route ordering admin/all before :id
- [Phase 25]: PG10 partial UNIQUE 호환을 위해 ADD CONSTRAINT 대신 CREATE UNIQUE INDEX ... WHERE 사용 (PG10/PG15 양쪽 호환)
- [Phase 25]: Sequelize 모델에 unique:true 컬럼 선언 제거 — 부분 UNIQUE는 인덱스 레벨에서만 관리 (D1-01 정합성)
- [Phase 25]: owner_groups_seq START 2 — 기존 4개 매장이 group=1 이므로 신규는 2부터 (D3-02/D3-03)
- [Phase 25]: global_clients 누적 UNIQUE 제약을 DO 블록 LOOP 로 일괄 제거 (Sequelize sync 누적 정리)
- [Phase 25 P02]: sales dual-FK 전략 — store_client_id 신규/clientId 레거시 (D2-01)
- [Phase 25 P03]: 4 매장 동일 document='00000000' → global_clients 1개로 통합, store_clients 4개 매핑 (owner_group UNIQUE 격리 정상 동작 검증)
- [Phase 25 P03]: PLAN 의 birthdate/city/notes 컬럼은 실제 GlobalClient 모델에 없음 → name_fantasy/transport/res_iva/location 으로 매핑, note 는 store_clients 로 이관
- [Phase 25 P04]: audit 테이블 3개 분리 (audit_logs ENUM 확장 회피, PG10 호환)
- [Phase 25 P04]: client_merges.field_picks JSONB 사용 (PG10 도 JSONB 지원, 인덱스 불필요)
- [Phase 25 P05]: OwnerScopeService in-memory 캐시 5분 TTL — DB pool 절약 (CLAUDE.md 성능 규약)
- [Phase 25 P05]: store.service.ts 에서 owner_groups_seq nextval try/catch fallback=1 — sequence 부재 시에도 안전
- [Phase 25 P05]: CommonModule import alias `Phase25CommonModule` — 기존 common/cache 등과 충돌 회피
- [Phase 25 P06]: 명시적 slug 'manage-clientes-import' — 스페인어 액센트가 generateSlug 에서 깨지므로 func.slug 우선 패턴
- [Phase 25 P06]: GlobalClientsService.findOrCreate signature 변경 (ownerGroupId 추가) — 모든 호출자가 그룹 명시 필수
- [Phase 25 P06]: 별도 모듈 app/global-clients/ 는 Wave 2 범위 외 — 자체 massive-upload 가 있으나 캐노니컬 아님 (Plan 25-10+ 에서 통합 검토)
- [Phase 25 P09]: CUIT validators 명시적 export (isValidCuit + normalizeCuit) — 알고리즘 + 정규화 분리해서 import-side 활용성 높임
- [Phase 25 P09]: AFIP Pitfall 5 (calc==10 거부) 케이스 spec 으로 명시 검증 — 입력 '20000000012'
- [Phase 25 P07]: ClientsService.promote 가 conflict 시 DB 변경 0건 — status='merge_required' + conflictFields 반환 (사용자 결정 후 merge 별도 호출)
- [Phase 25 P07]: clients.note 를 store_clients.note 로 이관 (매장 비공개 정보 보존, GlobalClient 에 note 컬럼 없음)
- [Phase 25 P08]: MERGE_ALLOWED_FIELDS 화이트리스트는 GlobalClient 실제 컬럼만 — birthdate/city/notes 제외 (Plan 25-03 매핑 일관성)
- [Phase 25 P08]: 옵티미스틱 락 winnerUpdatedAt 비교 — Date 면 toISOString(), 아니면 String() 변환 (Sequelize timestamp 호환)
- [Phase 25 P08]: STALE_MERGE 응답 시 프론트가 GET /shared/global-clients/:id 재조회로 새 updatedAt 받아 재시도
- [Phase 25 P10]: 새 endpoint /clients/import 신설 (구 /global-clients/massive-upload 와 분리, 캐노니컬)
- [Phase 25 P10]: ImportRowDto + ImportBatchDto 분리 — class-validator + ValidateNested + Type
- [Phase 25 P11]: chunkSize=500 + MAX_ROWS=50000 + in-memory existingMap 캐시 (같은 batch 동일 doc 처리)
- [Phase 25 P11]: Default existing-hit policy='skip' — 가장 보수적. 사용자가 update/link 명시 필요
- [Phase 25 P11]: bulkCreate Local 실패 시 행마다 개별 INSERT fallback (어느 행이 실패했는지 식별 가능)
- [Phase 25 P12]: errorCode enum (EMPTY_FULLNAME / GLOBAL_UPSERT_FAILED / LOCAL_INSERT_FAILED) — 행 진단 일관성
- [Phase 25 P12]: per-row 에러는 트랜잭션 rollback 트리거 안 함 — 일부 실패해도 batch 는 성공 (격리)
- [Phase 25 P13]: Wave 5 frontend (Plan 14) 가 /global-clients/massive-upload → /clients/import 로 교체 예정
- [Phase 25 P14]: CargaMasivaClientesView 핵심 wiring 만 수행 — PromoteMergeDialog (cliente-vista 통합) 는 별도 phase
- [Phase 25 P14]: chunkSize=5000 — backend MAX_ROWS=50000 의 1/10, 큰 파일도 client-side 자동 분할
- [Phase 25 P14]: toImportRow 헬퍼 — 빈 문자열 → undefined 변환으로 백엔드 IsOptional + IsEmail 검증 호환
- [Phase 25 P15-deferred]: sales/reports scope audit (Wave 7) 는 큰 별도 phase 로 연기 — 4개 매장 모두 group=1 이라 운영 영향 없음
- [Phase 26]: PG10/PG15 호환: EXECUTE PROCEDURE (not EXECUTE FUNCTION), SERIAL (not GENERATED AS IDENTITY), ltree 미사용
- [Phase 26]: _phase26_cat_map 정식 테이블 (TEMP 아님) — 2주 롤백 윈도우 동안 보존, Wave 5 cleanup 시 DROP
- [Phase 26]: expenses_subcategory_id Wave 5 까지 유지 (두 컬럼 공존, 롤백 가능 윈도우 확보)
- [Phase 26]: subcategory 없던 expenses 행은 category_id = NULL (Sin categoría — 기존 동작 유지)
- [Phase 26]: Audit action enum: 'move'/'restore' mapped to 'edit' — AuditOptions.action union does not include those values
- [Phase 26]: ExpenseCategoryController: user.storeId! non-null assertion — @Auth() guarantees storeId for authenticated users
- [Phase 26]: Unit tests use jest mocks (not real DB) — DB trigger behavior covered by Wave 1 manual tests + DB-level guards
- [Phase 26]: apiConnector is a default export (not named) — all imports must use default import pattern
- [Phase 26]: Wave 3 nav for categorias-gastos: hardcoded in both superadmin block and admin append (navigation is DB-driven, admin extras are hardcoded)
- [Phase 26 P04]: Spec under src/app/reports/ (jest rootDir=src) — not under api-ventago/test/ which is outside testRegex
- [Phase 26 P04]: ReportsGastoService constructor adds optional sequelize? param — preserves existing instantiation, NestJS DI auto-wires at runtime, jest mock injects directly
- [Phase 26 P04]: depth='all' = depthLimit=5 (leaf preserved). RECURSIVE CTE uses anc_parent_id chain + DISTINCT ON ORDER BY anc_depth DESC to pick deepest ancestor ≤ depthLimit
- [Phase 26 P04]: Cockpit top-N flat 8-row breakdown preserved unchanged (RESEARCH §6 Q6) — new rollup card is additive
- [Phase 26 P04]: ExpenseModal always sends expensesSubcategoryId=null; categoryId is the source of truth (Wave 5 drop prep)
- [Phase 26 P04]: DataConfig column renderer falls back legacy subcategory string when expenseCategory.path missing — preserves continuity for partial-state rows
- [Phase 29]: [Phase 29 P01]: Plan 01 (Wave 0) — qrcode.react@4.2.0 + 8 MP_* env vars + 3 fixtures + axios mock helper + 2 ops docs. Checkpoint pending (operator must provision real MP Apps + secrets).
- [Phase 29]: [Phase 29 P02]: 7 mp_* tables (PG10/15 compat). Two partial UNIQUE indexes on mp_accounts (PG10 alternative to COALESCE-in-UNIQUE). VARCHAR+CHECK over PG ENUM. Cross-table FKs split-add (mp_movements.refund_id/transfer_id added in 29-04/29-05). Verified clean apply + idempotent re-run + clean rollback on host PG18.
- [Phase 29-pos-mercadopago-qr-din-mico]: Plan 02b: DataType.DECIMAL(14,2) used for monetary fields (sequelize doesn't export NUMERIC; PG-side equivalent)
- [Phase 29-pos-mercadopago-qr-din-mico]: Plan 02b: AppModule lives at src/app.module.ts (NestJS standard), not src/app/app.module.ts as plan stated
- [Phase 29-pos-mercadopago-qr-din-mico]: Plan 02b: MercadopagoModule re-exports SequelizeModule so downstream plans can @InjectModel any of the 7 mp_* models without re-importing
- [Phase 29-pos-mercadopago-qr-din-mico]: Plan 03: @Public() decorator created (api-ventago/src/app/auth/decorators/public.decorator.ts) — no global JWT guard exists yet, but documents intent + future-proof
- [Phase 29-pos-mercadopago-qr-din-mico]: Plan 03: MpOAuthService spec uses positional constructor args (bypassing NestJS DI) — @InjectModel/@InjectConnection are metadata-only
- [Phase 29-pos-mercadopago-qr-din-mico]: Plan 03: MpStorePosService swallows 4xx errors from MP Store/POS POST — already-registered = idempotent success (no separate GET-check needed)
- [Phase 29-pos-mercadopago-qr-din-mico]: Plan 03: AuditOptions.getDescription is (result, body, user) 3-arg — plan example used (params) 1-arg form, fixed to match interface
- [Phase 29-pos-mercadopago-qr-din-mico]: Plan 04: createIntent uses status='failed' UPDATE on MP API failure (rollback path) — preserves audit; Plan 08 cron is backup cleanup, not primary mechanism
- [Phase 29-pos-mercadopago-qr-din-mico]: Plan 04: external_reference = String(intent.id), NOT pendingVentaId (RESEARCH §Architecture) — webhook resolves intent first then walks intent.pending_venta_id
- [Phase 29-pos-mercadopago-qr-din-mico]: Plan 04: notification_url contains ?accountId=N query (RESEARCH §A9) — webhook auth resolves account directly via query if MP preserves URL
- [Phase 29-pos-mercadopago-qr-din-mico]: Plan 04: Spec import order matters — mock-mp-api.ts must be imported BEFORE any axios consumer or jest.mock('axios') is bypassed (real network calls leak through)
- [Phase 29-pos-mercadopago-qr-din-mico]: Plan 04: JSON fixture loaded via require() (CommonJS path) — tsconfig has no resolveJsonModule and adding it project-wide is out of scope
- [Phase 29]: MercadopagoModule imports WebsocketModule (not @Global) — explicit dependency keeps the module graph readable
- [Phase 29]: Webhook controller always returns 200 + setImmediate background processing — MP retry storm avoided; internal failures flow to polling fallback (Plan 04 GET endpoint)
- [Phase 29]: Webhook handler RE-FETCHES MP /v1/payments/{id} as canonical truth (RESEARCH §Pitfall 1 — QR webhooks have NO x-signature; payload is wake-up signal only)
- [Phase 29]: Idempotency proven by SELECT FOR UPDATE intent inside TX + intent.paymentId guard + DB UNIQUE on payment_id (defense in depth — RESEARCH §Pitfall 5/9)
- [Phase 29]: [Phase 29 P06]: literal('branch_id ASC NULLS FIRST') for Sequelize order — typed Order array does not accept NULLS FIRST modifier; literal() bypasses parser
- [Phase 29]: [Phase 29 P06]: Defensive toResponse() helper despite attributes whitelist — defense in depth for T-29-02 token leak mitigation
- [Phase 29]: [Phase 29 P06]: Palette modification deferred (Rule 4 architectural) — existing materio template info/warning colors visually adequate; global change would cascade to 60+ screens, out of scope
- [Phase 29]: [Phase 29 P06]: MP frontend file location src/views/mercadopago/ (NOT src/views/configuracion/mercadopago/) — matches Phase 26 categorias-gastos pattern
- [Phase 29]: PaymentSummaryModal extended with MP QR side-panel + processedIntentRef double-trigger guard + auto-handleSubmit (Plan 07)
- [Phase 29]: Plan 08b: MP wallet rows rendered in adjacent MUI Table inside CashControlList CardFilter (above existing FullTable/DataGrid) — Variant A highlighted-row visual + role-gated buttons + chip don't map cleanly to DataGrid column-renderer model
- [Phase 29]: Plan 08b: Type re-exports from SWR hooks (McdpgWalletRow, McdpgMovementRow) — single-import ergonomics for downstream components (no need to import from both hook + types module)
- [Phase 29]: Plan 08b: useBranch returns plain any[] not paginated {data,total} — defensive shape handling Array.isArray(branches) || (branches as any).data ?? [] avoids future hook-shape regression
- [Phase 29]: Plan 09: refundForSale signature uses sale.id only (lookups mp_payment_intents via pendingVentaId) — SalePaymentMethod has no mpPaymentId column
- [Phase 29]: Plan 09: X-Idempotency-Key=refund-{saleId}-{attemptNo} — same key returns same MP refund record (T-29-06 mitigation), attemptNo increments per user-driven retry
- [Phase 29]: Plan 09: McdpgRefundFailureSection extracted as separate component — keeps SalesDetailView modification surgical (3-line addition + 1 import) and reusable
- [Phase 29]: Plan 09: nullifySale failure path NEVER throws (D-A4-03) — sale always nullified, MP failure surfaces via mpRefundResults/mpRefundFailed flags attached to reversalSale.dataValues
- [Phase 25]: [Phase 25 P15]: findAllScoped 분기 정책 — storeId 명시 시 ownerScope 미호출 (DB pool 절약), null 시 ownerGroup 매장 IN
- [Phase 25]: [Phase 25 P15]: resolveSaleClient — storeClient/globalClient eager 미적재 시 legacy clients 폴백 (호환성 우선)
- [Phase 25]: [Phase 25 P15]: 32 reports services 일괄 ownerGroup 변환 deferred — 운영 single-group 환경 즉시 leak 0, scope.helper.ts 만 추가
- [Phase 25]: [Phase 25 P15]: sales-create storeClientId 자동 추론 — clientId → document → store_clients (Plan 16 ClientsSync 매핑 활용)
- [Phase 25]: Plan 25-17: Backfill 스크립트 dev 검증 완료 (17 synced_new + 10 existing + 13 sales_remapped + 0 errors), idempotent 확인. 운영 적용은 사용자 승인 대기.
- [Phase 25]: Plan 25-17: standalone NestJS script — main.ts 진입점 아니므로 webcrypto polyfill + require.main === module 가드 + getModelToken(Class) 패턴 추가
- [Phase 32]: Phase 32-01: Stocks historial drawer backend — getHistorial service method + GET /reports/stocks-cockpit/historial endpoint with 7-way SQL classification, counterparty branch resolution from movido note pattern, audit_logs JOIN with 'Sistema' fallback. Plan SQL fix (talles/talle_id → sizes/size_id) per actual schema.
- [Phase 32-stocks-historial-drawer-stocks-row-380px-drawer-productbranc]: Drawer state owned by StocksCockpitBody (single instance + cross-panel toggle close); same-target re-click closes via prev-target kind+ids comparison
- [Phase 32-stocks-historial-drawer-stocks-row-380px-drawer-productbranc]: PanelC cell <td> converted to <Box component=td> sx :hover selector (idiomatic MUI hover-reveal) — fixed plan ambiguity around .MuiBox-root selector on native td
- [Phase 32-stocks-historial-drawer-stocks-row-380px-drawer-productbranc]: useStocksHistorial accumulates rows via prevOffsetRef gate (offset==0 replaces, offset>prev appends); loadMore no-op unless data.hasMore=true
- [Phase 39-modo-restaurante-pos-mesas]: [Phase 39 P01]: use_restaurant_mode DEFAULT false (기존 use_* default true 와 차별 — 소매 무영향). restaurant_category_ids JSONB nullable.
- [Phase 39-modo-restaurante-pos-mesas]: [Phase 39 P01]: 순환 FK(sales.tableId ↔ restaurant_tables.currentSaleId)는 constraints:false BelongsTo + 마이그레이션 분리(39-01 current_sale_id, 39-02 table_id)로 회피. 신규 sales 컬럼 전부 nullable → 소매 회귀 0.
- [Phase 39-modo-restaurante-pos-mesas]: [Phase 39 P01]: last_comanda_at 신규 컬럼으로 comanda 증분 경계 확정 (39-RESEARCH Open Q2 해소). pos_x/pos_y REAL 정규화 0~1 (D-08).
- [Phase 39]: [Phase 39 P02]: findScoped() private 헬퍼로 update/updatePosition/remove 스코프 조회 통일 (IDOR 방지 단일 지점). syncTableStatus 는 39-03 이 이미 로드한 RestaurantTable row + options.transaction 재사용.
- [Phase 39]: [Phase 39 P02]: findByBranch 단일 SELECT(sales JOIN 금지) — pool 절약. DTO posX/posY @Min(0)@Max(1) + shape/status @IsEnum + DB CHECK 이중 방어. module exports 에 SequelizeModule 추가(Sellers 선례).
- [Phase 39]: [Phase 39 P04]: update() 도 findOrCreateByStoreId 경유로 보강 — 토글/설정 저장 경로(update-flag 포함)는 store_config 행 부재 시 자동 생성, GET(findByStoreId)은 NotFound 유지. useRestaurantMode 화이트리스트 @Patch+@Put 두 곳 모두 추가.
- [Phase 39]: [Phase 39 P05]: payMerge 배분 = 각 sale 자기 totalAmount 1행 결제(비율 배분 아님) — integer 정확 일치 + D-03 매출 귀속 보존. grand-total ΣtotalAmount 단일 검증.
- [Phase 39]: [Phase 39 P05]: 식당 결제 box-operation = recordBoxOperation(cashRegister closingTime=null findOne → addOperation(data,t) 위치 transaction). 미오픈 시 소매와 동일 스킵. RestaurantTable+CashRegister sales.module forFeature 등록.
- [Phase 39]: 39-07: placeOrder totalAmount 동기화(백엔드)로 결제 검증 통과 보장 + GET :id 조회 라우트 추가 (39-05 갭 해소)
- [Phase 40]: 40-04: qr 배달 주문 접수 시 MpPaymentIntent(pendingVentaId=sale.id)를 TX 커밋 후 생성 — plan 06 webhook가 intent.pendingVentaId로 delivery 자동 종료(REQ-8). Entregado는 Sale PAID이나 efectivo는 box-op 없이 por_cobrar 잔류(D-01/D-05, 정산은 plan 06).
- [Phase 40]: 40-06: QR 배달 자동 종료 hook은 intent.pendingVentaId(=delivery.saleId, plan04)로 delivery 조회 — 기존 intent-centric webhook은 saleId로 Sale을 안 찾으므로 linkage는 intent→delivery. post-commit + try/catch로 webhook 200 불변식+wallet-credit TX 무변경(additive).
- [Phase 40]: 40-06: L1 payout CSV = MinIO 원본 보관(D-07) + 고정 헤더(external_ref,amount) 검증 + sales.total_amount 정확 매칭(tolerance 없음, 센트반올림 정수비교). conciliacion 상태만 liquidado flip(T-40-22), storeId 스코프(T-40-21), 타입/크기/헤더 선검증(T-40-20).
- [Phase 40]: 40-07: RepartidoresCard는 use_restaurant_mode 이중 게이트(카드 내부 return null + RestauranteConfigView enabled 블록 내 렌더)로 소매 매장 노출 차단(T-40-25). NuevoPedidoModal은 OrderModal 메뉴 picker 재사용 + takeaway는 주소/라이더를 payload에서 제외(숨김 아님). useDeliveryBoard는 폴링 없이 Socket.io push 병합 대상.
- [Phase 40]: 40-08: DeliveryBoard는 base host + /restaurant 네임스페이스 Socket.io(auth.token=accessToken)로 delivery_updated 카드를 mutateRef 기반 functional updater로 SWR 캐시에 병합(폴링 없음). Por cobrar 컬럼 RED는 현금 미정산 통제 가시화. RestauranteShell이 Salón(기본)/Delivery/Liquidación을 next/dynamic ssr:false로 code-split하여 nueva-venta 식당모드 분기에 마운트(소매 VcontrolHome 무변경). 코드 완료, 블로킹 human-verify UAT 보류.
- [Phase 42]: 42-03 (executing, done 2026-06-19, feat/phase42-wave1) **[BLOCKING wave]**: 마이그레이션 로컬 적용 + deliver 결제귀속 재정렬(Pitfall 1) + RD-12 회귀 게이트. (1) **마이그레이션 3개 로컬 PG18 적용**(42-01 transportes + 42-03 use_envios 멱등 no-op + 42-02 online_orders prepared_at/dispatched_at/transporte_id 실적용 count 0→3) → BLOCKING 스키마검증 SCHEMA_OK(운영 PG10 미적용). (2) **deliverOrder**: 무조건 `paymentStatus=PAID` 제거 → `shipSaldo<=0 ? PAID : 유지`(부족분 외상 Cuentas por cobrar 노출). mirror.id 생성 직후 `shipSaldo>0 && isNewMirror(order.mirrorSaleId==null)` 일 때만 sale_credit 1건 누적(amount=shipSaldo, saleId=mirror.id, 동일 SERIALIZABLE deliver tx t — 새 pool 없음, 멱등 가드로 재-deliver 중복 차단). UPDATE/DELETE ledger 금지. (3) **createMirror**: optional `receivedAmount` 3번째 인자 → sale_payment_methods.amount=실수령액(total−shipSaldo), 미지정 시 totalAmount(완납 회귀-0). 불변식 SaleSource.ONLINE/SaleActivityType.SALE/online_order_id UNIQUE/dailyNumber 보존. (4) spec: 완납/부족분/멱등 deliver 3건 추가, online-orders jest 13/13 PASS(credit/box 독립 spec 부재 → online-orders 스위트가 mock 통합 커버). 커밋 9dda6e4(api-ventago submodule). (out-of-scope: no-unsafe-* eslint pre-existing 24건 baseline, 신규 0건 — nest build SWC 게이트 무관).
- [Phase 42]: 42-02 (executing, done 2026-06-19, feat/phase42-wave1): OnlineOrder 보강 + ship 완납게이트 + cobro + cancel favor. **ship 은 metadata.shipSaldo 에 외상 의도만 기록** — sale_credit ledger 행은 deliver(42-03)에서 mirrorSaleId 기준 누적(RESOLVED Pitfall-1 seam, ship 에서 appendMovement 호출 X). shipOrder(userId): transporte.name 미러(D-05) + dispatchedAt + saldo>0 시 익명 차단(Pitfall 2) + assertCreditEligible(positional sig, 동일 tx). prepareOrder→preparedAt(Listo 파생, D-03, 신규 enum 없음). registerCobro: split payments → registerPayment(credit_payment FIFO, 자체 tx 중첩 X/Pitfall 3) + 줄별 caja addOperation + 열린-caja 미오픈 차단(Pitfall 4). cancelOrder(refundAction): devolver=caja 역 movement / favor=appendMovement favor_in, 기존 reverseSale+nullifyMirror 보존(RD-12). computeReceivedSoFar: metadata.received 우선 / paymentStatus=paid→total / else 0. transportes.findScoped private→public. OnlineOrdersModule→CreditModule/BoxOperationModule/TransportesModule import(싱글턴 재사용). transporteId plain INTEGER(boot-hang guard). 마이그레이션 42-02 미적용(42-03 이 순서대로). online-orders.service jest 10/10 PASS. 커밋 6179da1/fcc6d74/9a0d143. (out-of-scope: mp-webhook spec TS2554 2건 pre-existing→deferred-items.md)
- [Phase 42]: 42-01 (executing, done 2026-06-19, feat/phase42-wave1): Transporte = Repartidor(Phase 40) 1:1 복제하되 phone 제외(D-04 스코프 {id,storeId,name,isActive}). store-scoped CRUD(findByStore activeOnly 단일 SELECT pool 절약 + findScoped NotFoundException IDOR 가드 + soft-toggle isActive, hard-delete 없음), 모든 라우트 @Auth() + storeId @GetUser 전용. use_envios = useRestaurantMode(39-03) 패턴 미러 default false → 기존 매장 자동 OFF(RD-12). 마이그레이션 2개(42-01-transportes.sql SERIAL/snake_case/IF NOT EXISTS, 42-03-store-config-use-envios.sql)는 **미적용** — 42-03 BLOCKING task 에서 42-02 online_orders FK 컬럼과 순서 맞춰 로컬 적용 후 운영 PG10 런북. TransportesModule exports [TransportesService] → 42-02 online-orders 가 ship 시 transporte.name 미러(D-05) 소비. jest 5/5 PASS. 백엔드 eslint 는 analog 동일 패턴(빌드 게이트 아님 — NestJS/SWC).
- [Phase 42]: 42-04: /envios Socket.io gateway (domain-separated from /restaurant, /print-agent) — JWT handshake + branch-room IDOR guard; post-commit envio_updated emits on all transitions+cobro (never inside tx)
- [Phase 42]: 42-04: GET /online-orders/:id replaced simple detail with auth-scoped merged-timeline (I-1 PII fix); read-side routes board/:branchId + cuentas-por-cobrar (RD-7 source) + :id/nota owned in backend
- [Phase 42]: 42-05 (done 2026-06-19, feat/phase42-wave1): 프론트 envíos foundation. useEnvios StoreConfig 플래그(default false, fetched+memoized)로 despacho 머신 전체 게이트. SWR 훅 3개(useTransportes 5분 dedup, useDespachoBoard branchId null-key+폴링없음 D-11, useCuentasPorCobrar 5분 dedup). envioLabels(canal/columnKey status/payment 라벨+hex 색, saldo>0 빨강). TransporteCard=RepartidoresCard clone(phone 제거)+useEnvios 게이트+soft toggle(put isActive, remove 없음)+이중 에러(Alert+toast). EnviosConfigView+/configuracion/envios 페이지(토글). **deviation: cuentas per-client 잔액 필드=clientBalance(42-04-SUMMARY 권위 계약), plan 본문의 balance 아님 — clientBalance 매핑.** **Rule3: storeConfig update-flag 화이트리스트에 useEnvios 추가(없으면 토글 400 → 카드 영구 도달불가).** 8 frontend 파일 eslint exit0, storeConfig.controller jest 5/5 PASS. 커밋 20ee42b/e054609/edc9ca9(ventago-app)+536521b(api-ventago).
- [Phase 42]: 42-06 (code complete 2026-06-19, browser UAT pending, feat/phase42-wave1): Ventas Online 3탭 격상 + Despacho 칸반 + 실시간 /envios 소켓 + master-detail 셸. **useEnvios 게이트(RD-12 #1 회귀-0)**: true→EnviosControlCenter(Despacho/Cuentas por cobrar/Historial), false→LegacyVentasOnline(Phase27 Pedidos/Envíos/Devoluciones 원본 verbatim 추출, 레거시 코드경로 일절 미변경). **DespachoBoard**(DeliveryBoard clone, 의류 매핑): 5컬럼(nuevo/preparando/listo/en_transito/entregado) columnKey 그룹핑+count 배지+세로스택. /envios Socket.io 구독(envio_updated → mutateRef 함수형 병합 id 교체, false revalidate 없음, 폴링 0 D-11, cleanup off+disconnect, deps=[branchId]만 — cards 변경마다 재연결 X). 카드: orderNumber/canalLabel/clientName/address/total/paymentStatus 칩(saldo>0 빨강)/transporte+tracking 칩/Saldo $X 빨강 배지. master-detail 75/25: 카드 선택→우측 패널, EnvioTimeline 자리는 inline placeholder(42-07). Despachar(listo): activeOnly transporte 드롭다운+tracking → PATCH /online-orders/:id/ship, saldo>0 외상발송 완납게이트 경고 Alert(despachar con saldo/외상으로 발송). 코드스플릿 next/dynamic ssr:false. **stub(plan 지시, 42-07/08 파일 충돌 회피)**: Cuentas/Historial 탭=inline 'Cargando…' placeholder(42-08), 타임라인=inline dashed container(42-07) — 신규 stub 파일 미생성. 2파일 eslint exit0 + tsc 무에러. 커밋 6034965(DespachoBoard)+81598f3(VentasOnlineView)(ventago-app submodule, fix/pos-precio-base-fallback 브랜치 — 42-05 frontend 와 동일 위치). **browser UAT PENDING**: 3탭 렌더/실시간 소켓 무새로고침/외상게이트/use_envios=false 레거시 무회귀(5 step).
- [Phase 42]: 42-07: Ticket/Recibo wired to existing POST /print/temp (no online-order print route exists); cancel is PATCH :id/cancel {refundAction}; CobroModal props-injected (no POS coupling)
- [Phase 37]: 37-06: QR 출퇴근(Fichaje) 백엔드 — seller_attendance+reseller_store_qr_auth 2 격리테이블, 데스크톱 게이트 일일 HMAC QR, punch role 라우팅(vendedor 출퇴근토글 60s멱등/revendedor 매장권 Phase24승인게이트), RequireAttendanceGuard /mobile/* 출근게이트(NOT_CLOCKED_IN), caja-cierre 강제종료(단일tx NO-OP), /mobile/me clockedIn. 4 task 커밋(efb127d/3e5f249/ade706f/7aa9770), 40 jest green, 기존테이블 ALTER 0. 신규 env ATTENDANCE_QR_SECRET(fail-closed) + 마이그레이션 5432/5434 수동적용 + DI부팅/실기기 UAT 대기.
- [Phase 37]: 37-08: mobile-sales-app Fichaje feature — attendance dto/repo/punchController(성공 후 scope invalidate), fichaje_scanner_sheet(qr_scanner 클론 + parseFichajeDeeplink /m/fichaje?s=&b=&d=&t= + es-AR 에러토스트), fichaje_result_screen(role 분기 entrada/salida근무시간/store_authorized), home 출근게이트(clockedIn=false 작업잠금+"Fichá tu entrada"/true 정상+"Fichar salida"), revendedor_home 매장권 프롬프트(Phase24 대기). 2 task 커밋(83c4d4c/1f9cfc1), flutter test 13 green + scoped analyze clean. F1-F8 dev 통합 UAT 사용자 대기(37-HUMAN-UAT.md). Phase 37 코드 3표면(06/07/08) 완료.
- [Phase 57]: 57-01: buildFactura fuente única D-02/D-04 (build-factura.ts, puro sin DB, reusa applyPartial+letraOf+computeNetoIva canónicos; condIvaLabel map en code-maps). TDD RED ac5fd32 → GREEN 1095563, jest 23/23.
- [Phase 57]: 57-02: fiscal-formatter.js reescrito standalone (no extiende formatInvoiceHtml) porque la shape factura D-02 es independiente del control-ticket; main.js print_invoice bifurca en payload.factura (fiscal path gate printFiscal), control ticket intacto. QR imagen escaneable (QRCode.toDataURL), IVA 21% solo A/M via factura.ivaDiscrim, escapeHtml en todo campo (T-57-04). dcf22c5+ccdf560.
- [Phase 57]: [Phase 57 P03]: afip_issuers.invoice_type (A|M) replica exacta del patrón invoiceSucursal (migración+modelo+DTO); selector RadioGroup RI-gated en ModalBranch vía watch('ivaCondition')==='RI'; payload envía invoiceType solo cuando RI (undefined si no-RI). Migración commiteada NO ejecutada — pendiente dual-apply 5432+5434.
- [Phase 61]: [Phase 61 P01]: Task 1+2 를 store-theme.constants.ts 한정으로 단일 커밋 병합 — 헬퍼 선언(Task1)과 사용(Task2) 분리 시 no-unused-vars 로 Task1 자체 eslint verify 불가능한 구조적 제약 때문
- [Phase 61]: payment/shipping 로고 칩도 logo 와 동일하게 svg 허용(결제·배송 브랜드 아이콘 동일 취급)
- [Phase 61]: smoke-shop-theme.sh — EDIT_TOKEN 미설정 시 조회만 best-effort 수행 후 exit 0, 네트워크 호출 전체를 set -e 로부터 방어
- [Phase 61]: Task1+2 커밋 병합(동일 함수 SELECT 절 순차 확장으로 diff 분리 비실용적); bestseller 강등은 permission denied 문자열 매칭
- [Phase 61]: macrostructure CHECK 제약 4값 교체(로컬5432+운영5434 대조완료) — 운영엔 shop_readonly role 부재 확인, bestseller 는 안전강등으로 무해
- [Phase 61]: 'doc' macrostructure 완전 제거 — sanitizeMacrostructure() 에서 별도 강등 분기 없이 whitelist 밖 값과 동일 처리
- [Phase 61]: diseno.tsx 에 content state 신설(계획 외) — SaveThemeBody.content 필수화로 발생할 수 있던 매장 섹션 설정 유실 방지(초안 로드 시 t.content 보존, 편집 UI는 후속 플랜 범위)
- [Phase 61]: MasonryLayout 이 initialItems 변경(상위 카테고리 필터 재조회)에 맞춰 내부 페이지네이션 상태(items/page/done)를 재동기화 — 필터 전환 시 이전 목록 잔존 방지
- [Phase 61]: globals.css :root 에 --on-navy 폴백(#ffffff) 추가 — 테마 조회 실패 시 var(--navy) 배경 위 텍스트가 사라지지 않도록 함
- [Phase 61]: duoBanners 서브폼에 + Agregar/✕ Quitar 버튼 추가(빈 배열 시작이라 편집 진입점 필수, Rule 2)
- [Phase 61]: GENRE_LABELS(theme-preset.ts) 한국어→스페인어 통일(아코디언 노출 카피, Rule 1)
- [Phase 61]: Carousel.tsx initialItems 재동기화 useEffect 추가 — 검색 필터가 carousel 섹션에 반영되지 않던 회귀 수정
- [Phase 61]: index.tsx 최상위 loading state 제거 — 각 섹션/레이아웃 컴포넌트가 자체 로딩 표시를 소유
- [Phase 61]: reels 상품 오버레이 매칭 실패 시 미렌더(가짜 데이터 금지), .sf-rail 재사용+인라인 오버라이드, durationLabel 힌트는 라벨 병기
- [Phase 61]: ProductCard: useThemeContent() 무조건 호출 후 options 폴백(rules-of-hooks 준수) — options prop 없으면 Provider 의 productCard 자동 적용
- [Phase 61]: 가격 필터(filters.price) 실구현, color/size 필터는 variant 집계 데이터 부재로 정직한 no-op(가짜 필터 미렌더)
- [Phase 61]: quiz 결과 카드는 ProductCard 재사용 대신 UI-SPEC 전용 DOM(MATCH 배지+매칭 이유)으로 QuizSection.tsx 내부 구현; 포커스/hover/반응형은 styled-jsx로 처리해 globals.css 무변경 유지
- [Phase 61]: PanelPrimitives.TextField 에 선택적 hint prop 추가(Rule 2) — 쿠폰/SEO/pixel 안내 문구 표시를 위해 공용 컴포넌트 최소 확장, 하위호환 유지
- [Phase 61]: trust.paymentLogos/shippingLogos 배열 편집을 '기존+빈 add-slot' 결합 배열의 단일 map() 으로 구현 — acceptance 리터럴 카운트와 최대 8슬롯 반복 업로드 요구를 동시 충족
- [Phase 61-tienda-online-editor]: 61-15 Task 1(자동 게이트 10종) 전부 PASS — 마이그레이션 1건/Pool 0/doc 렌더 0/유닛 45 PASS/tsc·eslint 0. Task 2(브라우저 UAT 8항목+운영5434 재확인, checkpoint:human-verify)는 오케스트레이터 Chrome 수행 대기

### Pending Todos

None yet.

### Blockers/Concerns

- **[39-03 Task 2 — blocking human-action checkpoint]** print-agent `print_temp` 핸들러 코드는 머지됨(9f1339d). 운영 print-agent 가 신규 빌드를 받으려면 `push-both.sh` 로 CI 재빌드(GitHub Actions `build-print-agent.yml`) + 운영 PC 재설치 필요 (사용자 액션 — 실행자가 트리거하지 않음). 미완 시 운영 comanda/resumen 출력 무동작. dev(`npm run dev:print`)는 최신 코드 즉시 반영되므로 39-07 dev 검증은 가능.
- Phase 61 61-15 Task 2 checkpoint:human-verify 대기 — ./dev.sh 로컬 기동 후 브라우저 UAT 11개 항목(무회귀 최우선 + R3/R4/R9 rails·masonry·왕복/R10 reels 탭재생/R11 quiz 왕복+Network/R7 팝업·SEO/R5·R6 productCard·filters)을 61-UAT.md 「브라우저 UAT 체크리스트」에 따라 오케스트레이터 Chrome 으로 수행 필요. 운영 5434 CHECK 제약 대조는 61-04 에서 이미 완료(재확인만).

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260420-qet | useVariants 토글 — 신상품 등록 화면 단순화 (VariantsStock 조건부 숨김 + cantidad TextField) | 2026-04-20 | 89184d0 | [260420-qet-tienda-admin-usevariants-false-variantss](./quick/260420-qet-tienda-admin-usevariants-false-variantss/) |

## Session Continuity

Last session: 2026-08-18T02:37:09.316Z

**Phase 40 planned (2026-06-16):** gsd-plan-phase 40 — research 생략, pattern-mapper(40-PATTERNS.md) → gsd-planner 8개 PLAN.md(6 wave, 커밋 7d3da0e) → plan-checker 1차 ISSUES(blocker: 40-06 webhook 경로 오류, warning: QR intent 링크·CSV 템플릿) → 수정(40-04/40-06, 커밋 f2d2cbf) → plan-checker 2차 PASS. REQ-1~9 전부 커버. 다음=`/gsd-execute-phase 40`.

---
*(이전 세션)*

Stopped at: context exhaustion at 100% (2026-08-18)
Resume file: None
Next: (Phase 39 잔여) Jenkins 배포완료 후 운영 /sellers vs /sellers?excludeAdmins=true 검증 + 운영 PC print-agent v1.0.8 재설치 + 브라우저 UAT(식당+소매 판매원 귀속). (다음 phase) `/gsd-plan-phase 40` — 식당 delivery 레이어(Repartidor/RestaurantDelivery/RiderSettlement + 화면 4개), 40-SPEC/40-CONTEXT 완료됨.

## 2026-08-10 세션 — 유지보수 연쇄 (핸드오프: `.planning/HANDOFF-2026-08-10.md`)

한 Phase 가 아니라 서로 물린 유지보수 5건. **전부 운영 배포 + 실측 검증 완료.**

1. **입고 합계 절단** — `stock-today` 가 product_branch 행 단위로 50개를 잘라 2지점 매장의
   뒤쪽 지점이 사라졌다(HELGUERA 360 → 40). 페이지 단위를 codigo madre 로. `api 5193b67`

2. **즉시배송 운송사** — `delivers_immediately` 면 en_transito 를 건너뛰고 entregado.
   목표 상태만 바뀌고 회계는 그대로 → **미수금 유지**. `api c8ed68c` / `front f297084`

3. **취소 다이얼로그 공용화** — 세 화면(칸반·타임라인·주문상세) 한 컴포넌트로.
4. **취소된 외상이 채무로 남던 결함** — `sale_credit_void` 신설(마이그레이션 양쪽 적용).
   함께: open 잔액이 favor_apply 를 이중 차감하던 기존 오류 4곳 수정. `api dfe31af`,`d715c8d`

5. **POS 카탈로그 즉시 갱신** — 3경로(탭/브라우저/소켓) + 출처별 debounce(local 1.5s /
   remote 5s). 도중 **브라우저가 store room 에 아예 안 들어가던 결함** 발견·수정(`a1f4e0c`)
   → `emitToStore` 를 쓰던 다른 기능(보류판매·store_notice)도 같이 살아난다.

남은 것: 외상 주문 un-ship 개방(별도 설계 필요) / 다른 PC 두 대 실측 /
AFIP 인증서 `nam` 8/17 만료 / 테스트 잔여물 정리 여부.

## 2026-08-11 세션 — 잔여물 정리 + 외상 un-ship 개방

`HANDOFF-2026-08-10.md` 의 「남은 일」을 이어받아 진행. AFIP 은 사용자 지시로 제외,
Phase 77 은 사용자 지시로 보류(Wave 0 결정 D1/D4/D6 미확정 상태).

### 1. 잔여물 정리 ✅

- **CatalogChanged 로그 강등** — `logger.log` → `debug`. 운영은 `NODE_ENV=production` →
  winston level=`info` 라 억제되고 로컬 dev 는 계속 보인다. storeId 없음 `warn` 은 유지
  (알림이 안 나가는 상황까지 조용해지면 안 된다). `api c1b6018` (#668 SUCCESS)

  - 실측: 24시간 1건이라 지금은 소음이 아니었다. 가격 일괄 수정 같은 배치 경로 대비.
- **운영 테스트 데이터 정리** — 제품 415 일가(62) + 477 일가(2) 하드 삭제.
  `sale_items` 참조 **0건**(한 번도 안 팔림)을 확인하고 진행. 삭제: products 64 /
  ProductBranch 122 / prices 192 / stocks 120 / stock_balances 120.

  - `stocks` 는 append-only 지만 `stocks_immutable_guard` 가 `SET LOCAL
    ventago.stocks_maintenance='on'` 유지보수 경로를 **함수 안에 명시적으로 제공**한다.
    앱 정책(재고 0 + 제품 보존)의 대안은 존재하지 않았던 −1800 출고를 원장에 영구히
    남기므로 하드 삭제를 택했다.

  - `stock_balances` 는 FK 가 없어 CASCADE 안 됨 → 명시 삭제 필요.
  - 고객 7480 favor 500 → `favor_refund` 1행(엔드포인트가 없어 `appendMovement` 로직을
    SQL 로 재현) + `store_clients.favor_balance` 캐시 갱신.

  - **주문 #11 / sales 141·142 는 보존** — 취소+역분개 쌍은 정합적 회계 이력.
  - 검증: 잔존 0 / favor 0 / `v_stock_balance_drift`·`v_stock_tenant_leak` 각 0행.
  - 로컬(5432)에는 더미가 없어 운영 전용 작업(스키마 아님 → 양쪽 적용 대상 아님).

### 2. 외상 주문 un-ship 개방 ✅ (배포됨, 운영 실측은 미수행)

`api a780487`(#669 SUCCESS) / `front 5653dc0`(#597)
설계·CODEX 자문·검증 기록: `.gsd/review-request-unship-credit.md`

- `applyUnship` 이 `sale_credit_void` 로 외상을 역기입 → `revertOrder` 의 차단 2곳 제거.
- **순서 제약**: void 는 반드시 `detachOnlineOrder` **앞**. detach 후에는
  `sales.online_order_id` 복구 경로가 사라져 어느 sale 의 채무인지 못 되짚는다.

- **수금이 끼면 fail-closed** — 원장(`payment_in` 부착) + 주문(`received` 증가) 양방향 검사.
  후자가 따로 필요한 이유: `registerCobro` 수금은 고객 전체 외상에 FIFO 배분되므로
  다른 주문을 갚았으면 원장 검사에 안 잡히는데, 재발송 saldo 는 `received` 로 계산돼
  채무가 과소 기록된다. 주문 장부와 고객 원장이 서로 다른 것을 센다.

- `voidSaleCredits` 를 resolve/plan/assert/execute 로 분리. **공용 헬퍼에 정책을 넣지 않는다**
  — 넣었으면 부분 수금 주문을 더는 취소하지 못하는 회귀(CODEX 지적).

- 함께 고침: `registerCobro` 의 lost update(트랜잭션 밖 스냅샷 되쓰기) → 잠근 최신 행 병합.
- `toCard.deliveredImmediately` 추가 → 화면이 `entregado` 칸의 두 되돌리기를 구분.
- 테스트 8건, **뮤테이션 5종 사멸**. 단 처음엔 가드 테스트 2건이 잘못된 이유로 통과했다
  (mock 잔액 미설정 → 잔액 가드가 대신 던짐). mock 을 고쳐 실제 가드를 검증하게 만듦.

### 남은 일 (이 세션 이후)

- **외상 un-ship 운영 실측** — 발송 → 되돌리기 → 재발송 왕복 미확인.
- **AFIP 인증서 `nam` 8/17 만료** (사용자 지시로 이번 세션 제외). `AFIP_CERT_ALERT_EMAIL` 미설정.
- **Phase 77** 보류 — Wave 0 결정 D1(자산 시드)·D4(track_stock 기본값)·D6(승인 임계) 미확정.
  기술 결정 D2/D3/D5/D7 은 권장안 채택 예정이었음.

- POS 카탈로그 갱신의 **다른 PC 두 대 실측** (물리 장비 필요 — 사용자 액션).
- `runStatusTx` 에 SERIALIZABLE 재시도 없음 (ship/deliver/cancel 전 경로 공통, 별건).
