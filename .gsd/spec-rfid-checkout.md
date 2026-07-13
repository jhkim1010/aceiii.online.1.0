# SPEC: RFID 계산대 빠른 스캔 파일럿 (C 트랙 / Phase 56 잠정)

생성일: 2026-07-13
작성: GSD Plan 단계
상태: **승인 대기** (승인 후 Execute)

## 목표

계산대에서 바구니에 담긴 상품을 UHF RFID로 **한 번에 읽어** POS(nueva-venta) 카트에 자동 투입한다. 상품 태그는 Zebra RFID 프린터-엔코더로 발행(ZPL `^RFW`)하며, 리더가 읽은 EPC는 서버에서 **배치 단일 쿼리**로 상품 해석해 pool 낭비 없이 처리한다.

## 배경 및 컨텍스트

기존 하드웨어 연동 패턴을 그대로 재사용한다.
- **에이전트 패턴**: `zebra-agent`(Electron) → Socket.IO `/print-agent` 네임스페이스 → API Key(`branch_agents`) 인증 → 서버가 이벤트 push / 에이전트가 `emitWithAck`로 조회. (`api-ventago/src/app/print/print.gateway.ts`, 410줄)
- **게이트웨이 기존 핸들러**: `agent_online`, `print_ack`, `get_price_types`, `get_branches`, `get_stock_today`, `search_products`, `get_qr_pending`, `mark_qr_printed`. → 여기에 `rfid_scan` 추가.
- **에이전트 타입**: `branch_agents.agentType` = `STRING(20)` default `'thermal'`, 현재 `'thermal'|'zebra'`. → `'rfid'` 값 추가(스키마 변경 불필요).
- **터미널 매핑**: `terminals.thermalAgentId`, `terminals.zebraAgentId` FK 존재. → `rfidAgentId` FK 추가(마이그레이션).
- **상품 식별**: `products.sku` (unique per `store_id`). EPC는 `product_id`로 매핑.
- **프론트 소켓 훅 선례**: `useSuspendedSaleSocket`, `useMpApprovedSocket`, `useThermalAgentStatus` (`ventago-app/src/views/homes/hook/`). → `useRfidScanSocket` 동일 패턴.
- **판매 생성**: `SalesCreateService.create(createSaleDto)` (`sales-create.service.ts`). RFID는 카트 투입까지만 담당하고 결제/판매 생성은 기존 흐름 그대로.
- **캐시**: `MemoryCacheService` (`src/common/cache/memory-cache.service.ts`), TTL 캐시 사용 가능.
- **로그 점검**: `logs/error-2026-07-11.log` 비어 있음(에러 없음). `combined-2026-07-11.log` pool 정상(size=2, using=0%, max=80).

## 기술 스택

- 백엔드: NestJS 11 + Sequelize(PostgreSQL 18, pgbouncer transaction pooling)
- 프론트: Next.js 13(Pages Router) + Redux + Socket.io-client
- 에이전트: Electron 28 + socket.io-client
- 하드웨어(신규): UHF RFID 리더(고정), RFID 프린터-엔코더
- ESLint: 프로젝트 설정 존재(Warning=에러). newline-before-return / lines-around-comment 규칙 준수 필수.

## Pool 현황 (반드시 준수)

- 현재: `min=2, max=80`(앱→pgbouncer 클라이언트 상한). 백엔드는 pgbouncer `pool_size=50`으로 캡, PG `max_connections=100`.
- **RFID 위험**: 고정 리더는 초당 수백 태그를 뿜을 수 있음. → **태그 1건 = 쿼리 1건 절대 금지.**
- 규칙: (1) 에이전트가 dedup/디바운스로 배치 전송, (2) 서버는 `WHERE epc = ANY($1::text[])` 단일 쿼리로 커넥션 1개만 사용, (3) 핫 EPC는 `MemoryCacheService` 60초 TTL 캐시.

---

## 하드웨어 권장안 (리더 미정 → 조사 반영)

