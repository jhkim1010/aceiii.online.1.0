# SPEC: Phase 58 — 오프라인-퍼스트 POS (Modo Sin Conexión)
생성일: 2026-07-20
상태: EXECUTE (Wave A 진행 중) — 브랜치: api-ventago `feature/phase58-offline-sync`

## 확정된 결정 (2026-07-20 사용자 승인)
- 로컬 DB: **PostgreSQL 설치형** (지점 PC)
- 파일럿: **coolsistema 매장 (store 6)**
- 작업 브랜치: api-ventago `feature/phase58-offline-sync` (main 직접 작업 금지)

## 스키마 실측 결과 (TASK-2 감사 — 로컬 5432 확인)
- 대상 테이블 전부 `updated_at` 보유 → 증분 커서 가능. `deleted_at` 은 product_promotions 만 보유
  → hard delete 전파는 `GET /offline-sync/ids` prune 방식으로 해결 (마이그레이션 불필요, TASK-2 스코프 축소)
- 실제 테이블명: `"ProductBranch"`(대소문자 quoted), `boxes`, `user_roles`, `role_functions`,
  `role_function_actions`, `product_promotions`
- `stocks` 는 절대값이 아니라 **이벤트 원장** (SUM=현재고) → 스냅샷+델타 설계와 정합
- `sync_outbox`/`product_sync` 테이블은 WooCommerce 채널 동기화가 선점 →
  본 기능 네임스페이스는 **`offline-sync`** / 로컬 outbox 는 **`offline_outbox`**

## 목표
인터넷 단절 시에도 지점(sucursal)에서 판매·금전함 운영을 지속하고, 회선 복구 시
백그라운드로 운영서버(PG18:5434)와 자동 정합(sync)하는 오프라인-퍼스트 아키텍처 구축.

## 결론 먼저: 가능한가?
**가능하다.** 소매 POS에서 검증된 패턴(Local-first + Outbox + Idempotent Sync)이며,
Ventago 는 이미 유리한 조건을 갖추고 있다:
- print-agent/zebra-agent 로 "지점 PC에 상주 프로그램 배포" 경험과 CI가 이미 있음
- 판매는 append-only 데이터라 충돌(conflict)이 본질적으로 적음
- 참조데이터는 SWR 훅으로 이미 추상화되어 있어 소스 전환이 쉬움

단, 스키마 확인으로 확정된 제약 1개:
**모든 PK가 integer sequence** (products, sales, sale_items, clients, users 등 전부) →
오프라인에서 로컬이 integer id 를 발급하면 서버와 100% 충돌한다.
따라서 "오프라인 생성 데이터는 UUID 비즈니스 키로 식별, 서버 id는 동기화 시 매핑"이 설계의 핵심.

---

## 핵심 개념 (아키텍처)

### 1. Edge Sync Agent (지점당 1대) — 새 워크스페이스 `edge-agent/`
print-agent 와 같은 방식으로 지점 PC에 설치되는 상주 프로그램.
- 구성: NestJS 경량 서버(포트 5010) + 로컬 PostgreSQL (또는 임베디드 PG)
- 역할 3가지:
  a) **Pull 동기화**: 온라인일 때 참조데이터를 주기적으로 로컬 PG에 내려받음
  b) **오프라인 API**: 단절 시 프론트엔드의 판매/조회 요청을 로컬에서 처리
  c) **Push 동기화**: 복구 시 outbox 를 순서대로 운영서버에 업로드
- 인증: branch_agents 테이블 재사용 (agentType: 'edge' 추가) — 기존 API Key 체계 그대로

### 2. 항상-로컬 아님, "Failover 프록시" 모드 (권장)
프론트엔드(api.service.ts)는 평소 그대로 클라우드 API 사용.
- 헬스체크(5초 간격 or 요청 실패 시)로 클라우드 불가 감지 → baseURL 을
  `http://localhost:5010/api` (edge-agent)로 전환 + 화면에 "MODO SIN CONEXIÓN" 배지
- 복구 감지 → 클라우드로 복귀. 전환 로직은 api.service.ts 한 곳에만 존재
- 대안(항상 edge 경유 프록시)은 단순하지만 edge 미설치 매장이 죽는 단일장애점이 됨 → 기각

### 3. Pull 동기화 (참조데이터, 서버→로컬)
대상: products(+categorías/sizes/colors/price_types/precios), stocks(해당 지점),
clients, users(vendedores)+roles+permissions, payment_methods, promotions, terminals/box.
- 방식: 증분 동기화 — 각 테이블 `updated_at > last_sync_at` (+ soft-delete 전파용 `deleted_at`)
- 백엔드에 `GET /sync/pull?tables=...&since=...` 엔드포인트 1개 (배치, 페이지네이션)
- 주기: 참조데이터 5분, 재고 1분. 최초 설치 시 풀 스냅샷
- 충돌 규칙: **참조데이터는 무조건 서버 승리** (로컬에서 수정 불가 — 읽기 전용)

