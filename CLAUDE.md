# Ventago — POS/ERP 시스템 개발 가이드

## 프로젝트 개요

다점포 소매업 대상 POS/ERP 시스템. 재고·판매·재무·생산·외주 관리를 포함한 종합 업무 플랫폼.

- **운영 URL**: https://newapi.coolsistema.com/api (API), https://ventago.coolsistema.com (프론트)
- **배포**: Jenkins CI/CD → Docker (서버: srv803182)
- **저장소 구조**: npm workspaces 모노레포

```
ACE_online_1.0/
├── api-ventago/     # NestJS 백엔드 (포트 5002)
├── ventago-app/     # Next.js 프론트엔드 (포트 5001 docker / 3000 dev)
└── print-agent/     # 프린트 서비스
```

---

## 기술 스택

### 백엔드 (api-ventago)
- **Framework**: NestJS 11 + TypeScript
- **ORM**: Sequelize + sequelize-typescript (`underscored: true` 전역 설정 → DB 컬럼은 snake_case)
- **DB**: PostgreSQL 15 (Docker 컨테이너 `dbpostgres`, DB명 `ventago`)
- **인증**: JWT (Passport)
- **파일 저장**: MinIO (S3 호환, MinioService/MinioModule로 공유)
- **실시간**: Socket.io
- **로깅**: Winston (nest-winston)
- **스케줄링**: @nestjs/schedule

### 프론트엔드 (ventago-app)
- **Framework**: Next.js 13 (Pages Router) + React 18
- **UI**: Material-UI (MUI) 5
- **상태관리**: Redux Toolkit
- **폼**: React Hook Form + Yup
- **HTTP**: Axios (`src/services/api.service.ts`의 `apiConnector`)
- **인가**: CASL (Attribute-based ACL)
- **분석**: PostHog

---

## 아키텍처 핵심 규칙

### DB 컬럼 네이밍
Sequelize `underscored: true` 설정으로 모델의 camelCase 속성이 DB snake_case 컬럼으로 자동 매핑됨.
- 모델: `logoUrl` → DB: `logo_url`
- 모델: `aliasName` → DB: `alias_name`
- **SQL 직접 실행 시 반드시 snake_case 사용**

### 멀티테넌트 구조
거의 모든 테이블에 `store_id` FK가 있어 매장 단위로 데이터 격리됨.

### 파일 업로드 (MinIO)
- `MinioModule`을 해당 모듈의 `imports`에 추가
- `MinioService.uploadFile(file, fileName)` → `{ fileName }` 반환
- 프론트엔드 이미지 URL: `{API_HOST}/minio/{fileName}`
- 개발: `http://localhost:5002/api`, 운영: `https://newapi.coolsistema.com/api`

### API 서비스 (`api.service.ts`)
```typescript
apiConnector.get(path)           // GET
apiConnector.post(path, body)    // POST
apiConnector.put(path, body)     // PUT
apiConnector.sendFile(path, formData)  // POST multipart
apiConnector.putFile(path, formData)   // PUT multipart
```

### 인증 컨텍스트
`useAuth()` 훅으로 `user` 객체 접근. user에는 `storeId`, `storeName`, `aliasName`, `logoUrl`, 권한 정보 포함.
auth 응답은 `api-ventago/src/app/auth/auth.service.ts`의 `/me` 엔드포인트에서 구성.

### 세션 & 터미널 보안 (`api-ventago/src/app/session/`)
중복 로그인 절대 차단 + 디바이스/IP 기반 부정 사용 방지 시스템.

**테이블 3개:**
- `active_sessions` — 유저당 1개만 존재 (UNIQUE userId). 새 로그인 시 기존 세션 삭제 → 기존 세션은 즉시 401 `SESSION_EXPIRED`
- `terminal_devices` — 브라우저 fingerprint ↔ 터미널 바인딩. 새 디바이스 접속 시 터미널 등록 강제
- `branch_ip_registries` — public IP ↔ 지점(sucursal) 매핑. 새 IP 접속 시 지점 등록 강제

**로그인 플로우:**
1. 자격 증명 검증 → 기존 ActiveSession 삭제 (중복 로그인 차단)
2. IP 확인 → 미등록 IP면 `requireBranchRegistration: true` 반환
3. Fingerprint 확인 → 미등록이면 `requireTerminalRegistration: true` 반환
4. 정상이면 `sessionToken` (UUID v4) 발급

**프론트엔드 연동:**
- `api.service.ts`: 모든 요청에 `x-session-token` 헤더 자동 주입
- `AuthContext.tsx`: 디바이스 fingerprint 수집, sessionToken 저장
- `LoginView.tsx`: Branch/Terminal 등록 모달, 세션만료 알림 (`?reason=session_expired`)
- `utils/device-fingerprint.ts`: 브라우저 특성 SHA-256 해시

