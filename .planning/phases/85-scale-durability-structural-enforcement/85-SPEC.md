---
phase: 85-scale-durability-structural-enforcement
milestone: v1.1
created: 2026-08-19
status: planned
waves: 8
depends_on: [69, 75, 76]
---

# Phase 85 — 300매장 내구성: 규약을 코드로 강제한다

## 목표

**300매장 시점에 문제가 생기지 않도록, 지금 안 하면 그때 못 하는 것을 지금 한다.**

두 가지를 한다.

1. **재발 경로를 닫는다** — 위반이 "나쁜 코드"가 아니라 **불가능한 코드**가 되게 한다.
   린트 경고나 코드 리뷰로 잡지 않는다. 발견은 사람이 고쳐야 끝나고, 1인 팀에서는
   발견 속도가 수정 속도를 넘는 순간 게이트가 꺼진다(`eslint-disable` 한 줄).
2. **테이블이 작을 때만 무통증인 것을 지금 붙인다** — 파티셔닝·무중단 마이그레이션 규약·
   무중단 배포. 300매장에서는 비용이 수십 배가 되거나 아예 불가능해진다.

## 배경

근거: `85-FINDINGS.md` (2026-08-19 코드 실측 + 반증 조사)
자문 메모: `.planning/ADVISOR-2026-08-19-승산과-300매장.md`

한 줄 요약: **지켜진 규약과 무너진 규약의 차이는 성실함이 아니라 강제 지점의 유무다.**
2026-07-31 리뷰에서 지적된 9건 중 백엔드 5건은 전부 해결됐고(강제 지점이 있는 형태로 고쳤다),
프론트 3건은 19일이 지나도록 하나도 안 고쳐졌으며 **신규 위반이 늘었다**(문서에만 있는 규약).

## 기술 스택

- 백엔드: NestJS 11 + Sequelize (`underscored: true`), PostgreSQL 18
- 프론트: Next.js 13 Pages Router + MUI 5 + SWR
- DB: 로컬 Mac PG18 `:5432` / 운영 srv803182 PG18 `ventago18` `:5434` (앱은 pgbouncer `:5432` 경유)
- ESLint: `api-ventago` (package.json `lint`), `ventago-app/.eslintrc.json` — **Warning 도 빌드를 막는다**
- 배포: Jenkins (`api-coolsistema` / `front-coolsistema`) → Docker

---

## 웨이브 구조

착수 순서에는 이유가 있다. **재발 경로를 먼저 닫는다** — 위반 개수가 아직 적을 때가 가장 싸고,
닫지 않으면 뒤 웨이브를 하는 동안에도 계속 늘어난다(B-8 이 실제로 그렇게 됐다).

| W | 이름 | 성격 | 왜 이 순서인가 |
|---|---|---|---|
| **W1** | 캐시 API 봉인 | 재발방지 | 가장 기계적이고 위험이 낮다. 강제 지점 패턴을 팀(=미래의 자신)에게 먼저 증명한다 |
| **W2** | 소켓 공유 provider + 서버측 연결 제한 | 재발방지 | **유일하게 악화 중.** 새 기능이 하나 더 붙기 전에 닫아야 복제가 멈춘다 |
| **W3** | pageSize 하드 클램프 + POS 검색 전환 | 재발방지 | 화면이 깨지므로 W3 순서가 중요 — 검색 먼저, 클램프 나중 |
| **W4** | 무중단 마이그레이션 규약 + 파티셔닝 | 나중엔 못 함 | 테이블이 작은 지금이 유일한 무통증 시점 |
| **W5** | 무중단 배포(블루/그린 또는 롤링) | 나중엔 못 함 | 첫 유료 고객 온보딩 전까지 |
| **W6** | 매장별 논리 복구 (A-3) | 사업 요건 | 유료 고객이 생기면 연 2~5회 반드시 요청된다 |
| **W7** | 보고서 야간 rollup | 확장성 | 300매장이 월초에 같이 돌린다 |
| **W8** | 300매장 회귀 자동화 + p95 배포 게이트 | 관측→게이트 | **모든 웨이브의 회귀를 잡는 마지막 그물.** 이게 없으면 W1~W7 도 조용히 낡는다 |

