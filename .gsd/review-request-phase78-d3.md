# 자문 요청 — Phase 78 D3: 무거운 테스트 스위트를 어디서 돌릴 것인가

## 질문

Phase 78(모듈 무결성 스위트)의 L2~L5(Playwright E2E + DB 를 쓰는 통합/동시성 테스트)를
**어디서, 어떤 안전장치로** 돌려야 하는가. 스테이지 서버를 새로 만들 가치가 있는가,
아니면 현재 호스트에 자원 상한을 걸어 돌려도 되는가.

## 실측 (2026-08-11)

### 인프라 — 서버는 하나뿐이다
- `srv803182` (VM), **8 vCPU / 31 GiB RAM / swap 0B**, load avg 3.72 (9일 가동)
- `~/.ssh/config` 의 `jhkim-server` 와 `myserver` 는 **같은 IP(62.72.7.245)** — 스테이지 없음
- 메모리: total 31Gi / used 8.0Gi / free 7.1Gi / **buff-cache 18Gi / available 23Gi**
- **cgroup v2 (`cgroup2fs`) + `/usr/bin/systemd-run` 사용 가능**

### 이 호스트에 같이 사는 것
- **Jenkins** (JVM, RSS ~517 MB) — 운영 빌드가 여기서 돈다
- **호스트 PostgreSQL 18** 클러스터 `ventago18` 포트 5434 (운영 DB, Docker 아님) + pgbouncer
- Docker 컨테이너 13개: `ventagoapp`(운영 프론트), `api_ventago`(운영 API), `ventago_redis`,
  `minio`, `coolsistemamongodb`, `postgresql-dbpostgres-1`(별도 시스템), `apicoolsistema`,
  `coolinvoice`, `tienda_coolsistema`, `syncace`, `vw-agent`, `portainer`, `pgadmin`

### 운영 PostgreSQL 설정
```
shared_buffers        = 262144  (2 GiB)
effective_cache_size  = 1572864 (12 GiB)   ← 페이지 캐시 18 GiB 에 의존
work_mem              = 16384   (16 MB)
max_connections       = 200
```
앱 pool: 워커당 min2/max20, PM2 4워커 → 앱 상한 80, pgbouncer pool_size 50.

### 현재 빌드 부하
Jenkins 빌드(api) 소요 54~65초. 프론트는 Next 프로덕션 빌드(125 페이지).

### 이 프로젝트의 jest 전력 (중요)
- **기본 옵션이면 메모리 20 GB 초과** — 기계가 언 적이 있다
- **2 워커면 랜덤 suite 가 SIGTERM 으로 죽는다** → 전체 실행은 `--maxWorkers=1` 강제
- 전용 config 4종(`jest-e2e`/`concurrency`/`tenant`/`family`)이 이미 전부 `maxWorkers: 1`
- `family` 는 `NODE_OPTIONS=--max-old-space-size=6144`

### 성능 규약
- slow query 임계 100ms
- 사이드바 클릭 → 렌더 완료 P95 ≤ 300ms

## 내가 지금 생각하는 위험 구분

1. **OOM kill** — 23 GiB 여유가 있어 확률은 낮다. 다만 **swap 0** 이라 초과하면
   점진적 저하 없이 OOM killer 가 즉시 victim 을 고른다. RSS 가 큰 Postgres 가 표적이 되기 쉽다.
   jest 가 20 GB 를 찍은 전례가 있어 **상한이 없으면** 도달 가능한 범위다.

2. **페이지 캐시 축출 (이쪽이 더 현실적)** — OOM 이 안 나도, 테스트의 파일 I/O 와
   힙 사용이 18 GiB buff/cache 를 밀어낸다. PG 는 `effective_cache_size=12 GiB` 를 전제로
   플랜을 짜므로 캐시가 식으면 **운영 쿼리가 디스크로 내려가 느려진다.**
   그리고 이건 로그에 "테스트 때문"이라고 안 남는다 → 원인 추적이 어렵다.

3. **CPU/IO 경합** — 8 vCPU 에 load 3.7. Playwright(브라우저 N개) + jest 가 얹히면
   운영 API 응답에 직접 영향.

## 선택지

| 안 | 내용 | 비용 |
|---|---|---|
| (a) | **개발자 Mac 에서만** 실행. Jenkins 에는 L1(정적)만 | 0. 단 야간 자동화하려면 Mac 이 켜져 있어야 함 |
| (b) | **같은 호스트 + cgroup v2 상한** — `systemd-run --scope -p MemoryMax=… -p CPUQuota=… -p IOWeight=…` + `nice`/`ionice`, `--maxWorkers=1` | 0. 스테이지 불필요 |
| (c) | **별도 저사양 VPS** 를 스테이지로 신설 | 월 비용 + 운영 부담(마이그레이션/시드 동기화) |

## 묻고 싶은 것

1. **(b) 가 실제로 안전한가?** cgroup v2 의 `memory.max` 는 그 cgroup 의 **페이지 캐시까지
   포함**해 제한하므로, 상한을 걸면 테스트가 호스트 전체 캐시를 밀어내는 것을 상당히
   막아준다고 이해했다. 이 이해가 맞는가? 맞다면 위험 2가 상당 부분 해소되는가?
   놓친 함정이 있는가(예: `memory.max` 초과 시 그 cgroup 내부 OOM 이 테스트를 죽여
   **거짓 실패**를 만드는 문제, dirty page writeback 이 상한과 무관하게 IO 를 유발하는 문제)?

2. **구체적인 상한값**을 어떻게 잡아야 하는가? 위 실측(31 GiB / 8 vCPU / swap 0 /
   PG 가 12 GiB 캐시 전제)에서 `MemoryMax` / `CPUQuota` / `IOWeight` 권장치와 그 근거는?
   jest 가 과거 20 GB 를 찍었다는 점을 감안하면 상한이 낮으면 테스트가 계속 죽지 않겠는가?

3. **테스트용 PostgreSQL 을 어디에 둘 것인가?** Phase 78 은 일회용 DB
   (`ventago_test_<runid>` 생성 후 DROP)를 쓰기로 했다. 이걸 **운영과 같은 PG18 클러스터
   (5434)** 에 만들면 같은 shared_buffers·WAL·체크포인터를 공유해 운영에 영향을 준다.
   별도 포트로 테스트 전용 인스턴스를 띄우는 게 맞는가, 아니면 Docker PG 를 쓰는 게 맞는가?
   (이게 (b) 의 실질적 급소라고 본다 — cgroup 으로 프로세스는 가둬도 **DB 는 공유**된다)

4. **(c) 스테이지를 만들 가치가 있는가?** 만든다면 최소 사양과, 마이그레이션·시드를
   운영과 어긋나지 않게 유지하는 방법은? (이 프로젝트는 dev-운영 스키마 분기로
   배포 후 500 사고를 여러 번 냈다)

5. **야간 자동 실행**을 (a) 로 하면 Mac 이 꺼져 있을 때 조용히 안 돈다.
   이 프로젝트는 "감시 장치가 부재에서 침묵한다"로 3번 당했다.
   **실행 자체가 안 된 것**을 어떻게 감지해야 하는가?
