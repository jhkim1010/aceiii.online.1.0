# 65-W7 — DB 자격증명 회전 대상 주체 목록

작성: 2026-08-05
대상 커밋: 루트 `a85123c` · `api-ventago@0625429` · `ventago-app@461ff5e` · `vw-agent`(루트 내 디렉터리)
성격: **조사 결과 정리.** 이 문서 단계에서 회전은 실행하지 않는다.

> **이 문서에는 비밀번호 값을 적지 않는다.** 위치만 가리킨다. 값이 필요하면 해당 파일을 직접 열어 본다.

---

## 0. 선결론 — W7 도 절반은 이미 배포돼 있었다

`be8c387` **2026-07-29** — `sec(credentials): Phase 65 W7 — 마이그레이션 10파일 PGPASSWORD 평문 제거(환경변수
참조) + DB/JWT 시크릿 폴백 제거(미설정 시 부팅 실패)`. W6 커밋(`c23ab35`)과 같은 날이다.

| 항목 | 상태 | 근거 |
|---|---|---|
| W7-1 마이그레이션 평문 `PGPASSWORD` 제거 | **완료** — 10파일 전부 `"$PGPASSWORD"` 참조로 바뀜 | `api-ventago/migrations/*.sql`, `extract-and-build-payload.sh:13` |
| W7-2 시크릿 폴백 제거 | **완료** — `requireSecret()` 로 미설정 시 부팅 실패, `email-secret` 고정 폴백 제거 | `src/config/env.config.ts:11-30`, `src/common/*/email-secret.ts` |
| W7-3 **비밀번호 회전** | **미실행** ← 이 문서의 대상 | — |
| W7-4 시크릿 스캔 게이트 | **미실행** | — |
| (W7 범위 밖이었던) **루트 저장소 평문 잔존** | **미처리** — `be8c387` 은 `api-ventago` 만 건드렸다 | 아래 §2 |

**결론: 앱 코드는 깨끗하다. 남은 노출은 (a) 루트 저장소의 문서·스크립트 평문, (b) 회전 미실행.**
(a)를 지워도 git 이력에 값이 남으므로 **(b) 회전이 실제 차단 조치**다.

---

## 1. 회전 대상 계정 — 3개

저장소 근거로 확인된 DB 계정은 하나가 아니라 **셋**이다. 65-PLAN 은 `coolsistema` 하나만 상정했다.

| # | 계정 | 용도 | 평문 노출 |
|---|---|---|---|
| A | `coolsistema` | 앱 본체(api-ventago) — DB owner | **있음** — 루트 저장소 15파일 |
| B | `postgres` | 로컬 Mac PG18 superuser (마이그레이션·임포트 실행용) | **있음** — 3파일 |
| C | `ventago_watcher` | vw-agent 감시 전용 read-only | 없음(`.env` 참조만) — 다만 A/B 회전 시 함께 검토 |

---

## 2. 계정 A `coolsistema` — 평문 잔존 위치 (저장소 근거, 전수)

`api-ventago` / `ventago-app` 소스에는 **0건**. 전부 루트 저장소의 문서·설정·스크립트다.

**실행 가능한 것 (우선 제거 대상)**
| 파일 | 성격 |
|---|---|
| `.codex/config.toml:6` | MCP postgres 서버 접속 문자열 통째 (`localhost:15432`) |
| `pre-deploy.sh:53,103` | 배포 전 스크립트 |
| `scripts/measure-cockpit-pool.sh:55` | 측정 스크립트 |

**문서 (실행되진 않지만 값이 그대로 노출)**
`AGENTS.md:245` · `.gsd/spec-codigo-import-review.md:65` · `docs/superpowers/plans/2026-05-11-product-promotions.md`(2곳) ·
`docs/superpowers/plans/2026-06-11-mobile-access-terminal-binding.md`(3곳) ·
`docs/superpowers/specs/2026-05-29-shared-folders-google-drive-design.md:636` ·
`.planning/phases/` 하위 6파일(14-01 / 25-17 / 26-01 / 26-02 / 29-02 / 29-VALIDATION / 33.1-03)

> `CLAUDE.md` 에 있던 1건은 2026-08-05 문서 정리 중 제거됨(`e804678`, 부수효과).

### 회전 시 갱신해야 할 주체

**저장소로 확인됨 (실측 완료)**