### W1 — 캐시 API 봉인

`getOrLoad` 를 추가하고 사용처를 바꾸면 **44번째 호출부가 또 생긴다.**
그래서 `get()`/`set()` 을 **private 으로 내리고 `getOrLoad` 만 public** 으로 노출한다.
stampede 패턴이 컴파일 불가능해진다. 교체 작업량은 같은데 재발 가능성이 0 이 된다.

- 대상: `MemoryCacheService` 주입 파일 **38개**
- 불변식: 모든 캐시 키에 `storeId` 명시 (기존 규약, 이 기회에 타입으로 강제)
- TTL: 참조 60초 / 대시보드 30초 (기존 규약 유지) — 예외는 그 자리에 **왜 다른지 주석 필수**

### W2 — 소켓 공유 provider + 서버측 연결 제한

> ★★ **착수 전 코드 대조 결과 (2026-08-20) — 아래 원안의 수치 2개가 틀렸다.**
>
> **① 대상은 4개가 아니라 9개다.** `socket.io-client` 를 직접 import 하는 파일 전수:
> `utils/catalog-refresh.ts` · `components/team-chat/TeamChatPanel.tsx` ·
> `hooks/useRemoteSupport.ts` · `pages/soporte/visor.tsx` ·
> `views/homes/hook/useThermalAgentStatus.ts` · `views/homes/hook/useSuspendedSaleSocket.ts` ·
> `views/mercadopago/hooks/useMpApprovedSocket.ts` · `views/restaurante/DeliveryBoard.tsx` ·
> `views/ventas-online/DespachoBoard.tsx`
> 전부 **같은 네임스페이스**(기본)에 붙고 `WS_URL`/`WS_HOST` 상수가 9곳에 복붙돼 있다.
> 원안의 4개만 고치면 **import 봉인이 성립하지 않는다** — 이 웨이브의 목적 자체가 사라진다.
>
> **② 「서버측 제한 기본 2」를 그대로 켜면 오늘 POS 가 전부 끊긴다.** POS(nueva-venta) 한 탭의
> 동시 소켓은 최대 **5개**다: TeamChatPanel(전역 — `UserLayout.tsx:313`) · catalog-refresh
> (`ProductList`) · useThermalAgentStatus(`ProductList`) · useSuspendedSaleSocket
> (`DraftAndDebtorsList`) · useMpApprovedSocket(`PaymentSummaryModal`, MP 결제 시).
> 제한값은 **통합 후 실측**으로 정하고, 켜는 것은 클라이언트 배포가 끝난 **다음 릴리스**다.
>
> ③ 서버측에는 현재 연결 제한이 **전혀 없다**. 게이트웨이는 5개
> (`websocket` · `print` · `online-orders-board` · `restaurant-delivery` · `support`).
>
> ⑤ **기전을 확인했다 (socket.io-client 4.8.3 `lookup()` 20~24행).**
> ```js
> const sameNamespace = cache[id] && path in cache[id]["nsps"];
> const newConnection = opts.forceNew || ... || sameNamespace;
> ```
> 서로 **다른** 네임스페이스는 같은 Manager 에 다중화돼 물리 연결 1개를 공유한다. 그런데
> **같은 네임스페이스를 두 번째로 열면 socket.io 가 일부러 새 Manager(=새 물리 연결)를 만든다.**
> `/realtime` 을 5곳이 각자 `io()` 로 여니 **정확히 5개의 물리 연결**이 생긴다.
> → 고칠 것은 "소켓을 줄이자"가 아니라 **"같은 네임스페이스는 한 번만 연다"** 이다.
> → `/support`(2곳)는 같은 네임스페이스라 2연결, `/envios`·`/restaurant` 는 1곳씩이라 무해.
>   그래도 래퍼로 넣는다 — 안 그러면 import 봉인이 안 되고 10번째가 또 생긴다.
>
> ⑥ ★ **공유 소켓에서는 `socket.off('event')` 가 흉기다.** 지금 모든 훅이 cleanup 에서
> 이벤트명만으로 `off` 를 부르는데(예: `useSuspendedSaleSocket.ts:50`), 소켓을 공유하면
> 그 한 줄이 **다른 소비자의 핸들러까지 전부 지운다.** 래퍼는 반드시
> `off(event, handler)` 로 자기 핸들러만 떼야 하고, `disconnect()` 는 **참조 수가 0일 때만** 한다.
>
> ④ 원안의 `catalog-refresh.ts:134` 는 **현재도 정확하다.** 그 파일 122행 주석이
> "기존 useSuspendedSaleSocket / useMpApprovedSocket 과 같은 형태" 라고 적고 안티패턴을
> 그대로 복제했다 — STATE.md 의 B-8 「복제 중」 진단이 코드로 확인된다.

