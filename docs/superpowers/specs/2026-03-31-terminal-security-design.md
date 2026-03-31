# Terminal Security & Device Management Design

## 목적
멀티 터미널/카하 환경에서 부정 사용을 방지하고, 중복 로그인을 절대적으로 차단하는 시스템.

## 핵심 요구사항

1. **중복 로그인 절대 불가** — 한 유저는 동시에 하나의 세션만 유지. 새 로그인 시 기존 세션 즉시 무효화.
2. **디바이스 감지** — 같은 IP에서 새 디바이스 접속 시 터미널 등록 강제.
3. **IP 기반 지점 감지** — 완전히 다른 public IP에서 접속 시 새 Sucursal 등록 강제.

---

## 설계

### 1. ActiveSession 테이블 (중복 로그인 방지)

```
ActiveSession
├── id (PK)
├── userId (FK → Users, UNIQUE) — 유저당 1개만 존재
├── sessionToken (STRING, UNIQUE) — UUID v4
├── deviceFingerprint (STRING) — 브라우저 fingerprint hash
├── publicIp (VARCHAR)
├── userAgent (TEXT)
├── terminalId (FK → Terminal, nullable)
├── branchId (FK → Branch, nullable)
├── storeId (FK → Store)
├── lastActivityAt (TIMESTAMP)
├── createdAt, updatedAt
```

**로직**: 로그인 시 기존 ActiveSession 삭제 → 새 세션 생성 → sessionToken 반환.
모든 API 요청 시 JWT + sessionToken 검증. 불일치 시 401 + `SESSION_EXPIRED` 코드.

### 2. TerminalDevice 테이블 (디바이스-터미널 바인딩)

```
TerminalDevice
├── id (PK)
├── deviceFingerprint (STRING, UNIQUE per store)
├── publicIp (VARCHAR)
├── terminalId (FK → Terminal)
├── branchId (FK → Branch)
├── storeId (FK → Store)
├── registeredAt (TIMESTAMP)
├── lastSeenAt (TIMESTAMP)
```

### 3. BranchIpRegistry 테이블 (IP-지점 매핑)

```
BranchIpRegistry
├── id (PK)
├── publicIp (VARCHAR, UNIQUE per store)
├── branchId (FK → Branch)
├── storeId (FK → Store)
├── registeredAt (TIMESTAMP)
├── lastSeenAt (TIMESTAMP)
```

### 4. 로그인 플로우

```
1. 자격 증명 검증 (email/password)
2. 기존 ActiveSession 삭제 (중복 로그인 차단)
3. Public IP 추출
4. BranchIpRegistry에서 IP 확인
   └─ 미등록 IP → requireBranchRegistration: true 반환
5. TerminalDevice에서 fingerprint 확인
   └─ 미등록 디바이스 → requireTerminalRegistration: true 반환
6. 정상 → sessionToken + accessToken 발급
```

### 5. 프론트엔드 플로우

- 로그인 응답에 `requireBranchRegistration` 또는 `requireTerminalRegistration` 플래그
- 해당 모달 표시 → 사용자가 이름 입력 → POST로 등록 → 세션 완성
- 모든 API 요청에 `x-session-token` 헤더 추가
- 401 + `SESSION_EXPIRED` 수신 시 → 즉시 로그아웃 + "다른 기기에서 로그인되었습니다" 알림

### 6. Fingerprint 방식

브라우저에서 `navigator.userAgent + screen.width + screen.height + timezone + language + platform` 조합의 SHA-256 해시.
별도 라이브러리 없이 간단한 해시로 구현 (완벽할 필요 없음, 충분한 구별력).

---

## 파일 변경 목록

### 백엔드 (새 파일)
- `api-ventago/src/app/session/active-session.model.ts`
- `api-ventago/src/app/session/terminal-device.model.ts`
- `api-ventago/src/app/session/branch-ip-registry.model.ts`
- `api-ventago/src/app/session/session.service.ts`
- `api-ventago/src/app/session/session.controller.ts`
- `api-ventago/src/app/session/session.module.ts`
- `api-ventago/src/app/session/dto/register-terminal.dto.ts`
- `api-ventago/src/app/session/dto/register-branch.dto.ts`
- `api-ventago/src/app/session/guards/session.guard.ts`

### 백엔드 (수정)
- `api-ventago/src/app/auth/auth.service.ts` — signIn에 세션 로직 통합
- `api-ventago/src/app/auth/auth.module.ts` — SessionModule import
- `api-ventago/src/app/auth/auth.controller.ts` — IP/fingerprint 파라미터 추가
- `api-ventago/src/app/auth/dto/signIn-auth.dto.ts` — fingerprint 필드 추가

### 프론트엔드 (수정)
- `ventago-app/src/context/AuthContext.tsx` — sessionToken 관리, fingerprint 수집
- `ventago-app/src/context/types.ts` — 타입 추가
- `ventago-app/src/views/login/LoginView.tsx` — 등록 모달 추가
- `ventago-app/src/services/api.service.ts` — x-session-token 헤더 추가

### DB 마이그레이션
- `active_sessions`, `terminal_devices`, `branch_ip_registries` 테이블 생성
