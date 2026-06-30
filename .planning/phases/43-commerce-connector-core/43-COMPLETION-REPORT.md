# Phase 43 — Commerce Connector Core: COMPLETION REPORT

> 상태: ✅ 완료 — 빌드/Jest/ESLint 3관문 전부 PASS + 로컬 PG18 마이그레이션 검증
> 일자: 2026-06-27

## 목표 달성

WooCommerce 싱크의 비즈니스 로직을 플랫폼 무관 코어로 추출하고, `CommerceConnector` 인터페이스 + WooCommerce 어댑터 + outbox 기반 push worker 를 구축. **기능 변경 0** (WC 기존 동작 무중단). 신규 플랫폼(TN/Shopify/Empretienda)이 이 코어 위에 빌드 가능한 상태.

## 완료된 Wave

| Wave | 내용 | 상태 |
|---|---|---|
| 43-01 | commerce_channels/product_sync/sync_outbox + 복사 마이그레이션 + 모델 3 | ✅ 로컬 PG18 적용·검증 |
| 43-02 | resolver 3종(stock/price/sku-matcher) 추출 + Jest | ✅ |
| 43-03 | CommerceConnector 인터페이스 + WC 어댑터 + registry | ✅ |
| 43-04 | orchestrator + outbox(enqueue/worker/cron) + sales-create 트리거(flag) | ✅ |
| 43-05 | 모듈 배선 + 정적 검증 + 문서 | ✅ |

## 핵심 설계 결정 (구현 반영됨)

- **D-43-1a 복사 마이그레이션**: wp_* → commerce_* 복사. 옛 테이블 보존(rollback). 로컬 실측: 1행/5행 정확 복사, 멱등성·dedupe 통과.
- **D-43-2 어댑터 격리**: 비즈니스 로직은 core 독점, 어댑터는 인증·전송·변환·서명만.
- **D-43-3 outbox**: fire-and-forget → 영속 큐. 판매 트랜잭션 내 INSERT, worker 가 배치 push.
- **D-43-6/7/8/9 동시성**: ingest 외부호출 무 + 짧은 트랜잭션, 재고 SERIALIZABLE(Phase 28 재사용), outbox BATCH 상한, Phase 48 백본통일을 oversell 방지 필수단계로 격상.

## 품질 검증

| 항목 | 결과 |
|---|---|
| 마이그레이션 (격리 PG14 + 로컬 PG18) | ✅ 복사 정확·멱등·dedupe PASS |
| import 경로 실재 | ✅ 전부 확인 |
| 모델 속성 일치 | ✅ Stocks/Price/Product 컬럼 일치 |
| no-unused-vars | ✅ 의심 0 |
| newline-before-return | ✅ 0 (1건 수정) |
| 기존 wp/ 디렉터리 | ✅ 무변경(회귀 0) |
| 빌드 (nest build) | ✅ 0 에러 |
| Jest (integrations/core) | ✅ 11/11 PASS |
| ESLint (core+adapters) | ✅ 0 problems (declare id 로 잔여 해결) |

## Pool 안전 (사용자 최우선 관심사)

- outbox worker 는 기존 Sequelize 인스턴스 재사용 — **신규 pool 생성 0**
- 외부 API I/O 는 DB 트랜잭션 밖 (커넥션 미점유)
- BATCH_SIZE=20 + 동시 tick 가드 → push 동시성이 pool(min10/max80) 위협 안 함
- ingest 는 외부호출 무 → 동시 webhook 도 짧은 트랜잭션

## 변경/생성 파일

신규(14): core/{commerce-connector.interface, connector.registry, outbox.service, outbox.cron, sync-orchestrator.service, stock/price-resolver.service, sku-matcher.service, commerce-core.module}, core/models/{commerce-channel, product-sync, sync-outbox}, core/__tests__/resolvers.spec, adapters/woocommerce/woocommerce.adapter
신규 마이그레이션(4): phase43-{commerce-channels, product-sync, sync-outbox}.sql + apply-local.sh
수정(3): app.module.ts, sales/sales-create.service.ts, sales/sales.module.ts

## 다음 단계

1. 사용자 Mac: `npm run build` + `npx jest integrations/core` + `npx eslint src/app/integrations` 최종 게이트
2. Phase 44 (Tienda Nube) — 이 코어 위 첫 신규 어댑터(레퍼런스). `/gsd-spec-phase 44`
3. 운영 마이그레이션은 별도(사용자 확인). 옛 wp_* DROP 은 한 사이클 후.
