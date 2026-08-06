# Phase 74: 백업 RPO 축소 · 복구 검증 — Plan

**Created:** 2026-08-06
**Source:** `74-SPEC.md` (R1~R6)
**Waves:** 5
**특징:** 애플리케이션 코드 변경 0 — 운영 스크립트·크론·문서만. **Jenkins 빌드·배포를 타지 않는다.**

---

## 실행 순서

```
W1{검증 기준선} · W2{실패 알람}   ← 병렬 · 무위험 · 승인 불필요 · 먼저 끝낸다
                ↓
W3{연속 WAL}                      ← ★ 승인 게이트 (복제 슬롯 디스크 위험)
                ↓
W4{복구 리허설}                    ← W3 후여야 PITR 까지 검증 가능
                ↓
W5{암호화 · DB 밖 자산}            ← W4 와 일부 병렬 (리허설에 1회 포함)
```

---

## W0. 사전 실측 — 착수 전 필수

계획을 세우기 전에 **먼저 알아야 하는 값**이다. 추측으로 진행하지 않는다.

| # | 태스크 | 명령 |
|---|---|---|
| 0-1 | **현행 백업 스크립트 내용 확인** — 플래그·대상 DB·로테이션 로직 | `sudo -u postgres cat /var/lib/postgresql/pg_backups/pg_backup_ventago.sh` |
| 0-2 | **현행 덤프 내용 검증** (R2 기준선) | `sudo -u postgres pg_restore -l <최신>.dump \| grep -c 'TABLE DATA'` |
| 0-3 | DB 실크기 · 일 WAL 생성량 | `psql -p 5434 -c "SELECT pg_size_pretty(pg_database_size('ventago'));"` · `SELECT pg_walfile_name(pg_current_wal_lsn());` 24h 간격 2회 |
| 0-4 | 디스크 여유 (슬롯 안전판 산정 근거) | `df -h /var/lib/postgresql` |
| 0-5 | 현재 가동 시각 (재시작 0회 증명의 기준점) | `psql -p 5434 -c "SELECT pg_postmaster_start_time();"` |
| 0-6 | **로컬↔운영 테이블 목록 대조** (211 vs 205 차이 원인 확정) | 운영: `psql -p 5434 -Atc "SELECT table_schema\|\|'.'\|\|table_name FROM information_schema.tables WHERE table_type='BASE TABLE' AND table_schema NOT IN ('pg_catalog','information_schema') ORDER BY 1;"` → 로컬 5432 동일 쿼리와 `diff` |

- **게이트 결과 (2026-08-06 실측): PASS.** `pg_restore -l ... | grep -c 'TABLE DATA'` = **211**.
  로컬 public 스키마 205개(`.planning/intel/db-schema-tables.md`, 같은 날 재생성) 이상이므로 **반쪽 덤프가 아니다.**
  W1 기준선은 **211** 로 확정한다.
  **`CLAUDE.md:66` 등에 남아 있는 "133개"는 오래된 값이므로 근거로 쓰지 않는다** — W1-7 에서 정정.

- **★ 파생 발견 1 — 로컬↔운영 스키마 차이 약 6개 (신규 태스크 0-6).**
  205(로컬 public) vs 211(운영 덤프)의 차이는 ① 운영에만 있는 백업 테이블 잔재 ② `public` 외 스키마
  ③ **한쪽에만 적용된 마이그레이션** 중 하나다. ③이면 「DB 마이그레이션 적용 규칙」이 경고하는
  dev-운영 분기 상태이므로 배포 후 500(`relation does not exist`) 사고로 이어진다.
  W1 착수 전 목록을 대조해 원인을 확정한다. **이 phase 범위 밖 원인이면 별도 이슈로 분리**하고 여기서 고치지 않는다.

