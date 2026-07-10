# Ventago PG10 → PG18 마이그레이션 런북 (Option A: ventago 전용 PG18 클러스터 분리)

> 기준일 2026-07-10 · 방식: dump/restore + pgbouncer 재지정 · 리허설 우선 · PG10 무손상 보존
> **v3 — Phase 0 recon 전부 확정 반영 (포트/collate/pgbouncer 실측값)**

## 0. 목표 & 방식

- 운영 `jhkim-server`의 **공유 PG10 클러스터**(141개 DB, 이 중 ventago 포함)에서 **`ventago` DB만** 같은 호스트의 **새 PG18 클러스터**로 분리 이전.
- 나머지 DB 전부 **PG10 그대로 — 손대지 않음**.
- **pgbouncer의 `ventago` 항목 한 줄만** PG18로 재지정. 롤백 = 그 줄을 PG10으로 되돌리고 reload.
- 리허설로 앱 검증 후 심야 짧은 다운타임에 컷오버.

## 1. 실측 배선도 (recon 확정, 2026-07-10) ★

```
앱 →  pgbouncer :5432  →  [databases] ventago = host=127.0.0.1 port=5433  →  PG10 실서버 :5433
컷오버 후:            →  ventago = host=127.0.0.1 port=5434              →  PG18 신클러스터 :5434
```

| 항목 | 확정값 | 함의 |
|---|---|---|
| PG 버전 / OS | PG **10.23** / Ubuntu **24.04** / PGDG apt | `postgresql-18` apt 공존 설치 |
| **pgbouncer 리스닝** | **5432** (`listen_addr=*`) | 앱이 붙는 포트. 변경 금지 |
| **PG10 실서버** | **5433** | 덤프 소스. pgbouncer 백엔드 타깃 |
| **신규 PG18** | **5434** (빈 포트로 신설) | 5432/5433 충돌 회피 |
| ventago 크기 | **27MB** | dump/restore 수초, 다운타임 몇 분 |
| **ventago collate/ctype** | **C.UTF-8 / C.UTF-8**, UTF8 | ★ 신클러스터 반드시 동일. C.UTF-8은 glibc 버전 무관 → 인덱스 collation 깨짐 위험 사실상 0 |
| ventago owner / ACL | owner **coolsistema**, `ventago_watcher` CONNECT | role 2개 이전 + CONNECT grant 재부여 |
| 확장 / replication | **plpgsql만 / 0** | 호환성·standby 이슈 없음 |
| password_encryption | **md5** | ★ 신 PG18도 md5 → pgbouncer/userlist 무변경 |
| pgbouncer 인증 | `auth_type=md5`, `auth_file=/etc/pgbouncer/userlist.txt` | 신클러스터가 같은 md5 해시 수용해야 함(role 이전으로 해결) |
| pgbouncer 풀 | `pool_mode=transaction`, `default_pool_size=20`, `reserve=10`, `max_client_conn=1000` | ventago 서버측 커넥션 최대 ~30 → PG18 `max_connections=100` 기본으로 충분 |
| **admin_users** | **미설정** (stats_users=coolsistema,postgres 만) | 콘솔 `PAUSE/RESUME` 불가 → 컷오버는 앱 quiesce + SIGHUP reload 방식 채택 |
| 디스크 | 91G 여유 | PG18 클러스터 나란히 세울 공간 충분 |

## 2. Phase 1 — PG18 클러스터 구축 + 리허설 (운영 무중단, read-only 덤프)

```bash
# 1) PG18 설치 (PG10과 공존)
sudo apt update && sudo apt install -y postgresql-18

# 2) ventago 전용 PG18 클러스터 — 포트 5434, locale은 운영과 동일한 C.UTF-8 ★
sudo pg_createcluster --locale C.UTF-8 --port 5434 18 ventago18 -- --encoding=UTF8

# 3) md5 로 맞춤(무변경 컷오버) + pg_hba md5 유지 + 기동
sudo -u postgres psql -p 5434 -c "ALTER SYSTEM SET password_encryption = 'md5';"
#   /etc/postgresql/18/ventago18/pg_hba.conf 의 로컬 인증도 md5 확인
sudo pg_ctlcluster 18 ventago18 restart

# 4) roles 이전 (coolsistema + ventago_watcher, md5 해시 그대로 → 인증 동일)
sudo -u postgres pg_dumpall -p 5433 --globals-only | sudo -u postgres psql -p 5434

# 5) ventago 무중단 덤프(PG10 5433) → PG18(5434) 복원
sudo -u postgres pg_dump -p 5433 -Fc -d ventago -f /tmp/ventago.dump
sudo -u postgres psql -p 5434 -c \
  "CREATE DATABASE ventago OWNER coolsistema ENCODING 'UTF8' LC_COLLATE 'C.UTF-8' LC_CTYPE 'C.UTF-8' TEMPLATE template0;"
sudo -u postgres pg_restore -p 5434 -d ventago -j4 /tmp/ventago.dump

# 6) DB 레벨 CONNECT grant 재부여(운영 ACL 정합) + 통계
sudo -u postgres psql -p 5434 -c "GRANT CONNECT ON DATABASE ventago TO ventago_watcher;"
sudo -u postgres psql -p 5434 -d ventago -c "ANALYZE;"
```

