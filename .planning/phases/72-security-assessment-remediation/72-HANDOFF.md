# Phase 72 — 재개용 핸드오프 (2026-08-06 갱신)

이 문서 하나만 읽으면 다음 세션이 바로 이어갈 수 있게 쓴 것이다.

---

## 1. 지금 상태 한 줄

**72-01 · 72-02 완료(배포 검증까지). 72-03 · 71-02 코드 완료 + 배포 검증 — 실기기 검증만 남음.**

전 세션의 미검증 항목(Jenkins 빌드)은 **해소됐다**. 이후 배포도 전부 커밋 대조까지 확인:
api #609/#610, front #534/#535/#536 모두 SUCCESS.

남은 것은 **코드로는 더 확인할 수 없는 실기기 검증 2건**뿐이다 — 72-03(관리자앱 지문
재로그인·회수), 71-02(모바일 사이드바·다크 첫 페인트). 각 절 끝의 «남은 검증» 참조.

---

## 2. git 상태

| 저장소 | HEAD | 마지막 커밋 |
|---|---|---|
| root | `289cd2e` | ventago-app gitlink 갱신 (모바일 사이드바 + 다크 모드 깜빡임, P71-02) |
| api-ventago | `9b73fea` | 관리자앱 기기 토큰 — 원문 비밀번호 보관을 대체 (P72-03 백엔드) |
| ventago-app | `db75525` | 모바일 사이드바 저장값 오염 + 다크 모드 흰 화면 깜빡임 (P71-02) |

**커밋되지 않은 것들 (모두 이번 작업과 무관한 기존 WIP — 건드리지 말 것):**
```
 M .claude/hooks/.gsd-snapshot.json
 M manuales/manual_ventas.md
 M package-lock.json
?? setup-mcp-postgres-ssh.sh          ← 사용자 파일. codex 지적 미반영(아래 6절)
 M api-ventago/commit-wave1-security.sh   ← 1줄 변경, 잔여 스크립트
```

---

## 3. ★ 재개 첫 동작

SSH 키는 이제 agent 에 등록돼 있다(`ssh-add -l` 로 확인). 끊겼으면 원인은 **passphrase +
빈 ssh-agent** 이지 키 미등록이 아니다 — 이 지점을 이미 두 번 오진했다:

```
! ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

빌드/배포 확인 명령:

```bash
# 최근 빌드 번호 + 결과
ssh jhkim-server "for j in api-new-coolsistema front-coolsistema; do echo \"=== \$j ===\"; \
  for b in \$(ls -1 /var/lib/jenkins/jobs/\$j/builds/ | grep -E '^[0-9]+\$' | sort -n | tail -3); do \
    echo \"  #\$b \$(grep -o '<result>[A-Z]*</result>' /var/lib/jenkins/jobs/\$j/builds/\$b/build.xml)\"; done; done"

# 빌드가 실제로 어떤 커밋을 담았는지 (여기까지 봐야 "배포됐다"고 할 수 있다)
ssh jhkim-server "grep -oE '(Checking out Revision|Commit message:).*' /var/lib/jenkins/jobs/<job>/builds/<n>/log | head -4"

