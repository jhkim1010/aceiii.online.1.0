# SPEC: Phase 60 Wave B — 운영서버 관리포트 폐쇄 + nginx basic auth + 인증서 권한
생성일: 2026-07-21

## 목표
운영서버(62.72.7.245)에서 인터넷에 노출된 **관리 콘솔 직접 포트**를 127.0.0.1로 묶고, nginx 서브도메인에 basic auth 이중 인증을 추가하며, world-writable(777) 인증서 개인키 권한을 정리한다. 앱/에이전트/사용 중 서비스에는 무영향을 보장한다. (7등급→목표 4등급 진행)

## 배경 및 컨텍스트 (실측 2026-07-21)
- Wave A 적용 완료: sshd 키 전용, fail2ban. lastb 6,073건은 전 세계 봇넷 스캔(표적 아님).
- 관리 콘솔용 nginx 서브도메인이 **이미 존재**(TLS): deploy→8080(Jenkins), cooldb→8090(pgAdmin), minio→9001(콘솔), apiminio→9005(MinIO S3), portainer→9000/9443. → 서브도메인 신설 불필요, 직접 포트만 닫으면 됨.
- **대상 6개 포트 전부 현재 외부 활성연결(ESTABLISHED) 0건** — 지금 끊길 세션 없음.
- 리스너 종류: 8080=java(systemd Jenkins), 나머지(8090/9000/9443/9001/9005/27021)=docker-proxy(compose).
- compose 경로: portainer=/home/coolsistema/infra/portainer, minio=/home/coolsistema/infra/minio, pgadmin=/home/coolsistema/infra/pgadmin, mongo=/home/coolsistema/mongodb.

### ★영향도 조사 결과 (핵심)
- **Mongo 27021 안전**: 소비자 apicoolsistema 가 mongo 와 동일 도커망(coolsistema-prod)에서 컨테이너명 직접통신. 호스트포트 미경유 → 바인딩 무영향.
- **MinIO 9005 안전**: 백엔드 .env `MINIO_HOST=apiminio.coolsistema.com:443` — 앱은 nginx 서브도메인 경유. 9005 raw 포트 직접 미사용. 바인딩 후에도 nginx→127.0.0.1:9005 유지. (단 apiminio 는 basic auth 제외 필수 — S3 클라이언트는 basic-auth 헤더 안 보냄, 걸면 업로드 401.)
- **★api3(oldapi-cool-web-1) 사용 중**: 오늘 16:02~ market/merce 유저가 /admin/reporting 사용(48h 725줄). → **중지 금지**. 기존 b1 스크립트의 api3 stop/vhost disable 단계 제거.
- **★DB 포트 이번 웨이브 제외**: vw-agent·syncace 가 `host.docker.internal` 로 DB 접속 → PG 5432/5433/54322 를 127.0.0.1 로 묶으면 즉시 단절. 기존 b2 의 54322 단계 제거. DB 포트는 별도 웨이브(선행: 두 에이전트를 도커망 호스트명으로 이전).

## 기술 스택 / 영향
- 대상: nginx 설정, docker compose(4개), systemd(jenkins), 파일 권한. **앱 코드 변경 없음**.
- **PostgreSQL pool 영향: 없음.** Ventago 앱 DB(PG18:5434 localhost)·pgbouncer(5432)는 이번 웨이브에서 미변경. Mongo 27021 바인딩도 apicoolsistema 연결(도커망) 미영향 확인. → pool 신규연결/고갈 리스크 0.
- ESLint: 해당 없음(앱 소스 미변경).

## 승인된 범위 (사용자 결정 2026-07-21)
- 차단: **관리 콘솔만** — Jenkins 8080, pgAdmin 8090, Portainer 9000/9443, MinIO 9001/9005, Mongo 27021.
- 유지: 5002(agent raw-IP 고정), 443/80(nginx), 22(SSH), 5432/5433/54322(DB=별도웨이브), 3030 syncace·8085 api3(사용 중), 5001/5010/5011(프론트).
- basic auth: portainer/minio/deploy/cooldb 4종 추가. **apiminio 제외**(앱 S3 경로).
- 인증서: 777→640(key)/750(dir), 신중 단계 실행 포함.

