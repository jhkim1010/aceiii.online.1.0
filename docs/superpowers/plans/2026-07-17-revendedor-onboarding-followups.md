# Revendedor 온보딩 — Deferred Follow-ups

원 계획: `docs/superpowers/plans/2026-07-17-revendedor-onboarding-read-mvp.md`
브랜치: `feat/revendedor-onboarding` (3 repo). 최종 리뷰 후 의도적으로 미룬 항목.

## Must-decide (결정됨: 후속)

### F-1 재제출-후-거부 경로 (spec §7) — 미구현
- 현재: `register()` 가 기존 `document` 존재 시 무조건 409 → **rejected reseller 재진입 불가**.
- spec §7 원안: 거부 후 재제출 → 새 `reseller_documents` 행(이력 보존) + `status='pending_review'` 복귀.
- 구현 시: 백엔드 `register()` 를 기존 행이 `status='rejected'` 이면 update-in-place(새 서류행 insert, status 리셋, 링크 재생성) + 앱에서 거부 상태 감지해 재가입 화면 재오픈 UX.
- 사유: 읽기 MVP 스코프 밖 엣지 경로. 사용자 결정으로 후속 슬라이스.

## Important (fast-follow)

### F-2 reseller 401 mid-session 미바운스 (mobile)
- `resellerDioProvider` 에 401 응답 인터셉터 없음. `resellerSessionProvider.build()` 는 부팅 시 토큰만 검사.
- 세션 중 토큰 폐기/만료 시 로그인 복귀 대신 에러카드 표시(앱 재시작 시 self-heal). read-MVP 수용, 인터셉터 추가로 개선.

## Minor (triaged — 병합 무블록)

- **M-1** register race-dup: 동시 동일 document 제출 시 DB UNIQUE 로 막히나 raw `UniqueConstraintError`(500, 클린 409 아님) + MinIO 고아 객체 3개. 저확률. → catch 로 409 변환 + 고아 스윕.
- **M-2** `RESELLER_DOCS_REQUIRED` 어느 서류 누락인지 미표기. UX 폴리시.
- **M-3** `me()` 중복 `findByPk` (JWT strategy 가 이미 로드). perf, 저트래픽 무해.
- **M-4** `/reseller/auth/me` 에서 `provinceSource` 제거(소비자 0). 무해.
- **M-5** admin approve/reject body 가 class-validator DTO 아님(빈 storeIds no-op, reject.reason maxLength 300 미가드 → 초과 시 500). superadmin 전용, 저위험. DTO 로 교체.
- **M-6** ventago-app pending 목록 `rows.slice(0,50)` 무표시 truncation + 백엔드 `pending()` 무 LIMIT. 저볼륨 무해, 표시/LIMIT 추가.
- **M-7** resubmission 시 `pending()` 이 latest-per-docType 미필터 → 웹 drawer `key={docType}` 중복키 경고(F-1 구현 시 동반 해결).
- **M-8** mobile catalog `copyWith(loadMoreError:null)` 로 에러 클리어 불가(현재 미사용, latent). `hotCount` 파싱했으나 미표시. reseller 로그인 성공-nav 테스트 없음.

## 문서 정합
- spec `2026-07-17-...-design.md` §3.2 는 admin 라우트를 `/admin/resellers...` 로 표기했으나 실제 구현·웹 소비 모두 `/reseller/admin/*`. 코드 정확, spec 텍스트만 stale.
