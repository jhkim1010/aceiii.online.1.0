# 운영 서버 점검 2026-09-26 — 보안 · 300ms 병목 · 작업 리스트

절차: `.claude/skills/revision-servidor-produccion`. 측정은 **전부 읽기 전용**.
자문: codex (4회 침묵사 후 짧은 프롬프트로 분할해 3건 수령 — §6).
직전 점검 2026-09-01 과 대조 가능하도록 같은 항목을 유지했다.

---

## 0. 한 줄 결론

| 축 | 결론 |
|---|---|
| **300ms 병목** | **없다.** 시간대별 p95 최댓값이 **40ms**. 하루 31,752건 중 300ms 초과 **6건(0.02%)** |
| **DB** | **무죄.** 앱 핫패스 쿼리 최댓값 12.4ms. 느린 쿼리 상위는 전부 배치(매장 purge·레거시 임포트) |
| **보안** | 침입 흔적 없음(24h 인증 실패 1건). 문제는 **침입**이 아니라 **권한 귀속** — 주인 모르는 root 급 키 6개 |
| **앱 오류** | 2026-09-25 error 로그 **0 bytes** |

---

## 1. 성능 — 300ms 병목은 없다 (실측)

### 1-a. API 지연 (로그 3일)

| 날짜 | 요청 수 | 300ms 초과 | 비율 |
|---|---|---|---|
| 2026-09-24 | 31,775 | 24 | 0.08% |
| 2026-09-25 | 31,752 | **6** | **0.02%** |
| 2026-09-26(부분) | 2,765 | 0 | 0% |

★ **codex 가 「일평균이 피크를 가린다」는 편향을 경고**해서 시간대별로 다시 쟀다.
  그 걱정은 **여기서는 성립하지 않는다**:

```
00~09시 p95 =  4~15ms      12~18시(영업 피크) p95 = 20~30ms
21시 p95 = 40ms  ← 하루 최댓값
```

⤷ 피크 시간대조차 300ms 목표의 **1/10** 이다.

### 1-b. 300ms 를 넘은 6건의 정체

| 경로 | 비고 |
|---|---|
| `GET /products/by-parent?parent=false&pageSize=1000` ×4 | **의도된 설계다** — §5 참조 |
| `GET /health` 400ms ×1 | 단발 |
| `POST /auth/login` 303ms ×1 | 단발(bcrypt) |

2026-09-24 에는 `POST /onboarding/otp/verify` 가 **1,674ms · 1,334ms** 2건 있었다.
가입 심사 경로라 POS 와 무관하고 호출이 드물지만, 1.6초는 유일하게 «사람이 기다리는» 값이다.

### 1-c. DB (pg_stat_statements)

- 전체 DB 시간의 **86%가 레거시 임포트**(`legacy_stage_nam2`) — 배치이고 POS 가 아니다.
- 앱 핫패스는 전부 1ms 미만: `SET TimeZone` 178,726회 0.02ms · `SELECT $1` 303,126회 0.01ms ·
  `INSERT cron_leases` 104,251회 0.11ms.
- 평균 300ms 초과 쿼리 12개는 **전부 호출 1~28회**의 배치(매장 purge `DELETE FROM sales` 15.7초 등).
- 연결 수 8개(활성 1 · idle 7). pool 압박 없음.

---

## 2. ★ 보안 작업 리스트

### P1 — 권한 귀속 (지금, 서비스 영향 없음)

**① 주인 모르는 root 급 SSH 키 6개를 식별한다**

`jhkim` · `wiljac` · `deploy` 는 전부 `NOPASSWD: ALL` 이다 — **그 계정의 키 = 즉시 root.**
auth.log 4주치로 실제 사용을 셌다:

| 계정 | 지문(앞 8자) | 주석 | 4주 사용 |
|---|---|---|---|
| jhkim | `yX4kUe48` | (없음) | **7,148** ← 주 사용 키 |
| jhkim = deploy | `A4hOggX2` | junghokim10@gmail.com | 115 |
| jhkim | `4OdZ5zwr` | dbeaver@marcoskim-mac | 44 · **permitopen 제한 있음(모범)** |
| jhkim | `sZfaKbpP` | marcoskim@192.168.1.7 | **1** |
| jhkim | `MC89t2gv` | marcoskim@RuthKimui-MacBookAir.local | **1** |
| jhkim | `p0Afgl5S` | jhkim@62.72.7.245 | **1** |
| jhkim | `s4M+qx14` | jhkim@62.72.7.245 | **1** |
| jhkim | `cWorfJiG` | (없음) | **1** |
| wiljac | `fvhSik1u` | Wiljac | 33 |
| deploy | `8Hjh7Csk` | (없음) | **1** |

⤷ **6개가 4주 동안 사실상 안 쓰였고, 그 하나하나가 root 다.**
   `postgres` 의 백업 키 2개는 `command=` 로 잘 묶여 있다(모범).

- **할 것**: 위 6개의 주인을 확인 → 확인 안 되는 것부터 제거. 한 번에 하나씩, 백업 후.
- **깨질 수 있는 것**: 아무도 모르는 자동화(백업·배포·모니터링)가 그 키를 쓰고 있을 수 있다.
- **검증**: 제거 후 24시간 동안 `auth.log` 에 그 지문의 실패가 없는지. 다른 SSH 세션을 열어 둔 채 작업.
- ★ **`A4hOggX2` 는 `jhkim` 과 `deploy` 양쪽에 들어 있다** — 키 하나가 두 개의 root 다. 분리할 것.

**② `ubuntu` 계정의 `NOPASSWD: ALL` 제거**
키가 **0개**라 지금 SSH 로는 못 들어온다. 그래도 남겨둘 이유가 없다.
- **깨질 수 있는 것**: cloud-init / 제공사 콘솔 복구 경로. 확인 후에 건드린다.

### P2 — 공개 포트 줄이기 (며칠, 한 번에 하나씩)

**★★ 실측으로 알아낸 것: 그 포트들은 이미 nginx+TLS 뒤에 있다 = 직접 공개가 중복이다.**

| 공개 포트 | 서비스 | nginx 경유 이름 | 중복? |
|---|---|---|---|
| 3030 | syncace | `sync.coolsistema.com` | **예** |
| 4000 | frontend-invoice | `factura.coolsistema.com` | **예** |
| 5001 | ventago front | `app.` · `new.` | **예** |
| 5003 | ventago api | `newapi.`(upstream `ventago_api`) | **예** |
| 5010 | coolinvoice | `api.` · `invoice.` · `manager.` | **예** (남의 시스템) |
| 5011 | apicoolsistema | `manager.` | **예** (남의 시스템) |
| 5111 | api-invoice | `api-factura.` | **예** (남의 시스템) |
| 6001·6002 | coolify-realtime | — | 아니오 |
| 54322 | **postgres 14.1** (남의 시스템) | — | 아니오 |

- **할 것**: Ventago 것부터(**5003 · 5001**) `ports:` 를 `127.0.0.1:` 바인딩으로 바꾼다.
  나머지는 소유자에게 통보.
- ★★★ **방화벽만으로는 안 된다.** 저 10개는 `docker-proxy` 가 게시한 포트라
  **Docker 가 UFW 규칙을 우회한다**(codex 가 짚었고 Docker 공식 문서가 명시).
  UFW 를 켜도 열린 채로 남는다 → `DOCKER-USER` 체인이거나 **publish 를 127.0.0.1 로 바꾸는 것**이 정답.
- **깨질 수 있는 것**: IP·포트로 직접 붙는 클라이언트.
  ★ **에이전트는 안전하다 — 확인했다.** `print-agent/main.js:33` · `zebra-agent/main.js:17`
    둘 다 `https://newapi.coolsistema.com/api` 를 쓴다(nginx+TLS 경유).
    CLAUDE.md 의 「운영 `http://62.72.7.245:5002/api`」는 **낡은 기재다** — 서버에 공개된
    5002 포트는 **아예 없다**(공개된 것은 5003, 5002 는 컨테이너 내부 포트).
    ⤷ CLAUDE.md 를 고칠 것. 그 기재를 믿고 5002 를 여는 작업을 하면 헛수고가 된다.
