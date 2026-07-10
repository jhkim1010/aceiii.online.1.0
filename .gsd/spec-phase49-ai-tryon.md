# SPEC: Phase 49 — AI Virtual Try-On (포인터)

생성일: 2026-06-29 · 갱신: 2026-07-10

> 정식 스펙은 phase 폴더에 있습니다(프로젝트 phase 컨벤션):
> - `.planning/phases/49-ai-virtual-tryon/49-CONTEXT.md`
> - `.planning/phases/49-ai-virtual-tryon/49-SPEC.md`
> - B트랙(vendedor) 실행용 GSD SPEC: `.gsd/spec-phase49-vendedor-ai.md`
>
> **번호 주의**: Phase 46(Shopify)/47(Empretienda)/48(WC 통일)은 멀티플랫폼 싱크 마스터플랜
> (`.planning/docs/multiplatform-sync-master-plan.md`)에 예약됨 → AI 가상피팅은 **49**.

## 요약

- **목표**: 사용자 사진으로 카탈로그 옷 가상착용 + 상황별 추천 + 구매 연결.
- **코드**: `api-ventago/src/app/tryon/` (`TryOnProvider` 추상화 + `StubTryOnProvider`).
- **상태**:
  - Wave 49-01 (PoC: 추상화+스텁+독립폼+from-product+프라이버시) — ✅ 완료
  - A트랙: 49-02 FASHN 어댑터 / 49-03 옷이미지 품질 / 49-05 프라이버시 / 49-06 tienda-app 통합 — ⬜ (49-04 는 49-08/09 로 흡수)
  - B트랙(2026-07-10, 판매원 앱 판매촉진): 49-07 vendedor 피팅 / 49-08 카탈로그 AI 태깅 / 49-09 스타일리스트 / 49-10 Flutter / 49-11 파일럿 — ⬜
- **핵심 통찰**: AI 는 외부 API 라 쉬움. 진짜 병목은 옷 이미지(데이터) + 비용/프라이버시. B트랙 flat-lay 촬영 루프가 이미지 공백을 현장에서 메움.
- **다음 착수**: TASK-0(FASHN $7.50 수동 품질검증) → 49-02. B트랙 백엔드는 vendedor 인증 전환 머지 후.
