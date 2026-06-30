# 43-01 SUMMARY — 데이터 모델 & 비파괴 마이그레이션

> Wave: 43-01 · 상태: ✅ 완료 (코드 + 로컬 PG18 적용 + 실 DB 검증)
> 일자: 2026-06-27

## 완료된 태스크

- [x] TASK-1: wp_channels·wp_product_sync·online_orders 컬럼 재확인 (read-only MCP)
- [x] TASK-2: `migrations/phase43-commerce-channels.sql` — commerce_channels + 복사 마이그레이션
- [x] TASK-3: `migrations/phase43-product-sync.sql` — product_sync + 복사 마이그레이션
- [x] TASK-4: `migrations/phase43-sync-outbox.sql` — sync_outbox 큐 + dedupe partial-unique
- [x] TASK-5: Sequelize 모델 3개 (`core/models/`)

## 생성/변경 파일

| 파일 | 내용 |
|---|---|
| `api-ventago/migrations/phase43-commerce-channels.sql` | wp_channels 일반화(+platform, +external_meta jsonb, +legacy_wp_channel_id). `INSERT...SELECT` 복사. idempotent |
| `api-ventago/migrations/phase43-product-sync.sql` | wp_product_sync 일반화(+channel_id FK, wc_product_id→external_product_id varchar). 복사. idempotent |
| `api-ventago/migrations/phase43-sync-outbox.sql` | outbox 큐. due 인덱스 + 미완료 dedupe partial-unique |
| `api-ventago/migrations/phase43-apply-local.sh` | 로컬 적용 스크립트(순서 보장 + 전후 검증) |
| `api-ventago/src/app/integrations/core/models/commerce-channel.model.ts` | CommerceChannel 모델 + CommercePlatform 타입 |
| `api-ventago/src/app/integrations/core/models/product-sync.model.ts` | ProductSync 모델 |
| `api-ventago/src/app/integrations/core/models/sync-outbox.model.ts` | SyncOutbox 모델 + Outbox 타입 |

## 품질 검증 (샌드박스 격리 PG14 로 실측)

샌드박스에 PG14 를 사용자 모드로 띄워 실제 dev 데이터(wp_channels 1행 / wp_product_sync 5행)와 동일 구조로 재현 후 검증:

- ✅ 3개 마이그레이션 문법·실행 통과 (PG10/15/18 호환 기능만 사용: SERIAL, JSONB, DO 블록, to_regclass, partial unique index)
- ✅ 복사 정확성: 1행→1행, 5행→5행. platform='woocommerce', legacy_* 추적 컬럼 정상
- ✅ 타입 변환: wc_product_id(int)→external_product_id(varchar), NULL 보존 확인(id=3)
- ✅ FK 연결: product_sync.channel_id 가 복사된 commerce_channels.id 로 정확히 매핑
- ✅ 멱등성: 3개 전부 재실행 → 행수 불변(1/5)
- ✅ outbox dedupe: pending 중복 차단 / done 후 재삽입 허용
- ✅ Sequelize 모델 import 경로 4개(store/branch/products/priceType) 실재 확인

## 로컬 PG18 적용 결과 (2026-06-27 실측)

사용자가 `phase43-apply-local.sh` 실행 → Claude 가 read-only MCP 로 실 DB 검증:
- ✅ commerce_channels 1행 (platform='woocommerce', legacy_wp_channel_id=3 — 실 운영 채널 id 추적)
- ✅ product_sync 5행 전부 channel_id=1 로 정확 매핑, 채널 legacy(3)와 일관
- ✅ wc_product_id→external_product_id 변환 정합 (id_mismatch=0), 누락 0 (unmapped=0)
- ✅ 행수 wp 1/5 = commerce 1/5
- ✅ 옛 wp_* 테이블 보존 확인

## 후속
- ⏳ ESLint/tsc: 샌드박스 node_modules 부재로 미실행 → 사용자 Mac 또는 43-05 통합 검증에서 확인. (정적 점검상 규칙 위반 요소 없음)
- → 다음 Wave 43-02: resolver 추출(sku-matcher/stock-resolver/price-resolver)

## 주의

- 옛 `wp_channels`/`wp_product_sync` 는 **보존**(DROP 안 함). rollback 안전장치(D-43-1a).
- 운영 DB 미적용. 로컬 dev 만 대상.
