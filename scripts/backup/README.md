# 테넌트 DB 백업 + 자동 복구 시험 (2026-08-29)

**이 폴더는 사본이다.** 실제로 도는 것은 각 서버 위의 파일이고, 여기 있는 것은
서버가 사라졌을 때 되살리기 위한 보관본이다. 서버에서 고쳤으면 **여기도 갱신**할 것.

## 왜 만들었나

PG10(5433)에 있는 **126개 레거시 테넌트 DB 의 마지막 백업이 9개월 전**이었다
(2025-11-19). 크론에 있던 백업은 `ventago` 한 DB 뿐이었다.

## 무엇이 도는가

| 시각(UTC) | 서버 | 하는 일 |
|---|---|---|
| 01:30 | 운영 | `pg_backup_todas.sh` — 125개 DB 를 `pg_dump -Fc`, MANIFEST(sha256), `pg_restore -l` 검증 |
| 03:00 | 서버2 | `pull_and_test.sh` — 최신 백업을 **당겨와** 표본 4개를 실제로 복원 |
| 03:40 | 운영 | `dropbox_sync.sh` — 오프사이트 사본 |
| 04:20 | 운영 | `vigilar_restore_test.py` — **서버2 가 보고했는지** 확인 |

## 설계에서 중요한 것 세 가지

**1. 서버2 가 «당겨온다».** 운영이 밀지 않는다. 운영이 뚫려도 백업 시험장을 못
건드리게 하기 위해서다. 운영의 `authorized_keys` 에 있는 서버2 키는
`command="serve_latest.sh",restrict` 로 묶여 셸이 열리지 않는다(대조군 확인함).

**2. 복원 «성공» 을 믿지 않는다.** 빈 DB 도 오류 없이 복원된다. 그래서
**덤프가 담고 있다고 말하는 테이블 수**와 복원 결과를 대조한다.
- `TABLE DATA` 행을 빼야 한다(안 빼면 기대치가 2배 → 전부 실패).
- `information_schema.tables` 는 **뷰까지 센다** → `table_type='BASE TABLE'` 필수.
- 진짜로 빈 테넌트가 있다(`krafting`, `test`). 「0개면 실패」로 짜면 위양성이 매일
  나고, **일주일이면 아무도 이 로그를 안 본다.**

**3. 부재를 다른 기계가 본다.** 서버2 가 꺼지거나 크론이 지워지면 실패조차 나지
않고 그냥 조용해진다. 그래서 서버2 는 결과를 운영으로 밀어 올리고
(`recibir_estado.sh`, 역시 `command=` 로 묶임), 운영이 **48시간 넘게 보고가 없으면**
경보한다. 성공 알림은 **월요일만** 보낸다 — 매일 오면 읽지 않게 되기 때문이다.

## 점검하는 법

```bash
# 알림 경로가 살아 있는지 (토큰 만료를 잡는다)
ssh root@74.208.60.137 'sudo -u postgres /var/lib/postgresql/pull_and_test.sh --probar-aviso'

# 마지막 시험 결과
ssh jhkim-server 'sudo cat /var/lib/postgresql/pg_backups/estado_restore_test.json'
ssh root@74.208.60.137 'sudo -u postgres tail -20 /var/lib/postgresql/restore-test/pull_and_test.log'
```

## 알려진 한계

- **표본은 하루 4개**(가장 큰 것 + 무작위 3). 125개를 다 돌리면 몇 시간이 걸린다.
  즉 한 DB 는 대략 **한 달에 한 번** 복원된다 — 「매일 전부 검증된다」가 아니다.
- 서버2 의 복원 클러스터는 **5440** 포트 전용이며 시험 후 DB 를 지운다.
- Dropbox 쪽 `todas/` 는 **자동 삭제를 걸지 않았다**(보존 정책 미정).