- **★ 파생 발견 2 — `pg_restore` 는 `--cluster` 필수 (W4 에 반영).**
  실측 시 `Warning: No existing cluster is suitable as a default target` 이 출력됐다.
  `-l`(목록)은 접속하지 않아 무해했지만, **실제 복구에서는 Debian `pg_wrapper` 가 대상 클러스터를
  선택하지 못해 실패하거나 엉뚱한 클러스터를 향한다.** `74-RUNBOOK.md` 의 모든 복구 명령은
  `--cluster 18/<클러스터명>` 또는 `/usr/lib/postgresql/18/bin/pg_restore` 절대 경로를 **반드시** 포함한다.
  장애 상황에서 처음 마주치면 안 되는 함정이다.
- 0-5 값을 기록해 둔다. W3 완료 후 같은 값이어야 "재시작 0회"가 증명된다.

---

## W1. 백업 내용 자동 검증 (R2) — 무위험 · 병렬

| # | 태스크 | 대상 |
|---|---|---|
| 1-1 | `pg_backup_ventago.sh` 말미에 `pg_restore -l` 항목 수 검사 추가. 하한 = **직전 성공값의 90%** (고정 숫자 금지 — 테이블 증감에 견디게) | 서버 스크립트 |
| 1-2 | `pg_restore -l` 자체 실패(손상 덤프) → 즉시 exit 1 | 서버 스크립트 |
| 1-3 | 검사 결과를 `verify.log` 에 append (항목 수 · 하한 · 판정) | 서버 |
| 1-4 | 직전 성공값 저장 파일(`verify.baseline`) 도입 — 첫 실행 시 0-2 값으로 초기화 | 서버 |
| 1-5 | **의도적 손상 테스트** — 덤프 사본을 truncate 해 검사가 실패로 잡는지 확인 | 서버 (사본만) |
| 1-6 | 스크립트를 `scripts/pg_backup_ventago.sh` 로 저장소에 **커밋** — 현재 서버에만 존재해 서버 소실 시 스크립트도 소실 | 저장소 |
| 1-7 | **문서 정정** — 「133개 테이블」이 실제 205개다. `CLAUDE.md:66` · `.planning/docs/ventago-handbook.html` · `ventago-system-map.html` · `39/40/42/56-CONTEXT.md`. 근본을 안 고치면 다음 phase 에서 재발한다 | 저장소 |
| 1-8 | **Phase 65 W8 표기 정정** — `ROADMAP.md:1206`(wave 표) + `ROADMAP.md:377`(요약행) **2곳**. 8-1~8-4 는 구현·배포됨, 미구현은 8-5 뿐 | `ROADMAP.md` |

- **게이트:** 정상 덤프 통과 · 손상 덤프 실패 감지 · `verify.log` 기록 확인
- **주의:** 1-1 수정 중 스크립트가 깨지면 백업 자체가 멈춘다. **수정 전 사본 필수**,
  수정 후 다음 03:17 실행 성공을 확인하기 전까지 완료로 표시하지 않는다.

---

## W2. 실패 알람 (R4) — 무위험 · 병렬