- **검증**: 바꾼 뒤 `https://<이름>` 으로 접속 · 판매 1건 · 인쇄 1건 · 카하 마감까지 확인.
  포트당 **영업일 1일**을 두고 다음 포트로 넘어간다.

**③ `deploy.coolsistema.com` (→ 8080, Coolify) 에 `auth_basic` 이 없다**
`cooldb`(Jenkins, 8090)에는 있다. 8080 은 자체 로그인이 있을 것이나 **확인 안 됐다.**
- **할 것**: 먼저 로그인 화면이 실제로 막는지 확인. 아니면 `auth_basic` 추가.

### P3 — 낭비 제거 (효과는 작지만 확실)

**④ 와일드카드 서브도메인이 캐시 없이 API 를 부른다** (§3 별도 항목)

**⑤ 빈 일을 도는 크론 3개**

| 대상 | 실제 행 수 | 호출 수 |
|---|---|---|
| `sync_outbox` | **0** | UPDATE 310,203 |
| `campaign_recipients` | **0** | UPDATE 103,404 |
| `commerce_channels` | **1** (2026-06-03 생성) | INSERT 39,819 |

지금 지연을 만들지는 않는다(각 0.01~0.15ms). 다만 **WAL·autovacuum·로그를 계속 만든다.**
- **할 것**: 주기를 늘리거나, 할 일이 없으면 조회 자체를 건너뛰게.
- ★ `sync_outbox` 는 [[commerce-sync-machinery-is-built-but-dormant]] — **기능은 만들어져 있고
  `USE_OUTBOX_SYNC` 가 꺼져 있어 0행**이다. 끄지 말고 **주기만** 늘릴 것.

---

## 3. ★ 안 보이던 결함 — 와일드카드 서브도메인 (신규 발견)

```
nginx:  server_name ~^(?<sub>[a-z0-9-]+)\.coolsistema\.com$  →  127.0.0.1:3060 (tienda-app)
tienda-app/src/middleware.ts:  매 요청마다 fetch(`${API}/public/shop/by-slug/${sub}`)  — 캐시 없음
```

실측: **`GET /api/public/shop/by-slug/ecommerce` 404 가 하루 563건**,
User-Agent 가 **`"Next.js Middleware"`** — 외부 공격이 아니라 **우리 프론트 자신**이다.
404 면 `NextResponse.next()` 로 통과시키므로 **화면은 안 깨진다.** 순수 낭비 + 로그 소음.

**codex 판정(그대로 옮김)**: 「로그 소음만이 아니다. 와일드카드 때문에 누군가 서브도메인을
바꿔 가며 요청하면 **인증 없이** nginx → Next.js → API → PostgreSQL 까지 일을 시킬 수 있다.」

- **할 것**(codex 권고 + 내 판단):
  1. 미들웨어에 `subdominio → storeId` **캐시 5~10분** + **부정 캐시 1~5분**(LRU 상한 필수 —
     안 그러면 무작위 이름이 메모리를 채운다).
  2. 공개 엔드포인트에 **IP·호스트명 단위 rate limit**.
  3. hostname 을 조회 **전에** 정규화·검증(길이·문자·기준 도메인).
- ★ codex 의 3번 제안(「모르는 서브도메인은 즉시 404, 앱으로 안 넘김」)은 **동작 변경**이다.
  지금은 통과시켜 몰이 안 깨지게 하고 있다. **제품 결정이라 사용자 확인 후에** 한다.

---

## 4. ★★ 과대평가하고 있던 것 (codex + 실측)

**이 목록이 작업 리스트만큼 중요하다.** 여기 있는 것에 시간을 쓰면 안 된다.

