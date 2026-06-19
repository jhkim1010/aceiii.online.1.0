# 42-01 SUMMARY — Transporte CRUD + use_envios 게이트 (RD-1)

**Wave:** 1
**Status:** done
**Executed:** 2026-06-19
**Branch:** feat/phase42-wave1

## Goal

Phase 40 Repartidor 패턴을 1:1 복제해 신규 `Transporte` 엔티티(store-scoped CRUD, soft-toggle isActive)를 만들고, `use_envios` store-config 게이트 플래그(기본 OFF)를 추가. 42-02(OnlineOrder transporteId FK)와 프론트 Transporte 카드가 의존하는 백엔드 foundation.

## Artifacts

| 파일 | 역할 | 비고 |
|------|------|------|
| `api-ventago/migrations/42-01-transportes.sql` | transportes 테이블 DDL | SERIAL, snake_case, IF NOT EXISTS, PG10/15/18 호환. **미적용**(42-03 BLOCKING task 에서 online_orders 컬럼과 함께 적용 — 42-02 FK 가 transportes 참조) |
| `api-ventago/migrations/42-03-store-config-use-envios.sql` | use_envios 컬럼 | `BOOLEAN NOT NULL DEFAULT false` — 기존 매장 자동 OFF. **미적용** |
| `api-ventago/src/app/transportes/transportes.model.ts` | Transporte 모델 | `{ id, storeId, name, isActive }` — phone 제거(D-04), `tableName: 'transportes'` |
| `api-ventago/src/app/transportes/transportes.service.ts` | CRUD 서비스 | findByStore(activeOnly) 단일 SELECT(pool 절약) + create + update soft-toggle + findScoped IDOR 가드(NotFoundException) |
| `api-ventago/src/app/transportes/transportes.controller.ts` | CRUD 라우트 | 모든 라우트 @Auth(), storeId 는 @GetUser 에서만(요청 본문 신뢰 X) |
| `api-ventago/src/app/transportes/dto/transporte.dto.ts` | DTO | Create{name}, Update{name?, isActive?} class-validator |
| `api-ventago/src/app/transportes/transportes.module.ts` | 모듈 | forFeature([Transporte]), exports [TransportesService, SequelizeModule] (online-orders 가 name 미러 소비) |
| `api-ventago/src/app/transportes/transportes.service.spec.ts` | jest spec | 5 behaviors — **PASS (5/5)** |
| `api-ventago/src/app/store/config/storeConfig.model.ts` (MODIFY) | useEnvios 컬럼 추가 | useRestaurantMode 인접, field: 'use_envios', default false |
| `api-ventago/src/app.module.ts` (MODIFY) | TransportesModule 등록 | import + imports 배열 |

## Must-haves 충족

- ✅ Store operator can create/list/update Transporte scoped to their store (storeId from @GetUser, 모든 쿼리 storeId WHERE)
- ✅ isActive=false soft-toggle 보존(never hard-deleted) + activeOnly 로 despacho 드롭다운 소스에서 제외
- ✅ store_configs use_envios default false → 기존 매장 무영향(RD-12)

## Verification

- `npx jest transportes.service` → **5/5 PASS** (create storeId 주입 + isActive default / findByStore 단일 SELECT / activeOnly 필터 / 타 store NotFoundException IDOR / update soft-toggle no-destroy)
- 마이그레이션 acceptance grep 전부 통과, `GENERATED AS IDENTITY` 토큰 없음
- `npx tsc --noEmit` → transporte/useEnvios 관련 신규 에러 0
- `phone` 필드 누출 0 (모델/DTO)
- ESLint: 신규 백엔드 파일은 analog(repartidores)과 **동일 패턴** — 백엔드 eslint 는 빌드 게이트 아님(NestJS/SWC). 빌드 차단 룰(newline-before-return/lines-around-comment/no-unused-vars) 위반 없음

## Threat model

- T-42-01 (cross-store 조회/조작): 모든 쿼리 storeId WHERE + findScoped NotFoundException — mitigated
- T-42-02 (storeId 위조): @GetUser 에서만 취득, 요청 본문 미신뢰, @Auth() 전 라우트 — mitigated
- T-42-03 (use_envios): boolean flag, PII 없음, default false — accept

## Notes / 다음 단계

- 마이그레이션 2개는 **미적용 상태**(plan 설계대로). 42-03 BLOCKING task 에서 42-02 online_orders 컬럼과 순서 맞춰 로컬 적용 → 운영 PG10 런북.
- TransportesService 는 exports 됨 → 42-02 online-orders 가 ship 시 transporte.name 하위호환 미러(D-05)에 소비.
