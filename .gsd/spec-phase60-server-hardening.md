# SPEC: Phase 60 — 운영 서버 보안 강화 (7등급 → 4등급)
생성일: 2026-07-21 · 상태: 계획(결정 D1~D3 대기)

## 목표
외부 노출 면적을 22/80/443 세 포트로 줄이고, SSH 무차별 대입을 차단한다.
사용자가 직접 쓰는 관리 도구(pgAdmin·Portainer·MinIO)의 **외부 접근은 유지**하되 인증 계층 뒤로 옮긴다.

## 배경 (2026-07-21 실측 — 등급 판정 근거)
- ufw inactive(방화벽 없음), fail2ban 없음
- sshd: PermitRootLogin **yes**, PasswordAuthentication 유효값 **yes**
  (50-cloud-init.conf 의 yes 가 60-cloudimg 의 no 보다 먼저 로드 — sshd 는 선착 값 우선)
- 외부(0.0.0.0) 개방 19포트: 22, 80, 443, **8080(Jenkins)**, 5001/5002/5010/5011(API),
  **5432/5433/54322(PG×3)**, **27021(Mongo)**, **8090(pgAdmin)**, **9000/9443(Portainer)**,
  **9001/9005(MinIO)**, 8085(구웹), 3030(syncace)
- 가점: PG18:5434 는 localhost 전용(핵심 운영 DB 안전), 전 서비스 자체 인증 존재,
  unattended-upgrades 활성, 컨테이너 격리, nginx TLS
- 마스터 개인키 평문 + 122 slug 공유(certificados/key), 프론트 x-api-key '12345' 하드코딩
- ※Jenkins 8080: GitHub 실웹훅은 현재 작동하지 않음(푸시 후 수동 시뮬레이션으로 트리거해 옴)
  → 외부 개방 불필요 판단. 단, 향후 GitHub 웹훅 복구 원하면 nginx 로 /github-webhook/ 만 프록시.

## 결정 필요 (D1~D3)
- **D1. 관리 도구 접근 방식** (사용자: 외부 직접 접속 사용 중 — 아래 §접근 대체 방법 참조)
  - (a) nginx 서브도메인 + HTTPS + basic auth (지금처럼 브라우저로 어디서나 — **권장**)
  - (b) SSH 터널 (가장 강력, 접속 전 터널 명령 1회 필요)
  - 도구별 혼합 가능 (예: pgAdmin·Portainer=(a), MinIO 콘솔=(b))
- **D2. MinIO 9005(S3 API) 앱 의존 확인**: carpetas-compartidas 등에서 프론트/외부가
  MinIO URL 을 직접 호출하는지 — 직접 호출하면 nginx 프록시 경유로 전환 필요 (차단 금지!)
- **D3. 고정 IP 여부**: 사무실/집 IP 고정이면 nginx allow/deny 로 IP 제한 추가(무료 보안 +1)

## 태스크 목록

### Wave A — 무중단 즉시 (승인 후 바로)
- [ ] TASK-1: sshd 강화 — PermitRootLogin no + PasswordAuthentication no (키 인증 유지 확인
      후! 기존 SSH 세션 유지한 채 새 창 접속 테스트 → 성공 시에만 reload) + AllowUsers jhkim
- [ ] TASK-2: fail2ban 설치·활성 (sshd jail 기본)
- [ ] TASK-3: certificados 권한 — 마스터키·slug key 파일 600, 폴더 소유 정리
- [ ] TASK-4: 접속 실패 로그 현황 캡처 (before/after 비교용 — lastb | wc)

### Wave B — 관리 도구 인증 계층 (D1 결정 후, 짧은 재시작 영업시간 외)
- [ ] TASK-5: nginx 서브도메인 3종 생성 — pgadmin./portainer./minio.coolsistema.com
      + certbot TLS + htpasswd basic auth (+D3 시 IP allowlist)
- [ ] TASK-6: docker compose 바인딩 변경 — pgAdmin 8090, Portainer 9000/9443, MinIO 9001,
      Mongo 27021, Jenkins 8080 → **127.0.0.1:포트** (nginx 만 접근)
- [ ] TASK-7: MinIO 9005 처리 (D2 결과에 따라: 앱 미사용→127.0.0.1 / 사용→nginx 프록시)
- [ ] TASK-8: PG 5432/5433/54322 → 127.0.0.1 바인딩 (앱은 전부 서버 내부/도커 네트워크 접속
      — 외부 의존 없음 확인 후. pgAdmin 이 도커 네트워크로 접속하므로 무영향)
- [ ] TASK-9: 각 도구 접속 검증 (새 URL/터널로 로그인 확인) → 이상 시 즉시 원복

