# PLAN 2026-10-13 — edge-agent 시범 설치 + 인터넷 단절 시험 (coolsistema, store 6 / branch 6)

> 요청: 「시범 매장 1곳(coolsistema)에서 edge-agent 를 설치하고 인터넷 단절 시험을 하는 계획을 세워줘」
> 목표: 인터넷이 끊겨도 **판매가 계속되고, 복구되면 장부(판매·재고·카하)에 정확히 한 번 들어간다.**
> 이 문서는 조사·계획만이다. 코드·운영 DB 는 건드리지 않았다(운영은 SELECT 만).

---

## 1. 현재 상태 요약

### 1-1. 있는 것

| 구성 | 위치 | 상태 |
|---|---|---|
| edge-agent (Node 서비스, 로컬 PG 필수) | `edge-agent/src/*` (2,195줄) | 코드 있음. **운영에서 한 번도 판매를 처리한 적 없음** |
| 설치 스크립트 (Windows, 관리자 PowerShell) | `edge-agent/install.ps1` | Node ≥18·PostgreSQL 이 **이미 설치돼 있어야** 함(58–72행에서 확인만, 설치 안 함). 자동 시작은 SYSTEM 예약작업(152–159행) |
| 배포 워크플로 | `.github/workflows/build-edge-agent.yml` | 태그 `edge-agent-v*` 로 트리거, **zip 만 만든다**(Node/PG 미포함). **실행 이력 0회** |
| 서버 수신부 | `api-ventago/src/app/offline-sync/*` | `POST /offline-sync/push`, `GET manifest/pull/ids`, `GET edge-ticket` |
| 프론트 우회 | `ventago-app/src/services/api.service.ts:139-178`, `offline-mode.service.ts` | `POST /sales` 와 `POST /print/temp·/print/barcode` 만 edge 로 우회 |
| print-agent edge failover | `print-agent/src/edge-failover.js`, `print-agent/main.js:946-961` | 클라우드 소켓이 끊기면 `localhost:5010` 으로 2차 접속 |
| 단위 시험 | `api-ventago/src/app/offline-sync/offline-push.service.spec.ts` | **2026-10-13 로컬 실행 20/20 통과**(7.8초, `--maxWorkers=1`). edge-agent 쪽 시험은 **0개** |

### 1-2. 운영 실측 (2026-10-13, SELECT 만)

- `branch_agents` id **17** `agent_type='edge'` branch 6 「Edge Sync Agent — coolsistema piloto」, `is_online=f`, `last_seen_at=2026-07-20`.
- `offline_sync_ops` **0행**, `sales.offline_number IS NOT NULL` **0행** — 오프라인 판매가 운영에 착지한 적 없음.
- branch 6 의 서랍(boxes): **4개**(6 Caja 1 · 15 JuanaCaja · 16 2o piso · 17 3o piso). 지금 열린 세션은 box 6 (cash_register 415) 하나.
- branch 6 에 연결된 print 에이전트: thermal 5·14·27(27 온라인), zebra 13·16(16 온라인). terminal 6 → thermal 27, terminal 17·36 → thermal 5.
- `store_configs(6)`: `allow_sale_without_stock = t`, `use_factura_electronica = t`, **`afip_auto_issue = f`**, `afip_production = t`.
- 최근 7일 판매자: user **16 (israel@cool, `users.branch_id` = NULL)** 14건, user **7 (admin@cool, `branch_id` = 16 HELGUERA)** 6건.
- 15분 활동 사용자: 1명(조사 시점).

### 1-3. 동작 구조 (코드 근거)