**두 겹으로 막는다. 클라이언트만 고치면 다음 사람이 또 `io()` 를 부른다 — 실제로 그렇게 됐다.**

1. 클라이언트: 단일 `/realtime` provider(탭당 1소켓, 여러 room join). `socket.io-client` 직접
   import 를 봉인하고 래퍼만 노출
2. **서버: 같은 `(userId, terminalId)` 에서 소켓이 N개(기본 2) 넘게 오면 거부 + 경고 로그.**
   위반이 배포 후가 아니라 **개발 중 즉시** 드러난다

- 통합 대상: `useThermalAgentStatus` · `useSuspendedSaleSocket` · `useMpApprovedSocket` · `utils/catalog-refresh.ts`
- 함께: `PrinterConfigTab.tsx:90` 30초 폴링 → 기존 realtime 채널로 대체(리팩터의 남은 절반)
- ★ 서버측 제한은 **W2 마지막에** 켠다. 먼저 켜면 기존 클라이언트가 전부 끊긴다

#### W2 검증 결과 (2026-08-20)

| 확인 | 방법 | 결과 |
|---|---|---|
| 소비자 5명 → 물리 연결 1개 | 단위 spec (`socket-registry.spec.ts`) | `io()` **정확히 1회**. codex 결함 3건도 각각 mutation 검증 |
| 실제 앱에서 소켓 공유 | 운영 POS 에서 SPA 이동(나갔다 복귀) | 새 WebSocket **0개** — 공유 소켓이 유지·재사용됐다. 종전이면 3개가 닫히고 3개가 새로 열린다 |
| POS 탭 1개의 서버 연결 비용 | 운영 API 컨테이너의 established 연결 수 | **44 → 46 → 44** (탭 열기/닫기). +2 = WebSocket 1 + HTTP keepalive 1. 종전이면 +4 |

#### W2 잔여 2건 완료 (2026-08-20 밤)

| 항목 | 결과 |
|---|---|
| `PrinterConfigTab.tsx:90` 30초 폴링 | **제거** — 공유 소켓 `register_branch` 구독으로 대체(`ventago-app e7f4f7b`) |
| 서버측 소켓 수 제한 | **집계까지 완료, 한도는 꺼 둔 채 배포**(`api-ventago f682397`) |

★ **제한의 형태가 계획서와 다르다 — 의도적이다.**

계획서는 "같은 `(userId, terminalId)` 에서 N개(기본 2) 넘으면 거부" 였다. 실제로는:

1. **`terminalId` 는 handshake 시점에 없다.** JWT 에는 userId/storeId 만 있고 terminalId 는
   접속 뒤 `register_terminal` 로 온다. 그래서 키는 `(네임스페이스, userId|agentId)` 다.
2. **워커 로컬로 세면 실제의 1/4 만 보인다.** 운영은 pm2 4워커고 한 탭의 소켓들은 OS 가
   워커에 나눠 배정한다(rate-limit 에서 이미 겪은 함정 — `redis-throttler.storage.ts`).
   그래서 Redis 공유 해시로 센다. 죽은 항목은 6분 만료 + HDEL 로 자가 치유한다 —
   이게 없으면 워커가 SIGKILL 로 죽을 때마다 카운트가 영구히 올라가 **한도를 켠 순간 전원 차단**이다.