**SessionGuard 적용:** `guards/session.guard.ts` — JWT 인증 후 추가로 sessionToken 검증. 필요한 컨트롤러에 `@UseGuards(SessionGuard)` 적용.

---

## 주요 모듈 맵

### 백엔드 모듈 위치
```
api-ventago/src/app/
├── auth/           # JWT 인증, 권한 가드
├── store/          # 매장 관리 (로고 업로드 포함)
├── branch/         # 지점 관리
├── users/          # 사용자, 역할, 권한
├── products/       # 상품, 카테고리, 재고
├── sales/          # 판매, 결제수단, 할인
├── expenses/       # 비용 관리
├── box/            # 금전함 운영
├── caja-fuerte/    # 금고 관리
├── production/     # 생산 관리 (BOM, 작업지시)
├── subcon/         # 외주 (납품업체, 발주, 검수, 정산)
├── marketplace/    # 마켓플레이스
├── revendedor/     # 재판매자 포털
└── chat/           # AI 채팅 (Knowledge base)
```

### 프론트엔드 페이지 구조
```
ventago-app/src/pages/
├── nueva-venta/    # POS 판매 화면
├── ventas/         # 판매 내역
├── productos/      # 상품 관리
├── precios/        # 가격 관리
├── gastos/         # 비용 관리
├── caja/           # 금전함
├── caja-fuerte/    # 금고
├── control-de-caja/# 금전함 통제
├── sucursales/     # 지점 관리
├── usuarios/       # 사용자 관리
├── talleres/       # 외주 관리
├── dashboards/     # 대시보드
├── reportes/       # 보고서
├── configuracion/  # 설정
└── admin/          # 관리자 (매장, 앱, 구독 등)
```

---

## 레이아웃 구조

### 사이드바
- `ventago-app/src/layouts/UserLayout.tsx` — 메인 레이아웃 진입점
- `ventago-app/src/@core/layouts/VerticalLayout.tsx` — 레이아웃 프레임
- `ventago-app/src/@core/layouts/components/vertical/navigation/index.tsx` — 네비게이션 (React.memo 적용)
- `ventago-app/src/layouts/components/vertical/SidebarFooter.tsx` — 사이드바 하단 (로고/매장명 + 시계)

### 사이드바 리렌더링 방지 (적용됨)
- `Navigation` 컴포넌트: `React.memo` 적용, `darkTheme`을 `useMemo`로 메모이제이션
- `UserLayout`: `navMenuBranding`, `navMenuAfterContent`, `appBarContent` 등을 `useCallback`/`useMemo`로 추출
- `VerticalLayout`: `{...props}` 스프레드 제거하고 명시적 props 전달

---

## 개발 환경

### 로컬 실행
```bash
# 전체 (루트에서)
npm run dev

# 개별 실행
npm run dev:api   # api-ventago
npm run dev:app   # ventago-app
```

### Docker (운영서버)
```bash
# 백엔드
cd api-ventago && docker compose up -d

# 프론트엔드
cd ventago-app && docker compose build && docker compose up -d
```

### DB 접속 (Docker)
```bash
docker exec api_ventago node -e "
const { Client } = require('pg');
const c = new Client({host:'dbpostgres',user:'coolsistema',password:'Coo1s1stem4Adm1nPg',database:'ventago'});
c.connect().then(() => c.query('SQL HERE')).then(r => { console.log(r.rows); c.end(); });
"
```

---

## ESLint 규칙 (빌드 에러 방지)

이 프로젝트의 ESLint는 Warning도 에러로 처리되어 빌드를 막음.

| 규칙 | 대처 |
|------|------|
| `newline-before-return` | `return` 문 바로 위에 빈 줄 필요 |
| `lines-around-comment` | 주석(`//`) 바로 위에 빈 줄 필요 |
| `no-unused-vars` | import한 변수는 반드시 사용 |
| `react-hooks/exhaustive-deps` | Warning이므로 빌드는 통과하나 주의 필요 |

---

## 배포 파이프라인

- **Jenkins** 빌드: `front-coolsistema` job (프론트), `api-coolsistema` job (백엔드)
- 빌드 실패 시 로그 파일(`#NNN.txt`)을 분석해 에러 수정 후 push
- 프론트 빌드: `docker compose build` → `npm run build` (Next.js)
- 백엔드: NestJS SWC 빌드

---

## 최근 주요 개발 이력

| 날짜 | 작업 내용 |
|------|-----------|
| 2026-03-31 | 매장 로고 업로드 기능 (MinIO 저장, 사이드바 하단 표시) |
| 2026-03-31 | 사이드바 메뉴 클릭 시 전체 리렌더링 문제 해결 (React.memo/useMemo) |
| 2026-03-31 | DB 마이그레이션: `stores` 테이블에 `logo_url` 컬럼 추가 |
