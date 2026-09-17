---
phase: 89-qr-public-product-page
plan: 02
subsystem: infra
tags: [minio, s3, diagnostics, mojibake, multer, products]

# Dependency graph
requires: []
provides:
  - "판정: 상품 이미지 모지바케(114건 중 35건, ★실측 39건이 아니라 35건 — 아래 참고)는 ⓑ — MinIO 에 깨진 이름 그대로 저장돼 있다. DB 는 정확하다"
  - "읽기 전용 진단 스크립트 api-ventago/scripts/diagnose-image-names.js — raw/fix/brk 세 후보를 MinIO statObject 로 대조"
  - "후속 정정 작업의 정확한 범위: products.image_url 35행, 각 행 MinIO 객체 복사 선행 필요(DB 문자열만 바꾸는 정정은 안 통한다)"
affects: [89-06]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "MinIO 진단 스크립트는 port 를 Number() 로 바꾸면 안 된다 — minio@8.0.7 서명 계산이 깨진다(운영 컨테이너에서 문자열 vs 숫자로 직접 재현)"

key-files:
  created:
    - api-ventago/scripts/diagnose-image-names.js
    - .planning/phases/89-qr-public-product-page/89-DIAGNOSIS-imagenes.md
  modified: []

key-decisions:
  - "진단 스크립트를 이 사이드박스(Node v26)가 아니라 운영 컨테이너(api_ventago, Node v20 — 실제 운영과 동일 런타임)에서 실행 — dotenv/minio 의존성이 이미 있고, 같은 자격증명·환경으로 재현성을 보장하기 위함. docker cp + docker exec 만 사용, 컨테이너 재시작·설정 변경 없음(실행 후 임시 파일 삭제로 원복)"
  - "port 를 Number() 로 강제 변환하지 않고 ConfigService.get() 원본(문자열)을 그대로 넘기도록 스크립트 수정 — minio.service.ts 실제 코드 형태와 일치시킴(Rule 1 버그 수정)"

patterns-established:
  - "MinIO 클라이언트 진단/1회성 스크립트는 port 값의 타입(string vs number)에 민감하다 — 원본 env 문자열을 그대로 넘길 것"

requirements-completed: [REQ-06]

# Metrics
duration: 10min
completed: 2026-09-16
---

# Phase 89 Plan 02: 상품 이미지 모지바케 진단 Summary

**판정 ⓑ — 상품 이미지 image_url 비ASCII 35건 전부가 MinIO 에 "깨진 이름 그대로" 저장돼 있다(raw_hit 35/35, fix_hit·missing 0건). DB 는 정확하고, 이 plan 은 products.image_url 에 UPDATE 0건 · MinIO 에 쓰기 0건.**

## Performance

- **Duration:** 약 10분 (자동화 작업 시간 기준. 신호 진단 과정에서 발견한 진단 도구 자체 버그 조사 포함)
- **Started:** 2026-09-16T21:15 (-03:00)
- **Completed:** 2026-09-16T21:25 (-03:00)
- **Tasks:** 2/2 완료
- **Files modified:** 2 (신규 스크립트 1 + 진단 문서 1), 스크립트 1개 추가 수정(버그 픽스)

## Accomplishments
- 읽기 전용 진단 스크립트(`diagnose-image-names.js`) 작성 — DB `image_url` 을 raw/fix(latin1→utf8)/brk(utf8→latin1) 세 후보로 MinIO `statObject` 대조, 대조군(`ascii_ok`) 검증 포함
- 운영 실 데이터(114건) 로 실행 — **판정 ⓑ 확정**: 비ASCII 35건 전부 `raw_hit`(MinIO 에 그 깨진 이름 그대로 객체 실재), `fix_hit`/`missing` 0건
- 경로 1(`products.service.ts` `imageName`)·경로 2(Multer/Busboy 기본 charset, `defParamCharset`/`defCharset`/`busboy` 0건 확인)이 유력 원인으로 좁혀짐, 경로 3(sanitize)은 배제 근거와 함께 기록
- 후속 정정 작업의 **정확한 범위**를 문서화: 35행, 그리고 "DB 문자열만 고치는" 정정은 통하지 않는다는 것(fix 후보가 MinIO 에 없음)을 실측으로 확정 — 다음 세션이 잘못된 접근으로 시간을 낭비하지 않도록 함

## Task Commits

Each task was committed atomically (서브모듈 `api-ventago` 커밋 → 슈퍼프로젝트 gitlink 포인터 커밋 순):

1. **Task 1: DB image_url ↔ MinIO 오브젝트 키 대조 스크립트 (읽기 전용)** - `b11ceb8b` (api-ventago, feat) + `f6d2076` (root, chore: submodule pointer)
2. **Task 2: 운영 데이터로 실행해 판정을 하나로 좁힌다** - `e2396fa4` (api-ventago, fix — 진단 스크립트 자체의 port 타입 버그) + `a0c4b08` (root, docs: 판정 문서 + submodule pointer)

**Plan metadata:** (이 SUMMARY + STATE.md + ROADMAP.md — 이후 커밋)

## Files Created/Modified
- `api-ventago/scripts/diagnose-image-names.js` - 읽기 전용 MinIO/DB 대조 진단 스크립트(raw/fix/brk 세 후보, 대조군 검증, 동시 8개 제한)
- `.planning/phases/89-qr-public-product-page/89-DIAGNOSIS-imagenes.md` - 판정 ⓑ 기록 + 명령 출력 원문 + 경로별 확인/배제 근거 + 후속 조치 범위