| 항목 | 왜 과대평가인가 |
|---|---|
| **`pageSize=1000` 을 50으로 줄이기** (codex 가 권고했다) | **하면 회귀다.** `ProductList.tsx:346-366` 주석에 근거가 있다 — POS 검색은 **클라이언트 필터(0ms)** 이고, 서버 검색으로 옮기면 키 입력마다 왕복 **376ms 실측**으로 **더 느려진다.** `hasMore` 계약 + 잘렸을 때만 도는 서버 폴백이 이미 있다. 화면 진입당 1회 호출이고 p95 126ms다. **고칠 것이 아니라 지켜볼 것.** |
| fail2ban · 「24h 인증 실패 1건」 | 외부 소음이 적다는 뜻일 뿐, **도난당한 키의 피해를 줄이지 않는다**(codex). |
| 키 **개수** 자체 | 주인이 확인되고 회전되는 7개가, **주인 모르는 1개보다 낫다**(codex). |
| root 의 잔존 키 4개 | `PermitRootLogin no` 라 **SSH 로 쓸 수 없다.** 2026-09-01 에도 같은 결론. |
| TLS 1.0/1.1 | 2026-09-01 에 이미 «우선순위 아님» 으로 정리됨. |
| 평균 300ms 초과 쿼리 12개 | **전부 배치**(호출 1~28회). 매장 purge·레거시 임포트·시드. POS 가 아니다. |
| 「일평균이 피크를 가린다」 | codex 의 합리적 의심이었으나 **시간대별로 재서 반증했다** — 피크 p95 30ms. |

---

## 5. 영구 제외 (재제안하지 않음)

**운영 DB 인터넷 노출** — 2026-09-11 사용자가 영구 제외했다
([[infra-two-items-permanently-dropped]]). 이번에도 상태는 그대로다:
PG10 `5433` 이 `0.0.0.0` · `host all all 0.0.0.0/0 md5` · EOL 2022-11.
**`db=ventago` 로 붙는 외부 접속은 0건**이고, 붙는 것은 레거시 테넌트다 — 닫으면 매장이 끊긴다.
⤷ **「남은 작업」으로 세지 않는다.** 단 노출 때문에 **실제 사고**가 나면 별개 사안으로 보고한다.

`54322`(postgres 14.1, 남의 시스템)도 공개돼 있으나 **Ventago 것이 아니다** — 소유자에게 통보만.

---

## 6. codex 자문에 대해 (다음 세션을 위한 기록)

★★ **codex 가 이날 4회 연속 조용히 죽었다**(exit 0 · 프롬프트만 에코 ·
`hook: UserPromptSubmit Completed` 에서 끝). 대조군으로 원인을 갈랐다:

| 시험 | 길이 | 결과 |
|---|---|---|
| `Responde solo: OK-CONTROL` | 30자 | **통과** |
| 「7개 키 + sudo NOPASSWD, 좋은 관행인가」 | 100자 | **통과** — 보안 단어는 문제가 아니다 |
| 성능 질문 | ~700자 | **통과** |
| 보안 계획 질문 | ~1,350자 | **죽음** |
| 전체 측정치 | ~4,500자 | **죽음** |

⤷ 원인은 **프롬프트 길이**다(보안 내용도, 훅 실패도 아니었다 — 둘 다 통과 사례에 있었다).
  **~700자로 쪼개면 돈다.** [[codex-exec-dies-silently-on-big-prompt]] 에 임계값을 보강할 것.

---

## 7. 다음 점검 때 대조할 것

| 항목 | 2026-09-01 | **2026-09-26** |
|---|---|---|
| 공개 앱 포트 | 7개 | **12개** (4000·5111·6001·6002 증가) |
| 시간대 p95 | (측정 안 함) | **최대 40ms** |
| 300ms 초과 비율 | 689건 중 1건 | **31,752건 중 6건 (0.02%)** |
| 주인 모르는 root 급 키 | (센 적 없음) | **6개** |
| 방화벽 | inactive | inactive (변화 없음) |
| fail2ban · 보안 업데이트 | 양호 | 양호 (24h 실패 1건 · 대기 0건) |
| 앱 error 로그 | 500 반복 있었음 | **0 bytes** |

---

## 8. ★★ 해결 완료 — `by-parent` 와 «비압축 API» (2026-09-26, 사용자 지시로 착수)

§4 에서 「고칠 것이 아니라 지켜볼 것」으로 분류했던 건을 **사용자 지시로 풀었다.**
결론부터: **`pageSize` 는 건드리지 않았다.** 줄여야 할 것은 행 수가 아니라 **행의 무게**였다.