| 주체 | 위치 | 갱신 방법 |
|---|---|---|
| api-ventago 앱 | 운영 서버 `.env` 의 `DATABASE_PASSWORD` | 컨테이너 재기동 필요. `env.config.ts` 가 미설정 시 **부팅을 실패시키므로** 오타가 나면 즉시 드러난다(안전) |
| `.codex/config.toml` | 로컬 개발 도구(MCP postgres) | 파일 수정. **포트 15432 의 정체 확인 필요** — 로컬 PG 는 5432, 운영은 5434 다. SSH 터널일 가능성 |
| `pre-deploy.sh` / `scripts/measure-cockpit-pool.sh` | 로컬·운영 실행 스크립트 | 환경변수 참조로 교체(W7-1 이 마이그레이션에 한 것과 동일 패턴) |

**서버 확인 필요 (이 세션에서 미확인 — SSH 불가)**

| 주체 | 확인 명령 |
|---|---|
| **pgbouncer** ★ | `sudo cat /etc/pgbouncer/userlist.txt` — `coolsistema` 해시가 여기 박혀 있다. **여기를 안 바꾸면 앱이 전부 죽는다.** SCRAM 이면 PG 쪽 변경 후 해시 재생성 필요 |
| 백업 크론 (03:17) | `sudo crontab -l`, `sudo -u postgres crontab -l`, `ls /etc/cron.d/` |
| Jenkins | 잡 설정·Credentials 에 DB 접속이 있는지 (`api-new-coolsistema` / `front-coolsistema`) |
| 운영자 `.pgpass` | `ls -l ~/.pgpass /root/.pgpass /var/lib/postgresql/.pgpass` |
| `venpsql` 별칭 | `type venpsql`, `grep -rn venpsql ~/.bashrc ~/.zshrc /etc/profile.d/` |
| 다른 앱의 공유 사용 | `sudo -u postgres psql -p 5434 -c "SELECT DISTINCT usename, application_name, client_addr FROM pg_stat_activity WHERE usename='coolsistema'"` ← **가장 확실한 실측.** 목록에 없는 주체는 회전 후 죽는다 |

---

## 3. 계정 B `postgres` (로컬 superuser) — 평문 잔존

| 파일 | 성격 |
|---|---|
| `api-ventago/migrations/2026-06-25-legacy-imports.sql:8` | 주석 내 접속 문자열 |
| `docs/superpowers/plans/2026-07-09-factura-electronica-plan-1-backend-core.md:108` | 실행 예시 |
| `vw-agent/migrations/001_create_ventago_watcher.sql:18` | 실행 예시 |

로컬 Mac 전용이라 운영 노출은 아니지만, **공개 저장소가 아니어도 값이 이력에 남는다.** A 와 같이 정리한다.

---

## 4. 계정 C `ventago_watcher` (vw-agent)

- 정의: `vw-agent/migrations/001_create_ventago_watcher.sql` — SELECT-only, `statement_timeout=3s`, `application_name='vw-agent-watcher'`
- 비밀번호: `vw-agent/.env` 의 `PG_WATCHER_PASSWORD` (저장소에는 `.env.example` 만 있고 값 없음 — **깨끗**)
- 회전 필요성: A/B 와 별개 계정이므로 필수는 아니나, 같은 창에서 함께 도는 게 운영상 편하다

### ★ 부수 발견 — vw-agent 가 구 클러스터를 보고 있을 수 있다

`vw-agent/.env.example:21-25` 가 **`PG_PORT=5433`** 을 기본값으로 두고 "운영: 호스트 PG10, 5433" 이라고 설명한다.
2026-07-10 PG18 컷오버 이후 **5433 은 롤백 안전망일 뿐 실사용 클러스터가 아니다**(현재는 5434).
운영 `.env` 가 예시대로면 감시 에이전트가 **아무도 안 쓰는 DB 를 감시**하고 있다 — 장애가 나도 조용하다.

확인: `ssh jhkim-server "docker exec vw-agent env | grep PG_PORT"` 또는 서버의 `vw-agent/.env`.
W7 회전과 별개로 **먼저 확인할 가치가 있다.** (W8 장애 감지 미착수와 겹치는 지점)

---

## 5. 회전 실행 순서 (승인 후)

파괴적 작업이다. 단독 배포 창에서, 다른 wave 와 겹치지 않게.

1. **사전 실측** — `pg_stat_activity` 로 `coolsistema` 실제 접속 주체 전수 확보(§2 마지막 명령). 목록에 없는 주체는 회전 후 조용히 죽는다
2. **롤백 지점** — 현재 pgbouncer `userlist.txt` 백업, 현재 비밀번호 보관
3. `ALTER ROLE coolsistema PASSWORD '<신규>'` (PG18 5434)
4. pgbouncer `userlist.txt` 갱신 → `pgbouncer` reload
5. 앱 `.env` `DATABASE_PASSWORD` 갱신 → 컨테이너 재기동 → `/health` 확인
6. 백업 크론 · Jenkins · `.pgpass` · `venpsql` 갱신
7. **검증** — 판매 1건 왕복, 다음 날 03:17 백업 성공 확인, `pg_stat_activity` 에서 실패 접속 0
8. 구 비밀번호 폐기 + 저장소 평문 제거(§2·§3) + W7-4 스캔 게이트 추가

