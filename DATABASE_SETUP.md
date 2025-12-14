# 데이터베이스 설정 가이드

## 로컬 PostgreSQL 사용 (권장)

이 프로젝트는 기본적으로 **로컬 PostgreSQL**을 사용합니다.

### 1단계: PostgreSQL 설치

#### macOS (Homebrew)
```bash
brew install postgresql@15
```

#### Linux (Ubuntu/Debian)
```bash
sudo apt-get update
sudo apt-get install postgresql postgresql-contrib
```

#### Windows
[PostgreSQL 공식 사이트](https://www.postgresql.org/download/windows/)에서 설치

### 2단계: PostgreSQL 시작

#### macOS (Homebrew)
```bash
brew services start postgresql@15
```

#### Linux
```bash
sudo systemctl start postgresql
sudo systemctl enable postgresql  # 부팅 시 자동 시작
```

### 3단계: 데이터베이스 생성

```bash
# PostgreSQL에 접속
psql postgres

# 데이터베이스 생성
CREATE DATABASE ventago;

# 사용자 확인 (필요시)
CREATE USER postgres WITH PASSWORD 'postgres';
GRANT ALL PRIVILEGES ON DATABASE ventago TO postgres;

# 종료
\q
```

또는 간단하게:
```bash
createdb ventago
```

### 4단계: 환경 변수 설정

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
JWT_SECRET_KEY=your_secret_key_here
PORT=5002
```

### 5단계: 마이그레이션 실행

```bash
npm run db:migrate
```

또는:
```bash
cd api-ventago
npm run migrate
```

## 빠른 설정 (한 번에)

```bash
# 1. 데이터베이스 생성
npm run db:create

# 2. 마이그레이션 실행
npm run db:migrate

# 또는 한 번에
npm run db:setup
```

## 연결 정보

- **Host**: localhost
- **Port**: 5432 (PostgreSQL 기본 포트)
- **Database**: ventago
- **User**: postgres
- **Password**: postgres (또는 설정한 비밀번호)

## 문제 해결

### PostgreSQL이 실행되지 않는 경우

#### macOS
```bash
# 상태 확인
brew services list

# 시작
brew services start postgresql@15

# 재시작
brew services restart postgresql@15
```

#### Linux
```bash
# 상태 확인
sudo systemctl status postgresql

# 시작
sudo systemctl start postgresql
```

### 데이터베이스 연결 테스트

```bash
# PostgreSQL에 접속
psql -U postgres -d ventago

# 또는
psql postgres
\c ventago
```

### 포트가 이미 사용 중인 경우

```bash
# 포트 5432 사용 중인 프로세스 확인
lsof -i :5432

# PostgreSQL이 다른 포트에서 실행 중인지 확인
psql -U postgres -p 5433  # 예시: 포트 5433
```

### 마이그레이션 오류

```bash
# 마이그레이션 상태 확인
cd api-ventago
npx sequelize-cli db:migrate:status

# 마이그레이션 롤백 (필요시)
npx sequelize-cli db:migrate:undo
```

## 개발 워크플로우

1. **PostgreSQL 시작** (한 번만):
   ```bash
   brew services start postgresql@15  # macOS
   ```

2. **데이터베이스 설정** (처음 한 번만):
   ```bash
   npm run db:setup
   ```

3. **개발 서버 시작**:
   ```bash
   npm run dev
   ```

## Docker 사용 (선택사항)

Docker를 사용하고 싶은 경우:

```bash
# Docker로 PostgreSQL 실행
cd api-ventago/docker
docker-compose -f docker-compose-postgresql.yml up -d

# .env 파일에서 포트를 54321로 변경
DATABASE_PORT=54321
```

## 주의사항

- 로컬 PostgreSQL을 사용하는 경우, `.env` 파일의 `DATABASE_PORT`는 `5432`여야 합니다
- 프로덕션 환경에서는 다른 설정을 사용하세요
- 비밀번호는 환경 변수로 관리하고 Git에 커밋하지 마세요
