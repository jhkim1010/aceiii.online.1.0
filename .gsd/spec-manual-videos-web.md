# SPEC: 웹 영상 매뉴얼 (로그인 사용자 전용, vendedor/revendedor 제외)
생성일: 2026-07-18

## 목표
ventago-app 웹 매뉴얼 화면에 "영상 매뉴얼(여러 편)"을 추가한다.
영상은 MinIO 비공개 버킷에 저장하고, 로그인한 시스템 사용자(단 vendedor/revendedor 역할 제외)에게만
짧은 수명(10분) presigned URL 로 재생을 허용한다. 업로드는 수동(사용자 직접).

## 배경 및 컨텍스트
- 기존 manuales(PDF)는 Next.js `public/manuales/` 정적 파일 + `/manuales/manifest.json` 으로
  서빙됨 → 무인증 접근 가능. 영상엔 부적합(대용량 + 접근제한 필요)이라 별도 경로로 구현.
- 재사용 자산: api-ventago `src/common/minio/minio.service.ts`(minio v8), `@Auth(...ValidRoles)` 가드,
  ventago-app `src/views/manuales/ManualesView.tsx`(진입점 이미 존재), `apiConnector`(JWT 자동 주입).
- 역할: ValidRoles = admin, superadmin, vendedor, gerente, envioManager. revendedor 는 별도 auth realm.
  → 허용 = @Auth(admin, superadmin, gerente, envioManager) (= vendedor 제외). revendedor 는 realm 분리라 자동 제외.
  ※ LEGACY_ROLE_ALIAS 로 cashier→vendedor 매핑되므로 cashier 도 제외됨(요구사항과 일치, 리뷰에서 재확인).

## 기술 스택
- 백엔드: NestJS (api-ventago), minio v8. **PostgreSQL 미사용 → pool 영향 0.**
- 프론트: Next.js + MUI (ventago-app).
- ESLint: 두 repo 각각 존재.

## 태스크 목록
- [ ] TASK-1: MinioService 에 presignedGetObject(objectName, expirySeconds=600) 추가 (try/catch) — 파일: api-ventago/src/common/minio/minio.service.ts
- [ ] TASK-2: 영상 매뉴얼 컨트롤러/모듈 — GET /manuales/videos(목록, manifest=MinIO manuales/videos/index.json), GET /manuales/videos/:id/url(presigned). @Auth(admin,superadmin,gerente,envioManager) — 파일: api-ventago/src/app/manuales-video/*
- [ ] TASK-3: ManualesView 에 "영상" 섹션 + <video> 플레이어 + 사용자명 워터마크 오버레이 (apiConnector, 403 시 섹션 숨김) — 파일: ventago-app/src/views/manuales/ManualesView.tsx
- [ ] TASK-4: ESLint 검증 (변경 파일, --fix)
- [ ] TASK-5: 빌드/타입체크 (api tsc, front next lint/build)
- [ ] TASK-6: 수동 업로드 가이드 + index.json 템플릿 제공 (MinIO manuales/videos/)

## 완료 기준
- ESLint 오류 0개
- api 타입체크/프론트 빌드 통과
- 비로그인 및 vendedor → 403, 그 외 로그인 사용자 → presigned URL 재생 정상(로컬 검증)
- PostgreSQL pool 신규 사용 0 (presigned 방식만)

## 금지사항 / 주의사항
- PostgreSQL 신규 connection/pool 사용 금지 (presigned URL 만).
- 기존 정적 manuales(PDF) 동작 변경 금지.
- api-ventago 다른 모듈 건드리지 않기.
- 운영 배포(api_ventago 재빌드 + front 재배포)는 별도 승인 게이트.
  ※ 참고: 현재 운영 api_ventago 는 reseller 등 최신 커밋 미배포 상태 → 이번 배포 시 함께 반영됨(사용자 인지 필요).
