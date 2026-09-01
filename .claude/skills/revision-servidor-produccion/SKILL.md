---
name: revision-servidor-produccion
description: 운영 서버(srv803182 / 62.72.7.245) 보안·성능 정기 점검 절차. 노출 포트·방화벽·SSH 키·PostgreSQL 접근제어·pgbouncer 를 실측하고, 300ms 초과 쿼리와 화면 깜빡임(500 반복)의 원인을 추적한다. "보안 점검", "서버 점검", "느린 쿼리", "화면 깜빡임" 요청 시 사용.
---

<context>
## 대상

단일 서버에 다음이 함께 돈다 — 하나를 막으면 다른 것이 죽을 수 있다.

```
Ventago(신규)   PG18 :5434 localhost 전용 · api :5003 · front :5001
레거시 ACE      PG10 :5433 **0.0.0.0 노출** · 126개 테넌트 DB · 36GB
공용            pgbouncer :5432(운영) :6432(staging) · nginx :80/:443
기타            coolinvoice :5010 · apicoolsistema :5011 · syncace :3030
                api_staging :5013 · docker postgres :54322
localhost 전용  Jenkins :8090 · MinIO :9000/:9001 · portainer :9443
```

★★★ **매장이 실제로 영업에 쓰고 있다.** 방화벽·pg_hba 를 일괄로 조이면
매출이 멈춘다. 점검은 «먼저 관찰, 나중에 차단» 순서로만 한다.
</context>

<procedure>
## 1. 노출면 실측 (읽기 전용, 안전)

```bash
ssh jhkim-server '
sudo ss -lntp | awk "NR==1 || /0\.0\.0\.0|\[::\]/"       # 외부 노출 포트
sudo ufw status verbose; sudo iptables -S | head -5       # 방화벽
sudo sshd -T | grep -iE "^(permitrootlogin|passwordauth|maxauthtries|port)"
'
```

★ `0.0.0.0` 으로 뜨는 것만 인터넷 노출이다. `127.0.0.1` 은 아니다.
  둘을 섞어 세면 위험이 실제보다 훨씬 커 보인다.

## 2. PostgreSQL 접근제어

```bash
ssh jhkim-server '
for P in 5433 5434; do
  echo "--- 포트 $P ---"
  sudo -u postgres psql -p $P -At -c "SHOW hba_file" | xargs sudo grep -vE "^\s*#|^\s*$"
  sudo -u postgres psql -p $P -At -c "SELECT current_setting(\$\$listen_addresses\$\$)"
done'
```

★ 확인 지점: `host all all 0.0.0.0/0` 이 있는가. PG10 은 **있다**(레거시
  데스크톱 앱이 인터넷 너머로 직접 붙는 구조).
★ **«실패 로그 0건» 은 안전의 근거가 아니다.** 로그가 켜져 있는지,
  보존 기간이 얼마인지, 이미 성공한 침입이 없는지를 따로 봐야 한다.

## 3. SSH 키 인벤토리 — 제한 없는 키를 센다

```bash
ssh jhkim-server '
for U in jhkim postgres root; do
  H=$(getent passwd $U | cut -d: -f6)
  sudo test -f "$H/.ssh/authorized_keys" || continue
  echo "[$U]"
  sudo grep -vE "^\s*#|^\s*$" "$H/.ssh/authorized_keys" | while read -r l; do
    case "$l" in ssh-*) echo "   제한없음 ★ $(echo $l | awk "{print \$NF}")" ;;
                 *) echo "   $(echo "$l" | sed -E "s/ ssh-.*//" | cut -c1-50) | $(echo $l | awk "{print \$NF}")" ;;
    esac
  done
done
sudo grep -rhE "^[^#].*NOPASSWD" /etc/sudoers /etc/sudoers.d/ '
```

★★★ **제한 없는 키 + NOPASSWD sudo = 그 키가 곧 root 다.**
  passphrase 없는 키라면 노트북 도난이 서버 장악이 된다.

## 4. 300ms 초과 쿼리

```bash
ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -P pager=off -c \"
SELECT round(mean_exec_time::numeric)::text||'ms' AS media,
       round(max_exec_time::numeric)::text||'ms' AS pico, calls,
       left(regexp_replace(query,'\s+',' ','g'),68) AS consulta
  FROM pg_stat_statements
 WHERE mean_exec_time > 300
   AND query !~* 'legacy_stage|CREATE TABLE|DROP |ALTER |VACUUM|DO \\\$\\\$'
 ORDER BY mean_exec_time DESC LIMIT 12;\""
```

★★ **배치를 걸러내지 않으면 오독한다.** 상위는 거의 항상 레거시 임포트나
  일회성 정리(DELETE FROM sales …)다. 그것을 «느린 시스템» 으로 보고하면
  실제 문제(핫패스)를 놓친다. 위 `!~*` 필터가 그 역할이다.
★ 진짜 확인 지점은 **호출이 많은 쿼리가 빠른가** 다:
  `WHERE calls > 500 ORDER BY calls DESC` — 여기가 0.x ms 면 DB 는 무죄다.
★ `round(double precision, int)` 는 PG18 에 없다 → `::numeric` 캐스트 필수.

## 5. 화면 깜빡임 — DB 가 아니라 500 반복을 의심한다

