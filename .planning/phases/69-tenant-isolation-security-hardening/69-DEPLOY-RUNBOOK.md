# Phase 69 — 배포 런북 (테넌트 격리 잔여 구멍 봉쇄)

**작성:** 2026-08-01
**DDL:** **0건** — 마이그레이션 없음. 변경되는 것은 코드와 `.env` 키뿐이다.
**성격:** 신규 기능 0, 전부 무회귀 보안 교정.

---

## 0. 배포 순서 — 반드시 app → api

| 순서 | 대상 | 이유 |
|---|---|---|
| 1 | `ventago-app` (front-coolsistema) | 69-02 가 `/realtime` 소켓 4종에 handshake JWT 를 배선했다. **api 가 먼저 뜨면** 구 프론트 소켓이 유예 10초 뒤 끊겨 팀 채팅·MP 승인 자동 판매·프린터 상태가 **조용히** 멈춘다 |
| 2 | `api-ventago` (api-new-coolsistema) | 소켓 인증 강제 + 나머지 4개 교정 |

**실제 적용 순서 확인 (2026-08-01):** 프론트 `ventagoapp` 컨테이너 21:04 UTC 생성(소켓 인증 커밋 `f8c3a2b` 포함) →
api 빌드 #592/#593 이후 22:46 / 23:23 재생성. 순서 지켜짐.

## 1. 배포 절차

```bash
# 1) 프론트 먼저
cd ventago-app && git push origin main          # → Jenkins front-coolsistema
# 빌드 성공 + 컨테이너 재생성 확인 후에만 다음 단계로

# 2) 백엔드
cd api-ventago && git push origin main          # → Jenkins api-new-coolsistema
```

빌드 확인:

```bash
ssh jhkim-server "grep -m1 'Finished:' /var/lib/jenkins/jobs/api-new-coolsistema/builds/<N>/log"
ssh jhkim-server "docker ps --format '{{.Names}} {{.Status}}' | grep -E 'api_ventago|ventagoapp'"
```

빌드 실패 시 `/var/lib/jenkins/jobs/<job>/builds/<N>/log` 를 읽고 수정 → 재push. "배포 완료" 는
**빌드 성공 + 컨테이너 재생성 확인까지**를 뜻한다.

## 2. env 키

`.env` 는 **컨테이너 생성 시에만 주입**된다 → 키를 바꾸면 `docker compose up -d --force-recreate` 필수.

| 키 | 기본값(코드) | 운영 현재값 | 의미 |
|---|---|---|---|
| `TENANT_GUARD_MODE` | `enforce` | (미설정 → enforce) | `store_id` 보유 모델 격리. `warn` = 로그만, `off` = 비활성 |
| `TENANT_DERIVED_MODE` | `enforce` (69-07 승격) | `enforce` (명시) | `store_id` 미보유 파생 모델의 부모 INNER JOIN. `observe` = 로그만 |

- 두 키 모두 **미설정이면 가장 안전한 값(enforce)** 이다. 설정 유실이 방어막을 끄지 않는다.
- 69-08(TenantContext fail-closed)에는 **env 스위치가 없다.** 컨텍스트 미확정 요청은 항상 403 이다 —
  격리가 꺼진 채 전 매장을 훑는 것보다 안전한 실패이기 때문. 되돌리려면 코드 롤백뿐이다.
- `.env.example` 에 두 키가 문서화돼 있다(69-07).

운영 `.env` 위치: `/var/lib/jenkins/workspace/api-new-coolsistema/.env`

## 3. 배포 직후 확인 (5분 내)

```bash
# (1) 격리 훅 설치 로그 — mode/derivedMode 가 모두 enforce 인가
ssh jhkim-server "docker exec api_ventago sh -c \"grep TenantGuard logs/combined-\$(date +%Y-%m-%d).log | tail -2\""
# 기대: 격리 훅 설치 완료 — mode=enforce 보호모델=114 (글로벌행 허용 8) 제외=30 | 파생스코프 derivedMode=enforce 대상=39

# (2) 신규 차단·에러
ssh jhkim-server "docker exec api_ventago sh -c \"grep -cE '\\[error\\]' logs/combined-\$(date +%Y-%m-%d).log; grep -c 'TENANT-CTX' logs/combined-\$(date +%Y-%m-%d).log\""
# 기대: 0 / 0  (TENANT-CTX 가 늘면 정상 사용자가 fail-closed 에 걸리고 있다는 뜻)

# (3) 격리 누수 경고
ssh jhkim-server "docker exec api_ventago sh -c \"grep '격리 누수' logs/combined-\$(date +%Y-%m-%d).log | tail -5\""
```

★ **enforce 회귀는 에러가 아니라 '빈 목록' 으로 나타난다.** 로그만 보고 안심하면 안 되고,
화면 순회(69-UAT.md)로 목록이 실제로 채워지는지 확인해야 한다.

## 4. 롤백 절차

### 4-1. 파생 스코프만 되돌리기 (재배포 불필요, 최우선 수단)

목록이 비거나 집계가 어긋나면 먼저 이것부터:

```bash
ssh jhkim-server "sed -i 's/^TENANT_DERIVED_MODE=.*/TENANT_DERIVED_MODE=observe/' /var/lib/jenkins/workspace/api-new-coolsistema/.env"
ssh jhkim-server "cd /var/lib/jenkins/workspace/api-new-coolsistema && docker compose up -d --force-recreate"
# 확인: 부팅 로그에 derivedMode=observe
```

`observe` 는 JOIN 을 주입하지 않고 사각지대 로그만 남긴다 — 격리는 `store_id` 보유 모델(114개)에 그대로 유지된다.

### 4-2. 격리 훅 전체 완화

```bash
TENANT_GUARD_MODE=warn   # 차단하지 않고 로그만 — 최후의 수단
```

### 4-3. 코드 롤백 (fail-closed / 소켓 인증)

env 스위치가 없는 두 가지(69-08 fail-closed, 69-01/02 소켓 인증)는 **코드 롤백**이 유일한 수단이다.
소켓 인증을 되돌릴 때는 **api 를 먼저** 되돌린다(순서가 배포와 반대다 — 구 api + 신 프론트는 정상 동작).

```bash
cd api-ventago && git revert <sha> && git push origin main
```

## 5. 사용자 영향 공지

| 대상 | 영향 | 안내 |
|---|---|---|
| 벤더 포털 사용자 | 69-05 배포 즉시 **기존 토큰 전부 무효**(`TOKEN_LEGACY_REAUTH`) | 재로그인 필요. 같은 전화번호가 여러 매장에 있으면 로그인 시 매장을 고르게 된다 |
| 매장 미배정(`store_id IS NULL`) 비-superadmin 계정 | 매장 데이터 요청 403 | 실측상 해당 계정 0명(69-NULL-STORE-SURVEY.md). 앞으로 생기면 `[TENANT-CTX] 매장 미배정 사용자` 로그로 즉시 식별 |
| print-agent / zebra-agent | API Key 는 그대로 통과(`branch_agents` 실재 키만) | 조치 불필요 |

## 6. 배포 후 회귀 관문

```bash
cd api-ventago
npm run test:tenant        # R1~R5 경계 20종 (실 DB 불요)
npm run test:concurrency   # Phase 64 동시성 8종 (실 DB 필요)
```
