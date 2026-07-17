# SPEC: Revendedor 보안 체인 (Chain of Trust) — NFC 뱃지 possession factor + Companion-Device 승인

생성일: 2026-07-17
작성: GSD Plan 단계 (Execute 미착수 — 승인 대기)

## 목표

Revendedor(재판매자)에게 물리 NFC 뱃지(NTAG 424 DNA)를 발급하여, **뱃지 없이는 보호 기능(구매 등)을 쓸 수 없게** 하는 다층 보안 체인을 구축한다. 노트북·아이패드(NFC 미탑재)는 **폰이 뱃지를 읽어 서버를 통해 세션을 개방**하는 companion-device 승인으로 해결한다. 전 과정 pool 무부담(possession 검증은 stateless JWT claim, nonce는 MemoryCacheService in-memory).

## 배경 및 컨텍스트 (코드 확인 결과)

### 현재 Revendedor 인증 (분석 완료)
- `revendedor.model.ts` (테이블 `revendedores`): store 소속 없음, `document`(DNI/CUIT)·`email`·`password`(bcrypt)·`isActive`. 크로스 매장 브라우징 구조.
- `revendedor-jwt.strategy.ts`: **완전 stateless JWT** (`revendedor-jwt` 전략, payload `{id, type:'revendedor'}`). `validate()`에서 `isActive`만 확인. **세션/기기 바인딩 없음** → 뱃지 체인은 깨끗한 신규 추가.
- `RevendedorAuthGuard` = `AuthGuard('revendedor-jwt')` 단순 래퍼.

### 재사용할 기존 자산 (신규 개발 최소화)
- **MemoryCacheService** (`src/common/cache/memory-cache.service.ts`): `get<T>(key)` / `set(key, value, ttlMs)` / `del(key)` / `delByPrefix(prefix)`. nonce 저장에 그대로 사용 → **DB 0회**.
- **WebSocket 게이트웨이 패턴** (`print.gateway.ts`): `@WebSocketGateway({namespace, cors: wsCorsOptions})`, handshake auth, `SocketRateLimiter`(브루트포스 방어), Winston Logger, room(`client.join`), 중복소켓 last-wins. 이 패턴을 `/revendedor` 네임스페이스로 미러링.
- **세션 보안 참고** (`session/`): `active_sessions`·`terminal_devices`·`branch_ip_registries` + `SessionGuard`(x-session-token). Revendedor 판은 이보다 가볍게(stateless) 간다.
- Sequelize `underscored: true` → 모델 camelCase = DB snake_case 자동 매핑.

### Pool 현황 (database.module.ts 확인)
- `min=2, max=80`, pgbouncer(pool_size=50) 경유, `acquire=15000`, `idle=10000`. 부팅 로그 `using=0(0%)` 정상. → **본 기능은 tap당 인덱스 조회 1~2회 + 카운터 update 1회만 발생**하도록 설계.

### ★ 로그 점검 결과 (반드시 반영)
- `error-2026-07-17.log`: `[Scheduler] schema "reseller" does not exist` — reseller 스키마 참조 스케줄러가 이미 존재(별건). 본 작업과 무관하나, 신규 테이블은 `reseller` 스키마가 아닌 **public 스키마**에 만든다(혼동 방지).
- `error-2026-07-16.log`: 로컬 5432 스키마 드리프트 잔존(`is_warehouse`·`store_notices`·`Product.serial`). → **본 마이그레이션은 로컬(5432)·운영(5434) 동시 적용 규칙을 엄수**(CLAUDE.md 「DB 마이그레이션 적용 규칙」). 한쪽만 적용 금지.

## 보안 체인 아키텍처 (Chain of Trust — fail-closed)

Revendedor가 보호 기능에 도달하려면 **모든 링크가 성립**해야 한다. 한 링크라도 끊기면 차단.

| # | 링크 | factor | 상태 | 검증 위치 |
|---|------|--------|------|-----------|
| L1 | 비밀번호(document/email + pw) | 아는 것 | 기존 | revendedor-jwt |
| L2 | 물리 NFC 뱃지(NTAG 424 DNA, 암호 SUN 서명) | 가진 것 | **신규** | badge/authorize |
| L3 | 뱃지를 읽는 폰이 등록된 기기 | 신뢰 기기 | **신규(Phase 2)** | revendedor_devices |
| L4 | 폰이 데스크톱 세션을 QR nonce로 개방 | 동반 승인 | **신규** | Socket.io + nonce |
| L5 | possession 인증 TTL(교대/N시간) | 시간 | **신규** | JWT `badge_exp` |
| L6 | 서버의 즉시 폐기 권한(분실/해고) | 폐기 | **신규** | badge.status |

### 핵심 흐름 (companion-device, stateless·pool-free)

