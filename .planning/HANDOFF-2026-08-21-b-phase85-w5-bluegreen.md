# 핸드오프 — 2026-08-21 오후 · Phase 85 W5 무중단 배포 **완결**

`HANDOFF-2026-08-21-phase85-w3-w4-w8.md` 에서 이어짐.

## Phase 85 진행률: 8 웨이브 중 **6 완결 + 3 조건부 보류**

| 웨이브 | 상태 |
|---|---|
| W1 캐시 · W2 소켓 · W3 pageSize · W4 규약 · W8 강제지점 | ✅ 완결(이전) |
| **W5 무중단 배포(HTTP)** | ✅ **완결 — 운영 배선 + 첫 배포 성공** |
| W6 매장별 논리 복구 | ⬜ **다음 세션** |
| W4 파티셔닝 / W7 rollup / W8 p95 게이트 | ⏸ 조건 기록 후 보류(변동 없음) |

---

## ★ 오늘 배운 것 — 가장 중요한 것부터

### 1. 스크립트를 만든 것과 배포 경로가 그것을 쓰는 것은 다르다

오전 세션이 `deploy-bluegreen.sh` 를 만들고 nginx 를 `upstream ventago_api` 로 바꿔 두었다.
그런데 **Jenkins job 은 여전히 `docker compose build` + `up -d`** 였다. 즉 W5 는
"만들어 뒀지만 켜지지 않은" 상태였고, 핸드오프에는 그 구분이 없었다.

결과가 실제 장애로 나타나 있었다 — **빌드 #777 (11:58) FAILURE**:

```
+ docker compose up -d
Error response from daemon: Conflict. The container name "/api_ventago"
is already in use by container "707461a0e78c..."
```

blue/green 이 컨테이너를 `api_ventago` 로 rename 해 둔 상태(project `ventago_5003`)와
Jenkins 의 `compose up`(project `api-new-coolsistema`)이 **같은 이름을 두고 다퉜다.**
두 계보가 공존하는 구조 자체가 원인이었고, job 을 스크립트로 교체해 없앴다.

★ **다음 세션 규칙: "구현됐다" 를 볼 때 호출부까지 본다.** 배포 스크립트는 Jenkins job,
  마이그레이션은 DB, 엔드포인트는 프론트 호출 — 만든 것과 쓰이는 것을 따로 확인한다.

### 2. 배선을 막고 있던 진짜 장벽은 권한이었다

```
$ sudo -l -U jenkins
User jenkins is not allowed to run sudo on srv803182.
```

전환 단계는 `/etc/nginx/conf.d/` 쓰기 + `nginx -s reload` 라 root 가 필요하다.
**그대로 켰으면 매 배포가 "green 빌드 → 전환 실패 → green 폐기" 로 끝났을 것이다.**
게다가 종전 코드는 `printf > "$CONF"` 의 실패를 검사하지 않아 **안 바뀐 것을
"✓ 전환 완료" 로 보고**했다 — 리다이렉션 실패는 늘 이 형태로 조용하다.

권한을 여는 방식에서 두 길이 있었다:

| | 여는 것 | jenkins 를 잡은 사람이 할 수 있는 일 |
|---|---|---|
| (가) | conf 를 jenkins 소유 + `nginx -t`/`-s reload` NOPASSWD | **임의 nginx 설정을 쓰고 reload** — 어떤 도메인이든 자기 백엔드로 |
| (나) ← 채택 | 헬퍼 1개만 NOPASSWD | 미리 정한 **두 포트 중 하나**를 가리키게 함 |

`/usr/local/bin/ventago-switch-upstream` (root:root 755) 이 인자를 case 화이트리스트로
검증하고 **경로를 스크립트 안에 박는다.** 실측: 허용 밖 포트(`8080`) · 경로 주입
(`../../etc/nginx`) · 명령 주입(`5012; rm -rf /tmp/x`) 전부 exit 2.

★ 이 파일을 jenkins 가 고칠 수 있으면 위 좁힘이 통째로 무의미하다. **root 소유 유지.**

### 3. 되돌리기가 두 벌이면 반드시 한쪽만 고쳐진다 (codex P2)

`nginx -t` 실패 분기는 "백업이 없으면 conf 를 지운다" 를 했는데 `reload` 실패 분기는
안 했다. conf 가 **처음부터 없던 환경**에서 reload 가 실패하면 "되돌린다" 고 보고하면서
새 설정을 디스크에 남긴다 → **다음 nginx 재시작 때 아무도 전환한 적 없는 포트로 간다.**
`rollback()` 하나로 합쳤다. 판단 기록: `.team/reviews/phase85-w5-resolution.md`

★ **되돌리기 시험은 전제를 먼저 확인한다.** 첫 검증은 이전 실행이 남긴 `.bak` 때문에
  `rm` 분기가 아니라 `cp` 분기를 타서 **엉뚱한 분기를 검증할 뻔했다.** 결과가
  "수정이 안 먹었다" 처럼 보였는데 실은 시험이 틀렸다.

### 4. 리허설이 리허설 구실을 하려면 같은 코드가 돌아야 한다

포트·서비스명·project 접두사·빌드 인자를 **전부 변수로** 뺐다. 하드코딩해 두면
"스테이징용 사본" 이 생기고 그 사본은 운영 것과 조용히 갈라진다.

---

## 검증 숫자 (이게 판정이다)