1. **오프라인 감지(브라우저)**: 네트워크 오류 2회/10초(`offline-mode.service.ts:23,26`) → `/version` 확인 실패 → offline 진입 → `http://localhost:5010/api/health` 로 edge 확인(`:34`, 기본 URL).
2. **판매 우회 조건**: offline + edge 감지 + **`localStorage.ventago_offline_sales === '1'`**(파일럿 플래그) + `POST /sales` (`api.service.ts:139-178`). 플래그가 없으면 판매는 그냥 실패한다.
3. **edge 인증**: 서버가 지점 agentKey 로 HMAC 서명한 티켓(`x-edge-ticket`), **TTL 12시간**(`edge-ticket.service.ts:17`). 로그인 직후(`AuthContext.tsx:254`)·복구 직후에만 받는다. 티켓 없으면 edge 가 401(`edge-agent/src/server.js:87-104`).
4. **캡처**: edge 가 `offline_outbox` 에 `sale.create` 기록, 번호 `OFF-<ULID>`(`server.js:248`), 미러 재고 best-effort 차감(`:259`). 응답 `id:null, offline:true`.
5. **인쇄**: `/print/temp` 를 edge 가 받아 edge 에 붙은 print-agent 로 emit(`edge-agent/src/print-gateway.js`).
6. **동기화**: push-worker 20초 주기, 배치 20, 온라인일 때만(`push-worker.js:30-110`). 서버는 `op_uuid` ON CONFLICT 로 수신하고 `SalesCreateService.create(dto, { idempotencyKey: 'offline:'+uuid, offlineNumber, suppressAutoPrint: true })` (`offline-push.service.ts:368-392`). 판매일은 `originalAt`, 지점은 에이전트가 정한다(`:354`).
7. **POS 카탈로그는 edge 미러를 쓰지 않는다** — 브라우저가 페이지 로드 때 받은 것을 메모리에 쥔다. Service Worker/IndexedDB 없음(grep 0건). → **단절 중 새로고침하면 POS 화면 자체가 안 뜬다.**

### 1-4. 알려진 위험 (근거 포함) — 시험 전에 판정이 필요한 것

| # | 위험 | 근거 | 영향 |
|---|---|---|---|
| R1 | **판매자 티켓이 404** — 티켓 지점은 `users.branch_id` 로 정한다. 실제 판매자 israel 은 NULL, admin 은 16 | `edge-ticket.controller.ts:35`, `edge-ticket.service.ts:82-92` | 지금 상태로는 **실제 판매자 둘 다 오프라인 판매 불가(401)** |
| R2 | **error 는 양쪽 종결** — 서버 `error/unsupported` 는 재전송해도 같은 오류 반환, edge 는 `pending` 만 고른다 | `offline-push.service.ts:237-244, 301-315` / `push-worker.js:87-95` / `db.js:262-269` | 동기화 단계 예외 1건 = **물건은 나갔는데 장부에 없는 판매**. 아무도 모른다(알림 없음) |
| R3 | **네트워크 실패 8회면 영구 정지** — `attempts < 8` 이고 배치 전체가 함께 +1 | `db.js:266`, `push-worker.js:70-75` | 20초 주기면 약 3분 실패 후 그 배치(최대 20건) 영영 안 감 — 단, 오프라인일 땐 drain 을 건너뛰므로(`:31`) 실제로는 「온라인 판정인데 push 실패」(서버 500·인증 오류) 때만 소진 |
| R4 | **결제 중 단절 = 이중 판매** — 첫 `POST /sales` 가 클라우드에 닿고 응답만 잃으면, offline 전환 후 재시도는 edge 로 가서 **다른 멱등키**(`offline:<uuid>`)로 또 생성된다. edge 는 `Idempotency-Key` 헤더를 읽지 않는다(grep 0건) | `ProductList.tsx:2543-2545`, `server.js:209-283` | 판매 2건·재고 2번 차감·현금 2번 |
| R5 | **동기화 시점 카하로 현금이 들어간다** — 열린 카하가 없으면 현금 입금을 **조용히 건너뛴다**; 지점에 열린 카하가 없으면 **사용자 기준으로 폴백**해 다른 지점 서랍에 꽂을 수 있다; 지점에 서랍이 여럿이면 `id DESC` 첫 번째 | `sales-create.service.ts:3404-3436`, `:3250-3267`, `cashRegister.service.ts:2090-2104` | 서랍 현금과 장부가 갈라진다. branch 6 은 서랍 4개 |
| R6 | **현금 환불(반품·cambio) 동기화는 카하 없으면 throw** → R2 로 종결 | `sales-create.service.ts:3341-3350` (`ERR-DEV-001`) | 반품 판매가 사라짐 |
| R7 | 티켓 12시간 만료 — 오프라인 중 갱신 불가 | `edge-ticket.service.ts:17`, `offline-mode.service.ts:71-97` | 아침 로그인 → 밤 단절이면 401 |
| R8 | 단절 중 새로고침/재로그인 불가 (오프라인 로그인은 P72-01 에서 제거) | 1-3 ⑦, commit 5ce98a1 | 브라우저 재시작 = 영업 중단 |
| R9 | 오프라인 판매 응답 `id:null` → F10 발급 모달·WhatsApp·「마지막 판매 수정」 등 id 를 쓰는 후속이 깨질 수 있다 | `ProductList.tsx:2596-2615` (`setFacturarSale(createdSale)`) | 화면 오류 (데이터 손상은 아님) |
| R10 | 신규 고객 등록은 edge 로 안 간다(`/clients` 미우회). 서버엔 `client.create` op 가 있지만 프론트 배선 없음 | `api.service.ts:139-178`, `ProductList.tsx:1777,1786` | 고객 지정 판매는 **단절 전에 이미 선택된 고객만** |
| R11 | 미러 `users` 가 `SELECT t.*` — 비밀번호 해시 등이 지점 PC 로 복제된다 | `table-registry.ts:91-96` | 보안 메모(파일럿 차단 사유는 아님, edge 는 127.0.0.1 바인딩 `config.js:17`) |
| R12 | Chrome 의 공개 사이트 → `localhost` 요청 제한(Local Network Access 권한 프롬프트) — **미확인** | 브라우저 정책 | 첫 접속 때 「허용」을 안 누르면 edge 감지 실패 |
| R13 | 3개월간 서버가 바뀌었는데 edge 는 07-20 이후 안 돌았다 — manifest/pull 계약이 아직 맞는지 **검증된 적 없음** | `never-executed-code-is-unverified` | 첫 기동에서 결함이 겹겹이 나올 수 있다 |

