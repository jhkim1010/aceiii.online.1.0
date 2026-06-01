# SPEC: Phase 37 Mobile Sales Shell

생성일: 2026-05-31
GSD 워크플로우 spec 단계 산출물.

**메인 SPEC 위치:** [.planning/phases/37-mobile-sales-shell/37-SPEC.md](../.planning/phases/37-mobile-sales-shell/37-SPEC.md)

이 파일은 GSD 의 `.gsd/spec-*.md` 컨벤션 준수를 위한 참조용. 실제 SPEC 본문은 위 경로의 phase 폴더에 있으며 ROADMAP / CONTEXT.md 와 함께 관리됩니다.

## 빠른 요약

- **목표:** vendedor/revendedor 듀얼 모드 Flutter 모바일 앱. role 기반 scope 자동 결정.
- **베타 매장:** coolsistema (store_id=6, vendedor 2명)
- **MVP 범위:** Wave 1-4 (Backend Auth/Scope + Catalog/Sales + Flutter Shell + Vendedor 화면)
- **Plan 분할:** 5 plans (37-01..37-05), 35 tasks total
- **선결조건:** Phase 33 ✅, Phase 17 ✅, Phase 36 (Phase 35 운영 잠금 해제) ⏳

## GSD 검증 포인트

- ✅ 로그 파일 확인 완료 (2026-05-31 error 0건)
- ✅ Pool 설정 확인 (min=10/max=80, monitoring 80%/waiting 경고 자동)
- ✅ PostgreSQL pool 안전 규칙 SPEC 내 명시 (전역 pool 재사용, finally release, 새 Pool 생성 금지)
- ✅ ESLint 검증 단계 각 Wave 의 마지막 task 로 포함
- ✅ 한국어 주석 / 영어 변수명 컨벤션 적용
- ✅ 에러 핸들링 try/catch + 명확한 401/403 코드 정의
