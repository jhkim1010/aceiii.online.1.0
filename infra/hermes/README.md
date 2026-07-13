# Hermes Agent — 운영서버 격리 설치 (srv803182)

24시간 상시 코딩 에이전트(Hermes Agent, Nous Research)를 **운영 서버에 영향 0**로 올리기 위한 격리 설치 자산.

## 왜 격리가 필요한가
이 서버(srv803182)는 Ventago 뿐 아니라 coolinvoice·apicoolsistema·mongodb 등 **12개 운영 컨테이너**가 함께 도는 박스이고, **swap 이 0B** 이다. 자율 에이전트가 메모리를 튀기면 커널 OOM 이 운영 컨테이너를 죽일 수 있으므로, 자원·유저·DB·네트워크 4중 격리가 전제다.

## 파일
| 파일 | 역할 |
|------|------|
| `install-hermes.sh` | 유저 생성 + 의존성 + Node/uv/Python3.11 + Hermes 설치 (멱등) |
| `hermes-gateway.service` | systemd 유닛 (MemoryMax 하드캡 + 보안 격리) |
| `verify-hermes.sh` | 설치 전/후 운영 영향 대조 (읽기 전용) |

## 4중 격리 요약
1. **유저**: `hermes` non-root, docker/sudo 그룹 제외 → 운영 컨테이너·소스 접근 불가
2. **자원**: `MemoryMax=4G`(하드캡) · `CPUQuota=300%` · `OOMPolicy=stop` → 초과 시 Hermes만 종료
3. **DB**: 운영 자격증명 미부여. pgbouncer(5432)/PG18(5434) 접근 금지
4. **네트워크**: 게이트웨이 아웃바운드 전용 → 신규 인바운드 포트 없음

## 설치 순서
```bash
# 0) (설치 전) 운영 상태 스냅샷
bash verify-hermes.sh > /tmp/hermes-before.txt

# 1) 설치 (root)
sudo bash install-hermes.sh

# 2) LLM 자격증명 설정 (hermes 유저, 600 권한, 레포 커밋 금지)
sudo -u hermes mkdir -p /home/hermes/.hermes
sudo -u hermes tee /home/hermes/.hermes/gateway.env >/dev/null <<'ENV'
# 예시 — 실제 provider/키로 교체
# HERMES_MODEL_PROVIDER=...
# HERMES_API_KEY=...
# 게이트웨이 채널 토큰 (Telegram/Discord 등)
# TELEGRAM_BOT_TOKEN=...
ENV
sudo chmod 600 /home/hermes/.hermes/gateway.env

# 3) hermes 바이너리 실경로 확인 후 유닛의 ExecStart 보정
sudo -u hermes bash -lc 'command -v hermes'

# 4) systemd 등록
sudo cp hermes-gateway.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now hermes-gateway

# 5) (설치 후) 대조 + 상한 실측
bash verify-hermes.sh > /tmp/hermes-after.txt
diff /tmp/hermes-before.txt /tmp/hermes-after.txt || true
systemctl show hermes-gateway -p MemoryMax -p MemoryCurrent -p CPUQuotaPerSecUSec
```

## DB 가 필요해질 경우 (pool 낭비 방지)
Hermes 는 기본적으로 운영 DB 를 쓰지 않는다. 만약 dev DB 가 필요하면 **운영 pool 과 완전 분리**:
```sql
-- PG18(5434) 에 최소권한 role + 전용 DB
CREATE ROLE hermes_dev LOGIN PASSWORD '***';
CREATE DATABASE hermes_dev OWNER hermes_dev;
-- 앱측 pool 은 max 5 (절대 pgbouncer/운영 pool 재사용 금지)
```
연결은 `postgres://hermes_dev@127.0.0.1:5434/hermes_dev` 직결, pool `max:5, idleTimeoutMillis:30000`.

## 운영 정지/복구
```bash
sudo systemctl stop hermes-gateway     # 즉시 중지 (운영 무영향)
sudo systemctl disable hermes-gateway  # 부팅 자동실행 해제
```

## 알려진 사전 이슈 (범위 밖, 별도 보고)
- 5432(pgbouncer)·5433(구 PG10) 가 `0.0.0.0` 로 외부 노출 중 — Hermes 와 무관한 기존 보안 이슈. ufw 로 22 외 차단 검토 권장(운영 영향 있어 별도 확인 필요).