| # | 태스크 | 위치 |
|---|---|---|
| 2-1 | `notify.sh` — `tools/uptime-watchdog.sh` 의 `send_telegram()` 을 그대로 이식한 공용 알림 함수. 자격증명은 `.uptime.env` 와 동일 방식(gitignore) | 서버 `pg_backups/` |
| 2-2 | `pg_backup_ventago.sh` · `dropbox_sync.sh` · W1 검증 실패 경로에 2-1 연결 | 서버 |
| 2-3 | 크론에서 `>/dev/null 2>&1` 제거 → 스크립트 내부 로깅으로 대체 | postgres crontab |
| 2-4 | **부재 감지(dead man's switch)** — 최신 덤프 mtime > 26시간이면 알림. **Mac launchd 에서 실행** (서버가 죽으면 서버 안 감시도 죽는다). ssh 로 mtime 조회 → 임계 초과 시 Telegram | Mac `tools/backup-freshness-watchdog.sh` |
| 2-5 | 2-4 를 `com.ventago.backup-freshness.plist` 로 등록 (StartInterval 3600). `uptime-watchdog` plist 와 같은 패턴 | Mac launchd |
| 2-6 | **성공 알림 금지 확인** — 정상 경로에서 Telegram 호출 0건 | 검토 |
| 2-7 | 잔재 정리 — jhkim crontab 의 1회성 `pgbouncer_switch.sh`(2026-04-18) 제거 · `/home/jhkim/pg_backups/pg_backup.sh` 삭제 | 서버 |

- **게이트:** 백업 인위 실패 → 60초 내 Telegram · 덤프 mtime 조작 → Mac 워치독 알림 ·
  정상 운영 24시간 동안 알림 0건
- **주의:** 2-7 의 crontab 편집은 백업 크론과 같은 파일을 건드릴 수 있다. **사본 후 진행.**

---

## W3. 연속 WAL — RPO 24시간 → 수 초 (R1) ★ 승인 게이트

**이 wave 는 사전 승인 없이 착수하지 않는다.** 잘못하면 디스크가 차서 DB 가 정지한다.

| # | 태스크 | 비고 |
|---|---|---|
| 3-1 | **안전판 먼저** — `ALTER SYSTEM SET max_slot_wal_keep_size = '10GB'` + `pg_reload_conf()`. 0-4 디스크 여유 기준으로 값 조정. **재시작 불필요** | 이것을 3-2 보다 **먼저** 한다 |
| 3-2 | `SHOW max_slot_wal_keep_size` 로 적용 확인 후 물리 복제 슬롯 생성 | 순서 역전 금지 |
| 3-3 | `pg_receivewal` systemd 서비스 등록 — `Restart=always`, 출력 → `/var/lib/postgresql/pg_wal_archive/`. **`--synchronous` 사용 금지** (운영 커밋이 수신기에 묶인다) | `infra/` 에 유닛 파일 커밋 |
| 3-4 | 주 1회 `pg_basebackup` 크론 — WAL 재생 시작점. 논리 덤프만으로는 PITR 불가 | 일요일 04:00 제안 (03:17 백업·03:40 업로드와 충돌 회피) |
| 3-5 | WAL 아카이브 14일 로테이션 + 슬롯 lag 감시 → W2 알람 연결 | 슬롯 lag 급증 = 수신기 사망 신호 |
| 3-6 | 재시작 0회 증명 — `pg_postmaster_start_time()` 이 0-5 값과 동일한지 확인 | |

- **승인 필요 사항 (실행 전 사용자에게 보고):**
  1. 0-4 디스크 여유 실측값 + 제안 `max_slot_wal_keep_size` 값
  2. 0-3 일 WAL 생성량 → 14일 보존 시 예상 점유량
  3. 슬롯 생성 SQL 전문
- **게이트:** 슬롯 active=true · WAL 세그먼트 지속 생성 · `max_slot_wal_keep_size` 설정됨 ·
  **재시작 0회** · 수신기 강제 종료 시 알람 발생 + 슬롯이 안전판에서 멈춤(디스크 무한 증가 없음)
- **롤백:** 수신기 정지 → 슬롯 drop. 슬롯만 지우면 원상 복귀되며 기존 백업 경로는 무영향.

---

## W4. 복구 리허설 (R3) — W3 이후

| # | 태스크 | 비고 |
|---|---|---|
| 4-1 | 임시 클러스터 생성 (**포트 5435**) — `pg_createcluster`. 운영 5434·로컬 5432 **미접촉** | 리허설 후 제거 가능 |
| 4-2 | 최신 덤프 `pg_restore` + `globals_*.sql.gz` 복원 → **소요 시간 측정** | RTO 실측값 |
| 4-3 | 행수 대비 — `sales` · `sale_items` · `stocks` · `stock_balances` · `products` · `users` | 운영과 대조 |
| 4-4 | **기존 불변식 뷰 재사용** — `v_stock_balance_drift` 0행 · `v_stock_tenant_leak` 0행 | 새 검증 장치 만들지 않는다 |
| 4-5 | role `coolsistema` + 시퀀스 owner 정상 여부 (「DB 마이그레이션 적용 규칙」의 owner 이전 원칙과 동일 지점) | permission denied 재발 방지 |
| 4-6 | **PITR 리허설** — 기저 백업 + WAL 재생으로 임의 시각 도달 | W3 완료 후에만 가능 |
| 4-7 | `74-RUNBOOK.md` 작성 — 실제 장애 시 **이 문서만 보고** 복구 가능해야 한다. 측정된 RTO 기재 | 추정 금지 |
| 4-8 | **분기 1회 반복** 고정 — 크론 또는 캘린더. 1회성 검증은 6개월 뒤 무의미 | |
| 4-9 | 임시 클러스터 정리 + 운영 무영향 확인 (`pg_postmaster_start_time()` 불변, 연결 수 변동 없음) | |

- **게이트:** 복구 성공 · 4-3 행수 일치 · 4-4 양쪽 0행 · RTO 문서화 · 운영 무영향
- **금지:** 운영 DB(5434) 와 로컬 개발 DB(5432) 를 리허설 대상으로 쓰지 않는다

---

## W5. 오프사이트 암호화 + DB 밖 자산 (R5·R6)

| # | 태스크 | 비고 |
|---|---|---|
| 5-1 | `age` 설치 + 키페어 생성. 공개키로 암호화, 개인키는 **Dropbox 밖** 보관 | gpg 도 가능하나 age 가 단순 |
| 5-2 | `dropbox_sync.sh` 수정 — 업로드 **전** 암호화, `.dump.age` 만 전송 | 서버 로컬 14일 사본은 **평문 유지** (키 없이 즉시 복구 가능해야 함) |
| 5-3 | Dropbox 기존 평문 `.dump` 정리 — 암호화 사본 검증 **후** 삭제 | 순서 역전 금지 |
| 5-4 | `certificados` · `manuales` tar + 암호화 → 같은 Dropbox 경로. 인증서에 개인키가 있으므로 평문 업로드 금지 | 일 1회 |
| 5-5 | `.env` **키 인벤토리** 작성 — 항목명만, **값 0건**. Phase 65 W7 원칙 준수 | `74-RUNBOOK.md` |
| 5-6 | 저장소 키 값 스캔 — 커밋된 비밀 0건 확인 | |
| 5-7 | **암호화 사본에서 복구 1회** (W4 리허설에 포함) — 복호 안 되는 백업은 백업이 아니다 | |

- **게이트:** Dropbox 평문 `.dump` 0개 · 암호화 사본 복구 성공 · 인증서 복원 확인 ·
  저장소 키 값 0건 · 서버 로컬 평문 사본 유지 확인
- **주의:** 5-3 을 5-7 보다 먼저 하면 **복호 실패 시 백업이 통째로 사라진다.** 순서를 지킨다.

---

## 승인 게이트 요약

| 시점 | 내용 | 이유 |
|---|---|---|
| W0 종료 후 | 0-2 덤프 검증 결과 | 반쪽 백업이면 phase 우선순위가 바뀐다 |
| W3 착수 전 | 디스크 여유 + WAL 생성량 + `max_slot_wal_keep_size` 제안값 + 슬롯 생성 SQL | 디스크 고갈 → **DB 정지** 위험 |
| W2-7 / W1-1 실행 전 | crontab · 백업 스크립트 수정 내용 | 편집 실수로 **백업 자체가 멈춤** |
| W5-3 실행 전 | Dropbox 평문 사본 삭제 | 복호 검증(5-7) 선행 필수 |

## 완료 기준

- W1·W2 만으로도 **부분 완료로 인정**한다 — 백업이 반쪽인지 알게 되고, 실패 시 알게 된다
- 전체 완료 = `74-SPEC.md` 「Success Criteria」 전 항목 TRUE
- **운영 무중단** — 전 과정 API·PostgreSQL 재시작 0회
- **앱 pool 무영향** — `pg_receivewal`(replication 연결) · `pg_dump`(5434 직결) 모두 pgbouncer 미경유

## 이 phase 가 하지 않는 것

서버 2호기 · read replica · nginx LB · 자동 failover — `D-63-2` 보류 결정 **유지**.
`archive_mode=on` 전환(재시작 필요) · pgBackRest/Barman 도입 · MinIO 백업 저장소(같은 서버라 오프사이트 아님) ·
Phase 65 W8-5 알람 2종(백업 무관) · 애플리케이션 코드 변경.