```
[데스크톱/아이패드 웹]                    [서버]                      [폰 = NFC 리더]
 1. 비번 로그인(L1) → 미승격 JWT
 2. /revendedor 소켓 연결 → nonce 발급 ──▶ MemoryCache.set(
    QR 표시(nonce 인코딩)                    `rev:qr:${nonce}`,
                                            {socketId, revendedorId, ttl 120s})
                                                                    3. 뱃지 탭 → NTAG 424 DNA
                                                                       SUN(uid+ctr+CMAC) 읽기
                                                                    4. QR 스캔(nonce)
                                            ◀── POST /revendedor/badge/authorize
                                                { nonce, sun } + 폰 JWT(Bearer)
 5. verify:
    - SUN CMAC 검증(마스터키→UID 다이버시파이 per-tag 키)
    - read_ctr > last_read_ctr (리플레이 차단) → update
    - badge.status='active'
    - badge.revendedor_id == nonce.revendedorId == 폰 JWT.id  (3자 일치)
    - nonce 유효·미만료·미사용 → 즉시 del(1회용)
 6. 승격 JWT 발급(badge_verified=true, badge_exp=+Nh)
 7. Socket emit(nonce.socketId, 'badge_authorized', {token}) ─────▶
 8. 데스크톱: 승격 JWT 저장 → 잠금 해제 ◀──
```

- **L2 뱃지 검증**: NTAG 424 DNA의 SDM/SUN(Secure Unique NFC). tap마다 read counter 증가 + AES-CMAC 서명 → **복제 불가**. 서버는 마스터키에서 UID로 per-tag 키를 다이버시파이(NXP AN12196)하여 CMAC 검증. **DB에는 키를 저장하지 않음**(uid·last_read_ctr·status만).
- **pool 안전**: possession 상태를 JWT claim에 실어 stateless로 → 보호 API 매 호출마다 DB 조회 0. tap 1회당 DB는 badge 조회 1 + counter update 1뿐. nonce는 전부 in-memory.
- **멀티인스턴스 주의**: 2인스턴스 복귀 시 (a) nonce in-memory·(b) Socket.io emit이 인스턴스 로컬. → **금지사항**에 sticky session 또는 Redis 어댑터 필요 명시(현 단계는 단일 인스턴스 가정, 실운영 전 결정).

## 기술 스택
- 백엔드: NestJS 11 + Sequelize(`underscored:true`) + Socket.io + MemoryCacheService
- DB: PostgreSQL 18 (로컬 5432 / 운영 5434) — 신규 테이블 2개
- NFC 암호: NXP NTAG 424 DNA SDM/SUN, AES-128 CMAC, 키 다이버시피케이션(마스터키는 env/secret store)
- 모바일: Flutter(revendedor 앱) — `nfc_manager`(NFC 읽기) + `mobile_scanner`(QR 스캔), null-safety, Riverpod
- 웹: Next.js(revendedor 포털) — QR 표시 + socket.io-client
- ESLint: 프로젝트 규칙(Warning=에러). `newline-before-return`, `lines-around-comment` 준수.

## DB 스키마 (신규)

### `revendedor_badges` (public)
| 컬럼(snake_case) | 타입 | 제약 |
|---|---|---|
| id | serial | PK |
| revendedor_id | int | FK→revendedores.id, NOT NULL, INDEX |
| badge_uid | varchar(32) | NOT NULL, **UNIQUE** (NTAG 7-byte UID hex) |
| last_read_ctr | int | NOT NULL default 0 (SDM 카운터, 리플레이 차단) |
| label | varchar(64) | 물리 각인 시리얼(자긍심 요소) |
| status | varchar(16) | NOT NULL default 'active' — active|revoked|lost |
| issued_at | timestamptz | default now() |
| revoked_at | timestamptz | null |
| last_used_at | timestamptz | null |
| created_at / updated_at | timestamptz | timestamps |

- 운영(5434) 적용 SQL 끝에 owner 이전 DO 블록(`ALTER TABLE/SEQUENCE ... OWNER TO coolsistema`) 필수(누락 시 permission denied 500).

### `revendedor_devices` (public, Phase 2 — L3)
revendedor_id, device_token(uuid), device_fingerprint, platform, status, last_seen_at, timestamps. 뱃지를 읽는 폰이 등록 기기인지 확인. MVP에선 스킵 가능(체인 강화용).

### nonce (테이블 아님 — MemoryCacheService)
key `rev:qr:${nonce}` → `{ socketId, revendedorId, createdAt }`, TTL 120s, 승인 시 즉시 del.

## 태스크 목록 (Execute 단계에서 하나씩)