### Wave C — 마무리
- [ ] TASK-10: ufw enable (22/80/443 allow) — 도커 우회 특성상 바인딩 정리(Wave B) 후
      2차 방어선으로만. DOCKER-USER 체인 규칙 추가는 선택.
- [ ] TASK-11: x-api-key '12345' → 실키 교체 (front env + api 검증측 동기 배포)
- [ ] TASK-12: cool-invoice 온보딩 개별 키 생성으로 변경 (플랜 B CondIVA 패치와 함께)
- [ ] TASK-13: 보안 점검 스크립트 tools/security-check.sh (포트·sshd·fail2ban 상태 리포트)

## 접근 대체 방법 상세 (D1 참고자료)

### 방법 (a) — nginx 서브도메인 + basic auth (권장: 지금 사용 습관 그대로)
접속 주소만 바뀜: `http://IP:8090` → `https://pgadmin.coolsistema.com` (브라우저 비밀번호
프롬프트 1회 → 기존 pgAdmin 로그인). 서버 구성 예:
```nginx
server {
  server_name pgadmin.coolsistema.com;
  listen 443 ssl;  # certbot 이 인증서 처리
  auth_basic "Restricted";
  auth_basic_user_file /etc/nginx/.htpasswd;   # htpasswd -c 로 생성
  location / { proxy_pass http://127.0.0.1:8090; proxy_set_header Host $host; }
}
```
- 장점: 어디서나·모바일에서도 사용, HTTPS 암호화, 도구 자체 취약점 앞에 2차 벽
- 단점: 여전히 인터넷에 문이 있음(단, nginx+basic auth 를 뚫어야 도구에 닿음)
- Portainer 는 9443(자체 TLS) 대신 9000 을 프록시. MinIO 콘솔은 websocket 헤더 추가 필요.

### 방법 (b) — SSH 터널 (가장 강력: 문 자체가 없음)
서비스는 127.0.0.1 전용 → 사용 전 Mac 터미널에서 터널 1회:
```bash
ssh -N -L 8090:127.0.0.1:8090 -L 9000:127.0.0.1:9000 -L 9001:127.0.0.1:9001 jhkim@62.72.7.245
```
→ 브라우저에서 `http://localhost:8090` (pgAdmin), `localhost:9000` (Portainer), `localhost:9001` (MinIO).
~/.ssh/config 에 등록하면 `ssh -N tunel` 한 단어로 실행:
```
Host tunel
  HostName 62.72.7.245
  User jhkim
  LocalForward 8090 127.0.0.1:8090
  LocalForward 9000 127.0.0.1:9000
  LocalForward 9001 127.0.0.1:9001
```
- 장점: 외부에서 포트 자체가 안 보임 — 해당 서비스의 원격 공격면 0
- 단점: 접속 전 터널 실행 필요(Mac 로그인 시 자동 실행 등록 가능), 폰에서는 불편

## 완료 기준
- 외부 개방 포트 = 22/80/443 (+D2 에 따라 MinIO 프록시 경로)
- ssh root/password 로그인 불가, fail2ban 동작 (banned IP 카운트 확인)
- 관리 도구 3종 모두 새 경로로 정상 사용 확인 (사용자 직접 확인)
- 기존 서비스(POS·API·발급·백업·Jenkins 빌드) 전부 무영향 — 스모크 통과

## 함정 3가지
1. **자기 잠금(lockout)**: sshd 변경 후 기존 세션 끊기 전에 반드시 새 창에서 키 접속 검증.
   비상용으로 호스팅사(콘솔) 접근 경로 확인해 둘 것.
2. **docker 는 ufw 를 우회**: 방화벽만 켜고 안심 금지 — 반드시 바인딩(127.0.0.1) 우선.
3. **숨은 외부 의존**: MinIO S3 URL·모바일 앱·webhook 등이 특정 포트를 직접 부를 수 있음
   — 바인딩 변경 전 D2 확인 + 하나씩 변경·검증 (한꺼번에 X).

## 점검 포인트
- 1주: fail2ban 차단 통계, 접속 실패 로그 감소 확인, 도구 사용 불편 여부
- 1개월: 외부 포트 스캔 재실행(22/80/443 만), x-api-key 교체 완료
- 3개월: 개별 키 온보딩 적용 확인, 인증서 갱신 시 개별 키 회전 시작 여부 결정

## 금지사항
- 모든 서버 설정 변경·재시작은 승인 게이트 + 영업시간 외
- 한 번에 여러 서비스 바인딩 변경 금지 — 하나 변경→검증→다음
- sshd 변경 시 세션 이중화 필수