# 컨테이너 재생성 확인
ssh jhkim-server "docker ps --format '{{.Names}}\t{{.Status}}' | grep -i coolsistema"
```

---

## 4. 완료분 요약

### 72-01 edge-agent 배포 게이트 (코드 완료 / 실환경 미검증)

결정: **인증은 HMAC-SHA256** (RS256 아님). edge 가 이미 `branch_agents.api_key` 로 서버와 공유
비밀을 갖고 있고 서버 JWT 도 HS256 이라, RS256 은 전 클라이언트에 파급된다.
결정: **해시 미러 제거** (사용자 선택). 프론트가 오프라인 로그인을 호출한 적이 없어 비용 0.

바뀐 것:
- `api-ventago/src/app/offline-sync/offline-sync.service.ts` — `MIRROR_SECRET_COLUMNS` 이름 기준 필터.
  **보고서가 지적한 `users.password` 뿐 아니라 `users.mobile_pin` 과 `branch_agents.api_key` 도 미러에
  나가고 있었다.** `api_key` 는 에이전트가 서버에 인증하는 수단이라 더 위험했다.
  registry 가 `SELECT t.*` 이므로 컬럼 열거식이 아니라 이름 필터로 막았다 — 열거식은 나중에 추가되는
  비밀 컬럼을 조용히 흘린다.
- `api-ventago/src/app/offline-sync/edge-ticket.service.ts` (신규) — `signEdgeTicket`/`verifyEdgeTicket`,
  payload `{u,s,b,exp}`, TTL 12h, `timingSafeEqual`(길이 선검사). Controller 는 OfflineSyncModule 에 등록됨.
- `edge-agent/src/edge-ticket.js` (신규) — 서버 검증 로직 미러. **둘은 같이 바뀌어야 한다**(주석 명시).
- `edge-agent/src/server.js` — `decodeJwtPayload`·bcrypt 제거, CORS 허용목록(미허용 origin 403),
  `/api/health` 뒤 auth 미들웨어(유효 `x-edge-ticket` 없으면 401), 신원은 검증된 티켓에서만
  (`req.identity.u`), `/api/offline/auth/login` 삭제.
- `edge-agent/src/config.js` — `bindHost: '127.0.0.1'` 기본, `corsOrigins` 기본에 운영 origin 포함.
- `ventago-app` — `offline-mode.service.ts` 의 `refreshEdgeTicket()`(로그인 직후 + 클라우드 복구 직후
  호출), 위조 가능하던 `x-user-id` 제거.

**codex 가 잡은 내 치명적 누락 2건 (빌드로는 안 잡히는 것들):**
1. `refreshEdgeTicket()` 을 정의만 하고 아무 데서도 호출하지 않았다 → 모든 edge 요청 401 될 상태였다.
2. edge 기본 CORS 에 운영 origin 이 빠져 있었다 → 환경변수 없는 기존 설치가 티켓 검증 전에 403.

**미검증:** edge-agent 가 어디에도 배포돼 있지 않아 E2E(타 기기 차단 / 위조 토큰 거부 / 오프라인 판매
왕복)를 못 돌렸다. 72-01-PLAN.md 의 verification 항목은 **edge 를 실제로 띄울 때 확인해야 한다.**

### 72-02 보안 헤더 (완료 — 운영 응답으로 검증, 후속 1건)

`ventago-app/next.config.js` 에 X-Frame-Options DENY / X-Content-Type-Options / Referrer-Policy /
Permissions-Policy / **CSP-Report-Only** + prod 한정 HSTS. 수집 엔드포인트
`ventago-app/src/pages/api/csp-report.ts`. Next.js 13.5.11 로 올리며 lockfile 재생성.
`curl -I https://app.coolsistema.com/` 로 6개 헤더 전부 실제 응답에 실리는 것을 확인했다.

**2026-08-06 발견·수정: 리포트가 전부 버려지고 있었다.**
`report-uri /api/csp-report` (슬래시 없음) + `trailingSlash: true` → nginx 가 308 로
`/api/csp-report/` 에 리다이렉트하는데, **CSP 보고 요청은 사양상 리다이렉트를 따르지 않는다.**
배포 후 3시간 동안 수집 0건이었던 이유가 이것이다. `report-uri /api/csp-report/` 로 수정(`de80175`).
슬래시 경로에 직접 POST → 204 + 서버 로그 기록까지 확인했다.
→ **"0건"과 "수집이 안 됨"은 겉보기가 같다.** 수집 파이프라인은 합성 리포트로 따로 찔러봐야 한다.