★ 안심 요소: store 6 은 `allow_sale_without_stock=t` 라 재고 부족으로 동기화가 거절되지 않는다. `afip_auto_issue=f` 라 동기화 시 자동 발급도 없다(켜져 있었다면 `suppressAutoPrint` 는 **출력만** 막고 발급은 한다 — `sales-create.service.ts:1346`). 무인 재인쇄는 두 경로 모두 막혀 있다(`:1305`, `:1383`, 시험 `suppressAutoPrint` 2건 통과).

---

## 2. 사전 작업 (파일럿 전에 끝낼 것)

### P0 — 이게 없으면 시험 자체가 무의미 (코드 변경)

| 항목 | 내용 | 배포 |
|---|---|---|
| **P0-1 R1 티켓 지점** | 티켓 지점을 `users.branch_id` 가 아니라 **POS 가 선택한 지점**으로 발급(그 지점에 대한 사용자 접근권은 서버가 검증). 또는 임시로 판매자 `users.branch_id=6` DML — 운영 DML 이므로 **사용자 승인 필요**, 그리고 다지점 사용자의 다른 기능에 영향 → 코드 수정 권장 | api + app |
| **P0-2 R2/R3 종결 상태** | edge: `error` 를 `quarantine`(보존) 로 바꾸고 **재시도 버튼/엔드포인트**(`POST /api/edge/outbox/:uuid/retry`) 추가. 서버: 기존 `error` op 재전송 시 **재적용 시도**(멱등키 `offline:<uuid>` 가 이미 있어 판매 1건 보장). attempts 상한 도달 시 삭제가 아니라 대기 유지 + 로그 경보 | edge + api |
| **P0-3 R4 결제 중 단절 이중 판매** | 프론트가 edge 로 보낼 때 같은 `Idempotency-Key` 를 body/헤더로 싣고, edge 가 outbox payload 에 보존 → 서버가 **클라우드 원래 키로** 먼저 조회(`sale_idempotency_keys`)해 이미 생성됐으면 `duplicate` 로 응답 | app + edge + api |
| **P0-4 R5/R6 카하 귀속** | 오프라인 op 의 현금은 **캡처 시점 서랍**에 묶는다: 판매 payload 에 terminal/box 를 싣고, 동기화 때 그 box 의 열린 세션 → 없으면 `box_settlements` 구간 규칙에 맞는 처리(최소한: 조용히 건너뛰지 말고 op 를 `received`(재시도 가능)로 남기고 경보). 사용자 기준 폴백은 오프라인 경로에서 금지. 현금 환불 op 도 throw → 종결이 아니라 대기 | api |

★ P0-2·P0-4 는 「이 예외가 종결이 돼도 괜찮은가」 원칙(`offline-op-error-is-terminal-both-sides`)의 직접 적용이다. CODEX 자문 필수.
★ 각 수정은 돌연변이 대조군 포함 시험을 붙인다(R2 재적용, R4 키 충돌, R5 서랍 귀속).