### 4. 오프라인 쓰기 (로컬→서버) — Outbox 패턴
오프라인 허용 쓰기 작업(화이트리스트):
- 판매 생성 (sales + sale_items + pagos)
- 판매 보류/재개 (ventas_suspendidas)
- 금전함 이동 (apertura/cierre/movimientos)
- 신규 고객 등록 (clientes)
- 코만다/라벨 출력 (로컬 print-agent 직결 — 원래 로컬이라 무변경)

금지 작업(오프라인 불가, UI 비활성): 가격 변경, 상품 등록/수정, 사용자/권한 변경,
환불(refund), 타 지점 재고 조회 — 정합성 위험이 커서 온라인 전용.

메커니즘:
- 로컬 PG에 `sync_outbox(seq BIGSERIAL, op_type, payload JSONB, uuid, created_at, status)`
- 모든 오프라인 문서에 **UUID 발급** (`sale_uuid` 등) — integer PK 충돌 원천 차단
- 영수증 번호: 오프라인 전용 시리즈 `OFF-{terminalId}-{seq}` 로 발급(법정 연번 충돌 방지),
  동기화 후 서버가 정식 번호 부여 → 매핑 보존

### 5. 복구 시 정합 (Reconciliation)
- edge-agent 가 온라인 감지 → outbox 를 **seq 순서대로** `POST /sync/push` (배치)
- 서버는 uuid 로 **멱등 처리** (이미 있으면 skip) → 네트워크 재시도에 안전
- 서버가 정식 integer id 발급 → 응답으로 `uuid↔server_id` 매핑 반환, 로컬에 기록
- 재고: 오프라인 판매를 서버가 이벤트로 재적용 (음수 재고 허용 + 경고 리포트)
- 고객 중복: CUIT 기준 서버에서 병합, 매핑 반환
- 완료 후 pull 재실행으로 로컬 최신화 → "동기화 완료" 알림

### 6. 오프라인 인증/보안
현행 세션 보안(active_sessions UNIQUE, SessionGuard)은 온라인 전제 → 오프라인 모드 규칙:
- 로그인 상태에서 단절: 기존 JWT+sessionToken 을 로컬에서 유효 취급 (edge 가 서명 검증만)
- 단절 중 재로그인: 마지막 pull 된 users의 bcrypt 해시로 로컬 검증, 오프라인 세션 발급
- 복구 시: 오프라인 세션 무효화 → 정상 온라인 재로그인 강제 (중복로그인 차단 체계 복원)

---

## 기술 스택
- edge-agent: NestJS 11 + Sequelize (api-ventago 모듈 서브셋 재사용) / Electron 래핑 또는 pkg 바이너리
- 로컬 DB: PostgreSQL 16+ (설치형) — 로컬 pool: max 5, idleTimeoutMillis 30000 (지점 PC 사양 고려)
- 운영서버 sync 엔드포인트: api-ventago 에 SyncModule 추가 — **기존 pool(max 80) 공유, 추가 pool 생성 금지**
- 프론트: api.service.ts failover + 오프라인 배지 + 동기화 상태 위젯

## 태스크 목록 (Wave 분할 — 단계별 출시)
### Wave A: 읽기 오프라인 (위험도 최소, 즉시 가치) — ★2026-07-20 완료
- [x] TASK-1: 백엔드 OfflineSyncModule — manifest/pull/ids (api-ventago 73ca3a2)
- [x] TASK-2: updated_at 감사 완료 — 전 테이블 보유, 마이그레이션 불필요 (ids prune 방식 채택)
- [x] TASK-3: edge-agent (Node+pg+express, JSONB 미러, 파일 로거) — 샌드박스 E2E 통과:
      오프라인 기동→복구 자동감지→즉시 pull→미러 반영→증분 커서→재단절 감지
- [x] TASK-4: 프론트 offline-mode.service + OfflineBanner + api.service 네트워크 오류 신고/배너 억제

### 멀티매장/장기 단절 시나리오 검토 (사용자 질문 반영)
2개 매장 중 1곳만 하루 종일 오프라인 → 복구 시나리오는 **안전**하다:
매장 간 데이터는 store_id 로 격리되고, 오프라인 판매는 UUID append-only 라 온라인 매장과 충돌 없음.
단, 다음 3개 보완 태스크가 필요하다:
- [ ] TASK-B0: **print/zebra-agent 로컬 failover** — 두 에이전트는 운영서버 Socket.io 에 고정 접속하므로
      단절 시 코만다/라벨 출력이 끊긴다. 클라우드 소켓 disconnect 시 edge-agent(LAN)로 재접속하는
      2차 연결 로직 추가 (SERVER_URL fallback). edge 는 /print-agent 네임스페이스를 동일 계약으로 제공.
