## 총평

이 계획은 그대로 실행하면 안 됩니다. 핵심 Blocker는 테넌트 격리를 ORM 훅에 과도하게 의존하면서 raw SQL과 `store_id` 없는 4개 하위 테이블의 격리를 설계하지 않은 점, Telegram 유실을 허용한 점, 재고 원장 불변식과 멱등성·동시성 방어가 빠진 점입니다. D2-a 자체는 D2-b보다 낫지만, 기존 `ApprovalService`가 제공하던 승인자 등급·자가승인 금지·fail-closed 정책을 새 상태 전이 서비스에 명시적으로 이식해야 합니다. 운영 DB 적용·push까지 계획에 포함한 부분도 이 저장소의 codex 협업 역할과 충돌합니다.

## 반드시 고쳐야 할 것 (Blocker)

- [ ] **[CRITICAL] 신규 하위 테이블의 테넌트 격리 설계 추가** — 근거: [계획서:42](.gsd/spec-phase77-solicitudes-internas.md), [tenant-hooks.ts:692](api-ventago/src/common/tenant/tenant-hooks.ts), [tenant-scope.registry.ts:130](api-ventago/src/common/tenant/tenant-scope.registry.ts) — 제안: `internal_supply_stocks`, `internal_supply_movements`, `internal_request_items`, `internal_request_events`, attachments처럼 `store_id`가 없는 모델은 `DERIVED_SCOPE`에 부모 경로를 등록하고 테스트하십시오. 더 단순하고 강한 대안은 모든 운영 조회 대상 테이블에 `store_id`를 두고 복합 FK/트리거로 부모와의 일치를 강제하는 것입니다.

- [ ] **[CRITICAL] raw SQL마다 명시적 테넌트 조건 강제** — 근거: 계획된 KPI SQL은 `store_id=$1`을 사용하지만([설계서:489](docs/solicitudes-internas-spec.md)), superadmin 랭킹·cron·목록 join은 raw SQL로 계획되어 ORM 훅이 적용되지 않습니다. 훅 자체도 컨텍스트 미해석 시 no-op입니다([tenant-hooks.ts:59](api-ventago/src/common/tenant/tenant-hooks.ts)). — 제안: 매장 사용자의 `storeId`는 query parameter가 아니라 인증 사용자에서만 얻고, 모든 SQL에 서버 계산 scope를 bind하십시오. superadmin만 DTO의 `storeId`를 허용하고 `isSuperAdminUser()`로 판정하십시오.

- [ ] **[CRITICAL] 교차 매장 FK 오염 방지** — 근거: 설계 스키마는 `internal_requests.store_id`, `branch_id`, `asset_id`를 각각 독립 FK로만 선언하며([설계서:111](docs/solicitudes-internas-spec.md)), stocks는 `supply_id`와 `branch_id`만 가집니다([설계서:211](docs/solicitudes-internas-spec.md)). 자기 매장 request에 타 매장 branch/asset/supply를 연결할 수 있습니다. — 제안: 서비스에서 대상들을 같은 트랜잭션으로 소유권 검증하고, 가능하면 `(store_id,id)` 복합 UNIQUE/FK 또는 DB constraint trigger로 `request↔branch↔asset`, `supply↔branch`의 동일 매장을 강제하십시오.

- [ ] **[HIGH] Telegram 알림을 영속 outbox로 전환** — 근거: 계획은 커밋 후 fire-and-forget입니다([계획서:159](.gsd/spec-phase77-solicitudes-internas.md), [설계서:479](docs/solicitudes-internas-spec.md)). 규약은 필수 후속 작업을 같은 트랜잭션에서 outbox에 넣도록 요구합니다([CLAUDE.md:308](CLAUDE.md)). — 제안: 요청·상태 event와 `telegram_notification_outbox` 행을 같은 트랜잭션에 기록하고 별도 워커가 전송·재시도·성공 표기하도록 하십시오. 기존 `sync_outbox`는 `channel_id NOT NULL`, commerce platform, 단일 commerce processor에 묶여 있어 그대로 재사용하면 안 됩니다([sync-outbox.model.ts:29](api-ventago/src/app/integrations/core/models/sync-outbox.model.ts), [sync-orchestrator.service.ts:60](api-ventago/src/app/integrations/core/sync-orchestrator.service.ts)).