**후속(변동 없음):** 위반 리포트를 얼마간 모은 뒤 **Report-Only → enforce 전환.**
전환 전 반드시 결정할 것: `connect-src` 의 bare `http:`. LAN edge-agent(매장마다 다른 사설
IP:포트)를 열거할 수 없어 남겼는데, 이 상태로 enforce 하면 **모든 http 출처로의 연결이 허용**돼
connect-src 가 사실상 무력하다. CSP host-source 는 IP 옥텟 와일드카드를 지원하지 않으므로
edge 접근 방식 자체를 바꾸지 않는 한 좁힐 수 없다.

### 부수적으로 고친 운영 장애 3건

`ventago.coolsistema.com` 은 실제로 프록시되지 않는 호스트다(307 → `/25` → 404).
진짜 vhost 는 `app.coolsistema.com` / `new.coolsistema.com`. 이 오래된 호스트명 때문에
**Socket.io 가 전 사용자에게 거부**되고 있었고, MP OAuth 404, 인쇄 QR 404 도 같은 원인이었다.
30개 파일 정정(`ab0bd2e`) + `ws-cors.ts` 기본 허용목록 교체.

---

## 5. 완료 작업 상세 (72-03 · 71-02) — 둘 다 실기기 검증만 남음

### 72-03 관리자앱 원문 비밀번호 제거

**사용자 결정(2026-08-06): 관리자앱 전용 디바이스 토큰.** 전사 refresh token 인프라는
active_sessions(userId UNIQUE)·SessionGuard 와의 상호작용을 전부 재설계해야 해서 채택하지 않았다.
웹/POS/에이전트의 기존 로그인·JWT 흐름은 **한 줄도 건드리지 않았다.**

#### 만든 것

백엔드 (`9b73fea`) — `api-ventago/src/app/auth/`
- `admin-device-token.model.ts` / `admin-device-token.service.ts` / `dto/device-token.dto.ts`
- 라우트 5개: `POST device/register`(superadmin JWT 필수) / `POST device/refresh`(@Public) /
  `POST device/revoke`(@Public) / `GET device`(목록) / `DELETE device/:id`(원격 회수)
- `auth.service.ts` 에 **`issueAccessToken()` 추출** — signIn 과 기기 refresh 가 같은 함수로
  토큰을 만든다. 두 경로가 payload 를 각자 조립하면 한쪽만 roles 필터가 바뀔 때 관리자앱만
  다른 권한의 토큰을 받고, 그 차이는 런타임에서야 드러난다.
- spec 12건 (`admin-device-token.service.spec.ts`) — 전부 통과. auth 폴더 전체 43건도 통과.

앱 (`2eb4ce9`) — `ventago-admin-app/lib/`
- 로그인 성공 → `registerDevice()`. **원문 비밀번호 저장 제거.**
- 지문 성공 → `refreshWithDevice()`. 회전된 토큰을 반드시 저장(안 하면 다음 지문이 막힌다).
- `bootstrap()` 에서 **`admin_saved_pass` 삭제** — 기존 설치분 정리. 이게 빠지면 코드만 고치고
  이미 깔린 단말엔 원문이 계속 남는다.
- 로그아웃을 UI 선택으로: "Cerrar sesión"(지문 재입장 가능) vs "Olvidar este dispositivo"(서버 회수).
- dio 401 인터셉터에서 `/auth/device/` 제외 — 아니면 지문 실패마다 "Sesión expirada" 가 뜬다.

DB: `migrations/2026-08-06-admin-device-tokens.sql` — **운영 5434 적용 완료**
(테이블+시퀀스 owner `coolsistema` 확인). 로컬 PG 미기동이라 미적용 → 6절 참조.

#### 설계상 알아둘 것 (다시 건드릴 때)

- **회전 유예창 60초.** 서버가 회전을 커밋한 뒤 응답이 유실되면 단말은 구토큰을 들고 재시도한다.
  이걸 탈취로 오인해 회수하면 정당한 관리자가 잠긴다 — 지문을 지키려던 작업이 지문을 깨는 셈이다.
  창 안이면 **새 토큰을 재발급**한다(해시만 저장하므로 "현재 토큰 반환"은 물리적으로 불가능).
  창 밖의 구토큰 제시는 탈취로 보고 기기를 회수한다. `rotatedAt` 은 재시도로 갱신하지 않는다 —
  갱신하면 유예창이 무한 연장돼 재사용 탐지가 죽는다.