### P1 — 시험 전 설정·확인 (코드 아님)

1. **워크플로 첫 실행**: `git tag edge-agent-v0.1.0 && git push origin edge-agent-v0.1.0` → Actions 성공 + 릴리스 자산 `VentaGO-Edge-Agent.zip` 존재 확인. 로컬 electron-builder 와 무관(순수 zip)하지만 **실행 이력이 0** 이므로 반드시 한 번 돌린다.
2. **R13 사전 리허설(Claude, 로컬 Mac)**: 로컬 PG 에 `ventago_edge` 생성 → edge 를 **로컬 API(5002)** 에 붙여 manifest/pull/push 를 한 바퀴. 「실행된 적 없는 코드」 층을 현장 전에 벗긴다. 리허설 항목 = 4장 매트릭스의 A·B·E 행.
3. **agentKey**: 기존 id 17 키를 재사용할지, 새로 발급할지 결정(7월 키가 어디에 남아 있는지 모름 → **새 발급 권장**: 화면 `Sucursales → Impresoras` 에서 edge 추가 후 17 은 비활성).
4. **단절 시험 시간**: 매장 영업 외 시간 또는 15분 활동 사용자 ≤5 일 때(CLAUDE.md 낮 규칙). 시험 판매는 운영 장부에 실제로 남는다.

### P2 — 파일럿 중에는 운영 규칙으로 회피 (코드 후순위)

- R8: 단절 중 **브라우저 새로고침·닫기 금지**를 현장에 공지. 시험 시작 전 POS 를 한 번 완전히 로드.
- R7: 시험 시작 직전 **재로그인**(티켓 새로 받기).
- R9·R10: 오프라인에서 F10·WhatsApp·신규 고객은 「안 되는 것」으로 문서화.
- 단일 서랍: 시험 중 branch 6 은 **서랍 하나만 열어 둔다**(R5 의 「여러 서랍 중 id DESC」 회피).

---

## 3. 설치 절차 (coolsistema 현장)

전제: POS 브라우저와 edge 와 print-agent 가 **같은 PC**(edge 는 127.0.0.1 바인딩, 프론트·print-agent 의 기본 edge URL 이 `localhost:5010`).

| 단계 | 누가 | 할 일 | 확인 |
|---|---|---|---|
| 1 | 매장 | POS PC 에 **Node 20 LTS**, **PostgreSQL 16**(설치 시 postgres 비밀번호 기록) 설치 | `node -v`, `psql --version` |
| 2 | 매장/원격 | 릴리스 zip 을 `C:\Ventago\edge-agent` 에 풀기 | 폴더에 `install.ps1`, `src\` |
| 3 | Claude(화면) | `Sucursales → coolsistema → Impresoras` 에서 edge 에이전트 추가 → apiKey 복사 | `branch_agents` 에 새 행(SELECT 확인) |
| 4 | 매장 | 관리자 PowerShell: `Set-ExecutionPolicy -Scope Process Bypass -Force; .\install.ps1` → apiKey·PG 비밀번호 입력 | 스크립트 6단계 모두 OK, `config.json` 권한 제한 |
| 5 | 매장 | 재부팅 1회 → 자동 기동 확인 | `Get-ScheduledTaskInfo -TaskName VentagoEdgeAgent` LastTaskResult 0 |
| 6 | Claude | 온라인 확인 | 운영 `SELECT id,is_online,last_seen_at FROM branch_agents WHERE agent_type='edge' AND branch_id=6;` → 최근 1분 이내 |
| 7 | 매장 | 브라우저에서 `http://localhost:5010/api/health` | `{"ok":true,"cloudOnline":true}` |
| 8 | 매장 | 미러 완료 대기(5분) → edge 로그 `[cycle#N] done` 확인 | `logs\edge-agent-YYYY-MM-DD.log`에 ERROR 없음 |
| 9 | 매장 | POS 브라우저 개발자도구 콘솔: `localStorage.setItem('ventago_offline_sales','1')` (필요 시 `localStorage.setItem('ventago_debug_offline','1')`) → **재로그인** | 콘솔 `[OfflineMode] edge ticket 갱신 — 만료 …` |
| 10 | 매장 | Chrome 에 Local Network Access 프롬프트가 뜨면 「허용」 | edge health 가 POS 에서 성공 |
| 11 | 매장 | print-agent 설정의 edgeUrl 기본값(`localhost:5010`) 유지 | print-agent 로그 attach 성공 |

