# VentaGO - 모노레포 풀스택 프로젝트

VentaGO는 상점(매장)의 판매, 재고, 상품 관리를 위한 POS/ERP 시스템입니다.

## 📦 모노레포 구조

이 프로젝트는 **npm workspaces**를 사용하는 모노레포입니다.

```
ACE_online_1.0/
├── package.json          # 루트 설정 (workspaces 정의)
├── node_modules/         # 공유 의존성 (호이스팅됨)
├── api-ventago/         # 워크스페이스 1: 백엔드 API (NestJS)
└── ventago-app/         # 워크스페이스 2: 프론트엔드 앱 (Next.js)
```

### 모노레포의 장점

- ✅ **통합 의존성 관리**: 한 번의 `npm install`로 모든 워크스페이스 설치
- ✅ **중복 제거**: 공통 패키지는 루트 `node_modules`에 호이스팅
- ✅ **공유 코드 용이**: 향후 `packages/` 폴더에 공유 라이브러리 추가 가능
- ✅ **버전 일관성**: 모든 워크스페이스에서 동일한 패키지 버전 사용

## 🚀 빠른 시작

### 1. 모든 의존성 설치 (모노레포 방식)

```bash
# 루트에서 한 번만 실행하면 모든 워크스페이스 설치됨
npm install
```

> **참고**: 모노레포에서는 각 워크스페이스 폴더로 이동해서 `npm install`을 실행할 필요가 없습니다.

### 2. 데이터베이스 설정

#### 로컬 PostgreSQL 사용 (권장)

1. **PostgreSQL 설치** (Homebrew):
```bash
brew install postgresql@15
```

2. **PostgreSQL 시작**:
```bash
brew services start postgresql@15
```

3. **데이터베이스 생성**:
```bash
createdb ventago
```

4. **환경 변수 설정**:
`api-ventago/.env` 파일 생성:
```bash
cp api-ventago/.env.example api-ventago/.env
```

`.env` 파일 내용:
```env
DATABASE_HOST=localhost
DATABASE_PORT=5432
DATABASE_NAME=ventago
DATABASE_USER=postgres
DATABASE_PASSWORD=postgres
JWT_SECRET_KEY=your_secret_key
PORT=5002
```

5. **마이그레이션 실행**:
```bash
npm run db:migrate
```

> **참고**: Docker를 사용하려면 `DATABASE_SETUP.md`를 참조하세요.

### 3. 개발 서버 실행

#### 동시 실행 (권장)
```bash
# 루트에서 실행 - 백엔드와 프론트엔드를 동시에 실행
npm run dev
```

#### 개별 실행
```bash
# 백엔드만 실행
npm run dev:api
# 또는 워크스페이스 직접 지정
npm run start:dev --workspace=api-ventago

# 프론트엔드만 실행
npm run dev:app
# 또는 워크스페이스 직접 지정
npm run dev --workspace=ventago-app
```

## 개발 워크플로우

### 모노레포 명령어 사용법

```bash
# 모든 워크스페이스 동시 실행
npm run dev

# 특정 워크스페이스만 실행
npm run dev:api      # 백엔드만
npm run dev:app      # 프론트엔드만

# 워크스페이스에 패키지 추가
npm install axios --workspace=api-ventago
npm install lodash --workspace=ventago-app

# 모든 워크스페이스에 동일한 패키지 추가
npm install typescript --workspaces

# 워크스페이스 목록 확인
npm ls --workspaces --depth=0
```

### VS Code 통합

VS Code에서 `Cmd+Shift+P` → "Tasks: Run Task" → "dev: 전체 실행" 선택

## 빌드

### 프로덕션 빌드
```bash
npm run build
```

### 개별 빌드
```bash
npm run build:api  # 백엔드만
npm run build:app  # 프론트엔드만
```

## 포트 정보

- **백엔드 API**: http://localhost:5002/api
- **프론트엔드**: http://localhost:3000

## 유용한 명령어

```bash
# 코드 포맷팅
npm run format

# 린트 검사
npm run lint

# 백엔드 마이그레이션
cd api-ventago
npm run migrate
```

## Git 워크플로우

이 모노레포는 **통합 푸시**와 **개별 푸시**를 모두 지원합니다.

### 모든 저장소 한꺼번에 푸시
```bash
npm run git:push:all
# 또는
./scripts/git-push.sh all
```

### 개별 저장소 푸시
```bash
npm run git:push:root    # 루트만
npm run git:push:api     # 백엔드만
npm run git:push:app     # 프론트엔드만

# 또는
./scripts/git-push.sh root
./scripts/git-push.sh api
./scripts/git-push.sh app
```

### 저장소 상태 확인
```bash
npm run git:status
# 또는
./scripts/git-status.sh
```

자세한 내용은 [GIT_WORKFLOW.md](./GIT_WORKFLOW.md)를 참조하세요.

## 기술 스택

### Backend (api-ventago)
- NestJS 11.x
- TypeScript
- PostgreSQL + Sequelize
- JWT 인증

### Frontend (ventago-app)
- Next.js 13.x
- React 18
- Material-UI
- Redux Toolkit
- TypeScript

## 문제 해결

### 포트 충돌
- 백엔드 포트 변경: `api-ventago/.env`에서 `PORT` 수정
- 프론트엔드 포트 변경: `ventago-app/package.json`의 `dev` 스크립트에 `-p 3001` 추가

### 데이터베이스 연결 오류
- PostgreSQL이 실행 중인지 확인:
  ```bash
  # macOS
  brew services list | grep postgresql
  
  # Linux
  sudo systemctl status postgresql
  ```
- `.env` 파일이 `api-ventago/` 폴더에 있는지 확인
- 데이터베이스가 생성되었는지 확인:
  ```bash
  psql -U postgres -l | grep ventago
  ```
- 포트가 5432인지 확인 (로컬 PostgreSQL 기본 포트)
- 자세한 내용은 [DATABASE_SETUP.md](./DATABASE_SETUP.md) 참조

### 의존성 오류
```bash
# 모노레포 전체 정리 후 재설치
npm run clean:install

# 또는 수동으로
npm run clean
npm install
```

### 모노레포 관련 명령어
```bash
# 워크스페이스 목록 확인
npm ls --workspaces --depth=0

# 특정 워크스페이스의 스크립트 실행
npm run <script> --workspace=<workspace-name>

# 모든 워크스페이스에서 동일한 스크립트 실행
npm run <script> --workspaces
```

# aceiii.online.1.0