- macOS `useDataProtectionKeyChain: false` 는 **그대로 뒀다.** 의도적 우회이고 entitlement 없이
  `true` 로 되돌리면 `errSecMissingEntitlement(-34018)` 로 저장이 통째로 깨진다. 대신 그 저장소에
  담기는 **내용**을 원문 비밀번호 → 회수 가능한 토큰으로 낮췄다. 근본 해결(앱 서명/entitlement 정비)은
  이번 범위 밖 — 계획서 task 4 의 "불가능하면 그 사실과 이유를 기록한다"에 해당한다.

#### ★ 남은 검증 (실기기 필요 — 코드로는 더 못 한다)

계획서 `<verification>` 항목 그대로:
1. 로그인 → 앱 종료 → **지문으로 재로그인 성공** (기능이 유지되는지)
2. 단말 저장소에 `admin_saved_pass` 가 없다 (기존 설치분도 업데이트 후 사라지는지)
3. `DELETE /auth/device/:id` 로 회수 후 해당 단말이 재로그인 **못 하는지**
4. 로그아웃 두 메뉴가 문서대로 동작하는지

서버 쪽 상태는 다음으로 즉시 볼 수 있다:
```bash
ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -c \
  'SELECT id,user_id,device_id,platform,issued_at,last_used_at,revoked_at,revoked_reason \
   FROM admin_device_tokens ORDER BY id DESC LIMIT 10;'"
```
운영 superadmin 은 `users.id=1` (`superadmin@ventago.test`, store_id NULL) 하나뿐이다.

### 71-02 모바일 사이드바 + 다크 모드 플래시 (2026-08-06 완료, 실기기 검증 남음)

커밋 `db75525` (ventago-app) / gitlink `289cd2e`. front 빌드 #536 SUCCESS, 배포 커밋 대조 완료.

**모바일 사이드바 — 저장값 오염 수정**

`Layout` 이 모바일 진입 시 `saveSettings({ navCollapsed: false })` 로 사용자 설정 자체를 바꾸고
데스크톱 복귀 시 ref 로 되돌리고 있었다. 두 가지가 틀렸다:
1. 화면 폭 때문에 설정이 영구히 덮인다(모바일에서 앱을 닫으면 false 가 남는다).
2. **복원은 항상 이 effect 보다 늦다.** React 가 자식 effect 를 먼저 돌리므로 Layout 의 effect 는
   언제나 복원 전 기본값만 보고 지나간다 — "늦으면 누락"이 아니라 **항상 누락**이다.
   모바일 드로어 폭은 `hidden` 과 무관하게 `navCollapsed` 로 정해지므로(`Drawer.tsx:180`),
   접힘을 켜 둔 사용자는 모바일에서 **라벨도 안 보이는 좁은 레일**로 메뉴가 열렸다.

→ `getEffectiveSettings(settings, hidden)` (`@core/layouts/utils.ts`) 로 표시값만 계산.
   effect·ref 제거. 데스크톱에서는 입력 객체를 그대로 반환해 참조 안정성을 유지한다.

**주의 — 이 구조가 만든 함정 2개 (같이 막아뒀다):**
- `Layout` 에만 마스킹하면 안 된다. `UserLayout` 의 사이드바 콜백들이 원본 `settings` 를 읽어
  **드로어는 전체 폭인데 내용물만 `opacity:0` 인 빈 메뉴**가 된다. 두 곳이 같은 헬퍼를 쓴다.
- 핀 토글이 `saveSettings({ ...settings, ... })` 로 **전체를 펼쳐 저장**하고 있었다. 마스킹된
  스냅샷이 그대로 저장되면 표시용 값이 사용자 설정을 덮는다. 함수형 패치로 교체
  (`UserLayout`, `VerticalNavHeader`). **앞으로 마스킹된 settings 를 받는 컴포넌트에서
  스프레드 저장을 부활시키지 말 것.**