**태그 발행(프린터-엔코더)**: **Zebra ZD621R** (4" 데스크톱, ZPL `^RFW` UHF 인코딩 지원). 기존 Zebra/ZPL 생태계와 1:1 정합 — `zebra-agent`의 ZPL 파이프라인을 그대로 확장. (대량/산업용은 ZT411R.)

**계산대 고정 리더 1차 후보**: **Zebra FX9600**(LLRP over TCP, 견고·검증됨) + **근접/차폐 안테나**.
- ★계산대 핵심 요건 = **read-zone 국한**. 옆 계산대·통로 상품 오독을 막기 위해 차폐 안테나 또는 RFID 리드 패드(near-field) 필수.
- 대안: Zebra FXR90(신형 고정형).
- **최종 선정은 실기 데모로 오독률(false read) 검증 후 확정** — 검증 전 벤더 확정 금지(사용자 "검증된 방법 우선" 원칙).

---

## 태스크 목록

### Wave 0 — 게이트 (하드웨어)
- [ ] **TASK-0 (GATE)**: 계산대 리더 데모기 + ZD621R 확보 → 실기 read-zone/오독률 검증. **통과 전 리더 LLRP 실드라이버(TASK-10 LLRP부) 착수 금지.** 소프트웨어는 mock 드라이버로 선행 개발.

### Wave 1 — 서버 기반 (DB + 해석)
- [ ] TASK-1: 마이그레이션 `product_epc` 테이블 — `id`, `epc`(unique, text), `product_id`(FK→products), `sale_item_id`(nullable FK), `store_id`(FK), `status`(activo/anulado), `issued_at`. 끝에 owner+시퀀스 `coolsistema` 이전 DO 블록. — 파일: `api-ventago/migrations/56xx-create-product-epc.sql`
- [ ] TASK-2: 마이그레이션 `terminals.rfid_agent_id` FK(nullable) → `branch_agents`. — 파일: `api-ventago/migrations/56xx-terminal-rfid-agent.sql`
- [ ] TASK-3: EPC 인코딩 스킴 순수 모듈 `epc-scheme.ts` (store prefix + product_id + serial → 96bit hex, SGTIN 유사). + 유닛테스트. — 파일: `api-ventago/src/app/print/epc/epc-scheme.ts`
- [ ] TASK-4: `ProductEpc` 모델 + `rfid.service.ts` — `resolveEpcs(epcs[])`(배치 `ANY` 단일 쿼리, 60s 캐시), `issueEpcs(items)`(EPC 생성+upsert). **pool 안전 패턴 준수.** — 파일: `api-ventago/src/app/print/product-epc.model.ts`, `rfid.service.ts`

### Wave 2 — 게이트웨이 + 발행 플로우
- [ ] TASK-5: `print.gateway.ts` — `@SubscribeMessage('rfid_scan')`: `{epcs}` 수신 → `resolveEpcs` 배치 → 해당 터미널 room 에 `rfid_cart_items` emit. `agentType 'rfid'` 인증 허용. — 파일: `print.gateway.ts`
- [ ] TASK-6: 태그 발행 — 서버가 EPC 생성/upsert(`issueEpcs`) 후 zebra/rfid 프린터 에이전트로 `epcHex` 포함 print 페이로드 전송(EPC 권한 서버 집중, 중복 방지). — 파일: `print.service.ts`

### Wave 3 — 발행 에이전트(zebra-agent 확장)
- [ ] TASK-7: `zpl-formatter.js` — `^RFW,H` EPC write 블록 추가(`formatRfidLabel` 또는 rfid 플래그) + 유닛테스트. — 파일: `zebra-agent/src/zpl-formatter.js`
- [ ] TASK-8: `zebra-agent/main.js` — print 핸들러가 `epcHex` 수신 시 인코딩 포함 출력. — 파일: `zebra-agent/main.js`

### Wave 4 — 리더 에이전트(신규 rfid-agent)
- [ ] TASK-9: `rfid-agent` 스캐폴드(zebra-agent 복제) — 소켓/API Key 인증/트레이/셋업 마법사. — 폴더: `rfid-agent/`
- [ ] TASK-10: `reader-driver.js` 인터페이스 + **mock 드라이버(개발용)** + LLRP 드라이버(TASK-0 통과 후). EPC dedup/디바운스(예: 500ms 윈도우, unique set) 후 배치. — 파일: `rfid-agent/src/reader-driver.js`
- [ ] TASK-11: `rfid_scan` emit(배치, 지점/터미널 컨텍스트는 서버가 API Key로 도출). — 파일: `rfid-agent/main.js`

### Wave 5 — 프론트(POS 투입)
- [ ] TASK-12: `useRfidScanSocket` 훅 — `rfid_cart_items` 수신(기존 훅 패턴). — 파일: `ventago-app/src/views/homes/hook/useRfidScanSocket.ts`
- [ ] TASK-13: nueva-venta 뷰 — 수신 상품 카트 투입 + **미등록 EPC 처리 UX**(무시/경고). — 파일: `ventago-app/src/views/nueva-venta/*`
- [ ] TASK-14: 터미널-RFID에이전트 매핑 UI(`sucursales/[id]/impresora` 확장). — 파일: 해당 페이지

### Wave 6 — 검증
- [ ] TASK-15: ESLint 실행(api + app) 오류 0개
- [ ] TASK-16: PostgreSQL pool 안전 점검 — `rfid_scan` 배치 쿼리 확인, per-tag 쿼리 없음, `release()`/`pool.query` 준수, 캐시 TTL 동작
- [ ] TASK-17: E2E 스모크(mock reader → rfid_scan → resolve → 카트 투입) + 로그 확인

## 완료 기준

- ESLint 오류 0개 (api-ventago + ventago-app)
- `rfid_scan` 처리가 태그 수와 무관하게 **배치당 커넥션 1개**만 사용(부하 테스트로 pool 로그 확인)
- mock reader로 E2E: 스캔 → 해석 → nueva-venta 카트 자동 투입 성공
- 마이그레이션 로컬(5432)·운영(5434) 동시 적용 + owner=coolsistema 확인
- 미등록 EPC가 계산 흐름을 막지 않음(graceful)

## 금지사항 / 주의사항

- 태그 1건마다 DB 쿼리 금지 — 반드시 배치.
- 마이그레이션 한쪽만 적용 금지(로컬/운영 동시). 신규 테이블 owner+시퀀스 coolsistema 필수.
- 기존 `/print-agent` 인증·재연결 로직 회귀 주의(zebra/thermal 에이전트 영향 없어야 함).
- 판매 생성/결제 로직은 이번 범위 밖 — 카트 투입까지만.
- TASK-0(하드웨어 오독률 검증) 통과 전 LLRP 실드라이버 확정 금지.
- ESLint: `newline-before-return`, `lines-around-comment` 준수.

## 실행 순서 권장

TASK-0(하드웨어 발주/데모)를 **병행**하면서, 소프트웨어는 Wave 1→2 + mock reader(TASK-10 mock)로 E2E를 먼저 완성 → 하드웨어 도착 시 LLRP 드라이버·ZD621R 인코딩만 결합. (하드웨어 대기시간 낭비 방지)