- [ ] **[HIGH] D2-a에 승인 보안 불변식 이식** — 근거: 기존 승인 서비스는 자가승인을 차단하고([approval.service.ts:524](api-ventago/src/app/permissions/approval.service.ts)), DB 현재 역할과 생성 시점 정책 스냅샷으로 승인 등급을 확인하며([approval.service.ts:394](api-ventago/src/app/permissions/approval.service.ts)), 정책 미상 시 fail-closed입니다([approval.service.ts:417](api-ventago/src/app/permissions/approval.service.ts)). 계획에는 이 요건이 없습니다. — 제안: `internal_requests` 전이에 maker-checker, DB 기반 승인자 역할, threshold의 `approver_role_slug`, 원자적 조건부 UPDATE/row lock, 승인·거절 audit를 명시하십시오.

- [ ] **[HIGH] 소모품 원장 불변성과 잔액 갱신을 DB에서 강제** — 근거: 계획은 애플리케이션 이중 쓰기와 사후 drift 조회만 둡니다([계획서:157](.gsd/spec-phase77-solicitudes-internas.md)). 기존 재고는 UPDATE/DELETE를 DB에서 막고([immutable migration:20](api-ventago/migrations/2026-07-28-phase65-w2-stocks-immutable-trigger.sql)), 원장 INSERT의 같은 트랜잭션에서 잔액을 갱신합니다([stock-balances migration:91](api-ventago/migrations/2026-08-02-stock-balances.sql)). — 제안: movement append-only 트리거와 `AFTER INSERT` balance upsert 트리거를 사용하십시오. 애플리케이션은 movement만 INSERT해야 합니다.

- [ ] **[HIGH] 생성 POST에 멱등성 추가** — 근거: 판매 인프라는 claim을 업무 트랜잭션과 결합하고([sale-idempotency.service.ts:19](api-ventago/src/app/sales/sale-idempotency.service.ts)), `(store_id,idempotency_key)` 충돌과 body hash를 처리합니다([sale-idempotency.service.ts:53](api-ventago/src/app/sales/sale-idempotency.service.ts)). Phase 77 계획에는 해당 태스크가 없습니다. — 제안: `Idempotency-Key`를 받고 request hash와 `internal_request_id`를 같은 생성 트랜잭션에 저장하십시오. 판매 전용 테이블에 넣지 말고 별도 테이블 또는 명시적으로 일반화한 공용 테이블을 사용하십시오.

- [ ] **[HIGH] 상태 전이·자동 입고의 동시 실행 방어** — 근거: 계획은 `finalizado` 시 items별 자동 입고만 명시합니다([계획서:152](.gsd/spec-phase77-solicitudes-internas.md)). 동일 요청에 두 번 `finalizado`가 경합하면 movement가 중복될 수 있습니다. — 제안: request row를 `FOR UPDATE`하고 현재 상태를 재검증하며, 자동 입고 movement에 `(request_id, request_item_id, kind)` UNIQUE를 두십시오.

## 고치는 게 좋은 것 (Should)

- [ ] **[MEDIUM] 부트스트랩의 “한 번의 join”을 JSON 집계 또는 분리 쿼리로 변경** — events와 items를 동시에 join하면 요청당 `events × items`만큼 행이 증폭되고 pagination/count가 왜곡될 수 있습니다. 목록 25건을 먼저 고른 뒤 `LATERAL jsonb_agg`를 쓰거나, 선택된 request ID 대상으로 events/items를 각각 한 번씩 조회하십시오.