**다크 모드 깜빡임 — 쿠키+SSR 로 가지 않았다**

이 앱은 페이지가 **전부 정적 생성(○)** 이라 요청 시점 쿠키를 읽을 수 없다. 읽으려면
`_app.getInitialProps` 가 필요하고 그러면 자동 정적 최적화가 꺼져 **모든 페이지가 매 요청
서버 렌더**가 된다. 깜빡임 하나 때문에 전 페이지 렌더 계약과 P95 300ms 목표를 바꾸는 건
균형이 맞지 않는다고 판단했다. (ROADMAP 의 «쿠키 기반 SSR» 항목은 이 근거로 보류.)

실제로 다크 사용자가 보는 흰 화면은 `AuthLoadingShell` 이 light 팔레트로 칠해진 것이다.
그래서 React 밖에서, 페인트 전에, 배경색만 맞춘다:
- `_document` 동기 인라인 스크립트 → localStorage 의 `mode`/`skin` 을 읽어 CSS 변수
  `--ventago-bg-default` + `html[data-theme]` 설정. **React 트리를 안 건드리므로 hydration
  불일치가 없다** — 이전 시도가 여기서 깨졌다(`settingsContext.tsx` 주석 참조).
- 부트스트랩 CSS 를 **emotion SSR 스타일 뒤에** 주입(`getInitialProps` 의 styles 배열 마지막).
  `.auth-loading-shell` 만 `!important` — emotion 이 클라이언트에서 뒤에 주입할 수 있어서다.
- `ThemeComponent` 가 이후 변수를 현재 테마와 계속 동기화(런타임 테마 변경 후 재등장하는
  대기 화면이 이전 색으로 남는 것 방지).

색은 `palette/index.ts` 의 `defaultBgColor()` 와 **반드시 일치해야 한다** — 한쪽만 바꾸면
첫 페인트와 hydration 후 색이 어긋나 오히려 깜빡임이 생긴다.
dark `#141C28` / dark+bordered `#1A2332` / light·semi-dark `#F8F7FA`.

검증: 운영 HTML 에서 스크립트 존재 · CSS 가 emotion 뒤 · 셸 클래스 존재를 확인했고,
스크립트를 5개 설정 조합으로 실행해 반환색을 팔레트와 대조했다.

**★ CSP 부채:** 이 인라인 스크립트는 `script-src 'unsafe-inline'` 에 의존한다.
enforce 전환 때 그걸 빼려면 **nonce 를 붙여야 한다** — 그냥 빼면 깜빡임이 되돌아온다.

**남은 검증 (실기기):** 데스크톱에서 접기 → 모바일 폭 → 메뉴가 펼쳐진 형태인지 →
새로고침 → 데스크톱 복귀 시 다시 접혀 있는지 → **localStorage 의 `navCollapsed` 가
모바일 진입 전후 동일한지**(이번 수정의 핵심). 테마는 다크 저장 후 새로고침해
첫 페인트 배경 확인.

---

## 6. 미해결 잔여 항목

- **`setup-mcp-postgres-ssh.sh`** (untracked, 사용자 파일). codex 지적 3건 미반영:
  `.pgpass` 이스케이핑, 임시파일 권한, sshd listen-address 확인. 제안만 하고 손대지 않았다.
- **운영 서버 `/root` 의 비밀 파일 3개 (600)** — 사용자가 password manager 로 옮기고 삭제할 것:
  `coolsistema.newpw.20260805-rot`, `coolsistema.oldhash.20260805-rot`,
  `shop_readonly.newpw.20260805-shopro`
