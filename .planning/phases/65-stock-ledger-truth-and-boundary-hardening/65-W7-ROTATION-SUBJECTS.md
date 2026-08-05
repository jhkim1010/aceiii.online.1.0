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

## 6. 이 세션에서 확인하지 못한 것

운영 서버 SSH 가 막혀 있다 — 이 세션의 SSH 키는 GitHub 에만 등록됐고 srv803182 에는 없다(`Permission denied (publickey)`).
§2 의 "서버 확인 필요" 6항목과 §4 의 vw-agent 실제 포트가 **전부 미확인**이다.
서버 `~/.ssh/authorized_keys` 에 이 세션 공개키를 추가하면 나머지도 채울 수 있다.