- [ ] TASK-B1: push 시 **원본 시각 보존** — 오프라인 판매/caja 이벤트는 다음날 동기화돼도
      created_at/operation_date 를 원래 발생 시각으로 기록 (일자별 리포트 정합).
- [ ] TASK-B2: 장기 단절 리스크 리포트 — 단절 중 클라우드에서 발생한 같은 지점의 변화
      (ecommerce 주문 재고 차감, 가격 변경)와의 괴리를 동기화 완료 리포트에 명시.
      (선택) 지점 오프라인 감지 시 해당 지점 ecommerce 재고 sync 일시정지.

### Wave B: 오프라인 판매 — ★코어 파이프라인 완료 (2026-07-20)
- [x] TASK-5(개정): sales 테이블 무변경 설계 채택 — 멱등성/매핑은 신규 `offline_sync_ops`
      원장이 전담 (migrations/phase58-offline-sync-ops.sql).
      ⚠ 로컬 5432 적용 잔여(MCP 읽기전용): `psql -d ventago -f api-ventago/migrations/phase58-offline-sync-ops.sql`
      ⚠ 운영 5434 적용은 승인 게이트 (ALTER OWNER coolsistema 포함)
- [x] TASK-6: edge POST /api/offline/sales — CreateSaleDto 동일 body, OFF-{branch}-{seq} 발급,
      offline_outbox 기록, 미러재고 best-effort 차감, manifest 영속(오프라인 재기동 branch 유지)
- [x] TASK-7: 서버 POST /offline-sync/push — offline_sync_ops 착지→uuid 멱등→
      SalesCreateService 재사용(saleDate=원본시각 → TASK-B1 충족), per-op 실패 격리
- [x] push-worker: 20s drain + 복구 즉시 drain + attempts 백오프(8회) + 결과 매핑 저장
- [x] 프론트: 오프라인+edge+플래그(ventago_offline_sales='1') 시 POST /sales → edge 우회 (파일럿 게이트)
- [ ] TASK-8: 오프라인 인증 강화 — 현재 JWT payload 힌트 수준(서명검증 없음, LAN 한정).
      bcrypt 로컬 로그인 + HMAC 은 Wave B2
- E2E(샌드박스): 오프라인 판매 2건 캡처→복구 자동 push(9001/9002)→멱등 재전송(dup, 동일 id)→
      온라인 즉시 push(9003)→무신원 거부→오프라인 재기동 manifest 복원(OFF-1-x) 전부 통과

### Wave C: 금전함 + 고객 + 운영도구
- [ ] TASK-9: caja 오프라인 (apertura/cierre/movimientos outbox)
- [ ] TASK-10: 오프라인 고객 등록 + CUIT 병합
- [ ] TASK-11: 동기화 대시보드 (pendientes, 마지막 sync, 충돌 리포트)
- [ ] TASK-12: ESLint 전체 검증 + pool 안전 점검 (edge/서버 양쪽)

## 완료 기준
- 랜선 뽑고 판매 5건 → 복구 → 운영서버에 5건 정확히 반영, 중복 0, 재고 일치
- 동기화 중 앱 강제종료 후 재시작해도 중복 전송 없음 (멱등성)
- ESLint 오류 0개, pool: 모든 connect 에 finally release, edge pool max 5

## 금지사항 / 주의사항
- 마이그레이션은 **로컬 5432 + 운영 5434 동시 적용** (owner→coolsistema DO 블록 포함)
- 운영 API 에 새 Pool 생성 금지 — 기존 database.module.ts pool 공유
- sales 테이블에 branch_id 없음 — 지점 판정은 user_id→users.branch_id 경유 (스키마 reference 준수)
- 오프라인 화이트리스트 외 쓰기 작업은 UI에서 명시적으로 차단
- Wave A 를 운영 1개 지점(파일럿)에서 검증 후 B 진행 — 한 번에 전체 출시 금지

## 빠지기 쉬운 함정 3가지
1. integer PK 를 로컬에서 발급해 동기화 시 충돌 → 반드시 UUID 비즈니스 키
2. 재고를 로컬에서 절대값으로 덮어쓰기 → 반드시 델타(판매 이벤트) 재적용 방식
3. 시계 어긋난 지점 PC의 updated_at 비교 실패 → since 는 서버가 준 커서 토큰 사용

## 점검 포인트
- 1주: Wave A 파일럿 지점에서 pull 정합률/트래픽 측정 (pull 배치가 pool 점유 <1s 인지)
- 1개월: Wave B 실단절 리허설 (영업시간 외 랜선 분리 테스트)
- 3개월: 전 지점 배포 + 오프라인 판매 비율/충돌 리포트 리뷰
