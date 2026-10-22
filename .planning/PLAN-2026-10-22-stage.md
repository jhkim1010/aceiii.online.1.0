# Stage — stage.coolsistema.com (운용3)

2026-10-22 · 사용자 결정: 운용3(Vultr Miami 149.28.107.232)에 둔다 · DNS A 레코드로 연결.
목적: 운영에 올리기 전에 **같은 커밋을 운영 데이터 복사본에서** 사용자와 Claude 가 직접 눌러 본다.

## 구성

| | 운영 | 스테이지 (운용3) |
|---|---|---|
| 앱 | app.coolsistema.com | **stage.coolsistema.com** → 127.0.0.1:5101 |
| API | newapi.coolsistema.com | **stageapi.coolsistema.com** → 127.0.0.1:5102 |
| DB | PG18 ventago18:5434 | **PG18 클러스터 `stage`:5435**, DB `ventago` |
| Redis | ventago_redis | 별도 컨테이너 `stage_redis` |
| MinIO | 운영 | 운용3 minio 의 **별도 버킷** (운영 사진은 안 보일 수 있음) |

- 운용3 의 대기용 복제본(ventago18:5434)·대기 컨테이너는 **손대지 않는다.**
- failover.sh 는 운용3 를 운영으로 올리기 전에 **스테이지를 먼저 내린다**(자원 확보).

## DB 갱신 (매일 03:00 BA + 수동)
복제본(읽기 전용)에서 `pg_dump` → `stage` 클러스터에 DROP/CREATE 후 `pg_restore` → **위생 처리**.

위생 처리 (바깥으로 나가는 연동 차단 — 스테이지가 실제 쇼핑몰·MP·WhatsApp 을 부르면 안 된다):
- `commerce_channels`, `wp_channels` — wc 키·secret 비움, 비활성
- `mp_accounts` access/refresh token 비움 · `subscription_config` mp/stripe 키 비움
- `store_whatsapp_config.access_token` · `store_configs.email_api_key_enc` 비움
- AFIP: 인증서 볼륨을 **마운트하지 않는다** → 발급 불가(CAE 요청 자체가 안 나간다)
- API env: Telegram·SMTP·WhatsApp·MP 웹훅 관련 변수 **복사하지 않음**

## 배포 (Mac → 운용3)
`scripts/stage/deploy.sh [api-commit] [app-commit]` — GitHub 을 거치지 않는다(push 전 커밋을 시험하는 것이 목적):
`git archive` → rsync → 운용3 에서 `docker build` → stage 컨테이너 교체. 앱은 빌드 인자
`NEXT_PUBLIC_API_HOST=https://stageapi.coolsistema.com/api` 로 스테이지 API 를 보게 한다
(ventago-app `api.service.ts`·CSP 에 이 변수를 받는 코드가 필요 — 기본값은 운영 그대로).

## 사용자가 할 일
DNS 에 A 레코드 2개: `stage` → 149.28.107.232, `stageapi` → 149.28.107.232.
(지금 `*.coolsistema.com` 와일드카드가 운영 IP 로 가므로 개별 레코드가 우선한다.) 생기면 certbot 으로 인증서.

## 순서
1. 운용3: PG `stage` 클러스터 + 갱신·위생 스크립트 + 타이머
2. ventago-app: `NEXT_PUBLIC_API_HOST` 받기 (기본값 운영 — 운영 동작 불변)
3. 운용3: stage compose (api·app·redis) + deploy.sh
4. DNS 확인 → nginx + certbot
5. failover.sh 에 「스테이지 먼저 내림」
6. 확인: 로그인 · 판매 1건 · 인쇄/AFIP 가 **나가지 않는지** · 연동 호출 0건