3. **한도 기본값은 0(꺼짐)이다.** "기본 2" 는 통합 **전**(POS 한 탭 = 5소켓) 값이라 그대로
   켜면 POS 가 전부 끊긴다. 그리고 한 사람이 탭을 여러 개 여는 것은 정상이므로 한도는
   추측이 아니라 **실사용 분포**로 정해야 한다.

★ **집계 identity 는 JWT 모양마다 다르다** (배포 후 운영 값을 보고 두 번 고쳤다).
이 저장소의 토큰은 한 가지가 아니다 — 사용자 토큰에는 `id` 가 **없고**(email 이 사실상
식별자다), 공방 포털 토큰에는 id·email 이 **둘 다 없다**(vendorId 를 쓴다).
처음엔 전원이 `u:undefined` 로 뭉쳤고, 그 상태로 한도를 켰다면 전원 차단이었다.
→ `jwtIdentity()` 가 `type` 접두어 + (id | vendorId) → email 해시 → 소켓별 고유 순으로 고른다.

**켜는 절차 (다음 세션이 할 일):**
```
GET /api/diagnostics/sockets          # superadmin. histogram = "N개 든 사람이 몇 명"
→ 며칠치 꼬리를 본 뒤
SOCKET_MAX_PER_IDENTITY=<값>          # api-ventago .env — 재배포 불필요, 재시작만
```
`SOCKET_WARN_PER_IDENTITY`(기본 6)는 한도가 꺼진 동안에도 초과 시 경고 로그를 남긴다.

★ 남은 구조적 지뢰(이번 범위 밖, 기록만): 서버 `registerBranch` 는 `client.branchId`
**단일 슬롯**이라 새 지점을 등록하면 이전 방을 떠난다. 소켓을 공유하는 지금, 서로 다른
branchId 를 요구하는 소비자가 **동시에** 뜨면 나중 것이 앞 것을 방에서 밀어낸다.
현재는 `useThermalAgentStatus`(POS)와 `PrinterConfigTab`(sucursales) 둘뿐이고 서로 다른
페이지라 동시에 뜨지 않아 무해하다 — **셋째가 생기면 그때 터진다.**

★ 로컬 재현 환경 구축 중 걸린 것 (다음에 또 걸린다):
  - **로컬 `ventago` DB 는 비어 있다**(0 테이블). 메모리의 "복원했다" 기록은 낡았다.
    → SSH 터널(`ssh -N -L 15432:127.0.0.1:5434`)로 `ventago_staging` 을 쓰는 편이 빠르다.
  - **프로덕션 번들은 API 를 `https://newapi.coolsistema.com/api` 로 보낸다**
    (`api.service.ts:20`, NODE_ENV!=='development'). 로컬에서 `next start` 로 띄우면
    **브라우저가 운영에 로그인**한다 — 중복로그인 차단으로 실제 사용자가 튕긴다. 반드시 `next dev`.
  - 로컬 `.env` 는 운영 값을 쓰되 **DB 와 CRON 은 반드시 다르게** 한다
    (DB→터널/스테이징, `CRON_ENABLED=false`). 크론을 켜면 캠페인·Telegram 이 실제로 나간다.

### W3 — pageSize 하드 클램프 + POS 검색 전환

순서를 지키지 않으면 화면이 죽는다.

1. 서버측 검색·필터 엔드포인트 제공 (POS 상품, 보류판매, 지출)
2. 화면을 검색으로 전환 (`ProductList` · `DraftAndDebtorsList` · `DailySalesStats` 지출 · restaurante 3곳 · talleres · `InvoiceAditional` · `AccessLogsView`)
3. **마지막에** 공용 pagination 파이프가 `pageSize` 를 50 으로 하드 클램프.
   클라이언트가 1000 을 보내도 50 이 온다 → 남은 위반은 **고장 나서** 드러난다