### 8-a. 먼저 잰 것 — 어디에 시간이 가는가

| 측정 | 값 |
|---|---|
| 이 경로의 **DB 쿼리** (운영 pg_stat_statements) | **전부 3ms 미만** → DB 는 무죄 |
| 운영 응답 크기 | **301,175 B** (로그의 바이트 필드) |
| 로컬 재현 | 336 KB · 중앙값 43ms |
| 페이로드 구성 | `stockByVariant` **87.5%**, 그 안의 **`prices` 가 72.5%** |
| 그 `prices` 안 | `priceType` **객체 전체가 가격마다 복제** — 190 variant × 약 6가격 = 같은 것 1,140벌 = **221 KB** |

⤷ 126~260ms 는 전송도 DB 도 아니고 **Sequelize 모델 인스턴스 약 1,500개**의 생성 비용이었다.
  `Product` 32컬럼(`longDescription`·`seoDescription`·`routingTemplate`…)을 madre 와
  **모든 variant** 에 대해 하이드레이션하는데, 응답에 나가는 것은 **8개**뿐이었다.

### 8-b. 고친 것 ① — api `815da689` (빌드 #963 ✅)

`attributes` 화이트리스트 + 핫패스의 `console.log` 제거.

★ **검증 기준을 「응답이 바이트 단위로 같은가」로 잡았다** — 335,946 B 로 **동일**.
  계약을 안 건드렸으므로 프론트 회귀가 구조적으로 불가능하다.
실측(로컬 20회): `parent=false` 중앙값 **43ms → 34ms (-21%)**, p95 44 → 37. `parent=true` 26ms.

★★ **이 작업이 눈에 안 보이는 것을 한 번 부쉈다.** `storeId` 를 attributes 에서 빼자
  전역 테넌트 훅(`common/tenant/tenant-hooks.ts:675`, `getDataValue('storeId')`)이
  `undefined` 를 읽어 **멀티테넌트 격리 검증이 꺼졌는데 응답은 그대로였다.**
  로그의 「격리 누수 감지」가 **변경 전 0건 → 후 2건**으로 잡아 줬다.
  ⤷ `storeId` 를 되돌리고 **이유를 그 자리에 적었다.** 재발 방지는
    `by-parent-attributes.spec.ts`(대조군 3개 · 돌연변이 2개 적용 2개 사망).

### 8-c. 고친 것 ② — nginx gzip (더 큰 쪽이었다)

**`gzip_types` 와 `gzip_proxied` 가 둘 다 주석 처리돼 있었다.** nginx 기본값이
`gzip_proxied off` 라 **`proxy_pass` 뒤 응답은 `gzip on` 이 있어도 압축되지 않는다** —
곧 **모든 API JSON 이 비압축으로 인터넷을 건너고 있었다.** 301KB 짜리 POS 카탈로그가
매장 회선에서 매 화면 진입마다 그대로 내려갔고, **이것은 서버측 지표(126~260ms)에
전혀 안 잡힌다.**

적용: `newapi.coolsistema.com.conf` · `app.coolsistema.com.conf` 의 **:443 블록에만**
(전역 `nginx.conf` 는 안 건드림 — 같은 서버의 남의 시스템에 영향 주지 않으려고).

```nginx
gzip on;  gzip_vary on;  gzip_proxied any;
gzip_comp_level 5;  gzip_min_length 1024;
gzip_types application/json;      # ← text/plain 제외
```

★ **`text/plain` 을 일부러 뺐다.** socket.io 폴링이 그 타입이고 거기로 **인쇄 에이전트**가
  다닌다. 실측으로 확인: `/socket.io/?EIO=4&transport=polling` 응답에
  **`content-encoding` 없음** — 무영향.

| 검증 | 결과 |
|---|---|
| `nginx -t` | ok (경고는 전부 기존 것) |
| 적용 | `systemctl reload` (무중단) |
| 압축 동작 | 공개 카탈로그 `content-encoding: gzip`, 2,239 B → **644 B** |
| 큰 페이로드 예상 | 로컬 실측 336 KB → **11 KB (96.7%)** |
| reload 후 | API 200 · 프론트 200 · nginx error.log 0줄 · api error 로그 **0 bytes** |
| 백업 | `/etc/nginx/backups/*.antes-gzip-20260926-025002` — **`sites-enabled/` 바깥**에 둠 |