```bash
ssh jhkim-server '
E=$(sudo ls -t /var/lib/ventago-logs/api/error-*.log | head -1)
sudo grep -a "ExceptionFilter" "$E" | tail -5 | cut -c1-160
F=$(sudo ls -t /var/lib/ventago-logs/api/combined-*.log | head -1)
sudo grep -aoE "(GET|POST|PUT|DELETE) /api/[^ ]+ [0-9]{3} [0-9]+ms" "$F" \
  | awk "{gsub(/ms/,\"\",\$4); if (\$4+0>300) print \$4, \$2, \$3}" | sort -rn | head
'
```

★★★ 2026-09-01 실측: 오늘 689건 중 300ms 초과는 **1건**. 성능은 멀쩡했다.
  깜빡임의 실제 원인은 `/configuracion/` 에서 같은 요청이 **500 으로 반복 실패**한 것이었다:
  `PUT /api/colors/59` 6회, `POST /api/subcategories` 3회.
  원인은 `colors_name_store_id` / `subcategories_name_store_id` **유니크 제약 위반**이
  Sequelize `Validation error` → HTTP 500 으로 새어 나온 것.
  사용자는 이유를 모르니 다시 누르고, 목록이 다시 그려지며 «깜빡임» 이 된다.
  → **중복 이름은 409 + 스페인어 안내로 돌려줘야 한다.**

## 6. codex 자문

```bash
NODE_OPTIONS="" codex exec --skip-git-repo-check "$(cat 프롬프트)" < /dev/null > /tmp/out.txt
```
★ 실측값을 붙여 주고 «무엇을 끊을 위험이 있는지» 를 함께 물어야 실행 가능한
  답이 온다. 「모범사례 위반」만 나열하면 아무것도 못 고친다.
★ **과대평가하기 쉬운 항목을 지적해 달라고 명시**할 것. 2026-09-01 자문에서
  TLS 1.0/1.1 과 root authorized_keys 는 «지금 우선순위 아님» 으로 정리됐다
  (`PermitRootLogin no` 라 root 키는 SSH 로 못 쓴다).
</procedure>

<findings>
## 2026-09-01 점검 결과 (다음 점검 때 대조용)

| 심각도 | 항목 | 상태 |
|---|---|---|
| CRITICAL | PG10 `0.0.0.0/0 md5` · 126 테넌트 · EOL 2022-11 | **미해결** |
| CRITICAL | passphrase 없는 키 + `jhkim NOPASSWD: ALL` | 부분 완화 |
| HIGH | 앱 포트 7개 직접 공개(3030·5001·5003·5010·5011·5013·54322) | 미해결 |
| HIGH | pgbouncer 5432 평문(client_tls_sslmode 없음) | 미해결 |
| MEDIUM | staging(5013·6432)이 운영 서버에서 공개 | 미해결 |
| LOW | TLS 1.0/1.1 · root 잔존 키 4개 | 우선순위 낮음 |
| — | ufw inactive, iptables INPUT ACCEPT | 방화벽 없음 |
| ✓ | OS 보안 업데이트 0건 · fail2ban 활성 · PG18 localhost | 양호 |

**해결된 것**: 126개 테넌트 DB 백업(2026-08-29 부터 매일 + 서버2 복구시험).

## 실행 순서 (codex 권고 — 이 순서를 지킬 것)

1. PG10·pgbouncer·공개 포트의 **접속원을 72시간 수집** (읽기 전용, 안전)
2. DB 역할 권한·비밀번호 재사용 조사 (읽기 전용)
3. 보호된 신규 경로를 **기존과 병행** 구축 (VPN / TLS 프록시 / allowlist)
4. 매장을 소수씩 이전, 이전된 접속원부터 차단
5. 마지막 매장 이전 후에야 `0.0.0.0/0` 제거
6. PG10 업그레이드는 **별도 환경에서 리허설** 후
7. TLS·잔존 키 정리는 마지막

★★★ **1번을 건너뛰고 3~5번을 하면 매장이 죽는다.** 이것이 이 점검의 핵심 규칙이다.
</findings>

<gotchas>
## SSH 키 제한 — DBeaver 와 충돌하는 조합 (2026-09-01 실측)

터널 전용 키를 만들 때 다음은 **DBeaver 를 깨뜨린다**:

| 옵션 | 결과 |
|---|---|
| `restrict` | ✗ PTY 를 막는데 DBeaver 가 PTY 를 요청 → `Connection reset` |
| `command="...exit 1"` | ✗ 종료코드로 실패 판정 |
| `command="/bin/true"` | ✗ 세션 즉시 종료 → 터널도 함께 죽음 |
| `restrict,pty,command="cat > /dev/null"` | ✗ 여전히 실패 |
| **`permitopen="127.0.0.1:5434"`** | **✓ 동작** — 세션에 손대지 않는다 |

★★ 교훈: **세션 동작을 건드리는 옵션은 GUI 클라이언트를 깬다.**
  포워딩 목적지만 제한하는 `permitopen` 은 안전하다.
★★★ 진단은 `Details >>` 의 한 줄이 추측 네 번보다 빨랐다.
  `Connection reset` + 서버 로그의 `Accepted publickey`(그 뒤 없음) 조합이
  «인증은 됐고 세션에서 끊겼다» 를 정확히 가리켰다.
★ `nc -z` 로 `permitopen` 을 시험하면 **항상 통과한다** — 로컬 리스너만 보기 때문이다.
  반드시 그 포트로 **실제 통신**해야 한다(psql 등).
</gotchas>
