# 판매원 앱 저장소 분리 & 직원 협업 가이드

작성: 2026-07-14 · 대상: mobile-sales-app (Flutter 판매원 앱)

## 왜 분리하나

GitHub 권한은 저장소 단위다. 직원에게 판매원 앱만 맡기려면 모노레포(`aceiii.online.1.0`) 접근을 주면 안 되고,
`mobile-sales-app`을 별도 저장소로 분리한 뒤 그 저장소에만 협업자로 초대한다.
api-ventago / ventago-app 이 이미 쓰는 "중첩 repo + gitlink" 패턴과 동일하다.

## 사전 스캔 결과 (2026-07-14, 분리 안전 확인)

- 소스(lib/, test/): 하드코딩 API 키·비밀번호 **없음** (런타임 secure storage 토큰 읽기뿐)
- URL: `https://newapi.coolsistema.com/api`, `http://localhost` (공개 주소만)
- 키파일(.env/.pem/.jks/keystore/service-account): **없음**
- git 이력(12커밋): 삭제된 시크릿 파일 이력 **없음**
→ 이력 포함 분리해도 안전.

## 실행 순서 (사장님, Mac에서 1회)

```bash
cd ~/Trabajos_Programming/ACE_online_1.0
./scripts/split-mobile-sales-app.sh
```

스크립트가 하는 일: ① `gh`로 private repo 생성 → ② `git subtree split`(이력 보존) →
③ 새 repo push → ④ 모노레포 폴더를 중첩 repo(gitlink)로 전환 + 커밋.
원본은 `mobile-sales-app.bak`으로 보존되며, 확인 후 삭제한다.

## 직원 초대

1. https://github.com/jhkim1010/mobile-sales-app/settings/access
2. "Add people" → 직원 GitHub 계정 → Role: **Write**
   (Write면 push 가능. PR 리뷰 강제하려면 main 브랜치 보호 규칙 추가 권장:
   Settings > Branches > Add rule > Require a pull request before merging)
3. 직원에게 주는 링크: **https://github.com/jhkim1010/mobile-sales-app**

## 직원에게 주는 것 / 안 주는 것

| 준다 | 안 준다 |
|---|---|
| 앱 저장소 링크 (위) | 모노레포·api-ventago·ventago-app 접근 |
| 테스트 계정 (예: dummy@cool / PIN 1234 / store 6) | 운영 DB·SSH·Jenkins 접근 |
| API 문서 필요분 (엔드포인트 스펙 발췌) | 백엔드 소스 |

앱은 운영 API(https://newapi.coolsistema.com/api)에 HTTP로만 붙으므로 백엔드 소스 없이 개발 가능하다.

## 직원 작업 흐름

```bash
git clone https://github.com/jhkim1010/mobile-sales-app.git
cd mobile-sales-app
flutter pub get
flutter run            # 테스트 계정으로 로그인
# 작업 → 브랜치 → PR (main 보호 시) 또는 main push
```

## 사장님 동기화 흐름 (직원 작업 반영)

```bash
cd ~/Trabajos_Programming/ACE_online_1.0
./scripts/sync-mobile-sales-app.sh   # 직원 main → 모노레포 gitlink 갱신
git push origin main                 # 루트 반영
```

릴리스 빌드(GitHub Actions `build-mobile-sales-app.yml`)는 지금처럼 루트 저장소에서 태그로 트리거 —
빌드 전에 sync 스크립트만 먼저 실행하면 된다.

## 주의

- 중첩 repo 전환 후 모노레포에서 앱 파일을 직접 고치면 직원 repo와 갈라진다.
  앱 수정은 가급적 앱 repo 쪽(직원 흐름)으로 일원화하고, 사장님이 직접 고칠 땐
  `mobile-sales-app/` 안에서 커밋 후 origin push (그 폴더가 곧 앱 repo다).
- `mobile-sales-app.bak` 은 diff 확인 후 삭제.
- 향후 talleres-vendor-app / ventago-admin-app 도 같은 스크립트 패턴으로 분리 가능.
