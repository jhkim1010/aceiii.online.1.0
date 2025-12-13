# 모노레포 구조 설명

## 현재 구조: 모노레포 (npm workspaces)

이 프로젝트는 **npm workspaces**를 사용하는 모노레포 구조입니다.

### 모노레포의 장점

1. **의존성 관리 통합**
   - 루트에서 `npm install` 한 번으로 모든 워크스페이스의 의존성 설치
   - 중복된 의존성은 루트 `node_modules`에 호이스팅되어 디스크 공간 절약

2. **통합 명령어 실행**
   - `npm run dev --workspace=api-ventago` - 특정 워크스페이스만 실행
   - `npm run dev` - 모든 워크스페이스 동시 실행

3. **공유 패키지 가능**
   - 향후 공유 라이브러리/유틸리티를 `packages/` 폴더에 추가 가능
   - 예: `packages/shared-types`, `packages/common-utils`

### 워크스페이스 구조

```
ACE_online_1.0/
├── package.json          # 루트 설정 (workspaces 정의)
├── node_modules/         # 공유 의존성 (호이스팅됨)
├── api-ventago/         # 워크스페이스 1
│   ├── package.json
│   └── node_modules/    # 워크스페이스 전용 의존성
└── ventago-app/         # 워크스페이스 2
    ├── package.json
    └── node_modules/    # 워크스페이스 전용 의존성
```

### 사용 방법

#### 1. 의존성 설치
```bash
# 모든 워크스페이스 의존성 설치
npm install

# 특정 워크스페이스에 의존성 추가
npm install <package> --workspace=api-ventago
npm install <package> --workspace=ventago-app

# 개발 의존성 추가
npm install -D <package> --workspace=api-ventago
```

#### 2. 스크립트 실행
```bash
# 모든 워크스페이스 동시 실행
npm run dev

# 특정 워크스페이스만 실행
npm run dev:api
npm run dev:app

# 또는 직접 워크스페이스 지정
npm run start:dev --workspace=api-ventago
npm run dev --workspace=ventago-app
```

#### 3. 빌드
```bash
# 전체 빌드
npm run build

# 개별 빌드
npm run build:api
npm run build:app
```

### 모노레포 vs 멀티레포 비교

| 특징 | 모노레포 (현재) | 멀티레포 (이전) |
|------|----------------|----------------|
| 의존성 관리 | 통합 관리 | 각각 독립적 |
| 설치 명령어 | `npm install` (한 번) | 각 프로젝트마다 실행 |
| 공유 코드 | 쉬움 (packages 폴더) | 어려움 (별도 패키지) |
| 버전 관리 | 단일 저장소 | 여러 저장소 |
| CI/CD | 단일 파이프라인 | 각각 별도 |

### 향후 확장 가능성

공유 패키지를 추가하려면:

1. `packages/` 폴더 생성
2. `package.json`의 `workspaces`에 추가:
   ```json
   "workspaces": [
     "api-ventago",
     "ventago-app",
     "packages/*"
   ]
   ```
3. 예시 구조:
   ```
   packages/
   ├── shared-types/     # TypeScript 타입 정의
   ├── common-utils/     # 공통 유틸리티 함수
   └── api-client/        # API 클라이언트 SDK
   ```

### 주의사항

- 각 워크스페이스는 독립적으로 실행 가능
- 루트 `node_modules`에 호이스팅된 패키지는 모든 워크스페이스에서 사용 가능
- 워크스페이스별 `node_modules`는 해당 워크스페이스 전용