**되돌리기:** 3~6 을 역순으로. 5 에서 실패하면 앱이 부팅을 거부하므로(W7-2 효과) 조용한 반쪽 상태는 생기지 않는다.

---

## 6. 이 세션에서 확인하지 못한 것 — **해소됨 (2026-08-05)**

~~운영 서버 SSH 가 막혀 있다~~ → `jhkim` 계정으로 접속 확보. 원인은 키가 아니라 `PermitRootLogin no` 였다.
아래 §7 에 전수 결과를 기록한다.

---

## 7. 서버 확인 결과 (2026-08-05, 전부 조회성)

### 회전이 실제로 건드려야 하는 것 — **2곳**

| # | 주체 | 확인 결과 | 조치 |
|---|---|---|---|
| 1 | **pgbouncer `userlist.txt`** ★ | `/etc/pgbouncer/userlist.txt` — **148개 항목**, `auth_type = md5` | **md5 해시 재생성 필수.** 평문이 아니라 `md5(password+username)` 해시가 들어간다. 이 파일을 안 고치면 **앱 전체 정지** |
| 2 | **`/home/jhkim/.pgpass`** | 8줄 전부 `coolsistema` (포트 5432·5433·5434·6432) | 8줄 모두 갱신. **포트 6432 는 리스닝하지 않는다** — 죽은 항목이니 정리 대상 |

### 회전과 무관한 것 — 계획서의 가정을 정정한다

| 주체 | 계획서 가정 | **실제** |
|---|---|---|
| **백업 크론 03:17** | 회전 대상 | **무관.** `postgres` 크론 `17 3 * * *` → `pg_backup_ventago.sh`. **포트 5434 직결**(pgbouncer 아님), `postgres` 로컬 peer 인증, **스크립트에 비밀번호 없음**. 산출물 `ventago_20260805_031701.dump` 정상 생성 확인 |
| **Jenkins** | 회전 대상 | **무관.** `credentials.xml` 의 `coolsistema` 는 `BasicSSHUserPrivateKey` — **SSH 개인키**이지 DB 비밀번호가 아니다. 게다가 `api-new-coolsistema` job 은 이 자격증명을 참조하지 않는다 |
| **`venpsql`** | 회전 대상 | **무관.** `/usr/local/bin/venpsql` 에 자격증명 0건 (`.pgpass` 경유) |

### 접속 주체 실측 (`pg_stat_activity`)

```
coolsistema | 127.0.0.1 |       | 3      ← 전부 pgbouncer 경유(로컬)
postgres    |           | psql  | 1
```

원격에서 직접 붙는 `coolsistema` 주체는 **없다**. 회전 후 조용히 죽을 외부 주체는 현재 관측되지 않는다.
다만 이건 **스냅샷**이다 — 간헐적으로만 붙는 주체(주 1회 배치 등)는 여기 안 잡힌다.

### 별건 — 감시 에이전트가 잘못된 클러스터를 보고 있다 ⚠

```
docker exec vw-agent env → PG_PORT=5433, PG_HOST=host.docker.internal
pg_lsclusters → 10/main 5433 online (롤백 안전망)  /  18/ventago18 5434 online (운영)
```

`.env.example` 의 기본값(`5433`)이 운영에 그대로 들어가 있다. **PG10 은 살아 있어서 접속은 성공하고,
그래서 에이전트는 계속 "정상" 을 보고한다.** 실제 운영 DB(5434)가 무슨 일이 나도 이 감시는 조용하다.

회전과 독립된 문제이며 **회전보다 먼저 고치는 편이 낫다** — 회전 중 이상을 감지할 수단이 지금은 없는 셈이다.

### 회전 순서 (§5 를 실측으로 갱신)

1. `ALTER ROLE coolsistema PASSWORD '<신규>'` (PG18 **5434**)
2. **`userlist.txt` 의 md5 해시 재생성 → `pgbouncer` reload** ★ 여기를 빠뜨리면 앱 전체 정지
3. 앱 `.env` `DATABASE_PASSWORD` → 컨테이너 재기동 → `/health`
4. `/home/jhkim/.pgpass` 8줄 갱신
5. 검증 — 판매 1건 왕복 · `pg_stat_activity` 실패 접속 0 · **다음 날 03:17 백업**(무관하지만 확인은 한다)

백업·Jenkins·venpsql 단계는 **삭제한다**. 회전 표면이 계획서보다 좁다.