> 참고: dump/restore는 **논리 복제**라 모든 인덱스를 PG18에서 새로 빌드 → 메이저점프 인덱스 손상 원천 배제. collate까지 C.UTF-8로 일치하므로 정렬/유니크 의미도 운영과 동일.

**검증 (리허설 — 운영 무중단):**
```bash
# 행수 대조: 핵심 테이블이 PG10(5433) == PG18(5434) 인지
for t in sales sale_items products users active_sessions; do
  echo -n "$t  10:"; sudo -u postgres psql -p 5433 -d ventago -tAc "select count(*) from $t";
  echo -n "$t  18:"; sudo -u postgres psql -p 5434 -d ventago -tAc "select count(*) from $t";
done
# 시퀀스 최신값 대조도 동일 방식 권장
```
**스모크(스테이징 앱 .env → 127.0.0.1:5434 직결):** 부팅 로그(Pool) · 로그인/세션 · 판매+결제 1건 · 상품/재고 · **보고서 날짜경계(TZ -03:00)** · 프린터 socket.

## 3. Phase 2 — 백업 & 롤백 자산

```bash
DATE=$(date +%Y%m%d_%H%M)
sudo -u postgres pg_dumpall -p 5433 --globals-only -f /tmp/globals_$DATE.sql
sudo -u postgres pg_dump -p 5433 -Fc -d ventago -f /tmp/ventago_cutover_$DATE.dump
sudo cp /etc/pgbouncer/pgbouncer.ini /etc/pgbouncer/pgbouncer.ini.bak.$DATE   # 이미 자동 백업 관행 있음
```
- **롤백 = pgbouncer `ventago` 라인을 `port=5433`(PG10)로 되돌리고 reload.** PG10 ventago 무손상이라 즉시 복귀.

## 4. Phase 3 — 컷오버 (심야 다운타임 창, ventago만)

`admin_users` 미설정이라 콘솔 `PAUSE ventago`는 불가 → **앱 quiesce + SIGHUP reload** 방식(다른 DB 무영향, pgbouncer 재시작 안 함):

```bash
# 1) ventago 앱만 중지(=신규 트랜잭션 차단). 다른 DB 트래픽 무관.
#    (api-ventago 컨테이너 stop 또는 유지보수 모드)

# 2) 최종 델타 덤프 → PG18(5434) drop/recreate 복원 (Phase 1의 5~6단계 반복)
sudo -u postgres pg_dump -p 5433 -Fc -d ventago -f /tmp/ventago_final.dump
sudo -u postgres psql -p 5434 -c "DROP DATABASE IF EXISTS ventago;"
sudo -u postgres psql -p 5434 -c \
  "CREATE DATABASE ventago OWNER coolsistema ENCODING 'UTF8' LC_COLLATE 'C.UTF-8' LC_CTYPE 'C.UTF-8' TEMPLATE template0;"
sudo -u postgres pg_restore -p 5434 -d ventago -j4 /tmp/ventago_final.dump
sudo -u postgres psql -p 5434 -c "GRANT CONNECT ON DATABASE ventago TO ventago_watcher;"
sudo -u postgres psql -p 5434 -d ventago -c "ANALYZE;"

# 3) pgbouncer ventago 라인만 5433 → 5434 로 수정
#    ventago = host=127.0.0.1 port=5434 dbname=ventago
sudo systemctl reload pgbouncer      # SIGHUP: 설정만 재적용, 다른 DB 커넥션 유지

# 4) ventago 앱 재기동 → 스모크(로그인/판매1건/보고서). 실패 시 라인 5433 복귀 + reload + 앱 재기동.
```
안정화 확인 후에도 PG10의 ventago DB는 **공유 클러스터라 즉시 drop 금지** — 롤백 안전망으로 당분간 보존.

## 5. 로컬 / 문서 정리

- 로컬: Homebrew PG18.3(포트 5432, Docker 미사용) → **조치 불필요**. (로컬 ventago는 collate `en_US.UTF-8`이지만 이건 로컬 dev 전용, 운영 신클러스터와 무관.)
- 문서: `CLAUDE.md`·`DATABASE_SETUP.md`의 PG10/PG15·Docker 언급 정리(마지막 단계).

## 6. 호환성 체크리스트

- [ ] PG18 클러스터 **locale = C.UTF-8 / C.UTF-8**, encoding UTF8 ★
- [ ] **password_encryption = md5** (PG18) + pg_hba md5 ★
- [ ] roles `coolsistema` + `ventago_watcher` 이전(md5 해시 포함), DB CONNECT grant 재부여
- [ ] owner = coolsistema 정합 ([[project_ventago_prod_table_ownership]])
- [ ] pgbouncer **ventago 라인만** 5433→5434, `systemctl reload`(재시작 아님)
- [ ] 컷오버 전 pgbouncer.ini 백업, 롤백 문구(→5433) 손 닿는 곳에
- [ ] 확장 plpgsql만 / replication 0 → 추가 위험 없음

### pool 노트 (낭비 방지)
pgbouncer가 ventago를 `transaction` 풀·`default_pool_size=20`(+reserve 10)로 잡으므로 **PG18 서버측 커넥션은 최대 ~30**. PG18 `max_connections`는 **기본 100으로 충분** — 200+로 과설정하면 메모리만 낭비(=규약 위반). ventago 전용 클러스터라 다른 DB와 커넥션 경쟁도 없음(격리 이득). 앱 재시작은 `onModuleDestroy` 정상 종료로 pool 누수 없음.