★ **C-5 는 W3 로 끝나지 않는다.** 상품 5만 개 매장이 들어오면 50 페이지네이션으로도 POS 가 못 쓴다.
카탈로그 **delta sync + 로컬 인덱스**가 진짜 답이며, 이는 별도 Phase 로 뺀다.
W3 는 그 전제(서버측 검색)를 만드는 데까지다.

### W4 — 무중단 마이그레이션 규약 + 파티셔닝

- 규약: expand → migrate → contract. `NOT NULL` 은 백필 후 별도 단계.
  인덱스는 `CREATE INDEX CONCURRENTLY`. 큰 테이블 `ALTER` 는 잠금 시간 사전 측정 필수.
  **CLAUDE.md 에 못 박고 307번째 마이그레이션부터 적용한다.**
- 파티셔닝: `85-FINDINGS.md` E 절의 행 수 실측 **후에** 대상 확정.
  후보는 `stocks`(append-only) · `sales` · `sale_items` · `sync_outbox` · `slow_query_log`.
  ★ 추측으로 파티셔닝하지 않는다 — 잘못 자르면 되돌리는 비용이 자르는 비용보다 크다.

### W5 — 무중단 배포

nginx upstream 2개 + 헬스체크 통과 후 전환 + 구 컨테이너 드레인.
`api-ventago/docker-compose.yml` 에 healthcheck 는 이미 있다(`:30`, `:61`) — 그것을 **전환 조건**으로 쓴다.

### W6 — 매장별 논리 복구 (A-3)

`store_id` 하나만 내보내고 되돌리는 경로. FK 그래프 순서를 지켜야 하므로
`.planning/intel/db-schema-fks.md` 가 유일한 근거다.
- 내보내기: 매장 1개 전 테이블 → 시점 지정
- 되돌리기: **격리된 스테이징에서 먼저 검증 후** 운영 적용(운영 직접 실행은 사용자 승인 필수)
- ★ 이건 사업 요건이다. 고객이 "어제 데이터로 돌려주세요" 라고 하면 지금은 답이 없다

### W7 — 보고서 야간 rollup

요청 시 계산 → 사전 집계 + 조회. 300매장이 월초에 동시에 돌리는 것을 흡수한다.
크론은 W1~W9 의 `runWhenLeader` / SchedulerRegistry 게이트를 그대로 탄다(Phase 75 W6-1 자산).

### W8 — 300매장 회귀 자동화 + p95 배포 게이트

**손 절차로 남으면 반드시 안 돈다.** 사용자가 `loadtest/README.md` 에 직접 적어 두었고
2026-08-07 되살릴 때 실제로 2건이 걸렸다.

- 309매장 스테이징 준비를 **스크립트 1개**로 (Phase 76 목표 계승)
- **주 1회 자동 실행** (심야)
- **p95 > 300ms 이면 배포를 막는다.** 지금은 342~664ms 가 측정만 되고 아무것도 막지 않는다
- W1~W7 각 웨이브의 불변식을 이 리그에서 회귀 검사

---

## 완료 기준

각 웨이브는 **아래를 전부 만족해야** DONE 이다. 하나라도 미충족이면 다음 웨이브로 가지 않는다.

| # | 기준 |
|---|---|
| G-1 | ESLint 오류 **0** (`npm run lint` — api + app 양쪽. Warning 도 빌드를 막는다) |
| G-2 | 해당 웨이브의 **강제 지점이 실제로 강제하는지** 회귀 테스트로 증명 (위반 코드가 컴파일/런타임에서 거부되는 테스트) |
| G-3 | PostgreSQL pool: 신규 `pool.connect()` 직접 사용 0건. 트랜잭션 내 외부 I/O 0건. `transaction` 인자 누락 0건 |
| G-4 | 마이그레이션이 있으면 **로컬(5432) + 운영(5434) 양쪽 적용 확인** 후에만 DONE |
| G-5 | push 후 Jenkins 빌드 성공 + 운영 컨테이너 재생성 확인 |
| G-6 | 최신 로그(`api-ventago/logs/error-*.log`)에 **새로운** 에러 0건 |