- [ ] **[MEDIUM] “API 4개면 pool 4개 소모” 표현 수정** — 근거: 설계서가 이를 단정합니다([설계서:342](docs/solicitudes-internas-spec.md)). 병렬 4요청은 순간 동시 checkout을 최대 4개 늘릴 수 있지만, 요청마다 항상 4개를 장시간 점유한다는 뜻은 아닙니다. — 제안: HTTP 1회는 UX·일관성상의 선택으로 유지하되, `Promise.all ≤ 3`을 근거 없는 절대 규칙으로 두지 말고 부하 측정으로 상한을 확정하십시오.

- [ ] **[MEDIUM] 요청 코드용 전용 카운터 확정** — `MAX()+1`은 경합 안전하지 않고 aggregate에 `FOR UPDATE`를 붙이는 방식도 적절하지 않습니다. — 제안: `(store_id,last_value)` 전용 counter 테이블을 `UPDATE ... RETURNING`하거나 PostgreSQL sequence 기반 표시 코드를 사용하십시오.

- [ ] **[MEDIUM] 자산 자동 시드의 물리 자산 의미 수정** — `terminals`는 `box_id`, `store_id`, soft-delete 상태를 가진 논리 POS 단위입니다([db-schema-tables.md:2933](.planning/intel/db-schema-tables.md)). 이를 곧바로 `PC-*`로 부르는 근거는 없습니다. — 제안: `pos_terminal` 유형으로만 시드하거나 D1-b로 전환하십시오. 물리 PC는 수동 등록 후 선택적으로 terminal에 연결하십시오.

- [ ] **[MEDIUM] 시드 필터와 source uniqueness 추가** — boxes와 terminals 모두 `is_deleted`가 있습니다([db-schema-tables.md:211](.planning/intel/db-schema-tables.md), [db-schema-tables.md:2933](.planning/intel/db-schema-tables.md)). — 제안: `t.is_deleted=false`, `b.is_deleted=false`, 활성 status를 적용하고 `terminal_id`, `branch_agent_id`에 각각 partial UNIQUE를 두십시오. 사용자가 수정 가능한 `code`를 멱등성 키로 사용하지 마십시오.

- [ ] **[MEDIUM] 첨부 업로드 보상·삭제 정책 추가** — 현재 `MinioService`에는 upload/download만 있고 삭제 API가 없습니다([minio.service.ts:43](api-ventago/src/common/minio/minio.service.ts)). — 제안: UUID object key, MIME/크기 제한, 업로드 후 DB insert 실패 시 보상 삭제, attachment 삭제 endpoint, orphan 정리 job을 추가하십시오.

- [ ] **[MEDIUM] 감사 로그 태스크 추가** — 승인·거절·비용 변경·재고 조정·자산 등록은 감사 대상입니다. 기존 컨트롤러들은 `@Audit`를 광범위하게 사용합니다. 상태 event는 업무 타임라인이지 보안 감사 로그를 대체하지 않습니다.

- [ ] **[MEDIUM] 권한 매트릭스와 seed 추가** — 기존 권한은 `permissionSlug + action`을 검사합니다([approval.controller.ts:46](api-ventago/src/app/permissions/approval.controller.ts), [permission.guard.ts:134](api-ventago/src/app/permissions/guards/permission.guard.ts)). — 제안: 최소 `solicitudes.read/create/update/approve`, `internal_assets.read/create/update`, `internal_supplies.read/manage/move`를 역할별로 정의하십시오.

- [ ] **[MEDIUM] 저재고 Telegram fail-closed 라우팅** — 설계는 chat 미설정 시 전역 채널로 fallback합니다([설계서:508](docs/solicitudes-internas-spec.md)). — 제안: 매장별 알림은 `telegram_chat_id`가 없으면 발송하지 않고 운영 경고/audit를 남기십시오. 전역 fallback은 명시적으로 opt-in한 매장만 허용하십시오.

- [ ] **[MEDIUM] 자동 입고의 품목 락 순서 고정** — 장바구니 items를 `supply_id, branch_id` 오름차순으로 처리하십시오. 같은 잔액 행을 서로 다른 순서로 갱신하면 교착 가능성이 있습니다.

