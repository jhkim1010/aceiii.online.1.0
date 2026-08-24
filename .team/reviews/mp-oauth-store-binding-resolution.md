# 수용본 — MercadoPago OAuth 매장 귀속 결함 (2026-08-23/24)

## 무엇이 뚫려 있었나

```
GET /api/mercadopago/oauth/start?storeId=N   @Auth(admin, superadmin)
  → storeId 가 **호출자의 매장인지 확인하지 않는다**
  → 그 값이 HMAC 서명된 state 에 실려 @Public() 콜백까지 간다
  → 콜백이 그 값으로 mp_accounts 에 쓴다 (기존 행이면 **덮는다**)
```

A매장 admin 이 `start?storeId=B` → 자기 MP 계정으로 OAuth 완료 →
**B매장 행이 공격자 토큰으로 덮인다** → B매장 QR 대금이 공격자에게 간다.

★ 전역 Sequelize 테넌트 가드가 다른 MP 라우트는 덮는데,
  **콜백은 `@Public()` 이라 테넌트 컨텍스트가 없어 no-op** 이다. 그래서 이 경로만 뚫렸다.

★ 운영 실측 `mp_accounts` **0행** — 실제 피해 없음. 순수 예방 수정이다.

## 내가 처음에 틀렸던 것

`disconnect/:accountId` 도 구멍이라고 사용자에게 보고했는데 **틀렸다.**
`MpAccount` 에 `storeId` 가 있고 `mp_accounts` 는 면제 목록에 없어 가드가 덮는다
(운영 부팅 로그: `[TenantGuard] 격리 훅 설치 완료 — mode=enforce 보호모델=122`).
근거를 확인하기 전에 말한 것이 잘못이었다.

## 1R (설계) 수용 — 안 C + 콜백 관계 검증

| codex | 조치 |
|---|---|
| A(=start 인가)는 필수 | `superadmin` 아니면 `user.storeId !== storeId` 거부 + 지점 소속 확인 |
| B(=콜백 재확인) | 쓰기 직전 `branch.store_id` 를 DB 로 재확인 — `start` 는 JWT 축, 여기는 **관계 축** (같은 축이면 한 겹) |
| C(=서버 저장 단일사용 nonce) | `mp_oauth_states` 신설. state 에는 **nonce 만**. 콜백은 payload 가 아니라 **그 행**에서 범위를 읽는다 |
| **다른 `mpUserId` 는 기본 거부** | 토큰 갱신과 **수취 계정 교체**를 분리. 교체는 `allowReplace` 승인 필요 |
| 미래 `ts` 허용 | `age < -60s` 거부 |
| 오류 문구 URL 반사 | 고정 코드만 (`KNOWN_CALLBACK_ERRORS`), 상세는 서버 로그 |
| `Number.isNaN` 부족 | `Number.isSafeInteger` + 양수 |

## 2R (구현) 수용 — HIGH 1 · MEDIUM 2

**[HIGH] `expectedMpUserId` 를 저장만 하고 쓰지 않았다.**
그러면 교체 승인이 "**A 를 바꾼다**" 가 아니라 "**콜백 시점의 무엇이든 바꾼다**" 가 된다 —
10분 창 안에 다른 요청이 먼저 B 로 바꿔도 옛 승인이 그것을 덮는다.
→ 활성 행을 `FOR UPDATE` 로 잠그고, 그 `mpUserId` 가 `scope.expectedMpUserId` 와
  다르면 `OAUTH_ACCOUNT_STATE_CHANGED` 로 중단한다.

**[MEDIUM] 인가 판정보다 외부 I/O 가 먼저였다.**
승인 없는 교체가 결국 거부되더라도 그 전에 `registerStoreAndPos()` 가
**남의 MP 계정에 Store/POS 를 만들어** 놓았다.
→ 판정을 외부 호출 앞으로. (트랜잭션 밖은 유지 — 커넥션 장기 점유 금지.)

**[MEDIUM] 끊고 다른 계정으로 재연결할 길이 막혔다.**
→ 계약을 정했다: **연결 해제는 이미 명시적·감사되는 admin 행위이므로 그 자체가 승인이다.**
  판정은 **활성 행만** 본다. 활성 행이 없으면 자유롭게 연결하고, 트랜잭션 안에서
  끊긴 **같은 계정** 행이 있으면 되살린다(지갑 보존), 다른 계정이면 새 행을 만든다
  (`mp_wallets` 가 1:1 이라 계정이 다르면 지갑도 달라야 한다).

## ★ codex 가 가정한 것보다 나빴던 것 — 내가 실측으로 찾음

codex 는 "`mp_accounts` 의 UNIQUE 인덱스는 활성 행에만 적용된다" 고 썼다.
**실측하니 그런 인덱스가 아예 없었다** — `mp_accounts_pkey` 뿐이다.

```
CREATE UNIQUE INDEX mp_accounts_pkey ON public.mp_accounts USING btree (id)   ← 전부
```

즉 같은 (매장, 지점)에 **활성 행이 여러 개** 생길 수 있고,
`MpAccountResolverService.findOne({storeId, branchId, disconnectedAt: null})` 은
그중 **아무거나** 고른다 — **어느 계정이 QR 대금을 받는지가 비결정적**이다.

→ `uq_mp_accounts_active_scope` 추가. `NULLS NOT DISTINCT` 가 핵심이다 —
  매장 단위 연결은 `branch_id IS NULL` 이라 기본(`NULLS DISTINCT`)이면
  **정작 막아야 할 자리가 안 막힌다.**

## 검증

- 단위 566건 (store + mercadopago + common) · OAuth 집중 39건
- `tsc` 0 · API 빌드 0 · 프론트 빌드 0 (프론트 lint 는 빌드 게이트다)
- **대조군 5종** — 각 방어를 하나씩 무력화하면 그 자리에서 죽는다:
  ① 매장 인가 제거 ② 계정 교체 차단 제거 ③ `expectedMpUserId` 대조 제거
  ④ `FOR UPDATE` 제거 ⑤ 외부 I/O 를 판정 앞으로
  (③④⑤ 는 tsc 통과를 확인해 **컴파일 실패로 인한 가짜 실패가 아님**을 확인했다 —
   첫 시도에서 파일이 깨져 8건만 돌았고, 그건 유효한 대조군이 아니었다)
- 마이그레이션 2개 로컬(5432) + 운영(5434) 양쪽 적용·검증

## 범위 밖으로 남긴 것 (후속 보안 부채)

- `refunds/:saleId/retry` — `saleId` 무검사로 `mp_refunds`/`mp_refund_attempts` INSERT.
  두 모델은 `store_id` 가 없고 **읽기 쪽 파생 훅만** 있어 쓰기가 무방비다 (HIGH)
- `disconnect`·`qr`·`payment-intents`·`wallets/:id/movements` — 전역 가드에만 의존.
  `TENANT_GUARD_MODE=warn` 이면 전부 열린다 → 핸들러에 명시 검사 추가 필요
- webhook 의 `findByPk(accountIdFromQuery)` — 재조회 토큰 검증이 교차 확정은 막지만
  유효하되 틀린 `accountId` 로 그 알림을 실패시키는 DoS 가 가능
