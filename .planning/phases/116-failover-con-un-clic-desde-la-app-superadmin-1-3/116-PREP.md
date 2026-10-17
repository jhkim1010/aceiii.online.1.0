# Phase 116 — superadmin 전용앱에서 한 번의 클릭으로 전환 (운용1 → 운용3)

등록 2026-10-17. 대화로 정한 방향만. 설계는 discuss 부터.

## 사용자 요청
「운용1과 3의 전환을 superadmin 용 전용앱에서 한번의 클릭으로 전환하게 할 수 있을까?」

## 현재 상태 (2026-10-17)
- 복제: 자동·실시간(운용1 PG18 → 운용3 streaming, lag ~0.05s) · MinIO 사본 1h.
- 감지: 자동(감시 3곳 → 텔레그램).
- 전환: **수동** — 운용3 `/usr/local/sbin/ventago-failover`, 확인 문구 `PROMOVER ventago`, TTY 필요. 실측 55s.
- DNS: **수동**(GoDaddy). TTL 300 으로 아직 안 내림.
- 운용3 API 이미지: 배포마다 수동 반입(낡으면 옛 코드가 뜬다).
- 복귀: Mac 에서 `failback.sh`(`VOLVER A PROD`), 실측 90s.
- 부활 가드: 운용3 PROMOVIDO 이면 운영 PG 기동 거부(실측).

## 핵심 제약
버튼이 운용1 API(`newapi`)를 거치면 **운용1이 죽었을 때 버튼도 죽는다.**
→ 운용3 위의 별도 제어 서비스(운용3 직행 주소, 예 `control.coolsistema.com`)가 기존 failover 스크립트를 부른다.

```
관리자앱 ──(평소)──────→ 운용1 API
        └─(전환 버튼)──→ 운용3 제어 서비스 → ventago-failover (비대화형 모드)
```

## 안전장치 (초안)
1. 인증: 관리자앱 기기 토큰 + 지문([[admin-app-device-token-replaces-password]]). 제어 서비스는 별도 키·IP 제한 검토.
2. 누르기 전 상태판: 운용1 생존을 **두 지점**(운용3 + srv2 감시)에서 판정 · 복제 lag · 운용3 이미지가 운영과 같은지.
3. 잠금: 운용1 이 살아 있으면 잠금(split-brain) · lag 기준 초과면 잠금(**RPO 게이트** — CODEX 115 지적, 현 스크립트엔 없음).
4. 확인 동작: 길게 누르기 또는 문구 입력.
5. 기록: 누가·언제 → 감사 로그 + 텔레그램.
6. 스크립트 비대화형 실행 경로: 현재 TTY·확인 문구 전제 → 제어 서비스용 인자/토큰 방식 필요. 스크립트 자체 검사는 그대로 유지.

## 미결 (착수 시 결정)
- **DNS 방식** — 이것이 「한 번의 클릭」을 정한다:
  - GoDaddy API 키 → 버튼이 A 레코드 변경, TTL(300s 로 내려도 최대 5분) 지연.
  - Cloudflare 프록시 → 원본만 바꿔 수 초 전환, TTL 문제 없음. 도메인 DNS 이관 필요(사용자 결정). Claude 추천.
- 복귀도 앱에서 할지 — 초안: 처음엔 **전환만**, 복귀는 터미널(계획된 야간 작업).
- 운용2(미래, Phase 115)를 제3 판정자로 쓰면 자동 전환까지 갈 수 있다 — 이 Phase 범위 밖.

## 선행 작업 (이 Phase 전에 하면 좋은 것)
1. DNS TTL 300(사용자, GoDaddy)
2. 운용3 API 이미지를 배포마다 자동 동기화
3. failover 에 RPO 게이트(lag 초과 시 승격 차단)

---

## 결정 보강 (2026-10-17, 사용자 승인) — Cloudflare 무료 + srv2 판정 + 반자동 → 자동

**DNS**: Cloudflare 무료 플랜(Claude 추천, 사용자가 무료 방식 선택). GoDaddy 는 **등록·갱신 그대로**, 네임서버만 Cloudflare 로.
유료 Load Balancing($5)은 쓰지 않는다 — 트래픽만 넘길 뿐 **DB 승격은 안 해 주므로** 무료와 차이가 작다.

**왜 DNS 만 바꾸면 안 되나**: 운용3 DB 는 평소 읽기 전용 복제본. 원본만 돌리면 화면은 뜨고 판매·재고 저장은 전부 실패.
→ 순서 고정: ① 운용1 다운 판정 → ② 운용3 승격(failover, RPO 게이트 포함) → ③ 성공 시에만 Cloudflare 원본 변경.

**구성**
- 제3 판정자 = **srv2(74.208.60.137)** — 가용성 감시가 이미 돈다([[ventago-uptime-watchdogs-two-servers]]).
- 판정: srv2 **와** 운용3 이 **둘 다** 운용1 다운을 N분 연속 볼 때만(둘 사이만 끊긴 경우 오판 방지).
- 실행: srv2 → 운용3 승격 지시 → 성공 시 Cloudflare API 로 app·newapi 원본 = 운용3.
- 펜싱 이중화: Cloudflare 프록시가 원본을 바꾸면 운용1 이 되살아나도 사용자 트래픽이 안 간다 + 기존 부활 가드(운용1 PG 기동 차단).

**단계**
1. **반자동(먼저)**: srv2 판정 → 텔레그램 + 관리자앱 알림 → 사용자가 **한 번 클릭**(이 Phase 의 버튼).
2. **완전 자동(나중)**: 리허설로 판정 신뢰가 쌓이면 예) 「두 지점에서 5분 이상 다운」→ 자동. 
   근거: 2026-10-16 Hostinger 하이퍼바이저 정지 18분 후 자체 복구 — 자동이었다면 불필요한 전환 + 야간 복귀(정지 ~90s). 비동기 복제라 전환 순간 미전송 판매 유실 가능.

**Cloudflare 이전 체크리스트 (착수 시)**
- 레코드 전수 대조: app·newapi·apiminio·`*.coolsistema.com`(쇼핑몰 와일드카드)·coolinvoice·ubf·**MX·TXT(SPF/DKIM)** 등. 빠지면 그 서비스가 끊긴다.
- 주황 구름(프록시)은 **app·newapi 만**. 나머지는 회색(DNS 만) = 지금과 동일.
- GoDaddy DNSSEC 켜져 있으면 네임서버 변경 **전에** 끈다.
- 고객 IP: nginx + `trustedClientIp()` 가 `CF-Connecting-IP` 를 믿게(Cloudflare IP 대역만). 빠뜨리면 지점 IP 등록·세션 보안이 Cloudflare IP 로 잡힌다([[nginx-appends-xff-so-first-value-is-attacker-input]]).
- 무료 한도: 업로드 100MB · 프록시 응답 100초 — 이를 넘는 요청(긴 보고서·업로드) 점검. WebSocket(소켓·print-agent) 지원.
- 운용1·운용3 인증서: Cloudflare Origin Certificate 로 통일 검토.
- IP 로 직접 붙는 것(PG10 레거시 pgbouncer)은 영향 없음 — 호스트명으로 붙는다면 회색 레코드.
- 세션은 DB(active_sessions)에 있어 복제됨 → 전환해도 유지. Redis(캐시·소켓 어댑터)는 복제 안 됨 — 캐시 재생성만.