## Decisions Made
- **진단 실행 위치를 운영 컨테이너(`api_ventago`)로 선택**: 이 세션의 Node 버전(v26)이 minio@8.0.7 과 함께 쓰였을 때 서명 계산에 문제를 일으켜(아래 이슈 참고), 운영과 동일한 Node v20 런타임에서 재현성을 확보하기 위함. `docker cp`(임시 파일 복사) + `docker exec`(읽기 전용 스크립트 실행)만 사용했고, 실행 후 `/app/scripts-tmp` 와 `/tmp` 임시 파일을 전부 삭제해 컨테이너 상태를 원복했다 — 컨테이너 재시작·설정 변경·서비스 영향 없음.
- **`port` 를 `Number()` 로 변환하지 않기로 결정**: minio.service.ts 의 실제 프로덕션 코드는 `ConfigService.get()` 원본(문자열)을 그대로 `Minio.Client` 생성자에 넘긴다. 진단 스크립트도 그 형태를 그대로 따르는 것으로 통일 — 별도의 "타입 안전성 개선"을 시도하지 않았다(범위 밖).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] 진단 스크립트가 이 세션 환경(Node v26)에서 MinIO 인증에 실패**
- **Found during:** Task 2 (운영 데이터로 스크립트 실행 중)
- **Issue:** `node api-ventago/scripts/diagnose-image-names.js` 를 이 클라우드 세션(Node v26.6.0)에서 직접 실행하면 `statObject`/`getObject` 모두 `SignatureDoesNotMatch` 로 실패했다. 자격증명은 운영 컨테이너의 실제 값과 SHA-256 해시로 대조해 **완전히 동일함**을 확인했으므로 자격증명 문제가 아니었다.
- **원인 규명:** 운영 컨테이너(Node v20.20.2, 실제 서비스가 정상 작동 중인 환경) 안에서 컴파일된 `MinioService` 클래스를 직접 호출하니 성공했다. 차이를 좁혀 가다 `Minio.Client({ port })` 에 **문자열 `'443'`은 성공, 숫자 `443`은 실패**한다는 것을 직접 재현으로 확인했다(minio@8.0.7 의 서명 계산이 port 의 타입에 따라 Host 문자열을 다르게 구성하는 것으로 보인다). 원래 스크립트는 `Number(process.env.MINIO_PORT)` 를 썼던 것이 원인이었다.
- **Fix:** `Number()` 변환을 제거하고 `process.env.MINIO_PORT` 원본 문자열을 그대로 `Minio.Client` 에 넘기도록 수정 — 실제 `minio.service.ts` 가 하는 방식과 동일하게 맞췄다.
- **Files modified:** `api-ventago/scripts/diagnose-image-names.js`
- **Verification:** 수정 후 운영 컨테이너 안에서 `statObject`/`getObject` 정상 동작 확인(`{"size":...,"etag":...}` 반환), 이어서 전체 114건 대조 정상 완료
- **Committed in:** `e2396fa4` (Task 2 관련 수정 커밋, Task 1 파일에 대한 후속 수정)
- **참고:** 이 버그는 **진단 스크립트 자체의 문제였고 운영 애플리케이션과는 무관하다** — 실제 운영 서비스(`/api/minio/:filename`)는 이 조사 내내 정상 작동 중이었음을 `docker logs` 로 확인했다(200 응답 다수 관측).

---

**Total deviations:** 1 auto-fixed (Rule 3 — 진단 스크립트 자체의 실행 환경 블로커, 운영 서비스에는 영향 없음)
**Impact on plan:** 진단 결과(판정 ⓑ, 35건, DB 쓰기 0건)에는 영향 없음 — 스크립트가 실행 가능하도록 만드는 수정이었을 뿐, 운영 데이터·MinIO 객체·코드 로직은 전혀 건드리지 않았다.

## Issues Encountered
- 위 Deviations 절 참고. 그 외 추가 문제 없음 — 운영 5434 SELECT 1회, MinIO statObject 114회(읽기 전용) 모두 예상대로 완료.

## User Setup Required
None - 외부 서비스 설정 불필요.

## Next Phase Readiness
- **후속 정정 plan 후보(신규, ROADMAP 등록 권장)**: `products.image_url` 비ASCII 35행 — 각 행에 대해 (1) MinIO 객체를 올바른 이름(`fix` 후보, latin1→utf8)으로 **복사**(원본은 남겨 둬도 무방), (2) 복사 성공을 `statObject` 로 개별 확인한 뒤에만 DB `UPDATE`. **DB 문자열만 고치는 정정은 통하지 않는다** — 이번 실측에서 `fix` 후보가 MinIO 에 존재하지 않음을 확인했기 때문이다.
- **재발 방지(코드)**: 상품 이미지 업로드 경로(`products.service.ts` `imageName`/`imageFile.originalname` 처리, 또는 Multer/Busboy 옵션에 `defParamCharset` 지정)에 대한 별도 코드 수정이 필요 — 이 plan 의 범위 밖.
- 89-06(사진 없어도 안 깨지는 공개 페이지 UI 방어)은 이 진단과 독립적으로 진행 가능 — 블로커 없음.

---
*Phase: 89-qr-public-product-page*
*Completed: 2026-09-16*

## Self-Check: PASSED

- FOUND: api-ventago/scripts/diagnose-image-names.js
- FOUND: .planning/phases/89-qr-public-product-page/89-DIAGNOSIS-imagenes.md
- FOUND: .planning/phases/89-qr-public-product-page/89-02-SUMMARY.md
- FOUND commit b11ceb8b (api-ventago submodule)
- FOUND commit e2396fa4 (api-ventago submodule)
- FOUND commit f6d2076 (root)
- FOUND commit a0c4b08 (root)
