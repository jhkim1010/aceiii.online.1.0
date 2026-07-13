# SPEC: Hermes Agent 운영서버 격리 설치 (24/7)
생성일: 2026-07-13

## 목표
운영 서버 srv803182(Ubuntu 24.04, KVM8, 32GB RAM, **swap 0**)에 Hermes Agent(Nous Research)를 24시간 상시 운영으로 설치하되, 12개 운영 컨테이너·PG18(5434)·pgbouncer(5432)에 자원/보안 영향 0가 되도록 4중 격리한다.

## 배경 및 컨텍스트 (실측 2026-07-13)
- 서버: Ubuntu 24.04.2, 커널 6.8, systemd 255, AMD EPYC 7543P(8 vCPU)
- 메모리: 31Gi 중 가용 16Gi, **swap 0B** → 메모리 하드캡 필수
- 디스크: 288G 여유(26% 사용)
- 부하: load avg 1.7 / 8코어(~21%), 최근 OOM 이력 없음
- 컨테이너 12개 총 메모리 ≈ 3.6GiB (api_ventago 123MB, mongodb 1.16G, apicoolsistema 1G 등)
- 리스너: 5432(pgbouncer, 0.0.0.0), 5433(구PG10, 0.0.0.0), 5434(PG18, 127.0.0.1), 54322(docker PG)
- `hermes` 유저 미존재, ufw 비활성
- 누락 의존성: node/npm, ripgrep, ffmpeg, uv (Python 3.12.3 존재 — Hermes 권장 3.11은 uv로 별도 설치)

## 기술 스택
- 에이전트: Hermes Agent (Python 3.11 + Node.js + ripgrep + ffmpeg + git)
- 서비스 관리: systemd (User=hermes, MemoryMax/CPUQuota/OOMPolicy)
- 상시 운영: `hermes gateway` (Telegram/Discord/Slack 등 **아웃바운드** 연결 → 인바운드 포트 불필요)
- DB: Hermes는 운영 DB 미접근. 필요 시 별도 `hermes_dev` role + pool max 5

## 4중 격리 설계 (필수 제약)
1. **유저 격리**: 전용 non-root 유저 `hermes`. docker/sudo 그룹 절대 미포함 → 운영 컨테이너·소스 접근 불가
2. **자원 격리**: systemd `MemoryHigh=3G` / `MemoryMax=4G`(하드캡, swap 0 대응) / `CPUQuota=300%` / `OOMPolicy=stop` → 한도 초과 시 Hermes 자기 프로세스만 종료, 운영 무영향
3. **DB 격리**: 운영 자격증명(.pgpass 등) 미부여. pgbouncer(5432)/PG18(5434) 접근 금지. dev DB 필요 시 pool max 5~10으로 신규 생성
4. **네트워크 격리**: 게이트웨이는 아웃바운드 전용 → 신규 인바운드 포트 미개방. 웹 UI 필요 시 127.0.0.1 바인딩 + SSH 터널

## 태스크 목록
- [ ] TASK-1: 전용 유저 `hermes` 생성 (docker/sudo 제외) — install-hermes.sh
- [ ] TASK-2: 시스템 의존성 설치 ripgrep, ffmpeg (apt, 서비스 아님·무해) — install-hermes.sh
- [ ] TASK-3: hermes 유저 하 Node(nvm LTS20) + uv + Python 3.11 설치 — install-hermes.sh
- [ ] TASK-4: Hermes Agent 설치 (공식 install.sh, hermes 유저) — install-hermes.sh
- [ ] TASK-5: LLM 백엔드 자격증명 env 설정 (/home/hermes/.hermes/gateway.env, 600) — 사용자 입력 필요
- [ ] TASK-6: systemd 유닛 등록 (자원/보안 격리) — hermes-gateway.service
- [ ] TASK-7: 네트워크 점검 — 인바운드 포트 미개방 확인, 게이트웨이 아웃바운드 검증
- [ ] TASK-8: DB 격리 확인 — 운영 자격증명 미부여 확인
- [ ] TASK-9: 상시 운영 검증 — enable/start, 로그 확인, MemoryMax 실측(운영 메모리 헤드룸 재확인)
- [ ] TASK-10: infra/hermes/ 에 스크립트·유닛·문서 커밋

## 완료 기준
- Hermes 24/7 running (systemctl enabled + active)
- 운영 컨테이너 12개 메모리/상태 변화 없음 (설치 전후 대조)
- 신규 인바운드 포트 0개, 운영 DB 접근 경로 0개
- systemd MemoryMax=4G 하드캡 실효 확인

## 금지사항 / 주의사항
- hermes 유저를 docker/sudo 그룹에 추가 금지
- pgbouncer(5432)/PG18(5434)/운영 컨테이너 설정 절대 미변경
- 상태변경 명령(useradd/apt/systemd)은 실행 전 사용자 확인
- 구 PG10(5433)·pgbouncer(5432)가 0.0.0.0 노출된 것은 기존 이슈 — 이번 작업 범위 밖(별도 보고)
- LLM API 키는 레포에 커밋 금지, env 파일(600)에만 저장