되돌리기: 백업 파일을 제자리에 복사 → `nginx -t` → `reload`.

### 8-d. `.bak` 조사 결과 (사용자 지시: 「옮기기 전에 먼저 조사」)

**결론: 옮겨도 동작은 아무것도 바뀌지 않는다.** 이미 무시되고 있기 때문이다.

근거(`nginx -T` 덤프의 로드 순서 — 먼저 나온 블록이 이긴다):

```
816:  # configuration file .../newapi.coolsistema.com.conf            ← 살아 있는 것
919:  # configuration file .../newapi.coolsistema.com.conf.bak-...    ← 무시됨
```

- 활성 블록(816~918)에 **내 gzip 6줄이 들어 있고** `client_max_body_size 128m` 이다
  (= 새 파일). 무시되는 블록에는 gzip **0줄**.
- nginx 도 명시적으로 `conflicting server name "newapi.coolsistema.com" ... ignored` 라고 말한다.
- ★ **위험은 「지금」이 아니라 「다음」이다.** `include sites-enabled/*` 는 **이름 순**이라,
  `.conf` 보다 앞서는 이름(예: `newapi.coolsistema.com.co`, `...conf.0`)의 파일이 생기면
  **그때 옛 설정이 이긴다.** 고쳐도 안 먹는 상태가 되고 원인을 찾기 어렵다.
- 옮기면 없어지는 것: 경고 2줄 + 위 위험. 없어지지 않는 것: `invoice`·`manager` 의
  충돌 — 그건 **별개이고 남의 시스템**이다(`api-coolsistema.com.conf` 가 `invoice` 를
  중복 선언). 건드리지 않는다.

---

## 9. ★★★ 멀티테넌트 격리 전수 조사 (2026-09-26, 사용자 절대 지시)

> 「태넌트 간의 데이터는 절대로 혼동되거나 오염되어서는 안 돼. 그건 이 시스템의 죽음이야」
> 「`store=undefined` 에 대해서도 절대로 허용해서는 안 되」
> 「이번 주말동안 완벽하게 막아야 해 … 어느 매장, 어느 코드에서 발생했는지 로그에」

### 9-a. 결론 먼저 — 오염의 증거는 **없다**

운영 로그 **14일 전수**(2026-09-13 ~ 09-26):

| | |
|---|---|
| 「격리 누수 감지」 경보 | **776건** |
| 그중 `store=<다른 매장 숫자>` = **진짜 오염** | **0건** |
| `store=undefined` = **확인 불가** | **776건** |

★ 그러나 **「확인 불가」는 「안전」이 아니다.** 776번 못 봤다는 뜻이고,
  진짜 누수 1건이 나도 **그 소음에 묻힌다.** 그래서 고쳤다.

### 9-b. 가드가 «실제로» 하는 일 (여기서 오해가 나기 쉽다)

운영 부팅 로그: `[TenantGuard] mode=enforce 보호모델=130 (글로벌행 허용 8) 제외=30 | 파생스코프 derivedMode=enforce 대상=45`

| 경로 | 동작 |
|---|---|
| 쓰기 `beforeUpdate`/`beforeDestroy` | **막는다** (enforce 에서만) |
| 읽기 `beforeFind` | `where` 를 매장으로 **좁힌다** → **데이터는 맞게 나온다** |
| 결과 검증 `afterFind` | **절대 throw 하지 않는다** — 되짚어 보는 감시일 뿐 |

⤷ 그래서 `store=undefined` 는 「데이터가 샜다」가 아니라
  **「좁히긴 했는데 확인을 못 했다」**다. 이 구분이 이번 조사의 핵심이다.

★ 가드가 **완전히 no-op** 인 경우: 컨텍스트 없음(크론·워커) · `ctx.system` ·
  **`ctx.isSuperAdmin`**. 매장 대행(`X-Store-Id`)은 `isSuperAdmin:false` 로 컨텍스트를
  세우므로 가드가 산다 — 그래서 `getScope()` 가 superadmin 에게 `storeId: undefined` 를
  주는데도 구조된다. **애플리케이션 코드 자체는 안 좁혀져 있다는 뜻이다.**