---

## 4. 단절 시험 시나리오

### 4-0. 공통

- **단절 방법**: 라우터 WAN 케이블 분리(권장 — LAN 은 살아 있어야 print-agent·edge 가 통신). PC 의 Wi-Fi 끄기는 localhost 엔 무해하지만 네트워크 프린터(LAN) 가 끊기므로 쓰지 않는다.
- **시험 상품**: 저가 시험 상품 1–2종 고정, notes 에 `PRUEBA OFFLINE <행번호>` 기입.
- **시작 기록**: `T0 = now()` 를 적어 둔다 → 아래 조회에 사용.
- **현장 기록**: 각 행마다 화면의 `OFF-…` 번호, 금액, 결제수단, 종이 출력 장수.
- 단절 중 확인: edge `GET /api/offline/outbox`(티켓 필요) 또는 로그 `[sale] captured OFF-…`.

### 4-1. 시험 매트릭스

| # | 시나리오 | 기대 결과 | 합격 기준 |
|---|---|---|---|
| A1 | 단절 **전** 판매 1건(대조군, 현금) | 일반 판매, `daily_number` 있음 | sales 1행, offline_number NULL, 종이 1장 |
| A2 | 단절 → 배너 「Sin conexión」 확인 → 현금 판매 | edge 캡처, 화면 「Venta registrada sin conexión」, 티켓에 `OFF-…` | outbox +1 pending, 종이 1장 |
| A3 | 단절 중 판매 **3건 연속**(현금·tarjeta 수동·현금+tarjeta 분할) | 전부 캡처 | outbox 3행, 번호 서로 다름 |
| A4 | 단절 직후 **첫 판매**(감지 전) | 1차 요청 실패 토스트 → 감지 후 재시도는 edge | **판매 1건만** 남는다(R4 대조 — 이 시점엔 클라우드에 안 닿으므로 1건이어야 정상) |
| A5 | **결제 버튼 누른 순간** 케이블 분리(요청이 서버에 닿았을 수 있음) | P0-3 적용 전: 이중 판매 가능 / 적용 후: 1건 | 복구 후 같은 금액·시각 판매 **2건이면 불합격** |
| B1 | crédito(외상) 판매 — 단절 전 고객 선택해 둔 상태 | 캡처되고 동기화 시 외상 원장 반영 | `sales.store_client_id` 채워짐, 외상 잔액 증가 |
| B2 | 고객 지정 판매(단절 전 선택) | 캡처 | `client_id` 유지 |
| B3 | 단절 중 **신규 고객 등록** | 실패(기대) | 화면 오류만, 판매 데이터 오염 없음 |
| B4 | MP QR/Point 결제 | 불가(기대) | 결제 시작 안 됨, 부분 저장 없음 |
| C1 | 반품/cambio, **현금 환불 없음**(favor 로) | 캡처·동기화 | 음수 행·favor 반영 |
| C2 | 반품, **현금 환불 있음** | P0-4 전: 카하 없으면 종결 error 위험 → **이 행은 P0-4 후에만** | outbox done, box_operations `retiro` 1행 |
| D1 | 판매 직후 티켓 자동 인쇄(impTiq on) | edge 경유 1장 | 종이 **정확히 1장** |
| D2 | 코만다/라벨(`/print/temp`, `/print/barcode`) | edge 경유 출력 | 1장 |
| D3 | F10(Facturar) | 발급 불가(네트워크) — 화면이 깨지지 않는지 | 모달 오류 메시지, 판매는 남음, 복구 후 Pendientes 에서 수동 발급 가능 |
| E1 | 단절 중 카하 개시/마감 시도 | 불가(기대 — GET/POST 클라우드) | 화면 오류, 서랍 세션 변화 없음 |
| E2 | 10분 단절 후 **복구** | 15초 내 온라인 전환, push 20초 내 drain | outbox 전부 done, `offline_sync_ops` 전부 applied |
| E3 | 복구 후 **중복 인쇄 감시** 5분 | 아무 것도 안 나와야 함 | 추가 종이 **0장** |
| E4 | 복구 후 카하 마감 | 오프라인 현금이 마감 금액에 포함 | 4-2 ③ 합계 = 실제 서랍 현금 |
| F1 | 단절 중 edge PC 재부팅(또는 서비스 재시작) | outbox 보존, 재기동 후 manifest 복원 | 재부팅 전 캡처분 유실 0 |
| F2 | edge 프로세스 중지 상태에서 단절 | 판매 우회 안 됨(기대) — 판매 실패 표시 | **조용한 성공 표시 없음**(종이 나갔는데 장부 없음 금지) |
| F3 | 강제 오류 op(서버가 거부할 판매) 1건 | P0-2 후: quarantine + 재시도 가능 | 재시도로 applied 되거나 사람이 볼 수 있는 경보 |