**백엔드 (api-ventago)**
- [ ] TASK-1: 마이그레이션 SQL `migrations/2026xxxx-revendedor-badges.sql` (테이블 2개 + 인덱스 + owner DO 블록). 로컬·운영 동시 적용용.
- [ ] TASK-2: `revendedor-badge.model.ts` (Sequelize 모델, camelCase) — 파일 1개
- [ ] TASK-3: `revendedor-badge.service.ts` — SUN CMAC 검증 + 카운터 replay 차단 + status 확인 + 승격 JWT 발급. pool 안전(조회1/update1). try/catch 필수.
- [ ] TASK-4: `revendedor-badge.controller.ts` — `POST /revendedor/badge/authorize`(폰), 관리자용 발급/폐기 `POST|PATCH /revendedor/badge` (superadmin). 
- [ ] TASK-5: `RevendedorBadgeGuard` — 승격 JWT claim(`badge_verified` && `badge_exp>now`) 검증(stateless, DB 0). 보호 대상 엔드포인트(구매 등)에 `@UseGuards`.
- [ ] TASK-6: `revendedor.gateway.ts` (`/revendedor` 네임스페이스) — nonce 발급 이벤트 + `badge_authorized` emit. `SocketRateLimiter`·wsCorsOptions·Logger 재사용.
- [ ] TASK-7: `revendedor.module.ts` 배선(모델·서비스·게이트웨이·MemoryCacheService import) + JWT 승격 claim 반영.
- [ ] TASK-8: 마스터키 env(`NTAG_MASTER_KEY`) `.env.example` 추가 + 부재 시 명확한 부팅 경고.

**모바일 (Flutter revendedor 앱)**
- [ ] TASK-9: NFC 읽기(`nfc_manager`) — NTAG 424 DNA SUN 파싱, iOS Core NFC 포그라운드 탭 UX
- [ ] TASK-10: QR 스캔 → `/badge/authorize` 호출, 결과 표시. 에러 핸들링.

**웹 (Next.js revendedor 포털)**
- [ ] TASK-11: 미승격 상태 UI + QR 표시 + socket.io-client(`badge_authorized`) 수신 → 승격 토큰 저장·잠금 해제
- [ ] TASK-12: 보호 액션 게이팅(승격 전 구매 버튼 비활성)

**검증**
- [ ] TASK-13: ESLint `npx eslint . --fix` 오류 0
- [ ] TASK-14: PostgreSQL pool 체크리스트(release 누락 없음 — 본 기능은 pool.query/ORM만 사용, 수동 connect 없음 확인)
- [ ] TASK-15: 단위테스트 — SUN 위조/리플레이(카운터 역행)/폐기 뱃지/3자 불일치 각각 차단되는지. (print 모듈의 `*.spec.ts` 패턴 참고)
- [ ] TASK-16: 마이그레이션 로컬(5432)·운영(5434) 동시 적용 + 양쪽 스키마 대조

**하드웨어 (병렬)**
- [ ] TASK-17: NTAG 424 DNA 카드/태그 50~100개 수입(ShopNFC/GoToTags) + 검증용 안드로이드폰. ACR122U(현지 MercadoLibre)는 데스크톱 예비 리더.

## 완료 기준
- ESLint 오류 0
- 뱃지 없이는 보호 API가 401(fail-closed)
- 복제 SUN·리플레이·폐기 뱃지·3자 불일치가 모두 차단(테스트 통과)
- 보호 API 매 호출 DB possession 조회 0 (stateless claim), tap당 DB ≤ 2쿼리
- 마이그레이션 로컬·운영 스키마 일치

## 금지사항 / 주의사항
- **뱃지 마스터키를 DB·git·프론트에 저장 금지** — env/secret store만. per-tag 키는 UID 다이버시피케이션으로 런타임 도출.
- **일반 NFC/UID 태그(NTAG213 등) 사용 금지** — 복제 가능 → 자긍심/보안 모델 붕괴. 반드시 424 DNA(SUN).
- **마이그레이션 한쪽만 적용 금지** — 로컬 5432 + 운영 5434 동시. owner DO 블록 누락 금지.
- **신규 테이블은 `reseller` 스키마 아닌 public** (2026-07-17 로그의 reseller 스키마 에러와 격리).
- **멀티인스턴스**: 2인스턴스 복귀 시 nonce/Socket emit이 인스턴스 로컬 → sticky session 또는 socket.io Redis 어댑터 결정 필요(실운영 전).
- 수동 `pool.connect()` 도입 금지 — ORM/`pool.query`로 자동 반환 유지.
- 기존 `revendedor-jwt` 전략·`sale/hold` 로직 무변경(부작용 차단).

## 미해결 결정사항 (사용자 확인 필요)
1. **companion 승인 UX**: QR 스캔(데스크톱에 QR 표시 → 폰 스캔) vs 푸시 승인(데스크톱 요청 → 폰 알림). SPEC 기본값=QR(카메라 필요, Socket.io로 견고).
2. **뱃지 강제 범위**: 로그인 자체를 막을지 vs 구매 등 보호 액션만 막을지. SPEC 기본값=보호 액션(브라우징은 허용, 구매는 뱃지 필수).
3. **재인증 주기(L5 TTL)**: 교대 1회 / 4h / 8h 등. SPEC 기본값=8h.
4. **L3 폰 기기 바인딩**을 MVP에 포함할지 Phase 2로 미룰지. SPEC 기본값=Phase 2.
