# 운영서버 백업 → Dropbox 자동 전송 설치 가이드

현재 상태 (2026-07-15 확인 완료):

- 백업: postgres 유저 crontab, 매일 03:17, `/var/lib/postgresql/pg_backups/pg_backup_ventago.sh` (PG18:5434 직결, pool 소비 없음, 14일 로테이션) — 마지막 로그 정상 성공
- rclone v1.60.1 서버 설치 완료 (제가 이미 설치해 두었습니다)
- 남은 작업: ① Dropbox 인증(1회) ② 스크립트 배치 ③ 크론 등록 ④ 테스트

---

## 1단계 — Mac에서 Dropbox 인증 토큰 받기 (1회만)

Mac 터미널에서:

```bash
brew install rclone
rclone authorize "dropbox"
```

브라우저가 열리면 Dropbox 로그인 → 허용. 터미널에 아래 형태의 토큰 JSON이 출력됩니다 (전체를 복사):

```
{"access_token":"sl.xxxx...","token_type":"bearer","refresh_token":"xxxx","expiry":"..."}
```

## 2단계 — 서버에서 rclone 리모트 등록 (postgres 유저)

서버 SSH 접속 후 (토큰 JSON을 본인 것으로 교체, 작은따옴표 유지):

```bash
sudo -u postgres rclone config create dropbox dropbox token '{"access_token":"...전체 JSON...","token_type":"bearer","refresh_token":"...","expiry":"..."}'

# 연결 확인 (Dropbox 루트 목록이 나오면 성공)
sudo -u postgres rclone lsd dropbox:
```

## 3단계 — 업로드 스크립트 배치

함께 드린 `dropbox_sync.sh` 파일을 서버로 복사:

```bash
# Mac에서 (파일 있는 위치에서)
scp dropbox_sync.sh jhkim@62.72.7.245:/tmp/

# 서버에서
sudo mv /tmp/dropbox_sync.sh /var/lib/postgresql/pg_backups/
sudo chown postgres:postgres /var/lib/postgresql/pg_backups/dropbox_sync.sh
sudo chmod +x /var/lib/postgresql/pg_backups/dropbox_sync.sh
```

## 4단계 — 수동 테스트

```bash
sudo -u postgres /var/lib/postgresql/pg_backups/dropbox_sync.sh
sudo -u postgres tail -20 /var/lib/postgresql/pg_backups/dropbox_sync.log

# Dropbox에 올라갔는지 확인
sudo -u postgres rclone ls dropbox:ventago_pg_backups
```

Dropbox 앱/웹의 `ventago_pg_backups` 폴더에 `ventago_YYYYMMDD_HHMMSS.dump` 와 `globals_*.sql.gz` 가 보이면 성공입니다.

## 5단계 — 크론 등록 (백업 03:17 → 업로드 03:40)

```bash
sudo -u postgres bash -c '(crontab -l; echo "40 3 * * * /var/lib/postgresql/pg_backups/dropbox_sync.sh >/dev/null 2>&1") | crontab -'
sudo -u postgres crontab -l
```

---

## 운영 메모

- **pool 영향 없음**: rclone은 완성된 백업 파일만 읽어 업로드하므로 PostgreSQL 커넥션을 사용하지 않습니다.
- **대역폭**: `--bwlimit 8M`으로 제한되어 있어 운영 트래픽에 부담 없습니다. 백업이 커지면 조정하세요.
- **보관 정책**: 서버는 기존 14일 로테이션 유지, Dropbox는 무기한 보관. Dropbox 쪽 90일 자동 정리를 원하면 스크립트 하단 주석을 해제하세요.
- **점검**: 문제가 생기면 항상 `/var/lib/postgresql/pg_backups/dropbox_sync.log` 마지막 부분부터 확인하세요.
- **정리 권장**: `/home/jhkim/pg_backups/pg_backup.sh` 는 잘못된 대상(도커 PG14 컨테이너, `-U postgres` 역할 없음)을 바라보는 옛 스크립트로 계속 실패 로그만 남깁니다. 크론에 등록되어 있지 않으므로 삭제해도 무방합니다.