| 대상 | 방향 | 요청 | 502/503/000 |
|---|---|---|---|
| 스테이징 1회차 | 5012 → 5013 | 824 | **0** |
| 스테이징 2회차 | 5013 → 5012 | 686 | **0** |
| **운영 #778** | **5002 → 5003** | (프로브 결과는 아래) | |

비교 기준: **같은 기전의 첫 운영 시험은 198요청 중 502 가 85건**이었다.

운영 배포 후 상태: upstream=5003 · `api_ventago` project=`ventago_5003` ·
5002 잔여 컨테이너 0 · PM2 4워커 online · 외부 newapi/app 둘 다 200.

---

## ★ 약속의 범위 — 오해하면 안 되는 것

- ✔ **HTTP 는 안 끊긴다.** nginx 가 green 스모크 통과 후에만 전환한다.
- ✘ **WebSocket 은 끊기고 재연결한다.** 연결은 handshake 때 고른 컨테이너에 수명 동안
  고정되고 Redis 어댑터는 broadcast 를 중계할 뿐 연결을 옮기지 않는다. 구조상 피할 수 없다.
  클라이언트는 전부 자동 재연결한다(브라우저 레지스트리 · print/zebra agent Infinity).
- nginx `/socket.io/` 의 `proxy_read_timeout 86400` 때문에 drain(20s) 후 강제 종료된다.

---

## 운영 서버 변경 (저장소 밖 — 재구축 시 필요)

| 경로 | 내용 |
|---|---|
| `/usr/local/bin/ventago-switch-upstream` | root:root 755. 원본은 `api-ventago/scripts/ventago-switch-upstream.sh` |
| `/etc/sudoers.d/ventago-bluegreen` | `jenkins ALL=(root) NOPASSWD: /usr/local/bin/ventago-switch-upstream` (visudo -c 검증) |
| `/etc/nginx/conf.d/ventago-api-upstream.conf` | 운영 upstream (헬퍼가 씀) |
| `/etc/nginx/conf.d/ventago-api-staging-upstream.conf` | 스테이징 리허설용 |
| `/etc/nginx/conf.d/ventago-staging-front.conf` | `127.0.0.1:5099` 루프백 전용 |
| `/home/jhkim/phase63-staging/docker-compose.yml` | 이름·포트 변수화 (기본값 무변경, `.bak-w5-bluegreen`) |
| Jenkins `api-new-coolsistema` builders | `bash scripts/deploy-bluegreen.sh` (백업 `config.xml.bak-pre-bluegreen-20260821`) |
| `/etc/nginx/sites-disabled/` | sites-enabled 에서 옮긴 `.bak` 5개 (**삭제 아님**) |

★ **Jenkins config.xml 을 고쳐도 Jenkins 는 안 집는다** — 메모리에 들고 있다.
  Manage Jenkins → Reload Configuration from Disk 를 눌러야 한다(이번엔 사용자가 눌렀다).
  CLI jar 도 없고 익명 접근도 403이라 이 세션에서는 자동화 경로가 없었다.

---

## 이월 (고치지 않고 기록만)

- ★ **`/etc/sudoers.d/jhkim-bot` 이 mode 0440 이 아니라 sudo 가 통째로 무시하고 있다.**
  그 파일이 주려던 권한은 지금 효력이 없다. 언제부터인지 미확인 — 확인 필요.
- nginx `include sites-enabled/*` 에 확장자 필터가 없다. `.bak` 5개를 옮겨
  conflicting 경고 12 → 2 로 줄였다. **남은 2건(`invoice`·`manager`)은 coolinvoice 쪽
  실제 파일끼리의 중복**이라 손대지 않았다 — Ventago 밖이다.
- **프론트(`ventagoapp` 5001)는 blue/green 이 없다.** 여전히 컨테이너 교체 방식이다.
  Next.js 는 정적 청크 해시가 갈려서 전환 중 stale HTML 문제가 API 보다 까다롭다(별건).
- POS 카탈로그 P95 초과(376ms/341KB) · 소켓 한도 여전히 0 · `/me` 11쿼리 미캐시 ·
  `mobile-stock` 캐시 키에 지점 없음 · 스테이징 테이블 14개 누락 — 전부 종전 그대로.

---

## 다음 세션

**W6 매장별 논리 복구.** codex 가 짚은 함정(2026-08-21 자문):
- **MinIO 는 JSON 에 key 를 넣는 것만으로 백업이 아니다** — 객체 manifest + 존재/해시
  검증 + 별도 version 또는 불변 사본이 필요하다.
- **시퀀스**: 새 ID 로 전면 재매핑이면 안 건드린다. 원 ID 보존이면 각 sequence 를
  복원된 최대값보다 크게 `setval`.
- 이미 있는 것: `store.service.ts` 의 백업본 복원 경로. **내보내기 쪽은 미확인.**

★ Phase 86(레거시 임포트)은 **별도 브랜치에 보존만** 해 뒀다 —
`feature/phase86-legacy-import-full` 의 `31d38e7`(SPEC·RUNBOOK·도구) +
api-ventago `phase86-migrations` 브랜치 `13d468e`(마이그레이션 M1~M7).
**미해결 codex 지적 2건**이 남아 있다: `SaleSource` 에 `LEGACY` 미추가 / `source='legacy'`
판매 취소 시 재고 복원 가드 없음. 재개하려면 거기부터.