- [ ] **[MEDIUM] 테스트 태스크 분리** — 상태 머신, 불법 전이, 자가승인, 타 매장 IDOR, raw SQL scope, 동시 finalizado, 동일 Idempotency-Key, 원장 UPDATE/DELETE 차단, Telegram retry, 첨부 보상 삭제에 대한 `*.spec.ts`가 필요합니다.

- [ ] **[LOW] i18n 키 작업 추가** — 스페인어 문자열을 컴포넌트에 직접 박지 말고 기존 i18n 키 체계에 요청 상태·오류·권한 메시지를 등록하십시오.

- [ ] **[LOW] 취소와 삭제 정책 명확화** — request hard delete endpoint는 만들지 말고 `cancelado`를 종결 상태로 유지하십시오. 잘못 취소한 요청은 복구보다 새 요청 생성 또는 명시적 superadmin 재개 전이를 선택하고 audit를 남기십시오.

- [ ] **[MEDIUM] 운영 적용·push를 구현 계획에서 분리** — 근거: TASK-5와 TASK-36은 운영 DB 적용과 push를 요구합니다([계획서:147](.gsd/spec-phase77-solicitudes-internas.md), [계획서:215](.gsd/spec-phase77-solicitudes-internas.md)). — 제안: 검토/코드 작성 단계와 운영 승인·배포 단계를 별도 게이트로 나누십시오.

## 쟁점 8건에 대한 답

