# Phase 74: 백업 RPO 축소 · 복구 검증 — Context

**Created:** 2026-08-06
**Source:** 사용자 요청("백업(병렬) 서버 준비") → 현황 실측으로 범위 재조정
**결론 요약:** 백업은 **이미 있고 건강하다**. 문제는 **주기(24시간)** 와 **검증·알람 부재**다.

---

## 왜 이 phase 인가

사용자의 최초 요청은 "안전성을 위한 병렬(백업) 서버"였다. 실측 결과 **서버 이중화보다 먼저 닫아야 할 구멍이
더 싸고 더 크다**는 것이 확인됐다.

- 서버 2호기는 **서버가 죽는 것**을 막는다. 그러나 현재 실질 위험은 서버 하드웨어 고장이 아니라
  **하루치 데이터 손실**이다(RPO 24시간).
- 2호기·read replica 는 잘못된 `DELETE` 나 논리적 손상을 **그대로 복제**한다. 백업만이 그것을 되돌린다.
- 서버 2호기는 `D-63-2` 에서 보류 결정된 상태이고, 그 결정을 뒤집을 근거가 아직 없다.
  (부하 실측이 목표치 미달이라는 증거가 없고, 크론 리더 중복·pool 예산 재산정 등 선행 부채가 남아 있다.)

따라서 이 phase 는 **이중화를 다루지 않는다.** RPO 를 24시간에서 수 초로 줄이고,
백업이 실제로 복구되는지 증명하고, 실패했을 때 알게 만든다.

---

## 현재 상태 (2026-08-06 운영 서버 실측)

### 작동 중인 것 — 손대지 않는다

| 항목 | 실측값 | 근거 |
|---|---|---|
| 논리 백업 | 매일 **03:17**, `pg_backup_ventago.sh` | `sudo -u postgres crontab -l` |
| 접속 경로 | **PG18 5434 직결** (pgbouncer 우회) | `docs/DROPBOX_BACKUP_SETUP.md` |
| 산출물 | `ventago_YYYYMMDD_HHMMSS.dump` (custom) + `globals_*.sql.gz` | 디렉터리 목록 |
| 서버 보관 | **14일 로테이션** (7/23~8/6 = 15개 확인) | 디렉터리 목록 |
| 오프사이트 | 매일 **03:40** rclone → `dropbox:ventago_pg_backups`, 무기한 | `dropbox_sync.log` |
| 대역폭 | `--bwlimit 8M` — 운영 트래픽 무영향 | `scripts/dropbox_sync.sh` |
| 최근 실행 | 8/5·8/6 연속 **업로드 성공** | `dropbox_sync.log` |
| dump 크기 | 2.0 MB (7/29 이후 1.3M→1.9M, Stock Vistas 반영) | 디렉터리 목록 |

**pgbouncer 우회는 이미 올바르게 돼 있다.** pgbouncer 는 transaction pooling 이라
세션 스냅샷이 필요한 `pg_dump` 가 정상 동작하지 않는다. 5434 직결이라 앱 pool 을 전혀 소비하지 않는다.
이 설계는 **유지**한다.

### 결함

