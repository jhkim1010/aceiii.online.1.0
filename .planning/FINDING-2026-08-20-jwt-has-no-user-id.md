# 발견 — 사용자 JWT 에 `id` 가 없다 (2026-08-20, Phase 85 W2 중 우연히)

> ## ✅ 해결됨 (2026-08-20 밤, 사용자 승인 후 당일 처리)
>
> | 단계 | 내용 | 결과 |
> |---|---|---|
> | B-1 | email 없이 사용자를 만들 수 없게 — 서버가 합성 주소로 채운다 | `api-ventago 1073e89` · api #767 SUCCESS |
> | A | 남아 있던 4명 백필 + `users.email SET NOT NULL` | `0394b4a` · 운영 적용 완료 |
> | C | 토큰에 `id` 추가 · id 우선 조회 · 캐시 키 이중 무효화 · `/auth/me` | `822c00b` · api #769 SUCCESS |
>
> 순서는 codex 지적을 받아 **생성 차단 → 데이터 정리 → NOT NULL → 구조** 로 바꿨다
> (A 를 먼저 하면 그 사이 만들어지는 사용자가 다시 NULL 이 된다).
> 판단 기록: `.team/reviews/jwt-identity-resolution.md`
>
> ★ 부작용(의도): email=NULL 로 발급됐던 토큰은 이후 401 이다 — 그 계정들은 재로그인이 필요하다.
> ★ 남은 것: 소켓 게이트웨이는 여전히 DB 를 다시 보지 않는다(정지된 사용자의 소켓이
>   토큰 만료까지 산다). 별건으로 남긴다.
>
> 아래는 발견 당시의 기록이다.

**Phase 85 의 일이 아니다.** 소켓 집계를 배포하고 운영 값을 보다가 드러났다.

## 사실

사용자 토큰의 서명 payload 는 이렇다 (`auth.service.ts:646` · `:785` · `:1119` · `:1179`,
`mobile-auth.service.ts:291` — **네 곳 전부 같다**):

```
{ name, lastName, email, status, trialEndsAt, roles, storeId }
```

`JwtPayload` 인터페이스에는 `id: string` 이 선언돼 있지만 **어디서도 넣지 않는다.**
운영에서 실제로 확인한 payload 필드: `[email, exp, iat, lastName, name, roles, status,
storeId, trialEndsAt]`.

그리고 **운영 `users` 26명 중 4명은 `email IS NULL`** 이다(username 으로 로그인하는 계정):

| id | username | store_id | status | last_login_at |
|---|---|---|---|---|
| 24 | venta1@cool | 6 | active | 2026-08-20 |
| 25 | venta2@cool | 6 | inactive | 2026-07-29 |
| 29 | vendedor@cool | 6 | inactive | 2026-08-20 |
| 40 | cajerauno@liverpool-tienda | **17** | active | (없음) |

## 이것이 만드는 결과 3가지

### 1) ★ null-email 계정끼리 신원이 섞인다 (심각)

`jwt.strategy.validate` 는 **email 로 사용자를 찾는다**:
```ts
this.usersService.findOneByEmail(data.email)   // where: { email: userEmail }
```
`data.email` 이 null 이면 Sequelize 가 `WHERE email IS NULL` 을 만들고
`findOne` 은 **그중 첫 행 하나**를 돌려준다. 운영에서 확인:

```sql
SELECT id, username, store_id FROM users WHERE email IS NULL LIMIT 1;
-- 24 | venta1@cool | 6
```

즉 **id 29(vendedor@cool)로 로그인해도 이후 모든 요청은 id 24(venta1)로 해석된다.**
`sales.user_id` 같은 귀속, 감사 로그, 권한이 전부 다른 사람 것이 된다
(관련: `dont-attribute-without-evidence`).

★ **id 40 은 store 17 이다.** 아직 로그인 기록이 없어 사고가 안 났을 뿐, 로그인하는 순간
**store 6 사용자로 해석된다** — 테넌트 경계를 넘는다(Phase 69 의 주제).

★ 권한 캐시도 같이 섞인다: `authUserKey(data.email)` 이라 4명이 **캐시 항목 하나**를 공유한다.

### 2) `emitToUser` 가 브라우저에 도달하지 못한다

`websocket.service.ts:55` 주석이 이미 적어 둔 기존 결함이다. `client.data.userId` 가 항상
undefined 라 `user:{id}` room 에 못 들어간다. store room 만 살아 있다.

### 3) 소켓 집계가 사람을 식별하지 못한다 (Phase 85 W2 — 우회함)

`jwtIdentity()` 가 id → vendorId → email 해시 → **name 해시** 순으로 내려가며 우회했다
(`api-ventago c501d72`). 근본이 고쳐지면 자동으로 `u:{id}` 를 쓴다.

## 고친다면

1. 네 곳의 서명 payload에 `id: user.id` 추가 (추가만, 제거 없음)
2. `jwt.strategy` 가 **id 우선**으로 조회하고 email 은 폴백으로만 (`findOneById`)
3. 인증 캐시 키도 id 기준으로 (`authUserKey`)
4. 기존 토큰은 6시간이면 만료되고 `/me` 가 매번 재서명하므로 전환은 빠르다
5. ★ 그와 별개로 **`users.email` 에 NULL 을 허용할 것인지** 결정해야 한다.
   허용한다면 email 을 신원으로 쓰는 경로를 전수로 찾아 바꿔야 한다.

★ 이 변경은 **모든 인증 요청이 타는 경로**를 건드린다. 영업시간에 하지 말 것.