| # | 내 판단 | 근거 | 계획 수정 필요 |
|---|---|---|---|
| Q1 | **반대. fire-and-forget만으로는 부족합니다.** 생성·승인·거절·완료 알림은 화면과 완료 기준이 약속하는 업무 알림이므로 영속 큐 대상입니다. 중요도별 두 경로는 운영 의미가 불명확해지므로 4종 모두 같은 경로가 낫습니다. | 규약은 필수 후속 작업의 outbox 기록을 요구합니다([CLAUDE.md:308](CLAUDE.md)). 다만 기존 `sync_outbox`는 commerce channel/platform/op type과 단일 processor에 결합돼 있습니다([sync-outbox.model.ts:29](api-ventago/src/app/integrations/core/models/sync-outbox.model.ts), [sync-orchestrator.service.ts:81](api-ventago/src/app/integrations/core/sync-orchestrator.service.ts)). | 예 — Telegram 전용 outbox 또는 기존 outbox의 명시적 범용화가 필요합니다. 단순히 `solicitud.*` 타입만 추가하면 안 됩니다. |
| Q2 | **D2-a에 동의합니다. 단 현재 근거 일부는 틀렸습니다.** 기존 서비스는 주석과 달리 실제 approve/reject 경로에서 audit_log나 socket emit을 하지 않습니다. 따라서 “그 기능을 잃는다”는 손실은 확인되지 않습니다. 대신 승인 보안 정책을 잃는 것이 치명적입니다. | 서비스 헤더는 audit/socket을 주장하지만([approval.service.ts:7](api-ventago/src/app/permissions/approval.service.ts)), 실제 create/approve/reject는 모델 저장과 로그뿐입니다([approval.service.ts:177](api-ventago/src/app/permissions/approval.service.ts), [approval.service.ts:506](api-ventago/src/app/permissions/approval.service.ts)). `approval_requests`는 24시간 만료 모델입니다([approval-request.model.ts:81](api-ventago/src/app/permissions/models/approval-request.model.ts)). 비즈니스 상태와 승인 상태를 원자적으로 동기화하는 기존 패턴은 확인되지 않습니다. | 예 — D2-a 유지, maker-checker·승인등급·audit·동시성 방어를 명시적으로 추가하십시오. |
| Q3 | **DB 트리거 방식에 동의합니다.** 규모가 작아도 원장 불변식은 정확성 문제입니다. 최소 immutable trigger만으로는 잔액 이중 쓰기 누락을 막지 못하므로 balance apply까지 DB가 담당하는 편이 맞습니다. | 기존 `stocks`는 immutable trigger와 AFTER INSERT balance trigger를 함께 사용합니다([immutable migration:37](api-ventago/migrations/2026-07-28-phase65-w2-stocks-immutable-trigger.sql), [stock-balances migration:110](api-ventago/migrations/2026-08-02-stock-balances.sql)). drift view는 탐지일 뿐 예방이 아닙니다. Phase 70-06은 공통 부모행을 갱신한 트리거만 폐기했고 key별 balance 트리거는 유지했습니다([retire migration:10](api-ventago/migrations/2026-08-04-retire-product-stock-cache.sql)). | 예 — movement-only 애플리케이션 쓰기 + DB balance trigger로 변경하십시오. |
| Q4 | **엔드포인트 집계에는 동의하지만 “상세 1회 join”에는 반대합니다.** 하나의 page API는 역할 맞춤 payload에 적합하나, SWR 캐시 세분화를 포기한 대가로 모든 필터 변경 때 KPI·rail까지 재조회됩니다. | 유사 선례는 cockpit 서비스들이 summary/trend/list를 서버 내부 `Promise.all`로 모으는 형태입니다. 정확히 `/page`라는 동일 선례는 확인되지 않았습니다. 응답이 “수십 KB”라는 주장은 측정 근거가 없습니다([설계서:364](docs/solicitudes-internas-spec.md)). | 예 — page API는 유지하되 JSON 집계/3개 bounded query, payload 측정, KPI·rail의 짧은 TTL 캐시를 검토하십시오. |
| Q5 | **멱등성은 필요합니다. 과잉이 아닙니다.** 다품목 생성은 중복 시 승인·비용·입고까지 중복됩니다. | 기존 구현은 key claim과 생성 행을 같은 트랜잭션에 묶고 body hash 충돌을 처리합니다([sale-idempotency.service.ts:21](api-ventago/src/app/sales/sale-idempotency.service.ts), [sale-idempotency.service.ts:99](api-ventago/src/app/sales/sale-idempotency.service.ts)). `sale_id`·sales 조회에 결합돼 있어 테이블 그대로 재사용할 수 없습니다([sale-idempotency.model.ts:29](api-ventago/src/app/sales/sale-idempotency.model.ts)). | 예 — 별도 `internal_request_idempotency_keys`가 최소 변경입니다. 장기적으로만 공용 테이블 일반화를 고려하십시오. |
| Q6 | **경로는 맞지만 D1-a의 의미와 필터가 틀렸습니다.** `terminals.box_id→boxes.branch_id`가 실제 FK 경로이고 두 테이블 모두 soft-delete를 가집니다. terminal을 물리 PC로 간주할 근거는 없습니다. | FK는 schema intel에 확인됩니다([db-schema-fks.md:354](.planning/intel/db-schema-fks.md)). `boxes.is_deleted`와 `terminals.is_deleted`가 존재합니다([db-schema-tables.md:220](.planning/intel/db-schema-tables.md), [db-schema-tables.md:2941](.planning/intel/db-schema-tables.md)). | 예 — 활성 필터, source FK partial UNIQUE, `pos_terminal` 유형 또는 수동 물리 PC 등록으로 수정하십시오. |
| Q7 | **현재 계획으로는 차단 보장이 없습니다.** 프론트 역할 분기는 보안 경계가 아니며, 훅도 raw SQL·미해석 컨텍스트·파생 모델을 자동 보호하지 않습니다. | 훅은 등록된 모델을 부팅 시 순회하지만([tenant-hooks.ts:692](api-ventago/src/common/tenant/tenant-hooks.ts)), 컨텍스트가 없으면 no-op입니다([tenant-hooks.ts:59](api-ventago/src/common/tenant/tenant-hooks.ts)). 계획 예시는 `user.roles.includes()`를 사용해 역할 shape 호환 유틸과 불일치합니다([설계서:348](docs/solicitudes-internas-spec.md)); 올바른 유틸은 [tenant-user.util.ts:26](api-ventago/src/common/tenant/tenant-user.util.ts)). | 예 — query `storeId` 허용 규칙, 명시 scope bind, derived scope, IDOR 테스트, `isSuperAdminUser()` 사용을 추가하십시오. |
| Q8 | **다수 누락됐고 일부는 Blocker입니다.** 특히 audit, 권한, idempotency, 테넌트 복합 소유권, 첨부 보상 삭제, cron chat 격리, 자동 입고 중복 방지, 테스트가 필요합니다. | 계획 태스크에는 이 항목들이 없고, 기존 코드에는 Audit/PermissionGuard/멱등성 패턴이 존재합니다. MinIO에는 삭제 메서드도 없습니다([minio.service.ts:43](api-ventago/src/common/minio/minio.service.ts)). | 예 |