### 9-c. 사용자 가설 검증 — 「SKU 처럼 store 를 품은 값으로 store 지정 없이 처리」

**가설이 맞았다.** DB 에서 근거를 잡았다(`pg_constraint`): **매장별로만 유일한** 업무 키가
**14개 테이블**에 있다 — `products.sku` · `credit_payments.receipt_no` ·
`online_orders.order_number` · `talleres_lotes.cut_ticket_number` 등.

실제로 **매장 간에 값이 겹치는 것은 단 하나**:

```
sku = 'GEN-0001'  →  14개 매장 (6,9,11,13,14,15,16,17,18,19,20,21,22,23)
```

그리고 그것을 읽는 코드가 이 형태다:

```ts
// products.service.ts:550
async findGenericProduct(storeId?: number) {
  const where: any = { isGeneric: true };
  if (storeId) where.storeId = storeId;     // ← 매장 필터가 «선택적»
  ...
// products.controller.ts:103
storeId: isSuperAdmin ? undefined : (user?.storeId ?? undefined)
```

⤷ superadmin 이면 `storeId` 가 **undefined** → 매장 필터 없음 → 가드도 no-op.
  같은 형태(`if (storeId) where.storeId = storeId`)가 저장소에 **35곳**.
  다만 보고서류는 「전 매장」이 의도라 전부가 결함은 아니다.
  **위협은 셋이 겹칠 때다: ①매장 소유 행을 ②필터 없이 읽어 ③특정 매장의 거래에 쓴다.**

### 9-d. 고친 것 (배포 완료)

| # | 내용 | 커밋 |
|---|---|---|
| 1 | 「검증 불가」를 「누수」에서 **분리**. `GLOBAL_ROW_TABLES`(users 등 8개)에서 미선택 행이 **전역행으로 조용히 통과**하던 것을 막음 | api `5c2034a6` |
| 2 | 경보에 **`파일:줄` 3단 사슬 + 매장 + user**. throttle 키도 **위치별** | api `5c2034a6` |
| 3 | `--enable-source-maps` — 줄 번호가 `dist/*.js` → **`src/*.ts`** | api `5c2034a6` |
| 4 | `beforeFind` 가 **`storeId` 를 SELECT 에 강제**, `afterFind` 가 검증 후 도로 뺌 → `store=undefined` 가 **구조적으로 소멸** | api `bec38dad` |

★ 4번의 안전장치: **`group` 이 있거나 집계 표현식이 섞인 `attributes` 는 안 건드린다**
  (SELECT 에 GROUP BY 밖 컬럼을 넣으면 PG 가 거부한다). 애매하면 아무것도 안 한다.

★★ **E2E 대조군으로 확인했다** — `by-parent` 의 attributes 에서 `storeId` 를 손으로 빼고
  (= 536개 호출부 중 아무거나 흉내) 로컬 API 에 요청:

| | 가드 수정 **전** | 가드 수정 **후** |
|---|---|---|
| 경보 | 0 → **2건** | 0 → **0건** |
| 응답 | 335,946 B | **335,946 B (동일)** |
| `storeId` 응답 유출 | — | **없음** |

### 9-e. ★ 아직 안 막힌 것 (다음 작업)

- **raw SQL `sequelize.query` 219곳은 훅을 아예 안 탄다.** 그중 store 조건이 없는 것 **204곳**.
  대부분은 이미 인가된 기본키로 좁혀 무해하지만 **전수 판정은 안 했다.**
  ⤷ 이건 훅으로 못 막는다. PG **RLS + 세션 GUC** 이거나 **lint 규칙**이 필요하다.
- `findGenericProduct(storeId?)` 처럼 **매장 인자가 선택적인 함수** — 가드가 구해 주고
  있지만 **코드 자체를 필수 인자로 바꿔야** 가드가 꺼진 경로(크론·superadmin)에서도 안전하다.
- 주말 목표 대비: **탐지·예방은 배포됐고, raw SQL 경로가 남았다.**