★ A5·C2·F3 는 P0 수정 **전에는 돌리지 않는다**(실제 장부 오염이 예상되는 행). 수정 전 실행 시 판정은 「위험 재현」일 뿐이다.

### 4-2. 복구 후 대조 조회 (운영, SELECT 만; `:t0` 은 시험 시작 시각, `:agent` 는 새 edge id)

```sql
-- ① op 원장: 전부 applied 여야 한다
SELECT status, count(*) FROM offline_sync_ops
 WHERE agent_id = :agent AND received_at >= :t0 GROUP BY 1;

-- ② op ↔ 판매 1:1, 지점·번호·판매일 확인
SELECT o.op_uuid, o.status, o.error, o.offline_number AS op_num, o.original_at,
       s.id, s.offline_number, s.branch_id, s.terminal_id, s.sale_date, s.daily_number,
       s.total_amount, s.user_id, s.afip_status
  FROM offline_sync_ops o LEFT JOIN sales s ON s.id = o.result_id
 WHERE o.agent_id = :agent AND o.received_at >= :t0 ORDER BY o.id;

-- ③ 서랍 현금: 오프라인 현금 판매마다 box_operations 'venta' 1행, 올바른 서랍
SELECT s.id, s.offline_number, spm.amount, bo.id AS bo_id, bo.cash_register_id, cr.box_id, bo.amount
  FROM sales s
  JOIN sale_payment_methods spm ON spm.sale_id = s.id
  JOIN payment_methods pm ON pm.id = spm.payment_method_id AND pm.slug = 'efectivo'
  LEFT JOIN box_operations bo ON bo.description = 'Venta en efectivo, venta numero: #' || s.id
  LEFT JOIN cash_registers cr ON cr.id = bo.cash_register_id
 WHERE s.store_id = 6 AND s.created_at >= :t0
 ORDER BY s.id;   -- bo_id NULL 이면 R5 재현(불합격)

-- ④ 이중 판매 감시 (A5): 같은 금액이 2분 안에 2건
SELECT a.id, b.id, a.total_amount, a.sale_date, b.sale_date
  FROM sales a JOIN sales b ON a.store_id = b.store_id AND a.id < b.id
   AND a.total_amount = b.total_amount
   AND abs(extract(epoch FROM a.sale_date - b.sale_date)) < 120
 WHERE a.store_id = 6 AND a.created_at >= :t0;

-- ⑤ 재고 원장 불변식 (0행이어야 함)
SELECT * FROM v_stock_balance_drift;
SELECT * FROM v_stock_tenant_leak;
SELECT st.product_branch_id, sum(st.stock) FROM stocks st
  JOIN "ProductBranch" pb ON pb.id = st.product_branch_id
 WHERE pb.branch_id = 6 AND st.created_at >= :t0 GROUP BY 1;

-- ⑥ 멱등키
SELECT idempotency_key, status, sale_id FROM sale_idempotency_keys
 WHERE store_id = 6 AND created_at >= :t0 ORDER BY id;
```

edge 로컬(지점 PC):
```sql
SELECT status, count(*) FROM offline_outbox GROUP BY 1;                 -- 전부 done
SELECT seq, uuid, offline_number, status, attempts, last_error
  FROM offline_outbox WHERE status <> 'done' ORDER BY seq;              -- 0행
```

**전체 합격** = ① 전부 applied · ② 1:1 · ③ bo_id NULL 0행 · ④ 0행 · ⑤ 불변식 0행 · edge outbox 미완료 0행 · 종이 장수 = 판매 수(재인쇄 제외).

---

## 5. 롤백 / 안전장치