## 계획에 없지만 필요한 태스크

- TASK-01A: 신규 모델 전체 테넌트 구조 결정 — 직접 `store_id` 또는 `DERIVED_SCOPE`, raw SQL scope 표 작성.
- TASK-01B: 교차 매장 FK 불변식과 DB 제약/constraint trigger 작성.
- TASK-01C: movement immutable + balance apply trigger, 동시성 테스트 작성.
- TASK-04A: 요청 코드 전용 store counter 마이그레이션.
- TASK-08A: 승인 정책 서비스 — maker-checker, 승인자 등급, 조건부 상태 전이, audit.
- TASK-08B: `finalizado` 자동 입고 멱등 UNIQUE와 row lock.
- TASK-10A: Telegram 전용 outbox 테이블·worker·lease·retry·dedupe·실패 관제.
- TASK-10B: 매장 chat 미설정 시 발송 차단 정책과 설정 검증.
- TASK-11A: `Idempotency-Key` DTO/controller/service/테이블 및 replay 테스트.
- TASK-11B: CASL이 아니라 이 저장소의 `PermissionGuard` 방식에 맞춘 permission/action seed.
- TASK-11C: 첨부 MIME/크기/UUID key, MinIO delete, DB 실패 보상, orphan cleanup.
- TASK-12A: 목록 선페이지네이션 + events/items JSON 집계, 행 증폭·payload 크기 테스트.
- TASK-14A: 설계 문서의 `user.roles.includes('superadmin')`를 `isSuperAdminUser()`로 수정.
- TASK-29A: 백엔드 단위·통합 테스트와 프론트 역할 렌더링 테스트.
- TASK-29B: i18n 키 및 스페인어 오류 메시지 등록.
- TASK-35A: 1 API와 분리 API의 P95·pool checkout·응답 바이트 비교 부하 테스트.
- TASK-36A: 운영 DB 적용·push를 사용자 승인과 구현 담당자에게 넘기는 별도 배포 게이트.

## 과하다고 보는 것 (제거 권장)

- `Promise.all`을 무조건 3개 이하로 제한하는 규칙. 쿼리 비용·실행시간·pool 측정 없이 호출 개수만 제한하면 느린 단일 쿼리가 더 나쁠 수 있습니다.
- 페이지 API 호출이 반드시 1회여야 한다는 완료 기준. 핵심 기준은 P95, 총 쿼리 비용, payload, 캐시 효율입니다.
- `React.memo`를 파일 단위 태스크로 강제하는 것. 실제 props 안정성과 렌더 프로파일 없이 적용하면 의미가 없습니다.
- terminal을 `PC-*` 물리 자산으로 자동 생성하는 D1-a 현행안.
- `sync_outbox`에 commerce schema를 유지한 채 `solicitud.*` op type만 얹는 방안.
- 요청 hard delete와 취소 후 임의 복구. 감사 가능한 종결 상태와 새 요청 생성이 더 단순합니다.
- 검토 계획에 운영 DB 동시 적용, `git push origin main`, 운영 컨테이너 재생성을 직접 포함하는 것. 이는 별도 승인된 배포 절차로 분리해야 합니다.