Phase 전체 완료 기준:

- [ ] `getOrLoad` 외 캐시 접근 경로 없음 (`get`/`set` private)
- [ ] POS 탭당 `/realtime` 소켓 **1개** (실측: DevTools + 서버 `sockets` 카운트)
- [ ] `pageSize > 50` 요청이 서버에서 50 으로 클램프됨 (프론트 하드코딩 잔존 여부와 무관)
- [ ] 무중단 마이그레이션 규약이 CLAUDE.md 에 있고 이후 마이그레이션이 준수
- [ ] 파티셔닝 대상 확정 및 적용 (행 수 실측 근거 첨부)
- [ ] 배포 중 `/api/health` 무중단 (외부 워치독 기준 5xx 0건)
- [ ] 매장 1개 논리 복구가 스테이징에서 1회 완주
- [ ] 309매장 리그 주 1회 자동 실행 + p95 게이트 가동

---

## 금지사항 / 주의사항

- ★ **착수 전 코드 대조 필수.** 이 Phase 의 근거 문서(2026-07-31 리뷰)는 이미 **2건이 낡아 있었다**
  (B-4·B-7). Phase 84 도 W1·W2 에서 두 번 다 계획이 틀렸다. **있는 것을 다시 만들지 않는다.**
- ★ **pool max 를 올리지 않는다.** 병목은 앱 pool 이 아니다. 쿼리·요청 동시성으로 해결한다.
- ★ **테넌트별 DB/스키마 분리로 가지 않는다.** 300개 스키마 마이그레이션은 1인 운용 불가.
  `store_id` 공유 스키마가 정답이며 필요한 것은 격리 강화지 물리 분리가 아니다.
- ★ **Kubernetes / 마이크로서비스로 가지 않는다.** Docker Compose + PM2 로 300은 충분하다.
- ★ **읽기 복제본은 이 Phase 범위가 아니다** (등급 C, 100매장 이후).
- ★ `stocks` 는 append-only. UPDATE/DELETE 금지(`trg_stocks_immutable`). 보정은 반대 부호 행으로.
- ★ 재고 읽기는 `stock_balances`/뷰만. `products.stock` 은 Phase 70-06 에서 강등됨 — 신규 참조 금지.
- ★ W2 서버측 소켓 제한은 클라이언트 전환 **후에** 켠다. 순서를 바꾸면 전 고객이 끊긴다.
- ★ W3 하드 클램프는 검색 전환 **후에** 켠다. 순서를 바꾸면 화면이 죽는다.
- ★ 운영 DML/DDL 은 SQL + 예상 영향 row 수를 보여주고 **사용자 승인 후** 실행한다.

---

## 실행 규칙

- 플랜 파일은 **웨이브 착수 시점에** 쓴다. 지금 W4~W8 까지 상세 플랜을 쓰면 착수 전에 낡는다
  (Phase 84 의 교훈). 이 SPEC 이 웨이브의 계약이고, 플랜은 그때의 코드 실측 위에서 만든다.
- 한 번에 한 웨이브. 웨이브 범위 밖 변경 금지.
- 주석은 한국어, 함수·변수명은 영어. 에러 핸들링 항상 포함.
- 예상치 못한 문제 발견 시 실행을 멈추고 보고한다.

## 플랜 목록

- [ ] `85-01-PLAN.md` — W1 캐시 API 봉인 ← **다음 착수**
- [ ] W2 플랜 — 착수 시 작성
- [ ] W3 플랜 — 착수 시 작성
- [ ] W4 플랜 — 행 수 실측 후 작성
- [ ] W5 플랜 — 착수 시 작성
- [ ] W6 플랜 — 착수 시 작성
- [ ] W7 플랜 — 착수 시 작성
- [ ] W8 플랜 — 착수 시 작성