| 상황 | 조치 |
|---|---|
| 오프라인 판매 우회를 즉시 끄기 | POS 브라우저: `localStorage.removeItem('ventago_offline_sales')` → 판매는 우회 안 되고 실패로 보인다(조용한 성공 없음). 인쇄 우회는 플래그와 무관하므로 edge 를 멈춘다 |
| edge 정지 | `Stop-ScheduledTask -TaskName VentagoEdgeAgent` (+ `Disable-ScheduledTask`) |
| 서버측 차단 | edge 에이전트 행 비활성/삭제 → manifest·push 가 401, 티켓 404 (화면 조작, 승인 불필요 범위인지 사용자 확인) |
| outbox 가 `error` 로 굳음 (P0-2 전) | **삭제 금지.** `offline_outbox` 행의 payload 를 꺼내 보존 → 원인 수정 후 `UPDATE offline_outbox SET status='pending', attempts=0 WHERE uuid=…` (edge 로컬). 서버 `offline_sync_ops.status='error'` 행은 그대로 두면 재전송이 같은 오류를 돌려받으므로, 서버 쪽 `status='received'` 로 되돌리는 **운영 DML 은 사용자 승인 후** |
| 이중 판매 발생 | 운영 판매 취소(anular) 절차로 1건 취소 — 사람이 판단. 자동 삭제 없음 |
| 서랍 불일치 | E4 마감 전 ③ 조회로 확인, 누락분은 카하 수동 입금으로 보정(사유 기재) |
| 시험 데이터 | 지우지 않는다(`keep-test-artifacts`). notes `PRUEBA OFFLINE` 로 식별 |

---

## 6. 일정 · 역할 · 질문

### 6-1. 일정(안)

| 단계 | 내용 | 담당 | 예상 |
|---|---|---|---|
| D0 | 사용자 질문 답변 수령(6-3) | 사용자 | — |
| D1 | P0-1~P0-4 구현 + 시험 + CODEX 자문, 밤 배포(api·app·edge 태그) | Claude | 1–2일 |
| D1 | P1-2 로컬 리허설(매트릭스 A·B·E·F1) | Claude | 반나절 |
| D2 | 현장 설치(3장 1–11) | 매장 + Claude 원격 확인 | 1시간 |
| D2 | 24시간 온라인 관찰(자동 기동·미러·last_seen) | Claude | — |
| D3 | 단절 시험(4장), 영업 외 시간 | 매장(케이블·판매·종이 세기) + Claude(조회·판정) | 1–2시간 |
| D3 | 결과 보고서 + 다음 단계(B 웨이브: 오프라인 GET, 신선도 게이트) 판단 | Claude | — |

### 6-2. 역할

- **Claude**: 코드 수정·시험·배포, 에이전트 등록 화면 조작, 운영 SELECT 대조, 판정·보고. 운영 DML/DDL·서비스 재시작은 승인 후.
- **매장/사용자**: Node·PG 설치, install.ps1 실행(관리자 권한), 케이블 분리/연결, 실제 판매 입력, 종이 장수 기록, 브라우저 콘솔 플래그 설정.

### 6-3. 시작 전에 사용자에게 물을 것

1. coolsistema 의 **POS PC OS**(Windows 버전?) 와 사양(RAM — 로컬 PostgreSQL 이 상주한다). Mac 이면 install.ps1 대신 수동 설치 + launchd.
2. **POS 를 돌리는 PC 가 몇 대**인가, 그중 어느 PC 에 edge 를 둘 것인가. (edge 는 지점당 1대, 기본 127.0.0.1 바인딩 — 다른 PC 의 POS 는 `EDGE_BIND_HOST=0.0.0.0` + `ventago_edge_url` 설정이 필요하고 LAN 노출이 생긴다.)
3. 그 PC 에 붙은 **프린터**는 어느 에이전트인가(thermal 27 「comandera Sala」 / 5 「PB comandera」?), USB 인가 네트워크인가.
4. 시험 판매자 계정: israel(branch_id NULL)·admin(branch 16) 중 누구로 할지 — **R1 때문에 P0-1 없이는 둘 다 안 된다.** 임시로 `users.branch_id=6` 을 바꾸는 쪽을 원하는지, 코드 수정을 원하는지.
5. 기존 edge 에이전트(id 17) 키를 버리고 **새로 발급**해도 되는지.
6. 단절 시험 **날짜·시간대**(영업 외 권장)와 현장에서 케이블을 뽑을 사람.
7. 시험 판매(운영 장부에 남음)를 그대로 둘지, 시험 후 anular 할지.
8. P0 4건을 모두 하고 시험할지, **P0-1 만 하고 A·B·D·E 행부터** 먼저 볼지(A5·C2·F3 는 P0 전엔 제외).