- **로컬 Mac 에 `ventago` DB 가 없다** (2026-08-06 재확인: 5432 소켓 자체가 없어 PG 미기동).
  아래 마이그레이션 **3건이 운영 5434 에만** 적용된 상태다. CLAUDE.md 는 양쪽 동시 적용을 요구한다 —
  로컬 DB 를 세울 때 이 셋을 함께 적용해야 스키마가 갈라지지 않는다:
  ```
  api-ventago/migrations/2026-08-05-approval-request-policy-snapshot.sql
  api-ventago/migrations/2026-08-05-shop-readonly-role.sql
  api-ventago/migrations/2026-08-06-admin-device-tokens.sql
  ```
- **CSP Report-Only → enforce** 전환 (위 72-02). 이제 리포트가 실제로 수집되므로
  `docker logs ventagoapp | grep '[csp-report]'` 로 며칠 모은 뒤 판단할 수 있다.
  전환 전 **반드시 결정할 것 2가지**:
  1. `connect-src` 의 bare `http:` — 그대로 두고 enforce 하면 모든 http 출처가 허용돼
     connect-src 가 사실상 무력하다(LAN edge-agent 때문에 남긴 것. 71-02 절 참조).
  2. `script-src 'unsafe-inline'` — `_document` 의 테마 부트스트랩 스크립트가 이것에
     의존한다. 빼려면 **nonce 를 붙여야** 하고, 그냥 빼면 다크 모드 깜빡임이 되돌아온다.

---

## 7. 이 세션에서 배운 것 (반복 방지)

- **SSH 실패를 키 등록 문제로 오진하지 마라.** 이 환경의 원인은 passphrase + 빈 ssh-agent 였고,
  내가 붙인 `BatchMode=yes` 가 프롬프트를 숨겨 증상을 가렸다.
- **대량 문자열 치환은 반드시 정확한 긴 패턴으로만.** 짧은 토큰("postgres")으로 돌렸다가 178개 파일을
  오염시켜 되돌렸고, 호스트명 치환 때는 내 주석과 `qr-fit.test.js`(URL 50→46 바이트)를 깨뜨렸다.
- **`psql -c` 는 `:'var'` 를 보간하지 않는다.** stdin 파이프로 넘길 것(`ps` 노출도 피한다).
- **빌드 통과 ≠ 동작.** 이번 72-01 의 치명적 결함 2건은 전부 타입체크·빌드를 통과했고 codex 리뷰에서만
  잡혔다. 배선(호출부 존재 여부)과 기본값(환경변수 없는 기존 설치)은 별도로 확인해야 한다.

(2026-08-06 추가)

- **"수집 0건"을 "위반 0건"으로 읽지 마라.** CSP 리포트가 3시간 내내 0건이었던 건 위반이 없어서가
  아니라 `report-uri` 가 308 리다이렉트를 타서 전부 버려졌기 때문이다. **파이프라인은 합성 데이터로
  직접 찔러 확인**해야 한다 — 빈 결과와 고장난 수집은 겉보기가 같다.
  (일반화: `trailingSlash: true` 인 앱에서 리다이렉트를 따르지 않는 클라이언트 — CSP 보고, webhook,
  일부 SDK — 를 상대하는 경로는 슬래시를 정확히 맞춰야 한다.)
- **배포 검증은 빌드 결과가 아니라 "어떤 커밋이 담겼나"까지 본다.** Jenkins 로그의
  `Checking out Revision` 을 push 한 HEAD 와 대조해야 "배포됐다"고 말할 수 있다.
- **새 엔드포인트는 배포 후 실제로 찔러본다.** 라우트 미등록(404)·모듈 미등록·테이블 부재는 전부
  빌드를 통과한다. bogus 입력으로 **의도한 401/400 이 우리 메시지로** 돌아오는지 확인하면
  라우트·가드·DTO·DB 까지 한 번에 검증된다.
- **상태 기계는 단위 테스트로 고정한다.** 회전/유예/재사용 감지처럼 "두 번째 호출에서야" 드러나는
  로직은 너무 엄격하면 사용자가 잠기고 너무 느슨하면 구자격증명이 통하는데, **양쪽 실패 모두
  타입체크를 통과한다.**
