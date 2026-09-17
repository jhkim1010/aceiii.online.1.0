# arriba.world 서브도메인 — 사용자 결정 + 실측 (2026-09-17)

신청자가 **자기가 정한 이름**을 `coolsistema.com` 또는 `arriba.world` 앞에 붙여
공개몰 주소로 쓸 수 있게 한다. (`minegocio.arriba.world`)

---

## 사용자 결정 (2026-09-17)

| # | 결정 | 내용 | 결과 |
|---|---|---|---|
| **D-1** | 이름 유일성 | **전역 유일** — 이름 하나는 한 매장 | `mana` 를 누가 가져가면 `mana.coolsistema.com` 과 `mana.arriba.world` 둘 다 그 매장 것. 손님이 도메인을 헷갈려 남의 가게로 가는 일이 **구조적으로 불가능**하다. 현 DB 제약(`uq_stores_slug` · `ux_stores_slug_canonical`)이 이미 이 모양이라 **스키마 변경이 가장 작다** |
| **D-2** | 이름 입력 시점 | **가입 단계에서 정한다** | `/register` 에 이름 + 도메인 선택을 추가. 실시간 중복 확인 + 미리보기 필요. ★ 지금은 가입에서 slug 를 **전혀 안 정한다**(기본값 NULL) — 이 변경이 작업의 본체다 |
| **D-3** | 이름 변경 | **바꿀 수 있되 옛 이름을 살려둔다** | 옛 이름 → 새 이름 **301 리다이렉트**. 이미 인쇄된 QR 라벨과 손님이 저장한 링크가 안 죽는다. 이름 이력 테이블 필요. ★ Phase 89 가 죽은 라벨을 살렸는데 같은 일을 다시 만들지 않기 위한 결정 |
| **D-4** | 등록업체 | **GoDaddy** (coolsistema.com 과 동일) | 서버에 저장된 GoDaddy API 키(`SAVED_GD_K`/`SAVED_GD_S`)로 acme.sh 와일드카드 발급 가능. 자동 갱신도 기존 cron 에 들어간다 |

---

## 실측 — 운영은 이미 이 구조로 돌고 있다 (2026-09-17 확인)

```
/etc/nginx/sites-enabled/shop-wildcard.coolsistema.com.conf
  server_name ~^(?<sub>[a-z0-9-]+)\.coolsistema\.com$
  ssl_certificate /etc/ssl/certs/coolsistema-wildcard/fullchain.pem
  proxy_pass http://127.0.0.1:3060        ← tienda-app

인증서: acme.sh `*.coolsistema.com_ecc` (DNS-01, GoDaddy API)
        cron: 41 5,11,17,23 * * *  /root/.acme.sh/acme.sh --cron
        SAN: *.coolsistema.com, coolsistema.com   유효기간 ~2026-10-21
```

★★ **서브도메인 해석 코드는 도메인을 모른다.** `tienda-app/src/middleware.ts:27-33` 이
Host 에서 **첫 라벨만** 떼어 slug 로 쓴다(`.coolsistema.com` 을 잘라내는 방식이 아니다).
⤷ `minegocio.arriba.world` 로 들어와도 **이 파일은 고칠 필요가 없다.**

★ URL 을 조립하는 곳은 저장소 전체에 **2곳뿐**이고 둘 다 이미 env 로 빠져 있다:
- `api-ventago/src/app/print/qr-public.service.ts:70,80` — `SHOP_BASE_DOMAIN`
- `ventago-app/src/services/store-theme.service.ts:11-12,22` — `NEXT_PUBLIC_SHOP_BASE_DOMAIN`
⤷ **단, 전역 단일 값이라 「매장별 도메인」을 못 낸다.** 이 둘이 매장 값을 읽어야 한다.

---

## 해야 할 일

### 인프라
1. **GoDaddy 에서 `*.arriba.world` A 레코드 → `62.72.7.245`** ← 사용자 작업
2. acme.sh 로 `*.arriba.world` 와일드카드 발급 (기존 GoDaddy 키 재사용) ← 서버 변경, 승인 필요
3. nginx vhost 1개 추가 — `shop-wildcard.coolsistema.com.conf` 복사 후 도메인·인증서만 교체,
   프록시 대상은 같은 `127.0.0.1:3060` ← 서버 변경, 승인 필요

### DB
4. `stores` 에 **도메인 컬럼이 없다** — 매장이 도메인을 고르려면 추가해야 한다.
   D-1(전역 유일) 덕에 slug 제약은 **그대로 둔다**.
5. **이름 이력 테이블** (D-3 의 301 리다이렉트 근거). 옛 이름도 전역 유일 공간을 점유해야
   남이 가져가 남의 가게로 가는 일이 없다.

### 코드
6. URL 조립 2곳 → 매장별 도메인을 읽도록
7. **가입 흐름에 이름 + 도메인 선택 추가** (D-2) — 실시간 중복 확인 · 미리보기 · 예약어 거절
8. 옛 이름 301 리다이렉트 (D-3) — `tienda-app` 미들웨어에서 처리
9. ★ **예약어 목록이 두 군데서 다르다** — API 34개(`api-ventago/src/app/shop-public/store-slug.util.ts:7-40`)
   vs 미들웨어 7개(`tienda-app/src/middleware.ts:11-19`). 도메인이 둘이 되면 이 불일치가
   실제 사고가 된다(한쪽만 막는 이름이 생긴다). **한 곳에서만 오게** 해야 한다.

---

## 주의

★ `tienda-app` 에는 **Dockerfile 이 없고** `docker-compose.yml` 에도 없다. 그런데 운영
`https://cool.coolsistema.com` 은 **200 으로 살아 있다**(89-04 실측). 3060 에 무엇이 어떻게
떠 있는지는 **아직 확인 못 했다** — 배포 작업 전에 반드시 실측할 것.

★ `stores` Sequelize 모델에 `slug` 속성이 **없다** — slug 접근은 전부 원시 SQL 이다.
  컬럼을 더한다면 모델에 넣을지부터 정할 것(넣으면 `@Column` 에 명시적 `type` 필수).

관련: `.gsd/spec-store-storefront-subdomains.md` (TASK-8~11 · `:72` 커스텀 도메인은 미구현)