| # | 결함 | 심각도 | Wave |
|---|------|--------|------|
| 1 | **RPO 24시간** — `archive_mode=off` 로 WAL 미보관. 03:17 이후 장애 시 그날 영업(판매·재고·수금) 전량 소실 | 치명 | W3 |
| 2 | **복구 리허설 0건** — 덤프가 실제 restore 되는지 한 번도 검증되지 않음. 검증 안 된 백업은 백업이 아니다 | 치명 | W4 |
| 3 | **백업 내용 미검증** — 덤프에 205개 테이블이 다 들어 있는지 확인하는 장치 없음. 플래그 실수로 반쪽 덤프여도 파일 크기만 정상으로 보인다 | 높음 | W1 |
| 4 | **실패 알람 없음** — 크론이 `>/dev/null 2>&1` 로 출력을 버려 cron mail 조차 안 간다. `dropbox_sync.sh` 의 `exit 1` 도 아무 데도 도달하지 않는다. 며칠 조용히 실패해도 모른다 | 높음 | W2 |
| 5 | **오프사이트 평문** — 고객 개인정보·AFIP 세금 데이터가 암호화 없이 Dropbox 에 상주. 계정 침해 = 전 매장 데이터 유출 | 높음 | W5 |
| 6 | **DB 밖 자산 미백업** — `../certificados`(AFIP 인증서, RW·TA 캐시 포함), `../manuales` 가 백업 대상 밖. 인증서 재발급은 AFIP 절차라 즉시 복구 불가 | 중 | W5 |
| 7 | **Dropbox 단일 실패점** — rclone refresh token 만료·계정 잠김 시 오프사이트가 조용히 끊긴다. 결함 4 와 겹쳐 무기한 무감지 | 중 | W2 |

### 유리한 조건

- **`wal_level=replica` 가 이미 켜져 있다.** 연속 WAL 확보에 필요한 값은 충족돼 있어
  **`wal_level` 변경도, 서버 재시작도 필요 없다.**
- **DB 가 작다** (dump 2.0 MB). WAL 생성량도 작을 것이므로 `pg_receivewal` 의 디스크·대역폭 비용이 사소하다.
  복구 리허설도 수 분 내 끝난다.
- **Telegram 알림 경로가 이미 있다.** `tools/uptime-watchdog.sh` 가 Mac launchd 60초 주기로
  운영 `/api/health` 를 외부에서 감시하고 실패 시 Telegram 을 보낸다. 같은 패턴·같은 자격증명을 재사용한다.
- **복구 검증에 쓸 불변식이 이미 있다.** `v_stock_balance_drift`(0행) / `v_stock_tenant_leak`(0행) 은
  Stock Vistas 에서 만든 감시 뷰다. 복구된 DB 에서 이 두 뷰가 0행이면 재고 원장이 온전하다는 뜻이다.
  **새 검증 장치를 만들 필요가 없다.**

### 정정 사항

`ROADMAP.md:1206` 는 **Phase 65 W8(장애 감지)을 「미착수」로 표기하지만 실제로는 대부분 구현돼 있다.**

| W8 태스크 | 실제 상태 | 근거 |
|---|---|---|
| 8-1 `/health` (DB SELECT 1 + 5초 캐시 + `@Public`) | **구현됨** | `api-ventago/src/app/health/health.controller.ts` |
| 8-2 docker healthcheck + `restart: always` | **구현됨** | `api-ventago/docker-compose.yml` |
| 8-3 외부 uptime 감시 → Telegram | **★ 스크립트만 존재 · 2026-08-06 까지 미작동** | 아래 「실행 상태 실측」 참조 |
| 8-4 `enableShutdownHooks()` | **구현됨** | `api-ventago/src/main.ts:135` |
| 8-5 알람 2종 (pool waiting 지속 · outbox lease 초과) | **미구현** | `api-ventago/src/database/database.module.ts:276` 은 로그만 남김 |

이 표기 정정은 W1 에서 처리한다. **8-5 는 이 phase 범위 밖**이다(백업과 무관 — Phase 65 잔여로 남긴다).

### ★ 실행 상태 실측 (2026-08-06) — "코드가 있다"와 "돌고 있다"는 다르다

위 표를 처음 쓸 때 **코드 존재만 보고 「구현·배포됨」으로 판단하는 오류**를 범했다.
실제 실행 상태를 확인해 보니 launchd 에이전트가 **하나도 돌고 있지 않았다.**

```
$ ls -d /Users/marcoskim/Trabajos_Programming/ACE_online_1.0
  → 옛 경로 없음
$ launchctl list | grep ventago
  → (출력 없음)
```