## 태스크 목록
- [ ] TASK-0: 사전 점검 — Jenkins 진행중 빌드 없음 확인, 4개 서브도메인 200/301/403 정상 baseline 기록, 각 compose `.bak` 백업. (세션 이중화: SSH 22 미변경이라 잠금위험 없음)
- [ ] TASK-1 (B1 수정판): nginx basic auth — portainer/minio/deploy/cooldb vhost 에 auth_basic + htpasswd(admin). **api3 stop 단계 삭제**. nginx -t → reload(실패 시 자동 원복). 검증: 무인증 curl 401.
- [ ] TASK-2 (B2 수정판): 관리 콘솔 포트 127.0.0.1 바인딩 — 하나씩 재기동·검증. 순서: pgAdmin → Portainer → MinIO(콘솔+S3, 이후 apiminio 헬스+실제 업로드 스모크) → Mongo. **54322 단계 삭제**.
- [ ] TASK-3: Jenkins 8080 — systemd `JENKINS_LISTEN_ADDRESS=127.0.0.1` override → restart. 검증: deploy.coolsistema.com 401, 서버내부 127.0.0.1:8080 200/403.
- [ ] TASK-4 (인증서, 신중): certificados 권한 정리. (a) 그룹 gid=1000 기반 `chown -R jenkins:1000`, dir 750/file 640. (b) **먼저 1개 매장 서브디렉터리로 카나리** → 두 앱(coolinvoice uid1000 group-read, api_ventago root) 읽기 + 발급 스모크 검증 → 전체 롤아웃. 롤백: `chmod -R u+rwX,go+rX` 원복 문서화.
- [ ] TASK-5: 최종 검증 — `ss -ltn` 에서 8090/9000/9443/9001/9005/27021/8080 외부 노출 사라짐 확인. 5002/443/22 유지 확인. print-agent(5002)·발급·리포팅(api3) 정상. compose/nginx 변경분 git 커밋 + 스크립트 tools/ 보존.

## 완료 기준
- 대상 7개 포트가 0.0.0.0 에서 사라지고 127.0.0.1(또는 nginx 경유)만 남음.
- 4개 관리 서브도메인 무인증 접근 시 401.
- 앱(POS/프론트/모바일)·프린터 에이전트·발급·api3 리포팅 전부 정상.
- 인증서 개인키 world-readable 제거, 두 앱 발급 정상.
- pool: 앱 DB 연결 수 before/after 동일.

## 금지사항 / 주의사항
- ❌ oldapi-cool-web-1(api3) 중지·vhost 비활성화 금지 (사용 중).
- ❌ DB 포트(5432 pgbouncer/5433/54322) 이번 웨이브 차단 금지 (vw-agent·syncace host.docker.internal 의존).
- ❌ apiminio 에 basic auth 금지 (앱 S3 업로드 깨짐).
- ❌ 5002 차단 금지 (print/zebra agent raw-IP 접속).
- ⚠ 각 단계 하나씩 재기동·검증 후 다음. compose `.bak` 즉시 롤백 경로 유지.
- ⚠ 인증서는 매장 1개 카나리 후 전체 — coolinvoice(uid1000)·api_ventago(root) 공유 마운트, jenkins(uid110) writer.

## 후속(별도 웨이브)
- Wave B-DB: vw-agent·syncace 를 도커망 호스트명으로 이전 후 PG 포트 폐쇄.
- 시급 별건: MinIO 자격증명 기본값(minioadmin/minioadmin123) 교체.
- Wave C: ufw + SSH 22 고정IP allowlist(D3 결정 필요) + x-api-key 개별키.
