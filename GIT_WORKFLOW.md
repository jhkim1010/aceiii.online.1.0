# Git 워크플로우 가이드

이 모노레포는 **통합 푸시**와 **개별 푸시**를 모두 지원합니다.

## 저장소 구조

- **루트 저장소**: `https://github.com/jhkim1010/aceiii.online.1.0.git`
  - 모노레포 통합 설정, 루트 파일들
  
- **백엔드 저장소**: `https://github.com/WillAular/api-ventago.git`
  - `api-ventago/` 폴더의 백엔드 코드
  
- **프론트엔드 저장소**: `https://github.com/WillAular/ventago-app.git`
  - `ventago-app/` 폴더의 프론트엔드 코드

## 사용 방법

### 방법 1: npm 스크립트 사용 (권장)

```bash
# 모든 저장소 상태 확인
npm run git:status

# 모든 저장소 한꺼번에 푸시
npm run git:push:all

# 개별 푸시
npm run git:push:root    # 루트만
npm run git:push:api     # 백엔드만
npm run git:push:app     # 프론트엔드만

# 커밋만 하고 푸시는 안 함
npm run git:commit:all
npm run git:commit:root
npm run git:commit:api
npm run git:commit:app
```

### 방법 2: 셸 스크립트 사용

```bash
# 모든 저장소 상태 확인
./scripts/git-status.sh

# 모든 저장소 한꺼번에 푸시
./scripts/git-push.sh all

# 개별 푸시
./scripts/git-push.sh root    # 루트만
./scripts/git-push.sh api     # 백엔드만
./scripts/git-push.sh app     # 프론트엔드만
```

### 방법 3: 직접 Git 명령어 사용

#### 루트 저장소
```bash
git add .
git commit -m "커밋 메시지"
git push origin main
```

#### 백엔드 저장소
```bash
cd api-ventago
git add .
git commit -m "커밋 메시지"
git push origin main  # 또는 master
cd ..
```

#### 프론트엔드 저장소
```bash
cd ventago-app
git add .
git commit -m "커밋 메시지"
git push origin main  # 또는 master
cd ..
```

## 워크플로우 예시

### 시나리오 1: 백엔드만 수정했을 때
```bash
# 백엔드만 푸시
npm run git:push:api

# 또는
./scripts/git-push.sh api
```

### 시나리오 2: 프론트엔드만 수정했을 때
```bash
# 프론트엔드만 푸시
npm run git:push:app

# 또는
./scripts/git-push.sh app
```

### 시나리오 3: 모노레포 설정만 변경했을 때
```bash
# 루트만 푸시
npm run git:push:root

# 또는
./scripts/git-push.sh root
```

### 시나리오 4: 모든 곳을 수정했을 때
```bash
# 모든 저장소 푸시
npm run git:push:all

# 또는
./scripts/git-push.sh all
```

## 주의사항

1. **각 워크스페이스는 독립적인 저장소**
   - 각 워크스페이스 폴더에서 직접 git 작업 가능
   - 루트에서 통합 관리도 가능

2. **커밋 메시지**
   - 각 저장소는 독립적으로 커밋 메시지를 작성할 수 있습니다
   - 스크립트는 기본 메시지를 사용하지만, 직접 커밋할 때는 의미있는 메시지를 작성하세요

3. **브랜치 관리**
   - 각 저장소는 독립적인 브랜치를 가질 수 있습니다
   - 기본 브랜치는 `main` 또는 `master`입니다

4. **충돌 방지**
   - 한 저장소에서 작업 중일 때는 다른 저장소에서 같은 파일을 수정하지 마세요
   - 각 워크스페이스는 독립적으로 관리되므로 일반적으로 충돌이 발생하지 않습니다

## 팁

- **상태 확인**: 작업 전에 `npm run git:status`로 모든 저장소 상태 확인
- **작은 커밋**: 변경사항이 많을 때는 여러 번 나눠서 커밋하는 것이 좋습니다
- **의미있는 메시지**: 커밋 메시지는 무엇을 변경했는지 명확하게 작성하세요