원인은 **저장소 경로 이동**이다. `Trabajos_Programming/ACE_online_1.0` →
`TrabajoProgramming/aceiii.online.1.0` 으로 옮겼는데 plist 4개가 옛 경로를 가리킨 채 남았고,
`launchctl list` 가 비어 있는 것으로 보아 **등록조차 해제된 상태**였다.

| 에이전트 | 역할 | 상태 |
|---|---|---|
| `com.ventago.uptime-watchdog` | 외부에서 `/api/health` 60초 감시 | **미작동** |
| `com.ventago.trello-sync` | Trello 동기화 | **미작동** |
| `com.ventago.agent-runner` | 작업 큐 러너 | **미작동** |
| `com.ventago.git-fetch-notify` | 원격 변경 알림 | **미작동** |

즉 **서버가 죽어도 아무도 모르는 상태**였다. Phase 65 W8-3 이 막으려던
"2026-07-25 재부팅 후 2시간 무감지 다운"의 재발 방지 장치가 그대로 꺼져 있었다.
`.planning/trello-inbox/` 리포트들이 몇 달째 "동기화 복구 필요"를 반복 기록한 것도 같은 원인으로 보인다.

**같은 날 조치 완료** — 경로 교정(plist 4개 + `git-fetch-notify.sh`) 후
신규 `com.ventago.backup-freshness` 포함 **5개 재등록**, `launchctl list` exit code 전부 0.
`uptime-watchdog` / `backup-freshness` 수동 실행 OK 확인.

**교훈:** 배포 여부는 코드가 아니라 **실행 상태**로 확인해야 한다.
그래서 Phase 75 W1(일일 자동 점검)에 **launchd 에이전트 생존 확인**을 항목으로 추가했다(Phase 75 결함 12).
감시기 자체를 감시하지 않으면 같은 일이 반복된다.

### 정리 대상

- `crontab -l` (jhkim) 의 `00 06 18 04 * bash /home/jhkim/pgbouncer_switch.sh` — 2026-04-18 06:00 **1회성 잔재**.
  이미 지난 날짜라 다시 실행되지 않지만 crontab 을 읽는 사람을 혼란시킨다.
- `/home/jhkim/pg_backups/pg_backup.sh` — 도커 PG14 컨테이너를 바라보는 옛 스크립트.
  크론 미등록이라 무해하나 `docs/DROPBOX_BACKUP_SETUP.md` 가 이미 삭제를 권고한 상태.

---

## 범위 밖 (명시적)

- **서버 2호기 · read replica · nginx LB** — `D-63-2` 보류 결정 **유지**. 이 phase 는 내구성(durability)만 다루고
  가용성(availability)은 다루지 않는다. 착수 조건은 `66-PLAN.md:109` 의 "컨테이너 2대 결정" 그대로다.
- **자동 failover (Patroni/repmgr)** — 2호기 없이 의미 없다. 위와 한 묶음.
- **`archive_mode=on` 전환** — PostgreSQL 재시작이 필요하다. `pg_receivewal` 이 재시작 없이 같은 목적을
  달성하므로 **이번엔 하지 않는다.** 별도 정비창이 생기면 재검토한다(둘은 병행 가능하며 배타적이지 않다).
- **pgBackRest / Barman 도입** — 현재 DB 크기(2 MB dump)에 비해 운영 복잡도가 과대하다.
  DB 가 수십 GB 로 커지거나 증분 백업이 필요해질 때 재검토.
- **MinIO 를 백업 저장소로 사용** — MinIO 는 **같은 서버**에 있다. 서버가 죽으면 백업도 같이 죽으므로
  오프사이트 요건을 만족하지 못한다. Dropbox 를 유지한다.
- **Phase 65 W8-5 알람 2종** — 백업과 무관. Phase 65 잔여로 남긴다.
- **애플리케이션 코드 변경** — 이 phase 는 **운영 스크립트·크론·문서만** 다룬다.
  `api-ventago` / `ventago-app` 빌드·배포가 필요 없다. 따라서 Jenkins 파이프라인을 타지 않는다.
