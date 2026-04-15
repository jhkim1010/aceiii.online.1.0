# 서버 사양 권장안 & PostgreSQL 튜닝

## 최소 서버 사양 (500 터미널 기준)

| 항목 | 최소 | 권장 |
|------|------|------|
| CPU | 4 cores | 8 cores |
| RAM | 8 GB | 16 GB |
| 디스크 | SSD 100GB | NVMe SSD 200GB |
| 네트워크 | 100 Mbps | 1 Gbps |
| OS | Ubuntu 22.04 LTS | Ubuntu 24.04 LTS |

## PostgreSQL 튜닝 (RAM 8GB 기준)

```ini
# postgresql.conf 또는 ALTER SYSTEM SET

# 메모리
shared_buffers = 2GB                # RAM의 25%
effective_cache_size = 6GB          # RAM의 75%
work_mem = 8MB                      # 복잡한 정렬/해시 조인용
maintenance_work_mem = 512MB        # VACUUM, CREATE INDEX용

# 연결
max_connections = 100               # Sequelize pool max=50 + admin + 여유
idle_in_transaction_session_timeout = 30000  # 30초 — 방치 트랜잭션 자동 종료

# WAL / 디스크
wal_buffers = 64MB
checkpoint_completion_target = 0.9
random_page_cost = 1.1              # SSD 기준 (HDD는 4.0)
effective_io_concurrency = 200      # SSD 기준

# 쿼리 최적화
default_statistics_target = 100     # ANALYZE 정확도
```

## PostgreSQL 튜닝 (RAM 16GB 기준)

```ini
shared_buffers = 4GB
effective_cache_size = 12GB
work_mem = 16MB
maintenance_work_mem = 1GB
```

## Sequelize Pool 설정 (현재)

```
min: 5, max: 50, idle: 10000ms, acquire: 30000ms
```

500 터미널 동시 접속 시 pool max=50으로 충분. 단, PM2 클러스터 모드 사용 시 인스턴스별 pool이 생기므로:
- 2 인스턴스 × max 50 = 100 connections → max_connections=100 이상 필요
- 4 인스턴스 × max 50 = 200 connections → max_connections=250 권장

## Docker 리소스 제한 권장

```yaml
# docker-compose.yml
services:
  api_ventago:
    deploy:
      resources:
        limits:
          cpus: '4'
          memory: 4G
        reservations:
          cpus: '2'
          memory: 2G

  ventago_app:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
        reservations:
          cpus: '1'
          memory: 1G
```

## 적용 방법

```bash
# 1. PostgreSQL 컨테이너에 접속
docker exec -it dbpostgres psql -U coolsistema -d ventago

# 2. 튜닝 값 적용
ALTER SYSTEM SET shared_buffers = '2GB';
ALTER SYSTEM SET effective_cache_size = '6GB';
ALTER SYSTEM SET work_mem = '8MB';
ALTER SYSTEM SET maintenance_work_mem = '512MB';
ALTER SYSTEM SET random_page_cost = 1.1;
ALTER SYSTEM SET effective_io_concurrency = 200;
ALTER SYSTEM SET idle_in_transaction_session_timeout = 30000;

# 3. PostgreSQL 재시작 필요
SELECT pg_reload_conf(); -- 일부 설정만 적용
-- shared_buffers 변경은 PostgreSQL 재시작 필요
```
