# Phase 56 — VentaGO 파트너 네트워크 (도매상↔소매상 실시간 판매 공유) [포인터]

> 정식 문서는 `.planning/phases/56-partner-network/` 에 있음. 본 파일은 프로젝트 관례(.gsd 포인터).
> **번호 이력:** 최초 `53-partner-network` 로 생성됐으나 `.gsd/spec-phase53-security-hardening.md`(보안 강화)와 번호 충돌 → 2026-07-11 **Phase 56** 으로 재번호. (53=보안강화·54=관측·55=렌더링플리커 이미 점유, 다음 빈 번호 56.)

## 구성 문서
- `.planning/phases/56-partner-network/56-CONTEXT.md` — Phase 경계, D-01~D-14 결정, canonical refs
- `.planning/phases/56-partner-network/56-SPEC.md` — RPN-1~6 요구사항, 5-wave 태스크 29개, 보안/프라이버시 게이트
- `.planning/phases/56-partner-network/56-RESEARCH.md` — 코드 검증, 유사시스템, 기술스택 근거, 리스크

## 핵심 불변식
1. 양측 동의(`partner_links.status='active'`) 전 어떤 데이터도 무공유.
2. 매출 총액·고객 정보 절대 미공유 — payload 화이트리스트(`sku`/`quantity_sold`/`stock_remaining`/`shared_at`)만.
3. 연결 해제 시 `partner_data_shares` CASCADE 삭제(감사 로그는 별도 보존).

## 재사용 기반 (코드 검증 완료)
- `sales-create.service.ts` 커밋 후 best-effort 블록(트랜잭션 밖, pool 영향 0) 훅
- `integrations/core/` outbox 큐(신규 pool 0, cron worker 재사용)
- Socket.io 신규 `/partner` namespace(`/envios` 게이트웨이 동형)
- `store_id` FK + `partner_links.status` 이중 격리(cross-store)

## 설계 리뷰 반영 (2026-07-11)
- ②비대칭 공유: `shared_categories` 단일 → `shared_categories_a`/`_b` 측별 2컬럼.
- ③매칭 키: `category_id` 제외(cross-store 불가), SKU/codigo_madre + 기존 `sku-matcher.service.ts` 재사용.
- ④전달 저장: `partner_share_outbox` 신규 테이블 확정(sync_outbox.channel_id/platform NOT NULL) — worker 만 재사용.
